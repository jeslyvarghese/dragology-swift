import Foundation

/// A point in an element's own coordinates, to be resolved once the
/// scene is assembled and the element's final position is known.
public struct PointRef: Sendable {
    public var elementID: String
    public var local: Vec2

    public init(_ elementID: String, _ local: Vec2 = .zero) {
        self.elementID = elementID
        self.local = local
    }
}

/// Collects drawing that has to wait until the whole tree is built, such
/// as edges between elements laid out in different parts of it.
public final class Finalizers<State: Equatable> {
    public typealias Resolve = (PointRef) -> Vec2

    private var pending: [(Resolve) -> Node<State>] = []

    public init() {}

    public func add(_ draw: @escaping (Resolve) -> Node<State>) {
        pending.append(draw)
    }

    /// Draws everything that was deferred, against the finished `tree`.
    public func run(against tree: Node<State>) -> [Node<State>] {
        let resolve: Resolve = { reference in
            guard let found = tree.find(where: { $0.id == reference.elementID }) else {
                preconditionFailure("No element has the id \"\(reference.elementID)\".")
            }

            return found.transform.localToGlobal(reference.local)
        }

        return pending.map { $0(resolve) }
    }
}
