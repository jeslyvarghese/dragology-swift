import DragologySwift
import Foundation

// MARK: - Snap to islands

struct IslandState: Equatable {
    /// The island it's resting on, or nil when it's out at sea.
    var island: Int? = 0
    var x = 0.0
    var y = 0.0

    var summary: String {
        island.map { "island \($0)" } ?? "at sea"
    }
}

private enum Islands {
    static let positions = [Vec2(80, 130), Vec2(280, 130)]
    static let smallRadius = 10.0
    static let bigRadius = 20.0
    static let dotRadius = 12.0
    static let lineWidth = 2.0
}

func islands(_ context: RenderContext<IslandState>) -> Node<IslandState> {
    let state = context.state
    let d = context.d
    let position = state.island.map { Islands.positions[$0] } ?? Vec2(state.x, state.y)

    return group {
        for (index, island) in Islands.positions.enumerated() {
            circle(radius: state.island == index ? Islands.bigRadius : Islands.smallRadius)
                .stroke(Ink.outline, lineWidth: Islands.lineWidth)
                .transform(.translate(island))
        }

        circle(radius: Islands.dotRadius)
            .id("dot")
            .fill(Ink.blue)
            .transform(.translate(position))
            .onDrag {
                d.closest(Islands.positions.indices.map { IslandState(island: $0) })
                    .withFloating()
                    .whenFar(d.vary(IslandState(island: nil), \.x, \.y))
            }
    }
}

// MARK: - Magnetic targets

struct MagnetState: Equatable {
    var current = 1
}

private enum Magnets {
    static let targets: [(position: Vec2, strength: Double, color: RGBA)] = [
        (Vec2(100, 140), 0.6, Ink.muted),
        (Vec2(200, 60), 1, Ink.red),
        (Vec2(320, 140), 2.5, Ink.blue),
    ]
    static let targetRadius = 18.0
    static let haloBase = 55.0
    static let haloOpacity = 0.06
    static let targetOpacity = 0.6
    static let puckRadius = 14.0
    static let labelSize = 11.0
    static let labelOffset = 28.0
}

func magnets(_ context: RenderContext<MagnetState>) -> Node<MagnetState> {
    let d = context.d

    return group {
        for (index, target) in Magnets.targets.enumerated() {
            group {
                circle(radius: Magnets.haloBase / target.strength)
                    .fill(target.color.withOpacity(Magnets.haloOpacity))
                    .stroke(target.color.withOpacity(Magnets.targetOpacity))
                    .hitTesting(.disabled)

                circle(radius: Magnets.targetRadius)
                    .fill(target.color.withOpacity(Magnets.targetOpacity))
                    .hitTesting(.disabled)

                label("×\(target.strength)", size: Magnets.labelSize)
                    .fill(Ink.text)
                    .transform(.translate(0, Magnets.labelOffset))
                    .hitTesting(.disabled)
            }
            .id("target-\(index)")
            .transform(.translate(target.position))
        }

        circle(radius: Magnets.puckRadius)
            .id("puck")
            .fill(Ink.text)
            .stroke(.white, lineWidth: 2)
            .zIndex(.relative(2))
            .transform(.translate(Magnets.targets[context.state.current].position))
            .onDrag {
                d.closest(Magnets.targets.indices.map { index in
                    let strength = Magnets.targets[index].strength

                    return d.fixed(MagnetState(current: index)).changeGap { $0 * strength }
                })
            }
    }
}

// MARK: - Sharpness

struct SharpnessState: Equatable {
    var isOn = false
}

private enum Sharpness {
    static let levels = [1, 1.5, 2, 3, 5, 10]
    static let columns = 2
    static let cellWidth = 170.0
    static let cellHeight = 100.0
    static let switchWidth = 120.0
    static let switchHeight = 60.0
    static let knobRadius = 26.0
    static let offX = 30.0
    static let onX = 90.0
    static let margin = 20.0
    static let labelSize = 11.0
    static let labelOffset = -9.0
}

