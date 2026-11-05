# Things to Know

Rules of thumb, limitations, and how this differs from the web version.

## Rules of thumb

- **Position with ``SceneNode/transform(_:)``.** That's what the engine reads and blends.
- **Give an id to anything that reorders, or that floats.** Ids match nodes across renders,
  and must be unique in the scene.
- **Keep render functions pure.** They run on many hypothetical states per frame. The canvas
  keeps the function it was first given.
- **Write render functions as `func`s.** Swift 6 rejects a global `let` closure.
- **Build a hit target with `.fill(.clear)`.** As in SVG, an outline with no fill doesn't
  catch touches inside it.
- **Make sure targets are in different places.** Two targets in one spot can't be told apart
  by dragging. `between` logs a warning, and the later one can't be reached.
- **`vary` needs an element that moves smoothly with its parameters.**

## Limitations

- To scroll in a parent `ScrollView`, use `.dragActivation(.longPress())`. With the default
  `.immediate`, a swipe that starts on a draggable element drags it.
- It clips to its bounds, so leave room for anything dragged near the edges.
- Scene content isn't exposed to VoiceOver yet.
- Only one touch at a time, as in the original.
- In a `DragItem`, position and opacity animate, but what's inside the view doesn't blend.
- Hit testing uses an estimated size for text.

## Differences from the web version

- `vary` uses a damped Gauss-Newton solver with an active set, not COBYLA. It relies on
  derivatives, so it can stall on render functions that jump discontinuously.
- Colors blend in sRGB, not Lab.
- Paths with different commands blend by resampling. Mismatched shapes switch at the halfway
  point, and mismatched transforms blend as matrices, where the web version throws.
- Natural-neighbor weights come from clipping Voronoi cells directly.
- Transition durations are in seconds.
- The debug views aren't ported.
