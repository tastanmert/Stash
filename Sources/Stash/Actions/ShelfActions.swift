import AppKit
import SwiftUI
import StashCore

enum ActionCategory: CaseIterable {
    case image, pdf, text, general, custom, scripts, share

    var title: String {
        switch self {
        case .general: L("General Actions")
        case .image: L("Image Actions")
        case .pdf: L("PDF Actions")
        case .text: L("Text Actions")
        case .custom: L("Custom Actions")
        case .scripts: L("Custom Scripts")
        case .share: L("Share Actions")
        }
    }
}

/// Something you can do with the files on a shelf: from the action menu or as an instant action.
struct ShelfAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let category: ActionCategory
    /// Whether the action can handle these items.
    let applies: ([ShelfItem]) -> Bool
    /// From the menu, the action first shows an options page inside the shelf.
    /// As an instant action it runs with the options used last time.
    var hasOptions = false
    /// For share actions: the system service, whose icon is shown in Settings.
    var service: NSSharingService.Name?
    let perform: (ShelfController, [ShelfItem]) -> Void

    var image: NSImage? { service.flatMap { NSSharingService(named: $0)?.image } }

    /// Runs the action from a menu: options page first when there is one.
    func invoke(on controller: ShelfController, items: [ShelfItem]) {
        RecentActions.record(id)
        if hasOptions { controller.showPage(.action(id)) } else { perform(controller, items) }
    }
}

private extension Array where Element == ShelfItem {
    var images: [ShelfItem] { filter(\.isImage) }
    var pdfs: [ShelfItem] { filter { $0.type?.conforms(to: .pdf) ?? false } }
    var texts: [ShelfItem] { filter { $0.text != nil || ($0.type?.conforms(to: .text) ?? false) } }
}

enum ActionCatalog {
    static let all: [ShelfAction] = [
        // General
        ShelfAction(id: "getInfo", title: L("Get Info"), symbol: "info.circle.fill", category: .general, applies: { !$0.isEmpty }) { c, items in
            guard items.count <= 5 || c.confirm(L("Get Info"), L("Get info will open %d windows. Do you want to continue?", items.count)) else { return }
            let pb = NSPasteboard(name: .init("Stash.GetInfo"))
            pb.clearContents()
            pb.writeObjects(items.map { $0.url as NSURL })
            NSPerformService("Finder/Show Info", pb)
            c.finishAction()
        },
        ShelfAction(id: "batchRename", title: L("Rename"), symbol: "character.cursor.ibeam", category: .general,
                    applies: { !$0.isEmpty }, hasOptions: true) { c, items in
            let rule = ActionOptions.renameRule
            do {
                c.relocate(items, to: try FileOperations.batchRename(items.map(\.url), rule: rule))
                if ActionOptions.renameClosesShelf { c.close() } else { c.finishAction() }
            } catch {
                c.alert(L("Could not perform the action"), L("Failed to rename the files. Please ensure the files are accessible to Stash and try again."))
            }
        },
        ShelfAction(id: "zip", title: L("Create ZIP Archive"), symbol: "doc.zipper", category: .general,
                    applies: { !$0.isEmpty }, hasOptions: true) { c, items in
            let urls = items.map(\.url), name = ActionOptions.zipName(for: items)
            ActionRunner.run(c, busy: L("Compressing..."), outputFolder: L("ZIP Archives")) { folder in
                [try FileOperations.zip(urls, name: name, in: folder)]
            }
        },
        ShelfAction(id: "copyPath", title: L("Copy Path"), symbol: "doc.on.doc.fill", category: .general, applies: { !$0.isEmpty }) { c, items in
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(items.map(\.url.path).joined(separator: "\n"), forType: .string)
            c.showToast(L("Copied path to clipboard"))
            c.finishAction()
        },
        ShelfAction(id: "copyTo", title: L("Copy to..."), symbol: "arrow.right.circle.fill", category: .general, applies: { !$0.isEmpty }) { c, items in
            ActionRunner.transfer(c, items, move: false)
        },
        ShelfAction(id: "moveTo", title: L("Move to..."), symbol: "arrow.right.circle", category: .general, applies: { !$0.isEmpty }) { c, items in
            ActionRunner.transfer(c, items, move: true)
        },
        ShelfAction(id: "trash", title: L("Move to Trash"), symbol: "trash.fill", category: .general, applies: { !$0.isEmpty }) { c, items in
            var trashed: Set<UUID> = []
            for item in items where (try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)) != nil { trashed.insert(item.id) }
            c.remove(trashed)
            if trashed.count < items.count { c.alert(L("Could not perform the action"), L("Some files could not be moved")) } else { c.finishAction() }
        },

