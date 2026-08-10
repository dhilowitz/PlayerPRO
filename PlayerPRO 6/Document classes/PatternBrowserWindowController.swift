//
//  PatternBrowserWindowController.swift
//  PlayerPRO 6
//
//  A flat browser of every pattern that exists in the song (the original's
//  "Patterns List" window, Files/Pattern.c's PatListDlog) -- distinct from
//  PartitionListWindowController, which shows the ORDER the patterns play
//  in, not what patterns exist. A position in the order list can repeat a
//  pattern or skip one entirely; nothing here is affected by that. Built
//  entirely in code, no nib, following the same shape as every other
//  window added this project.
//
//  Confirmed live on the original PlayerPRO (Dave's iMac): its toolbar has
//  six real actions -- New, Load (from file), Save (to file), Delete,
//  Info (a dialog for the pattern's own metadata), and Display (opens the
//  selected pattern in the pattern editor). Load/Save are omitted here:
//  they read/write the original's raw single-pattern file format (a
//  'SNPL'/'PATN'-typed dump of the in-memory PatData struct, SaveAPatternInt
//  in Pattern.c) which nothing in this codebase implements or parses --
//  same reasoning as the Mixer's omitted FX slots. New/Delete/Info/Display
//  are all real and fully wired.
//

import Cocoa
import PlayerPROKit

class PatternBrowserWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

	weak var currentDocument: PPDocument?

	private var tableView: NSTableView!
	private var newButton: NSButton!
	private var deleteButton: NSButton!
	private var infoButton: NSButton!
	private var displayButton: NSButton!

	private static let idColumnID = NSUserInterfaceItemIdentifier("id")
	private static let sizeColumnID = NSUserInterfaceItemIdentifier("size")
	private static let nameColumnID = NSUserInterfaceItemIdentifier("name")

	// See PartitionListWindowController's identical override for why this
	// is needed: addWindowController puts this under the document's
	// automatic title sync, which would otherwise overwrite the title set
	// below with just the document's own display name.
	override func windowTitle(forDocumentDisplayName displayName: String) -> String {
		return String(format: NSLocalizedString("Patterns List (%@)", comment: "pattern browser window title, %@ is the document name"), displayName)
	}

	convenience init() {
		let contentRect = NSRect(x: 0, y: 0, width: 360, height: 420)
		let window = NSWindow(contentRect: contentRect,
							   styleMask: [.titled, .closable, .miniaturizable, .resizable],
							   backing: .buffered, defer: false)
		window.title = NSLocalizedString("Patterns List", comment: "pattern browser window title")
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

		let idColumn = NSTableColumn(identifier: PatternBrowserWindowController.idColumnID)
		idColumn.title = NSLocalizedString("ID", comment: "pattern browser ID column")
		idColumn.width = 40
		idColumn.minWidth = 30
		table.addTableColumn(idColumn)

		let sizeColumn = NSTableColumn(identifier: PatternBrowserWindowController.sizeColumnID)
		sizeColumn.title = NSLocalizedString("Size", comment: "pattern browser size column")
		sizeColumn.width = 80
		sizeColumn.minWidth = 60
		table.addTableColumn(sizeColumn)

		let nameColumn = NSTableColumn(identifier: PatternBrowserWindowController.nameColumnID)
		nameColumn.title = NSLocalizedString("Name", comment: "pattern browser name column")
		nameColumn.width = 200
		nameColumn.minWidth = 80
		table.addTableColumn(nameColumn)

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

		// Same sizing reasoning as PartitionListWindowController's +/-
		// buttons: .rounded needs more than ~28pt to center a single glyph
		// without clipping it.
		let buttonSize: CGFloat = 34

		let new = NSButton(title: "+", target: self, action: #selector(newPattern))
		new.bezelStyle = .rounded
		new.frame = NSRect(x: x, y: 4, width: buttonSize, height: 22)
		strip.addSubview(new)
		newButton = new
		x += buttonSize + 2

		let delete = NSButton(title: "\u{2212}", target: self, action: #selector(deletePattern))
		delete.bezelStyle = .rounded
		delete.frame = NSRect(x: x, y: 4, width: buttonSize, height: 22)
		strip.addSubview(delete)
		deleteButton = delete
		x += buttonSize + 10

		let info = NSButton(title: NSLocalizedString("Info…", comment: "pattern browser info button"), target: self, action: #selector(showInfo))
		info.bezelStyle = .rounded
		info.frame = NSRect(x: x, y: 4, width: 64, height: 22)
		strip.addSubview(info)
		infoButton = info
		x += 68

		let display = NSButton(title: NSLocalizedString("Display", comment: "pattern browser display button"), target: self, action: #selector(displayPattern))
		display.bezelStyle = .rounded
		display.frame = NSRect(x: x, y: 4, width: 74, height: 22)
		strip.addSubview(display)
		displayButton = display

		content.addSubview(strip)
	}

	// MARK: Reload

	func reload() {
		tableView.reloadData()
	}

	// MARK: NSTableViewDataSource

	func numberOfRows(in tableView: NSTableView) -> Int {
		return currentDocument?.theMusic?.patterns.count ?? 0
	}

	// MARK: NSTableViewDelegate

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let identifier = tableColumn?.identifier,
			  let music = currentDocument?.theMusic,
			  row < music.patterns.count,
			  let pattern = music.patterns[row] as? PPPatternObject else { return nil }

		if identifier == PatternBrowserWindowController.idColumnID {
			return NSTextField(labelWithString: "\(pattern.index)")
		}

		if identifier == PatternBrowserWindowController.sizeColumnID {
			return NSTextField(labelWithString: "\(pattern.patternSize)x\(music.totalTracks)")
		}

		if identifier == PatternBrowserWindowController.nameColumnID {
			// Read-only, matching the original: renaming happens through
			// the Info dialog, not inline in this list (Classic's list
			// widget this was built on, LDEF-based, didn't support inline
			// text editing the way NSTableView does).
			let rawName: String = pattern.patternName ?? ""
			let name = rawName.isEmpty ? NSLocalizedString("Untitled", comment: "unnamed pattern") : rawName
			return NSTextField(labelWithString: name)
		}

		return nil
	}

	// MARK: Actions

	@objc private func newPattern() {
		currentDocument?.createNewPattern()
	}

	@objc private func deletePattern() {
		guard let doc = currentDocument, let music = doc.theMusic else { return }
		let row = tableView.selectedRow
		guard row >= 0, row < music.patterns.count else { return }

		// Matches the original's confirm-before-delete (InfoL(50) in
		// DeleteAPattern) -- this is the only destructive action in this
		// window and it can't be undone.
		let alert = NSAlert()
		alert.messageText = NSLocalizedString("Delete this pattern?", comment: "delete pattern confirm title")
		alert.informativeText = NSLocalizedString("This can't be undone.", comment: "delete pattern confirm body")
		alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete pattern confirm button"))
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "delete pattern cancel button"))
		alert.buttons.first?.hasDestructiveAction = true
		guard alert.runModal() == .alertFirstButtonReturn else { return }

		doc.deletePattern(at: row)
	}

	@objc private func showInfo() {
		guard let music = currentDocument?.theMusic else { return }
		let row = tableView.selectedRow
		guard row >= 0, row < music.patterns.count, let pattern = music.patterns[row] as? PPPatternObject else { return }

		let alert = NSAlert()
		alert.messageText = NSLocalizedString("Pattern Info", comment: "pattern info dialog title")
		alert.addButton(withTitle: NSLocalizedString("OK", comment: "pattern info OK button"))
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "pattern info cancel button"))

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
		field.stringValue = pattern.patternName ?? ""
		alert.accessoryView = field
		alert.window.initialFirstResponder = field

		guard alert.runModal() == .alertFirstButtonReturn else { return }
		pattern.patternName = field.stringValue
		currentDocument?.updateChangeCount(.changeDone)
		reload()
	}

	@objc private func displayPattern() {
		guard let doc = currentDocument, let music = doc.theMusic else { return }
		let row = tableView.selectedRow
		guard row >= 0, row < music.patterns.count else { return }

		doc.currentPatternID = row
		doc.mainViewController?.window?.makeKeyAndOrderFront(self)
	}
}
