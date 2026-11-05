# How It Works

What the engine does with the states you give it.

## Model-driven dragging

Most drag code works in geometry: hit regions, offsets, snapping distances. Here you work
in your own model. When a drag starts, the engine:

1. Calls your `onDrag` closure, which returns a ``DragSpec`` naming the reachable states.
2. Renders each of those states speculatively, with your own render function.
3. Reads where the dragged element lands in each render. Those positions are the targets.
4. On every frame, turns the finger's position into a preview to show, and a state to
   commit if the finger lifts here.

Change your layout and the drag follows, because the targets come from the same code that
draws the scene.

## Why a scene tree, and not SwiftUI views

This approach has to render hypothetical states, read positions out of them, and blend
between them. SwiftUI views are opaque, so none of that is possible on them. ``SceneNode`` is a
plain-data scene tree that plays the part SVG plays on the web, and `DragCanvas` draws
it with a SwiftUI `Canvas`.

To put a real SwiftUI view in a scene, use `DragItem`. The scene decides where the view goes,
and SwiftUI draws what's in it, so its `@State` and controls keep working.

## Layers

Any node with an ``SceneNode/id`` becomes a separate layer. Layers are matched by id between
renders, wherever they sit in each tree, so a node can change parents and still blend
smoothly. A layer that exists in only one state fades, or grows out of another with
``SceneNode/emergeFrom(_:mode:)``.

## Behaviors

A running spec is an ``DragOperator``. Each frame it takes a ``DragFrame`` and returns a
``DragResult``, whose main parts are a preview, a drop state, and a `gap`: how far the
element is from the finger. Combinators like `closest` choose between their children by
comparing gaps.

## Solving for numbers

``DragSpecBuilder/vary(_:_:constraint:pin:)`` handles continuous values. It searches for the
numbers that bring the element to the finger, rendering the state as it goes. You don't
write any inverse geometry: if an element's position comes from an angle, dragging it
works out the angle.
