import AppKit
import Carbon.HIToolbox
import QuickLookUI
import SwiftUI
import StashCore

/// Owns one shelf: its floating panel, its items and everything you can do with them.
final class ShelfController: NSObject {
    static let stackSize = NSSize(width: 198, height: 207)
    /// The size of the item list.
    static let detailSize = NSSize(width: 400, height: 304)
    /// Options pages of actions, which need more height for their forms.
    static let actionSize = NSSize(width: 330, height: 420)

    let model: ShelfModel
    let panel: ShelfPanel
    private(set) var dockedEdge: NSRectEdge?
    private var undockedFrame: NSRect?
    private var isPeeking = false
    private var toastTask: Task<Void, Never>?
    private var snapTask: Task<Void, Never>?
    private var hasReceivedDrop = false
    /// Set while this shelf was opened by a drag that is still going on.
    var openedByDrag = false

    init(model: ShelfModel = ShelfModel(), origin: NSPoint) {
        self.model = model
        panel = ShelfPanel(contentRect: NSRect(origin: origin, size: Self.stackSize))
        super.init()
        panel.controller = self
        let host = ShelfHostView(controller: self)
        panel.contentView = host
        applySpaceBehavior()
        NotificationCenter.default.addObserver(self, selector: #selector(shelfDidMove), name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(shelfDidResignKey), name: NSWindow.didResignKeyNotification, object: panel)
    }

    var manager: ShelfManager { .shared }

    // MARK: Showing and closing

    func show() {
        panel.alphaValue = 0
        if Prefs.bool(Pref.takeFocus) {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    /// Closes the shelf. With `clearing` (⌥ held) the items are dropped instead of kept in Recent Shelves.
    func close(clearing: Bool = false) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible, QLPreviewPanel.shared().dataSource === self {
            QLPreviewPanel.shared().orderOut(nil)
        }
        manager.shelfWillClose(self, remember: !clearing)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }) { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    func applySpaceBehavior() {
        let restrict = model.keepInOwnSpace || Prefs.bool(Pref.restrictToSpace)
        panel.collectionBehavior = restrict ? [.fullScreenAuxiliary] : [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // MARK: Items

    func add(_ new: [ShelfItem]) {
        let existing = Set(model.items.map(\.url.standardizedFileURL))
        let fresh = new.filter { !existing.contains($0.url.standardizedFileURL) }
        if fresh.count < new.count, fresh.isEmpty { showToast(L("One or more items is already present in the shelf")) }
        guard !fresh.isEmpty else { return }
        withAnimation(.spring(duration: 0.3)) { model.items.append(contentsOf: fresh) }
        manager.didActivate(self)
        manager.itemsChanged(self)
        if !hasReceivedDrop {
            hasReceivedDrop = true
            if Prefs.bool(Pref.retractAfterDrop), dockedEdge == nil { dock(to: nearestEdge) }
        }
        TitleGenerator.suggestTitle(for: model)
    }

    func add(from pasteboard: NSPasteboard) {
        let items = PasteboardImporter.items(from: pasteboard) { [weak self] promised in self?.add(promised) }
        add(items)
    }

    func remove(_ ids: Set<UUID>) {
        withAnimation(.spring(duration: 0.25)) {
            model.items.removeAll { ids.contains($0.id) }
            model.selection.subtract(ids)
        }
        manager.itemsChanged(self)
        if model.items.isEmpty, model.page == .items { model.page = .stack; resize() }
    }

    func clear() {
        remove(Set(model.items.map(\.id)))
    }

    func addFromClipboard() {
        let items = PasteboardImporter.items(from: .general) { [weak self] promised in self?.add(promised) }
        if items.isEmpty { NSSound.beep() } else { add(items) }
    }

    /// Called by the drag source after items were dragged out of the shelf.
    func dragEnded(items: [ShelfItem], operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        let moved = operation.contains(.move) || operation.contains(.delete) || items.contains { !$0.exists }
        let mode: CloseOnDragOut = Prefs.value(Pref.closeOnDragOut, default: .moved)
        if moved { remove(Set(items.map(\.id))) }
        switch mode {
        case .always: if model.items.isEmpty || items.count == model.items.count || moved { close() }
        case .moved: if moved, model.items.isEmpty { close() }
        case .never: if model.items.isEmpty { close() }
        }
    }

    // MARK: Pages and size

    func showPage(_ page: ShelfPage) {
        withAnimation(.spring(duration: 0.3)) { model.page = page }
        resize()
        if page != .stack { panel.makeKey() }
    }

    func toggleItemsPage() { showPage(model.page == .stack ? .items : .stack) }

    func resize() {
        let size = switch model.page {
        case .stack: Self.stackSize
        case .items: Self.detailSize
        case .action: Self.actionSize
        }
        var frame = panel.frame
        guard frame.size != size else { return }
        // Keep the top edge in place, and the edge the shelf sits against.
        let top = frame.maxY
        let rightAligned = frame.midX > (panel.screen ?? NSScreen.main!).visibleFrame.midX
        if rightAligned { frame.origin.x = frame.maxX - size.width }
        frame.size = size
        frame.origin.y = top - size.height
        frame = frame.clamped(to: (panel.screen ?? NSScreen.main!).visibleFrame)
        panel.setFrame(frame, display: true, animate: true)
    }

    // MARK: File actions

    var targetItems: [ShelfItem] { model.selectedItems }

    func open(_ items: [ShelfItem]? = nil) {
        let items = items ?? targetItems
        if items.count > 3, !confirm(L("You are about to open %i files", items.count), L("Depending on the files, this might open multiple applications and could have performance impact. Do you want to proceed?")) { return }
        for item in items { NSWorkspace.shared.open(item.url) }
        finishAction()
    }

    func open(_ items: [ShelfItem], with app: URL) {
        NSWorkspace.shared.open(items.map(\.url), withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        finishAction()
    }

    func reveal(_ items: [ShelfItem]? = nil) {
        let items = items ?? targetItems
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    func copyToPasteboard(_ items: [ShelfItem]? = nil) {
        let items = items ?? targetItems
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { DragSourceView.pasteboardItem(for: $0) })
        showToast(items.count == 1 ? L("Copied to clipboard") : L("%d items copied to clipboard", items.count))
    }

    func moveToNewShelf(_ items: [ShelfItem]? = nil) {
        let items = items ?? targetItems
        remove(Set(items.map(\.id)))
        let shelf = manager.newShelf(items: items.map { ShelfItem(url: $0.url, text: $0.text, link: $0.link, isTemporary: $0.isTemporary) },
                                     at: .near(panel.frame))
        shelf.panel.makeKey()
        if model.items.isEmpty { close() }
    }

    func beginRename(_ item: ShelfItem) {
        if model.page == .stack { showPage(.items) }
        model.selection = [item.id]
        model.renamingID = item.id
    }

    func rename(_ item: ShelfItem, to newName: String) {
        model.renamingID = nil
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        guard !trimmed.contains("/"), !trimmed.contains(":") else { return alert(L("Invalid name"), L("The filename contains a character that cannot be used.")) }
        guard trimmed.utf8.count <= 255 else { return alert(L("Invalid name"), L("The filename is too long.")) }
        let target = item.url.deletingLastPathComponent().appending(path: trimmed)
        guard !FileManager.default.fileExists(atPath: target.path) else { return alert(L("File already exists"), L("A file with this name already exists. Choose a different name.")) }
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            if let i = model.items.firstIndex(where: { $0.id == item.id }) {
                ThumbnailCache.shared.forget(item.url)
                model.items[i].url = target
            }
            manager.itemsChanged(self)
        } catch {
            alert(L("Move failed"), error.localizedDescription)
        }
    }

    func performDoubleClick(on item: ShelfItem) {
        switch Prefs.value(Pref.doubleClickFiles, default: DoubleClickFiles.reveal) {
        case .reveal: reveal(model.selection.contains(item.id) ? targetItems : [item])
        case .open: open(model.selection.contains(item.id) ? targetItems : [item])
        case .quickLook: quickLook()
        case .none: break
        }
    }

    /// Set while an instant action dropped on this shelf's dock runs.
    var runningInstantAction = false

    /// Whether the shelf is about to close once the running action succeeds.
    var willCloseAfterAction: Bool {
        runningInstantAction && Prefs.value(Pref.afterAction, default: AfterAction.close) == .close
    }

    /// After a successful instant action the shelf closes or stays, as set in Settings.
    func finishAction() {
        guard runningInstantAction else { return }
        let closing = willCloseAfterAction
        runningInstantAction = false
        if closing { close() }
    }

    /// Points the shelf at rewritten files (an action that replaced its originals).
    func replaceItems(with urls: [URL]) {
        let byName = Dictionary(urls.map { ($0.deletingPathExtension().path, $0) }, uniquingKeysWith: { a, _ in a })
        for index in model.items.indices {
            guard let url = byName[model.items[index].url.deletingPathExtension().path] else { continue }
            ThumbnailCache.shared.forget(model.items[index].url)
            model.items[index].url = url
        }
        manager.itemsChanged(self)
    }

    /// Items that were moved elsewhere on disk keep their place on the shelf.
    func relocate(_ items: [ShelfItem], to urls: [URL]) {
        for (item, url) in zip(items, urls) {
            guard let index = model.items.firstIndex(where: { $0.id == item.id }) else { continue }
            ThumbnailCache.shared.forget(item.url)
            model.items[index].url = url
        }
        manager.itemsChanged(self)
    }

    // MARK: Quick Look

    func quickLook() {
        guard !model.items.isEmpty else { return }
        NSApp.activate()
        panel.makeKey()
        let ql = QLPreviewPanel.shared()!
        if ql.isVisible { ql.orderOut(nil) } else { ql.makeKeyAndOrderFront(nil) }
    }

    // MARK: Shelf settings

    func setPinned(_ pinned: Bool) {
        model.pinned = pinned
        manager.itemsChanged(self)
    }

    func setColor(_ index: Int?) {
        model.colorIndex = index
        manager.itemsChanged(self)
    }

    func setAlwaysShowIndicator(_ value: Bool) {
        model.alwaysShowIndicator = value
        manager.itemsChanged(self)
    }

    func setKeepInOwnSpace(_ value: Bool) {
        model.keepInOwnSpace = value
        applySpaceBehavior()
    }

    // MARK: Docking

    var nearestEdge: NSRectEdge {
        let screen = (panel.screen ?? NSScreen.main!).visibleFrame
        return panel.frame.midX < screen.midX ? .minX : .maxX
    }

    func toggleDock() {
        if dockedEdge == nil { dock(to: nearestEdge) } else { undock() }
    }

    func dock(to edge: NSRectEdge) {
        if model.page != .stack { showPage(.stack) }
        undockedFrame = panel.frame
        dockedEdge = edge
        model.isDocked = true
        panel.setFrame(dockedFrame(for: edge), display: true, animate: true)
    }

    func undock() {
        guard dockedEdge != nil else { return }
        dockedEdge = nil
        isPeeking = false
        model.isDocked = false
        let screen = (panel.screen ?? NSScreen.main!).visibleFrame
        let target = (undockedFrame ?? panel.frame).clamped(to: screen)
        panel.setFrame(target, display: true, animate: true)
    }

    private func dockedFrame(for edge: NSRectEdge) -> NSRect {
        let screen = (panel.screen ?? NSScreen.main!).visibleFrame
        var frame = panel.frame
        let visible: CGFloat = 26
        frame.origin.x = edge == .minX ? screen.minX - frame.width + visible : screen.maxX - visible
        frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        return frame
    }

    private func peekFrame(for edge: NSRectEdge) -> NSRect {
        let screen = (panel.screen ?? NSScreen.main!).visibleFrame
        var frame = panel.frame
        frame.origin.x = edge == .minX ? screen.minX + 8 : screen.maxX - frame.width - 8
        return frame
    }

    /// Slides a docked shelf out while the pointer (or a drag) is over it.
    func setPeeking(_ peek: Bool) {
        guard let edge = dockedEdge, peek != isPeeking else { return }
        isPeeking = peek
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(peek ? peekFrame(for: edge) : dockedFrame(for: edge), display: true)
        }
    }

    func edgeDoubleClicked() {
        switch Prefs.value(Pref.doubleClickEdge, default: EdgeAction.dock) {
        case .dock, .retract: toggleDock()
        case .none: break
        }
    }

    @objc private func shelfDidMove(_ note: Notification) {
        guard dockedEdge == nil, Prefs.bool(Pref.snapIntoPlace), !NSEvent.modifierFlags.contains(.command) else { return }
        snapTask?.cancel()
        snapTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, NSEvent.pressedMouseButtons == 0 else { return }
            self?.snap()
        }
    }

    @objc private func shelfDidResignKey(_ note: Notification) {
        guard Prefs.bool(Pref.closeDetailOutside), model.page != .stack, !QLPreviewPanel.sharedPreviewPanelExists() || !QLPreviewPanel.shared().isVisible else { return }
        showPage(.stack)
    }

    /// Aligns the shelf with the closest screen edge or another shelf.
    private func snap() {
        let screen = (panel.screen ?? NSScreen.main!).visibleFrame
        var frame = panel.frame
        let threshold: CGFloat = 40, margin: CGFloat = 12
        if frame.minX - screen.minX < threshold { frame.origin.x = screen.minX + margin }
        if screen.maxX - frame.maxX < threshold { frame.origin.x = screen.maxX - frame.width - margin }
        if screen.maxY - frame.maxY < threshold { frame.origin.y = screen.maxY - frame.height - margin }
        if frame.minY - screen.minY < threshold { frame.origin.y = screen.minY + margin }
        for other in manager.controllers where other !== self {
            let o = other.panel.frame
            if abs(frame.minX - o.minX) < threshold, abs(frame.maxY - o.minY) < threshold { frame.origin = NSPoint(x: o.minX, y: o.minY - frame.height - margin) }
            if abs(frame.minX - o.minX) < threshold, abs(frame.minY - o.maxY) < threshold { frame.origin = NSPoint(x: o.minX, y: o.maxY + margin) }
        }
        if frame != panel.frame { panel.setFrame(frame, display: true, animate: true) }
    }

    // MARK: Keyboard

    /// Shelf shortcuts; they work while the shelf is the key window.
    func handleKey(_ event: NSEvent) -> Bool {
        if model.renamingID != nil { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // The item list keeps Finder's keys: Return renames, Delete removes the selection, Esc goes back.
        if model.page != .stack, mods.isEmpty {
            switch Int(event.keyCode) {
            case kVK_Return where model.selection.count == 1:
                if let first = model.selectedItems.first { beginRename(first) }
                return true
            case kVK_Delete where !model.selection.isEmpty, kVK_ForwardDelete where !model.selection.isEmpty:
                remove(model.selection)
                return true
            case kVK_Escape:
                showPage(.stack)
                return true
            default: break
            }
        }
        let pressed = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
        if let action = KeyboardAction.shelf.first(where: { $0.activeCombo == pressed }) {
            perform(action)
            return true
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (mods, key, Int(event.keyCode)) {
        case (.command, "a", _): model.selection = Set(model.items.map(\.id))
        case (.command, _, kVK_Delete): if !model.selection.isEmpty { remove(model.selection) } else if model.items.count == 1 { clear() }
        case (.command, "o", _): open()
        case (.command, "r", _): reveal()
        case ([], _, kVK_LeftArrow), ([], _, kVK_RightArrow), ([], _, kVK_DownArrow), ([], _, kVK_UpArrow): moveSelection(event.keyCode)
        default: return false
        }
        return true
    }

    func perform(_ action: KeyboardAction) {
        switch action {
        case .close: close()
        case .quickLook: quickLook()
        case .dock: toggleDock()
        case .dockLeft: dockedEdge == .minX ? undock() : dock(to: .minX)
        case .dockRight: dockedEdge == .maxX ? undock() : dock(to: .maxX)
        case .commandBar: CommandBar.shared.show(for: self)
        case .clearContents: clear()
        case .copyContents: copyToPasteboard()
        case .pasteContents: addFromClipboard()
        case .actionMenu: showActionMenu()
        case .openDetailView: toggleItemsPage()
        default: action.perform()
        }
    }

    /// Pops up the overflow menu under the shelf's top-right button.
    func showActionMenu() {
        guard let view = panel.contentView else { return }
        let y = view.isFlipped ? 48 : view.bounds.height - 48
        ShelfMenu.make(for: self).popUp(positioning: nil, at: NSPoint(x: view.bounds.width - 46, y: y), in: view)
    }

    private func moveSelection(_ keyCode: UInt16) {
        guard !model.items.isEmpty else { return }
        let ids = model.items.map(\.id)
        let current = ids.lastIndex { model.selection.contains($0) } ?? -1
        let step = (keyCode == 123 || keyCode == 126) ? -1 : 1
        let next = min(max(current + step, 0), ids.count - 1)
        model.selection = [ids[next]]
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { QLPreviewPanel.shared().reloadData() }
    }

    func optionKeyChanged(_ down: Bool) {
        if model.isOptionDown != down { model.isOptionDown = down }
    }

    // MARK: Messages

    func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation { model.toast = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation { self?.model.toast = nil }
        }
    }

    func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.beginSheetModal(for: panel)
    }

    func confirm(_ title: String, _ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("Continue"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Quick Look

extension ShelfController: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    private var previewItems: [ShelfItem] {
        let selected = model.items.filter { model.selection.contains($0.id) }
        return selected.isEmpty ? model.items : selected
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewItems.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewItems[index].url as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        return handleKey(event)
    }
}

extension NSRect {
    func clamped(to bounds: NSRect) -> NSRect {
        var r = self
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }
}
