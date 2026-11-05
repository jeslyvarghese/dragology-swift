import Foundation

/// Which input of a blend supplies what can't be blended, such as drag
/// handlers and stacking.
enum UnblendedSide {
    case first
    case second
}

private enum Blend {
    /// Below this opacity, a fading element is dropped.
    static let minVisibleOpacity = 1e-3
    /// Weights below this don't contribute to a weighted blend.
    static let minWeight = 1e-10
}

extension SceneNode {
    /// Blends two renders of the same node. Children pair up by key, or
    /// else by position; one with no partner fades.
    static func lerp(_ a: SceneNode, _ b: SceneNode, _ t: Double, unblended: UnblendedSide) -> SceneNode {
        var result: SceneNode

        switch unblended {
        case .first:
            result = a
        case .second:
            result = b
        }

        result.transform = SceneTransform.lerp(a.transform, b.transform, t)
        result.opacity = mix(a.opacity, b.opacity, t)
        result.shape = SceneShape.lerp(a.shape, b.shape, t)
        result.style = SceneStyle.lerp(a.style, b.style, t)
        result.children = lerpChildren(a.children, b.children, t, unblended: unblended)

        return result
    }

    private static func lerpChildren(
        _ a: [SceneNode],
        _ b: [SceneNode],
        _ t: Double,
        unblended: UnblendedSide
    ) -> [SceneNode] {
        let slotsA = slots(a)
        let slotsB = Dictionary(uniqueKeysWithValues: slots(b).map { ($0.slot, $0.node) })
        let keysA = Set(slotsA.map(\.slot))

        // Keep A's order, then add children that only B has.
        var result: [SceneNode] = []

        for (slot, childA) in slotsA {
            if let childB = slotsB[slot] {
                result.append(lerp(childA, childB, t, unblended: unblended))
                continue
            }

            if let faded = childA.faded(by: 1 - t) {
                result.append(faded)
            }
        }

        for (slot, childB) in slots(b) where !keysA.contains(slot) {
            if let faded = childB.faded(by: t) {
                result.append(faded)
            }
        }

        return result
    }

    /// Identifies children the same way paths do.
    private static func slots(_ children: [SceneNode]) -> [(slot: String, node: SceneNode)] {
        var unkeyedIndex = 0

        return children.map { child in
            if let key = child.key { return (key, child) }

            defer { unkeyedIndex += 1 }
            return (String(unkeyedIndex), child)
        }
    }

    /// Gives this node's first box and label the origin's size and place.
    /// False if either node has no box.
    @discardableResult
    fileprivate mutating func takeBox(of origin: SceneNode) -> Bool {
        let isBox = { (child: SceneNode) in
            if case .rect = child.shape { return true }
            return false
        }

        let isLabel = { (child: SceneNode) in
            if case .text = child.shape { return true }
            return false
        }

        guard let box = children.firstIndex(where: isBox),
              let originBox = origin.children.first(where: isBox) else {
            return false
        }

        children[box].shape = originBox.shape

        if let label = children.firstIndex(where: isLabel),
           let originLabel = origin.children.first(where: isLabel) {
            children[label].transform = originLabel.transform
        }

        return true
    }

    fileprivate func faded(by factor: Double) -> SceneNode? {
        let faded = opacity * factor
        guard faded > Blend.minVisibleOpacity else { return nil }

        var copy = self
        copy.opacity = faded
        return copy
    }
}

extension LayeredScene {
    /// Blends two scenes layer by layer, matching layers by id.
    static func lerp(
        _ a: LayeredScene,
        _ b: LayeredScene,
        _ t: Double,
        unblended: UnblendedSide
    ) -> LayeredScene {
        var layers: [String: SceneLayer<State>] = [:]
        let keys = a.order + b.order.filter { a.layers[$0] == nil }

        for key in keys {
            // Stand in for a layer that's about to emerge on the other side.
            // Blends can run either way, so this works in both directions.
            let inA = a.layers[key] ?? b.layers[key].flatMap(a.emergingVersion)
            let inB = b.layers[key] ?? a.layers[key].flatMap(b.emergingVersion)

            switch (inA, inB) {
            case (let layerA?, let layerB?):
                let stacking: [Int]

                switch unblended {
                case .first:
                    stacking = layerA.stackingPath
                case .second:
                    stacking = layerB.stackingPath
                }

                layers[key] = SceneLayer(
                    node: SceneNode.lerp(layerA.node, layerB.node, t, unblended: unblended),
                    stackingPath: stacking
                )

            case (let layerA?, nil):
                if let faded = layerA.node.faded(by: 1 - t) {
                    layers[key] = SceneLayer(node: faded, stackingPath: layerA.stackingPath)
                }

            case (nil, let layerB?):
                if let faded = layerB.node.faded(by: t) {
                    layers[key] = SceneLayer(node: faded, stackingPath: layerB.stackingPath)
                }

            case (nil, nil):
                continue
            }
        }

        return a
            .replacing(layers: layers, order: keys.filter { layers[$0] != nil })
            .mergingDescendants(of: b)
    }

    /// What `layer` looks like just before emerging in this scene, if it
    /// names an origin here.
    private func emergingVersion(of layer: SceneLayer<State>) -> SceneLayer<State>? {
        guard let originID = layer.node.emergeOrigin,
              let origin = layers[originID] else {
            return nil
        }

        var node = layer.node

        switch layer.node.emergeMode {
        case .clone:
            node.transform = origin.node.transform
            node.takeBox(of: origin.node)

        case .morph where node.takeBox(of: origin.node):
            node.transform = origin.node.transform
            node.opacity = 0

        case .scale, .morph:
            node.transform = origin.node.transform + .scale(0)
            node.opacity = 0
        }

        return SceneLayer(node: node, stackingPath: layer.stackingPath)
    }

    /// Blends several scenes. `weights` maps index to weight, summing to 1.
    static func lerp(_ scenes: [LayeredScene], weights: [Int: Double]) -> LayeredScene {
        let entries = weights
            .filter { $0.value > Blend.minWeight }
            .sorted { $0.key < $1.key }

        guard let first = entries.first else { return scenes[0] }

        // What can't be blended comes from the heaviest scene.
        let heaviest = entries.max { $0.value < $1.value }?.key

        var blended = scenes[first.key]
        var accumulated = first.value

        // Fold pairwise, weighting each scene against the total so far.
        for (index, weight) in entries.dropFirst() {
            let t = weight / (accumulated + weight)
            let side: UnblendedSide = index == heaviest ? .second : .first

            blended = lerp(blended, scenes[index], t, unblended: side)
            accumulated += weight
        }

        return blended
    }
}
