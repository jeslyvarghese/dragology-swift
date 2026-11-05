import DragologySwift
import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            // The demos draw with fixed colors, chosen for a light background.
            GalleryScreen()
                .preferredColorScheme(.light)
        }
    }
}

/// Lists every demo. Passing `-demo <title>` at launch opens one directly,
/// which is how the UI tests get to it.
struct GalleryScreen: View {
    private static let launchDemoKey = "demo"

    @State private var path: [String] = UserDefaults.standard
        .string(forKey: GalleryScreen.launchDemoKey)
        .map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(DemoCatalog.sections) { section in
                    Section(section.title) {
                        ForEach(section.demos) { demo in
                            NavigationLink(value: demo.title) {
                                VStack(alignment: .leading) {
                                    Text(demo.title)
                                    Text(demo.operators)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("dragology-swift")
            .navigationDestination(for: String.self) { title in
                DemoCatalog.demo(titled: title)?.makeView()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// The four controls from the first version of the demo.
struct ControlsScreen: View {
    private enum Layout {
        static let canvasWidth: CGFloat = 320
        static let toggleHeight: CGFloat = 70
        static let sliderHeight: CGFloat = 50
        static let dialHeight: CGFloat = 150
        static let listHeight: CGFloat = 200
        static let spacing: CGFloat = 8
    }

    @State private var toggleState = ToggleState()
    @State private var sliderState = SliderState()
    @State private var dialState = DialState()
    @State private var listState = ListState()

    var body: some View {
        VStack(spacing: Layout.spacing) {
            demo(
                title: toggleState.isOn ? "on" : "off",
                identifier: "toggle",
                height: Layout.toggleHeight
            ) {
                DraggableCanvas(state: $toggleState, draggable: toggleSwitch)
            }

            demo(
                title: String(Int(sliderState.value.rounded())),
                identifier: "slider",
                height: Layout.sliderHeight
            ) {
                DraggableCanvas(state: $sliderState, draggable: slider)
            }

            demo(
                title: "\(Int(dialState.degrees.rounded()))°",
                identifier: "dial",
                height: Layout.dialHeight
            ) {
                DraggableCanvas(state: $dialState, draggable: dial)
            }

            demo(
                title: listState.items.joined(separator: ","),
                identifier: "list",
                height: Layout.listHeight
            ) {
                DraggableCanvas(state: $listState, draggable: reorderableList)
            }
        }
        .padding()
    }

    private func demo<Content: View>(
        title: String,
        identifier: String,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text(title)
                .font(.caption.monospaced())
                .accessibilityIdentifier(identifier + "Value")

            content()
                .frame(width: Layout.canvasWidth, height: height)
                .accessibilityElement()
                .accessibilityIdentifier(identifier)
        }
    }
}
