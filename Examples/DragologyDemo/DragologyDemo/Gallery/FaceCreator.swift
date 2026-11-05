import DragologySwift
import Foundation

private enum Face {
    static let center = Vec2(200, 180)
    static let defaultRadius = 120.0
    static let eyeRadius = 12.0
    static let faceStroke = 3.0
    static let mouthStroke = 4.0
    static let faceMargin = eyeRadius + faceStroke / 2 + 2
    static let eyeMargin = eyeRadius + mouthStroke / 2 + 4
    static let eyeReach = eyeRadius + 2
    static let minEyeSpacing = eyeRadius + 5
    static let minMouthHalfWidth = 10.0
    static let maxControlOffset = 100.0
    static let minFaceRadius = 40.0

    /// Where a cubic with fixed ends passes at t = 0.5, per control point.
    static let midpointControlShare = 0.375
    static let midpointEndShare = 0.5

    static let outlineSamplesPerSegment = 16
    static let shapeSamplesPerSegment = 8
    static let mouthSamples = 8
    static let pushIterations = 3
    /// Each step around the outline must cover this share of an even step.
    static let minAngleStepShare = 0.25
    static let eyePushVerticalBias = 0.5
    static let minEyePush = 0.1

    static let mouthHandleCount = 11
    static let endpointRadius = 8.0
    static let mouthHandleRadius = 14.0
    static let draggedMouthHandleRadius = 8.0
    static let perimeterHandleCount = 7
    static let draggedPerimeterRadius = 6.0
    static let minPerimeterHitRadius = 16.0
    static let perimeterHitShare = 0.13
    static let handleOpacity = 0.4
    static let endpointLineWidth = 1.5

    /// Handles nearer an end than this move that end, not the middle.
    static let curveEndZone = 0.4
    static let perimeterEndZone = 0.35

    static let skin = RGBA(hex: 0xFFE0B2)
    static let skinEdge = RGBA(hex: 0xE6A756)
    static let eye = RGBA(hex: 0x333333)
    static let mouth = RGBA(hex: 0xC0392B)
    static let activeEndpoint = RGBA(hex: 0xE74C3C)

    static let faceZ = 0
    static let featureZ = 1
    static let mouthHandleZ = 2
    static let endpointZ = 3
}

struct FaceState: Equatable {
    var eyeY = Face.center.y - 25
    var eyeDx = 40.0
    var mouthDx = 50.0
    var mouthY = Face.center.y + 40
    var control1 = Vec2(20, 30)
    var control2 = Vec2(-20, 30)
    var radiusX = Face.defaultRadius
    var radiusTop = Face.defaultRadius
    var radiusBottom = Face.defaultRadius
    var bulgeTop = 0.0
    var bulgeBottom = 0.0

    var summary: String {
        let values = [eyeDx, mouthDx, radiusX, radiusTop, radiusBottom].map { String(Int($0.rounded())) }
        return "eyes \(values[0]) mouth \(values[1]) face \(values[2]) \(values[3]) \(values[4])"
    }

    fileprivate var mouthLeft: Vec2 { Vec2(Face.center.x - mouthDx, mouthY) }
    fileprivate var mouthRight: Vec2 { Vec2(Face.center.x + mouthDx, mouthY) }
    fileprivate var leftEye: Vec2 { Vec2(Face.center.x - eyeDx, eyeY) }
    fileprivate var rightEye: Vec2 { Vec2(Face.center.x + eyeDx, eyeY) }

    fileprivate var mouthCurve: Cubic {
        Cubic(
            start: mouthLeft,
            control1: mouthLeft + control1,
            control2: mouthRight + control2,
            end: mouthRight
        )
    }

    /// Evenly spaced points along the mouth, including both ends.
    fileprivate var mouthPoints: [Vec2] {
        (0...Face.mouthSamples).map { mouthCurve.point(at: Double($0) / Double(Face.mouthSamples)) }
    }

