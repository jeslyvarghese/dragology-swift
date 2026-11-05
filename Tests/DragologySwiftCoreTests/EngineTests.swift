import Testing
@testable import DragologySwiftCore

@Suite struct BetweenDragTests {
    @Test func theKnobBlendsAndDropsOnTheNearestState() {
        let engine = DragEngine(state: ToggleState(), scene: toggle)

        drag(engine, from: Vec2(30, 30), through: [Vec2(45, 30)])

        // A quarter of the way along, in the running preview.
        #expect(engine.scene.origin(of: "knob") == Vec2(45, 30))

        engine.pointerUp(at: Vec2(45, 30), now: 0)
        #expect(engine.state == ToggleState(isOn: false))

        drag(engine, from: Vec2(30, 30), through: [Vec2(80, 30)])
        engine.pointerUp(at: Vec2(80, 30), now: 0)
        #expect(engine.state == ToggleState(isOn: true))
    }

    @Test func thePreviewStaysOnTheHull() {
        let engine = DragEngine(state: ToggleState(), scene: toggle)

        drag(engine, from: Vec2(30, 30), through: [Vec2(60, 200)])

        #expect(engine.scene.origin(of: "knob") == Vec2(60, 30))
    }

    @Test func dropsAnimateThenSettle() {
        let engine = DragEngine(state: ToggleState(), scene: toggle)

        drag(engine, from: Vec2(30, 30), through: [Vec2(50, 30)])
        engine.pointerUp(at: Vec2(50, 30), now: 1)

        // Right after the drop, the knob hasn't jumped home.
        #expect(engine.scene.origin(of: "knob") == Vec2(50, 30))
        #expect(engine.needsFrames)

        engine.tick(now: 1 + DragTransition.standard.duration + 0.01)

        #expect(engine.scene.origin(of: "knob") == Vec2(30, 30))
        #expect(!engine.needsFrames)
    }
}

@Suite struct VaryDragTests {
    @Test func theThumbFollowsThePointer() throws {
        let engine = DragEngine(state: SliderState(), scene: slider)

        drag(engine, from: Vec2(100, 0), through: [Vec2(150, 40)])

        let origin = try #require(engine.scene.origin(of: "thumb"))
        #expect(abs(origin.x - 150) < 1e-3)
    }

    @Test func theConstraintHolds() {
        let engine = DragEngine(state: SliderState(), scene: slider)

        drag(engine, from: Vec2(100, 0), through: [Vec2(500, 0)])
        engine.pointerUp(at: Vec2(500, 0), now: 0)

        #expect(abs(engine.state.value - 240) < 1e-6)
    }

    @Test func theGrabOffsetIsKept() {
        let engine = DragEngine(state: SliderState(), scene: slider)

        // Grabbed 5 points right of center, so the value lags by 5.
        drag(engine, from: Vec2(105, 0), through: [Vec2(155, 0)])
        engine.pointerUp(at: Vec2(155, 0), now: 0)

        #expect(abs(engine.state.value - 150) < 1e-3)
    }
}

@Suite struct FloatingDragTests {
    @Test func theDraggedRowFollowsAndOthersPreview() throws {
        let engine = DragEngine(state: ListState(), scene: list)

        // Grab row "a" and carry it to the third slot.
        drag(engine, from: Vec2(50, 15), through: [Vec2(70, 95)])

        let dragged = try #require(engine.scene.origin(of: "a"))
        #expect(dragged == Vec2(20, 80))

        // Spring is mid-flight at time 0, so settle it before measuring.
        engine.tick(now: 10)

        #expect(engine.scene.origin(of: "b") == Vec2(0, 0))
        #expect(engine.scene.origin(of: "c") == Vec2(0, 40))
    }

    @Test func dropCommitsTheOrder() {
        let engine = DragEngine(state: ListState(), scene: list)

        drag(engine, from: Vec2(50, 15), through: [Vec2(50, 95)])
        engine.pointerUp(at: Vec2(50, 95), now: 0)

        #expect(engine.state.items == ["b", "c", "a"])
    }

    @Test func theFloatDrawsOnTop() throws {
        let engine = DragEngine(state: ListState(), scene: list)

        drag(engine, from: Vec2(50, 15), through: [Vec2(50, 60)])

        let top = try #require(engine.scene.drawOrder.last)
        #expect(top.node.id == "a")
    }
}

@Suite struct CompositionTests {
    private struct Island: Equatable {
        var x = 0.0
        var isSnapped = true
    }

    private static func islands(_ configure: @escaping (DragSpec<Island>, SceneContext<Island>) -> DragSpec<Island>) -> DragScene<Island> {
        { context in
            SceneCircle(radius: 10)
                .id("dot")
                .fill(.black)
                .transform(.translate(context.state.x, 0))
                .onDrag {
                    let snap = context.drag.fixed(Island(x: 100, isSnapped: true))
                    return configure(snap, context)
                }
        }
    }

    @Test func whenFarHandsOverToTheBackground() {
        let draggable = Self.islands { snap, context in
            snap.whenFar(Island(x: 0, isSnapped: false), gap: WhenFarGap(50))
        }

        let near = DragEngine(state: Island(), scene: draggable)
        drag(near, from: .zero, through: [Vec2(70, 0)])
        near.pointerUp(at: Vec2(70, 0), now: 0)
        #expect(near.state.isSnapped)

        let far = DragEngine(state: Island(), scene: draggable)
        drag(far, from: .zero, through: [Vec2(20, 0)])
        far.pointerUp(at: Vec2(20, 0), now: 0)
        #expect(!far.state.isSnapped)
    }

