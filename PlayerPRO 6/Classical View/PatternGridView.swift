//
//  PatternGridView.swift
//  PlayerPRO 6
//
//  Read-only pattern grid. Layout follows the classic PlayerPRO editor:
//  a row-number gutter, one colour-coded header per track, four-row beat
//  banding, and each track split into note / instrument / volume / effect /
//  argument sub-columns.
//

import Cocoa
import PlayerPROKit

@objc(PPPatternGridView)
open class PatternGridView: NSView {

	// MARK: Content

	@objc open var pattern: PPPatternObject? {
		didSet { invalidateSize(); needsDisplay = true }
	}

	/// Number of tracks to show. The pattern itself does not carry this, it
	/// comes from the music header.
	@objc open var trackCount: Int = 4 {
		didSet { invalidateSize(); needsDisplay = true }
	}

	/// Row that playback is currently on, or -1 for none.
	@objc open var playbackRow: Int = -1 {
		didSet {
			guard playbackRow != oldValue else { return }
			setNeedsDisplay(rowRect(oldValue))
			setNeedsDisplay(rowRect(playbackRow))
		}
	}

	private var rowCount: Int {
		return Int(pattern?.patternSize ?? 64)
	}

	// MARK: Cursor and selection
	//
	// The classic editor selects a rectangle over (track, position) rather than
	// a single cell, and Delete, transpose and copy all act on that rectangle.
	// The cursor is one corner of it; an unextended selection is a single cell.

	/// Row and track the cursor sits on.
	@objc open private(set) var cursorRow: Int = 0
	@objc open private(set) var cursorTrack: Int = 0

	/// The other corner of the selection. Equal to the cursor when nothing is
	/// extended.
	private var anchorRow: Int = 0
	private var anchorTrack: Int = 0

	/// Rows moved per arrow press and per note entry. The editor calls this the
	/// step, and it is 1 by default.
	@objc open var step: Int = 1

	/// Selection bounds, normalised so top <= bottom and left <= right.
	@objc open var selectedRowRange: NSRange {
		let lo = min(cursorRow, anchorRow), hi = max(cursorRow, anchorRow)
		return NSRange(location: lo, length: hi - lo + 1)
	}

	@objc open var selectedTrackRange: NSRange {
		let lo = min(cursorTrack, anchorTrack), hi = max(cursorTrack, anchorTrack)
		return NSRange(location: lo, length: hi - lo + 1)
	}

	private func isSelected(row: Int, track: Int) -> Bool {
		return NSLocationInRange(row, selectedRowRange)
			&& NSLocationInRange(track, selectedTrackRange)
	}

	/// Move the cursor, optionally dragging the selection with it.
	@objc open func setCursorRow(_ row: Int, track: Int, extending: Bool) {
		let oldSel = selectionRect()
		cursorRow = clampRow(row)
		cursorTrack = clampTrack(track)
		if !extending {
			anchorRow = cursorRow
			anchorTrack = cursorTrack
		}
		setNeedsDisplay(oldSel.union(selectionRect()))
		scrollCursorToVisible()
	}

	private func clampRow(_ r: Int) -> Int {
		guard rowCount > 0 else { return 0 }
		return max(0, min(rowCount - 1, r))
	}

	private func clampTrack(_ t: Int) -> Int {
		guard trackCount > 0 else { return 0 }
		return max(0, min(trackCount - 1, t))
	}

	private func selectionRect() -> NSRect {
		let rows = selectedRowRange, tracks = selectedTrackRange
		return NSRect(x: trackX(tracks.location),
					  y: headerHeight + CGFloat(rows.location) * rowHeight,
					  width: CGFloat(tracks.length) * trackWidth,
					  height: CGFloat(rows.length) * rowHeight)
	}

	private func scrollCursorToVisible() {
		var r = NSRect(x: trackX(cursorTrack),
					   y: headerHeight + CGFloat(cursorRow) * rowHeight,
					   width: trackWidth, height: rowHeight)
		// keep the header from covering the cursor when scrolled to the top
		r = r.insetBy(dx: 0, dy: -headerHeight)
		scrollToVisible(r)
	}

