import Foundation

/// Where Stash keeps its own files.
public struct StashPaths: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static let standard = StashPaths(
        root: URL.applicationSupportDirectory.appending(path: "Stash", directoryHint: .isDirectory))

    /// Text, images and other raw drag data written out as files.
    public var temporary: URL { root.appending(path: "Temporary", directoryHint: .isDirectory) }
    /// Results of file actions (zip, resized images, merged PDFs).
    public var output: URL { root.appending(path: "Actions Output", directoryHint: .isDirectory) }
    /// User scripts shown as custom actions.
    public var scripts: URL { root.appending(path: "Scripts", directoryHint: .isDirectory) }
    public var shelvesFile: URL { root.appending(path: "shelves.json") }
    public var foldersFile: URL { root.appending(path: "folders.json") }

    public func ensureDirectories() throws {
        for dir in [temporary, output, scripts] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// A fresh, collision-free URL inside `directory` for a file called `name`.
    public static func uniqueURL(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appending(path: name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = directory.appending(path: numbered)
            n += 1
        }
        return candidate
    }

    /// Total size in bytes of the regular files under `directory`.
    public static func size(of directory: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
