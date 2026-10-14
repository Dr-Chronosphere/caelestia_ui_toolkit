# Fractal edge handles (mouse and touch resize)

Drag the border between two tiles to resize them, with a mouse or a finger, in the
[fractal-wm](https://github.com/cgranier/fractal-wm) layout.

## Why this exists

Hyprland's built-in `general.resize_on_border` asks the active layout to resize. A Lua layout
registers only `recalculate` and `layout_msg` (checked in `hl.meta.lua` on Hyprland 0.56): there is no
resize hook, so Hyprland cannot tell fractal-wm that a border was dragged, and fractal-wm's
layout is driven by node weights anyway. So the handles are our own.

## How it works

1. **Engine patch** (`integration/fractal-wm-edge-resize.patch`, against fractal-wm `a0969a8`):
   - new layout command `edge <idA> <idB> <ratio>`: sets how the combined space of two
     neighbouring siblings is shared (combined weight preserved, limits respected);
   - the status file now includes each placed node's `box` and the work `area`.
2. **This overlay**: one thin layer-shell window per seam, on the Top layer, built from those
   boxes. Dragging sends `edge` commands (throttled to about 30 per second, then a final one on
   release). Wayland delivers touch to the surface like pointer input, so it works with touch too.

While you drag, a click-through guide line follows the pointer or finger, so you always see where
the edge is going even if the windows trail behind (the handle windows themselves stay frozen
during a drag; moving a window under the pointer would corrupt the drag maths).

Settings (environment variables of the overlay process, e.g. `env FRACTAL_EDGE_MODE=release
bin/caelestia-fractal-edges restart`):

| Variable | Default | Meaning |
| --- | --- | --- |
| `FRACTAL_EDGE_MODE` | `live` | `live`: tiles follow the drag. `release`: only the guide line moves; tiles snap on release (no lag, no mid-drag reflow) |
| `FRACTAL_EDGE_INTERVAL` | `33` | minimum ms between live resize commands |
| `FRACTAL_EDGE_GRAB` | `16` | handle thickness in px (try `28` for fingers) |

Handles appear only on workspaces using `lua:fractal`, and only between tiles that are on screen
(not tabs, not hidden tiles). Handle thickness defaults to 16 px (`FRACTAL_EDGE_GRAB=28` for fingers).

## Install

`bin/caelestia-fractal-setup install` clones fractal-wm, applies the engine patch and does the rest
of the Lua setup (see `apps/fractal-map/README.md`). Then:

```sh
hyprctl reload                                    # the layout hot-swaps
/path/to/caelestia_ui_toolkit/bin/caelestia-fractal-edges start
```

Start it at login from your Hyprland autostart. `stop` and `restart` also work. Applying the
patch by hand to your own clone also works: `git apply integration/fractal-wm-edge-resize.patch`.

## Tests

```sh
node apps/fractal-edges/tests/seams.test.mjs            # seam geometry, using real engine output
python3 apps/fractal-edges/tests/run_ui_tests.py        # drag maths with synthetic pointer events (PySide6)
# engine patch: apply to a fresh upstream clone, then
lua tests/test_tree.lua && TMPDIR=/tmp lua tests/test_glue.lua      # 35 + 12 tests pass
```

## Not verified (needs a live Hyprland and Quickshell)

- The overlay itself: monitor origin (`HyprlandMonitor.x/y`), detecting the layout via
  `lastIpcObject.tiledLayout`, `Hyprland.dispatch` of the layout message, per-seam layer windows.
- Lag in `live` mode. Likely causes: Hyprland animating every window move, and clients
  re-rendering at each size. `release` mode avoids both. The engine no longer rewrites its state
  file on every `edge` command (status file at once, state at most every 400 ms).
- Touch: relies on Qt turning touch into mouse events on a `MouseArea`.
- Handles sit over 8 px of each neighbouring window's edge, and a fullscreen window hides them.