        // Images
        ShelfAction(id: "redact", title: L("Redact Text..."), symbol: "text.redaction", category: .image,
                    applies: { !$0.images.isEmpty }) { c, items in
            for item in items.images { RedactWindow.show(item.url, from: c) }
        },
        ShelfAction(id: "resize", title: L("Resize"), symbol: "arrow.down.right.and.arrow.up.left", category: .image,
                    applies: { !$0.images.isEmpty }, hasOptions: true) { c, items in
            let urls = items.images.map(\.url), mode = ActionOptions.resizeMode, copy = ActionOptions.resizeCopy
            ActionRunner.run(c, busy: L("Resizing..."), outputFolder: L("Resized Images"), replacesSources: !copy) { folder in
                try FileOperations.resizeImages(urls, mode: mode, replacing: !copy, in: folder)
            }
        },
        ShelfAction(id: "convert", title: L("Convert Format"), symbol: "arrow.2.squarepath", category: .image,
                    applies: { !$0.images.isEmpty }, hasOptions: true) { c, items in
            let urls = items.images.map(\.url), format = ActionOptions.convertFormat, quality = ActionOptions.convertQuality
            ActionRunner.run(c, busy: L("Converting..."), outputFolder: L("Converted Images")) { folder in
                try FileOperations.convertImages(urls, to: format, quality: quality, in: folder)
            }
        },
        ShelfAction(id: "compressImages", title: L("Compress"), symbol: "rectangle.compress.vertical", category: .image,
                    applies: { !$0.images.isEmpty }, hasOptions: true) { c, items in
            let urls = items.images.map(\.url), quality = ActionOptions.compressQuality, copy = ActionOptions.compressCopy
            ActionRunner.run(c, busy: L("Compressing..."), outputFolder: L("Compressed Images"), replacesSources: !copy) { folder in
                try FileOperations.compressImages(urls, quality: quality, replacing: !copy, in: folder)
            }
        },
        ShelfAction(id: "removeMetadata", title: L("Remove Metadata"), symbol: "tag.slash.fill", category: .image,
                    applies: { !$0.images.isEmpty }) { c, items in
            let urls = items.images.map(\.url)
            ActionRunner.run(c, busy: L("Processing..."), outputFolder: L("Removed Images Metadata")) { folder in
                try FileOperations.removeMetadata(urls, in: folder)
            }
        },
        ShelfAction(id: "ocr", title: L("Extract Text"), symbol: "doc.text.magnifyingglass", category: .image,
                    applies: { !$0.images.isEmpty }, hasOptions: true) { c, items in
            ActionRunner.extractText(c, items.images)
        },
        ShelfAction(id: "imagesToPDF", title: L("Create PDF"), symbol: "doc.badge.plus", category: .image,
                    applies: { !$0.images.isEmpty }, hasOptions: true) { c, items in
            let urls = items.images.map(\.url)
            ActionRunner.run(c, busy: L("Processing..."), outputFolder: L("PDF from Images")) { folder in
                [try FileOperations.imagesToPDF(urls, in: folder)]
            }
        },
        ShelfAction(id: "stitchImages", title: L("Stitch"), symbol: "rectangle.split.1x2", category: .image,
                    applies: { $0.images.count >= 2 }, hasOptions: true) { c, items in
            let urls = items.images.map(\.url)
            ActionRunner.run(c, busy: L("Processing..."), outputFolder: L("Stitched Images")) { folder in
                [try FileOperations.stitchImages(urls, in: folder)]
            }
        },
        ShelfAction(id: "desktopPicture", title: L("Set Desktop Picture"), symbol: "macwindow.on.rectangle", category: .image,
                    applies: { $0.count == 1 && $0[0].isImage }) { c, items in
            do {
                for screen in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(items[0].url, for: screen) }
                c.finishAction()
            } catch {
                c.alert(L("Could not perform the action"), error.localizedDescription)
            }
        },

        // PDF
        ShelfAction(id: "stitchPDF", title: L("Stitch PDF's"), symbol: "doc.on.doc.fill", category: .pdf,
                    applies: { $0.pdfs.count >= 2 }) { c, items in
            let urls = items.pdfs.map(\.url)
            ActionRunner.run(c, busy: L("Processing..."), outputFolder: L("Stitch PDFs")) { folder in
                [try FileOperations.stitchPDFs(urls, in: folder)]
            }
        },
        ShelfAction(id: "protectPDF", title: L("Protect Using Password"), symbol: "lock.doc", category: .pdf,
                    applies: { $0.count == 1 && !$0.pdfs.isEmpty }, hasOptions: true) { c, _ in
            // A password is never stored, so this always asks for one.
            c.showPage(.action("protectPDF"))
        },

        // Text
        ShelfAction(id: "copyText", title: L("Copy Text Content"), symbol: "doc.text", category: .text,
                    applies: { !$0.texts.isEmpty }) { c, items in
            let text = items.texts.compactMap { $0.text ?? (try? String(contentsOf: $0.url, encoding: .utf8)) }.joined(separator: "\n\n")
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            c.showToast(L("Content has been copied to your clipboard"))
            c.finishAction()
        },

        // Share
        share("airdrop", L("AirDrop"), "dot.radiowaves.up.forward", .sendViaAirDrop),
        share("mail", L("Mail"), "envelope", .composeEmail),
        share("messages", L("Messages"), "message", .composeMessage),
        share("reminders", L("Reminders"), "checklist", NSSharingService.Name("com.apple.reminders.sharingextension")),
    ]

    /// Built-in actions followed by the user's custom actions and scripts.
    static var everything: [ShelfAction] { all + CustomActionStore.shared.shelfActions + ScriptActions.actions }

    static func action(_ id: String) -> ShelfAction? {
        if id.hasPrefix("custom:") { return CustomActionStore.shared.shelfActions.first { $0.id == id } }
        if id.hasPrefix("script:") { return ScriptActions.actions.first { $0.id == id } }
        return all.first { $0.id == id }
    }

    static func applicable(to items: [ShelfItem], in category: ActionCategory? = nil) -> [ShelfAction] {
        everything.filter { (category == nil || $0.category == category) && $0.applies(items) }
    }

    private static func share(_ id: String, _ title: String, _ symbol: String, _ name: NSSharingService.Name) -> ShelfAction {
        ShelfAction(id: id, title: title, symbol: symbol, category: .share, applies: { !$0.isEmpty }, service: name) { c, items in
            guard let service = NSSharingService(named: name), service.canPerform(withItems: items.map(\.url)) else {
                return c.alert(L("Could not perform the action"), L("The operation cannot be performed with this type of files"))
            }
            service.perform(withItems: items.map(\.url))
            c.finishAction()
        }
    }

    /// The system share sheet with every available service.
    static func showSharePicker(for c: ShelfController, items: [ShelfItem]) {
        guard let view = c.panel.contentView else { return }
        let picker = NSSharingServicePicker(items: items.map(\.url))
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 30, width: 1, height: 1), of: view, preferredEdge: .minY)
    }
}

