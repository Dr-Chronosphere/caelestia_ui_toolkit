#!/usr/bin/env bash
# Exercise bin/caelestia-fractal-edges stop/restart against a fake `qs`, checking that it
# shuts down gracefully (ipc quit), falls back to kill, and waits before starting again.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
log="$tmp/qs.log"
state="$tmp/alive"          # exists while the fake overlay "runs"

# Fake qs: records args; `ipc call ... isRunning` succeeds while alive; `quit`/`kill` mark it dead
# after a short delay (so the launcher's wait loop is exercised); `--daemonize` marks it alive.
cat > "$tmp/bin/qs" <<FAKE
#!/usr/bin/env bash
echo "\$*" >> "$log"
case "\$*" in
  *"ipc call fractaledges isRunning"*) [ -e "$state" ] && exit 0 || exit 1 ;;
  *"ipc call fractaledges quit"*) [ "\${FAKE_QUIT_FAILS:-0}" = 1 ] && exit 1; (sleep 0.3; rm -f "$state") & exit 0 ;;
  *" kill"*) (sleep 0.3; rm -f "$state") & exit 0 ;;
  *"--daemonize"*) touch "$state"; exit 0 ;;
esac
FAKE
chmod +x "$tmp/bin/qs"
# Fake pgrep: "running" while the state file exists.
cat > "$tmp/bin/pgrep" <<FAKE
#!/usr/bin/env bash
[ -e "$state" ]
FAKE
chmod +x "$tmp/bin/pgrep"
export PATH="$tmp/bin:$PATH"
fail() { echo "FAIL $*"; cat "$log"; exit 1; }

touch "$state"
"$repo/bin/caelestia-fractal-edges" stop
grep -q "ipc call fractaledges quit" "$log" || fail "stop uses the graceful quit"
grep -q " kill" "$log" && fail "no kill needed when quit works"
[ -e "$state" ] && fail "stop waits for exit"

: > "$log"; touch "$state"
"$repo/bin/caelestia-fractal-edges" restart
grep -q "ipc call fractaledges quit" "$log" || fail "restart quits gracefully first"
[ -e "$state" ] || fail "restart started a new instance after the old one exited"
[ "$(grep -n 'quit' "$log" | head -1 | cut -d: -f1)" -lt "$(grep -n 'daemonize' "$log" | head -1 | cut -d: -f1)" ] || fail "quit happens before start"

: > "$log"; touch "$state"
FAKE_QUIT_FAILS=1 "$repo/bin/caelestia-fractal-edges" stop
grep -q " kill" "$log" || fail "falls back to kill when quit fails"

: > "$log"; rm -f "$state"
"$repo/bin/caelestia-fractal-edges" stop      # nothing running: must not hang or fail
echo "launcher test passed"
