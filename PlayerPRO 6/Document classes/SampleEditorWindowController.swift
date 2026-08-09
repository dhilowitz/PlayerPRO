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

	// addWindowController (PPDocument.swift's showSampleEditor(for:sampleIndex:))
	// puts this controller under the document's automatic
	// synchronizeWindowTitleWithDocumentName(), which otherwise silently
	// overwrites any title set elsewhere (e.g. configure(), below) with
	// just the document's own display name -- this is the documented hook
	// for a window controller to have a say in that instead.
	override func windowTitle(forDocumentDisplayName displayName: String) -> String {
		let rawName: String = sample.name ?? ""
		let sampleName = rawName.isEmpty ? NSLocalizedString("Untitled", comment: "unnamed sample") : rawName
		return String(format: NSLocalizedString("Sample Editor (%@ \u{203A} %@)", comment: "sample editor window title: document name, sample name"),
					  displayName, sampleName)
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
		buildControlStrip(strip)
	}

	// MARK: Zoom controls
	//
	// A small +/-/Fit button strip, mirroring PianoWindowController's
	// octave-shift buttons rather than a slider, for visual consistency
	// with this window's only sibling built the same code-only way.

	private func buildControlStrip(_ strip: NSView) {
		let zoomOut = NSButton(title: "\u{2212}", target: editorView, action: #selector(SampleEditorView.zoomOut))
		zoomOut.bezelStyle = .rounded
		zoomOut.frame = NSRect(x: 6, y: 4, width: 34, height: 22)
		strip.addSubview(zoomOut)

		let zoomIn = NSButton(title: "+", target: editorView, action: #selector(SampleEditorView.zoomIn))
		zoomIn.bezelStyle = .rounded
		zoomIn.frame = NSRect(x: 44, y: 4, width: 34, height: 22)
		strip.addSubview(zoomIn)

		let fit = NSButton(title: NSLocalizedString("Fit", comment: "sample editor zoom-to-fit button"),
							target: editorView, action: #selector(SampleEditorView.zoomToFit))
		fit.bezelStyle = .rounded
		fit.frame = NSRect(x: 82, y: 4, width: 44, height: 22)
		strip.addSubview(fit)

		let filters = NSPopUpButton(frame: NSRect(x: 134, y: 3, width: 180, height: 24), pullsDown: true)
		filters.addItem(withTitle: NSLocalizedString("Filters", comment: "sample editor filters popup title"))
		let handler = (AppDelegate.shared as! AppDelegate).filterHandler
		for plug in handler.plugInArray {
			filters.addItem(withTitle: plug.menuName)
		}
		filters.target = self
		filters.action = #selector(filterSelected(_:))
		strip.addSubview(filters)
		filtersPopUp = filters
	}

	private var filtersPopUp: NSPopUpButton!

	// MARK: Filters Plugs

	/// Runs the selected Filters Plug (Normalize/Backwards/Fade/Crop/Echo/
	/// Amplitude/etc, already built and working elsewhere in this port)
	/// against the current selection. beginWithPlugAtIndex already handles
	/// both sync plugs and async-sheet ones uniformly -- the handler closure
	/// below is always the single place undo registration + commit happens,
	/// regardless of which kind actually ran.
	@objc private func filterSelected(_ sender: NSPopUpButton) {
		// Item 0 is the "Filters" title itself (pulls-down menu); real
		// plugs start at 1, matching plugInArray's own 0-based indexing.
		let idx = sender.indexOfSelectedItem - 1
		defer { sender.selectItem(at: 0) }

		guard idx >= 0, let document = currentDocument, editorView.selection.length > 0 else {
			NSSound.beep()
			return
		}

		let target = sample
		let oldData: Data = target.data ?? Data()
		let name = filterHandler.plugInArray[idx].menuName

		filterHandler.beginWithPlugAtIndex(idx, data: target, selectionRange: editorView.selection,
											onlyCurrentChannel: false, driver: theDriver, parentDocument: document) { [weak self] error in
			guard let self = self else { return }
			if let error = error {
				if !PPErrorIsUserCancelled(error) {
					document.presentError(error)
				}
				return
			}
			// target.data was mutated in place by the plug (the same
			// mutableCopy-mutate-reassign idiom every Filters Plug already
			// uses) -- register undo against the pre-filter snapshot, then
			// commit (write-through/reattach/refresh) with a no-op mutate,
			// since the mutation already happened.
			self.editorView.registerExternalDataEditUndo(name, oldData: oldData)
			self.commitEdit(name) { _ in }
		}
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

		// Title is handled by windowTitle(forDocumentDisplayName:) above,
		// not set directly here -- addWindowController's automatic title
		// sync would just overwrite a direct assignment anyway.
		editorView.sampleObject = sample
		editorView.zoomToFit()
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
