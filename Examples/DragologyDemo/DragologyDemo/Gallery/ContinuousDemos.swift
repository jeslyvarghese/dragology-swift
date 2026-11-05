import DragologySwift
import Foundation

// MARK: - Bézier curve

struct BezierState: Equatable {
    var p0 = Vec2(40, 50)
    var p1 = Vec2(170, 50)
    var p2 = Vec2(90, 220)
    var p3 = Vec2(320, 220)

    /// The point on the curve at `t`, from 0 to 1.
    func point(at t: Double) -> Vec2 {
        let u = 1 - t
        let first = p0 * (u * u * u)
        let second = p1 * (3 * u * u * t)
        let third = p2 * (3 * u * t * t)
        let fourth = p3 * (t * t * t)

        return first + second + third + fourth
    }
}

private enum Bezier {
    static let endpointRadius = 14.0
    static let controlRadius = 11.0
    static let curveWidth = 6.0
    static let handleRadius = 14.0
    static let draggedHandleRadius = 9.0
    static let handleCount = 9
    static let handleOpacity = 0.3
    static let labelOffset = 22.0
    static let labelSize = 12.0
    static let lineWidth = 2.0
}

func bezier(_ context: SceneContext<BezierState>) -> SceneNode<BezierState> {
    let state = context.state
    let d = context.drag

    return SceneGroup {
        SceneLine(from: state.p0, to: state.p1).stroke(Ink.outline).hitTesting(.disabled)
        SceneLine(from: state.p3, to: state.p2).stroke(Ink.outline).hitTesting(.disabled)

        ScenePath([.move(state.p0), .cubic(control1: state.p1, control2: state.p2, end: state.p3)])
            .stroke(Ink.blue, lineWidth: Bezier.curveWidth)
            .hitTesting(.disabled)

        // Invisible handles along the curve bend it by moving both control
        // points together, pinned to the same offset from each other.
        for index in 1...Bezier.handleCount {
            let t = Double(index) / Double(Bezier.handleCount + 1)
            let id = "curve-\(index)"
            let isDragged = context.draggedID == id

            SceneCircle(radius: isDragged ? Bezier.draggedHandleRadius : Bezier.handleRadius)
                .id(id)
                .fill(isDragged ? Ink.blue.withOpacity(Bezier.handleOpacity) : .clear)
                .transform(.translate(state.point(at: t)))
                .onDrag {
                    d.vary(state, \.p1.x, \.p1.y, \.p2.x, \.p2.y, pin: { candidate in
                        [candidate.p2.x - candidate.p1.x, candidate.p2.y - candidate.p1.y]
                    })
                }
        }

        bezierPoint("p1", "P1", state.p1, radius: Bezier.controlRadius, color: Ink.amber) {
            d.vary(state, \.p1.x, \.p1.y)
        }

        bezierPoint("p2", "P2", state.p2, radius: Bezier.controlRadius, color: Ink.amber) {
            d.vary(state, \.p2.x, \.p2.y)
        }

        bezierPoint("p0", "P0", state.p0, radius: Bezier.endpointRadius, color: Ink.red) {
            d.vary(state, \.p0.x, \.p0.y)
        }

        bezierPoint("p3", "P3", state.p3, radius: Bezier.endpointRadius, color: Ink.red) {
            d.vary(state, \.p3.x, \.p3.y)
        }
    }
}

private func bezierPoint(
    _ id: String,
    _ title: String,
    _ position: Vec2,
    radius: Double,
    color: SceneColor,
    onDrag: @escaping () -> DragSpec<BezierState>
) -> SceneNode<BezierState> {
    SceneGroup {
        SceneCircle(radius: radius)
            .fill(color)
            .stroke(Ink.text, lineWidth: Bezier.lineWidth)

        SceneText(title, size: Bezier.labelSize)
            .fill(Ink.muted)
            .transform(.translate(0, -Bezier.labelOffset))
            .hitTesting(.disabled)
    }
    .id(id)
    .transform(.translate(position))
    .zIndex(.relative(1))
    .onDrag(onDrag)
}

