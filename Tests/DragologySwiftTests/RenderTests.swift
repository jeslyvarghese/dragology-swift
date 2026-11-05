import CoreGraphics
import SwiftUI
import Testing
@testable import DragologySwift

private struct Empty: Equatable {}

private enum Fixture {
    static let side = 100
    static let tolerance = 2
}

@Suite struct DragListLayoutTests {
    private func layout() -> DragListLayout<String> {
        var layout = DragListLayout(ids: ["a", "b", "c"], spacing: 10)
        layout.heights = ["a": 50, "b": 100, "c": 30]
        return layout
    }

    @Test func rowsStackByTheirOwnHeights() {
        let layout = layout()

        #expect(layout.offset(at: 0) == 0)
        #expect(layout.offset(at: 1) == 60)
        #expect(layout.offset(at: 2) == 170)
        #expect(layout.totalHeight == 200)
    }

    @Test func unmeasuredRowsUseAnEstimate() {
        let layout = DragListLayout(ids: ["a", "b"], spacing: 0)

        #expect(layout.height(of: "a") > 0)
        #expect(layout.offset(at: 1) == layout.height(of: "a"))
    }

    @Test func movingKeepsHeightsWithTheirRows() {
        let moved = layout().moving(from: 0, to: 2)

        #expect(moved.ids == ["b", "c", "a"])
        #expect(moved.offset(at: 2) == 150)
    }

    @Test func voiceOverMovesStopAtTheEnds() {
        let layout = layout()

        #expect(layout.stepMoves(from: 0).map(\.name) == ["Move down"])
        #expect(layout.stepMoves(from: 1).map(\.name) == ["Move up", "Move down"])
        #expect(layout.stepMoves(from: 2).map(\.name) == ["Move up"])
        #expect(layout.stepMoves(from: 1)[0].layout.ids == ["b", "a", "c"])
    }

    @Test func anEmptyListHasNoHeight() {
        #expect(DragListLayout<String>(ids: [], spacing: 10).totalHeight == 0)
    }
}

/// The toggle from the docs and the site, word for word.
private struct ToggleState: Equatable {
    var isOn = false
}

private func toggle(_ context: SceneContext<ToggleState>) -> SceneNode<ToggleState> {
    SceneGroup {
        SceneRect(width: 120, height: 60, cornerRadius: 30)
            .fill(context.state.isOn ? SceneColor(hex: 0x22C55E) : SceneColor(hex: 0xD1D5DB))

        SceneCircle(radius: 26)
            .id("knob")
            .fill(.white)
            .transform(.translate(context.state.isOn ? 90 : 30, 30))
            .onDrag {
                context.drag.between([ToggleState(isOn: false), ToggleState(isOn: true)])
            }
    }
}

/// Draws scenes offscreen and inspects the pixels they produce.
@Suite struct RenderTests {
    /// The color at a point, as 8-bit SceneColor.
    @MainActor
    private func pixel<V: View>(of view: V, x: Int, y: Int) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view)
        let image = try #require(renderer.cgImage)

        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        // Shift the image so the wanted pixel lands on the 1x1 bitmap.
        context.draw(image, in: CGRect(
            x: -x,
            y: y - image.height + 1,
            width: image.width,
            height: image.height
        ))

        return bytes
    }

    @MainActor
    private func canvas(_ root: @escaping () -> SceneNode<Empty>) -> some View {
        DragCanvas(state: .constant(Empty())) { _ in root() }
            .frame(width: CGFloat(Fixture.side), height: CGFloat(Fixture.side))
    }

    @Test func theDocumentedToggleWorks() {
        let engine = DragEngine(state: ToggleState(), scene: toggle)

        engine.pointerDown(at: Vec2(30, 30), now: 0)
        engine.pointerMoved(to: Vec2(85, 30), now: 0)
        engine.tick(now: 0)
        engine.pointerUp(at: Vec2(85, 30), now: 0)

        #expect(engine.state.isOn)
    }

    @MainActor
    @Test func shapesLandWhereTheirTransformsSay() throws {
        let view = canvas {
            SceneRect(width: 20, height: 20)
                .fill(SceneColor(hex: 0xFF0000))
                .transform(.translate(60, 10))
        }

        let inside = try pixel(of: view, x: 70, y: 20)
        let outside = try pixel(of: view, x: 20, y: 70)

        #expect(inside[0] > 250 && inside[3] > 250)
        #expect(outside[3] == 0)
    }

    @MainActor
    @Test func laterLayersDrawOnTop() throws {
        let view = canvas {
            SceneGroup {
                SceneRect(width: 100, height: 100).id("top").fill(SceneColor(hex: 0x00FF00)).zIndex(.relative(1))
                SceneRect(width: 100, height: 100).id("bottom").fill(SceneColor(hex: 0xFF0000))
            }
        }

        let color = try pixel(of: view, x: 50, y: 50)

        #expect(color[1] > 250 && color[0] < 5)
    }

    @MainActor
    @Test func opacityReachesThePixels() throws {
        let view = canvas {
            SceneRect(width: 100, height: 100).fill(.black).opacity(0.5)
        }

        let color = try pixel(of: view, x: 50, y: 50)

        #expect(abs(Int(color[3]) - 128) <= Fixture.tolerance)
    }
}
