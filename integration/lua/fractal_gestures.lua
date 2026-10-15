-- fractal_gestures.lua: touchpad gestures for the fractal layout. Part of caelestia_ui_toolkit.
--
--   require("hypr.fractal_gestures").setup()                     -- defaults below
--   require("hypr.fractal_gestures").setup({ fingers = 3, special_fingers = 4, mod_fingers = 2,
--                                           mods = "SUPER", special = "special", pinch = false })
--
-- Touchpad (Hyprland's native gestures):
--   `fingers` (3) swipe UP            -> zoom-in  (the focused window fills the view)
--   `fingers` (3) swipe DOWN          -> zoom-out
--   `special_fingers` (4) swipe up or down -> toggle the special workspace (scratchpad) `special`
--   `workspace_fingers` (4) swipe left or right -> switch workspace (Hyprland's native workspace swipe)
--   the same zoom swipes with `mod_fingers` (2) fingers while `mods` are held (mod_fingers = false
--     to skip)
--   pinch = true also binds pinch out/in with `fingers` fingers to zoom-in/out (off by default)
--   Set workspace_fingers = false to leave workspace swiping to your own config. No five-finger
--   gesture is bound.
--
-- Touchscreen: Hyprland has no native touchscreen pinch. fractal_keys.lua binds a 3-finger pinch
-- through the hyprgrass plugin when it is loaded; this file only reports whether it is.
--
-- On Hyprland 0.56 a gesture's `action` is a string or a Lua FUNCTION (not a dispatcher object), so
-- the layout command is wrapped in a function. Every hl.gesture call is wrapped in pcall, so a value
-- the running Hyprland rejects (an unknown direction, say) cannot break the rest of the config; what
-- happened is written to $XDG_STATE_HOME/fractal-wm/gestures.log (`caelestia-fractal-setup check`
-- prints it).

local M = {}

local HOME = os.getenv("HOME") or ""
local STATE_DIR = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/fractal-wm"
local log_lines = {}

local function note(fmt, ...)
  log_lines[#log_lines + 1] = string.format(fmt, ...)
end

local function flush_log()
  pcall(os.execute, string.format("mkdir -p %q", STATE_DIR))
  local f = io.open(STATE_DIR .. "/gestures.log", "w")
  if not f then return end
  f:write(os.date("%Y-%m-%d %H:%M:%S"), " fractal_gestures.setup\n")
  for _, l in ipairs(log_lines) do f:write("  ", l, "\n") end
  f:close()
end

-- An action that sends `msg` to the active workspace's layout (same path as the key bindings).
local function layout(msg)
  return function() hl.dispatch(hl.dsp.layout(msg)) end
end

local function try(label, spec)
  local ok, err = pcall(hl.gesture, spec)
  note("%s: %s", label, ok and "accepted" or ("REJECTED (" .. tostring(err) .. ")"))
  return ok
end

-- Toggle the special workspace `name`: the dispatcher if this Hyprland has it, else the built-in
-- "special" gesture action.
local function special_action(name)
  if type(hl) == "table" and type(hl.dsp) == "table" and type(hl.dsp.workspace) == "table"
      and type(hl.dsp.workspace.toggle_special) == "function" then
    return function() hl.dispatch(hl.dsp.workspace.toggle_special(name)) end, "hl.dsp.workspace.toggle_special"
  end
  return "special", "built-in special action"
end

function M.setup(opts)
  opts = opts or {}
  log_lines = {}
  local fingers = opts.fingers or 3
  local special_fingers = opts.special_fingers
  if special_fingers == nil then special_fingers = 4 end
  local workspace_fingers = opts.workspace_fingers
  if workspace_fingers == nil then workspace_fingers = 4 end
  local mod_fingers = opts.mod_fingers
  if mod_fingers == nil then mod_fingers = 2 end
  local mods = opts.mods or "SUPER"
  local special = opts.special or "special"

  if type(hl) ~= "table" or type(hl.gesture) ~= "function" then
    note("hl.gesture is not available in this Hyprland: touchpad gestures not installed")
  else
    try(fingers .. "-finger swipe up -> zoom-in", { fingers = fingers, direction = "up", action = layout("zoom-in") })
    try(fingers .. "-finger swipe down -> zoom-out", { fingers = fingers, direction = "down", action = layout("zoom-out") })
    if special_fingers then
      local act, how = special_action(special)
      try(special_fingers .. "-finger vertical swipe -> toggle special workspace '" .. special .. "' (" .. how .. ")",
        { fingers = special_fingers, direction = "vertical", action = act })
    end
    if workspace_fingers then
      try(workspace_fingers .. "-finger horizontal swipe -> switch workspace",
        { fingers = workspace_fingers, direction = "horizontal", action = "workspace" })
    end
    if mod_fingers then
      try(mod_fingers .. "-finger swipe up + " .. mods .. " -> zoom-in",
        { fingers = mod_fingers, direction = "up", mods = mods, action = layout("zoom-in") })
      try(mod_fingers .. "-finger swipe down + " .. mods .. " -> zoom-out",
        { fingers = mod_fingers, direction = "down", mods = mods, action = layout("zoom-out") })
    end
    if opts.pinch then
      try(fingers .. "-finger pinch out -> zoom-in", { fingers = fingers, direction = "pinchout", action = layout("zoom-in") })
      try(fingers .. "-finger pinch in -> zoom-out", { fingers = fingers, direction = "pinchin", action = layout("zoom-out") })
    end
  end

  if type(hl) == "table" and type(hl.plugin) == "table" and hl.plugin.hyprgrass then
    note("touchscreen pinch: hyprgrass is loaded (fractal_keys.lua binds the 3-finger pinch)")
  else
    note("touchscreen pinch: hyprgrass is not loaded, so no touchscreen pinch (Hyprland has none natively)")
  end

  flush_log()
  return M
end

return M
