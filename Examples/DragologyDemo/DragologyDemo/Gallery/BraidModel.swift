import DragologySwift
import Foundation

// The braid group B_n, ported from Dragology's braid demo.
//
// The state is a word in the generators σ_i and their inverses. Letters
// act on positions: σ_i crosses the strands in rows i and i+1 (counting
// from 0), and the strand in row i passes over when the sign is positive.
// Strands are numbered from 1, by their row at the left end.

enum BraidSign: Equatable {
    case positive, negative

    var inverse: BraidSign { self == .positive ? .negative : .positive }
}

/// What a column is, when it isn't a plain crossing.
enum BraidGap: Equatable {
    /// Full width with no crossing, standing in for a cancelled letter
    /// mid-drag, so that nothing to the right shifts.
    case blank
    /// No width at all, so the drop animates as a plain slide.
    case closed
    /// A crossing `p` of the way done, while a point is being turned.
    case pending
}

/// A column of the diagram: a letter, or a gap standing in for one.
struct BraidColumn: Equatable {
    var i: Int
    var sign: BraidSign
    var gap: BraidGap?
    var p = 0.0
    /// A crossing with no width, which swaps its strands all the same.
    /// Only used to start a stabilization at the front of the word.
    var isFlat = false

    var isLetter: Bool { gap == nil }
    var isClosed: Bool { gap == .closed }
    var isPending: Bool { gap == .pending }

    /// Whether this is part of the logical word, as a letter or a blank.
    var isInWord: Bool { !isClosed && !isPending }

    /// This column, as a plain letter.
    var letter: BraidColumn { BraidColumn(i: i, sign: sign) }
}

/// A conjugation in progress: the last crossing is `t` of the way around
/// its loops to the front.
struct BraidOrbit: Equatable {
    var t: Double
    var id: String
}

struct BraidState: Equatable {
    var n: Int
    var word: [BraidColumn]
    /// Draw strands with one piece per column, for a braid move on the
    /// letters from this index. Without it, a piece per crossing.
    var wiresByColumn: Int?
    /// Draw the closure, with the Markov moves.
    var isClosure = false
    var palette: [Int]?
    /// Mid-stabilization: the last row lies on the one above it, with
    /// this strand hidden, so it's drawn as the braid without them.
    var newRowStrand: Int?
    var orbit: BraidOrbit?

    /// The logical word, as signed generator numbers.
    var summary: String {
        let letters = word.filter(\.isInWord).map { letter -> String in
            let generator = letter.i + 1
            return String(letter.sign == .positive ? generator : -generator)
        }

        return "n=\(n) " + (letters.isEmpty ? "e" : letters.joined(separator: " "))
    }
}

/// A braid to start from.
struct BraidPreset {
    var title: String
    var state: BraidState

    private init(_ title: String, n: Int, word: [Int], isClosure: Bool) {
        self.title = title

        let letters = word.map { generator in
            BraidColumn(i: abs(generator) - 1, sign: generator > 0 ? .positive : .negative)
        }

        state = BraidState(n: n, word: letters, isClosure: isClosure)
    }

    private static func open(_ n: Int, _ word: [Int]) -> BraidPreset {
        BraidPreset("\(n) strands", n: n, word: word, isClosure: false)
    }

    private static func closed(_ title: String, _ n: Int, _ word: [Int]) -> BraidPreset {
        BraidPreset(title, n: n, word: word, isClosure: true)
    }

    /// Open braids with a commutation and a braid move ready to try, then
    /// links: first in as few strands as they can be, then in more, to be
    /// reduced with Markov moves.
    static let all = [
        open(4, [1, -3, 2, 1, 2]),
        open(3, [1, 2, 1, -2]),
        open(2, [1, 1, -1]),
        open(5, [1, -3, 4, 2, 1, 2]),
        open(6, [1, -3, 5, 4, 2, 1, 2]),
        closed("closed: 4 strands", 4, [1, -3, 2, 1, 2]),
        closed("unknot", 1, []),
        closed("Hopf link", 2, [1, 1]),
        closed("trefoil", 2, [1, 1, 1]),
        closed("cinquefoil", 2, [1, 1, 1, 1, 1]),
        closed("figure-eight", 3, [1, -2, 1, -2]),
        closed("Borromean rings", 3, [1, -2, 1, -2, 1, -2]),
        closed("(3, 4) torus knot", 3, [1, 2, 1, 2, 1, 2, 1, 2]),
        closed("unknot (4 strands)", 4, [1, -2, 3]),
        closed("Hopf link (3 strands)", 3, [1, 1, 1, 2, -1]),
        closed("trefoil (3 strands)", 3, [1, 2, 1, 2]),
        closed("figure-eight (4 strands)", 4, [2, 1, -2, 1, -2, 3, -2]),
    ]
}

// MARK: - Braid math

