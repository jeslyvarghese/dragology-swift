import Dragology
import Foundation

/// The web version is 680 points wide. On a phone the views stack instead
/// of shrinking, so that everything stays big enough for a finger.
enum PermLayout {
    static let width = 390.0
    static let height = 600.0
}

private enum Metrics {
    static let tile = 32.0
    static let cell = 20.0
    static let nodeRadius = 12.0
    static let solidRadius = 80.0
    static let rowSpacing = 24.0
    static let wireWidth = 2.5
    static let wireOverhang = 14.0
    static let endLabelOffset = 22.0
    static let wiringInset = 110.0

    static let twoLineOrigin = Vec2(28, 44)
    static let matrixOrigin = Vec2(262, 50)
    static let cycleOrigin = Vec2(12, 250)
    static let solidOrigin = Vec2(288, 250)
    static let wordHeadingY = 364.0
    static let wordOrigin = Vec2(12, 392)
    static let infoY = 416.0
    static let wiringOrigin = Vec2(48, 462)
    static let wiringHeadingOffset = Vec2(-36, -18)
    static let headingOrigin = Vec2(12, 14)
    static let solidHeadingOrigin = Vec2(206, 158)
    static let headingWidth = 366.0
    static let solidHeadingWidth = 172.0
    static let headingRule = 7.0

    static let letterSlotStart = 34.0
    static let maxLetterWidth = 22.0
    static let letterArea = 330.0
    static let wordFontSize = 17.0
    static let infoFontSize = 12.0
    static let labelSize = 10.0
    static let tileFontSize = 16.0
    static let nodeFontSize = 13.0
    static let matrixLabelSize = 9.0
    static let matrixLabelOffset = 7.0

    static let liftedTile = 6.0
    static let tileGap = 8.0
    static let tileCorner = 5.0
    static let lineWidth = 1.5
    static let snapRadius = 3.0
    static let lockPast = 10.0
    static let bracketInset = 6.0
    static let bracketBow = 18.0
    static let bracketOverhang = 4.0
    static let bracketExtra = 12.0

    static let minRingRadius = 22.0
    static let ringRadiusPerNode = 6.0
    static let ringGap = 14.0
    static let arcSamples = 12
    static let loopRadius = 8.0
    static let loopHalfWidth = 5.0
    static let loopInset = 3.0
    static let arrowClearance = 4.0
    static let arrowLength = 7.0
    static let loopArrowLength = 6.0
    static let arrowAngle = Double.pi / 3
    static let ringZ = -1

    static let dotRadius = 7.0
    static let dotHitInset = 1.0

    static let walkWidth = 3.0
    static let walkFrontOpacity = 0.4
    static let walkBackOpacity = 0.5
    static let walkHandleWidth = 12.0
    static let vertexHitRadius = 12.0
    static let vertexRadius = 2.5
    static let tokenRadius = 10.0
    static let tokenStroke = 2.0
    static let tokenBackOpacity = 0.55
    static let activeOpacity = 0.35
    static let faceOpacity = 0.72
    static let shadeBase = 0.84
    static let shadeRange = 0.2
    static let minFacing = 0.1
    static let hexagonLabelSize = 9.0
    static let hexagonLabelOffset = 14.0

    static let faceFrontZ = 4
    static let faceBackZ = 1
    static let edgesBackZ = 2
    static let edgesFrontZ = 5
    static let solidWalkZ = (back: 3, front: 6, token: 7)
    static let flatWalkZ = (back: 1, front: 1, token: 2)

    static let minColumns = 13
    static let spareColumns = 4
    static let apexShare = 0.35
    static let handleRowShare = 0.3
    static let cornerRadius = 4.0
    static let endHitOpacity = 0.6

    static let hexFace = RGBA(hex: 0xD6E0EF)
    static let squareFace = RGBA(hex: 0xF5DEB3)
    static let frontEdge = RGBA(hex: 0x475569)
    static let backEdge = RGBA(hex: 0x64748B)
    static let accent = RGBA(hex: 0x2563EB)
    static let handle = RGBA(hex: 0xDC2626)
    static let stuck = RGBA(hex: 0x9CA3AF)
    static let label = RGBA(hex: 0x6B7280)
    static let ink = RGBA(hex: 0x1F2937)
    static let mutedFill = RGBA(hex: 0xF3F4F6)
    static let mutedStroke = RGBA(hex: 0xD1D5DB)

    static let colors: [(fill: RGBA, stroke: RGBA)] = [
        (RGBA(hex: 0xFECACA), RGBA(hex: 0xDC2626)),
        (RGBA(hex: 0xFDE68A), RGBA(hex: 0xD97706)),
        (RGBA(hex: 0xBBF7D0), RGBA(hex: 0x16A34A)),
        (RGBA(hex: 0xBFDBFE), RGBA(hex: 0x2563EB)),
        (RGBA(hex: 0xDDD6FE), RGBA(hex: 0x7C3AED)),
        (RGBA(hex: 0xFBCFE8), RGBA(hex: 0xDB2777)),
    ]

    static func color(_ value: Int) -> (fill: RGBA, stroke: RGBA) {
        colors[(value - 1) % colors.count]
    }
}

func permutationLab(_ context: RenderContext<PermState>) -> Node<PermState> {
    PermRenderer(context).scene()
}

private extension RGBA {
    func shaded(by factor: Double) -> RGBA {
        let clamp = { (value: Double) in min(max(value * factor, 0), 1) }

        return RGBA(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: alpha)
    }
}

private func subscriptDigit(_ value: Int) -> String {
    let digits = Array("₀₁₂₃₄₅₆₇₈₉")
    return String(digits[value % digits.count])
}

