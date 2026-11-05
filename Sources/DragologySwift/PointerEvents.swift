import SwiftUI

/// When a touch turns into a drag.
public enum DragActivation: Sendable, Equatable {
    /// As soon as the finger moves. The default.
    case immediate
    /// After a short hold, so that a parent `ScrollView` can still scroll.
    case longPress(minimumDuration: TimeInterval = 0.3)
}

extension EnvironmentValues {
    @Entry var dragActivation = DragActivation.immediate
}

extension View {
    /// Sets when touches in the canvases inside this view start a drag.
    public func dragActivation(_ activation: DragActivation) -> some View {
        environment(\.dragActivation, activation)
    }

    func pointerEvents<State>(activation: DragActivation, engine: DragEngine<State>) -> some View {
        modifier(PointerEventsModifier(activation: activation, engine: engine))
    }
}

private func currentTime() -> TimeInterval {
    Date.timeIntervalSinceReferenceDate
}

private extension Vec2 {
    init(_ point: CGPoint) {
        self.init(Double(point.x), Double(point.y))
    }
}

#if os(iOS)

private struct PointerEventsModifier<State: Equatable>: ViewModifier {
    let activation: DragActivation
    let engine: DragEngine<State>

    func body(content: Content) -> some View {
        content.gesture(PointerRecognizer(activation: activation, engine: engine))
    }
}

/// Reports a touch from start to finish, including when the system takes
/// it away. It only begins on something the engine would act on, so that
/// other touches reach whatever's behind the canvas.
private struct PointerRecognizer<State: Equatable>: UIGestureRecognizerRepresentable {
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let converter: CoordinateSpaceConverter
        var engine: DragEngine<State>

        init(converter: CoordinateSpaceConverter, engine: DragEngine<State>) {
            self.converter = converter
            self.engine = engine
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            engine.wouldHandlePress(at: Vec2(converter.localLocation))
        }
    }

    let activation: DragActivation
    let engine: DragEngine<State>

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter, engine: engine)
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()

        // Controls inside hosted views need to see their touches too.
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator

        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        context.coordinator.engine = engine

        switch activation {
        case .immediate:
            recognizer.minimumPressDuration = 0
        case .longPress(let minimumDuration):
            recognizer.minimumPressDuration = minimumDuration
        }
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = Vec2(context.converter.localLocation)

        switch recognizer.state {
        case .began:
            engine.pointerDown(at: point, now: currentTime())

        case .changed:
            engine.pointerMoved(to: point, now: currentTime())

        case .ended:
            engine.pointerUp(at: point, now: currentTime())

        case .cancelled, .failed:
            engine.pointerCancelled(now: currentTime())

        default:
            break
        }
    }
}

#else

/// Mac hosts have no touches to share, so a plain drag gesture does.
private struct PointerEventsModifier<State: Equatable>: ViewModifier {
    let activation: DragActivation
    let engine: DragEngine<State>

    @SwiftUI.State private var isPressing = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if !isPressing {
                        isPressing = true
                        engine.pointerDown(at: Vec2(value.startLocation), now: currentTime())
                    }

                    engine.pointerMoved(to: Vec2(value.location), now: currentTime())
                }
                .onEnded { value in
                    isPressing = false
                    engine.pointerUp(at: Vec2(value.location), now: currentTime())
                }
        )
    }
}

#endif
