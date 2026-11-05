import Testing
@testable import DragologySwiftCore

private struct Empty: Equatable {}

@Suite struct TransformTests {
    @Test func stepsApplyRightToLeft() {
        let transform = SceneTransform.translate(10, 0) + .rotate(degrees: 90)
        let point = transform.localToGlobal(Vec2(1, 0))

        #expect(abs(point.x - 10) < 1e-9)
        #expect(abs(point.y - 1) < 1e-9)
    }

    @Test func globalToLocalInverts() throws {
        let transform = SceneTransform.translate(10, 20) + .rotate(degrees: 30) + .scale(2)
        let point = Vec2(7, -3)
        let roundTrip = try #require(transform.globalToLocal(transform.localToGlobal(point)))

        #expect(roundTrip.distance(to: point) < 1e-9)
    }

    @Test func anglesBlendTheShortWay() {
        let blended = SceneTransform.lerp(.rotate(degrees: 350), .rotate(degrees: 10), 0.5)

        guard case .rotate(let degrees, _)? = blended.steps.first else {
            Issue.record("Expected a rotation")
            return
        }

        #expect(abs(degrees - 360) < 1e-9)
    }

    @Test func nestedTranslationsLineUp() {
        let nested = SceneTransform.translate(10, 0) + .translate(0, 10)
        let blended = SceneTransform.lerp(nested, .translate(30, 30), 0.5)

        #expect(blended.steps == [.translate(Vec2(20, 20))])
    }

    @Test func mismatchedTransformsStillBlend() {
        let blended = SceneTransform.lerp(.translate(100, 0), .scale(3), 0.5)
        let origin = blended.localToGlobal(.zero)

        #expect(abs(origin.x - 50) < 1e-9)
    }
}

@Suite struct LayerTests {
    @Test func idsBecomeLayersWithAccumulatedTransforms() {
        let root: SceneNode<Empty> = SceneGroup {
            SceneGroup {
                SceneRect(width: 10, height: 10).id("inner").transform(.translate(1, 2))
            }
            .transform(.translate(10, 20))
        }

        let scene = LayeredScene(root: root)

        #expect(scene.origin(of: "inner") == Vec2(11, 22))
    }

    @Test func extractingTakesDescendantsAlong() throws {
        let root: SceneNode<Empty> = SceneGroup {
            SceneGroup {
                SceneRect(width: 1, height: 1).id("child")
            }
            .id("parent")

            SceneRect(width: 1, height: 1).id("other")
        }

        let split = try #require(LayeredScene(root: root).extracting(id: "parent"))

        #expect(split.extracted.layers["child"] != nil)
        #expect(split.remaining.layers["child"] == nil)
        #expect(split.remaining.layers["other"] != nil)
    }

    @Test func stackingFollowsZIndices() {
        let root: SceneNode<Empty> = SceneGroup {
            SceneRect(width: 1, height: 1).id("top").zIndex(.absolute(1))
            SceneRect(width: 1, height: 1).id("bottom").zIndex(.relative(-1))
            SceneRect(width: 1, height: 1).id("middle")
        }

        let ids = LayeredScene(root: root).drawOrder.compactMap(\.node.id)

        #expect(ids == ["bottom", "middle", "top"])
    }

    @Test func childrenStackAboveParentsUnlessNegative() {
        #expect(LayeredScene<Empty>.compareStacking([0], [0, 0]) < 0)
        #expect(LayeredScene<Empty>.compareStacking([0], [0, -1]) > 0)
    }

    @Test func hitTestingFindsTheTopmostHandler() throws {
        let root: SceneNode<Empty> = SceneGroup {
            SceneRect(width: 100, height: 100).id("under").fill(.white).onTap {}
            SceneRect(width: 100, height: 100).id("over").fill(.white).zIndex(.relative(1)).hitTesting(.disabled)
        }

        let hit = try #require(LayeredScene(root: root).hitTest(Vec2(50, 50)))

        // The top layer opted out, so the touch reaches the one beneath.
        #expect(hit.onTap != nil)
    }
}

