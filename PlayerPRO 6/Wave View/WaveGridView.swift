//
//  WaveGridView.swift
//  PlayerPRO 6
//
//  The Wave tab: unlike Digital/Classic/Box, this is not a note-entry grid.
//  X axis is pattern position, Y axis is tracker channel, and each cell
//  shows the actual rendered audio for that slice as a min/max peak line --
//  a real oscillogram, not a symbolic view of the pattern data. See
//  WAVE-EDITOR-SPEC.md, derived from Files/wds_editors/WaveEditor.c.
//

import Cocoa
import PlayerPROKit

@objc public enum WaveGridMode: Int {
	case play = 0
	case zoom = 1
	case note = 2
}

@objc(PPWaveGridView)
open class WaveGridView: NSView {

	public override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	// MARK: Content

	@objc open var pattern: PPPatternObject? {
		didSet { invalidateSize(); peakCache = nil; needsDisplay = true }
	}

	@objc open var music: PPMusicObject? {
		didSet { rebuildRenderer() }
	}

	@objc open var trackCount: Int = 4 {
		didSet { invalidateSize(); peakCache = nil; needsDisplay = true }
	}

	/// The document's live playback driver -- used for mute/solo, the
	/// play-mode scrub, and coloring inactive channels gray. Never used for
	/// rendering; see WaveformRenderer for why that needs its own private
	/// offline driver instead.
	@objc open weak var driver: PPDriver? {
		didSet { needsDisplay = true }
	}

	private var renderer: WaveformRenderer?

	private func rebuildRenderer() {
		guard let music = music else { renderer = nil; return }
		renderer = WaveformRenderer(music: music, library: globalMadLib)
		peakCache = nil
		needsDisplay = true
	}

	private var patternLength: Int {
		return Int(pattern?.patternSize ?? 0)
	}

	// MARK: Mode
	//
	// Tab cycles play -> zoom -> note -> play, matching the original's
	// DoKeyPressWave. The hosting controller's three mode buttons set this
	// directly.

	@objc open var mode: WaveGridMode = .play {
		didSet { needsDisplay = true }
	}

	@objc open func cycleMode() {
		switch mode {
		case .play: mode = .zoom
		case .zoom: mode = .note
		case .note: mode = .play
		}
	}

	/// Fired on a note-mode click with (row, track), so the hosting
	/// controller can move the Digital editor's cursor there -- the modern
	/// equivalent of the original's ShowCurrentCmdNote/SetCommandTrack
	/// bridge into the Digital editor.
	@objc open var positionSelected: ((Int, Int) -> Void)?

	// MARK: Zoom
	//
	// XSize (column width) doubles/halves, 4...128, default 8. YSize (row
	// height) is one of five fixed stops, default 32 -- both exactly
	// matching the original's CreateWaveWindow defaults and DoItemPressWave/
	// the YSize popup's five choices.

	@objc open private(set) var xSize: CGFloat = 8
	@objc open private(set) var ySize: CGFloat = 32

	private static let xSizeMin: CGFloat = 4
	private static let xSizeMax: CGFloat = 128
	static let yStops: [CGFloat] = [16, 32, 64, 128, 256]

	@objc open func zoomIn() {
		guard xSize < WaveGridView.xSizeMax else { return }
		xSize *= 2
		invalidateSize(); peakCache = nil; needsDisplay = true
	}

	@objc open func zoomOut() {
		guard xSize > WaveGridView.xSizeMin else { return }
		xSize /= 2
		invalidateSize(); peakCache = nil; needsDisplay = true
	}

	@objc open func resetZoom() {
		guard xSize != 8 else { return }
		xSize = 8
		invalidateSize(); peakCache = nil; needsDisplay = true
	}

	@objc open func changeYSize(_ size: CGFloat) {
		guard WaveGridView.yStops.contains(size), size != ySize else { return }
		ySize = size
		invalidateSize(); peakCache = nil; needsDisplay = true
	}

