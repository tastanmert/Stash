import AppKit
import SwiftUI

/// Colors of the shelf chrome, following the system appearance.
enum ShelfStyle {
    static let corner: CGFloat = 22
    static let background = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(white: 0.085, alpha: 1) : NSColor(white: 0.965, alpha: 1) })
    static let control = Color.primary.opacity(0.12)
    static let controlHover = Color.primary.opacity(0.18)
    static let glyph = Color.primary.opacity(0.85)
}

/// The shelf is see-through like a menu: what's behind it tints its background.
struct ShelfMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Moves the shelf when its background is dragged. SwiftUI content doesn't pass background drags on
/// to the window (isMovableByWindowBackground has no effect under it), so the move is started here.
struct WindowDragArea: NSViewRepresentable {
    let controller: ShelfController

    func makeNSView(context: Context) -> DragAreaView { DragAreaView(controller: controller) }
    func updateNSView(_ view: DragAreaView, context: Context) {}

    final class DragAreaView: NSView {
        weak var controller: ShelfController?

        init(controller: ShelfController) {
            self.controller = controller
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { return controller?.edgeDoubleClicked() ?? () }
            window?.performDrag(with: event)
        }
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

struct ShelfRootView: View {
    let model: ShelfModel
    let controller: ShelfController

    var body: some View {
        ZStack {
            // Empty parts of the shelf move the window.
            WindowDragArea(controller: controller)
            switch model.page {
            case .stack: ShelfStackPage(model: model, controller: controller).transition(.opacity)
            case .items: ShelfItemsPage(model: model, controller: controller).transition(.opacity)
            case .action(let id): ShelfActionPage(id: id, model: model, controller: controller).transition(.opacity)
            }
            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let busy = model.busy {
                ZStack {
                    ShelfStyle.background.opacity(0.92)
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShelfMaterial())
        .clipShape(RoundedRectangle(cornerRadius: ShelfStyle.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ShelfStyle.corner, style: .continuous)
                .strokeBorder(model.isDropTargeted ? Color.orange : Color.primary.opacity(0.1), lineWidth: model.isDropTargeted ? 4 : 0.5)
        }
        .scaleEffect(model.isDropTargeted ? 1.02 : 1)
        .animation(.spring(duration: 0.25), value: model.isDropTargeted)
    }

}

// MARK: - Stack page (the compact shelf)

struct ShelfStackPage: View {
    let model: ShelfModel
    let controller: ShelfController
    @State private var hover = false
    @Environment(\.controlActiveState) private var activeState

    /// The grab handle is the shelf's color indicator: it shows on hover, and a colored
    /// one also stays while Stash is active (or always, with "Always Show Indicator").
    private var showsHandle: Bool {
        hover || (model.color != nil && (model.alwaysShowIndicator || activeState != .inactive))
    }

    var body: some View {
        ZStack {
            if model.items.isEmpty {
                Text(L("Drop files here"))
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
            } else {
                ItemStack(items: model.items)
                    .frame(width: 112, height: 104)
                    .overlay {
                        DragSource(controller: controller, items: { model.items },
                                   onDoubleClick: { controller.showPage(.items) },
                                   menu: { ShelfMenu.make(for: controller) })
                    }
                    .offset(y: -6)
            }
            VStack(spacing: 0) {
                HStack {
                    CircleButton(symbol: model.isOptionDown ? "xmark.bin" : "xmark", help: L("Close the shelf (hold down Option to clear shelf content)")) {
                        controller.close(clearing: NSEvent.modifierFlags.contains(.option))
                    }
                    Spacer()
                    if model.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(45))
                    }
                    Spacer()
                    // An empty shelf has nothing to act on, so no action menu.
                    if model.items.isEmpty {
                        Color.clear.frame(width: 32, height: 32)
                    } else {
                        CircleMenuButton(symbol: "chevron.down", help: L("Perform tasks with the files in the shelf")) {
                            ShelfMenu.make(for: controller)
                        }
                    }
                }
                Spacer()
                if !model.items.isEmpty {
                    TitlePill(title: model.title) { controller.showPage(.items) }
                }
            }
            .padding(7)
            VStack {
                Capsule().fill(model.color.map { Color(nsColor: $0).opacity(hover ? 1 : 0.6) } ?? Color.primary.opacity(0.22))
                    .frame(width: 36, height: 5).padding(.top, 5)
                Spacer()
            }
            .opacity(showsHandle ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: showsHandle)
        }
        .onHover { hover = $0 }
    }
}

/// Up to three items, the first one on top, the others fanned out behind it.
struct ItemStack: View {
    let items: [ShelfItem]
    private let angles: [Double] = [0, -3, 4]

