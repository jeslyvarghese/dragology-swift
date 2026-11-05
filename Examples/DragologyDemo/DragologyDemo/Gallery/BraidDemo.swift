import DragologySwift
import Foundation

/// The overall size of the demo. The web version sets the cross-section
/// beside the diagram; on a phone it goes underneath, which leaves the
/// diagram's handles big enough for a finger.
enum BraidLayout {
    static let width = 390.0
    static let height = 580.0
}

private enum Metrics {
    static let rowSpacing = 28.0
    static let stroke = 3.0
    static let strandGap = 3.0
    static let halo = stroke + 2 * strandGap
    static let topMargin = 52.0
    static let openLeftMargin = 48.0
    static let openRightMargin = 44.0
    static let stub = 14.0
    static let labelOffset = 22.0
    static let wireOverhang = 14.0
    static let wordOffset = 34.0

    static let maxStrands = 6
    static let closureColumns = 12
    static let loopSpacing = 10.0
    static let topCornerRadius = 8.0
    static let bottomCornerRadius = 8.0
    static let loopGap = 2.0
    static let loopMargin = stub + Double(maxStrands - 1) * loopSpacing + 4
    static let loopMarginSlack = 4.0
    static let closureRightSlack = 12.0
    static let closureBottom = Double(maxStrands - 1) * (rowSpacing + loopSpacing)
        + topCornerRadius + bottomCornerRadius + loopGap + 16

    static let panelWidth = 150.0
    static let panelGap = 44.0
    /// Half the plane's depth, in rows, set so that a crossing's half-turn
    /// draws about 0.8 times as wide as it is tall.
    static let depth = 0.96 * panelWidth / (2 * 0.8 * rowSpacing)
    static let perspective = 0.5
    /// A turn snaps to its end, and chains on, from this close.
    static let snapDistance = 4.0
    static let panelRowOverhang = 0.75

    static let minColumns = 12
    static let handleRowShare = 0.3
    static let apexShare = 0.35
    static let crossingHandleMinRadius = 13.0
    static let handleZ = 6
    static let pointZ = 7
    static let draggedPointZ = 8
    static let activeHandleOpacity = 0.35
    static let pointHaloRadius = 11.0
    static let pointRadius = 6.5
    static let pointHaloOpacity = 0.8
    static let pointStroke = 1.5
    static let boxTopShare = 0.5
    static let boxHeightShare = 0.9
    static let boxCornerRadius = 4.0
    static let fadeDistance = 16.0
    static let crossSamples = 16
    static let halfTurn = 0.5

    static let glyphSize = 17.0
    static let scriptSize = 11.0
    static let glyphShift = 6.0
    static let inverseGlyphShift = 9.0
    static let subscriptOffset = Vec2(9, 6)
    static let superscriptOffset = Vec2(11, -7)
    static let betaOffset = -30.0
    static let labelSize = 11.0

    static let ink = SceneColor(hex: 0x1F2937)
    static let label = SceneColor(hex: 0x6B7280)
    static let handle = SceneColor(hex: 0xDC2626)
    static let crossing = SceneColor(hex: 0x2563EB)
    static let stuck = SceneColor(hex: 0x9CA3AF)
    static let panelFill = SceneColor(hex: 0xF8FAFC)
    static let panelFullFill = SceneColor(hex: 0xFFF7ED)
    static let panelFullStroke = SceneColor(hex: 0xFB923C)
    static let panelFullText = SceneColor(hex: 0xC2410C)
    static let gridLine = SceneColor(hex: 0xE2E8F0)

    static let colors: [(fill: SceneColor, stroke: SceneColor)] = [
        (SceneColor(hex: 0xFECACA), SceneColor(hex: 0xDC2626)),
        (SceneColor(hex: 0xFDE68A), SceneColor(hex: 0xD97706)),
        (SceneColor(hex: 0xBBF7D0), SceneColor(hex: 0x16A34A)),
        (SceneColor(hex: 0xBFDBFE), SceneColor(hex: 0x2563EB)),
        (SceneColor(hex: 0xDDD6FE), SceneColor(hex: 0x7C3AED)),
        (SceneColor(hex: 0xFBCFE8), SceneColor(hex: 0xDB2777)),
    ]
}

/// Samples across a crossing drawn along two tracks: how far along it
/// is, and how far across, matching the cubic a column draws.
private let crossSamples: [(along: Double, across: Double)] = (0...Metrics.crossSamples).map { index in
    let s = Double(index) / Double(Metrics.crossSamples)

    return (1.5 * s * (1 - s) + s * s * s, 3 * s * s - 2 * s * s * s)
}

func braid(_ context: SceneContext<BraidState>) -> SceneNode<BraidState> {
    BraidRenderer(context).scene()
}

/// Where a strand can be grabbed.
private enum StrandHandle {
    enum BraidSide {
        case above, below
    }

    /// The tip of a cancelling pair: drag it back across to cancel.
    case apex(index: Int, row: Int)
    /// Where an apex lands mid-cancel. Not draggable.
    case blank(index: Int, row: Int)
    /// A straight run: drag it across a neighbor to pass in front of it
    /// and back, or across the middle of a braid for the braid move.
    case straight(index: Int, row: Int, braidSide: BraidSide?)

    var index: Int {
        switch self {
        case .apex(let index, _), .blank(let index, _), .straight(let index, _, _):
            return index
        }
    }

    var row: Int {
        switch self {
        case .apex(_, let row), .blank(_, let row), .straight(_, let row, _):
            return row
        }
    }
}

/// One crossing's drawing and the handle that goes with it.
private struct LaidOutColumn {
    var column: BraidColumn
    var layoutIndex: Int
    var wordIndex: Int
    var pairID: String
    var handleID: String
}

/// A conjugation, laid out along its two loops.
private struct Displacement {
    var isComingIn: Bool
    var layoutIndex: Int
    var row: Int
    var shift: Double
    var tracks: [BraidTrack]
    var trackStarts: [Double]
    var center: Vec2
    /// How far along the loops the right edge of the diagram is.
    var seam: Double

