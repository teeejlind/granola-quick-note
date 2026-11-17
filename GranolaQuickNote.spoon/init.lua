--- === GranolaQuickNote ===
---
--- Press one key (default: the Mac mic key) to start a Granola note with recording.
--- Launches Granola if needed, sends its `granola://new-document` deep link, and brings
--- the window forward even when it lives on another Space.
---
--- Not affiliated with Granola. The deep link is not a documented API and may change.

local obj = {}
obj.__index = obj

obj.name = "GranolaQuickNote"
obj.version = "0.1.0"
obj.author = "TJ Lind"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/teeejlind/granola-quick-note"

obj.spoonPath = hs.spoons.scriptPath()

--- GranolaQuickNote.config
--- Variable
--- Settings table; override with `:configure({...})` before `:start()`.
---  * keyCode (number|string) - key to capture. Default 176 (mic key on many Macs). A string
---    is looked up in hs.keycodes.map, e.g. "f19". See the README for finding your keycode.
---  * autoTranscribe (boolean) - start recording when the note opens. Default true.
---  * launchWaitSeconds (number) - how long to wait for Granola's window after launching it.
---    Default 20. After this the link is sent anyway.
---  * launchSettleSeconds (number) - pause after the window appears, before sending the link.
---  * cooldownSeconds (number) - ignore presses this soon after the last one. Default 2.
---  * bundleID (string) - Granola's bundle ID. Default "com.granola.app".
---  * url (string) - override the whole deep link (ignores autoTranscribe).
---  * windowHelper (string) - path to the compiled app-windows helper. Default: bin/app-windows
---    inside the Spoon. If missing, only windows on visible Spaces can be found.
---  * focusAttempts / focusRetrySeconds (number) - how hard to try to focus the window.
---  * logPath (string|nil) - log file. Default: granola_quick_note.log in your Hammerspoon
---    config folder. Set to false to disable logging.
obj.defaults = {
  keyCode = 176,
  autoTranscribe = true,
  launchWaitSeconds = 20,
  launchSettleSeconds = 1.5,
  cooldownSeconds = 2,
  bundleID = "com.granola.app",
  url = nil,
  windowHelper = nil,
  focusAttempts = 8,
  focusRetrySeconds = 0.4,
  logPath = nil,
}

obj.cfg = {}
for k, v in pairs(obj.defaults) do obj.cfg[k] = v end

obj.state = {
  lastLaunchAt = 0,
  lastDetectedAt = nil,
  lastLaunchSucceeded = nil,
  lastFocusResult = nil,
  launchCount = 0,
}
obj.tap = nil

function obj:configure(overrides)
  for k, v in pairs(overrides or {}) do self.cfg[k] = v end
  return self
end

local function resolveKeyCode(key)
  if type(key) == "number" then return key end
  local code = hs.keycodes.map[tostring(key):lower()]
  if not code then error("GranolaQuickNote: unknown key '" .. tostring(key) .. "'") end
  return code
end

function obj:_url()
  if self.cfg.url then return self.cfg.url end
  local u = "granola://new-document?creation_source=hammerspoon"
  if self.cfg.autoTranscribe then u = u .. "&auto_transcribe=1" end
  return u
end

function obj:_helper()
  local path = self.cfg.windowHelper or (self.spoonPath .. "bin/app-windows")
  if hs.fs.attributes(path, "mode") then return path end
  return nil
end

function obj:_log(message)
  local path = self.cfg.logPath
  if path == false then return end
  path = path or (hs.configdir .. "/granola_quick_note.log")
  local file = io.open(path, "a")
  if file then
    file:write(os.date("%Y-%m-%d %H:%M:%S"), " ", message, "\n")
    file:close()
  end
end

-- The main window is the largest normal-layer window taller than 200px; Granola also has
-- thin overlay strips we don't want. Uses the CoreGraphics helper (all Spaces) when built,
-- otherwise Hammerspoon's own view (visible Spaces only).
function obj:_findMainWindowID(callback)
  local helper = self:_helper()
  if helper then
    hs.task.new(helper, function(_, stdOut)
      local bestID, bestArea = nil, 0
      for id, w, h in (stdOut or ""):gmatch("(%d+) (%d+)x(%d+)") do
        local area = tonumber(w) * tonumber(h)
        if tonumber(h) > 200 and area > bestArea then bestID, bestArea = tonumber(id), area end
      end
      callback(bestID)
    end, { self.cfg.bundleID }):start()
  else
    local app = hs.application.get(self.cfg.bundleID)
    local bestID, bestArea = nil, 0
    for _, win in ipairs(app and app:allWindows() or {}) do
      local f = win:frame()
      if f.h > 200 and f.w * f.h > bestArea then bestID, bestArea = win:id(), f.w * f.h end
    end
    callback(bestID)
  end
end

local function spaceIsVisible(spaceID)
  for _, active in pairs(hs.spaces.activeSpaces()) do
    if active == spaceID then return true end
  end
  return false
end

