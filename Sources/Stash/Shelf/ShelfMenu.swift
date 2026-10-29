import AppKit
import SwiftUI

/// Runs a closure for a menu item; kept alive as the item's represented object.
private final class MenuHandler: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

extension NSMenuItem {
    /// A menu item that runs a closure.
    convenience init(_ title: String, symbol: String? = nil, key: String = "", modifiers: NSEvent.ModifierFlags = .command, handler: @escaping () -> Void) {
        let target = MenuHandler(handler)
        self.init(title: title, action: #selector(MenuHandler.run), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        self.target = target
        representedObject = target
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        showsImage()
    }

    /// macOS 27 hides menu item images unless asked; Stash's menus show an icon on every row.
    func showsImage() {
        if #available(macOS 27.0, *) { preferredImageVisibility = .visible }
    }
}

extension NSMenu {
    func add(_ title: String, symbol: String? = nil, key: String = "", modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true, handler: @escaping () -> Void) {
        let item = NSMenuItem(title, symbol: symbol, key: key, modifiers: modifiers, handler: handler)
        item.isEnabled = enabled
        addItem(item)
    }

    func addSubmenu(_ title: String, symbol: String? = nil, image: NSImage? = nil, build: (NSMenu) -> Void) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = image ?? symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        item.showsImage()
        let sub = NSMenu(title: title)
        build(sub)
        item.submenu = sub
        addItem(item)
    }

    func addHeader(_ title: String) {
        addItem(NSMenuItem.sectionHeader(title: title))
    }
}

/// The shelf's action menu (chevron button, right click).
enum ShelfMenu {
    static func make(for c: ShelfController) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let items = c.targetItems
        let hasItems = !items.isEmpty
        // Items picked in the list get the commands that only make sense for a selection.
        let selecting = !c.model.selection.isEmpty

        FileActionMenu.addRecent(to: menu, controller: c)

        if hasItems {
            menu.addSubmenu(L("Open With"), image: OpenWith.applications(for: items.prefix(1).map(\.url)).first?.icon) { sub in
                for app in OpenWith.applications(for: items.map(\.url)) {
                    let entry = NSMenuItem(app.name) { c.open(items, with: app.url) }
                    entry.image = app.icon
                    sub.addItem(entry)
                }
                if sub.items.isEmpty { sub.add(L("No content"), enabled: false) {} }
            }
            menu.add(L("Show in Finder")) { c.reveal() }
            menu.items.last?.image = OpenWith.icon(URL(filePath: "/System/Library/CoreServices/Finder.app"))
            menu.add(L("Quick Look"), symbol: "eye") { c.quickLook() }
                menu.addItem(.separator())

            FileActionMenu.addShareActions(to: menu, controller: c)
            menu.addItem(.separator())
        }

        menu.add(L("Add From Clipboard"), symbol: "doc.on.clipboard") { c.addFromClipboard() }
        if hasItems {
            menu.add(L("Copy %@", items.count == 1 ? items[0].displayName : L("%d Files", items.count)), symbol: "doc.on.doc") { c.copyToPasteboard() }
            FileActionMenu.addMainMenuActions(to: menu, controller: c)
            FileActionMenu.addAllActions(to: menu, controller: c)
            if selecting {
                menu.add(L("Move to New Shelf"), symbol: "rectangle.portrait.on.rectangle.portrait", enabled: c.model.items.count > 1) { c.moveToNewShelf() }
                menu.add(L("Remove From Shelf"), symbol: "minus.circle") { c.remove(c.model.selection) }
            }
        }
        menu.addItem(.separator())

