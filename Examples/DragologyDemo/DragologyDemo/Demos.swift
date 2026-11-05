import DragologySwift
import Foundation

private enum Palette {
    static let accent = SceneColor(hex: 0x3B82F6)
    static let track = SceneColor(hex: 0xD1D5DB)
    static let on = SceneColor(hex: 0x22C55E)
    static let row = SceneColor(hex: 0xF3F4F6)
    static let rowBorder = SceneColor(hex: 0x9CA3AF)
    static let ink = SceneColor(hex: 0x374151)
}

// MARK: - drag.between: a toggle switch

struct ToggleState: Equatable {
    var isOn = false
}

private enum ToggleMetrics {
    static let width = 120.0
    static let height = 60.0
    static let knobRadius = 26.0
    static let offX = 30.0
    static let onX = 90.0
    static let y = 30.0
}

func toggleSwitch(_ context: SceneContext<ToggleState>) -> SceneNode<ToggleState> {
    let state = context.state
    let knobX = state.isOn ? ToggleMetrics.onX : ToggleMetrics.offX

    return SceneGroup {
        SceneRect(
            width: ToggleMetrics.width,
            height: ToggleMetrics.height,
            cornerRadius: ToggleMetrics.height / 2
        )
        .fill(state.isOn ? Palette.on : Palette.track)

        SceneCircle(radius: ToggleMetrics.knobRadius)
            .id("knob")
            .fill(.white)
            .transform(.translate(knobX, ToggleMetrics.y))
            .onDrag {
                context.drag
                    .between([ToggleState(isOn: false), ToggleState(isOn: true)])
                    .withDropTransition(.easing(.elasticOut))
            }
    }
}

// MARK: - drag.vary with a constraint: a slider

struct SliderState: Equatable {
    var value = 100.0
}

private enum SliderMetrics {
    static let inset = 20.0
    static let maxValue = 280.0
    static let y = 25.0
    static let thumbRadius = 14.0
    static let trackWidth = 4.0
}

func slider(_ context: SceneContext<SliderState>) -> SceneNode<SliderState> {
    let state = context.state

    return SceneGroup {
        SceneLine(from: .zero, to: Vec2(SliderMetrics.maxValue, 0))
            .stroke(Palette.track, lineWidth: SliderMetrics.trackWidth)

        SceneCircle(radius: SliderMetrics.thumbRadius)
            .id("thumb")
            .fill(Palette.accent)
            .transform(.translate(state.value, 0))
            .onDrag {
                context.drag.vary(state, \.value, constraint: { candidate in
                    DragConstraint.inOrder(0, candidate.value, SliderMetrics.maxValue)
                })
            }
    }
    .transform(.translate(SliderMetrics.inset, SliderMetrics.y))
}

// MARK: - drag.vary through a rotation: a dial

struct DialState: Equatable {
    var degrees = 0.0
}

private enum DialMetrics {
    static let center = Vec2(160, 75)
    static let radius = 60.0
    static let handleRadius = 14.0
    static let ringWidth = 3.0
}

func dial(_ context: SceneContext<DialState>) -> SceneNode<DialState> {
    let state = context.state

    return SceneGroup {
        SceneCircle(radius: DialMetrics.radius)
            .stroke(Palette.track, lineWidth: DialMetrics.ringWidth)

        // The render function only rotates; `vary` works out the angle.
        SceneCircle(radius: DialMetrics.handleRadius)
            .id("handle")
            .fill(Palette.accent)
            .transform(.rotate(degrees: state.degrees) + .translate(DialMetrics.radius, 0))
            .onDrag { context.drag.vary(state, \.degrees) }
    }
    .transform(.translate(DialMetrics.center))
}

// MARK: - drag.closest + withFloating: a reorderable list

struct ListState: Equatable {
    var items = ["Apples", "Bananas", "Cherries", "Dates"]

    func moving(from source: Int, to destination: Int) -> ListState {
        var copy = self
        copy.items.insert(copy.items.remove(at: source), at: destination)
        return copy
    }
}

private enum ListMetrics {
    static let width = 300.0
    static let rowHeight = 42.0
    static let pitch = 48.0
    static let cornerRadius = 6.0
    static let borderWidth = 1.5
    static let fontSize = 16.0
    /// Keeps row borders inside the canvas, which clips its content.
    static let inset = 2.0
}

func reorderableList(_ context: SceneContext<ListState>) -> SceneNode<ListState> {
    let state = context.state

    return SceneGroup {
        for (index, item) in state.items.enumerated() {
            SceneGroup {
                SceneRect(
                    width: ListMetrics.width,
                    height: ListMetrics.rowHeight,
                    cornerRadius: ListMetrics.cornerRadius
                )
                .fill(Palette.row)
                .stroke(Palette.rowBorder, lineWidth: ListMetrics.borderWidth)

                SceneText(item, size: ListMetrics.fontSize)
                    .fill(Palette.ink)
                    .transform(.translate(ListMetrics.width / 2, ListMetrics.rowHeight / 2))
            }
            .id(item)
            .transform(.translate(0, Double(index) * ListMetrics.pitch))
            .zIndex(context.draggedID == item ? .absolute(1) : .relative(0))
            .onDrag {
                let orders = state.items.indices.map { state.moving(from: index, to: $0) }
                return context.drag.closest(orders).withFloating()
            }
        }
    }
    .transform(.translate(ListMetrics.inset, ListMetrics.inset))
}
