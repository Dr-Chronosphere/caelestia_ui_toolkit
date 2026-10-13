# Trellis-style "Spaces" on Caelestia: feasibility notes

Status: **design only, nothing built.** Written after looking at what Trellis actually is.

## What Trellis is

- [Trellis](https://github.com/DanFessler/trellis) (TrellisUI) is a **layout engine for web apps**
  (TypeScript, React, web components): nested panels, zoom, floating stages. Its "Desktop" demo
  (stage, dock, minimap) is a web page that *imitates* a desktop.
- TrellisWM is a separate Mac window manager built on the same idea (I could not open its site
  from the build sandbox, so details are unverified).
- Trellis is free for non-commercial use only (sponsorship/licence for commercial use). We would
  reimplement the ideas natively rather than copy code.

So Trellis itself cannot manage native Linux windows. The question is which of its *ideas* can be
done on Hyprland (Caelestia's compositor) with Quickshell.

## What is realistic

| Idea in the screenshot | On Hyprland + Quickshell | Verdict |
| --- | --- | --- |
| Named spaces ("Studio", "Projects") | Named workspaces (`workspace name:Studio`), listed/created/renamed from the shell | Yes |
| Overview: all spaces with window previews | Quickshell overlay; live thumbnails via Wayland screencopy | Yes (GPU/permission cost, needs testing) |
| Move windows between spaces by dragging | `movetoworkspacesilent` dispatch | Yes |
| "Map": zoomed-out layout of all spaces | 2D arrangement stored in our own state file; overlay animates between overview and map | Yes, as an overlay, not a compositor feature |
| Windows living *inside* a zoomable canvas | Hyprland has no canvas; windows belong to a workspace | **No** (fake with overlay transitions only) |
| Nested ("fractal") spaces | Emulate with names like `Studio/Projects`, grouped in the UI | Emulation only |
| Folder = space | Store `{space, folder}`; entering a space launches the file manager at that folder | Yes, good fit with the new file manager |

Existing Hyprland plugins (e.g. hyprexpo, hyprscrolling from hyprland-plugins) cover parts of
overview/scrolling in the compositor itself; worth evaluating before building our own.

## Proposed shape

1. `SpacesService` (Quickshell `Hyprland` module): workspaces, windows, monitors, dispatch.
2. `SpacesOverlay` (layer-shell overlay using this toolkit): overview grid, bottom bar like the
   screenshot (Overview / Desktop / + / ‹ › / "N spaces" / Map), drag windows between spaces.
3. `Map` view: pan/zoom canvas of space cards; positions persisted next to the scheme state.
4. Optional folder binding that launches `caelestia-files` in a space.

## Risks / unknowns to check first

- Live thumbnails need Wayland toplevel export support in the compositor and Quickshell
  (`ScreencopyView`); verify on your Hyprland version before designing around it.
- Persistent workspaces and names interact with how Caelestia already manages workspaces in its
  bar; the overlay must not fight it.
- Frameless windows: Hyprland draws no title bars, so traffic-light style controls would be
  app-drawn (close works; minimize/maximize are not meaningful when tiling).
