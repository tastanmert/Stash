import AppKit
import SwiftUI
import StashCore

/// "Redact Text": an editor window where detected text (Smart Redact)
/// or boxes you draw (Manual) are painted over in one color.
enum RedactWindow {
    /// Open editors, kept alive until they close.
    private static var windows: [NSWindow] = []

    static func show(_ url: URL, from controller: ShelfController) {
        guard let image = try? FileOperations.orientedImage(at: url) else {
            return controller.alert(L("Could not perform the action"), L("The operation cannot be performed with this type of files"))
        }
        // The image shows at its own size when it fits, under a 52 pt bar.
        let scale = min(1, 800 / Double(image.width), 640 / Double(image.height))
        let width = max(440, Double(image.width) * scale), height = max(200, Double(image.height) * scale)
        let frame = NSRect(x: 0, y: 0, width: width, height: height + RedactView.barHeight)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = url.lastPathComponent
        window.isReleasedWhenClosed = false
        window.setFrame(frame, display: false)
        let session = RedactSession(url: url, image: image, controller: controller)
        let host = NSHostingView(rootView: RedactView(session: session) { [weak window] in window?.close() })
        host.sizingOptions = [] // keep the window's frame; the view would add the title bar on top
        window.contentView = host
        window.center()
        windows.removeAll { !$0.isVisible }
        windows.append(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        session.detect()
    }
}

@Observable
final class RedactSession {
    enum Mode: Hashable { case smart, manual }

    struct Box: Identifiable {
        let id = UUID()
        /// Unit coordinates, origin at the top left of the image.
        var rect: CGRect
        var selected: Bool
        /// Found by Smart Redact (selectable) rather than drawn (deletable).
        let detected: Bool
    }

    let url: URL
    let image: NSImage
    private let cgImage: CGImage
    private weak var controller: ShelfController?
    var boxes: [Box] = []
    var mode: Mode = .smart
    var analyzing = true
    var smartAvailable = true
    var saving = false
    var notice: String?
    var color: Color = .black

    var replacesOriginal = UserDefaults.standard.bool(forKey: ActionOptions.redactReplaceKey) {
        didSet { UserDefaults.standard.set(replacesOriginal, forKey: ActionOptions.redactReplaceKey) }
    }
    var revealsInFinder = UserDefaults.standard.bool(forKey: ActionOptions.redactRevealKey) {
        didSet { UserDefaults.standard.set(revealsInFinder, forKey: ActionOptions.redactRevealKey) }
    }

    init(url: URL, image: CGImage, controller: ShelfController) {
        self.url = url
        self.cgImage = image
        self.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        self.controller = controller
    }

    var hasRedactions: Bool { boxes.contains(where: \.selected) }

    func detect() {
        let image = cgImage
        Task {
            let rects = (try? await Background.run { try FileOperations.textBoxes(in: image) }) ?? []
            analyzing = false
            // Vision's boxes hug the glyphs; a little margin covers ascenders and descenders.
            boxes += rects.map { rect in
                let padded = rect.insetBy(dx: -rect.height * 0.12, dy: -rect.height * 0.15)
                return Box(rect: padded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)), selected: false, detected: true)
            }
            if rects.isEmpty {
                smartAvailable = false
                mode = .manual
                notice = L("Smart Redact is disabled as there was no text detected in the image.")
            }
        }
    }

    func toggle(_ id: Box.ID) {
        guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
        boxes[index].selected.toggle()
    }

    func delete(_ id: Box.ID) { boxes.removeAll { $0.id == id } }

    func add(_ rect: CGRect) { boxes.append(Box(rect: rect, selected: true, detected: false)) }

    func save(then close: @escaping () -> Void) {
        let rects = boxes.filter(\.selected).map(\.rect)
        guard !rects.isEmpty else { return close() }
        saving = true
        let url = url, replacing = replacesOriginal
        let fill = NSColor(color).usingColorSpace(.sRGB)?.cgColor ?? NSColor.black.cgColor
        let folder = StashPaths.standard.output.appending(path: L("Redacted Images"), directoryHint: .isDirectory)
        Task {
            do {
                let output = try await Background.run {
                    try FileOperations.redact(url, rects: rects, color: fill, replacing: replacing, in: folder)
                }
                saving = false
                if revealsInFinder || controller == nil {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                } else if replacing {
                    controller?.replaceItems(with: [output])
                } else {
                    controller?.add([ShelfItem(url: output)])
                }
                controller?.finishAction()
                close()
            } catch {
                saving = false
                let alert = NSAlert()
                alert.messageText = L("Could not perform the action")
                alert.informativeText = ActionRunner.message(for: error)
                alert.runModal()
            }
        }
    }
}

