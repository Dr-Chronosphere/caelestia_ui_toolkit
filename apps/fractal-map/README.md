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

1. **The layout engine** (from upstream; see its README for details):

   ```sh
   git clone https://github.com/cgranier/fractal-wm.git ~/fractal-wm
   cd ~/fractal-wm
   ln -s "$PWD/lua/fractal.lua"      ~/.config/hypr/fractal.lua
   ln -s "$PWD/lua/fractal_tree.lua" ~/.config/hypr/fractal_tree.lua
   cp lua/fractal_keys.lua ~/.config/hypr/fractal_keys.lua
   mkdir -p ~/.local/bin && ln -s "$PWD/bin/fractal" ~/.local/bin/fractal   # needs jq, notify-send
   ```

   Add `require("hypr.fractal_keys")` to your `hyprland.lua`, then
   `hyprctl reload && hyprctl configerrors && fractal on`.

2. **Point the map key at this overlay.** In your copy `~/.config/hypr/fractal_keys.lua`, replace
   the `SUPER + CTRL + Y` binding (the `else` branch that runs `fractal show`) with:

   ```lua
   bind("SUPER + CTRL + Y", "Fractal: map", "/path/to/caelestia_ui_toolkit/bin/caelestia-fractal-map toggle")
   ```

   Check for clashes with your existing Caelestia bindings (`hyprctl binds`); Super+Ctrl is
   the upstream default chord.

3. **Optional:** start the overlay at login so the first toggle is instant, by adding to your
   Hyprland autostart: `/path/to/caelestia_ui_toolkit/bin/caelestia-fractal-map close`
   (starts the background instance without showing it).

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
