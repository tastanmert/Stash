import Foundation

/// A shelf as stored on disk: kept for "Recent Shelves", "Reopen Last Closed Shelf" and pinned shelves.
public struct ShelfRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String?
    /// The title the shelf showed when it was closed (its count or intelligent name).
    public var title: String?
    public var paths: [String]
    public var closedAt: Date
    public var pinned: Bool
    public var colorIndex: Int?
    /// Optional so records saved before this setting existed still decode.
    public var alwaysShowIndicator: Bool?

    public init(id: UUID = UUID(), name: String? = nil, title: String? = nil, paths: [String], closedAt: Date = .now, pinned: Bool = false, colorIndex: Int? = nil, alwaysShowIndicator: Bool? = nil) {
        self.id = id
        self.name = name
        self.title = title
        self.paths = paths
        self.closedAt = closedAt
        self.pinned = pinned
        self.colorIndex = colorIndex
        self.alwaysShowIndicator = alwaysShowIndicator
    }

    /// Items that still exist on disk.
    public var existingURLs: [URL] {
        paths.map { URL(filePath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Recent (closed) shelves, newest first, plus pinned shelves; persisted as JSON.
public struct ShelfStore: Codable, Equatable, Sendable {
    public var recent: [ShelfRecord] = []
    public var pinned: [ShelfRecord] = []
    public static let maxRecent = 10

    public init() {}

    public mutating func addRecent(_ record: ShelfRecord) {
        guard !record.paths.isEmpty else { return }
        recent.removeAll { $0.id == record.id }
        recent.insert(record, at: 0)
        if recent.count > Self.maxRecent { recent.removeLast(recent.count - Self.maxRecent) }
    }

    public mutating func removeRecent(id: UUID) { recent.removeAll { $0.id == id } }

    /// Takes the most recent shelf whose items still exist, dropping it from the list.
    public mutating func popLastRestorable() -> ShelfRecord? {
        while let first = recent.first {
            recent.removeFirst()
            if !first.existingURLs.isEmpty { return first }
        }
        return nil
    }

    public mutating func setPinned(_ record: ShelfRecord?) {
        guard let record else { return }
        pinned.removeAll { $0.id == record.id }
        if record.pinned { pinned.append(record) }
    }

    public static func load(from url: URL) -> ShelfStore {
        guard let data = try? Data(contentsOf: url) else { return ShelfStore() }
        return (try? JSONDecoder().decode(ShelfStore.self, from: data)) ?? ShelfStore()
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
