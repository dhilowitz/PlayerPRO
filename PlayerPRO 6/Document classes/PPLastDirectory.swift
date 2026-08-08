//
//  PPLastDirectory.swift
//  PlayerPRO 6
//
//  Each save/open panel remembers its own last-used directory,
//  independent of the others -- Import and Export in the Instrument panel,
//  and the document Save panel, each get their own key so using Export
//  doesn't jump the next Import to wherever Export last landed.
//

import Foundation

enum PPLastDirectory {
	private static func key(_ purpose: String) -> String {
		return "PPLastDirectory." + purpose
	}

	/// The last directory used for `purpose`, or nil if there isn't one yet
	/// or it no longer exists on disk -- pointing a panel at a stale,
	/// deleted folder would be worse than just leaving it at its own
	/// default.
	static func url(for purpose: String) -> URL? {
		guard let path = UserDefaults.standard.string(forKey: key(purpose)) else { return nil }
		let url = URL(fileURLWithPath: path, isDirectory: true)
		guard (try? url.checkResourceIsReachable()) == true else { return nil }
		return url
	}

	/// Remembers the directory containing `fileURL` (or `fileURL` itself,
	/// if it's already a directory) as the last-used location for `purpose`.
	static func remember(_ fileURL: URL, for purpose: String) {
		let directory = fileURL.hasDirectoryPath ? fileURL : fileURL.deletingLastPathComponent()
		UserDefaults.standard.set(directory.path, forKey: key(purpose))
	}
}