enum BraidMath {
    /// The strand in each row after `word`.
    static func permutation(n: Int, word: [BraidColumn]) -> [Int] {
        var rows = Array(1...max(n, 1))

        for column in word where column.isLetter {
            rows.swapAt(column.i, column.i + 1)
        }

        return rows
    }

    /// The row a strand in row `row` is in after `column`.
    static func rowAfter(_ row: Int, _ column: BraidColumn) -> Int {
        guard column.isLetter, row == column.i || row == column.i + 1 else { return row }

        return row == column.i ? column.i + 1 : column.i
    }

    struct Crossing {
        var a: Int
        var b: Int
        var over: Int
    }

    /// For each column, the strands in its two rows just before it, and
    /// which of them passes over.
    static func crossings(n: Int, columns: [BraidColumn]) -> [Crossing] {
        var rows = Array(1...max(n, 1))

        return columns.map { column in
            let a = rows[column.i]
            let b = rows[column.i + 1]

            if column.isLetter {
                rows.swapAt(column.i, column.i + 1)
            }

            return Crossing(a: a, b: b, over: column.sign == .positive ? a : b)
        }
    }

    static func pairKey(_ a: Int, _ b: Int) -> String {
        "\(min(a, b))-\(max(a, b))"
    }

    /// Whether Reidemeister III applies at `start`: σ_i σ_k σ_i with
    /// neighboring generators, and some strand over both of the others.
    static func isBraid(n: Int, word: [BraidColumn], at start: Int) -> Bool {
        guard start >= 0, start + 2 < word.count else { return false }

        let first = word[start]
        let middle = word[start + 1]
        let last = word[start + 2]

        guard first.i == last.i, abs(first.i - middle.i) == 1 else { return false }

        let overs = crossings(n: n, columns: word)[start...(start + 2)].map(\.over)

        return overs.contains { strand in overs.filter { $0 == strand }.count == 2 }
    }

    /// Applies the braid move at `start`: the generators go i k i → k i k,
    /// with signs chosen so each pair of strands keeps the same one on top.
    static func braided(n: Int, word: [BraidColumn], at start: Int) -> [BraidColumn] {
        let before = crossings(n: n, columns: word)[start...(start + 2)]
        let overOf = Dictionary(uniqueKeysWithValues: before.map { (pairKey($0.a, $0.b), $0.over) })

        let outer = word[start + 1].i
        let inner = word[start].i
        var result = word

        result[start] = BraidColumn(i: outer, sign: .positive)
        result[start + 1] = BraidColumn(i: inner, sign: .positive)
        result[start + 2] = BraidColumn(i: outer, sign: .positive)

        let after = crossings(n: n, columns: result)

        for index in start...(start + 2) {
            let crossing = after[index]
            let isFirstOver = overOf[pairKey(crossing.a, crossing.b)] == crossing.a

            result[index].sign = isFirstOver ? .positive : .negative
        }

        return result
    }

    /// Whether two neighboring columns cancel: σ_i σ_i⁻¹, or the two gaps
    /// standing in for such a pair.
    static func cancels(_ a: BraidColumn?, _ b: BraidColumn?) -> Bool {
        guard let a, let b, a.i == b.i else { return false }
        guard (a.gap != nil) == (b.gap != nil) else { return false }

        return a.gap != nil || a.sign != b.sign
    }

    struct Move {
        var word: [BraidColumn]
        var isBraid: Bool
    }

    /// Words reachable by one relation that moves the crossing at `index`:
    /// commuting with a neighbor, or a braid move from the middle crossing.
    static func crossingMoves(n: Int, word: [BraidColumn], index: Int) -> [Move] {
        let generator = word[index].i

        let commutes = { (other: Int) in
            word.indices.contains(other) && abs(word[other].i - generator) >= 2
        }

        let swapped = { (a: Int, b: Int) -> [BraidColumn] in
            var copy = word
            copy.swapAt(a, b)
            return copy
        }

        var moves: [Move] = []

        if commutes(index - 1) {
            moves.append(Move(word: swapped(index - 1, index), isBraid: false))
        }

        if commutes(index + 1) {
            moves.append(Move(word: swapped(index, index + 1), isBraid: false))
        }

        if isBraid(n: n, word: word, at: index - 1) {
            moves.append(Move(word: braided(n: n, word: word, at: index - 1), isBraid: true))
        }

        return moves
    }

