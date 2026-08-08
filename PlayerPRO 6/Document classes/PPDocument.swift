//
//  PPDocument.swift
//  PPMacho
//
//  Created by C.W. Betts on 8/21/14.
//
//

import Cocoa
import PlayerPROCore
import PlayerPROKit
import AVFoundation
import AudioToolbox

@objc(PPDocument) class PPDocument: NSDocument {	
	var instrumentList: InstrumentPanelController! = nil
	// @objc: WaveViewController.m reaches this to bridge Wave's note-mode
	// clicks into the Digital editor. Plain internal vars on an NSObject
	// subclass aren't visible from Objective-C in Swift 4's reduced
	// implicit-@objc-inference mode (theMusic/theDriver below need the same
	// explicit marker for the same reason).
	@objc var mainViewController: DocumentWindowController! = nil
	// Created lazily, on first use of the Piano menu item -- unlike
	// instrumentList, there is no reason for this window to always be open
	// alongside the document.
	var pianoWindow: PianoWindowController?
	// Same lazy-creation reasoning as pianoWindow.
	var patternListWindow: PatternListWindowController?
	@objc dynamic let theDriver: PPDriver
	// Nothing previously assigned this to the driver: PPDriver.currentMusic
	// stayed nil forever, so -play had nothing to play regardless of whether
	// the transport controls were wired to it.
	@objc dynamic private(set) var theMusic: PPMusicObject! {
		didSet { theDriver.currentMusic = theMusic }
	}

	// Which pattern (an ID -- an index into theMusic.patterns) the four
	// pattern editors currently display. Every editor in this port used to
	// hardcode music.patterns[0] -- there was nowhere else to get a
	// pattern number from, since nothing built the Pattern List window
	// that's supposed to be the actual way to navigate a song's
	// structure. @objc dynamic so each editor's existing KVO observer on
	// theMusic (already used to reload when the document's music object
	// itself changes) can observe this the same way.
	@objc dynamic var currentPatternID: Int = 0


	@objc dynamic var musicName: String {
		get {
			return theMusic.title
		}
		set {
			theMusic.title = newValue
		}
	}
	
	@objc dynamic var musicInfo: String {
		get {
			return theMusic.information
		}
		set {
			theMusic.information = newValue
		}
	}
	
	// MARK: - NSDocument type info
	override class func isNativeType(_ aType: String) -> Bool {
		return aType == MADNativeUTI
	}
	
	override class var readableTypes: [String] {
		struct StaticStorage {
			static var readables: [String]?
		}
		
		if let readables = StaticStorage.readables {
			return readables
		}
		
		let importUTIsArray = globalMadLib.filter({ $0.canImport == true }).map({ $0.UTITypes })
		let importUTISet: Set<String> = {
			var toRet = Set<String>()
			for arr in importUTIsArray {
				toRet.formUnion(arr)
			}
			return toRet
		}()
		var toRet = Array(importUTISet)
		toRet.insert(MADNativeUTI, at: 0)
		toRet.append(MADGenericUTI)
		StaticStorage.readables = toRet
		return toRet
	}
	
	override class var writableTypes: [String] {
		struct StaticStorage {
			static var writables: [String]?
		}
		
		if let writables = StaticStorage.writables {
			return writables
		}
		
		var toRet = globalMadLib.filter({ $0.canExport == true }).map({ $0.UTITypes.first! })
		toRet.insert(MADNativeUTI, at: 0)
		StaticStorage.writables = toRet
		return toRet
	}
	
	// MARK: -
	
	override func makeWindowControllers() {
		let docWinCon = DocumentWindowController(windowNibName: NSNib.Name(rawValue: "PPDocument"))
		addWindowController(docWinCon)
		docWinCon.currentDocument = self
		instrumentList = InstrumentPanelController(windowNibName: NSNib.Name(rawValue: "InsPanel"))
		addWindowController(instrumentList)
		instrumentList.currentDocument = self
		mainViewController = docWinCon

		// InsPanel.xib and PPDocument.xib place their windows almost exactly on
		// top of each other (63pt apart), so the instrument panel opens hiding
		// most of the document window on every launch. Anchor it to the right
		// of the document window instead, falling back to a small offset if
		// there is no room on screen.
		if let docWindow = docWinCon.window, let insWindow = instrumentList.window {
			let gap: CGFloat = 12
			var origin = NSPoint(x: docWindow.frame.maxX + gap,
								  y: docWindow.frame.maxY - insWindow.frame.height)
			if let screen = docWindow.screen ?? NSScreen.main,
			   origin.x + insWindow.frame.width > screen.visibleFrame.maxX {
				origin = NSPoint(x: docWindow.frame.minX + 24, y: docWindow.frame.minY - 24)
			}
			insWindow.setFrameOrigin(origin)
		}

		// NSDocument shows window controllers in the order they were added,
		// each via its own showWindow(_:)/makeKeyAndOrderFront -- so
		// instrumentList (added second, above) ends up key, not the main
		// document window. Every menu item whose action lives on
		// DocumentWindowController (Instruments List, Partition List, etc.)
		// is validated against the key window's responder chain, so with
		// the instrument panel key they all show up grayed out until the
		// user happens to click the document window themselves. Re-key the
		// document window explicitly so the menu bar is correct from the
		// moment a document opens.
		docWinCon.window?.makeKeyAndOrderFront(self)
	}

