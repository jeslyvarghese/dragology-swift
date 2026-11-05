import Foundation

public struct ClosestOptions: Sendable {
    /// Stay on the current option until another beats it by this many
    /// points, to stop flickering between near-equal options.
    public var stickiness: Double
    /// Once the active option carries the element this far from its
    /// start, lock onto it until it comes back within that distance.
    public var lockPast: Double?

    public init(stickiness: Double = 0, lockPast: Double? = nil) {
        self.stickiness = stickiness
        self.lockPast = lockPast
    }
}

/// Runs every option, and follows the one with the lowest gap.
final class ClosestOperator<State: Equatable>: Operator<State> {
    private static var emptySegment: String { "none" }

    private let options: [Operator<State>]
    private let settings: ClosestOptions
    /// Where the dragged element starts, for `lockPast`.
    private let home: Vec2?
    private var lastBest: Int?
    private var lockedIndex: Int?

    init(context: DragContext<State>, specs: [DragSpec<State>], options settings: ClosestOptions) {
        options = specs.map { $0.makeOperator(context) }
        self.settings = settings
        home = settings.lockPast == nil ? nil : context.position(in: context.startState)

        super.init(context: context, name: "closest")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        // With nothing to choose from, stay on the starting state. That
        // lets `closest(specs).whenFar(...)` work when `specs` is empty.
        guard !options.isEmpty else { return emptyResult() }

        // Options run lazily, so a locked frame only runs the locked one.
        var results: [Int: DragResult<State>] = [:]
        let resultAt = { [options] (index: Int) -> DragResult<State> in
            if let result = results[index] { return result }

            let result = options[index].run(frame).prefixingPath(String(index))
            results[index] = result
            return result
        }

        // Release a lock once the element comes back near home.
        if let locked = lockedIndex, !isPastLock(resultAt(locked)) {
            lockedIndex = nil
        }

        if let locked = lockedIndex {
            lastBest = locked
            return resultAt(locked)
        }

        // Favor the previous winner by the stickiness amount.
        let adjustedGap = { [lastBest, settings] (index: Int) -> Double in
            resultAt(index).gap - (index == lastBest ? settings.stickiness : 0)
        }
        let gaps = options.indices.map { ($0, adjustedGap($0)) }
        let best = gaps.min { $0.1 < $1.1 }?.0 ?? 0

        if isPastLock(resultAt(best)) {
            lockedIndex = best
        }

        lastBest = best

        return resultAt(best)
    }

    private func isPastLock(_ result: DragResult<State>) -> Bool {
        guard let home, let lockPast = settings.lockPast else { return false }

        // A preview without the dragged element counts as far from home.
        guard let position = result.grabPosition ?? context.position(in: result.preview.value) else {
            return true
        }

        return position.distance(to: home) > lockPast
    }

    private func emptyResult() -> DragResult<State> {
        let context = self.context

        var result = DragResult(
            preview: Lazy { context.render(context.startState) },
            dropState: context.startState,
            gap: .infinity
        )
        result.activePath = Self.emptySegment

        return result
    }
}
