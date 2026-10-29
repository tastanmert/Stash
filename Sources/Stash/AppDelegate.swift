import AppKit
import StashCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.register()
        try? StashPaths.standard.ensureDirectories()
        applyDockVisibility()
        StatusMenuController.shared.refresh()
        HotKeyCenter.shared.registerAll()
        NotchController.shared.refresh()
        DragMonitor.shared.onDragStateChange = { NotchController.shared.dragStateChanged($0) }
        DragMonitor.shared.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchController.shared.refresh() }
        }
        AppMaintenance.start()
        FolderMonitor.shared.start()
        NSApp.servicesProvider = ServicesProvider.shared
        NSUpdateDynamicServices()
        if !Prefs.bool(Pref.hasLaunched) {
            UserDefaults.standard.set(true, forKey: Pref.hasLaunched)
            OnboardingWindowController.shared.show()
        }
        WhatsNew.showIfUpdated()
    }

    /// `stash://add?path=/a&path=/b`, `stash://new`, `stash://clipboard` (for Raycast, Alfred, the terminal).
    func applicationWillTerminate(_ notification: Notification) {
        ShelfManager.shared.rememberOpenShelves()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "stash" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch url.host() {
            case "add":
                let items = query.filter { $0.name == "path" }.compactMap(\.value).filter { !$0.isEmpty }
                    .map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                    .map { ShelfItem(url: $0) }
                ShelfManager.shared.addFromOutside(items)
            case "new": ShelfManager.shared.newShelf().panel.makeKey()
            case "clipboard": ShelfManager.shared.newShelfFromClipboard()
            default: NSSound.beep()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindowController.shared.show() }
        return true
    }

    func applyDockVisibility() {
        NSApp.setActivationPolicy(Prefs.bool(Pref.showInDock) ? .regular : .accessory)
    }
}

/// Housekeeping: clears out unused temporary files and watches the free disk space.
enum AppMaintenance {
    private static var timer: Timer?
    private(set) static var disk = DiskSpaceMonitor()

    static func start() {
        runChecks()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in MainActor.assumeIsolated { runChecks() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { runChecks() }
        }
    }

    private static func runChecks() {
        purgeOrphanedTemporaryFiles()
        checkDiskSpace()
    }

    /// Removes temporary files that no open, recent or pinned shelf refers to any more (older than a day).
    static func purgeOrphanedTemporaryFiles() {
        let paths = StashPaths.standard
        let manager = ShelfManager.shared
        let referenced = Set((manager.recent + manager.pinned).flatMap(\.paths) + manager.controllers.flatMap { $0.model.items.map(\.url.path) })
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: paths.temporary, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let dayAgo = Date.now.addingTimeInterval(-86_400)
        for url in entries {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
            let inUse = referenced.contains { $0.hasPrefix(url.path) }
            if modified < dayAgo, !inUse { try? fm.trashItem(at: url, resultingItemURL: nil) }
        }
    }

    /// Updates the low disk space warning (shown at the top of the menu bar menu).
    static func checkDiskSpace() {
        guard let free = DiskSpaceMonitor.available(at: StashPaths.standard.root) else { return }
        disk.update(available: free)
    }
}