-- With "Switch to a Space with open windows" off, activating an app leaves its window
-- buried on another Space. Switch only the Space of the display the window lives on,
-- then focus it.
function obj:_bringForward(attempt)
  attempt = attempt or 1
  self:_findMainWindowID(function(windowID)
    local spaces = windowID and hs.spaces.windowSpaces(windowID) or {}
    local spaceID = spaces[1]

    if spaceID and not spaceIsVisible(spaceID) then
      self:_log("window " .. windowID .. " on hidden " .. tostring(hs.spaces.spaceType(spaceID))
        .. " space " .. spaceID .. "; switching")
      local ok, err = hs.spaces.gotoSpace(spaceID)
      if not ok then self:_log("gotoSpace failed: " .. tostring(err)) end
    end

    -- No Space at all: the window is hidden (closed to the menu bar). Unhide it.
    if not spaceID and attempt == 1 then
      local app = hs.application.get(self.cfg.bundleID)
      if app then app:unhide(); app:activate(true) end
    end

    local window = windowID and hs.window.get(windowID)
    if window then
      window:focus()
      self.state.lastFocusResult = "focused window " .. windowID
      self:_log(self.state.lastFocusResult .. " after attempt " .. attempt)
      return
    end

    if attempt < self.cfg.focusAttempts then
      hs.timer.doAfter(self.cfg.focusRetrySeconds, function() self:_bringForward(attempt + 1) end)
    else
      local app = hs.application.get(self.cfg.bundleID)
      if app then app:activate(true) end
      self.state.lastFocusResult = "fell back to activate (window " .. tostring(windowID)
        .. ", space " .. tostring(spaceID) .. ")"
      self:_log(self.state.lastFocusResult)
    end
  end)
end

function obj:_fire()
  local url = self:_url()
  local opened = hs.urlevent.openURLWithBundle(url, self.cfg.bundleID)
  self.state.lastLaunchSucceeded = opened
  if opened then
    self.state.launchCount = self.state.launchCount + 1
    self:_log("opened " .. url)
    hs.timer.doAfter(0.3, function() self:_bringForward(1) end)
  else
    self:_log("openURLWithBundle failed")
    hs.alert.show("Could not open Granola Quick Note", 2)
  end
end

-- A link sent during Granola's cold start can land before it has a signed-in session and
-- get dropped, so launch first and wait for the main window.
function obj:_waitForWindow(deadline)
  self:_findMainWindowID(function(windowID)
    if windowID then
      self:_log("Granola up with window " .. windowID)
      hs.timer.doAfter(self.cfg.launchSettleSeconds, function() self:_fire() end)
    elseif hs.timer.secondsSinceEpoch() < deadline then
      hs.timer.doAfter(0.5, function() self:_waitForWindow(deadline) end)
    else
      self:_log("Granola window never appeared; sending link anyway")
      self:_fire()
    end
  end)
end

function obj:_open()
  local now = hs.timer.secondsSinceEpoch()
  if now - self.state.lastLaunchAt < self.cfg.cooldownSeconds then return end
  self.state.lastLaunchAt = now
  hs.alert.show("Starting Granola Quick Note", 1)

  if hs.application.get(self.cfg.bundleID) then
    self:_fire()
  else
    self:_log("Granola not running; launching")
    hs.application.launchOrFocusByBundleID(self.cfg.bundleID)
    self:_waitForWindow(now + self.cfg.launchWaitSeconds)
  end
end

--- GranolaQuickNote:start()
--- Method
--- Start capturing the key. The key is swallowed (keyDown and keyUp), so nothing else
--- (dictation, Siri) sees it. Returns the Spoon.
function obj:start()
  self:stop()
  local keyCode = resolveKeyCode(self.cfg.keyCode)
  self.cfg.resolvedKeyCode = keyCode
  if not self:_helper() then
    self:_log("app-windows helper not built; only windows on visible Spaces can be found")
  end
  self.tap = hs.eventtap.new(
    { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp },
    function(event)
      if event:getKeyCode() ~= keyCode then return false end
      if event:getType() == hs.eventtap.event.types.keyDown
          and event:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then
        self.state.lastDetectedAt = hs.timer.secondsSinceEpoch()
        self:_open()
      end
      return true
    end
  ):start()
  return self
end

--- GranolaQuickNote:stop()
--- Method
--- Stop capturing the key and give it back to macOS.
function obj:stop()
  if self.tap then self.tap:stop(); self.tap = nil end
  return self
end

--- GranolaQuickNote:status()
--- Method
--- Returns a table for debugging: is the tap running, last key press, last launch result.
function obj:status()
  local now = hs.timer.secondsSinceEpoch()
  local s = self.state
  return {
    loaded = self.tap ~= nil,
    enabled = self.tap and self.tap:isEnabled() or false,
    keyCode = self.cfg.resolvedKeyCode,
    helperBuilt = self:_helper() ~= nil,
    secondsSinceKeyDetected = s.lastDetectedAt and now - s.lastDetectedAt or nil,
    secondsSinceLastLaunch = s.lastLaunchAt > 0 and now - s.lastLaunchAt or nil,
    lastLaunchSucceeded = s.lastLaunchSucceeded,
    lastFocusResult = s.lastFocusResult,
    launchCount = s.launchCount,
    url = self:_url(),
  }
end

--- GranolaQuickNote:focusTest()
--- Method
--- Bring Granola's window forward (switching Spaces if needed) WITHOUT opening a note or
--- starting a recording. Safe to run any time.
function obj:focusTest()
  self:_bringForward(1)
  return self
end

return obj
