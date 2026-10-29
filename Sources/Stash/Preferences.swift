import AppKit
import StashCore

/// UserDefaults keys. SwiftUI reads them through @AppStorage; AppKit code through `Prefs`.
enum Pref {
    static let shakeEnabled = "shakeEnabled"
    static let shakeSensitivity = "shakeSensitivity"
    static let modifierEnabled = "modifierEnabled"
    static let modifierKey = "modifierKey"
    static let notchEnabled = "notchEnabled"
    static let notchHighlight = "notchHighlight"
    static let shelfLocation = "shelfLocation"
    static let addingBehavior = "addingBehavior"
    static let ignoredApps = "ignoredApps"
    static let doubleClickFiles = "doubleClickFiles"
    static let doubleClickEdge = "doubleClickEdge"
    static let closeOnDragOut = "closeOnDragOut"
    static let intelligentNames = "intelligentNames"
    static let snapIntoPlace = "snapIntoPlace"
    static let retractAfterDrop = "retractAfterDrop"
    static let alwaysCopy = "alwaysCopy"
    static let plainText = "plainText"
    static let restrictToSpace = "restrictToSpace"
    static let shelfColors = "shelfColors"
    static let takeFocus = "takeFocus"
    static let closeDetailOutside = "closeDetailOutside"
    static let showInMenuBar = "showInMenuBar"
    static let menuBarIcon = "menuBarIcon"
    static let showInDock = "showInDock"
    static let hasLaunched = "hasLaunched"
    static let displayMode = "displayMode"
    static let instantActionsEnabled = "instantActionsEnabled"
    static let instantActions = "instantActions"
    static let mainMenuActions = "mainMenuActions"
    static let afterAction = "afterAction"
    static let screenshotShelf = "screenshotShelf"
    static let actionOutput = "actionOutput"
    static let screenshotFolder = "screenshotFolder"
    static let screenshotAppend = "screenshotAppend"
    static let screenshotClipboard = "screenshotClipboard"
    static let screenshotMessage = "screenshotMessage"

    static func register() {
        UserDefaults.standard.register(defaults: [
            shakeEnabled: true,
            shakeSensitivity: ShakeDetector.Sensitivity.standard.rawValue,
            modifierEnabled: false,
            modifierKey: ModifierKey.shift.rawValue,
            notchEnabled: true,
            notchHighlight: NotchHighlight.hover.rawValue,
            shelfLocation: ShelfLocation.topRight.rawValue,
            addingBehavior: AddingBehavior.newShelf.rawValue,
            doubleClickFiles: DoubleClickFiles.reveal.rawValue,
            doubleClickEdge: EdgeAction.dock.rawValue,
            closeOnDragOut: CloseOnDragOut.moved.rawValue,
            intelligentNames: true,
            snapIntoPlace: false,
            retractAfterDrop: false,
            alwaysCopy: false,
            plainText: false,
            restrictToSpace: false,
            shelfColors: false,
            takeFocus: false,
            closeDetailOutside: true,
            showInMenuBar: true,
            menuBarIcon: MenuBarIcon.pocket.rawValue,
            showInDock: false,
            displayMode: DisplayMode.grid.rawValue,
            instantActionsEnabled: true,
            afterAction: AfterAction.close.rawValue,
            screenshotShelf: false,
            actionOutput: ActionRunner.OutputPlacement.currentShelf.rawValue,
            screenshotAppend: false,
            screenshotClipboard: false,
            screenshotMessage: true,
            instantActions: ["airdrop", "messages", "mail"],
            mainMenuActions: ["copyTo", "moveTo"],
        ])
        ActionOptions.register()
    }
}

/// Typed access for AppKit code.
enum Prefs {
    static var d: UserDefaults { .standard }
    static func bool(_ key: String) -> Bool { d.bool(forKey: key) }
    static func value<T: RawRepresentable>(_ key: String, default value: T) -> T where T.RawValue == String {
        guard let raw = d.string(forKey: key), let parsed = T(rawValue: raw) else { return value }
        return parsed
    }
    static var ignoredApps: [String] {
        get { d.stringArray(forKey: Pref.ignoredApps) ?? [] }
        set { d.set(newValue, forKey: Pref.ignoredApps) }
    }
}

enum ModifierKey: String, CaseIterable, Identifiable {
    case command, control, shift
    var id: String { rawValue }
    var flag: NSEvent.ModifierFlags { switch self { case .command: .command; case .control: .control; case .shift: .shift } }
    var title: String {
        switch self {
        case .command: L("Using ⌘ Command key")
        case .control: L("Using ⌃ Control key")
        case .shift: L("Using ⇧ Shift key")
        }
    }
}

enum NotchHighlight: String, CaseIterable, Identifiable {
    case always, hover, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .always: L("Always Highlight While Dragging")
        case .hover: L("Highlight When Hovering Over Notch")
        case .none: L("No Highlighting")
        }
    }
}