    /// The crossing drawn along the tracks, from track `k` to the other.
    func crossingPoints(from k: Int, width: Double) -> [Vec2] {
        crossSamples.map { sample in
            Vec2.lerp(
                tracks[k].point(at: trackStarts[k] + sample.along * width),
                tracks[1 - k].point(at: trackStarts[1 - k] + sample.along * width),
                sample.across
            )
        }
    }
}

private struct WirePiece {
    var key: String
    var commands: [PathCommand]
    var z: Int
}

/// Lays out and draws one state.
private struct BraidRenderer {
    let context: SceneContext<BraidState>
    let d: DragSpecBuilder<BraidState>
    let raw: BraidState
    let n: Int
    let isClosure: Bool
    let columns: [BraidColumn]
    let word: [BraidColumn]
    let palette: [Int]?
    /// The cleaned state that drags build on.
    let state: BraidState
    let permutation: [Int]
    let length: Int
    let columnCount: Int
    let origin: Vec2
    let rightMargin: Double
    let columnWidth: Double
    let wireEnd: Double
    /// How far the last row is below the one above it, in rows.
    let grow: Double
    let crossings: [BraidMath.Crossing]

    private let wireStart = 0.0

    init(_ context: SceneContext<BraidState>) {
        self.context = context
        d = context.drag

        // Past halfway, a conjugation is drawn as the word with the
        // crossing moved to the front, coming in from behind.
        var raw = context.state

        if let orbit = raw.orbit, orbit.t >= Metrics.halfTurn {
            let rotated = BraidMath.rotated(raw.word, palette: raw.palette)

            raw.word = rotated.word
            raw.palette = rotated.palette
        }

        self.raw = raw
        n = raw.n
        isClosure = raw.isClosure
        columns = raw.word
        word = raw.word.filter(\.isInWord).map(\.letter)

        palette = raw.isClosure
            ? BraidMath.recolored(n: raw.n, columns: raw.word, hint: raw.palette, colorCount: Metrics.colors.count)
            : nil

        state = BraidState(n: raw.n, word: word, isClosure: raw.isClosure, palette: palette)
        permutation = BraidMath.permutation(n: raw.n, word: word)
        length = word.count
        columnCount = raw.isClosure ? Metrics.closureColumns : max(Metrics.minColumns, 2 * raw.n + 4)

        origin = Vec2(
            raw.isClosure ? Metrics.loopMargin + Metrics.loopMarginSlack : Metrics.openLeftMargin,
            Metrics.topMargin
        )

        rightMargin = raw.isClosure ? Metrics.loopMargin + Metrics.closureRightSlack : Metrics.openRightMargin
        columnWidth = (BraidLayout.width - origin.x - rightMargin) / Double(columnCount)
        wireEnd = Double(columnCount) * columnWidth
        grow = raw.newRowStrand == nil ? 1 : 0
        crossings = BraidMath.crossings(n: raw.n, columns: raw.word)
    }

    // MARK: Capacity

    private var capacity: Int { columnCount - 1 }

    private func canAppend(_ count: Int) -> Bool {
        length + count <= capacity
    }

    /// A crossing being turned counts once it's past halfway.
    private var isFull: Bool {
        let hasTurned = columns.contains { $0.isPending && $0.p > Metrics.halfTurn }

        return length + (hasTurned ? 1 : 0) >= capacity
    }

    // MARK: Geometry

    private var lastRow: Int { n - 1 }

    private func rowY(_ row: Double) -> Double {
        let split = Double(n - 2)

        return Metrics.rowSpacing * (min(row, split) + max(0, row - split) * grow)
    }

    private func rowY(_ row: Int) -> Double {
        rowY(Double(row))
    }

    private var loopBottom: Double {
        rowY(lastRow) + Metrics.topCornerRadius + Metrics.bottomCornerRadius + Metrics.loopGap
    }

    /// How far a row's loop is outside the innermost one.
    private func loopOffset(_ row: Double) -> Double {
        let level = Double(lastRow) - row

        return (level <= 1 ? level * grow : level - 1 + grow) * Metrics.loopSpacing
    }

    /// A row's loop, from the right around to the left, into row `endRow`.
    private func loopTrack(row: Double, from startX: Double, to endX: Double, endRow: Double? = nil) -> BraidTrack {
        let y = rowY(row)
        let endY = rowY(endRow ?? row)
        let offset = loopOffset(row)
        let right = wireEnd + Metrics.stub + offset
        let left = wireStart - Metrics.stub - offset
        let bottom = loopBottom + offset
        let bottomRadius = Metrics.bottomCornerRadius + offset
        let radius = Metrics.topCornerRadius
        let pi = Double.pi

        return BraidTrack(start: Vec2(startX, y))
            .line(to: Vec2(right - radius, y))
            .arc(center: Vec2(right - radius, y + radius), radius: radius, from: -pi / 2, to: 0)
            .line(to: Vec2(right, bottom - bottomRadius))
            .arc(center: Vec2(right - bottomRadius, bottom - bottomRadius), radius: bottomRadius, from: 0, to: pi / 2)
            .line(to: Vec2(left + bottomRadius, bottom))
            .arc(center: Vec2(left + bottomRadius, bottom - bottomRadius), radius: bottomRadius, from: pi / 2, to: pi)
            .line(to: Vec2(left, endY + radius))
            .arc(center: Vec2(left + radius, endY + radius), radius: radius, from: pi, to: 3 * pi / 2)
            .line(to: Vec2(endX, endY))
    }

