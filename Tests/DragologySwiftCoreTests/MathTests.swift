import Testing
@testable import DragologySwiftCore

@Suite struct TriangulationTests {
    @Test func twoPointsBlendAlongTheirEdge() {
        let triangulation = Triangulation(points: [Vec2(0, 0), Vec2(100, 0)])
        let projection = triangulation.project(Vec2(25, 40))

        #expect(abs((projection.weights[0] ?? 0) - 0.75) < 1e-9)
        #expect(abs((projection.weights[1] ?? 0) - 0.25) < 1e-9)
        #expect(abs(projection.distance - 40) < 1e-9)
    }

    @Test func insideATriangleWeightsSumToOne() {
        let triangulation = Triangulation(points: [Vec2(0, 0), Vec2(100, 0), Vec2(0, 100)])
        let projection = triangulation.project(Vec2(25, 25))

        #expect(projection.distance == 0)
        #expect(abs(projection.weights.values.reduce(0, +) - 1) < 1e-9)
        #expect(abs((projection.weights[0] ?? 0) - 0.5) < 1e-9)
    }

    @Test func cocircularGridIsCoveredWithoutGaps() {
        let grid = (0..<4).flatMap { x in (0..<4).map { y in Vec2(Double(x) * 50, Double(y) * 50) } }
        let triangulation = Triangulation(points: grid)

        // Every interior sample must land in a triangle, not on an edge.
        for x in stride(from: 1.0, to: 150, by: 7) {
            for y in stride(from: 1.0, to: 150, by: 7) {
                #expect(triangulation.project(Vec2(x, y)).distance == 0)
            }
        }
    }

    @Test func collinearPointsProjectOntoTheLine() {
        let triangulation = Triangulation(points: [Vec2(0, 0), Vec2(200, 0), Vec2(100, 0)])
        let projection = triangulation.project(Vec2(150, 30))

        #expect(abs((projection.weights[1] ?? 0) - 0.5) < 1e-9)
        #expect(abs((projection.weights[2] ?? 0) - 0.5) < 1e-9)
    }

    @Test func coincidentPointsAreReported() {
        let triangulation = Triangulation(points: [Vec2(5, 5), Vec2(5, 5), Vec2(50, 5)])

        #expect(triangulation.coincidentIndices == [1])
    }
}

@Suite struct DistanceMinimizerTests {
    @Test func reachesAnUnconstrainedTarget() {
        var minimizer = DistanceMinimizer(parameters: [0, 0])
        minimizer.minimize(target: Vec2(30, -40)) { Vec2($0[0], $0[1]) }

        #expect(abs(minimizer.parameters[0] - 30) < 1e-3)
        #expect(abs(minimizer.parameters[1] + 40) < 1e-3)
    }

    @Test func stopsAtAConstraint() {
        var minimizer = DistanceMinimizer(parameters: [100])
        minimizer.minimize(
            target: Vec2(500, 0),
            position: { Vec2($0[0], 0) },
            constraints: { Constraint.inOrder(0, $0[0], 240) }
        )

        #expect(abs(minimizer.parameters[0] - 240) < 1e-6)
    }

    @Test func slidesAlongAConstraintInTwoDimensions() {
        var minimizer = DistanceMinimizer(parameters: [10, 10])
        minimizer.minimize(
            target: Vec2(500, 70),
            position: { Vec2($0[0], $0[1]) },
            constraints: { Constraint.lessThan($0[0], 100) }
        )

        // x hits its limit, but y must still reach the target.
        #expect(abs(minimizer.parameters[0] - 100) < 1e-6)
        #expect(abs(minimizer.parameters[1] - 70) < 1e-3)
    }

    @Test func followsAnAngleAroundACircle() {
        var minimizer = DistanceMinimizer(parameters: [0.1])
        let onCircle = { (parameters: [Double]) in
            Vec2(100 * Foundation_cos(parameters[0]), 100 * Foundation_sin(parameters[0]))
        }

        minimizer.minimize(target: Vec2(0, 200), position: onCircle)

        #expect(abs(minimizer.parameters[0] - Double.pi / 2) < 1e-3)
    }

    @Test func mixedUnitsConverge() {
        // A parameter worth 1000 points per unit, next to one worth 0.01.
        var minimizer = DistanceMinimizer(parameters: [0, 0])
        minimizer.minimize(target: Vec2(250, 3)) { Vec2($0[0] * 1000, $0[1] * 0.01) }

        #expect(abs(minimizer.parameters[0] - 0.25) < 1e-3)
        #expect(abs(minimizer.parameters[1] - 300) < 1)
    }
}

import Foundation

private func Foundation_cos(_ value: Double) -> Double { cos(value) }
private func Foundation_sin(_ value: Double) -> Double { sin(value) }
