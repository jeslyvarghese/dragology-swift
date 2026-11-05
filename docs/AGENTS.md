# Using dragology-swift

Notes for coding agents. The full guide is at
https://dragology.quadratic.xyz/docs/documentation/dragologyswiftcore.

For a reorderable list, use `DragList($items) { item in Row(item: item) }`, and stop here.

For anything else, a scene is a pure function from state to a `SceneNode` tree. Elements declare the states they can
be dragged to, and the engine does the rest.

```swift
func toggle(_ context: SceneContext<ToggleState>) -> SceneNode<ToggleState> {
    SceneCircle(radius: 26)
        .id("knob")
        .fill(.white)
        .transform(.translate(context.state.isOn ? 90 : 30, 30))
        .onDrag { context.drag.between([ToggleState(isOn: false), ToggleState(isOn: true)]) }
}

DragCanvas(state: $state, scene: toggle)
```

- State must be `Equatable`.
- Write render functions as `func`s, and keep them pure.
- Position with `.transform`. Rects grow from the origin; circles and text are centered on it.
- Give `.id` to anything that reorders or floats. Ids are unique across the scene.
- `.fill(.clear)` makes an invisible touch target. A shape with no fill catches nothing.
- `drag.vary` takes key paths: `drag.vary(state, \.x, \.y)`. Constraints return values that must be
  at most zero, and helpers in `DragConstraint` combine with `+`.
- Don't use `.foo` at the start of a line in a builder: it continues the previous line. Use
  the components `SceneGroup`, `SceneRect`, `SceneCircle`, `SceneLine`, `ScenePath`, and `SceneText`.

`Examples/DragologyDemo/DragologyDemo/Gallery` has a working example of every operator.
