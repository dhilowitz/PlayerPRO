//
//  PianoWindowController.swift
//  PlayerPRO 6
//
//  Standalone window hosting the on-screen piano keyboard (PianoKeyboardView).
//  Built entirely in code rather than a nib: there is no existing Piano
//  window layout to adapt in this project -- PPSmallPianoView is an
//  unrelated 2014 stub used as a color swatch inside the instrument volume/
//  panning envelope editor, not this feature. See PIANO-KEYBOARD-SPEC.md.
//

import Cocoa
import PlayerPROKit

class PianoWindowController: NSWindowController {

	let pianoView = PianoKeyboardView(frame: NSRect(x: 0, y: 0, width: 1920, height: 60))
	private var octaveLabel: NSTextField!

	/// Owning document, for the driver and the currently selected instrument.
	/// Weak: the document outlives this window controller's lifetime, not the
	/// other way around.
	weak var currentDocument: PPDocument? {
		didSet {
			pianoView.driver = currentDocument?.theDriver
			refreshSelectedInstrument()
		}
	}

	/// Bridges scrubbed/clicked notes into whichever pattern grid is
	/// currently recording, matching the original's DigitalEditorProcess
	/// call from DoItemPressPiano. See PatternGridView.enterNote(_:).
	var noteEntered: ((Int) -> Void)? {
		get { pianoView.noteEntered }
		set { pianoView.noteEntered = newValue }
	}

	convenience init() {
		let contentWidth: CGFloat = 700
		let stripHeight: CGFloat = 30
		let pianoHeight: CGFloat = 60

		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: stripHeight + pianoHeight),
							   styleMask: [.titled, .closable, .miniaturizable, .resizable],
							   backing: .buffered, defer: false)
		window.title = NSLocalizedString("Piano", comment: "piano window title")
		window.isReleasedWhenClosed = false

		self.init(window: window)

		let content = window.contentView!

		let scroller = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: pianoHeight))
		scroller.hasHorizontalScroller = true
		scroller.hasVerticalScroller = false
		scroller.autohidesScrollers = false
		scroller.autoresizingMask = [.width, .height]
		scroller.documentView = pianoView
		content.addSubview(scroller)

		let strip = NSView(frame: NSRect(x: 0, y: pianoHeight, width: contentWidth, height: stripHeight))
		strip.autoresizingMask = [.width, .minYMargin]
		content.addSubview(strip)
		buildControlStrip(strip)
	}

	// MARK: Octave shift
	//
	// Matches the original's Left/Right buttons and "Piano +0 Octave(s)"
	// title text -- range -7...+7, enforced by PianoKeyboardView itself.

	private func buildControlStrip(_ strip: NSView) {
		let left = NSButton(title: "◀", target: self, action: #selector(shiftOctaveDown))
		left.bezelStyle = .rounded
		left.frame = NSRect(x: 6, y: 4, width: 28, height: 22)
		strip.addSubview(left)

		let right = NSButton(title: "▶", target: self, action: #selector(shiftOctaveUp))
		right.bezelStyle = .rounded
		right.frame = NSRect(x: 38, y: 4, width: 28, height: 22)
		strip.addSubview(right)

		let label = NSTextField(labelWithString: "")
		label.frame = NSRect(x: 74, y: 6, width: 220, height: 18)
		strip.addSubview(label)
		octaveLabel = label
		updateOctaveLabel()
	}

	@objc private func shiftOctaveDown() {
		pianoView.octaveOffset -= 1
		updateOctaveLabel()
	}

	@objc private func shiftOctaveUp() {
		pianoView.octaveOffset += 1
		updateOctaveLabel()
	}

	private func updateOctaveLabel() {
		let n = pianoView.octaveOffset
		let sign = n >= 0 ? "+" : ""
		octaveLabel.stringValue = String(format: NSLocalizedString("Piano %@%d Octave(s)", comment: "piano octave readout"), sign, n)
	}

	// MARK: Selected instrument

	func refreshSelectedInstrument() {
		pianoView.instrument = currentDocument?.instrumentList?.selectedInstrument
	}
}
