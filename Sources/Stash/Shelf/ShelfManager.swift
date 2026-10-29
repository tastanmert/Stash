import AppKit
import StashCore

/// All open shelves, plus recent and pinned ones.
final class ShelfManager {
    static let shared = ShelfManager()

    enum Placement {
        /// Next to the cursor of a drag in progress.
        case cursor(NSPoint)
        /// The "Default shelf location" setting.
        case standard
        /// Just under a rectangle (the notch, another shelf).
        case below(NSRect)
        /// Beside another shelf.
        case near(NSRect)
    }

    private(set) var controllers: [ShelfController] = []
    private(set) var store: ShelfStore
    private(set) weak var lastActive: ShelfController?
    private let paths = StashPaths.standard
    /// Called whenever the open / recent / pinned lists change (menu bar menu refresh).
    var onChange: () -> Void = {}

    private init() {
        store = ShelfStore.load(from: StashPaths.standard.shelvesFile)
    }

    var recent: [ShelfRecord] { store.recent }
    var pinned: [ShelfRecord] { store.pinned }
    var visibleShelves: [ShelfController] { controllers.filter { $0.panel.isVisible && $0.panel.isOnActiveSpace } }

    // MARK: Creating

    @discardableResult
    func newShelf(items: [ShelfItem] = [], at placement: Placement = .standard, model: ShelfModel = ShelfModel()) -> ShelfController {
        let origin = self.origin(for: placement, size: ShelfController.stackSize)
        let controller = ShelfController(model: model, origin: origin)
        controllers.append(controller)
        controller.show()
        if !items.isEmpty { controller.add(items) }
        lastActive = controller
        onChange()
        return controller
    }

    func newShelfFromClipboard() {
        let items = PasteboardImporter.items(from: .general) { [weak self] promised in self?.newShelf(items: promised) }
        if items.isEmpty { NSSound.beep() } else { newShelf(items: items) }
    }

    /// Adds files from a shortcut, the Services menu, a URL or a watched folder.
    @discardableResult
    func addFromOutside(_ items: [ShelfItem], forceNewShelf: Bool = false) -> ShelfController? {
        guard !items.isEmpty else { return nil }
        let behavior: AddingBehavior = forceNewShelf ? .newShelf : Prefs.value(Pref.addingBehavior, default: .newShelf)
        switch behavior {
        case .lastActive where lastActive?.panel.isVisible == true:
            lastActive?.add(items)
            return lastActive
        case .visible where !visibleShelves.isEmpty:
            let shelf = visibleShelves.last { $0 === lastActive } ?? visibleShelves.last
            shelf?.add(items)
            return shelf
        default:
            return newShelf(items: items)
        }
    }

    func open(_ record: ShelfRecord) {
        if let open = controllers.first(where: { $0.model.id == record.id }) {
            open.undock()
            open.panel.orderFrontRegardless()
            return
        }
        let items = record.existingURLs.map { ShelfItem(url: $0, isTemporary: $0.path.hasPrefix(paths.temporary.path)) }
        guard !items.isEmpty else {
            store.removeRecent(id: record.id)
            save()
            return
        }
        let model = ShelfModel(id: record.id)
        model.customName = record.name
        model.colorIndex = record.colorIndex
        model.alwaysShowIndicator = record.alwaysShowIndicator ?? false
        model.pinned = record.pinned
        store.removeRecent(id: record.id)
        newShelf(items: items, model: model)
    }

    func reopenLastClosed() {
        guard let record = store.popLastRestorable() else { return NSSound.beep() }
        open(record)
    }

    // MARK: Lifecycle callbacks

    func didActivate(_ controller: ShelfController) { lastActive = controller }

    func itemsChanged(_ controller: ShelfController) {
        if controller.model.pinned || store.pinned.contains(where: { $0.id == controller.model.id }) {
            var record = controller.model.record
            record.pinned = controller.model.pinned
            if store.pinned.contains(where: { $0.id == record.id }) || record.pinned {
                store.pinned.removeAll { $0.id == record.id }
                if record.pinned { store.pinned.append(record) }
            }
            save()
        }
        onChange()
    }

    /// Shelves still open when Stash quits go to Recent Shelves, so they can be reopened.
    func rememberOpenShelves() {
        for controller in controllers where !controller.model.pinned { store.addRecent(controller.model.record) }
        save()
    }

