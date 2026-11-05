import Dragology
import Foundation

// MARK: - Three states

struct TriangleState: Equatable {
    var index = 0
}

private enum Triangle {
    static let positions = [Vec2(10, 10), Vec2(200, 10), Vec2(105, 170)]
    static let side = 60.0
    static let cornerRadius = 4.0
    static let lineWidth = 6.0
    static let states = positions.indices.map { TriangleState(index: $0) }

    static var center: Vec2 {
        positions.reduce(.zero, +) * (1 / Double(positions.count)) + half
    }

    static var half: Vec2 { Vec2(side / 2, side / 2) }
}

enum TriangleMode: Int, CaseIterable {
    case closest, closestFloating, between, betweenFloating

    var title: String {
        switch self {
        case .closest: "closest"
        case .closestFloating: "closest + floating"
        case .between: "between"
        case .betweenFloating: "between + floating"
        }
    }
}

func triangle(mode: TriangleMode) -> Draggable<TriangleState> {
    { context in
        let position = Triangle.positions[context.state.index]

        return group {
            for slot in Triangle.positions {
                rect(width: Triangle.side, height: Triangle.side, cornerRadius: Triangle.cornerRadius)
                    .stroke(Ink.outline)
                    .transform(.translate(slot))
            }

            rect(width: Triangle.side, height: Triangle.side, cornerRadius: Triangle.cornerRadius)
                .id("switch")
                .fill(Ink.text)
                .transform(.translate(position))
                .onDrag {
                    let d = context.d

                    switch mode {
                    case .closest:
                        return d.closest(Triangle.states)
                    case .closestFloating:
                        return d.closest(Triangle.states).withFloating()
                    case .between:
                        return d.between(Triangle.states)
                    case .betweenFloating:
                        return d.between(Triangle.states).withFloating()
                    }
                }

            // Shows how the rest of the scene blends along with the square.
            line(from: Triangle.center, to: position + Triangle.half)
                .stroke(Ink.outline, lineWidth: Triangle.lineWidth)
                .hitTesting(.disabled)
        }
    }
}

/// The closest mode again, written by hand with `d.custom`.
func customTriangle(_ context: RenderContext<TriangleState>) -> Node<TriangleState> {
    let position = Triangle.positions[context.state.index]

    return group {
        for slot in Triangle.positions {
            rect(width: Triangle.side, height: Triangle.side, cornerRadius: Triangle.cornerRadius)
                .stroke(Ink.outline)
                .transform(.translate(slot))
        }

        rect(width: Triangle.side, height: Triangle.side, cornerRadius: Triangle.cornerRadius)
            .id("switch")
            .fill(Ink.purple)
            .transform(.translate(position))
            .onDrag {
                context.d.custom { dragContext in
                    { frame in
                        let dragged = frame.pointer - dragContext.anchor
                        let best = Triangle.positions.indices.min {
                            Triangle.positions[$0].distance(to: dragged)
                                < Triangle.positions[$1].distance(to: dragged)
                        } ?? 0
                        let state = Triangle.states[best]

                        var result = DragResult(
                            preview: Lazy { dragContext.render(state) },
                            dropState: state,
                            gap: dragged.distance(to: Triangle.positions[best])
                        )
                        result.activePath = String(best)

                        return result
                    }
                }
            }
    }
}

// MARK: - Ring of beads

struct RingState: Equatable {
    var beads = ["A", "B", "C", "D", "E"]
}

private enum Ring {
    static let center = Vec2(170, 170)
    static let radius = 110.0
    static let beadRadius = 26.0
    static let fullTurn = 360.0
    static let topOfCircle = -90.0
    static let farGap = 65.0
    static let fontSize = 16.0
    static let lineWidth = 1.5
    static let draggedZ = 2
    static let restingZ = 1
}

enum RingMode: Int, CaseIterable {
    case closest, floating, removable, between

    var title: String {
        switch self {
        case .closest: "closest"
        case .floating: "closest + floating"
        case .removable: "whenFar + floating"
        case .between: "between"
        }
    }
}

