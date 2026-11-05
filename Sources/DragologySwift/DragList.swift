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
    @Entry var dragRow: @MainActor (AnyHashable) -> AnyView = { _ in AnyView(EmptyView()) }
    @Entry var dragRowHeightReport: @MainActor (AnyHashable, Double) -> Void = { _, _ in }
    @Entry var dragRowMoves: @MainActor (AnyHashable) -> [DragRowMove] = { _ in [] }
}

/// A way to move a row without dragging, offered to VoiceOver.
struct DragRowMove: Identifiable {
    var name: String
    var perform: @MainActor () -> Void

    var id: String { name }
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

    /// The single-step moves available to the row at `index`.
    func stepMoves(from index: Int) -> [(name: String, layout: DragListLayout)] {
        var moves: [(name: String, layout: DragListLayout)] = []

        if index > 0 { moves.append(("Move up", moving(from: index, to: index - 1))) }
        if index < ids.count - 1 { moves.append(("Move down", moving(from: index, to: index + 1))) }

        return moves
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
        DragCanvas(state: $layout, scene: DragListScenes.scene(for: Item.ID.self, style: style))
            .id(style)
            .dragActivation(activation ?? .longPress())
            .environment(\.externalStateTransition, nil)
            .environment(\.dragRow, rowView)
            .environment(\.dragRowHeightReport, recordHeight)
            .environment(\.dragRowMoves, rowMoves)
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

    private func rowMoves(_ key: AnyHashable) -> [DragRowMove] {
        guard let id = key.base as? Item.ID, let index = layout.ids.firstIndex(of: id) else { return [] }

        return layout.stepMoves(from: index).map { move in
            DragRowMove(name: move.name) { layout = move.layout }
        }
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
}

/// The scene behind a `DragList`.
enum DragListScenes {
    static func scene<ID: Hashable>(for _: ID.Type, style: DragListStyle) -> DragScene<DragListLayout<ID>> {
        { context in
            let layout = context.state

            // A row measured at no width would wrap down to a huge height.
            guard layout.width > 0 else { return SceneNode() }

            var nodes: [SceneNode<DragListLayout<ID>>] = []
            var offset = 0.0

            for (index, id) in layout.ids.enumerated() {
                // Finding where a row lands takes only that row. A drag
                // checks every order, so this is what keeps long lists fast.
                if !context.isTracking || context.draggedID == rowID(id) {
                    nodes.append(rowNode(id, index: index, offset: offset, style: style, context: context))
                }

                offset += layout.height(of: id) + layout.spacing
            }

            return SceneNode(children: nodes)
        }
    }

    private static func rowID<ID: Hashable>(_ id: ID) -> String {
        "row-\(id)"
    }

    private static func rowNode<ID: Hashable>(
        _ id: ID,
        index: Int,
        offset: Double,
        style: DragListStyle,
        context: SceneContext<DragListLayout<ID>>
    ) -> SceneNode<DragListLayout<ID>> {
        let layout = context.state
        let nodeID = rowID(id)
        // Scenes are built and drawn on the main actor, in practice.
        nonisolated(unsafe) let key = AnyHashable(id)
        let width = layout.width

        return DragItem(width: width, height: layout.height(of: id), interaction: .interactive) {
            DragRowHost(key: key, width: width)
        }
        .id(nodeID)
        .transform(.translate(0, offset))
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

/// Shows a row at its natural height, reports what that is, and offers
/// its moves to VoiceOver.
struct DragRowHost: View {
    let key: AnyHashable
    let width: Double

    @Environment(\.dragRow) private var row
    @Environment(\.dragRowHeightReport) private var reportHeight
    @Environment(\.dragRowMoves) private var moves

    var body: some View {
        row(key)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { reportHeight(key, $0) }
            .accessibilityElement(children: .contain)
            .accessibilityActions {
                ForEach(moves(key)) { move in
                    Button(move.name, action: move.perform)
                }
            }
    }
}
