import Foundation
import os

/// How `between` shares weight among targets.
public enum BetweenInterpolation: Sendable {
    /// Blends the three corners of the pointer's triangle.
    case delaunay
    /// Smoother across triangle edges, at the cost of blending more scenes.
    case naturalNeighbor
}

public struct BetweenOptions: Sendable {
    public var interpolation: BetweenInterpolation
    /// 1 blends evenly. Higher values pull the element towards its
    /// nearest target, approaching `closest` as this grows.
    public var sharpness: Double?

    public init(interpolation: BetweenInterpolation = .delaunay, sharpness: Double? = nil) {
        self.interpolation = interpolation
        self.sharpness = sharpness
    }
}

/// Blends the rendered targets by where the pointer sits among them.
final class BetweenOperator<State: Equatable>: Operator<State> {
    private struct Target {
        var state: State
        var scene: LayeredScene<State>
        var position: Vec2
    }

    private static var logger: Logger {
        Logger(subsystem: "dragology-swift", category: "between")
    }

    private let options: BetweenOptions
    /// Non-fixed targets, which have to run on every frame.
    private let branches: [Operator<State>]
    private var targets: [Target] = []
    private var triangulation: Triangulation?

    init(context: DragContext<State>, specs: [DragSpec<State>], options: BetweenOptions) {
        self.options = options

        // Fixed targets never change, so they're measured just once.
        let fixedStates = specs.compactMap(\.fixedState)
        let isAllFixed = fixedStates.count == specs.count

        branches = isAllFixed ? [] : specs.map { $0.makeOperator(context) }

        super.init(context: context, name: "between")

        guard isAllFixed else { return }

        setTargets(fixedStates.compactMap { state in
            let scene = context.render(state)

            guard let position = context.position(in: scene) else { return nil }

            return Target(state: state, scene: scene, position: position)
        })
    }

    private func setTargets(_ newTargets: [Target]) {
        targets = newTargets

        let triangulation = Triangulation(points: newTargets.map(\.position))
        self.triangulation = triangulation

        // Two targets in one place can't be told apart by dragging.
        if !triangulation.coincidentIndices.isEmpty {
            Self.logger.warning(
                "between: targets \(triangulation.coincidentIndices) repeat an earlier position, so they can't be reached. Are you reordering siblings without ids?"
            )
        }
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        if !branches.isEmpty {
            setTargets(branches.compactMap { branch in
                let result = branch.run(frame)
                let scene = result.preview.value

                guard let position = context.position(in: scene) else { return nil }

                return Target(state: result.dropState, scene: scene, position: position)
            })
        }

        guard let triangulation, let nearest = nearestTarget(to: frame.pointer) else {
            preconditionFailure("between: the dragged element is missing from every target.")
        }

        let projection = triangulation.project(frame.pointer)
        let blend = blendWeights(triangulation, frame.pointer, projection)
        let weights = sharpened(blend)
        let scenes = targets.map(\.scene)

        // The grabbed point goes to the same blend of its positions.
        let grabPosition = weights.reduce(Vec2.zero) { sum, entry in
            sum + targets[entry.key].position * entry.value
        }

        return DragResult(
            preview: Lazy { LayeredScene.lerp(scenes, weights: weights) },
            dropState: nearest.state,
            gap: projection.distance,
            grabPosition: grabPosition
        )
    }

    private func blendWeights(
        _ triangulation: Triangulation,
        _ pointer: Vec2,
        _ projection: Triangulation.Projection
    ) -> [Int: Double] {
        switch options.interpolation {
        case .delaunay:
            return projection.weights
        case .naturalNeighbor:
            return triangulation.naturalNeighbors(pointer).weights
        }
    }

    private func nearestTarget(to pointer: Vec2) -> Target? {
        targets.min {
            $0.position.distanceSquared(to: pointer) < $1.position.distanceSquared(to: pointer)
        }
    }

    private func sharpened(_ weights: [Int: Double]) -> [Int: Double] {
        guard let sharpness = options.sharpness else { return weights }

        let raised = weights.mapValues { pow($0, sharpness) }
        let total = raised.values.reduce(0, +)

        return raised.mapValues { $0 / total }
    }
}