    /// The outline as four curves, from the top going clockwise. The left
    /// half mirrors the right.
    fileprivate var outline: [Cubic] {
        let halfRoot = 1 / 2.0.squareRoot()
        let share = Face.midpointControlShare
        let half = Face.midpointEndShare

        // Pick control points that send each curve through its bulged midpoint.
        let topMiddle = Vec2(radiusX * halfRoot, -radiusTop * halfRoot)
        let topBulged = topMiddle + topMiddle.normalized * bulgeTop
        let topControlX = (topBulged.x - half * radiusX) / share
        let topControlY = (topBulged.y + half * radiusTop) / share

        let bottomMiddle = Vec2(radiusX * halfRoot, radiusBottom * halfRoot)
        let bottomBulged = bottomMiddle + bottomMiddle.normalized * bulgeBottom
        let bottomControlY = (bottomBulged.y - half * radiusBottom) / share
        let bottomControlX = (bottomBulged.x - half * radiusX) / share

        let at = { (x: Double, y: Double) in Face.center + Vec2(x, y) }

        return [
            Cubic(
                start: at(0, -radiusTop),
                control1: at(topControlX, -radiusTop),
                control2: at(radiusX, topControlY),
                end: at(radiusX, 0)
            ),
            Cubic(
                start: at(radiusX, 0),
                control1: at(radiusX, bottomControlY),
                control2: at(bottomControlX, radiusBottom),
                end: at(0, radiusBottom)
            ),
            Cubic(
                start: at(0, radiusBottom),
                control1: at(-bottomControlX, radiusBottom),
                control2: at(-radiusX, bottomControlY),
                end: at(-radiusX, 0)
            ),
            Cubic(
                start: at(-radiusX, 0),
                control1: at(-radiusX, topControlY),
                control2: at(-topControlX, -radiusTop),
                end: at(0, -radiusTop)
            ),
        ]
    }
}

enum FaceMode: Int, CaseIterable {
    case standard, fixedFace, mickey, freeFeatures

    var title: String {
        switch self {
        case .standard: "features move face"
        case .fixedFace: "features stay inside"
        case .mickey: "Mickey mode"
        case .freeFeatures: "eyes can pass the mouth"
        }
    }

    fileprivate var expandsFace: Bool { self != .fixedFace }
    fileprivate var constrainsShape: Bool { self != .mickey }
    fileprivate var keepsEyesAboveMouth: Bool { self != .freeFeatures }
    fileprivate var scalesCurve: Bool { self != .freeFeatures }
}

private struct Cubic {
    var start, control1, control2, end: Vec2

    func point(at t: Double) -> Vec2 {
        let u = 1 - t
        let first = start * (u * u * u)
        let second = control1 * (3 * u * u * t)
        let third = control2 * (3 * u * t * t)
        let fourth = end * (t * t * t)

        return first + second + third + fourth
    }
}

// MARK: - Outline lookup

/// The outline's distance from the center, by angle.
private struct RadialOutline {
    private struct Sample {
        var angle: Double
        var radius: Double
    }

    private let samples: [Sample]

    init(_ state: FaceState) {
        let count = Face.outlineSamplesPerSegment

        samples = state.outline
            .flatMap { curve in
                (0..<count).map { index -> Sample in
                    let offset = curve.point(at: Double(index) / Double(count)) - Face.center
                    return Sample(angle: offset.angle, radius: offset.length)
                }
            }
            .sorted { $0.angle < $1.angle }
    }

    /// Interpolates between the two samples either side of `angle`.
    func radius(at angle: Double) -> Double {
        let count = samples.count
        let fullTurn = 2 * Double.pi
        let upper = (samples.firstIndex { $0.angle >= angle } ?? count) % count
        let lower = (upper - 1 + count) % count

        var span = samples[upper].angle - samples[lower].angle
        var offset = angle - samples[lower].angle

        if span <= 0 { span += fullTurn }
        if offset < 0 { offset += fullTurn }

        let t = span > 0 ? offset / span : 0

        return samples[lower].radius + t * (samples[upper].radius - samples[lower].radius)
    }

