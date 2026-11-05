import DragologySwift
import SwiftUI

/// One entry in the gallery.
struct DemoEntry: Identifiable {
    let title: String
    let operators: String
    let makeView: () -> AnyView

    var id: String { title }

    init<Content: View>(_ title: String, _ operators: String, @ViewBuilder view: @escaping () -> Content) {
        self.title = title
        self.operators = operators
        makeView = { AnyView(view()) }
    }
}

struct DemoSection: Identifiable {
    let title: String
    let demos: [DemoEntry]

    var id: String { title }
}

/// Ported from the demos at https://declarative-dragging.github.io.
@MainActor
enum DemoCatalog {
    private static let standardSize = CGSize(width: 360, height: 300)

    static func demo(titled title: String) -> DemoEntry? {
        sections.flatMap(\.demos).first { $0.title == title }
    }

    static let sections = [
        DemoSection(title: "Basics", demos: [
            DemoEntry("Controls", "between, vary, closest") { ControlsScreen() },

            DemoEntry("Drag List", "DragList") { DragListScreen() },

            DemoEntry("Drag Board", "DragBoard") { DragBoardScreen() },

            DemoEntry("Real SwiftUI Views", "DragItem, dragActivation") { RealViewsScreen() },

            DemoEntry("Three States", "closest, between, withFloating") {
                DemoPage(
                    note: "One interface with three states, under four different specs.",
                    size: CGSize(width: 280, height: 250),
                    initial: TriangleState(),
                    modes: TriangleMode.allCases.map(\.title),
                    draggable: { triangle(mode: TriangleMode(rawValue: $0) ?? .closest) },
                    summary: { "state \($0.index)" }
                )
            },

            DemoEntry("Custom Behavior", "d.custom") {
                DemoPage(
                    note: "The closest mode again, written by hand.",
                    size: CGSize(width: 280, height: 250),
                    initial: TriangleState(),
                    draggable: customTriangle,
                    summary: { "state \($0.index)" }
                )
            },
        ]),

        DemoSection(title: "Discrete States", demos: [
            DemoEntry("Ring of Beads", "closest, whenFar, withFloating") {
                DemoPage(
                    note: "From the paper's first scenario. Each stage adds one modifier.",
                    size: CGSize(width: 340, height: 340),
                    initial: RingState(),
                    modes: RingMode.allCases.map(\.title),
                    draggable: { ring(mode: RingMode(rawValue: $0) ?? .closest) },
                    summary: { $0.beads.joined() }
                )
            },

            DemoEntry("Kanban", "closest, between, withSnapRadius") {
                DemoPage(
                    note: "Drag cards between columns, or drag a column by its header.",
                    size: CGSize(width: 360, height: 220),
                    initial: KanbanState(),
                    draggable: kanban,
                    summary: \.summary
                )
            },

            DemoEntry("Towers of Hanoi", "closest, withFloating") {
                DemoPage(
                    note: "Only legal moves are offered, so illegal ones can't happen.",
                    size: CGSize(width: 360, height: 140),
                    initial: HanoiState(),
                    draggable: hanoi,
                    summary: { $0.pegs.map { $0.map(String.init).joined() }.joined(separator: "|") }
                )
            },

            DemoEntry("Sliding Tiles", "between, withSnapRadius (chained)") {
                DemoPage(
                    note: "Chaining lets one drag slide across several squares. The blank can be dragged too.",
                    size: CGSize(width: 324, height: 324),
                    initial: FifteenState(),
                    draggable: fifteen,
                    summary: \.summary
                )
            },

            DemoEntry("Tromino Tiling", "between, withSnapRadius (chained)") {
                DemoPage(
                    note: "Drag the black square, and the whole tiling rearranges around it.",
                    size: CGSize(width: 356, height: 356),
                    initial: TrominoState(),
                    modes: TrominoMode.allCases.map(\.title),
                    draggable: { tromino(mode: TrominoMode(rawValue: $0) ?? .smooth) },
                    summary: { "\($0.missing.x),\($0.missing.y)" }
                )
            },
        ]),

        DemoSection(title: "Continuous Values", demos: [
            DemoEntry("Bézier Curve", "vary, pin") {
                DemoPage(
                    note: "Drag the points, or the curve itself.",
                    size: CGSize(width: 360, height: 270),
                    initial: BezierState(),
                    draggable: bezier,
                    summary: { "p1 \(Int($0.p1.x)),\(Int($0.p1.y))" }
                )
            },

            DemoEntry("Clock", "vary") {
                DemoPage(
                    note: "Both hands drive one number, and neither hand has any angle math.",
                    size: CGSize(width: 300, height: 300),
                    initial: ClockState(),
                    draggable: clock,
                    summary: \.summary
                )
            },

            DemoEntry("Linked Sliders", "varyFunction") {
                DemoPage(
                    note: "Each slider moves itself and every slider below it.",
                    size: CGSize(width: 310, height: 240),
                    initial: LinkedSlidersState(),
                    draggable: linkedSliders,
                    summary: { $0.values.map { String(Int($0.rounded())) }.joined(separator: " ") }
                )
            },

            DemoEntry("Mirror", "vary, changeFrame") {
                DemoPage(
                    note: "The point follows your finger's reflection.",
                    size: CGSize(width: 300, height: 300),
                    initial: MirrorState(),
                    draggable: mirror,
                    summary: { "\(Int($0.angle.rounded()))°" }
                )
            },

            DemoEntry("Scheduler", "between, vary, constraints") {
                DemoPage(
                    note: "From the paper's second scenario. Red lines are conflicts: overlapping meetings in one room.",
                    size: CGSize(width: Scheduler.width, height: Scheduler.height),
                    initial: SchedulerState(),
                    draggable: scheduler,
                    summary: \.summary
                )
            },

            DemoEntry("Chain of Links", "vary, during, withChaining") {
                DemoPage(
                    note: "Chaining feeds each frame into the next, which gives the chain its memory.",
                    size: standardSize,
                    initial: ChainState(),
                    draggable: chainOfLinks,
                    summary: { "first dot at \(Int($0.dots[0].x.rounded()))" }
                )
            },

            DemoEntry("Card Piles", "vary, during") {
                DemoPage(
                    note: "Overlapping cards form piles. Drag the grey area to move a pile.",
                    size: CGSize(width: 430, height: 340),
                    initial: PilesState.initial,
                    draggable: cardPiles,
                    summary: \.summary
                )
            },
        ]),

        DemoSection(title: "Showcases", demos: [
            DemoEntry("Face Creator", "vary, during, constraints") {
                DemoPage(
                    note: "Drag the eyes, the mouth, or the outline. Features push each other around.",
                    size: CGSize(width: 400, height: 350),
                    initial: FaceState(),
                    modes: FaceMode.allCases.map(\.title),
                    draggable: { faceCreator(mode: FaceMode(rawValue: $0) ?? .standard) },
                    summary: \.summary
                )
            },

            DemoEntry("Braid Group", "between, closest, vary, chained") {
                DemoPage(
                    note: "Every drag is a relation, so the braid never changes, only its word.",
                    size: CGSize(width: BraidLayout.width, height: BraidLayout.height),
                    initial: BraidPreset.all[0].state,
                    modes: BraidPreset.all.map(\.title),
                    draggable: { _ in braid },
                    summary: \.summary,
                    stateForMode: { BraidPreset.all[$0].state }
                )
            },

            DemoEntry("Permutation Lab", "between, closest, vary, chained") {
                DemoPage(
                    note: "One permutation, shown five ways, all in sync. Everything can be dragged.",
                    size: CGSize(width: PermLayout.width, height: PermLayout.height),
                    initial: PermPreset.all[0].state,
                    modes: PermPreset.all.map(\.title),
                    draggable: { _ in permutationLab },
                    summary: \.summary,
                    stateForMode: { PermPreset.all[$0].state }
                )
            },

            DemoEntry("Animate Algebra", "between, emergeFrom (morph), chained") {
                DemoPage(
                    note: "Drag any part of the expression. Only rewrites that keep its value are offered.",
                    size: CGSize(width: 360, height: 430),
                    initial: AlgebraState(),
                    modes: AlgebraMode.allCases.map(\.title),
                    draggable: { animateAlgebra(mode: AlgebraMode(rawValue: $0) ?? .basics) },
                    summary: \.summary
                )
            },

            DemoEntry("Twisted Trees 3→3", "between, dropTarget, natural neighbor") {
                DemoPage(
                    note: "Order-preserving maps between trees. Drag a black node into a grey one.",
                    size: CGSize(width: 300, height: 460),
                    initial: TwistState(morph: TwistUniverse.small.morphs[0]),
                    modes: TwistMode.allCases.map(\.title),
                    draggable: { twistedTrees(.small, mode: TwistMode(rawValue: $0) ?? .naturalNeighbor) },
                    summary: \.summary
                )
            },

            DemoEntry("Twisted Trees 7→7", "between, dropTarget, natural neighbor") {
                DemoPage(
                    note: "The same idea with bigger trees, chosen from over 5,000 possible maps.",
                    size: CGSize(width: 400, height: 600),
                    initial: TwistState(morph: TwistUniverse.large.morphs[0]),
                    modes: TwistMode.allCases.filter { $0 != .traditional }.map(\.title),
                    draggable: { twistedTrees(.large, mode: TwistMode(rawValue: $0) ?? .naturalNeighbor) },
                    summary: \.summary
                )
            },
        ]),

        DemoSection(title: "Composition", demos: [
            DemoEntry("Snap to Islands", "whenFar, vary, withFloating") {
                DemoPage(
                    note: "Discrete islands in a continuous sea.",
                    size: CGSize(width: 360, height: 260),
                    initial: IslandState(),
                    draggable: islands,
                    summary: \.summary
                )
            },

            DemoEntry("Magnetic Targets", "closest, changeGap") {
                DemoPage(
                    note: "Reweighted gaps give each target a different reach.",
                    size: CGSize(width: 370, height: 240),
                    initial: MagnetState(),
                    draggable: magnets,
                    summary: { "target \($0.current)" }
                )
            },

            DemoEntry("Sharpness", "between (sharpness)") {
                DemoPage(
                    note: "Higher sharpness pulls the knob towards its ends.",
                    size: CGSize(width: 340, height: 320),
                    initial: SharpnessState(),
                    draggable: sharpness,
                    summary: { $0.isOn ? "on" : "off" }
                )
            },

            DemoEntry("Blend Weights", "between (natural neighbor)") {
                DemoPage(
                    note: "Move across triangle edges and compare: natural neighbor has no creases.",
                    size: CGSize(width: 350, height: 330),
                    initial: BlendState(),
                    modes: BlendMode.allCases.map(\.title),
                    draggable: { blendWeights(mode: BlendMode(rawValue: $0) ?? .delaunay) },
                    summary: { "target \($0.corner)" }
                )
            },

            DemoEntry("Emerge From", "emergeFrom") {
                DemoPage(
                    note: "The second dot grows out of the first as you drag.",
                    size: CGSize(width: 340, height: 200),
                    initial: EmergeState(),
                    draggable: emerge,
                    summary: { $0.isRight ? "right" : "left" }
                )
            },

            DemoEntry("Sprouting Tree", "between, emergeFrom, chained") {
                DemoPage(
                    note: "Pull a leaf down and sideways to fork it, or up to fold it back.",
                    size: CGSize(width: 360, height: 320),
                    initial: SproutState(),
                    draggable: sproutingTree,
                    summary: \.summary
                )
            },

            DemoEntry("Drag to Copy", "switchToStateAndFollow") {
                DemoPage(
                    note: "Dragging leaves the original behind and takes a copy. Tap to remove.",
                    size: standardSize,
                    initial: CopyState(),
                    draggable: dragToCopy,
                    summary: \.summary
                )
            },

            DemoEntry("Copy or Move", "reactTo") { CopyOrMoveScreen() },

            DemoEntry("Insert and Remove", "dropTarget, switchToStateAndFollow") {
                DemoPage(
                    note: "Pull tiles off the toolbar, rearrange them, or drop them in the bin.",
                    size: CGSize(width: 350, height: 280),
                    initial: ShelfState(),
                    draggable: shelf,
                    summary: \.summary
                )
            },

            DemoEntry("Timeline (substate)", "substate, closest, vary") {
                DemoPage(
                    note: "The spec is written for one block, not the whole state.",
                    size: CGSize(width: 360, height: 190),
                    initial: TimelineState(),
                    draggable: timelineSubstate,
                    summary: \.summary
                )
            },

            DemoEntry("Timeline (embed)", "embed, closest, vary") {
                DemoPage(
                    note: "Each block is a draggable in its own right, embedded in the timeline.",
                    size: CGSize(width: 360, height: 190),
                    initial: TimelineState(),
                    draggable: timelineEmbed,
                    summary: \.summary
                )
            },

            DemoEntry("Overlay", "withOverlay") {
                DemoPage(
                    note: "The ring only exists while you're dragging.",
                    size: CGSize(width: 350, height: 180),
                    initial: MarkerState(),
                    draggable: marker,
                    summary: { $0.isDocked ? "docked" : "home" }
                )
            },
        ]),
    ]
}

/// The web demo watches the Alt key. Here a switch does that job.
private struct CopyOrMoveScreen: View {
    @State private var copySwitch = CopySwitch()

    var body: some View {
        VStack {
            Toggle("Copy while dragging", isOn: $copySwitch.isCopying)
                .padding(.horizontal)

            DemoPage(
                note: "The spec is rebuilt if the switch changes during a drag.",
                size: CGSize(width: 360, height: 300),
                initial: CopyState(),
                draggable: copyOrMove(copySwitch),
                summary: \.summary
            )
        }
    }
}
