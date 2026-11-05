import Foundation

/// Everything a render function gets.
public struct RenderContext<State: Equatable> {
    public let state: State
    /// Builds drag specs.
    public let d = DragSpecBuilder<State>()
    /// The id of the element being dragged, if there is one.
    public let draggedID: String?
    /// True when only the dragged element's position matters, so a
    /// render function can skip expensive decoration.
    public let isTracking: Bool
    let applyState: (State, Transition?) -> Void

    /// Changes state outside of a drag, such as on a tap.
    public func setState(_ state: State, transition: Transition? = .standard) {
        applyState(state, transition)
    }

    /// Draws a sub-draggable for one part of the state. Its drags and
    /// state changes are lifted back up to this level automatically.
    public func embed<Sub: Equatable>(
        _ draggable: Draggable<Sub>,
        at path: WritableKeyPath<State, Sub>
    ) -> Node<State> {
        let parent = state
        let parentApply = applyState
        let builder = d

        let subContext = RenderContext<Sub>(
            state: parent[keyPath: path],
            draggedID: draggedID,
            isTracking: isTracking,
            applyState: { subState, transition in
                var next = parent
                next[keyPath: path] = subState
                parentApply(next, transition)
            }
        )

        return draggable(subContext).retyped { onDrag in
            { builder.substate(parent, path) { _ in onDrag() } }
        }
    }
}

/// A pure function from state to scene. It runs on many hypothetical
/// states during a drag, so it must not have side effects.
public typealias Draggable<State: Equatable> = (RenderContext<State>) -> Node<State>

/// Computes a value on first use, then keeps it. Previews are often
/// never shown, and rendering one is the expensive part of a frame.
public final class Lazy<Value> {
    private var compute: (() -> Value)?
    private var cached: Value?

    public init(_ compute: @escaping () -> Value) {
        self.compute = compute
    }

    public var value: Value {
        if let cached { return cached }

        guard let compute else {
            preconditionFailure("Lazy value lost both its result and its computation.")
        }

        let computed = compute()
        cached = computed
        self.compute = nil

        return computed
    }
}

/// A request to commit to the drop state right now, and carry on
/// dragging from there.
public struct Chaining<State: Equatable> {
    /// The element to continue with. Defaults to the current one.
    public var draggedID: String?
    /// The spec to continue with. Defaults to the element's own.
    public var followSpec: DragSpec<State>?
    /// Nil means no animation.
    public var transition: Transition?

    public init(
        draggedID: String? = nil,
        followSpec: DragSpec<State>? = nil,
        transition: Transition? = .standard
    ) {
        self.draggedID = draggedID
        self.followSpec = followSpec
        self.transition = transition
    }
}

/// The input to a drag behavior on each frame.
public struct DragFrame: Sendable {
    public var pointer: Vec2

    public init(pointer: Vec2) {
        self.pointer = pointer
    }
}

/// What a drag behavior produces on each frame.
public struct DragResult<State: Equatable> {
    /// What to display.
    public var preview: Lazy<LayeredScene<State>>
    /// What the state becomes if the drag ends now.
    public var dropState: State
    /// How far the dragged element is from the pointer. `closest` and
    /// `whenFar` compare these.
    public var gap: Double
    /// Where this behavior puts the grabbed point, if known without
    /// rendering the preview.
    public var grabPosition: Vec2?
    /// Which branch of the spec is driving. A change triggers a transition.
    public var activePath = ""
    /// Nil means no animation.
    public var dropTransition: Transition? = .standard
    public var branchTransition: Transition? = .standard
    /// Set to chain into a new drag from `dropState`.
    public var chain: Chaining<State>?

    public init(
        preview: Lazy<LayeredScene<State>>,
        dropState: State,
        gap: Double,
        grabPosition: Vec2? = nil
    ) {
        self.preview = preview
        self.dropState = dropState
        self.gap = gap
        self.grabPosition = grabPosition
    }

    /// Records that this result came through the branch called `segment`.
    func prefixingPath(_ segment: String) -> DragResult {
        var copy = self
        copy.activePath = segment + "/" + activePath
        return copy
    }
}

/// What's fixed for the length of a drag.
public struct DragContext<State: Equatable> {
    public var draggable: Draggable<State>
    public var draggedPath: String
    public var draggedID: String?
    /// The grabbed point, in the dragged element's local coordinates.
    public var anchor: Vec2
    public var startState: State

    /// Finds an element in a state, by id or else by the dragged path.
    func element(id: String?, in state: State) -> Node<State>? {
        let tree = renderTree(state, isTracking: true).assigningPaths()

        if let id {
            return tree.find { $0.id == id }?.node
        }

        return tree.find { $0.path == draggedPath }?.node
    }

    private func renderTree(_ state: State, isTracking: Bool) -> Node<State> {
        let context = RenderContext(
            state: state,
            draggedID: draggedID,
            isTracking: isTracking,
            applyState: { _, _ in
                assertionFailure("setState can't be called while rendering speculatively.")
            }
        )

        return draggable(context)
    }

    /// Renders a state, to show as a preview.
    public func render(_ state: State) -> LayeredScene<State> {
        LayeredScene(root: renderTree(state, isTracking: false).assigningPaths())
    }

    /// Where a state puts the grabbed point, in canvas coordinates. Nil
    /// if the element is missing. Cheaper than a full `render`.
    public func position(in state: State) -> Vec2? {
        let tree = renderTree(state, isTracking: true)

        if let draggedID {
            let found = tree.find { $0.id == draggedID }
            return found?.transform.localToGlobal(anchor)
        }

        // Without an id, the element can only be found by path.
        let found = tree.assigningPaths().find { $0.path == draggedPath }
        return found?.transform.localToGlobal(anchor)
    }

    /// Where a rendered scene puts the grabbed point.
    public func position(in scene: LayeredScene<State>) -> Vec2? {
        scene.find(path: draggedPath)?.transform.localToGlobal(anchor)
    }
}

/// A running drag behavior, built fresh from a spec for each drag.
/// Subclass this for behaviors that the built-in operators can't compose.
open class Operator<State: Equatable> {
    public let context: DragContext<State>
    /// Names this operator in active paths.
    public let name: String

    public init(context: DragContext<State>, name: String) {
        self.context = context
        self.name = name
    }

    /// Computes one frame. May keep memory between frames in fields.
    open func frame(_ frame: DragFrame) -> DragResult<State> {
        preconditionFailure("Subclasses of Operator must override frame(_:).")
    }

    /// Runs a frame, recording this operator on the active path.
    public final func run(_ frame: DragFrame) -> DragResult<State> {
        self.frame(frame).prefixingPath(name)
    }
}
