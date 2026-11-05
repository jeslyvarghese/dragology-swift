import Foundation

/// An sRGB color with alpha, each component in `0...1`.
public struct SceneColor: Equatable, Sendable {
    public var red, green, blue, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// From a `0xRRGGBB` literal.
    public init(hex: UInt32, alpha: Double = 1) {
        let channelMask: UInt32 = 0xFF
        let channelMax = Double(channelMask)
        let redShift: UInt32 = 16
        let greenShift: UInt32 = 8

        self.init(
            red: Double((hex >> redShift) & channelMask) / channelMax,
            green: Double((hex >> greenShift) & channelMask) / channelMax,
            blue: Double(hex & channelMask) / channelMax,
            alpha: alpha
        )
    }

    public static let black = SceneColor(red: 0, green: 0, blue: 0)
    public static let white = SceneColor(red: 1, green: 1, blue: 1)
    public static let clear = SceneColor(red: 0, green: 0, blue: 0, alpha: 0)

    var transparent: SceneColor {
        var copy = self
        copy.alpha = 0
        return copy
    }

    static func lerp(_ a: SceneColor, _ b: SceneColor, _ t: Double) -> SceneColor {
        SceneColor(
            red: mix(a.red, b.red, t),
            green: mix(a.green, b.green, t),
            blue: mix(a.blue, b.blue, t),
            alpha: mix(a.alpha, b.alpha, t)
        )
    }

    /// A missing color blends as the other color, faded out.
    static func lerpOptional(_ a: SceneColor?, _ b: SceneColor?, _ t: Double) -> SceneColor? {
        switch (a, b) {
        case (nil, nil):
            return nil
        case (let a?, nil):
            return lerp(a, a.transparent, t)
        case (nil, let b?):
            return lerp(b.transparent, b, t)
        case (let a?, let b?):
            return lerp(a, b, t)
        }
    }
}

/// How a shape is painted.
public struct SceneStyle: Equatable, Sendable {
    public var fill: SceneColor?
    public var stroke: SceneColor?
    public var lineWidth: Double

    public init(fill: SceneColor? = nil, stroke: SceneColor? = nil, lineWidth: Double = 1) {
        self.fill = fill
        self.stroke = stroke
        self.lineWidth = lineWidth
    }

    static func lerp(_ a: SceneStyle, _ b: SceneStyle, _ t: Double) -> SceneStyle {
        SceneStyle(
            fill: SceneColor.lerpOptional(a.fill, b.fill, t),
            stroke: SceneColor.lerpOptional(a.stroke, b.stroke, t),
            lineWidth: mix(a.lineWidth, b.lineWidth, t)
        )
    }
}

/// One segment of a `SceneShape.path`.
public enum PathCommand: Equatable, Sendable {
    case move(Vec2)
    case line(Vec2)
    case quad(control: Vec2, end: Vec2)
    case cubic(control1: Vec2, control2: Vec2, end: Vec2)
    case close

    var points: [Vec2] {
        switch self {
        case .move(let point), .line(let point):
            return [point]
        case .quad(let control, let end):
            return [control, end]
        case .cubic(let control1, let control2, let end):
            return [control1, control2, end]
        case .close:
            return []
        }
    }

    /// How finely curves are divided when flattened.
    private static var curveSamples: Int { 12 }

    /// A path as a run of points, with its curves flattened.
    static func flattened(_ commands: [PathCommand]) -> [Vec2] {
        var points: [Vec2] = []

        for command in commands {
            switch command {
            case .move(let point), .line(let point):
                points.append(point)

            case .quad(let control, let end):
                guard let start = points.last else { continue }

                points += sampledCurve { t in
                    let u = 1 - t
                    return start * (u * u) + control * (2 * u * t) + end * (t * t)
                }

            case .cubic(let control1, let control2, let end):
                guard let start = points.last else { continue }

                points += sampledCurve { t in
                    let u = 1 - t
                    let first = start * (u * u * u) + control1 * (3 * u * u * t)
                    return first + control2 * (3 * u * t * t) + end * (t * t * t)
                }

            case .close:
                continue
            }
        }

        return points
    }

