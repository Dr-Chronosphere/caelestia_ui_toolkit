# Trellis-style spatial workspace on Caelestia: design notes

Status: **design only, nothing built yet. See `fractal-wm-integration.md`: an existing project (fractal-wm) implements the real-window version of this idea on Hyprland, which changes the plan below.** Based on reading the Trellis source
(`DanFessler/trellis`, commit `9d1da36`), mainly `packages/core/src/model/{types,spatial}.ts`,
`packages/core/src/runtime/navigation.ts` and `examples/desktop/`.

Licence note: Trellis is free for non-commercial use only (sponsorship/enterprise licence
otherwise). I studied the architecture; any implementation here should be written independently
from these notes, not copied. Decide on the licence of this repo before publishing it.

## What Trellis actually does

The screenshot is the `examples/desktop` demo. Its "spaces" are **not** separate workspaces:

- **One world document** (serializable): a tree of `split`s (weighted rows/columns), `panel`s
  (tab groups of views) and exactly one `stage`; plus `floating` panels (rects as fractions of
  the stage), `hidden` panels (minimized, with a restore target) and a `views` table
  (`type` + params).
- In the demo the **Desktop is the stage**; Finder windows are floating on it. The green window
  button *docks* a window beside the stage as a panel in the tree (that is "Projects",
  "Reference", "Studio" in the screenshot).
- **A camera** is a rect in world fractions (0-1) driven by a spring. `frame(node)` zooms the
  camera to a node or a contiguous range of siblings; `overview()` frames the root;
  `maximize` remembers and restores the previous framing; visits form a history; framings can be
  saved. Zoom is rubber-banded (about 1.35x, 30% overshoot) and springs to the best fit.
- **Views keep running** while hidden or zoomed away. Content has a `minSize` and scales down
  below it ("interactive" or "inert" while scaled).
- The **minimap** is just an SVG of the tree's rects plus the live camera rect; clicking a tile
  frames it.
- The **bottom bar** is outside the workspace: Overview / Desktop / saved framings / Map toggle.

## What this means on Hyprland

Real windows (Firefox, a terminal) belong to the compositor and cannot be placed inside a
zoomable canvas. Our own apps can. That suggests two tiers:

### Tier A: in-process spatial workspace for toolkit apps (buildable and testable)

A `Workspace` QML component that implements the Trellis ideas natively:

- JS model: tree + stage + floating + hidden + views, as in the document above (plain JSON, so
  it can be persisted and unit-tested with node like our other logic).
- A world `Item` scaled/translated by a spring-animated camera; each panel is laid out from the
  tree's fractional rects; QML pointer input stays live at any zoom because transforms apply to
  hit testing.
- View types registered by name: `files` (our file manager, already built as a standalone
  `FilesView`), `mixer` (audio), later notes and others. Singleton or per-folder instances.
- Minimap and bottom bar as toolkit components.
- Hosted in one Quickshell window (or a full-screen layer), so it is a Caelestia app like the
  others. The folder-as-panel look in the screenshot comes for free: each docked `files` view is
  just a folder.

### Tier B: Hyprland integration (needs verification on a live system)

- Overview of real windows: Quickshell's Hyprland module for workspaces/clients and dispatch,
  Wayland screencopy for live thumbnails. A "space" could map to a named Hyprland workspace.
- Dragging real windows between spaces: `movetoworkspacesilent`.
- Nested spaces cannot be native; emulate with names (`Studio/Projects`) grouped in the UI.
- Existing plugins (hyprexpo, hyprscrolling) already cover parts of overview/scrolling inside
  the compositor and should be evaluated before building our own.

## Open questions

- Should Tier A hold only toolkit apps, or also present real windows as thumbnails in the world
  (Tier B)? The second is a much bigger and riskier step.
- Is Tier A meant to replace the desktop (full-screen layer over the wallpaper) or be an app you
  open on demand? On-demand is far simpler and safer to start with.
- Frameless windows: Hyprland draws no title bars, so window controls (close, dock, minimize
  to dock) would be drawn by our workspace.