func sharpness(_ context: RenderContext<SharpnessState>) -> Node<SharpnessState> {
    let state = context.state

    return group {
        for (index, level) in Sharpness.levels.enumerated() {
            group {
                label("sharpness: \(level)", size: Sharpness.labelSize)
                    .fill(Ink.muted)
                    .transform(.translate(Sharpness.switchWidth / 2, Sharpness.labelOffset))

                rect(
                    width: Sharpness.switchWidth,
                    height: Sharpness.switchHeight,
                    cornerRadius: Sharpness.switchHeight / 2
                )
                .fill(state.isOn ? Ink.green : Ink.outline)

                circle(radius: Sharpness.knobRadius)
                    .id("knob-\(index)")
                    .fill(.white)
                    .transform(.translate(
                        state.isOn ? Sharpness.onX : Sharpness.offX,
                        Sharpness.switchHeight / 2
                    ))
                    .onDrag {
                        context.d.between(
                            [SharpnessState(isOn: false), SharpnessState(isOn: true)],
                            options: BetweenOptions(sharpness: level)
                        )
                    }
            }
            .transform(.translate(
                Sharpness.margin + Double(index % Sharpness.columns) * Sharpness.cellWidth,
                Sharpness.margin + Double(index / Sharpness.columns) * Sharpness.cellHeight
            ))
        }
    }
}

// MARK: - Blend weights

struct BlendState: Equatable {
    var corner = 0
}

private enum BlendGrid {
    static let targets: [(position: Vec2, color: RGBA)] = [
        (Vec2(40, 40), Ink.red),
        (Vec2(300, 60), Ink.blue),
        (Vec2(280, 260), Ink.green),
        (Vec2(60, 280), Ink.amber),
        (Vec2(150, 140), Ink.purple),
    ]
    static let dotRadius = 22.0
    static let markerRadius = 6.0
    static let swatchSide = 40.0
    static let swatchCornerRadius = 8.0
    static let swatchPosition = Vec2(300, 280)
}

enum BlendMode: Int, CaseIterable {
    case delaunay, naturalNeighbor

    var title: String {
        switch self {
        case .delaunay: "Delaunay"
        case .naturalNeighbor: "natural neighbor"
        }
    }

    var interpolation: BetweenInterpolation {
        switch self {
        case .delaunay: .delaunay
        case .naturalNeighbor: .naturalNeighbor
        }
    }
}

func blendWeights(mode: BlendMode) -> Draggable<BlendState> {
    { context in
        let target = BlendGrid.targets[context.state.corner]

        return group {
            for other in BlendGrid.targets {
                circle(radius: BlendGrid.markerRadius)
                    .fill(other.color)
                    .transform(.translate(other.position))
            }

            rect(
                width: BlendGrid.swatchSide,
                height: BlendGrid.swatchSide,
                cornerRadius: BlendGrid.swatchCornerRadius
            )
            .fill(target.color)
            .transform(.translate(BlendGrid.swatchPosition))

            circle(radius: BlendGrid.dotRadius)
                .id("dot")
                .fill(target.color)
                .transform(.translate(target.position))
                .onDrag {
                    context.d.between(
                        BlendGrid.targets.indices.map { BlendState(corner: $0) },
                        options: BetweenOptions(interpolation: mode.interpolation)
                    )
                }
        }
    }
}

// MARK: - Emerge from

struct EmergeState: Equatable {
    var isRight = false
}

private enum Emerge {
    static let leftX = 90.0
    static let rightX = 250.0
    static let y = 50.0
    static let lowerY = 150.0
    static let radius = 18.0
    static let lineWidth = 2.0
}

func emerge(_ context: RenderContext<EmergeState>) -> Node<EmergeState> {
    let state = context.state

    return group {
        circle(radius: Emerge.radius)
            .id("dot")
            .fill(Ink.blue)
            .transform(.translate(state.isRight ? Emerge.rightX : Emerge.leftX, Emerge.y))
            .onDrag {
                context.d.between([EmergeState(isRight: false), EmergeState(isRight: true)])
            }

        if state.isRight {
            circle(radius: Emerge.radius)
                .id("second-dot")
                .fill(Ink.amber)
                .stroke(Ink.text, lineWidth: Emerge.lineWidth)
                .transform(.translate(Emerge.rightX, Emerge.lowerY))
                .emergeFrom("dot")
        }
    }
}