/// The last few actions used, shown at the top of the menu while ⌥ is held.
enum RecentActions {
    private static let key = "recentActions"
    static var ids: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func record(_ id: String) {
        var list = ids.filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(3)), forKey: key)
    }
}

/// Runs file operations off the main actor and puts their results where the user wants them.
enum ActionRunner {
    enum OutputPlacement: String, CaseIterable, Identifiable {
        case currentShelf, newShelf, finder
        var id: String { rawValue }
        var title: String {
            switch self {
            case .currentShelf: L("Current Shelf")
            case .newShelf: L("New Shelf")
            case .finder: L("Finder")
            }
        }
    }

    /// - Parameters:
    ///   - outputFolder: subfolder of Stash's output folder for the results, unless `folder` names another place.
    ///   - placement: where to show the results; the Settings choice when nil.
    static func run(_ c: ShelfController, busy: String, outputFolder: String, folder custom: URL? = nil,
                    placement: OutputPlacement? = nil, replacesSources: Bool = false,
                    work: @escaping @Sendable (URL) throws -> [URL]) {
        let folder = custom ?? StashPaths.standard.output.appending(path: outputFolder, directoryHint: .isDirectory)
        withAnimation { c.model.busy = busy }
        Task {
            do {
                let urls = try await Background.run { try work(folder) }
                withAnimation { c.model.busy = nil }
                deliver(urls, from: c, replacedSources: replacesSources, placement: placement)
            } catch {
                withAnimation { c.model.busy = nil }
                c.alert(L("Could not perform the action"), message(for: error))
            }
        }
    }

