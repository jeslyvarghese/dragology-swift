import XCTest

/// Drives the demo with real touches, through the whole stack:
/// gesture recognition, coordinate mapping, the frame loop, and drop.
final class DragTests: XCTestCase {
    private enum Timing {
        static let press: TimeInterval = 0.05
        static let settle: TimeInterval = 2
    }

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "Controls"]
        app.launch()
    }

    /// Drags between two points given in a canvas's own coordinates.
    private func drag(in identifier: String, from start: CGVector, to end: CGVector) {
        let canvas = app.otherElements[identifier]
        XCTAssertTrue(canvas.waitForExistence(timeout: Timing.settle))

        let origin = canvas.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(start)
        let to = origin.withOffset(end)

        from.press(forDuration: Timing.press, thenDragTo: to)
    }

    private func value(of identifier: String) -> String {
        app.staticTexts[identifier + "Value"].label
    }

    private func waitForValue(of identifier: String, _ matches: @escaping (String) -> Bool) {
        let predicate = NSPredicate { _, _ in matches(self.value(of: identifier)) }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)

        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: Timing.settle), .completed,
                       "Unexpected \(identifier) value: \(value(of: identifier))")
    }

    func testToggleFlipsWhenDraggedAcross() {
        XCTAssertEqual(value(of: "toggle"), "off")

        drag(in: "toggle", from: CGVector(dx: 30, dy: 30), to: CGVector(dx: 95, dy: 30))

        waitForValue(of: "toggle") { $0 == "on" }
    }

    func testToggleStaysWhenDraggedOnlyALittle() {
        drag(in: "toggle", from: CGVector(dx: 30, dy: 30), to: CGVector(dx: 50, dy: 30))

        waitForValue(of: "toggle") { $0 == "off" }
    }

    func testSliderFollowsTheFinger() {
        XCTAssertEqual(value(of: "slider"), "100")

        // The thumb sits at x = 120 in the canvas, for a value of 100.
        drag(in: "slider", from: CGVector(dx: 120, dy: 25), to: CGVector(dx: 220, dy: 25))

        waitForValue(of: "slider") { abs((Int($0) ?? 0) - 200) <= 3 }
    }

    func testSliderStopsAtItsLimit() {
        drag(in: "slider", from: CGVector(dx: 120, dy: 25), to: CGVector(dx: 319, dy: 25))

        waitForValue(of: "slider") { $0 == "280" }
    }

    func testDialTurnsToTheFinger() {
        // From the handle at 3 o'clock to 6 o'clock, past the ring's radius.
        drag(in: "dial", from: CGVector(dx: 220, dy: 75), to: CGVector(dx: 160, dy: 148))

        waitForValue(of: "dial") { abs((Int($0.dropLast()) ?? 0) - 90) <= 3 }
    }

    func testListReorders() {
        XCTAssertEqual(value(of: "list"), "Apples,Bananas,Cherries,Dates")

        drag(in: "list", from: CGVector(dx: 150, dy: 20), to: CGVector(dx: 150, dy: 120))

        waitForValue(of: "list") { $0 == "Bananas,Cherries,Apples,Dates" }
    }

    func testTouchingEmptySpaceChangesNothing() {
        drag(in: "list", from: CGVector(dx: 310, dy: 195), to: CGVector(dx: 150, dy: 20))

        waitForValue(of: "list") { $0 == "Apples,Bananas,Cherries,Dates" }
    }
}