@Suite struct ShapeTests {
    @Test func aSlotIsHitAcrossItsSizeWithNoFill() {
        let shape = SceneShape.slot(size: Vec2(100, 50))

        #expect(shape.contains(Vec2(50, 25), style: SceneStyle()))
        #expect(!shape.contains(Vec2(150, 25), style: SceneStyle()))
    }

    @Test func hostedContentSurvivesFloatingAndBlending() {
        let slotted: SceneNode<Empty> = SceneNode(shape: .slot(size: Vec2(10, 10)))
        var a = slotted
        a.hostedContent = "content"

        let blended = SceneNode.lerp(a, a, 0.5, unblended: .first)

        #expect(blended.hostedContent as? String == "content")
    }

    @Test func pathsAreHitByTheirOutlineNotTheirBox() {
        // A triangle: the box's far corner is outside it.
        let shape = SceneShape.path([.move(.zero), .line(Vec2(100, 0)), .line(Vec2(0, 100)), .close])
        let style = SceneStyle(fill: .black)

        #expect(shape.contains(Vec2(20, 20), style: style))
        #expect(!shape.contains(Vec2(90, 90), style: style))
    }

    @Test func aRectWithASlightlyNegativeSizeCanBeHitTested() {
        let shape = SceneShape.rect(size: Vec2(-1e-9, 10), cornerRadius: 0)
        let style = SceneStyle(fill: .black)

        #expect(!shape.contains(Vec2(5, 5), style: style))
        #expect(shape.contains(Vec2(0, 5), style: style))
    }
}

@Suite struct BlendTests {
    @Test func pathsOfDifferentStructuresBlendAlongTheirLength() throws {
        let straight = SceneShape.path([.move(.zero), .line(Vec2(100, 0))])
        let bent = SceneShape.path([.move(Vec2(0, 100)), .line(Vec2(50, 100)), .line(Vec2(100, 100))])

        guard case .path(let commands) = SceneShape.lerp(straight, bent, 0.5) else {
            Issue.record("Expected a path")
            return
        }

        let points = PathCommand.flattened(commands)

        #expect(points.first == Vec2(0, 50))
        #expect(try #require(points.last).distance(to: Vec2(100, 50)) < 1e-9)
        #expect(points.allSatisfy { abs($0.y - 50) < 1e-9 })
    }

    @Test func layersMatchByIDAcrossReparenting() {
        let a: SceneNode<Empty> = SceneGroup {
            SceneGroup { SceneCircle(radius: 5).id("dot") }.transform(.translate(0, 0))
        }
        let b: SceneNode<Empty> = SceneGroup {
            SceneGroup {
                SceneGroup { SceneCircle(radius: 5).id("dot") }.transform(.translate(100, 0))
            }
        }

        let blended = LayeredScene.lerp(
            LayeredScene(root: a),
            LayeredScene(root: b),
            0.5,
            unblended: .first
        )

        #expect(blended.origin(of: "dot") == Vec2(50, 0))
    }

    @Test func aLayerOnOneSideFades() {
        let a: SceneNode<Empty> = SceneGroup { SceneCircle(radius: 5).id("dot") }
        let b: SceneNode<Empty> = SceneGroup {}

        let blended = LayeredScene.lerp(LayeredScene(root: a), LayeredScene(root: b), 0.25, unblended: .first)

        #expect(blended.layers["dot"]?.node.opacity == 0.75)
    }

    @Test func weightedBlendMatchesAverage() {
        let scenes: [LayeredScene<Empty>] = [0.0, 30.0, 60.0].map { x in
            LayeredScene(root: SceneGroup { SceneCircle(radius: 1).id("dot").transform(.translate(x, 0)) })
        }

        let blended = LayeredScene.lerp(scenes, weights: [0: 1.0 / 3, 1: 1.0 / 3, 2: 1.0 / 3])
        let origin = blended.origin(of: "dot")

        #expect(abs((origin?.x ?? 0) - 30) < 1e-9)
    }
}
