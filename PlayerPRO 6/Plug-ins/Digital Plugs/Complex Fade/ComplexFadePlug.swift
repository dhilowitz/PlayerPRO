//
//  CompFadePlug.swift
//  PPMacho
//
//  Created by C.W. Betts on 9/15/14.
//
//

import Foundation
import PlayerPROKit.PPPlugIns

public final class ComplexFade: NSObject, PPDigitalPlugin {
	public var hasUIConfiguration: Bool {
		return true
	}
	
	public convenience init(forPlugIn: ()) {
		self.init()
	}
	
	override public init() {
		super.init()
	}
	
	public func run(with aPcmd: UnsafeMutablePointer<Pcmd>, driver: PPDriver) throws {
		throw PPMADError(.orderNotImplemented)
	}
	
	public func beginRun(with aPcmd: UnsafeMutablePointer<Pcmd>, driver: PPDriver, parentWindow window: NSWindow, handler: @escaping PPPlugErrorBlock) {
		let controller = ComplexFadeController(windowNibName: NSNib.Name(rawValue: "ComplexFadeController"))
		controller.thePcmd = aPcmd;
		controller.fadeType = .instrument;
		controller.currentBlock = handler
		controller.parentWindow = window

		window.beginSheet(controller.window!, completionHandler: { (retVal) -> Void in
			// See DepthPlug.swift's identical fix -- an empty closure here
			// captured nothing, so controller (target of the sheet's OK/
			// Cancel) was deallocated the instant this method returned,
			// leaving the sheet permanently undismissable.
			_ = controller
		})
	}
}