// MARK: - Sprouting tree

struct SproutNode: Equatable {
    var id: String
    var children: [SproutNode] = []
    var emergeOrigin: String?

    var leafCount: Int {
        children.isEmpty ? 1 : children.reduce(0) { $0 + $1.leafCount }
    }

    /// Replaces a leaf with a fork. The child at `keepIndex` keeps the
    /// leaf's id, so it visibly moves, while the others grow out of it.
    func sprouting(_ target: String, keepIndex: Int) -> SproutNode {
        guard id == target, children.isEmpty else {
            var copy = self
            copy.emergeOrigin = nil
            copy.children = children.map { $0.sprouting(target, keepIndex: keepIndex) }
            return copy
        }

        let kept = SproutNode(id: target)
        let sibling = SproutNode(id: freshID(), emergeOrigin: target)

        return SproutNode(
            id: freshID(),
            children: keepIndex == 0 ? [kept, sibling] : [sibling, kept],
            emergeOrigin: target
        )
    }

    /// Replaces a leaf's parent with the leaf.
    func pruning(_ target: String) -> SproutNode {
        if children.contains(where: { $0.id == target }) {
            return SproutNode(id: target)
        }

        var copy = self
        copy.emergeOrigin = nil
        copy.children = children.map { $0.pruning(target) }

        return copy
    }
}

struct SproutState: Equatable {
    var root = SproutNode(id: "root")

    var summary: String {
        "leaves: \(root.leafCount)"
    }
}

private enum Sprout {
    static let nodeRadius = 15.0
    static let levelHeight = 60.0
    static let leafWidth = 46.0
    static let top = 40.0
    static let centerX = 180.0
    static let snapRadius = 5.0
    static let lineWidth = 2.0
    static let draggedZ = 3
    static let restingZ = 1
}

/// Each subtree gets a width in proportion to its leaves.
private func sproutLayout(_ node: SproutNode, x: Double, y: Double) -> [String: Vec2] {
    var positions = [node.id: Vec2(x, y)]
    var cursor = x - Double(node.leafCount) * Sprout.leafWidth / 2

    guard !node.children.isEmpty else { return positions }

    for child in node.children {
        let width = Double(child.leafCount) * Sprout.leafWidth

        positions.merge(sproutLayout(child, x: cursor + width / 2, y: y + Sprout.levelHeight)) { first, _ in first }
        cursor += width
    }

    return positions
}

func sproutingTree(_ context: RenderContext<SproutState>) -> Node<SproutState> {
    let positions = sproutLayout(context.state.root, x: Sprout.centerX, y: Sprout.top)

    return group { sproutSubtree(context.state.root, positions: positions, context: context) }
}

private func sproutSubtree(
    _ node: SproutNode,
    positions: [String: Vec2],
    context: RenderContext<SproutState>
) -> Node<SproutState> {
    let position = positions[node.id] ?? .zero
    let isLeaf = node.children.isEmpty

    return group {
        for (index, child) in node.children.enumerated() {
            line(from: position, to: positions[child.id] ?? .zero)
                .id("edge-\(node.id)-\(index)")
                .stroke(Ink.outline, lineWidth: Sprout.lineWidth)
                .emergeFrom(node.emergeOrigin ?? child.emergeOrigin)
                .hitTesting(.disabled)
        }

        for child in node.children {
            sproutSubtree(child, positions: positions, context: context)
        }

        sproutDot(node, position: position, isLeaf: isLeaf, context: context)
    }
    .id("tree-\(node.id)")
}

private func sproutDot(
    _ node: SproutNode,
    position: Vec2,
    isLeaf: Bool,
    context: RenderContext<SproutState>
) -> Node<SproutState> {
    let state = context.state
    let d = context.d

    let dot: Node<SproutState> = circle(radius: Sprout.nodeRadius)
        .id(node.id)
        .fill(isLeaf ? Ink.blue : Ink.faint)
        .stroke(isLeaf ? Ink.text : Ink.muted, lineWidth: Sprout.lineWidth)
        .transform(.translate(position))
        .zIndex(.relative(context.draggedID == node.id ? Sprout.draggedZ : Sprout.restingZ))
        .emergeFrom(node.emergeOrigin)

    guard isLeaf else { return dot }

    return dot.onDrag {
        // Pull down to sprout left or right, or up to fold into the parent.
        var options = [0, 1].map { keepIndex in
            d.between([state, SproutState(root: state.root.sprouting(node.id, keepIndex: keepIndex))])
        }

        if state.root.id != node.id {
            options.append(d.between([state, SproutState(root: state.root.pruning(node.id))]))
        }

        return d.closest(options).withSnapRadius(Sprout.snapRadius, chaining: .chainOnSnap)
    }
}