/// A filled triangle with its tip at `tip`, pointing along `direction`.
private func arrowHead(tip: Vec2, direction: Vec2, length: Double, fill: RGBA) -> Node<PermState> {
    let halfWidth = length * tan(Metrics.arrowAngle / 2)

    return path([
        .move(.zero),
        .line(Vec2(-length, halfWidth)),
        .line(Vec2(-length, -halfWidth)),
        .close,
    ])
    .fill(fill)
    .transform(.translate(tip) + .rotate(degrees: direction.angle * 180 / .pi))
    .hitTesting(.disabled)
}

/// An arc as a fixed number of straight pieces, so that it blends.
private func arcCommands(center: Vec2, radius: Double, from start: Double, to end: Double) -> [PathCommand] {
    let points = (0...Metrics.arcSamples).map { index -> Vec2 in
        let angle = start + (end - start) * Double(index) / Double(Metrics.arcSamples)
        return center + Vec2(radius * cos(angle), radius * sin(angle))
    }

    return [.move(points[0])] + points.dropFirst().map(PathCommand.line)
}

/// A word letter with where it goes.
private struct WordLetter {
    var generator: Int
    var layoutIndex: Int
    var wordIndex: Int
    var pairID: String
}

private struct WalkZ {
    var back: Int
    var front: Int
    var token: Int
}

/// Lays out and draws one state.
private struct PermRenderer {
    let context: RenderContext<PermState>
    let d: DragSpecBuilder<PermState>
    let raw: PermState
    let n: Int
    let columns: [PermColumn]
    /// The logical word, without closed columns.
    let word: [PermColumn]
    /// The cleaned state that drags build on.
    let state: PermState
    let permutation: [Int]
    let columnCount: Int
    let columnWidth: Double
    let wireEnd: Double

    init(_ context: RenderContext<PermState>) {
        self.context = context
        d = context.d
        raw = context.state
        n = raw.n
        columns = raw.word
        word = raw.word.filter { !$0.isClosed }
        state = PermState(n: raw.n, word: word, mode: raw.mode, style: raw.style, view: raw.view)
        permutation = PermMath.permutation(n: raw.n, word: word)
        columnCount = max(Metrics.minColumns, raw.n * (raw.n - 1) / 2 + Metrics.spareColumns)
        columnWidth = (PermLayout.width - Metrics.wiringInset) / Double(columnCount)
        wireEnd = Double(columnCount) * columnWidth
    }

    // MARK: Rewrites

    private var capacity: Int { columnCount - 1 }

    private func canAppend(_ count: Int) -> Bool {
        word.count + count <= capacity
    }

    private func with(word newWord: [PermColumn]) -> PermState {
        var copy = state
        copy.word = newWord
        return copy
    }

    private func appending(_ generator: Int) -> PermState {
        with(word: word + [PermColumn(generator: generator)])
    }

    private func withPermutation(_ newPermutation: [Int]) -> PermState {
        with(word: PermMath.reducedWord(for: newPermutation).map { PermColumn(generator: $0) })
    }

    private func byColumn(_ state: PermState) -> PermState {
        var copy = state
        copy.wiresByColumn = true
        return copy
    }

    /// Two zero-width columns, drawn the same as `state`, so that an
    /// inserted pair widens from nothing.
    private func withClosed(at index: Int, _ generator: Int) -> PermState {
        let closed = PermColumn(generator: generator, kind: .closed)
        var copy = word
        copy.insert(contentsOf: [closed, closed], at: index)

        return with(word: copy)
    }

    private func inserting(at index: Int, _ generator: Int) -> PermState {
        let letter = PermColumn(generator: generator)
        var copy = word
        copy.insert(contentsOf: [letter, letter], at: index)

        return with(word: copy)
    }

    private func gapped(at index: Int) -> PermState {
        var copy = word
        copy[index].kind = .blank
        copy[index + 1].kind = .blank

        return with(word: copy)
    }

    private static func closingBlanks(_ state: PermState) -> PermState {
        var copy = state

        copy.word = state.word.map { column in
            column.kind == .blank ? PermColumn(generator: column.generator, kind: .closed) : column
        }

        return copy
    }

    // MARK: Word letters

    private var wordLetters: [WordLetter] {
        var rows = Array(1...n)
        var seen = Set<String>()
        var letters: [WordLetter] = []
        var wordIndex = 0

        for (index, column) in columns.enumerated() where !column.isClosed {
            let current = wordIndex
            wordIndex += 1

            guard column.isLetter else { continue }

            let i = column.generator
            var pairID = "\(min(rows[i], rows[i + 1]))-\(max(rows[i], rows[i + 1]))"

            rows.swapAt(i, i + 1)

            while seen.contains(pairID) { pairID += "x" }

            seen.insert(pairID)
            letters.append(WordLetter(generator: i, layoutIndex: index, wordIndex: current, pairID: pairID))
        }

        return letters
    }

    // MARK: Drags

    /// A step along an adjacent transposition, chaining on when it lands.
    private func adjacentSpec(row: Int) -> DragSpec<PermState> {
        guard canAppend(1) else { return d.fixed(state) }

        var options: [DragSpec<PermState>] = []

        if row > 0 { options.append(d.between([state, appending(row - 1)])) }
        if row < n - 1 { options.append(d.between([state, appending(row)])) }

        return d.closest(options).withSnapRadius(Metrics.snapRadius, chaining: .chainOnSnap)
    }

    private func tileSpec(_ value: Int) -> DragSpec<PermState> {
        let row = permutation.firstIndex(of: value) ?? 0

        if raw.mode == .adjacent {
            return adjacentSpec(row: row)
        }

        let without = permutation.filter { $0 != value }

        let states = (0..<n).map { target -> PermState in
            var reordered = without
            reordered.insert(value, at: target)

            return withPermutation(reordered)
        }

        return d.closest(states).whenFar(state).withFloating()
    }