extension SceneColor {
    func withOpacity(_ opacity: Double) -> SceneColor {
        var copy = self
        copy.alpha = opacity
        return copy
    }
}

// MARK: - Clock

struct ClockState: Equatable {
    var hours = 4.333333

    var summary: String {
        let wrapped = hours.truncatingRemainder(dividingBy: Clock.hoursPerDial)
        let positive = wrapped < 0 ? wrapped + Clock.hoursPerDial : wrapped
        let minutes = Int(positive.truncatingRemainder(dividingBy: 1) * Clock.minutesPerHour)

        return String(format: "%d:%02d", Int(positive), minutes)
    }
}

private enum Clock {
    static let center = Vec2(150, 150)
    static let hoursPerDial = 12.0
    static let minutesPerHour = 60.0
    static let fullTurn = 360.0
    static let topOfDial = -90.0
    static let handleRadius = 14.0
    static let faceRadius = 130.0
    static let hourLength = 70.0
    static let hourWidth = 6.0
    static let minuteLength = 110.0
    static let minuteWidth = 4.0
}

func clock(_ context: SceneContext<ClockState>) -> SceneNode<ClockState> {
    let state = context.state

    func hand(_ id: String, degrees: Double, length: Double, width: Double) -> SceneNode<ClockState> {
        SceneGroup {
            SceneLine(from: .zero, to: Vec2(length, 0))
                .stroke(.black, lineWidth: width)
                .hitTesting(.disabled)

            SceneCircle(radius: Clock.handleRadius)
                .fill(.black)
                .transform(.translate(length, 0))
                .onDrag { context.drag.vary(state, \.hours) }
        }
        .id(id)
        .transform(.translate(Clock.center) + .rotate(degrees: degrees + Clock.topOfDial))
    }

    return SceneGroup {
        SceneCircle(radius: Clock.faceRadius)
            .stroke(Ink.outline, lineWidth: Clock.minuteWidth)
            .transform(.translate(Clock.center))

        // Both hands drive the same number, at different rates.
        hand(
            "hour",
            degrees: state.hours * Clock.fullTurn / Clock.hoursPerDial,
            length: Clock.hourLength,
            width: Clock.hourWidth
        )

        hand(
            "minute",
            degrees: state.hours * Clock.fullTurn,
            length: Clock.minuteLength,
            width: Clock.minuteWidth
        )
    }
}

// MARK: - Linked sliders

struct LinkedSlidersState: Equatable {
    var values = (1...LinkedSliders.count).map {
        Double($0) / Double(LinkedSliders.count + 1) * LinkedSliders.width
    }
}

enum LinkedSliders {
    static let count = 5
    static let width = 260.0
    static let trackHeight = 6.0
    static let thumbRadius = 14.0
    static let spacing = 44.0
    static let originX = 24.0
    static let originY = 30.0
}

func linkedSliders(_ context: SceneContext<LinkedSlidersState>) -> SceneNode<LinkedSlidersState> {
    let state = context.state
    let height = LinkedSliders.trackHeight

    return SceneGroup {
        for (index, value) in state.values.enumerated() {
            SceneGroup {
                SceneRect(width: LinkedSliders.width, height: height, cornerRadius: height / 2)
                    .fill(Ink.faint)
                    .transform(.translate(0, -height / 2))

                SceneRect(width: value, height: height, cornerRadius: height / 2)
                    .fill(Ink.blue)
                    .transform(.translate(0, -height / 2))

                SceneCircle(radius: LinkedSliders.thumbRadius)
                    .fill(.white)
                    .stroke(Ink.outline)
                    .transform(.translate(value, 0))
                    .onDrag {
                        // One number moves this slider and all those below it.
                        context.drag.varyFunction(
                            initial: [0],
                            state: { parameters in
                                var copy = state

                                for lower in index..<copy.values.count {
                                    copy.values[lower] += parameters[0]
                                }

                                return copy
                            },
                            constraint: { candidate in
                                candidate.values.flatMap {
                                    DragConstraint.inOrder(0, $0, LinkedSliders.width)
                                }
                            }
                        )
                    }
            }
            .transform(.translate(
                LinkedSliders.originX,
                LinkedSliders.originY + Double(index) * LinkedSliders.spacing
            ))
        }
    }
}

