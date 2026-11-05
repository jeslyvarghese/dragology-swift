import Dragology
import Foundation

// MARK: - Trees and maps

struct TwistTree: Sendable {
    var id: String
    var children: [TwistTree] = []

    var preorder: [TwistTree] {
        [self] + children.flatMap(\.preorder)
    }
}

/// Where each node of one tree goes in another.
typealias TreeMorph = [String: String]

/// A tree, with every order-preserving map from it to itself.
struct TwistUniverse: Sendable {
    let tree: TwistTree
    let morphs: [TreeMorph]
    private let distances: [String: [String: Int]]

    static let small = TwistUniverse(TwistTree(id: "root", children: [
        TwistTree(id: "a"),
        TwistTree(id: "b"),
    ]))

    static let large = TwistUniverse(TwistTree(id: "root", children: [
        TwistTree(id: "a", children: [TwistTree(id: "a1"), TwistTree(id: "a2")]),
        TwistTree(id: "b", children: [TwistTree(id: "b1"), TwistTree(id: "b2")]),
    ]))

    private init(_ tree: TwistTree) {
        self.tree = tree
        morphs = Self.allMorphs(of: tree)
        distances = Self.pairwiseDistances(in: tree)
    }

    func distance(_ a: String, _ b: String) -> Int {
        distances[a]?[b] ?? 0
    }

    /// Every map where an ancestor stays an ancestor (or the same node).
    private static func allMorphs(of tree: TwistTree) -> [TreeMorph] {
        var memo: [String: [TreeMorph]] = [:]

        func morphs(_ domain: TwistTree, into codomain: TwistTree) -> [TreeMorph] {
            let key = domain.id + ">" + codomain.id

            if let known = memo[key] { return known }

            // Each child can go anywhere at or below this node.
            let options = domain.children.map { child in
                codomain.preorder.flatMap { morphs(child, into: $0) }
            }

            let result = cartesianProduct(options).map { combination in
                combination.reduce(into: [domain.id: codomain.id]) { merged, morph in
                    merged.merge(morph) { first, _ in first }
                }
            }

            memo[key] = result

            return result
        }

        return tree.preorder.flatMap { morphs(tree, into: $0) }
    }

    private static func cartesianProduct(_ lists: [[TreeMorph]]) -> [[TreeMorph]] {
        lists.reduce([[]]) { partial, list in
            partial.flatMap { prefix in list.map { prefix + [$0] } }
        }
    }

    /// The path between two nodes goes up to their lowest common ancestor.
    private static func pairwiseDistances(in tree: TwistTree) -> [String: [String: Int]] {
        var ancestry: [String: [String]] = [:]

        func visit(_ node: TwistTree, path: [String]) {
            let here = path + [node.id]
            ancestry[node.id] = here
            node.children.forEach { visit($0, path: here) }
        }

        visit(tree, path: [])

        return ancestry.mapValues { first in
            ancestry.mapValues { second in
                let shared = zip(first, second).prefix { $0 == $1 }.count
                return first.count + second.count - 2 * shared
            }
        }
    }
}

struct TwistState: Equatable {
    var morph: TreeMorph
    var highlightedNode: String?

    var summary: String {
        morph.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: " ")
    }
}

enum TwistMode: Int, CaseIterable {
    case naturalNeighbor, delaunay, oneNode, bad, worse, traditional

    var title: String {
        switch self {
        case .naturalNeighbor: "natural neighbor"
        case .delaunay: "Delaunay"
        case .oneNode: "one node at a time"
        case .bad: "bad drag: drop targets"
        case .worse: "worse drag: no animation"
        case .traditional: "with traditional diagram"
        }
    }

    /// The drop-target modes show what the usual approach feels like.
    fileprivate var usesDropTargets: Bool {
        self == .bad || self == .worse
    }
}