	/// Coarser zoom renders at a lower sample rate, same tradeoff the
	/// original makes (rate2khz/rate5khz/rate11khz keyed off XSize) --
	/// wide-zoomed-out views would otherwise spend far more time decoding
	/// audio than the resulting single-pixel-wide peak could ever show.
	private var renderSampleRate: UInt32 {
		if xSize < 8 { return 2000 }
		if xSize < 32 { return 5000 }
		return 11025
	}

	// MARK: Geometry

	private let gutterWidth: CGFloat = 30
	private let headerHeight: CGFloat = 16

	open override var isFlipped: Bool { return true }

	private func invalidateSize() {
		let w = gutterWidth + CGFloat(patternLength) * xSize
		let h = headerHeight + CGFloat(trackCount) * ySize
		if frame.size != NSSize(width: w, height: h) {
			setFrameSize(NSSize(width: w, height: h))
		}
	}

	private func channelRect(_ channel: Int) -> NSRect {
		return NSRect(x: 0, y: headerHeight + CGFloat(channel) * ySize,
					  width: bounds.width, height: ySize)
	}

	private func columnX(_ column: Int) -> CGFloat {
		return gutterWidth + CGFloat(column) * xSize
	}

	/// Which (row, channel) cell a point in the wave area lands in, or nil
	/// when it's in the gutter/header.
	private func cell(at point: NSPoint) -> (row: Int, channel: Int)? {
		guard point.x >= gutterWidth, point.y >= headerHeight, xSize > 0, ySize > 0 else { return nil }
		let row = Int((point.x - gutterWidth) / xSize)
		let channel = Int((point.y - headerHeight) / ySize)
		guard row >= 0, row < max(patternLength, 1), channel >= 0, channel < trackCount else { return nil }
		return (row, channel)
	}

	/// Which channel a point in the left gutter is over, clamped in range --
	/// mirrors the original's DoItemPressWave gutter hit-test, which clamps
	/// rather than rejecting an out-of-range click.
	private func gutterChannel(at point: NSPoint) -> Int? {
		guard point.x < gutterWidth, point.y >= headerHeight else { return nil }
		let channel = Int((point.y - headerHeight) / ySize)
		return max(0, min(trackCount - 1, channel))
	}

	// MARK: Peak cache
	//
	// Recomputed only when the visible column range or zoom actually
	// changes, not on every redraw -- rendering is a real (if muted/offline)
	// audio decode pass per channel, not free. The original recomputes on
	// much the same triggers (ComputeWave is called from UpdateWaveWindow on
	// every exposed-area redraw, scroll and zoom step); this is not a
	// deliberate shortcut so much as the same tradeoff the original made,
	// translated to a modern cache instead of relying on QuickDraw's own
	// dirty-region tracking.

	private struct PeakCache {
		var fromRow: Int
		var toRow: Int
		var xSize: CGFloat
		var peaksByChannel: [[WaveformRenderer.Peak]]
	}

	private var peakCache: PeakCache?

	/// Range currently queued for a background-of-the-runloop render, if
	/// any -- guards against piling up redundant requests while scrolling/
	/// zooming quickly, and against a now-stale request overwriting a
	/// fresher cache once it finally completes.
	private var pendingRange: (fromRow: Int, toRow: Int, xSize: CGFloat)?