    var body: some View {
        let shown = Array(items.prefix(3))
        ZStack {
            ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { index, item in
                ItemThumbnail(item: item, side: 88)
                    .rotationEffect(.degrees(angles[index]))
                    .offset(x: CGFloat(index) * 2, y: CGFloat(index) * 2)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
        }
    }
}

struct ItemThumbnail: View {
    let item: ShelfItem
    let side: CGFloat
    @State private var cache = ThumbnailCache.shared

    var body: some View {
        let image = cache.image(for: item, size: side)
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
    }
}

struct CircleButton: View {
    let symbol: String
    var help: String = ""
    var size: CGFloat = 32
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(ShelfStyle.glyph)
                .frame(width: size, height: size)
                .background(hover ? ShelfStyle.controlHover : ShelfStyle.control, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// A circle button that pops up an AppKit menu below itself.
struct CircleMenuButton: View {
    let symbol: String
    var help: String = ""
    var size: CGFloat = 32
    let menu: () -> NSMenu
    @State private var hover = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(ShelfStyle.glyph)
            .frame(width: size, height: size)
            .background(hover ? ShelfStyle.controlHover : ShelfStyle.control, in: Circle())
            .overlay {
                MenuAnchor(label: help) { view in
                    menu().popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
                }
            }
            .onHover { hover = $0 }
            .help(help)
    }
}

/// The shelf name at the bottom; scrolls when it doesn't fit. Opens the item list.
struct TitlePill: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // At most 80 pt wide; a longer name scrolls inside that width instead of pushing into the chevron.
                MarqueeText(text: title, font: .system(size: 12))
                    .frame(width: min((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width.rounded(.up) + 1, 80))
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .foregroundStyle(ShelfStyle.glyph)
            .padding(.leading, 12).padding(.trailing, 10)
            .frame(height: 28)
            .background(hover ? ShelfStyle.controlHover : Color.primary.opacity(0.09), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Text that slides sideways when it is wider than its frame.
struct MarqueeText: View {
    let text: String
    let font: Font
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        // Sizes the box: as wide as offered (not the whole text), one line high.
        Text(text).font(font).lineLimit(1).fixedSize(horizontal: false, vertical: true)
            .hidden()
            .overlay {
                GeometryReader { box in
                    let overflow = textWidth > box.size.width + 1
                    HStack(spacing: 28) {
                        Text(text).font(font).lineLimit(1).fixedSize()
                            .background(GeometryReader { t in Color.clear.onAppear { textWidth = t.size.width }.onChange(of: text) { textWidth = t.size.width } })
                        if overflow { Text(text).font(font).lineLimit(1).fixedSize() }
                    }
                    .offset(x: overflow ? offset : 0)
                    .frame(width: box.size.width, alignment: overflow ? .leading : .center)
                    .clipped()
                    .mask(LinearGradient(stops: overflow ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.08), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)] : [.init(color: .black, location: 0), .init(color: .black, location: 1)], startPoint: .leading, endPoint: .trailing))
                    .onAppear { boxWidth = box.size.width; restart(overflow: overflow) }
                    .onChange(of: textWidth) { restart(overflow: textWidth > box.size.width + 1) }
                }
            }
    }

    private func restart(overflow: Bool) {
        offset = 0
        guard overflow else { return }
        let distance = textWidth + 28
        withAnimation(.linear(duration: Double(distance) / 30).delay(1).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}

// MARK: - Items page (detail view)

struct ShelfItemsPage: View {
    @Bindable var model: ShelfModel
    let controller: ShelfController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                CircleButton(symbol: "chevron.left", help: L("Show the previous screen")) { controller.showPage(.stack) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(model.totalSize.fileSize).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                CircleButton(symbol: "slider.horizontal.2.square", help: L("Shelf Preferences")) { model.showsPreferences = true }
                    .popover(isPresented: $model.showsPreferences, arrowEdge: .leading) {
                        ShelfPreferences(model: model, controller: controller)
                    }
                DisplayModePicker(mode: $model.displayMode)
            }
            .padding(7)
            ScrollView {
                if model.displayMode == .grid {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 14) {
                        ForEach(model.items) { item in ItemCell(item: item, model: model, controller: controller, style: .grid) }
                        RevealTile { controller.reveal(model.items) }
                    }
                    .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 12)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.items) { item in ItemCell(item: item, model: model, controller: controller, style: .list) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selection = [] }
        }
        .onChange(of: model.displayMode) { UserDefaults.standard.set(model.displayMode.rawValue, forKey: Pref.displayMode) }
    }
}

/// Icons / list switch: two round segments in a capsule.
private struct DisplayModePicker: View {
    @Binding var mode: DisplayMode

