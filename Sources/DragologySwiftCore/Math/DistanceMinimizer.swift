import Foundation

/// Finds parameters that bring a point as close as possible to a
/// target, subject to inequality constraints (`value <= 0` is satisfied).
///
/// This drives `vary`. Upstream Dragology uses COBYLA, which is
/// derivative-free; this is a damped Gauss-Newton solver with an active
/// set instead. `vary` problems are tiny least-squares fits (a 2D
/// residual over one or two parameters), which this solves in very few
/// evaluations. Each evaluation is a speculative render, so that's what
/// matters. It does assume the point moves smoothly with the parameters.
///
/// Stateful: each call warm-starts from the previous solution.
struct DistanceMinimizer {
    private enum Limits {
        static let maxIterations = 16
        /// Damping starts small, and adapts as steps succeed or fail.
        static let initialDamping = 1e-6
        static let maxDamping = 1e8
        static let dampingDecrease = 0.25
        static let dampingIncrease = 8.0
        /// Finite-difference step, relative to each parameter's size.
        static let differenceStep = 1e-6
        /// Squared pixels: closer than this is close enough.
        static let convergedCost = 1e-8
        /// Smallest relative improvement worth another iteration.
        static let minImprovement = 1e-7
        /// Keeps parameters that don't move the point from going singular.
        static let curvatureFloor = 1e-9
        /// Weight of constraint violation in step acceptance.
        static let violationPenalty = 1e4
        static let constraintTolerance = 1e-9
        static let multiplierTolerance = 1e-9
        static let gradientFloor = 1e-12
    }

    private(set) var parameters: [Double]

    init(parameters: [Double]) {
        self.parameters = parameters
    }

    mutating func minimize(
        target: Vec2,
        position: ([Double]) -> Vec2?,
        constraints: (([Double]) -> [Double])? = nil
    ) {
        func constraintValues(_ x: [Double]) -> [Double] {
            constraints?(x) ?? []
        }

        // Combine distance and violation, to compare candidate steps.
        func merit(_ x: [Double]) -> Double {
            guard let point = position(x), point.isFinite else { return .infinity }

            let violation = constraintValues(x).reduce(0) { sum, value in
                let excess = max(value, 0)
                return sum + excess * excess
            }

            return point.distanceSquared(to: target) + Limits.violationPenalty * violation
        }

        var current = parameters
        var currentMerit = merit(current)
        var damping = Limits.initialDamping

        for _ in 0..<Limits.maxIterations {
            guard currentMerit > Limits.convergedCost else { break }
            guard let origin = position(current), origin.isFinite else { break }

            let jacobian = Self.pointJacobian(at: current, origin: origin, position: position)
            let values = constraintValues(current)
            let gradients = Self.constraintGradients(at: current, values: values, of: constraintValues)

            // Raise damping until a step improves things, or give up.
            var accepted = false

            while damping <= Limits.maxDamping {
                let step = Self.solveStep(
                    jacobian: jacobian,
                    residual: target - origin,
                    constraintValues: values,
                    constraintGradients: gradients,
                    damping: damping
                )
                let (candidate, candidateMerit) = bestAlong(
                    step,
                    from: current,
                    currentMerit: currentMerit,
                    slope: Self.meritSlope(jacobian, residual: target - origin, step: step),
                    merit: merit
                )

                if candidateMerit < currentMerit {
                    let improvement = (currentMerit - candidateMerit) / currentMerit

                    current = candidate
                    currentMerit = candidateMerit
                    damping = max(damping * Limits.dampingDecrease, Limits.initialDamping)
                    accepted = improvement > Limits.minImprovement
                    break
                }

                damping *= Limits.dampingIncrease
            }

            guard accepted else { break }
        }

        parameters = current
    }

    /// Tries the full step, then the minimum of the parabola through what's
    /// known along it. When the target is out of reach, such as a finger
    /// outside a dial, Gauss-Newton steps overshoot; this reins them in.
    private func bestAlong(
        _ step: [Double],
        from start: [Double],
        currentMerit: Double,
        slope: Double,
        merit: ([Double]) -> Double
    ) -> (point: [Double], merit: Double) {
        let full = zip(start, step).map { $0 + $1 }
        let fullMerit = merit(full)

        // The parabola needs to curve upwards to have a minimum.
        let curvature = fullMerit - currentMerit - slope

        guard slope < 0, curvature > 0, fullMerit.isFinite else { return (full, fullMerit) }

        let fraction = -slope / (2 * curvature)

        guard fraction < 1 else { return (full, fullMerit) }

        let partial = zip(start, step).map { $0 + fraction * $1 }
        let partialMerit = merit(partial)

        return partialMerit < fullMerit ? (partial, partialMerit) : (full, fullMerit)
    }

    /// The rate of change of squared distance along `step`.
    private static func meritSlope(_ jacobian: [Vec2], residual: Vec2, step: [Double]) -> Double {
        let gradientDotStep = zip(jacobian, step).reduce(0.0) { sum, entry in
            sum + entry.0.dot(residual) * entry.1
        }

        return -2 * gradientDotStep
    }

    /// One column of pixel movement per parameter, by forward differences.
    private static func pointJacobian(
        at x: [Double],
        origin: Vec2,
        position: ([Double]) -> Vec2?
    ) -> [Vec2] {
        x.indices.map { index in
            var nudged = x
            let step = differenceStep(for: x[index])
            nudged[index] += step

            guard let moved = position(nudged), moved.isFinite else { return .zero }

            return (moved - origin) * (1 / step)
        }
    }

