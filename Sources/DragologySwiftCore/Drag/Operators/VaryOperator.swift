import Foundation

/// Continuously solves for the parameters that bring the dragged
/// element to the pointer.
final class VaryOperator<State: Equatable>: Operator<State> {
    private var minimizer: DistanceMinimizer
    private let stateFromParameters: ([Double]) -> State
    private let constraintValues: (([Double]) -> [Double])?

    init(
        context: DragContext<State>,
        initial: [Double],
        stateFromParameters: @escaping ([Double]) -> State,
        constraint: ((State) -> [Double])?,
        pin: ((State) -> [Double])?
    ) {
        minimizer = DistanceMinimizer(parameters: initial)
        self.stateFromParameters = stateFromParameters

        // A pin holds its values at what they are in the initial state.
        let pinTargets = pin?(stateFromParameters(initial)) ?? []

        let combined = { (state: State) -> [Double] in
            let pinned = zip(pin?(state) ?? [], pinTargets).flatMap { Constraint.equal($0, $1) }
            return (constraint?(state) ?? []) + pinned
        }

        let isConstrained = constraint != nil || pin != nil
        constraintValues = isConstrained ? { combined(stateFromParameters($0)) } : nil

        super.init(context: context, name: "vary")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        let context = self.context
        let stateFromParameters = self.stateFromParameters

        minimizer.minimize(
            target: frame.pointer,
            position: { context.position(in: stateFromParameters($0)) },
            constraints: constraintValues
        )

        let state = stateFromParameters(minimizer.parameters)
        let scene = context.render(state)

        guard let position = context.position(in: scene) else {
            preconditionFailure("vary: the dragged element is missing from a varied state.")
        }

        return DragResult(
            preview: Lazy { scene },
            dropState: state,
            gap: position.distance(to: frame.pointer),
            grabPosition: position
        )
    }
}