    private static func sampledCurve(_ point: (Double) -> Vec2) -> [Vec2] {
        (1...curveSamples).map { point(Double($0) / Double(curveSamples)) }
    }

    /// `count` points spaced evenly along a run of points.
    static func resampled(_ points: [Vec2], count: Int) -> [Vec2] {
        let lengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
        let total = lengths.reduce(0, +)

        guard total > 0, let first = points.first else {
            return Array(repeating: points.first ?? .zero, count: count)
        }

        var result = [first]
        var segment = 0
        var passed = 0.0

        for index in 1..<count {
            let target = total * Double(index) / Double(count - 1)

            while segment < lengths.count - 1, passed + lengths[segment] < target {
                passed += lengths[segment]
                segment += 1
            }

            let span = lengths[segment]
            let t = span > 0 ? (target - passed) / span : 0

            result.append(Vec2.lerp(points[segment], points[segment + 1], min(t, 1)))
        }

        return result
    }

    /// Nil unless the commands are the same kind.
    static func lerp(_ a: PathCommand, _ b: PathCommand, _ t: Double) -> PathCommand? {
        switch (a, b) {
        case (.move(let p), .move(let q)):
            return .move(Vec2.lerp(p, q, t))

        case (.line(let p), .line(let q)):
            return .line(Vec2.lerp(p, q, t))

        case (.quad(let c, let p), .quad(let d, let q)):
            return .quad(control: Vec2.lerp(c, d, t), end: Vec2.lerp(p, q, t))

        case (.cubic(let c1, let c2, let p), .cubic(let d1, let d2, let q)):
            return .cubic(
                control1: Vec2.lerp(c1, d1, t),
                control2: Vec2.lerp(c2, d2, t),
                end: Vec2.lerp(p, q, t)
            )

        case (.close, .close):
            return .close

        default:
            return nil
        }
    }
}

/// An axis-aligned box.
struct Bounds: Equatable {
    var min: Vec2
    var max: Vec2

    init(min: Vec2, max: Vec2) {
        self.min = min
        self.max = max
    }

    /// The box around some points. Nil if there are none.
    init?(around points: [Vec2]) {
        let xs = points.map(\.x)
        let ys = points.map(\.y)

        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }

        self.init(min: Vec2(minX, minY), max: Vec2(maxX, maxY))
    }

    func contains(_ point: Vec2) -> Bool {
        point.x >= min.x && point.x <= max.x && point.y >= min.y && point.y <= max.y
    }

    /// The box around this one, after a transform.
    func transformed(by transform: SceneTransform) -> Bounds {
        let corners = [min, Vec2(max.x, min.y), max, Vec2(min.x, max.y)]

        return Bounds(around: corners.map(transform.localToGlobal)) ?? self
    }

    static func union(_ a: Bounds?, _ b: Bounds?) -> Bounds? {
        guard let a else { return b }
        guard let b else { return a }

        return Bounds(around: [a.min, a.max, b.min, b.max])
    }
}

/// What a node draws. Rects grow from the origin; circles and text
/// are centered on it. Position them with the node's transform.
public enum SceneShape: Equatable, Sendable {
    case none
    case rect(size: Vec2, cornerRadius: Double)
    case circle(radius: Double)
    case line(from: Vec2, to: Vec2)
    case path([PathCommand])
    case text(String, size: Double)
    /// A space held for content the host draws, such as a SwiftUI view.
    /// It grows from the origin, like a rect.
    case slot(size: Vec2)

    private enum Metrics {
        /// Lines are thin, so grabbing one needs this much slack.
        static let minLineHitRadius = 12.0
        /// Average glyph width, relative to font size, for text hits.
        static let glyphWidthRatio = 0.6
    }

