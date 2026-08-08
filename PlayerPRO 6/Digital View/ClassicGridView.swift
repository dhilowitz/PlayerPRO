//
//  ClassicGridView.swift
//  PlayerPRO 6
//
//  The Classic tab: a piano-roll, not a text grid. X axis is pattern
//  position, Y axis is note pitch (96 rows, high notes at the top), and
//  each note-on is a colored block, colored by track like every other
//  editor's track headers -- multiple channels sounding at once show as
//  several blocks stacked at different pitches, not several rows of text.
//  See CLASSIC-EDITOR-SPEC.md, derived from Files/wds_editors/ClassicalP.c.
//
//  Hosted, despite the name, by DigitalViewController -- the earlier
//  Digital/Classic tab-mislabeling fix (see DIGITAL-EDITOR-SPEC.md) swapped
//  which view controller instance sits under which tab without renaming
//  the classes, so DigitalViewController's view is what actually appears
//  under the "Classic" tab.
//

import Cocoa
import PlayerPROKit

@objc public enum ClassicGridMode: Int {
	case play = 0
	case zoom = 1
}

@objc(PPClassicGridView)
open class ClassicGridView: NSView {

	public override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	// MARK: Content

	@objc open var pattern: PPPatternObject? {
		didSet { invalidateSize(); needsDisplay = true }
	}

	@objc open var trackCount: Int = 4 {
		didSet { needsDisplay = true }
	}

	/// -1 shows every track; 0..<trackCount restricts to one, matching the
	/// original's Track popup (dialog item 7).
	@objc open var selectedTrack: Int = -1 {
		didSet { needsDisplay = true }
	}

	/// -1 shows notes from every instrument; 0-based otherwise, matching the
	/// original's Instrument popup (dialog item 8) -- compared against a
	/// command's `ins - 1` since 0 means "no instrument" in Cmd.
	@objc open var selectedInstrument: Int = -1 {
		didSet { needsDisplay = true }
	}

	/// The live playback driver, for the play-mode scrub only. Playhead
	/// highlighting is driven externally via `playbackRow`, the same
	/// pattern PatternGridView already uses, rather than this view reading
	/// the driver's position itself on a timer.
	@objc open weak var driver: PPDriver?

	@objc open var playbackRow: Int = -1 {
		didSet {
			guard playbackRow != oldValue else { return }
			setNeedsDisplay(columnRect(oldValue))
			setNeedsDisplay(columnRect(playbackRow))
		}
	}

	private var patternLength: Int {
		return Int(pattern?.patternSize ?? 0)
	}

	// MARK: Mode
	//
	// Matches the original exactly: Option-click always zooms out regardless
	// of mode; Cmd-click always zooms in regardless of mode; a plain click
	// zooms in while Zoom mode is selected, or scrubs playback while Play
	// mode is selected. There is no "zoom out via Zoom mode" without the
	// Option modifier in the original either.

	@objc open var mode: ClassicGridMode = .play

	// MARK: Zoom
	//
	// zoomLevel is the original's ZoomLevelPat: powers of 2, 1...32. Unlike
	// the original -- which squeezes all 96 note rows into whatever window
	// height is available, giving each row as little as 1-2px on a classic
	// low-res screen -- this port fixes rowHeight and scrolls vertically
	// instead, since a modern display has no equivalent excuse to make 96
	// rows illegible. Horizontal zoom is unchanged in spirit: zoomLevel
	// controls column width the same way.

	@objc open private(set) var zoomLevel: Int = 1
	private let baseColumnWidth: CGFloat = 3
	private var columnWidth: CGFloat { return baseColumnWidth * CGFloat(zoomLevel) }
	private let rowHeight: CGFloat = 6
	private let noteCount = 96

	@objc open func zoomIn(atColumn column: Int) {
		guard zoomLevel < 32 else { return }
		rezoom(to: zoomLevel * 2, keepingColumnStationary: column)
	}

	@objc open func zoomOut(atColumn column: Int) {
		guard zoomLevel > 1 else { return }
		rezoom(to: zoomLevel / 2, keepingColumnStationary: column)
	}

	private func rezoom(to newLevel: Int, keepingColumnStationary column: Int) {
		guard let scrollView = enclosingScrollView else {
			zoomLevel = newLevel
			invalidateSize(); needsDisplay = true
			return
		}
		let screenXBefore = columnX(column) - scrollView.contentView.bounds.minX
		zoomLevel = newLevel
		invalidateSize()
		let newOrigin = NSPoint(x: max(0, columnX(column) - screenXBefore), y: scrollView.contentView.bounds.minY)
		scrollView.contentView.scroll(to: newOrigin)
		scrollView.reflectScrolledClipView(scrollView.contentView)
		needsDisplay = true
	}