    private static func deliver(_ urls: [URL], from c: ShelfController, replacedSources: Bool, placement chosen: OutputPlacement? = nil) {
        if replacedSources {
            // The originals were rewritten (and maybe renamed); point the shelf at the new files.
            c.replaceItems(with: urls)
            return c.finishAction()
        }
        var placement: OutputPlacement = chosen ?? Prefs.value(Pref.actionOutput, default: .currentShelf)
        if placement == .currentShelf, c.willCloseAfterAction { placement = .newShelf }
        let items = urls.map { ShelfItem(url: $0) }
        switch placement {
        case .currentShelf: c.add(items)
        case .newShelf: ShelfManager.shared.newShelf(items: items, at: .near(c.panel.frame))
        case .finder: NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
        c.finishAction()
    }

    static func transfer(_ c: ShelfController, _ items: [ShelfItem], move: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Select Folder")
        panel.message = move ? L("Select the folder where the files should be moved to") : L("Select the folder where the files should be copied to")
        NSApp.activate()
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let results = try FileOperations.transfer(items.map(\.url), to: destination, move: move)
            if move { c.relocate(items, to: results) }
            c.finishAction()
        } catch {
            c.alert(L("Could not perform the action"), move ? L("Some files could not be moved") : error.localizedDescription)
        }
    }

    static func extractText(_ c: ShelfController, _ items: [ShelfItem], toFile: Bool = ActionOptions.ocrToFile) {
        withAnimation { c.model.busy = L("Processing...") }
        Task {
            let urls = items.map(\.url)
            let texts = (try? await Background.run { try FileOperations.recognizeText(in: urls) }) ?? []
            withAnimation { c.model.busy = nil }
            guard texts.contains(where: { !$0.isEmpty }) else {
                return c.alert(L("Could not perform the action"), items.count == 1 ? L("Could not find text in the image") : L("Could not find text in the images"))
            }
            if toFile {
                let folder = StashPaths.standard.output.appending(path: L("Extracted Text From Images"), directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var urls: [URL] = []
                for (item, text) in zip(items, texts) where !text.isEmpty {
                    let url = StashPaths.uniqueURL(in: folder, name: item.url.deletingPathExtension().lastPathComponent + ".txt")
                    if (try? Data(text.utf8).write(to: url)) != nil { urls.append(url) }
                }
                deliver(urls, from: c, replacedSources: false)
            } else {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(texts.filter { !$0.isEmpty }.joined(separator: "\n\n"), forType: .string)
                c.showToast(L("Extracted text has been copied to your clipboard"))
                c.finishAction()
            }
        }
    }

    static func message(for error: any Error) -> String {
        switch error as? FileOperationError {
        case .unsupportedFiles: L("The operation cannot be performed with this type of files")
        case .alreadyProtected: L("The PDF is already protected with a password.")
        case .noTextFound: L("Could not find text in the image")
        case .toolFailed(let text) where !text.isEmpty: text
        default: error.localizedDescription
        }
    }
}

/// Runs work on the concurrent pool so long file operations never block the shelf.
nonisolated enum Background {
    @concurrent static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T { try work() }
}

/// Options of the configurable actions, remembered between uses (passwords never are).
enum ActionOptions {
    enum ResizePreset: String, CaseIterable, Identifiable {
        case p25, p50, p75, percent, pixels
        var id: String { rawValue }
        var title: String {
            switch self {
            case .p25: "25%"
            case .p50: "50%"
            case .p75: "75%"
            case .percent: L("Custom (percent)")
            case .pixels: L("Custom (pixels)")
            }
        }
    }

