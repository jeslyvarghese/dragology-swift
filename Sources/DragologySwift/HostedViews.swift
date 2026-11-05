import SwiftUI

/// Whether a hosted view's own controls receive touches.
public enum DragItemInteraction: Sendable {
    /// The view is display only, and any touch on it drags it.
    case dragOnly
    /// Buttons and fields inside keep working. A touch only becomes a
    /// drag once it moves.
    case interactive
}

/// What a `.slot` holds when it's drawn by SwiftUI.
struct HostedContent {
    var make: @MainActor () -> AnyView
    var interaction: DragItemInteraction
}

/// Puts a real SwiftUI view in a `DragCanvas`. It moves, turns, and
/// fades with the scene, and keeps its `@State` as long as its node keeps
/// its id. What's inside doesn't blend: it shows one state's content at a
/// time.
///
/// This is a function, not a type, because it builds a `SceneNode`: that's what
/// lets `.id`, `.transform`, and `.onDrag` chain onto it. It's capitalized
/// to read like the SwiftUI component it stands in for.
public func DragItem<State, Content: View>(
    width: Double,
    height: Double,
    interaction: DragItemInteraction = .dragOnly,
    @ViewBuilder content: @escaping @MainActor () -> Content
) -> SceneNode<State> {
    var node = SceneNode<State>(shape: .slot(size: Vec2(width, height)))

    node.hostedContent = HostedContent(make: { AnyView(content()) }, interaction: interaction)

    // A pending tap holds a press back until it moves, leaving the view's
    // controls the chance to act on it first.
    if case .interactive = interaction {
        node.onTap = {}
    }

    return node
}

/// One thing to stack in a scene, from back to front.
enum SceneItem<State: Equatable>: Identifiable {
    /// Consecutive layers that one canvas can draw.
    case drawing(index: Int, layers: [SceneLayer<State>])
    case hosted(HostedItem)

    var id: String {
        switch self {
        case .drawing(let index, _):
            return "drawing-\(index)"
        case .hosted(let item):
            return item.id
        }
    }

    static func items(in scene: LayeredScene<State>) -> [SceneItem] {
        var items: [SceneItem] = []
        var run: [SceneLayer<State>] = []
        var runIndex = 0

        for layer in scene.drawOrder {
            run.append(layer)

            let hosted = HostedItem.collect(in: layer.node, parent: .identity, opacity: 1)

            guard !hosted.isEmpty else { continue }

            // A layer's own drawing goes under the views it holds.
            items.append(.drawing(index: runIndex, layers: run))
            items += hosted.map(SceneItem.hosted)
            run = []
            runIndex += 1
        }

        if !run.isEmpty {
            items.append(.drawing(index: runIndex, layers: run))
        }

        return items
    }
}

/// A hosted view, with where it ends up.
struct HostedItem: Identifiable {
    var id: String
    var content: HostedContent
    var size: Vec2
    var transform: SceneTransform
    var opacity: Double

    static func collect<State>(in node: SceneNode<State>, parent: SceneTransform, opacity: Double) -> [HostedItem] {
        let transform = parent + node.transform
        let combined = opacity * node.opacity
        var items: [HostedItem] = []

        if case .slot(let size) = node.shape, let content = node.hostedContent as? HostedContent {
            items.append(HostedItem(
                id: node.id ?? node.path,
                content: content,
                size: size,
                transform: transform,
                opacity: combined
            ))
        }

        return items + node.children.flatMap { collect(in: $0, parent: transform, opacity: combined) }
    }
}

/// Draws the engine's current scene. A view of its own so that it
/// observes `scene` and redraws whenever the engine publishes a frame.
struct SceneStack<State: Equatable>: View {
    let engine: DragEngine<State>

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            ForEach(SceneItem.items(in: engine.scene)) { item in
                switch item {
                case .drawing(_, let layers):
                    Canvas { context, _ in
                        SceneRenderer.draw(layers, in: context)
                    }
                    .allowsHitTesting(false)

                case .hosted(let hosted):
                    hosted.content.make()
                        .frame(width: hosted.size.x, height: hosted.size.y)
                        .transformEffect(CGAffineTransform(hosted.transform.affine))
                        .opacity(hosted.opacity)
                        .allowsHitTesting(hosted.content.interaction == .interactive)
                }
            }
        }
    }
}
