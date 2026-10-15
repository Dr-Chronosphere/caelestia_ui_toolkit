#!/usr/bin/env sh
# Add a "open audio mixer" icon to caelestia-shell's audio popout.
#
#   add-popout-button.sh <path/to/AudioPopout.qml>            # install
#   add-popout-button.sh --revert <path/to/AudioPopout.qml>   # restore the backup
#
# Works on a user copy of the shell (e.g. ~/.config/quickshell/caelestia), not on the
# package-owned files. Idempotent; keeps a backup next to the file as AudioPopout.qml.orig.
set -eu

revert=0
if [ "${1:-}" = "--revert" ]; then revert=1; shift; fi
file=${1:?usage: add-popout-button.sh [--revert] <path/to/AudioPopout.qml>}

[ -f "$file" ] || { echo "error: $file not found" >&2; exit 1; }

if [ "$revert" = 1 ]; then
    [ -f "$file.orig" ] || { echo "error: no backup ($file.orig)" >&2; exit 1; }
    cp "$file.orig" "$file" && rm "$file.orig"
    echo "restored $file"
    exit 0
fi

if grep -q caelestia-audio-mixer "$file"; then
    echo "already installed in $file"
    exit 0
fi
[ -w "$file" ] || { echo "error: $file is not writable; copy the shell into ~/.config/quickshell/caelestia first (see apps/audio-mixer/README.md)" >&2; exit 1; }
grep -q '^    ColumnLayout {$' "$file" || { echo "error: unexpected AudioPopout.qml layout (no top-level ColumnLayout); not modified" >&2; exit 1; }
grep -q '^import Quickshell\.Services\.Pipewire$' "$file" || { echo "error: unexpected AudioPopout.qml imports; not modified" >&2; exit 1; }

cp "$file" "$file.orig"
tmp=$(mktemp)
have_qs=0
grep -q '^import Quickshell$' "$file" && have_qs=1
awk -v have_qs="$have_qs" '
/^import Quickshell\.Services\.Pipewire$/ && !seen_import {
    if (have_qs == 0) print "import Quickshell"
    seen_import = 1
}
/^    ColumnLayout \{$/ && !done {
    print "    // Opens the standalone Caelestia audio mixer (caelestia_ui_toolkit)."
    print "    IconButton {"
    print "        anchors.top: parent.top"
    print "        anchors.right: parent.right"
    print "        anchors.margins: Tokens.padding.small"
    print "        icon: \"tune\""
    print "        type: IconButton.Text"
    print "        onClicked: Quickshell.execDetached([\"caelestia-audio-mixer\"])"
    print "    }"
    print ""
    done = 1
}
{ print }
' "$file" > "$tmp"
cat "$tmp" > "$file" && rm -f "$tmp"
echo "installed in $file (backup: $file.orig)"
