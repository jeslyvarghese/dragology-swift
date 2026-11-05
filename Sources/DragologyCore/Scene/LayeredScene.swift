import Foundation

/// A piece of a scene that stacks and blends independently. Its node's
/// transform and opacity already include those of its ancestors.
public struct Layer<State: Equatable> {
    public var node: Node<State>
    public var stackingPath: [Int]
}

/// What a touch landed on.
struct Hit<State: Equatable> {
    struct DragTarget {
        var node: Node<State>
        var transform: Transform
    }

    var dragTarget: DragTarget?
    var onTap: (() -> Void)?
}

/// A scene flattened into layers, one for each node with an id, plus a
/// root layer holding everything else.
///
/// Layers are what make blending robust: a node matches its counterpart
/// by id, wherever each one sits in its tree.
public struct LayeredScene<State: Equatable> {
    private static var rootKey: String { "" }

    public private(set) var layers: [String: Layer<State>] = [:]
    /// Layer keys in insertion order, the tiebreak for equal stacking.
    private(set) var order: [String] = []
    /// Each layer id's nested layer ids, transitively.
    private(set) var descendants: [String: Set<String>] = [:]

    init() {}

    /// Pulls every node with an id out into its own layer.
    public init(root: Node<State>) {
        let remainder = extract(
            root,
            ancestors: [],
            accumulatedTransform: .identity,
            accumulatedOpacity: 1,
            stackingPath: []
        )

        guard let remainder else { return }

        layers[Self.rootKey] = Layer(node: remainder, stackingPath: [])
        order.insert(Self.rootKey, at: 0)
    }

    private mutating func extract(
        _ node: Node<State>,
        ancestors: [String],
        accumulatedTransform: Transform,
        accumulatedOpacity: Double,
        stackingPath: [Int]
    ) -> Node<State>? {
        let transform = accumulatedTransform + node.transform
        let opacity = accumulatedOpacity * node.opacity
        let id = node.id

        // Every layer adds a step to the stacking path.
        var childStackingPath = stackingPath

        if id != nil {
            switch node.zIndex {
            case .relative(let index):
                childStackingPath.append(index)
            case .absolute(let index):
                childStackingPath = [index]
            }
        }

        var remainder = node
        let childAncestors = id.map { ancestors + [$0] } ?? ancestors

        remainder.children = node.children.compactMap { child in
            extract(
                child,
                ancestors: childAncestors,
                accumulatedTransform: transform,
                accumulatedOpacity: opacity,
                stackingPath: childStackingPath
            )
        }

        guard let id else { return remainder }

        precondition(layers[id] == nil, "Duplicate id \"\(id)\": ids must be unique in a scene.")

        for ancestor in ancestors {
            descendants[ancestor, default: []].insert(id)
        }

        // Ancestors' effects are baked in, so the layer stands alone.
        remainder.transform = transform
        remainder.opacity = opacity

        layers[id] = Layer(node: remainder, stackingPath: childStackingPath)
        order.append(id)

        return nil
    }

    /// Layers from back to front.
    public var drawOrder: [Layer<State>] {
        let keys = order.enumerated().sorted { lhs, rhs in
            guard let a = layers[lhs.element], let b = layers[rhs.element] else { return false }

            let comparison = Self.compareStacking(a.stackingPath, b.stackingPath)
            return comparison == 0 ? lhs.offset < rhs.offset : comparison < 0
        }

        return keys.compactMap { layers[$0.element] }
    }

    /// Lexicographic, except that a missing step sits just below zero:
    /// a layer's children stack above it, unless they ask to go below.
    static func compareStacking(_ a: [Int], _ b: [Int]) -> Int {
        for (stepA, stepB) in zip(a, b) where stepA != stepB {
            return stepA - stepB
        }

        if a.count == b.count { return 0 }

        if a.count > b.count {
            return a[b.count] >= 0 ? 1 : -1
        }

        return b[a.count] >= 0 ? -1 : 1
    }

    // MARK: Queries

    /// Finds a node by its path, with its full transform.
    func find(path: String) -> (node: Node<State>, transform: Transform)? {
        for key in order {
            guard let layer = layers[key] else { continue }

            // A layer's transform is complete, so it starts from the identity.
            if let found = layer.node.find(where: { $0.path == path }) {
                return found
            }
        }

        return nil
    }