	/// Returns the cached peaks for this range if already computed;
	/// otherwise queues a render and returns nil for this pass (the
	/// caller draws blank until it completes and calls needsDisplay).
	///
	/// renderPeaks runs a real audio decode loop (stop/seek/play/
	/// directSave, per channel) -- calling it synchronously from here
	/// used to mean running it *inside* draw(_:), i.e. inside an active
	/// Core Animation rendering pass. That's the likely cause of a Metal/
	/// IOGPU crash seen after this tab started actually rendering (once an
	/// earlier, unrelated crash in the render pipeline was fixed):
	/// hammering CoreAudio's HAL from inside a live Metal commit is not a
	/// combination anything here was designed to survive. Deferred to the
	/// next run-loop turn instead -- still the main thread, not a
	/// background queue, since the underlying engine (PPDriver/
	/// MADDriverRec) has no documented thread-safety guarantee and this
	/// project has no way to verify one without live testing.
	private func peaks(forVisibleRange fromRow: Int, _ toRow: Int) -> [[WaveformRenderer.Peak]]? {
		if let cache = peakCache, cache.fromRow == fromRow, cache.toRow == toRow, cache.xSize == xSize {
			return cache.peaksByChannel
		}
		guard let renderer = renderer, toRow > fromRow else { return nil }

		if let pending = pendingRange, pending.fromRow == fromRow, pending.toRow == toRow, pending.xSize == xSize {
			return nil		// already queued for this exact range
		}

		let columns = toRow - fromRow
		let rate = renderSampleRate
		pendingRange = (fromRow, toRow, xSize)

		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			guard let pending = self.pendingRange,
				  pending.fromRow == fromRow, pending.toRow == toRow, pending.xSize == self.xSize else {
				return		// a newer request has since superseded this one
			}
			let peaksByChannel = renderer.renderPeaks(fromRow: fromRow, toRow: toRow, columns: columns, sampleRate: rate)
			self.pendingRange = nil
			self.peakCache = PeakCache(fromRow: fromRow, toRow: toRow, xSize: self.xSize, peaksByChannel: peaksByChannel)
			self.needsDisplay = true
		}
		return nil
	}

	// MARK: Drawing

	private static let mutedColor = NSColor(calibratedWhite: 0.6, alpha: 1)
	private static let waveColor = NSColor.black
	private static let gutterBack = NSColor(calibratedWhite: 0.93, alpha: 1)
	private static let gridLine = NSColor(calibratedWhite: 0.80, alpha: 1)
	private static let centerLine = NSColor(calibratedWhite: 0.85, alpha: 1)

	open override func draw(_ dirtyRect: NSRect) {
		NSColor.white.setFill()
		dirtyRect.fill()

		guard patternLength > 0, trackCount > 0 else {
			drawPlaceholder()
			return
		}

		let firstRow = max(0, Int((dirtyRect.minX - gutterWidth) / xSize))
		let lastRow = min(patternLength, Int((dirtyRect.maxX - gutterWidth) / xSize) + 1)

		drawGutter(dirtyRect)

		guard firstRow < lastRow else { return }

		let peaksByChannel = peaks(forVisibleRange: firstRow, lastRow)

		for channel in 0..<trackCount {
			let r = channelRect(channel)
			guard r.intersects(dirtyRect) else { continue }

			let active = driver?.isChannelActive(at: channel) ?? true
			(active ? WaveGridView.waveColor : WaveGridView.mutedColor).setStroke()

			WaveGridView.centerLine.setStroke()
			let midY = r.midY
			NSBezierPath.strokeLine(from: NSPoint(x: max(dirtyRect.minX, gutterWidth), y: midY),
									  to: NSPoint(x: dirtyRect.maxX, y: midY))

			(active ? WaveGridView.waveColor : WaveGridView.mutedColor).setStroke()

			guard let channelPeaks = peaksByChannel?[channel] else { continue }
			for row in firstRow..<min(lastRow, channelPeaks.count + firstRow) {
				let peak = channelPeaks[row - firstRow]
				let x = columnX(row) + xSize / 2
				let scale = (ySize / 2) / 128
				let yMin = midY - CGFloat(peak.max) * scale
				let yMax = midY - CGFloat(peak.min) * scale
				NSBezierPath.strokeLine(from: NSPoint(x: x, y: yMin), to: NSPoint(x: x, y: yMax))
			}
		}

		drawColumnSeparators(dirtyRect, firstRow: firstRow, lastRow: lastRow)
	}

	private func drawGutter(_ dirtyRect: NSRect) {
		guard dirtyRect.minX < gutterWidth else { return }
		WaveGridView.gutterBack.setFill()
		NSRect(x: 0, y: headerHeight, width: gutterWidth, height: bounds.height - headerHeight).fill()

		let attrs: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 9),
			.foregroundColor: NSColor.black
		]
		for channel in 0..<trackCount {
			let r = channelRect(channel)
			let active = driver?.isChannelActive(at: channel) ?? true
			let label = String(format: "%02d", channel + 1)
			var a = attrs
			a[.foregroundColor] = active ? NSColor.black : WaveGridView.mutedColor
			label.draw(at: NSPoint(x: 3, y: r.minY + 2), withAttributes: a)
		}
	}

	private func drawColumnSeparators(_ dirtyRect: NSRect, firstRow: Int, lastRow: Int) {
		WaveGridView.gridLine.setStroke()
		let step = max(1, Int(16 / max(xSize, 1)))		// thin out labels/rules at small zoom
		let path = NSBezierPath()
		path.lineWidth = 1
		var row = firstRow - (firstRow % step)
		while row <= lastRow {
			let x = columnX(row)
			path.move(to: NSPoint(x: x, y: headerHeight))
			path.line(to: NSPoint(x: x, y: bounds.height))
			row += step
		}
		path.stroke()
	}

	private func drawPlaceholder() {
		let text = "No pattern"
		let attrs: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 11),
			.foregroundColor: NSColor.secondaryLabelColor
		]
		let size = text.size(withAttributes: attrs)
		text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
	}

	// MARK: Input

	open override var acceptsFirstResponder: Bool { return true }

	private var scrubbing = false
	private var wasPlayingBeforeScrub = false

	open override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let p = convert(event.locationInWindow, from: nil)

		if let channel = gutterChannel(at: p) {
			handleGutterClick(channel: channel, modifiers: event.modifierFlags)
			return
		}

		guard let c = cell(at: p) else { return }

		switch mode {
		case .play:
			beginScrub(atRow: c.row)
		case .zoom:
			if event.clickCount >= 2 {
				resetZoom()
			} else if event.modifierFlags.contains(.option) {
				zoomOut()
			} else {
				zoomIn()
			}
		case .note:
			driver?.patternPosition = Int16(c.row)
			positionSelected?(c.row, c.channel)
		}
	}

	open override func mouseDragged(with event: NSEvent) {
		guard mode == .play, scrubbing else { return }
		let p = convert(event.locationInWindow, from: nil)
		let row = max(0, min(patternLength - 1, Int((p.x - gutterWidth) / xSize)))
		driver?.patternPosition = Int16(row)
	}

	open override func mouseUp(with event: NSEvent) {
		guard scrubbing else { return }
		scrubbing = false
		if !wasPlayingBeforeScrub {
			_ = try? driver?.pause()
		}
	}

	private func beginScrub(atRow row: Int) {
		guard let driver = driver else { return }
		wasPlayingBeforeScrub = driver.isPlayingMusic
		driver.patternPosition = Int16(row)
		if !wasPlayingBeforeScrub {
			_ = driver.play()
		}
		scrubbing = true
	}

	/// Cmd-click mutes/unmutes a channel; Option-click solos it (or, if it's
	/// already the only active channel, un-solos back to all-active) --
	/// exactly DoItemPressWave's gutter behavior, moved to setChannel(at:toActive:).
	private func handleGutterClick(channel: Int, modifiers: NSEvent.ModifierFlags) {
		guard let driver = driver else { return }

		if modifiers.contains(.command) {
			driver.setChannel(at: channel, toActive: !driver.isChannelActive(at: channel))
		} else if modifiers.contains(.option) {
			let activeCount = (0..<trackCount).filter { driver.isChannelActive(at: $0) }.count
			if activeCount <= 1 && driver.isChannelActive(at: channel) {
				for i in 0..<trackCount { driver.setChannel(at: i, toActive: true) }
			} else {
				for i in 0..<trackCount { driver.setChannel(at: i, toActive: i == channel) }
			}
		} else {
			return
		}
		needsDisplay = true
	}

	open override func keyDown(with event: NSEvent) {
		if event.keyCode == 48 {	// Tab
			cycleMode()
		} else {
			super.keyDown(with: event)
		}
	}
}
