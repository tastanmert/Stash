import AppKit
import SwiftUI
import StashCore

/// An action the user made from a template, with its parameters fixed (Settings ▸ Custom Actions).
/// It shows up in the shelf's action menu and among the instant actions like a built-in one.
struct CustomAction: Codable, Identifiable, Equatable {
    enum Template: String, Codable, CaseIterable, Identifiable {
        case move, copy, zip, openWith, rename, resize, compress, convert, imagesToPDF, ocr, stitch
        var id: String { rawValue }

        var title: String {
            switch self {
            case .move: L("Move Files to Folder")
            case .copy: L("Copy Files to Folder")
            case .zip: L("Create ZIP Archive")
            case .openWith: L("Open with Application")
            case .rename: L("Rename Files")
            case .resize: L("Resize Images")
            case .compress: L("Compress Images")
            case .convert: L("Convert Images")
            case .imagesToPDF: L("Convert Images to PDF")
            case .ocr: L("Extract Text from Image")
            case .stitch: L("Stitch Images")
            }
        }

        var description: String {
            switch self {
            case .move: L("Move files to the specified destination.")
            case .copy: L("Copy files to the specified destination.")
            case .zip: L("Create a ZIP archive in the specified destination folder.")
            case .openWith: L("Opens files with the specified application.")
            case .rename: L("Rename multiple files using find-and-replace matching or a custom naming format.")
            case .resize: L("Modify the image's size by selecting a predefined option or specifying your own dimensions.")
            case .compress: L("Compress images and photos for displaying on web pages, sharing on social networks or sending by email.")
            case .convert: L("Convert the format of an image to the specified format.")
            case .imagesToPDF: L("Create a single PDF file from multiple images.")
            case .ocr: L("Analyzes the images and extracts the text onto your clipboard or creates new text files containing the extracted text.")
            case .stitch: L("Create a single image from multiple images.")
            }
        }

        var symbol: String {
            switch self {
            case .move: "arrow.right.circle"
            case .copy: "arrow.right.circle.fill"
            case .zip: "doc.zipper"
            case .openWith: "arrow.up.forward.app"
            case .rename: "character.cursor.ibeam"
            case .resize: "arrow.down.right.and.arrow.up.left"
            case .compress: "rectangle.compress.vertical"
            case .convert: "arrow.triangle.2.circlepath"
            case .imagesToPDF: "doc.richtext"
            case .ocr: "text.viewfinder"
            case .stitch: "rectangle.split.1x2"
            }
        }

        var forImages: Bool { [.resize, .compress, .convert, .imagesToPDF, .ocr, .stitch].contains(self) }
        /// Templates whose result is new files that are shown somewhere.
        var makesFiles: Bool { [.zip, .resize, .compress, .convert, .imagesToPDF, .stitch].contains(self) }
    }

    var id = UUID()
    var template: Template
    var name: String
    /// Destination (move, copy) or "Save in" folder of the generated files; nil saves in Stash's own folder.
    var folder: String?
    var app: String?
    var rename = RenameRule()
    var resizePreset = ActionOptions.ResizePreset.pixels.rawValue
    var width = 500
    var height = 500
    var createCopy = true
    var quality = 0.8
    var format = FileOperations.ImageFormat.jpeg.rawValue
    var output = ActionRunner.OutputPlacement.currentShelf.rawValue
    var ocrToFile = false

    init(template: Template) {
        self.template = template
        name = template.title
    }

    var shelfActionID: String { "custom:\(id.uuidString)" }
    var folderURL: URL? { folder.map { URL(filePath: $0, directoryHint: .isDirectory) } }
    var placement: ActionRunner.OutputPlacement { .init(rawValue: output) ?? .currentShelf }

    var resizeMode: FileOperations.ResizeMode {
        switch ActionOptions.ResizePreset(rawValue: resizePreset) ?? .pixels {
        case .p25: .percent(width: 25, height: 25)
        case .p50: .percent(width: 50, height: 50)
        case .p75: .percent(width: 75, height: 75)
        case .percent: .percent(width: max(1, width), height: max(1, height))
        case .pixels: .maxPixels(width: max(1, width), height: max(1, height))
        }
    }

