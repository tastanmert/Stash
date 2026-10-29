import AppKit
import SwiftUI

/// "What's New in Stash": shown after an update and from the menu bar menu.
enum WhatsNew {
    private static var controller: NSWindowController?
    private static let seenKey = "whatsNewSeenVersion"

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    static func show() {
        if controller == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 781),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // The content fills the whole window, title bar included, so the frame is the size.
            window.setFrame(NSRect(x: 0, y: 0, width: 760, height: 781), display: false)
            let host = NSHostingView(rootView: WhatsNewView { window.close() })
            host.sizingOptions = [] // keep the window's frame; the view would add the title bar on top
            window.contentView = host
            window.center()
            controller = NSWindowController(window: window)
        }
        UserDefaults.standard.set(version, forKey: seenKey)
        NSApp.activate()
        controller?.window?.makeKeyAndOrderFront(nil)
    }

    /// After an update (not on the very first launch, which shows the quick start guide instead).
    static func showIfUpdated() {
        let seen = UserDefaults.standard.string(forKey: seenKey)
        if seen == nil { UserDefaults.standard.set(version, forKey: seenKey) } else if seen != version { show() }
    }
}

private struct WhatsNewView: View {
    let close: () -> Void

    private struct Feature: Identifiable {
        let symbol: String
        let title: String
        let text: String
        var id: String { symbol }
    }

    private let features = [
        Feature(symbol: "tray.circle", title: L("Shelves for Everything"),
                text: L("Collect files, images, and text in floating shelves, then drag them out wherever you need them.")),
        Feature(symbol: "bolt.circle", title: L("Actions and Instant Actions"),
                text: L("Zip, resize, convert, or share files right from the shelf, or drop them on an instant action while you drag.")),
        Feature(symbol: "arrow.triangle.2.circlepath.circle", title: L("Automation"),
                text: L("Watch folders, open new screenshots in a shelf, run your own scripts, and use Stash in Shortcuts.")),
        Feature(symbol: "ellipsis", title: L("More"),
                text: L("Command bar, Select Shelf, pinned and recent shelves in the menu bar, stash:// links, and more.")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text(L("What's New in Stash"))
                .font(.system(size: 40, weight: .bold))
                .padding(.top, 40)
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 40) {
                ForEach(features) { feature in
                    HStack(alignment: .center, spacing: 32) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: feature.symbol == "ellipsis" ? 22 : 34, weight: feature.symbol == "ellipsis" ? .black : .regular))
                            .foregroundStyle(Color.orange)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(feature.title).font(.system(size: 16, weight: .bold))
                            Text(feature.text).font(.system(size: 14)).foregroundStyle(.secondary)
                                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(width: 430)
            Spacer(minLength: 30)
            Button(action: close) {
                Text(L("Continue")).font(.system(size: 13, weight: .medium))
                    .frame(width: 196, height: 30)
                    .background(Color.primary.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            Button(L("Learn More...")) {
                close()
                OnboardingWindowController.shared.show()
            }
            .buttonStyle(.link)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .frame(width: 760, height: 781)
    }
}
