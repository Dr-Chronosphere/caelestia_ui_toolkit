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
| `FRACTAL_EDGE_ANIM` | `suspend` | by default Hyprland's animations are switched off during a drag and restored 150 ms after the last resize (only if they were on); `keep` leaves them alone |
| `FRACTAL_EDGE_GRAB` | `16` | handle thickness in px (try `28` for fingers) |

Handle windows are keyed by seam and kept alive: each spans its whole seam, and floating windows
only cut the *input region* (a mask of the grabbable stretches) and the visible bar. Because the
window is never rebuilt, a hovered handle does not blink out after you let go, a handle that
starts cut can grow back to its full length, and that growth is animated like the guide's cuts
(they share `CutLine.qml`). After a drag the guide springs to the limit, then fades out so it
cross-fades with the handle bar instead of vanishing.

When the guide line slides sideways past a floating window's edge, the cut around that window
opens or closes over about 140 ms (around the window's centre) instead of popping.

The overlay also adds a Hyprland *layer rule* with `no_anim = true` for its own surfaces
(`caelestia-fractal-edge`, `caelestia-fractal-guide`) and re-applies it after a config reload.
Without it, your `layersIn`/`layersOut` slide-and-fade animations make a "ghost" of the guide line
float away whenever it is hidden. To make the rule permanent instead, add this to your Hyprland
Lua config: `hl.layer_rule({ name = "fractal-edges-noanim", match = { namespace = "caelestia-fractal-(edge|guide)" }, no_anim = true })`.

Each seam knows how far the engine will let it move (the tiles' weights are kept within 0.2-5,
mirrored in `Seams.js`). Dragging past that limit does not just stop: the guide line stretches
a little (it gets harder to pull, up to about 40 px beyond the limit) and thickens, then springs back
smoothly when you let go, while the tiles stay at the limit.

Floating windows (and scratchpad/special-workspace and pinned windows) always sit above the tiled
layout, but layer-shell surfaces render above *every* window, so handles and the drag guide are cut
wherever a floating window covers a seam (pieces shorter than 24 px are dropped). The overlay reads
`hyprctl clients -j` / `monitors -j` on window events and polls every 350 ms while a floating window
exists, so dragging a floating window keeps the handles in step.

Handles appear only on workspaces using `lua:fractal`, and only between tiles that are on screen
(not tabs, not hidden tiles). Handle thickness defaults to 16 px (`FRACTAL_EDGE_GRAB=28` for fingers).

## Install

`bin/caelestia-fractal-setup install` clones fractal-wm, applies the engine patch and does the rest
of the Lua setup (see `apps/fractal-map/README.md`). Then:

```sh
hyprctl reload                                    # the layout hot-swaps
/path/to/caelestia_ui_toolkit/bin/caelestia-fractal-edges start
```

Start it at login from your Hyprland autostart. `stop` and `restart` shut the overlay down
gracefully (an IPC `quit` that destroys the handle windows first, then exits), fall back to
`qs kill`, and wait for the old instance to be gone before a restart starts a new one.

Quickshell hot-reloads when its files change, so run `bin/caelestia-fractal-edges stop` before
`git pull`. Otherwise it may try to reload mid-update and log a harmless
`EdgeStrip is not a type` error (the old version keeps running). Applying the
patch by hand to your own clone also works: `git apply integration/fractal-wm-edge-resize.patch`.

## Tests

```sh
node apps/fractal-edges/tests/seams.test.mjs            # seam geometry, using real engine output
python3 apps/fractal-edges/tests/run_ui_tests.py        # drag maths with synthetic pointer events (PySide6)
# engine patch: apply to a fresh upstream clone, then
lua tests/test_tree.lua && TMPDIR=/tmp lua tests/test_glue.lua      # 35 + 12 tests pass
```

## Animations and lag

While a handle is dragged, the overlay runs `hyprctl eval 'hl.config({ animations = { enabled = false } })'`
and restores it afterwards (it reads `animations:enabled` first, so it never enables animations you
had off). This keeps tiles locked to the pointer and the guide line on the seam instead of over
window contents. If the overlay dies mid-drag, `hyprctl reload` restores your settings.

Hyprland animation `speed` is in units of 100 ms, so `hl.animation({ leaf = "windowsMove", speed = 6 })`
means every tile move takes 600 ms. In `live` mode the handles send about 30 resizes a second, so
tiles can never catch up with the pointer. Two ways out:

- `FRACTAL_EDGE_MODE=release`: only the guide line follows the pointer; tiles resize once on
  release (one animation). Works with any animation settings.
- Shorten the window-move animation if you want `live` to feel direct, e.g. change `speed = 6` to
  `speed = 2` on the `windowsMove` line of your animations file, then `hyprctl reload`. This
  affects all window moves, not just handle drags.

The Lua API's `no_anim` rule field exists for layer rules; I did not find it for window rules, so
there is no per-window "don't animate" switch to use for the engine's parked windows.

## Troubleshooting

- **Crash on exit** (`Aborted` inside `QWindow::unsetCursor`, seen when killing the overlay with
  `qs kill`): handle windows own a resize cursor and were destroyed during teardown, after Qt
  could no longer unset it. `stop`/`restart` now avoid this. If you still get a crash report,
  please keep it; the stack trace and the last lines of the log are what I need.
- `integration/test-launchers.sh` tests the stop/restart logic against a fake `qs`.

## Not verified (needs a live Hyprland and Quickshell)

- The overlay itself: monitor origin (`HyprlandMonitor.x/y`), detecting the layout via
  `lastIpcObject.tiledLayout`, `Hyprland.dispatch` of the layout message, per-seam layer windows.
- Lag in `live` mode. Likely causes: Hyprland animating every window move, and clients
  re-rendering at each size. `release` mode avoids both. The engine no longer rewrites its state
  file on every `edge` command (status file at once, state at most every 400 ms).
- Touch: relies on Qt turning touch into mouse events on a `MouseArea`.
- Floating-window clipping: the overlay assumes `clients -j` / `monitors -j` have the usual fields
  (`floating`, `at`, `size`, `workspace`, `pinned`, `specialWorkspace`); the geometry is tested with
  sample data, not against your Hyprland. A floating window *behind* another overlay surface is
  treated like any other.
- Handles sit over 8 px of each neighbouring window's edge, and a fullscreen window hides them.