    private func cycleSpec(_ value: Int, cycles: [[Int]]) -> DragSpec<PermState> {
        let without = cycles.map { $0.filter { $0 != value } }.filter { !$0.isEmpty }
        var options: [[Int]] = []

        // After any element of any cycle, or as a fixed point.
        for (index, cycle) in without.enumerated() {
            for after in cycle.indices {
                var placed = without
                placed[index].insert(value, at: after + 1)
                options.append(PermMath.permutation(n: n, cycles: placed))
            }
        }

        options.append(PermMath.permutation(n: n, cycles: without + [[value]]))

        var seen = Set<[Int]>()
        let unique = options.filter { seen.insert($0).inserted }

        return d.closest(unique.map(withPermutation)).withFloating()
    }

    private func matrixSpec(_ value: Int) -> DragSpec<PermState> {
        let row = permutation.firstIndex(of: value) ?? 0

        return d.between((0..<n).map { target in
            var swapped = permutation
            swapped.swapAt(row, target)

            return withPermutation(swapped)
        })
    }

    private func tokenSpec() -> DragSpec<PermState> {
        guard canAppend(1) else { return d.fixed(state) }

        let steps = (0..<(n - 1)).map { d.between([state, appending($0)]) }

        // Commit to an edge once out on it, as the shortest are very short.
        return d.closest(steps, options: ClosestOptions(lockPast: Metrics.lockPast))
            .withSnapRadius(Metrics.snapRadius, chaining: .chainOnSnap)
    }

    /// The rewrites available at a vertex of the walk: across a square
    /// to commute, or back along a spur to cancel.
    private func walkVertexMoves(_ index: Int) -> [PermState] {
        guard index > 0, index < word.count else { return [] }

        let previous = word[index - 1]
        let current = word[index]

        guard previous.isLetter, current.isLetter else { return [] }

        if abs(previous.generator - current.generator) >= 2 {
            var copy = word
            copy.swapAt(index - 1, index)

            return [with(word: copy)]
        }

        return previous.generator == current.generator ? [gapped(at: index - 1)] : []
    }

    private func walkVertexSpec(_ index: Int) -> DragSpec<PermState> {
        let moves = walkVertexMoves(index).map { d.between([state, $0]).onDrop(Self.closingBlanks) }

        return moves.isEmpty ? d.fixed(state) : d.closest(moves)
    }

    private func faceSpec(_ index: Int) -> DragSpec<PermState> {
        let solid = TruncatedOctahedron.shared

        // Keeps the grabbed face turned toward you. Otherwise, past the
        // silhouette, dragging back would turn the solid backwards.
        let minimum = min(Metrics.minFacing, solid.facing(raw.view, face: index))

        var start = state
        start.view = raw.view.folded

        return d
            .vary(start, \.view.spinX, \.view.spinY, constraint: { candidate in
                Constraint.moreThan(solid.facing(candidate.view, face: index), minimum)
            })
            .onDrop { dropped in
                var result = dropped
                result.view = dropped.view.folded
                return result
            }
    }

    // MARK: Scene

    private var showsSolid: Bool { n == 4 && raw.style == .solid }

    func scene() -> Node<PermState> {
        let solid = showsSolid ? solidNode() : nil

        // Turning the solid only moves the solid, so that's all the
        // optimizer needs to see.
        if context.isTracking, context.draggedID?.hasPrefix("ph-face-") == true, let solid {
            return Node(children: [solid])
        }

        var parts = headings()
        parts.append(wordNode())
        parts += twoLineNodes()
        parts += cycleNodes()
        parts.append(matrixNode())

        if let solid {
            parts.append(solid)
        } else if n <= 4 {
            parts.append(flatNode())
        }

        parts.append(wiringNode())

        return Node(children: parts)
    }

    private func smallLabel(_ text: String, at position: Vec2) -> Node<PermState> {
        // Labels are centered, so lead with their measured half width.
        let halfWidth = Double(text.count) * Metrics.labelSize * 0.3

        return label(text.uppercased(), size: Metrics.labelSize)
            .fill(Metrics.label)
            .transform(.translate(position + Vec2(halfWidth, 0)))
            .hitTesting(.disabled)
    }

    private func heading(_ title: String, at position: Vec2, width: Double) -> Node<PermState> {
        group {
            smallLabel(title, at: .zero)

            line(from: Vec2(0, Metrics.headingRule), to: Vec2(width, Metrics.headingRule))
                .stroke(Ink.faint)
                .hitTesting(.disabled)
        }
        .transform(.translate(position))
    }

    private func headings() -> [Node<PermState>] {
        var parts = [
            heading("the permutation π", at: Metrics.headingOrigin, width: Metrics.headingWidth),
            heading("a word for π", at: Vec2(Metrics.headingOrigin.x, Metrics.wordHeadingY), width: Metrics.headingWidth),
        ]

        if n <= 4 {
            parts.append(heading("permutohedron", at: Metrics.solidHeadingOrigin, width: Metrics.solidHeadingWidth))
        }

        return parts
    }

    // MARK: Word

