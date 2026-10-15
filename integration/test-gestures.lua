-- Test integration/lua/fractal_gestures.lua against a fake `hl`. Run: lua5.4 integration/test-gestures.lua
package.path = "integration/lua/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_getenv = os.getenv
os.getenv = function(k) if k == "XDG_STATE_HOME" then return tmp end return real_getenv(k) end

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2) end end

local function fake(opts)
  opts = opts or {}
  local env = { specs = {}, dispatched = {} }
  _G.hl = {
    gesture = function(spec)
      if opts.reject and opts.reject(spec) then error("unknown direction '" .. tostring(spec.direction) .. "'") end
      env.specs[#env.specs + 1] = spec
    end,
    dispatch = function(d) env.dispatched[#env.dispatched + 1] = d end,
    dsp = { layout = function(msg) return "layout:" .. msg end },
    plugin = opts.hyprgrass and { hyprgrass = {} } or {},
  }
  package.loaded["fractal_gestures"] = nil
  return env
end
local function slurp() local f = io.open(tmp .. "/fractal-wm/gestures.log") local t = f and f:read("a") or "" if f then f:close() end return t end

test("3-finger swipe up/down zoom, 4-finger vertical toggles the special workspace, 2-finger + modifier zoom", function()
  local env = fake()
  require("fractal_gestures").setup()
  eq(#env.specs, 5, "five gestures (no pinch by default)")
  local by = {}
  for _, s in ipairs(env.specs) do by[s.fingers .. s.direction .. (s.mods or "")] = s end
  assert(by["3up"] and by["3down"] and by["4vertical"] and by["2upSUPER"] and by["2downSUPER"], "all five present")
  for _, s in ipairs(env.specs) do
    if s.fingers ~= 4 then eq(type(s.action), "function", "action is a function (0.56 rejects dispatcher objects)") end
  end
  by["3up"].action()
  by["3down"].action()
  by["2upSUPER"].action()
  eq(table.concat(env.dispatched, ","), "layout:zoom-in,layout:zoom-out,layout:zoom-in", "zoom actions send the layout commands via hl.dispatch")
  eq(by["3up"].mods, nil, "the plain 3-finger gesture has no modifier")
  for _, s in ipairs(env.specs) do assert(s.fingers ~= 5, "nothing on five fingers") end
  for _, s in ipairs(env.specs) do assert(s.direction ~= "left" and s.direction ~= "right" and s.direction ~= "horizontal", "horizontal swipes are left to the workspace swipe") end
end)

test("special workspace: uses the dispatcher when Hyprland has it, else the built-in action", function()
  local env = fake()
  hl.dsp.workspace = { toggle_special = function(name) return "toggle_special:" .. name end }
  require("fractal_gestures").setup({ special = "scratch" })
  local sp
  for _, s in ipairs(env.specs) do if s.fingers == 4 then sp = s end end
  eq(type(sp.action), "function")
  sp.action()
  eq(env.dispatched[#env.dispatched], "toggle_special:scratch")
  env = fake()
  require("fractal_gestures").setup()
  for _, s in ipairs(env.specs) do if s.fingers == 4 then sp = s end end
  eq(sp.action, "special", "falls back to the built-in 'special' action")
end)

test("options: finger counts and modifier; pinch opt-in; false skips groups", function()
  local env = fake()
  require("fractal_gestures").setup({ fingers = 4, special_fingers = 5, mod_fingers = 3, mods = "SUPER+CTRL", pinch = true })
  local seen = {}
  for _, s in ipairs(env.specs) do seen[#seen + 1] = s.fingers .. s.direction .. (s.mods or "") end
  table.sort(seen)
  eq(table.concat(seen, ","), "3downSUPER+CTRL,3upSUPER+CTRL,4down,4pinchin,4pinchout,4up,5vertical")
  env = fake()
  require("fractal_gestures").setup({ mod_fingers = false, special_fingers = false })
  eq(#env.specs, 2)
end)

test("a rejected value does not break setup, and is recorded", function()
  local env = fake({ reject = function(spec) return spec.direction == "vertical" end })
  local ok = pcall(function() require("fractal_gestures").setup() end)
  eq(ok, true, "setup survives hl.gesture raising")
  eq(#env.specs, 4, "the other gestures were still registered")
  local log = slurp()
  assert(log:find("REJECTED", 1, true), "log says what was rejected")
  assert(log:find("unknown direction 'vertical'", 1, true), "with Hyprland's own message")
end)

test("no hl.gesture at all: setup is a no-op that says so", function()
  fake()
  hl.gesture = nil
  local ok = pcall(function() require("fractal_gestures").setup() end)
  eq(ok, true)
  assert(slurp():find("hl.gesture is not available", 1, true))
end)

test("reports whether hyprgrass (touchscreen pinch) is loaded", function()
  fake({ hyprgrass = false })
  require("fractal_gestures").setup()
  assert(slurp():find("hyprgrass is not loaded", 1, true))
  fake({ hyprgrass = true })
  require("fractal_gestures").setup()
  assert(slurp():find("hyprgrass is loaded", 1, true))
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