	/// Shows this document's piano keyboard window, creating it on first use.
	func showPiano() {
		let piano: PianoWindowController
		if let existing = pianoWindow {
			piano = existing
		} else {
			piano = PianoWindowController()
			piano.currentDocument = self
			piano.noteEntered = { [weak self] note in
				self?.mainViewController.enterPianoNote(note)
			}
			pianoWindow = piano
		}
		piano.showWindow(self)
		piano.window?.makeKeyAndOrderFront(self)
	}

	/// Shows this document's pattern (order) list window, creating it on
	/// first use.
	func showPatternList() {
		let list: PatternListWindowController
		if let existing = patternListWindow {
			list = existing
		} else {
			list = PatternListWindowController()
			list.currentDocument = self
			patternListWindow = list
		}
		list.reload()
		list.showWindow(self)
		list.window?.makeKeyAndOrderFront(self)
	}

	private func resetPlayerPRODriver() {
		var theSett = MADDriverSettings.new()
		let defaults = UserDefaults.standard
		
		//TODO: Sanity Checking
		theSett.surround = defaults.bool(forKey: PPSurroundToggle)
		theSett.outPutRate = UInt32(defaults.integer(forKey: PPSoundOutRate))
		theSett.outPutBits = Int16(defaults.integer(forKey: PPSoundOutBits))
		if (defaults.bool(forKey: PPOversamplingToggle)) {
			theSett.oversampling = Int32(defaults.integer(forKey: PPOversamplingAmount))
		} else {
			theSett.oversampling = 1;
		}
		theSett.Reverb = defaults.bool(forKey: PPReverbToggle)
		theSett.ReverbSize = Int32(defaults.integer(forKey: PPReverbAmount))
		theSett.ReverbStrength = Int32(defaults.integer(forKey: PPReverbStrength))
		if (defaults.bool(forKey: PPStereoDelayToggle)) {
			theSett.MicroDelaySize = Int32(defaults.integer(forKey: PPStereoDelayAmount))
		} else {
			theSett.MicroDelaySize = 0;
		}
		
		theSett.driverMode = MADSoundOutput(rawValue: Int16(defaults.integer(forKey: PPSoundDriver))) ?? .CoreAudioDriver
		theSett.repeatMusic = false;
		
		do {
			try theDriver.changeDriverSettings(to: &theSett)
		} catch {
			Swift.print("Unable to change driver for \(self), error '\(error)'")
			//NSAlert(error: createErrorFromMADErrorType(returnerr)).beginSheetModalForWindow(self.windowForSheet, completionHandler: { (returnCode) -> Void in
			//currently, do nothing
			//})

		}
	}
	
	@objc private func soundPreferencesDidChange(_ notification: Notification) {
		resetPlayerPRODriver()
	}
	
	convenience init(music: PPMusicObject) {
		self.init()
		theMusic = music
		// theMusic's didSet (which attaches this music to theDriver) does
		// not fire for this assignment -- confirmed with a standalone
		// reproduction of this exact pattern (an @objc dynamic property,
		// set from a convenience init after self.init() has already
		// returned): Swift silently skips the observer here. Every
		// document created this way (a brand new untitled song, and
		// complex-format imports via AppDelegate) never got its music
		// attached to the driver at all, so pattern playback had nothing
		// to play -- not a sample/instrument-import-specific bug, a
		// document-creation one. Explicit call needed until/unless this
		// initializer is restructured so didSet can be trusted here.
		theDriver.currentMusic = music
	}
	