func ring(mode: RingMode) -> Draggable<RingState> {
    { context in
        let state = context.state
        let count = state.beads.count

        return group {
            circle(radius: Ring.radius).stroke(Ink.faint, lineWidth: Ring.lineWidth)

            for (index, bead) in state.beads.enumerated() {
                let angle = Double(index) / Double(count) * Ring.fullTurn + Ring.topOfCircle
                let color = Ink.series[Int(bead.unicodeScalars.first?.value ?? 0) % Ink.series.count]

                group {
                    circle(radius: Ring.beadRadius)
                        .fill(color)
                        .stroke(Ink.muted, lineWidth: Ring.lineWidth)

                    label(bead, size: Ring.fontSize).fill(.white)
                }
                .id(bead)
                .transform(.translate(polar(radius: Ring.radius, degrees: angle)))
                .zIndex(.relative(context.draggedID == bead ? Ring.draggedZ : Ring.restingZ))
                .onDrag {
                    let d = context.d

                    // Every position this bead could be reinserted at.
                    let orders = state.beads.indices.map { target -> RingState in
                        var copy = state
                        copy.beads.remove(at: index)
                        copy.beads.insert(bead, at: target)
                        return copy
                    }

                    switch mode {
                    case .closest:
                        return d.closest(orders)

                    case .floating:
                        return d.closest(orders).withFloating()

                    case .removable:
                        var removed = state
                        removed.beads.remove(at: index)

                        return d.closest(orders)
                            .whenFar(d.fixed(removed).onDrop(state), gap: WhenFarGap(Ring.farGap))
                            .withFloating()

                    case .between:
                        return d.between(orders)
                    }
                }
            }
        }
        .transform(.translate(Ring.center))
    }
}

// MARK: - Kanban

struct KanbanCard: Equatable {
    var id: String
    var title: String
}

struct KanbanColumn: Equatable {
    var id: String
    var title: String
    var cards: [KanbanCard]
}

struct KanbanState: Equatable {
    var columns = [
        KanbanColumn(id: "todo", title: "To Do", cards: [
            KanbanCard(id: "1", title: "Task A"),
            KanbanCard(id: "2", title: "Task B"),
        ]),
        KanbanColumn(id: "doing", title: "Doing", cards: [KanbanCard(id: "3", title: "Task C")]),
        KanbanColumn(id: "done", title: "Done", cards: [KanbanCard(id: "4", title: "Task D")]),
    ]

    var summary: String {
        columns.map { "\($0.id):" + $0.cards.map(\.title).joined(separator: "+") }
            .joined(separator: " ")
    }
}

private enum Kanban {
    static let columnWidth = 112.0
    static let columnGap = 8.0
    static let cardHeight = 34.0
    static let cardGap = 6.0
    static let headerHeight = 28.0
    static let padding = 6.0
    static let snapRadius = 20.0
    static let ghostOpacity = 0.3
    static let titleSize = 13.0
    static let cardTextSize = 12.0
    static let cornerRadius = 4.0
    static let draggedColumnZ = 5
    static let cardZ = 1
    static let draggedCardZ = 10
}

func kanban(_ context: RenderContext<KanbanState>) -> Node<KanbanState> {
    let state = context.state
    let d = context.d

    return group {
        for (columnIndex, column) in state.columns.enumerated() {
            let columnID = "column-\(column.id)"
            let height = Kanban.headerHeight + Kanban.padding * 2
                + Double(column.cards.count) * (Kanban.cardHeight + Kanban.cardGap)

            group {
                rect(width: Kanban.columnWidth, height: height, cornerRadius: Kanban.cornerRadius)
                    .fill(Ink.panel)
                    .stroke(Ink.outline)

                label(column.title, size: Kanban.titleSize)
                    .fill(Ink.text)
                    .transform(.translate(Kanban.columnWidth / 2, Kanban.headerHeight / 2))

                for (cardIndex, card) in column.cards.enumerated() {
                    kanbanCard(card, column: columnIndex, index: cardIndex, context: context)
                }
            }
            .id(columnID)
            .transform(.translate(Double(columnIndex) * (Kanban.columnWidth + Kanban.columnGap), 0))
            .zIndex(.relative(context.draggedID == columnID ? Kanban.draggedColumnZ : 0))
            .onDrag {
                // The other places this column could go.
                let orders = state.columns.indices.map { target -> KanbanState in
                    var copy = state
                    copy.columns.insert(copy.columns.remove(at: columnIndex), at: target)
                    return copy
                }

                return d.between(orders).withSnapRadius(Kanban.snapRadius, transition: .standard)
            }
        }
    }
}

