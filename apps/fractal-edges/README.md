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
| `FRACTAL_EDGE_SETTLE` | `260` | ms for a shrinking cut (and the rubber-band spring-back) to settle |
| `FRACTAL_EDGE_RECOIL` | `6` | px the line pulls back from a floating window after cutting in (`0` = none) |
| `FRACTAL_EDGE_DEBUG` | off | `1`: log drags, handle windows appearing/vanishing and floating-window changes with a ms clock (run `qs -p apps/fractal-edges` in a terminal to see it) |
| `FRACTAL_ICON_MIN_FRAC` | `0.25` | tiles narrower/shorter than this fraction of the work area get an icon card |
| `FRACTAL_ICON_MIN_W` / `FRACTAL_ICON_MIN_H` | unset | pixel overrides for the fraction |
| `FRACTAL_CARD_RADIUS` | window rounding | card corner radius (default: read from `decoration:rounding`) |
| `FRACTAL_CARD_BLUR` | `wallpaper` | `wallpaper`: cards show a pre-blurred copy of your wallpaper; `off`: opaque cards |
| `FRACTAL_CARD_BLUR_AMOUNT` | `0.5` | how heavy the wallpaper blur is (0..1) |
| `FRACTAL_WALLPAPER` | Caelestia's current wallpaper | image path to use for the card backdrop |
| `FRACTAL_CARD_PAD` | `0` | px to grow (+) or shrink (-) cards; their base size matches where windows really sit in their tiles (measured from `hyprctl clients`) |
| `FRACTAL_ICONS` | on | `off` disables the icon cards |
| `FRACTAL_CARD_BLUR` | `wallpaper` | `wallpaper`: cards show a pre-blurred copy of your wallpaper; `off`: opaque cards |
| `FRACTAL_CARD_BLUR_AMOUNT` | `0.5` | how heavy the wallpaper blur is (0..1) |
| `FRACTAL_EDGE_GRAB` | `16` | handle thickness in px (try `28` for fingers) |

Handle windows are keyed by seam and kept alive: each spans its whole seam, and floating windows
only cut the *input region* (a mask of the grabbable stretches) and the visible bar. Because the
window is never rebuilt, a hovered handle does not blink out after you let go, a handle that
starts cut can grow back to its full length, and that growth is animated like the guide's cuts
(they share `CutLine.qml`). After a drag the guide springs to the limit, then fades out so it
cross-fades with the handle bar instead of vanishing.

Every change of a cut follows one rule (`CutLine.qml`; the rules are pure functions in `Seams.js`,
unit-tested), whether it comes from the line sliding past a window or from a window moving or
resizing by just a few pixels:

- **A cut that gets bigger is applied at once**, plus a small *recoil*: the line snaps to the window's
  edge, then pulls back 6 px from it (always away from the window, so it never overlaps).
  Before the recoil: **cutting in is instant.** A line that moves under a window is cut at once, so it is never drawn
  over the window, however fast you drag (an animated cut-in left the line over the window for the
  few frames it took).
- **A cut that gets smaller eases** (by any amount, not just a full uncover).
  Before: **cutting out is animated.** When the line emerges from behind a window, the gap closes inward
  from both ends toward the window's centre, over 260 ms with an ease-out. The rubber-band
  spring-back uses the same duration and curve (`Guide.cutDuration`) so the two feel alike.

At the start of a drag the guide's ratio is set before its seam, so it never appears at the
previous drag's ratio (that stale first frame used to show a full-size line that then cut in).

The overlay also adds a Hyprland *layer rule* with `no_anim = true` for its own surfaces
(`fractal-edges-edge`, `fractal-edges-guide`, `fractal-edges-card`) and re-applies it after a config reload.
Without it, your `layersIn`/`layersOut` slide-and-fade animations make a "ghost" of the guide line
float away whenever it is hidden. To make the rule permanent instead, add this to your Hyprland
Lua config: `hl.layer_rule({ name = "fractal-edges-noanim", match = { namespace = "fractal-edges-(edge|guide|card)" }, no_anim = true })`.

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

## Icons for tiles that are too small (level of detail)

Like Trellis collapsing small windows to icons: a tile smaller than 220 x 140 px (override with
`FRACTAL_ICON_MIN_W` / `FRACTAL_ICON_MIN_H`; `FRACTAL_ICONS=off` disables) is covered by an opaque
card showing the app's icon (and its name when there is room). **Tapping or clicking the card zooms
into that window** (it sends the layout's `zoom <id>`, so the window fills the view and the card
goes away).

