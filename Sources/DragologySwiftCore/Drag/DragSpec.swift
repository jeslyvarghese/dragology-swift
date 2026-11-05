import Foundation

/// A declarative description of a drag. It's inert until a drag starts,
/// when it's turned into a running `DragOperator`.
public struct DragSpec<State: Equatable> {
    let makeOperator: (DragContext<State>) -> DragOperator<State>
    /// Set when this spec only shows a state, which `between` can
    /// render once instead of on every frame.
    let fixedState: State?

    /// Makes a spec from a custom operator.
    public init(_ makeOperator: @escaping (DragContext<State>) -> DragOperator<State>) {
        self.makeOperator = makeOperator
        fixedState = nil
    }

    init(fixed state: State) {
        makeOperator = { FixedOperator(context: $0, state: state) }
        fixedState = state
    }
}

/// The vocabulary of drag primitives and combinators.
public struct DragSpecBuilder<State: Equatable>: Sendable {
    public init() {}

    /// Shows a single state.
    public func fixed(_ state: State) -> DragSpec<State> {
        DragSpec(fixed: state)
    }

    /// Follows whichever option gets the element closest to the pointer.
    public func closest(_ states: [State], options: ClosestOptions = ClosestOptions()) -> DragSpec<State> {
        closest(states.map(fixed), options: options)
    }

    public func closest(_ specs: [DragSpec<State>], options: ClosestOptions = ClosestOptions()) -> DragSpec<State> {
        DragSpec { ClosestOperator(context: $0, specs: specs, options: options) }
    }

    /// Blends between targets, inside their convex hull.
    public func between(_ states: [State], options: BetweenOptions = BetweenOptions()) -> DragSpec<State> {
        between(states.map(fixed), options: options)
    }

    public func between(_ specs: [DragSpec<State>], options: BetweenOptions = BetweenOptions()) -> DragSpec<State> {
        precondition(!specs.isEmpty, "between requires at least one target.")

        return DragSpec { BetweenOperator(context: $0, specs: specs, options: options) }
    }

    /// Continuously varies numbers in `state`, to bring the dragged
    /// element to the pointer. `state` is the optimizer's starting point.
    public func vary(
        _ state: State,
        _ paths: WritableKeyPath<State, Double>...,
        constraint: ((State) -> [Double])? = nil,
        pin: ((State) -> [Double])? = nil
    ) -> DragSpec<State> {
        vary(state, paths: paths, constraint: constraint, pin: pin)
    }

    /// `vary`, for when the paths are chosen at runtime.
    public func vary(
        _ state: State,
        paths: [WritableKeyPath<State, Double>],
        constraint: ((State) -> [Double])? = nil,
        pin: ((State) -> [Double])? = nil
    ) -> DragSpec<State> {
        let stateFromParameters = { (parameters: [Double]) -> State in
            var copy = state

            for (path, value) in zip(paths, parameters) {
                copy[keyPath: path] = value
            }

            return copy
        }

        return varyFunction(
            initial: paths.map { state[keyPath: $0] },
            state: stateFromParameters,
            constraint: constraint,
            pin: pin
        )
    }

    /// Shows `state` whenever the pointer is over the element `targetID`.
    /// The target's box comes from `boundsState`, or else from `state`,
    /// for targets that move or vanish when dropped on.
    public func dropTarget(_ targetID: String, _ state: State, boundsState: State? = nil) -> DragSpec<State> {
        DragSpec {
            DropTargetOperator(context: $0, targetID: targetID, state: state, boundsState: boundsState)
        }
    }

    /// Jumps to `state` as the drag starts, and carries on dragging the
    /// element `id` there. Uses `followSpec`, or else that element's own.
    public func switchToStateAndFollow(
        _ state: State,
        _ id: String,
        followSpec: DragSpec<State>? = nil
    ) -> DragSpec<State> {
        DragSpec {
            FollowOperator(context: $0, state: state, draggedID: id, followSpec: followSpec)
        }
    }

    /// Rebuilds a spec whenever `value` changes during the drag.
    public func reactTo<Value: Equatable>(
        _ value: @escaping () -> Value,
        _ makeSpec: @escaping (Value) -> DragSpec<State>
    ) -> DragSpec<State> {
        DragSpec { ReactToOperator(context: $0, value: value, makeSpec: makeSpec) }
    }

    /// Writes a spec for just one part of the state.
    public func substate<Sub: Equatable>(
        _ state: State,
        _ path: WritableKeyPath<State, Sub>,
        _ makeSpec: (DragSpecBuilder<Sub>) -> DragSpec<Sub>
    ) -> DragSpec<State> {
        let spec = makeSpec(DragSpecBuilder<Sub>())

        return DragSpec { SubstateOperator(context: $0, state: state, path: path, spec: spec) }
    }

    /// Defines a behavior from scratch: given the context, returns the
    /// function that runs on each frame.
    public func custom(
        _ makeBehavior: @escaping (DragContext<State>) -> (DragFrame) -> DragResult<State>
    ) -> DragSpec<State> {
        DragSpec { CustomOperator(context: $0, behavior: makeBehavior($0)) }
    }

