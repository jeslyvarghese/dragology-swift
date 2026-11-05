import Foundation
import Observation

/// The drag state machine. It knows nothing about any UI framework: a
/// host feeds it pointer events and clock ticks, and draws `scene`.
@Observable
public final class DragEngine<State: Equatable> {
    /// An in-flight animation: what was on screen when it started.
    private struct Spring {
        var origin: LayeredScene<State>
        var startTime: TimeInterval
        var transition: DragTransition

        func isFinished(at now: TimeInterval) -> Bool {
            now - startTime >= transition.duration
        }
    }

    /// A press on a tappable element, which hasn't yet moved far enough
    /// to count as a drag.
    private struct PendingPress {
        var startPoint: Vec2
        var drag: ActiveDrag?
        var onTap: (() -> Void)?
    }

    private struct ActiveDrag {
        var context: DragContext<State>
        var behavior: DragOperator<State>
        var result: DragResult<State>
    }

    private enum Phase {
        case idle
        case pressed(PendingPress)
        case dragging(ActiveDrag)
    }

    /// The state outside of any drag. Changes on drop and `setState`.
    public private(set) var state: State
    /// What to draw right now.
    public private(set) var scene: LayeredScene<State>
    /// True while the host needs to keep calling `tick`.
    public private(set) var needsFrames = false
    /// Counts the changes that came from the user: drops, and `setState`
    /// calls from the scene. A host watches this to know when to read
    /// `state` back. Watching `state` itself would also catch changes the
    /// host made, and writing those back can overwrite newer ones.
    public private(set) var userChangeCount = 0

    @ObservationIgnored private let sceneFunction: DragScene<State>
    @ObservationIgnored private let dragThreshold: Double
    @ObservationIgnored private var phase = Phase.idle
    @ObservationIgnored private var spring: Spring?
    @ObservationIgnored private var pointer = Vec2.zero
    @ObservationIgnored private var idleScene: LayeredScene<State>

    /// - Parameters:
    ///   - state: The state to start from.
    ///   - dragThreshold: How far a press on a tappable element must travel
    ///     before it's a drag and not a tap.
    ///   - sceneFunction: The render function.
    public init(
        state: State,
        dragThreshold: Double = DragEngine.standardDragThreshold,
        scene sceneFunction: @escaping DragScene<State>
    ) {
        self.state = state
        self.dragThreshold = dragThreshold
        self.sceneFunction = sceneFunction

        // `setState` needs `self`, so the first render can't use it yet.
        let first = Self.interactiveRender(sceneFunction, state, setState: { _, _ in })
        idleScene = first
        scene = first

        refreshIdleScene()
    }

    public static var standardDragThreshold: Double { 2 }

    /// Whether a press here would do anything. A host can leave other
    /// touches alone, so that they reach whatever's behind it.
    public func wouldHandlePress(at point: Vec2) -> Bool {
        guard case .idle = phase, let hit = idleScene.hitTest(point) else { return false }

        return hit.dragTarget != nil || hit.onTap != nil
    }

    // MARK: Pointer events

    public func pointerDown(at point: Vec2, now: TimeInterval) {
        guard case .idle = phase else { return }
        guard let hit = idleScene.hitTest(point) else { return }

        pointer = point

        let drag = hit.dragTarget.map { makeDrag(for: $0, pointer: point) }

        // Without a tap to protect, a drag can start right away.
        if let drag, hit.onTap == nil || dragThreshold <= 0 {
            phase = .dragging(drag)
            needsFrames = true
            return
        }

        guard drag != nil || hit.onTap != nil else { return }

        phase = .pressed(PendingPress(startPoint: point, drag: drag, onTap: hit.onTap))
    }

    public func pointerMoved(to point: Vec2, now: TimeInterval) {
        pointer = point

        guard case .pressed(let press) = phase, let drag = press.drag else { return }
        guard point.distance(to: press.startPoint) > dragThreshold else { return }

        phase = .dragging(drag)
        needsFrames = true
    }

    public func pointerUp(at point: Vec2, now: TimeInterval) {
        pointer = point

        switch phase {
        case .idle:
            return

        case .pressed(let press):
            phase = .idle
            press.onTap?()

        case .dragging(let drag):
            finish(drag, at: point, now: now)
        }
    }

    /// The system took the touch away: back out, as if never dragged.
    public func pointerCancelled(now: TimeInterval) {
        guard case .dragging(let drag) = phase else {
            phase = .idle
            return
        }

        startSpring(from: displayed(drag.result.preview.value, now: now), transition: .standard, now: now)
        phase = .idle
        tick(now: now)
    }

    private func finish(_ drag: ActiveDrag, at point: Vec2, now: TimeInterval) {
        let result = drag.behavior.run(DragFrame(pointer: point))

        if let transition = result.dropTransition {
            startSpring(from: displayed(result.preview.value, now: now), transition: transition, now: now)
        } else {
            spring = nil
        }

        phase = .idle
        state = result.dropState
        userChangeCount += 1
        refreshIdleScene()
        tick(now: now)
    }

