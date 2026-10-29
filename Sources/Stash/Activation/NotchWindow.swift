import AppKit
import SwiftUI

/// A drop zone around the MacBook notch. It only takes mouse events while a drag is going on,
/// so it never gets in the way of the menu bar.
final class NotchController {
    static let shared = NotchController()
    private var windows: [NotchWindow] = []

    func refresh() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard Prefs.bool(Pref.notchEnabled) else { return }
        for screen in NSScreen.screens where screen.safeAreaInsets.top > 0 {
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { continue }
            let notch = NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                               width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            let window = NotchWindow(notch: notch)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func dragStateChanged(_ dragging: Bool) {
        for window in windows { window.setDragging(dragging) }
    }
}

final class NotchWindow: NSPanel {
    let state = NotchState()
    let notch: NSRect

    init(notch: NSRect) {
        self.notch = notch
        // A little wider and taller than the notch so it is easy to hit.
        let frame = NSRect(x: notch.minX - 40, y: notch.minY - 34, width: notch.width + 80, height: notch.height + 34)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NotchDropView(frame: NSRect(origin: .zero, size: frame.size), window: self)
        contentView = view
    }

    func setDragging(_ dragging: Bool) {
        ignoresMouseEvents = !dragging
        state.dragging = dragging
        if !dragging { state.hovering = false }
    }

    func drop(_ pasteboard: NSPasteboard) {
        let items = PasteboardImporter.items(from: pasteboard) { promised in
            ShelfManager.shared.newShelf(items: promised, at: .below(self.notch))
        }
        if !items.isEmpty { ShelfManager.shared.newShelf(items: items, at: .below(notch)) }
    }
}

@Observable final class NotchState {
    var dragging = false
    var hovering = false
}

private final class NotchDropView: NSView {
    weak var notchWindow: NotchWindow?

    init(frame: NSRect, window: NotchWindow) {
        notchWindow = window
        super.init(frame: frame)
        registerForDraggedTypes(PasteboardImporter.acceptedTypes)
        let host = NSHostingView(rootView: NotchGlow(state: window.state, notchSize: window.notch.size))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        notchWindow?.state.hovering = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { notchWindow?.state.hovering = false }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        notchWindow?.state.hovering = false
        notchWindow?.drop(sender.draggingPasteboard)
        return true
    }
}

/// The ring drawn around the notch while dragging.
private struct NotchGlow: View {
    let state: NotchState
    let notchSize: CGSize
    @AppStorage(Pref.notchHighlight) private var highlight = NotchHighlight.hover.rawValue

    var body: some View {
        let mode = NotchHighlight(rawValue: highlight) ?? .hover
        let visible = state.dragging && (mode == .always || (mode == .hover && state.hovering))
        VStack {
            UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                .fill(Color.black)
                .overlay {
                    UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                        .strokeBorder(Color.accentColor, lineWidth: state.hovering ? 3 : 2)
                }
                .overlay(alignment: .bottom) {
                    if state.hovering {
                        Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.white).padding(.bottom, 6)
                    }
                }
                .frame(width: notchSize.width + (state.hovering ? 40 : 16), height: notchSize.height + (state.hovering ? 30 : 8))
                .shadow(color: .accentColor.opacity(0.6), radius: state.hovering ? 10 : 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(visible ? 1 : 0)
        .animation(.spring(duration: 0.25), value: visible)
        .animation(.spring(duration: 0.25), value: state.hovering)
    }
}
