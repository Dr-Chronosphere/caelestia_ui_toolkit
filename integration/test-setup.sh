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
# upgrading: an older applied patch (simulated by editing a patched file) is reverted and re-applied
sed -i 's/"edge moved"/"edge moved (older patch)"/' "$HOME/fractal-wm/lua/fractal.lua"
"$repo/bin/caelestia-fractal-setup" install --yes >/dev/null || fail "install over an older patch"
grep -q "older patch" "$HOME/fractal-wm/lua/fractal.lua" && fail "old patch left behind"
grep -q "save_soon" "$HOME/fractal-wm/lua/fractal.lua" || fail "new patch not applied"
# unrelated local changes are never touched: ignored while the patch is current,
# and a refusal (not a clobber) when the patch would need re-applying
echo "mine" >> "$HOME/fractal-wm/README.md"
"$repo/bin/caelestia-fractal-setup" install --yes >/dev/null || fail "install with an unrelated change and a current patch"
sed -i 's/"edge moved"/"edge moved (stale)"/' "$HOME/fractal-wm/lua/fractal.lua"
"$repo/bin/caelestia-fractal-setup" install --yes >/dev/null 2>&1 && fail "install should refuse: stale patch plus unrelated local changes"
grep -q mine "$HOME/fractal-wm/README.md" || fail "unrelated change was lost"
git -C "$HOME/fractal-wm" checkout -q -- README.md
"$repo/bin/caelestia-fractal-setup" install --yes >/dev/null || fail "install after the unrelated change is gone"
[ "$(grep -c fractal_keys "$HOME/.config/hypr/hyprland.lua")" = 1 ] || fail "require line added once"
"$repo/bin/caelestia-fractal-setup" check | grep -q MISSING && fail "check reports missing items after install"
grep -q "caelestia-fractal-map" "$HOME/.config/hypr/fractal_keys.lua" || fail "map key rewritten"
[ -L "$HOME/.config/hypr/fractal_gestures.lua" ] && [ -e "$HOME/.config/hypr/fractal_gestures.lua" ] || fail "gestures link"
[ "$(grep -c fractal_gestures "$HOME/.config/hypr/hyprland.lua")" = 1 ] || fail "gestures require line added once"
[ "$(grep -c 'layout = "lua:fractal"' "$HOME/.config/hypr/hyprland.lua")" = 1 ] || fail "default layout line added once"
chk=$("$repo/bin/caelestia-fractal-setup" check); case "$chk" in *"fractal is the default layout"*) ;; *) fail "check reports the default layout" ;; esac
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
