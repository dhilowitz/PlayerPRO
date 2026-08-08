//
//  BoxViewController.swift
//  PPMacho
//
//  Created by C.W. Betts on 9/29/14.
//
//

import Cocoa
import PlayerPROKit

class BoxViewController: NSViewController {

	@IBOutlet weak var currentDocument: PPDocument!

	private var gridScrollView: NSScrollView!
	private(set) var gridView: BoxGridView!
	private var observedDocument: PPDocument?
	private var trackPopup: NSPopUpButton!
	private var modeControl: NSSegmentedControl!
	private var instrumentField: NSTextField!

	private static var musicContext = 0

	deinit {
		observedDocument?.removeObserver(self, forKeyPath: "theMusic", context: &BoxViewController.musicContext)
	}

    @available(OSX 10.10, *)
    override func viewDidLoad() {
        super.viewDidLoad()

		// Same reasoning as every other tab in this port: the view arrives
		// from the nib empty, so the grid, its scroller and the control
		// strip are all built here rather than in Interface Builder.
		gridView = BoxGridView(frame: .zero)

		let bounds = view.bounds
		let stripHeight: CGFloat = 30

		let scroller = NSScrollView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - stripHeight))
		scroller.hasVerticalScroller = true
		scroller.hasHorizontalScroller = true
		scroller.autohidesScrollers = false
		scroller.borderType = .bezelBorder
		scroller.autoresizingMask = [.width, .height]
		scroller.documentView = gridView
		view.addSubview(scroller)
		gridScrollView = scroller

		buildControlStrip(above: scroller, in: bounds, height: stripHeight)

		if let doc = resolvedDocument() {
			doc.addObserver(self, forKeyPath: "theMusic", options: [.initial], context: &BoxViewController.musicContext)
			observedDocument = doc
		}
    }

	// MARK: Control strip
	//
	// Mode (Note/Trash/Play/Zoom, the original's five buttons minus SeeAll/
	// Prefs/Help -- see BOX-EDITOR-SPEC.md's known gaps), a Track popup
	// (edits always target one concrete track, unlike Classic/Wave's "All"
	// filters), zoom in/out buttons (the original's discrete step table, not
	// a doubling zoom), and the instrument a newly-placed note is stamped
	// with.

	private func buildControlStrip(above scroller: NSView, in bounds: NSRect, height stripHeight: CGFloat) {
		let strip = NSView(frame: NSRect(x: 0, y: bounds.height - stripHeight, width: bounds.width, height: stripHeight))
		strip.autoresizingMask = [.width, .minYMargin]

		var x: CGFloat = 6

		let mode = NSSegmentedControl(frame: NSRect(x: x, y: 4, width: 200, height: 22))
		mode.segmentCount = 4
		mode.setLabel(NSLocalizedString("Note", comment: "box editor mode"), forSegment: 0)
		mode.setLabel(NSLocalizedString("Trash", comment: "box editor mode"), forSegment: 1)
		mode.setLabel(NSLocalizedString("Play", comment: "box editor mode"), forSegment: 2)
		mode.setLabel(NSLocalizedString("Zoom", comment: "box editor mode"), forSegment: 3)
		mode.segmentStyle = .rounded
		mode.selectedSegment = 0
		mode.target = self
		mode.action = #selector(modeChanged(_:))
		strip.addSubview(mode)
		modeControl = mode
		x += mode.frame.width + 14

		x = addLabel(NSLocalizedString("Track:", comment: "box editor track label"), atX: x, toStrip: strip)

		let popup = NSPopUpButton(frame: NSRect(x: x, y: 4, width: 70, height: 22), pullsDown: false)
		popup.target = self
		popup.action = #selector(trackChanged(_:))
		strip.addSubview(popup)
		trackPopup = popup
		x += popup.frame.width + 14

		x = addLabel(NSLocalizedString("Ins:", comment: "box editor instrument label"), atX: x, toStrip: strip)

		let field = NSTextField(frame: NSRect(x: x, y: 5, width: 36, height: 21))
		field.alignment = .right
		field.integerValue = 1
		field.target = self
		field.action = #selector(instrumentChanged(_:))
		strip.addSubview(field)
		instrumentField = field
		x += field.frame.width + 14

		let zoomOut = NSButton(title: "−", target: self, action: #selector(zoomOutTapped))
		zoomOut.bezelStyle = .rounded
		zoomOut.frame = NSRect(x: x, y: 4, width: 28, height: 22)
		strip.addSubview(zoomOut)
		x += 30

		let zoomIn = NSButton(title: "+", target: self, action: #selector(zoomInTapped))
		zoomIn.bezelStyle = .rounded
		zoomIn.frame = NSRect(x: x, y: 4, width: 28, height: 22)
		strip.addSubview(zoomIn)

		view.addSubview(strip)
	}

	private func addLabel(_ text: String, atX x: CGFloat, toStrip strip: NSView) -> CGFloat {
		let label = NSTextField(labelWithString: text)
		label.sizeToFit()
		label.frame = NSRect(x: x, y: 7, width: label.frame.width, height: 17)
		strip.addSubview(label)
		return x + label.frame.width + 4
	}

	@objc private func modeChanged(_ sender: NSSegmentedControl) {
		gridView.mode = BoxGridMode(rawValue: sender.selectedSegment) ?? .note
		view.window?.makeFirstResponder(gridView)
	}

	@objc private func trackChanged(_ sender: NSPopUpButton) {
		gridView.selectedTrack = sender.indexOfSelectedItem
		view.window?.makeFirstResponder(gridView)
	}

	@objc private func instrumentChanged(_ sender: NSTextField) {
		gridView.defaultInstrument = UInt8(clamping: sender.integerValue)
		view.window?.makeFirstResponder(gridView)
	}

	@objc private func zoomInTapped() {
		gridView.zoomIn()
		view.window?.makeFirstResponder(gridView)
	}

	@objc private func zoomOutTapped() {
		gridView.zoomOut()
		view.window?.makeFirstResponder(gridView)
	}

	// MARK: Document binding
	//
	// Same File's Owner quirk every other tab controller in this port works
	// around: currentDocument is wired to File's Owner, which for
	// PPDocument.xib is the DocumentWindowController rather than the
	// document, even though this property is declared PPDocument!. Reading
	// through AnyObject first avoids ever sending a PPDocument-only message
	// to what might actually be a DocumentWindowController instance.
	private func resolvedDocument() -> PPDocument? {
		guard let candidate = currentDocument else { return nil }
		let object = candidate as AnyObject
		if let doc = object as? PPDocument { return doc }
		if let winCon = object as? DocumentWindowController { return winCon.currentDocument }
		return nil
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if context == &BoxViewController.musicContext {
			reloadFromDocument()
		} else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}

	private func reloadFromDocument() {
		guard let doc = resolvedDocument(), let music = doc.theMusic, music.patterns.count > 0 else {
			gridView.pattern = nil
			gridView.music = nil
			return
		}

		gridView.editUndoManager = doc.undoManager
		gridView.trackCount = max(1, music.totalTracks)
		gridView.music = music
		gridView.pattern = (music.patterns[0] as! PPPatternObject)
		gridView.driver = doc.theDriver
		gridView.didEditPattern = { [weak doc] in
			doc?.updateChangeCount(.changeDone)
		}

		rebuildTrackPopup(music.totalTracks)
	}

	private func rebuildTrackPopup(_ trackCount: Int) {
		trackPopup.removeAllItems()
		for i in 0..<trackCount {
			trackPopup.addItem(withTitle: "\(i + 1)")
		}
		trackPopup.selectItem(at: 0)
		gridView.selectedTrack = 0
	}
}
