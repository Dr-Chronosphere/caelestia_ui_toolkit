import Quickshell

// One input rectangle of the cards surface's mask, from a {x, y, w, h} rect (all zero = none).
Region {
    property var rect: ({ "x": 0, "y": 0, "w": 0, "h": 0 })

    x: rect.x
    y: rect.y
    width: rect.w
    height: rect.h
}