    /// One line describing what the action does, shown under its name in Settings (Markdown).
    var summary: String {
        let folderName = folderURL.map { FileManager.default.displayName(atPath: $0.path) }
        let percent = "\(Int((quality * 100).rounded()))%"
        switch template {
        case .move: return folderName.map { L("Move to '%@'", $0) } ?? template.title
        case .copy: return folderName.map { L("Copy to '%@'", $0) } ?? template.title
        case .zip: return folderName.map { L("Save to '%@'", $0) } ?? L("Create ZIP archive")
        case .openWith: return app.map { L("Open with '%@'", FileManager.default.displayName(atPath: $0).replacingOccurrences(of: ".app", with: "")) } ?? template.title
        case .rename:
            return rename.mode == .custom ? L("Rename files with custom format `%@`", rename.format)
                                          : L("Rename files by replacing **%@** with **%@**", rename.find, rename.replacement)
        case .resize:
            return switch resizeMode {
            case .maxPixels(let w, let h): L("Resize images to max. %dpx width, %dpx height", w, h)
            case .percent(let w, let h): L("Resize images to %d%% width, %d%% height", w, h)
            }
        case .compress: return L("Compress images at %@ quality level", percent)
        case .convert: return L("Convert images to %@ at %@ quality level", format.uppercased(), percent)
        case .imagesToPDF: return L("Convert images to PDF")
        case .ocr: return ocrToFile ? L("Extract text from image to text file") : L("Extract text from image to clipboard")
        case .stitch: return L("Stitch images")
        }
    }

    /// Why the action can't be saved yet, or nil.
    var problem: String? {
        switch template {
        case .move where folder == nil, .copy where folder == nil: L("Please select a destination and try again.")
        case .openWith where app == nil: L("No application has been specified. Update the configuration and try again.")
        case .rename:
            switch rename.validate() {
            case .missing: L("Field cannot be empty")
            case .invalidCharacter(let c): L("The following character is not allowed in the custom format: \"%@\"", c)
            case nil: nil
            }
        case .resize where width < 1 || height < 1: L("The provided width and/or height are invalid. Please try again with different values.")
        default: nil
        }
    }
}

/// The user's custom actions, kept in the defaults as JSON.
@Observable
final class CustomActionStore {
    static let shared = CustomActionStore()
    private static let key = "customActions"

    var actions: [CustomAction] {
        didSet { if let data = try? JSONEncoder().encode(actions) { UserDefaults.standard.set(data, forKey: Self.key) } }
    }

    private init() {
        actions = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([CustomAction].self, from: $0) } ?? []
    }

    func save(_ action: CustomAction) {
        if let i = actions.firstIndex(where: { $0.id == action.id }) { actions[i] = action } else { actions.append(action) }
    }

    func delete(_ action: CustomAction) { actions.removeAll { $0.id == action.id } }

    /// The custom actions as shelf actions, for menus and instant actions.
    var shelfActions: [ShelfAction] {
        actions.map { custom in
            ShelfAction(id: custom.shelfActionID, title: custom.name, symbol: custom.template.symbol, category: .custom,
                        applies: { items in custom.template.forImages ? items.contains(where: \.isImage) : !items.isEmpty }) { c, items in
                CustomActionRunner.perform(custom, on: c, items: custom.template.forImages ? items.filter(\.isImage) : items)
            }
        }
    }
}

