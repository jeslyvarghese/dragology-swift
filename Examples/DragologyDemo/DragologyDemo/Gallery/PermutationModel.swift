import Dragology
import Foundation

// Permutation math for the lab, ported from Dragology's demo. The state
// is a word in the adjacent transpositions s_0 … s_{n-2}, and π comes from
// it. Letters act on positions: s_i swaps entries i and i+1. Permutations
// are written in one-line notation, with values counted from 1.

/// A column of the wiring diagram.
struct PermColumn: Equatable {
    enum Kind: Equatable {
        case letter
        /// Full width but flat, mid-cancel, so nothing to the right moves.
        case blank
        /// No width, after a cancel, so the drop is a plain slide.
        case closed
    }

    var generator: Int
    var kind = Kind.letter

    var isLetter: Bool { kind == .letter }
    var isClosed: Bool { kind == .closed }
}

enum PermTileMode: Equatable {
    case free
    /// Each step writes a letter, and chaining lets one drag write many.
    case adjacent
}

enum PermSolidStyle: Equatable {
    case solid
    case schlegel
}

struct Vec3: Equatable, Sendable {
    var x, y, z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }

    func dot(_ other: Vec3) -> Double { x * other.x + y * other.y + z * other.z }

    func cross(_ other: Vec3) -> Vec3 {
        Vec3(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
    }

    var normalized: Vec3 {
        let length = dot(self).squareRoot()
        return Vec3(x / length, y / length, z / length)
    }
}

/// A rotation, as a unit quaternion.
struct Quaternion: Equatable, Sendable {
    var w, x, y, z: Double

    init(axis: Vec3, angle: Double) {
        let sine = sin(angle / 2)

        w = cos(angle / 2)
        x = axis.x * sine
        y = axis.y * sine
        z = axis.z * sine
    }

    private init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    /// `self` after `other`.
    func multiplied(by other: Quaternion) -> Quaternion {
        Quaternion(
            w: w * other.w - x * other.x - y * other.y - z * other.z,
            x: w * other.x + x * other.w + y * other.z - z * other.y,
            y: w * other.y - x * other.z + y * other.w + z * other.x,
            z: w * other.z + x * other.y - y * other.x + z * other.w
        )
    }

    var normalized: Quaternion {
        let length = (w * w + x * x + y * y + z * z).squareRoot()

        return Quaternion(w: w / length, x: x / length, y: y / length, z: z / length)
    }

    func rotate(_ v: Vec3) -> Vec3 {
        let axis = Vec3(x, y, z)
        let doubled = axis.cross(v)
        let t = Vec3(2 * doubled.x, 2 * doubled.y, 2 * doubled.z)
        let u = axis.cross(t)

        return Vec3(v.x + w * t.x + u.x, v.y + w * t.y + u.y, v.z + w * t.z + u.z)
    }
}

/// How the solid is turned. A drag varies `spinX` and `spinY`, a rotation
/// in the screen plane applied on top, and the drop folds them in. Screen
/// axes can move any grabbed point in both directions; the solid's own
/// axes can't move a point near them sideways.
struct PermView: Equatable {
    var orientation: Quaternion
    var spinX = 0.0
    var spinY = 0.0

    /// Yawed 160°, then pitched −35°, with the walk to the start in front.
    static let initial = PermView(
        orientation: Quaternion(axis: Vec3(1, 0, 0), angle: -35 * .pi / 180)
            .multiplied(by: Quaternion(axis: Vec3(0, 1, 0), angle: 160 * .pi / 180))
    )

    var rotation: Quaternion {
        let angle = hypot(spinX, spinY)

        guard angle != 0 else { return orientation }

        return Quaternion(axis: Vec3(spinX / angle, spinY / angle, 0), angle: angle)
            .multiplied(by: orientation)
    }

    var folded: PermView {
        PermView(orientation: rotation.normalized)
    }
}

struct PermState: Equatable {
    var n: Int
    var word: [PermColumn]
    var mode: PermTileMode
    var style: PermSolidStyle
    var view: PermView
    /// Draw wires with a segment per column, for a braid move.
    var wiresByColumn = false

    var summary: String {
        let digits = PermMath.permutation(n: n, word: word).map(String.init).joined()
        let letters = word.filter { !$0.isClosed }.count
        let turn = String(format: "%.2f", view.orientation.w)

        return "π=\(digits) length \(letters) turn \(turn)"
    }
}