private enum Twist {
    static let bgPadding = 10.0
    static let bgGap = 40.0
    static let fgSize = 40.0
    static let fgGap = 20.0
    static let emptyBgSize = 10.0
    static let snapRadius = 20.0
    static let badTransition = Transition(easing: .cubicOut, duration: 0.3)
    static let bgEdgeWidth = 12.0
    static let fgEdgeWidth = 2.0
    static let bgFill = RGBA(hex: 0xD3D3D3)
    static let highlight = RGBA(hex: 0x93C5FD)
    static let arrow = RGBA(hex: 0x4287F5)
    static let draggedNode = Ink.blue
    static let edgeZ = -2
    static let circleZ = -1
    static let traditionalY = 300.0
    static let traditionalGap = 40.0
    /// How far an arrow bows, relative to the distance it spans.
    static let arrowBowDivisor = 6.0
    static let arrowHeadLength = 22.0
    static let arrowHeadAngle = Double.pi / 5
    static let arrowHeadInset = 5.0
}

// MARK: - Interval layout

/// Overlaps two intervals so that the union starts at zero, is as short
/// as possible, and then lines their anchors up as well as it can.
private func overlapIntervals(
    aLength: Double,
    aAnchor: Double,
    bLength: Double,
    bAnchor: Double
) -> (aOffset: Double, bOffset: Double, length: Double) {
    if aLength >= bLength {
        return (0, max(0, min(aLength - bLength, aAnchor - bAnchor)), aLength)
    }

    return (max(0, min(bLength - aLength, bAnchor - aAnchor)), 0, bLength)
}

// MARK: - Rendering

func twistedTrees(_ universe: TwistUniverse, mode: TwistMode) -> Draggable<TwistState> {
    { context in
        let renderer = TwistRenderer(universe: universe, mode: mode, context: context)
        let bgTree = renderer.drawBgSubtree(universe.tree, fgNodes: [universe.tree]).drawn.node
        let extras = mode == .traditional ? renderer.drawTraditional() : []
        let main = Node<TwistState>(children: [bgTree] + extras)

        return Node(children: [main] + renderer.finalizers.run(against: main))
    }
}

/// Draws one state. Grey "background" nodes hold the black "foreground"
/// nodes that the map sends there.
private struct TwistRenderer {
    struct Drawn {
        var node: Node<TwistState>
        var width: Double
        var height: Double
    }

    struct DrawnBg {
        var drawn: Drawn
        var center: PointRef
    }

    let universe: TwistUniverse
    let mode: TwistMode
    let context: RenderContext<TwistState>
    let finalizers = Finalizers<TwistState>()

    private var morph: TreeMorph { context.state.morph }

    // MARK: Drag

    /// One map per place the dragged node could go, moving everything
    /// else as little as possible.
    private func targetMorphs(for dragged: String) -> [TreeMorph] {
        let domainIDs = Array(morph.keys)

        if mode == .oneNode {
            return universe.morphs.filter { candidate in
                domainIDs.allSatisfy { $0 == dragged || morph[$0] == candidate[$0] }
            }
        }

        let movement = { (candidate: TreeMorph) in
            domainIDs.reduce(0) { sum, id in
                sum + universe.distance(morph[id] ?? "", candidate[id] ?? "")
            }
        }

        return universe.tree.preorder.compactMap { target in
            universe.morphs
                .filter { $0[dragged] == target.id }
                .min { movement($0) < movement($1) }
        }
    }

    func dragSpec(for dragged: String) -> DragSpec<TwistState> {
        let d = context.d
        let morphs = targetMorphs(for: dragged)

        guard mode.usesDropTargets else {
            let interpolation: BetweenInterpolation = mode == .delaunay ? .delaunay : .naturalNeighbor

            return d
                .between(morphs.map { TwistState(morph: $0) }, options: BetweenOptions(interpolation: interpolation))
                .withSnapRadius(Twist.snapRadius, transition: .standard)
        }

        let current = morph
        let byTarget = Dictionary(morphs.compactMap { candidate in
            candidate[dragged].map { ($0, candidate) }
        }) { first, _ in first }

        let targets = byTarget.keys.sorted().map { target in
            d.dropTarget("bg-circle-\(target)", TwistState(morph: current, highlightedNode: target))
        }

        return d.closest(targets)
            .whenFar(TwistState(morph: current))
            .onDrop { preview in
                TwistState(morph: preview.highlightedNode.flatMap { byTarget[$0] } ?? current)
            }
            .withDropTransition(mode == .bad ? Twist.badTransition : nil)
    }