    /// The topmost thing under a point.
    func hitTest(_ point: Vec2) -> Hit<State>? {
        for layer in drawOrder.reversed() {
            if let hit = Self.hitTest(layer.node, point, parentTransform: .identity, enclosing: Hit()) {
                return hit
            }
        }

        return nil
    }

    private static func hitTest(
        _ node: Node<State>,
        _ point: Vec2,
        parentTransform: Transform,
        enclosing: Hit<State>
    ) -> Hit<State>? {
        guard case .enabled = node.hitTesting else { return nil }
        guard let local = node.transform.globalToLocal(point) else { return nil }

        // The nearest enclosing handlers win.
        let transform = parentTransform + node.transform
        var current = enclosing

        if node.onDrag != nil {
            current.dragTarget = Hit.DragTarget(node: node, transform: transform)
        }

        if let onTap = node.onTap {
            current.onTap = onTap
        }

        for child in node.children.reversed() {
            let hit = hitTest(child, local, parentTransform: transform, enclosing: current)
            if let hit { return hit }
        }

        return node.shape.contains(local, style: node.style) ? current : nil
    }

    // MARK: Editing

    /// Splits off a layer and everything nested in it.
    func extracting(id: String) -> (remaining: LayeredScene, extracted: LayeredScene)? {
        guard layers[id] != nil else { return nil }

        let extractedIDs = (descendants[id] ?? []).union([id])
        var remaining = LayeredScene()
        var extracted = LayeredScene()

        for key in order {
            guard let layer = layers[key] else { continue }

            if extractedIDs.contains(key) {
                extracted.append(key, layer)
            } else {
                remaining.append(key, layer)
            }
        }

        // Keep only the nesting that stays within each half.
        for (ancestor, nested) in descendants {
            if extractedIDs.contains(ancestor) {
                extracted.descendants[ancestor] = nested.intersection(extractedIDs)
            } else {
                remaining.descendants[ancestor] = nested.subtracting(extractedIDs)
            }
        }

        return (remaining, extracted)
    }

    private mutating func append(_ key: String, _ layer: Layer<State>) {
        layers[key] = layer
        order.append(key)
    }

    /// Replaces a layer, or adds it if the scene doesn't have it.
    mutating func setLayer(_ layer: Layer<State>, forKey key: String) {
        guard layers[key] != nil else {
            append(key, layer)
            return
        }

        layers[key] = layer
    }

    func merging(_ other: LayeredScene) -> LayeredScene {
        var merged = self

        for key in other.order {
            guard let layer = other.layers[key] else { continue }

            precondition(merged.layers[key] == nil, "Cannot merge scenes: duplicate id \"\(key)\".")
            merged.append(key, layer)
        }

        merged.descendants.merge(other.descendants) { first, _ in first }

        return merged
    }

    /// Applies a change to every layer.
    func mapLayers(_ change: (inout Layer<State>) -> Void) -> LayeredScene {
        var copy = self

        for key in order {
            guard var layer = copy.layers[key] else { continue }

            change(&layer)
            copy.layers[key] = layer
        }

        return copy
    }

    /// Renames layers, to place a copy of them alongside the originals.
    func prefixingIDs(_ prefix: String) -> LayeredScene {
        var renamed = LayeredScene()

        for key in order {
            guard var layer = layers[key] else { continue }

            let id = prefix + key
            layer.node.id = id
            layer.node.path = id + "/"
            renamed.append(id, layer)
        }

        return renamed
    }

    /// Rebuilds the scene with the given layers, in a stable order.
    func replacing(layers newLayers: [String: Layer<State>], order newOrder: [String]) -> LayeredScene {
        var copy = self
        copy.layers = newLayers
        copy.order = newOrder
        return copy
    }

    /// This scene for a different state type, without drag handlers.
    func retyped<Other>() -> LayeredScene<Other> {
        var copy = LayeredScene<Other>()

        for key in order {
            guard let layer = layers[key] else { continue }

            copy.setLayer(Layer(node: layer.node.retyped(), stackingPath: layer.stackingPath), forKey: key)
        }

        copy.descendants = descendants

        return copy
    }

    /// Combines nesting information from two blended scenes.
    func mergingDescendants(of other: LayeredScene) -> LayeredScene {
        var copy = self
        copy.descendants.merge(other.descendants) { $0.union($1) }
        return copy
    }
}