// MARK: - Mirror

struct MirrorState: Equatable {
    var angle = -45.0
}

private enum Mirror {
    static let center = Vec2(150, 150)
    static let radius = 110.0
    static let handleRadius = 16.0
    static let axisOverhang = 20.0
    static let lineWidth = 2.0
}

func mirror(_ context: SceneContext<MirrorState>) -> SceneNode<MirrorState> {
    let state = context.state
    let reach = Mirror.radius + Mirror.axisOverhang

    return SceneGroup {
        SceneCircle(radius: Mirror.radius).stroke(Ink.outline, lineWidth: Mirror.lineWidth)

        SceneLine(from: Vec2(-reach, 0), to: Vec2(reach, 0))
            .stroke(Ink.faint)
            .hitTesting(.disabled)

        SceneGroup {
            SceneCircle(radius: Mirror.handleRadius)
                .id("point")
                .fill(.black)
                .transform(.translate(Mirror.radius, 0))
                .onDrag {
                    context.drag
                        .vary(state, \.angle)
                        .changeFrame { frame in
                            // Flip the finger upside down, across the center.
                            DragFrame(pointer: Vec2(
                                frame.pointer.x,
                                2 * Mirror.center.y - frame.pointer.y
                            ))
                        }
                }
        }
        .transform(.rotate(degrees: state.angle))
    }
    .transform(.translate(Mirror.center))
}

// MARK: - Scheduler

struct Meeting: Equatable {
    var start: Double
    var end: Double
    var room: Int

    func overlaps(_ other: Meeting) -> Bool {
        start < other.end && other.start < end
    }
}

struct SchedulerState: Equatable {
    var meetings = [
        Meeting(start: 20, end: 100, room: 0),
        Meeting(start: 60, end: 160, room: 1),
        Meeting(start: 10, end: 70, room: 2),
        Meeting(start: 120, end: 200, room: 0),
        Meeting(start: 80, end: 140, room: 2),
    ]

    var summary: String {
        meetings.map { "\(Int($0.start.rounded()))-\(Int($0.end.rounded()))@\($0.room)" }
            .joined(separator: " ")
    }
}

enum Scheduler {
    static let rooms = 4
    static let trackHeight = 40.0
    static let gap = 8.0
    static let dotRadius = 7.0
    static let barHeight = 6.0
    static let endTime = 250.0
    static let minLength = 4 * dotRadius
    static let graphX = endTime + 40
    static let nodeRadius = 10.0
    static let margin = 10.0
    static let snapRadius = 10.0
    static let conflictWidth = 6.0
    static let conflictOpacity = 0.6
    static let draggedZ = 10
    static let labelSize = 12.0
    static let labelInset = 20.0
    static let labelOffset = 9.0
    static let width = graphX + endTime + 2 * margin
    static let height = Double(rooms) * (trackHeight + gap) + 2 * margin

    static func trackY(_ room: Int) -> Double {
        Double(room) * (trackHeight + gap) + trackHeight / 2
    }

    static func nodePosition(_ meeting: Meeting) -> Vec2 {
        Vec2(graphX + (meeting.start + meeting.end) / 2, trackY(meeting.room))
    }
}