enum CustomActionRunner {
    static func perform(_ action: CustomAction, on c: ShelfController, items: [ShelfItem]) {
        if let problem = action.problem { return c.alert(L("Could not perform the action"), problem) }
        let urls = items.map(\.url)
        let folder = action.folderURL, placement = action.placement
        switch action.template {
        case .move, .copy:
            guard let folder else { return }
            do {
                let results = try FileOperations.transfer(urls, to: folder, move: action.template == .move)
                if action.template == .move { c.relocate(items, to: results) }
                c.finishAction()
            } catch {
                c.alert(L("Could not perform the action"), ActionRunner.message(for: error))
            }
        case .openWith:
            guard let app = action.app, FileManager.default.fileExists(atPath: app) else {
                return c.alert(L("Could not perform the action"), L("The specified application cannot be found. Update the configuration and try again."))
            }
            c.open(items, with: URL(filePath: app))
        case .rename:
            do {
                c.relocate(items, to: try FileOperations.batchRename(urls, rule: action.rename))
                c.finishAction()
            } catch {
                c.alert(L("Could not perform the action"), L("Failed to rename the files. Please ensure the files are accessible to Stash and try again."))
            }
        case .zip:
            let name = ActionOptions.zipName(for: items)
            ActionRunner.run(c, busy: L("Compressing..."), outputFolder: L("ZIP Archives"), folder: folder, placement: placement) { out in
                [try FileOperations.zip(urls, name: name, in: out)]
            }
        case .resize:
            let mode = action.resizeMode, copy = action.createCopy
            ActionRunner.run(c, busy: L("Resizing..."), outputFolder: L("Resized Images"), folder: folder, placement: placement, replacesSources: !copy) { out in
                try FileOperations.resizeImages(urls, mode: mode, replacing: !copy, in: out)
            }
        case .compress:
            let quality = action.quality, copy = action.createCopy
            ActionRunner.run(c, busy: L("Compressing..."), outputFolder: L("Compressed Images"), folder: folder, placement: placement, replacesSources: !copy) { out in
                try FileOperations.compressImages(urls, quality: quality, replacing: !copy, in: out)
            }
        case .convert:
            let format = FileOperations.ImageFormat(rawValue: action.format) ?? .jpeg, quality = action.quality
            ActionRunner.run(c, busy: L("Converting..."), outputFolder: L("Converted Images"), folder: folder, placement: placement) { out in
                try FileOperations.convertImages(urls, to: format, quality: quality, in: out)
            }
        case .imagesToPDF:
            ActionRunner.run(c, busy: L("Processing..."), outputFolder: L("PDF from Images"), folder: folder, placement: placement) { out in
                [try FileOperations.imagesToPDF(urls, in: out)]
            }
        case .stitch:
            guard urls.count >= 2 else { return c.alert(L("Could not perform the action"), L("The operation cannot be performed with this type of files")) }
            ActionRunner.run(c, busy: L("Processing..."), outputFolder: L("Stitched Images"), folder: folder, placement: placement) { out in
                [try FileOperations.stitchImages(urls, in: out)]
            }
        case .ocr:
            ActionRunner.extractText(c, items, toFile: action.ocrToFile)
        }
    }
}

// MARK: - Settings

struct CustomActionsSettings: View {
    @State private var store = CustomActionStore.shared
    @State private var editing: CustomAction?
    @State private var showsScripts = false