// MARK: - Drag to copy

struct CopyDot: Equatable {
    var id: String
    var position: Vec2
    var color: RGBA
}

struct CopyState: Equatable {
    var dots = [CopyDot(id: "first", position: Vec2(170, 110), color: Ink.series[0])]

    var summary: String {
        "dots: \(dots.count)"
    }

    /// This state with one more dot, sitting on top of `dot`.
    func addingCopy(of dot: CopyDot) -> (state: CopyState, copy: Int) {
        var next = self
        var copy = dot
        copy.id = freshID()
        copy.color = Ink.series[dots.count % Ink.series.count]
        next.dots.append(copy)

        return (next, next.dots.count - 1)
    }
}

private enum Copies {
    static let radius = 26.0
}

func dragToCopy(_ context: RenderContext<CopyState>) -> Node<CopyState> {
    let state = context.state
    let d = context.d

    return group {
        for (index, dot) in state.dots.enumerated() {
            circle(radius: Copies.radius)
                .id("dot-\(dot.id)")
                .fill(dot.color)
                .transform(.translate(dot.position))
                .onTap {
                    guard state.dots.count > 1 else { return }

                    var next = state
                    next.dots.remove(at: index)
                    context.setState(next)
                }
                .onDrag {
                    let (next, copy) = state.addingCopy(of: dot)

                    return d.switchToStateAndFollow(
                        next,
                        "dot-\(next.dots[copy].id)",
                        followSpec: d.vary(next, \.dots[copy].position.x, \.dots[copy].position.y)
                    )
                }
        }
    }
}

// MARK: - Copy or move

/// Stands in for the web demo's Alt key, which iPhones don't have.
@Observable
final class CopySwitch {
    var isCopying = false
}

func copyOrMove(_ isCopying: CopySwitch) -> Draggable<CopyState> {
    { context in
        let state = context.state
        let d = context.d

        return group {
            for (index, dot) in state.dots.enumerated() {
                circle(radius: Copies.radius)
                    .id("dot-\(dot.id)")
                    .fill(dot.color)
                    .transform(.translate(dot.position))
                    .onDrag {
                        d.reactTo({ isCopying.isCopying }) { copying in
                            guard copying else {
                                return d.vary(state, \.dots[index].position.x, \.dots[index].position.y)
                            }

                            let (next, copy) = state.addingCopy(of: dot)

                            return d.switchToStateAndFollow(
                                next,
                                "dot-\(next.dots[copy].id)",
                                followSpec: d.vary(next, \.dots[copy].position.x, \.dots[copy].position.y)
                            )
                        }
                    }
            }
        }
    }
}

// MARK: - Insert and remove

struct ShelfTile: Equatable {
    var id: String
    var label: String
}

struct ShelfState: Equatable {
    var items = [
        ShelfTile(id: "A", label: "🍎"),
        ShelfTile(id: "B", label: "🍎"),
        ShelfTile(id: "C", label: "🍌"),
    ]

    var summary: String {
        items.isEmpty ? "(empty)" : items.map(\.label).joined()
    }
}

enum Shelf {
    static let tile = 50.0
    static let store = ["🍎", "🍌", "🍇"]
    static let toolbarPadding = 5.0
    static let toolbarExtraWidth = 20.0
    static let toolbarMargin = 10.0
    static let binX = 280.0
    static let fontSize = 22.0
    static let binFontSize = 28.0
    static let cornerRadius = 4.0
    static let lineWidth = 2.0
    static let origin = 8.0
    static let backgroundZ = -10
    static let binFill = RGBA(hex: 0xFFEEEE)

