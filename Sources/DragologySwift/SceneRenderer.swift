import DragologySwiftCore
import SwiftUI

/// Draws scene layers into a SwiftUI graphics context.
enum SceneRenderer {
    static func draw<State>(_ layers: [SceneLayer<State>], in context: GraphicsContext) {
        for layer in layers {
            draw(layer.node, in: context)
        }
    }

    private static func draw<State>(_ node: SceneNode<State>, in parent: GraphicsContext) {
        // The context is a value, so changes here stay in this subtree.
        var context = parent
        context.concatenate(CGAffineTransform(node.transform.affine))
        context.opacity *= node.opacity

        drawShape(node.shape, style: node.style, in: context)

        for child in node.children {
            draw(child, in: context)
        }
    }

    private static func drawShape(_ shape: SceneShape, style: SceneStyle, in context: GraphicsContext) {
        if case .text(let string, let size) = shape {
            drawText(string, size: size, style: style, in: context)
            return
        }

        guard let path = Path(shape) else { return }

        if let fill = style.fill {
            context.fill(path, with: .color(Color(fill)))
        }

        if let stroke = style.stroke {
            context.stroke(path, with: .color(Color(stroke)), lineWidth: style.lineWidth)
        }
    }

    private static func drawText(_ string: String, size: Double, style: SceneStyle, in context: GraphicsContext) {
        let color = Color(style.fill ?? .black)
        let text = Text(string).font(.system(size: size)).foregroundStyle(color)

        context.draw(text, at: .zero, anchor: .center)
    }
}

extension CGAffineTransform {
    init(_ affine: Affine) {
        self.init(a: affine.a, b: affine.b, c: affine.c, d: affine.d, tx: affine.tx, ty: affine.ty)
    }
}

private extension CGPoint {
    init(_ vector: Vec2) {
        self.init(x: vector.x, y: vector.y)
    }
}

private extension Color {
    init(_ color: SceneColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

private extension Path {
    /// Nil for shapes with no outline.
    init?(_ shape: SceneShape) {
        switch shape {
        case .none, .text, .slot:
            return nil

        case .rect(let size, let cornerRadius):
            let bounds = CGRect(x: 0, y: 0, width: size.x, height: size.y)
            self.init(roundedRect: bounds, cornerRadius: cornerRadius)

        case .circle(let radius):
            let diameter = radius * 2
            self.init(ellipseIn: CGRect(x: -radius, y: -radius, width: diameter, height: diameter))

        case .line(let from, let to):
            self.init()
            move(to: CGPoint(from))
            addLine(to: CGPoint(to))

        case .path(let commands):
            self.init()
            commands.forEach { add($0) }
        }
    }

    private mutating func add(_ command: PathCommand) {
        switch command {
        case .move(let point):
            move(to: CGPoint(point))

        case .line(let point):
            addLine(to: CGPoint(point))

        case .quad(let control, let end):
            addQuadCurve(to: CGPoint(end), control: CGPoint(control))

        case .cubic(let control1, let control2, let end):
            addCurve(to: CGPoint(end), control1: CGPoint(control1), control2: CGPoint(control2))

        case .close:
            closeSubpath()
        }
    }
}
