import SwiftUI

/// Where cards go: everything the engine has to know about a board.
struct DragBoardLayout<ColumnID: Hashable, CardID: Hashable>: Equatable {
    struct Column: Equatable {
        var id: ColumnID
        var cards: [CardID]
    }

    /// What an unmeasured card is assumed to need.
    private static var estimatedHeight: Double { 44 }
    /// Room left for dropping on a column with no cards.
    private static var emptyColumnHeight: Double { 60 }

    static var headerHeight: Double { 36 }
    static var padding: Double { 8 }

    var columns: [Column]
    var spacing: Double
    var width = 0.0
    var heights: [CardID: Double] = [:]

    init(columns: [Column], spacing: Double) {
        self.columns = columns
        self.spacing = spacing
    }

    var columnWidth: Double {
        let gaps = spacing * Double(max(columns.count - 1, 0))
        return (width - gaps) / Double(max(columns.count, 1))
    }

    var cardWidth: Double { columnWidth - 2 * Self.padding }

    func columnX(_ column: Int) -> Double {
        Double(column) * (columnWidth + spacing)
    }

    func height(of id: CardID) -> Double {
        heights[id] ?? Self.estimatedHeight
    }

    func cardOffset(column: Int, index: Int) -> Double {
        columns[column].cards.prefix(index).reduce(Self.headerHeight) { $0 + height(of: $1) + spacing }
    }

    func columnHeight(_ column: Int) -> Double {
        let cards = columns[column].cards
        let content = cards.isEmpty
            ? Self.emptyColumnHeight
            : cards.reduce(-spacing) { $0 + height(of: $1) + spacing }

        return Self.headerHeight + content + Self.padding
    }

    /// Columns line up at the top, and the tallest sets the height.
    var totalHeight: Double {
        columns.indices.map(columnHeight).max() ?? 0
    }

    func moving(from source: (column: Int, index: Int), to target: (column: Int, index: Int)) -> DragBoardLayout {
        var copy = self
        let card = copy.columns[source.column].cards.remove(at: source.index)
        copy.columns[target.column].cards.insert(card, at: target.index)
        return copy
    }

    /// Every slot in every column that this card could move to.
    func allMoves(from source: (column: Int, index: Int)) -> [DragBoardLayout] {
        columns.indices.flatMap { column -> [DragBoardLayout] in
            let isSameColumn = column == source.column
            let slots = columns[column].cards.count + (isSameColumn ? 0 : 1)

            return (0..<slots).map { moving(from: source, to: (column, $0)) }
        }
    }

    /// The single-step moves for this card, offered to VoiceOver.
    func stepMoves(from source: (column: Int, index: Int)) -> [(name: String, layout: DragBoardLayout)] {
        var moves: [(name: String, layout: DragBoardLayout)] = []
        let count = columns[source.column].cards.count

        if source.index > 0 {
            moves.append(("Move up", moving(from: source, to: (source.column, source.index - 1))))
        }

        if source.index < count - 1 {
            moves.append(("Move down", moving(from: source, to: (source.column, source.index + 1))))
        }

        for (name, neighbor) in [("Move left", source.column - 1), ("Move right", source.column + 1)]
        where columns.indices.contains(neighbor) {
            let slot = min(source.index, columns[neighbor].cards.count)

            moves.append((name, moving(from: source, to: (neighbor, slot))))
        }

        return moves
    }
}

/// Tells a column's header apart from its cards, among the views a board
/// looks up by key.
private struct DragBoardHeaderKey<ColumnID: Hashable>: Hashable {
    var id: ColumnID
}

/// A board of columns, with cards the user can drag within and between
/// them.
///
/// ```swift
/// DragBoard($columns, cards: \.cards) { column in
///     Text(column.title)
/// } card: { card in
///     CardView(card: card)
/// }
/// ```
///
/// Cards size themselves, keep their state through drags, and their
/// controls keep working. A long press picks up a card, so the board can
/// sit in a `ScrollView`. Set `.dragActivation(_:)` to change that.
public struct DragBoard<Column: Identifiable, Card: Identifiable, Header: View, CardContent: View>: View {
    private typealias Layout = DragBoardLayout<Column.ID, Card.ID>

    @Binding private var columns: [Column]
    private let cards: WritableKeyPath<Column, [Card]>
    private let header: @MainActor (Column) -> Header
    private let card: @MainActor (Card) -> CardContent

    @SwiftUI.State private var layout: DragBoardLayout<Column.ID, Card.ID>
    @Environment(\.dragActivation) private var activation

    public init(
        _ columns: Binding<[Column]>,
        cards: WritableKeyPath<Column, [Card]>,
        spacing: Double = 8,
        @ViewBuilder header: @escaping @MainActor (Column) -> Header,
        @ViewBuilder card: @escaping @MainActor (Card) -> CardContent
    ) {
        _columns = columns
        self.cards = cards
        self.header = header
        self.card = card

        let snapshot = columns.wrappedValue.map { column in
            Layout.Column(id: column.id, cards: column[keyPath: cards].map(\.id))
        }

        _layout = SwiftUI.State(initialValue: Layout(columns: snapshot, spacing: spacing))
    }

    private var snapshot: [Layout.Column] {
        columns.map { Layout.Column(id: $0.id, cards: $0[keyPath: cards].map(\.id)) }
    }