    // MARK: Background tree

    func drawBgSubtree(_ bgNode: TwistTree, fgNodes: [TwistTree]) -> DrawnBg {
        let here = fgNodes.filter { morph[$0.id] == bgNode.id }
        let passingThrough = fgNodes.filter { morph[$0.id] != bgNode.id }
        let (bg, leftBelow) = drawBgNode(bgNode, fgNodes: here)
        let below = passingThrough + leftBelow

        guard !bgNode.children.isEmpty else { return bg }

        let children = bgNode.children.map { drawBgSubtree($0, fgNodes: below) }
        let gaps = Twist.bgGap * Double(children.count - 1)
        let childrenWidth = children.reduce(gaps) { $0 + $1.drawn.width }

        let overlap = overlapIntervals(
            aLength: bg.drawn.width,
            aAnchor: bg.drawn.width / 2,
            bLength: childrenWidth,
            bAnchor: childrenWidth / 2
        )

        var parts = [
            Node<TwistState>(children: [bg.drawn.node])
                .id("bg-node-group-\(bgNode.id)")
                .transform(.translate(overlap.aOffset, 0)),
        ]

        var x = overlap.bOffset
        let y = bg.drawn.height + Twist.bgGap
        var bottom = bg.drawn.height

        for (child, drawn) in zip(bgNode.children, children) {
            parts.append(
                Node(children: [drawn.drawn.node])
                    .id("bg-child-group-\(bgNode.id)-\(child.id)")
                    .transform(.translate(x, y))
            )

            x += drawn.drawn.width + Twist.bgGap
            bottom = max(bottom, y + drawn.drawn.height)

            addBgEdge(from: bg.center, to: drawn.center, id: "bg-edge-\(bgNode.id)-\(child.id)")
        }

        return DrawnBg(
            drawn: Drawn(node: Node(children: parts), width: overlap.length, height: bottom),
            center: bg.center
        )
    }

    private func addBgEdge(from start: PointRef, to end: PointRef, id: String) {
        finalizers.add { resolve in
            line(from: resolve(start), to: resolve(end))
                .id(id)
                .stroke(Twist.bgFill, lineWidth: Twist.bgEdgeWidth)
                .zIndex(.absolute(Twist.edgeZ))
                .hitTesting(.disabled)
        }
    }

    /// A grey circle, sized to hold the foreground nodes placed in it.
    private func drawBgNode(_ bgNode: TwistTree, fgNodes: [TwistTree]) -> (DrawnBg, below: [TwistTree]) {
        var inside: [Node<TwistState>] = []
        var below: [TwistTree] = []
        var x = Twist.bgPadding
        let y = Twist.bgPadding
        var maxX = x + Twist.emptyBgSize
        var maxY = y + Twist.emptyBgSize

        for fgNode in fgNodes {
            let (drawn, left) = drawFgSubtree(fgNode, in: bgNode.id)

            inside.append(
                Node(children: [drawn.node])
                    .id("fg-in-bg-\(bgNode.id)-\(fgNode.id)")
                    .transform(.translate(x, y))
            )

            x += drawn.width + Twist.fgGap
            maxX = max(maxX, x - Twist.fgGap)
            maxY = max(maxY, y + drawn.height)
            below += left
        }

        maxX += Twist.bgPadding
        maxY += Twist.bgPadding

        // The smallest circle around the contents' box.
        let boxCenter = Vec2(maxX / 2, maxY / 2)
        let radius = boxCenter.length
        let circleCenter = Vec2(radius, radius)
        let circleID = "bg-circle-\(bgNode.id)"
        let isHighlighted = context.state.highlightedNode == bgNode.id

        let node: Node<TwistState> = group {
            circle(radius: radius)
                .id(circleID)
                .fill(isHighlighted ? Twist.highlight : Twist.bgFill)
                .transform(.translate(circleCenter))
                .zIndex(.absolute(Twist.circleZ))

            Node<TwistState>(children: inside).transform(.translate(circleCenter - boxCenter))
        }

        let drawn = Drawn(node: node, width: 2 * radius, height: 2 * radius)

        return (DrawnBg(drawn: drawn, center: PointRef(circleID)), below)
    }

