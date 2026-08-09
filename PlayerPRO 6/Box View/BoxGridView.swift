//
//  BoxGridView.swift
//  PlayerPRO 6
//
//  The Box tab: an editable piano-roll (compare Classic's read-only one).
//  Every track's notes draw overlaid in one shared 96-row grid, color-coded
//  by track same as everywhere else, but this editor also lets you place,
//  drag, delete and audition notes -- Box's actual reason for existing
//  beyond Classic's view-only piano-roll. See BOX-EDITOR-SPEC.md, derived
//  from Files/wds_editors/Mozart.c.
//
//  Scope note: the original splits vertical scrolling into two nested
//  controls -- which tracks are visible (c3h) and which note range within
//  each visible track's own fixed-height strip (c1h) -- so each track is a
//  short banded row, not a full-height piano roll. This port instead reuses
//  the single full-height, all-tracks-overlaid layout ClassicGridView
//  already has, proven correct there, rather than re-deriving a second,
//  more complex dual-scroll layout. Edits always target one explicit
//  `selectedTrack` (never "all"), since placing/deleting a note needs a
//  definite track regardless of how many are visible at once. See the spec
//  chapter's "Deviation" section for the full reasoning and what's deferred
//  because of it (multi-note rubber-band selection, moving a selection as a
//  block, the original's Command dialog on double-click).
//

import Cocoa
import PlayerPROKit

@objc public enum BoxGridMode: Int {
	case note = 0
	case trash = 1
	case play = 2
	case zoom = 3
}

@objc(PPBoxGridView)
open class BoxGridView: NSView {

