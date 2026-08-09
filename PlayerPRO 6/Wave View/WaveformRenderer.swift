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

	private let music: PPMusicObject
	private let library: PPLibrary
	/// Kept only to read back the live outPutRate a caller may have changed
	/// via renderPeaks (see below) -- each render pass now builds its own
	/// fresh driver rather than reusing one across channels, so this is no
	/// longer "the" driver, just the last rate requested.
	private var outPutRate: UInt32
	let totalChannels: Int

	init?(music: PPMusicObject, library: PPLibrary) {
		let channels = music.totalTracks
		guard channels > 0 else { return nil }

		self.music = music
		self.library = library
		self.outPutRate = MADDriverSettings.new().outPutRate
		self.totalChannels = channels
	}

	/// Builds a fresh driver with this renderer's fixed settings (8-bit,
	/// DeluxeStereoOutPut -- see the class-level doc comment for why) plus
	/// whatever outPutRate is currently in effect. A fresh driver per call
	/// is deliberate, not incidental: BytesToRemoveAtEnd (MainDriver.c),
	/// which -[PPDriver directSave] trusts to size its returned NSData, is
	/// only ever reset inside NoteAnalyse at a pattern/order-list end, and
	/// otherwise carries over from whatever the last render happened to
	/// leave it at. Reusing one driver across renderPeaks' per-channel loop
	/// meant that once any channel's render hit a pattern end, the next
	/// channel's very first directSave() call allocated an undersized
	/// buffer against that stale leftover value while the mixer wrote its
	/// full untrimmed size into it -- a real heap overflow, confirmed as
	/// the cause of a crash reported switching to this tab. A brand new
	/// PPDriver starts that field at 0, so this can't happen regardless of
	/// how the previous render ended.
	private func makeDriver() -> PPDriver? {
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
		settings.numChn = Int16(totalChannels)
		settings.outPutRate = outPutRate

		guard let driver = try? PPDriver(library: library, settings: &settings) else { return nil }
		driver.currentMusic = music
		return driver
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

		outPutRate = sampleRate

		var result = [[Peak]](repeating: [], count: totalChannels)

		for channel in 0..<totalChannels {
			// A fresh driver per channel -- see makeDriver()'s doc comment
			// for why this isn't just "simpler," it's the actual fix for a
			// real heap-overflow crash. Muting/stop/seek/play state below is
			// therefore all local to this one channel's driver, not shared
			// across iterations the way it was before.
			guard let driver = makeDriver() else { continue }

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
