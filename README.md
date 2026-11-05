# Dragology for iOS

An unofficial Swift port of [Dragology](https://github.com/declarative-dragging/dragology),
the library behind [Declarative Dragging](https://declarative-dragging.github.io/)
(Horowitz, Blinn, and Heer, UIST 2026). It isn't affiliated with or endorsed by the
original authors.

You don't write gesture handlers. You write a pure function from state to a scene,
and declare which states each element can be dragged to. The engine renders those
states speculatively, finds where the element lands in each, and builds the drag:
drop zones, previews, and animation.

**[Site](https://dragology.quadratic.xyz/)** ·
**[Docs](https://dragology.quadratic.xyz/docs/documentation/dragologycore)**

## Install

Add this package with Swift Package Manager, and depend on the `Dragology` product.
Requires iOS 17 or macOS 14.

```swift
.package(url: "https://github.com/jeslyvarghese/dragology-swift", from: "0.1.0")
```

## Example

```swift
import Dragology
import SwiftUI

struct ToggleState: Equatable {
    var isOn = false
}

func toggle(_ context: RenderContext<ToggleState>) -> Node<ToggleState> {
    group {
        rect(width: 120, height: 60, cornerRadius: 30)
            .fill(context.state.isOn ? RGBA(hex: 0x22C55E) : RGBA(hex: 0xD1D5DB))

        circle(radius: 26)
            .id("knob")
            .fill(.white)
            .transform(.translate(context.state.isOn ? 90 : 30, 30))
            .onDrag {
                context.d.between([ToggleState(isOn: false), ToggleState(isOn: true)])
            }
    }
}

struct ContentView: View {
    @State private var state = ToggleState()

    var body: some View {
        DraggableCanvas(state: $state, draggable: toggle)
            .frame(width: 200, height: 100)
    }
}
```

`Examples/DragologyDemo` is a gallery of demos, most of them ported from the original
site, with at least one for every operator. Its showcases include the braid group,
Permutation Lab, Animate Algebra, Twisted Trees, and Face Creator.

## Why a scene tree, and not SwiftUI views?

Declarative dragging has to render hypothetical states, read positions out of them,
and blend between them. SwiftUI views are opaque, so none of that is possible on
them. `Node` is a plain-data scene tree standing in for the SVG of the original,
which `DraggableCanvas` draws with a SwiftUI `Canvas`.

## Drag specs

| Spec | Behavior |
|---|---|
| `d.fixed(state)` | Show one state |
| `d.closest(statesOrSpecs, options:)` | Follow whichever option lands closest to the finger |
| `d.between(statesOrSpecs, options:)` | Blend between targets, inside their convex hull |
| `d.vary(state, \.x, \.y, constraint:, pin:)` | Solve for numbers that bring the element to the finger |
| `d.varyFunction(initial:, state:, ...)` | `vary`, for parameters that change state in concert |
| `d.dropTarget(id, state, boundsState:)` | Show a state while over the element `id` |
| `d.switchToStateAndFollow(state, id, followSpec:)` | Jump to a state, and carry on dragging another element |
| `d.reactTo(value, makeSpec)` | Rebuild a spec when a value changes mid-drag |
| `d.substate(state, \.part) { d in ... }` | Write a spec for one part of the state |
| `d.custom { context in { frame in ... } }` | Write a behavior from scratch |
| `.whenFar(specOrState, gap:)` | Switch to a background spec when far from this one |
| `.withFloating(options)` | Detach the element so it follows the finger |
| `.withSnapRadius(radius, transition:, chaining:)` | Jump the preview to the drop state when close |
| `.withChaining(draggedID:, followSpec:, transition:)` | Commit to each drop state, and restart the drag from it |
| `.onDrop(stateOrFunction)` | Change the drop state, leaving the preview alone |
| `.during(function)` | Transform the state on every frame |
| `.withOverlay(node)` | Draw extra content on top, only during the drag |
| `.withDropTransition(_:)` | Set the drop animation |
| `.withBranchTransition(_:)` | Set the animation between branches |
| `.changeFrame`, `.changeGap`, `.changeResult`, `.withInitContext` | Advanced: adjust a spec's input, gap, result, or context |
| `.with(wrap)` | Apply a reusable modifier |

`context.embed(draggable, at: \.part)` draws a sub-draggable for one part of the state,
and `.emergeFrom(id, mode:)` makes a new layer grow out of an existing one.

For anything else, subclass `Operator` and wrap it with `DragSpec { context in ... }`.

## Things to know

- **Position with `.transform`.** That's what the engine reads and blends.
- **Give an `.id` to anything that reorders, or that's used with `withFloating`.** Ids
  are how nodes match up across renders. They must be unique in the scene.
- **Render functions must be pure.** They run on many hypothetical states per frame,
  and the canvas keeps the function it was first given.
- **`vary` needs the element to move smoothly with its parameters.**
- **A shape with no fill doesn't catch touches inside it**, as in SVG. Use `.fill(.clear)`
  for an invisible touch target.
- **Write render functions as `func`s.** Swift 6 rejects a global `let` closure.

## Differences from the web version

- `vary` uses a damped Gauss-Newton solver with an active set, not COBYLA. It needs
  fewer renders, but unlike COBYLA it relies on derivatives, so it can stall on render
  functions that jump discontinuously.
- Colors blend in sRGB, not Lab.
- Paths with different commands blend by resampling both along their length. The web
  version uses `d3-interpolate-path`. Mismatched shapes switch at the halfway point,
  and mismatched transforms blend as matrices, where the web version throws.
- Coincident `between` targets log a warning and the later ones become unreachable.
  The web version throws.
- Transition durations are in seconds.
- Natural-neighbor weights come from clipping Voronoi cells directly. The web version
  ports Tinfour's algorithm. Both compute Sibson coordinates.

## Not ported yet

- The debug views (spec tree, overlay, drop zones)
- SwiftUI views inside a scene
- Some demos, including the algebra Macro Recorder and Stage Builder

## Known limitations

- `DraggableCanvas` claims every touch, so it blocks scrolling in a parent `ScrollView`.
- `DraggableCanvas` clips to its bounds, so give it room for anything dragged near its
  edges. The web version lets content overflow.
- Canvas content isn't exposed to VoiceOver yet.
- Hit testing uses an estimated size for text.
- One touch at a time, like the original.

## Testing

```sh
swift test

xcodebuild test \
  -project Examples/DragologyDemo/DragologyDemo.xcodeproj \
  -scheme DragologyDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The second command drives the demo with real touches on a simulator.

## Attribution

If you use this in research, please cite the original paper:

```bibtex
@inproceedings{horowitz2026declarative,
  title     = {Declarative Dragging},
  author    = {Horowitz, Joshua and Blinn, Andrew and Heer, Jeffrey},
  booktitle = {Proceedings of the 39th Annual ACM Symposium on
               User Interface Software and Technology (UIST '26)},
  year      = {2026}
}
```

## License

MIT, as with the original. `LICENSE` keeps the original copyright notice.