    private func makeDrag(for target: Hit<State>.DragTarget, pointer: Vec2) -> ActiveDrag {
        guard let onDrag = target.node.onDrag, let anchor = target.transform.globalToLocal(pointer) else {
            preconditionFailure("A drag target must have a handler and an invertible transform.")
        }

        let context = DragContext(
            scene: sceneFunction,
            draggedPath: target.node.path,
            draggedID: target.node.id,
            anchor: anchor,
            startState: state
        )

        let behavior = onDrag().makeOperator(context)

        return ActiveDrag(
            context: context,
            behavior: behavior,
            result: behavior.run(DragFrame(pointer: pointer))
        )
    }

    // MARK: Clock

    /// Advances one frame.
    public func tick(now: TimeInterval) {
        if case .dragging(let drag) = phase {
            advance(drag, now: now)
            return
        }

        if let spring, spring.isFinished(at: now) {
            self.spring = nil
        }

        scene = displayed(idleScene, now: now)
        needsFrames = spring != nil
    }

    private func advance(_ drag: ActiveDrag, now: TimeInterval) {
        let frame = DragFrame(pointer: pointer)
        let result = drag.behavior.run(frame)

        if let chained = chain(from: drag, result: result, frame: frame, now: now) {
            phase = .dragging(chained)
            scene = displayed(chained.result.preview.value, now: now)
            needsFrames = true
            return
        }

        // A new branch springs from whatever was on screen.
        if result.activePath != drag.result.activePath {
            if let transition = result.branchTransition {
                startSpring(from: displayed(drag.result.preview.value, now: now), transition: transition, now: now)
            } else {
                spring = nil
            }
        }

        if let spring, spring.isFinished(at: now) {
            self.spring = nil
        }

        phase = .dragging(ActiveDrag(context: drag.context, behavior: drag.behavior, result: result))
        scene = displayed(result.preview.value, now: now)
        needsFrames = true
    }

    /// Restarts the drag from the drop state, if the result asks to. Nil
    /// if not, or if there's nothing to continue with.
    private func chain(
        from drag: ActiveDrag,
        result: DragResult<State>,
        frame: DragFrame,
        now: TimeInterval
    ) -> ActiveDrag? {
        guard let chaining = result.chain else { return nil }
        guard result.dropState != drag.context.startState else { return nil }

        let state = result.dropState
        let id = chaining.draggedID ?? drag.context.draggedID

        guard let element = drag.context.element(id: id, in: state) else {
            preconditionFailure("Chained drag: couldn't find element \(id ?? drag.context.draggedPath).")
        }

        guard let spec = chaining.followSpec ?? element.onDrag?() else { return nil }

        // Spring from what's on screen, before any of the new drag shows.
        if let transition = chaining.transition {
            startSpring(from: displayed(drag.result.preview.value, now: now), transition: transition, now: now)
        } else {
            spring = nil
        }

        var context = drag.context
        context.draggedID = id
        context.draggedPath = element.path
        context.startState = state

        let behavior = spec.makeOperator(context)

        return ActiveDrag(context: context, behavior: behavior, result: behavior.run(frame))
    }

    // MARK: State changes

    /// Changes state from outside a drag. Ignored during a drag, as the
    /// drop is about to decide the state anyway.
    public func setState(_ newState: State, transition: DragTransition? = .standard, now: TimeInterval) {
        guard newState != state else { return }

        if case .dragging = phase { return }

        if let transition {
            startSpring(from: scene, transition: transition, now: now)
        } else {
            spring = nil
        }

        phase = .idle
        state = newState
        refreshIdleScene()
        tick(now: now)
    }

    // MARK: Rendering

    private func refreshIdleScene() {
        idleScene = Self.interactiveRender(sceneFunction, state) { [weak self] newState, transition in
            self?.setState(newState, transition: transition, now: Self.currentTime)
            self?.userChangeCount += 1
        }
        scene = idleScene
    }

    private static var currentTime: TimeInterval { Date.timeIntervalSinceReferenceDate }

    private static func interactiveRender(
        _ sceneFunction: DragScene<State>,
        _ state: State,
        setState: @escaping (State, DragTransition?) -> Void
    ) -> LayeredScene<State> {
        let context = SceneContext(
            state: state,
            draggedID: nil,
            isTracking: false,
            applyState: setState
        )

        return LayeredScene(root: sceneFunction(context).assigningPaths())
    }

    private func startSpring(from origin: LayeredScene<State>, transition: DragTransition, now: TimeInterval) {
        spring = Spring(origin: origin, startTime: now, transition: transition)
        needsFrames = true
    }

    /// `target`, as seen through any running spring.
    private func displayed(_ target: LayeredScene<State>, now: TimeInterval) -> LayeredScene<State> {
        guard let spring else { return target }

        let progress = spring.transition.progress(elapsed: now - spring.startTime)
        var blended = LayeredScene.lerp(target, spring.origin, 1 - progress, unblended: .first)

        // Layers tracking the finger must not lag behind it.
        for (key, layer) in target.layers {
            if case .immediate = layer.node.transitionPolicy {
                blended.setLayer(layer, forKey: key)
            }
        }

        return blended
    }
}
