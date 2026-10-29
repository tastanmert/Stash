import AppKit
import StashCore

/// Watches system-wide drags and opens a shelf when the cursor is shaken or the
/// activation modifier is held while dragging.
final class DragMonitor {
    static let shared = DragMonitor()

    private var monitors: [Any] = []
    private var detector = ShakeDetector()
    private var changeCountAtMouseDown = 0
    private var isDragging = false
    private var openedThisDrag = false
    /// Notified when a drag of files starts and ends (the notch window listens).
    var onDragStateChange: (Bool) -> Void = { _ in }

    func start() {
        guard monitors.isEmpty else { return }
        let dragPasteboard = NSPasteboard(name: .drag)
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.changeCountAtMouseDown = dragPasteboard.changeCount
                self?.detector.reset()
                self?.openedThisDrag = false
            }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.dragged(event, pasteboard: dragPasteboard) }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.ended() }
        }) { monitors.append(m) }
    }

    private func dragged(_ event: NSEvent, pasteboard: NSPasteboard) {
        // A real drag session writes to the drag pasteboard; plain mouse moves (selecting text, moving windows) don't.
        guard pasteboard.changeCount != changeCountAtMouseDown, PasteboardImporter.canRead(pasteboard) else { return }
        if !isDragging {
            isDragging = true
            onDragStateChange(true)
        }
        guard !openedThisDrag, !isIgnoredApp else { return }
        let location = NSEvent.mouseLocation
        detector.sensitivity = Prefs.value(Pref.shakeSensitivity, default: .standard)
        let shaken = Prefs.bool(Pref.shakeEnabled) && detector.add(x: location.x, y: location.y, time: event.timestamp)
        let modifier: ModifierKey = Prefs.value(Pref.modifierKey, default: .shift)
        let held = Prefs.bool(Pref.modifierEnabled) && event.modifierFlags.contains(modifier.flag)
        guard shaken || held else { return }
        openedThisDrag = true
        let shelf = ShelfManager.shared.newShelf(at: .cursor(location))
        shelf.openedByDrag = true
        InstantActionsDock.shared.show(below: shelf)
    }

    private func ended() {
        guard isDragging else { return }
        isDragging = false
        onDragStateChange(false)
        // Give the drop a moment to land before tidying up empty shelves.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            InstantActionsDock.shared.hide()
            ShelfManager.shared.dragEnded()
        }
    }

    private var isIgnoredApp: Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return Prefs.ignoredApps.contains(id)
    }
}
