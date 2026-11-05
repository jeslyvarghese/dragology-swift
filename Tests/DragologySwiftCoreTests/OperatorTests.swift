import Testing
@testable import DragologySwiftCore

/// A dot at `x`, plus a target zone with its own id.
private struct Dot: Equatable {
    var x = 0.0
    var y = 0.0
    var isTrashed = false
    var extra = false
}

private func zone() -> Node<Dot> {
    rect(width: 50, height: 50).id("zone").fill(.white).transform(.translate(200, 0))
}

private func scene(_ spec: @escaping (RenderContext<Dot>) -> DragSpec<Dot>) -> Draggable<Dot> {
    { context in
        group {
            zone()

            if context.state.extra {
                circle(radius: 5).id("copy").fill(.black).transform(.translate(context.state.x, 50))
            }

            circle(radius: 10)
                .id("dot")
                .fill(.black)
                .transform(.translate(context.state.x, context.state.y))
                .onDrag { spec(context) }
        }
    }
}

@Suite struct DropTargetTests {
    private static func draggable(_ context: RenderContext<Dot>) -> Node<Dot> {
        scene { context in
            context.d
                .dropTarget("zone", Dot(isTrashed: true))
                .whenFar(context.d.vary(context.state, \.x, \.y), gap: WhenFarGap(1))
        }(context)
    }

    @Test func droppingInsideTheTargetTakesItsState() {
        let engine = DragEngine(state: Dot(), draggable: Self.draggable)

        drag(engine, from: .zero, through: [Vec2(225, 25)])
        engine.pointerUp(at: Vec2(225, 25), now: 0)

        #expect(engine.state.isTrashed)
    }

    @Test func droppingOutsideFallsThrough() {
        let engine = DragEngine(state: Dot(), draggable: Self.draggable)

        drag(engine, from: .zero, through: [Vec2(100, 25)])
        engine.pointerUp(at: Vec2(100, 25), now: 0)

        #expect(!engine.state.isTrashed)
        #expect(abs(engine.state.x - 100) < 1e-3)
    }
}