    /// At most zero when the point is inside, with the margin to spare.
    func excess(of point: Vec2, margin: Double) -> Double {
        let offset = point - Face.center
        return offset.length - (radius(at: offset.angle) - margin)
    }

    /// Pulls a point towards the center until it's inside.
    func clamped(_ point: Vec2, margin: Double) -> Vec2 {
        let offset = point - Face.center
        let limit = radius(at: offset.angle) - margin

        guard offset.length > limit, offset.length > 0 else { return point }

        return Face.center + offset.normalized * limit
    }
}

// MARK: - Constraints

private func featureConstraints(_ state: FaceState) -> [Double] {
    let curve = state.mouthCurve
    let count = Face.mouthSamples

    // The mouth has to keep heading right, so it can't double back.
    let advancing = (0..<count).flatMap { index -> [Double] in
        let here = curve.point(at: Double(index) / Double(count))
        let next = curve.point(at: Double(index + 1) / Double(count))

        return Constraint.lessThan(here.x, next.x)
    }

    return Constraint.moreThan(state.eyeDx, Face.minEyeSpacing)
        + Constraint.moreThan(state.mouthDx, Face.minMouthHalfWidth)
        + Constraint.lessThan(state.control1.length, Face.maxControlOffset)
        + Constraint.lessThan(state.control2.length, Face.maxControlOffset)
        + advancing
}

private func featureConstraintsInsideFace(_ state: FaceState) -> [Double] {
    let outline = RadialOutline(state)
    let points = [state.leftEye, state.rightEye] + state.mouthPoints

    return featureConstraints(state) + points.map { outline.excess(of: $0, margin: Face.faceMargin) }
}

/// Keeps the outline star-shaped: its angle must always move forward.
private func shapeConstraints(_ state: FaceState) -> [Double] {
    let count = Face.shapeSamplesPerSegment
    let fullTurn = 2 * Double.pi

    let angles = state.outline.flatMap { curve in
        (0..<count).map { index in
            (curve.point(at: Double(index) / Double(count)) - Face.center).angle
        }
    }

    let minimumStep = fullTurn / Double(angles.count) * Face.minAngleStepShare

    return angles.indices.flatMap { index -> [Double] in
        var step = angles[(index + 1) % angles.count] - angles[index]

        if step < -Double.pi { step += fullTurn }

        return Constraint.moreThan(step, minimumStep)
    }
}

// MARK: - Features pushing each other

private func mouthPushedBelowEyes(_ state: FaceState) -> FaceState {
    var result = state

    for _ in 0..<Face.pushIterations {
        var push = 0.0

        for point in result.mouthPoints {
            for eye in [result.leftEye, result.rightEye]
            where abs(point.x - eye.x) < Face.eyeReach && point.y < eye.y + Face.eyeMargin {
                push = max(push, eye.y + Face.eyeMargin - point.y)
            }
        }

        guard push > 0 else { break }

        result.mouthY += push
    }

    return result
}

private func mouthPushedAway(_ state: FaceState) -> FaceState {
    let minDistance = Face.eyeRadius + Face.eyeMargin
    var result = state

    for _ in 0..<Face.pushIterations {
        var push = 0.0

        for point in result.mouthPoints {
            for eye in [result.leftEye, result.rightEye] {
                push = max(push, minDistance - point.distance(to: eye))
            }
        }

        guard push > 0 else { break }

        result.mouthY += push
    }

    return result
}

private func eyesClampedAboveMouth(_ state: FaceState) -> FaceState {
    var result = state

    for point in state.mouthPoints {
        for eye in [state.leftEye, state.rightEye] where abs(point.x - eye.x) < Face.eyeReach {
            result.eyeY = min(result.eyeY, point.y - Face.eyeMargin)
        }
    }

    return result
}

