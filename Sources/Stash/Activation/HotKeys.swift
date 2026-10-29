import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, stored as "keyCode:modifiers" in UserDefaults.
struct KeyCombo: Hashable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    static func == (a: KeyCombo, b: KeyCombo) -> Bool { a.keyCode == b.keyCode && a.modifiers == b.modifiers }
    func hash(into hasher: inout Hasher) { hasher.combine(keyCode); hasher.combine(modifiers.rawValue) }

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift])
    }

    init?(string: String) {
        let parts = string.split(separator: ":").compactMap { UInt($0) }
        guard parts.count == 2 else { return nil }
        self.init(keyCode: UInt32(parts[0]), modifiers: NSEvent.ModifierFlags(rawValue: parts[1]))
    }

    var string: String { "\(keyCode):\(modifiers.rawValue)" }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// "⌃⌥Space"
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    var isValid: Bool { !modifiers.intersection([.command, .option, .control]).isEmpty }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }
        if let fn = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12].firstIndex(of: Int(code)) {
            return "F\(fn + 1)"
        }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let layout = unsafeBitCast(data, to: CFData.self)
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Keyboard shortcuts: global ones work everywhere, shelf ones while a shelf is the key window.
/// Each default can be turned off or reassigned in Settings.
enum KeyboardAction: String, CaseIterable, Identifiable {
    // Global
    case newShelf, newClipboardShelf, selectShelf, reopenLastClosed, toggleDocking, closeAll
    // Shelf
    case close, quickLook, dock, dockLeft, dockRight, commandBar, clearContents, copyContents, pasteContents, actionMenu, openDetailView

    var id: String { rawValue }

    static var global: [KeyboardAction] { allCases.filter(\.isGlobal) }
    static var shelf: [KeyboardAction] { allCases.filter { !$0.isGlobal } }

    var isGlobal: Bool {
        switch self {
        case .newShelf, .newClipboardShelf, .selectShelf, .reopenLastClosed, .toggleDocking, .closeAll: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .newShelf: L("New Shelf")
        case .newClipboardShelf: L("New Clipboard Shelf")
        case .selectShelf: L("Select Shelf")
        case .reopenLastClosed: L("Reopen Last Closed Shelf")
        case .toggleDocking: L("Toggle Docking for All Shelves")
        case .closeAll: L("Close All Shelves")
        case .close: L("Close")
        case .quickLook: L("Quick Look")
        case .dock: L("Dock to Nearest Edge")
        case .dockLeft: L("Dock to Left Edge")
        case .dockRight: L("Dock to Right Edge")
        case .commandBar: L("Open Command Bar")
        case .clearContents: L("Clear Shelf Content")
        case .copyContents: L("Copy Shelf Content")
        case .pasteContents: L("Paste")
        case .actionMenu: L("Open Action Menu")
        case .openDetailView: L("Open Detail View")
        }
    }

    var defaultsKey: String { "hotkey.\(rawValue)" }
    private var enabledKey: String { "hotkey.\(rawValue).enabled" }

    var defaultCombo: KeyCombo {
        let shiftOption: NSEvent.ModifierFlags = [.option, .shift]
        return switch self {
        case .newShelf: KeyCombo(keyCode: UInt32(kVK_Space), modifiers: shiftOption)
        case .newClipboardShelf: KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: shiftOption)
        case .selectShelf: KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: shiftOption)
        case .reopenLastClosed: KeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: shiftOption)
        case .toggleDocking: KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: shiftOption)
        case .closeAll: KeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: [.control, .option])
        case .close: KeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: .command)
        case .quickLook: KeyCombo(keyCode: UInt32(kVK_Space), modifiers: [])
        case .dock: KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: .shift)
        case .dockLeft: KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: .shift)
        case .dockRight: KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: .shift)
        case .commandBar: KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: .command)
        case .clearContents: KeyCombo(keyCode: UInt32(kVK_Delete), modifiers: [])
        case .copyContents: KeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: .command)
        case .pasteContents: KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: .command)
        case .actionMenu: KeyCombo(keyCode: UInt32(kVK_Return), modifiers: [])
        case .openDetailView: KeyCombo(keyCode: UInt32(kVK_Tab), modifiers: [])
        }
    }

    private var enabledByDefault: Bool {
        switch self {
        case .reopenLastClosed, .toggleDocking, .closeAll, .openDetailView: false
        default: true
        }
    }

    var combo: KeyCombo {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(KeyCombo.init(string:)) ?? defaultCombo }
        nonmutating set { UserDefaults.standard.set(newValue.string, forKey: defaultsKey) }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? enabledByDefault }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// The combination while the shortcut is turned on.
    var activeCombo: KeyCombo? { isEnabled ? combo : nil }

    func restoreDefault() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: enabledKey)
    }

    /// Shelf shortcuts may be a bare key (Space, Return); global ones need ⌘, ⌃ or ⌥.
    func accepts(_ combo: KeyCombo) -> Bool { !isGlobal || combo.isValid }

    /// Another enabled action of the same kind that already uses `combo`.
    func conflict(with combo: KeyCombo) -> KeyboardAction? {
        Self.allCases.first { $0 != self && $0.isGlobal == isGlobal && $0.activeCombo == combo }
    }

    func perform() {
        let manager = ShelfManager.shared
        switch self {
        case .newShelf: manager.newShelf().panel.makeKey()
        case .newClipboardShelf: manager.newShelfFromClipboard()
        case .selectShelf: ShelfSelector.shared.begin()
        case .reopenLastClosed: manager.reopenLastClosed()
        case .toggleDocking: manager.toggleDockingAll()
        case .closeAll: manager.closeAll()
        default: break
        }
    }
}

/// Registers the global `KeyboardAction` shortcuts with Carbon (no Accessibility permission needed).
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false
    /// While a shortcut is being recorded in Settings, hot keys are paused.
    var paused = false { didSet { paused ? unregisterAll() : registerAll() } }

    func registerAll() {
        unregisterAll()
        installHandler()
        for (index, action) in KeyboardAction.allCases.enumerated() where action.isGlobal {
            guard let combo = action.activeCombo else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x53_54_53_48), id: UInt32(index)) // 'STSH'
            if RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    /// Whether the system (or another app) already owns this combination.
    func isTakenBySystem(_ combo: KeyCombo) -> Bool {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x54_45_53_54), id: 999)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if let ref { UnregisterEventHotKey(ref) }
        return status != noErr
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if KeyboardAction.allCases.indices.contains(index) { KeyboardAction.allCases[index].perform() }
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
