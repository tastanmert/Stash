import AppKit
import ServiceManagement
import SwiftUI
import StashCore

/// The quick start guide shown on first launch (and from the menu).
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // The content fills the whole window, title bar included, so the frame is the size.
        window.setFrame(NSRect(x: 0, y: 0, width: 690, height: 700), display: false)
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        // A fresh view each time, so the guide starts again from its first page.
        let host = NSHostingView(rootView: OnboardingView { [weak self] in self?.finish() })
        host.sizingOptions = [] // keep the window's frame; the view would add the title bar on top
        window?.contentView = host
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // The illustrations redraw every frame; a closed (hidden) window would keep them running.
    func windowWillClose(_ notification: Notification) { window?.contentView = nil }

    private func finish() {
        window?.close()
        guard !UserDefaults.standard.bool(forKey: "askedLaunchAtLogin") else { return }
        UserDefaults.standard.set(true, forKey: "askedLaunchAtLogin")
        let alert = NSAlert()
        alert.messageText = L("Would you like to launch Stash at login?")
        alert.informativeText = L("You can always change this option in Stash's settings.")
        alert.addButton(withTitle: L("Yes (Recommended)"))
        alert.addButton(withTitle: L("No"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { try? SMAppService.mainApp.register() }
    }
}

private enum OnboardingScene { case icon, shelf, demo, actions, menuBar }

private struct OnboardingPage {
    let scene: OnboardingScene
    let title: String
    let text: String
}

private struct OnboardingView: View {
    let done: () -> Void
    @State private var index = 0
    @State private var appeared = false
    @State private var demo = DemoStage.start

    private let pages = [
        OnboardingPage(scene: .icon, title: L("Drag and drop. Without the friction."),
                       text: L("Stash is a drag and drop utility that lets you collect, organize, process, and share files in floating shelves.")),
        OnboardingPage(scene: .shelf, title: L("Meet Your Shelf"),
                       text: L("Stash uses small floating windows called shelves. Drag files, images, or text onto a shelf and drop them wherever you need them later.")),
        OnboardingPage(scene: .demo, title: L("Try It Out"),
                       text: L("Click and hold the file above to start. You'll see how the shelf appears when you shake your cursor.")),
        OnboardingPage(scene: .actions, title: L("Powerful Shelf"),
                       text: L("The shelf organizes your files, handles tasks like resizing or zipping, and lets you share them quickly.")),
        OnboardingPage(scene: .menuBar, title: L("Ready When You Need It"),
                       text: L("Stash stays out of your way, but it's always ready in the menu bar whenever you need a shelf.")),
    ]

    var body: some View {
        let page = pages[index]
        VStack(spacing: 0) {
            Group {
                if page.scene == .icon {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 150, height: 150)
                        .scaleEffect(appeared ? 1 : 0.85)
                        .padding(.top, 72)
                        .frame(height: 300, alignment: .top)
                } else if page.scene == .demo {
                    DemoFile(stage: $demo)
                        .frame(width: 560, height: 280)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 44)
                        .frame(height: 300, alignment: .top)
                } else {
                    OnboardingSceneView(scene: page.scene)
                        .frame(width: 560, height: 280)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 44)
                        .frame(height: 300, alignment: .top)
                }
            }
            .id(index)
            .transition(.opacity)

            Text(page.scene == .demo ? demo.title : page.title)
                .font(.system(size: 28, weight: .medium))
                .padding(.top, 28)
                .opacity(appeared ? 1 : 0)
            Text(page.scene == .demo ? demo.text : page.text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(width: 470)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .opacity(appeared ? 1 : 0)
            Spacer()
            HStack(spacing: 10) {
                if index > 0 {
                    CapsuleButton(title: L("Back"), prominent: false) { withAnimation(.easeInOut(duration: 0.25)) { index -= 1 } }
                }
                if page.scene == .demo, demo != .finished {
                    // The demo can be left without doing it.
                    CapsuleButton(title: L("Skip"), prominent: true) { withAnimation(.easeInOut(duration: 0.25)) { index += 1 } }
                } else if index < pages.count - 1 {
                    CapsuleButton(title: index == 0 ? L("Get Started") : L("Next"), prominent: true) {
                        withAnimation(.easeInOut(duration: 0.25)) { index += 1 }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    CapsuleButton(title: L("Done"), prominent: true, action: done).keyboardShortcut(.defaultAction)
                }
            }
            .opacity(appeared ? 1 : 0)
            .padding(.bottom, 26)
        }
        .frame(width: 690, height: 700)
        .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.2)) { appeared = true } }
    }
}