	public override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		registerForDraggedTypes([PatternGridView.pasteboardType])
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		registerForDraggedTypes([PatternGridView.pasteboardType])
	}

	// MARK: Content

	@objc open var pattern: PPPatternObject? {
		didSet { invalidateSize(); needsDisplay = true }
	}

	@objc open var music: PPMusicObject? {
		didSet { needsDisplay = true }
	}

	@objc open var trackCount: Int = 4 {
		didSet { needsDisplay = true }
	}

	/// Which track note placement, deletion and drag-out act on. Always a
	/// concrete track, never "all" -- unlike Classic/Wave's filters, this
	/// one has to pick a definite edit target, not just a view filter.
	@objc open var selectedTrack: Int = 0 {
		didSet { needsDisplay = true }
	}

	@objc open weak var driver: PPDriver?

	@objc open var playbackRow: Int = -1 {
		didSet {
			guard playbackRow != oldValue else { return }
			setNeedsDisplay(columnRect(oldValue))
			setNeedsDisplay(columnRect(playbackRow))
		}
	}

	/// Values stamped on a newly-placed note, matching the original's
	/// curInstru/curEffect/curArgu/curVol "current settings."
	@objc open var defaultInstrument: UInt8 = 1
	@objc open var defaultEffect: UInt8 = 0
	@objc open var defaultArgument: UInt8 = 0
	@objc open var defaultVolume: UInt8 = 0xFF

	@objc open var didEditPattern: (() -> Void)?
	@objc open var editUndoManager: UndoManager?

	private var effectiveUndoManager: UndoManager? {
		return editUndoManager ?? undoManager
	}

	private var patternLength: Int {
		return Int(pattern?.patternSize ?? 0)
	}

	// MARK: Mode

	@objc open var mode: BoxGridMode = .note

	// MARK: Zoom
	//
	// A discrete step table, not the doubling zoom Classic/Wave use --
	// matches the original's MOLargList/MOHautList exactly (index 0 is most
	// zoomed out, 7 most zoomed in). Click zooms in one step; Option-click
	// zooms out one step, in Zoom mode.

	private static let widthSteps: [CGFloat] = [5, 8, 12, 14, 16, 20, 25, 30]
	private static let heightSteps: [CGFloat] = [5, 8, 10, 10, 12, 20, 25, 30]

	@objc open private(set) var zoomIndex: Int = 3 {
		didSet { invalidateSize(); needsDisplay = true }
	}

	private var columnWidth: CGFloat { return BoxGridView.widthSteps[zoomIndex] }
	private var rowHeight: CGFloat { return BoxGridView.heightSteps[zoomIndex] }
	private let noteCount = 96

	@objc open func zoomIn() {
		guard zoomIndex < BoxGridView.widthSteps.count - 1 else { return }
		zoomIndex += 1
	}

	@objc open func zoomOut() {
		guard zoomIndex > 0 else { return }
		zoomIndex -= 1
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

	private func noteY(_ note: Int) -> CGFloat {
		return CGFloat(noteCount - note) * rowHeight
	}

	private func cell(at point: NSPoint) -> (row: Int, note: Int)? {
		guard columnWidth > 0, rowHeight > 0 else { return nil }
		let row = Int(point.x / columnWidth)
		let note = noteCount - 1 - Int(point.y / rowHeight)
		guard row >= 0, row < max(patternLength, 1), note >= 0, note < noteCount else { return nil }
		return (row, note)
	}

	// MARK: Palette

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

	private static let playbackBand = NSColor(calibratedRed: 0.72, green: 0.85, blue: 0.72, alpha: 0.5)
	private static let selectedTrackBand = NSColor(calibratedRed: 0.85, green: 0.90, blue: 1.0, alpha: 0.35)

	// MARK: Drawing

	open override func draw(_ dirtyRect: NSRect) {
		NSColor.white.setFill()
		dirtyRect.fill()

		guard patternLength > 0, trackCount > 0, columnWidth > 0, let pattern = pattern else { return }

		if playbackRow >= 0 {
			BoxGridView.playbackBand.setFill()
			columnRect(playbackRow).fill()
		}

		let firstColumn = max(0, Int(dirtyRect.minX / columnWidth))
		let lastColumn = min(patternLength - 1, Int(dirtyRect.maxX / columnWidth))
		guard firstColumn <= lastColumn else { return }

		for column in firstColumn...lastColumn {
			for track in 0..<trackCount {
				let cmd = pattern.getCommand(position: Int16(column), channel: Int16(track))
				let note = Int(cmd.note)
				guard note != 0xFF, note != 0xFE, note >= 0, note < noteCount else { continue }

				let r = NSRect(x: columnX(column), y: noteY(note), width: columnWidth, height: rowHeight)
				let color = BoxGridView.trackColors[track % BoxGridView.trackColors.count]
				(track == selectedTrack ? color : color.withAlphaComponent(0.55)).setFill()
				r.fill()

				if track == selectedTrack {
					NSColor.black.setStroke()
					NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
				}
			}
		}
	}

	// MARK: Undo / editing

	private func withUndo(_ name: String, _ body: () -> Void) {
		let um = effectiveUndoManager
		um?.setActionName(name)
		body()
		didEditPattern?()
	}

	// internal, not private, so these can be exercised directly by a
	// headless test harness without needing a real window to synthesize
	// mouse events against.
	func placeNote(row: Int, note: Int) {
		guard let pattern = pattern else { return }
		withUndo(NSLocalizedString("Add Note", comment: "undo name")) {
			pattern.modifyCommand(atPosition: Int16(row), channel: Int16(selectedTrack)) { cmd in
				cmd.pointee.note = MADByte(note)
				cmd.pointee.ins = self.defaultInstrument
				if let eff = MADEffectID(rawValue: self.defaultEffect) { cmd.pointee.cmd = eff }
				cmd.pointee.arg = self.defaultArgument
				cmd.pointee.vol = self.defaultVolume
			}
		}
		setNeedsDisplay(columnRect(row))
	}

	func deleteNote(row: Int) {
		guard let pattern = pattern else { return }
		withUndo(NSLocalizedString("Delete Note", comment: "undo name")) {
			pattern.modifyCommand(atPosition: Int16(row), channel: Int16(selectedTrack)) { cmd in
				cmd.pointee.ins = 0
				cmd.pointee.note = 0xFF
				cmd.pointee.cmd = MADEffectID(rawValue: 0) ?? cmd.pointee.cmd
				cmd.pointee.arg = 0
				cmd.pointee.vol = 0xFF
			}
		}
		setNeedsDisplay(columnRect(row))
	}

	func hasNote(row: Int, track: Int) -> Bool {
		guard let pattern = pattern else { return false }
		let note = pattern.getCommand(position: Int16(row), channel: Int16(track)).note
		return note != 0xFF && note != 0xFE
	}

	// MARK: Audition (Play mode)
	//
	// Same primitive PianoKeyboardView.audition(note:) uses -- PPDriver
	// pitch-shifts from the sample's own base rate, so no manual rate math
	// is needed here either.

	private func audition(note: Int) {
		guard let driver = driver, let music = music,
			  defaultInstrument > 0, Int(defaultInstrument) - 1 < music.instruments.count else { return }
		let instrument = music.instruments[Int(defaultInstrument) - 1]
		guard let sample = instrument.samples.first, let data = sample.data else { return }
		let channel = Int32(driver.availableChannel)
		guard channel >= 0 else { return }
		// PPDriver.playSoundData's "amplitude" parameter is the sample's bit
		// depth (8/16), not a volume -- passing volume here silently broke
		// the mixer's bit-depth dispatch (MADChannel.amp) entirely, so
		// audition never actually produced sound despite reporting success.
		try? driver.playSoundData(from: data as Data, fromChannel: channel,
								  amplitude: Int16(sample.amplitude), bitRate: UInt32(sample.c2spd),
								  isStereo: sample.isStereo, withNote: UInt8(note))
	}

	// MARK: Clipboard-compatible drag payload
	//
	// Same wire format PatternGridView's own clipboard and PianoKeyboardView's
	// drag-out both already use: [tracks: Int32, length: Int32] then Cmd
	// bytes, no trackStart/posStart -- confirmed the hard way in the Piano
	// phase that carrying those extra fields breaks decoding, since
	// PatternGridView.decode(_:) never reads them.

	func encodedDrag(row: Int, note: Int) -> Data {
		var cmd = Cmd()
		cmd.ins = defaultInstrument
		cmd.note = MADByte(note)
		cmd.cmd = MADEffectID(rawValue: defaultEffect) ?? cmd.cmd
		cmd.arg = defaultArgument
		cmd.vol = defaultVolume

		var out = Data()
		let header: [Int32] = [1, 1]
		header.withUnsafeBytes { out.append(contentsOf: $0) }
		withUnsafeBytes(of: &cmd) { out.append(contentsOf: $0) }
		return out
	}

	func decode(_ data: Data) -> Cmd? {
		let headerSize = MemoryLayout<Int32>.size * 2
		let cellSize = MemoryLayout<Cmd>.size
		guard data.count >= headerSize + cellSize else { return nil }
		return data.withUnsafeBytes { $0.load(fromByteOffset: headerSize, as: Cmd.self) }
	}

	// MARK: Input

	open override var acceptsFirstResponder: Bool { return true }

	private var trashing = false
	private var lastTrashedRow: Int?
	private var draggingOutRow: Int?

	open override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let p = convert(event.locationInWindow, from: nil)
		guard let c = cell(at: p) else { return }

		switch mode {
		case .zoom:
			if event.modifierFlags.contains(.option) { zoomOut() } else { zoomIn() }

		case .trash:
			trashing = true
			lastTrashedRow = nil
			trashAt(row: c.row)

		case .play:
			audition(note: c.note)

		case .note:
			if hasNote(row: c.row, track: selectedTrack) {
				beginDragOut(row: c.row, note: c.note, event: event)
			} else {
				placeNote(row: c.row, note: c.note)
			}
		}
	}

	open override func mouseDragged(with event: NSEvent) {
		guard mode == .trash, trashing else { return }
		let p = convert(event.locationInWindow, from: nil)
		guard let c = cell(at: p) else { return }
		trashAt(row: c.row)
	}

	open override func mouseUp(with event: NSEvent) {
		trashing = false
		lastTrashedRow = nil
	}

	private func trashAt(row: Int) {
		guard row != lastTrashedRow else { return }
		lastTrashedRow = row
		guard hasNote(row: row, track: selectedTrack) else { return }
		deleteNote(row: row)
	}

	private func beginDragOut(row: Int, note: Int, event: NSEvent) {
		let payload = encodedDrag(row: row, note: note)

		let item = NSPasteboardItem()
		item.setData(payload, forType: PatternGridView.pasteboardType)

		let draggingItem = NSDraggingItem(pasteboardWriter: item)
		draggingItem.setDraggingFrame(NSRect(x: columnX(row), y: noteY(note), width: columnWidth, height: rowHeight), contents: nil)

		beginDraggingSession(with: [draggingItem], event: event, source: self)
	}

	open override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		return sender.draggingPasteboard().data(forType: PatternGridView.pasteboardType) != nil ? .copy : []
	}

	open override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		return sender.draggingPasteboard().data(forType: PatternGridView.pasteboardType) != nil ? .copy : []
	}

	open override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard let data = sender.draggingPasteboard().data(forType: PatternGridView.pasteboardType),
			  let cmd = decode(data) else { return false }
		let p = convert(sender.draggingLocation(), from: nil)
		guard let c = cell(at: p), let pattern = pattern else { return false }

		withUndo(NSLocalizedString("Move Note", comment: "undo name")) {
			pattern.replaceCommand(atPosition: Int16(c.row), channel: Int16(selectedTrack), cmd: cmd)
		}
		setNeedsDisplay(columnRect(c.row))
		return true
	}
}

extension BoxGridView: NSDraggingSource {
	// Copy-only, deliberately: dragging an existing note out duplicates it
	// rather than moving it. A true move needs to delete the source note
	// only when the drop actually lands somewhere else (not when the drag
	// is cancelled, and not when it drops back on its own origin cell) --
	// getting that wrong silently loses or duplicates pattern data, so it's
	// left as a documented gap (see BOX-EDITOR-SPEC.md) rather than shipped
	// half-verified.
	public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		return .copy
	}
}