    private func wordNode() -> Node<PermState> {
        let letters = wordLetters
        let letterWidth = min(Metrics.maxLetterWidth, Metrics.letterArea / Double(max(word.count, 1)))
        let inversions = PermMath.inversions(permutation)
        let length = letters.count
        let verdict = length == inversions ? "reduced ✓" : "not reduced (\(length - inversions) to cancel)"
        let info = "length \(length) · inversions \(inversions) · \(verdict)"
        let infoHalfWidth = Double(info.count) * Metrics.infoFontSize * 0.26

        var parts: [Node<PermState>] = [
            label("π =", size: Metrics.wordFontSize)
                .id("word-pi")
                .fill(Metrics.ink)
                .transform(.translate(Metrics.wordOrigin + Vec2(Metrics.wordFontSize / 2 + 4, 0)))
                .hitTesting(.disabled),

            label(info, size: Metrics.infoFontSize)
                .fill(Metrics.ink)
                .transform(.translate(Metrics.wordOrigin.x + infoHalfWidth, Metrics.infoY))
                .hitTesting(.disabled),
        ]

        if length == 0 {
            parts.append(
                label("e", size: Metrics.wordFontSize)
                    .fill(Metrics.stuck)
                    .transform(.translate(Metrics.wordOrigin + Vec2(Metrics.letterSlotStart + 8, 0)))
                    .hitTesting(.disabled)
            )
        }

        // Fixed anchors for letters to grow from. They never scale, so a
        // letter emerging beside another doesn't stack scales.
        let slotPosition = { (index: Int) in
            Metrics.wordOrigin + Vec2(Metrics.letterSlotStart + Double(index) * letterWidth + 8, 0)
        }

        for slot in 0..<capacity {
            parts.append(Node<PermState>().id("word-slot-\(slot)").transform(.translate(slotPosition(slot))))
        }

        for letter in letters {
            parts.append(
                label("s" + subscriptDigit(letter.generator + 1), size: Metrics.wordFontSize)
                    .id("word-letter-\(letter.pairID)")
                    .fill(Metrics.ink)
                    .transform(.translate(slotPosition(letter.wordIndex)))
                    .emergeFrom("word-slot-\(letter.wordIndex)")
                    .hitTesting(.disabled)
            )
        }

        return Node(children: parts)
    }

    // MARK: Two-line notation

    private func tileContents(_ value: Int, isMuted: Bool) -> Node<PermState> {
        let color = Metrics.color(value)

        return group {
            rect(width: Metrics.tile, height: Metrics.tile, cornerRadius: Metrics.tileCorner)
                .fill(isMuted ? Metrics.mutedFill : color.fill)
                .stroke(isMuted ? Metrics.mutedStroke : color.stroke, lineWidth: Metrics.lineWidth)

            label(String(value), size: Metrics.tileFontSize)
                .fill(isMuted ? Metrics.stuck : Metrics.ink)
                .transform(.translate(Metrics.tile / 2, Metrics.tile / 2))
        }
    }

    private func twoLineNodes() -> [Node<PermState>] {
        let origin = Metrics.twoLineOrigin
        let width = Double(n) * Metrics.tile
        let bottom = 2 * Metrics.tile + Metrics.bracketExtra
        let middle = Metrics.tile + Metrics.bracketOverhang
        let top = -Metrics.bracketOverhang
        let left = -Metrics.bracketInset
        let right = width + Metrics.bracketInset

        let bracket = { (x: Double, bow: Double) -> Node<PermState> in
            path([.move(Vec2(x, top)), .quad(control: Vec2(bow, middle), end: Vec2(x, bottom))])
                .stroke(Metrics.stuck, lineWidth: Metrics.lineWidth)
                .hitTesting(.disabled)
        }

        var header: [Node<PermState>] = [
            bracket(left, -Metrics.bracketBow),
            bracket(right, width + Metrics.bracketBow),
        ]

        for value in 1...n {
            header.append(tileContents(value, isMuted: true).transform(.translate(Double(value - 1) * Metrics.tile, 0)))
        }

        let rowOrigin = origin + Vec2(0, Metrics.tile + Metrics.tileGap)

        let tiles = permutation.enumerated().map { index, value -> Node<PermState> in
            let id = "tl-tile-\(value)"
            let isDragged = context.draggedID == id
            let renderer = self

            return Node(children: [tileContents(value, isMuted: false)])
                .id(id)
                .transform(.translate(rowOrigin + Vec2(Double(index) * Metrics.tile, isDragged ? -Metrics.liftedTile : 0)))
                .zIndex(isDragged ? .absolute(1) : .relative(0))
                .onDrag { renderer.tileSpec(value) }
        }

        return [Node(children: header).transform(.translate(origin))] + tiles
    }

    // MARK: Cycles

    private func cycleNodes() -> [Node<PermState>] {
        let cycles = PermMath.cycles(of: permutation)
        var cursor = 0.0
        var nodePositions: [Int: Vec2] = [:]
        var rings: [Node<PermState>] = []

        for cycle in cycles {
            let count = cycle.count
            let radius = count == 1 ? 0 : max(Metrics.minRingRadius, Metrics.ringRadiusPerNode * Double(count))
            let center = Vec2(cursor + radius + Metrics.nodeRadius, 0)

            for (index, value) in cycle.enumerated() {
                let degrees = -90 + 360 * Double(index) / Double(count)
                nodePositions[value] = center + polar(radius: radius, degrees: degrees)
            }

            cursor += 2 * (radius + Metrics.nodeRadius) + Metrics.ringGap
            rings.append(ringNode(cycle, center: center, radius: radius))
        }

        let renderer = self

        let nodes = (1...n).map { value -> Node<PermState> in
            let id = "cyc-node-\(value)"
            let color = Metrics.color(value)

            let content: Node<PermState> = group {
                circle(radius: Metrics.nodeRadius)
                    .fill(color.fill)
                    .stroke(color.stroke, lineWidth: Metrics.lineWidth)

                label(String(value), size: Metrics.nodeFontSize).fill(Metrics.ink)
            }

            return content
                .id(id)
                .transform(.translate(nodePositions[value] ?? .zero))
                .zIndex(context.draggedID == id ? .absolute(1) : .relative(0))
                .onDrag { renderer.cycleSpec(value, cycles: cycles) }
        }

        return [
            smallLabel("cycle diagram", at: Metrics.cycleOrigin + Vec2(0, -84)),
            Node(children: rings + nodes).transform(.translate(Metrics.cycleOrigin)),
        ]
    }

