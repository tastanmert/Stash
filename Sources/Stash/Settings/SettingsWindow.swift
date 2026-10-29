import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    let state = SettingsState()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = L("Settings")
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        super.init(window: window)
        // 700×600 overall; without this the hosting view would add the title bar on top.
        window.setFrame(NSRect(x: 0, y: 0, width: 700, height: 600), display: false)
        let host = NSHostingView(rootView: SettingsRoot(state: state))
        host.sizingOptions = []
        window.contentView = host
        window.center()
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(tab: SettingsTab? = nil) {
        if let tab { state.tab = tab }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if !Prefs.bool(Pref.showInDock) {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

@Observable final class SettingsState {
    var tab: SettingsTab = .activation
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case activation, interaction, general, customActions, instantActions, folderMonitoring
    var id: String { rawValue }

    var title: String {
        switch self {
        case .activation: L("Shelf Activation")
        case .interaction: L("Shelf Interaction")
        case .general: L("General")
        case .customActions: L("Custom Actions")
        case .instantActions: L("Instant Actions")
        case .folderMonitoring: L("Folder Monitoring")
        }
    }

    var symbol: String {
        switch self {
        case .activation: "cursorarrow.motionlines"
        case .interaction: "rectangle.split.2x1"
        case .general: "gearshape"
        case .customActions: "person.crop.circle.fill"
        case .instantActions: "bolt.circle.fill"
        case .folderMonitoring: "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .activation: .green
        case .interaction: .purple
        case .general: .gray
        case .customActions: .orange
        case .instantActions: .red
        case .folderMonitoring: .indigo
        }
    }

    static let groups: [[SettingsTab]] = [[.activation, .interaction, .general], [.customActions, .instantActions, .folderMonitoring]]
}

struct SettingsRoot: View {
    @Bindable var state: SettingsState

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $state.tab)
                .frame(width: 200)
            Divider()
            Group {
                switch state.tab {
                case .activation: ActivationSettings()
                case .interaction: InteractionSettings()
                case .general: GeneralSettings()
                case .customActions: CustomActionsSettings()
                case .instantActions: InstantActionsSettings()
                case .folderMonitoring: FolderMonitoringSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 700, height: 600)
        .ignoresSafeArea()
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 42)
            VStack(spacing: 0) {
                ForEach(Array(SettingsTab.groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { Color.clear.frame(height: 13) }
                    ForEach(group) { tab in
                        Button { selection = tab } label: { SidebarRow(tab: tab, selected: selection == tab) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            Spacer()
            Button {
                AboutWindow.show()
            } label: {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                    HStack(spacing: 4) {
                        Text("Stash").fontWeight(.medium)
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
        .frame(maxHeight: .infinity)
        .background(VisualEffect(material: .sidebar))
    }
}

private struct SidebarRow: View {
    let tab: SettingsTab
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            SettingsIcon(symbol: tab.symbol, tint: tab.tint, size: 20)
            Text(tab.title).font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(selected ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// The small dark tile with a colored glyph used in the sidebar.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.98, alpha: 1) }))
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(tint == .gray ? Color.secondary : tint)
            }
            .frame(width: size, height: size)
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

// MARK: - Building blocks shared by the settings pages

/// A settings page: centered title and description above grouped cards.
struct SettingsPage<Content: View>: View {
    let title: String
    let description: String
    var learnMore: URL?
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
            } header: {
                VStack(spacing: 8) {
                    Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.primary).padding(.top, 11)
                    if !description.isEmpty {
                        Text(description).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
            }
            content
        }
        .formStyle(.grouped)
    }
}

/// Icon + title (+ optional description) on the left, a control on the right.
struct SettingRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, subtitle == nil ? 0 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 2)
    }
}

/// A row holding a right-aligned pop-up menu.
struct PickerRow<Value: Hashable & Identifiable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        HStack {
            Spacer()
            Picker("", selection: $selection) {
                ForEach(options) { Text(title($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

struct InfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            Text(text).font(.system(size: 12)).frame(width: 260).padding(14).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Binds an enum stored as a raw string in UserDefaults.
func enumBinding<T: RawRepresentable>(_ storage: Binding<String>, default value: T) -> Binding<T> where T.RawValue == String {
    Binding(get: { T(rawValue: storage.wrappedValue) ?? value }, set: { storage.wrappedValue = $0.rawValue })
}
