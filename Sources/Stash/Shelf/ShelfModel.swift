import AppKit
import StashCore

/// Observable state of one shelf, read by its SwiftUI views.
@Observable
final class ShelfModel {
    let id: UUID
    var items: [ShelfItem] = []
    var customName: String?
    var generatedName: String?
    var colorIndex: Int?
    var pinned = false
    var keepInOwnSpace = false
    var alwaysShowIndicator = false
    /// The detail view's preferences popover is open.
    var showsPreferences = false
    var page: ShelfPage = .stack
    var isDetail: Bool { page != .stack }
    var displayMode: DisplayMode = Prefs.value(Pref.displayMode, default: .grid)
    var selection: Set<UUID> = []
    var isDropTargeted = false
    var isDocked = false
    var renamingID: UUID?
    var isOptionDown = false
    /// A short note shown at the bottom of the shelf ("Link copied to clipboard").
    var toast: String?
    /// A running task ("Compressing...").
    var busy: String?
    /// The error of the last failed action.
    var error: String?

    init(id: UUID = UUID()) { self.id = id }

    var title: String {
        if let customName, !customName.isEmpty { return customName }
        if Prefs.bool(Pref.intelligentNames), let group = folderGroup {
            switch group.kind {
            case .image: return L("%@ Images", group.folder)
            case .text: return L("%@ Texts", group.folder)
            case .folder: return L("%@ Folders", group.folder)
            default: return L("%@ Files", group.folder)
            }
        }
        if let generatedName, Prefs.bool(Pref.intelligentNames) { return generatedName }
        return ShelfTitle.make(names: items.map(\.displayName), kinds: items.map(\.titleKind)) { count, kind in
            switch kind {
            case .image: L("%d Images", count)
            case .text: L("%d Texts", count)
            case .folder: L("%d Folders", count)
            default: L("%d Files", count)
            }
        }
    }

    /// Items that all come from one real folder (not Stash's temporary one) are named after it.
    var folderGroup: (folder: String, kind: ShelfTitle.Kind?)? {
        guard !items.contains(where: \.isTemporary) else { return nil }
        let parents = items.map { FileManager.default.displayName(atPath: $0.url.deletingLastPathComponent().path) }
        return ShelfTitle.folderGroup(parents: parents, kinds: items.map(\.titleKind))
    }

    var selectedItems: [ShelfItem] {
        let picked = items.filter { selection.contains($0.id) }
        return picked.isEmpty ? items : picked
    }

    /// Gray (index 0) is the default and counts as no color.
    var color: NSColor? { colorIndex.flatMap { $0 == 0 ? nil : ShelfColor.all[$0 % ShelfColor.all.count].color } }

    var totalSize: Int64 { items.compactMap(\.size).reduce(0, +) }

    var record: ShelfRecord {
        ShelfRecord(id: id, name: customName, title: title, paths: items.map(\.url.path), pinned: pinned, colorIndex: colorIndex,
                    alwaysShowIndicator: alwaysShowIndicator ? true : nil)
    }
}

enum ShelfPage: Equatable { case stack, items, action(String) }

/// Indicator colors, in the order of the shelf's color grid (two rows of five).
struct ShelfColor {
    let name: String
    let color: NSColor
    static let all: [ShelfColor] = [
        ShelfColor(name: L("Gray"), color: NSColor(srgbRed: 0.56, green: 0.56, blue: 0.57, alpha: 1)),
        ShelfColor(name: L("Orange"), color: NSColor(srgbRed: 0.82, green: 0.48, blue: 0.27, alpha: 1)),
        ShelfColor(name: L("Yellow"), color: NSColor(srgbRed: 0.87, green: 0.71, blue: 0.26, alpha: 1)),
        ShelfColor(name: L("Green"), color: NSColor(srgbRed: 0.48, green: 0.79, blue: 0.26, alpha: 1)),
        ShelfColor(name: L("Teal"), color: NSColor(srgbRed: 0.29, green: 0.64, blue: 0.58, alpha: 1)),
        ShelfColor(name: L("Blue"), color: NSColor(srgbRed: 0.30, green: 0.53, blue: 0.91, alpha: 1)),
        ShelfColor(name: L("Purple"), color: NSColor(srgbRed: 0.48, green: 0.33, blue: 0.90, alpha: 1)),
        ShelfColor(name: L("Pink"), color: NSColor(srgbRed: 0.91, green: 0.53, blue: 0.49, alpha: 1)),
        ShelfColor(name: L("Cream"), color: NSColor(srgbRed: 0.93, green: 0.89, blue: 0.61, alpha: 1)),
        ShelfColor(name: L("Sage"), color: NSColor(srgbRed: 0.42, green: 0.55, blue: 0.37, alpha: 1)),
    ]
}

extension Int64 {
    var fileSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