    /// The same structure whatever the cycle's length, so rings can blend.
    private func ringNode(_ cycle: [Int], center: Vec2, radius: Double) -> Node<PermState> {
        var parts: [Node<PermState>] = [
            circle(radius: radius)
                .stroke(Ink.faint)
                .opacity(cycle.count == 1 ? 0 : 1)
                .transform(.translate(center)),
        ]

        if cycle.count == 1 {
            parts.append(selfLoop(cycle[0], center: center))
        } else {
            parts += cycle.indices.map { arrowNode(cycle, index: $0, center: center, radius: radius) }
        }

        return Node(children: parts)
            .id("cyc-ring-\(cycle[0])")
            .zIndex(.relative(Metrics.ringZ))
    }

    /// A fixed point gets a little loop above its node.
    private func selfLoop(_ value: Int, center: Vec2) -> Node<PermState> {
        let radius = Metrics.loopRadius
        let halfWidth = Metrics.loopHalfWidth
        let baseY = -Metrics.nodeRadius + Metrics.loopInset
        let rise = (radius * radius - halfWidth * halfWidth).squareRoot()
        let loopCenter = Vec2(0, baseY - rise)
        let start = atan2(rise, -halfWidth)
        let end = atan2(rise, halfWidth) + 2 * .pi

        return group {
            path(arcCommands(center: loopCenter, radius: radius, from: start, to: end))
                .stroke(Metrics.stuck, lineWidth: Metrics.lineWidth)
                .hitTesting(.disabled)

            arrowHead(
                tip: Vec2(halfWidth, baseY),
                direction: Vec2(-0.6, 1),
                length: Metrics.loopArrowLength,
                fill: Metrics.stuck
            )
        }
        .id("cyc-loop-\(value)")
        .transform(.translate(center))
    }

    private func arrowNode(_ cycle: [Int], index: Int, center: Vec2, radius: Double) -> Node<PermState> {
        let count = Double(cycle.count)
        let from = cycle[index]
        let to = cycle[(index + 1) % cycle.count]
        let clearance = asin(min(1, (Metrics.nodeRadius + Metrics.arrowClearance) / radius))
        let top = -Double.pi / 2
        let start = top + 2 * .pi * Double(index) / count + clearance
        let end = top + 2 * .pi * Double(index + 1) / count - clearance
        let tip = center + Vec2(radius * cos(end), radius * sin(end))
        let tangent = Vec2(cos(end + .pi / 2), sin(end + .pi / 2))

        return group {
            path(arcCommands(center: center, radius: radius, from: start, to: end))
                .stroke(Metrics.label, lineWidth: Metrics.lineWidth)
                .hitTesting(.disabled)

            arrowHead(tip: tip, direction: tangent, length: Metrics.arrowLength, fill: Metrics.label)
        }
        .id("cyc-arrow-\(from)-\(to)")
    }

    // MARK: Matrix

    private func matrixNode() -> Node<PermState> {
        let cell = Metrics.cell
        let side = Double(n) * cell
        let renderer = self

        var parts: [Node<PermState>] = [
            rect(width: side, height: side).fill(.white).stroke(Metrics.stuck).hitTesting(.disabled),
        ]

        for k in 1..<n {
            let offset = Double(k) * cell

            parts.append(line(from: Vec2(offset, 0), to: Vec2(offset, side)).stroke(Ink.faint).hitTesting(.disabled))
            parts.append(line(from: Vec2(0, offset), to: Vec2(side, offset)).stroke(Ink.faint).hitTesting(.disabled))
        }

        for k in 1...n {
            let center = (Double(k) - 0.5) * cell

            for position in [Vec2(center, -Metrics.matrixLabelOffset), Vec2(-Metrics.matrixLabelOffset, center)] {
                parts.append(
                    label(String(k), size: Metrics.matrixLabelSize)
                        .fill(Metrics.stuck)
                        .transform(.translate(position))
                        .hitTesting(.disabled)
                )
            }
        }

        for value in 1...n {
            let id = "mat-dot-\(value)"
            let row = permutation.firstIndex(of: value) ?? 0
            let color = Metrics.color(value)

            let dot: Node<PermState> = group {
                circle(radius: cell / 2 - Metrics.dotHitInset).fill(.clear)
                circle(radius: Metrics.dotRadius).fill(color.stroke)
            }

            parts.append(
                dot
                    .id(id)
                    .transform(.translate((Double(value) - 0.5) * cell, (Double(row) + 0.5) * cell))
                    .zIndex(context.draggedID == id ? .absolute(1) : .relative(0))
                    .onDrag { renderer.matrixSpec(value) }
            )
        }

        return Node(children: parts).transform(.translate(Metrics.matrixOrigin))
    }

    // MARK: Walk

    private var stepKeys: [String] {
        (0...columns.count).map { count in
            Permutohedron.key(PermMath.permutation(n: n, word: Array(columns.prefix(count))))
        }
    }

    private var vertexKeys: [String] {
        (0...word.count).map { count in
            Permutohedron.key(PermMath.permutation(n: n, word: Array(word.prefix(count))))
        }
    }

