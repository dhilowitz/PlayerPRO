//
//  SampleEditorWindowController.swift
//  PlayerPRO 6
//
//  A per-sample waveform editor window, opened by double-clicking a sample
//  row in the Instrument Panel -- the modern equivalent of the legacy app's
//  Samples.c dialog (one window per instrument slot). Built entirely in
//  code, following the same shape as PatternListWindowController/
//  PianoWindowController: no nib, cached per document, registered via
//  addWindowController so document-hosted menu actions keep validating
//  while this window is key.
//

import Cocoa
import PlayerPROKit

final class SampleEditorWindowController: NSWindowController {

	weak var currentDocument: PPDocument?
	private(set) var instrument: PPInstrumentObject!
	private(set) var sampleIndex: Int = 0

	let editorView = SampleEditorView(frame: NSRect(x: 0, y: 0, width: 640, height: 220))

	private weak var filterHandler: FilterPlugHandler!
	private weak var theDriver: PPDriver!

	/// Always re-resolved, never stored: replaceInSamples(at:with:) installs
	/// a fresh copy on every commit (PPInstrumentObject.m's write-through
	/// fix always copies before storing, matching addSamplesObject:'s own
	/// convention), so a stored reference here would go stale after the
	/// very first edit and silently diverge from what's actually in
	/// instrument.samples.
	var sample: PPSampleObject {
		instrument.samplesObject(at: sampleIndex)
	}

	convenience init() {
		let contentWidth: CGFloat = 640
		let stripHeight: CGFloat = 30
		let waveformHeight: CGFloat = 220

		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: stripHeight + waveformHeight),
							   styleMask: [.titled, .closable, .miniaturizable, .resizable],
							   backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false

		self.init(window: window)

		let content = window.contentView!

		let scroller = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: waveformHeight))
		scroller.hasHorizontalScroller = true
		scroller.hasVerticalScroller = false
		scroller.autohidesScrollers = false
		scroller.autoresizingMask = [.width, .height]
		scroller.documentView = editorView
		content.addSubview(scroller)

		let strip = NSView(frame: NSRect(x: 0, y: waveformHeight, width: contentWidth, height: stripHeight))
		strip.autoresizingMask = [.width, .minYMargin]
		content.addSubview(strip)
	}

	/// Finishes configuring a freshly-init()'d controller for a specific
	/// (instrument, sample) slot -- kept separate from init() since
	/// currentDocument/filterHandler/theDriver aren't known at construction
	/// time in PPDocument.showSampleEditor(for:sampleIndex:)'s
	/// create-and-cache flow.
	func configure(document: PPDocument, instrument: PPInstrumentObject, sampleIndex: Int) {
		self.currentDocument = document
		self.instrument = instrument
		self.sampleIndex = sampleIndex
		self.filterHandler = (AppDelegate.shared as! AppDelegate).filterHandler
		self.theDriver = document.theDriver

		editorView.editUndoManager = document.undoManager
		editorView.commitMutation = { [weak self] name, mutate in
			self?.commitEdit(name, mutate)
		}

		let samp = sample
		window?.title = String(format: NSLocalizedString("%d - %@", comment: "sample editor window title: index - name"),
								sampleIndex, samp.name.isEmpty ? NSLocalizedString("Untitled", comment: "unnamed sample") : samp.name)
		editorView.sampleObject = samp
	}

	// MARK: Commit

	/// The single choke point every mutation (data edit, loop edit, filter
	/// result) goes through: re-fetch the canonical sample, apply the
	/// mutation, write it through to the music struct, push the change to
	/// the live driver, mark the document dirty, and refresh the view with
	/// the freshly-installed copy so it's never left looking at an orphaned
	/// instance.
	func commitEdit(_ name: String, _ mutate: (PPSampleObject) -> Void) {
		let current = sample
		mutate(current)
		instrument.replaceInSamples(at: sampleIndex, with: current)

		do {
			try theDriver.reattachCurrentMusic()
		} catch {
			NSLog("SampleEditorWindowController: reattachCurrentMusic failed after \(name): \(error)")
		}

		currentDocument?.updateChangeCount(.changeDone)

		let refreshed = sample
		editorView.sampleObject = refreshed
		// Matches every other reload site in InstrumentPanelController --
		// there's no existing per-row refresh helper, only whole-outline
		// reloadData().
		currentDocument?.instrumentList?.instrumentOutline?.reloadData()
	}
}
