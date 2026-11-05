import Foundation

/// How an animated change plays out over time.
public struct DragTransition: Sendable {
    public enum Easing: Sendable {
        case cubicOut
        case elasticOut
        case custom(@Sendable (Double) -> Double)
    }

    private enum Elastic {
        static let period = 0.3 / (2 * Double.pi)
        static let phase = Double.pi / 2 * period
        static let decayRate = -10.0
        /// Shifts and rescales the decay so that it ends at exactly zero.
        static let decayFloor = 0.0009765625
        static let decayScale = 1.0009775171065494
    }

    private static let standardDuration: TimeInterval = 0.2

    public var easing: Easing
    public var duration: TimeInterval

    public static let standard = DragTransition(easing: .cubicOut, duration: standardDuration)

    public init(easing: Easing, duration: TimeInterval) {
        self.easing = easing
        self.duration = duration
    }

    /// The default duration, with a different easing.
    public static func easing(_ easing: Easing) -> DragTransition {
        DragTransition(easing: easing, duration: standardDuration)
    }

    /// Progress after `elapsed` seconds. Elastic easing overshoots 1.
    func progress(elapsed: TimeInterval) -> Double {
        let t = min(max(elapsed / duration, 0), 1)

        switch easing {
        case .cubicOut:
            let remaining = 1 - t
            return 1 - remaining * remaining * remaining

        case .elasticOut:
            let decay = (pow(2, Elastic.decayRate * t) - Elastic.decayFloor) * Elastic.decayScale
            return 1 - decay * sin((t + Elastic.phase) / Elastic.period)

        case .custom(let function):
            return function(t)
        }
    }
}