	// MARK: Geometry

	open override var isFlipped: Bool { return true }

	private func invalidateSize() {
		let w = CGFloat(patternLength) * columnWidth
		let h = CGFloat(noteCount) * rowHeight
		if frame.size != NSSize(width: w, height: h) {
			setFrameSize(NSSize(width: w, height: h))
		}
	}

	private func columnX(_ column: Int) -> CGFloat {
		return CGFloat(column) * columnWidth
	}

	private func columnRect(_ column: Int) -> NSRect {
		guard column >= 0, column < patternLength else { return .zero }
		return NSRect(x: columnX(column), y: 0, width: columnWidth, height: bounds.height)
	}

	/// y position matches the original's `Pos = NUMBER_NOTES - note`: high
	/// notes near the top.
	private func noteY(_ note: Int) -> CGFloat {
		return CGFloat(noteCount - note) * rowHeight
	}

	private func column(at point: NSPoint) -> Int? {
		guard columnWidth > 0 else { return nil }
		let column = Int(point.x / columnWidth)
		guard column >= 0, column < max(patternLength, 1) else { return nil }
		return column
	}

	// MARK: Palette
	//
	// Same eight-color track palette PatternGridView/PianoKeyboardView each
	// already carry their own copy of -- not consolidated into a shared
	// module in this pass, matching the existing duplication in this
	// codebase rather than introducing a new shared file for it.

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

	private static let playbackBand = NSColor(calibratedRed: 0.72, green: 0.85, blue: 0.72, alpha: 0.6)

	// MARK: Drawing

	open override func draw(_ dirtyRect: NSRect) {
		NSColor.white.setFill()
		dirtyRect.fill()

		guard patternLength > 0, trackCount > 0, columnWidth > 0 else { return }

		if playbackRow >= 0 {
			ClassicGridView.playbackBand.setFill()
			columnRect(playbackRow).fill()
		}

		guard let pattern = pattern else { return }

		let firstColumn = max(0, Int(dirtyRect.minX / columnWidth))
		let lastColumn = min(patternLength - 1, Int(dirtyRect.maxX / columnWidth))
		guard firstColumn <= lastColumn else { return }

		let tracks: [Int] = selectedTrack >= 0 ? [selectedTrack] : Array(0..<trackCount)

		for column in firstColumn...lastColumn {
			for track in tracks {
				guard track < trackCount else { continue }
				let cmd = pattern.getCommand(position: Int16(column), channel: Int16(track))
				let note = Int(cmd.note)
				guard note != 0xFF, note != 0xFE, note >= 0, note < noteCount else { continue }

				if selectedInstrument >= 0 {
					guard Int(cmd.instrument) == selectedInstrument + 1 else { continue }
				}

				let r = NSRect(x: columnX(column), y: noteY(note), width: columnWidth, height: rowHeight)
				ClassicGridView.trackColors[track % ClassicGridView.trackColors.count].setFill()
				r.fill()
			}
		}
	}

	// MARK: Input

	open override var acceptsFirstResponder: Bool { return true }

	private var scrubbing = false
	private var wasPlayingBeforeScrub = false

	open override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let p = convert(event.locationInWindow, from: nil)
		guard let column = column(at: p) else { return }

		if event.modifierFlags.contains(.option) {
			zoomOut(atColumn: column)
		} else if event.modifierFlags.contains(.command) || mode == .zoom {
			zoomIn(atColumn: column)
		} else {
			beginScrub(atColumn: column)
		}
	}

	open override func mouseDragged(with event: NSEvent) {
		guard mode == .play, scrubbing else { return }
		let p = convert(event.locationInWindow, from: nil)
		guard let column = column(at: p) else { return }
		driver?.patternPosition = Int16(column)
	}

	open override func mouseUp(with event: NSEvent) {
		guard scrubbing else { return }
		scrubbing = false
		if !wasPlayingBeforeScrub {
			_ = try? driver?.pause()
		}
	}

	private func beginScrub(atColumn column: Int) {
		guard let driver = driver else { return }
		wasPlayingBeforeScrub = driver.isPlayingMusic
		driver.patternPosition = Int16(column)
		if !wasPlayingBeforeScrub {
			_ = driver.play()
		}
		scrubbing = true
	}
}
