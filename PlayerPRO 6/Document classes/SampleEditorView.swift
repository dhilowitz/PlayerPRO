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

	/// Set by SampleEditorWindowController to its own commitEdit(_:_:) --
	/// the view never mutates the music struct/instrument array directly,
	/// it only ever asks for a named mutation to be committed. Mutation
	/// closures act on the freshly-resolved canonical PPSampleObject
	/// commitEdit re-fetches internally, not on any object this view holds.
	/// Used for both data edits (Delete/Paste) and loop edits -- the commit
	/// side is identical either way, only the undo payload differs (see
	/// performDataEdit vs performLoopEdit).
	var commitMutation: ((_ name: String, _ mutate: @escaping (PPSampleObject) -> Void) -> Void)?

	/// Horizontal zoom: pixels of view width per byte of sample data. See
	/// invalidateSize()/zoomToFit() (added with the zoom UI).
	private(set) var pixelsPerByte: CGFloat = 1.0

	private let waveformColorChannel0 = NSColor.systemRed
	private let waveformColorChannel1 = NSColor.systemBlue.withAlphaComponent(0.75)
	private let selectionColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.4)
	private let loopColor = NSColor(calibratedRed: 0.2, green: 0.1, blue: 0.5, alpha: 0.8)

	// MARK: Loop markers
	//
	// This format's sData struct has one loop (loopBeg/loopSize/loopType),
	// not a separate sustain loop -- there's nothing else in PPSampleObject's
	// API to add a marker for.

	private enum LoopMarker { case begin, end }
	private var draggingMarker: LoopMarker?
	private var dragOriginalLoopBegin: Int32 = 0
	private var dragOriginalLoopSize: Int32 = 0
	private static let markerHitTolerance: CGFloat = 4

	// MARK: Selection
	//
	// Byte offsets into sampleObject.data -- the same domain
	// FilterPlugHandler.beginWithPlugAtIndex(...selectionRange:...) already
	// expects, so selection can be handed straight to a Filters Plug with no
	// translation layer once that lands.

	private(set) var selection = NSRange(location: 0, length: 0) {
		didSet { needsDisplay = true }
	}
	private var dragAnchorByte = 0

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

	private static let minPixelsPerByte: CGFloat = 1.0 / 256
	private static let maxPixelsPerByte: CGFloat = 64

	@objc func zoomIn() {
		pixelsPerByte = min(pixelsPerByte * 2, Self.maxPixelsPerByte)
		invalidateSize()
	}

	@objc func zoomOut() {
		pixelsPerByte = max(pixelsPerByte / 2, Self.minPixelsPerByte)
		invalidateSize()
	}

	/// Sets pixelsPerByte so the whole sample exactly fills the current
	/// scroll-view viewport -- frame.width doubling as `larg` (Phase 2)
	/// means this is just "pick the scale where byteCount * pixelsPerByte
	/// equals the visible width."
	@objc func zoomToFit() {
		guard let byteCount = sampleObject?.data.count, byteCount > 0,
			  let visibleWidth = enclosingScrollView?.contentView.bounds.width, visibleWidth > 0 else {
			return
		}
		pixelsPerByte = visibleWidth / CGFloat(byteCount)
		invalidateSize()
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

		if selection.length > 0 {
			let x0 = viewX(forByteOffset: selection.location)
			let x1 = viewX(forByteOffset: selection.location + selection.length)
			selectionColor.setFill()
			NSRect(x: x0, y: bounds.minY, width: x1 - x0, height: bounds.height).fill()
		}

		if samp.loopSize != 0 {
			loopColor.setStroke()
			let path = NSBezierPath()
			path.lineWidth = 2
			for byteOffset in [Int(samp.loopBegin), Int(samp.loopBegin) + Int(samp.loopSize)] {
				let x = viewX(forByteOffset: byteOffset)
				path.move(to: NSPoint(x: x, y: bounds.minY))
				path.line(to: NSPoint(x: x, y: bounds.maxY))
			}
			path.stroke()
		}
	}

	// MARK: Byte-offset math (inverse of drawSample's domain math)

	/// Bytes per sample-frame -- every byte offset this view produces
	/// (selection edges, a future paste/loop-marker position) must be a
	/// multiple of this or 16-bit/stereo data corrupts on the next read.
	/// Exactly what e.g. PPNormalizePlug already silently assumes about the
	/// selection range it's handed.
	private var frameSize: Int {
		let bytesPerSample = (sampleObject?.amplitude == 16) ? 2 : 1
		return bytesPerSample * (sampleObject?.isStereo == true ? 2 : 1)
	}

	private func snapToFrame(_ byteOffset: Int) -> Int {
		let fs = frameSize
		guard fs > 0 else { return byteOffset }
		return (byteOffset / fs) * fs
	}

	private func byteOffset(forViewX x: CGFloat) -> Int {
		guard let samp = sampleObject, frame.width > 0, samp.data.count > 0 else { return 0 }
		let units = samp.amplitude == 16 ? samp.data.count / 2 : samp.data.count
		let unitIndex = Int((x * CGFloat(units)) / frame.width)
		let byteOffset = samp.amplitude == 16 ? unitIndex * 2 : unitIndex
		return snapToFrame(min(max(byteOffset, 0), samp.data.count))
	}

	/// Inverse of byteOffset(forViewX:), for drawing the selection overlay.
	private func viewX(forByteOffset byteOffset: Int) -> CGFloat {
		guard let samp = sampleObject, samp.data.count > 0 else { return 0 }
		return (CGFloat(byteOffset) / CGFloat(samp.data.count)) * frame.width
	}

	// MARK: Mouse

	private func hitTestLoopMarker(at p: NSPoint) -> LoopMarker? {
		guard let samp = sampleObject, samp.loopSize != 0 else { return nil }
		let beginX = viewX(forByteOffset: Int(samp.loopBegin))
		let endX = viewX(forByteOffset: Int(samp.loopBegin) + Int(samp.loopSize))
		if abs(p.x - beginX) <= Self.markerHitTolerance { return .begin }
		if abs(p.x - endX) <= Self.markerHitTolerance { return .end }
		return nil
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let p = convert(event.locationInWindow, from: nil)

		if let marker = hitTestLoopMarker(at: p), let samp = sampleObject {
			draggingMarker = marker
			dragOriginalLoopBegin = samp.loopBegin
			dragOriginalLoopSize = samp.loopSize
			return
		}

		dragAnchorByte = byteOffset(forViewX: p.x)
		selection = NSRange(location: dragAnchorByte, length: 0)
	}

	override func mouseDragged(with event: NSEvent) {
		let p = convert(event.locationInWindow, from: nil)

		if let marker = draggingMarker, let samp = sampleObject {
			let here = byteOffset(forViewX: p.x)
			// Live visual feedback only -- mutates the view's own held
			// PPSampleObject directly (safe: its setters write into its own
			// private buffer, per PPSampleObject.m), no undo/commit per
			// mouse-move event. mouseUp commits once, matching this
			// codebase's existing instinct of never spamming undo per pixel.
			switch marker {
			case .begin:
				let end = Int(samp.loopBegin) + Int(samp.loopSize)
				let newBegin = min(here, end - frameSize)
				samp.loopBegin = Int32(max(newBegin, 0))
				samp.loopSize = Int32(end - Int(samp.loopBegin))
			case .end:
				let newEnd = max(here, Int(samp.loopBegin) + frameSize)
				samp.loopSize = Int32(newEnd - Int(samp.loopBegin))
			}
			needsDisplay = true
			return
		}

		let here = byteOffset(forViewX: p.x)
		selection = here >= dragAnchorByte
			? NSRange(location: dragAnchorByte, length: here - dragAnchorByte)
			: NSRange(location: here, length: dragAnchorByte - here)
	}

	override func mouseUp(with event: NSEvent) {
		guard draggingMarker != nil, let samp = sampleObject else { return }
		draggingMarker = nil
		let newBegin = samp.loopBegin, newSize = samp.loopSize
		guard newBegin != dragOriginalLoopBegin || newSize != dragOriginalLoopSize else { return }
		// The live-feedback drag above already mutated the object directly;
		// re-apply the same final values through performLoopEdit so the
		// commit/undo/write-through path runs exactly once, on release.
		performLoopEdit(oldBegin: dragOriginalLoopBegin, oldSize: dragOriginalLoopSize,
						 newBegin: newBegin, newSize: newSize)
	}

	// MARK: Delete

	override func keyDown(with event: NSEvent) {
		// Delete = 0x33 (Backspace), forwardDelete = 0x75.
		if event.keyCode == 0x33 || event.keyCode == 0x75 {
			deleteSelection()
			return
		}
		super.keyDown(with: event)
	}

	@objc func delete(_ sender: Any?) {
		deleteSelection()
	}

	private func deleteSelection() {
		guard let samp = sampleObject, selection.length > 0, let range = Range(selection) else { return }
		var newData: Data = samp.data ?? Data()
		newData.removeSubrange(range)
		performDataEdit(NSLocalizedString("Delete", comment: "sample editor undo action name"), newData: newData)
		selection = NSRange(location: min(selection.location, newData.count), length: 0)
	}

	/// Snapshot-and-restore, mirroring PatternGridView.withUndo/restorePattern:
	/// the restore closure re-registers itself with the pre-edit data as its
	/// own "new" value, so undo and redo compose through the same method.
	private func performDataEdit(_ name: String, newData: Data) {
		guard let samp = sampleObject else { return }
		// samp.data is a null_resettable NSData property, imported as an
		// implicitly-unwrapped optional -- give it an explicit non-optional
		// type up front rather than let a later composition (e.g. an
		// interpolation or ternary) silently re-widen it back to Optional,
		// the same trap already found and fixed once in
		// PatternListWindowController for patternName.
		let oldData: Data = samp.data ?? Data()
		commitMutation?(name) { $0.data = newData }
		effectiveUndoManager?.registerUndo(withTarget: self) { target in
			target.performDataEdit(name, newData: oldData)
		}
		effectiveUndoManager?.setActionName(name)
	}

	/// Same self-composing register-undo-inside-the-restore shape as
	/// performDataEdit, but the payload is two Int32s instead of a full
	/// buffer snapshot -- a loop move never touches .data, so there's
	/// nothing expensive to snapshot. Still funnels through the same
	/// commitMutation choke point as a data edit, since both mutate fields
	/// PPInstrumentObject.m's write-through fix covers.
	private func performLoopEdit(oldBegin: Int32, oldSize: Int32, newBegin: Int32, newSize: Int32) {
		let name = NSLocalizedString("Move Loop Point", comment: "sample editor undo action name")
		commitMutation?(name) { $0.loopBegin = newBegin; $0.loopSize = newSize }
		effectiveUndoManager?.registerUndo(withTarget: self) { target in
			target.performLoopEdit(oldBegin: newBegin, oldSize: newSize, newBegin: oldBegin, newSize: oldSize)
		}
		effectiveUndoManager?.setActionName(name)
	}

	// MARK: Clipboard
	//
	// A new lightweight type carrying raw bytes plus format metadata --
	// deliberately NOT the existing whole-sample net.sourceforge.playerpro.sData
	// UTI (PPSampleObject's own NSSecureCoding/pasteboard conformance),
	// which archives an entire sample object (name, loop points, slot
	// indices) via NSKeyedArchiver. A selection is a sub-range of bytes, not
	// a sample -- modeled on PatternGridView's own clipboard (its `Block`/
	// encode(_:)/decode(_:)), which solves the identical "copy a sub-range
	// with format metadata" problem for pattern cells.

	@objc static let pasteboardType = NSPasteboard.PasteboardType("com.quadmation.playerpro.sampledata")

	private struct Fragment {
		var amplitude: MADByte
		var stereo: Bool
		var bytes: Data
	}

	private func encode(_ fragment: Fragment) -> Data {
		var out = Data()
		var amp = Int32(fragment.amplitude)
		var stereoFlag = Int32(fragment.stereo ? 1 : 0)
		withUnsafeBytes(of: &amp) { out.append(contentsOf: $0) }
		withUnsafeBytes(of: &stereoFlag) { out.append(contentsOf: $0) }
		out.append(fragment.bytes)
		return out
	}

	private func decode(_ data: Data) -> Fragment? {
		let headerSize = MemoryLayout<Int32>.size * 2
		guard data.count >= headerSize else { return nil }
		let amp = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self) }
		let stereoFlag = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self) }
		let bytes = data.subdata(in: data.index(data.startIndex, offsetBy: headerSize)..<data.endIndex)
		return Fragment(amplitude: MADByte(amp), stereo: stereoFlag != 0, bytes: bytes)
	}

	@objc func copy(_ sender: Any?) {
		guard let samp = sampleObject, selection.length > 0,
			  let data: Data = samp.data, let range = Range(selection) else { return }
		let fragment = Fragment(amplitude: samp.amplitude, stereo: samp.isStereo, bytes: data.subdata(in: range))
		let pb = NSPasteboard.general
		pb.clearContents()
		pb.setData(encode(fragment), forType: Self.pasteboardType)
	}

	@objc func cut(_ sender: Any?) {
		copy(sender)
		deleteSelection()
	}

	@objc func paste(_ sender: Any?) {
		guard let samp = sampleObject,
			  let pbData = NSPasteboard.general.data(forType: Self.pasteboardType),
			  let fragment = decode(pbData) else { return }

		// Refuse a format mismatch rather than attempt an implicit bit-depth/
		// channel-count conversion -- that's real DSP, out of scope for this
		// pass alongside the deferred FFT work. Same-format paste (by far
		// the common case) works immediately.
		guard fragment.amplitude == samp.amplitude, fragment.stereo == samp.isStereo else {
			NSSound.beep()
			return
		}

		var newData: Data = samp.data ?? Data()
		if selection.length > 0, let range = Range(selection) {
			newData.replaceSubrange(range, with: fragment.bytes)
		} else {
			let insertAt = newData.index(newData.startIndex, offsetBy: min(selection.location, newData.count))
			newData.insert(contentsOf: fragment.bytes, at: insertAt)
		}
		performDataEdit(NSLocalizedString("Paste", comment: "sample editor undo action name"), newData: newData)
		selection = NSRange(location: selection.location + fragment.bytes.count, length: 0)
	}
}
