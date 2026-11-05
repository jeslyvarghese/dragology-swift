import CoreGraphics
import SwiftUI
import Testing
@testable import Dragology

private struct Empty: Equatable {}

private enum Fixture {
    static let side = 100
    static let tolerance = 2
}

/// The toggle from the docs and the site, word for word.
private struct ToggleState: Equatable {
    var isOn = false
}

private func toggle(_ context: RenderContext<ToggleState>) -> Node<ToggleState> {
    group {
        rect(width: 120, height: 60, cornerRadius: 30)
            .fill(context.state.isOn ? RGBA(hex: 0x22C55E) : RGBA(hex: 0xD1D5DB))

        circle(radius: 26)
            .id("knob")
            .fill(.white)
            .transform(.translate(context.state.isOn ? 90 : 30, 30))
            .onDrag {
                context.d.between([ToggleState(isOn: false), ToggleState(isOn: true)])
            }
    }
}

/// Draws scenes offscreen and inspects the pixels they produce.
@Suite struct RenderTests {
    /// The color at a point, as 8-bit RGBA.
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
    private func canvas(_ root: @escaping () -> Node<Empty>) -> some View {
        DraggableCanvas(state: .constant(Empty())) { _ in root() }
            .frame(width: CGFloat(Fixture.side), height: CGFloat(Fixture.side))
    }

    @Test func theDocumentedToggleWorks() {
        let engine = DragEngine(state: ToggleState(), draggable: toggle)

        engine.pointerDown(at: Vec2(30, 30), now: 0)
        engine.pointerMoved(to: Vec2(85, 30), now: 0)
        engine.tick(now: 0)
        engine.pointerUp(at: Vec2(85, 30), now: 0)

        #expect(engine.state.isOn)
    }

    @MainActor
    @Test func shapesLandWhereTheirTransformsSay() throws {
        let view = canvas {
            rect(width: 20, height: 20)
                .fill(RGBA(hex: 0xFF0000))
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
            group {
                rect(width: 100, height: 100).id("top").fill(RGBA(hex: 0x00FF00)).zIndex(.relative(1))
                rect(width: 100, height: 100).id("bottom").fill(RGBA(hex: 0xFF0000))
            }
        }

        let color = try pixel(of: view, x: 50, y: 50)

        #expect(color[1] > 250 && color[0] < 5)
    }

    @MainActor
    @Test func opacityReachesThePixels() throws {
        let view = canvas {
            rect(width: 100, height: 100).fill(.black).opacity(0.5)
        }

        let color = try pixel(of: view, x: 50, y: 50)

        #expect(abs(Int(color[3]) - 128) <= Fixture.tolerance)
    }
}