    /// One gradient row per constraint, by forward differences.
    private static func constraintGradients(
        at x: [Double],
        values: [Double],
        of constraintValues: ([Double]) -> [Double]
    ) -> [[Double]] {
        guard !values.isEmpty else { return [] }

        var rows = Array(repeating: Array(repeating: 0.0, count: x.count), count: values.count)

        for column in x.indices {
            var nudged = x
            let step = differenceStep(for: x[column])
            nudged[column] += step

            for (row, moved) in constraintValues(nudged).enumerated() {
                rows[row][column] = (moved - values[row]) / step
            }
        }

        return rows
    }

    private static func differenceStep(for value: Double) -> Double {
        Limits.differenceStep * max(abs(value), 1)
    }

    /// Solves the damped least-squares step, holding violated linearized
    /// constraints at equality (a small primal active-set method).
    private static func solveStep(
        jacobian: [Vec2],
        residual: Vec2,
        constraintValues: [Double],
        constraintGradients: [[Double]],
        damping: Double
    ) -> [Double] {
        let count = jacobian.count

        // Normal equations, with Marquardt scaling so that parameters in
        // different units (pixels, radians) are damped comparably.
        var hessian = Array(repeating: Array(repeating: 0.0, count: count), count: count)
        var gradient = Array(repeating: 0.0, count: count)

        for row in 0..<count {
            gradient[row] = jacobian[row].dot(residual)

            for column in 0..<count {
                hessian[row][column] = jacobian[row].dot(jacobian[column])
            }

            hessian[row][row] += damping * max(hessian[row][row], Limits.curvatureFloor)
        }

        // A constraint without a gradient can't be acted on.
        let usable = constraintGradients.indices.filter { index in
            constraintGradients[index].contains { abs($0) > Limits.gradientFloor }
        }

        var active: [Int] = []
        var best = Array(repeating: 0.0, count: count)

        // Each pass adds the worst violation, or drops a constraint that's
        // pushing the wrong way. Bounded, as cycling is possible.
        for _ in 0...(2 * usable.count + 1) {
            guard let (step, multipliers) = solveKKT(
                hessian: hessian,
                gradient: gradient,
                active: active,
                constraintValues: constraintValues,
                constraintGradients: constraintGradients
            ) else {
                return best
            }

            best = step

            let violation = { (index: Int) -> Double in
                constraintValues[index] + dot(constraintGradients[index], step)
            }
            let worst = usable
                .filter { !active.contains($0) && violation($0) > Limits.constraintTolerance }
                .max { violation($0) < violation($1) }

            if let worst {
                active.append(worst)
                continue
            }

            // Feasible. A negative multiplier means that constraint is
            // holding the step back for no reason, so release it.
            let release = multipliers.indices
                .filter { multipliers[$0] < -Limits.multiplierTolerance }
                .min { multipliers[$0] < multipliers[$1] }

            guard let release else { return step }

            active.remove(at: release)
        }

        return best
    }

    /// Solves `[H Aᵀ; A 0] [step; λ] = [g; -c]` for the active constraints.
    private static func solveKKT(
        hessian: [[Double]],
        gradient: [Double],
        active: [Int],
        constraintValues: [Double],
        constraintGradients: [[Double]]
    ) -> (step: [Double], multipliers: [Double])? {
        let count = gradient.count
        let size = count + active.count
        var matrix = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        var rhs = Array(repeating: 0.0, count: size)

        for row in 0..<count {
            rhs[row] = gradient[row]

            for column in 0..<count {
                matrix[row][column] = hessian[row][column]
            }
        }

        for (offset, constraint) in active.enumerated() {
            let index = count + offset
            rhs[index] = -constraintValues[constraint]

            for column in 0..<count {
                matrix[index][column] = constraintGradients[constraint][column]
                matrix[column][index] = constraintGradients[constraint][column]
            }
        }

        guard let solution = solveLinearSystem(matrix, rhs) else { return nil }

        return (Array(solution[..<count]), Array(solution[count...]))
    }

    /// Gaussian elimination with partial pivoting. Nil if singular.
    private static func solveLinearSystem(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix
        var b = rhs
        let size = b.count

        for pivot in 0..<size {
            guard let best = (pivot..<size).max(by: { abs(a[$0][pivot]) < abs(a[$1][pivot]) }) else {
                return nil
            }
            guard abs(a[best][pivot]) > Limits.gradientFloor else { return nil }

            a.swapAt(pivot, best)
            b.swapAt(pivot, best)

            for row in (pivot + 1)..<size {
                let factor = a[row][pivot] / a[pivot][pivot]
                guard factor != 0 else { continue }

                for column in pivot..<size {
                    a[row][column] -= factor * a[pivot][column]
                }

                b[row] -= factor * b[pivot]
            }
        }

        // Back-substitute from the last row up.
        var solution = Array(repeating: 0.0, count: size)

        for row in (0..<size).reversed() {
            let known = ((row + 1)..<size).reduce(0.0) { $0 + a[row][$1] * solution[$1] }
            solution[row] = (b[row] - known) / a[row][row]
        }

        return solution
    }

    private static func dot(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }
}

/// Helpers for `vary` constraints. Each returns values that must end
/// up `<= 0`, so they can be concatenated with `+`.
public enum DragConstraint {
    public static func lessThan(_ a: Double, _ b: Double) -> [Double] { [a - b] }
    public static func moreThan(_ a: Double, _ b: Double) -> [Double] { [b - a] }
    public static func equal(_ a: Double, _ b: Double) -> [Double] { [a - b, b - a] }

    /// Keeps numbers in ascending order: `inOrder(0, s.value, 240)`.
    public static func inOrder(_ values: Double...) -> [Double] {
        zip(values, values.dropFirst()).map { $0 - $1 }
    }
}