private func kanbanCard(
    _ card: KanbanCard,
    column: Int,
    index: Int,
    context: RenderContext<KanbanState>
) -> Node<KanbanState> {
    let state = context.state
    let id = "card-\(card.id)"
    let isDragged = context.draggedID == id
    let width = Kanban.columnWidth - Kanban.padding * 2
    let y = Kanban.headerHeight + Kanban.padding + Double(index) * (Kanban.cardHeight + Kanban.cardGap)

    return group {
        rect(width: width, height: Kanban.cardHeight, cornerRadius: Kanban.cornerRadius)
            .fill(.white)
            .stroke(isDragged ? Ink.blue : Ink.faint)

        label(card.title, size: Kanban.cardTextSize)
            .fill(Ink.text)
            .transform(.translate(width / 2, Kanban.cardHeight / 2))
    }
    .id(id)
    .transform(.translate(Kanban.padding, y))
    .zIndex(.relative(isDragged ? Kanban.draggedCardZ : Kanban.cardZ))
    .onDrag {
        var without = state
        without.columns[column].cards.remove(at: index)

        // Every slot in every column.
        let moves = without.columns.indices.flatMap { target in
            (0...without.columns[target].cards.count).map { slot -> KanbanState in
                var copy = without
                copy.columns[target].cards.insert(card, at: slot)
                return copy
            }
        }

        return context.d.closest(moves).withFloating(FloatingOptions(ghostOpacity: Kanban.ghostOpacity))
    }
}

// MARK: - Towers of Hanoi

struct HanoiState: Equatable {
    /// Each peg's disks, from the top down. Bigger numbers are bigger disks.
    var pegs = [[1, 2, 3], [], []]
}

private enum Hanoi {
    static let diskCount = 3
    static let pegWidth = 10.0
    static let baseHeight = 10.0
    static let diskHeight = 24.0
    static let minDiskWidth = 40.0
    static let diskWidthStep = 22.0
    static let pegSpacing = 118.0
    static let firstPegX = 60.0
    static let pegHeight = Double(diskCount + 1) * diskHeight
    static let baseWidth = 108.0
    static let ghostOpacity = 0.5
    static let cornerRadius = 4.0
    static let fontSize = 14.0
    static let topMargin = 10.0

    static func diskWidth(_ disk: Int) -> Double {
        minDiskWidth + Double(disk - 1) * diskWidthStep
    }
}

func hanoi(_ context: RenderContext<HanoiState>) -> Node<HanoiState> {
    let state = context.state

    return group {
        for pegIndex in state.pegs.indices {
            group {
                rect(width: Hanoi.baseWidth, height: Hanoi.baseHeight)
                    .fill(Ink.muted)
                    .transform(.translate(-Hanoi.baseWidth / 2, Hanoi.pegHeight))

                rect(width: Hanoi.pegWidth, height: Hanoi.pegHeight)
                    .fill(Ink.outline)
                    .transform(.translate(-Hanoi.pegWidth / 2, 0))
            }
            .transform(.translate(Hanoi.firstPegX + Double(pegIndex) * Hanoi.pegSpacing, 0))
        }

        for (pegIndex, peg) in state.pegs.enumerated() {
            for (position, disk) in peg.enumerated() {
                hanoiDisk(disk, peg: pegIndex, position: position, height: peg.count, context: context)
            }
        }
    }
    .transform(.translate(0, Hanoi.topMargin))
}

private func hanoiDisk(
    _ disk: Int,
    peg: Int,
    position: Int,
    height: Int,
    context: RenderContext<HanoiState>
) -> Node<HanoiState> {
    let state = context.state
    let width = Hanoi.diskWidth(disk)
    let x = Hanoi.firstPegX + Double(peg) * Hanoi.pegSpacing - width / 2
    let y = Hanoi.pegHeight - Double(height - position) * Hanoi.diskHeight

    let node: Node<HanoiState> = group {
        rect(width: width, height: Hanoi.diskHeight, cornerRadius: Hanoi.cornerRadius)
            .fill(Ink.series[disk % Ink.series.count])

        label(String(disk), size: Hanoi.fontSize)
            .fill(.white)
            .transform(.translate(width / 2, Hanoi.diskHeight / 2))
    }
    .id("disk-\(disk)")
    .transform(.translate(x, y))
    .zIndex(.relative(1))

    // Only the top disk of a peg can move.
    guard position == 0 else { return node }

    return node.onDrag {
        var without = state
        without.pegs[peg].removeFirst()

        // Legal moves: any peg whose top disk is bigger, or an empty one.
        let moves = without.pegs.indices.compactMap { target -> HanoiState? in
            if let top = without.pegs[target].first, top < disk { return nil }

            var copy = without
            copy.pegs[target].insert(disk, at: 0)
            return copy
        }

        return context.d.closest(moves).withFloating(FloatingOptions(ghostOpacity: Hanoi.ghostOpacity))
    }
}

