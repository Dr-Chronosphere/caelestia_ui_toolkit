# Caelestia UI Toolkit

Reusable QML components for building standalone apps that look and feel like
[caelestia-shell](https://github.com/caelestia-dots/shell): Material 3 colours that follow
your wallpaper scheme, the shell's rounding/spacing/typography tokens, and its expressive
animation curves.

Pure QML (QtQuick only) apart from two optional Quickshell pieces: live scheme watching and
`AppWindow`. It does **not** depend on the shell's compiled plugin, so it works next to any
installed caelestia version.

## How theming works

The shell writes the active scheme to `$XDG_STATE_HOME/caelestia/scheme.json`
(default `~/.local/state/caelestia/scheme.json`). `Theme` watches that file through
Quickshell and updates `Theme.palette.m3*` live, so apps recolour when the scheme or wallpaper
changes. If the file or Quickshell is missing, the shell's default dark palette is used.

Sizing, font and animation tokens are the shell's *default* values, hard-coded in
`Theme.qml`. User overrides in `shell.json` are not read yet.

## Usage

Make the module importable, then import it:

```sh
export QML_IMPORT_PATH=/path/to/caelestia_ui_toolkit/qml
```

```qml
import QtQuick
import Quickshell
import CaelestiaUI

ShellRoot {
    AppWindow {
        visible: true
        implicitWidth: 400; implicitHeight: 300

        Column {
            anchors.centerIn: parent
            StyledText { text: "Hello"; font: Theme.headline.small }
            TextButton { text: "Go"; onClicked: console.log("clicked") }
        }
    }
}
```

Run the gallery: `examples/gallery/run.sh` (needs `qs`, i.e. Quickshell).

## Components (v0.1)

| Area | Types |
| --- | --- |
| Theme | `Theme` (singleton: palette, rounding, spacing, padding, fonts, icon sizes, curves, durations) |
| Animation | `Anim` (typed M3 expressive durations/curves), `CAnim` (colour transitions) |
| Basics | `StyledText`, `MaterialIcon`, `StyledRect`, `StateLayer`, `StyledTextField`, `RoundedImage` |
| Controls | `ButtonBase`, `TextButton`, `IconButton`, `StyledSwitch`, `StyledSlider` |
| Layout | `Card`, `ListRow`, `SectionHeader` |
| Window | `AppWindow` (themed `FloatingWindow`, needs Quickshell) |

Fonts (`GoogleSansFlex`, `Material Symbols Rounded`) are installed by the caelestia dots; apps
fall back to system fonts if absent.

## Tests

Headless tests load every component, apply schemes and check rendered colours. They need
PySide6 (no Quickshell):

```sh
pip install PySide6-Essentials
python3 tests/run_tests.py                          # toolkit
node apps/audio-mixer/tests/logic.test.mjs          # mixer logic
node apps/files/tests/logic.test.mjs                # file manager logic
python3 apps/files/tests/run_ui_tests.py            # file manager UI on a temp tree
python3 apps/audio-mixer/tests/run_ui_tests.py      # mixer UI with a mock service
```

## Apps

- [`apps/audio-mixer`](apps/audio-mixer): PipeWire output switching, simultaneous output and
  per-app routing. Launch with `bin/caelestia-audio-mixer`.

- [`apps/files`](apps/files): file manager (places sidebar, breadcrumbs, icon/list views, search).
  Launch with `bin/caelestia-files`.

Design notes for a Trellis-style spaces overview on Hyprland: [`docs/spaces-design.md`](docs/spaces-design.md).

## Status / known gaps

- Verified headlessly with Qt (PySide6): components load, theming updates live, layout renders.
- Not yet verified against a real Quickshell session: `SchemeFile` (file watching) and `AppWindow`.
- Missing vs the shell: press ripple, wavy slider, text fields, menus, scroll bars, transparency
  layers, `shell.json` token overrides.
- License: not chosen yet. The shell is GPL-3.0; this code is a fresh implementation of the same
  design, but decide the license deliberately before publishing.