    static let resizePresetKey = "action.resize.preset"
    static let resizeWidthKey = "action.resize.width"
    static let resizeHeightKey = "action.resize.height"
    static let resizeCopyKey = "action.resize.copy"
    static let convertFormatKey = "action.convert.format"
    static let convertQualityKey = "action.convert.quality"
    static let compressQualityKey = "action.compress.quality"
    static let compressCopyKey = "action.compress.copy"
    static let ocrToFileKey = "action.ocr.toFile"

    static func register() {
        UserDefaults.standard.register(defaults: [
            resizePresetKey: ResizePreset.p50.rawValue, resizeWidthKey: 1920, resizeHeightKey: 1080, resizeCopyKey: true,
            convertFormatKey: FileOperations.ImageFormat.jpeg.rawValue, convertQualityKey: 0.85,
            compressQualityKey: 0.6, compressCopyKey: true, ocrToFileKey: false,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var resizeMode: FileOperations.ResizeMode {
        let w = d.integer(forKey: resizeWidthKey), h = d.integer(forKey: resizeHeightKey)
        switch ResizePreset(rawValue: d.string(forKey: resizePresetKey) ?? "") ?? .p50 {
        case .p25: return .percent(width: 25, height: 25)
        case .p50: return .percent(width: 50, height: 50)
        case .p75: return .percent(width: 75, height: 75)
        case .percent: return .percent(width: max(1, w), height: max(1, h))
        case .pixels: return .maxPixels(width: max(1, w), height: max(1, h))
        }
    }

    static var resizeCopy: Bool { d.bool(forKey: resizeCopyKey) }
    static var convertFormat: FileOperations.ImageFormat { .init(rawValue: d.string(forKey: convertFormatKey) ?? "") ?? .jpeg }
    static var convertQuality: Double { d.double(forKey: convertQualityKey) }
    static var compressQuality: Double { d.double(forKey: compressQualityKey) }
    static var compressCopy: Bool { d.bool(forKey: compressCopyKey) }
    static var ocrToFile: Bool { d.bool(forKey: ocrToFileKey) }

    static let redactReplaceKey = "action.redact.replace"
    static let redactRevealKey = "action.redact.reveal"
    static let renameRuleKey = "action.rename.rule"
    static let renameClosesKey = "action.rename.closeShelf"

    /// Batch Rename's last settings.
    static var renameRule: RenameRule {
        get { d.data(forKey: renameRuleKey).flatMap { try? JSONDecoder().decode(RenameRule.self, from: $0) } ?? RenameRule() }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: renameRuleKey) }
    }

    static var renameClosesShelf: Bool { d.bool(forKey: renameClosesKey) }

    /// "Report.pdf" → "Report", several files → "Archive".
    static func zipName(for items: [ShelfItem]) -> String {
        items.count == 1 ? items[0].url.deletingPathExtension().lastPathComponent : L("Archive")
    }
}