func scheduler(_ context: SceneContext<SchedulerState>) -> SceneNode<SchedulerState> {
    let state = context.state

    return SceneGroup {
        for room in 0..<Scheduler.rooms {
            let y = Scheduler.trackY(room)

            SceneLine(from: Vec2(0, y), to: Vec2(Scheduler.endTime, y))
                .stroke(Ink.outline)
                .hitTesting(.disabled)

            SceneText("room \(room)", size: Scheduler.labelSize)
                .fill(Ink.muted)
                .transform(.translate(Scheduler.endTime - Scheduler.labelInset, y + Scheduler.labelOffset))
                .hitTesting(.disabled)
        }

        for first in state.meetings.indices {
            for second in state.meetings.indices where first < second {
                if state.meetings[first].overlaps(state.meetings[second]) {
                    conflictEdge(first, second, state: state)
                }
            }
        }

        for index in state.meetings.indices {
            meetingNode(index, context: context)
        }
    }
    .transform(.translate(Scheduler.margin, Scheduler.margin))
}

private func conflictEdge(_ first: Int, _ second: Int, state: SchedulerState) -> SceneNode<SchedulerState> {
    let a = state.meetings[first]
    let b = state.meetings[second]
    let start = Scheduler.nodePosition(a)
    let end = Scheduler.nodePosition(b)
    let isConflict = a.room == b.room

    return SceneGroup {
        SceneLine(from: start, to: end)
            .stroke(Ink.red.withOpacity(isConflict ? Scheduler.conflictOpacity : 0), lineWidth: Scheduler.conflictWidth)
            .hitTesting(.disabled)

        SceneLine(from: start, to: end)
            .stroke(Ink.muted)
            .hitTesting(.disabled)
    }
    .id("edge-\(first)-\(second)")
    .zIndex(.relative(-1))
}

private func meetingNode(_ index: Int, context: SceneContext<SchedulerState>) -> SceneNode<SchedulerState> {
    let state = context.state
    let d = context.drag
    let meeting = state.meetings[index]
    let y = Scheduler.trackY(meeting.room)
    let color = Ink.series[index % Ink.series.count]
    let barID = "bar-\(index)"
    let node = Scheduler.nodePosition(meeting)

    let changeRoom = { () -> DragSpec<SchedulerState> in
        let states = (0..<Scheduler.rooms).map { room -> SchedulerState in
            var copy = state
            copy.meetings[index].room = room
            return copy
        }

        return d.between(states).withSnapRadius(Scheduler.snapRadius, transition: .standard)
    }

    let constraint = { (candidate: SchedulerState) -> [Double] in
        let current = candidate.meetings[index]

        return DragConstraint.lessThan(0, current.start)
            + DragConstraint.lessThan(current.start, current.end - Scheduler.minLength)
            + DragConstraint.lessThan(current.end, Scheduler.endTime)
    }

    return SceneGroup {
        SceneRect(width: meeting.end - meeting.start, height: Scheduler.barHeight, cornerRadius: Scheduler.barHeight / 2)
            .id(barID)
            .fill(color)
            .transform(.translate(meeting.start, y - Scheduler.barHeight / 2))
            .onDrag(changeRoom)

        SceneCircle(radius: Scheduler.dotRadius)
            .id("left-\(index)")
            .fill(color)
            .transform(.translate(meeting.start + Scheduler.dotRadius, y))
            .onDrag { d.vary(state, \.meetings[index].start, constraint: constraint) }

        SceneCircle(radius: Scheduler.dotRadius)
            .id("right-\(index)")
            .fill(color)
            .transform(.translate(meeting.end - Scheduler.dotRadius, y))
            .onDrag { d.vary(state, \.meetings[index].end, constraint: constraint) }

        SceneCircle(radius: Scheduler.nodeRadius)
            .fill(color)
            .stroke(.white, lineWidth: 2)
            .transform(.translate(node))
            .onDrag(changeRoom)
    }
    .id("meeting-\(index)")
    .zIndex(.relative(context.draggedID == barID ? Scheduler.draggedZ : index))
}

// MARK: - Chain of links

