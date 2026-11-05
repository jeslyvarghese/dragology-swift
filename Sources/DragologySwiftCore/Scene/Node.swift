import Foundation

/// Where a layer stacks: relative to its parent layer, or absolutely,
/// escaping the hierarchy (`.absolute(1)` brings a dragged item forward).
public enum ZIndex: Equatable, Sendable {
    case relative(Int)
    case absolute(Int)
}

/// Whether animated transitions apply to a node's layer.
public enum TransitionPolicy: Sendable {
    case animated
    /// Always shows the latest position, for things tracking a finger.
    case immediate
}

/// Whether a node can receive touches.
public enum HitTesting: Sendable {
    case enabled
    case disabled
}

/// How a layer appears from another layer, as it comes into existence.
public enum EmergeMode: Sendable {
    /// Grows out of the origin from nothing, fading in.
    case scale
    /// Starts as a full-size copy sitting on the origin, then splits off.
    case clone
    /// Fades in from the size of the origin's box, for box-and-label nodes.
    /// Grows from nothing, like `scale`, if either has no box.
    case morph
}

/// One element of a scene: Dragology's equivalent of an SVG element.
///
/// SwiftUI views are opaque, so they can't be rendered speculatively,
/// measured, or blended. A `Node` tree is plain data that can.
public struct Node<State: Equatable> {
    /// Identity across renders. Nodes with an id become separate layers,
    /// which can be blended, re-parented, and restacked independently.
    public var id: String?
    /// Pins this node's slot among its siblings, without making a layer.
    public var key: String?
    public var transform: Transform = .identity
    public var opacity: Double = 1
    public var zIndex: ZIndex = .relative(0)
    public var shape: Shape = .none
    public var style = Style()
    public var children: [Node] = []
    public var onDrag: (() -> DragSpec<State>)?
    public var onTap: (() -> Void)?
    public var transitionPolicy: TransitionPolicy = .animated
    public var hitTesting: HitTesting = .enabled
    /// The layer this one grows out of, when a blend has no earlier
    /// version of it. Without this, a new layer simply fades in.
    public var emergeOrigin: String?
    public var emergeMode: EmergeMode = .scale

    /// A stable address, for dragged nodes without an id.
    var path = ""

    public init(shape: Shape = .none, children: [Node] = []) {
        self.shape = shape
        self.children = children
    }
}

// MARK: - Modifiers

extension Node {
    private func with(_ change: (inout Node) -> Void) -> Node {
        var copy = self
        change(&copy)
        return copy
    }

    public func id(_ id: String) -> Node { with { $0.id = id } }
    public func key(_ key: String) -> Node { with { $0.key = key } }
    public func transform(_ transform: Transform) -> Node { with { $0.transform = transform } }
    public func opacity(_ opacity: Double) -> Node { with { $0.opacity = opacity } }
    public func zIndex(_ zIndex: ZIndex) -> Node { with { $0.zIndex = zIndex } }
    public func fill(_ color: RGBA?) -> Node { with { $0.style.fill = color } }

    public func stroke(_ color: RGBA?, lineWidth: Double = 1) -> Node {
        with {
            $0.style.stroke = color
            $0.style.lineWidth = lineWidth
        }
    }

    public func hitTesting(_ hitTesting: HitTesting) -> Node { with { $0.hitTesting = hitTesting } }

    /// Makes this node draggable. The closure runs when a drag starts.
    public func onDrag(_ spec: @escaping () -> DragSpec<State>) -> Node {
        with { $0.onDrag = spec }
    }

    public func onTap(_ action: @escaping () -> Void) -> Node { with { $0.onTap = action } }

    /// Makes this layer grow out of `origin` when it first appears.
    public func emergeFrom(_ origin: String?, mode: EmergeMode = .scale) -> Node {
        with {
            $0.emergeOrigin = origin
            $0.emergeMode = mode
        }
    }
}

// MARK: - Building

