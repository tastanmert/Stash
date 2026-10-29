import AppKit
import Carbon.HIToolbox
import QuickLookThumbnailing
import StashCore
import UniformTypeIdentifiers

/// The menu bar item and its menu.
final class StatusMenuController: NSObject, NSMenuDelegate {
    static let shared = StatusMenuController()
    private var item: NSStatusItem?

    func refresh() {
        if Prefs.bool(Pref.showInMenuBar) {
            if item == nil {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                let menu = NSMenu()
                menu.delegate = self
                item?.menu = menu
            }
            let icon: MenuBarIcon = Prefs.value(Pref.menuBarIcon, default: .pocket)
            item?.button?.image = icon.image
            item?.button?.toolTip = "Stash"
        } else if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let manager = ShelfManager.shared

        AppMaintenance.checkDiskSpace()
        if AppMaintenance.disk.isLow {
            let warning = NSMenuItem(title: L("Low disk space"), action: nil, keyEquivalent: "")
            warning.subtitle = L("Stash may quit unexpectedly when storage is critically low.")
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.systemYellow]))
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let newShelf = NSMenuItem(L("New Shelf")) { manager.newShelf().panel.makeKey() }
        if let combo = KeyboardAction.newShelf.activeCombo { newShelf.setShortcut(combo) }
        if newShelf.keyEquivalent == " " { newShelf.keyEquivalent = "␣" }
        menu.addItem(newShelf)
        let clipboard = NSMenuItem(L("New Shelf From Clipboard")) { manager.newShelfFromClipboard() }
        if let combo = KeyboardAction.newClipboardShelf.activeCombo { clipboard.setShortcut(combo) }
        menu.addItem(clipboard)
        if !manager.controllers.isEmpty {
            let closeAll = NSMenuItem(L("Close All Shelves")) { manager.closeAll() }
            if let combo = KeyboardAction.closeAll.activeCombo { closeAll.setShortcut(combo) }
            menu.addItem(closeAll)
        }

        if !manager.pinned.isEmpty {
            menu.addItem(.separator())
            menu.addHeader(L("Pinned Shelves"))
            for record in manager.pinned { addRecord(record, to: menu, pinned: true) }
        }

        if !manager.recent.isEmpty {
            menu.addItem(.separator())
            menu.addHeader(L("Recent Shelves"))
            for record in manager.recent.prefix(Self.inlineRecentCount) { addRecord(record, to: menu, pinned: false) }
            menu.addSubmenu(L("All Shelves")) { sub in
                for record in manager.recent { addRecord(record, to: sub, pinned: false) }
                sub.addItem(.separator())
                sub.add(L("Clear Recent Shelves")) { manager.clearRecent() }
                let hint = NSMenuItem(title: L("Hold ⌥ to remove single shelve"), action: nil, keyEquivalent: "")
                hint.isEnabled = false
                sub.addItem(hint)
            }
        }

        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        menu.addHeader(L("Version %@", version))
        menu.add(L("New in This Version...")) { WhatsNew.show() }
        menu.add(L("Quick Start Guide...")) { OnboardingWindowController.shared.show() }
        menu.add(L("About Stash...")) { AboutWindow.show() }
        menu.add(L("Settings..."), key: ",") { SettingsWindowController.shared.show() }
        menu.items.last?.allowsAutomaticKeyEquivalentLocalization = false
        menu.addItem(.separator())
        menu.add(L("Quit"), key: "q") { NSApp.terminate(nil) }
    }

    /// Recent shelves listed in the menu itself; All Shelves has the rest.
    private static let inlineRecentCount = 3

    private func addRecord(_ record: ShelfRecord, to menu: NSMenu, pinned: Bool) {
        let urls = record.paths.map { URL(filePath: $0) }
        let images = urls.allSatisfy { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        let title = record.name ?? record.title ?? (urls.count == 1 ? urls[0].lastPathComponent : L(images ? "%d Images" : "%d Files", urls.count))
        let open = NSMenuItem(title) { ShelfManager.shared.open(record) }
        open.subtitle = Self.dateText(record.closedAt)
        MenuThumbnails.shared.apply(to: open, for: urls)
        menu.addItem(open)
        let remove = NSMenuItem(pinned ? L("Unpin Shelf") : L("Remove From List")) {
            if pinned { ShelfManager.shared.unpin(record) } else { ShelfManager.shared.removeRecent(record) }
        }
        remove.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil)
        remove.isAlternate = true
        remove.keyEquivalentModifierMask = .option
        menu.addItem(remove)
    }

    /// "Today, 09:42", "Yesterday, 15:12", "26 Oct 2026, 11:05".
    static func dateText(_ date: Date) -> String {
        let day = DateFormatter()
        day.dateStyle = .medium
        day.timeStyle = .none
        day.doesRelativeDateFormatting = true
        let time = DateFormatter()
        time.dateStyle = .none
        time.timeStyle = .short
        return day.string(from: date) + ", " + time.string(from: date)
    }
}

/// Quick Look thumbnails for the shelves in the menu, made once and kept.
final class MenuThumbnails {
    static let shared = MenuThumbnails()
    private static let size = NSSize(width: 32, height: 32)
    private var cache: [String: NSImage] = [:]

    func apply(to item: NSMenuItem, for urls: [URL]) {
        // macOS 27 hides menu item images unless asked; the shelf pictures are the point of these rows.
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
        guard let first = urls.first else { return }
        // One file, or a shelf of images, shows the (first) picture; any other mix shows a folder.
        let allImages = urls.allSatisfy { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        guard urls.count == 1 || allImages else {
            item.image = Self.icon(nil)
            return
        }
        let key = first.path
        if let image = cache[key] { item.image = image; return }
        item.image = Self.icon(first)
        guard FileManager.default.fileExists(atPath: first.path) else { return }
        let request = QLThumbnailGenerator.Request(fileAt: first, size: Self.size, scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        Task { [weak item] in
            guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
            let image = Self.fit(NSImage(cgImage: rep.cgImage, size: .zero))
            cache[key] = image
            item?.image = image
        }
    }

    private static func icon(_ url: URL?) -> NSImage {
        let image = url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .folder)
        image.size = size
        return image
    }

    /// Scales the thumbnail into the 32 pt box, keeping its shape.
    private static func fit(_ image: NSImage) -> NSImage {
        let pixels = image.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? image.size
        let scale = min(size.width / max(pixels.width, 1), size.height / max(pixels.height, 1))
        image.size = NSSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
        return image
    }
}

extension NSMenuItem {
    /// Shows a shortcut next to the item (display only).
    func setShortcut(_ combo: KeyCombo) {
        let special: [Int: Int] = [
            kVK_Space: 0x20, kVK_Return: 0x0D, kVK_Tab: 0x09, kVK_Delete: 0x08, kVK_ForwardDelete: NSDeleteFunctionKey, kVK_Escape: 0x1B,
            kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey, kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
        ]
        if let scalar = special[Int(combo.keyCode)].flatMap(UnicodeScalar.init) {
            keyEquivalent = String(Character(scalar))
        } else {
            keyEquivalent = KeyCombo.keyName(combo.keyCode).lowercased()
        }
        keyEquivalentModifierMask = combo.modifiers
    }

    /// Shows the shortcut of `action` while it is turned on.
    func setShortcut(_ action: KeyboardAction) {
        if let combo = action.activeCombo { setShortcut(combo) } else { keyEquivalent = "" }
    }
}
