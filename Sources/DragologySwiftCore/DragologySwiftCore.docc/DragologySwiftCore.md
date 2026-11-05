# ``DragologySwiftCore``

Build drag interactions by declaring what an element can become.

## Overview

dragology-swift is an unofficial Swift port of
[Dragology](https://github.com/declarative-dragging/dragology). Dragology and
[Declarative Dragging](https://declarative-dragging.github.io/) were created by
[Joshua Horowitz](https://joshuahhh.com/), [Andrew Blinn](https://andrewblinn.com/), and
[Jeffrey Heer](https://homes.cs.washington.edu/~jheer/), who aren't involved in this port.

You write a pure function from state to a scene, and say which states each element can
be dragged to. The engine renders those states speculatively, finds where the element
lands in each one, and builds the drag from that: drop zones, previews, and animation.

Add the `DragologySwift` product to your app. It brings in this module, along with
`DragCanvas`, the SwiftUI view that hosts a scene.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:HowItWorks>
- <doc:ComposingDrags>
- <doc:ThingsToKnow>

### Drawing

- ``SceneNode``
- ``SceneNodeBuilder``
- ``SceneTransform``
- ``SceneStyle``
- ``SceneColor``
- ``SceneShape``
- ``PathCommand``
- ``ZIndex``
- ``EmergeMode``
- ``HitTesting``
- ``SceneDeferred``
- ``ScenePoint``

### Describing drags

- ``DragScene``
- ``SceneContext``
- ``DragSpec``
- ``DragSpecBuilder``
- ``DragConstraint``
- ``DragTransition``
- ``ClosestOptions``
- ``BetweenOptions``
- ``BetweenInterpolation``
- ``FloatingOptions``
- ``WhenFarGap``
- ``SnapChaining``

### Writing your own operators

- ``DragOperator``
- ``DragContext``
- ``DragFrame``
- ``DragResult``
- ``DragChaining``
- ``LazyPreview``

### Running a drag

- ``DragEngine``
- ``LayeredScene``
- ``SceneLayer``
- ``Vec2``
