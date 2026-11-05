import Foundation

/// Starts out in a new state, dragging a different element.
final class FollowOperator<State: Equatable>: Operator<State> {
    private let inner: Operator<State>

    init(context: DragContext<State>, state: State, draggedID: String, followSpec: DragSpec<State>?) {
        var followContext = context
        followContext.startState = state
        followContext.draggedID = draggedID
        followContext.draggedPath = draggedID + "/"

        guard let spec = followSpec ?? followContext.element(id: draggedID, in: state)?.onDrag?() else {
            preconditionFailure("switchToStateAndFollow: no spec to follow on \"\(draggedID)\".")
        }

        inner = spec.makeOperator(followContext)

        super.init(context: context, name: "switchToStateAndFollow")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        inner.run(frame)
    }
}
