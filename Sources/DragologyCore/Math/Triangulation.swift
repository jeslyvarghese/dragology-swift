import Foundation

/// A Delaunay triangulation of a handful of drop targets, used by
/// `between` to turn a pointer position into blend weights.
///
/// Target counts are small, so this favors a short Bowyer-Watson
/// implementation over asymptotic speed.
struct Triangulation {
    /// Where a query point landed, as blend weights by input index.
    struct Projection {
        var weights: [Int: Double]
        var point: Vec2
        var distance: Double
    }

    private enum Tolerance {
        /// Points closer than this count as the same target.
        static let coincident = 1e-9
        /// Relative area below which a point set counts as collinear.
        static let collinear = 1e-9
        /// Shrinks circumcircles slightly, so cocircular grids stay stable.
        static let circumcircle = 1e-12
        /// Slack on barycentric coordinates at triangle edges.
        static let barycentric = 1e-9
    }

    /// How far the enclosing super-triangle sits, in point-set spans.
    private static let superTriangleScale = 1e4

    private struct Triangle {
        var a: Int
        var b: Int
        var c: Int
    }

    private struct Edge: Hashable {
        var low: Int
        var high: Int

        init(_ a: Int, _ b: Int) {
            low = min(a, b)
            high = max(a, b)
        }
    }

    /// Distinct points, and each one's index in the original input.
    private let points: [Vec2]
    private let inputIndices: [Int]
    private let triangles: [Triangle]
    private let edges: [Edge]

    /// The input indices dropped because they repeat an earlier point.
    let coincidentIndices: [Int]

    init(points input: [Vec2]) {
        // Keep the first of any coincident points: two targets in one
        // place can't be told apart by position.
        var distinct: [Vec2] = []
        var indices: [Int] = []
        var duplicates: [Int] = []

        for (index, point) in input.enumerated() {
            let isDuplicate = distinct.contains {
                $0.distance(to: point) < Tolerance.coincident
            }

            if isDuplicate {
                duplicates.append(index)
                continue
            }

            distinct.append(point)
            indices.append(index)
        }

        points = distinct
        inputIndices = indices
        coincidentIndices = duplicates

        // Collinear points have no triangles: chain them along the line.
        if let chain = Self.collinearChain(distinct) {
            triangles = []
            edges = zip(chain, chain.dropFirst()).map { Edge($0, $1) }
            return
        }

        triangles = Self.bowyerWatson(distinct)
        edges = Array(Set(triangles.flatMap { triangle in
            [
                Edge(triangle.a, triangle.b),
                Edge(triangle.b, triangle.c),
                Edge(triangle.c, triangle.a),
            ]
        }))
    }

    /// Blend weights for `query`, projecting onto the hull if it's outside.
    func project(_ query: Vec2) -> Projection {
        if let inside = containingTriangleProjection(query) {
            return inside
        }

        // Outside the hull, the nearest point on any edge is on the hull.
        var best = nearestVertexProjection(query)

        for edge in edges {
            let start = points[edge.low]
            let span = points[edge.high] - start
            let t = min(max((query - start).dot(span) / span.lengthSquared, 0), 1)
            let point = start + span * t
            let distance = point.distance(to: query)

            guard distance < best.distance else { continue }

            best = Projection(
                weights: [
                    inputIndices[edge.low]: 1 - t,
                    inputIndices[edge.high]: t,
                ],
                point: point,
                distance: distance
            )
        }

        return best
    }

    /// Sibson weights for `query`, which vary more smoothly than a
    /// triangle's. Each target's weight is the share of the query's
    /// Voronoi cell taken from that target's own cell. Falls back to
    /// `project` on the hull and beyond, where the two agree.
    func naturalNeighbors(_ query: Vec2) -> Projection {
        let projection = project(query)

        guard projection.distance == 0, !triangles.isEmpty else { return projection }

        let isOnTarget = points.contains { $0.distance(to: query) < Tolerance.coincident }

        guard !isOnTarget else { return projection }

        // The query's cell if it joined the targets.
        let queryCell = points.reduce(boundingPolygon()) { cell, point in
            Self.clip(cell, closerTo: query, than: point)
        }

        // Carve that cell up by which target owned each piece.
        var areas: [Int: Double] = [:]

        for (index, point) in points.enumerated() {
            let stolen = points.reduce(queryCell) { cell, other in
                other == point ? cell : Self.clip(cell, closerTo: point, than: other)
            }

            areas[inputIndices[index]] = Self.area(of: stolen)
        }

        let total = areas.values.reduce(0, +)

        guard total > 0 else { return projection }

        return Projection(
            weights: areas.mapValues { $0 / total },
            point: query,
            distance: 0
        )
    }

    /// A box far outside the targets, standing in for the whole plane.
    private func boundingPolygon() -> [Vec2] {
        let bounds = points.reduce(into: (min: points[0], max: points[0])) { box, point in
            box.min = Vec2(min(box.min.x, point.x), min(box.min.y, point.y))
            box.max = Vec2(max(box.max.x, point.x), max(box.max.y, point.y))
        }

        let span = max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y, 1)
        let margin = span * Self.superTriangleScale

