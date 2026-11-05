# Using Dragology for iOS

Notes for coding agents. The full guide is at
https://dragology.quadratic.xyz/docs/documentation/dragologycore.

A scene is a pure function from state to a `Node` tree. Elements declare the states they can
be dragged to, and the engine does the rest.

```swift
func toggle(_ context: RenderContext<ToggleState>) -> Node<ToggleState> {
    circle(radius: 26)
        .id("knob")
        .fill(.white)
        .transform(.translate(context.state.isOn ? 90 : 30, 30))
        .onDrag { context.d.between([ToggleState(isOn: false), ToggleState(isOn: true)]) }
}

DraggableCanvas(state: $state, draggable: toggle)
```

- State must be `Equatable`.
- Write render functions as `func`s, and keep them pure.
- Position with `.transform`. Rects grow from the origin; circles and text are centered on it.
- Give `.id` to anything that reorders or floats. Ids are unique across the scene.
- `.fill(.clear)` makes an invisible touch target. A shape with no fill catches nothing.
- `d.vary` takes key paths: `d.vary(state, \.x, \.y)`. Constraints return values that must be
  at most zero, and helpers in `Constraint` combine with `+`.
- Don't use `.foo` at the start of a line in a builder: it continues the previous line. Use
  the free functions `group`, `rect`, `circle`, `line`, `path`, and `label`.

`Examples/DragologyDemo/DragologyDemo/Gallery` has a working example of every operator.
