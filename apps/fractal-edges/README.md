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
   **Screen edges come first**: within 10% of the work area's edge (`FRACTAL_EDGE_SCREEN_BAND`, 0 =
   off) the window takes a *half* of the screen (left, right, top or bottom), and in a corner a
   *quadrant* (the other windows are split between the rest), whatever windows happen to exist, so a
   pure split-screen is always one drop away.
3. A highlight (`DropHighlight.qml`, namespace `fractal-edges-drop`, click-through) shows where the
   window will sit, gliding between targets.
4. While you drag, the layout keeps the dragged window's slot (`drag-hold`), so the other tiles
   **do not reflow** and a swap is a real swap; a window you float on purpose is released after a
   second. It tells the layout (`drop-intent <window> <target|screen> <zone>`, from the patched fractal-wm), so when
   Hyprland re-tiles the window it lands there. Needs the updated engine patch: re-run
   `caelestia-fractal-setup install`.

A window you float on purpose (a key bind) sits still and never counts as a drag. `FRACTAL_EDGE_DRAG=off`
disables all of it; `FRACTAL_EDGE_DEBUG=1` logs `float event …` and `drop target …` lines, which show
whether Hyprland floats your tile when you drag it (if it doesn't, nothing here fires). Logic and
tests: `DragDrop.js`, `tests/dragdrop.test.mjs`.

## Tabbable windows (the file explorer) and the layout drop

The file explorer merges windows into tabs when you drop one on another. So that doesn't fight the
layout's drop zones, **an explorer window carried over another explorer window is left to the
explorer** (no highlight, no drop intent); everywhere else (screen edges, any other window) the
layout drop applies as usual. To make the layout take over for explorer windows too, bind a key:

    bin/caelestia-fractal-edges layoutdrop on      # key press (a hold: press = on, release = off)
    bin/caelestia-fractal-edges layoutdrop off
    bin/caelestia-fractal-edges layoutdrop toggle  # or a single toggle key

A window counts as tabbable when its title starts with `Files #`.

## Zoom on small apps, and how zooming looks

- **Zoom on a card's app.** A card never takes focus, so `zoom-in` (the 3-finger swipe up) used to
  zoom into whatever was focused before. (A first fix focused the window on hover, but Hyprland
  warps the cursor to a window when it is focused, which teleported the pointer.) Now the zoom-in
  gestures read the pointer position (`hl.get_cursor_pos()`) and send the layout `zoom-at <x> <y>`,
  which zooms into the window under the pointer without touching focus. Keyboard `zoom-in` still
  uses the focused window.
- **Camera zoom.** Windows outside the view used to be parked in the top-left corner, so a zoom flew
  every other window to that corner. With the updated layout engine (`park = "camera"`, the new
  default) they leave the screen in their own direction, as a real camera zoom would, and slide back
  in from there on zoom-out; they still overlap their monitor by a few pixels so the map can capture
  them. `fractal.setup({ park = "corner" })` brings the old behaviour back.

## Cards follow their windows

- **Zoom / reflow:** when a card's tile changes, the card travels there with the *compositor's own
  animation*: the duration and bezier of your `windowsMove` animation (resolved through
  `windows` / `global` as Hyprland does, read from `hyprctl animations -j`), started the moment the
  layout changes. It moves in step with its window and needs no polling, so there is no lag. If
  Hyprland animations are off, it moves instantly. `FRACTAL_EDGE_FOLLOW=off` makes it jump instead.
- **A window being dragged** is a floating window under the pointer, so its card follows by sampling
  its position (about every 16 ms) with a short glide. A window never hides its own card.
- **Workspace switch:** the old workspace's cards slide out and the new one's slide in, using your
  workspace animation (style, speed and bezier read from `hyprctl animations -j`: `slide` horizontal,
  `slidevert` vertical, other styles don't move). Cards made during a slide are simply there instead
  of fading in. `FRACTAL_EDGE_WS_SLIDE=off` disables it.

## Dragging a window to another workspace

Drag a window to the extreme left or right edge of the screen and hold it there: a glowing strip
with "Workspace N" and a fill shows the hold time, and then the window is moved to the previous /
next workspace (and you go with it). The first workspace has no "previous". The layout lets go of
the window's slot on the old workspace first (`drag-release`).

- `FRACTAL_EDGE_WS_EDGE=off` turns it off; `FRACTAL_EDGE_WS_EDGE_PX` (default 24) is the strip's
  width and `FRACTAL_EDGE_WS_EDGE_MS` (default 600) the hold time. The strip wins over the screen
  half/quadrant zones within its few pixels.
- The move uses Hyprland's Lua API (`hl.dsp.window.move({ workspace, follow, window })`, falling back
  to move + `hl.dsp.focus({ workspace })`) through `hyprctl eval`; I couldn't verify those names, so
  run with `FRACTAL_EDGE_DEBUG=1` and read `workspace hop result: …` in the log if nothing happens.

## Custom workspace swipe (hides the cards while you swipe)

Hyprland's native workspace swipe gives programs no signal, so the icon cards can't know it is under
way (they'd stay put while the windows slide). With the custom handler they can:

1. In `~/.config/hypr/hyprland/gestures.lua` remove or comment out your own
   `hl.gesture({ ..., direction = "horizontal", action = "workspace" })` (Hyprland keeps the first
   gesture registered for a finger count + direction).
2. In `hyprland.lua` change the setup line to
   `require("hypr.fractal_gestures").setup({ swipe_workspaces = true })`
   (`workspace_fingers = 4` and `swipe_threshold = 120` are the defaults), then `hyprctl reload`.

The gesture is a live Lua gesture (`start` / `update` / `finish`): it streams the finger motion to the
overlay with `hl.dsp.event`, which shows up here as a `custom` event. While you swipe the cards fade
out and a strip shows how far you have gone ("Workspace N", filling up to the threshold); on release
past the threshold the workspace changes with Hyprland's normal workspace animation (previous when
you swipe right, next when you swipe left), and the cards return after the slide. The windows
themselves do **not** follow the fingers: Lua can't offset a workspace.
`FRACTAL_EDGE_DEBUG=1` logs the `swipe …` events.

## Icon cards as real windows (opt-in): `FRACTAL_CARD_MODE=window`

By default a card is a layer surface, which Hyprland doesn't move with the workspace swipe, so a
native swipe slides the windows and leaves the cards behind. In window mode each card is a **floating
window** that a window rule makes undecorated and unfocusable, so the compositor moves it with the
swipe and with every workspace/zoom animation exactly like the app windows (no events, no slide code).

- Start in it with `FRACTAL_CARD_MODE=window bin/caelestia-fractal-edges restart`, or switch live:
  `bin/caelestia-fractal-edges cardmode window|layer|toggle` (quick testing; takes effect at once).
- The overlay registers the rule through `hyprctl eval` (`hl.window_rule`, match
  `title = "^fractal-edges-card "`, `float`, `no_focus`, `no_initial_focus`, `no_follow_mouse`,
  `no_shadow`, `no_blur`, `no_dim`, `decorate = false`, `border_size = 0`, `rounding = 0`; all of
  these are keys from Hyprland's window-rule docs) and again after a config reload.
- Each card window is positioned and sized with `hl.dsp.window.resize` / `.move` (absolute) through
  `hyprctl eval`, so Hyprland animates it with the same curve as the window underneath. A card fades
  in only after it has been placed. Cards of a workspace you have left stay alive (parked) so they
  slide away with it; they are re-used when you come back.
- **Side effects to look for:** the card windows are real windows (Caelestia's bar/workspace
  indicators may count or list them); clicking one relies on `no_focus` still delivering the click
  (a click zooms into the app through the layout, and hovering focuses the app's window through the
  layout, so neither needs the window to take focus); a card sits above the app's tiled window but
  may not be above other floating windows. Absolute `move` coordinates are assumed to be in the
  same global layout space as the overlay's (single monitor at 0,0 is the safe case).
- The handles, drop zones and floating-window clipping ignore card windows (title prefix).
- The window-mode path hides a card while its window is being dragged and during the custom
  workspace swipe; the layer-mode follow/slide code is not used.

### Window mode: placement, animations and the Caelestia bar

- **No flash in the middle of the screen.** A new window is opened wherever the compositor likes
  (the centre), so the first placement is *instant* (the window's animations are switched off for
  it through `hl.dsp.window.set_prop({ prop = "no_anim" })` and back on right after), and the card
  stays invisible until the compositor reports the window at its place. A card whose tile changes
  (reflow, zoom) is moved with the normal animation.
- **No stuck cards.** After every move the overlay asks the compositor where the window is, and
  keeps re-sending the placement until it is there (a move that did not take is repeated after the
  animation should have finished).
- **The bar does not count them.** The window rule tags card windows `hide_in_bar`, which is already in
  Caelestia's default `bar.workspaces.ignoredTags`. If you changed that list in
  `~/.config/caelestia/shell.json`, add `"hide_in_bar"` back (or any tag, then change the tag in
  `Seams.cardWindowRuleCommand()` to match).

### Window mode: diagnosing it

`bin/caelestia-fractal-edges doctor` lists the card windows (floating?, tags, position, size,
workspace) and the last window-rule results. The rules are registered as four small rules (core:
float/no_focus..., look: no shadow/blur/dim/decorate, shape: border_size/rounding, tag: `hide_in_bar`),
each in its own `pcall`, and each result is written to
`~/.local/state/fractal-edges/rules.log` (`ok` or `ERROR <message>`). If a card window looks like an
ordinary window (visible frame, in the middle of the screen, counted by the bar), look there first:
a key your Hyprland rejects shows up as `ERROR`, and the others still apply. A healthy card window
shows `floating=true` and `tags=["hide_in_bar…"]` in the doctor output.

Card moves are now sent as direct dispatches over the Hyprland socket the moment the layout
changes (no helper process in between), so the card starts moving with its window; the first
placement of a new card is instant and the card stays invisible until the compositor reports its
window at the right place.

### Why the card window rules did not run (fixed)

The rule snippet had a `"\n"` with the wrong escaping, which made it invalid Lua, so `hyprctl eval`
ran none of it (no rules, no `rules.log`: the card windows were then ordinary windows, centred, focusable
and counted by the bar). Every snippet sent to Hyprland is now checked with a real Lua parser in
`tests/seams.test.mjs` (when `lua5.4` is installed), and the rule snippet is executed against a stand-in
`hl`, so a syntax error like that cannot come back unnoticed.

A fading card (one whose tile grew, or whose window closed) is now removed only after its 450 ms fade
has finished (540 ms), so the fade-out is always seen.
