import Foundation

/// Where children line up across a row or column.
public enum SceneAlignment: Sendable {
    case start
    case center
    case end
}

private enum StackAxis {
    case horizontal
    case vertical
}

/// Stacks children from top to bottom, using the space each one occupies.
public func SceneColumn<State>(
    spacing: Double = 0,
    alignment: SceneAlignment = .start,
    @SceneNodeBuilder<State> _ content: () -> [SceneNode<State>]
) -> SceneNode<State> {
    stacked(content(), axis: .vertical, spacing: spacing, alignment: alignment)
}

/// Stacks children from left to right, using the space each one occupies.
public func SceneRow<State>(
    spacing: Double = 0,
    alignment: SceneAlignment = .start,
    @SceneNodeBuilder<State> _ content: () -> [SceneNode<State>]
) -> SceneNode<State> {
    stacked(content(), axis: .horizontal, spacing: spacing, alignment: alignment)
}

/// Each child goes in a positioned group of its own, which leaves its id
/// and its own transform alone, so it still matches across renders.
private func stacked<State>(
    _ children: [SceneNode<State>],
    axis: StackAxis,
    spacing: Double,
    alignment: SceneAlignment
) -> SceneNode<State> {
    let bounds = children.map { $0.bounds() }

    let crossExtent = bounds.compactMap { $0 }.map { box -> Double in
        let size = box.max - box.min
        return axis == .vertical ? size.x : size.y
    }.max() ?? 0

    var cursor = 0.0
    var placed: [SceneNode<State>] = []

    for (child, box) in zip(children, bounds) {
        guard let box else {
            placed.append(child)
            continue
        }

        let size = box.max - box.min
        let along = axis == .vertical ? size.y : size.x
        let across = axis == .vertical ? size.x : size.y
        let slack = crossExtent - across

        let crossOffset: Double

        switch alignment {
        case .start: crossOffset = 0
        case .center: crossOffset = slack / 2
        case .end: crossOffset = slack
        }

        // Shift by the box's corner, as a circle's box starts above the origin.
        let target = axis == .vertical ? Vec2(crossOffset, cursor) : Vec2(cursor, crossOffset)

        placed.append(SceneNode(children: [child]).transform(.translate(target - box.min)))
        cursor += along + spacing
    }

    return SceneNode(children: placed)
}
