import SwiftUI

/// How a row behaves while it's dragged in a `DragList`.
public enum DragListStyle: Hashable, Sendable {
    /// The row follows the finger, and the others make room. A faint copy
    /// marks where it would land.
    case floating(ghostOpacity: Double = 0.3)
    /// The row slides between its possible positions.
    case sliding
    /// The row jumps from one position to the next.
    case snapping
}

extension EnvironmentValues {
    @Entry var dragListStyle = DragListStyle.floating()
    @Entry var dragListRow: @MainActor (AnyHashable) -> AnyView = { _ in AnyView(EmptyView()) }
    @Entry var dragListHeightReport: @MainActor (AnyHashable, Double) -> Void = { _, _ in }
}

extension View {
    /// Sets how rows behave in the `DragList`s inside this view.
    public func dragListStyle(_ style: DragListStyle) -> some View {
        environment(\.dragListStyle, style)
    }
}

/// Where rows go: everything the engine has to know about a list.
struct DragListLayout<ID: Hashable>: Equatable {
    /// What an unmeasured row is assumed to need.
    private static var estimatedHeight: Double { 44 }

    var ids: [ID]
    var spacing: Double
    var width = 0.0
    var heights: [ID: Double] = [:]

    init(ids: [ID], spacing: Double) {
        self.ids = ids
        self.spacing = spacing
    }

    func height(of id: ID) -> Double {
        heights[id] ?? Self.estimatedHeight
    }

    func offset(at index: Int) -> Double {
        ids.prefix(index).reduce(0) { $0 + height(of: $1) + spacing }
    }

    var totalHeight: Double {
        guard !ids.isEmpty else { return 0 }

        return offset(at: ids.count) - spacing
    }

    func moving(from source: Int, to destination: Int) -> DragListLayout {
        var copy = self
        copy.ids.insert(copy.ids.remove(at: source), at: destination)
        return copy
    }
}

/// A list of your own views that the user can reorder by dragging.
///
/// ```swift
/// DragList($tasks) { task in
///     TaskRow(task: task)
/// }
/// ```
///
/// Rows size themselves, keep their state through drags, and their
/// controls keep working. A long press picks up a row, so the list can sit
/// in a `ScrollView`. Set `.dragActivation(_:)` to change that.
public struct DragList<Item: Identifiable, Row: View>: View {
    @Binding private var items: [Item]
    private let row: @MainActor (Item) -> Row

    @SwiftUI.State private var layout: DragListLayout<Item.ID>
    @Environment(\.dragListStyle) private var style
    @Environment(\.dragActivation) private var activation

    public init(
        _ items: Binding<[Item]>,
        spacing: Double = 8,
        @ViewBuilder row: @escaping @MainActor (Item) -> Row
    ) {
        _items = items
        self.row = row
        _layout = SwiftUI.State(initialValue: DragListLayout(ids: items.wrappedValue.map(\.id), spacing: spacing))
    }

    public var body: some View {
        DragCanvas(state: $layout, scene: Self.scene(style: style))
            .id(style)
            .dragActivation(activation ?? .longPress())
            .environment(\.externalStateTransition, nil)
            .environment(\.dragListRow, rowView)
            .environment(\.dragListHeightReport, recordHeight)
            .frame(height: layout.totalHeight)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { layout.width = $0 }
            .onChange(of: items.map(\.id)) { _, ids in
                guard ids != layout.ids else { return }

                layout.ids = ids
            }
            .onChange(of: layout.ids) { _, ids in
                reorderItems(to: ids)
            }
    }

    /// Rows are looked up by id as they're drawn, so they're always current,
    /// even though the canvas keeps the scene function it was first given.
    private func rowView(_ key: AnyHashable) -> AnyView {
        guard let item = items.first(where: { AnyHashable($0.id) == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(row(item))
    }

    private func recordHeight(_ key: AnyHashable, _ height: Double) {
        let tolerance = 0.5

        guard let id = key.base as? Item.ID, abs(layout.height(of: id) - height) > tolerance else { return }

        layout.heights[id] = height
    }

    private func reorderItems(to ids: [Item.ID]) {
        guard ids != items.map(\.id) else { return }

        let byID = Dictionary(items.map { ($0.id, $0) }) { first, _ in first }

        items = ids.compactMap { byID[$0] }
    }

    private static func scene(style: DragListStyle) -> DragScene<DragListLayout<Item.ID>> {
        { context in
            let layout = context.state

            // A row measured at no width would wrap down to a huge height.
            guard layout.width > 0 else { return SceneNode() }

            let nodes = layout.ids.enumerated().map { index, id in
                rowNode(id, index: index, style: style, context: context)
            }

            return SceneNode(children: nodes)
        }
    }

    private static func rowNode(
        _ id: Item.ID,
        index: Int,
        style: DragListStyle,
        context: SceneContext<DragListLayout<Item.ID>>
    ) -> SceneNode<DragListLayout<Item.ID>> {
        let layout = context.state
        let nodeID = "row-\(id)"
        let key = AnyHashable(id)
        let width = layout.width

        return DragItem(width: width, height: layout.height(of: id), interaction: .interactive) {
            DragListRowHost(key: key, width: width)
        }
        .id(nodeID)
        .transform(.translate(0, layout.offset(at: index)))
        .zIndex(context.draggedID == nodeID ? .absolute(1) : .relative(0))
        .onDrag {
            let orders = layout.ids.indices.map { layout.moving(from: index, to: $0) }

            switch style {
            case .floating(let ghostOpacity):
                return context.drag.closest(orders).withFloating(FloatingOptions(ghostOpacity: ghostOpacity))
            case .sliding:
                return context.drag.between(orders)
            case .snapping:
                return context.drag.closest(orders)
            }
        }
    }
}

/// Shows a row at its natural height, and reports what that is.
private struct DragListRowHost: View {
    let key: AnyHashable
    let width: Double

    @Environment(\.dragListRow) private var row
    @Environment(\.dragListHeightReport) private var reportHeight

    var body: some View {
        row(key)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { reportHeight(key, $0) }
    }
}