    /// The crossing on its way around, drawn along its two loops. It stays
    /// in the word, so everything else draws just as in that word.
    private var displacement: Displacement? {
        guard let orbit = raw.orbit else { return nil }

        let isComingIn = orbit.t >= Metrics.halfTurn
        let layoutIndex = isComingIn ? 0 : columns.count - 1
        let row = columns[layoutIndex].i
        let restWidth = Double(columns.count - 1) * columnWidth
        let rows = [Double(row), Double(row + 1)]

        let lengths = rows.map { loopTrack(row: $0, from: wireStart + restWidth, to: wireStart).length }
        let middleLength = (lengths[0] + lengths[1]) / 2

        // At the front, its column opens up as it comes in.
        let opening = columnWidth - (1 - orbit.t) * (middleLength - columnWidth)
        let shift = isComingIn ? min(max(opening, 0), columnWidth) : 0
        let startX = wireStart + shift

        let tracks = rows.map { loopTrack(row: $0, from: startX + restWidth, to: startX) }
        let starts = lengths.map { orbit.t * ($0 - columnWidth) }

        let center = Vec2.lerp(
            tracks[0].point(at: starts[0] + columnWidth / 2),
            tracks[1].point(at: starts[1] + columnWidth / 2),
            Metrics.halfTurn
        )

        return Displacement(
            isComingIn: isComingIn,
            layoutIndex: layoutIndex,
            row: row,
            shift: shift,
            tracks: tracks,
            trackStarts: starts,
            center: center,
            seam: wireEnd - (startX + restWidth)
        )
    }

    private func width(ofColumn index: Int, _ disp: Displacement?) -> Double {
        if let disp, disp.isComingIn, index == 0 { return disp.shift }

        guard index < columns.count else { return columnWidth }

        let column = columns[index]

        if column.isClosed || column.isFlat { return 0 }
        if column.isPending { return column.p * columnWidth }

        return columnWidth
    }

    private func x(ofColumn index: Int, _ disp: Displacement?) -> Double {
        let laidOut = min(index, columns.count)
        let widths = (0..<laidOut).reduce(0.0) { $0 + width(ofColumn: $1, disp) }

        return wireStart + widths + Double(max(0, index - columns.count)) * columnWidth
    }

    /// The right edge of logical column `index`.
    private func edgeX(_ index: Int, _ disp: Displacement?) -> Double {
        let real = columns.indices.filter { columns[$0].isInWord }

        return x(ofColumn: index < length ? real[index] : columns.count, disp) + columnWidth
    }

    // MARK: Column ids

    /// Each column with a stable id: the pair of strands in its rows,
    /// suffixed if that pair meets more than once.
    private var laidOutColumns: [LaidOutColumn] {
        var seen = Set<String>()
        var seenHandles = Set<String>()

        func take(_ key: String, _ used: inout Set<String>) -> String {
            var id = key

            while used.contains(id) { id += "x" }

            used.insert(id)

            return id
        }

        var wordIndex = 0

        return columns.enumerated().map { index, column in
            let key = BraidMath.pairKey(crossings[index].a, crossings[index].b)
            let pairID = take(key, &seen)
            let handleID = column.isClosed ? "" : take(key, &seenHandles)
            let logical = column.isInWord ? wordIndex : -1

            if column.isInWord { wordIndex += 1 }

            return LaidOutColumn(
                column: column,
                layoutIndex: index,
                wordIndex: logical,
                pairID: pairID,
                handleID: handleID
            )
        }
    }

    // MARK: Rewrites

    /// Two zero-width columns at `index`, drawn the same as `state`, so
    /// that an inserted pair widens from nothing.
    private func withClosed(at index: Int, _ letter: BraidColumn) -> BraidState {
        var closed = letter
        closed.gap = .closed

        var copy = state
        copy.word.insert(contentsOf: [closed, closed], at: index)

        return copy
    }

    private func inserting(at index: Int, _ letter: BraidColumn) -> BraidState {
        let inverse = BraidColumn(i: letter.i, sign: letter.sign.inverse)

        var copy = state
        copy.word.insert(contentsOf: [letter, inverse], at: index)

        return copy
    }

    /// Cancels the pair at `index` into blanks, so nothing shifts mid-drag.
    private func gapped(at index: Int) -> BraidState {
        var blank = word[index]
        blank.gap = .blank

        var copy = state
        copy.word[index] = blank
        copy.word[index + 1] = blank

        return copy
    }

    private static func closingBlanks(_ state: BraidState) -> BraidState {
        var copy = state

        copy.word = state.word.map { column in
            guard column.gap == .blank else { return column }

            var closed = column
            closed.gap = .closed

            return closed
        }

        return copy
    }

    private func byColumn(_ state: BraidState, from start: Int) -> BraidState {
        var copy = state
        copy.wiresByColumn = start
        return copy
    }

    // MARK: Strand handles

    private func strandHandles(_ strand: Int) -> [StrandHandle] {
        let wordColumns = columns.filter(\.isInWord)
        var handles: [StrandHandle] = []
        var row = strand - 1
        var index = 0

        while index <= length {
            let column = index < length ? wordColumns[index] : nil
            let next = index + 1 < length ? wordColumns[index + 1] : nil
            let letter = column.flatMap { $0.isLetter ? word[index] : nil }
            let nextRow = letter.map { BraidMath.rowAfter(row, $0) } ?? row

            if letter != nil, nextRow != row, BraidMath.cancels(column, next) {
                handles.append(.apex(index: index, row: nextRow))
                row = nextRow
                index += 1
                continue
            }

            if let column, !column.isLetter, BraidMath.cancels(column, next) {
                handles.append(.blank(index: index, row: row))
                index += 2
                continue
            }

            let side = braidSide(row: row, index: index, letter: letter)

            if nextRow == row, canAppend(2) || side != nil {
                handles.append(.straight(index: index, row: row, braidSide: side))
            }

            row = nextRow
            index += 1
        }

        return handles
    }

    /// Which side a strand bypasses a braid's middle crossing on, if it does.
    private func braidSide(row: Int, index: Int, letter: BraidColumn?) -> StrandHandle.BraidSide? {
        guard let letter, BraidMath.isBraid(n: n, word: word, at: index - 1) else { return nil }

        let outer = word[index - 1].i

        guard row == outer || row == outer + 1 else { return nil }
        guard row != letter.i, row != letter.i + 1 else { return nil }

        return row < letter.i ? .below : .above
    }

    // MARK: Wires

    /// The stacking of strand `strand` in column `index`. It has to agree
    /// at both ends of every drag, as stacking isn't blended.
    private func pieceZ(strand: Int, column index: Int) -> Int {
        if let start = raw.wiresByColumn {
            let window = Array(start..<(start + 3))
            let strands = Set(window.flatMap { [crossings[$0].a, crossings[$0].b] })

            if window.contains(index), strands.contains(strand) {
                return window.filter { crossings[$0].over == strand }.count
            }
        }

        return index < columns.count && crossings[index].over == strand ? 1 : 0
    }

