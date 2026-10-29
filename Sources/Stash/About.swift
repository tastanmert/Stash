import AppKit
import SwiftUI
import StashCore

/// "About Stash": icon, version, this Mac's instance ID and a few links.
enum AboutWindow {
    private static var controller: NSWindowController?

    static func show() {
        if controller == nil {
            let frame = NSRect(x: 0, y: 0, width: 400, height: 573)
            let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setFrame(frame, display: false)
            let host = NSHostingView(rootView: AboutView())
            host.sizingOptions = [] // keep the window's frame; the view would add the title bar on top
            window.contentView = host
            window.center()
            controller = NSWindowController(window: window)
        }
        NSApp.activate()
        controller?.window?.makeKeyAndOrderFront(nil)
    }

    /// A short ID for this installation, to tell Macs apart when reporting a problem.
    static var instanceID: String {
        let key = "instanceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)) + "-M"
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

private struct AboutView: View {
    @State private var showsPrivacy = false
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 104, height: 104).padding(.top, 42)
            HStack(spacing: 6) {
                Text("Stash").fontWeight(.semibold)
                Text(version).foregroundStyle(.secondary)
            }
            .font(.system(size: 17))
            .padding(.top, 10)
            .padding(.bottom, 6)
            Form {
                Section {
                    LabeledContent(L("Version"), value: "\(version) (\(build))")
                    LabeledContent(L("Instance ID")) {
                        HStack(spacing: 8) {
                            Text(AboutWindow.instanceID).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                            Button(L("Copy")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(AboutWindow.instanceID, forType: .string)
                            }
                        }
                    }
                }
                Section {
                    LinkRow(title: L("New in This Version")) { WhatsNew.show() }
                }
                Section(L("Links")) {
                    LinkRow(title: L("Tips")) { OnboardingWindowController.shared.show() }
                    LinkRow(title: L("Privacy Policy")) { showsPrivacy = true }
                    LinkRow(title: L("Application Data")) {
                        try? FileManager.default.createDirectory(at: StashPaths.standard.root, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(StashPaths.standard.root)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 400, height: 573)
        .alert(L("Privacy Policy"), isPresented: $showsPrivacy) {
            Button(L("OK")) {}
        } message: {
            Text(L("Stash works entirely on your Mac. It has no account, collects no data and sends nothing over the network; intelligent shelf names use the on-device model."))
        }
    }
}

/// A row that acts like a link: title and a chevron.
private struct LinkRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
