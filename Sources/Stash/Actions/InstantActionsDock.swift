import AppKit
import SwiftUI

@Observable
final class InstantDockModel {
    var actions: [ShelfAction] = []
    var highlighted: Int?
}

/// Instant action tiles under a shelf opened by a drag. Dropping files on a tile runs that action.
final class InstantActionsDock {
    static let shared = InstantActionsDock()
    static let tile = NSSize(width: 70, height: 64)
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 8

    private let model = InstantDockModel()
    private var panel: NSPanel?
    private weak var shelf: ShelfController?

    /// The actions chosen in Settings, in order, when instant actions are on.
    static var configuredActions: [ShelfAction] {
        guard Prefs.bool(Pref.instantActionsEnabled) else { return [] }
        return (UserDefaults.standard.stringArray(forKey: Pref.instantActions) ?? []).compactMap(ActionCatalog.action)
    }

    func show(below shelf: ShelfController) {
        let actions = Self.configuredActions
        guard !actions.isEmpty else { return }
        self.shelf = shelf
        model.actions = actions
        model.highlighted = nil
        let count = CGFloat(actions.count)
        let size = NSSize(width: count * Self.tile.width + (count - 1) * Self.spacing + Self.padding * 2,
                          height: Self.tile.height + Self.padding * 2)
        let panel = self.panel ?? makePanel()
        panel.setFrame(frame(for: size, near: shelf.panel), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        self.panel = panel
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        model.highlighted = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    /// Below the shelf, or above it when there is no room underneath.
    private func frame(for size: NSSize, near shelf: NSWindow) -> NSRect {
        let area = (shelf.screen ?? NSScreen.main!).visibleFrame
        let anchor = shelf.frame
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - 10 - size.height)
        if origin.y < area.minY { origin.y = anchor.maxY + 10 }
        origin.x = min(max(origin.x, area.minX + 8), area.maxX - size.width - 8)
        return NSRect(origin: origin, size: size)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = ShelfPanel.shelfLevel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = InstantDockDropView(model: model) { [weak self] index, pasteboard in
            self?.perform(index, from: pasteboard)
        }
        return panel
    }

    private func perform(_ index: Int, from pasteboard: NSPasteboard) {
        guard let shelf, model.actions.indices.contains(index) else { return }
        let action = model.actions[index]
        let items = PasteboardImporter.items(from: pasteboard) { [weak shelf] promised in
            guard let shelf else { return }
            shelf.add(promised)
            shelf.runningInstantAction = true
            action.perform(shelf, promised)
        }
        hide()
        guard !items.isEmpty else { return }
        // The files land on the shelf first, so they stay there if the action fails.
        shelf.add(items)
        shelf.runningInstantAction = true
        RecentActions.record(action.id)
        action.perform(shelf, items)
    }
}

/// Accepts drops on the tiles and tracks which tile is under the cursor.
private final class InstantDockDropView: NSView {
    let model: InstantDockModel
    let onDrop: (Int, NSPasteboard) -> Void

    init(model: InstantDockModel, onDrop: @escaping (Int, NSPasteboard) -> Void) {
        self.model = model
        self.onDrop = onDrop
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes(PasteboardImporter.acceptedTypes)
        let host = NSHostingView(rootView: InstantDockView(model: model))
        host.autoresizingMask = [.width, .height]
        host.sizingOptions = []
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }

    private func tile(at info: any NSDraggingInfo) -> Int? {
        let x = convert(info.draggingLocation, from: nil).x - InstantActionsDock.padding
        let stride = InstantActionsDock.tile.width + InstantActionsDock.spacing
        let index = Int(floor(x / stride))
        let inside = x - CGFloat(index) * stride <= InstantActionsDock.tile.width
        return inside && model.actions.indices.contains(index) ? index : nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let index = tile(at: sender)
        if model.highlighted != index { model.highlighted = index }
        return index == nil ? [] : .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { model.highlighted = nil }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let index = tile(at: sender) else { return false }
        model.highlighted = nil
        onDrop(index, sender.draggingPasteboard)
        return true
    }
}

private struct InstantDockView: View {
    let model: InstantDockModel

    var body: some View {
        HStack(spacing: InstantActionsDock.spacing) {
            ForEach(Array(model.actions.enumerated()), id: \.offset) { index, action in
                let on = model.highlighted == index
                VStack(spacing: 6) {
                    Image(systemName: action.symbol).font(.system(size: 20, weight: .medium))
                    Text(action.title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(on ? Color.white : ShelfStyle.glyph)
                .frame(width: InstantActionsDock.tile.width, height: InstantActionsDock.tile.height)
                .background(on ? Color.accentColor : ShelfStyle.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(on ? 1.06 : 1)
            }
        }
        .padding(InstantActionsDock.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShelfStyle.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(duration: 0.2), value: model.highlighted)
    }
}
