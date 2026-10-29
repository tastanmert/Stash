import AppKit
import SwiftUI

/// "Select Shelf": dims the screen, puts a letter on every visible shelf and activates the one whose letter you press.
final class ShelfSelector {
    static let shared = ShelfSelector()
    private static let letters = Array("ASDFGHJKLQWERTYUIOPZXCVBNM")

    private var dimmers: [NSWindow] = []
    private var hints: [NSWindow] = []
    private var targets: [Character: ShelfController] = [:]

    var isActive: Bool { !dimmers.isEmpty }

    func begin() {
        end()
        let shelves = ShelfManager.shared.visibleShelves.sorted {
            $0.panel.frame.minX != $1.panel.frame.minX ? $0.panel.frame.minX < $1.panel.frame.minX : $0.panel.frame.maxY > $1.panel.frame.maxY
        }
        guard !shelves.isEmpty else { NSSound.beep(); return }
        guard shelves.count > 1 else { return activate(shelves[0]) }

        for screen in NSScreen.screens {
            let dimmer = KeyCaptureWindow(frame: screen.frame) { [weak self] event in self?.handle(event) }
            dimmer.onClick = { [weak self] in self?.end() }
            dimmers.append(dimmer)
        }
        for (shelf, letter) in zip(shelves, Self.letters) {
            targets[letter] = shelf
            hints.append(HintWindow(letter: letter, over: shelf.panel.frame))
        }
        NSApp.activate()
        dimmers.forEach { $0.orderFrontRegardless() }
        dimmers.first?.makeKey()
        hints.forEach { $0.orderFrontRegardless() }
    }

    func end() {
        (dimmers + hints).forEach { $0.orderOut(nil) }
        dimmers.removeAll()
        hints.removeAll()
        targets.removeAll()
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { return end() }
        guard let char = event.charactersIgnoringModifiers?.uppercased().first, let shelf = targets[char] else { return NSSound.beep() }
        // Hand the keyboard to the shelf before the capture window goes away.
        activate(shelf)
        end()
    }

    private func activate(_ shelf: ShelfController) {
        if shelf.dockedEdge != nil { shelf.undock() }
        NSApp.activate()
        shelf.panel.makeKeyAndOrderFront(nil)
        ShelfManager.shared.didActivate(shelf)
    }
}

/// A full-screen dimming window that takes the keyboard while shelves are being picked.
private final class KeyCaptureWindow: NSWindow {
    let onKey: (NSEvent) -> Void
    var onClick: () -> Void = {}

    init(frame: NSRect, onKey: @escaping (NSEvent) -> Void) {
        self.onKey = onKey
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: ShelfPanel.shelfLevel.rawValue - 1)
        backgroundColor = NSColor.black.withAlphaComponent(0.25)
        isOpaque = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onKey(event) }
    override func mouseDown(with event: NSEvent) { onClick() }
}

/// The letter shown in the middle of a shelf.
private final class HintWindow: NSPanel {
    init(letter: Character, over shelf: NSRect) {
        let size = NSSize(width: 64, height: 64)
        let frame = NSRect(x: shelf.midX - size.width / 2, y: shelf.midY - size.height / 2, width: size.width, height: size.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: ShelfPanel.shelfLevel.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView:
            Text(String(letter))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size.width, height: size.height)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
    }
}
