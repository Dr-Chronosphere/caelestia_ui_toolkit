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

## Tabs and merging windows

Every explorer window has tabs (`Ctrl+T` new, `Ctrl+W` close, `Ctrl+Tab` / `Ctrl+Shift+Tab` cycle,
middle-click a tab to close it). Run `bin/caelestia-files [path]` again and it opens another window
in the running instance (`--tab [path]` opens a tab in the newest window instead).

**Drag one explorer window over another** (Super+drag, or however you move windows) and the window
underneath blurs and offers to take the tabs; leave it there for about half a second and the two
become one window with both windows' tabs (each tab keeps its folder and back/forward history).

- The compositor moves the window, so the app can't see the pointer. It samples window geometry
  (`hyprctl clients -j`, every 70 ms, only while two or more explorer windows exist) and decides a
  window is "carried" when its position changes without its size changing, and "over" another when
  its centre is inside that window on the same workspace. The merge happens when the carried window
  has been still for `FILES_MERGE_SETTLE` ms (default 450). So pausing over a window merges; keep
  moving to avoid it.
- For an exact trigger, bind the mouse-button release to `bin/caelestia-files drop`, which merges the
  carried window into the one it's over at once.
- `FILES_MERGE=off` disables the sampling. Windows are matched by the `Files #N` in their title.
- `FILES_START=/some/dir` sets the first window's folder.
- Logic: `logic/Tabs.js` (tab list) and `logic/Merge.js` (drag detection), tested by
  `tests/tabs.test.mjs`; `tests/run_tabs_ui_tests.py` covers the tab UI and merge headlessly.

## Look (after the reference design)

- **Header:** the folder's name as a title, with search, sort, hidden-files and an "Icon view" / "List
  view" toggle on the right; navigation and the breadcrumb on the second row.
- **Tiles:** folders show their item count ("4 items"), files their kind and size ("PDF · 2 kB");
  images get thumbnails.
- **Translucent window:** `FILES_OPACITY` (0.3 to 1, default 0.92). The window is see-through; for
  the desktop behind it to be *blurred* too, add a Hyprland window rule with blur for the explorer,
  for example (Lua config) `hl.window_rule({ match = { title = "^Files #" }, blur = true })`. The
  exact rule syntax depends on your Hyprland version, so check it against your config's other
  window rules.