- The window underneath keeps running at its tiny size; the card is a layer surface on top of it.
- **Cards follow their tile live, including while you drag a handle.** They resize with the tile and
  fade with its size: invisible at the threshold, fully visible once the tile is 20% below it, using
  the shell's own effects curve (`Anim.DefaultEffects`, the same `expressiveDefaultEffects` curve the
  toolkit uses everywhere). A card whose tile grew (or whose window closed) fades out before its
  window is removed; one hidden by a floating window goes at once, never drawn over it. A faint card
  (alpha < 0.3) takes no input, so taps reach the window beneath.
- **Blur:** the card's backing is translucent over a pre-blurred copy of your wallpaper (the
  wallpaper decoded at 1/12 size, blurred once with a multi-pass down/up-sample effect, scaled up
  and cropped to the card's place on screen), so it costs nothing per frame and fades smoothly.
  `FRACTAL_CARD_BLUR=off` gives opaque cards, `FRACTAL_CARD_BLUR_AMOUNT` the blur strength.
- **One surface per monitor:** all cards are items in a single screen-sized layer surface whose input
  mask covers only the cards, so a tile change moves/resizes items instead of reconfiguring a layer
  surface per card per frame. (Up to 12 cards are tappable at once.)
- The icon comes from the window class via the desktop entry (`DesktopEntries.heuristicLookup`),
  falling back to the lower-cased class as an icon name, then to a lettered badge.
- Cards are skipped where a floating window overlaps them (a layer surface would otherwise be
  drawn over that window), and are not rebuilt while you drag a handle.
- Cards are keyed by window id and fade in. `Lod.js` holds the (unit-tested)
  rules, `IconCard.qml` the card.

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

## Not verified (icons)

Everything that needs Quickshell or Hyprland: resolving icons (`DesktopEntries`, `iconPath`),
the card windows themselves, and that `zoom <id>` is what you want when a card is tapped. The
rules (which tiles get a card, sizes, floating-window overlap) and the card's rendering and
tap signal are tested headlessly.

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

## Stacking

Surfaces in one layer stack by creation order, and `order` layer rules only affect space reservation,
so cards are Top-layer while the handles and the guide are Overlay: they always draw above the cards
(and the rubber-band overshoot is visible). Caveat: Overlay is above Caelestia's own Top-layer
drawers, so a handle can still cover a popout where they overlap.

## Diagnosing smoothness

`FRACTAL_EDGE_PROFILE=1 bin/caelestia-fractal-edges restart`, drag a handle, then read the log with
`qs -p <path to apps/fractal-edges> log`. Every 2 s it prints UI-thread frame count, frames over 24 ms
and the worst gap (stalls in the overlay itself), how many layout status updates and card rebuilds
happened, and rebuild cost; each rebuild also prints every card's `scale`, `alpha` and fade `mode`.
Many slow frames means the overlay is stalling; none but visible stutter means the lag is Hyprland
or the status file's update rate (compare `status=` to the drag speed).

## Layer namespaces

The overlay's surfaces are `fractal-edges-edge`, `-guide` and `-card`. They deliberately do **not**
start with `caelestia-`: Caelestia's Hyprland config blurs layers matching `caelestia-.*`, and that
rule was blurring whatever was behind a card (the live app) as soon as the card was opaque enough to
pass the rule's alpha cutoff, a sudden pop mid-fade. The overlay's rule also sets `blur = false`.

## Dragging a tile to reposition it

Hyprland floats a tiled window while you drag it and re-tiles it on release; the layout used to put
it next to the *focused* tile, wherever you dropped it, and showed nothing while you dragged. Now:

1. When a tile floats and the pointer then moves, the overlay polls the pointer
   (`hyprctl cursorpos -j`, about 30 times a second).
2. It finds the tile under the pointer. The middle of the tile (30% of it each way,
   `FRACTAL_EDGE_SWAP_SIZE`, 0 = never) **swaps** the two windows and shows the swap icon; anywhere
   else the window goes **beside** the tile on the side the pointer is on (whichever offset from
   the middle is larger decides between left/right and up/down), so it never displaces the app
   underneath.
3. A highlight (`DropHighlight.qml`, namespace `fractal-edges-drop`, click-through) shows where the
   window will sit, gliding between targets.
4. It tells the layout (`drop-intent <window> <target> <zone>`, from the patched fractal-wm), so when
   Hyprland re-tiles the window it lands there. Needs the updated engine patch: re-run
   `caelestia-fractal-setup install`.

A window you float on purpose (a key bind) sits still and never counts as a drag. `FRACTAL_EDGE_DRAG=off`
disables all of it; `FRACTAL_EDGE_DEBUG=1` logs `float event …` and `drop target …` lines, which show
whether Hyprland floats your tile when you drag it (if it doesn't, nothing here fires). Logic and
tests: `DragDrop.js`, `tests/dragdrop.test.mjs`.
