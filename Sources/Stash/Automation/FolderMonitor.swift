import AppKit
import CoreServices
import StashCore

/// Reports files that appear in a set of folders (FSEvents, file-level events).
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    var onNewFiles: ([URL]) -> Void = { _ in }

    func watch(_ paths: [String]) {
        stop()
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, Self.callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info, let list = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
        var urls: [URL] = []
        for index in 0..<count {
            let flag = Int(flags[index])
            let appeared = flag & (kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed) != 0
            guard appeared, flag & kFSEventStreamEventFlagItemIsFile != 0 || flag & kFSEventStreamEventFlagItemIsDir != 0 else { continue }
            urls.append(URL(filePath: list[index]))
        }
        guard !urls.isEmpty else { return }
        // The stream delivers on the main queue. A pointer isn't Sendable, its address is.
        let address = UInt(bitPattern: info)
        MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(pointer).takeUnretainedValue().onNewFiles(urls)
        }
    }
}

/// Folder Monitoring and the Screenshot shelf: new files in watched folders show up in a shelf.
final class FolderMonitor {
    static let shared = FolderMonitor()

    private let paths = StashPaths.standard
    private let watcher = DirectoryWatcher()
    private(set) var folders: [WatchedFolder] = []
    /// Files already shown, so a rename burst or a second event doesn't open another shelf.
    private var shown: Set<String> = []
    private var pending: [UUID: [URL]] = [:]

    private init() {
        folders = WatchedFolder.load(from: paths.foldersFile)
        watcher.onNewFiles = { [weak self] urls in self?.handle(urls) }
    }

    // MARK: Folders

    func start() { refresh() }

    func update(_ folder: WatchedFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) { folders[index] = folder } else { folders.append(folder) }
        save()
    }

    func remove(_ folder: WatchedFolder) {
        folders.removeAll { $0.id == folder.id }
        save()
    }

    func isAvailable(_ folder: WatchedFolder) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
            && FileManager.default.isReadableFile(atPath: folder.path)
    }

    private func save() {
        try? WatchedFolder.save(folders, to: paths.foldersFile)
        refresh()
    }

    /// Restarts the stream for the enabled folders and the screenshot folder.
    func refresh() {
        var watched = folders.filter { $0.enabled && isAvailable($0) }.map(\.path)
        if Prefs.bool(Pref.screenshotShelf) { watched.append(ScreenshotShelf.folder.path) }
        watcher.watch(Array(Set(watched)))
    }

    // MARK: New files

    private func handle(_ urls: [URL]) {
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !shown.contains(path), NewFileFilter.isCandidate(url), FileManager.default.fileExists(atPath: path) else { continue }
            if Prefs.bool(Pref.screenshotShelf), url.deletingLastPathComponent().standardizedFileURL.path == ScreenshotShelf.folder.standardizedFileURL.path,
               ScreenshotShelf.isScreenshot(url) {
                shown.insert(path)
                ScreenshotShelf.show(url)
                continue
            }
            let facts = FileFacts(url: url)
            guard let folder = folders.first(where: { $0.enabled && $0.covers(url) && $0.accepts(facts) }) else { continue }
            shown.insert(path)
            schedule(url, for: folder)
        }
    }

    /// Waits the folder's delay (letting downloads finish) and shows everything that arrived meanwhile together.
    private func schedule(_ url: URL, for folder: WatchedFolder) {
        let first = pending[folder.id] == nil
        pending[folder.id, default: []].append(url)
        guard first else { return }
        Task {
            try? await Task.sleep(for: .seconds(folder.delay))
            let urls = (pending.removeValue(forKey: folder.id) ?? []).filter { FileManager.default.fileExists(atPath: $0.path) }
            show(urls, from: folder)
        }
    }

    private func show(_ urls: [URL], from folder: WatchedFolder) {
        guard !urls.isEmpty else { return }
        let groups = folder.shelfPerFile ? urls.map { [$0] } : [urls]
        for group in groups {
            let shelf = ShelfManager.shared.addFromOutside(group.map { ShelfItem(url: $0) })
            shelf?.showToast(group.count == 1 ? L("New file in %@", folder.name) : L("%d new files in %@", group.count, folder.name))
        }
    }
}

/// Shows new screenshots in a shelf.
enum ScreenshotShelf {
    private weak static var lastShelf: ShelfController?

    /// Where macOS saves screenshots (Desktop unless changed in the Screenshot app).
    static var systemFolder: URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !location.isEmpty {
            return URL(filePath: (location as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return URL.desktopDirectory
    }

    static var folder: URL {
        if let path = UserDefaults.standard.string(forKey: Pref.screenshotFolder), !path.isEmpty { return URL(filePath: path, directoryHint: .isDirectory) }
        return systemFolder
    }

    /// macOS marks screenshots with a Spotlight attribute stored as an extended attribute.
    static func isScreenshot(_ url: URL) -> Bool {
        if getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0 { return true }
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool { return value }
        return false
    }

    static func show(_ url: URL) {
        let item = ShelfItem(url: url)
        if Prefs.bool(Pref.screenshotAppend), let shelf = lastShelf, shelf.panel.isVisible {
            shelf.add([item])
        } else {
            lastShelf = ShelfManager.shared.newShelf(items: [item])
        }
        if Prefs.bool(Pref.screenshotMessage) { lastShelf?.showToast(L("New screenshot in %@", FileManager.default.displayName(atPath: url.deletingLastPathComponent().path))) }
        if Prefs.bool(Pref.screenshotClipboard), let image = NSImage(contentsOf: url) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
    }
}