    func shelfWillClose(_ controller: ShelfController, remember: Bool) {
        controllers.removeAll { $0 === controller }
        if remember, !controller.model.pinned { store.addRecent(controller.model.record) }
        save()
        onChange()
    }

    func closeAll() {
        for controller in controllers { controller.close() }
    }

    func toggleDockingAll() {
        let anyUndocked = controllers.contains { $0.dockedEdge == nil }
        for controller in controllers {
            if anyUndocked { if controller.dockedEdge == nil { controller.dock(to: controller.nearestEdge) } } else { controller.undock() }
        }
    }

    func clearRecent() {
        store.recent.removeAll()
        save()
        onChange()
    }

    func removeRecent(_ record: ShelfRecord) {
        store.removeRecent(id: record.id)
        save()
        onChange()
    }

    func unpin(_ record: ShelfRecord) {
        store.pinned.removeAll { $0.id == record.id }
        controllers.first { $0.model.id == record.id }?.model.pinned = false
        save()
        onChange()
    }

    private func save() { try? store.save(to: paths.shelvesFile) }

    /// Shelves opened by a drag that then dropped nothing go away when the drag ends.
    func dragEnded() {
        for controller in controllers where controller.openedByDrag {
            controller.openedByDrag = false
            if controller.model.items.isEmpty { controller.close(clearing: true) }
        }
    }

    // MARK: Placement

    private func origin(for placement: Placement, size: NSSize) -> NSPoint {
        let screen = screenForPlacement(placement)
        let area = screen.visibleFrame
        let margin: CGFloat = 20
        var frame = NSRect(origin: .zero, size: size)
        switch placement {
        case .cursor(let point):
            // Beside the cursor, toward the middle of the screen, so the drop target is a short move away.
            let right = point.x < area.midX
            frame.origin.x = right ? point.x + 40 : point.x - 40 - size.width
            frame.origin.y = point.y - size.height / 2
        case .below(let rect):
            frame.origin.x = rect.midX - size.width / 2
            frame.origin.y = rect.minY - size.height - 8
        case .near(let rect):
            frame.origin.x = rect.minX - size.width - 12
            frame.origin.y = rect.maxY - size.height
            if frame.minX < area.minX { frame.origin.x = rect.maxX + 12 }
        case .standard:
            let location: ShelfLocation = Prefs.value(Pref.shelfLocation, default: .topRight)
            switch location {
            case .topLeft: frame.origin = NSPoint(x: area.minX + margin, y: area.maxY - size.height - margin)
            case .topRight: frame.origin = NSPoint(x: area.maxX - size.width - margin, y: area.maxY - size.height - margin)
            case .bottomLeft: frame.origin = NSPoint(x: area.minX + margin, y: area.minY + margin)
            case .bottomRight: frame.origin = NSPoint(x: area.maxX - size.width - margin, y: area.minY + margin)
            case .center: frame.origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
            case .nearCursor:
                let p = NSEvent.mouseLocation
                frame.origin = NSPoint(x: p.x - size.width / 2, y: p.y - size.height / 2)
            }
            // Cascade so a new shelf does not sit exactly on top of another.
            // A full column continues in the next one, toward the middle of the screen.
            let goesDown = frame.midY > area.midY, goesLeft = frame.midX > area.midX
            let top = frame.origin.y
            while controllers.contains(where: { abs($0.panel.frame.minX - frame.minX) < 8 && abs($0.panel.frame.minY - frame.minY) < 8 }) {
                frame.origin.y += goesDown ? -(size.height + 12) : (size.height + 12)
                if !area.contains(frame) {
                    frame.origin.y = top
                    frame.origin.x += goesLeft ? -(size.width + 12) : (size.width + 12)
                    if !area.contains(frame) { break }
                }
            }
        }
        return frame.clamped(to: area).origin
    }

    private func screenForPlacement(_ placement: Placement) -> NSScreen {
        let point: NSPoint
        switch placement {
        case .cursor(let p): point = p
        case .below(let r), .near(let r): point = NSPoint(x: r.midX, y: r.midY)
        case .standard: point = NSEvent.mouseLocation
        }
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