struct ChainState: Equatable {
    var dots = (0..<ChainLinks.count).map {
        Vec2(ChainLinks.startX + Double($0) * ChainLinks.length, ChainLinks.startY)
    }
}

private enum ChainLinks {
    static let count = 10
    static let length = 36.0
    static let dotRadius = 10.0
    static let startX = 20.0
    static let startY = 150.0
    static let lineWidth = 2.5
    static let minDistance = 0.001
}

/// Walks outward from the dragged dot, pulling each neighbor to exactly
/// one link's length along its current direction.
private func enforcingLinks(_ state: ChainState, from dragged: Int) -> ChainState {
    var dots = state.dots

    func pull(_ index: Int, toward anchor: Int, fallback: Double) {
        let offset = dots[index] - dots[anchor]
        let distance = offset.length

        guard distance >= ChainLinks.minDistance else {
            dots[index] = dots[anchor] + Vec2(fallback * ChainLinks.length, 0)
            return
        }

        dots[index] = dots[anchor] + offset * (ChainLinks.length / distance)
    }

    for index in stride(from: dragged - 1, through: 0, by: -1) {
        pull(index, toward: index + 1, fallback: -1)
    }

    for index in stride(from: dragged + 1, to: dots.count, by: 1) {
        pull(index, toward: index - 1, fallback: 1)
    }

    return ChainState(dots: dots)
}

func chainOfLinks(_ context: SceneContext<ChainState>) -> SceneNode<ChainState> {
    let state = context.state

    return SceneGroup {
        for (index, pair) in zip(state.dots, state.dots.dropFirst()).enumerated() {
            SceneLine(from: pair.0, to: pair.1)
                .id("link-\(index)")
                .stroke(Ink.muted, lineWidth: ChainLinks.lineWidth)
                .hitTesting(.disabled)
        }

        for (index, dot) in state.dots.enumerated() {
            let id = "dot-\(index)"

            SceneCircle(radius: ChainLinks.dotRadius)
                .id(id)
                .fill(Ink.text)
                .transform(.translate(dot))
                .zIndex(context.draggedID == id ? .absolute(1) : .relative(0))
                .onDrag {
                    // Chaining feeds each frame's result into the next, so
                    // the chain trails behind instead of starting afresh.
                    context.drag
                        .vary(state, \.dots[index].x, \.dots[index].y)
                        .during { enforcingLinks($0, from: index) }
                        .withChaining(transition: nil)
                }
        }
    }
}

// MARK: - Card piles

struct CardInPile: Equatable {
    var dx: Double
    var dy: Double
}

struct Pile: Equatable {
    var x: Double
    var y: Double
    var cards: [String: CardInPile]
}

struct PilesState: Equatable {
    var piles: [String: Pile]

    init(cards: [String: Vec2]) {
        let singles = cards.map { id, position in
            (id, Pile(x: position.x, y: position.y, cards: [id: CardInPile(dx: 0, dy: 0)]))
        }

        piles = Dictionary(uniqueKeysWithValues: singles)
        self = recomputedPiles(self)
    }

    static let initial = PilesState(cards: [
        "a": Vec2(60, 40),
        "b": Vec2(105, 70),
        "c": Vec2(260, 30),
        "d": Vec2(300, 60),
        "e": Vec2(160, 220),
        "f": Vec2(340, 220),
    ])

    var summary: String {
        piles.keys.sorted().joined(separator: " ")
    }
}

enum Piles {
    static let cardWidth = 70.0
    static let cardHeight = 100.0
    static let cornerRadius = 6.0
    static let pilePadding = 12.0
    static let pileCornerRadius = 12.0
    static let pileOpacity = 0.4
    static let draggedPileOpacity = 0.7
    static let separator = "-"
    static let lineWidth = 1.5
    static let draggedCardZ = 2
    static let cardZ = 1
}

