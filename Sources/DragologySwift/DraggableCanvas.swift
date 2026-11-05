@_exported import DragologySwiftCore
import SwiftUI

/// Hosts a `Draggable` in SwiftUI: routes touches to the engine, runs
/// its clock, and keeps it in sync with `state`.
///
/// The render function is captured when the canvas first appears, so
/// it should depend only on the state it's given.
public struct DraggableCanvas<State: Equatable>: View {
    @Binding private var state: State
    @SwiftUI.State private var engine: DragEngine<State>
    @SwiftUI.State private var isPressing = false
    /// Resets however a gesture ends, including when it's cancelled.
    @GestureState private var isTouching = false

    public init(state: Binding<State>, draggable: @escaping Draggable<State>) {
        _state = state
        _engine = SwiftUI.State(
            initialValue: DragEngine(state: state.wrappedValue, draggable: draggable)
        )
    }

    public var body: some View {
        TimelineView(.animation(paused: !engine.needsFrames)) { timeline in
            SceneCanvas(engine: engine)
                .onChange(of: timeline.date) { _, date in
                    engine.tick(now: date.timeIntervalSinceReferenceDate)
                }
        }
        .contentShape(Rectangle())
        .gesture(pointerGesture)
        .onChange(of: isTouching) { _, isTouching in
            guard !isTouching else { return }

            finishCancelledTouch()
        }
        .onChange(of: state) { _, newState in
            engine.setState(newState, now: Self.now)
        }
        .onChange(of: engine.state) { _, newState in
            state = newState
        }
    }

    /// Reports every touch from its very start, so the engine can tell
    /// presses, taps, and drags apart itself.
    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($isTouching) { _, isTouching, _ in
                isTouching = true
            }
            .onChanged { value in
                let point = Vec2(value.location)

                if isPressing {
                    engine.pointerMoved(to: point, now: Self.now)
                    return
                }

                isPressing = true
                engine.pointerDown(at: Vec2(value.startLocation), now: Self.now)
                engine.pointerMoved(to: point, now: Self.now)
            }
            .onEnded { value in
                isPressing = false
                engine.pointerUp(at: Vec2(value.location), now: Self.now)
            }
    }

    /// `DragGesture` reports no cancellation, but its gesture state still
    /// resets. A normal end also lands here, so this waits a turn: by
    /// then `onEnded` has cleared `isPressing` if the touch really ended.
    private func finishCancelledTouch() {
        Task { @MainActor in
            guard isPressing else { return }

            isPressing = false
            engine.pointerCancelled(now: Self.now)
        }
    }

    private static var now: TimeInterval { Date.timeIntervalSinceReferenceDate }
}

/// Draws the engine's current scene. A view of its own so that it
/// observes `scene` and redraws whenever the engine publishes a frame.
private struct SceneCanvas<State: Equatable>: View {
    let engine: DragEngine<State>

    var body: some View {
        let scene = engine.scene

        Canvas { context, _ in
            SceneRenderer.draw(scene, in: context)
        }
    }
}

private extension Vec2 {
    init(_ point: CGPoint) {
        self.init(Double(point.x), Double(point.y))
    }
}