/// The small orange capsule button of the guide (or a quiet one for Back).
private struct CapsuleButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 18)
                .frame(minWidth: 98, minHeight: 30)
                .background(prominent ? Color.orange : Color.primary.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Illustrations (drawn here, animated with a looping clock)

private struct OnboardingSceneView: View {
    let scene: OnboardingScene

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            switch scene {
            case .shelf: ShelfScene(t: t)
            case .actions: ActionsScene(t: t)
            case .menuBar: MenuBarScene(t: t)
            case .icon, .demo: EmptyView()
            }
        }
    }
}

/// Progress through a looping animation, 0...1.
private func phase(_ t: TimeInterval, period: Double) -> Double { t.truncatingRemainder(dividingBy: period) / period }

private func ease(_ x: Double) -> Double { x < 0 ? 0 : x > 1 ? 1 : x * x * (3 - 2 * x) }

/// A file card: a white page with a coloured badge, like the files on a shelf.
private struct FileCard: View {
    var color: Color = .blue
    var symbol = "photo"
    var size: CGFloat = 54

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
            .fill(Color.white)
            .frame(width: size * 0.8, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.32, weight: .medium)).foregroundStyle(color))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// A miniature shelf: dark rounded window with close and menu buttons and a title pill.
private struct MiniShelf<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                    .frame(width: 16, height: 16).background(Color.white.opacity(0.12), in: Circle())
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    .frame(width: 16, height: 16).background(Color.white.opacity(0.12), in: Circle())
            }
            .foregroundStyle(.white.opacity(0.8))
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
        .padding(8)
        .frame(width: 128, height: 136)
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .environment(\.colorScheme, .dark)
    }
}

/// Files fly onto a shelf one after another, then the stack is dragged away.
private struct ShelfScene: View {
    let t: TimeInterval

    var body: some View {
        let p = phase(t, period: 6)
        let colors: [Color] = [.blue, .orange, .green]
        let symbols = ["photo", "doc.text", "music.note"]
        let landed = (0..<3).filter { p > 0.15 + Double($0) * 0.15 }.count
        ZStack {
            MiniShelf(label: landed == 0 ? L("Drop files here") : L("%d Files", landed)) {
                ZStack {
                    ForEach(0..<landed, id: \.self) { i in
                        FileCard(color: colors[i], symbol: symbols[i], size: 46)
                            .rotationEffect(.degrees(Double(i - 1) * 7))
                    }
                }
                .offset(y: p > 0.75 ? -CGFloat(ease((p - 0.75) / 0.2)) * 220 : 0)
                .opacity(p > 0.75 ? 1 - ease((p - 0.8) / 0.15) : 1)
            }
            ForEach(0..<3, id: \.self) { i in
                let start = 0.02 + Double(i) * 0.15
                let x = ease((p - start) / 0.13)
                if p > start, p < start + 0.13 {
                    FileCard(color: colors[i], symbol: symbols[i], size: 46)
                        .offset(x: CGFloat(1 - x) * (i.isMultiple(of: 2) ? -220 : 220), y: CGFloat(1 - x) * -60)
                }
            }
        }
    }
}

/// The shelf's action menu opens and an action is chosen.
private struct ActionsScene: View {
    let t: TimeInterval

    var body: some View {
        let p = phase(t, period: 5)
        let menuIn = ease((p - 0.12) / 0.1)
        let chosen = Int(min(max((p - 0.3) / 0.12, 0), 3))
        let rows: [(String, String)] = [
            ("doc.zipper", L("Create ZIP Archive")), ("photo.badge.arrow.down", L("Resize")),
            ("arrow.triangle.2.circlepath", L("Convert Format")), ("airplayaudio", "AirDrop"),
        ]
        HStack(alignment: .top, spacing: 10) {
            MiniShelf(label: L("%d Images", 3)) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        FileCard(color: [.blue, .teal, .indigo][i], size: 46).rotationEffect(.degrees(Double(i - 1) * 7))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 7) {
                        Image(systemName: rows[i].0).frame(width: 16)
                        Text(rows[i].1)
                        Spacer()
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .foregroundStyle(i == chosen ? Color.white : Color.primary)
                    .background(i == chosen ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(5)
            .frame(width: 168)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            .opacity(menuIn * (p > 0.85 ? 1 - ease((p - 0.85) / 0.1) : 1))
            .offset(y: CGFloat(1 - menuIn) * -6)
        }
        .offset(x: 30)
    }
}

/// The menu bar item opens its menu with recent shelves.
private struct MenuBarScene: View {
    let t: TimeInterval
    // Formatted once: the body runs every frame.
    private static let today = StatusMenuController.dateText(.now)
    private static let yesterday = StatusMenuController.dateText(.now.addingTimeInterval(-86_400))