    private static func polyline(_ points: [Vec2]) -> [PathCommand] {
        points.map(PathCommand.line)
    }

    /// A strand as pieces, each its own layer over a white halo, so it's
    /// broken exactly where something in front of it passes. Piece k blends
    /// with piece k, so every drag keeps each strand's number of pieces.
    private func wirePieces(_ strand: Int, _ disp: Displacement?) -> (pieces: [WirePiece], endRow: Double) {
        var pieces: [WirePiece] = []
        var row = Double(strand - 1)
        var from: [PathCommand] = [
            .move(Vec2(isClosure ? wireStart : wireStart - Metrics.wireOverhang, rowY(row))),
        ]
        var onTrack: BraidTrack?
        var trackFrom = 0.0

        func push(_ commands: [PathCommand], z: Int) {
            pieces.append(WirePiece(key: String(pieces.count), commands: commands, z: z))
        }

        for (index, column) in columns.enumerated() {
            let intRow = Int(row.rounded())
            let isInColumn = intRow == column.i || intRow == column.i + 1

            if raw.wiresByColumn == nil, !isInColumn { continue }

            // A pending crossing ends partway, where its turn has got to.
            let endRow: Double

            if column.isPending {
                endRow = row + Double(BraidMath.rowAfter(intRow, column.letter) - intRow) * column.p
            } else {
                endRow = Double(BraidMath.rowAfter(intRow, column))
            }

            let z = pieceZ(strand: strand, column: index)

            if let disp, index == disp.layoutIndex {
                let k = intRow == disp.row ? 0 : 1
                let other = disp.tracks[1 - k]
                let points = disp.crossingPoints(from: k, width: columnWidth)
                let after = disp.trackStarts[1 - k] + columnWidth
                let last = points[points.count - 1]

                if disp.isComingIn {
                    // Just the crossing, then on around the loop.
                    push([.move(points[0])] + Self.polyline(Array(points.dropFirst())), z: z)
                    from = [.move(last)] + Self.polyline(other.points(from: after, to: other.length))
                } else {
                    // The run out along the loop to the crossing, and it.
                    let run = disp.tracks[k].points(from: 0, to: disp.trackStarts[k])

                    push(from + Self.polyline(run) + Self.polyline(points), z: z)
                    from = [.move(last)]
                    onTrack = other
                    trackFrom = after
                }

                row = endRow
                continue
            }

            let x = x(ofColumn: index, disp)
            let w = width(ofColumn: index, disp)
            let startY = rowY(row)
            let endY = rowY(endRow)

            push(
                from + [
                    .line(Vec2(x, startY)),
                    .cubic(
                        control1: Vec2(x + w / 2, startY),
                        control2: Vec2(x + w / 2, endY),
                        end: Vec2(x + w, endY)
                    ),
                ],
                z: z
            )

            from = [.move(Vec2(x + w, endY))]
            row = endRow
        }

        // Keyed apart, so a column added at the end doesn't take this over.
        let free: [PathCommand]

        if let onTrack, let disp {
            free = from + Self.polyline(onTrack.points(from: trackFrom, to: max(trackFrom, disp.seam)))
        } else {
            free = from + [.line(Vec2(isClosure ? wireEnd : wireEnd + Metrics.wireOverhang, rowY(row)))]
        }

        pieces.append(WirePiece(key: "free", commands: free, z: 0))

        return (pieces, row)
    }

    private func loopPath(row: Double, _ disp: Displacement?) -> [PathCommand] {
        let points: [Vec2]

        if let disp, row == Double(disp.row) || row == Double(disp.row + 1) {
            let k = Int(row) - disp.row
            let track = disp.tracks[k]
            let start = disp.trackStarts[k]

            points = disp.isComingIn
                ? track.points(from: disp.seam, to: max(disp.seam, start))
                : track.points(from: max(disp.seam, start + columnWidth), to: track.length)
        } else {
            let track = loopTrack(row: row, from: wireEnd, to: wireStart, endRow: row.rounded())
            points = track.points(from: 0, to: track.length)
        }

        return [.move(points[0])] + Self.polyline(Array(points.dropFirst()))
    }

    private func strandColor(_ strand: Int) -> (fill: SceneColor, stroke: SceneColor) {
        let index = palette.map { $0[strand - 1] } ?? (strand - 1)
        return Metrics.colors[index % Metrics.colors.count]
    }

    /// A strand coming out of the row above hides until it's out.
    private func strandOpacity(_ strand: Int) -> Double {
        raw.newRowStrand == strand ? 0 : 1
    }

    // MARK: Cross-section

    /// Each strand's row and depth at the right end of the diagram. The
    /// strands are points in a plane, and a crossing is a half-turn.
    private func endConfiguration(_ disp: Displacement?) -> [Int: (row: Double, depth: Double)] {
        var rows = Array(1...max(n, 1))
        var turning: (index: Int, angle: Double)?

        for (index, column) in columns.enumerated() {
            if column.isPending {
                turning = (index, acos(1 - 2 * column.p))
                break
            }

            guard column.isLetter else { continue }

            if let disp, !disp.isComingIn, index == disp.layoutIndex {
                // Only as far through as it's got by the right edge.
                let average = disp.trackStarts.reduce(0, +) / Double(disp.trackStarts.count)
                let done = min(max((disp.seam - average) / columnWidth, 0), 1)

                if done < 1 {
                    turning = (index, BraidMath.turnAngle(atFraction: done))
                    break
                }
            }

            rows.swapAt(column.i, column.i + 1)
        }

        var positions: [Int: (row: Double, depth: Double)] = [:]

        for (row, strand) in rows.enumerated() {
            positions[strand] = (Double(row), 0)
        }

        guard let turning else { return positions }

        let i = columns[turning.index].i
        let over = crossings[turning.index].over
        let cosine = cos(turning.angle)
        let sine = sin(turning.angle)

        for (offset, strand) in [rows[i], rows[i + 1]].enumerated() {
            positions[strand] = (
                Double(i) + Metrics.halfTurn + (offset == 0 ? -Metrics.halfTurn : Metrics.halfTurn) * cosine,
                (strand == over ? Metrics.halfTurn : -Metrics.halfTurn) * sine
            )
        }

        return positions
    }

