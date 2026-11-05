// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dragology-swift",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DragologySwift", targets: ["DragologySwift"]),
    ],
    targets: [
        // UI-independent: math, scene tree, drag operators, and the engine.
        .target(name: "DragologySwiftCore"),

        // SwiftUI host. Depends on the core, never the other way around.
        .target(name: "DragologySwift", dependencies: ["DragologySwiftCore"]),

        .testTarget(name: "DragologySwiftCoreTests", dependencies: ["DragologySwiftCore"]),
        .testTarget(name: "DragologySwiftTests", dependencies: ["DragologySwift"]),
    ]
)