@Suite struct ChainingTests {
    @Test func chainingCommitsAndRebuildsTheSpec() {
        // Each step only offers the next 100 points, so reaching 200
        // takes two chained hops.
        let draggable = scene { context in
            let next = Dot(x: context.state.x + 100)

            return context.d
                .between([context.state, next])
                .withSnapRadius(5, chaining: .chainOnSnap)
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        drag(engine, from: .zero, through: [Vec2(100, 0), Vec2(100, 0), Vec2(200, 0), Vec2(200, 0)])
        engine.pointerUp(at: Vec2(200, 0), now: 0)

        #expect(engine.state.x == 200)
    }

    @Test func withoutChainingOneHopIsTheLimit() {
        let draggable = scene { context in
            context.d.between([context.state, Dot(x: context.state.x + 100)])
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        drag(engine, from: .zero, through: [Vec2(100, 0), Vec2(200, 0)])
        engine.pointerUp(at: Vec2(200, 0), now: 0)

        #expect(engine.state.x == 100)
    }

    @Test func withChainingFeedsEachResultIntoTheNextFrame() {
        // Without feedback, `during` would always start from the original.
        let draggable = scene { context in
            context.d
                .vary(context.state, \.x)
                .during { state in
                    var copy = state
                    copy.y += 1
                    return copy
                }
                .withChaining(transition: nil)
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        drag(engine, from: .zero, through: [Vec2(1, 0), Vec2(2, 0), Vec2(3, 0)])
        engine.pointerUp(at: Vec2(3, 0), now: 0)

        #expect(engine.state.y >= 3)
    }

    @Test func followSwitchesElementAndState() throws {
        let draggable: Draggable<Dot> = { context in
            let state = context.state

            return group {
                if state.extra {
                    circle(radius: 5)
                        .id("copy")
                        .fill(.black)
                        .transform(.translate(state.y, 0))
                }

                circle(radius: 10)
                    .id("dot")
                    .fill(.black)
                    .transform(.translate(state.x, 0))
                    .onDrag {
                        let copied = Dot(x: state.x, y: state.x, extra: true)

                        return context.d.switchToStateAndFollow(
                            copied,
                            "copy",
                            followSpec: context.d.vary(copied, \.y)
                        )
                    }
            }
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        drag(engine, from: .zero, through: [Vec2(80, 0)])

        let copy = try #require(engine.scene.origin(of: "copy"))
        #expect(abs(copy.x - 80) < 1e-3)
        #expect(engine.scene.origin(of: "dot") == .zero)

        engine.pointerUp(at: Vec2(80, 0), now: 0)
        #expect(engine.state.extra)
    }
}

@Suite struct SubstateTests {
    private struct Block: Equatable {
        var position = 0.0
    }

    private struct Timeline: Equatable {
        var title = "kept"
        var blocks = [Block(), Block()]
    }

    private static func blockNode(_ context: RenderContext<Block>) -> Node<Block> {
        rect(width: 20, height: 20)
            .id("embedded")
            .fill(.black)
            .transform(.translate(context.state.position, 0))
            .onDrag { context.d.vary(context.state, \.position) }
    }

    @Test func aSubstateSpecEditsOnlyItsPart() {
        let draggable: Draggable<Timeline> = { context in
            let state = context.state

            return rect(width: 20, height: 20)
                .id("block")
                .fill(.black)
                .transform(.translate(state.blocks[1].position, 0))
                .onDrag {
                    context.d.substate(state, \.blocks[1]) { d in
                        d.vary(state.blocks[1], \.position)
                    }
                }
        }

        let engine = DragEngine(state: Timeline(), draggable: draggable)

        drag(engine, from: Vec2(5, 5), through: [Vec2(55, 5)])
        engine.pointerUp(at: Vec2(55, 5), now: 0)

        #expect(abs(engine.state.blocks[1].position - 50) < 1e-3)
        #expect(engine.state.blocks[0].position == 0)
        #expect(engine.state.title == "kept")
    }

    @Test func anEmbeddedDraggableLiftsItsDrags() {
        let draggable: Draggable<Timeline> = { context in
            group { context.embed(Self.blockNode, at: \.blocks[0]) }
        }

        let engine = DragEngine(state: Timeline(), draggable: draggable)

        drag(engine, from: Vec2(5, 5), through: [Vec2(35, 5)])
        engine.pointerUp(at: Vec2(35, 5), now: 0)

        #expect(abs(engine.state.blocks[0].position - 30) < 1e-3)
        #expect(engine.state.title == "kept")
    }
}

@Suite struct AdvancedModifierTests {
    @Test func reactToRebuildsWhenItsValueChanges() {
        final class Flag {
            var isOn = false
        }

        let flag = Flag()
        let draggable = scene { context in
            context.d.reactTo({ flag.isOn }) { isOn in
                context.d.fixed(Dot(x: isOn ? 100 : 50))
            }
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        drag(engine, from: .zero, through: [Vec2(10, 0)])
        #expect(engine.scene.origin(of: "dot") == Vec2(50, 0))

        flag.isOn = true
        engine.tick(now: 10)
        engine.tick(now: 20)
        #expect(engine.scene.origin(of: "dot") == Vec2(100, 0))
    }

    @Test func overlaysShowDuringTheDragAndGoAwayAfter() {
        let draggable = scene { context in
            context.d.fixed(Dot(x: 10)).withOverlay(circle(radius: 3).id("mark"))
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)
        let hasOverlay = { engine.scene.layers.keys.contains { $0.hasSuffix("mark") } }

        drag(engine, from: .zero, through: [Vec2(10, 0)])
        #expect(hasOverlay())
        #expect(engine.scene.drawOrder.last?.node.id?.hasSuffix("mark") == true)

        engine.pointerUp(at: Vec2(10, 0), now: 0)
        engine.tick(now: 10)
        #expect(!hasOverlay())
    }

    @Test func changeFrameRemapsThePointer() {
        let draggable = scene { context in
            context.d
                .vary(context.state, \.x)
                .changeFrame { DragFrame(pointer: Vec2(-$0.pointer.x, 0)) }
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        drag(engine, from: .zero, through: [Vec2(40, 0)])
        engine.pointerUp(at: Vec2(40, 0), now: 0)

        #expect(abs(engine.state.x + 40) < 1e-3)
    }

    @Test func changeGapReweightsClosest() {
        let draggable = scene { context in
            context.d.closest([
                context.d.fixed(Dot(x: 0)).changeGap { $0 * 10 },
                context.d.fixed(Dot(x: 100)),
            ])
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        // Nearer the first target, but its gap counts for ten times more.
        drag(engine, from: .zero, through: [Vec2(20, 0)])
        engine.pointerUp(at: Vec2(20, 0), now: 0)

        #expect(engine.state.x == 100)
    }

    @Test func changeResultCanRewriteTheOutcome() {
        let draggable = scene { context in
            context.d.fixed(Dot(x: 10)).changeResult { $0.dropState.y = 7 }
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        drag(engine, from: .zero, through: [Vec2(10, 0)])
        engine.pointerUp(at: Vec2(10, 0), now: 0)

        #expect(engine.state.y == 7)
    }

    @Test func customBehaviorsRunEachFrame() {
        let draggable = scene { context in
            context.d.custom { dragContext in
                { frame in
                    let state = Dot(x: frame.pointer.x.rounded())

                    return DragResult(
                        preview: Lazy { dragContext.render(state) },
                        dropState: state,
                        gap: 0
                    )
                }
            }
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        drag(engine, from: .zero, through: [Vec2(12.4, 0)])
        engine.pointerUp(at: Vec2(12.4, 0), now: 0)

        #expect(engine.state.x == 12)
    }

    @Test func withInitContextAdjustsTheAnchor() {
        let draggable = scene { context in
            context.d
                .vary(context.state, \.x)
                .withInitContext { $0.anchor = Vec2(10, 0) }
        }

        let engine = DragEngine(state: Dot(), draggable: draggable)

        drag(engine, from: .zero, through: [Vec2(50, 0)])
        engine.pointerUp(at: Vec2(50, 0), now: 0)

        #expect(abs(engine.state.x - 40) < 1e-3)
    }
}

@Suite struct EmergenceTests {
    private struct Sprout: Equatable {
        var isGrown = false
    }

    private static func tree(_ mode: EmergeMode) -> (Sprout) -> LayeredScene<Sprout> {
        { state in
            LayeredScene(root: group {
                circle(radius: 5).id("seed").transform(.translate(100, 0))

                if state.isGrown {
                    circle(radius: 5)
                        .id("leaf")
                        .transform(.translate(100, 100))
                        .emergeFrom("seed", mode: mode)
                }
            })
        }
    }

    @Test func scaleGrowsFromTheOriginAndFadesIn() throws {
        let render = Self.tree(.scale)
        let blended = LayeredScene.lerp(render(Sprout()), render(Sprout(isGrown: true)), 0.5, unblended: .first)
        let leaf = try #require(blended.layers["leaf"])

        #expect(leaf.node.opacity == 0.5)
        #expect(blended.origin(of: "leaf") == Vec2(100, 50))
    }

    @Test func cloneStaysOpaque() throws {
        let render = Self.tree(.clone)
        let blended = LayeredScene.lerp(render(Sprout()), render(Sprout(isGrown: true)), 0.5, unblended: .first)
        let leaf = try #require(blended.layers["leaf"])

        #expect(leaf.node.opacity == 1)
        #expect(blended.origin(of: "leaf") == Vec2(100, 50))
    }

    @Test func morphStartsFromTheOriginsBox() throws {
        let render = { (isGrown: Bool) -> LayeredScene<Sprout> in
            LayeredScene(root: group {
                group { rect(width: 10, height: 10) }.id("seed")

                if isGrown {
                    group { rect(width: 30, height: 30) }
                        .id("box")
                        .transform(.translate(100, 0))
                        .emergeFrom("seed", mode: .morph)
                }
            })
        }

        let blended = LayeredScene.lerp(render(false), render(true), 0.5, unblended: .first)
        let box = try #require(blended.layers["box"])

        #expect(box.node.opacity == 0.5)
        #expect(box.node.children.first?.shape == .rect(size: Vec2(20, 20), cornerRadius: 0))
    }

    @Test func itWorksInBothDirections() {
        let render = Self.tree(.scale)
        let blended = LayeredScene.lerp(render(Sprout(isGrown: true)), render(Sprout()), 0.5, unblended: .first)

        #expect(blended.origin(of: "leaf") == Vec2(100, 50))
    }
}

@Suite struct NaturalNeighborTests {
    private let square = [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100), Vec2(40, 60)]

    private func reconstruct(_ weights: [Int: Double]) -> Vec2 {
        weights.reduce(Vec2.zero) { $0 + square[$1.key] * $1.value }
    }

    @Test func weightsSumToOneAndReproduceThePoint() {
        let triangulation = Triangulation(points: square)

        // Sibson coordinates have linear precision: they rebuild the query.
        for query in [Vec2(20, 30), Vec2(70, 80), Vec2(50, 10), Vec2(90, 50)] {
            let weights = triangulation.naturalNeighbors(query).weights

            #expect(abs(weights.values.reduce(0, +) - 1) < 1e-6)
            #expect(reconstruct(weights).distance(to: query) < 1e-3)
        }
    }

    @Test func outsideTheHullItMatchesTheProjection() {
        let triangulation = Triangulation(points: square)
        let projection = triangulation.naturalNeighbors(Vec2(200, 50))

        #expect(projection.point == Vec2(100, 50))
    }

    @Test func aTargetGetsAllTheWeightAtItsOwnPosition() {
        let triangulation = Triangulation(points: square)
        let weights = triangulation.naturalNeighbors(Vec2(40, 60)).weights

        #expect(abs((weights[4] ?? 0) - 1) < 1e-6)
    }
}

@Suite struct HitRuleTests {
    @Test func anOutlineDoesntCatchTouchesInside() {
        let root: Node<Dot> = group {
            rect(width: 100, height: 100).id("under").fill(.white).onTap {}
            circle(radius: 40).id("ring").stroke(.black).transform(.translate(50, 50)).zIndex(.relative(1))
        }

        let hit = LayeredScene(root: root).hitTest(Vec2(50, 50))

        #expect(hit?.onTap != nil)
    }
}