    var body: some View {
        SettingsPage(title: L("Custom Actions"), description: L("Create actions with predefined parameters for frequent tasks. Custom actions work alongside built-in ones.")) {
            Section {
                if store.actions.isEmpty {
                    Text(L("No Custom Actions")).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                ForEach(store.actions) { action in
                    Button { editing = action } label: {
                        HStack(spacing: 10) {
                            SettingsIcon(symbol: action.template.symbol, tint: .gray).frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.name)
                                Text((try? AttributedString(markdown: action.summary)) ?? AttributedString(action.summary))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(L("Rename")) { editing = action }
                        Button(L("Delete")) { store.delete(action) }
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    Menu {
                        ForEach(CustomAction.Template.allCases) { template in
                            Button(template.title) { editing = CustomAction(template: template) }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
            }
            Section {
                SettingRow(symbol: "terminal", title: L("Custom scripts"), subtitle: L("Manage UNIX or Automator scripts to perform actions on the files in the shelf.")) {
                    Button(L("Manage...")) { showsScripts = true }
                }
            }
        }
        .sheet(item: $editing) { action in
            CustomActionEditor(action: action) { store.save($0) }
        }
        .sheet(isPresented: $showsScripts) { ScriptsSheet() }
    }
}

/// The sheet that sets up a custom action: its name and the template's parameters.
struct CustomActionEditor: View {
    @State var action: CustomAction
    let save: (CustomAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SettingsIcon(symbol: action.template.symbol, tint: .gray).frame(width: 22, height: 22)
                    Text(action.template.title).font(.system(size: 17, weight: .bold))
                }
                Text(action.template.description).font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 60)
            }
            .padding(.top, 22)
            Form {
                Section {
                    LabeledContent(L("Display name")) {
                        TextField("", text: $action.name).labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 240)
                    }
                }
                parameters
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Save")) {
                    if let problem = action.problem { return error = problem }
                    if action.name.trimmingCharacters(in: .whitespaces).isEmpty { action.name = action.template.title }
                    save(action)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 500, height: 453)
        .alert(L("Invalid Input"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("OK")) {}
        } message: {
            Text(error ?? "")
        }
    }

    @ViewBuilder private var parameters: some View {
        switch action.template {
        case .move, .copy:
            Section { FolderRow(title: L("Destination"), path: $action.folder, message: action.template == .move ? L("Select the folder where the files should be moved to") : L("Select the folder where the files should be copied to")) }
        case .zip:
            Section { FolderRow(title: L("Save in"), path: $action.folder) }
        case .openWith:
            Section { ApplicationRow(path: $action.app) }
        case .rename:
            RenameFields(rule: $action.rename)
        case .resize:
            Section {
                Picker(L("Dimension"), selection: $action.resizePreset) {
                    ForEach(ActionOptions.ResizePreset.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if action.resizePreset == ActionOptions.ResizePreset.pixels.rawValue || action.resizePreset == ActionOptions.ResizePreset.percent.rawValue {
                    let pixels = action.resizePreset == ActionOptions.ResizePreset.pixels.rawValue
                    NumberRow(title: pixels ? L("Max. width (in px)") : L("Width (in %)"), value: $action.width)
                    NumberRow(title: pixels ? L("Max. height (in px)") : L("Height (in %)"), value: $action.height)
                }
            }
            outputSection(copyable: true)
        case .compress:
            Section { QualityRow(quality: $action.quality) }
            outputSection(copyable: true)
        case .convert:
            Section {
                Picker(L("Target format"), selection: $action.format) {
                    ForEach(FileOperations.ImageFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0.rawValue) }
                }
                if FileOperations.ImageFormat(rawValue: action.format)?.isLossy == true { QualityRow(quality: $action.quality) }
            }
            outputSection(copyable: false)
        case .imagesToPDF, .stitch:
            outputSection(copyable: false)
        case .ocr:
            Section {
                Picker(L("Output"), selection: $action.ocrToFile) {
                    Text(L("Clipboard")).tag(false)
                    Text(L("Text File")).tag(true)
                }
            }
        }
    }

    /// Where the generated files go: the shelf, a new shelf or Finder, and in which folder.
    @ViewBuilder private func outputSection(copyable: Bool) -> some View {
        Section {
            Picker(L("Show output in"), selection: $action.output) {
                ForEach(ActionRunner.OutputPlacement.allCases) { Text($0.title).tag($0.rawValue) }
            }
            if copyable { Toggle(L("Create copy"), isOn: $action.createCopy).toggleStyle(.switch) }
            if !copyable || action.createCopy { FolderRow(title: L("Save in"), path: $action.folder) }
        }
    }
}

/// Batch Rename's fields, shared by the custom action editor and the shelf's options page.
struct RenameFields: View {
    @Binding var rule: RenameRule

    var body: some View {
        Section {
            Picker(L("Rename option"), selection: $rule.mode) {
                Text(L("Replace Text")).tag(RenameRule.Mode.replace)
                Text(L("Custom Format")).tag(RenameRule.Mode.custom)
            }
            .pickerStyle(.segmented)
            if rule.mode == .replace {
                FieldRow(title: L("Find"), text: $rule.find)
                FieldRow(title: L("Replace with"), text: $rule.replacement)
                Toggle(L("Case sensitive"), isOn: $rule.caseSensitive).toggleStyle(.switch)
            } else {
                FieldRow(title: L("Format"), text: $rule.format, prompt: "new_#counter")
                NumberRow(title: L("Counter start value"), value: $rule.counterStart)
            }
        } footer: {
            if rule.mode == .custom {
                Text((try? AttributedString(markdown: L("Available variables: `#counter`, `#date` & `#original`"))) ?? "")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

/// A labeled text field with a visible border, so an empty field still reads as one.
private struct FieldRow: View {
    let title: String
    @Binding var text: String
    var prompt = ""

    var body: some View {
        LabeledContent(title) {
            TextField("", text: $text, prompt: Text(prompt)).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 150)
        }
    }
}

private struct NumberRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            TextField("", value: $value, format: .number).labelsHidden().textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing).frame(width: 84)
        }
    }
}

private struct QualityRow: View {
    @Binding var quality: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Image quality"))
            Slider(value: $quality, in: 0.1...1)
            HStack {
                Text(L("Low Quality"))
                Spacer()
                Text(L("High Quality"))
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

/// A folder parameter: its name and a button that picks another one.
private struct FolderRow: View {
    let title: String
    @Binding var path: String?
    var message: String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if let path {
                    Text(FileManager.default.displayName(atPath: path)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Button(L("Select Folder")) { pick() }
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Select Folder")
        panel.message = message ?? ""
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}

private struct ApplicationRow: View {
    @Binding var path: String?

    var body: some View {
        LabeledContent(L("Application")) {
            HStack(spacing: 6) {
                if let path {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 18, height: 18)
                    Text(FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")).foregroundStyle(.secondary)
                }
                Button(path == nil ? L("Choose Application...") : L("Choose Different Application...")) { pick() }
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}
