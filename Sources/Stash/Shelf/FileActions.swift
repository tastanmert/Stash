import AppKit
import SwiftUI
import StashCore

/// File actions in the shelf menu.
enum FileActionMenu {
    /// Actions shown right in the action menu; the rest are under All Actions (Settings ▸ Customize action menu).
    static var mainMenuIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: Pref.mainMenuActions) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Pref.mainMenuActions) }
    }

    /// The last actions used, at the top of the menu while ⌥ is held.
    static func addRecent(to menu: NSMenu, controller c: ShelfController) {
        let items = c.targetItems
        guard !items.isEmpty, NSEvent.modifierFlags.contains(.option) else { return }
        let actions = RecentActions.ids.compactMap(ActionCatalog.action).filter { $0.applies(items) }
        guard !actions.isEmpty else { return }
        menu.addHeader(L("Recent Actions"))
        for action in actions { add(action, to: menu, controller: c, items: items) }
        menu.addItem(.separator())
    }

    /// The applicable actions placed in the main menu.
    static func addMainMenuActions(to menu: NSMenu, controller c: ShelfController) {
        let items = c.targetItems, ids = Set(mainMenuIDs)
        for action in ActionCatalog.everything where action.category != .share && ids.contains(action.id) && action.applies(items) {
            add(action, to: menu, controller: c, items: items)
        }
    }

    /// AirDrop, Mail, Messages and Reminders inline, then every other service under More.
    static func addShareActions(to menu: NSMenu, controller c: ShelfController) {
        let items = c.targetItems
        for action in ActionCatalog.applicable(to: items, in: .share) where action.image != nil {
            add(action, to: menu, controller: c, items: items)
            menu.items.last?.image = action.image
            menu.items.last?.showsImage()
        }
        let urls = items.map(\.url)
        let inline = Set(ActionCatalog.applicable(to: items, in: .share).compactMap { $0.service.flatMap(NSSharingService.init(named:))?.title })
        menu.addSubmenu(L("More"), symbol: "ellipsis") { sub in
            for service in (NSSharingService.self as SharingServiceListing.Type).sharingServices(forItems: urls) where !inline.contains(service.title) {
                let entry = NSMenuItem(service.menuItemTitle) { service.perform(withItems: urls); c.finishAction() }
                entry.image = service.image
                sub.addItem(entry)
            }
            if sub.items.isEmpty { sub.add(L("No content"), enabled: false) {} }
        }
    }

    /// Every other applicable action, grouped by category.
    static func addAllActions(to menu: NSMenu, controller c: ShelfController) {
        let items = c.targetItems
        menu.addSubmenu(L("All Actions"), symbol: "ellipsis") { sub in
            sub.autoenablesItems = false
            for category in ActionCategory.allCases where category != .share {
                let actions = ActionCatalog.applicable(to: items, in: category).filter { !mainMenuIDs.contains($0.id) }
                guard !actions.isEmpty else { continue }
                if !sub.items.isEmpty { sub.addItem(.separator()) }
                sub.addHeader(category.title)
                for action in actions { add(action, to: sub, controller: c, items: items) }
            }
            if sub.items.isEmpty { sub.add(L("No content"), enabled: false) {} }
        }
    }

    private static func add(_ action: ShelfAction, to menu: NSMenu, controller c: ShelfController, items: [ShelfItem]) {
        // "Rename..." for one file, "Batch Rename..." for several; both open the options page.
        if action.id == "batchRename" {
            return menu.add(items.count == 1 ? L("Rename...") : L("Batch Rename..."), symbol: action.symbol) { action.invoke(on: c, items: items) }
        }
        let title = action.title.hasSuffix("...") || !action.hasOptions ? action.title : action.title + "..."
        menu.add(title, symbol: action.symbol) { action.invoke(on: c, items: items) }
    }
}

// MARK: - Options pages inside the shelf

/// The options page of a configurable action, shown in the shelf's detail size.
struct ShelfActionPage: View {
    let id: String
    let model: ShelfModel
    let controller: ShelfController

