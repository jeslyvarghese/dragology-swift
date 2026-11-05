@testable import DragologySwiftCore

/// A two-position switch: the knob is at x = 30 or x = 90.
struct ToggleState: Equatable {
    var isOn = false
}

func toggle(_ context: RenderContext<ToggleState>) -> Node<ToggleState> {
    let knobX = context.state.isOn ? 90.0 : 30.0

    return group {
        circle(radius: 26)
            .id("knob")
            .fill(.white)
            .transform(.translate(knobX, 30))
            .onDrag { context.d.between([ToggleState(isOn: false), ToggleState(isOn: true)]) }
    }
}

/// A horizontal slider, limited to 0...240.
struct SliderState: Equatable {
    var value = 100.0
}

func slider(_ context: RenderContext<SliderState>) -> Node<SliderState> {
    circle(radius: 14)
        .id("thumb")
        .fill(.black)
        .transform(.translate(context.state.value, 0))
        .onDrag {
            context.d.vary(context.state, \.value, constraint: { state in
                Constraint.inOrder(0, state.value, 240)
            })
        }
}

/// A vertical list of 40-point rows.
struct ListState: Equatable {
    var items = ["a", "b", "c"]

    func moving(from source: Int, to destination: Int) -> ListState {
        var copy = self
        copy.items.insert(copy.items.remove(at: source), at: destination)
        return copy
    }
}

func list(_ context: RenderContext<ListState>) -> Node<ListState> {
    let state = context.state

    return group {
        for (index, item) in state.items.enumerated() {
            rect(width: 100, height: 30)
                .id(item)
                .fill(.white)
                .transform(.translate(0, Double(index) * 40))
                .onDrag {
                    let orders = state.items.indices.map { state.moving(from: index, to: $0) }
                    return context.d.closest(orders).withFloating()
                }
        }
    }
}

/// Runs a whole drag at a fixed clock, returning the engine.
func drag<State>(
    _ engine: DragEngine<State>,
    from start: Vec2,
    through points: [Vec2]
) {
    engine.pointerDown(at: start, now: 0)

    for point in points {
        engine.pointerMoved(to: point, now: 0)
        engine.tick(now: 0)
    }
}

extension LayeredScene {
    /// Where a layer's origin ended up.
    func origin(of id: String) -> Vec2? {
        layers[id]?.node.transform.localToGlobal(.zero)
    }
}