        return [
            Vec2(bounds.min.x - margin, bounds.min.y - margin),
            Vec2(bounds.max.x + margin, bounds.min.y - margin),
            Vec2(bounds.max.x + margin, bounds.max.y + margin),
            Vec2(bounds.min.x - margin, bounds.max.y + margin),
        ]
    }

    /// Keeps the part of a convex polygon closer to `near` than `far`.
    private static func clip(_ polygon: [Vec2], closerTo near: Vec2, than far: Vec2) -> [Vec2] {
        let normal = far - near
        let midpoint = (near + far) * 0.5
        let side = { (point: Vec2) in (point - midpoint).dot(normal) }

        var result: [Vec2] = []

        for (index, current) in polygon.enumerated() {
            let next = polygon[(index + 1) % polygon.count]
            let sideCurrent = side(current)
            let sideNext = side(next)

            if sideCurrent <= 0 {
                result.append(current)
            }

            // Add the crossing point when an edge straddles the bisector.
            if (sideCurrent < 0) != (sideNext < 0), sideCurrent != sideNext {
                result.append(Vec2.lerp(current, next, sideCurrent / (sideCurrent - sideNext)))
            }
        }

        return result
    }

    /// Shoelace formula.
    private static func area(of polygon: [Vec2]) -> Double {
        let doubled = polygon.indices.reduce(0.0) { sum, index in
            sum + polygon[index].cross(polygon[(index + 1) % polygon.count])
        }

        return abs(doubled) / 2
    }

    private func containingTriangleProjection(_ query: Vec2) -> Projection? {
        for triangle in triangles {
            let a = points[triangle.a]
            let b = points[triangle.b]
            let c = points[triangle.c]

            let area = (b - a).cross(c - a)
            guard area != 0 else { continue }

            let weightB = (query - a).cross(c - a) / area
            let weightC = (b - a).cross(query - a) / area
            let weightA = 1 - weightB - weightC

            let isInside = [weightA, weightB, weightC].allSatisfy {
                $0 >= -Tolerance.barycentric
            }
            guard isInside else { continue }

            return Projection(
                weights: [
                    inputIndices[triangle.a]: weightA,
                    inputIndices[triangle.b]: weightB,
                    inputIndices[triangle.c]: weightC,
                ],
                point: query,
                distance: 0
            )
        }

        return nil
    }

    private func nearestVertexProjection(_ query: Vec2) -> Projection {
        let nearest = points.indices.min {
            points[$0].distanceSquared(to: query) < points[$1].distanceSquared(to: query)
        }

        guard let nearest else {
            return Projection(weights: [:], point: query, distance: .infinity)
        }

        return Projection(
            weights: [inputIndices[nearest]: 1],
            point: points[nearest],
            distance: points[nearest].distance(to: query)
        )
    }

    /// Point indices in order along their line, or nil if not collinear.
    private static func collinearChain(_ points: [Vec2]) -> [Int]? {
        guard let origin = points.first else { return [] }

        guard let farthest = points.max(by: {
            $0.distanceSquared(to: origin) < $1.distanceSquared(to: origin)
        }) else {
            return nil
        }

        let axis = farthest - origin
        let scale = axis.lengthSquared

        // A single point has no axis, and is trivially collinear.
        guard scale > 0 else { return Array(points.indices) }

        let isCollinear = points.allSatisfy {
            abs(axis.cross($0 - origin)) <= Tolerance.collinear * scale
        }
        guard isCollinear else { return nil }

        return points.indices.sorted {
            axis.dot(points[$0] - origin) < axis.dot(points[$1] - origin)
        }
    }

    private static func bowyerWatson(_ points: [Vec2]) -> [Triangle] {
        // Enclose everything in a huge triangle, with three extra vertices.
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        let center = Vec2((minX + maxX) / 2, (minY + maxY) / 2)
        let reach = max(maxX - minX, maxY - minY, 1) * superTriangleScale

        let vertices = points + [
            center + Vec2(-reach, -reach),
            center + Vec2(reach, -reach),
            center + Vec2(0, reach),
        ]
        let firstSuperVertex = points.count

        var triangles = [
            Triangle(a: firstSuperVertex, b: firstSuperVertex + 1, c: firstSuperVertex + 2),
        ]

        // Insert each point, re-triangulating the cavity it opens up.
        for index in points.indices {
            let point = vertices[index]
            let isBad = { (triangle: Triangle) in
                circumcircleContains(triangle, point, in: vertices)
            }

            // Edges used by exactly one bad triangle bound the cavity.
            var edgeUses: [Edge: Int] = [:]
            for triangle in triangles where isBad(triangle) {
                edgeUses[Edge(triangle.a, triangle.b), default: 0] += 1
                edgeUses[Edge(triangle.b, triangle.c), default: 0] += 1
                edgeUses[Edge(triangle.c, triangle.a), default: 0] += 1
            }

            triangles.removeAll(where: isBad)

            for (edge, uses) in edgeUses where uses == 1 {
                triangles.append(Triangle(a: edge.low, b: edge.high, c: index))
            }
        }

        // Drop everything still attached to the scaffolding.
        return triangles.filter {
            $0.a < firstSuperVertex && $0.b < firstSuperVertex && $0.c < firstSuperVertex
        }
    }

    private static func circumcircleContains(
        _ triangle: Triangle,
        _ point: Vec2,
        in vertices: [Vec2]
    ) -> Bool {
        let a = vertices[triangle.a]
        let b = vertices[triangle.b]
        let c = vertices[triangle.c]

        let determinant = 2 * (b - a).cross(c - a)
        guard determinant != 0 else { return false }

        // Circumcenter, relative to `a` to preserve precision.
        let ab = b - a
        let ac = c - a
        let offset = Vec2(
            (ac.y * ab.lengthSquared - ab.y * ac.lengthSquared) / determinant,
            (ab.x * ac.lengthSquared - ac.x * ab.lengthSquared) / determinant
        )

        let radiusSquared = offset.lengthSquared
        let distanceSquared = (a + offset).distanceSquared(to: point)

        return distanceSquared < radiusSquared * (1 - Tolerance.circumcircle)
    }
}
