import DragologySwift
import SwiftUI

struct TaskItem: Identifiable {
    var id: String
    var detail: String
}

/// An ordinary row. Nothing in it knows about dragging.
private struct TaskRow: View {
    let task: TaskItem

    @State private var isDone = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(task.id).font(.headline)

                Text(task.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("task-\(task.id)")
            }

            Spacer()

            Toggle("Done", isOn: $isDone)
                .labelsHidden()
                .accessibilityIdentifier("done-\(task.id)")
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}

struct DragListScreen: View {
    private enum Metrics {
        static let filler = 24
    }

    @State private var tasks = [
        TaskItem(id: "Call", detail: "The dentist"),
        TaskItem(id: "Plan", detail: "The whole trip, including where to stay, what to see, and how to get from each place to the next one without missing a connection"),
        TaskItem(id: "Pack", detail: "Bags"),
        TaskItem(id: "Read", detail: "A chapter"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hold a row to move it. This is the whole integration: a binding and a row.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(tasks.map(\.id).joined(separator: ","))
                    .font(.caption.monospaced())
                    .accessibilityIdentifier("dragListOrder")

                DragList($tasks) { task in
                    TaskRow(task: task)
                }

                ForEach(0..<Metrics.filler, id: \.self) { index in
                    Text("Row \(index + 1)").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}