private func eyesPushedAway(_ state: FaceState) -> FaceState {
    let minDistance = Face.eyeRadius + Face.eyeMargin
    var result = state

    for _ in 0..<Face.pushIterations {
        var pushY = 0.0
        var pushDx = 0.0

        for point in result.mouthPoints {
            for eye in [result.leftEye, result.rightEye] {
                let distance = point.distance(to: eye)

                guard distance < minDistance, distance > 0 else { continue }

                let deficit = minDistance - distance
                let direction = (eye - point) * (1 / distance)
                let isLeftEye = eye.x < Face.center.x

                pushY += direction.y * deficit
                pushDx += (isLeftEye ? -direction.x : direction.x) * deficit
            }
        }

        guard Vec2(pushY, pushDx).length >= Face.minEyePush else { break }

        result.eyeY += pushY * Face.eyePushVerticalBias
        result.eyeDx = max(Face.minEyeSpacing, result.eyeDx + pushDx * (1 - Face.eyePushVerticalBias))
    }

    return result
}

/// Grows the face just enough to fit a point.
private func faceExpanded(_ state: FaceState, toFit point: Vec2) -> FaceState {
    let offset = point - Face.center
    let limit = RadialOutline(state).radius(at: offset.angle) - Face.faceMargin

    guard offset.length > limit, offset.length > 0 else { return state }

    let deficit = offset.length - limit
    let horizontal = deficit * abs(cos(offset.angle))
    let vertical = deficit * abs(sin(offset.angle))

    var result = state
    result.radiusX += horizontal

    if offset.y < 0 {
        result.radiusTop += vertical
    } else if offset.y > 0 {
        result.radiusBottom += vertical
    }

    return result
}

private func faceExpandedForFeatures(_ state: FaceState) -> FaceState {
    let points = [state.leftEye, state.rightEye] + state.mouthPoints

    return points.reduce(state) { faceExpanded($0, toFit: $1) }
}

private func featuresClampedInside(_ state: FaceState) -> FaceState {
    let outline = RadialOutline(state)
    let clamp = { (point: Vec2) in outline.clamped(point, margin: Face.faceMargin) }
    let spread = { (point: Vec2) in abs(point.x - Face.center.x) }
    var result = state

    let leftEye = clamp(state.leftEye)
    let rightEye = clamp(state.rightEye)

    if leftEye != state.leftEye || rightEye != state.rightEye {
        result.eyeY = min(leftEye.y, rightEye.y)
        result.eyeDx = max(Face.minEyeSpacing, min(spread(leftEye), spread(rightEye)))
    }

    let mouthLeft = clamp(state.mouthLeft)
    let mouthRight = clamp(state.mouthRight)

    if mouthLeft != state.mouthLeft || mouthRight != state.mouthRight {
        result.mouthY = max(mouthLeft.y, mouthRight.y)
        result.mouthDx = max(Face.minMouthHalfWidth, min(spread(mouthLeft), spread(mouthRight)))
    }

    return result
}

// MARK: - Drags

/// The drag specs for one render of the face.
private struct FaceDrags {
    let state: FaceState
    let d: DragSpecBuilder<FaceState>
    let mode: FaceMode

    private typealias Parameter = WritableKeyPath<FaceState, Double>

    /// How far the mouth can drop before leaving the face.
    private var chinY: Double {
        Face.center.y + state.radiusBottom - Face.faceMargin
    }

    /// The share of the room below the mouth that's left at `mouthY`.
    private func verticalScale(from originalY: Double, to mouthY: Double) -> Double {
        let original = chinY - originalY

        return original > 0 ? (chinY - mouthY) / original : 1
    }

    private func featureConstraint(_ state: FaceState) -> [Double] {
        mode.expandsFace ? featureConstraints(state) : featureConstraintsInsideFace(state)
    }

