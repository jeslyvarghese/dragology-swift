import Foundation

/// Where a layer stacks: relative to its parent layer, or absolutely,
/// escaping the hierarchy (`.absolute(1)` brings a dragged item forward).
public enum ZIndex: Equatable, Sendable {
    case relative(Int)
    case absolute(Int)
}

/// Whether animated transitions apply to a node's layer.
public enum SceneTransitionPolicy: Sendable {
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
/// measured, or blended. A `SceneNode` tree is plain data that can.
public struct SceneNode<State: Equatable> {
    /// Identity across renders. Nodes with an id become separate layers,
    /// which can be blended, re-parented, and restacked independently.
    public var id: String?
    /// Pins this node's slot among its siblings, without making a layer.
    public var key: String?
    public var transform: SceneTransform = .identity
    public var opacity: Double = 1
    public var zIndex: ZIndex = .relative(0)
    public var shape: SceneShape = .none
    public var style = SceneStyle()
    public var children: [SceneNode] = []
    public var onDrag: (() -> DragSpec<State>)?
    public var onTap: (() -> Void)?
    public var transitionPolicy: SceneTransitionPolicy = .animated
    public var hitTesting: HitTesting = .enabled
    /// The layer this one grows out of, when a blend has no earlier
    /// version of it. Without this, a new layer simply fades in.
    public var emergeOrigin: String?
    public var emergeMode: EmergeMode = .scale
    /// What a host draws in a `.slot`. It's opaque here: the core only
    /// carries it along, which keeps it free of any UI framework.
    public var hostedContent: Any?

    /// A stable address, for nodes without an id.
    public internal(set) var path = ""

    public init(shape: SceneShape = .none, children: [SceneNode] = []) {
        self.shape = shape
        self.children = children
    }
}

// MARK: - Modifiers

extension SceneNode {
    private func with(_ change: (inout SceneNode) -> Void) -> SceneNode {
        var copy = self
        change(&copy)
        return copy
    }

    public func id(_ id: String) -> SceneNode { with { $0.id = id } }
    public func key(_ key: String) -> SceneNode { with { $0.key = key } }
    public func transform(_ transform: SceneTransform) -> SceneNode { with { $0.transform = transform } }
    public func opacity(_ opacity: Double) -> SceneNode { with { $0.opacity = opacity } }
    public func zIndex(_ zIndex: ZIndex) -> SceneNode { with { $0.zIndex = zIndex } }
    public func fill(_ color: SceneColor?) -> SceneNode { with { $0.style.fill = color } }

    public func stroke(_ color: SceneColor?, lineWidth: Double = 1) -> SceneNode {
        with {
            $0.style.stroke = color
            $0.style.lineWidth = lineWidth
        }
    }

    public func hitTesting(_ hitTesting: HitTesting) -> SceneNode { with { $0.hitTesting = hitTesting } }

    /// Makes this node draggable. The closure runs when a drag starts.
    public func onDrag(_ spec: @escaping () -> DragSpec<State>) -> SceneNode {
        with { $0.onDrag = spec }
    }

    public func onTap(_ action: @escaping () -> Void) -> SceneNode { with { $0.onTap = action } }

    /// Makes this layer grow out of `origin` when it first appears.
    public func emergeFrom(_ origin: String?, mode: EmergeMode = .scale) -> SceneNode {
        with {
            $0.emergeOrigin = origin
            $0.emergeMode = mode
        }
    }
}

// MARK: - Building

/// Builds a node's children, with the usual `if` and `for` support.
@resultBuilder
public enum SceneNodeBuilder<State: Equatable> {
    public static func buildExpression(_ node: SceneNode<State>) -> [SceneNode<State>] { [node] }
    public static func buildBlock(_ parts: [SceneNode<State>]...) -> [SceneNode<State>] { parts.flatMap { $0 } }
    public static func buildArray(_ parts: [[SceneNode<State>]]) -> [SceneNode<State>] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [SceneNode<State>]?) -> [SceneNode<State>] { part ?? [] }
    public static func buildEither(first part: [SceneNode<State>]) -> [SceneNode<State>] { part }
    public static func buildEither(second part: [SceneNode<State>]) -> [SceneNode<State>] { part }
}

public func SceneGroup<State>(@SceneNodeBuilder<State> _ content: () -> [SceneNode<State>]) -> SceneNode<State> {
    SceneNode(children: content())
}

public func SceneRect<State>(width: Double, height: Double, cornerRadius: Double = 0) -> SceneNode<State> {
    SceneNode(shape: .rect(size: Vec2(width, height), cornerRadius: cornerRadius))
}

public func SceneCircle<State>(radius: Double) -> SceneNode<State> {
    SceneNode(shape: .circle(radius: radius))
}

public func SceneLine<State>(from: Vec2, to: Vec2) -> SceneNode<State> {
    SceneNode(shape: .line(from: from, to: to))
}

public func ScenePath<State>(_ commands: [PathCommand]) -> SceneNode<State> {
    SceneNode(shape: .path(commands))
}

public func SceneText<State>(_ string: String, size: Double) -> SceneNode<State> {
    SceneNode(shape: .text(string, size: size))
}

// MARK: - Changing state types

extension SceneNode {
    /// This tree for a different state type. `lift` converts drag
    /// handlers; without it they're dropped, which suits inert previews.
    func retyped<Other>(
        lift: ((@escaping () -> DragSpec<State>) -> () -> DragSpec<Other>)? = nil
    ) -> SceneNode<Other> {
        var copy = SceneNode<Other>(shape: shape, children: children.map { $0.retyped(lift: lift) })

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
        copy.hostedContent = hostedContent
        copy.path = path

        if let onDrag, let lift {
            copy.onDrag = lift(onDrag)
        }

        return copy
    }
}

// MARK: - Tree queries

extension SceneNode {
    private static var rootPath: String { "/" }
    private static var pathSeparator: String { "/" }

    /// Gives every node a stable path. An id restarts the path, so a node
    /// keeps its address when it moves around the tree.
    func assigningPaths() -> SceneNode {
        assigningPaths(at: Self.rootPath)
    }

    private func assigningPaths(at inheritedPath: String) -> SceneNode {
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
        parentTransform: SceneTransform = .identity,
        where matches: (SceneNode) -> Bool
    ) -> (node: SceneNode, transform: SceneTransform)? {
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
    func bounds(parentTransform: SceneTransform = .identity) -> Bounds? {
        let accumulated = parentTransform + transform
        let own = shape.localBounds.map { $0.transformed(by: accumulated) }

        return children.reduce(own) { combined, child in
            Bounds.union(combined, child.bounds(parentTransform: accumulated))
        }
    }
}