    private var panelX: Double {
        (BraidLayout.width - Metrics.panelWidth) / 2 - origin.x
    }

    /// How far below the diagram the cross-section sits.
    private var panelOffsetY: Double {
        let bottom = isClosure ? Metrics.closureBottom : rowY(lastRow) + Metrics.wordOffset

        return bottom + Metrics.panelGap
    }

    /// Where height `y` at a depth is drawn: in perspective, with the near
    /// edge on the right, and the depth-0 line at full scale.
    private func project(_ y: Double, depth: Double) -> (position: Vec2, scale: Double) {
        let perspective = Metrics.perspective
        let u = Metrics.halfTurn - depth / (2 * Metrics.depth)
        let scale = (1 + perspective / 2) / (1 + perspective * u)
        let middleY = (rowY(0) + rowY(lastRow)) / 2

        let x = panelX + Metrics.panelWidth
            - Metrics.panelWidth * u * (1 + perspective) / (1 + perspective * u)

        return (Vec2(x, panelOffsetY + middleY + (y - middleY) * scale), scale)
    }

    // MARK: Drags

    /// Turning a point writes a crossing at the end of the word. Reaching
    /// the end snaps to it and chains on, so one drag can keep turning.
    private func turnSpec(strand: Int, toRow target: Int, isInFront: Bool) -> DragSpec<BraidState>? {
        guard canAppend(1) else { return nil }

        let row = permutation.firstIndex(of: strand) ?? 0
        let letter = BraidColumn(i: min(row, target), sign: (row < target) == isInFront ? .positive : .negative)
        let index = length

        var pending = letter
        pending.gap = .pending

        var turning = state
        turning.word.append(pending)

        var done = state
        done.word.append(letter)

        let cleaned = state

        return d
            .vary(turning, \.word[index].p, constraint: { candidate in
                DragConstraint.inOrder(0, candidate.word[index].p, 1)
            })
            .onDrop { $0.word[index].p > Metrics.halfTurn ? done : cleaned }
            .withSnapRadius(Metrics.snapDistance, chaining: .chainOnSnap)
    }

    private func pointSpec(_ strand: Int) -> DragSpec<BraidState> {
        let row = permutation.firstIndex(of: strand) ?? 0
        let rest = project(0, depth: 0).position.x + origin.x
        let low = rest - Metrics.snapDistance
        let high = rest + Metrics.snapDistance

        var options: [DragSpec<BraidState>] = []

        for isInFront in [true, false] {
            if row > 0, let spec = turnSpec(strand: strand, toRow: row - 1, isInFront: isInFront) {
                options.append(spec)
            }

            if row < n - 1, let spec = turnSpec(strand: strand, toRow: row + 1, isInFront: isInFront) {
                options.append(spec)
            }
        }

        // Holds the finger near the line the points rest on: enough to
        // say which way around, and close enough to snap at the end.
        return d.closest(options).changeFrame { frame in
            DragFrame(pointer: Vec2(min(max(frame.pointer.x, low), high), frame.pointer.y))
        }
    }

    /// Conjugates by dragging a crossing around its loops, starting `t` of
    /// the way from the end of the word to the front.
    private func orbitSpec(word orbitWord: [BraidColumn], palette: [Int]?, t: Double, id: String) -> DragSpec<BraidState> {
        var start = state
        start.word = orbitWord
        start.palette = palette
        start.orbit = BraidOrbit(t: t, id: id)

        return d
            .vary(start, \.orbit!.t, constraint: { candidate in
                DragConstraint.inOrder(0, candidate.orbit?.t ?? 0, 1)
            })
            .onDrop { dropped in
                var result = dropped
                result.orbit = nil

                guard (dropped.orbit?.t ?? 0) >= Metrics.halfTurn else { return result }

                let rotated = BraidMath.rotated(dropped.word, palette: dropped.palette)

                result.word = rotated.word
                result.palette = rotated.palette

                return result
            }
    }

    /// Pulls the bottom strand down into a new row and loop, crossing the
    /// new strand at that end of the word.
    private func stabilizeSpec(isAtEnd: Bool) -> DragSpec<BraidState>? {
        guard let palette, n < Metrics.maxStrands, canAppend(1) else { return nil }

        let letter = BraidColumn(i: n - 1, sign: isAtEnd ? .positive : .negative)
        let color = palette[(isAtEnd ? permutation[n - 1] : n) - 1]

        var grown = state
        grown.n = n + 1
        grown.word = isAtEnd ? word + [letter] : [letter] + word
        grown.palette = palette + [color]

        var hidden = letter

        if isAtEnd {
            hidden.gap = .closed
        } else {
            hidden.isFlat = true
        }

        var start = grown
        start.word = isAtEnd ? word + [hidden] : [hidden] + word
        start.newRowStrand = isAtEnd ? n + 1 : n

        let cleaned = state

        return d.between([start, grown]).onDrop { $0.newRowStrand != nil ? cleaned : $0 }
    }

    /// Which end of the word the bottom row's only crossing is at.
    private var kinkIsAtEnd: Bool? {
        guard palette != nil, n >= 2 else { return nil }

        let indices = word.indices.filter { word[$0].i == n - 2 }

        guard indices.count == 1 else { return nil }

        if indices[0] == length - 1 { return true }

        return indices[0] == 0 ? false : nil
    }

    /// Undoes a kink, Reidemeister I style, by pulling the loop back in.
    private func destabilizeSpec() -> DragSpec<BraidState>? {
        guard let palette, let isAtEnd = kinkIsAtEnd else { return nil }

        let index = isAtEnd ? length - 1 : 0

        var shrunk = state

        if isAtEnd {
            shrunk.word[index].gap = .closed
        } else {
            shrunk.word[index].isFlat = true
        }

        shrunk.newRowStrand = isAtEnd ? n : n - 1

        var gone = state
        gone.n = n - 1
        gone.word = isAtEnd ? Array(word.dropLast()) : Array(word.dropFirst())
        gone.palette = Array(palette.dropLast())

        let current = state

        return d.between([current, shrunk]).onDrop { $0.newRowStrand != nil ? gone : $0 }
    }