struct PermPreset {
    var title: String
    var state: PermState

    private init(_ title: String, _ start: [Int], _ mode: PermTileMode, _ style: PermSolidStyle) {
        self.title = title

        state = PermState(
            n: start.count,
            word: PermMath.reducedWord(for: start).map { PermColumn(generator: $0) },
            mode: mode,
            style: style,
            view: .initial
        )
    }

    static let all = [
        PermPreset("n = 4, adjacent tiles", [3, 1, 4, 2], .adjacent, .solid),
        PermPreset("n = 4, free tiles", [3, 1, 4, 2], .free, .solid),
        PermPreset("n = 4, Schlegel diagram", [3, 1, 4, 2], .adjacent, .schlegel),
        PermPreset("n = 3, hexagon", [2, 3, 1], .adjacent, .solid),
        PermPreset("n = 5", [3, 5, 1, 4, 2], .free, .solid),
        PermPreset("n = 6", [3, 5, 1, 6, 4, 2], .free, .solid),
        PermPreset("n = 4, identity", [1, 2, 3, 4], .adjacent, .solid),
    ]
}

enum PermMath {
    static func permutation(n: Int, word: [PermColumn]) -> [Int] {
        var result = Array(1...n)

        for column in word where column.isLetter {
            result.swapAt(column.generator, column.generator + 1)
        }

        return result
    }

    static func inversions(_ permutation: [Int]) -> Int {
        permutation.indices.reduce(0) { count, i in
            count + permutation[(i + 1)...].filter { $0 < permutation[i] }.count
        }
    }

    /// A reduced word, by bubble sort: each swap fixes exactly one
    /// inversion, so its length equals the inversion count.
    static func reducedWord(for permutation: [Int]) -> [Int] {
        var rows = permutation
        var swaps: [Int] = []
        var didChange = true

        while didChange {
            didChange = false

            for i in 0..<(rows.count - 1) where rows[i] > rows[i + 1] {
                rows.swapAt(i, i + 1)
                swaps.append(i)
                didChange = true
            }
        }

        return swaps.reversed()
    }

    /// Cycles, each starting at its smallest element, fixed points included.
    static func cycles(of permutation: [Int]) -> [[Int]] {
        var seen = Set<Int>()
        var result: [[Int]] = []

        for start in 1...permutation.count where !seen.contains(start) {
            var cycle: [Int] = []
            var current = start

            while !seen.contains(current) {
                seen.insert(current)
                cycle.append(current)
                current = permutation[current - 1]
            }

            result.append(cycle)
        }

        return result
    }

    static func permutation(n: Int, cycles: [[Int]]) -> [Int] {
        var result = Array(1...n)

        for cycle in cycles {
            for (index, value) in cycle.enumerated() {
                result[value - 1] = cycle[(index + 1) % cycle.count]
            }
        }

        return result
    }

    static func inverse(_ permutation: [Int]) -> [Int] {
        var result = permutation

        for (index, value) in permutation.enumerated() {
            result[value - 1] = index + 1
        }

        return result
    }

    /// Whether `word[start...]` begins s_i s_k s_i with neighboring i, k.
    static func isBraid(_ word: [PermColumn], at start: Int) -> Bool {
        guard start >= 0, start + 2 < word.count else { return false }

        let first = word[start]
        let middle = word[start + 1]
        let last = word[start + 2]

        return first.isLetter && middle.isLetter && last.isLetter
            && first.generator == last.generator
            && abs(first.generator - middle.generator) == 1
    }

    static func braided(_ word: [PermColumn], at start: Int) -> [PermColumn] {
        var result = word

        result[start] = word[start + 1]
        result[start + 1] = word[start]
        result[start + 2] = word[start + 1]

        return result
    }

    /// The first letter of each double s_i s_i that handles treat as a
    /// pair. Runs pair up from the right, so a pair inserted beside an
    /// identical letter is the pair.
    static func doublePairs(_ word: [PermColumn]) -> Set<Int> {
        let matches = { (index: Int, other: PermColumn) in
            word.indices.contains(index) && word[index].isLetter == other.isLetter
                && word[index].generator == other.generator
        }

        var pairs = Set<Int>()
        var index = 0

        while index < word.count {
            var run = 0

            while matches(index + run, word[index]) { run += 1 }

            if run >= 2, run.isMultiple(of: 2) {
                pairs.insert(index)
                index += 2
            } else {
                index += 1
            }
        }

        return pairs
    }