    /// A color for each strand's link component in the closure, where a
    /// strand ending in row r continues as strand r+1. Components keep the
    /// color hinted for their lowest strand, unless it's taken.
    static func recolored(n: Int, columns: [BraidColumn], hint: [Int]?, colorCount: Int) -> [Int] {
        let halfway = 0.5
        var rows = Array(1...max(n, 1))

        for column in columns where !(column.isPending && column.p <= halfway) {
            rows.swapAt(column.i, column.i + 1)
        }

        var palette = [Int?](repeating: nil, count: n)
        var used = Set<Int>()

        for strand in 1...max(n, 1) where palette[strand - 1] == nil {
            let hinted = hint.flatMap { $0.indices.contains(strand - 1) ? $0[strand - 1] : nil }
            let color: Int

            if let hinted, !used.contains(hinted) {
                color = hinted
            } else {
                color = (0..<colorCount).first { !used.contains($0) } ?? 0
            }

            used.insert(color)

            // Walk the component, following each strand into the next.
            var current = strand

            while palette[current - 1] == nil {
                palette[current - 1] = color
                current = (rows.firstIndex(of: current) ?? 0) + 1
            }
        }

        return palette.map { $0 ?? 0 }
    }

    /// The colors once `letter` moves from one end of the word to the
    /// other: the two strands in its rows trade numbers.
    static func swappedColors(_ palette: [Int]?, _ letter: BraidColumn) -> [Int]? {
        guard var colors = palette else { return nil }

        colors.swapAt(letter.i, letter.i + 1)

        return colors
    }

    /// The word with its last letter moved to the front, colors and all.
    static func rotated(_ word: [BraidColumn], palette: [Int]?) -> (word: [BraidColumn], palette: [Int]?) {
        guard let last = word.last else { return (word, palette) }

        return ([last] + word.dropLast(), swappedColors(palette, last))
    }

    /// How far through its half-turn a crossing is, `fraction` of the way
    /// across its column, matching the cubic the column draws.
    static func turnAngle(atFraction fraction: Double) -> Double {
        let bisectionSteps = 30
        var low = 0.0
        var high = 1.0

        for _ in 0..<bisectionSteps {
            let s = (low + high) / 2

            if 1.5 * s * (1 - s) + s * s * s < fraction {
                low = s
            } else {
                high = s
            }
        }

        let s = (low + high) / 2
        let height = 3 * s * s - 2 * s * s * s

        return acos(min(max(1 - 2 * height, -1), 1))
    }
}

// MARK: - Tracks

/// A path of lines and arcs, measured by length along it.
final class BraidTrack {
    private enum Segment {
        case line(from: Vec2, to: Vec2, length: Double)
        case arc(center: Vec2, radius: Double, start: Double, end: Double, length: Double)

        var length: Double {
            switch self {
            case .line(_, _, let length), .arc(_, _, _, _, let length):
                return length
            }
        }

        func point(at distance: Double) -> Vec2 {
            let fraction = length == 0 ? 0 : distance / length

            switch self {
            case .line(let from, let to, _):
                return Vec2.lerp(from, to, fraction)

            case .arc(let center, let radius, let start, let end, _):
                let angle = start + (end - start) * fraction
                return center + Vec2(radius * cos(angle), radius * sin(angle))
            }
        }

        var isArc: Bool {
            if case .arc = self { return true }
            return false
        }
    }

    /// Points are placed this far apart around arcs.
    private static var arcStep: Double { 4 }

    private var segments: [Segment] = []
    private let start: Vec2
    private(set) var length = 0.0

    init(start: Vec2) {
        self.start = start
    }

    private var end: Vec2 {
        segments.last.map { $0.point(at: $0.length) } ?? start
    }

    func line(to point: Vec2) -> BraidTrack {
        let from = end
        let span = from.distance(to: point)

        segments.append(.line(from: from, to: point, length: span))
        length += span

        return self
    }

    func arc(center: Vec2, radius: Double, from startAngle: Double, to endAngle: Double) -> BraidTrack {
        let span = radius * abs(endAngle - startAngle)

        segments.append(.arc(center: center, radius: radius, start: startAngle, end: endAngle, length: span))
        length += span

        return self
    }

    func point(at distance: Double) -> Vec2 {
        var rest = min(max(distance, 0), length)

        for segment in segments {
            if rest <= segment.length {
                return segment.point(at: rest)
            }

            rest -= segment.length
        }

        return end
    }

    /// Points from `from` to `to`: the ends, the corners between, and
    /// enough points around arcs to draw them.
    func points(from: Double, to: Double) -> [Vec2] {
        var result = [point(at: from)]
        var offset = 0.0

        for segment in segments {
            let low = max(from, offset)
            let high = min(to, offset + segment.length)

            if high > low, segment.isArc {
                let steps = Int(((high - low) / Self.arcStep).rounded(.up))

                for step in stride(from: 1, to: steps, by: 1) {
                    let along = low - offset + (high - low) * Double(step) / Double(steps)
                    result.append(segment.point(at: along))
                }
            }

            if offset + segment.length > low, offset + segment.length < to {
                result.append(segment.point(at: segment.length))
            }

            offset += segment.length
        }

        result.append(point(at: to))

        return result
    }
}