// MARK: - Sliding tiles

struct Cell: Equatable {
    var x: Int
    var y: Int
}

struct FifteenState: Equatable {
    static let blank = " "

    var tiles: [String: Cell] = [
        "12": Cell(x: 0, y: 0), "1": Cell(x: 1, y: 0), "2": Cell(x: 2, y: 0), "15": Cell(x: 3, y: 0),
        "11": Cell(x: 0, y: 1), "6": Cell(x: 1, y: 1), "5": Cell(x: 2, y: 1), "8": Cell(x: 3, y: 1),
        "7": Cell(x: 0, y: 2), "10": Cell(x: 1, y: 2), "9": Cell(x: 2, y: 2), "4": Cell(x: 3, y: 2),
        blank: Cell(x: 0, y: 3), "13": Cell(x: 1, y: 3), "14": Cell(x: 2, y: 3), "3": Cell(x: 3, y: 3),
    ]

    /// The row-by-row layout, for the readout.
    var summary: String {
        tiles.sorted { ($0.value.y, $0.value.x) < ($1.value.y, $1.value.x) }
            .map { $0.key == Self.blank ? "_" : $0.key }
            .joined(separator: " ")
    }
}

private enum Fifteen {
    static let side = 4
    static let tile = 80.0
    static let snapRadius = 10.0
    static let fontSize = 24.0
    static let inset = 2.0
    static let lineWidth = 2.0
    static let neighbors = [Cell(x: -1, y: 0), Cell(x: 1, y: 0), Cell(x: 0, y: -1), Cell(x: 0, y: 1)]
}

func fifteen(_ context: RenderContext<FifteenState>) -> Node<FifteenState> {
    let state = context.state

    return group {
        for (key, cell) in state.tiles.sorted(by: { $0.key < $1.key }) {
            let isBlank = key == FifteenState.blank

            group {
                rect(width: Fifteen.tile, height: Fifteen.tile)
                    .fill(isBlank ? .clear : Ink.panel)
                    .stroke(isBlank ? .clear : Ink.text, lineWidth: Fifteen.lineWidth)

                if !isBlank {
                    label(key, size: Fifteen.fontSize)
                        .fill(Ink.text)
                        .transform(.translate(Fifteen.tile / 2, Fifteen.tile / 2))
                }
            }
            .id("tile-\(isBlank ? "blank" : key)")
            .transform(.translate(Double(cell.x) * Fifteen.tile, Double(cell.y) * Fifteen.tile))
            .onDrag {
                // A tile can only trade places with a neighboring blank.
                let swaps = Fifteen.neighbors.compactMap { offset -> DragSpec<FifteenState>? in
                    let target = Cell(x: cell.x + offset.x, y: cell.y + offset.y)

                    guard let other = state.tiles.first(where: { $0.value == target })?.key else {
                        return nil
                    }
                    guard isBlank || other == FifteenState.blank else { return nil }

                    var swapped = state
                    swapped.tiles[key] = target
                    swapped.tiles[other] = cell

                    return context.d.between([state, swapped])
                }

                return context.d.closest(swaps)
                    .withSnapRadius(Fifteen.snapRadius, chaining: .chainOnSnap)
            }
        }
    }
    .transform(.translate(Fifteen.inset, Fifteen.inset))
}

// MARK: - Tromino tiling

struct TrominoState: Equatable {
    var missing = Cell(x: 0, y: 0)
}

private enum Tromino {
    static let level = 3
    static let cell = 44.0
    static let padding = cell * 6 / 40
    static let ghostOpacity = 0.2
    static let snapRadius = 1.0
    static let boardSide = 1 << level
    static let inset = 2.0
    static let quarterTurn = 90.0
    static let colors = [
        RGBA(hex: 0xADD8E6), RGBA(hex: 0x90EE90), RGBA(hex: 0xFFB6C1), RGBA(hex: 0xFFFFE0),
    ]
}

