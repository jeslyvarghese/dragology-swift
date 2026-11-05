import Foundation

private enum SnapSegment {
    static let snapped = "snapped"
    static let unsnapped = "unsnapped"
}

/// What happens on reaching the drop state.
public enum SnapChaining: Sendable {
    case none
    /// Commits to the state and continues the drag from there.
    case chainOnSnap
}

/// Shows the drop state outright once the element gets close to it.
final class SnapRadiusOperator<State: Equatable>: Operator<State> {
    /// A drop state's measurements. Drop states repeat from frame to
    /// frame, so the latest one is worth keeping.
    private struct Target {
        var state: State
        var position: Vec2?
        var preview: Lazy<LayeredScene<State>>
    }

    private let inner: Operator<State>
    private let radius: Double
    private let transition: Transition?
    private let chaining: SnapChaining
    private var target: Target?

    init(
        context: DragContext<State>,
        inner: DragSpec<State>,
        radius: Double,
        transition: Transition?,
        chaining: SnapChaining
    ) {
        self.inner = inner.makeOperator(context)
        self.radius = radius
        self.transition = transition
        self.chaining = chaining

        super.init(context: context, name: "withSnapRadius")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        var result = inner.run(frame)
        let target = target(for: result.dropState)

        let grabPosition = result.grabPosition ?? context.position(in: result.preview.value)

        guard let grabPosition, let position = target.position else { return result }

        let isSnapped = position.distance(to: grabPosition) <= radius

        if isSnapped {
            result.preview = target.preview
            result.grabPosition = position
        } else {
            result.grabPosition = grabPosition
        }

        if isSnapped, case .chainOnSnap = chaining {
            result.chain = Chaining(transition: transition)
        }

        // Only a transition makes snapping count as a branch switch.
        guard let transition else { return result }

        result.branchTransition = transition

        return result.prefixingPath(isSnapped ? SnapSegment.snapped : SnapSegment.unsnapped)
    }

    private func target(for state: State) -> Target {
        if let target, target.state == state { return target }

        let context = self.context
        let fresh = Target(
            state: state,
            position: context.position(in: state),
            preview: Lazy { context.render(state) }
        )
        target = fresh

        return fresh
    }
}
