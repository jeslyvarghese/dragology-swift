import Foundation

/// Runs a spec written for one part of the state. The spec sees a
/// render function over that part alone, with the rest held fixed.
final class SubstateOperator<State: Equatable, Sub: Equatable>: Operator<State> {
    private let state: State
    private let path: WritableKeyPath<State, Sub>
    private let inner: Operator<Sub>

    init(
        context: DragContext<State>,
        state: State,
        path: WritableKeyPath<State, Sub>,
        spec: DragSpec<Sub>
    ) {
        self.state = state
        self.path = path

        let draggable = context.draggable

        // Render the whole scene, for a hypothetical value of this part.
        let lensed: Draggable<Sub> = { subContext in
            var whole = state
            whole[keyPath: path] = subContext.state

            let wholeContext = RenderContext(
                state: whole,
                draggedID: subContext.draggedID,
                isTracking: subContext.isTracking,
                applyState: { _, _ in }
            )

            return draggable(wholeContext).retyped()
        }

        let subContext = DragContext<Sub>(
            draggable: lensed,
            draggedPath: context.draggedPath,
            draggedID: context.draggedID,
            anchor: context.anchor,
            startState: state[keyPath: path]
        )

        inner = spec.makeOperator(subContext)

        super.init(context: context, name: "substate")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        let result = inner.run(frame)

        var whole = state
        whole[keyPath: path] = result.dropState

        var lifted = DragResult<State>(
            preview: Lazy { result.preview.value.retyped() },
            dropState: whole,
            gap: result.gap,
            grabPosition: result.grabPosition
        )
        lifted.activePath = result.activePath
        lifted.dropTransition = result.dropTransition
        lifted.branchTransition = result.branchTransition

        return lifted
    }
}
