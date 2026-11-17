-- Logic tests for GranolaQuickNote against a mocked `hs`. Pure Lua; no Hammerspoon, no
-- Granola, no deep links are ever opened (urlevent is a stub).
-- Run: lua tests/test_spoon.lua   (from the repo root)
local fails, passes = 0, 0
local function check(name, cond)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. name) end
end

local W = {}  -- world state, reset per test
local function reset()
  W = { now = 1000, timers = {}, urls = {}, alerts = {}, running = true, installed = true,
        windows = { { id = 7, w = 1200, h = 800 } }, spaces = { [7] = 5 }, visible = { [1] = true },
        gotoOK = true, gotoCalls = 0, frontmost = nil, tapEnabled = true, tapStarts = 0,
        activated = 0, launched = 0, accessibility = true, logs = {} }
end
local function advance(dt)
  W.now = W.now + dt
  local due = {}
  for i = #W.timers, 1, -1 do
    local t = W.timers[i]
    if t.at <= W.now and not t.stopped then table.remove(W.timers, i); due[#due + 1] = t end
  end
  table.sort(due, function(a, b) return a.at < b.at end)
  for _, t in ipairs(due) do
    t.fn()
    if t.every and not t.stopped then t.at = W.now + t.every; W.timers[#W.timers + 1] = t end
  end
end
local function run(sec) for _ = 1, sec * 10 do advance(0.1) end end

local tapFn
local function mock()
  hs = {
    spoons = { scriptPath = function() return "/spoon/" end },
    configdir = "/tmp/gqn-test",
    keycodes = { map = { f19 = 80 } },
    alert = { show = function(m) W.alerts[#W.alerts + 1] = m end },
    fs = { attributes = function(p, what) if what == "size" then return 0 end
      if what == "mode" and not W.noHelper then return "file" end; return nil end },
    timer = {
      secondsSinceEpoch = function() return W.now end,
      doAfter = function(d, fn) local t = { at = W.now + d, fn = fn }; W.timers[#W.timers + 1] = t
        return { stop = function() t.stopped = true end } end,
      doEvery = function(d, fn) local t = { at = W.now + d, fn = fn, every = d }; W.timers[#W.timers + 1] = t
        return { stop = function() t.stopped = true end } end,
    },
    accessibilityState = function() return W.accessibility end,
    application = {
      get = function() return W.running and { unhide = function() end, activate = function() W.activated = W.activated + 1 end,
        allWindows = function() return {} end } or nil end,
      pathForBundleID = function() return W.installed and "/Applications/Granola.app" or nil end,
      launchOrFocusByBundleID = function() W.launched = W.launched + 1; return true end,
    },
    urlevent = { openURLWithBundle = function(u) W.urls[#W.urls + 1] = u; return true end },
    spaces = {
      windowSpaces = function(id) return W.spaces[id] and { W.spaces[id] } or {} end,
      activeSpaces = function() return W.visible end,
      spaceType = function() return "user" end,
      gotoSpace = function(id) W.gotoCalls = W.gotoCalls + 1
        if W.gotoOK then W.visible = { [1] = id }; return true end; return false, "boom" end,
    },
    window = {
      get = function(id) for _, w in ipairs(W.windows) do if w.id == id then
        return { focus = function() W.frontmost = id end } end end end,
      frontmostWindow = function() return W.frontmost and { id = function() return W.frontmost end } end,
    },
    task = { new = function(_, cb)
      return { start = function() local out = {}
        for _, w in ipairs(W.windows) do out[#out + 1] = w.id .. " " .. w.w .. "x" .. w.h .. " t" end
        cb(0, table.concat(out, "\n")) end } end },
    eventtap = {
      new = function(_, fn) tapFn = fn
        return { start = function(self) W.tapStarts = W.tapStarts + 1; W.tapEnabled = true; return self end,
          stop = function() W.tapEnabled = false end, isEnabled = function() return W.tapEnabled end } end,
      event = { types = { keyDown = 10, keyUp = 11 }, properties = { keyboardEventAutorepeat = 8 } },
    },
  }
  io.open = (function(orig) return function(p, m) if p:find("gqn-test") then return nil end; return orig(p, m) end end)(io.open)
end

local function press(code, autorepeat)
  local function ev(t) return { getKeyCode = function() return code end, getType = function() return t end,
    getProperty = function() return autorepeat and 1 or 0 end } end
  local down = tapFn(ev(10)); local up = tapFn(ev(11))
  return down, up
end

local function loadSpoon()
  reset(); mock()
  local f = assert(loadfile("GranolaQuickNote.spoon/init.lua"))
  return f()
end

-- 1. basic fire, swallows both events, ignores other keys
do local s = loadSpoon(); s:configure({ windowHelper = "/h", logPath = false }):start()
  local d, u = press(176); check("swallow keyDown", d == true); check("swallow keyUp", u == true)
  local d2 = press(12); check("other key passes", d2 == false)
  run(1); check("one link", #W.urls == 1)
  check("link has transcribe", W.urls[1]:find("auto_transcribe=1", 1, true) ~= nil)
  check("window focused", W.frontmost == 7)
end
-- 2. autotranscribe off
do local s = loadSpoon(); s:configure({ autoTranscribe = false, logPath = false }):start(); press(176); run(1)
  check("no transcribe param", not W.urls[1]:find("auto_transcribe", 1, true)) end
-- 3. key repeat and cooldown
do local s = loadSpoon(); s:configure({ logPath = false }):start()
  press(176, true); run(1); check("autorepeat ignored", #W.urls == 0)
  press(176); press(176); run(1); check("double press within cooldown = 1 link", #W.urls == 1)
  run(3); press(176); run(1); check("press after cooldown fires again", #W.urls == 2)
end
-- 4. cold start: launch first, link only after window appears
do local s = loadSpoon(); W.running = false; W.windows = {}
  s:configure({ logPath = false }):start(); press(176); run(2)
  check("launched app", W.launched == 1); check("no link before window", #W.urls == 0)
  W.windows = { { id = 9, w = 1200, h = 800 } }; run(4)
  check("link after window", #W.urls == 1)
end
-- 5. cold start timeout sends link anyway
do local s = loadSpoon(); W.running = false; W.windows = {}
  s:configure({ logPath = false, launchWaitSeconds = 5 }):start(); press(176); run(8)
  check("timeout still sends link", #W.urls == 1)
end
-- 6. not installed
do local s = loadSpoon(); W.installed = false; s:configure({ logPath = false }):start(); press(176); run(30)
  check("no link when not installed", #W.urls == 0 and W.launched == 0); check("alerts", W.alerts[#W.alerts]:find("not installed") ~= nil)
end
-- 7. other Space: switches, focuses
do local s = loadSpoon(); W.spaces[7] = 5; s:configure({ logPath = false }):start(); press(176); run(2)
  check("gotoSpace called", W.gotoCalls == 1); check("focused after switch", W.frontmost == 7) end
-- 8. gotoSpace keeps failing: retries, never claims success
do local s = loadSpoon(); W.gotoOK = false; s:configure({ logPath = false, focusAttempts = 3 }):start(); press(176); run(5)
  check("retried goto", W.gotoCalls >= 2); check("link still sent once", #W.urls == 1) end
-- 9. watchdog restarts a disabled tap
do local s = loadSpoon(); s:configure({ logPath = false }):start(); W.tapEnabled = false; run(6)
  check("watchdog restarted tap", W.tapEnabled and s:status().tapRestarts >= 1) end
-- 10. stop gives key back
do local s = loadSpoon(); s:configure({ logPath = false }):start(); s:stop(); check("stopped", not W.tapEnabled)
  W.tapEnabled = false; run(10); check("watchdog stopped", W.tapEnabled == false) end
-- 11. key names, lists, bad key
do local s = loadSpoon(); s:configure({ keyCode = "f19", logPath = false }):start()
  check("key name", select(1, press(80)) == true)
  s:configure({ keyCode = { 176, 80 } }):start(); check("key list", select(1, press(176)) == true and select(1, press(80)) == true)
  s:configure({ keyCode = "nope" }):start(); check("bad key: no tap, no crash", s.tap == nil)
end
-- 12. unknown option does not crash
do local s = loadSpoon(); s:configure({ keyCod = 1 }); check("typo ignored", s.cfg.keyCod == nil) end
-- 13. reload (start twice) leaves one live tap
do local s = loadSpoon(); s:configure({ logPath = false }):start():start(); check("restart ok", W.tapEnabled) end
-- 14. fallback without helper when helper missing
do local s = loadSpoon(); W.noHelper = true; s:configure({ logPath = false }):start(); check("helper reported missing", s:status().helperBuilt == false) end

print(("%d passed, %d failed"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)
