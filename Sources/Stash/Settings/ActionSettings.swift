import AppKit
import SwiftUI
import StashCore

/// Custom scripts: UNIX or Automator scripts in Stash's scripts folder, run on the shelf's files.
struct ScriptsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scripts = ScriptActions.scripts()
    @State private var editing: URL?
    @State private var importError = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                } header: {
                    VStack(spacing: 6) {
                        Text(L("Custom Scripts")).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        Text(L("Add your own UNIX or Automator scripts to perform actions on the files in the shelf. These actions will appear alongside other file actions."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                Section {
                    if scripts.isEmpty {
                        Text(L("No Custom Scripts")).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    ForEach(scripts, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ScriptActions.title(of: url))
                                Text(url.lastPathComponent).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L("Edit")) { editing = url }
                        }
                        .contextMenu {
                            Button(L("Edit")) { editing = url }
                            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Divider()
                            Button(L("Delete")) {
                                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                                reload()
                            }
                        }
                    }
                } footer: {
                    HStack {
                        Button(L("Reveal Scripts Directory")) {
                            try? FileManager.default.createDirectory(at: ScriptActions.folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(ScriptActions.folder)
                        }
                        Spacer()
                        Button(L("Import Script")) { importScript() }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 420)
        .onAppear(perform: reload)
        .sheet(item: $editing) { ScriptOptionsSheet(script: $0) }
        .alert(L("Could not load the file"), isPresented: $importError) {
            Button(L("OK")) {}
        } message: {
            Text(L("The selected file could not be loaded. Make sure the file is a script and that it's accessible."))
        }
    }

    private func reload() { scripts = ScriptActions.scripts() }

    private func importScript() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where (try? ScriptActions.importScript(url)) == nil { importError = true }
        reload()
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct ScriptOptionsSheet: View {
    let script: URL
    @Environment(\.dismiss) private var dismiss
    @State private var options = ScriptActions.Options()
    @State private var testResult: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(ScriptActions.title(of: script)).font(.system(size: 15, weight: .semibold)).padding(.top, 20)
            Form {
                Section {
                    Picker(L("Script output"), selection: $options.copyOutput) {
                        Text(L("Ignore")).tag(false)
                        Text(L("Copy to Clipboard")).tag(true)
                    }
                    Toggle(isOn: $options.closeShelf) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("Close Shelf"))
                            Text(L("Uncheck if you prefer to leave the shelf open when the script has been executed."))
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let testResult {
                    Section { Text(testResult).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button(L("Run Test...")) { runTest() }
                Spacer()
                Button(L("Done")) {
                    ScriptActions.setOptions(options, for: script)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 420, height: 360)
        .onAppear { options = ScriptActions.options(for: script) }
    }

    private func runTest() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.message = L("Select the files you want to use as input for the script")
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map(\.path)
        testResult = L("Executing script...")
        Task {
            let outcome = try? await Background.run { try ScriptActions.execute(script, paths: paths) }
            guard let outcome else { testResult = L("Failed to execute script"); return }
            let title = outcome.status == 0 ? L("Successfully executed script") : L("Failed to execute script")
            testResult = [title, outcome.output, outcome.errors].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }
}

struct InstantActionsSettings: View {
    @AppStorage(Pref.instantActionsEnabled) private var enabled = true
    @AppStorage(Pref.afterAction) private var afterAction = AfterAction.close.rawValue
    @State private var ids: [String] = UserDefaults.standard.stringArray(forKey: Pref.instantActions) ?? []

    private static let defaults = ["airdrop", "messages", "mail"]

    var body: some View {
        SettingsPage(title: L("Instant Actions"), description: L("Instant Actions appear below a new shelf when you drag files onto it. Drop files on an action to perform it.")) {
            Section {
                Toggle(L("Enable Instant Actions"), isOn: $enabled).toggleStyle(.switch)
            }
            Section {
                if ids.isEmpty {
                    Text(L("No content")).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                ForEach(ids, id: \.self) { id in
                    if let action = ActionCatalog.action(id) {
                        HStack(spacing: 10) {
                            ActionIcon(action: action, size: 24)
                            Text(action.title)
                            Spacer()
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 30)
                        .contextMenu { Button(L("Delete")) { remove(id) } }
                    }
                }
                .onMove { from, to in
                    ids.move(fromOffsets: from, toOffset: to)
                    save()
                }
            } footer: {
                HStack {
                    Button(L("Restore Defaults")) { ids = Self.defaults; save() }
                    Spacer()
                    Menu(L("Add New...")) {
                        ForEach(ActionCategory.allCases, id: \.self) { category in
                            Section(category.title) {
                                ForEach(ActionCatalog.everything.filter { $0.category == category && !ids.contains($0.id) }) { action in
                                    Button(action.title) { ids.append(action.id); save() }
                                }
                            }
                        }
                    }
                    .fixedSize()
                }
            }
            .disabled(!enabled)
            Section {
                SettingRow(symbol: "checkmark.circle", title: L("After a successful action")) {
                    HStack {
                        Picker("", selection: enumBinding($afterAction, default: AfterAction.close)) {
                            ForEach(AfterAction.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        InfoButton(text: L("By default, the shelf closes after a successful action. It remains open if the action fails."))
                    }
                }
            }
            .disabled(!enabled)
        }
    }

    private func remove(_ id: String) {
        ids.removeAll { $0 == id }
        save()
    }

    private func save() { UserDefaults.standard.set(ids, forKey: Pref.instantActions) }
}

struct FolderMonitoringSettings: View {
    @State private var folders = FolderMonitor.shared.folders
    @State private var editing: WatchedFolder?
    @State private var problem: String?

    var body: some View {
        SettingsPage(title: L("Folder Monitoring"), description: L("Monitor folders for file changes and automatically show the added file in a shelf.")) {
            Section {
                if folders.isEmpty {
                    Text(L("No Monitored Folders")).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                ForEach(folders) { folder in
                    Button { editing = folder } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path)).resizable().frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name)
                                Text((folder.path as NSString).abbreviatingWithTildeInPath).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            FolderStatus(folder: folder)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                        Button(L("Delete")) { FolderMonitor.shared.remove(folder); reload() }
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    Button(L("Add New Folder...")) { addFolder() }
                }
            }
        }
        .sheet(item: $editing, onDismiss: reload) { FolderDetailSheet(folder: $0) }
        .alert(L("Could not add folder"), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button(L("OK")) {}
        } message: { Text(problem ?? "") }
    }

    private func reload() { folders = FolderMonitor.shared.folders }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Select Folder")
        panel.message = L("Pick a folder for which new files should be automatically shown in a shelf")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path
        if folders.contains(where: { $0.url.standardizedFileURL.path == path }) {
            problem = L("This folder has already been added.")
        } else if Prefs.bool(Pref.screenshotShelf), ScreenshotShelf.folder.standardizedFileURL.path == path {
            problem = L("This folder is currently in use by the Screenshot shelf feature and cannot be monitored. To enable Folder Monitoring for this folder, please disable the Screenshot shelf first.")
        } else {
            let folder = WatchedFolder(path: path)
            FolderMonitor.shared.update(folder)
            reload()
            editing = folder
        }
    }
}

private struct FolderStatus: View {
    let folder: WatchedFolder

    var body: some View {
        let available = FolderMonitor.shared.isAvailable(folder)
        let (text, color): (String, Color) = !folder.enabled ? (L("Stopped"), .secondary) : available ? (L("Active"), .green) : (L("1 issue"), .orange)
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .help(available ? "" : L("The selected folder can't be found. It might have been moved or deleted. Reselect the folder and try again."))
    }
}

private struct FolderDetailSheet: View {
    @State var folder: WatchedFolder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path)).resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(.system(size: 15, weight: .semibold))
                    Text((folder.path as NSString).abbreviatingWithTildeInPath).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                FolderStatus(folder: folder)
            }
            .padding([.horizontal, .top], 20)
            Form {
                Section {
                    Toggle(L("Enabled"), isOn: $folder.enabled)
                    Toggle(L("Include nested subfolders"), isOn: $folder.includeSubfolders)
                    Toggle(L("Show each file in a new shelf"), isOn: $folder.shelfPerFile)
                    Stepper(value: $folder.delay, in: 0...60, step: 1) {
                        HStack {
                            Text(L("Delay"))
                            Spacer()
                            Text(L("%d sec", Int(folder.delay))).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Picker(L("Show files matching"), selection: $folder.matchAll) {
                        Text(L("All rules")).tag(true)
                        Text(L("Any rule")).tag(false)
                    }
                    Toggle(L("Case-sensitive"), isOn: $folder.caseSensitive)
                    ForEach($folder.rules) { $rule in RuleRow(rule: $rule) { folder.rules.removeAll { $0.id == rule.id } } }
                } header: {
                    Text(L("Rules"))
                } footer: {
                    HStack {
                        Text(folder.rules.isEmpty ? L("Without rules every new file is shown.") : "").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Add Rule")) { folder.rules.append(FolderRule(field: .fileExtension, comparison: .equals, value: "")) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button(L("Delete"), role: .destructive) {
                    FolderMonitor.shared.remove(folder)
                    dismiss()
                }
                Spacer()
                Button(L("Done")) {
                    FolderMonitor.shared.update(folder)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }
}

private struct RuleRow: View {
    @Binding var rule: FolderRule
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $rule.field) {
                ForEach(FolderRule.Field.allCases, id: \.self) { Text(title(of: $0)).tag($0) }
            }
            .labelsHidden().fixedSize()
            .onChange(of: rule.field) { _, field in
                if !field.comparisons.contains(rule.comparison) { rule.comparison = field.comparisons[0] }
                rule.value = field == .kind ? FolderRule.Kind.image.rawValue : ""
            }
            Picker("", selection: $rule.comparison) {
                ForEach(rule.field.comparisons, id: \.self) { Text(title(of: $0)).tag($0) }
            }
            .labelsHidden().fixedSize()
            if rule.field == .kind {
                Picker("", selection: $rule.value) {
                    ForEach(FolderRule.Kind.allCases, id: \.self) { Text(title(of: $0)).tag($0.rawValue) }
                }
                .labelsHidden()
            } else {
                TextField("", text: $rule.value, prompt: Text(rule.field == .size ? "MB" : ""))
                    .labelsHidden()
            }
            Button(action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    private func title(of field: FolderRule.Field) -> String {
        switch field {
        case .name: L("File name")
        case .fileExtension: L("File extension")
        case .kind: L("Kind")
        case .size: L("File size")
        }
    }

    private func title(of comparison: FolderRule.Comparison) -> String {
        switch comparison {
        case .contains: L("Contains")
        case .doesNotContain: L("Does not contain")
        case .beginsWith: L("Begins with")
        case .endsWith: L("Ends with")
        case .equals: L("Is")
        case .notEquals: L("Is not")
        case .greaterThan: L("Greater than")
        case .lessThan: L("Less than")
        }
    }

    private func title(of kind: FolderRule.Kind) -> String {
        switch kind {
        case .application: L("Application")
        case .archive: L("Archive")
        case .audio: L("Audio")
        case .document: L("Document")
        case .folder: L("Folder")
        case .image: L("Image")
        case .pdf: L("PDF")
        case .presentation: L("Presentation")
        case .text: L("Text")
        case .video: L("Video")
        }
    }
}

/// Settings ▸ Shelf Interaction ▸ Customize action menu: each action sits in the main menu or under All Actions.
struct CustomizeActionMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mainMenu = Set(FileActionMenu.mainMenuIDs)
    private static let defaults: Set<String> = ["copyTo", "moveTo"]
    private let order: [ActionCategory] = [.custom, .general, .image, .pdf, .text, .scripts]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(order, id: \.self) { category in
                    let actions = ActionCatalog.everything.filter { $0.category == category }
                    if !actions.isEmpty {
                        Section {
                            ForEach(actions) { action in
                                Picker(selection: binding(for: action.id)) {
                                    Text(L("Show in Main Menu")).tag(true)
                                    Text(L("Show in Submenu")).tag(false)
                                } label: {
                                    Label(action.title.replacingOccurrences(of: "...", with: ""), systemImage: action.symbol)
                                }
                            }
                        } header: {
                            Text(category.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button(L("Restore Defaults")) { mainMenu = Self.defaults }
                Spacer()
                Button(L("Done")) {
                    FileActionMenu.mainMenuIDs = ActionCatalog.everything.map(\.id).filter(mainMenu.contains)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 500, height: 560)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { mainMenu.contains(id) }, set: { if $0 { mainMenu.insert(id) } else { mainMenu.remove(id) } })
    }
}

struct ScreenshotShelfSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.screenshotShelf) private var enabled = false
    @AppStorage(Pref.screenshotFolder) private var folderPath = ""
    @AppStorage(Pref.screenshotAppend) private var append = false
    @AppStorage(Pref.screenshotClipboard) private var clipboard = false
    @AppStorage(Pref.screenshotMessage) private var message = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(L("Screenshot Shelf Settings")).font(.system(size: 15, weight: .semibold))
                Text(L("Automatically display new screenshots in a shelf.")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            Form {
                Section {
                    Toggle(L("Enabled"), isOn: $enabled)
                }
                Section {
                    LabeledContent {
                        HStack {
                            Text((ScreenshotShelf.folder.path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            InfoButton(text: L("The folder where your screenshots are stored. By default, this is the Desktop folder unless you've changed it manually."))
                        }
                    } label: { Text(L("Folder")) }
                    HStack {
                        Spacer()
                        Button(L("Pick Different Folder...")) { pickFolder() }
                    }
                    Picker(selection: $append) {
                        Text(L("New shelf")).tag(false)
                        Text(L("Existing screenshot shelf")).tag(true)
                    } label: {
                        HStack {
                            Text(L("Show screenshots in"))
                            InfoButton(text: L("By default, all screenshots will appear in a new shelf. Select \"Existing screenshot shelf\" if you prefer to append subsequent screenshots to the existing screenshot shelf instead."))
                        }
                    }
                    Toggle(isOn: $clipboard) {
                        HStack {
                            Text(L("Copy screenshot to clipboard"))
                            InfoButton(text: L("When enabled, screenshots will be automatically copied to your clipboard."))
                        }
                    }
                    Toggle(isOn: $message) {
                        HStack {
                            Text(L("Show confirmation message"))
                            InfoButton(text: L("Enabled by default, this option shows a message below shelves triggered by screenshots, indicating they were opened due to a new screenshot."))
                        }
                    }
                }
                .disabled(!enabled)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 440)
        .onChange(of: enabled) { FolderMonitor.shared.refresh() }
        .onChange(of: folderPath) { FolderMonitor.shared.refresh() }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = ScreenshotShelf.folder
        panel.prompt = L("Choose Folder")
        panel.message = L("Choose the folder where your screenshots are saved.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
    }
}

/// An action's icon: the app icon for share services, otherwise its symbol on a tile.
struct ActionIcon: View {
    let action: ShelfAction
    var size: CGFloat = 22

    var body: some View {
        if let image = action.image {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            SettingsIcon(symbol: action.symbol, tint: .accentColor).frame(width: size, height: size)
        }
    }
}
