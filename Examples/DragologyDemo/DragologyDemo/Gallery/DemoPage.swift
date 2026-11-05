import DragologySwift
import SwiftUI

private enum Layout {
    static let spacing: CGFloat = 12
}

private enum Identifier {
    static let canvas = "demoCanvas"
    static let value = "demoValue"
}

/// One demo: a note, optional mode picker, the canvas, and a readout of
/// the state. Designs wider than the screen are scaled down to fit.
struct DemoPage<State: Equatable>: View {
    let note: String
    let size: CGSize
    var modes: [String] = []
    let draggable: (Int) -> DragScene<State>
    let summary: (State) -> String
    /// Set for modes that each start from their own state.
    var stateForMode: ((Int) -> State)?

    @SwiftUI.State private var state: State
    /// `-mode <index>` at launch starts here, for the UI tests.
    @SwiftUI.State private var mode = UserDefaults.standard.integer(forKey: "mode")

    init(
        note: String,
        size: CGSize,
        initial: State,
        modes: [String] = [],
        draggable: @escaping (Int) -> DragScene<State>,
        summary: @escaping (State) -> String,
        stateForMode: ((Int) -> State)? = nil
    ) {
        self.note = note
        self.size = size
        self.modes = modes
        self.draggable = draggable
        self.summary = summary
        self.stateForMode = stateForMode

        let launchMode = UserDefaults.standard.integer(forKey: "mode")
        _state = SwiftUI.State(initialValue: stateForMode?(launchMode) ?? initial)
    }

    /// Changes mode and state together, so a canvas never sees a state
    /// from another mode.
    private var modeSelection: Binding<Int> {
        Binding(
            get: { mode },
            set: { newMode in
                mode = newMode

                if let stateForMode {
                    state = stateForMode(newMode)
                }
            }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.width - 2 * Layout.spacing
            let scale = min(1, available / size.width)

            VStack(alignment: .leading, spacing: Layout.spacing) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !modes.isEmpty {
                    Picker("Mode", selection: modeSelection) {
                        ForEach(modes.indices, id: \.self) { index in
                            Text(modes[index]).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Rebuilding on a mode change swaps in the new draggable.
                DragCanvas(state: $state, scene: draggable(mode))
                    .id(mode)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                    .accessibilityElement()
                    .accessibilityIdentifier(Identifier.canvas)

                Text(summary(state))
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .accessibilityIdentifier(Identifier.value)
            }
            .padding(Layout.spacing)
        }
    }
}

extension DemoPage {
    /// For demos with a single behavior.
    init(
        note: String,
        size: CGSize,
        initial: State,
        draggable: @escaping DragScene<State>,
        summary: @escaping (State) -> String
    ) {
        self.init(
            note: note,
            size: size,
            initial: initial,
            modes: [],
            draggable: { _ in draggable },
            summary: summary
        )
    }
}

/// Colors shared across the gallery.
enum Ink {
    static let outline = SceneColor(hex: 0xCBD5E1)
    static let faint = SceneColor(hex: 0xE5E7EB)
    static let muted = SceneColor(hex: 0x9CA3AF)
    static let text = SceneColor(hex: 0x374151)
    static let blue = SceneColor(hex: 0x3B82F6)
    static let red = SceneColor(hex: 0xEF4444)
    static let green = SceneColor(hex: 0x22C55E)
    static let amber = SceneColor(hex: 0xF59E0B)
    static let purple = SceneColor(hex: 0x8B5CF6)
    static let cyan = SceneColor(hex: 0x06B6D4)
    static let pink = SceneColor(hex: 0xEC4899)
    static let panel = SceneColor(hex: 0xF3F4F6)

    static let series = [blue, cyan, green, amber, purple, pink, red]
}

/// A point at a distance and angle from the origin.
func polar(radius: Double, degrees: Double) -> Vec2 {
    let radians = degrees * .pi / 180
    return Vec2(radius * cos(radians), radius * sin(radians))
}

extension Vec2 {
    var angle: Double { atan2(y, x) }
    var normalized: Vec2 { length > 0 ? self * (1 / length) : self }

    /// This point, moved `distance` in the direction of `target`.
    func towards(_ target: Vec2, by distance: Double) -> Vec2 {
        self + (target - self).normalized * distance
    }
}

/// A smooth curve through three points, as d3's `curveCardinal` draws it.
func cardinalCurve(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> [PathCommand] {
    let tensionShare = 1.0 / 6

    return [
        .move(a),
        .cubic(
            control1: a + (b - a) * tensionShare,
            control2: b + (a - c) * tensionShare,
            end: b
        ),
        .cubic(control1: b + (c - a) * tensionShare, control2: c, end: c),
    ]
}

/// A short id for something created during a drag.
func freshID() -> String {
    let length = 8
    return String(UUID().uuidString.prefix(length))
}