    static var toolbarHeight: Double { tile + 2 * toolbarPadding }
    static var listY: Double { toolbarHeight + toolbarMargin }
}

func shelf(_ context: RenderContext<ShelfState>) -> Node<ShelfState> {
    let state = context.state
    let d = context.d

    // Offers every slot in the list, plus the bin.
    func dropSpots(in base: ShelfState, tile: ShelfTile) -> DragSpec<ShelfState> {
        let inserts = (0...base.items.count).map { slot -> ShelfState in
            var copy = base
            copy.items.insert(tile, at: slot)
            return copy
        }

        // No floating over the bin, so the tile visibly disappears.
        return d.closest([
            d.closest(inserts).withFloating(),
            d.dropTarget("bin", base),
        ])
    }

    return group {
        rect(
            width: Double(Shelf.store.count) * Shelf.tile + Shelf.toolbarExtraWidth,
            height: Shelf.toolbarHeight,
            cornerRadius: Shelf.cornerRadius
        )
        .id("toolbar")
        .fill(Ink.panel)
        .stroke(Ink.outline)
        .zIndex(.relative(Shelf.backgroundZ))

        for (index, item) in Shelf.store.enumerated() {
            shelfTile(
                ShelfTile(id: "store-\(index)", label: item),
                at: Vec2(Shelf.toolbarPadding * 2 + Double(index) * Shelf.tile, Shelf.toolbarPadding)
            ) {
                // Pulls a new tile off the toolbar and follows that instead.
                let tile = ShelfTile(id: freshID(), label: item)
                var withTile = state
                withTile.items.append(tile)

                return d.switchToStateAndFollow(
                    withTile,
                    "tile-\(tile.id)",
                    followSpec: dropSpots(in: state, tile: tile).whenFar(d.fixed(state).withFloating())
                )
            }
        }

        for (index, tile) in state.items.enumerated() {
            shelfTile(tile, at: Vec2(Double(index) * Shelf.tile, Shelf.listY)) {
                var without = state
                without.items.remove(at: index)

                return dropSpots(in: without, tile: tile).whenFar(d.fixed(state).withFloating())
            }
        }

        group {
            rect(width: Shelf.tile, height: Shelf.tile, cornerRadius: Shelf.cornerRadius)
                .fill(Shelf.binFill)
                .stroke(Ink.muted, lineWidth: Shelf.lineWidth)

            label("🗑", size: Shelf.binFontSize)
                .transform(.translate(Shelf.tile / 2, Shelf.tile / 2))
        }
        .id("bin")
        .transform(.translate(Shelf.binX, 0))
    }
    .transform(.translate(Shelf.origin, Shelf.origin))
}

private func shelfTile(
    _ tile: ShelfTile,
    at position: Vec2,
    onDrag: @escaping () -> DragSpec<ShelfState>
) -> Node<ShelfState> {
    group {
        rect(width: Shelf.tile, height: Shelf.tile)
            .fill(.white)
            .stroke(.black, lineWidth: Shelf.lineWidth)

        label(tile.label, size: Shelf.fontSize)
            .transform(.translate(Shelf.tile / 2, Shelf.tile / 2))
    }
    .id("tile-\(tile.id)")
    .transform(.translate(position))
    .onDrag(onDrag)
}

// MARK: - Timelines

struct TimelineBlock: Equatable {
    var id: String
    var position: Double
    var track: Int
    var color: RGBA
}

struct TimelineState: Equatable {
    var blocks = [
        TimelineBlock(id: "Cats", position: 10, track: 0, color: Ink.blue),
        TimelineBlock(id: "Dogs", position: 100, track: 1, color: Ink.red),
        TimelineBlock(id: "Clouds", position: 50, track: 3, color: Ink.green),
    ]

    var summary: String {
        blocks.map { "\($0.id):\($0.track)@\(Int($0.position.rounded()))" }.joined(separator: " ")
    }
}

private enum Timeline {
    static let tracks = 4
    static let trackHeight = 36.0
    static let gap = 6.0
    static let blockWidth = 80.0
    static let trackWidth = 340.0
    static let margin = 10.0
    static let cornerRadius = 6.0
    static let fontSize = 13.0
    static let branchTransition = Transition(easing: .cubicOut, duration: 0.1)
    static let draggedZ = 1
}