    /// The last steps of any feature drag.
    private func finished(_ state: FaceState) -> FaceState {
        var result = state

        if mode.keepsEyesAboveMouth { result = eyesClampedAboveMouth(result) }
        if mode.expandsFace { result = faceExpandedForFeatures(result) }

        return featuresClampedInside(result)
    }

    func eyes() -> DragSpec<FaceState> {
        let start = state

        return d.vary(state, \.eyeY, \.eyeDx, constraint: featureConstraint).during { candidate in
            var result = mode.keepsEyesAboveMouth ? mouthPushedBelowEyes(candidate) : mouthPushedAway(candidate)

            // A pushed mouth flattens as it runs out of room.
            if result.mouthY != start.mouthY {
                let scale = verticalScale(from: start.mouthY, to: result.mouthY)

                result.control1.y = start.control1.y * scale
                result.control2.y = start.control2.y * scale
            }

            return finished(result)
        }
    }

    func mouthEnds() -> DragSpec<FaceState> {
        let start = state

        return d.vary(state, \.mouthDx, \.mouthY, constraint: featureConstraint).during { candidate in
            var result = eyesPushedAway(candidate)

            if mode.scalesCurve {
                let horizontal = start.mouthDx > 0 ? result.mouthDx / start.mouthDx : 1
                let vertical = verticalScale(from: start.mouthY, to: result.mouthY)

                result.control1 = Vec2(start.control1.x * horizontal, start.control1.y * vertical)
                result.control2 = Vec2(start.control2.x * horizontal, start.control2.y * vertical)
            }

            return finished(result)
        }
    }

    /// Near an end, the curve bends by that end's control point alone.
    func mouthCurve(at t: Double) -> DragSpec<FaceState> {
        let first: [Parameter] = [\.control1.x, \.control1.y]
        let second: [Parameter] = [\.control2.x, \.control2.y]

        let paths: [Parameter]

        if t < Face.curveEndZone {
            paths = first
        } else if t > 1 - Face.curveEndZone {
            paths = second
        } else {
            paths = first + second
        }

        return d.vary(state, paths: paths, constraint: featureConstraint)
            .during { finished(eyesPushedAway($0)) }
    }

    /// What a handle on one of the outline's four curves varies: the
    /// curve's start, its bulge, or its end.
    private static func outlineParameters(for segment: Int) -> [Parameter] {
        switch segment {
        case 0: [\.radiusTop, \.bulgeTop, \.radiusX]
        case 1: [\.radiusX, \.bulgeBottom, \.radiusBottom]
        case 2: [\.radiusBottom, \.bulgeBottom, \.radiusX]
        default: [\.radiusX, \.bulgeTop, \.radiusTop]
        }
    }

    func outline(segment: Int, t: Double) -> DragSpec<FaceState> {
        let parameters = Self.outlineParameters(for: segment)
        let index = t < Face.perimeterEndZone ? 0 : (t > 1 - Face.perimeterEndZone ? 2 : 1)

        return d
            .vary(state, paths: [parameters[index]], constraint: { candidate in
                let radii = Constraint.moreThan(candidate.radiusX, Face.minFaceRadius)
                    + Constraint.moreThan(candidate.radiusTop, Face.minFaceRadius)
                    + Constraint.moreThan(candidate.radiusBottom, Face.minFaceRadius)

                return mode.constrainsShape ? radii + shapeConstraints(candidate) : radii
            })
            .during { candidate in
                var result = mode.keepsEyesAboveMouth ? mouthPushedBelowEyes(candidate) : mouthPushedAway(candidate)
                result = eyesPushedAway(result)

                if mode.keepsEyesAboveMouth { result = eyesClampedAboveMouth(result) }

                return featuresClampedInside(result)
            }
    }
}

// MARK: - Rendering

