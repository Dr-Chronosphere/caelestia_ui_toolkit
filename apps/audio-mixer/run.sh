#!/usr/bin/env sh
# Launch the mixer with Quickshell, pointing it at the toolkit module.
here=$(cd "$(dirname "$0")" && pwd)
export QML_IMPORT_PATH="$here/../../qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
exec qs -p "$here" "$@"
