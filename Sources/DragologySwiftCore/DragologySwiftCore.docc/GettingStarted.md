# Getting Started

Make a toggle switch you can drag.

## Add the package

In Xcode, choose **File > Add Package Dependencies** and enter
`https://github.com/jeslyvarghese/dragology-swift`. Or add it to `Package.swift`:

```swift
.package(url: "https://github.com/jeslyvarghese/dragology-swift", from: "0.3.0")
```

Then depend on the `DragologySwift` product. It needs iOS 26 or macOS 26.

## Describe your state

State is a plain value. It has to be `Equatable`, so the engine can tell when it changes.

```swift
struct ToggleState: Equatable {
    var isOn = false
}
```

## Draw it

A render function turns state into a scene. Write it as a `func`: Swift 6 rejects a
global `let` closure.

```swift
import DragologySwift
import SwiftUI

func toggle(_ context: SceneContext<ToggleState>) -> SceneNode<ToggleState> {
    SceneGroup {
        SceneRect(width: 120, height: 60, cornerRadius: 30)
            .fill(context.state.isOn ? SceneColor(hex: 0x22C55E) : SceneColor(hex: 0xD1D5DB))

        SceneCircle(radius: 26)
            .id("knob")
            .fill(.white)
            .transform(.translate(context.state.isOn ? 90 : 30, 30))
    }
}
```

So far this is only a picture, with nothing about touch in it.

## Say what the knob can become

Add ``SceneNode/onDrag(_:)`` to the knob, listing the states it can be dragged between:

```swift
SceneCircle(radius: 26)
    .id("knob")
    .fill(.white)
    .transform(.translate(context.state.isOn ? 90 : 30, 30))
    .onDrag {
        context.drag.between([ToggleState(isOn: false), ToggleState(isOn: true)])
    }
```

That's the whole interaction. The knob slides between its two positions, the track's
color blends along with it, and it settles on the nearest state when you let go.

## Put it on screen

`DragCanvas` hosts the scene in SwiftUI, and keeps a binding up to date on each drop:

```swift
struct ContentView: View {
    @State private var state = ToggleState()

    var body: some View {
        DragCanvas(state: $state, scene: toggle)
            .frame(width: 200, height: 100)
    }
}
```

## Next steps

Read <doc:HowItWorks> to see what the engine does with those states, and
<doc:ComposingDrags> for the rest of the vocabulary. The `Examples/DragologyDemo` project
has more than thirty working demos.