/// Rebuilds the piles from scratch: cards that overlap, even through
/// other cards, belong together.
func recomputedPiles(_ state: PilesState) -> PilesState {
    var positions: [String: Vec2] = [:]

    for pile in state.piles.values {
        for (id, card) in pile.cards {
            positions[id] = Vec2(pile.x + card.dx, pile.y + card.dy)
        }
    }

    // Merge groups with union-find.
    var parent = Dictionary(uniqueKeysWithValues: positions.keys.map { ($0, $0) })

    func root(_ id: String) -> String {
        var current = id

        while let next = parent[current], next != current {
            current = next
        }

        return current
    }

    let ids = positions.keys.sorted()

    for (index, first) in ids.enumerated() {
        for second in ids[(index + 1)...] {
            guard let a = positions[first], let b = positions[second] else { continue }

            let isOverlapping = abs(a.x - b.x) < Piles.cardWidth && abs(a.y - b.y) < Piles.cardHeight

            if isOverlapping {
                parent[root(first)] = root(second)
            }
        }
    }

    // Center each pile on its cards.
    var result = state
    result.piles = [:]

    for members in Dictionary(grouping: ids, by: root).values {
        let points = members.compactMap { positions[$0] }
        let center = points.reduce(.zero, +) * (1 / Double(points.count))

        var cards: [String: CardInPile] = [:]

        for (id, point) in zip(members, points) {
            cards[id] = CardInPile(dx: point.x - center.x, dy: point.y - center.y)
        }

        result.piles[members.joined(separator: Piles.separator)] = Pile(x: center.x, y: center.y, cards: cards)
    }

    return result
}

func cardPiles(_ context: SceneContext<PilesState>) -> SceneNode<PilesState> {
    let state = context.state
    let piles = state.piles.sorted { $0.key < $1.key }

    return SceneGroup {
        for (pileID, pile) in piles where pile.cards.count > 1 {
            pileBackground(pileID, pile, context: context)
        }

        for (pileID, pile) in piles {
            for (cardID, card) in pile.cards.sorted(by: { $0.key < $1.key }) {
                let id = "card-\(cardID)"

                SceneRect(width: Piles.cardWidth, height: Piles.cardHeight, cornerRadius: Piles.cornerRadius)
                    .id(id)
                    .fill(.white)
                    .stroke(Ink.muted, lineWidth: Piles.lineWidth)
                    .transform(.translate(pile.x + card.dx, pile.y + card.dy))
                    .zIndex(.relative(context.draggedID == id ? Piles.draggedCardZ : Piles.cardZ))
                    .onDrag {
                        context.drag
                            .vary(state, \.piles[pileID]!.cards[cardID]!.dx, \.piles[pileID]!.cards[cardID]!.dy)
                            .during(recomputedPiles)
                    }
            }
        }
    }
}

private func pileBackground(
    _ pileID: String,
    _ pile: Pile,
    context: SceneContext<PilesState>
) -> SceneNode<PilesState> {
    let state = context.state
    let id = "pile-\(pileID)"
    let padding = Piles.pilePadding
    let positions = pile.cards.values.map { Vec2(pile.x + $0.dx, pile.y + $0.dy) }
    let minX = (positions.map(\.x).min() ?? 0) - padding
    let minY = (positions.map(\.y).min() ?? 0) - padding
    let maxX = (positions.map(\.x).max() ?? 0) + Piles.cardWidth + padding
    let maxY = (positions.map(\.y).max() ?? 0) + Piles.cardHeight + padding

    return SceneRect(width: maxX - minX, height: maxY - minY, cornerRadius: Piles.pileCornerRadius)
        .id(id)
        .fill(Ink.outline)
        .opacity(context.draggedID == id ? Piles.draggedPileOpacity : Piles.pileOpacity)
        .transform(.translate(minX, minY))
        .onDrag {
            context.drag
                .vary(state, \.piles[pileID]!.x, \.piles[pileID]!.y)
                .during(recomputedPiles)
        }
}
