//
//  PianoKeyMap.swift
//  PlayerPRO 6
//
//  Shared between the pattern grid's typed note entry and the on-screen
//  piano keyboard, since both are keying off the same physical layout.
//

import Foundation

enum PianoKeyMap {

	// The legacy editor reads its key map out of a user-editable 256-entry
	// PianoKey[] table in preferences, so the layout below is a default rather
	// than something fixed. It is the one PlayerPRO 5.9.8 ships with, read off
	// its piano window: a single chromatic run across the keyboard rows rather
	// than the two-octave split most trackers use.
	//
	// 9 0            -> G#2 A2
	// q w e r t y u i o p  -> A#2 .. G3
	// a s d f g h j k l    -> G#3 .. E4
	// z x c v b n m        -> F4  .. B4
	// Q W E R T            -> C5  .. E5

	/// Ordered low to high, matching the physical key rows left to right.
	static let orderedKeys: [Character] = ["9", "0",
											"q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
											"a", "s", "d", "f", "g", "h", "j", "k", "l",
											"z", "x", "c", "v", "b", "n", "m",
											"Q", "W", "E", "R", "T"]

	/// "9" is G#2: octave 2, semitone 8 -> note 32.
	static let baseNote = 32

	static let keyToNote: [Character: Int] = {
		var map = [Character: Int]()
		for (i, c) in orderedKeys.enumerated() {
			map[c] = baseNote + i
		}
		return map
	}()

	static let noteToKey: [Int: Character] = {
		var map = [Int: Character]()
		for (i, c) in orderedKeys.enumerated() {
			map[baseNote + i] = c
		}
		return map
	}()
}