    struct Move {
        var word: [PermColumn]
        var isBraid: Bool
    }

    /// Words reachable by one relation that moves the crossing at `index`.
    static func crossingMoves(_ word: [PermColumn], index: Int) -> [Move] {
        guard word[index].isLetter else { return [] }

        let generator = word[index].generator

        let commutes = { (other: Int) in
            word.indices.contains(other) && word[other].isLetter
                && abs(word[other].generator - generator) >= 2
        }

        let swapped = { (a: Int, b: Int) -> [PermColumn] in
            var copy = word
            copy.swapAt(a, b)
            return copy
        }

        var moves: [Move] = []

        if commutes(index - 1) { moves.append(Move(word: swapped(index - 1, index), isBraid: false)) }
        if commutes(index + 1) { moves.append(Move(word: swapped(index, index + 1), isBraid: false)) }
        if isBraid(word, at: index - 1) { moves.append(Move(word: braided(word, at: index - 1), isBraid: true)) }

        return moves
    }
}

// MARK: - Permutohedra

/// Every permutation as a vertex, with edges for adjacent swaps. A
/// permutation sits at its inverse: swapping adjacent positions then
/// swaps two coordinates that differ by 1, which is an edge of the polytope.
struct Permutohedron: Sendable {
    /// Unit-radius positions, by one-line digits.
    let positions: [String: Vec2]
    let keys: [String]
    let edges: [(String, String)]

    static let hexagon = Permutohedron(n: 3)
    static let schlegel = Permutohedron(n: 4)

    static func key(_ permutation: [Int]) -> String {
        permutation.map(String.init).joined()
    }

    static func allPermutations(_ values: [Int]) -> [[Int]] {
        guard !values.isEmpty else { return [[]] }

        return values.indices.flatMap { index -> [[Int]] in
            var rest = values
            let value = rest.remove(at: index)

            return allPermutations(rest).map { [value] + $0 }
        }
    }

    private static func dot(_ u: [Double], _ v: [Double]) -> Double {
        zip(u, v).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private init(n: Int) {
        let permutations = Self.allPermutations(Array(1...n))
        let middle = Double(n + 1) / 2
        let root2 = 2.0.squareRoot()
        let root6 = 6.0.squareRoot()

        let project: ([Double]) -> Vec2

        if n == 3 {
            let a = [1 / root2, -1 / root2, 0]
            let b = [1 / root6, 1 / root6, -2 / root6]

            project = { Vec2(Self.dot($0, a), Self.dot($0, b)) }
        } else {
            // A Schlegel diagram: the eye is just outside the face where π(4) = 4.
            let eyeDistance = 1.6
            let center = [-0.5, -0.5, -0.5, 1.5]
            let length = Self.dot(center, center).squareRoot()
            let direction = center.map { $0 / length }
            let eye = center.map { $0 * eyeDistance }
            let a = [1 / root2, -1 / root2, 0, 0]
            let b = [1 / root6, 1 / root6, -2 / root6, 0]

            project = { vertex in
                let toEye = zip(eye, vertex).map { $0 - $1 }
                let t = Self.dot(eye, direction) / Self.dot(toEye, direction)
                let projected = zip(eye, vertex).map { $0 + t * ($1 - $0) }

                return Vec2(Self.dot(projected, a), Self.dot(projected, b))
            }
        }

        let raw = permutations.map { permutation -> (String, Vec2) in
            let centered = PermMath.inverse(permutation).map { Double($0) - middle }
            return (Self.key(permutation), project(centered))
        }

        let radius = raw.map(\.1.length).max() ?? 1

        positions = Dictionary(uniqueKeysWithValues: raw.map { ($0.0, $0.1 * (1 / radius)) })
        keys = raw.map(\.0)

        edges = permutations.flatMap { permutation in
            (0..<(n - 1)).compactMap { i -> (String, String)? in
                var swapped = permutation
                swapped.swapAt(i, i + 1)

                let a = Self.key(permutation)
                let b = Self.key(swapped)

                return a < b ? (a, b) : nil
            }
        }
    }
}

/// The n = 4 permutohedron in 3D: a truncated octahedron. Its 14 faces
/// are the nonempty proper subsets S of values, where the first |S|
/// entries of π are S: hexagons for |S| = 1 or 3, squares for |S| = 2.
struct TruncatedOctahedron: Sendable {
    struct Face: Sendable {
        var id: String
        /// Vertices, in order around the face.
        var keys: [String]
        var isSquare: Bool
        var normal: Vec3
    }