enum TrominoMode: Int, CaseIterable {
    case smooth, snappy, maze

    var title: String {
        switch self {
        case .smooth: "between"
        case .snappy: "closest + floating"
        case .maze: "maze (chained)"
        }
    }
}

func tromino(mode: TrominoMode) -> Draggable<TrominoState> {
    { context in
        let state = context.state
        let d = context.d
        let square = Tromino.cell - 2 * Tromino.padding

        return group {
            trominoTiling(state.missing, level: Tromino.level)

            rect(width: square, height: square)
                .id("missing-square")
                .fill(.black)
                .zIndex(.relative(1))
                .transform(.translate(
                    Double(state.missing.x) * Tromino.cell + Tromino.padding,
                    Double(state.missing.y) * Tromino.cell + Tromino.padding
                ))
                .onDrag {
                    switch mode {
                    case .smooth:
                        return d.between(allTrominoStates())

                    case .snappy:
                        return d.closest(allTrominoStates())
                            .withFloating(FloatingOptions(ghostOpacity: Tromino.ghostOpacity))

                    case .maze:
                        let steps = singleRotations(of: state).map { d.between([state, $0]) }

                        return d.closest(steps)
                            .withSnapRadius(Tromino.snapRadius, chaining: .chainOnSnap)
                    }
                }
        }
        .transform(.translate(Tromino.inset, Tromino.inset))
    }
}

private func allTrominoStates() -> [TrominoState] {
    (0..<Tromino.boardSide).flatMap { x in
        (0..<Tromino.boardSide).map { y in TrominoState(missing: Cell(x: x, y: y)) }
    }
}

/// The moves that rotate exactly one tromino.
private func singleRotations(of state: TrominoState) -> [TrominoState] {
    (1...Tromino.level).flatMap { level -> [TrominoState] in
        let full = 1 << level
        let half = full / 2
        let missing = state.missing
        let isLeft = missing.x % full == half - 1
        let isRight = missing.x % full == half
        let isTop = missing.y % full == half - 1
        let isBottom = missing.y % full == half

        guard (isLeft || isRight) && (isTop || isBottom) else { return [] }

        return [
            TrominoState(missing: Cell(x: missing.x + (isLeft ? 1 : -1), y: missing.y)),
            TrominoState(missing: Cell(x: missing.x, y: missing.y + (isTop ? 1 : -1))),
        ]
    }
}

/// Tiles a board with one missing square: split it in four, then cover
/// the center with a tromino that gives each quarter a missing square.
private func trominoTiling(_ missing: Cell, level: Int) -> Node<TrominoState> {
    guard level > 0 else {
        return rect(width: Tromino.cell, height: Tromino.cell).fill(.white).stroke(.black)
    }

    let half = 1 << (level - 1)
    let isLeft = missing.x < half
    let isTop = missing.y < half
    let offset = Double(half) * Tromino.cell
    let turns = isLeft ? (isTop ? 0 : 3) : (isTop ? 1 : 2)
    let edge = Tromino.padding
    let far = Tromino.cell - Tromino.padding
    let near = Tromino.padding - Tromino.cell

    return group {
        trominoTiling(isLeft && isTop ? missing : Cell(x: half - 1, y: half - 1), level: level - 1)

        trominoTiling(
            !isLeft && isTop ? Cell(x: missing.x - half, y: missing.y) : Cell(x: 0, y: half - 1),
            level: level - 1
        )
        .transform(.translate(offset, 0))

        trominoTiling(
            isLeft && !isTop ? Cell(x: missing.x, y: missing.y - half) : Cell(x: half - 1, y: 0),
            level: level - 1
        )
        .transform(.translate(0, offset))

        group {
            trominoTiling(
                !isLeft && !isTop ? Cell(x: missing.x - half, y: missing.y - half) : Cell(x: 0, y: 0),
                level: level - 1
            )

            path([
                .move(Vec2(edge, edge)),
                .line(Vec2(near, edge)),
                .line(Vec2(near, far)),
                .line(Vec2(far, far)),
                .line(Vec2(far, near)),
                .line(Vec2(edge, near)),
                .close,
            ])
            .fill(Tromino.colors[level - 1])
            .stroke(.black)
            .transform(.rotate(degrees: Double(turns) * Tromino.quarterTurn))
            .hitTesting(.disabled)
        }
        .transform(.translate(offset, offset))
    }
}
