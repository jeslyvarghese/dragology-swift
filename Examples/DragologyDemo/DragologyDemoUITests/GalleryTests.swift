import XCTest

/// Drags in each gallery demo with real touches, and checks the state
/// that results. Points are in each demo's own design coordinates, and
/// are scaled to match, so this covers canvases shrunk to fit too.
final class GalleryTests: XCTestCase {
    private enum Timing {
        static let press: TimeInterval = 0.05
        static let settle: TimeInterval = 3
    }

    private enum Identifier {
        static let canvas = "demoCanvas"
        static let value = "demoValue"
    }

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func open(_ title: String, mode: Int = 0) {
        app = XCUIApplication()
        app.launchArguments = ["-demo", title, "-mode", String(mode)]
        app.launch()
    }

    private var value: String {
        app.staticTexts[Identifier.value].label
    }

    /// Where a design point is on screen.
    private func coordinate(_ point: CGPoint, designWidth: CGFloat) -> XCUICoordinate {
        let canvas = app.otherElements[Identifier.canvas]
        XCTAssertTrue(canvas.waitForExistence(timeout: Timing.settle))

        let scale = canvas.frame.width / designWidth

        return canvas
            .coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x * scale, dy: point.y * scale))
    }

    private func drag(_ start: CGPoint, to end: CGPoint, designWidth: CGFloat) {
        let from = coordinate(start, designWidth: designWidth)
        let to = coordinate(end, designWidth: designWidth)

        from.press(forDuration: Timing.press, thenDragTo: to)
    }

    private func expectValue(_ matches: @escaping (String) -> Bool) {
        let predicate = NSPredicate { _, _ in matches(self.value) }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)

        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: Timing.settle), .completed,
                       "Unexpected value: \(value)")
    }

    private func expectValue(_ expected: String) {
        expectValue { $0 == expected }
    }

    private func number(in string: String) -> Int? {
        Int(string.prefix { $0.isNumber })
    }

    // MARK: Basics

    func testThreeStates() {
        open("Three States")
        drag(CGPoint(x: 40, y: 40), to: CGPoint(x: 230, y: 40), designWidth: 280)
        expectValue("state 1")
    }

    func testCustomBehavior() {
        open("Custom Behavior")
        drag(CGPoint(x: 40, y: 40), to: CGPoint(x: 135, y: 200), designWidth: 280)
        expectValue("state 2")
    }

    // MARK: Real views

    private func tapCounter(_ name: String, times: Int) {
        let button = app.buttons["add-\(name)"]
        XCTAssertTrue(button.waitForExistence(timeout: Timing.settle))

        for _ in 0..<times { button.tap() }
    }

    func testRealViewsKeepTheirStateThroughADrag() {
        open("Real SwiftUI Views")
        tapCounter("Apples", times: 2)

        let count = app.staticTexts["count-Apples"]
        XCTAssertEqual(count.label, "2")

        // Long-press the card's title area, and carry it down two slots.
        let card = app.staticTexts["title-Apples"]
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 160))

        start.press(forDuration: 0.6, thenDragTo: end)

        let order = app.staticTexts["realViewsOrder"]
        let moved = NSPredicate { _, _ in order.label == "Bananas,Cherries,Apples,Dates" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: Timing.settle), .completed, order.label)

        XCTAssertEqual(app.staticTexts["count-Apples"].label, "2")
        tapCounter("Apples", times: 1)
        XCTAssertEqual(app.staticTexts["count-Apples"].label, "3")
    }

    func testSwipingOverCardsScrollsThePage() {
        open("Real SwiftUI Views")

        let card = app.staticTexts["title-Bananas"]
        XCTAssertTrue(card.waitForExistence(timeout: Timing.settle))

        let before = card.frame.minY
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)))

        XCTAssertLessThan(card.frame.minY, before - 50, "The page should have scrolled.")
        XCTAssertEqual(app.staticTexts["realViewsOrder"].label, "Apples,Bananas,Cherries,Dates")
    }

    // MARK: Drag list

    private func expectOrder(_ expected: String) {
        let order = app.staticTexts["dragListOrder"]
        let matches = NSPredicate { _, _ in order.label == expected }
        let expectation = XCTNSPredicateExpectation(predicate: matches, object: nil)

        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: Timing.settle), .completed, order.label)
    }

    func testDragListRowsSizeThemselves() {
        open("Drag List")

        let short = app.staticTexts["task-Call"]
        let tall = app.staticTexts["task-Plan"]
        let next = app.staticTexts["task-Pack"]
        XCTAssertTrue(tall.waitForExistence(timeout: Timing.settle))

        // The long row wraps, and the next row clears it.
        XCTAssertGreaterThan(tall.frame.height, short.frame.height * 1.5)
        XCTAssertGreaterThan(next.frame.minY, tall.frame.maxY)
    }

    func testDragListReorders() {
        open("Drag List")
        expectOrder("Call,Plan,Pack,Read")

        let row = app.staticTexts["task-Call"]
        XCTAssertTrue(row.waitForExistence(timeout: Timing.settle))

        let target = app.staticTexts["task-Pack"].frame.midY
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        start.press(forDuration: 0.6, thenDragTo: start.withOffset(CGVector(dx: 0, dy: target - row.frame.midY)))

        expectOrder("Plan,Pack,Call,Read")
    }

    func testDragListKeepsRowState() {
        open("Drag List")

        let toggle = app.switches["done-Read"].switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: Timing.settle))
        toggle.tap()

        let row = app.staticTexts["task-Read"]
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        start.press(forDuration: 0.6, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)))

        let value = app.switches["done-Read"].value as? String
        XCTAssertEqual(value, "1")
    }

    func testDragListScrolls() {
        open("Drag List")

        let row = app.staticTexts["task-Plan"]
        XCTAssertTrue(row.waitForExistence(timeout: Timing.settle))

        let before = row.frame.minY
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)))

        XCTAssertLessThan(row.frame.minY, before - 50, "The page should have scrolled.")
        expectOrder("Call,Plan,Pack,Read")
    }

    // MARK: Drag board

    private func expectBoard(_ expected: String) {
        let order = app.staticTexts["boardOrder"]
        let matches = NSPredicate { _, _ in order.label == expected }
        let expectation = XCTNSPredicateExpectation(predicate: matches, object: nil)

        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: Timing.settle), .completed, order.label)
    }

    private func dragCard(_ name: String, onto target: XCUIElement, dy: CGFloat = 0) {
        let card = app.staticTexts["card-\(name)"]
        XCTAssertTrue(card.waitForExistence(timeout: Timing.settle))

        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let offset = CGVector(dx: target.frame.midX - card.frame.midX, dy: target.frame.midY - card.frame.midY + dy)

        start.press(forDuration: 0.6, thenDragTo: start.withOffset(offset))
    }

    func testBoardMovesACardToAnEmptyColumn() {
        open("Drag Board")
        expectBoard("Todo:Design+Build the whole thing+Test Doing:Write Done:")

        dragCard("Design", onto: app.staticTexts["column-Done"], dy: 50)

        expectBoard("Todo:Build the whole thing+Test Doing:Write Done:Design")
    }

    func testBoardReordersWithinAColumn() {
        open("Drag Board")

        dragCard("Design", onto: app.staticTexts["card-Test"])

        expectBoard("Todo:Build the whole thing+Test+Design Doing:Write Done:")
    }

    func testBoardCardsSizeThemselves() {
        open("Drag Board")

        let long = app.staticTexts["card-Build the whole thing"]
        let next = app.staticTexts["card-Test"]
        XCTAssertTrue(long.waitForExistence(timeout: Timing.settle))

        // The long card wraps in its narrow column, and the next one clears it.
        XCTAssertGreaterThan(next.frame.minY, long.frame.maxY)
    }

    // MARK: Discrete states

    func testRingOfBeads() {
        open("Ring of Beads")
        drag(CGPoint(x: 170, y: 60), to: CGPoint(x: 235, y: 259), designWidth: 340)
        expectValue("BCADE")
    }

    func testKanbanMovesACardAcrossColumns() {
        open("Kanban")
        drag(CGPoint(x: 56, y: 51), to: CGPoint(x: 296, y: 100), designWidth: 360)
        expectValue { $0.contains("done:Task D+Task A") }
    }

    func testHanoiAllowsLegalMoves() {
        open("Towers of Hanoi")
        drag(CGPoint(x: 60, y: 46), to: CGPoint(x: 178, y: 90), designWidth: 360)
        expectValue("23|1|")
    }

    func testHanoiRefusesToMoveACoveredDisk() {
        open("Towers of Hanoi")
        drag(CGPoint(x: 30, y: 94), to: CGPoint(x: 178, y: 90), designWidth: 360)
        expectValue("123||")
    }

    func testSlidingTiles() {
        open("Sliding Tiles")
        drag(CGPoint(x: 122, y: 282), to: CGPoint(x: 42, y: 282), designWidth: 324)
        expectValue { $0.hasSuffix("13 _ 14 3") }
    }

    func testSlidingTilesChainAcrossSquares() {
        // The blank travels two squares in one drag, which takes a chain.
        open("Sliding Tiles")
        drag(CGPoint(x: 42, y: 282), to: CGPoint(x: 202, y: 282), designWidth: 324)
        expectValue { $0.hasSuffix("13 14 _ 3") }
    }

    func testTromino() {
        open("Tromino Tiling")
        drag(CGPoint(x: 24, y: 24), to: CGPoint(x: 156, y: 112), designWidth: 356)
        expectValue("3,2")
    }

    // MARK: Continuous values

    func testBezierPoint() {
        open("Bézier Curve")
        drag(CGPoint(x: 170, y: 50), to: CGPoint(x: 210, y: 110), designWidth: 360)
        expectValue { abs((self.number(in: String($0.dropFirst(3))) ?? 0) - 210) <= 3 }
    }

    func testClockMinuteHand() {
        open("Clock")
        drag(CGPoint(x: 245, y: 205), to: CGPoint(x: 150, y: 260), designWidth: 300)
        expectValue { $0.hasPrefix("4:29") || $0.hasPrefix("4:30") || $0.hasPrefix("4:31") }
    }

    func testLinkedSliders() {
        open("Linked Sliders")
        drag(CGPoint(x: 67, y: 30), to: CGPoint(x: 97, y: 30), designWidth: 310)

        // The first slider moved 30, and carried all the others along.
        expectValue { value in
            let numbers = value.split(separator: " ").compactMap { Int($0) }
            return numbers.count == 5 && abs(numbers[0] - 73) <= 3 && abs(numbers[1] - 117) <= 3
        }
    }

    func testLinkedSlidersStopWhenTheLastOneHitsItsLimit() {
        open("Linked Sliders")
        drag(CGPoint(x: 67, y: 30), to: CGPoint(x: 280, y: 30), designWidth: 310)

        // The bottom slider has the least room, so it limits all of them.
        expectValue("87 130 173 217 260")
    }

    func testMirror() {
        open("Mirror")
        drag(CGPoint(x: 228, y: 72), to: CGPoint(x: 150, y: 30), designWidth: 300)
        expectValue { abs((self.number(in: $0) ?? 0) - 90) <= 3 }
    }

    func testSchedulerChangesRoom() {
        open("Scheduler")
        drag(CGPoint(x: 70, y: 30), to: CGPoint(x: 70, y: 174), designWidth: 560)
        expectValue { $0.hasPrefix("20-100@3") }
    }

    func testSchedulerResizesAMeeting() {
        open("Scheduler")
        drag(CGPoint(x: 37, y: 30), to: CGPoint(x: 57, y: 30), designWidth: 560)
        expectValue { value in
            let start = self.number(in: value) ?? 0
            return abs(start - 40) <= 4 && value.contains("-100@0")
        }
    }

    func testChainOfLinksPullsTheFarEnd() {
        open("Chain of Links")
        drag(CGPoint(x: 344, y: 150), to: CGPoint(x: 355, y: 20), designWidth: 360)
        expectValue { (self.number(in: String($0.dropFirst("first dot at ".count))) ?? 0) > 20 }
    }

    func testCardPilesMerge() {
        open("Card Piles")
        drag(CGPoint(x: 375, y: 270), to: CGPoint(x: 215, y: 280), designWidth: 430)
        expectValue("a-b c-d e-f")
    }

    // MARK: Showcases

    /// The numbers in a readout, in order.
    private func numbers(in string: String) -> [Int] {
        string.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    func testFaceEyesSpreadApart() {
        open("Face Creator")
        drag(CGPoint(x: 240, y: 155), to: CGPoint(x: 270, y: 155), designWidth: 400)
        expectValue { abs((self.numbers(in: $0).first ?? 0) - 70) <= 3 }
    }

    func testFaceGrowsWhenAnEyeLeavesIt() {
        open("Face Creator")
        drag(CGPoint(x: 240, y: 155), to: CGPoint(x: 345, y: 155), designWidth: 400)
        expectValue { (self.numbers(in: $0).dropFirst(2).first ?? 0) > 130 }
    }

    func testFaceOutlineReshapes() {
        open("Face Creator")
        drag(CGPoint(x: 320, y: 180), to: CGPoint(x: 280, y: 180), designWidth: 400)
        expectValue { abs((self.numbers(in: $0).dropFirst(2).first ?? 0) - 80) <= 4 }
    }

    func testFaceMouthWidens() {
        open("Face Creator")
        drag(CGPoint(x: 250, y: 220), to: CGPoint(x: 280, y: 220), designWidth: 400)
        expectValue { abs((self.numbers(in: $0).dropFirst().first ?? 0) - 80) <= 4 }
    }

    func testBraidCrossingsCommute() {
        open("Braid Group")
        drag(CGPoint(x: 60, y: 66), to: CGPoint(x: 85, y: 66), designWidth: 390)
        expectValue("n=4 -3 1 2 1 2")
    }

    func testBraidMoveFromTheMiddleCrossing() {
        open("Braid Group")
        drag(CGPoint(x: 135, y: 66), to: CGPoint(x: 135, y: 94), designWidth: 390)
        expectValue("n=4 1 -3 1 2 1")
    }

    func testBraidTurningAPointWritesACrossing() {
        open("Braid Group")
        drag(CGPoint(x: 180, y: 214), to: CGPoint(x: 180, y: 242), designWidth: 390)
        expectValue { $0.split(separator: " ").count == 7 }
    }

    func testBraidDestabilizes() {
        // The unknot on four strands: pulling the innermost loop back in
        // removes a strand and its crossing, and the link stays the same.
        open("Braid Group", mode: 13)
        drag(CGPoint(x: 191, y: 154), to: CGPoint(x: 191, y: 126), designWidth: 390)
        expectValue("n=3 1 -2")
    }

    func testPermutationAdjacentTileWritesALetter() {
        open("Permutation Lab")
        drag(CGPoint(x: 44, y: 100), to: CGPoint(x: 76, y: 100), designWidth: 390)
        expectValue { $0.hasPrefix("π=1342") }
    }

    func testPermutationFreeReorder() {
        open("Permutation Lab", mode: 1)
        drag(CGPoint(x: 44, y: 100), to: CGPoint(x: 108, y: 100), designWidth: 390)
        expectValue { $0.hasPrefix("π=1432") }
    }

    func testPermutationMatrixDotSwapsRows() {
        open("Permutation Lab")
        drag(CGPoint(x: 312, y: 60), to: CGPoint(x: 312, y: 80), designWidth: 390)
        expectValue { $0.hasPrefix("π=1342") }
    }

    func testPermutationSolidTurns() {
        open("Permutation Lab")
        let before = value
        drag(CGPoint(x: 296, y: 250), to: CGPoint(x: 340, y: 270), designWidth: 390)
        expectValue { $0 != before && $0.hasPrefix("π=3142") }
    }

    func testAlgebraCommutes() {
        // Drag the bottom half of the sum up to swap it with the top half.
        open("Animate Algebra")
        drag(CGPoint(x: 54, y: 249), to: CGPoint(x: 54, y: 99), designWidth: 360)
        expectValue { $0.hasPrefix("(+ (+ (× 🎲 🦠)") }
    }

    func testAlgebraWrapsALeafInAddedZero() {
        // Pull a leaf down and right, to where it sits inside (+ 0 _).
        open("Animate Algebra")
        drag(CGPoint(x: 124, y: 34), to: CGPoint(x: 159, y: 79), designWidth: 360)
        expectValue { $0.contains("(+ 0 ⛅)") }
    }

    func testTwistedTreesMoveANodeDown() {
        open("Twisted Trees 3→3")
        drag(CGPoint(x: 55, y: 115), to: CGPoint(x: 44, y: 231), designWidth: 300)
        expectValue("a:a b:root root:root")
    }

    func testTwistedTreesPullTheRestAlong() {
        // The root can't sit below its children, so dragging it takes them too.
        open("Twisted Trees 3→3")
        drag(CGPoint(x: 85, y: 55), to: CGPoint(x: 44, y: 231), designWidth: 300)
        expectValue("a:a b:a root:a")
    }

    // MARK: Composition

    func testIslandsGoOutToSeaAndBack() {
        open("Snap to Islands")
        drag(CGPoint(x: 80, y: 130), to: CGPoint(x: 180, y: 220), designWidth: 360)
        expectValue("at sea")

        drag(CGPoint(x: 180, y: 220), to: CGPoint(x: 280, y: 130), designWidth: 360)
        expectValue("island 1")
    }

    func testMagneticTargets() {
        open("Magnetic Targets")
        drag(CGPoint(x: 200, y: 60), to: CGPoint(x: 150, y: 105), designWidth: 370)
        expectValue("target 0")
    }

    func testSharpness() {
        open("Sharpness")
        drag(CGPoint(x: 50, y: 50), to: CGPoint(x: 125, y: 50), designWidth: 340)
        expectValue("on")
    }

    func testBlendWeights() {
        open("Blend Weights")
        drag(CGPoint(x: 40, y: 40), to: CGPoint(x: 280, y: 260), designWidth: 350)
        expectValue("target 2")
    }

    func testEmergeFrom() {
        open("Emerge From")
        drag(CGPoint(x: 90, y: 50), to: CGPoint(x: 250, y: 50), designWidth: 340)
        expectValue("right")
    }

    func testSproutingTree() {
        open("Sprouting Tree")
        drag(CGPoint(x: 180, y: 40), to: CGPoint(x: 157, y: 100), designWidth: 360)
        expectValue("leaves: 2")
    }

    func testDragToCopyThenTapToRemove() {
        open("Drag to Copy")
        drag(CGPoint(x: 170, y: 110), to: CGPoint(x: 60, y: 60), designWidth: 360)
        expectValue("dots: 2")

        coordinate(CGPoint(x: 60, y: 60), designWidth: 360).tap()
        expectValue("dots: 1")
    }

    func testCopyOrMoveFollowsTheSwitch() {
        open("Copy or Move")
        drag(CGPoint(x: 170, y: 110), to: CGPoint(x: 60, y: 60), designWidth: 360)
        expectValue("dots: 1")

        app.switches.firstMatch.switches.firstMatch.tap()
        drag(CGPoint(x: 60, y: 60), to: CGPoint(x: 280, y: 200), designWidth: 360)
        expectValue("dots: 2")
    }

    func testBinRemovesATile() {
        open("Insert and Remove")
        drag(CGPoint(x: 33, y: 103), to: CGPoint(x: 313, y: 33), designWidth: 350)
        expectValue("🍎🍌")
    }

    func testToolbarAddsATile() {
        open("Insert and Remove")
        drag(CGPoint(x: 135, y: 38), to: CGPoint(x: 33, y: 103), designWidth: 350)
        expectValue("🍇🍎🍎🍌")
    }

    func testTimelineSubstate() {
        open("Timeline (substate)")
        drag(CGPoint(x: 60, y: 28), to: CGPoint(x: 110, y: 112), designWidth: 360)
        expectValue { $0.hasPrefix("Cats:2@6") }
    }

    func testTimelineEmbed() {
        open("Timeline (embed)")
        drag(CGPoint(x: 60, y: 28), to: CGPoint(x: 110, y: 112), designWidth: 360)
        expectValue { $0.hasPrefix("Cats:2@6") }
    }

    func testOverlay() {
        open("Overlay")
        drag(CGPoint(x: 70, y: 90), to: CGPoint(x: 280, y: 90), designWidth: 350)
        expectValue("docked")
    }
}