/// Slides along a track, and hops to whichever track is closest.
private func blockSpec(_ d: DragSpecBuilder<TimelineBlock>, _ block: TimelineBlock) -> DragSpec<TimelineBlock> {
    let onTracks = (0..<Timeline.tracks).map { track -> DragSpec<TimelineBlock> in
        var moved = block
        moved.track = track

        return d.vary(moved, \.position, constraint: { candidate in
            Constraint.inOrder(0, candidate.position, Timeline.trackWidth - Timeline.blockWidth)
        })
    }

    return d.closest(onTracks).withBranchTransition(Timeline.branchTransition)
}

private func blockShape<State>(_ block: TimelineBlock) -> Node<State> {
    group {
        rect(width: Timeline.blockWidth, height: Timeline.trackHeight, cornerRadius: Timeline.cornerRadius)
            .fill(block.color)

        label(block.id, size: Timeline.fontSize)
            .fill(.white)
            .transform(.translate(Timeline.blockWidth / 2, Timeline.trackHeight / 2))
    }
    .id(block.id)
    .transform(.translate(block.position, Double(block.track) * (Timeline.trackHeight + Timeline.gap)))
}

private func timelineTracks<State>() -> [Node<State>] {
    (0..<Timeline.tracks).map { track in
        rect(width: Timeline.trackWidth, height: Timeline.trackHeight, cornerRadius: Timeline.cornerRadius)
            .fill(Ink.panel)
            .stroke(Ink.faint)
            .transform(.translate(0, Double(track) * (Timeline.trackHeight + Timeline.gap)))
    }
}

/// Uses `d.substate`, so the spec only deals with one block.
func timelineSubstate(_ context: RenderContext<TimelineState>) -> Node<TimelineState> {
    let state = context.state

    let blocks = state.blocks.enumerated().map { index, block -> Node<TimelineState> in
        blockShape(block)
            .zIndex(.relative(context.draggedID == block.id ? Timeline.draggedZ : 0))
            .onDrag {
                context.d.substate(state, \.blocks[index]) { d in blockSpec(d, block) }
            }
    }

    return Node(children: timelineTracks() + blocks)
        .transform(.translate(Timeline.margin, Timeline.margin))
}

/// Uses `embed`, so each block is a draggable in its own right.
func timelineEmbed(_ context: RenderContext<TimelineState>) -> Node<TimelineState> {
    let blocks = context.state.blocks.indices.map { index in
        context.embed(blockDraggable, at: \.blocks[index])
    }

    return Node(children: timelineTracks() + blocks)
        .transform(.translate(Timeline.margin, Timeline.margin))
}

private func blockDraggable(_ context: RenderContext<TimelineBlock>) -> Node<TimelineBlock> {
    blockShape(context.state)
        .zIndex(.relative(context.draggedID == context.state.id ? Timeline.draggedZ : 0))
        .onDrag { blockSpec(context.d, context.state) }
}

// MARK: - Overlay

struct MarkerState: Equatable {
    var isDocked = false
}

private enum Marker {
    static let home = Vec2(70, 90)
    static let dock = Vec2(280, 90)
    static let radius = 22.0
    static let ringRadius = 30.0
    static let lineWidth = 3.0
    static let farGap = 80.0
}

func marker(_ context: RenderContext<MarkerState>) -> Node<MarkerState> {
    let state = context.state
    let docked = MarkerState(isDocked: true)

    let ring: Node<MarkerState> = circle(radius: Marker.ringRadius)
        .id("ring")
        .stroke(Ink.amber, lineWidth: Marker.lineWidth)
        .transform(.translate(Marker.dock))

    return group {
        circle(radius: Marker.radius)
            .id("dot")
            .fill(Ink.blue)
            .transform(.translate(state.isDocked ? Marker.dock : Marker.home))
            .onDrag {
                context.d
                    .fixed(docked)
                    .whenFar(MarkerState(isDocked: false), gap: WhenFarGap(Marker.farGap))
                    .withOverlay(ring)
            }
    }
}