    @Test func onDropChangesTheOutcomeButNotThePreview() {
        let draggable = Self.islands { snap, _ in
            snap.onDrop { state in
                var copy = state
                copy.x += 1
                return copy
            }
        }

        let engine = DragEngine(state: Island(), scene: draggable)
        drag(engine, from: .zero, through: [Vec2(100, 0)])

        #expect(engine.scene.origin(of: "dot") == Vec2(100, 0))

        engine.pointerUp(at: Vec2(100, 0), now: 0)
        #expect(engine.state.x == 101)
    }

    @Test func snapRadiusJumpsThePreview() {
        let draggable: DragScene<Island> = { context in
            SceneCircle(radius: 10)
                .id("dot")
                .fill(.black)
                .transform(.translate(context.state.x, 0))
                .onDrag {
                    context.drag
                        .between([Island(x: 0), Island(x: 100)])
                        .withSnapRadius(10, transition: nil)
                }
        }

        let engine = DragEngine(state: Island(), scene: draggable)

        drag(engine, from: .zero, through: [Vec2(95, 0)])
        #expect(engine.scene.origin(of: "dot") == Vec2(100, 0))

        engine.pointerMoved(to: Vec2(50, 0), now: 0)
        engine.tick(now: 0)
        #expect(engine.scene.origin(of: "dot") == Vec2(50, 0))
    }

    @Test func customOperatorsPlugIn() {
        // Shifts the pointer, the way a user-written operator might.
        final class Shifted: DragOperator<Island> {
            let inner: DragOperator<Island>

            init(context: DragContext<Island>, inner: DragSpec<Island>) {
                self.inner = inner.makeOperator(context)
                super.init(context: context, name: "shifted")
            }

            override func frame(_ frame: DragFrame) -> DragResult<Island> {
                inner.run(DragFrame(pointer: frame.pointer + Vec2(30, 0)))
            }
        }

        let draggable: DragScene<Island> = { context in
            SceneCircle(radius: 10)
                .id("dot")
                .fill(.black)
                .transform(.translate(context.state.x, 0))
                .onDrag {
                    let spec = context.drag.vary(context.state, \.x)
                    return DragSpec { Shifted(context: $0, inner: spec) }
                }
        }

        let engine = DragEngine(state: Island(), scene: draggable)
        drag(engine, from: .zero, through: [Vec2(10, 0)])
        engine.pointerUp(at: Vec2(10, 0), now: 0)

        #expect(abs(engine.state.x - 40) < 1e-3)
    }
}

@Suite struct InteractionTests {
    private struct Counter: Equatable {
        var taps = 0
        var position = 0.0
    }

    private static func tappable(_ context: SceneContext<Counter>) -> SceneNode<Counter> {
        SceneRect(width: 100, height: 100)
            .id("box")
            .fill(.white)
            .transform(.translate(context.state.position, 0))
            .onTap {
                var next = context.state
                next.taps += 1
                context.setState(next, transition: nil)
            }
            .onDrag { context.drag.vary(context.state, \.position) }
    }

    @Test func aPressThatDoesntMoveIsATap() {
        let engine = DragEngine(state: Counter(), scene: Self.tappable)

        engine.pointerDown(at: Vec2(50, 50), now: 0)
        engine.pointerMoved(to: Vec2(51, 50), now: 0)
        engine.pointerUp(at: Vec2(51, 50), now: 0)

        #expect(engine.state.taps == 1)
    }

    @Test func aPressThatMovesIsADragAndNotATap() {
        let engine = DragEngine(state: Counter(), scene: Self.tappable)

        drag(engine, from: Vec2(50, 50), through: [Vec2(80, 50)])
        engine.pointerUp(at: Vec2(80, 50), now: 0)

        #expect(engine.state.taps == 0)
        #expect(abs(engine.state.position - 30) < 1e-3)
    }

    @Test func aTouchOnNothingDoesNothing() {
        let engine = DragEngine(state: Counter(), scene: Self.tappable)

        engine.pointerDown(at: Vec2(500, 500), now: 0)
        engine.pointerUp(at: Vec2(500, 500), now: 0)

        #expect(engine.state == Counter())
    }

    @Test func aFloatMissingFromTheSpringIsStillDrawn() {
        // A spring whose origin lacks a layer blends it at zero opacity.
        // The finger's layer must be drawn on that very first frame anyway.
        var target = LayeredScene<Counter>(root: SceneGroup {})
        let layer = SceneLayer(node: SceneCircle(radius: 1) as SceneNode<Counter>, stackingPath: [])

        let countBefore = target.drawOrder.count
        target.setLayer(layer, forKey: "float")

        #expect(target.drawOrder.count == countBefore + 1)
    }

    @Test func cancellingKeepsTheOriginalState() {
        let engine = DragEngine(state: Counter(), scene: Self.tappable)

        drag(engine, from: Vec2(50, 50), through: [Vec2(80, 50)])
        engine.pointerCancelled(now: 0)

        #expect(engine.state == Counter())
    }

    @Test func externalStateAnimates() {
        let engine = DragEngine(state: Counter(), scene: Self.tappable)

        engine.setState(Counter(position: 100), now: 0)
        #expect(engine.needsFrames)

        engine.tick(now: 10)
        #expect(engine.scene.origin(of: "box") == Vec2(100, 0))
    }
}
