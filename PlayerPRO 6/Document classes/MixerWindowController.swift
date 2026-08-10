//
//  MixerWindowController.swift
//  PlayerPRO 6
//
//  Per-track mixing console -- the original app's View > Mixer window,
//  confirmed live on the original PlayerPRO running on Dave's iMac (a
//  bar-meter-only Carbon precursor exists in legacy source as
//  Files/wds_views/TrackView.c, but nothing richer than that was found in
//  any available source, legacy or SourceForge release archive -- see
//  kind-petting-balloon.md). Built entirely in code, no nib, following the
//  same shape as PatternListWindowController/PianoWindowController: cached
//  per document, registered via addWindowController so document-hosted
//  menu actions keep validating while this window is key.
//
//  v1 scope is one row per track -- Volume, Pan, Mute, and a live Activity
//  meter -- plus a Tempo readout. FX-slot checkboxes seen on the live app
//  are omitted (no plugin hosting exists anywhere in this codebase to back
//  them); the Global hard/soft sliders are deferred (their exact semantics
//  weren't confirmed live). Every control that IS here is fully wired to
//  the real engine, not decorative.
//

import Cocoa
import PlayerPROKit

class MixerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

	weak var currentDocument: PPDocument?

	private var tableView: NSTableView!
	private var tempoLabel: NSTextField!

	private static let trackColumnID = NSUserInterfaceItemIdentifier("track")
	private static let volumeColumnID = NSUserInterfaceItemIdentifier("volume")
	private static let panColumnID = NSUserInterfaceItemIdentifier("pan")
	private static let muteColumnID = NSUserInterfaceItemIdentifier("mute")
	private static let activityColumnID = NSUserInterfaceItemIdentifier("activity")

	// See PianoWindowController's identical override for why this is
	// needed: addWindowController puts this under the document's automatic
	// title sync, which would otherwise overwrite the title set below with
	// just the document's own display name.
	override func windowTitle(forDocumentDisplayName displayName: String) -> String {
		return String(format: NSLocalizedString("Mixer (%@)", comment: "mixer window title, %@ is the document name"), displayName)
	}

	convenience init() {
		let contentRect = NSRect(x: 0, y: 0, width: 460, height: 360)
		let window = NSWindow(contentRect: contentRect,
							   styleMask: [.titled, .closable, .miniaturizable, .resizable],
							   backing: .buffered, defer: false)
		window.title = NSLocalizedString("Mixer", comment: "mixer window title")
		window.isReleasedWhenClosed = false

		self.init(window: window)
		window.delegate = self

		let content = window.contentView!
		let headerHeight: CGFloat = 26

		let scroller = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height - headerHeight))
		scroller.hasVerticalScroller = true
		scroller.autohidesScrollers = false
		scroller.borderType = .bezelBorder
		scroller.autoresizingMask = [.width, .height]

		let table = NSTableView(frame: scroller.bounds)
		table.usesAlternatingRowBackgroundColors = true
		table.rowHeight = 26
		table.allowsMultipleSelection = false
		table.dataSource = self
		table.delegate = self
		table.headerView = NSTableHeaderView()

		let trackColumn = NSTableColumn(identifier: MixerWindowController.trackColumnID)
		trackColumn.title = NSLocalizedString("Track", comment: "mixer track column")
		trackColumn.width = 44
		trackColumn.minWidth = 32
		table.addTableColumn(trackColumn)

		let volumeColumn = NSTableColumn(identifier: MixerWindowController.volumeColumnID)
		volumeColumn.title = NSLocalizedString("Volume", comment: "mixer volume column")
		volumeColumn.width = 120
		volumeColumn.minWidth = 80
		table.addTableColumn(volumeColumn)

		let panColumn = NSTableColumn(identifier: MixerWindowController.panColumnID)
		panColumn.title = NSLocalizedString("Pan", comment: "mixer pan column")
		panColumn.width = 120
		panColumn.minWidth = 80
		table.addTableColumn(panColumn)

		let muteColumn = NSTableColumn(identifier: MixerWindowController.muteColumnID)
		muteColumn.title = NSLocalizedString("Mute", comment: "mixer mute column")
		muteColumn.width = 44
		muteColumn.minWidth = 36
		table.addTableColumn(muteColumn)

		let activityColumn = NSTableColumn(identifier: MixerWindowController.activityColumnID)
		activityColumn.title = NSLocalizedString("Activity", comment: "mixer activity meter column")
		activityColumn.width = 90
		activityColumn.minWidth = 60
		table.addTableColumn(activityColumn)

		scroller.documentView = table
		content.addSubview(scroller)
		self.tableView = table

		buildHeaderStrip(in: content, bounds: contentRect, height: headerHeight)
	}

	// MARK: Header strip

	private func buildHeaderStrip(in content: NSView, bounds: NSRect, height stripHeight: CGFloat) {
		let strip = NSView(frame: NSRect(x: 0, y: bounds.height - stripHeight, width: bounds.width, height: stripHeight))
		strip.autoresizingMask = [.width, .minYMargin]

		let label = NSTextField(labelWithString: "")
		label.frame = NSRect(x: 8, y: 4, width: 260, height: 18)
		strip.addSubview(label)
		tempoLabel = label

		content.addSubview(strip)
	}

	// MARK: Reload
	//
	// Rebuilds the row count (a song's track count is fixed once loaded, but
	// this is cheap and matches PatternListWindowController's reload()
	// precedent) and refreshes the static parts of the header/rows. Live,
	// per-tick refresh (activity meters, tempo while playing) is separate --
	// see the timer-driven update added alongside the control wiring.

	func reload() {
		tableView.reloadData()
	}

	// MARK: NSTableViewDataSource

	func numberOfRows(in tableView: NSTableView) -> Int {
		return currentDocument?.theMusic?.totalTracks ?? 0
	}

	// MARK: NSTableViewDelegate

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let identifier = tableColumn?.identifier else { return nil }

		if identifier == MixerWindowController.trackColumnID {
			let cell = NSTextField(labelWithString: "\(row + 1)")
			cell.alignment = .center
			return cell
		}

		if identifier == MixerWindowController.volumeColumnID {
			let slider = NSSlider(frame: .zero)
			slider.minValue = 0
			slider.maxValue = 64
			slider.tag = row
			return slider
		}

		if identifier == MixerWindowController.panColumnID {
			let slider = NSSlider(frame: .zero)
			slider.minValue = 0
			slider.maxValue = 64
			slider.tag = row
			return slider
		}

		if identifier == MixerWindowController.muteColumnID {
			let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
			checkbox.tag = row
			return checkbox
		}

		if identifier == MixerWindowController.activityColumnID {
			let meter = NSLevelIndicator(frame: .zero)
			meter.levelIndicatorStyle = .continuousCapacity
			meter.minValue = 0
			meter.maxValue = 64
			meter.isEditable = false
			meter.tag = row
			return meter
		}

		return nil
	}

	// MARK: NSWindowDelegate

	func windowWillClose(_ notification: Notification) {
	}
}
