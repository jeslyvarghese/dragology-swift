import DragologySwift
import SwiftUI

struct BoardCard: Identifiable {
    var id: String
}

struct BoardColumn: Identifiable {
    var id: String
    var cards: [BoardCard]
}

/// An ordinary view. Nothing in it knows about dragging.
private struct BoardCardView: View {
    let card: BoardCard

    var body: some View {
        Text(card.id)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.background, in: .rect(cornerRadius: 8))
            .accessibilityIdentifier("card-\(card.id)")
    }
}

struct DragBoardScreen: View {
    @State private var columns = [
        BoardColumn(id: "Todo", cards: [BoardCard(id: "Design"), BoardCard(id: "Build the whole thing"), BoardCard(id: "Test")]),
        BoardColumn(id: "Doing", cards: [BoardCard(id: "Write")]),
        BoardColumn(id: "Done", cards: []),
    ]

    private var summary: String {
        columns.map { "\($0.id):" + $0.cards.map(\.id).joined(separator: "+") }.joined(separator: " ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hold a card to move it, within a column or to another one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(summary)
                    .font(.caption.monospaced())
                    .accessibilityIdentifier("boardOrder")

                DragBoard($columns, cards: \.cards) { column in
                    Text(column.id)
                        .font(.headline)
                        .accessibilityIdentifier("column-\(column.id)")
                } card: { card in
                    BoardCardView(card: card)
                }
            }
            .padding()
        }
    }
}
