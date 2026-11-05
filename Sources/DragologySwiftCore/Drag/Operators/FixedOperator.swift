import Foundation

/// Shows one state, with the dragged element wherever that state puts it.
final class FixedOperator<State: Equatable>: DragOperator<State> {
    private let state: State
    private let position: Vec2?
    private let preview: LazyPreview<LayeredScene<State>>

    init(context: DragContext<State>, state: State) {
        self.state = state
        position = context.position(in: state)
        preview = LazyPreview { context.render(state) }

        super.init(context: context, name: "fixed")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        DragResult(
            preview: preview,
            dropState: state,
            gap: position?.distance(to: frame.pointer) ?? .infinity,
            grabPosition: position
        )
    }
}