    // MARK: Foreground tree

    /// Draws a foreground node, with whichever descendants share its
    /// background node. The rest are left for the tree below.
    private func drawFgSubtree(_ fgNode: TwistTree, in bgID: String) -> (Drawn, below: [TwistTree]) {
        let childrenID = "fg-children-\(fgNode.id)"
        var parts: [Node<TwistState>] = []
        var below: [TwistTree] = []
        var childrenX = 0.0
        var childrenHeight = 0.0

        for (index, child) in fgNode.children.enumerated() {
            if index > 0 { childrenX += Twist.fgGap }

            let edgeID = "fg-edge-\(fgNode.id)-\(child.id)"
            let parentRef = PointRef(fgNode.id)
            let childRef = PointRef(child.id)

            guard morph[child.id] == bgID else {
                below.append(child)

                // Heads for the child's slot, then on down to where it went.
                let slot = PointRef(childrenID, Vec2(childrenX, 0))
                addFgEdge(id: edgeID) { resolve in
                    cardinalCurve(resolve(parentRef), resolve(slot), resolve(childRef))
                }

                continue
            }

            let (drawn, left) = drawFgSubtree(child, in: bgID)

            parts.append(
                Node(children: [drawn.node])
                    .id("fg-child-\(fgNode.id)-\(child.id)")
                    .transform(.translate(childrenX, 0))
            )

            below += left
            childrenX += drawn.width
            childrenHeight = max(childrenHeight, drawn.height)

            addFgEdge(id: edgeID, zIndex: .absolute(Twist.circleZ)) { resolve in
                let start = resolve(parentRef)
                return cardinalCurve(start, start, resolve(childRef))
            }
        }

        let isNarrow = childrenX < Twist.fgSize
        let nodeX = isNarrow ? Twist.fgSize / 2 : childrenX / 2
        let childrenInset = isNarrow ? (Twist.fgSize - childrenX) / 2 : 0
        let isDraggedHere = mode.usesDropTargets && context.draggedID == fgNode.id
        let renderer = self

        let node: Node<TwistState> = group {
            circle(radius: Twist.fgSize / 2)
                .id(fgNode.id)
                .fill(isDraggedHere ? Twist.draggedNode : .black)
                .transform(.translate(nodeX, Twist.fgSize / 2))
                .onDrag { renderer.dragSpec(for: fgNode.id) }

            Node<TwistState>(children: parts)
                .id(childrenID)
                .transform(.translate(childrenInset, Twist.fgSize + Twist.fgGap))
        }

        let height = Twist.fgSize + (childrenHeight > 0 ? Twist.fgGap + childrenHeight : 0)

        return (Drawn(node: node, width: max(childrenX, Twist.fgSize), height: height), below)
    }

    private func addFgEdge(
        id: String,
        zIndex: ZIndex = .relative(0),
        commands: @escaping (Finalizers<TwistState>.Resolve) -> [PathCommand]
    ) {
        finalizers.add { resolve in
            path(commands(resolve))
                .id(id)
                .stroke(.black, lineWidth: Twist.fgEdgeWidth)
                .zIndex(zIndex)
                .hitTesting(.disabled)
        }
    }

    // MARK: Traditional diagram