    /// The walk from the identity along the word, its rewrite handles,
    /// and the token. `isFront` says whether an edge, or a vertex given
    /// twice, is on the near side.
    private func walkNodes(
        positions: [String: Vec2],
        isFront: @escaping (String, String) -> Bool,
        z: WalkZ
    ) -> [Node<PermState>] {
        let at = { (key: String) in (positions[key] ?? .zero) * Metrics.solidRadius }
        let tokenKey = Permutohedron.key(permutation)
        let steps = stepKeys
        let vertices = vertexKeys
        let renderer = self
        var parts: [Node<PermState>] = []

        // A segment per step, plus a zero-length tip at the last vertex,
        // which stretches along a new edge as a step is appended.
        for (index, key) in (steps + [tokenKey]).enumerated().dropFirst() {
            let previous = steps[index - 1]
            let front = isFront(previous, key)
            let isHidden = index <= columns.count && !columns[index - 1].isLetter
            let visible = front ? Metrics.walkFrontOpacity : Metrics.walkBackOpacity

            parts.append(
                line(from: at(previous), to: at(key))
                    .id("ph-walk-\(index - 1)")
                    .stroke(Metrics.accent, lineWidth: Metrics.walkWidth)
                    .opacity(isHidden ? 0 : visible)
                    .zIndex(.relative(front ? z.front : z.back))
                    .hitTesting(.disabled)
            )
        }

        // Braid handles, on the middle edge of s_i s_k s_i.
        for letter in wordLetters where PermMath.isBraid(word, at: letter.wordIndex - 1) {
            let index = letter.wordIndex
            let id = "ph-edge-\(index)"
            let p = at(vertices[index])
            let q = at(vertices[index + 1])
            let middle = (p + q) * 0.5
            let front = isFront(vertices[index], vertices[index + 1])

            parts.append(
                group {
                    line(from: p - middle, to: q - middle)
                        .stroke(Metrics.accent, lineWidth: Metrics.walkHandleWidth)
                        .opacity(context.draggedID == id ? Metrics.activeOpacity : 0)
                }
                .id(id)
                .transform(.translate(middle))
                .zIndex(.relative(front ? z.front : z.back))
                .onDrag {
                    let moved = renderer.with(word: PermMath.braided(renderer.word, at: index - 1))

                    return renderer.d.between([renderer.byColumn(renderer.state), renderer.byColumn(moved)])
                }
            )
        }

        // Vertex handles, wherever there's a move. The last is the token.
        for (index, key) in vertices.dropLast().enumerated() {
            // Mid-cancel, a spur's tip sits by a blank, with no moves of
            // its own, but it's the handle being dragged.
            let isMidCancel = index > 0 && !word[index - 1].isLetter

            guard !walkVertexMoves(index).isEmpty || isMidCancel else { continue }

            let id = "ph-v-\(index)"

            parts.append(
                group {
                    circle(radius: Metrics.vertexHitRadius)
                        .fill(Metrics.accent)
                        .opacity(context.draggedID == id ? Metrics.activeOpacity : 0)

                    circle(radius: Metrics.vertexRadius)
                        .fill(Metrics.accent.withOpacity(Metrics.faceOpacity))
                }
                .id(id)
                .transform(.translate(at(key)))
                .zIndex(.relative(isFront(key, key) ? z.front : z.back))
                .onDrag { renderer.walkVertexSpec(index) }
            )
        }

        parts.append(
            circle(radius: Metrics.tokenRadius)
                .id("ph-token")
                .fill(Metrics.accent)
                .stroke(.white, lineWidth: Metrics.tokenStroke)
                .opacity(isFront(tokenKey, tokenKey) ? 1 : Metrics.tokenBackOpacity)
                .transform(.translate(at(tokenKey)))
                .zIndex(.relative(z.token))
                .onDrag(renderer.tokenSpec)
        )

        return parts
    }

    private func flatNode() -> Node<PermState> {
        let layout = n == 3 ? Permutohedron.hexagon : Permutohedron.schlegel
        let at = { (key: String) in (layout.positions[key] ?? .zero) * Metrics.solidRadius }
        var parts: [Node<PermState>] = []

        for (a, b) in layout.edges {
            parts.append(line(from: at(a), to: at(b)).stroke(Metrics.mutedStroke).hitTesting(.disabled))
        }

        for key in layout.keys {
            parts.append(circle(radius: Metrics.vertexRadius).fill(Metrics.stuck).transform(.translate(at(key))))

            if n == 3 {
                let offset = (layout.positions[key] ?? .zero) * Metrics.hexagonLabelOffset

                parts.append(
                    label(key, size: Metrics.hexagonLabelSize)
                        .fill(Metrics.stuck)
                        .transform(.translate(at(key) + offset))
                        .hitTesting(.disabled)
                )
            }
        }

        let z = WalkZ(back: Metrics.flatWalkZ.back, front: Metrics.flatWalkZ.front, token: Metrics.flatWalkZ.token)

        parts += walkNodes(positions: layout.positions, isFront: { _, _ in true }, z: z)

        return Node(children: parts)
            .id("ph-flat")
            .transform(.translate(Metrics.solidOrigin))
    }

    /// Faces, edges, walk, and token, stacked from back to front, so
    /// what's behind shows faintly through. Faces sit at their centers,
    /// so that `vary` can follow a grabbed face as the solid turns.
    private func solidNode() -> Node<PermState> {
        let solid = TruncatedOctahedron.shared
        let view = solid.projected(raw.view)
        let edges = Permutohedron.schlegel.edges
        let scale = Metrics.solidRadius
        let renderer = self

        var edgeFront: [String: Bool] = [:]

        for (index, edge) in edges.enumerated() {
            edgeFront[edge.0 + "-" + edge.1] = view.edgeIsFront[index]
        }

        let isFront = { (a: String, b: String) -> Bool in
            if a == b {
                return solid.faces.indices.contains { view.isFront[$0] && solid.faces[$0].keys.contains(a) }
            }

            return edgeFront[a < b ? a + "-" + b : b + "-" + a] ?? false
        }

        var parts: [Node<PermState>] = [
            smallLabel("drag a face to turn it", at: Vec2(-scale - 8, scale + 22)),
        ]

        for (index, face) in solid.faces.enumerated() {
            let points = view.points[index]
            let center = points.reduce(.zero, +) * (1 / Double(points.count))
            let relative = points.map { ($0 - center) * scale }
            let base = face.isSquare ? Metrics.squareFace : Metrics.hexFace
            let fill = base.shaded(by: Metrics.shadeBase + Metrics.shadeRange * view.light[index])
            let outline = [PathCommand.move(relative[0])] + relative.dropFirst().map(PathCommand.line) + [.close]

            parts.append(
                group {
                    path(outline).fill(fill.withOpacity(view.isFront[index] ? Metrics.faceOpacity : 0))
                }
                .id(face.id)
                .transform(.translate(center * scale))
                .zIndex(.relative(view.isFront[index] ? Metrics.faceFrontZ : Metrics.faceBackZ))
                .onDrag { renderer.faceSpec(index) }
            )
        }

        parts.append(edgeLines(view, edges: edges, isFront: false))
        parts.append(edgeLines(view, edges: edges, isFront: true))

        let z = WalkZ(back: Metrics.solidWalkZ.back, front: Metrics.solidWalkZ.front, token: Metrics.solidWalkZ.token)

        parts += walkNodes(positions: view.positions, isFront: isFront, z: z)

        return Node(children: parts)
            .id("ph-solid")
            .transform(.translate(Metrics.solidOrigin))
    }