struct RedactView: View {
    static let barHeight: CGFloat = 52
    @Bindable var session: RedactSession
    let close: () -> Void
    /// The box being drawn in Manual mode, in unit coordinates.
    @State private var draft: CGRect?

    var body: some View {
        VStack(spacing: 0) {
            toolbar.frame(height: Self.barHeight)
            canvas
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .onExitCommand(perform: close)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        ZStack {
            Picker("", selection: $session.mode) {
                Text(L("Smart Redact")).tag(RedactSession.Mode.smart)
                Text(L("Manual")).tag(RedactSession.Mode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(!session.smartAvailable)
            HStack(spacing: 10) {
                Spacer()
                ColorPicker("", selection: $session.color, supportsOpacity: false)
                    .labelsHidden()
                    .help(L("Color"))
                Menu {
                    Picker(L("Save Options:"), selection: $session.replacesOriginal) {
                        Text(L("Create Copy")).tag(false)
                        Text(L("Replace Original File")).tag(true)
                    }
                    .pickerStyle(.inline)
                    Picker(L("When Done:"), selection: $session.revealsInFinder) {
                        Text(L("Show in shelf")).tag(false)
                        Text(L("Reveal in Finder")).tag(true)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .fixedSize()
                .help(L("Options"))
                Button {
                    session.save(then: close)
                } label: {
                    Group {
                        if session.analyzing || session.saving {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(session.analyzing || session.saving || !session.hasRedactions)
                .keyboardShortcut(.defaultAction)
                .help(L("Save"))
            }
            .padding(.trailing, 12)
        }
    }

    // MARK: Image and boxes

    private var canvas: some View {
        GeometryReader { geo in
            let fit = fitted(session.image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: session.image)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .offset(x: fit.minX, y: fit.minY)
                ForEach(session.boxes) { box in
                    if box.selected || (box.detected && session.mode == .smart) {
                        boxView(box, in: fit)
                    }
                }
                if let draft {
                    let r = place(draft, in: fit)
                    Rectangle().fill(session.color.opacity(0.7))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
                if session.analyzing {
                    Color.black.opacity(0.3).allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(drawing(in: fit), including: session.mode == .manual ? .all : .subviews)
            .overlay(alignment: .bottom) { noticeView }
        }
    }

    @ViewBuilder
    private func boxView(_ box: RedactSession.Box, in fit: CGRect) -> some View {
        let r = place(box.rect, in: fit)
        Group {
            if box.selected {
                Rectangle().fill(session.color)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.orange.opacity(0.15))
                    .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.orange, lineWidth: 1.5) }
            }
        }
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .offset(x: r.minX, y: r.minY)
        .onTapGesture { if box.detected && session.mode == .smart { session.toggle(box.id) } }
        .contextMenu {
            if box.detected {
                Button(box.selected ? L("Deselect") : L("Select")) { session.toggle(box.id) }
            } else {
                Button(L("Delete")) { session.delete(box.id) }
            }
        }
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice = session.notice {
            Text(notice)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 14)
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { session.notice = nil }
                }
        }
    }

    private func drawing(in fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let a = unit(value.startLocation, in: fit), b = unit(value.location, in: fit)
                draft = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            }
            .onEnded { _ in
                if let draft, draft.width > 0.005, draft.height > 0.005 { session.add(draft) }
                draft = nil
            }
    }

    // MARK: Geometry

    /// Where the image sits when fitted into the canvas, keeping its proportions.
    private func fitted(_ size: CGSize, in bounds: CGSize) -> CGRect {
        let scale = min(bounds.width / max(size.width, 1), bounds.height / max(size.height, 1))
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
    }

    private func place(_ rect: CGRect, in fit: CGRect) -> CGRect {
        CGRect(x: fit.minX + rect.minX * fit.width, y: fit.minY + rect.minY * fit.height,
               width: rect.width * fit.width, height: rect.height * fit.height)
    }

    private func unit(_ point: CGPoint, in fit: CGRect) -> CGPoint {
        CGPoint(x: min(max((point.x - fit.minX) / fit.width, 0), 1), y: min(max((point.y - fit.minY) / fit.height, 0), 1))
    }
}