    /// Blends matching shapes. Anything else switches over at the halfway
    /// point, as there's no meaningful in-between.
    static func lerp(_ a: SceneShape, _ b: SceneShape, _ t: Double) -> SceneShape {
        let halfway = 0.5
        let nearest = t < halfway ? a : b

        switch (a, b) {
        case (.rect(let p, let r), .rect(let q, let s)):
            return .rect(size: Vec2.lerp(p, q, t), cornerRadius: mix(r, s, t))

        case (.slot(let p), .slot(let q)):
            return .slot(size: Vec2.lerp(p, q, t))

        case (.circle(let r), .circle(let s)):
            return .circle(radius: mix(r, s, t))

        case (.line(let p1, let p2), .line(let q1, let q2)):
            return .line(from: Vec2.lerp(p1, q1, t), to: Vec2.lerp(p2, q2, t))

        case (.path(let p), .path(let q)):
            let blended = zip(p, q).compactMap { PathCommand.lerp($0, $1, t) }

            if p.count == q.count, blended.count == p.count {
                return .path(blended)
            }

            return lerpResampled(p, q, t) ?? nearest

        case (.text(let p, let r), .text(let q, let s)):
            return .text(t < halfway ? p : q, size: mix(r, s, t))

        default:
            return nearest
        }
    }

    /// Blends paths of different structures, by giving both the same
    /// number of points. Nil if either has too few points to measure.
    private static func lerpResampled(_ a: [PathCommand], _ b: [PathCommand], _ t: Double) -> SceneShape? {
        let minPoints = 2
        let pointsA = PathCommand.flattened(a)
        let pointsB = PathCommand.flattened(b)

        guard pointsA.count >= minPoints, pointsB.count >= minPoints else { return nil }

        let count = max(pointsA.count, pointsB.count)
        let blended = zip(
            PathCommand.resampled(pointsA, count: count),
            PathCommand.resampled(pointsB, count: count)
        ).map { Vec2.lerp($0, $1, t) }

        guard let first = blended.first else { return nil }

        let isClosed = a.last == .close && b.last == .close
        let lines = blended.dropFirst().map(PathCommand.line)

        return .path([.move(first)] + lines + (isClosed ? [.close] : []))
    }

    /// The box this shape occupies, in local coordinates.
    var localBounds: Bounds? {
        switch self {
        case .none:
            return nil

        case .rect(let size, _), .slot(let size):
            // A solver can leave a size a hair below zero.
            return Bounds(around: [.zero, size])

        case .circle(let radius):
            return Bounds(min: Vec2(-radius, -radius), max: Vec2(radius, radius))

        case .line(let from, let to):
            return Bounds(around: [from, to])

        case .path(let commands):
            return Bounds(around: commands.flatMap(\.points))

        case .text(let string, let size):
            let halfWidth = Double(string.count) * size * Metrics.glyphWidthRatio / 2
            return Bounds(min: Vec2(-halfWidth, -size / 2), max: Vec2(halfWidth, size / 2))
        }
    }

    /// Whether a point in local coordinates lands on this shape. As in
    /// SVG, an outline with no fill doesn't catch touches inside it.
    func contains(_ point: Vec2, style: SceneStyle) -> Bool {
        switch self {
        case .none:
            return false

        case .line(let from, let to):
            let hitRadius = max(style.lineWidth / 2, Metrics.minLineHitRadius)
            return Self.distance(from: point, toSegment: from, to) <= hitRadius

        case .text, .slot:
            return localBounds?.contains(point) ?? false

        case .circle(let radius):
            return style.fill != nil && point.length <= radius

        case .rect:
            return style.fill != nil && (localBounds?.contains(point) ?? false)

        case .path(let commands):
            return style.fill != nil && Self.polygon(PathCommand.flattened(commands), contains: point)
        }
    }

    /// Ray casting: a point is inside if a ray from it crosses the outline
    /// an odd number of times. Open paths are closed by a straight line.
    private static func polygon(_ points: [Vec2], contains point: Vec2) -> Bool {
        var isInside = false

        for (index, current) in points.enumerated() {
            let next = points[(index + 1) % points.count]

            guard (current.y > point.y) != (next.y > point.y) else { continue }

            let crossingX = current.x + (point.y - current.y) / (next.y - current.y) * (next.x - current.x)

            if point.x < crossingX {
                isInside.toggle()
            }
        }

        return isInside
    }

    private static func distance(from point: Vec2, toSegment start: Vec2, _ end: Vec2) -> Double {
        let span = end - start
        guard span.lengthSquared > 0 else { return point.distance(to: start) }

        let t = min(max((point - start).dot(span) / span.lengthSquared, 0), 1)
        return point.distance(to: start + span * t)
    }
}
