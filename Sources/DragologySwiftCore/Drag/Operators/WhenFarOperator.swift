import Foundation

/// When `whenFar` hands over to the background. A separate `outward`
/// and `inward` distance adds hysteresis, so it doesn't flicker.
public struct WhenFarGap: Sendable {
    private static let standardDistance = 50.0

    public var inward: Double
    public var outward: Double

    public static let standard = WhenFarGap(standardDistance)

    public init(_ distance: Double) {
        inward = distance
        outward = distance
    }

    public init(inward: Double, outward: Double) {
        precondition(inward <= outward, "whenFar: inward must not exceed outward, or it oscillates.")

        self.inward = inward
        self.outward = outward
    }
}

private enum WhenFarSegment {
    static let foreground = "foreground"
    static let background = "background"
}

/// Follows the foreground, or the background when it's too far away.
final class WhenFarOperator<State: Equatable>: DragOperator<State> {
    private let foreground: DragOperator<State>
    private let background: DragOperator<State>
    private let gap: WhenFarGap
    private var isInForeground = true

    init(
        context: DragContext<State>,
        foreground: DragSpec<State>,
        background: DragSpec<State>,
        gap: WhenFarGap
    ) {
        self.foreground = foreground.makeOperator(context)
        self.background = background.makeOperator(context)
        self.gap = gap

        super.init(context: context, name: "whenFar")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        let foregroundResult = foreground.run(frame)
        let threshold = isInForeground ? gap.outward : gap.inward

        isInForeground = foregroundResult.gap <= threshold

        guard isInForeground else {
            return background.run(frame).prefixingPath(WhenFarSegment.background)
        }

        return foregroundResult.prefixingPath(WhenFarSegment.foreground)
    }
}