    private func crossingSpec(_ laidOut: LaidOutColumn, id: String) -> DragSpec<BraidState>? {
        let index = laidOut.wordIndex
        let moves = BraidMath.crossingMoves(n: n, word: word, index: index)

        var options = moves.map { move -> DragSpec<BraidState> in
            var moved = state
            moved.word = move.word

            guard move.isBraid else { return d.between([state, moved]) }

            return d.between([byColumn(state, from: index - 1), byColumn(moved, from: index - 1)])
        }

        // In the closure, the last crossing can go on around its loops to
        // the front, and the first one back around to the end.
        if let palette {
            if index == length - 1 {
                options.append(orbitSpec(word: word, palette: palette, t: 0, id: id))
            }

            if index == 0, length > 1 {
                let first = laidOut.column.letter

                options.append(orbitSpec(
                    word: Array(word.dropFirst()) + [first],
                    palette: BraidMath.swappedColors(palette, first),
                    t: 1,
                    id: id
                ))
            }
        }

        return options.isEmpty ? nil : d.closest(options)
    }

    private func straightSpec(index: Int, row: Int, braidSide: StrandHandle.BraidSide?) -> DragSpec<BraidState> {
        var braidedState = state

        if braidSide != nil {
            braidedState.word = BraidMath.braided(n: n, word: word, at: index - 1)
        }

        let braided = d.between([byColumn(state, from: index - 1), byColumn(braidedState, from: index - 1)])

        func hop(to target: Int) -> DragSpec<BraidState> {
            let letter = BraidColumn(i: min(row, target), sign: row < target ? .positive : .negative)

            return d.between([withClosed(at: index, letter), inserting(at: index, letter)])
        }

        var options: [DragSpec<BraidState>] = []

        if braidSide == .above {
            options.append(braided)
        } else if row > 0, canAppend(2) {
            options.append(hop(to: row - 1))
        }

        if braidSide == .below {
            options.append(braided)
        } else if row < n - 1, canAppend(2) {
            options.append(hop(to: row + 1))
        }

        // The branches only trade places where both look like `state`, and
        // their wires have different structures, so switch instantly.
        return d.closest(options).withBranchTransition(nil)
    }

    // MARK: Drawing

    func scene() -> SceneNode<BraidState> {
        let disp = displacement
        let strands = (1...max(n, 1)).map { strand in
            (strand: strand, wire: wirePieces(strand, disp))
        }

        let laidOut = laidOutColumns
        var diagram: [SceneNode<BraidState>] = []

        if isClosure {
            diagram.append(closureBox())
        } else {
            diagram += strandLabels(disp)
        }

        for (strand, wire) in strands {
            diagram += wireNodes(strand, wire.pieces)
        }

        if isClosure {
            for (strand, wire) in strands {
                diagram += loopNodes(strand, endRow: wire.endRow, disp)
            }
        }

        diagram += laidOut.filter(\.column.isLetter).map { crossingHandle($0, disp) }

        for strand in 1...max(n, 1) {
            diagram.append(strandHandleGroup(strand, disp))
        }

        if palette != nil {
            diagram += [curlHandle(isAtEnd: true), curlHandle(isAtEnd: false), innerLoopHandle()]
        }

        return SceneNode(children: [
            SceneNode(children: diagram).transform(.translate(origin)),
            wordRow(laidOut, disp),
            SceneNode(children: panel(disp)).transform(.translate(origin)),
        ])
    }

    private func closureBox() -> SceneNode<BraidState> {
        let top = rowY(0) - Metrics.boxTopShare * Metrics.rowSpacing
        let height = rowY(lastRow) - rowY(0) + Metrics.boxHeightShare * Metrics.rowSpacing

        return SceneRect(width: wireEnd - wireStart, height: height, cornerRadius: Metrics.boxCornerRadius)
            .stroke(Ink.outline)
            .transform(.translate(wireStart, top))
    }

    private func strandLabels(_ disp: Displacement?) -> [SceneNode<BraidState>] {
        let ends = endConfiguration(disp)

        return (1...max(n, 1)).flatMap { strand -> [SceneNode<BraidState>] in
            [
                SceneText(String(strand), size: Metrics.labelSize)
                    .fill(Metrics.label)
                    .transform(.translate(wireStart - Metrics.labelOffset, rowY(strand - 1)))
                    .hitTesting(.disabled),

                SceneText(String(strand), size: Metrics.labelSize)
                    .id("wire-end-\(strand)")
                    .fill(Metrics.colors[(strand - 1) % Metrics.colors.count].stroke)
                    .transform(.translate(wireEnd + Metrics.labelOffset, rowY(ends[strand]?.row ?? 0)))
                    .hitTesting(.disabled),
            ]
        }
    }

    private func wireNodes(_ strand: Int, _ pieces: [WirePiece]) -> [SceneNode<BraidState>] {
        pieces.flatMap { piece -> [SceneNode<BraidState>] in
            [
                ScenePath(piece.commands)
                    .id("wire-\(strand)-\(piece.key)-halo")
                    .stroke(.white, lineWidth: Metrics.halo)
                    .zIndex(.relative(2 * piece.z))
                    .opacity(strandOpacity(strand)),

                ScenePath(piece.commands)
                    .id("wire-\(strand)-\(piece.key)")
                    .stroke(strandColor(strand).stroke, lineWidth: Metrics.stroke)
                    .zIndex(.relative(2 * piece.z + 1))
                    .opacity(strandOpacity(strand)),
            ]
        }
    }

    private func loopNodes(_ strand: Int, endRow: Double, _ disp: Displacement?) -> [SceneNode<BraidState>] {
        let row = Int(endRow.rounded())
        let commands = loopPath(row: endRow, disp)

        return [
            ScenePath(commands)
                .id("loop-\(row)-halo")
                .stroke(.white, lineWidth: Metrics.halo)
                .opacity(strandOpacity(strand)),

            ScenePath(commands)
                .id("loop-\(row)")
                .stroke(strandColor(strand).stroke, lineWidth: Metrics.stroke)
                .zIndex(.relative(1))
                .opacity(strandOpacity(strand)),
        ]
    }

