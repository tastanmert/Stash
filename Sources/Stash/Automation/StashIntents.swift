import AppIntents
import AppKit
import StashCore

// Shortcuts actions. They run inside Stash (it is launched in the background when needed).

struct NewShelfIntent: AppIntent {
    static let title = LocalizedStringResource("Create New Shelf")
    static let description = IntentDescription(LocalizedStringResource("Create a new empty shelf."))

    @MainActor func perform() async throws -> some IntentResult {
        ShelfManager.shared.newShelf()
        return .result()
    }
}

struct NewClipboardShelfIntent: AppIntent {
    static let title = LocalizedStringResource("Create Shelf from Clipboard")
    static let description = IntentDescription(LocalizedStringResource("Opens a new Stash shelf with the contents of your clipboard."))

    @MainActor func perform() async throws -> some IntentResult {
        ShelfManager.shared.newShelfFromClipboard()
        return .result()
    }
}

struct AddFilesToShelfIntent: AppIntent {
    static let title = LocalizedStringResource("Add Files to Shelf")
    static let description = IntentDescription(LocalizedStringResource("Adds files to a new shelf, or appends to an existing shelf."))

    @Parameter(title: LocalizedStringResource("Files"), description: LocalizedStringResource("The files to add to a shelf."))
    var files: [IntentFile]

    @Parameter(title: LocalizedStringResource("New Shelf"), description: LocalizedStringResource("Show added files in new shelf."), default: false)
    var newShelf: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$files) to a shelf") { \.$newShelf }
    }

    @MainActor func perform() async throws -> some IntentResult {
        let urls = try files.map(Self.localURL)
        ShelfManager.shared.addFromOutside(urls.map { ShelfItem(url: $0) }, forceNewShelf: newShelf)
        return .result()
    }

    /// Files from Finder come with their location; anything else is written to Stash's temporary folder.
    private static func localURL(_ file: IntentFile) throws -> URL {
        if let url = file.fileURL, FileManager.default.fileExists(atPath: url.path) { return url }
        let folder = StashPaths.standard.temporary
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = StashPaths.uniqueURL(in: folder, name: file.filename)
        try file.data.write(to: url)
        return url
    }
}

struct GetShelfFilesIntent: AppIntent {
    static let title = LocalizedStringResource("Get Files from Current Shelf")
    static let description = IntentDescription(LocalizedStringResource("Returns the files from the currently visible Stash shelf so you can pass them to other actions."))

    @Parameter(title: LocalizedStringResource("Close shelf"), description: LocalizedStringResource("Closes the shelf automatically after the action completes."), default: false)
    var closeShelf: Bool

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let manager = ShelfManager.shared
        let visible = manager.visibleShelves
        guard let shelf = visible.first(where: { $0 === manager.lastActive }) ?? visible.last else {
            throw StashIntentError.noVisibleShelf
        }
        let files = shelf.model.items.map { IntentFile(fileURL: $0.url, filename: $0.url.lastPathComponent) }
        guard !files.isEmpty else { throw StashIntentError.cannotResolve }
        if closeShelf { shelf.close() }
        return .result(value: files)
    }
}

struct ReopenLastShelfIntent: AppIntent {
    static let title = LocalizedStringResource("Reopen Last Shelf")
    static let description = IntentDescription(LocalizedStringResource("Reopen your most recently closed shelf."))

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = ShelfManager.shared
        guard let record = manager.recent.first else {
            return .result(dialog: IntentDialog(LocalizedStringResource("There's no recently closed shelf to reopen.")))
        }
        guard record.paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return .result(dialog: IntentDialog(LocalizedStringResource("Shelf can't be reopened because its items are no longer available.")))
        }
        manager.reopenLastClosed()
        return .result(dialog: "")
    }
}

enum StashIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noVisibleShelf, cannotResolve

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noVisibleShelf: LocalizedStringResource("Cannot get files as there is no visible Stash shelf.")
        case .cannotResolve: LocalizedStringResource("Failed to obtain files from shelf.")
        }
    }
}

struct StashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NewShelfIntent(), phrases: [
            "New \(.applicationName) shelf",
            "Start a new \(.applicationName) shelf",
            "Create new \(.applicationName) shelf",
            "Open a new shelf in \(.applicationName)",
        ], shortTitle: LocalizedStringResource("New Shelf"), systemImageName: "plus.rectangle.on.rectangle")
        AppShortcut(intent: NewClipboardShelfIntent(), phrases: [
            "New \(.applicationName) shelf from clipboard",
            "Clipboard to \(.applicationName) shelf",
            "Create shelf from clipboard in \(.applicationName)",
        ], shortTitle: LocalizedStringResource("New Clipboard Shelf"), systemImageName: "doc.on.clipboard")
        AppShortcut(intent: AddFilesToShelfIntent(), phrases: [
            "Add to \(.applicationName) shelf",
            "Add files to \(.applicationName)",
            "Add selection to \(.applicationName)",
            "Add items to \(.applicationName)",
        ], shortTitle: LocalizedStringResource("Add Files to Shelf"), systemImageName: "tray.and.arrow.down")
        AppShortcut(intent: GetShelfFilesIntent(), phrases: [
            "Get files from \(.applicationName) shelf",
            "Retrieve files from \(.applicationName)",
            "Fetch items from \(.applicationName) shelf",
        ], shortTitle: LocalizedStringResource("Get Files from Current Shelf"), systemImageName: "tray.and.arrow.up")
        AppShortcut(intent: ReopenLastShelfIntent(), phrases: [
            "Reopen last \(.applicationName) shelf",
            "Open last \(.applicationName) shelf",
            "Restore last \(.applicationName) shelf",
        ], shortTitle: LocalizedStringResource("Reopen Last Shelf"), systemImageName: "arrow.uturn.backward")
    }
}