    var body: some View {
        let p = phase(t, period: 5)
        let open = ease((p - 0.15) / 0.08) * (p > 0.85 ? 1 - ease((p - 0.85) / 0.08) : 1)
        let highlight = p > 0.5 && p < 0.85
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Spacer()
                Image(systemName: "tray.full")
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(open > 0.5 ? 0.15 : 0), in: RoundedRectangle(cornerRadius: 4))
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text("09:41").font(.system(size: 12, weight: .medium))
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .frame(height: 26)
            .background(.thinMaterial)
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    menuRow(L("New Shelf"), shortcut: "⌥⇧␣")
                    menuRow(L("New Shelf From Clipboard"), shortcut: "⌥⇧A")
                    Divider().padding(.vertical, 4)
                    Text(L("Recent Shelves")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.bottom, 2)
                    recentRow(L("%d Images", 4), detail: Self.today, highlighted: highlight)
                    recentRow("Report.pdf", detail: Self.yesterday, highlighted: false)
                }
                .padding(5)
                .frame(width: 230)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .opacity(open)
                .offset(y: CGFloat(1 - open) * -8)
                .padding(.trailing, 92)
            }
            .padding(.top, 4)
            Spacer()
        }
    }

    private func menuRow(_ title: String, shortcut: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut).foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10).padding(.vertical, 3)
    }

    private func recentRow(_ title: String, detail: String, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            FileCard(color: .blue, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11))
                Text(detail).font(.system(size: 9)).opacity(0.7)
            }
            Spacer()
        }
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Try It Out

/// The steps of the guide's demo, driven by a real drag of the example file.
private enum DemoStage {
    case start, shake, drop, finished

    var title: String {
        switch self {
        case .start: L("Try It Out")
        case .shake: L("Give It a Shake")
        case .drop: L("Drop It Onto the Shelf")
        case .finished: L("That's it!")
        }
    }

    var text: String {
        switch self {
        case .start: L("Click and hold the file above to start. You'll see how the shelf appears when you shake your cursor.")
        case .shake: L("While dragging the file, shake your mouse in any direction to create a shelf.")
        case .drop: L("Drag the file onto the shelf and release it.")
        case .finished: L("That's the whole idea. You can close the shelf anytime using the close button.")
        }
    }
}

private struct DemoFile: NSViewRepresentable {
    @Binding var stage: DemoStage

    func makeNSView(context: Context) -> DemoFileView { DemoFileView() }

    func updateNSView(_ view: DemoFileView, context: Context) {
        view.onStage = { stage = $0 }
    }
}

/// The example file of the demo. Our own drags never reach the system-wide drag monitor,
/// so the file watches its drag for a shake itself and opens a real shelf.
private final class DemoFileView: NSView, NSDraggingSource {
    var onStage: (DemoStage) -> Void = { _ in }
    private var detector = ShakeDetector()
    private var shelf: ShelfController?
    private let file: URL = {
        let folder = StashPaths.standard.temporary
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: L("Example") + ".txt")
        if !FileManager.default.fileExists(atPath: url.path) { try? Data("Stash\n".utf8).write(to: url) }
        return url
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: file.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(labelWithString: L("Example"))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64), icon.heightAnchor.constraint(equalToConstant: 64),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: file.path)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 32, y: point.y - 32, width: 64, height: 64), contents: icon)
        detector.reset()
        detector.sensitivity = Prefs.value(Pref.shakeSensitivity, default: .standard)
        beginDraggingSession(with: [item], event: event, source: self)
        onStage(.shake)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard shelf == nil, detector.add(x: screenPoint.x, y: screenPoint.y, time: ProcessInfo.processInfo.systemUptime) else { return }
        let opened = ShelfManager.shared.newShelf(at: .cursor(screenPoint))
        opened.openedByDrag = true
        shelf = opened
        onStage(.drop)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let opened = shelf
        shelf = nil
        Task {
            // Let the drop land before checking the shelf (and closing it if it stayed empty).
            try? await Task.sleep(for: .milliseconds(300))
            let dropped = opened?.model.items.contains { $0.url.standardizedFileURL == file.standardizedFileURL } == true
            ShelfManager.shared.dragEnded()
            onStage(dropped ? .finished : .start)
        }
    }
}