	// MARK: Metrics

	private let rowHeight: CGFloat = 14
	private let gutterWidth: CGFloat = 34
	private let headerHeight: CGFloat = 16
	/// note, instrument, volume, effect, argument
	private let subColumnWidths: [CGFloat] = [30, 24, 24, 20, 24]
	private var trackWidth: CGFloat {
		return subColumnWidths.reduce(0, +)
	}

	private var font: NSFont {
		return NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
	}

	// MARK: Palette
	//
	// The classic editor cycles a fixed set of track header colours and bands
	// every fourth row so the beat is readable at a glance.

	private static let trackColors: [NSColor] = [
		NSColor(calibratedRed: 0.87, green: 0.09, blue: 0.09, alpha: 1),
		NSColor(calibratedRed: 0.60, green: 0.66, blue: 0.13, alpha: 1),
		NSColor(calibratedRed: 0.20, green: 0.90, blue: 0.95, alpha: 1),
		NSColor(calibratedRed: 0.99, green: 0.95, blue: 0.15, alpha: 1),
		NSColor(calibratedRed: 0.36, green: 0.78, blue: 0.60, alpha: 1),
		NSColor(calibratedRed: 0.20, green: 0.85, blue: 0.95, alpha: 1),
		NSColor(calibratedRed: 0.35, green: 0.80, blue: 0.35, alpha: 1),
		NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.92, alpha: 1)
	]

	private let beatBand = NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.72, alpha: 1)
	private let offBand = NSColor.white
	private let playbackBand = NSColor(calibratedRed: 0.72, green: 0.85, blue: 0.72, alpha: 1)
	private let gutterBack = NSColor(calibratedWhite: 0.93, alpha: 1)
	private let selectionFill = NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.95, alpha: 0.28)
	private let cursorStroke = NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.85, alpha: 1)

	private static let noteNames = ["C-", "C#", "D-", "D#", "E-", "F-",
								   "F#", "G-", "G#", "A-", "A#", "B-"]

	// MARK: Geometry

	open override var isFlipped: Bool {
		return true
	}

	private func invalidateSize() {
		let w = gutterWidth + CGFloat(trackCount) * trackWidth
		let h = headerHeight + CGFloat(rowCount) * rowHeight
		if frame.size != NSSize(width: w, height: h) {
			setFrameSize(NSSize(width: w, height: h))
		}
	}

	private func rowRect(_ row: Int) -> NSRect {
		guard row >= 0 && row < rowCount else { return .zero }
		return NSRect(x: 0,
					  y: headerHeight + CGFloat(row) * rowHeight,
					  width: bounds.width,
					  height: rowHeight)
	}

	private func trackX(_ track: Int) -> CGFloat {
		return gutterWidth + CGFloat(track) * trackWidth
	}

	// MARK: Formatting
	//
	// Empty fields render blank rather than as zero — the classic editor
	// distinguishes "no command here" from "command with value 0", and a grid
	// full of zeroes is unreadable.

	private func noteText(_ note: MADByte) -> String {
		guard note != 0xFF else { return "···" }
		let n = Int(note)
		guard n >= 0 && n < 96 else { return "···" }
		return PatternGridView.noteNames[n % 12] + String(n / 12)
	}

	private func insText(_ ins: MADByte) -> String {
		return ins == 0 ? "··" : String(format: "%02d", Int(ins))
	}

	private func volText(_ vol: MADByte) -> String {
		return vol == 0xFF ? "··" : String(format: "%02d", Int(vol))
	}

	private func effText(_ eff: MADByte) -> String {
		return eff == 0 ? "·" : String(format: "%X", Int(eff))
	}

	private func argText(_ arg: MADByte) -> String {
		return arg == 0 ? "··" : String(format: "%02X", Int(arg))
	}

	// MARK: Input

	open override var acceptsFirstResponder: Bool {
		return true
	}

	open override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	open override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
	}

	/// Which cell a point lands in, or nil when it is in the gutter or header.
	private func cell(at point: NSPoint) -> (row: Int, track: Int)? {
		guard point.x >= gutterWidth, point.y >= headerHeight, trackWidth > 0 else {
			return nil
		}
		let track = Int((point.x - gutterWidth) / trackWidth)
		let row = Int((point.y - headerHeight) / rowHeight)
		guard track >= 0, track < trackCount, row >= 0, row < rowCount else {
			return nil
		}
		return (row, track)
	}

	open override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let p = convert(event.locationInWindow, from: nil)
		guard let c = cell(at: p) else { return }
		// shift-click extends, matching the shift-arrow behaviour
		setCursorRow(c.row, track: c.track, extending: event.modifierFlags.contains(.shift))
	}

	open override func mouseDragged(with event: NSEvent) {
		let p = convert(event.locationInWindow, from: nil)
		// clamp rather than bail, so dragging past the edge keeps extending
		let track = clampTrack(Int((p.x - gutterWidth) / max(trackWidth, 1)))
		let row = clampRow(Int((p.y - headerHeight) / rowHeight))
		setCursorRow(row, track: track, extending: true)
	}

	open override func keyDown(with event: NSEvent) {
		guard let chars = event.charactersIgnoringModifiers, let ch = chars.unicodeScalars.first else {
			super.keyDown(with: event)
			return
		}
		let extending = event.modifierFlags.contains(.shift)

		switch Int(ch.value) {
		case NSUpArrowFunctionKey:
			moveCursor(dRow: -step, dTrack: 0, extending: extending)
		case NSDownArrowFunctionKey:
			moveCursor(dRow: step, dTrack: 0, extending: extending)
		case NSLeftArrowFunctionKey:
			moveCursor(dRow: 0, dTrack: -1, extending: extending)
		case NSRightArrowFunctionKey:
			moveCursor(dRow: 0, dTrack: 1, extending: extending)
		case NSHomeFunctionKey:
			setCursorRow(0, track: cursorTrack, extending: extending)
		case NSEndFunctionKey:
			setCursorRow(rowCount - 1, track: cursorTrack, extending: extending)
		case NSPageUpFunctionKey:
			moveCursor(dRow: -16, dTrack: 0, extending: extending)
		case NSPageDownFunctionKey:
			moveCursor(dRow: 16, dTrack: 0, extending: extending)
		default:
			super.keyDown(with: event)
		}
	}

	/// Arrow movement. Tracks wrap around the pattern; rows wrap within it.
	/// Crossing into the next pattern via the order list is not wired up yet.
	private func moveCursor(dRow: Int, dTrack: Int, extending: Bool) {
		guard rowCount > 0, trackCount > 0 else { return }
		var row = cursorRow + dRow
		var track = cursorTrack + dTrack

		if track < 0 { track = trackCount - 1 }
		if track >= trackCount { track = 0 }

		if row < 0 { row += rowCount }
		if row >= rowCount { row -= rowCount }

		setCursorRow(row, track: track, extending: extending)
	}

	@objc open override func selectAll(_ sender: Any?) {
		guard rowCount > 0, trackCount > 0 else { return }
		anchorRow = 0
		anchorTrack = 0
		cursorRow = rowCount - 1
		cursorTrack = trackCount - 1
		needsDisplay = true
	}

	// MARK: Drawing

	open override func draw(_ dirtyRect: NSRect) {
		NSColor.white.setFill()
		dirtyRect.fill()

		guard let pattern = pattern, trackCount > 0 else {
			drawPlaceholder()
			return
		}

		let firstRow = max(0, Int((dirtyRect.minY - headerHeight) / rowHeight))
		let lastRow = min(rowCount - 1, Int((dirtyRect.maxY - headerHeight) / rowHeight))
		if firstRow <= lastRow {
			drawRows(firstRow...lastRow, of: pattern)
		}

		drawSeparators(dirtyRect)
		drawCursor()
		drawHeader(dirtyRect)		// last, so it stays on top when scrolled
	}

	private func drawCursor() {
		guard rowCount > 0, trackCount > 0 else { return }
		let r = NSRect(x: trackX(cursorTrack),
					   y: headerHeight + CGFloat(cursorRow) * rowHeight,
					   width: trackWidth, height: rowHeight)
		// Solid when we hold focus, dimmed when we do not, so it stays visible
		// without pretending to be active.
		let focused = (window?.firstResponder === self) && (window?.isKeyWindow ?? false)
		(focused ? cursorStroke : cursorStroke.withAlphaComponent(0.4)).setStroke()
		let path = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
		path.lineWidth = 2
		path.stroke()
	}

	private func drawPlaceholder() {
		let text = "No pattern"
		let attrs: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 11),
			.foregroundColor: NSColor.secondaryLabelColor
		]
		let size = text.size(withAttributes: attrs)
		text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
							  y: (bounds.height - size.height) / 2),
				  withAttributes: attrs)
	}

	private func drawRows(_ rows: ClosedRange<Int>, of pattern: PPPatternObject) {
		let cellAttrs: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: NSColor.black
		]
		let gutterAttrs: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: NSColor.darkGray
		]

		for row in rows {
			let band = rowRect(row)

			// beat banding, four rows on and four off
			if row == playbackRow {
				playbackBand.setFill()
			} else if (row / 4) % 2 == 0 {
				beatBand.setFill()
			} else {
				offBand.setFill()
			}
			band.fill()

			// row number gutter
			gutterBack.setFill()
			NSRect(x: 0, y: band.minY, width: gutterWidth, height: rowHeight).fill()
			String(format: "%03d", row).draw(
				at: NSPoint(x: 3, y: band.minY + 1), withAttributes: gutterAttrs)

			for track in 0..<trackCount {
				// selection wash, drawn under the text so the notes stay legible
				if isSelected(row: row, track: track) {
					selectionFill.setFill()
					NSRect(x: trackX(track), y: band.minY,
						   width: trackWidth, height: rowHeight).fill()
				}

				let cmd = pattern.getCommand(position: Int16(row), channel: Int16(track))
				var x = trackX(track)
				let fields = [noteText(cmd.note), insText(cmd.instrument),
							  volText(cmd.volume), effText(MADByte(cmd.command.rawValue)),
							  argText(cmd.argument)]
				for (i, text) in fields.enumerated() {
					text.draw(at: NSPoint(x: x + 2, y: band.minY + 1),
							  withAttributes: cellAttrs)
					x += subColumnWidths[i]
				}
			}
		}
	}

	private func drawSeparators(_ dirtyRect: NSRect) {
		let top = max(dirtyRect.minY, headerHeight)
		let bottom = dirtyRect.maxY

		// thin rules between sub-columns
		NSColor(calibratedWhite: 0.80, alpha: 1).setStroke()
		let thin = NSBezierPath()
		thin.lineWidth = 1
		for track in 0..<trackCount {
			var x = trackX(track)
			for w in subColumnWidths.dropLast() {
				x += w
				thin.move(to: NSPoint(x: x, y: top))
				thin.line(to: NSPoint(x: x, y: bottom))
			}
		}
		thin.stroke()

		// heavy rules between tracks
		NSColor.black.setStroke()
		let thick = NSBezierPath()
		thick.lineWidth = 1
		for track in 0...trackCount {
			let x = trackX(track)
			thick.move(to: NSPoint(x: x, y: top))
			thick.line(to: NSPoint(x: x, y: bottom))
		}
		thick.stroke()
	}

	private func drawHeader(_ dirtyRect: NSRect) {
		let headerRect = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
		guard headerRect.intersects(dirtyRect) else { return }

		gutterBack.setFill()
		headerRect.fill()

		let attrs: [NSAttributedString.Key: Any] = [
			.font: NSFont.boldSystemFont(ofSize: 9),
			.foregroundColor: NSColor.black
		]

		for track in 0..<trackCount {
			let r = NSRect(x: trackX(track), y: 0, width: trackWidth, height: headerHeight)
			PatternGridView.trackColors[track % PatternGridView.trackColors.count].setFill()
			r.fill()
			NSColor.black.setStroke()
			NSBezierPath(rect: r).stroke()

			let label = String(track + 1)
			let size = label.size(withAttributes: attrs)
			label.draw(at: NSPoint(x: r.midX - size.width / 2,
								   y: r.midY - size.height / 2),
					   withAttributes: attrs)
		}
	}
}
