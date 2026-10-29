import Foundation

/// How Batch Rename builds the new names: find-and-replace, or a format with `#counter`, `#date` and `#original`.
public struct RenameRule: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case replace, custom }

    public var mode: Mode = .replace
    public var find = ""
    public var replacement = ""
    public var caseSensitive = false
    public var format = "new_#counter"
    public var counterStart = 1

    public init() {}

    public enum Problem: Error, Equatable, Sendable {
        /// The search text (or the custom format) is empty.
        case missing
        /// The custom format contains a character a file name can't have.
        case invalidCharacter(String)
    }

    public func validate() -> Problem? {
        switch mode {
        case .replace:
            return find.isEmpty ? .missing : nil
        case .custom:
            if format.trimmingCharacters(in: .whitespaces).isEmpty { return .missing }
            return format.first { "/:".contains($0) }.map { .invalidCharacter(String($0)) }
        }
    }

    /// The new name of the `index`th file (counting from 0). The extension never changes.
    public func newName(for name: String, index: Int, date: Date = Date()) -> String {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        let newBase: String
        switch mode {
        case .replace:
            newBase = base.replacingOccurrences(of: find, with: replacement, options: caseSensitive ? [] : .caseInsensitive)
        case .custom:
            let day = date.formatted(.iso8601.year().month().day())
            newBase = format
                .replacingOccurrences(of: "#counter", with: String(counterStart + index))
                .replacingOccurrences(of: "#date", with: day)
                .replacingOccurrences(of: "#original", with: base)
        }
        let cleaned = newBase.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return ext.isEmpty ? cleaned : "\(cleaned).\(ext)"
    }
}

extension FileOperations {
    /// Renames the files in place and returns their new URLs, in the same order.
    /// A name that is taken gets a number ("new_1 2.png"); a file whose name doesn't change stays where it is.
    public static func batchRename(_ urls: [URL], rule: RenameRule, date: Date = Date()) throws -> [URL] {
        if rule.validate() != nil { throw FileOperationError.unsupportedFiles }
        var renamed: [URL] = []
        for (index, url) in urls.enumerated() {
            let name = rule.newName(for: url.lastPathComponent, index: index, date: date)
            guard !name.isEmpty, name != url.lastPathComponent else { renamed.append(url); continue }
            let target = StashPaths.uniqueURL(in: url.deletingLastPathComponent(), name: name)
            try FileManager.default.moveItem(at: url, to: target)
            renamed.append(target)
        }
        return renamed
    }
}
