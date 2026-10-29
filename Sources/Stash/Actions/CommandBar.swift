import AppKit
import SwiftUI

/// The command bar (⌘K on a shelf): type to find an action and run it on the shelf's files.
final class CommandBar {
    static let shared = CommandBar()
    private var panel: CommandBarPanel?

    func show(for controller: ShelfController) {
        close()
        let items = controller.targetItems
        guard !items.isEmpty else { return NSSound.beep() }
        let model = CommandBarModel(actions: ActionCatalog.applicable(to: items))
        model.run = { [weak self, weak controller] action in
            self?.close()
            guard let controller else { return }
            controller.panel.makeKey()
            action.invoke(on: controller, items: items)
        }
        model.cancel = { [weak self, weak controller] in
            self?.close()
            controller?.panel.makeKey()
        }
        let panel = CommandBarPanel(model: model, below: controller.panel.frame, on: controller.panel.screen)
        panel.onResignKey = { [weak self] in self?.close() }
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.onResignKey = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Extra words an action can be found by, besides its title.
    static let keywords: [String: [String]] = [
        "zip": [L("archive"), L("compress")],
        "copyPath": [L("copy"), L("clipboard"), L("pasteboard"), L("location")],
        "copyTo": [L("copy"), L("destination")],
        "moveTo": [L("destination"), L("location")],
        "trash": [L("delete"), L("remove"), L("trash")],
        "resize": [L("image"), L("change")],
        "convert": [L("image"), L("format"), L("change")],
        "compressImages": [L("image"), L("quality"), L("compress")],
        "stitchImages": [L("image"), L("merge")],
        "imagesToPDF": [L("image")],
        "ocr": [L("image"), L("copy"), L("clipboard")],
        "removeMetadata": [L("image"), L("remove"), L("hide")],
        "stitchPDF": [L("merge")],
        "copyText": [L("copy"), L("clipboard"), L("pasteboard")],
        "airdrop": [L("send")],
        "messages": [L("send")],
        "mail": [L("send")],
    ]
}

@Observable
final class CommandBarModel {
    let actions: [ShelfAction]
    var query = ""
    var highlighted = 0
    @ObservationIgnored var run: (ShelfAction) -> Void = { _ in }
    @ObservationIgnored var cancel: () -> Void = {}

    init(actions: [ShelfAction]) { self.actions = actions }

    struct Group: Identifiable {
        let title: String?
        let actions: [ShelfAction]
        var id: String { title ?? "" }
    }

    /// Recently used and suggested actions, or the matches for what was typed.
    var groups: [Group] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.isEmpty else { return [Group(title: nil, actions: actions.filter { matches($0, text) })] }
        let recent = RecentActions.ids.compactMap { id in actions.first { $0.id == id } }
        let rest = actions.filter { action in !recent.contains { $0.id == action.id } }
        return [Group(title: L("Recently used"), actions: recent), Group(title: L("Suggested"), actions: rest)].filter { !$0.actions.isEmpty }
    }

    var flat: [ShelfAction] { groups.flatMap(\.actions) }

    private func matches(_ action: ShelfAction, _ text: String) -> Bool {
        let words = [action.title, action.category.title] + (CommandBar.keywords[action.id] ?? [])
        return words.contains { $0.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The highlighted row, falling back to the first one when the list got shorter.
    var current: Int { flat.indices.contains(highlighted) ? highlighted : 0 }

    func move(_ step: Int) {
        let count = flat.count
        guard count > 0 else { return }
        highlighted = min(max(current + step, 0), count - 1)
    }

    func runHighlighted() {
        let list = flat
        guard !list.isEmpty else { return NSSound.beep() }
        run(list[current])
    }
}

private final class CommandBarPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(model: CommandBarModel, below shelf: NSRect, on screen: NSScreen?) {
        let size = NSSize(width: 320, height: 340)
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var origin = NSPoint(x: shelf.midX - size.width / 2, y: shelf.minY - size.height - 8)
        if origin.y < visible.minY { origin.y = shelf.maxY + 8 }
        let frame = NSRect(origin: origin, size: size).clamped(to: visible)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: ShelfPanel.shelfLevel.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: CommandBarView(model: model))
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onResignKey?() }
        }
    }

    override var canBecomeKey: Bool { true }
}

struct CommandBarView: View {
    @Bindable var model: CommandBarModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Perform action..."), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { model.runHighlighted() }
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.escape) { model.cancel(); return .handled }
                    .onChange(of: model.query) { model.highlighted = 0 }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let flat = model.flat
                        ForEach(model.groups) { group in
                            if let title = group.title {
                                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                            }
                            ForEach(group.actions) { action in
                                let index = flat.firstIndex { $0.id == action.id } ?? 0
                                CommandBarRow(action: action, highlighted: index == model.current)
                                    .id(action.id)
                                    .onTapGesture { model.run(action) }
                                    .onHover { if $0 { model.highlighted = index } }
                            }
                        }
                        if flat.isEmpty {
                            Text(L("No Actions")).font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.top, 24)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .onChange(of: model.highlighted) {
                    let flat = model.flat
                    if flat.indices.contains(model.highlighted) { proxy.scrollTo(flat[model.highlighted].id) }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { focused = true }
    }
}

private struct CommandBarRow: View {
    let action: ShelfAction
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            ActionIcon(action: action, size: 20)
            Text(action.title + (action.hasOptions ? "…" : "")).font(.system(size: 13))
            Spacer()
            Text(action.category.title).font(.system(size: 11)).foregroundStyle(highlighted ? .white.opacity(0.8) : .secondary)
        }
        .foregroundStyle(highlighted ? .white : .primary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}
