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

`integration/audio-popout-launch.patch` adds a "tune" icon next to *Output device* in the popout.
It targets caelestia-shell's `modules/bar/popouts/AudioPopout.qml` and needs a manual-install copy
of the shell (the AUR package's files should not be edited):

```sh
cd ~/.config/quickshell/caelestia
git apply /path/to/caelestia_ui_toolkit/integration/audio-popout-launch.patch
```

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
arguments (`slaves=` with a `sinks=` fallback), and the shell patch. Expect small fixes on first run.
