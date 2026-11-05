import Foundation

/// Rebuilds its spec whenever a watched value changes.
final class ReactToOperator<State: Equatable, Value: Equatable>: Operator<State> {
    private let value: () -> Value
    private let makeSpec: (Value) -> DragSpec<State>
    private var current: (value: Value, behavior: Operator<State>)?

    init(
        context: DragContext<State>,
        value: @escaping () -> Value,
        makeSpec: @escaping (Value) -> DragSpec<State>
    ) {
        self.value = value
        self.makeSpec = makeSpec

        super.init(context: context, name: "reactTo")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        let latest = value()

        if let current, current.value == latest {
            return current.behavior.run(frame)
        }

        let behavior = makeSpec(latest).makeOperator(context)
        current = (latest, behavior)

        return behavior.run(frame)
    }
}
