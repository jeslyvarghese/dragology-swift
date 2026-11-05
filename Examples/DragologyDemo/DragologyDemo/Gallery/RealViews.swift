import DragologySwift
import SwiftUI

struct FruitListState: Equatable {
    var names = ["Apples", "Bananas", "Cherries", "Dates"]

    func moving(from source: Int, to destination: Int) -> FruitListState {
        var copy = self
        copy.names.insert(copy.names.remove(at: source), at: destination)
        return copy
    }
}

private enum Metrics {
    static let cardWidth = 340.0
    static let cardHeight = 70.0
    static let pitch = 80.0
    static let cardCount = 4
    static let canvasHeight = pitch * Double(cardCount)
    static let filler = 24
    static let ghostOpacity = 0.3
}

/// An ordinary SwiftUI view, with state of its own and a working button.
private struct CounterCard: View {
    let name: String

    @State private var count = 0

    var body: some View {
        HStack {
            Text(name)
                .font(.headline)
                .accessibilityIdentifier("title-\(name)")

            Spacer()

            Text(String(count))
                .monospacedDigit()
                .accessibilityIdentifier("count-\(name)")

            Button("Add", systemImage: "plus") { count += 1 }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("add-\(name)")
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

private func fruitCards(_ context: SceneContext<FruitListState>) -> SceneNode<FruitListState> {
    let state = context.state

    return SceneGroup {
        for (index, name) in state.names.enumerated() {
            DragItem(width: Metrics.cardWidth, height: Metrics.cardHeight, interaction: .interactive) {
                CounterCard(name: name)
            }
            .id(name)
            .transform(.translate(0, Double(index) * Metrics.pitch))
            .zIndex(context.draggedID == name ? .absolute(1) : .relative(0))
            .onDrag {
                let orders = state.names.indices.map { state.moving(from: index, to: $0) }

                return context.drag.closest(orders)
                    .withFloating(FloatingOptions(ghostOpacity: Metrics.ghostOpacity))
            }
        }
    }
}

/// Real views, in a canvas, in a `ScrollView`. Swipes scroll the page, and
/// a long press picks up a card.
struct RealViewsScreen: View {
    @State private var state = FruitListState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hold a card to pick it up. Its counter is ordinary @State, and it keeps counting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(state.names.joined(separator: ","))
                    .font(.caption.monospaced())
                    .accessibilityIdentifier("realViewsOrder")

                DragCanvas(state: $state, scene: fruitCards)
                    .dragActivation(.longPress())
                    .frame(width: Metrics.cardWidth, height: Metrics.canvasHeight)

                ForEach(0..<Metrics.filler, id: \.self) { index in
                    Text("Row \(index + 1)").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}