    private func edgeLines(
        _ view: TruncatedOctahedron.Projection,
        edges: [(String, String)],
        isFront: Bool
    ) -> Node<PermState> {
        let scale = Metrics.solidRadius

        let lines = edges.enumerated().map { index, edge -> Node<PermState> in
            line(from: (view.positions[edge.0] ?? .zero) * scale, to: (view.positions[edge.1] ?? .zero) * scale)
                .stroke(isFront ? Metrics.frontEdge : Metrics.backEdge.withOpacity(Metrics.activeOpacity))
                .opacity(view.edgeIsFront[index] == isFront ? 1 : 0)
                .hitTesting(.disabled)
        }

        return Node(children: lines)
            .id(isFront ? "ph-edges-front" : "ph-edges-back")
            .zIndex(.relative(isFront ? Metrics.edgesFrontZ : Metrics.edgesBackZ))
    }

    // MARK: Wiring diagram

    private func rowY(_ row: Int) -> Double {
        Double(row) * Metrics.rowSpacing
    }

    private func width(ofColumn index: Int) -> Double {
        index < columns.count && columns[index].isClosed ? 0 : columnWidth
    }

    private func x(ofColumn index: Int) -> Double {
        let laidOut = min(index, columns.count)
        let widths = (0..<laidOut).reduce(0.0) { $0 + width(ofColumn: $1) }

        return widths + Double(max(0, index - columns.count)) * columnWidth
    }

    private func rowAfter(_ row: Int, _ column: PermColumn) -> Int {
        let i = column.generator

        guard column.isLetter, row == i || row == i + 1 else { return row }

        return row == i ? i + 1 : i
    }

    private func segment(x: Double, width: Double, from start: Int, to end: Int) -> [PathCommand] {
        let startY = rowY(start)
        let endY = rowY(end)

        return [
            .line(Vec2(x, startY)),
            .cubic(
                control1: Vec2(x + width / 2, startY),
                control2: Vec2(x + width / 2, endY),
                end: Vec2(x + width, endY)
            ),
        ]
    }

    /// A wire is a fixed number of segments, so segment k blends with
    /// segment k. Normally there's one per crossing the wire takes part
    /// in, so a crossing commuting past a neighbor slides sideways. In a
    /// braid move, one per column, as every column bends at once.
    private func wirePath(_ strand: Int) -> [PathCommand] {
        var segments: [[PathCommand]] = []
        var row = strand - 1

        for (index, column) in columns.enumerated() {
            let i = column.generator

            if !raw.wiresByColumn, row != i, row != i + 1 { continue }

            let next = rowAfter(row, column)

            segments.append(segment(x: x(ofColumn: index), width: width(ofColumn: index), from: row, to: next))
            row = next
        }

        let freeX = x(ofColumn: columns.count)

        if raw.wiresByColumn {
            segments.append(segment(x: freeX, width: wireEnd - freeX, from: row, to: row))
        } else {
            // Unused segments park flat at the first free column.
            let freeWidth = min(max(wireEnd - freeX, 0), columnWidth)

            segments.append(segment(x: freeX, width: freeWidth, from: row, to: row))

            while segments.count < columnCount + 2 {
                segments.append(segment(x: freeX + freeWidth, width: 0, from: row, to: row))
            }
        }

        let start = PathCommand.move(Vec2(-Metrics.wireOverhang, rowY(strand - 1)))
        let end = PathCommand.line(Vec2(wireEnd + Metrics.wireOverhang, rowY(row)))

        return [start] + segments.flatMap { $0 } + [end]
    }

    private func wiringNode() -> Node<PermState> {
        var parts: [Node<PermState>] = []

        for strand in 1...n {
            parts.append(
                label(String(strand), size: Metrics.labelSize)
                    .fill(Metrics.label)
                    .transform(.translate(-Metrics.endLabelOffset, rowY(strand - 1)))
                    .hitTesting(.disabled)
            )

            parts.append(wireEndHandle(strand))
        }

        for strand in 1...n {
            parts.append(
                path(wirePath(strand))
                    .id("wire-\(strand)")
                    .stroke(Metrics.color(strand).stroke, lineWidth: Metrics.wireWidth)
            )
        }

        parts += wordLetters.map(crossingHandle)

        for strand in 1...n {
            parts.append(Node(children: strandHandles(strand)))
        }

        let title = canAppend(1) ? "wiring diagram" : "diagram full: cancel a double crossing"

        return Node(children: [
            smallLabel(title, at: Metrics.wiringHeadingOffset),
        ] + parts)
        .transform(.translate(Metrics.wiringOrigin))
    }

    /// Drag a strand's end past a neighbor to add a crossing.
    private func wireEndHandle(_ strand: Int) -> Node<PermState> {
        let id = "wire-end-\(strand)"
        let row = permutation.firstIndex(of: strand) ?? 0
        let color = Metrics.color(strand)
        let renderer = self

        return group {
            circle(radius: Metrics.rowSpacing / 2 - 1)
                .fill(color.fill)
                .opacity(context.draggedID == id ? Metrics.endHitOpacity : 0)

            label(String(strand), size: Metrics.labelSize)
                .fill(color.stroke)
                .hitTesting(.disabled)
        }
        .id(id)
        .transform(.translate(wireEnd + Metrics.endLabelOffset, rowY(row)))
        .zIndex(.relative(1))
        .onDrag { renderer.adjacentSpec(row: row) }
    }

