import AppKit
import SwiftUI

/// Transparent AppKit layer over shelf content: starts multi-item drags out of the shelf
/// and reports clicks, double-clicks and context clicks to SwiftUI.
final class DragSourceView: NSView, NSDraggingSource {
    weak var controller: ShelfController?
    var items: () -> [ShelfItem] = { [] }
    var onClick: (NSEvent) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var contextMenu: (() -> NSMenu?)?
    private var mouseDownEvent: NSEvent?
    private var dragged: [ShelfItem] = []

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        window?.makeKey()
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard mouseDownEvent != nil else { return }
        if event.clickCount == 2 { onDoubleClick() } else { onClick(event) }
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick(event)
        guard let menu = contextMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard hypot(dx, dy) > 3 else { return }
        mouseDownEvent = nil
        dragged = items()
        guard !dragged.isEmpty else { return }
        let origin = convert(down.locationInWindow, from: nil)
        let draggingItems = dragged.enumerated().map { index, item in
            let dragItem = NSDraggingItem(pasteboardWriter: Self.pasteboardItem(for: item))
            let image = ThumbnailCache.shared.image(for: item, size: 64)
            let side: CGFloat = 64
            let offset = CGFloat(index) * 4
            dragItem.setDraggingFrame(NSRect(x: origin.x - side / 2 + offset, y: origin.y - side / 2 - offset, width: side, height: side), contents: image)
            return dragItem
        }
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        if context == .withinApplication { return .copy }
        return Prefs.bool(Pref.alwaysCopy) ? [.copy, .generic] : [.copy, .move, .generic, .link, .delete]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let items = dragged
        dragged = []
        // Dropping on another shelf of ours copies; that is not "moving out".
        let onOwnShelf = NSApp.windows.contains { $0 is ShelfPanel && $0.isVisible && $0.frame.contains(screenPoint) && $0 !== window }
        controller?.dragEnded(items: items, operation: onOwnShelf ? .copy : operation)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }

    /// What a shelf item looks like on a pasteboard: the file, plus its text or link where it has one.
    static func pasteboardItem(for item: ShelfItem) -> NSPasteboardItem {
        let pbItem = NSPasteboardItem()
        pbItem.setString(item.url.absoluteString, forType: .fileURL)
        if let text = item.text { pbItem.setString(text, forType: .string) }
        if let link = item.link {
            pbItem.setString(link.absoluteString, forType: .URL)
            if item.text == nil { pbItem.setString(link.absoluteString, forType: .string) }
        }
        return pbItem
    }
}

/// SwiftUI wrapper for `DragSourceView`.
struct DragSource: NSViewRepresentable {
    let controller: ShelfController
    var items: () -> [ShelfItem]
    var onClick: (NSEvent) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var menu: (() -> NSMenu?)?

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.controller = controller
        view.items = items
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.contextMenu = menu
    }
}

/// An invisible AppKit view that hands itself to `action`, so a menu can pop up from it.
struct MenuAnchor: NSViewRepresentable {
    var label = ""
    var action: (NSView) -> Void

    final class Anchor: NSView {
        var action: (NSView) -> Void = { _ in }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { action(self) }

        // A pop-up button for VoiceOver and other assistive apps.
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
        override func accessibilityPerformPress() -> Bool {
            // The menu runs its own tracking loop; don't hold the accessibility call open meanwhile.
            DispatchQueue.main.async { [weak self] in if let self { self.action(self) } }
            return true
        }
    }

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.action = action
        view.setAccessibilityLabel(label)
    }
}
