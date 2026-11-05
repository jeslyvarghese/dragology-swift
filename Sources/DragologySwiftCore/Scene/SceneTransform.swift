import Foundation

/// A 2D affine matrix, mapping `(x, y)` to
/// `(a·x + c·y + tx, b·x + d·y + ty)`.
public struct Affine: Equatable, Sendable {
    public var a, b, c, d, tx, ty: Double

    public static let identity = Affine(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public func apply(to point: Vec2) -> Vec2 {
        Vec2(a * point.x + c * point.y + tx, b * point.x + d * point.y + ty)
    }

    /// The transform that applies `inner` first, then `self`.
    func concatenating(_ inner: Affine) -> Affine {
        Affine(
            a: a * inner.a + c * inner.b,
            b: b * inner.a + d * inner.b,
            c: a * inner.c + c * inner.d,
            d: b * inner.c + d * inner.d,
            tx: a * inner.tx + c * inner.ty + tx,
            ty: b * inner.tx + d * inner.ty + ty
        )
    }

    /// Nil for a singular matrix, such as a scale of zero.
    var inverted: Affine? {
        let determinant = a * d - b * c
        guard determinant != 0 else { return nil }

        return Affine(
            a: d / determinant,
            b: -b / determinant,
            c: -c / determinant,
            d: a / determinant,
            tx: (c * ty - d * tx) / determinant,
            ty: (b * tx - a * ty) / determinant
        )
    }

    static func lerp(_ p: Affine, _ q: Affine, _ t: Double) -> Affine {
        Affine(
            a: mix(p.a, q.a, t),
            b: mix(p.b, q.b, t),
            c: mix(p.c, q.c, t),
            d: mix(p.d, q.d, t),
            tx: mix(p.tx, q.tx, t),
            ty: mix(p.ty, q.ty, t)
        )
    }
}

/// A list of transform steps. As in SVG, the last step applies to a
/// point first: `.translate(x, y) + .rotate(degrees: 45)` spins an
/// element in place, then moves it.
///
/// Steps stay symbolic so that blending two transforms can turn an
/// angle through its arc, instead of cutting across it.
public struct SceneTransform: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case translate(Vec2)
        case rotate(degrees: Double, center: Vec2)
        case scale(Vec2)
        case matrix(Affine)
    }

    private enum Angle {
        static let fullTurn = 360.0
        static let halfTurn = 180.0
        static let radiansPerDegree = Double.pi / halfTurn
    }

    public var steps: [Step]

    public static let identity = SceneTransform(steps: [])

    public init(steps: [Step]) {
        self.steps = steps
    }

    public static func translate(_ x: Double, _ y: Double) -> SceneTransform {
        translate(Vec2(x, y))
    }

    public static func translate(_ offset: Vec2) -> SceneTransform {
        SceneTransform(steps: [.translate(offset)])
    }

    public static func rotate(degrees: Double, around center: Vec2 = .zero) -> SceneTransform {
        SceneTransform(steps: [.rotate(degrees: degrees, center: center)])
    }

    public static func scale(_ factor: Double) -> SceneTransform {
        SceneTransform(steps: [.scale(Vec2(factor, factor))])
    }

    public static func scale(x: Double, y: Double) -> SceneTransform {
        SceneTransform(steps: [.scale(Vec2(x, y))])
    }

    public static func + (outer: SceneTransform, inner: SceneTransform) -> SceneTransform {
        SceneTransform(steps: outer.steps + inner.steps)
    }

    /// This transform as one matrix.
    public var affine: Affine {
        steps.reduce(.identity) { $0.concatenating(Self.affine(for: $1)) }
    }

    /// Maps a point in this transform's local space to its parent space.
    public func localToGlobal(_ point: Vec2) -> Vec2 {
        affine.apply(to: point)
    }

    /// Maps a parent-space point into local space. Nil if singular.
    public func globalToLocal(_ point: Vec2) -> Vec2? {
        affine.inverted?.apply(to: point)
    }

    /// Blends step by step when the two lists line up. Otherwise blends
    /// matrices, which is always defined but doesn't preserve arcs.
    public static func lerp(_ a: SceneTransform, _ b: SceneTransform, _ t: Double) -> SceneTransform {
        if a == b { return a }

        let stepsA = a.collapsingTranslations().steps
        let stepsB = b.collapsingTranslations().steps

        if stepsA.count == stepsB.count {
            let blended = zip(stepsA, stepsB).map { lerpStep($0, $1, t) }

            if blended.allSatisfy({ $0 != nil }) {
                return SceneTransform(steps: blended.compactMap { $0 })
            }
        }

        return SceneTransform(steps: [.matrix(Affine.lerp(a.affine, b.affine, t))])
    }

    /// Nesting can give two renders different numbers of translations.
    private func collapsingTranslations() -> SceneTransform {
        var result: [Step] = []

        for step in steps {
            guard case .translate(let offset) = step,
                  case .translate(let previous)? = result.last else {
                result.append(step)
                continue
            }

            result[result.count - 1] = .translate(previous + offset)
        }

        return SceneTransform(steps: result)
    }

    private static func lerpStep(_ a: Step, _ b: Step, _ t: Double) -> Step? {
        switch (a, b) {
        case (.translate(let p), .translate(let q)):
            return .translate(Vec2.lerp(p, q, t))

        case (.rotate(let p, let centerP), .rotate(let q, let centerQ)):
            return .rotate(degrees: lerpDegrees(p, q, t), center: Vec2.lerp(centerP, centerQ, t))

        case (.scale(let p), .scale(let q)):
            return .scale(Vec2.lerp(p, q, t))

        case (.matrix(let p), .matrix(let q)):
            return .matrix(Affine.lerp(p, q, t))

        default:
            return nil
        }
    }

    /// Takes the short way around.
    private static func lerpDegrees(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let wrapped = (b - a + Angle.halfTurn)
            .truncatingRemainder(dividingBy: Angle.fullTurn)
        let positive = wrapped < 0 ? wrapped + Angle.fullTurn : wrapped

        return a + (positive - Angle.halfTurn) * t
    }

    private static func affine(for step: Step) -> Affine {
        switch step {
        case .translate(let offset):
            return Affine(a: 1, b: 0, c: 0, d: 1, tx: offset.x, ty: offset.y)

        case .scale(let factor):
            return Affine(a: factor.x, b: 0, c: 0, d: factor.y, tx: 0, ty: 0)

        case .matrix(let matrix):
            return matrix

        case .rotate(let degrees, let center):
            let radians = degrees * Angle.radiansPerDegree
            let cosine = cos(radians)
            let sine = sin(radians)
            let rotation = Affine(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)

            // Rotate about the center: move it to the origin and back.
            return affine(for: .translate(center))
                .concatenating(rotation)
                .concatenating(affine(for: .translate(center * -1)))
        }
    }
}
