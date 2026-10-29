import AppKit
import SwiftUI
import StashCore

/// The "Add to Stash" entry of the Services menu.
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    @objc func addToStash(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let items = PasteboardImporter.items(from: pasteboard) { promised in ShelfManager.shared.addFromOutside(promised) }
        if items.isEmpty {
            error.pointee = L("The operation cannot be performed with this type of files") as NSString
        } else {
            ShelfManager.shared.addFromOutside(items)
        }
    }
}

/// Custom Scripts: UNIX scripts and Automator workflows in Stash's Scripts folder appear as file actions.
/// Each one gets the shelf's file paths as arguments.
enum ScriptActions {
    struct Options: Codable, Equatable {
        /// Put what the script prints on the clipboard.
        var copyOutput = false
        var closeShelf = true
    }

    static var folder: URL { StashPaths.standard.scripts }
    private static let optionsKey = "scriptOptions"

    static func scripts() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.filter(isRunnable).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static var actions: [ShelfAction] {
        scripts().map { url in
            ShelfAction(id: "script:" + url.lastPathComponent, title: title(of: url), symbol: url.pathExtension == "workflow" ? "gearshape.2" : "terminal",
                        category: .scripts, applies: { !$0.isEmpty }) { c, items in run(url, on: items, in: c) }
        }
    }

    static func title(of url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    private static func isRunnable(_ url: URL) -> Bool {
        ["workflow", "scpt", "applescript"].contains(url.pathExtension) || FileManager.default.isExecutableFile(atPath: url.path)
    }

    // MARK: Options

    static func options(for url: URL) -> Options {
        let all = (UserDefaults.standard.data(forKey: optionsKey)).flatMap { try? JSONDecoder().decode([String: Options].self, from: $0) } ?? [:]
        return all[url.lastPathComponent] ?? Options()
    }

    static func setOptions(_ options: Options, for url: URL) {
        var all = (UserDefaults.standard.data(forKey: optionsKey)).flatMap { try? JSONDecoder().decode([String: Options].self, from: $0) } ?? [:]
        all[url.lastPathComponent] = options
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: optionsKey)
    }

    // MARK: Managing

    /// Copies a script into the Scripts folder and makes it executable.
    @discardableResult
    static func importScript(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = StashPaths.uniqueURL(in: folder, name: url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: target)
        if !["workflow", "scpt", "applescript"].contains(target.pathExtension) {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        }
        guard isRunnable(target) else {
            try? FileManager.default.trashItem(at: target, resultingItemURL: nil)
            throw FileOperationError.unsupportedFiles
        }
        return target
    }

    // MARK: Running

    struct Outcome: Sendable {
        let status: Int32
        let output: String
        let errors: String
    }

    static func run(_ script: URL, on items: [ShelfItem], in c: ShelfController) {
        let paths = items.map(\.url.path)
        let options = options(for: script)
        withAnimation { c.model.busy = L("Executing script...") }
        Task {
            let outcome = try? await Background.run { try execute(script, paths: paths) }
            withAnimation { c.model.busy = nil }
            guard let outcome, outcome.status == 0 else {
                return c.alert(L("Failed to execute script"), outcome?.errors.isEmpty == false ? outcome!.errors : title(of: script))
            }
            if options.copyOutput {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(outcome.output, forType: .string)
                c.showToast(L("Content has been copied to your clipboard"))
            }
            if options.closeShelf, !c.willCloseAfterAction { c.close() } else { c.finishAction() }
        }
    }

    nonisolated static func execute(_ script: URL, paths: [String]) throws -> Outcome {
        let process = Process()
        switch script.pathExtension {
        case "workflow":
            process.executableURL = URL(filePath: "/usr/bin/automator")
            process.arguments = ["-i", paths.joined(separator: "\n"), script.path]
        case "scpt", "applescript":
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = [script.path] + paths
        default:
            process.executableURL = script
            process.arguments = paths
        }
        process.currentDirectoryURL = paths.first.map { URL(filePath: $0).deletingLastPathComponent() }
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // Read before waiting so a chatty script can't fill the pipe and stall.
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(status: process.terminationStatus,
                       output: String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                       errors: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
