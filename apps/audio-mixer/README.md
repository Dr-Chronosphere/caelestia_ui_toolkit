# Audio mixer

Standalone Caelestia-styled window for PipeWire:

- **Outputs**: click to switch the default output; per-device volume and mute.
- **Simultaneous output**: tick two or more outputs, press *Play on N selected*. This creates a
  combined sink (`pactl load-module module-combine-sink`) and makes it the default.
  *Stop combining* removes it and restores the previous output.
- **Apps**: per-app volume/mute, and buttons to move each app to a specific output
  (`pactl move-sink-input`).

## Requirements

Quickshell (`qs`), PipeWire with `pipewire-pulse` (provides `pactl`). Caelestia fonts for icons.

## Run

```sh
bin/caelestia-audio-mixer          # from the repo root; refuses to open a second copy
apps/audio-mixer/run.sh            # dev launcher (allows duplicates)
```

Put `bin/` on your `PATH` (or symlink the script into `~/.local/bin`) so the shell can call it.

## Open it from the shell's audio popout

`integration/add-popout-button.sh` adds a "tune" icon to the popout that runs
`caelestia-audio-mixer`. The packaged shell is read-only system files, so first make a user copy
of it. Copy *your installed* version (not a fresh clone) so it matches the installed plugin:

```sh
# Find the installed shell (Arch/AUR: /etc/xdg/quickshell/caelestia)
pacman -Ql caelestia-shell | grep AudioPopout.qml

rmdir ~/.config/quickshell/caelestia 2>/dev/null     # remove an empty dir if you made one
mkdir -p ~/.config/quickshell
cp -r /etc/xdg/quickshell/caelestia ~/.config/quickshell/caelestia

/path/to/caelestia_ui_toolkit/integration/add-popout-button.sh \
    ~/.config/quickshell/caelestia/modules/bar/popouts/AudioPopout.qml
```

Restart the shell (`caelestia shell -k; caelestia shell -d`). Quickshell prefers the copy in
`~/.config/quickshell` over the system one. Undo with `add-popout-button.sh --revert <same path>`
or by deleting the copy.

Trade-off: a user copy does not receive QML updates from package upgrades. After upgrading
`caelestia-shell`, delete the copy and repeat the steps above.

## Design

- `services/Mixer.qml`: the only PipeWire-aware code (Quickshell `Pipewire` + `pactl`).
- `services/Logic.js`: pure helpers (command building, `pactl` JSON parsing), unit-tested.
- `MixerView.qml`: the UI, takes the service as a property so it can be tested with a mock.

## Tests

```sh
node apps/audio-mixer/tests/logic.test.mjs
python3 apps/audio-mixer/tests/run_ui_tests.py     # needs PySide6
```

## Not verified yet

Written against Quickshell's documented API but never run against a live PipeWire session:
`Mixer.qml` (node tracking, link lookup for "current output", `pactl` flows), the combined-sink
arguments (`slaves=` with a `sinks=` fallback), and the popout script on real shell versions. Expect small fixes on first run.
