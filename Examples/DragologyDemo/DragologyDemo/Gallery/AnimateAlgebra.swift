import DragologySwift
import Foundation

struct AlgebraState: Equatable {
    var tree = AlgebraTree(id: "root", label: "+", children: [
        AlgebraTree(id: "root-1", label: "+", children: [
            AlgebraTree(id: "root-1-1", label: "+", children: [
                AlgebraTree(id: "root-1-1-1", label: "⛅"),
                AlgebraTree(id: "root-1-1-2", label: "-", children: [
                    AlgebraTree(id: "root-1-1-2-1", label: "🍄"),
                ]),
            ]),
            AlgebraTree(id: "root-1-2", label: "🍄"),
        ]),
        AlgebraTree(id: "root-2", label: "+", children: [
            AlgebraTree(id: "root-2-1", label: "×", children: [
                AlgebraTree(id: "root-2-1-1", label: "🎲"),
                AlgebraTree(id: "root-2-1-2", label: "🦠"),
            ]),
            AlgebraTree(id: "root-2-2", label: "×", children: [
                AlgebraTree(id: "root-2-2-1", label: "🎲"),
                AlgebraTree(id: "root-2-2-2", label: "🐝"),
            ]),
        ]),
    ])

    var summary: String { tree.text }
}

/// Which rules are on. The web demo has a checkbox for each.
enum AlgebraMode: Int, CaseIterable {
    case basics, associativity, distributivity, everything

    var title: String {
        switch self {
        case .basics: "identity, commutativity"
        case .associativity: "+ associativity"
        case .distributivity: "+ distributivity"
        case .everything: "everything"
        }
    }

    fileprivate var rules: [AlgebraRewrite] {
        let basics = AlgebraRules.identity + AlgebraRules.commutativity

        switch self {
        case .basics:
            return basics
        case .associativity:
            return basics + AlgebraRules.associativity
        case .distributivity:
            return basics + AlgebraRules.distribute + AlgebraRules.factor
        case .everything:
            return basics + AlgebraRules.associativity + AlgebraRules.distribute + AlgebraRules.factor
        }
    }
}

private enum Metrics {
    static let gap = 10.0
    static let padding = 5.0
    static let labelWidth = 20.0
    static let labelMinHeight = 20.0
    static let fontSize = 18.0
    static let maxCornerRadius = 14.0
    static let cornerShare = 0.3
    static let strokeWidth = 0.75
    static let draggedZ = 1000
    static let margin = 4.0
    static let lockPast = 20.0
    static let snapRadius = 1.0

    /// A subtle warm fill that deepens with nesting.
    static let baseFillAlpha = 0.02
    static let fillAlphaStep = 0.03
    static let maxFillAlpha = 0.15
    static let baseStrokeAlpha = 0.25
    static let strokeAlphaStep = 0.08
    static let maxStrokeAlpha = 0.5
    static let fill = SceneColor(hex: 0xB4AA96)
    static let stroke = SceneColor(hex: 0x8C8273)
    static let ink = SceneColor(hex: 0x3A3A38)
}

func animateAlgebra(mode: AlgebraMode) -> DragScene<AlgebraState> {
    let rules = mode.rules

    return { context in
        let renderer = AlgebraRenderer(context: context, rules: rules)

        return renderer.draw(context.state.tree, depth: 0, isInDragged: false).node
            .transform(.translate(Metrics.margin, Metrics.margin))
    }
}

/// Nested boxes: an operator's label, with its operands stacked beside it.
private struct AlgebraRenderer {
    struct Drawn {
        var node: SceneNode<AlgebraState>
        var width: Double
        var height: Double
    }

    let context: SceneContext<AlgebraState>
    let rules: [AlgebraRewrite]

    private func dragSpec(for id: String) -> DragSpec<AlgebraState> {
        let d = context.drag
        let state = context.state
        let rewritten = AlgebraEngine.allRewrites(of: state.tree, rules: rules, trigger: id)

        guard !rewritten.isEmpty else { return d.between([state]) }

        let options = rewritten.map { d.between([state, AlgebraState(tree: $0)]) }

        return d.closest(options, options: ClosestOptions(lockPast: Metrics.lockPast))
            .withSnapRadius(Metrics.snapRadius, chaining: .chainOnSnap)
    }

    func draw(_ tree: AlgebraTree, depth: Int, isInDragged: Bool) -> Drawn {
        let isDragged = isInDragged || tree.id == context.draggedID
        let children = tree.children.map { draw($0, depth: depth + 1, isInDragged: isDragged) }

        var y = 0.0
        var stacked: [SceneNode<AlgebraState>] = []

        for child in children {
            stacked.append(SceneNode(children: [child.node]).transform(.translate(0, y)))
            y += child.height + Metrics.gap
        }

        let widest = children.map(\.width).max()
        let innerWidth = Metrics.labelWidth + (widest.map { Metrics.gap + $0 } ?? 0)
        let innerHeight = children.isEmpty ? Metrics.labelMinHeight : y - Metrics.gap
        let width = innerWidth + Metrics.padding * 2
        let height = innerHeight + Metrics.padding * 2
        let corner = min(Metrics.maxCornerRadius, Metrics.cornerShare * min(width, height))
        let level = Double(depth)
        let fillAlpha = min(Metrics.baseFillAlpha + level * Metrics.fillAlphaStep, Metrics.maxFillAlpha)
        let strokeAlpha = min(Metrics.baseStrokeAlpha + level * Metrics.strokeAlphaStep, Metrics.maxStrokeAlpha)
        let renderer = self
        let id = tree.id

        let node: SceneNode<AlgebraState> = SceneGroup {
            SceneRect(width: width, height: height, cornerRadius: corner)
                .fill(Metrics.fill.withOpacity(fillAlpha))
                .stroke(Metrics.stroke.withOpacity(strokeAlpha), lineWidth: Metrics.strokeWidth)

            SceneText(tree.label, size: Metrics.fontSize)
                .fill(Metrics.ink)
                .transform(.translate(
                    Metrics.padding + Metrics.labelWidth / 2,
                    Metrics.padding + innerHeight / 2
                ))
                .hitTesting(.disabled)

            if !stacked.isEmpty {
                SceneNode<AlgebraState>(children: stacked).transform(.translate(
                    Metrics.padding + Metrics.labelWidth + Metrics.gap,
                    Metrics.padding
                ))
            }
        }
        .id(id)
        .zIndex(.relative(depth + (isDragged ? Metrics.draggedZ : 0)))
        .emergeFrom(tree.emergeOrigin, mode: tree.emergeMode)
        .onDrag { renderer.dragSpec(for: id) }

        return Drawn(node: node, width: width, height: height)
    }
}
