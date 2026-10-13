#!/usr/bin/env bash
# Exercise bin/caelestia-fractal-setup in a throwaway $HOME, then load the resulting
# hyprland.lua in a Lua VM with a stand-in `hl` and check the layout registers.
# Needs network (clones fractal-wm) and lua5.4. Run: integration/test-setup.sh
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME/.config/hypr"
printf -- '-- my config\nhl.config({ general = { gaps_in = 5 } })\n' > "$HOME/.config/hypr/hyprland.lua"

fail() { echo "FAIL $*"; exit 1; }
"$repo/bin/caelestia-fractal-setup" install --yes >/dev/null || fail "install"
"$repo/bin/caelestia-fractal-setup" install --yes >/dev/null || fail "second install (idempotent)"
[ "$(grep -c fractal_keys "$HOME/.config/hypr/hyprland.lua")" = 1 ] || fail "require line added once"
"$repo/bin/caelestia-fractal-setup" check | grep -q MISSING && fail "check reports missing items after install"
grep -q "caelestia-fractal-map" "$HOME/.config/hypr/fractal_keys.lua" || fail "map key rewritten"
[ -L "$HOME/.config/hypr/fractal.lua" ] && [ -e "$HOME/.config/hypr/fractal.lua" ] || fail "engine link"

cat > "$tmp/load.lua" <<LUA
local registered
local function catchall() return setmetatable({}, { __index = function() return catchall() end, __call = function() return catchall() end }) end
hl = catchall()
hl.layout = { register = function(name, provider) registered = name end }
hl.plugin = {}
hl.on = function() return { remove = function() end } end
assert(pcall(dofile, "$HOME/.config/hypr/hyprland.lua"))
assert(registered == "fractal", "layout registered")
LUA
lua5.4 "$tmp/load.lua" || fail "hyprland.lua does not load / layout not registered"
echo "setup test passed"