    public var body: some View {
        DragCanvas(state: $layout, scene: DragBoardScenes.scene(for: Column.ID.self, Card.ID.self))
            .dragActivation(activation ?? .longPress())
            .environment(\.externalStateTransition, nil)
            .environment(\.dragRow, content)
            .environment(\.dragRowHeightReport, recordHeight)
            .environment(\.dragRowMoves, cardMoves)
            .frame(height: layout.totalHeight)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { layout.width = $0 }
            .onChange(of: snapshot) { _, current in
                guard current != layout.columns else { return }

                layout.columns = current
            }
            .onChange(of: layout.columns) { _, arranged in
                rearrangeCards(to: arranged)
            }
    }

    private func content(_ key: AnyHashable) -> AnyView {
        if let headerKey = key.base as? DragBoardHeaderKey<Column.ID>,
           let column = columns.first(where: { $0.id == headerKey.id }) {
            return AnyView(header(column))
        }

        let all = columns.flatMap { $0[keyPath: cards] }

        guard let match = all.first(where: { AnyHashable($0.id) == key }) else {
            return AnyView(EmptyView())
        }

        return AnyView(card(match))
    }

    private func position(of key: AnyHashable) -> (column: Int, index: Int)? {
        guard let id = key.base as? Card.ID else { return nil }

        for (column, entry) in layout.columns.enumerated() {
            if let index = entry.cards.firstIndex(of: id) {
                return (column, index)
            }
        }

        return nil
    }

    private func cardMoves(_ key: AnyHashable) -> [DragRowMove] {
        guard let source = position(of: key) else { return [] }

        return layout.stepMoves(from: source).map { move in
            DragRowMove(name: move.name) { layout = move.layout }
        }
    }

    private func recordHeight(_ key: AnyHashable, _ height: Double) {
        let tolerance = 0.5

        guard let id = key.base as? Card.ID, abs(layout.height(of: id) - height) > tolerance else { return }

        layout.heights[id] = height
    }

    private func rearrangeCards(to arranged: [Layout.Column]) {
        guard arranged != snapshot else { return }

        let byID = Dictionary(columns.flatMap { $0[keyPath: cards] }.map { ($0.id, $0) }) { first, _ in first }

        var updated = columns

        for (index, column) in updated.enumerated() {
            guard let entry = arranged.first(where: { $0.id == column.id }) else { continue }

            updated[index][keyPath: cards] = entry.cards.compactMap { byID[$0] }
        }

        columns = updated
    }
}

/// The scene behind a `DragBoard`.
enum DragBoardScenes {
    private static var columnFill: SceneColor {
        SceneColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.12)
    }

    private static var cornerRadius: Double { 12 }
    private static var ghostOpacity: Double { 0.3 }

    static func cardID<CardID: Hashable>(_ id: CardID) -> String {
        "card-\(id)"
    }

    static func scene<ColumnID: Hashable, CardID: Hashable>(
        for _: ColumnID.Type,
        _: CardID.Type
    ) -> DragScene<DragBoardLayout<ColumnID, CardID>> {
        { context in
            let layout = context.state

            // A card measured at no width would wrap down to a huge height.
            guard layout.width > 0 else { return SceneNode() }

            var nodes: [SceneNode<DragBoardLayout<ColumnID, CardID>>] = []

            for (columnIndex, column) in layout.columns.enumerated() {
                // Finding where a card lands takes only that card.
                if !context.isTracking {
                    nodes += columnNodes(column.id, index: columnIndex, layout: layout)
                }

                for (index, id) in column.cards.enumerated()
                where !context.isTracking || context.draggedID == cardID(id) {
                    nodes.append(cardNode(id, column: columnIndex, index: index, context: context))
                }
            }

            return SceneNode(children: nodes)
        }
    }

    private static func columnNodes<ColumnID: Hashable, CardID: Hashable>(
        _ id: ColumnID,
        index: Int,
        layout: DragBoardLayout<ColumnID, CardID>
    ) -> [SceneNode<DragBoardLayout<ColumnID, CardID>>] {
        typealias Layout = DragBoardLayout<ColumnID, CardID>

        let width = layout.columnWidth
        let x = layout.columnX(index)

        // Scenes are built and drawn on the main actor, in practice.
        nonisolated(unsafe) let key = AnyHashable(DragBoardHeaderKey(id: id))

        let background: SceneNode<Layout> = SceneRect(
            width: width,
            height: layout.columnHeight(index),
            cornerRadius: cornerRadius
        )
        .id("column-\(id)")
        .fill(columnFill)
        .transform(.translate(x, 0))

        let header: SceneNode<Layout> = DragItem(width: width, height: Layout.headerHeight) {
            DragRowHost(key: key, width: width)
        }
        .id("header-\(id)")
        .transform(.translate(x, 0))

        return [background, header]
    }

    private static func cardNode<ColumnID: Hashable, CardID: Hashable>(
        _ id: CardID,
        column: Int,
        index: Int,
        context: SceneContext<DragBoardLayout<ColumnID, CardID>>
    ) -> SceneNode<DragBoardLayout<ColumnID, CardID>> {
        typealias Layout = DragBoardLayout<ColumnID, CardID>

        let layout = context.state
        let nodeID = cardID(id)
        let width = layout.cardWidth

        // Scenes are built and drawn on the main actor, in practice.
        nonisolated(unsafe) let key = AnyHashable(id)

        return DragItem(width: width, height: layout.height(of: id), interaction: .interactive) {
            DragRowHost(key: key, width: width)
        }
        .id(nodeID)
        .transform(.translate(
            layout.columnX(column) + Layout.padding,
            layout.cardOffset(column: column, index: index)
        ))
        .zIndex(context.draggedID == nodeID ? .absolute(1) : .relative(1))
        .onDrag {
            context.drag
                .closest(layout.allMoves(from: (column, index)))
                .withFloating(FloatingOptions(ghostOpacity: ghostOpacity))
        }
    }
}