    private var action: ShelfAction? { ActionCatalog.action(id) }
    private var items: [ShelfItem] { model.selectedItems }

    var body: some View {
        VStack(spacing: 0) {
            ShelfNavigationBar(title: action?.title ?? id, subtitle: subtitle, back: { controller.showPage(.stack) }) { EmptyView() }
            switch id {
            case "resize": ResizeOptions(run: run)
            case "convert": ConvertOptions(run: run)
            case "compressImages": CompressOptions(run: run)
            case "zip": ZipOptions(defaultName: ActionOptions.zipName(for: items)) { name, password in
                controller.showPage(.stack)
                let urls = items.map(\.url)
                ActionRunner.run(controller, busy: L("Compressing..."), outputFolder: L("ZIP Archives")) { folder in
                    [try FileOperations.zip(urls, name: name, password: password, in: folder)]
                }
            }
            case "protectPDF": PasswordOptions { password in
                controller.showPage(.stack)
                guard let url = items.first?.url else { return }
                ActionRunner.run(controller, busy: L("Processing..."), outputFolder: L("Password Protected PDFs")) { folder in
                    [try FileOperations.protectPDF(url, password: password, in: folder)]
                }
            }
            case "ocr": TextOptions(run: run)
            case "imagesToPDF":
                OptionsForm(description: L("Create a single PDF file from multiple images."), button: L("Create PDF"), run: run) { OutputPicker() }
            case "stitchImages":
                OptionsForm(description: L("Create a single image from multiple images."), button: L("Stitch"), run: run) { OutputPicker() }
            case "batchRename": BatchRenameOptions(items: items, run: run)
            default: Spacer()
            }
        }
    }

    private var subtitle: String {
        items.count == 1 ? items[0].displayName : L("%d items", items.count)
    }

    private func run() {
        controller.showPage(.stack)
        action?.perform(controller, items)
    }
}

/// Shared layout of an options page: a description, the controls and a primary button.
private struct OptionsForm<Content: View>: View {
    let description: String
    let button: String
    var disabled = false
    let run: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    content
                } header: {
                    Text(description).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button(button, action: run).keyboardShortcut(.defaultAction).disabled(disabled)
            }
            .padding(14)
        }
    }
}

private struct OutputPicker: View {
    @AppStorage(Pref.actionOutput) private var output = ActionRunner.OutputPlacement.currentShelf.rawValue

    var body: some View {
        Picker(L("Show output in"), selection: enumBinding($output, default: ActionRunner.OutputPlacement.currentShelf)) {
            ForEach(ActionRunner.OutputPlacement.allCases) { Text($0.title).tag($0) }
        }
    }
}

private struct ResizeOptions: View {
    let run: () -> Void
    @AppStorage(ActionOptions.resizePresetKey) private var preset = ActionOptions.ResizePreset.p50.rawValue
    @AppStorage(ActionOptions.resizeWidthKey) private var width = 1920
    @AppStorage(ActionOptions.resizeHeightKey) private var height = 1080
    @AppStorage(ActionOptions.resizeCopyKey) private var copy = true

    var body: some View {
        let mode = enumBinding($preset, default: ActionOptions.ResizePreset.p50)
        OptionsForm(description: L("Modify the image's size by selecting a predefined option or specifying your own dimensions."),
                    button: L("Resize"), disabled: width < 1 || height < 1, run: run) {
            Picker(L("Dimension"), selection: mode) {
                ForEach(ActionOptions.ResizePreset.allCases) { Text($0.title).tag($0) }
            }
            if mode.wrappedValue == .percent || mode.wrappedValue == .pixels {
                let pixels = mode.wrappedValue == .pixels
                TextField(pixels ? L("Max. width (in px)") : L("Width (in %)"), value: $width, format: .number)
                TextField(pixels ? L("Max. height (in px)") : L("Height (in %)"), value: $height, format: .number)
            }
            Toggle(L("Create copy"), isOn: $copy)
            if copy { OutputPicker() }
        }
    }
}

private struct ConvertOptions: View {
    let run: () -> Void
    @AppStorage(ActionOptions.convertFormatKey) private var format = FileOperations.ImageFormat.jpeg.rawValue
    @AppStorage(ActionOptions.convertQualityKey) private var quality = 0.85

