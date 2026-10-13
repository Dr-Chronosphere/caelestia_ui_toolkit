# Building on fractal-wm

Assessment of [cgranier/fractal-wm](https://github.com/cgranier/fractal-wm) (MIT) as the window
management half of the Trellis-style idea. Reviewed at commit `a0969a8` (2026-09-24, a single
"early, usable prototype" commit that author says runs daily on one machine).

## What it is

- A **Hyprland layout written in Lua** (`hl.layout.register`, Hyprland 0.56+ with the Lua
  config). One tree of *real* windows per workspace; the **viewport can be any node**, so you
  zoom in (the focused window plus everything split off from it fills the screen), zoom out,
  go back/forward, save named framings, and show an arbitrary set of tiles together.
- It is the same model as Trellis (see `spaces-design.md`) but on actual windows, inside the
  compositor, with no plugin and no daemon. This supersedes my earlier "Tier B" idea.
- A **map overlay** (`Map.qml` + `Model.js`) drawn with Quickshell: the tree as nested
  rectangles with live window thumbnails (`ScreencopyView`), breadcrumb, framings, selection by
  click/drag. It talks to the layout through `hyprctl dispatch 'hl.dsp.layout("…")'`.

## Does it fit Caelestia?

| Piece | Verdict |
| --- | --- |
| Lua engine (`lua/`, `bin/fractal`) | Shell-independent. Only comments and the keybinding helper mention Omarchy; the keys file already falls back to plain `hl.bind`. |
| Engine tests | Ran here: 30 + 11 Lua tests and 14 node tests all pass (Lua 5.4). No Hyprland was involved, so this proves the model, not the Hyprland glue. |
| Status contract | `$XDG_RUNTIME_DIR/fractal-wm/ws-<id>.json` (tree, viewport, focused, framings, canBack/canForward). Any shell can render it. |
| `Model.js` | Pure JS, no Quickshell. Reusable as is (MIT, keep the copyright notice). |
| `Map.qml` | Quickshell, but styled with Omarchy's `qs.Commons`/`qs.Ui`: about a dozen colour/spacing references plus 60 calls to a spacing function. Porting means swapping in `CaelestiaUI.Theme` and replacing the plugin host. |
| Caelestia shell | Already supports Lua-config Hyprland (`Hypr.usingLua`), so Lua users are a supported case. |

## The real constraint

fractal-wm needs **Hyprland 0.56+ running the Lua configuration**. Caelestia's dots have used
hyprlang (`hyprland.conf`). If you run hyprlang, using this means migrating your Hyprland config
to Lua first. That is the gating question; everything else is ordinary work.

## Gaps versus the screenshot

From upstream's own USAGE.md: no tab bar, no mouse docking or drag, zoom is Hyprland's
geometry animation rather than a camera zoom, multi-monitor untested (hidden windows are parked
transparent in a monitor corner and can land on a neighbour), framings are lost across a
Hyprland restart or a layout switch.

## Progress

- **Step 2 done (untested on a live system): `apps/fractal-map`** is a Caelestia port of the map
  overlay. `Model.js` and its tests are vendored unchanged, `MapView.qml` is the upstream
  interaction logic on `CaelestiaUI.Theme` (pure QtQuick, tested headlessly with upstream's
  fixture), `shell.qml` is the Quickshell wiring, `bin/caelestia-fractal-map` toggles it.
  Setup for a Lua-config system is in `apps/fractal-map/README.md`.

- **Mouse/touch resize**: Hyprland's `resize_on_border` cannot reach a Lua layout (the layout
  API has only `recalculate` and `layout_msg`). `integration/fractal-wm-edge-resize.patch` adds an
  `edge` command and node boxes to the status file (tests pass on a fresh upstream checkout);
  `apps/fractal-edges` is the overlay of draggable seam handles. See its README.

- **One-command setup**: `bin/caelestia-fractal-setup install|check` (tested in a throwaway `$HOME` by
  `integration/test-setup.sh`, including loading the resulting `hyprland.lua` in a Lua VM).

## Proposed work, in order

1. **Install and try the engine as is** on your system (no code from us): `fractal on`, zoom,
   framings. Confirms the Lua requirement and that it feels right.
2. **Caelestia Map overlay**: port `Map.qml` onto the toolkit (Theme, components), reusing
   `Model.js`; launched like our other apps and bound to a key.
3. **Bottom bar** like the screenshot (Overview, Desktop, framing chips, back/forward, Map) as a
   toolkit component reading the status JSON; possibly integrated with the Caelestia bar.
4. **Caelestia key bindings** in whichever config format you use.
5. Longer term, contribute upstream or fork: tab bar, mouse docking, multi-monitor.
6. Folder-as-space: framings named after folders, opening the file manager there.

Not planned: the in-process QML workspace ("Tier A") from `spaces-design.md`. fractal-wm
gives the real-window version of the idea, so Tier A is only worth doing later for toolkit apps
that want to be embedded in it.