    private func crossingHandle(_ laidOut: LaidOutColumn, _ disp: Displacement?) -> SceneNode<BraidState> {
        let isDisplaced = disp?.layoutIndex == laidOut.layoutIndex
        let base = "cross-\(laidOut.handleID)"
        let id: String

        // The crossing going around keeps the dragged handle's id, which
        // another crossing of the word it's drawn in might have.
        if isDisplaced, let orbit = raw.orbit {
            id = orbit.id
        } else {
            id = base + (raw.orbit?.id == base ? "-o" : "")
        }

        let column = laidOut.column
        let spec = laidOut.wordIndex >= 0 ? crossingSpec(laidOut, id: id) : nil
        let columnX = x(ofColumn: laidOut.layoutIndex, disp)
        let center = isDisplaced
            ? (disp?.center ?? .zero)
            : Vec2(columnX + columnWidth / 2, (rowY(column.i) + rowY(column.i + 1)) / 2)
        let radius = max(min(columnWidth, Metrics.rowSpacing) / 2 - 1, Metrics.crossingHandleMinRadius)
        let cleaned = state
        let builder = d

        return SceneGroup {
            SceneCircle(radius: radius)
                .fill(spec == nil ? Metrics.stuck : Metrics.crossing)
                .opacity(context.draggedID == id ? Metrics.activeHandleOpacity : 0)
        }
        .id(id)
        .transform(.translate(center))
        .zIndex(.relative(Metrics.handleZ))
        .onDrag { spec ?? builder.fixed(cleaned) }
    }

    private func strandHandleGroup(_ strand: Int, _ disp: Displacement?) -> SceneNode<BraidState> {
        let handles = strandHandles(strand).map { handle -> SceneNode<BraidState> in
            let id = "strand-\(strand)-\(handle.index)"
            let position = SceneTransform.translate(edgeX(handle.index, disp), rowY(handle.row))

            switch handle {
            case .blank:
                return SceneNode<BraidState>().id(id).transform(position)

            case .apex(let index, _):
                return apexHandle(id: id, at: position, index: index)

            case .straight(let index, let row, let side):
                return straightHandle(id: id, at: position, index: index, row: row, side: side)
            }
        }

        return SceneNode(children: handles).key("strand-handles-\(strand)")
    }

    private func apexHandle(id: String, at position: SceneTransform, index: Int) -> SceneNode<BraidState> {
        let side = Metrics.rowSpacing * 2 * Metrics.apexShare
        let half = side / 2
        let current = state
        let cancelled = gapped(at: index)
        let builder = d

        return SceneGroup {
            SceneRect(width: side, height: side, cornerRadius: Metrics.boxCornerRadius)
                .fill(Metrics.handle)
                .opacity(context.draggedID == id ? Metrics.activeHandleOpacity : 0)
                .transform(.translate(-half, -half))
        }
        .id(id)
        .transform(position)
        .zIndex(.relative(Metrics.handleZ))
        .onDrag { builder.between([current, cancelled]).onDrop(Self.closingBlanks) }
    }

    private func straightHandle(
        id: String,
        at position: SceneTransform,
        index: Int,
        row: Int,
        side: StrandHandle.BraidSide?
    ) -> SceneNode<BraidState> {
        let renderer = self
        let height = Metrics.rowSpacing * 2 * Metrics.handleRowShare

        return SceneGroup {
            SceneRect(width: columnWidth, height: height, cornerRadius: Metrics.boxCornerRadius)
                .fill(Metrics.handle)
                .opacity(context.draggedID == id ? Metrics.activeHandleOpacity : 0)
                .transform(.translate(-columnWidth, -height / 2))
        }
        .id(id)
        .transform(position)
        .zIndex(.relative(Metrics.handleZ))
        .onDrag { renderer.straightSpec(index: index, row: row, braidSide: side) }
    }

    private func curlHandle(isAtEnd: Bool) -> SceneNode<BraidState> {
        let id = isAtEnd ? "curl-right" : "curl-left"
        let left = isAtEnd ? -columnWidth : -Metrics.stub
        let right = isAtEnd ? Metrics.stub : 4
        let height = Metrics.rowSpacing * 2 * Metrics.handleRowShare

        let handle: SceneNode<BraidState> = SceneGroup {
            SceneRect(width: right - left, height: height, cornerRadius: Metrics.boxCornerRadius)
                .fill(Metrics.handle)
                .opacity(context.draggedID == id ? Metrics.activeHandleOpacity : 0)
                .transform(.translate(left, -height / 2))
        }
        .id(id)
        .transform(.translate(isAtEnd ? wireEnd : wireStart, rowY(lastRow)))
        .zIndex(.relative(Metrics.handleZ))

        // It stays when it can't be dragged, as where the dragged one lands.
        guard let spec = stabilizeSpec(isAtEnd: isAtEnd) else { return handle }

        return handle.onDrag { spec }
    }

    private func innerLoopHandle() -> SceneNode<BraidState> {
        let id = "inner-loop"
        let left = wireStart - Metrics.stub + Metrics.bottomCornerRadius
        let right = wireEnd + Metrics.stub - Metrics.bottomCornerRadius
        let height = Metrics.rowSpacing * 2 * Metrics.handleRowShare

        let handle: SceneNode<BraidState> = SceneGroup {
            SceneRect(width: right - left, height: height, cornerRadius: Metrics.boxCornerRadius)
                .fill(Metrics.handle)
                .opacity(context.draggedID == id ? Metrics.activeHandleOpacity : 0)
                .transform(.translate(-(right - left) / 2, -height / 2))
        }
        .id(id)
        .transform(.translate((left + right) / 2, loopBottom))
        .zIndex(.relative(Metrics.handleZ))

        guard let spec = destabilizeSpec() else { return handle }

        return handle.onDrag { spec }
    }

    // MARK: The word