    var body: some View {
        let selected = enumBinding($format, default: FileOperations.ImageFormat.jpeg)
        OptionsForm(description: L("Convert the format of an image to the specified format."), button: L("Convert"), run: run) {
            Picker(L("Target format"), selection: selected) {
                ForEach(FileOperations.ImageFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
            }
            if selected.wrappedValue.isLossy { QualitySlider(quality: $quality) }
            OutputPicker()
        }
    }
}

private struct CompressOptions: View {
    let run: () -> Void
    @AppStorage(ActionOptions.compressQualityKey) private var quality = 0.6
    @AppStorage(ActionOptions.compressCopyKey) private var copy = true

    var body: some View {
        OptionsForm(description: L("Compress images and photos for displaying on web pages, sharing on social networks or sending by email."),
                    button: L("Compress"), run: run) {
            QualitySlider(quality: $quality)
            Toggle(L("Create copy"), isOn: $copy)
            if copy { OutputPicker() }
        }
    }
}

private struct QualitySlider: View {
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
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }
}

private struct ZipOptions: View {
    let defaultName: String
    let run: (String, String?) -> Void
    @State private var name = ""
    @State private var password = ""

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        OptionsForm(description: L("Create a ZIP archive in the specified destination folder."), button: L("Create"),
                    disabled: trimmed.isEmpty || (!password.isEmpty && password.count < 3)) {
            run(trimmed, password.isEmpty ? nil : password)
        } content: {
            TextField(L("Filename"), text: $name)
            SecureField(L("ZIP Password:"), text: $password, prompt: Text(L("Optional Password")))
            OutputPicker()
        }
        .onAppear { if name.isEmpty { name = defaultName } }
    }
}

private struct PasswordOptions: View {
    let run: (String) -> Void
    @State private var password = ""

    var body: some View {
        OptionsForm(description: L("Protect your PDF with a password to prevent unauthorized access to the file content, especially for file sharing or archiving."),
                    button: L("Protect"), disabled: password.count < 3) {
            run(password)
        } content: {
            SecureField(L("Password"), text: $password, prompt: Text(L("Enter a password")))
            OutputPicker()
        }
    }
}

private struct TextOptions: View {
    let run: () -> Void
    @AppStorage(ActionOptions.ocrToFileKey) private var toFile = false

    var body: some View {
        OptionsForm(description: L("Analyzes the images and extracts the text onto your clipboard or creates new text files containing the extracted text."),
                    button: L("Extract Text"), run: run) {
            Picker(L("Output"), selection: $toFile) {
                Text(L("Clipboard")).tag(false)
                Text(L("Text File")).tag(true)
            }
            if toFile { OutputPicker() }
        }
    }
}

/// Every share service for some files. The listing API is deprecated in favor of the share picker,
/// which can't be shown as a submenu, so it is reached through a protocol to keep the build warning-free.
private protocol SharingServiceListing {
    static func sharingServices(forItems items: [Any]) -> [NSSharingService]
}

extension NSSharingService: SharingServiceListing {}

private struct BatchRenameOptions: View {
    let items: [ShelfItem]
    let run: () -> Void
    @State private var rule = ActionOptions.renameRule
    @AppStorage(ActionOptions.renameClosesKey) private var closeShelf = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                } header: {
                    Text(L("Rename multiple files using find-and-replace matching or a custom naming format."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                RenameFields(rule: $rule)
                Section(L("Preview")) {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                        GridRow {
                            Text(L("Current filename"))
                            Text(L("New filename"))
                        }
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                            GridRow {
                                Text(item.name)
                                Text(rule.validate() == nil ? rule.newName(for: item.name, index: index) : "–")
                            }
                            .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                Section { Toggle(L("Close shelf after renaming"), isOn: $closeShelf).toggleStyle(.switch) }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button(L("Rename")) {
                    ActionOptions.renameRule = rule
                    run()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.validate() != nil)
            }
            .padding(14)
        }
    }
}
