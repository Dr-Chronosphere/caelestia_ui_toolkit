# Fractal Map (Caelestia port)

A clickable map of your [fractal-wm](https://github.com/cgranier/fractal-wm) window tree, drawn
in Caelestia style. Click a window or container to zoom the viewport there, right-click for its
parent, shift-click or drag to pick several tiles and show them together, jump through the
breadcrumb or saved framings. Live window thumbnails when the compositor allows.

**Credit:** this is a port of `Map.qml` from fractal-wm by Carlos Granier (MIT, see
[`LICENSE.fractal-wm`](LICENSE.fractal-wm)). `Model.js` and its tests are vendored unchanged;
`MapView.qml` keeps upstream's interaction logic with Omarchy styling replaced by
`CaelestiaUI.Theme`; `shell.qml` is the Quickshell wiring.

## Requirements

- Hyprland 0.56+ with the **Lua configuration**
- fractal-wm installed and switched on for the workspace (below)
- Quickshell and this repo's `qml/` module (the launcher sets `QML_IMPORT_PATH`)

## Install

One command does the whole setup (clones fractal-wm at the commit our patch targets, applies
the edge-resize patch, links its Lua modules into `~/.config/hypr`, installs the keybindings with
`SUPER+CTRL+Y` opening this map, installs the `fractal` CLI, and adds the `require` line and
Lua `package.path` to your `hyprland.lua` after a backup):

```sh
/path/to/caelestia_ui_toolkit/bin/caelestia-fractal-setup install
/path/to/caelestia_ui_toolkit/bin/caelestia-fractal-setup check      # what is missing, if anything
hyprctl reload && hyprctl configerrors && fractal on
```

`module 'hypr.fractal' not found` means the Lua modules are not linked into `~/.config/hypr/`
or `~/.config` is not on Lua's `package.path`; `check` reports both. Needs `git` and `jq`
(and `notify-send` for `fractal show`).

Check for key clashes with your existing Caelestia bindings (`hyprctl binds`); Super+Ctrl is
upstream's default chord. To start the overlay at login so the first toggle is instant, add
`/path/to/caelestia_ui_toolkit/bin/caelestia-fractal-map close` to your Hyprland autostart.

## Use

`caelestia-fractal-map [toggle|open [workspace]|close]`. Keys inside the map are listed in its
footer: arrows move, Enter/click zoom, Space/shift-click/drag select, Backspace hides a tile,
Shift+arrows drive zoom/back/forward, Home overview, 1-9 framings, T thumbnails, Esc.

## Tests

```sh
node --test apps/fractal-map/tests/model.test.js        # upstream's 14 model tests
python3 apps/fractal-map/tests/run_ui_tests.py          # the view, driven with upstream's fixture (PySide6)
```

## Not verified

Everything Hyprland- or Quickshell-specific is untested here, because the build environment has
neither: the `qs` launcher/IPC flow, `hyprctl` calls, the status-file watcher, layer-shell
overlay, and live thumbnails (`ScreencopyView`). The headless tests cover the view's behaviour
against upstream's fixture, not the integration. Expect small fixes on first run.
