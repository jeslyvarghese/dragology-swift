import Foundation

/// Shows a state while the pointer is over a target element. The gap is
/// all or nothing: zero inside the target, infinite outside it.
final class DropTargetOperator<State: Equatable>: Operator<State> {
    private let state: State
    private let scene: LayeredScene<State>
    private let bounds: Bounds

    init(context: DragContext<State>, targetID: String, state: State, boundsState: State?) {
        self.state = state
        scene = context.render(state)

        let boundsScene = boundsState.map(context.render) ?? scene

        guard let bounds = boundsScene.layers[targetID]?.node.bounds() else {
            preconditionFailure("dropTarget: no element with bounds has the id \"\(targetID)\".")
        }

        self.bounds = bounds

        super.init(context: context, name: "dropTarget")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        let scene = self.scene

        return DragResult(
            preview: Lazy { scene },
            dropState: state,
            gap: bounds.contains(frame.pointer) ? 0 : .infinity
        )
    }
}
