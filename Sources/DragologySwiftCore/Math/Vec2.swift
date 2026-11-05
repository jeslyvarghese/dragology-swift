import Foundation

/// A 2D point or vector, in canvas coordinates.
public struct Vec2: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public static let zero = Vec2(0, 0)

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }

    public var lengthSquared: Double { x * x + y * y }
    public var length: Double { lengthSquared.squareRoot() }
    public var isFinite: Bool { x.isFinite && y.isFinite }

    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    public func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }
    public func distance(to other: Vec2) -> Double { (self - other).length }
    public func distanceSquared(to other: Vec2) -> Double { (self - other).lengthSquared }

    public static func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 {
        Vec2(mix(a.x, b.x, t), mix(a.y, b.y, t))
    }
}

/// Linear interpolation between two numbers.
@inline(__always)
func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}
