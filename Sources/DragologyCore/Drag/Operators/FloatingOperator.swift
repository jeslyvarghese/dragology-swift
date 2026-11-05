import Foundation

public struct FloatingOptions<State: Equatable> {
    private static var standardGhostOpacity: Double { 0.5 }

    /// Leaves a copy at the drop position, at this opacity.
    public var ghostOpacity: Double?
    /// Limits how far the element strays from its drop position: maps
    /// the distance to the pointer to the distance to float.
    public var tether: ((Double) -> Double)?

    public init(ghostOpacity: Double? = nil, tether: ((Double) -> Double)? = nil) {
        self.ghostOpacity = ghostOpacity
        self.tether = tether
    }

    public static var ghost: FloatingOptions {
        FloatingOptions(ghostOpacity: standardGhostOpacity)
    }
}

private enum Floating {
    /// Puts the floated element above everything else.
    static let topStackingStep = 1_000_000
    static let ghostPrefix = "ghost-"
    /// A shorter pointer offset has no meaningful direction.
    static let minTetherDistance = 1e-6
}

/// Lifts the dragged element out of the inner preview, and pins it to
/// the pointer. The rest of the preview becomes the backdrop.
final class FloatingOperator<State: Equatable>: Operator<State> {
    private let inner: Operator<State>
    private let options: FloatingOptions<State>
    private let draggedID: String
    /// The element, moved to the origin. Kept for frames whose preview
    /// doesn't contain it.
    private var cachedFloat: LayeredScene<State>?

    init(context: DragContext<State>, inner: DragSpec<State>, options: FloatingOptions<State>) {
        guard let draggedID = context.draggedID else {
            preconditionFailure("Floating drags require the dragged element to have an id.")
        }

        self.inner = inner.makeOperator(context)
        self.options = options
        self.draggedID = draggedID

        super.init(context: context, name: "withFloating")
    }

    override func frame(_ frame: DragFrame) -> DragResult<State> {
        let innerResult = inner.run(frame)

        var result = innerResult
        result.preview = Lazy { [self] in
            floatingPreview(backdrop: innerResult.preview.value, pointer: frame.pointer)
        }

        // Without a tether, the float sits right at the pointer.
        result.grabPosition = options.tether == nil ? frame.pointer : nil

        // Inner animations don't apply to a floating preview.
        result.dropTransition = .standard
        result.branchTransition = .standard
        result.chain = nil

        return result
    }

    private func floatingPreview(
        backdrop scene: LayeredScene<State>,
        pointer: Vec2
    ) -> LayeredScene<State> {
        let layerTransform = scene.layers[draggedID]?.node.transform
        let elementPosition = layerTransform?.localToGlobal(context.anchor)

        var backdrop = scene

        if let elementPosition, let split = scene.extracting(id: draggedID) {
            backdrop = decoratedBackdrop(split.remaining, extracted: split.extracted)
            cachedFloat = Self.movedToOrigin(split.extracted, from: elementPosition)
        }

        // A state without the element floats the one from the start state.
        guard let float = cachedFloat ?? startingFloat() else { return backdrop }

        let target = tetheredTarget(pointer: pointer, elementPosition: elementPosition)
        let floated = float.mapLayers { layer in
            layer.node.transform = .translate(target) + layer.node.transform
            layer.node.transitionPolicy = .immediate
            layer.stackingPath.insert(Floating.topStackingStep, at: 0)
        }

        return backdrop.merging(floated)
    }

    private func decoratedBackdrop(
        _ remaining: LayeredScene<State>,
        extracted: LayeredScene<State>
    ) -> LayeredScene<State> {
        guard let ghostOpacity = options.ghostOpacity else { return remaining }

        let ghost = extracted
            .prefixingIDs(Floating.ghostPrefix)
            .mapLayers { $0.node.opacity = ghostOpacity }

        return remaining.merging(ghost)
    }

    private func tetheredTarget(pointer: Vec2, elementPosition: Vec2?) -> Vec2 {
        guard let elementPosition, let tether = options.tether else { return pointer }

        let offset = pointer - elementPosition
        let distance = offset.length

        guard distance > Floating.minTetherDistance else { return pointer }

        return elementPosition + offset * (tether(distance) / distance)
    }

    private func startingFloat() -> LayeredScene<State>? {
        let scene = context.render(context.startState)

        guard let transform = scene.layers[draggedID]?.node.transform,
              let split = scene.extracting(id: draggedID) else {
            return nil
        }

        let float = Self.movedToOrigin(split.extracted, from: transform.localToGlobal(context.anchor))
        cachedFloat = float

        return float
    }

    private static func movedToOrigin(
        _ scene: LayeredScene<State>,
        from position: Vec2
    ) -> LayeredScene<State> {
        scene.mapLayers { layer in
            layer.node.transform = .translate(position * -1) + layer.node.transform
        }
    }
}
