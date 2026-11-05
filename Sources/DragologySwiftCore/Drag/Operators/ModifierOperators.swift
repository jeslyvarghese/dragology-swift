import Foundation

/// Adjusts the wrapped spec's result on each frame.
final class ResultModifierOperator<State: Equatable>: Operator<State> {
    private let inner: Operator<State>
    private let change: (inout DragResult<State>, DragFrame) -> Void

    init(
        context: DragContext<State>,
        name: String,
        inner: DragSpec<State>,
        change: @escaping (inout DragResult<State>, DragFrame) -> Void
    ) {
        self.inner = inner.makeOperator(context)
        self.change = change

        super.init(context: context, name: name)
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        var result = inner.run(frame)
        change(&result, frame)
        return result
    }
}

/// Transforms the wrapped spec's drop state, then re-renders it.
final class DuringOperator<State: Equatable>: Operator<State> {
    private let inner: Operator<State>
    private let transform: (State) -> State

    init(context: DragContext<State>, inner: DragSpec<State>, transform: @escaping (State) -> State) {
        self.inner = inner.makeOperator(context)
        self.transform = transform

        super.init(context: context, name: "during")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        var result = inner.run(frame)
        let state = transform(result.dropState)
        let scene = context.render(state)
        let position = context.position(in: scene)

        result.preview = Lazy { scene }
        result.dropState = state
        result.gap = position?.distance(to: frame.pointer) ?? .infinity
        result.grabPosition = position

        return result
    }
}

/// Draws fixed content above the wrapped spec's preview.
final class OverlayOperator<State: Equatable>: Operator<State> {
    private let inner: Operator<State>
    private let overlay: LayeredScene<State>

    init(context: DragContext<State>, inner: DragSpec<State>, overlay: Node<State>) {
        self.inner = inner.makeOperator(context)

        // Overlays sit above even floating elements. Each gets a prefix
        // of its own, so its ids can't collide with anything else's.
        let topStackingStep = 2_000_000
        let prefix = "overlay-\(UUID().uuidString)-"

        self.overlay = LayeredScene(root: Node(children: [overlay]))
            .prefixingIDs(prefix)
            .mapLayers { $0.stackingPath.insert(topStackingStep, at: 0) }

        super.init(context: context, name: "withOverlay")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        var result = inner.run(frame)
        let preview = result.preview
        let overlay = self.overlay

        result.preview = Lazy { preview.value.merging(overlay) }

        return result
    }
}

/// Remaps the frame before the wrapped spec sees it.
final class ChangeFrameOperator<State: Equatable>: Operator<State> {
    private let inner: Operator<State>
    private let transform: (DragFrame) -> DragFrame

    init(context: DragContext<State>, inner: DragSpec<State>, transform: @escaping (DragFrame) -> DragFrame) {
        self.inner = inner.makeOperator(context)
        self.transform = transform

        super.init(context: context, name: "changeFrame")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        inner.run(transform(frame))
    }
}

/// A behavior written by hand, as a function of the frame.
final class CustomOperator<State: Equatable>: Operator<State> {
    private let behavior: (DragFrame) -> DragResult<State>

    init(context: DragContext<State>, behavior: @escaping (DragFrame) -> DragResult<State>) {
        self.behavior = behavior

        super.init(context: context, name: "custom")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        behavior(frame)
    }
}