        menu.add(L("Clear Shelf"), symbol: "delete.left", enabled: hasItems) { c.clear() }
        menu.add(c.dockedEdge == nil ? L("Dock to Edge") : L("Undock"), symbol: "rectangle.lefthalf.inset.filled.arrow.left") { c.toggleDock() }
        menu.addSubmenu(L("Customize"), symbol: "slider.horizontal.2.square") { sub in addCustomize(to: sub, controller: c) }
        menu.add(L("Settings..."), symbol: "gearshape") { SettingsWindowController.shared.show() }
        return menu
    }

    /// Name, indicator color and window behavior of this shelf.
    private static func addCustomize(to sub: NSMenu, controller c: ShelfController) {
        sub.autoenablesItems = false
        sub.add(L("Change Name..."), symbol: "character.cursor.ibeam") {
            c.showPage(.items)
            c.model.showsPreferences = true
        }
        sub.addItem(.separator())
        sub.addHeader(L("Indicator Color"))
        let grid = NSMenuItem()
        // The menu stays open after a color is picked, so colors can be compared.
        grid.view = ColorGridMenuView(model: c.model) { c.setColor($0 == 0 ? nil : $0) }
        sub.addItem(grid)
        sub.add(L("Always Show Indicator"), symbol: "eye.circle.fill") { c.setAlwaysShowIndicator(!c.model.alwaysShowIndicator) }
        sub.items.last?.state = c.model.alwaysShowIndicator ? .on : .off
        sub.addItem(.separator())
        sub.add(L("Pin Shelf"), symbol: "pin.circle.fill") { c.setPinned(!c.model.pinned) }
        sub.items.last?.state = c.model.pinned ? .on : .off
        sub.add(L("Keep Shelf in Own Space"), symbol: "rectangle.split.2x1") { c.setKeepInOwnSpace(!c.model.keepInOwnSpace) }
        sub.items.last?.state = c.model.keepInOwnSpace ? .on : .off
    }

    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}

/// Applications that can open every one of the given files.
enum OpenWith {
    struct App { let url: URL; let name: String; let icon: NSImage }

    static func applications(for urls: [URL]) -> [App] {
        guard let first = urls.first else { return [] }
        var common = Set(NSWorkspace.shared.urlsForApplications(toOpen: first))
        for url in urls.dropFirst() { common.formIntersection(NSWorkspace.shared.urlsForApplications(toOpen: url)) }
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: first)
        return common
            .map { App(url: $0, name: FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: ""), icon: icon($0)) }
            .sorted { lhs, rhs in
                if lhs.url == preferred { return true }
                if rhs.url == preferred { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func icon(_ url: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

/// The two rows of indicator colors (Customize menu, shelf preferences); the current one has a ring.
/// The color grid inside a menu. SwiftUI buttons don't get clicks while a menu is tracking,
/// so the swatches are hit-tested here; the menu stays open.
final class ColorGridMenuView: NSView {
    private let pick: (Int) -> Void
    // Must match ColorGrid's layout below with size 20, spacing 5, row spacing 4 and the menu inset.
    private let cell: CGFloat = 26, spacing: CGFloat = 5, rowSpacing: CGFloat = 4, leading: CGFloat = 36, top: CGFloat = 6

    init(model: ShelfModel, pick: @escaping (Int) -> Void) {
        self.pick = pick
        let host = NSHostingView(rootView: ColorGrid(model: model, size: 20, spacing: 5, rowSpacing: 4, inset: true) { _ in })
        host.frame.size = host.fittingSize
        super.init(frame: host.frame)
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    // Taking the press keeps it from reaching the menu, which would treat it as choosing the item and close.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let x = point.x - leading, y = (isFlipped ? point.y : bounds.height - point.y) - top
        let column = Int(x / (cell + spacing)), row = Int(y / (cell + rowSpacing))
        guard x >= 0, y >= 0, (0..<5).contains(column), (0..<2).contains(row),
              x - CGFloat(column) * (cell + spacing) <= cell, y - CGFloat(row) * (cell + rowSpacing) <= cell else { return }
        pick(row * 5 + column)
    }
}

struct ColorGrid: View {
    let model: ShelfModel
    let size: CGFloat
    let spacing: CGFloat
    let rowSpacing: CGFloat
    /// In a menu the grid lines up with the item titles.
    let inset: Bool
    let pick: (Int?) -> Void

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: rowSpacing) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<5, id: \.self) { column in
                        let index = row * 5 + column
                        // Gray is the default color: picking it clears the shelf's color.
                        Button { pick(index == 0 ? nil : index) } label: {
                            Circle().fill(Color(nsColor: ShelfColor.all[index].color))
                                .frame(width: size, height: size)
                                .padding(3)
                                .overlay { if (model.colorIndex ?? 0) == index { Circle().strokeBorder(Color.orange, lineWidth: 2) } }
                        }
                        .buttonStyle(.plain)
                        .help(ShelfColor.all[index].name)
                    }
                }
            }
        }
        .padding(.leading, inset ? 36 : 0).padding(.trailing, inset ? 20 : 0).padding(.vertical, inset ? 6 : 0)
    }
}
