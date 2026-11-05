// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dragology",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Dragology", targets: ["Dragology"]),
    ],
    targets: [
        // UI-independent: math, scene tree, drag operators, and the engine.
        .target(name: "DragologyCore"),

        // SwiftUI host. Depends on the core, never the other way around.
        .target(name: "Dragology", dependencies: ["DragologyCore"]),

        .testTarget(name: "DragologyCoreTests", dependencies: ["DragologyCore"]),
        .testTarget(name: "DragologyTests", dependencies: ["Dragology"]),
    ]
)