    var body: some View {
        HStack(spacing: 0) {
            segment(.grid, symbol: "square.grid.2x2", help: L("Show files as icons"))
            segment(.list, symbol: "list.bullet", help: L("Show files in a list"))
        }
        .padding(2)
        .background(ShelfStyle.control, in: Capsule())
    }

    private func segment(_ value: DisplayMode, symbol: String, help: String) -> some View {
        Button { mode = value } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ShelfStyle.glyph)
                .frame(width: 28, height: 28)
                .background(mode == value ? ShelfStyle.controlHover : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The last grid cell: shows all of the shelf's files in Finder.
private struct RevealTile: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "arrowshape.turn.up.right.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(height: 68)
                Text(L("Reveal in Finder")).font(.system(size: 12))
            }
            .frame(maxWidth: .infinity)
            .opacity(hover ? 1 : 0.85)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// The shelf's own preferences, in a popover from the detail view's sliders button.
struct ShelfPreferences: View {
    @Bindable var model: ShelfModel
    let controller: ShelfController

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent(L("Shelf name")) {
                        TextField("", text: Binding(get: { model.customName ?? model.title }, set: { model.customName = $0.isEmpty ? nil : $0 }))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                }
                Section {
                    Toggle(L("Always show indicator"), isOn: Binding(get: { model.alwaysShowIndicator }, set: { controller.setAlwaysShowIndicator($0) }))
                    HStack(alignment: .top) {
                        Text(L("Indicator color")).padding(.top, 4)
                        Spacer()
                        ColorGrid(model: model, size: 18, spacing: 2, rowSpacing: 4, inset: false) { controller.setColor($0) }
                    }
                }
                Section {
                    Toggle(L("Pin Shelf"), isOn: Binding(get: { model.pinned }, set: { controller.setPinned($0) }))
                    Toggle(L("Keep Shelf in own Space"), isOn: Binding(get: { model.keepInOwnSpace }, set: { controller.setKeepInOwnSpace($0) }))
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            Text(L("These preferences apply only to this shelf."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.bottom, 18)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ShelfNavigationBar<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            CircleButton(symbol: "chevron.left", help: L("Show the previous screen"), size: 28, action: back)
            VStack(spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}

struct ItemCell: View {
    enum Style { case grid, list }
    let item: ShelfItem
    let model: ShelfModel
    let controller: ShelfController
    let style: Style
    @State private var newName = ""
    @FocusState private var renaming: Bool

    private var selected: Bool { model.selection.contains(item.id) }

    var body: some View {
        Group {
            if style == .grid { grid } else { list }
        }
        .background(selected ? Color.accentColor.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if model.renamingID != item.id {
                DragSource(controller: controller,
                           items: { selected ? model.selectedItems : [item] },
                           onClick: { event in click(event) },
                           onDoubleClick: { controller.performDoubleClick(on: item) },
                           menu: { ShelfMenu.make(for: controller) })
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 3) {
            ItemThumbnail(item: item, side: 68)
            name.font(.system(size: 13)).lineLimit(1).padding(.top, 5)
            Text(details).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var list: some View {
        HStack(spacing: 10) {
            ItemThumbnail(item: item, side: 22)
            name.font(.system(size: 14)).lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.size?.fileSize ?? item.type?.localizedDescription ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
                if let pixels = ThumbnailCache.shared.dimensions(for: item) {
                    Text(pixels).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }

    /// "189 KB • 1520x1626" for images, the size alone for other files.
    private var details: String {
        let size = item.size?.fileSize ?? item.type?.localizedDescription ?? ""
        guard let pixels = ThumbnailCache.shared.dimensions(for: item) else { return size }
        return "\(size) • \(pixels)"
    }

    @ViewBuilder private var name: some View {
        if model.renamingID == item.id {
            TextField("", text: $newName)
                .textFieldStyle(.roundedBorder)
                .focused($renaming)
                .onAppear { newName = item.name; renaming = true }
                .onSubmit { controller.rename(item, to: newName) }
                .onExitCommand { model.renamingID = nil }
        } else {
            Text(item.displayName).truncationMode(.middle)
        }
    }

    private func click(_ event: NSEvent) {
        let mods = event.modifierFlags
        if mods.contains(.command) {
            if selected { model.selection.remove(item.id) } else { model.selection.insert(item.id) }
        } else if mods.contains(.shift), let anchor = model.items.firstIndex(where: { model.selection.contains($0.id) }),
                  let here = model.items.firstIndex(of: item) {
            model.selection = Set(model.items[min(anchor, here)...max(anchor, here)].map(\.id))
        } else if event.type == .rightMouseDown, selected {
            // keep the selection for the context menu
        } else {
            model.selection = [item.id]
        }
    }
}
