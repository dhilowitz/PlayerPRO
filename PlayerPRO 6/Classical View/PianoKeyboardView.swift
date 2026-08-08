//
//  PianoKeyboardView.swift
//  PlayerPRO 6
//
//  On-screen piano keyboard: click or scrub to audition notes through the
//  selected instrument, drag a key out to place a note anywhere that
//  accepts the same 'Pcmd'/'TEXT' pasteboard flavors the pattern grid's
//  own clipboard uses. Layout follows the classic PlayerPRO piano: a
//  single chromatic row rather than a two-row split keyboard, colored by
//  octave, with the assigned physical key printed on each note.
//

import Cocoa
import PlayerPROKit

@objc(PPPianoKeyboardView)
open class PianoKeyboardView: NSView {

	// MARK: Content

	/// Driver used for auditioning notes. Playback needs a channel and the
	/// selected instrument's sample data; nothing plays without both set.
	@objc open weak var driver: PPDriver?

	@objc open weak var instrument: PPInstrumentObject? {
		didSet { needsDisplay = true }
	}

	/// Whole-octave shift, matching thePrefs.pianoOffset. Clamped to the
	/// original's -7...7 range.
	@objc open var octaveOffset: Int = 0 {
		didSet {
			octaveOffset = max(-7, min(7, octaveOffset))
			needsDisplay = true
		}
	}

	// MARK: Metrics
	//
	// Matches the "large piano" rendering in the original (ToucheLarg /
	// ToucheHaut) rather than attempting to recreate the "small piano"'s
	// baked-in PICT resource, which this project has no access to.

	private let keyWidth: CGFloat = 20
	private let keyHeight: CGFloat = 60
	private static let blackWhite = [false, true, false, true, false, false, true, false, true, false, true, false]

	private var noteCount: Int { return 96 }

	open override var isFlipped: Bool { return true }

	open override var intrinsicContentSize: NSSize {
		return NSSize(width: CGFloat(noteCount) * keyWidth, height: keyHeight)
	}

	// MARK: Colors