    /// The same map, drawn the textbook way: two trees and some arrows.
    func drawTraditional() -> [Node<TwistState>] {
        let domain = drawPlainTree(universe.tree, prefix: "domain", fill: .black, edgeWidth: Twist.fgEdgeWidth)
        let codomain = drawPlainTree(universe.tree, prefix: "codomain", fill: Twist.bgFill, edgeWidth: Twist.bgEdgeWidth)

        for (source, target) in morph.sorted(by: { $0.key < $1.key }) {
            addArrow(from: source, to: target)
        }

        return [
            Node(children: [domain.node]).transform(.translate(0, Twist.traditionalY)),
            Node(children: [codomain.node])
                .transform(.translate(domain.width + Twist.traditionalGap, Twist.traditionalY)),
        ]
    }

    private func addArrow(from source: String, to target: String) {
        let renderer = self
        let radius = Twist.fgSize / 2

        finalizers.add { resolve in
            let start = resolve(PointRef("domain-\(source)"))
            let end = resolve(PointRef("codomain-\(target)"))
            let bow = Vec2(0, -start.distance(to: end) / Twist.arrowBowDivisor)
            let middle = Vec2.lerp(start, end, 1.0 / 2) + bow
            let tail = start.towards(middle, by: radius)
            let tip = end.towards(middle, by: radius)
            let halfWidth = Twist.arrowHeadLength * tan(Twist.arrowHeadAngle / 2)

            return group {
                path([.move(tail), .quad(control: middle, end: tip.towards(middle, by: Twist.arrowHeadInset))])
                    .stroke(Twist.arrow, lineWidth: Twist.fgEdgeWidth)
                    .hitTesting(.disabled)

                path([
                    .move(.zero),
                    .line(Vec2(-Twist.arrowHeadLength, halfWidth)),
                    .line(Vec2(-Twist.arrowHeadLength, -halfWidth)),
                    .close,
                ])
                .fill(Twist.arrow)
                .transform(.translate(tip) + .rotate(degrees: (end - middle).angle * 180 / .pi))
                .onDrag { renderer.dragSpec(for: source) }
            }
            .id("morphism-arrow-\(source)")
        }
    }

    private func drawPlainTree(_ node: TwistTree, prefix: String, fill: RGBA, edgeWidth: Double) -> Drawn {
        var parts: [Node<TwistState>] = []
        var childrenX = 0.0
        var childrenHeight = 0.0

        for (index, child) in node.children.enumerated() {
            if index > 0 { childrenX += Twist.fgGap }

            let drawn = drawPlainTree(child, prefix: prefix, fill: fill, edgeWidth: edgeWidth)

            parts.append(
                Node(children: [drawn.node])
                    .id("\(prefix)-child-\(node.id)-\(child.id)")
                    .transform(.translate(childrenX, 0))
            )

            childrenX += drawn.width
            childrenHeight = max(childrenHeight, drawn.height)

            let start = PointRef("\(prefix)-\(node.id)")
            let end = PointRef("\(prefix)-\(child.id)")

            finalizers.add { resolve in
                line(from: resolve(start), to: resolve(end))
                    .id("\(prefix)-edge-\(node.id)-\(child.id)")
                    .stroke(fill, lineWidth: edgeWidth)
                    .hitTesting(.disabled)
            }
        }

        let nodeX = childrenX < Twist.fgSize ? Twist.fgSize / 2 : childrenX / 2

        let drawn: Node<TwistState> = group {
            circle(radius: Twist.fgSize / 2)
                .id("\(prefix)-\(node.id)")
                .fill(fill)
                .transform(.translate(nodeX, Twist.fgSize / 2))

            Node<TwistState>(children: parts).transform(.translate(0, Twist.fgSize + Twist.fgGap))
        }

        let height = Twist.fgSize + (childrenHeight > 0 ? Twist.fgGap + childrenHeight : 0)

        return Drawn(node: drawn, width: max(childrenX, Twist.fgSize), height: height)
    }
}
