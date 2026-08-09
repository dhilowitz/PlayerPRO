//
//  Length.swift
//  PPMacho
//
//  Created by C.W. Betts on 11/4/14.
//
//

import Cocoa
import PlayerPROKit.PPPlugIns

public final class LengthPlug: NSObject, PPFilterPlugin {
	public let hasUIConfiguration = true
	
	override init() {
		super.init()
	}
	
	public convenience init(forPlugIn: ()) {
		self.init()
	}
	
	public func run(withData theData: PPSampleObject, selectionRange selRange: NSRange, onlyCurrentChannel StereoMode: Bool, driver: PPDriver) throws {
		throw PPMADError(.orderNotImplemented)
	}
	
	public func beginRun(withData theData: PPSampleObject, selectionRange selRange: NSRange, onlyCurrentChannel StereoMode: Bool, driver: PPDriver, parentWindow document: NSWindow, handler handle: @escaping PPPlugErrorBlock) {
		let controller = LengthWindowController(windowNibName: NSNib.Name(rawValue: "LengthWindowController"))
		controller.theData = theData
		controller.selectionRange = selRange
		controller.stereoMode = StereoMode
		controller.parentWindow = document
		
		document.beginSheet(controller.window!, completionHandler: { (returnCode) -> Void in
			// See DepthPlug.swift's identical fix -- an empty closure here
			// captured nothing, so controller (target of the sheet's OK/
			// Cancel) was deallocated the instant this method returned,
			// leaving the sheet permanently undismissable.
			_ = controller
		})
	}
}