func faceCreator(mode: FaceMode) -> Draggable<FaceState> {
    { context in
        let state = context.state
        let drags = FaceDrags(state: state, d: context.d, mode: mode)
        let curves = state.outline

        return group {
            path(outlineCommands(curves))
                .id("face")
                .fill(Face.skin)
                .stroke(Face.skinEdge, lineWidth: Face.faceStroke)
                .zIndex(.relative(Face.faceZ))

            outlineHandles(curves, context: context, drags: drags)

            for (id, position) in [("left-eye", state.leftEye), ("right-eye", state.rightEye)] {
                circle(radius: Face.eyeRadius)
                    .id(id)
                    .fill(Face.eye)
                    .transform(.translate(position))
                    .zIndex(.relative(Face.featureZ))
                    .onDrag(drags.eyes)
            }

            mouth(state)

            mouthHandles(state, context: context, drags: drags)

            for (id, position) in [("mouth-left", state.mouthLeft), ("mouth-right", state.mouthRight)] {
                circle(radius: Face.endpointRadius)
                    .id(id)
                    .fill(context.draggedID == id ? Face.activeEndpoint : Face.mouth)
                    .stroke(Face.mouth, lineWidth: Face.endpointLineWidth)
                    .transform(.translate(position))
                    .zIndex(.relative(Face.endpointZ))
                    .onDrag(drags.mouthEnds)
            }
        }
    }
}

private func outlineCommands(_ curves: [Cubic]) -> [PathCommand] {
    guard let first = curves.first else { return [] }

    let segments = curves.map { PathCommand.cubic(control1: $0.control1, control2: $0.control2, end: $0.end) }

    return [.move(first.start)] + segments + [.close]
}

private func mouth(_ state: FaceState) -> Node<FaceState> {
    let curve = state.mouthCurve

    return path([.move(curve.start), .cubic(control1: curve.control1, control2: curve.control2, end: curve.end)])
        .id("mouth")
        .stroke(Face.mouth, lineWidth: Face.mouthStroke)
        .zIndex(.relative(Face.featureZ))
        .hitTesting(.disabled)
}

/// Invisible handles around the outline. They sit below the features,
/// so eyes and mouth win any contest for a touch.
private func outlineHandles(
    _ curves: [Cubic],
    context: RenderContext<FaceState>,
    drags: FaceDrags
) -> Node<FaceState> {
    let state = context.state
    let largest = max(state.radiusX, state.radiusTop, state.radiusBottom)
    let hitRadius = max(Face.minPerimeterHitRadius, largest * Face.perimeterHitShare)
    let positions = [0] + (1...Face.perimeterHandleCount).map {
        Double($0) / Double(Face.perimeterHandleCount + 1)
    }

    return group {
        for (segment, curve) in curves.enumerated() {
            for (index, t) in positions.enumerated() {
                let id = "outline-\(segment)-\(index)"
                let isDragged = context.draggedID == id

                circle(radius: isDragged ? Face.draggedPerimeterRadius : hitRadius)
                    .id(id)
                    .fill(isDragged ? Face.skinEdge.withOpacity(Face.handleOpacity) : .clear)
                    .transform(.translate(curve.point(at: t)))
                    .zIndex(.relative(Face.faceZ))
                    .onDrag { drags.outline(segment: segment, t: t) }
            }
        }
    }
}

private func mouthHandles(
    _ state: FaceState,
    context: RenderContext<FaceState>,
    drags: FaceDrags
) -> Node<FaceState> {
    group {
        for index in 1...Face.mouthHandleCount {
            let t = Double(index) / Double(Face.mouthHandleCount + 1)
            let id = "mouth-\(index)"
            let isDragged = context.draggedID == id

            circle(radius: isDragged ? Face.draggedMouthHandleRadius : Face.mouthHandleRadius)
                .id(id)
                .fill(isDragged ? Face.mouth.withOpacity(Face.handleOpacity) : .clear)
                .transform(.translate(state.mouthCurve.point(at: t)))
                .zIndex(.relative(Face.mouthHandleZ))
                .onDrag { drags.mouthCurve(at: t) }
        }
    }
}
