//
//  InstrumentPanelController.swift
//  PPMacho
//
//  Created by C.W. Betts on 9/29/14.
//
//

import Cocoa
import PlayerPROKit

class InstrumentPanelController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
	@IBOutlet weak var instrumentOutline:	NSOutlineView!
	
	@IBOutlet weak var currentDocument: PPDocument!
	weak var instrumentImporter: PPInstrumentPlugHandler!
	weak var sampleImporter: SamplePlugHandler!
	weak var filterHandler: FilterPlugHandler!
	weak var theDriver: PPDriver!
	
	// addWindowController (PPDocument.swift) puts this controller under the
	// document's automatic synchronizeWindowTitleWithDocumentName(), which
	// would otherwise overwrite InsPanel.xib's "Instruments" window title
	// with just the document's own display name.
	override func windowTitle(forDocumentDisplayName displayName: String) -> String {
		return String(format: NSLocalizedString("Instruments (%@)", comment: "instrument panel window title, %@ is the document name"), displayName)
	}

	func colorsDidChange(_ aNot: Notification) {

	}
	
	@IBAction func playSample(_ sender: AnyObject!) {
		// sender here is the NSButton the user clicked, not its cell -- this
		// force-cast to NSButtonCell always failed and crashed the app.
		guard let tag = (sender as? NSControl)?.tag else { return }
		let sampNum = tag % Int(MAXSAMPLE)
		let instrNum = tag / Int(MAXSAMPLE)
		playSample(instrument: Int16(instrNum), sample: Int16(sampNum))
	}
	
	private func loadInstrumentsFromMusic() {
		if (instrumentOutline != nil) {
			instrumentOutline.reloadData()
			instrumentOutline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
			instrumentOutline.scrollToBeginningOfDocument(nil)
		}
	}
	
	func importSample(from sampURL: URL, makeUserSelectInstrument selIns: Bool = false) throws {
		//TODO: handle selIns
		let plugType: MADFourChar = try sampleImporter.identifySampleFile(sampURL)

		// Used to always target instruments.first regardless of which
		// instrument was actually selected in the outline -- importing into
		// any slot but the very first one silently landed the new sample
		// somewhere the user wasn't looking, which read as "nothing
		// happened." Also never refreshed the outline/detail pane
		// afterward, so even a first-slot import wouldn't visibly show up
		// without deselecting and reselecting it by hand.
		guard let targetInstrument = selectedInstrument ?? currentDocument.theMusic.instruments.first else { return }

		sampleImporter.beginImportingSample(type: plugType, URL: sampURL, driver: theDriver, parentDocument: currentDocument) { (err, obj) in
			if let err = err {
				self.currentDocument.presentError(err)
			} else if let obj = obj {
				targetInstrument.add(obj)
				// The writeback into the MADMusic struct above is correct on
				// its own, but the live engine only ever runs its attach
				// step (which builds its own per-attach state) when
				// currentMusic actually changes -- it has no other way to
				// notice a sample added to an already-attached document.
				// Without this, the new sample shows up fine in this UI and
				// even plays via the toolbar/row preview buttons (those read
				// PPSampleObject.data directly, bypassing the engine
				// entirely), but pattern playback through the transport
				// can't find it until the document is closed and reopened,
				// which forces a fresh attach.
				// Logged either way, not just on failure: this was
				// previously swallowed silently via try?, and if pattern
				// playback still can't find a sample imported live even
				// with this succeeding, the reattach isn't the actual
				// fix and the real cause is still somewhere else.
				do {
					try self.theDriver.reattachCurrentMusic()
					NSLog("PPInstrumentPanelController: reattachCurrentMusic succeeded after importing sample into instrument %ld", targetInstrument.number)
				} catch {
					NSLog("PPInstrumentPanelController: reattachCurrentMusic FAILED after importing sample into instrument %ld: %@", targetInstrument.number, error as NSError)
				}
				self.instrumentOutline.reloadData()
				self.instrumentOutline.expandItem(targetInstrument)
				self.outlineViewSelectionDidChange(Notification(name: NSOutlineView.selectionDidChangeNotification))
				self.currentDocument.updateChangeCount(.changeDone)
			}
		}
	}

	func importInstrument(from sampURL: URL, makeUserSelectInstrument selIns: Bool = false) throws {
		//TODO: handle selIns
		let plugType: MADFourChar = try instrumentImporter.identifyInstrumentFile(sampURL)
		var theSamp: Int16 = 0;
		var theIns: Int16  = 0;

		instrumentImporter.beginImportingInstrument(ofType: plugType, from: sampURL, driver: currentDocument.theDriver, parentDocument: currentDocument) { (err, obj) in
			if let err = err {
				self.currentDocument.presentError(err)
			} else if let obj = obj {
				self.replaceObjectInInstruments(at: Int(theIns), withObject: obj)
				// Same reasoning and same logging as importSample(from:)'s
				// reattach above.
				do {
					try self.theDriver.reattachCurrentMusic()
					NSLog("PPInstrumentPanelController: reattachCurrentMusic succeeded after importing instrument at index %d", theIns)
				} catch {
					NSLog("PPInstrumentPanelController: reattachCurrentMusic FAILED after importing instrument at index %d: %@", theIns, error as NSError)
				}
				self.instrumentOutline.reloadData()
			} else {
				
			}
		}
	}
	
	func exportInstrumentList(to outURL: URL) -> MADErr {
		return currentDocument.theMusic.exportInstrumentList(to: outURL)
	}
	
	func importInstrumentList(from insURL: URL) throws {
		try currentDocument.theMusic.importInstrumentList(from: insURL)
	}
	
	@IBAction func importInstrument(_ sender: AnyObject!) {
		var fileDict = [String: [String]]()
		for obj in instrumentImporter {
			fileDict[obj.menuName] = obj.utiTypes
		}
		for obj in sampleImporter {
			fileDict[obj.menuName] = obj.utiTypes
		}

		let openPanel = NSOpenPanel()
		openPanel.directoryURL = PPLastDirectory.url(for: "instrumentFile")
		if let vc = OpenPanelViewController(openPanel: openPanel, instrumentDictionary:fileDict) {
			vc.setupDefaults()
			vc.beginOpenPanel(currentDocument.windowForSheet!, completionHandler: { (panelHandle: NSApplication.ModalResponse) -> Void in
				if panelHandle.rawValue == NSFileHandlingPanelOKButton {
					PPLastDirectory.remember(openPanel.url!, for: "instrumentFile")
					do {
						_ = try self.instrumentImporter.identifyInstrumentFile(openPanel.url!)
						try self.importInstrument(from: openPanel.url!)
					} catch let error as NSError {
						if error.domain == PPMADErrorDomain && error.code == Int(MADErr.cannotFindPlug.rawValue) {
							// Try sample importing
							do {
								try self.importSample(from: openPanel.url!)
							} catch {
								self.currentDocument.presentError(error)
							}
						} else {
							//present error
							self.currentDocument.presentError(error)
						}
					}
				}
			})
		}
	}
	
	// The actual audition primitive both playInstrument(_:) (the toolbar
	// button) and playSample(_:) (each row's inline play button) feed into
	// -- this was completely empty, so neither one has ever played audio
	// this whole port's life. A force-cast crash in playSample(_:) was
	// fixed earlier in this project's history, but that only stopped the
	// crash; it never made this body do anything. Same
	// PPDriver.playSoundData(...withNote:) primitive PianoKeyboardView/
	// BoxGridView's audition(note:) already use, which pitch-shifts from
	// the sample's own base rate.
	func playSample(instrument: Int16, sample sampleNumber: Int16, volume: UInt8 = 0xFF, note: UInt8 = 0xFF) {
		guard instrument >= 0, Int(instrument) < currentDocument.theMusic.instruments.count else { return }
		let ins = currentDocument.theMusic.instruments[Int(instrument)]
		guard sampleNumber >= 0, Int(sampleNumber) < ins.countOfSamples else { return }
		let samp = ins.samplesObject(at: Int(sampleNumber))
		guard let data = samp.data else { return }

		let channel = Int32(theDriver.availableChannel)
		guard channel >= 0 else { return }

		let playNote = note == 0xFF ? UInt8(samp.realNote) : note
		let playVolume = volume == 0xFF ? Int16(samp.volume) : Int16(volume)
		try? theDriver.playSoundData(from: data as Data, fromChannel: channel,
									  amplitude: playVolume, bitRate: UInt32(samp.c2spd),
									  isStereo: samp.isStereo, withNote: playNote)
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		// Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
		//instrumentOutline.selectRowIndexes(NSIndexSet(index: 0), byExtendingSelection: false)
		theDriver = currentDocument.theDriver
		sampleImporter = (AppDelegate.shared as! AppDelegate).samplesHandler
		instrumentImporter = (AppDelegate.shared as! AppDelegate).instrumentPlugHandler
		filterHandler = (AppDelegate.shared as! AppDelegate).filterHandler

		instrumentOutline.target = self
		instrumentOutline.doubleAction = #selector(openSampleEditor(_:))
	}
	
	
	/// Plugins currently offered by an in-flight export save panel's format
	/// popup -- indices must line up with that popup's items. Held here,
	/// not captured in a closure, since exportFormatPopupChanged(_:) is a
	/// plain target/action callback.
	private var pendingExportPlugs: [PPInstrumentImporterObject] = []

	// sender is either one of the per-plugin menu items AppDelegate builds
	// under Instruments > Export (tagged with its index into
	// instrumentImporter, same shape as
	// DocumentWindowController.exportMusicAs(_:)), OR InsPanel's own
	// toolbar "Export" button (InsPanel.xib, tag -1, wired directly to this
	// same selector with itself as sender) -- which carries no plugin
	// choice at all. This used to only handle the first case, so the
	// toolbar button -- the one actually reachable without digging into the
	// menu bar, and almost certainly what was clicked to report this bug --
	// silently did nothing.
	@IBAction func exportInstrument(_ sender: AnyObject!) {
		guard let instrument = selectedInstrument else { return }

		if let menuItem = sender as? NSMenuItem, menuItem.tag >= 0, menuItem.tag < instrumentImporter.plugInCount {
			presentExportPanel(for: instrument, using: instrumentImporter[menuItem.tag])
			return
		}

		let exportPlugs = instrumentImporter.filter { $0.mode == .export || $0.mode == .importExport }
		guard !exportPlugs.isEmpty else { return }

		if exportPlugs.count == 1 {
			presentExportPanel(for: instrument, using: exportPlugs[0])
			return
		}

		pendingExportPlugs = exportPlugs
		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 25))
		popup.addItems(withTitles: exportPlugs.map { $0.menuName })
		popup.target = self
		popup.action = #selector(exportFormatPopupChanged(_:))

		let savePanel = NSSavePanel()
		savePanel.accessoryView = popup
		savePanel.nameFieldStringValue = instrument.name
		savePanel.allowedFileTypes = exportPlugs[0].utiTypes
		savePanel.directoryURL = PPLastDirectory.url(for: "instrumentFile")

		savePanel.beginSheetModal(for: currentDocument.windowForSheet!) { [pendingExportPlugs] result in
			guard result == .OK, let url = savePanel.url else { return }
			PPLastDirectory.remember(url, for: "instrumentFile")
			self.performExport(instrument, using: pendingExportPlugs[popup.indexOfSelectedItem], to: url)
		}
	}

	@objc private func exportFormatPopupChanged(_ sender: NSPopUpButton) {
		(sender.window as? NSSavePanel)?.allowedFileTypes = pendingExportPlugs[sender.indexOfSelectedItem].utiTypes
	}

	private func presentExportPanel(for instrument: PPInstrumentObject, using plug: PPInstrumentImporterObject) {
		let savePanel = NSSavePanel()
		savePanel.allowedFileTypes = plug.utiTypes
		savePanel.nameFieldStringValue = instrument.name
		savePanel.title = String(format: NSLocalizedString("Export as %@", comment: "export instrument panel title"), plug.menuName)
		savePanel.directoryURL = PPLastDirectory.url(for: "instrumentFile")

		savePanel.beginSheetModal(for: currentDocument.windowForSheet!) { result in
			guard result == .OK, let url = savePanel.url else { return }
			PPLastDirectory.remember(url, for: "instrumentFile")
			self.performExport(instrument, using: plug, to: url)
		}
	}

	private func performExport(_ instrument: PPInstrumentObject, using plug: PPInstrumentImporterObject, to url: URL) {
		plug.beginExportInstrument(instrument, to: url, driver: theDriver, parentDocument: currentDocument) { error in
			if let error = error {
				self.currentDocument.presentError(error)
			}
		}
	}
	
	@IBAction func deleteInstrument(_ sender: AnyObject!) {

	}

	// Wired to InsPanel's toolbar "New" button and the Instruments menu's
	// "New Instrument" item (MainMenu.xib), neither of which previously had
	// any connection at all -- the menu item pointed at an empty, never-
	// populated submenu instead of an action. newInstrumentObjectByAddingToMusic:
	// already both creates the instrument and appends it to the music, so
	// there's nothing else to wire up here beyond refreshing the outline.
	@IBAction func newInstrument(_ sender: AnyObject!) {
		guard let newInstrument = PPInstrumentObject.newInstrumentObjectByAdding(toMusic: currentDocument.theMusic) else { return }
		instrumentOutline.reloadData()
		if let row = instrumentOutline.row(forItem: newInstrument) as Int?, row >= 0 {
			instrumentOutline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		}
		currentDocument.updateChangeCount(.changeDone)
	}
	
	// Wired to InsPanel's toolbar Play button (InsPanel.xib), which
	// previously had no action connection at all -- clicking it couldn't
	// have done anything regardless of this method's body. Plays the
	// selected instrument's first sample, same primitive PianoKeyboardView/
	// BoxGridView's audition(note:) already use elsewhere in this port.
	@IBAction func playInstrument(_ sender: AnyObject!) {
		guard let instrument = selectedInstrument, instrument.countOfSamples > 0 else { return }
		playSample(instrument: Int16(instrument.number), sample: 0)
	}
	
	@IBAction func showInstrumentInfo(_ sender: AnyObject!) {
		
	}
	
	// Double-clicking a sample row opens its editor directly; double-clicking
	// an instrument row is a no-op here (the legacy app routes that to a
	// separate, not-yet-built instrument-info editor -- out of scope).
	@objc private func openSampleEditor(_ sender: Any?) {
		guard let sample = instrumentOutline.item(atRow: instrumentOutline.clickedRow) as? PPSampleObject,
			  let instrument = instrumentOutline.parent(forItem: sample) as? PPInstrumentObject else { return }
		currentDocument.showSampleEditor(for: instrument, sampleIndex: sample.sampleIndex)
	}

	// Replaces the old NSDrawer-based static waveform preview (InsPanel.xib's
	// "Waveform" toolbar button, previously wired to toggleInfo: which just
	// opened/closed a drawer showing a read-only image) -- opens the real,
	// interactive editor for the selected instrument's first sample instead.
	@IBAction func openSampleEditorForSelection(_ sender: AnyObject!) {
		guard let instrument = selectedInstrument, instrument.countOfSamples > 0 else { return }
		currentDocument.showSampleEditor(for: instrument, sampleIndex: 0)
	}
	
	// Wired to InsPanel's toolbar "Delete" button (InsPanel.xib), which
	// previously had no connection at all -- it wasn't merely disabled by
	// validation, nothing could ever dispatch to it in the first place.
	@IBAction func deleteSample(_ sender: AnyObject!) {
		guard let sample = instrumentOutline.item(atRow: instrumentOutline.selectedRow) as? PPSampleObject,
			  let instrument = instrumentOutline.parent(forItem: sample) as? PPInstrumentObject else {
			NSSound.beep()
			return
		}
		instrument.removeSamples(at: IndexSet(integer: sample.sampleIndex))
		instrumentOutline.reloadData()
		currentDocument.updateChangeCount(.changeDone)
	}
	
	/// The instrument the outline selection currently resolves to -- either
	/// the selected row itself, or (when a sample subrow is selected) its
	/// owning instrument. Used to feed the piano keyboard window, which
	/// auditions and drags notes through whichever instrument is selected
	/// here, same as the original's "currently selected instrument" concept.
	var selectedInstrument: PPInstrumentObject? {
		guard let item = instrumentOutline?.item(atRow: instrumentOutline.selectedRow) else { return nil }
		if let ins = item as? PPInstrumentObject { return ins }
		if let samp = item as? PPSampleObject {
			return instrumentOutline.parent(forItem: samp) as? PPInstrumentObject
		}
		return nil
	}

	@objc func outlineViewSelectionDidChange(_ notification: Notification) {
		// Used to also populate the NSDrawer-based static waveform/detail
		// preview here (instrumentSize/instrumentLoopStart/etc, waveFormImage)
		// -- retired in favor of the real, interactive sample editor window
		// (double-click a sample row, or the toolbar's "Waveform" button for
		// the selected instrument's first sample).
		currentDocument?.pianoWindow?.refreshSelectedInstrument()
	}
	
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if item == nil {
			return currentDocument.theMusic.instruments.count
		}
		if let obj = item as? PPInstrumentObject {
			return obj.countOfSamples
		}
		
		return 0
	}
	
	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if item == nil {
			return currentDocument.theMusic.instruments[index]
		}
		if let obj = item as? PPInstrumentObject {
			return obj.samplesObject(at: index)
		}
		return NSNull()
	}
	
	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		if let obj = item as? PPInstrumentObject {
			return obj.countOfSamples != 0
		}
		return false
	}
	
	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		if tableColumn == nil {
			return nil
		}
		let theView = outlineView.makeView(withIdentifier: tableColumn!.identifier, owner: nil) as! PPInstrumentCellView
		theView.controller = self
		theView.textField?.isEditable = true
		theView.textField?.delegate = self
		if let obj = item as? PPInstrumentObject {
			theView.isSample = false
			theView.textField!.stringValue = obj.name
			theView.numField!.stringValue = String(format:"%03ld", obj.number + 1)
			theView.isBlank = obj.countOfSamples <= 0;
		} else if let obj2 = item as? PPSampleObject {
			theView.isSample = true
			theView.textField!.stringValue = obj2.name
			if (item as AnyObject).loopSize != 0 {
				theView.isLoopingSample = true
			} else {
				theView.isLoopingSample = false
			}
			theView.sampleButton!.tag = obj2.instrumentIndex * Int(MAXSAMPLE) + obj2.sampleIndex
			theView.isBlank = false
		}
		return theView
	}
	
	// The per-row name field (InsPanel.xib, PPInstrumentCellView's textField)
	// was never made editable, and had no delegate -- the model side
	// (-[PPInstrumentObject setName:]/-[PPSampleObject setName:]) already
	// writes straight through to the underlying struct, so this was a pure
	// UI gap, not a model bug. Handles both instrument and sample rows,
	// since both share the same textField outlet/prototype cell.
	override func controlTextDidEndEditing(_ obj: Notification) {
		guard let textField = obj.object as? NSTextField else { return }
		let row = instrumentOutline.row(for: textField)
		guard row >= 0, let item = instrumentOutline.item(atRow: row) else { return }
		if let instrument = item as? PPInstrumentObject {
			guard instrument.name != textField.stringValue else { return }
			instrument.name = textField.stringValue
		} else if let sample = item as? PPSampleObject {
			guard sample.name != textField.stringValue else { return }
			sample.name = textField.stringValue
		} else {
			return
		}
		currentDocument.updateChangeCount(.changeDone)
	}

	@objc(replaceObjectInInstrumentsAtIndex:withObject:)
	func replaceObjectInInstruments(at index: Int, withObject object: PPInstrumentObject!) {
		currentDocument.theMusic.replaceInInstruments(at: index, with: object)
	}
	
}