/// Builds a node's children, with the usual `if` and `for` support.
@resultBuilder
public enum NodeBuilder<State: Equatable> {
    public static func buildExpression(_ node: Node<State>) -> [Node<State>] { [node] }
    public static func buildBlock(_ parts: [Node<State>]...) -> [Node<State>] { parts.flatMap { $0 } }
    public static func buildArray(_ parts: [[Node<State>]]) -> [Node<State>] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [Node<State>]?) -> [Node<State>] { part ?? [] }
    public static func buildEither(first part: [Node<State>]) -> [Node<State>] { part }
    public static func buildEither(second part: [Node<State>]) -> [Node<State>] { part }
}

public func group<State>(@NodeBuilder<State> _ content: () -> [Node<State>]) -> Node<State> {
    Node(children: content())
}

public func rect<State>(width: Double, height: Double, cornerRadius: Double = 0) -> Node<State> {
    Node(shape: .rect(size: Vec2(width, height), cornerRadius: cornerRadius))
}

public func circle<State>(radius: Double) -> Node<State> {
    Node(shape: .circle(radius: radius))
}

public func line<State>(from: Vec2, to: Vec2) -> Node<State> {
    Node(shape: .line(from: from, to: to))
}

public func path<State>(_ commands: [PathCommand]) -> Node<State> {
    Node(shape: .path(commands))
}

public func label<State>(_ string: String, size: Double) -> Node<State> {
    Node(shape: .text(string, size: size))
}

// MARK: - Changing state types

extension Node {
    /// This tree for a different state type. `lift` converts drag
    /// handlers; without it they're dropped, which suits inert previews.
    func retyped<Other>(
        lift: ((@escaping () -> DragSpec<State>) -> () -> DragSpec<Other>)? = nil
    ) -> Node<Other> {
        var copy = Node<Other>(shape: shape, children: children.map { $0.retyped(lift: lift) })

        copy.id = id
        copy.key = key
        copy.transform = transform
        copy.opacity = opacity
        copy.zIndex = zIndex
        copy.style = style
        copy.onTap = onTap
        copy.transitionPolicy = transitionPolicy
        copy.hitTesting = hitTesting
        copy.emergeOrigin = emergeOrigin
        copy.emergeMode = emergeMode
        copy.path = path

        if let onDrag, let lift {
            copy.onDrag = lift(onDrag)
        }

        return copy
    }
}

// MARK: - Tree queries

extension Node {
    private static var rootPath: String { "/" }
    private static var pathSeparator: String { "/" }

    /// Gives every node a stable path. An id restarts the path, so a node
    /// keeps its address when it moves around the tree.
    func assigningPaths() -> Node {
        assigningPaths(at: Self.rootPath)
    }

    private func assigningPaths(at inheritedPath: String) -> Node {
        var copy = self
        copy.path = id.map { $0 + Self.pathSeparator } ?? inheritedPath

        var unkeyedIndex = 0

        copy.children = children.map { child in
            guard let key = child.key else {
                defer { unkeyedIndex += 1 }
                return child.assigningPaths(
                    at: copy.path + String(unkeyedIndex) + Self.pathSeparator
                )
            }

            return child.assigningPaths(at: copy.path + key + Self.pathSeparator)
        }

        return copy
    }

    /// Finds the first match, along with its full transform from the root.
    func find(
        parentTransform: Transform = .identity,
        where matches: (Node) -> Bool
    ) -> (node: Node, transform: Transform)? {
        let accumulated = parentTransform + transform

        if matches(self) {
            return (self, accumulated)
        }

        for child in children {
            if let found = child.find(parentTransform: accumulated, where: matches) {
                return found
            }
        }

        return nil
    }

    /// The box around this node and its children, in its parent's space.
    func bounds(parentTransform: Transform = .identity) -> Bounds? {
        let accumulated = parentTransform + transform
        let own = shape.localBounds.map { $0.transformed(by: accumulated) }

        return children.reduce(own) { combined, child in
            Bounds.union(combined, child.bounds(parentTransform: accumulated))
        }
    }
}