    static let shared = TruncatedOctahedron()

    private static var eyeDistance: Double { 4 }
    private static var screenScale: Double { 0.92 }
    private static var light: Vec3 { Vec3(-0.5, 0.7, 0.8).normalized }

    let positions: [String: Vec3]
    let faces: [Face]
    /// For each edge of the 2D layout, the two faces on it.
    let edgeFaces: [(Int, Int)]

    private init() {
        let layout = Permutohedron.schlegel
        let scale = 2 * 5.0.squareRoot()
        let middle = 2.5

        var positions: [String: Vec3] = [:]

        for key in layout.keys {
            let digits = key.compactMap(\.wholeNumberValue)
            let c = PermMath.inverse(digits).map { Double($0) - middle }

            positions[key] = Vec3(
                (c[0] + c[1] - c[2] - c[3]) / scale,
                (c[0] - c[1] + c[2] - c[3]) / scale,
                (c[0] - c[1] - c[2] + c[3]) / scale
            )
        }

        let faces = (1..<15).map { mask -> Face in
            let subset = (1...4).filter { mask & (1 << ($0 - 1)) != 0 }

            let keys = layout.keys.filter { key in
                let digits = key.compactMap(\.wholeNumberValue)
                return subset.allSatisfy { (digits.firstIndex(of: $0) ?? 0) < subset.count }
            }

            let points = keys.compactMap { positions[$0] }
            let count = Double(points.count)
            let center = Vec3(
                points.reduce(0) { $0 + $1.x } / count,
                points.reduce(0) { $0 + $1.y } / count,
                points.reduce(0) { $0 + $1.z } / count
            )

            // Sort the vertices by their angle around the face's center.
            let normal = center.normalized
            let u = (points[0] - center).normalized
            let w = normal.cross(u)
            let angle = { (key: String) -> Double in
                let offset = (positions[key] ?? center) - center
                return atan2(offset.dot(w), offset.dot(u))
            }

            return Face(
                id: "ph-face-" + subset.map(String.init).joined(),
                keys: keys.sorted { angle($0) < angle($1) },
                isSquare: subset.count == 2,
                normal: normal
            )
        }

        self.positions = positions
        self.faces = faces

        edgeFaces = layout.edges.map { a, b in
            let onEdge = faces.indices.filter { faces[$0].keys.contains(a) && faces[$0].keys.contains(b) }
            return (onEdge[0], onEdge[1])
        }
    }

    /// Positive when face `index` is turned toward the eye.
    func facing(_ view: PermView, face index: Int) -> Double {
        let rotation = view.rotation
        let face = faces[index]
        let vertex = positions[face.keys[0]] ?? Vec3(0, 0, 0)
        let toEye = (Vec3(0, 0, Self.eyeDistance) - rotation.rotate(vertex)).normalized

        return rotation.rotate(face.normal).dot(toEye)
    }

    struct Projection {
        var positions: [String: Vec2]
        var points: [[Vec2]]
        var isFront: [Bool]
        var light: [Double]
        var edgeIsFront: [Bool]
    }

    /// Turns the solid and projects it in perspective, with y down.
    func projected(_ view: PermView) -> Projection {
        let rotation = view.rotation

        let screen = positions.mapValues { position -> Vec2 in
            let turned = rotation.rotate(position)
            let perspective = Self.eyeDistance / (Self.eyeDistance - turned.z)

            return Vec2(turned.x * perspective, -turned.y * perspective) * Self.screenScale
        }

        let isFront = faces.indices.map { facing(view, face: $0) > 0 }

        return Projection(
            positions: screen,
            points: faces.map { face in face.keys.compactMap { screen[$0] } },
            isFront: isFront,
            light: faces.map { max(0, rotation.rotate($0.normal).dot(Self.light)) },
            edgeIsFront: edgeFaces.map { isFront[$0.0] || isFront[$0.1] }
        )
    }
}
