import Foundation
import UniformTypeIdentifiers

/// What a folder rule can look at for a new file.
public struct FileFacts: Equatable, Sendable {
    public var name: String
    public var fileExtension: String
    public var kind: FolderRule.Kind?
    /// Bytes.
    public var size: Int64

    public init(name: String, fileExtension: String, kind: FolderRule.Kind?, size: Int64) {
        self.name = name
        self.fileExtension = fileExtension
        self.kind = kind
        self.size = size
    }

    public init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey])
        self.init(name: url.lastPathComponent, fileExtension: url.pathExtension,
                  kind: values?.isDirectory == true ? .folder : values?.contentType.flatMap(FolderRule.Kind.init(type:)),
                  size: Int64(values?.fileSize ?? 0))
    }
}

/// One condition a new file has to meet, like "File extension is pdf" or "File size greater than 10 MB".
public struct FolderRule: Codable, Hashable, Sendable, Identifiable {
    public enum Field: String, Codable, CaseIterable, Sendable {
        case name, fileExtension, kind, size

        public var comparisons: [Comparison] {
            switch self {
            case .name, .fileExtension: [.contains, .doesNotContain, .beginsWith, .endsWith, .equals, .notEquals]
            case .kind: [.equals, .notEquals]
            case .size: [.greaterThan, .lessThan]
            }
        }
    }

    public enum Comparison: String, Codable, CaseIterable, Sendable {
        case contains, doesNotContain, beginsWith, endsWith, equals, notEquals, greaterThan, lessThan
    }

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case application, archive, audio, document, folder, image, pdf, presentation, text, video

        public init?(type: UTType) {
            let order: [(Kind, UTType)] = [
                (.pdf, .pdf), (.application, .application), (.image, .image), (.video, .movie), (.audio, .audio),
                (.archive, .archive), (.presentation, .presentation), (.text, .text),
                (.document, .spreadsheet), (.document, .content),
            ]
            guard let match = order.first(where: { type.conforms(to: $0.1) }) else { return nil }
            self = match.0
        }
    }

    public var id = UUID()
    public var field: Field
    public var comparison: Comparison
    /// Text for names and extensions, a `Kind` raw value, or megabytes for sizes.
    public var value: String

    public init(field: Field, comparison: Comparison, value: String) {
        self.field = field
        self.comparison = comparison
        self.value = value
    }

    public func matches(_ file: FileFacts, caseSensitive: Bool = false) -> Bool {
        switch field {
        case .name: compare(text: file.name, caseSensitive: caseSensitive)
        case .fileExtension: compare(text: file.fileExtension, against: value.hasPrefix(".") ? String(value.dropFirst()) : value, caseSensitive: caseSensitive)
        case .kind: comparison == .notEquals ? file.kind?.rawValue != value : file.kind?.rawValue == value
        case .size: compare(size: file.size)
        }
    }

    private func compare(text: String, against expected: String? = nil, caseSensitive: Bool) -> Bool {
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let expected = expected ?? value
        switch comparison {
        case .contains: return text.range(of: expected, options: options) != nil
        case .doesNotContain: return text.range(of: expected, options: options) == nil
        case .beginsWith: return text.range(of: expected, options: options.union(.anchored)) != nil
        case .endsWith: return text.range(of: expected, options: options.union([.anchored, .backwards])) != nil
        case .equals: return text.compare(expected, options: options) == .orderedSame
        case .notEquals: return text.compare(expected, options: options) != .orderedSame
        case .greaterThan, .lessThan: return false
        }
    }

    private func compare(size: Int64) -> Bool {
        guard let megabytes = Double(value.replacingOccurrences(of: ",", with: ".")) else { return false }
        let bytes = megabytes * 1_000_000
        switch comparison {
        case .greaterThan: return Double(size) > bytes
        case .lessThan: return Double(size) < bytes
        default: return false
        }
    }
}

/// A folder whose new files are shown in a shelf.
public struct WatchedFolder: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var path: String
    public var enabled = true
    public var includeSubfolders = false
    /// Seconds to wait before showing a new file, so downloads and copies can finish.
    public var delay: Double = 3
    /// Every new file gets its own shelf instead of sharing one.
    public var shelfPerFile = false
    public var caseSensitive = false
    /// All rules must match (And) or any one is enough (Or).
    public var matchAll = true
    public var rules: [FolderRule] = []

    public init(path: String) { self.path = path }

    public var url: URL { URL(filePath: path, directoryHint: .isDirectory) }
    public var name: String { FileManager.default.displayName(atPath: path) }

    public func accepts(_ file: FileFacts) -> Bool {
        guard !rules.isEmpty else { return true }
        return matchAll ? rules.allSatisfy { $0.matches(file, caseSensitive: caseSensitive) }
                        : rules.contains { $0.matches(file, caseSensitive: caseSensitive) }
    }

    /// Whether a changed path belongs to this folder (directly, or nested when subfolders are watched).
    public func covers(_ file: URL) -> Bool {
        let parent = file.deletingLastPathComponent().standardizedFileURL.path
        let root = url.standardizedFileURL.path
        return parent == root || (includeSubfolders && parent.hasPrefix(root.hasSuffix("/") ? root : root + "/"))
    }

    public static func load(from url: URL) -> [WatchedFolder] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WatchedFolder].self, from: data)) ?? []
    }

    public static func save(_ folders: [WatchedFolder], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(folders).write(to: url, options: .atomic)
    }
}

/// Files that should never pop up a shelf: hidden files and unfinished downloads.
public enum NewFileFilter {
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "opdownload"]

    public static func isCandidate(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return !name.hasPrefix(".") && !partialExtensions.contains(url.pathExtension.lowercased()) && name != "Icon\r"
    }
}