    /// Like `vary`, for parameters that change state in concert.
    public func varyFunction(
        initial: [Double],
        state: @escaping ([Double]) -> State,
        constraint: ((State) -> [Double])? = nil,
        pin: ((State) -> [Double])? = nil
    ) -> DragSpec<State> {
        DragSpec {
            VaryOperator(
                context: $0,
                initial: initial,
                stateFromParameters: state,
                constraint: constraint,
                pin: pin
            )
        }
    }
}

extension DragSpec {
    /// Switches to `background` when the pointer strays from this spec.
    public func whenFar(_ background: DragSpec, gap: WhenFarGap = .standard) -> DragSpec {
        let foreground = self

        return DragSpec {
            WhenFarOperator(context: $0, foreground: foreground, background: background, gap: gap)
        }
    }

    public func whenFar(_ background: State, gap: WhenFarGap = .standard) -> DragSpec {
        whenFar(DragSpec(fixed: background), gap: gap)
    }

    /// Detaches the dragged element so it follows the pointer, while the
    /// rest of the scene previews this spec.
    public func withFloating(_ options: FloatingOptions<State> = FloatingOptions()) -> DragSpec {
        let inner = self

        return DragSpec { FloatingOperator(context: $0, inner: inner, options: options) }
    }

    /// Jumps the preview to the drop state when within `radius` of it.
    public func withSnapRadius(
        _ radius: Double,
        transition: DragTransition? = nil,
        chaining: SnapChaining = .none
    ) -> DragSpec {
        let inner = self

        return DragSpec {
            SnapRadiusOperator(
                context: $0,
                inner: inner,
                radius: radius,
                transition: transition,
                chaining: chaining
            )
        }
    }

    /// Commits to each new drop state as it comes up, and restarts the
    /// drag from there.
    public func withChaining(
        draggedID: String? = nil,
        followSpec: DragSpec? = nil,
        transition: DragTransition? = .standard
    ) -> DragSpec {
        let chaining = DragChaining(draggedID: draggedID, followSpec: followSpec, transition: transition)

        return mappingResult(name: "withChaining") { result, _ in
            result.chain = result.chain ?? chaining
        }
    }

    /// Draws extra content over the preview while this spec is active,
    /// in canvas coordinates. It's gone on drop.
    public func withOverlay(_ overlay: SceneNode<State>) -> DragSpec {
        let inner = self

        return DragSpec { OverlayOperator(context: $0, inner: inner, overlay: overlay) }
    }

    /// Advanced: remaps the frame on its way to this spec.
    public func changeFrame(_ transform: @escaping (DragFrame) -> DragFrame) -> DragSpec {
        let inner = self

        return DragSpec { ChangeFrameOperator(context: $0, inner: inner, transform: transform) }
    }

    /// Advanced: reweights this spec's gap, to bias `closest` or `whenFar`.
    public func changeGap(_ transform: @escaping (Double) -> Double) -> DragSpec {
        mappingResult(name: "changeGap") { result, _ in
            result.gap = transform(result.gap)
        }
    }

    /// Advanced: edits this spec's whole result on each frame. A new
    /// preview clears the grab position, unless the edit sets its own.
    public func changeResult(_ change: @escaping (inout DragResult<State>) -> Void) -> DragSpec {
        mappingResult(name: "changeResult") { result, _ in
            let preview = result.preview
            let grabPosition = result.grabPosition

            change(&result)

            if result.preview !== preview, result.grabPosition == grabPosition {
                result.grabPosition = nil
            }
        }
    }

    /// Advanced: adjusts the context this spec starts with.
    public func withInitContext(_ change: @escaping (inout DragContext<State>) -> Void) -> DragSpec {
        let inner = self

        return DragSpec { context in
            var adjusted = context
            change(&adjusted)

            return inner.makeOperator(adjusted)
        }
    }

    /// Applies a reusable modifier, written as a function of a spec.
    public func with(_ wrap: (DragSpec) -> DragSpec) -> DragSpec {
        wrap(self)
    }

    /// Replaces the drop state, leaving the preview alone.
    public func onDrop(_ transform: @escaping (State) -> State) -> DragSpec {
        mappingResult(name: "onDrop") { result, _ in
            result.dropState = transform(result.dropState)
        }
    }

    public func onDrop(_ state: State) -> DragSpec {
        onDrop { _ in state }
    }

    /// Sets the animation on drop. Nil drops without animating.
    public func withDropTransition(_ transition: DragTransition?) -> DragSpec {
        mappingResult(name: "withDropTransition") { result, _ in
            result.dropTransition = transition
        }
    }

    /// Sets the animation between branches. Nil switches instantly.
    public func withBranchTransition(_ transition: DragTransition?) -> DragSpec {
        mappingResult(name: "withBranchTransition") { result, _ in
            result.branchTransition = transition
        }
    }

    /// Transforms the state on every frame, changing both preview and drop.
    public func during(_ transform: @escaping (State) -> State) -> DragSpec {
        let inner = self

        return DragSpec { DuringOperator(context: $0, inner: inner, transform: transform) }
    }

    private func mappingResult(
        name: String,
        _ change: @escaping (inout DragResult<State>, DragFrame) -> Void
    ) -> DragSpec {
        let inner = self

        return DragSpec {
            ResultModifierOperator(context: $0, name: name, inner: inner, change: change)
        }
    }
}
