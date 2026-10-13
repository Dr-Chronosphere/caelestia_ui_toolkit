# Files

Caelestia-styled file manager, inspired by a Finder-like spatial layout: places sidebar,
breadcrumb path bar, icon grid (or list), status bar.

- Browse with double-click / Enter, Back/Forward/Up, breadcrumb, places sidebar
  (Home plus whichever of Desktop, Documents, Downloads, Pictures, Music, Videos exist)
- Icon grid with image thumbnails, or a list with kind/size/modified columns
- Filename search in the current folder (folders are hidden while searching: Qt's name filters
  only apply to files), hidden-file toggle, sort cycling (name → modified → size → type)
- Opening a file runs `xdg-open`

Shortcuts: `Alt+←/→/↑` navigate, `Ctrl+F` search, `Ctrl+H` hidden files, `Esc` clear search,
`Backspace` up, arrow keys move the selection, `Enter` opens.

## Run

```sh
bin/caelestia-files            # single instance
apps/files/run.sh              # dev launcher
```

## Design

- `FilesView.qml`: the whole UI. Pure QtQuick + `Qt.labs.folderlistmodel` (no Quickshell, no
  shell plugin), so it can be tested headlessly. Opening a file is a signal (`openRequested`).
- `logic/Files.js`: pure helpers (paths, breadcrumbs, file kinds, sizes, places), unit-tested.
- `shell.qml`: Quickshell wrapper: window + `xdg-open`.

## Tests

```sh
node apps/files/tests/logic.test.mjs
python3 apps/files/tests/run_ui_tests.py        # needs PySide6; builds a temp directory tree
```

## Not there yet

Rename/delete/copy/move/new folder, trash, drag and drop, context menu, multi-select, tabs,
mounted drives, folder item counts, rounded image thumbnails were only checked with the software
renderer (the GPU mask path is untested), and nothing has been run in a live Quickshell session.
