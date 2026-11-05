# ``DragologyCore``

Build drag interactions by declaring what an element can become.

## Overview

Dragology for iOS is an unofficial Swift port of
[Dragology](https://github.com/declarative-dragging/dragology), the library behind
[Declarative Dragging](https://declarative-dragging.github.io/) by [Joshua Horowitz](https://joshuahhh.com/),
[Andrew Blinn](https://andrewblinn.com/), and [Jeffrey Heer](https://homes.cs.washington.edu/~jheer/).

You write a pure function from state to a scene, and say which states each element can
be dragged to. The engine renders those states speculatively, finds where the element
lands in each one, and builds the drag from that: drop zones, previews, and animation.

Add the `Dragology` product to your app. It brings in this module, along with
`DraggableCanvas`, the SwiftUI view that hosts a scene.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:HowItWorks>
- <doc:ComposingDrags>
- <doc:ThingsToKnow>

### Drawing

- ``Node``
- ``NodeBuilder``
- ``Transform``
- ``Style``
- ``RGBA``
- ``Shape``
- ``PathCommand``
- ``ZIndex``
- ``EmergeMode``
- ``HitTesting``
- ``Finalizers``
- ``PointRef``

### Describing drags

- ``Draggable``
- ``RenderContext``
- ``DragSpec``
- ``DragSpecBuilder``
- ``Constraint``
- ``Transition``
- ``ClosestOptions``
- ``BetweenOptions``
- ``BetweenInterpolation``
- ``FloatingOptions``
- ``WhenFarGap``
- ``SnapChaining``

### Writing your own operators

- ``Operator``
- ``DragContext``
- ``DragFrame``
- ``DragResult``
- ``Chaining``
- ``Lazy``

### Running a drag

- ``DragEngine``
- ``LayeredScene``
- ``Layer``
- ``Vec2``