	override init() {
		var drivSettings = MADDriverSettings.new()
		let defaults = UserDefaults.standard
		
		//TODO: Sanity Checking
		drivSettings.surround = defaults.bool(forKey: PPSurroundToggle)
		drivSettings.outPutRate = UInt32(defaults.integer(forKey: PPSoundOutRate))
		drivSettings.outPutBits = Int16(defaults.integer(forKey: PPSoundOutBits))
		if defaults.bool(forKey: PPOversamplingToggle) {
			drivSettings.oversampling = Int32(defaults.integer(forKey: PPOversamplingAmount))
		} else {
			drivSettings.oversampling = 1
		}
		drivSettings.Reverb = defaults.bool(forKey: PPReverbToggle)
		drivSettings.ReverbSize = Int32(defaults.integer(forKey: PPReverbAmount))
		drivSettings.ReverbStrength = Int32(defaults.integer(forKey: PPReverbStrength))
		if (defaults.bool(forKey: PPStereoDelayToggle)) {
			drivSettings.MicroDelaySize = Int32(defaults.integer(forKey: PPStereoDelayAmount))
		} else {
			drivSettings.MicroDelaySize = 0;
		}
		
		drivSettings.driverMode = MADSoundOutput(rawValue: Int16(defaults.integer(forKey: PPSoundDriver))) ?? .CoreAudioDriver
		drivSettings.repeatMusic = false;
		
		theDriver = try! PPDriver(library: globalMadLib, settings: &drivSettings)
		super.init()
		
		let defaultCenter = NotificationCenter.default
		defaultCenter.addObserver(self, selector: #selector(PPDocument.soundPreferencesDidChange(_:)), name: .PPSoundPreferencesDidChange, object: nil)
	}
	
    override func windowControllerDidLoadNib(_ aController: NSWindowController) {
        super.windowControllerDidLoadNib(aController)
        // Add any code here that needs to be executed once the windowController has loaded the document's window.
    }

	override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
		savePanel.directoryURL = PPLastDirectory.url(for: "documentSave")
		return true
	}

	override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
		super.save(to: url, ofType: typeName, for: saveOperation) { error in
			if error == nil {
				PPLastDirectory.remember(url, for: "documentSave")
			}
			completionHandler(error)
		}
	}

	override func write(to url: URL, ofType typeName: String) throws {
		if typeName != MADNativeUTI {
			guard let type = globalMadLib.typeFromUTI(typeName) else {
				throw NSError(domain: NSOSStatusErrorDomain, code: paramErr, userInfo: nil)
			}
			try theMusic.exportMusic(to: url, format: type, library: globalMadLib)
		} else {
			do {
				try theMusic.saveMusic(to: url, compress: UserDefaults.standard.bool(forKey: PPMMadCompression))
			} catch {
				if let error = error as? MADErr {
					throw error.convertToCocoaType()
				} else {
					throw error
				}
			}
		}
	}
	
	//override func write(to url: URL, ofType typeName: String, for saveOperation: NSSaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
	//	try super.write(to: url, ofType: typeName, for: saveOperation, originalContentsURL: absoluteOriginalContentsURL)
	//}
	
	override func read(from url: URL, ofType typeName: String) throws {
		func getType() throws -> String {
			if let type = globalMadLib.typeFromUTI(typeName) {
				return type
			}
			
			return try globalMadLib.identifyFile(at: url)
		}
		
		if typeName == MADNativeUTI {
			theMusic = try PPMusicObject(url: url, driver: theDriver)
		} else {
			let theType = try getType()
			theMusic = try PPMusicObject(url: url, stringType: theType, driver: theDriver)
			fileURL = nil
		}
	}
	
	override var autosavingFileType: String? {
		return MADNativeUTI
	}
	
	// autosavesInPlace = true switches NSDocument to Apple's modern
	// versions/autosave-in-place model (like TextEdit): background saves
	// go through ~/Library/Autosave Information, and Save As is meant to
	// be replaced by Duplicate/Move To/Browse All Versions. This app's
	// menu was never built for that model -- MainMenu.xib only has classic
	// Save/Save As/Revert wiring (saveDocumentAs:), no Duplicate or
	// versions-browser items anywhere -- so this looks like an inherited
	// Xcode template default rather than an intentional choice. With it on,
	// Save As... surfaced ~/Library/Autosave Information as its directory
	// instead of a real user-chosen location. False restores the classic
	// explicit-save behavior the rest of the UI already assumes.
	override class var autosavesInPlace: Bool {
		return false
	}

	func importMusicObject(_ theObj: PPMusicObject) {
		if theMusic == nil {
			theMusic = theObj
		}
	}
		
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}
