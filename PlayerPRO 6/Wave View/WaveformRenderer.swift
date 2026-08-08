//
//  WaveformRenderer.swift
//  PlayerPRO 6
//
//  Offline, headless renderer that produces per-channel peak (min/max)
//  waveform data for a range of pattern rows -- the audio-side counterpart
//  to WaveGridView's drawing. Owns a dedicated PPDriver, never the
//  document's live playback driver -- sharing it would mute, seek and
//  restart the user's actual playback as a side effect of just scrolling
//  this view. See WAVE-EDITOR-SPEC.md, "Why a private offline driver" and
//  "Why DeluxeStereoOutPut, not PolyPhonic".
//

import Foundation
import PlayerPROKit

final class WaveformRenderer {

	struct Peak {
		var min: Int8
		var max: Int8
	}

	private let driver: PPDriver
	let totalChannels: Int

	init?(music: PPMusicObject, library: PPLibrary) {
		let channels = music.totalTracks
		guard channels > 0 else { return nil }

		var settings = MADDriverSettings.new()
		settings.driverMode = .NoHardwareDriver
		settings.outPutBits = 8
		// PolyPhonic -- one physical channel per tracker channel, which is
		// what this feature actually wants -- crashes directSave() in this
		// engine (confirmed with a standalone reproduction harness; RDriver.h
		// itself warns "Do not use this!"). DeluxeStereoOutPut is the only
		// mode that header documents as supported, and the only one that
		// didn't crash, so per-channel isolation is done below by muting all
		// but one channel and rendering the otherwise-mixed stereo output.
		settings.outPutMode = .DeluxeStereoOutPut
		settings.numChn = Int16(channels)

		guard let driver = try? PPDriver(library: library, settings: &settings) else { return nil }
		driver.currentMusic = music
		self.driver = driver
		self.totalChannels = channels
	}

	/// Peak columns for every channel, covering pattern rows
	/// `fromRow..<toRow` of pattern 0 (the only pattern this port currently
	/// edits or displays anywhere -- see PatternGridView/ClassicalViewController;
	/// order-list navigation isn't wired up yet), bucketed into `columns`
	/// slices, rendered at `sampleRate` Hz (coarser rates render faster --
	/// what the original ties to zoom level; see the spec).
	func renderPeaks(fromRow: Int, toRow: Int, columns: Int, sampleRate: UInt32) -> [[Peak]] {
		guard columns > 0, toRow > fromRow else {
			return Array(repeating: [], count: totalChannels)
		}

		var settings = driver.driverSettings
		if settings.outPutRate != sampleRate {
			settings.outPutRate = sampleRate
			_ = try? driver.changeDriverSettings(to: &settings)
		}

		var result = [[Peak]](repeating: [], count: totalChannels)

		for channel in 0..<totalChannels {
			for other in 0..<totalChannels {
				driver.setChannel(at: other, toActive: other == channel)
			}

			// stop-then-seek-then-play, in that order, is the sequence
			// confirmed (in the reproduction harness) to actually reset the
			// engine's internal read position rather than continuing from
			// wherever the previous channel's render left off.
			_ = try? driver.stop()
			driver.patternPosition = Int16(fromRow)
			_ = driver.play()

			var data = Data()
			var safety = 0
			while safety < 200 {
				guard let chunk = driver.directSave(), !chunk.isEmpty else { break }
				data.append(chunk)
				safety += 1
				if driver.patternPosition >= Int16(toRow) { break }
			}

			result[channel] = WaveformRenderer.peaks(from: data, columns: columns)
		}

		// Leave this (private, offline-only) driver all-active so a later
		// render pass doesn't start out already muted from the last channel
		// rendered. Never touches the live driver's own mute state.
		for other in 0..<totalChannels {
			driver.setChannel(at: other, toActive: true)
		}

		return result
	}

	/// Bucket an interleaved 8-bit stereo buffer (2 bytes/frame, 128 =
	/// centre) into `columns` peak slices, taking whichever of L/R departs
	/// furthest from centre per frame -- panned content only occupies one
	/// side of a DeluxeStereoOutPut render (confirmed in the reproduction
	/// harness: an isolated channel's byte stream alternated real samples
	/// with exact-centre 128s), so this reads the signal regardless of pan.
	private static func peaks(from data: Data, columns: Int) -> [Peak] {
		let bytes = [UInt8](data)
		let frameCount = bytes.count / 2
		guard frameCount > 0 else {
			return Array(repeating: Peak(min: 0, max: 0), count: columns)
		}

		func centered(_ b: UInt8) -> Int8 {
			return Int8(truncatingIfNeeded: Int(b) - 128)
		}

		var out = [Peak]()
		out.reserveCapacity(columns)
		for col in 0..<columns {
			let start = (col * frameCount) / columns
			let end = max(start + 1, ((col + 1) * frameCount) / columns)
			var lo: Int8 = 127, hi: Int8 = -128
			for frame in start..<min(end, frameCount) {
				let l = centered(bytes[frame * 2])
				let r = centered(bytes[frame * 2 + 1])
				let v = abs(Int(l)) >= abs(Int(r)) ? l : r
				if v < lo { lo = v }
				if v > hi { hi = v }
			}
			out.append(Peak(min: lo, max: hi))
		}
		return out
	}
}