    /// One letter under each crossing, or over it in the closure, whose
    /// loops are underneath, so letters travel with their crossings.
    private func wordRow(_ laidOut: [LaidOutColumn], _ disp: Displacement?) -> SceneNode<BraidState> {
        let y = isClosure ? -Metrics.wordOffset : rowY(lastRow) + Metrics.wordOffset
        let pending = laidOut.first { $0.column.isPending }

        var parts: [SceneNode<BraidState>] = [
            SceneText("β", size: Metrics.glyphSize)
                .fill(Metrics.ink)
                .transform(.translate(Metrics.betaOffset, 0))
                .hitTesting(.disabled),
        ]

        if length == 0, pending == nil {
            parts.append(
                SceneText("e", size: Metrics.glyphSize)
                    .fill(Metrics.stuck)
                    .transform(.translate(columnWidth / 2, 0))
                    .hitTesting(.disabled)
            )
        }

        for item in laidOut where item.column.isLetter {
            parts.append(letterForColumn(item, disp))
        }

        if let pending {
            let center = x(ofColumn: pending.layoutIndex, disp) + width(ofColumn: pending.layoutIndex, disp) / 2

            parts.append(glyph(pending, x: center, opacity: pending.column.p))
        }

        return SceneNode(children: parts).transform(.translate(origin + Vec2(0, y)))
    }

    private func letterForColumn(_ item: LaidOutColumn, _ disp: Displacement?) -> SceneNode<BraidState> {
        let column = item.column

        guard let disp, disp.layoutIndex == item.layoutIndex else {
            let center = x(ofColumn: item.layoutIndex, disp) + columnWidth / 2

            return glyph(item, x: center, opacity: column.isFlat ? 0 : 1)
        }

        // Fades as the crossing leaves the diagram for the loops.
        let restY = (rowY(column.i) + rowY(column.i + 1)) / 2
        let distance = max(wireStart - disp.center.x, disp.center.x - wireEnd, abs(disp.center.y - restY))
        let opacity = min(max(1 - distance / Metrics.fadeDistance, 0), 1)

        return glyph(item, x: disp.center.x, opacity: opacity)
    }

    /// σ with its index as a subscript, and −1 above that for an inverse.
    private func glyph(_ item: LaidOutColumn, x: Double, opacity: Double) -> SceneNode<BraidState> {
        let isInverse = item.column.sign == .negative
        let shift = isInverse ? Metrics.inverseGlyphShift : Metrics.glyphShift

        return SceneGroup {
            SceneText("σ", size: Metrics.glyphSize)
                .fill(Metrics.ink)
                .hitTesting(.disabled)

            SceneText(String(item.column.i + 1), size: Metrics.scriptSize)
                .fill(Metrics.ink)
                .transform(.translate(Metrics.subscriptOffset))
                .hitTesting(.disabled)

            SceneText("−1", size: Metrics.scriptSize)
                .fill(Metrics.ink)
                .opacity(isInverse ? 1 : 0)
                .transform(.translate(Metrics.superscriptOffset))
                .hitTesting(.disabled)
        }
        .id("word-letter-\(item.pairID)")
        .opacity(opacity)
        .transform(.translate(x - shift, 0))
    }

    // MARK: The panel

    private func panel(_ disp: Displacement?) -> [SceneNode<BraidState>] {
        let overhang = Metrics.panelRowOverhang * Metrics.rowSpacing
        let top = rowY(0) - overhang
        let bottom = rowY(lastRow) + overhang
        let depth = Metrics.depth

        let corners = [
            project(top, depth: depth).position,
            project(top, depth: -depth).position,
            project(bottom, depth: -depth).position,
            project(bottom, depth: depth).position,
        ]

        let outline = [PathCommand.move(corners[0])] + corners.dropFirst().map(PathCommand.line) + [.close]
        let isFull = isFull

        var parts: [SceneNode<BraidState>] = [
            ScenePath(outline)
                .fill(isFull ? Metrics.panelFullFill : Metrics.panelFill)
                .stroke(isFull ? Metrics.panelFullStroke : Ink.outline)
                .hitTesting(.disabled),

            SceneText("Braid is full", size: Metrics.labelSize)
                .fill(Metrics.panelFullText)
                .opacity(isFull ? 1 : 0)
                .transform(.translate(
                    panelX + Metrics.panelWidth / 2,
                    max(corners[2].y, corners[3].y) + Metrics.fadeDistance
                ))
                .hitTesting(.disabled),
        ]

        for row in 0..<n {
            parts.append(
                SceneLine(from: project(rowY(row), depth: depth).position, to: project(rowY(row), depth: -depth).position)
                    .key("grid-\(row)")
                    .stroke(Metrics.gridLine)
                    .opacity(strandOpacity(row + 1))
                    .hitTesting(.disabled)
            )
        }

        parts.append(
            SceneLine(from: project(top, depth: 0).position, to: project(bottom, depth: 0).position)
                .stroke(Ink.outline)
                .hitTesting(.disabled)
        )

        let ends = endConfiguration(disp)

        for strand in 1...max(n, 1) {
            parts.append(pointNode(strand, ends[strand] ?? (0, 0)))
        }

        return parts
    }

    /// Drag a point around a neighbor, in front or behind, to add that
    /// crossing.
    private func pointNode(_ strand: Int, _ end: (row: Double, depth: Double)) -> SceneNode<BraidState> {
        let id = "pt-\(strand)"
        let isDragged = context.draggedID == id
        let projected = project(rowY(end.row), depth: end.depth)
        let color = strandColor(strand)
        let renderer = self

        return SceneGroup {
            SceneCircle(radius: Metrics.pointHaloRadius * projected.scale)
                .fill(color.fill)
                .opacity(isDragged ? Metrics.pointHaloOpacity : 0)

            SceneCircle(radius: Metrics.pointRadius * projected.scale)
                .fill(color.stroke)
                .stroke(.white, lineWidth: Metrics.pointStroke)
        }
        .id(id)
        .transform(.translate(projected.position))
        .opacity(strandOpacity(strand))
        .zIndex(.relative(isDragged ? Metrics.draggedPointZ : Metrics.pointZ))
        .onDrag { renderer.pointSpec(strand) }
    }
}