	private static let blackKeyFill = NSColor(calibratedWhite: 0.20, alpha: 1)
	private static let octaveColors: [NSColor] = [
		NSColor(calibratedRed: 0.87, green: 0.09, blue: 0.09, alpha: 1),
		NSColor(calibratedRed: 0.60, green: 0.66, blue: 0.13, alpha: 1),
		NSColor(calibratedRed: 0.20, green: 0.90, blue: 0.95, alpha: 1),
		NSColor(calibratedRed: 0.99, green: 0.95, blue: 0.15, alpha: 1),
		NSColor(calibratedRed: 0.36, green: 0.78, blue: 0.60, alpha: 1),
		NSColor(calibratedRed: 0.20, green: 0.85, blue: 0.95, alpha: 1),
		NSColor(calibratedRed: 0.35, green: 0.80, blue: 0.35, alpha: 1),
		NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.92, alpha: 1)
	]
	private static let heldFill = NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.85, alpha: 1)

	private static let noteNames = ["C-", "C#", "D-", "D#", "E-", "F-",
									"F#", "G-", "G#", "A-", "A#", "B-"]

	private func noteName(_ n: Int) -> String {
		return PianoKeyboardView.noteNames[n % 12] + String(n / 12)
	}

	// MARK: Drawing

	private func rect(forNote n: Int) -> NSRect {
		return NSRect(x: CGFloat(n) * keyWidth, y: 0, width: keyWidth, height: keyHeight)
	}

	open override func draw(_ dirtyRect: NSRect) {
		NSColor.white.setFill()
		dirtyRect.fill()

		let font = NSFont.systemFont(ofSize: 9)
		let noteFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular)

		for n in 0..<noteCount {
			let r = rect(forNote: n)
			guard r.intersects(dirtyRect) else { continue }

			let isBlack = PianoKeyboardView.blackWhite[n % 12]
			if n == heldNote {
				PianoKeyboardView.heldFill.setFill()
			} else if isBlack {
				PianoKeyboardView.blackKeyFill.setFill()
			} else {
				PianoKeyboardView.octaveColors[(n / 12) % PianoKeyboardView.octaveColors.count].setFill()
			}
			r.fill()

			NSColor.black.setStroke()
			NSBezierPath(rect: r).stroke()

			let textColor: NSColor = (isBlack || n == heldNote) ? .white : .black
			let letter = PianoKeyMap.noteToKey[n].map(String.init) ?? ""
			let letterAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
			let letterSize = letter.size(withAttributes: letterAttrs)
			letter.draw(at: NSPoint(x: r.midX - letterSize.width / 2, y: r.maxY - letterSize.height - 4),
						withAttributes: letterAttrs)

			let name = noteName(n)
			let nameAttrs: [NSAttributedString.Key: Any] = [.font: noteFont, .foregroundColor: textColor]
			let nameSize = name.size(withAttributes: nameAttrs)
			name.draw(at: NSPoint(x: r.midX - nameSize.width / 2, y: 4), withAttributes: nameAttrs)
		}
	}

	// MARK: Audition
	//
	// DoPlayInstruInt, which the original routes every piano hit through,
	// is Carbon-era glue with no modern equivalent -- confirmed by tracing
	// its declaration through MIDI-Hardware-OSX.c, which is part of the
	// actively-built engine, and finding no function body anywhere in that
	// tree. What does exist is PPDriver's lower-level
	// -playSoundDataFromData:...withNote:, which the engine itself
	// pitch-shifts from the sample's own base rate -- so this does not need
	// to reimplement note-to-rate math, just supply the sample and the
	// target note.

	private func audition(note: Int) {
		guard let driver = driver, let instrument = instrument,
			  let sample = instrument.samples.first, let data = sample.data else { return }
		let channel = Int32(driver.availableChannel)
		guard channel >= 0 else { return }
		try? driver.playSoundData(from: data as Data, fromChannel: channel,
								  amplitude: Int16(sample.volume), bitRate: UInt32(sample.c2spd),
								  isStereo: sample.isStereo, withNote: UInt8(note))
	}

	// MARK: Digital editor bridge
	//
	// Wired by whatever hosts this view, since the piano and the pattern
	// grid it feeds normally live in different windows. Not yet
	// implemented at the call site -- see PIANO-KEYBOARD-SPEC.md build
	// order step 4.
	@objc open var noteEntered: ((Int) -> Void)?

	// MARK: Clipboard-compatible drag payload
	//
	// A strict special case of the pattern grid's own Pcmd format: a 1x1
	// block. Unlike the original Carbon Pcmd struct, PatternGridView's Swift
	// reimplementation (PatternGridView.encode(_:)/decode(_:)) never carries
	// trackStart/posStart at all -- its header is just [tracks, length]
	// immediately followed by cell data. This must match that exactly, byte
	// for byte, or PatternGridView.paste(_:)/pasteData(_:atRow:track:) reads
	// the wrong bytes as the cell.

	// internal, not private, so it can be exercised directly by a headless
	// test harness without needing to simulate a live drag session.
	func encodedDrag(note: Int) -> Data {
		var cmd = Cmd()
		cmd.ins = MADByte((instrument?.number ?? -1) + 1)
		cmd.note = MADByte(note)
		cmd.cmd = MADEffectID(rawValue: 0) ?? cmd.cmd
		cmd.arg = 0
		cmd.vol = 0xFF

		var out = Data()
		let header: [Int32] = [1, 1]		// tracks, length
		header.withUnsafeBytes { out.append(contentsOf: $0) }
		withUnsafeBytes(of: &cmd) { out.append(contentsOf: $0) }
		return out
	}

	// MARK: Input

	open override var acceptsFirstResponder: Bool { return true }

	private var heldNote: Int? {
		didSet {
			guard heldNote != oldValue else { return }
			if let old = oldValue { setNeedsDisplay(rect(forNote: old)) }
			if let new = heldNote { setNeedsDisplay(rect(forNote: new)) }
		}
	}

	private func note(at point: NSPoint) -> Int? {
		guard point.x >= 0, point.y >= 0, point.y <= keyHeight else { return nil }
		let n = Int(point.x / keyWidth)
		guard n >= 0, n < noteCount else { return nil }
		return n
	}

	/// Raw key index (not octave-shifted) the drag-out gesture, if any,
	/// should visually originate from -- the held key's own rect, matching
	/// the original rather than wherever the mouse has since moved.
	private var dragOriginKey: Int?
	/// The actual musical note last entered/auditioned, i.e. dragOriginKey
	/// shifted by the current octave offset. What the drag payload carries.
	private var dragOriginShiftedNote: Int?

	open override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let p = convert(event.locationInWindow, from: nil)
		guard let n = note(at: p) else { return }
		enterHeld(n)
	}

	open override func mouseDragged(with event: NSEvent) {
		let p = convert(event.locationInWindow, from: nil)

		// Above the strip: start an OS-level drag of the last held note,
		// matching the original's "drag off the top edge" gesture.
		if p.y < 0, let originKey = dragOriginKey, let shifted = dragOriginShiftedNote {
			beginDragOut(key: originKey, shiftedNote: shifted, event: event)
			return
		}

		guard let n = note(at: p), n != heldNote else { return }
		enterHeld(n)
	}

	open override func mouseUp(with event: NSEvent) {
		heldNote = nil
		dragOriginKey = nil
		dragOriginShiftedNote = nil
	}

	private func enterHeld(_ n: Int) {
		heldNote = n
		let shifted = n + octaveOffset * 12
		guard shifted >= 0 && shifted < noteCount else {
			dragOriginKey = nil
			dragOriginShiftedNote = nil
			return
		}
		dragOriginKey = n
		dragOriginShiftedNote = shifted
		audition(note: shifted)
		noteEntered?(shifted)
	}

	private func beginDragOut(key: Int, shiftedNote: Int, event: NSEvent) {
		let pcmdData = encodedDrag(note: shiftedNote)
		let text = "\(noteName(shiftedNote)) \(String(format: "%02d", instrument?.number ?? 0)) .. ..."

		let item = NSPasteboardItem()
		item.setData(pcmdData, forType: PatternGridView.pasteboardType)
		item.setString(text, forType: .string)

		let draggingItem = NSDraggingItem(pasteboardWriter: item)
		draggingItem.setDraggingFrame(rect(forNote: key), contents: nil)

		heldNote = nil
		dragOriginKey = nil
		dragOriginShiftedNote = nil
		beginDraggingSession(with: [draggingItem], event: event, source: self)
	}
}

extension PianoKeyboardView: NSDraggingSource {
	public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		return .copy
	}
}