    private func crossingHandle(_ letter: WordLetter) -> Node<PermState> {
        let id = "cross-\(letter.pairID)"
        let moves = PermMath.crossingMoves(word, index: letter.wordIndex)
        let center = Vec2(
            x(ofColumn: letter.layoutIndex) + columnWidth / 2,
            (Double(letter.generator) + 0.5) * Metrics.rowSpacing
        )
        let renderer = self

        return group {
            circle(radius: min(columnWidth, Metrics.rowSpacing) / 2)
                .fill(moves.isEmpty ? Metrics.stuck : Metrics.accent)
                .opacity(context.draggedID == id ? Metrics.activeOpacity : 0)
        }
        .id(id)
        .transform(.translate(center))
        .zIndex(.relative(1))
        .onDrag {
            guard !moves.isEmpty else { return renderer.d.fixed(renderer.state) }

            let options = moves.map { move -> DragSpec<PermState> in
                let moved = renderer.with(word: move.word)

                guard move.isBraid else { return renderer.d.between([renderer.state, moved]) }

                return renderer.d.between([renderer.byColumn(renderer.state), renderer.byColumn(moved)])
            }

            return renderer.d.closest(options)
                .withSnapRadius(Metrics.snapRadius, chaining: .chainOnSnap)
        }
    }

    private func edgeX(_ index: Int) -> Double {
        let real = columns.indices.filter { !columns[$0].isClosed }

        return x(ofColumn: index < word.count ? real[index] : columns.count) + columnWidth
    }

    /// Handles along a strand: drag a straight bit across its neighbor to
    /// write s_i s_i, the apex of a double crossing back to cancel it, or
    /// a strand bumping around the middle of a braid across it.
    private func strandHandles(_ strand: Int) -> [Node<PermState>] {
        let pairs = PermMath.doublePairs(word)
        var handles: [Node<PermState>] = []
        var row = strand - 1
        var index = 0

        while index <= word.count {
            let id = "strand-\(strand)-\(index)"
            let column = index < word.count ? word[index] : nil
            let next = column.map { rowAfter(row, $0) } ?? row

            if let column, column.isLetter, next != row, pairs.contains(index) {
                handles.append(apexHandle(id: id, index: index, row: next))
                row = rowAfter(next, column)
                index += 2
                continue
            }

            if let column, !column.isLetter, index + 1 < word.count, !word[index + 1].isLetter {
                // Mid-cancel: the apex handle lands here.
                handles.append(Node<PermState>().id(id).transform(.translate(edgeX(index), rowY(row))))
                index += 2
                continue
            }

            let side = braidSide(row: row, index: index, column: column)

            if next == row, canAppend(2) || side != nil {
                handles.append(straightHandle(id: id, index: index, row: row, side: side))
            }

            row = next
            index += 1
        }

        return handles
    }

    private enum BraidSide {
        case above, below
    }

    private func braidSide(row: Int, index: Int, column: PermColumn?) -> BraidSide? {
        guard let column, column.isLetter, PermMath.isBraid(word, at: index - 1) else { return nil }

        let outer = word[index - 1].generator

        guard row == outer || row == outer + 1 else { return nil }
        guard row != column.generator, row != column.generator + 1 else { return nil }

        return row < column.generator ? .below : .above
    }

    private func apexHandle(id: String, index: Int, row: Int) -> Node<PermState> {
        let side = Metrics.rowSpacing * 2 * Metrics.apexShare
        let renderer = self

        return group {
            rect(width: side, height: side, cornerRadius: Metrics.cornerRadius)
                .fill(Metrics.handle)
                .opacity(context.draggedID == id ? Metrics.activeOpacity : 0)
                .transform(.translate(-side / 2, -side / 2))
        }
        .id(id)
        .transform(.translate(edgeX(index), rowY(row)))
        .zIndex(.relative(1))
        .onDrag {
            renderer.d.between([renderer.state, renderer.gapped(at: index)]).onDrop(Self.closingBlanks)
        }
    }

    private func straightHandle(id: String, index: Int, row: Int, side: BraidSide?) -> Node<PermState> {
        let height = Metrics.rowSpacing * 2 * Metrics.handleRowShare
        let renderer = self

        return group {
            rect(width: columnWidth, height: height, cornerRadius: Metrics.cornerRadius)
                .fill(Metrics.handle)
                .opacity(context.draggedID == id ? Metrics.activeOpacity : 0)
                .transform(.translate(-columnWidth, -height / 2))
        }
        .id(id)
        .transform(.translate(edgeX(index), rowY(row)))
        .zIndex(.relative(1))
        .onDrag { renderer.straightSpec(index: index, row: row, side: side) }
    }

    private func straightSpec(index: Int, row: Int, side: BraidSide?) -> DragSpec<PermState> {
        let hop = { (generator: Int) in
            d.between([withClosed(at: index, generator), inserting(at: index, generator)])
        }

        let braided = { [self] () -> DragSpec<PermState> in
            d.between([byColumn(state), byColumn(with(word: PermMath.braided(word, at: index - 1)))])
        }

        var options: [DragSpec<PermState>] = []

        if side == .above {
            options.append(braided())
        } else if row > 0, canAppend(2) {
            options.append(hop(row - 1))
        }

        if side == .below {
            options.append(braided())
        } else if row < n - 1, canAppend(2) {
            options.append(hop(row))
        }

        // The branches trade places where both look like `state`, and their
        // wires have different structures, so switch instantly.
        return d.closest(options).withBranchTransition(nil)
    }
}
