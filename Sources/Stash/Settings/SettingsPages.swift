import AppKit
import ServiceManagement
import SwiftUI
import StashCore

// MARK: - Shelf Activation

struct ActivationSettings: View {
    @AppStorage(Pref.shakeEnabled) private var shakeEnabled = true
    @AppStorage(Pref.shakeSensitivity) private var sensitivity = ShakeDetector.Sensitivity.standard.rawValue
    @AppStorage(Pref.modifierEnabled) private var modifierEnabled = false
    @AppStorage(Pref.modifierKey) private var modifierKey = ModifierKey.shift.rawValue
    @AppStorage(Pref.notchEnabled) private var notchEnabled = true
    @AppStorage(Pref.notchHighlight) private var notchHighlight = NotchHighlight.hover.rawValue
    @AppStorage(Pref.shelfLocation) private var location = ShelfLocation.topRight.rawValue
    @AppStorage(Pref.addingBehavior) private var adding = AddingBehavior.newShelf.rawValue
    @State private var showsShortcuts = false
    @State private var showsIgnored = false

    var body: some View {
        SettingsPage(title: L("Shelf Activation"), description: L("Choose how to activate shelves using gestures, modifier keys, the notch, or keyboard shortcuts.")) {
            Section {
                SettingRow(symbol: "cursorarrow.motionlines", title: L("Activate with shake gesture"), subtitle: L("Shake cursor while dragging.")) {
                    Toggle("", isOn: $shakeEnabled).toggleStyle(.switch).labelsHidden()
                }
                PickerRow(selection: enumBinding($sensitivity, default: ShakeDetector.Sensitivity.standard), options: ShakeDetector.Sensitivity.allCases) { $0.title }
                    .disabled(!shakeEnabled)
            }
            Section {
                SettingRow(symbol: "shift", title: L("Activate with modifier key"), subtitle: L("Hold a modifier key while dragging.")) {
                    Toggle("", isOn: $modifierEnabled).toggleStyle(.switch).labelsHidden()
                }
                PickerRow(selection: enumBinding($modifierKey, default: ModifierKey.shift), options: ModifierKey.allCases) { $0.title }
                    .disabled(!modifierEnabled)
            }
            Section {
                SettingRow(symbol: "keyboard", title: L("Keyboard shortcuts")) {
                    Button(L("Edit...")) { showsShortcuts = true }
                }
            }
            .sheet(isPresented: $showsShortcuts) { KeyboardShortcutsSheet() }
            Section {
                SettingRow(symbol: "macbook", title: L("Drop to notch"), subtitle: L("Drag files to the MacBook notch.")) {
                    Toggle("", isOn: $notchEnabled).toggleStyle(.switch).labelsHidden()
                        .onChange(of: notchEnabled) { NotchController.shared.refresh() }
                }
                PickerRow(selection: enumBinding($notchHighlight, default: NotchHighlight.hover), options: NotchHighlight.allCases) { $0.title }
                    .disabled(!notchEnabled)
            }
            Section {
                SettingRow(symbol: "rectangle.inset.topright.filled", title: L("Default shelf location"), subtitle: L("For shelves created without shaking the cursor.")) {
                    Picker("", selection: enumBinding($location, default: ShelfLocation.topRight)) {
                        ForEach(ShelfLocation.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingRow(symbol: "doc.badge.plus", title: L("Adding Files Behavior"), subtitle: L("Choose what happens when files are added using global shortcuts, integrations, or automations.")) {
                    HStack {
                        Picker("", selection: enumBinding($adding, default: AddingBehavior.newShelf)) {
                            ForEach(AddingBehavior.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        InfoButton(text: L("These settings apply only when adding files through global keyboard shortcuts, Shortcuts, the “Add to Stash” Service menu, the stash:// link or folder monitoring."))
                    }
                }
                SettingRow(symbol: "nosign", title: L("Ignored applications")) {
                    Button(L("Edit...")) { showsIgnored = true }
                }
            }
            .sheet(isPresented: $showsIgnored) { IgnoredAppsSheet() }
        }
    }
}

// MARK: - Shelf Interaction

struct InteractionSettings: View {
    @AppStorage(Pref.doubleClickFiles) private var doubleClickFiles = DoubleClickFiles.reveal.rawValue
    @AppStorage(Pref.doubleClickEdge) private var doubleClickEdge = EdgeAction.dock.rawValue
    @AppStorage(Pref.closeOnDragOut) private var closeOnDragOut = CloseOnDragOut.moved.rawValue
    @AppStorage(Pref.intelligentNames) private var intelligentNames = true
    @AppStorage(Pref.snapIntoPlace) private var snap = false
    @AppStorage(Pref.retractAfterDrop) private var retract = false
    @State private var showsAdvanced = false
    @State private var showsMenuEditor = false
    @State private var showsScreenshot = false

    var body: some View {
        SettingsPage(title: L("Shelf Interaction"), description: "") {
            Section {
                SettingRow(symbol: "cursorarrow.click.2", title: L("Double-click files")) {
                    Picker("", selection: enumBinding($doubleClickFiles, default: DoubleClickFiles.reveal)) {
                        ForEach(DoubleClickFiles.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingRow(symbol: "rectangle.portrait.lefthalf.inset.filled", title: L("Double-click shelf edge")) {
                    Picker("", selection: enumBinding($doubleClickEdge, default: EdgeAction.dock)) {
                        ForEach(EdgeAction.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            Section {
                SettingRow(symbol: "star", title: L("Customize action menu"), subtitle: L("Show actions in the main menu or group in a submenu.")) {
                    Button(L("Edit...")) { showsMenuEditor = true }
                }
                SettingRow(symbol: "camera.viewfinder", title: L("Screenshot shelf"), subtitle: L("Automatically show new screenshots inside a Stash shelf.")) {
                    Button(L("Setup...")) { showsScreenshot = true }
                }
            }
            .sheet(isPresented: $showsMenuEditor) { CustomizeActionMenuSheet() }
            .sheet(isPresented: $showsScreenshot) { ScreenshotShelfSheet() }
            Section {
                SettingRow(symbol: "xmark.rectangle", title: L("Close on drag out")) {
                    HStack {
                        Picker("", selection: enumBinding($closeOnDragOut, default: CloseOnDragOut.moved)) {
                            ForEach(CloseOnDragOut.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        InfoButton(text: L("When you drag items out, macOS may move or copy them depending on the destination. By default, Stash closes the shelf only after items are moved."))
                    }
                }
                SettingRow(symbol: "text.badge.star", title: L("Intelligent Shelf Names")) {
                    HStack {
                        Toggle("", isOn: $intelligentNames).toggleStyle(.switch).labelsHidden()
                        InfoButton(text: L("Stash uses on-device intelligence only when files are added to a shelf, giving it a more descriptive name if the files clearly belong together."))
                    }
                }
                SettingRow(symbol: "square.on.square.dashed", title: L("Snap into place")) {
                    HStack {
                        Toggle("", isOn: $snap).toggleStyle(.switch).labelsHidden()
                        InfoButton(text: L("When enabled, shelves auto-snap and align after moving. Hold Command while dragging to disable snapping."))
                    }
                }
                SettingRow(symbol: "arrow.right.to.line", title: L("Retract after first drop")) {
                    HStack {
                        Toggle("", isOn: $retract).toggleStyle(.switch).labelsHidden()
                        InfoButton(text: L("After the initial file drop, the shelf moves aside to stay out of the way."))
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    Button(L("Advanced...")) { showsAdvanced = true }
                }
            }
            .sheet(isPresented: $showsAdvanced) { AdvancedInteractionSheet() }
        }
    }
}

struct AdvancedInteractionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.alwaysCopy) private var alwaysCopy = false
    @AppStorage(Pref.plainText) private var plainText = false
    @AppStorage(Pref.restrictToSpace) private var restrict = false
    @AppStorage(Pref.shelfColors) private var colors = false
    @AppStorage(Pref.takeFocus) private var takeFocus = false
    @AppStorage(Pref.closeDetailOutside) private var closeDetail = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    toggle($alwaysCopy, L("Always copy items when dragging out"), L("By default, macOS moves items when you drag them within the same volume, and copies them when you drag them to a different volume. Turn this on to always copy."))
                    toggle($plainText, L("Convert text to plain text"), L("Dragging text keeps its formatting by default. Turn on to convert dragged text to plain text."))
                    toggle($restrict, L("Restrict to current Space"), L("Shelves appear in all Spaces by default. Turn on to limit new shelves to the current Space. Applies to new shelves and can be overridden for each shelf."))
                    toggle($colors, L("Use color to distinguish shelves"), L("Gives each open shelf a unique color for easy identification. Custom-named or colored shelves are excluded."))
                    toggle($takeFocus, L("Shelf takes focus when shown"), L("When turned on, the shelf becomes the active window and receives keyboard focus as soon as it appears."))
                    toggle($closeDetail, L("Close detail view when clicking outside"), L("Closes the shelf detail view when you interact outside the shelf."))
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 520)
    }

    private func toggle(_ value: Binding<Bool>, _ title: String, _ text: String) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @AppStorage(Pref.showInMenuBar) private var showInMenuBar = true
    @AppStorage(Pref.menuBarIcon) private var menuBarIcon = MenuBarIcon.pocket.rawValue
    @AppStorage(Pref.showInDock) private var showInDock = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var language = AppLanguage.current
    @State private var showsAppData = false
    @State private var launchError: String?

    var body: some View {
        SettingsPage(title: L("General"), description: "") {
            Section {
                SettingRow(symbol: "menubar.rectangle", title: L("Show in menu bar")) {
                    Toggle("", isOn: $showInMenuBar).toggleStyle(.switch).labelsHidden()
                        .onChange(of: showInMenuBar) {
                            if !showInMenuBar, !showInDock { showInDock = true }
                            StatusMenuController.shared.refresh()
                        }
                }
                SettingRow(symbol: MenuBarIcon(rawValue: menuBarIcon)?.symbol ?? "tray", title: L("Menu bar icon")) {
                    Picker("", selection: enumBinding($menuBarIcon, default: MenuBarIcon.pocket)) {
                        ForEach(MenuBarIcon.allCases) { icon in
                            Label { Text(icon.title) } icon: { Image(nsImage: icon.image) }.tag(icon)
                        }
                    }
                    .labelsHidden().fixedSize()
                    .onChange(of: menuBarIcon) { StatusMenuController.shared.refresh() }
                }
                .disabled(!showInMenuBar)
            }
            Section {
                SettingRow(symbol: "person.crop.circle", title: L("Launch at login")) {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                        .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                }
                SettingRow(symbol: "dock.rectangle", title: L("Show in Dock")) {
                    Toggle("", isOn: $showInDock).toggleStyle(.switch).labelsHidden()
                        .onChange(of: showInDock) {
                            if !showInDock, !showInMenuBar { showInMenuBar = true; StatusMenuController.shared.refresh() }
                            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
                            if !showInDock { SettingsWindowController.shared.show() }
                        }
                }
            }
            .alert(L("Launch at login couldn't be enabled."), isPresented: Binding(get: { launchError != nil }, set: { if !$0 { launchError = nil } })) {
                Button(L("Open System Settings")) { SMAppService.openSystemSettingsLoginItems() }
                Button(L("OK"), role: .cancel) {}
            } message: {
                Text(launchError ?? "")
            }
            Section {
                SettingRow(symbol: "globe", title: L("Language")) {
                    Picker("", selection: $language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    .onChange(of: language) { changeLanguage(language) }
                }
            }
            Section {
                SettingRow(symbol: "externaldrive", title: L("Application data")) {
                    Button(L("Manage...")) { showsAppData = true }
                }
            }
            .sheet(isPresented: $showsAppData) { AppDataSheet() }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if on, SMAppService.mainApp.status == .requiresApproval {
                launchError = L("Stash has been added as a login item, but macOS requires you to approve it manually.")
            }
        } catch {
            launchError = L("Try again, or add the app manually in System Settings → General → Login Items.")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func changeLanguage(_ language: AppLanguage) {
        guard language != AppLanguage.current else { return }
        language.apply()
        let alert = NSAlert()
        alert.messageText = L("Restart Stash to change the language.")
        alert.addButton(withTitle: L("Restart Now"))
        alert.addButton(withTitle: L("Later"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(filePath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Sheets

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Bumped by Restore Defaults so every row reloads.
    @State private var generation = 0

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text(L("To change a keyboard shortcut, click on the shortcut control and assign the new combination (press Esc ⎋ to cancel). To disable a keyboard shortcut, uncheck the checkbox."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section(L("Global Shortcuts")) {
                    ForEach(KeyboardAction.global) { ShortcutRow(action: $0) }
                }
                Section {
                    ForEach(KeyboardAction.shelf) { ShortcutRow(action: $0) }
                } header: {
                    Text(L("Shelf Shortcuts"))
                } footer: {
                    Text(L("Shelf shortcuts work only when the shelf is selected. Click the shelf first to activate it, then use the keyboard shortcuts.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .id(generation)
            HStack {
                Button(L("Restore Defaults")) {
                    KeyboardAction.allCases.forEach { $0.restoreDefault() }
                    HotKeyCenter.shared.registerAll()
                    generation += 1
                }
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 620)
    }
}

/// Checkbox, title and the shortcut control.
struct ShortcutRow: View {
    let action: KeyboardAction
    @State private var enabled = false
    @State private var problem: String?

    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { enabled }, set: setEnabled)) { Text(action.title) }
                .toggleStyle(.checkbox)
            Spacer()
            ShortcutRecorder(action: action, problem: $problem).disabled(!enabled)
        }
        .onAppear { enabled = action.isEnabled }
        .alert(L("Cannot Assign Shortcut"), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(problem ?? "") }
    }

    private func setEnabled(_ on: Bool) {
        if on, let other = action.conflict(with: action.combo) {
            problem = L("You cannot enable this action because this keyboard shortcut is already in use by the action '%@'.", other.title)
            return
        }
        action.isEnabled = on
        enabled = on
        if action.isGlobal { HotKeyCenter.shared.registerAll() }
    }
}

/// Click, then press a key combination.
struct ShortcutRecorder: View {
    let action: KeyboardAction
    @Binding var problem: String?
    @State private var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? L("Type shortcut…") : (combo?.display ?? ""))
                .frame(minWidth: 90)
                .foregroundStyle(recording ? Color.accentColor : .primary)
        }
        .onAppear { combo = action.combo }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.paused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyCenter.shared.paused = false
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { stop(); return }   // Esc cancels
        let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
        stop()
        guard action.accepts(candidate) else {
            problem = L("The recorded shortcut is invalid. Shortcuts must include at least one of the following modifiers: • Command (⌘) • Control (⌃) • Option (⌥)")
            return
        }
        if let other = action.conflict(with: candidate) {
            problem = L("This combination is already in use by a different keyboard shortcut in Stash. Try a different combination.") + " (\(other.title))"
            return
        }
        if action.isGlobal, candidate != action.combo, HotKeyCenter.shared.isTakenBySystem(candidate) {
            problem = L("The recorded shortcut is already in use by the system. Try a different combination.")
            HotKeyCenter.shared.registerAll()
            return
        }
        action.combo = candidate
        combo = candidate
        if action.isGlobal { HotKeyCenter.shared.registerAll() }
    }
}

struct IgnoredAppsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apps = Prefs.ignoredApps
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Ignored applications")).font(.headline)
            Text(L("Manage applications that ignore the shake gesture.")).font(.system(size: 12)).foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(apps, id: \.self) { id in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                            Text(FileManager.default.displayName(atPath: url.path))
                        } else {
                            Text(id)
                        }
                    }
                    .tag(id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            HStack(spacing: 0) {
                Button { add() } label: { Image(systemName: "plus").frame(width: 20) }
                Button { remove() } label: { Image(systemName: "minus").frame(width: 20) }.disabled(selection == nil)
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 380)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) { apps.append(id) }
        }
        Prefs.ignoredApps = apps
    }

    private func remove() {
        apps.removeAll { $0 == selection }
        selection = nil
        Prefs.ignoredApps = apps
    }
}

struct AppDataSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sizes: [URL: Int64] = [:]
    private let paths = StashPaths.standard

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text(L("Inspect and manage files created by Stash")).foregroundStyle(.secondary)
                }
                folder(paths.temporary, L("Temporary Folder"), L("The temporary folder contains files that were temporary created by Stash to accommodate drag & drop from sources that only provide the raw data, such as text or images."))
                folder(paths.output, L("Actions Output Folder"), L("The actions output folder contains files that were created as a result of explicit file action performed such as image resize or PDF stitching."))
                folder(paths.scripts, L("Scripts Folder"), L("Executable scripts in this folder appear as custom actions."))
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 470)
        .task { refresh() }
    }

    private func folder(_ url: URL, _ title: String, _ text: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(sizes[url].map(\.fileSize) ?? L("Calculating...")).foregroundStyle(.secondary)
                }
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(L("Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Spacer()
                Button(L("Clear Folder")) { clear(url) }.disabled((sizes[url] ?? 0) == 0 || url == paths.scripts)
            }
        }
    }

    private func refresh() {
        for url in [paths.temporary, paths.output, paths.scripts] { sizes[url] = StashPaths.size(of: url) }
    }

    private func clear(_ folder: URL) {
        let inUse = Set(ShelfManager.shared.controllers.flatMap { $0.model.items.map(\.url.path) })
        if inUse.contains(where: { $0.hasPrefix(folder.path) }) {
            let alert = NSAlert()
            alert.messageText = L("Recent Shelves")
            alert.informativeText = L("One or more open shelves contain files from this folder. These items will be removed from the shelves.")
            alert.addButton(withTitle: L("Clear Folder"))
            alert.addButton(withTitle: L("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
        for controller in ShelfManager.shared.controllers {
            let gone = Set(controller.model.items.filter { !$0.exists }.map(\.id))
            if !gone.isEmpty { controller.remove(gone) }
        }
        refresh()
    }
}
