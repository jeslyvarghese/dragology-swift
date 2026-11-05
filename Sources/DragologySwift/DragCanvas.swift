@_exported import DragologySwiftCore
import SwiftUI

/// Hosts a `DragScene` in SwiftUI: routes touches to the engine, runs
/// its clock, and keeps it in sync with `state`.
///
/// The render function is captured when the canvas first appears, so
/// it should depend only on the state it's given.
public struct DragCanvas<State: Equatable>: View {
    @Binding private var state: State
    @SwiftUI.State private var engine: DragEngine<State>
    @Environment(\.dragActivation) private var activation
    @Environment(\.externalStateTransition) private var externalTransition

    public init(state: Binding<State>, scene: @escaping DragScene<State>) {
        _state = state
        _engine = SwiftUI.State(
            initialValue: DragEngine(state: state.wrappedValue, scene: scene)
        )
    }

    public var body: some View {
        TimelineView(.animation(paused: !engine.needsFrames)) { timeline in
            SceneStack(engine: engine)
                .onChange(of: timeline.date) { _, date in
                    engine.tick(now: date.timeIntervalSinceReferenceDate)
                }
        }
        .contentShape(Rectangle())
        .pointerEvents(activation: activation ?? .immediate, engine: engine)
        .onChange(of: state) { _, newState in
            engine.setState(newState, transition: externalTransition, now: Date.timeIntervalSinceReferenceDate)
        }
        .onChange(of: engine.userChangeCount) {
            state = engine.state
        }
    }
}
