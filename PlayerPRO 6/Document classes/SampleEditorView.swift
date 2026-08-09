//
//  SampleEditorView.swift
//  PlayerPRO 6
//
//  The interactive waveform surface for the sample editor window (see
//  SampleEditorWindowController). Draws directly via PPSampleObject's
//  drawSample(...) primitive (PlayerPROKitAdditions.swift) -- a raw-CGContext
//  renderer already used by the (now-retired) static drawer preview -- rather
//  than going through its NSImage-producing wrapper, since this view redraws
//  live as the sample/selection/zoom change.
//

import Cocoa
import PlayerPROKit

final class SampleEditorView: NSView {

	/// Re-set by the window controller after every commit (see
	/// SampleEditorWindowController.commitEdit(_:_:)) -- never held onto
	/// across edits by anything else, since replaceInSamples(at:with:)
	/// always installs a fresh copy (see PPInstrumentObject.m's write-through
	/// fix), so a stale reference here would silently diverge from what's
	/// actually in the instrument's samples array.
	var sampleObject: PPSampleObject? {
		didSet {
			invalidateSize()
			needsDisplay = true
		}
	}

	/// Falls back to the responder chain if not set explicitly -- matches
	/// PatternGridView.editUndoManager, though SampleEditorWindowController
	/// sets this directly the same way ClassicalViewController/BoxViewController
	/// do for their grid views, rather than relying on the fallback.
	var editUndoManager: UndoManager?

	private var effectiveUndoManager: UndoManager? {
		return editUndoManager ?? undoManager
	}

	/// Horizontal zoom: pixels of view width per byte of sample data. See
	/// invalidateSize()/zoomToFit() (added with the zoom UI).
	private(set) var pixelsPerByte: CGFloat = 1.0

	private let waveformColorChannel0 = NSColor.systemRed
	private let waveformColorChannel1 = NSColor.systemBlue.withAlphaComponent(0.75)

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	// Every other grid view in this port draws top-down; match that rather
	// than AppKit's default bottom-up view coordinates.
	override var isFlipped: Bool { true }

	override var acceptsFirstResponder: Bool { true }

	// MARK: Sizing

	/// Resizes the view so its width represents the whole sample at the
	/// current zoom level -- frame.width doubles as `larg` (the "virtual
	/// full-sample pixel width") in drawSample's domain math at draw time,
	/// so zooming is just "resize the view, let NSScrollView reveal a
	/// window into it." Full zoom in/out/fit controls land with the zoom UI;
	/// for now this keeps the view sized to something sane whenever the
	/// sample changes.
	func invalidateSize() {
		guard let superview = superview else { return }
		let byteCount = CGFloat(sampleObject?.data.count ?? 0)
		let width = max(byteCount * pixelsPerByte, superview.bounds.width)
		let height = superview.bounds.height
		if frame.size != NSSize(width: width, height: height) {
			setFrameSize(NSSize(width: width, height: height))
		}
	}

	// MARK: Drawing

	override func draw(_ dirtyRect: NSRect) {
		NSColor.textBackgroundColor.setFill()
		dirtyRect.fill()

		guard let samp = sampleObject, samp.data.count > 0,
			  let ctx = NSGraphicsContext.current?.cgContext, frame.width > 0 else {
			return
		}

		// dirtyRect is already in this view's own coordinate space, which
		// (after invalidateSize()) IS the virtual `larg`-wide space drawSample
		// expects -- no separate zoom-window bookkeeping needed, AppKit's own
		// dirty-rect clipping is the zoom/scroll window.
		let tSS = max(Int(dirtyRect.minX), 0)
		let tSE = min(Int(dirtyRect.maxX) + 1, Int(frame.width))
		guard tSS < tSE else { return }

		let larg = Int(frame.width)
		let high = Int(bounds.height / 2)
		let midY = Int(bounds.midY)

		if samp.isStereo {
			ctx.setStrokeColor(waveformColorChannel1.cgColor)
			PPSampleObject.drawSample(start: 0, tSS: tSS, tSE: tSE, high: high, larg: larg,
									   trueV: midY, trueH: 0, channel: 1, currentData: samp, context: ctx)
		}

		ctx.setStrokeColor(waveformColorChannel0.cgColor)
		PPSampleObject.drawSample(start: 0, tSS: tSS, tSE: tSE, high: high, larg: larg,
								   trueV: midY, trueH: 0, channel: 0, currentData: samp, context: ctx)
	}
}
