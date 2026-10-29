import AppKit
import QuickLookUI
import SwiftUI

/// The borderless floating window of a shelf. It never activates the app unless it has to.
final class ShelfPanel: NSPanel {
    weak var controller: ShelfController?
    /// The utility window level, so shelves float above ordinary windows.
    static let shelfLevel = NSWindow.Level(rawValue: 19)

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = Self.shelfLevel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        controller?.optionKeyChanged(event.modifierFlags.contains(.option))
        super.flagsChanged(with: event)
    }

    // Quick Look panel control.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = controller
            panel.delegate = controller
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

/// Root view of a shelf panel: accepts drops and hosts the SwiftUI content.
final class ShelfHostView: NSView {
    weak var controller: ShelfController?
    /// The utility window level, so shelves float above ordinary windows.
    static let shelfLevel = NSWindow.Level(rawValue: 19)
    private var tracking: NSTrackingArea?
    private var flagsMonitor: Any?

    init(controller: ShelfController) {
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: ShelfController.stackSize))
        autoresizingMask = [.width, .height]
        registerForDraggedTypes(PasteboardImporter.acceptedTypes)
        let host = NSHostingView(rootView: ShelfRootView(model: controller.model, controller: controller))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        host.sizingOptions = []
        addSubview(host)
        // The option key changes the close button into "clear and close" even when the shelf isn't key.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.controller?.optionKeyChanged(event.modifierFlags.contains(.option))
            return event
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        controller?.optionKeyChanged(NSEvent.modifierFlags.contains(.option))
        controller?.setPeeking(true)
    }

    override func mouseExited(with event: NSEvent) { controller?.setPeeking(false) }

    // MARK: Dropping onto the shelf

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isExternal(sender), PasteboardImporter.canRead(sender.draggingPasteboard) else { return [] }
        controller?.setPeeking(true)
        withAnimation(.easeOut(duration: 0.15)) { controller?.model.isDropTargeted = true }
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isExternal(sender) ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        withAnimation(.easeOut(duration: 0.15)) { controller?.model.isDropTargeted = false }
        controller?.setPeeking(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        withAnimation(.easeOut(duration: 0.15)) { controller?.model.isDropTargeted = false }
        controller?.add(from: sender.draggingPasteboard)
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        controller?.setPeeking(false)
    }

    /// Drags that start on this same shelf are ignored.
    private func isExternal(_ info: any NSDraggingInfo) -> Bool {
        (info.draggingSource as? DragSourceView)?.controller !== controller
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { controller?.edgeDoubleClicked() }
        super.mouseDown(with: event)
    }
}
