//
//  PartitionListWindowController.swift
//  PlayerPRO 6
//
//  The order list (the original's "Partition List" -- Files/Partition.c):
//  up to 256 positions, each holding a pattern ID, played in sequence.
//  Distinct from the patterns themselves (PPMusicObject.patterns) -- a
//  position can repeat a pattern or skip one entirely; nothing about the
//  order list changes what patterns exist, only what order (and how
//  often) they play in. Built entirely in code, no nib, for the same
//  reason every other window added this project is: nothing here has an
//  existing layout to adapt.
//
//  Clicking a row does two things at once, matching the original exactly
//  (DoItemPressParti's plain-click handling already did both together --
//  its separate "Open" button duplicated the same effect): it jumps the
//  live transport to that order-list position, and it becomes the pattern
//  every editor in this port displays (see PPDocument.currentPatternID).
//

import Cocoa
import PlayerPROKit

class PartitionListWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

	/// Practical order-list length limit -- matches the original's own
	/// self-imposed UI cap (LISTSIZE = 256 in Partition.c, and repeated
	/// `if (numPointers > 256) numPointers = 256` guards throughout it),
	/// even though the underlying storage (oPointers[MAXPOINTER == 999])
	/// is allocated larger.
	private static let listSize = 256

	weak var currentDocument: PPDocument?

	private var tableView: NSTableView!
	private var lengthField: NSTextField!
	private var addButton: NSButton!
	private var removeButton: NSButton!

	private static let positionColumnID = NSUserInterfaceItemIdentifier("position")
	private static let patternColumnID = NSUserInterfaceItemIdentifier("pattern")

	// See PianoWindowController's identical override for why this is
	// needed: addWindowController puts this under the document's automatic
	// title sync, which would otherwise overwrite the title set below with
	// just the document's own display name.
	override func windowTitle(forDocumentDisplayName displayName: String) -> String {
		return String(format: NSLocalizedString("Partition List (%@)", comment: "partition list window title, %@ is the document name"), displayName)
	}

	convenience init() {
		let contentRect = NSRect(x: 0, y: 0, width: 320, height: 420)
		let window = NSWindow(contentRect: contentRect,
							   styleMask: [.titled, .closable, .miniaturizable, .resizable],
							   backing: .buffered, defer: false)
		window.title = NSLocalizedString("Partition List", comment: "partition list window title")
		window.isReleasedWhenClosed = false

		self.init(window: window)

		let content = window.contentView!
		let stripHeight: CGFloat = 30

		let scroller = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height - stripHeight))
		scroller.hasVerticalScroller = true
		scroller.autohidesScrollers = false
		scroller.borderType = .bezelBorder
		scroller.autoresizingMask = [.width, .height]

		let table = NSTableView(frame: scroller.bounds)
		table.usesAlternatingRowBackgroundColors = true
		table.rowHeight = 20
		table.allowsMultipleSelection = false
		table.dataSource = self
		table.delegate = self
		table.headerView = NSTableHeaderView()

		let posColumn = NSTableColumn(identifier: PartitionListWindowController.positionColumnID)
		posColumn.title = NSLocalizedString("Pos", comment: "partition list position column")
		posColumn.width = 44
		posColumn.minWidth = 36
		table.addTableColumn(posColumn)

		let patternColumn = NSTableColumn(identifier: PartitionListWindowController.patternColumnID)
		patternColumn.title = NSLocalizedString("Pattern", comment: "partition list pattern column")
		patternColumn.width = 250
		patternColumn.minWidth = 100
		table.addTableColumn(patternColumn)

		scroller.documentView = table
		content.addSubview(scroller)
		self.tableView = table

		buildControlStrip(in: content, bounds: contentRect, height: stripHeight)
	}

	// MARK: Control strip

	private func buildControlStrip(in content: NSView, bounds: NSRect, height stripHeight: CGFloat) {
		let strip = NSView(frame: NSRect(x: 0, y: bounds.height - stripHeight, width: bounds.width, height: stripHeight))
		strip.autoresizingMask = [.width, .minYMargin]

		var x: CGFloat = 6

		// .rounded's fixed corner/padding needs more than ~28pt to center a
		// single glyph without clipping it -- 28pt rendered "+" only half
		// visible. 34pt (matching the button's own height) gives it room.
		let buttonSize: CGFloat = 34

		let add = NSButton(title: "+", target: self, action: #selector(addPosition))
		add.bezelStyle = .rounded
		add.frame = NSRect(x: x, y: 4, width: buttonSize, height: 22)
		strip.addSubview(add)
		addButton = add
		x += buttonSize + 2

		let remove = NSButton(title: "\u{2212}", target: self, action: #selector(removePosition))
		remove.bezelStyle = .rounded
		remove.frame = NSRect(x: x, y: 4, width: buttonSize, height: 22)
		strip.addSubview(remove)
		removeButton = remove
		x += buttonSize + 6

		let label = NSTextField(labelWithString: NSLocalizedString("Length:", comment: "order list length label"))
		label.frame = NSRect(x: x, y: 7, width: 46, height: 17)
		strip.addSubview(label)
		x += 50

		let field = NSTextField(frame: NSRect(x: x, y: 5, width: 44, height: 21))
		field.alignment = .right
		field.target = self
		field.action = #selector(lengthFieldChanged(_:))
		strip.addSubview(field)
		lengthField = field

		content.addSubview(strip)
	}

	// MARK: Reload

	func reload() {
		tableView.reloadData()
		if let music = currentDocument?.theMusic {
			lengthField.integerValue = music.orderListLength
		}
		selectRow(forCurrentPosition: true)
	}

	/// Reflects the live transport's current order-list position in the
	/// table selection, without re-triggering a jump (that would be
	/// circular -- this is called *from* the playback-position update
	/// path, not the other way around).
	func selectRow(forCurrentPosition: Bool) {
		guard forCurrentPosition, let driver = currentDocument?.theDriver else { return }
		let row = Int(driver.partitionPosition)
		guard row >= 0, row < PartitionListWindowController.listSize else { return }
		if tableView.selectedRow != row {
			tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			tableView.scrollRowToVisible(row)
		}
	}

	// MARK: NSTableViewDataSource

	func numberOfRows(in tableView: NSTableView) -> Int {
		return PartitionListWindowController.listSize
	}

	// MARK: NSTableViewDelegate

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let identifier = tableColumn?.identifier, let music = currentDocument?.theMusic else { return nil }

		// Rows at/after the active order-list length still hold whatever
		// pattern ID they last had (oPointers is a fixed 256-slot array,
		// not a dynamically-sized list), but aren't part of what actually
		// plays -- dimmed instead of the original's red length marker, a
		// clearer "inactive" signal in a modern list.
		let active = row < music.orderListLength

		if identifier == PartitionListWindowController.positionColumnID {
			let cell = NSTextField(labelWithString: "\(row + 1)")
			cell.textColor = active ? .labelColor : .tertiaryLabelColor
			return cell
		}

		if identifier == PartitionListWindowController.patternColumnID {
			let popup = NSPopUpButton(frame: .zero, pullsDown: false)
			popup.tag = row
			for pattern in music.patterns {
				guard let pattern = pattern as? PPPatternObject else { continue }
				// patternName is a null_resettable NSString property, imported
				// into Swift as an implicitly-unwrapped optional -- composing it
				// in a ternary with a plain String (NSLocalizedString's return
				// type) keeps it Optional<String> rather than auto-unwrapping,
				// so interpolating it directly printed "Optional("Untitled")"
				// instead of "Untitled". Give it an explicit String type up
				// front so there's no ambiguity left for the ternary to widen.
				let rawName: String = pattern.patternName ?? ""
				let name = rawName.isEmpty ? NSLocalizedString("Untitled", comment: "unnamed pattern") : rawName
				popup.addItem(withTitle: "\(pattern.index): \(name)")
			}
			let currentID = Int(music.patternID(atOrderListPosition: row))
			if currentID >= 0 && currentID < music.patterns.count {
				popup.selectItem(at: currentID)
			}
			popup.target = self
			popup.action = #selector(patternPopupChanged(_:))
			popup.isEnabled = active || row == 0
			return popup
		}

		return nil
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		jumpToSelectedPosition()
	}

	// MARK: Actions

	/// Matches the original's plain-click behavior in DoItemPressParti
	/// exactly: selecting a position both repositions the live transport
	/// (PL/Pat/PartitionReader) and becomes the pattern every editor
	/// displays -- there's no separate "view" vs "play from here" concept.
	private func jumpToSelectedPosition() {
		guard let doc = currentDocument, let music = doc.theMusic else { return }
		let row = tableView.selectedRow
		guard row >= 0 else { return }

		let patternID = Int(music.patternID(atOrderListPosition: row))
		guard patternID >= 0, patternID < music.patterns.count else { return }

		doc.theDriver.partitionPosition = Int16(row)
		doc.theDriver.patternIdentifier = Int16(patternID)
		doc.theDriver.patternPosition = 0
		doc.currentPatternID = patternID
	}

	@objc private func patternPopupChanged(_ sender: NSPopUpButton) {
		guard let music = currentDocument?.theMusic else { return }
		let row = sender.tag
		let newPatternID = sender.indexOfSelectedItem
		guard newPatternID >= 0 else { return }

		music.setPatternID(UInt8(newPatternID), atOrderListPosition: row)
		currentDocument?.updateChangeCount(.changeDone)

		if row == tableView.selectedRow {
			jumpToSelectedPosition()
		}
	}

	@objc private func lengthFieldChanged(_ sender: NSTextField) {
		guard let music = currentDocument?.theMusic else { return }
		music.orderListLength = sender.integerValue
		currentDocument?.updateChangeCount(.changeDone)
		reload()
	}

	/// Duplicates the selected position's pattern ID into a new slot
	/// immediately after it, shifting everything else down -- matches the
	/// original's Add button exactly (traced through its shift loop in
	/// DoItemPressParti: only entries after the insertion point actually
	/// move, so the selected entry and its new neighbor start out
	/// identical, ready to be reassigned via the pattern popup).
	@objc private func addPosition() {
		guard let music = currentDocument?.theMusic else { return }
		let insertAt = max(0, tableView.selectedRow) + 1
		guard insertAt < PartitionListWindowController.listSize else { return }

		var i = PartitionListWindowController.listSize - 1
		while i >= insertAt {
			music.setPatternID(music.patternID(atOrderListPosition: i - 1), atOrderListPosition: i)
			i -= 1
		}

		music.orderListLength = min(PartitionListWindowController.listSize, music.orderListLength + 1)
		currentDocument?.updateChangeCount(.changeDone)
		reload()
		tableView.selectRowIndexes(IndexSet(integer: insertAt), byExtendingSelection: false)
	}

	/// Removes the selected position, shifting everything after it up --
	/// matches the original's Remove button.
	@objc private func removePosition() {
		guard let music = currentDocument?.theMusic else { return }
		let removeAt = tableView.selectedRow
		guard removeAt >= 0 else { return }

		var i = removeAt
		while i < PartitionListWindowController.listSize - 1 {
			music.setPatternID(music.patternID(atOrderListPosition: i + 1), atOrderListPosition: i)
			i += 1
		}
		music.setPatternID(0, atOrderListPosition: PartitionListWindowController.listSize - 1)

		music.orderListLength = max(1, music.orderListLength - 1)
		currentDocument?.updateChangeCount(.changeDone)
		reload()
	}
}
