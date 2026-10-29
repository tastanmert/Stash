import Foundation

/// Deterministic shelf titles ("3 Files", "2 Images", "Report.pdf").
public enum ShelfTitle {
    public enum Kind: Sendable { case image, text, folder, other }

    /// - Parameters:
    ///   - names: display names of the items.
    ///   - kinds: kinds of the items (same order).
    ///   - plural: localized template picker, e.g. `{ count, kind in "\(count) Files" }`.
    public static func make(names: [String], kinds: [Kind], plural: (Int, Kind?) -> String) -> String {
        if names.count == 1 { return names[0] }
        let unique = Set(kinds)
        let kind = unique.count == 1 ? unique.first : nil
        return plural(names.count, kind == .other ? nil : kind)
    }

    /// "dragtest Images": when every item comes from the same folder, that folder's name plus the
    /// kind most of the items share (nil when no kind is in the majority).
    public static func folderGroup(parents: [String], kinds: [Kind]) -> (folder: String, kind: Kind?)? {
        guard parents.count > 1, let first = parents.first, !first.isEmpty, parents.allSatisfy({ $0 == first }) else { return nil }
        let counts = Dictionary(kinds.map { ($0, 1) }, uniquingKeysWith: +)
        guard let top = counts.max(by: { $0.value < $1.value }) else { return (first, nil) }
        return (first, top.value * 2 > kinds.count && top.key != .other ? top.key : nil)
    }
}