enum ShelfLocation: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight, center, nearCursor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topLeft: L("Top Left Corner")
        case .topRight: L("Top Right Corner")
        case .bottomLeft: L("Bottom Left Corner")
        case .bottomRight: L("Bottom Right Corner")
        case .center: L("Center")
        case .nearCursor: L("Near Cursor")
        }
    }
}

enum AddingBehavior: String, CaseIterable, Identifiable {
    case newShelf, lastActive, visible
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newShelf: L("Show in New Shelf")
        case .lastActive: L("Add to Last Active Shelf")
        case .visible: L("Add to Visible Shelf")
        }
    }
}

enum DoubleClickFiles: String, CaseIterable, Identifiable {
    case reveal, open, quickLook, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reveal: L("Reveal in Finder")
        case .open: L("Open Files")
        case .quickLook: L("Quick Look")
        case .none: L("No Action")
        }
    }
}

enum EdgeAction: String, CaseIterable, Identifiable {
    case dock, retract, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dock: L("Dock Shelf")
        case .retract: L("Retract Shelf")
        case .none: L("No Action")
        }
    }
}

enum CloseOnDragOut: String, CaseIterable, Identifiable {
    case moved, always, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .moved: L("Only when items are moved")
        case .always: L("Always")
        case .never: L("Never (when possible)")
        }
    }
}

enum MenuBarIcon: String, CaseIterable, Identifiable {
    case pocket, traditional, traditionalFill, minimal, document, document2
    var id: String { rawValue }
    /// SF Symbol of the icon; the pocket is drawn by Stash itself.
    var symbol: String {
        switch self {
        case .pocket: "tray"
        case .traditional: "tray"
        case .traditionalFill: "tray.fill"
        case .minimal: "square.stack"
        case .document: "doc"
        case .document2: "doc.on.doc"
        }
    }
    var title: String {
        switch self {
        case .pocket: "Stash"
        case .traditional: L("Traditional")
        case .traditionalFill: L("Traditional (Fill)")
        case .minimal: L("Minimalistic")
        case .document: L("Document")
        case .document2: L("Document 2")
        }
    }

    /// The menu bar image, a template so it follows the menu bar's colour.
    var image: NSImage {
        let image = self == .pocket ? Self.pocketImage : NSImage(systemSymbolName: symbol, accessibilityDescription: "Stash") ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// The app icon's pocket with two files in it, drawn at the menu bar's 18 pt.
    private static let pocketImage = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        // Two files peeking out of the pocket, like the app icon: a solid one behind an outlined one.
        func file(x: CGFloat, angle: CGFloat) -> NSBezierPath {
            let path = NSBezierPath(roundedRect: NSRect(x: -2.7, y: -4.5, width: 5.4, height: 9), xRadius: 1.3, yRadius: 1.3)
            var transform = AffineTransform(rotationByDegrees: angle)
            transform.append(AffineTransform(translationByX: x, byY: 12.4))
            path.transform(using: transform)
            return path
        }
        NSColor.black.set()
        file(x: 6.8, angle: 12).fill()
        let front = file(x: 11.2, angle: -8)
        NSGraphicsContext.current?.compositingOperation = .clear
        front.fill()
        front.lineWidth = 3
        front.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        front.lineWidth = 1.3
        front.stroke()
        let pocket = NSBezierPath()
        pocket.move(to: NSPoint(x: 2.2, y: 9.6))
        pocket.line(to: NSPoint(x: 15.8, y: 9.6))
        pocket.line(to: NSPoint(x: 15.8, y: 5.4))
        pocket.curve(to: NSPoint(x: 9, y: 1.6), controlPoint1: NSPoint(x: 15.8, y: 2.8), controlPoint2: NSPoint(x: 12, y: 1.6))
        pocket.curve(to: NSPoint(x: 2.2, y: 5.4), controlPoint1: NSPoint(x: 6, y: 1.6), controlPoint2: NSPoint(x: 2.2, y: 2.8))
        pocket.close()
        // A clear margin around the pocket keeps the files' lines from touching it.
        NSGraphicsContext.current?.compositingOperation = .clear
        pocket.lineWidth = 2.4
        pocket.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setFill()
        pocket.fill()
        return true
    }
}

enum DisplayMode: String { case grid, list }

enum AfterAction: String, CaseIterable, Identifiable {
    case close, keepOpen
    var id: String { rawValue }
    var title: String { self == .close ? L("Close shelf") : L("Keep shelf open") }
}

extension ShakeDetector.Sensitivity: Identifiable {
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: L("Default Sensitivity")
        case .high: L("High Sensitivity")
        case .highest: L("Highest Sensitivity")
        }
    }
}
