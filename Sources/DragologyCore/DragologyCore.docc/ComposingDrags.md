# Composing Drags

Build complex drags out of simple ones.

## Primitives

| Spec | Behavior |
|---|---|
| `d.fixed(state)` | Show one state |
| `d.vary(state, \.x, \.y, constraint:, pin:)` | Solve for numbers that bring the element to the finger |
| `d.varyFunction(initial:, state:, ...)` | `vary`, for parameters that change state in concert |
| `d.dropTarget(id, state, boundsState:)` | Show a state while over the element `id` |
| `d.custom { context in { frame in ... } }` | Write a behavior from scratch |

## Combinators

| Spec | Behavior |
|---|---|
| `d.closest(statesOrSpecs, options:)` | Follow whichever option lands closest to the finger |
| `d.between(statesOrSpecs, options:)` | Blend between targets, inside their convex hull |
| `.whenFar(specOrState, gap:)` | Switch to a background spec when far from this one |
| `d.switchToStateAndFollow(state, id, followSpec:)` | Jump to a state, and carry on dragging another element |
| `d.reactTo(value, makeSpec)` | Rebuild a spec when a value changes mid-drag |
| `d.substate(state, \.part) { d in ... }` | Write a spec for one part of the state |

## Modifiers

| Spec | Behavior |
|---|---|
| `.withFloating(options)` | Detach the element so it follows the finger |
| `.withSnapRadius(radius, transition:, chaining:)` | Jump the preview to the drop state when close |
| `.withChaining(draggedID:, followSpec:, transition:)` | Commit to each drop state, and restart the drag from it |
| `.onDrop(stateOrFunction)` | Change the drop state, leaving the preview alone |
| `.during(function)` | Transform the state on every frame |
| `.withOverlay(node)` | Draw extra content on top, only during the drag |
| `.withDropTransition(_:)`, `.withBranchTransition(_:)` | Set the animations |
| `.changeFrame`, `.changeGap`, `.changeResult`, `.withInitContext` | Advanced: adjust a spec's input, gap, result, or context |
| `.with(wrap)` | Apply a reusable modifier |

## Choosing how a reorder feels

The same list of states gives three different drags:

```swift
d.between(orders)                // slides between positions
d.closest(orders)                // jumps between positions
d.closest(orders).withFloating() // follows the finger, and the rest make room
```

## Islands in a sea

Snap to fixed spots when near them, and roam freely otherwise:

```swift
d.closest(islands)
    .withFloating()
    .whenFar(d.vary(IslandState(island: nil), \.x, \.y))
```

## Constraints

A `vary` constraint returns numbers that must end up at or below zero. ``Constraint`` has
helpers, which combine with `+`:

```swift
d.vary(state, \.value, constraint: { candidate in
    Constraint.inOrder(0, candidate.value, 240)
})
```

## Chaining

A spec is normally fixed when the drag starts. Chaining commits to a state partway through
and starts a fresh spec from there, so one drag can make a series of moves:

```swift
d.closest(steps).withSnapRadius(10, chaining: .chainOnSnap)
```

## Your own operators

Subclass ``Operator`` and override ``Operator/frame(_:)``, then wrap it with
``DragSpec/init(_:)``. Reusable modifiers can be plain functions from spec to spec, applied
with ``DragSpec/with(_:)``.
