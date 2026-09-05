-- Actually LOAD the addon and RUN its logic.
--
-- Every other harness in this repo reads the source as text: they mirror the
-- physics, they parse the tables, they count the specifiers. None of them can
-- catch the thing that actually ruins a race, which is a Lua error thrown at
-- the moment a line runs -- a nil concatenated into a string, an arithmetic on
-- a field that turned out to be optional, a method called on a widget that was
-- never built. That has bitten this addon before: `"SHORTCUT: " .. track.shortcut`
-- took the whole race start down for any track that had not defined one.
--
-- WoW runs Lua 5.1, and so does this. The addon's API surface is stubbed below
-- -- enough of it that every file loads and every pure-logic path can be driven
-- for real.
--
-- Run: lua5.1 verify-runtime.lua

-- The addon chats on load, so `print` is silenced further down. `say` is the
-- harness's own voice and is captured here before that happens.
local say = print
local failures, checks = 0, 0
local function ok(name, fn, ...)
  checks = checks + 1
  local args = { ... }
  local good, err = pcall(fn, unpack(args))
  if good then
    say(("   ok   %s"):format(name))
  else
    failures = failures + 1
    say(("  FAIL  %s\n          %s"):format(name, tostring(err)))
  end
end

-- ---------------------------------------------------------------------------
-- A WoW API stub. Widgets answer any method with a widget, so layout code runs
-- end to end without a client; anything that must return a real value is
-- listed explicitly.
-- ---------------------------------------------------------------------------
local widget = {}
--- HOW MUCH WORK ONE FRAME IS.
---
--- "Smooth" in a WoW addon is not about maths -- it is about how many widget
--- calls cross into the client per frame. A pseudo-3D road is drawn by moving
--- and tinting a few hundred textures every single frame, and that number is
--- invisible from inside the addon. Counting it here is the only way to know
--- whether a render pass got cheaper or quietly doubled.
local widgetCalls = 0
widget.__index = function(self, key)
  local fixed = rawget(widget, key)
  if fixed then
    -- Show/Hide/SetShown/SetPoint are hot too, and they are real methods below.
    if key == "Show" or key == "Hide" or key == "SetShown" or key == "SetPoint" then
      widgetCalls = widgetCalls + 1
    end
    return fixed
  end
  -- Only synthesise METHODS. Widget methods are UpperCamelCase without
  -- exception; anything else is a field the addon set on the widget itself, and
  -- handing back a function for those is how `model.akZoom` became a function
  -- and Data/Models.lua tried to multiply by it. A stub that answers every
  -- question invents faults of its own.
  if key:match("^%u") then
    widgetCalls = widgetCalls + 1
    return function(...) return self end
  end
  return nil
end
--- Every widget ever created, counted by kind.
---
--- WoW cannot destroy a frame; Hide is the whole vocabulary. So a screen that
--- builds itself again on every visit does not replace anything, it ADDS -- and
--- for the racer grid what it adds is eleven PlayerModels a time. Counting is
--- the only way to see that from outside.
local widgetsMade = {}
--- Every widget ever made, in creation order, so a window's whole tree can be
--- walked from outside it. Nothing else can answer "is anything in this window
--- printed through anything else" without a WoW client to look at.
local everyWidget = {}
local function newWidget(kind, name, parent)
  widgetsMade[kind] = (widgetsMade[kind] or 0) + 1
  local w = setmetatable({ akKind = kind, akName = name, akParent = parent,
    akShown = false, akPoints = {} }, widget)
  everyWidget[#everyWidget + 1] = w
  return w
end
function widget:GetWidth() return 1365 end
function widget:GetHeight() return 768 end
function widget:GetFrameLevel() return 1 end
function widget:GetEffectiveScale() return 1 end
function widget:IsShown() return self.akShown and true or false end
function widget:IsVisible() return self.akShown and true or false end
-- akShown starts false for every widget, so "was this ever visible" cannot be
-- read from it: a control built and never touched looks exactly like one that
-- was deliberately hidden. akHidden records the DELIBERATE act, which is the
-- only one a layout check should honour.
function widget:SetShown(v)
  self.akShown = v and true or false
  self.akHidden = not self.akShown
  return self
end
--- RECORDED SO A CHECK CAN PRESS A BUTTON.
---
--- Everything a menu does happens inside an OnClick handler. Without these the
--- harness could build a screen and measure it but never use it, so "does the
--- cup ask before it throws four races away" was not a question it could put.
--- Nothing here FIRES a handler; a check reaches for the one it means.
function widget:SetScript(name, fn)
  self.akScripts = self.akScripts or {}
  self.akScripts[name] = fn
  return self
end
function widget:HookScript(name, fn)
  self.akHooks = self.akHooks or {}
  self.akHooks[name] = self.akHooks[name] or {}
  table.insert(self.akHooks[name], fn)
  return self
end
function widget:GetScript(name)
  return self.akScripts and self.akScripts[name]
end
--- Press it, the way a mouse would.
function widget:akClick(...)
  local fn = self:GetScript("OnClick")
  assert(fn, "that control has no OnClick handler")
  return fn(self, ...)
end
function widget:Show() self.akShown, self.akHidden = true, false return self end
function widget:Hide() self.akShown, self.akHidden = false, true return self end
-- RECORDED, not swallowed. Everything else the renderer does to a widget is a
-- no-op here, which is fine for "does it run"; it is useless for "does the
-- tunnel actually have walls in it". These four are what decides whether a
-- texture is visible, so they are kept.
function widget:SetVertexColor(r, g, b, a)
  self.akColor = { r or 1, g or 1, b or 1, a or 1 }
  return self
end
--- Recorded for the same reason: WHERE a strip was put is the whole question
--- in "does the road actually reach the horizon". Both call forms appear in the
--- renderer -- (point, x, y) and (point, relativeTo, relativePoint, x, y) -- and
--- they are told apart by whether the second argument is a number.
function widget:SetPoint(point, a, b, c, d)
  self.akAnchor = point
  if type(a) == "number" then
    self.akX, self.akY = a, b
    self.akRelTo, self.akRelPoint = nil, nil
  else
    self.akX, self.akY = c, d
    -- Recorded so a control anchored to its NEIGHBOUR can still be placed:
    -- "under the name, whatever height the name turned out to be" is the whole
    -- reason these layouts are written imperatively in the first place.
    self.akRelTo, self.akRelPoint = a, b
  end
  return self
end
--- Recorded so a frame that fills its parent still has a measurable size. The
--- pause panel does this, and without it every control on it was unplaceable.
function widget:SetAllPoints(target)
  self.akAllPoints = target or self.akParent or true
  self.akAnchor = self.akAnchor or "TOPLEFT"
  self.akX, self.akY = self.akX or 0, self.akY or 0
  return self
end
function widget:SetSize(w, h) self.akWidth, self.akHeight = w, h return self end
function widget:SetWidth(w) self.akWidth = w return self end
function widget:SetHeight(h) self.akHeight = h return self end
function widget:SetAlpha(a) self.akAlpha = a return self end
function widget:GetAlpha() return self.akAlpha or 1 end
function widget:SetTexCoord(...) self.akTexCoord = { ... } return self end
-- PARENTED. These used to drop the parent on the floor, which makes "do two
-- things on the same frame sit on top of each other" unanswerable -- and that
-- is the one question a window nobody can screenshot most needs asked.
function widget:CreateTexture(...) return newWidget("Texture", nil, self) end
--- The line primitive the road's kerbs are drawn with. Its two endpoints are
--- recorded into the same akX/akY/akWidth/akHeight box every other region uses,
--- so a check that asks "where did that strip end up" gets the same answer
--- whichever primitive the renderer chose.
function widget:CreateLine(...)
  local line = newWidget("Line", nil, self)
  function line:SetThickness(t) self.akThickness = t return self end
  function line:GetThickness() return self.akThickness or 1 end
  function line:SetStartPoint(_, _, x, y)
    self.akStartX, self.akStartY = x, y
    self:akMeasure()
    return self
  end
  function line:SetEndPoint(_, _, x, y)
    self.akEndX, self.akEndY = x, y
    self:akMeasure()
    return self
  end
  function line:akMeasure()
    local x0, y0 = self.akStartX, self.akStartY
    local x1, y1 = self.akEndX, self.akEndY
    if not (x0 and x1) then return end
    local half = (self.akThickness or 1) * 0.5
    self.akAnchor = "BOTTOM"
    self.akX = (x0 + x1) * 0.5
    self.akY = math.min(y0, y1)
    self.akWidth = math.abs(x1 - x0) + half * 2
    self.akHeight = math.max(1, math.abs(y1 - y0))
  end
  return line
end
function widget:CreateFontString(...) return newWidget("FontString", nil, self) end
function widget:CreateAnimationGroup(...) return newWidget("AnimGroup") end
function widget:CreateAnimation(...) return newWidget("Anim") end
function widget:GetName() return self.akName end
function widget:GetObjectType() return self.akKind end
function widget:GetText() return self.akText or "" end
function widget:SetText(t) self.akText = t return self end
--- Recorded so a FontString has a measurable box: it has no SetSize, its width
--- comes from its string and its height from its font.
function widget:SetFont(_, size) self.akFontSize = size return self end
function widget:SetJustifyH(j) self.akJustify = j return self end
function widget:GetNumPoints() return 0 end
function widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
--- FrizQt's average uppercase advance is about 0.62 of the point size; see the
--- CELL note in Art/hud-font.js, which is calibrated against the real thing.
function widget:GetStringWidth()
  return #tostring(self.akText or "") * (self.akFontSize or 12) * 0.62
end
function widget:GetStringHeight() return 12 end
function widget:GetScale() return 1 end
function widget:GetAlpha() return self.akAlpha or 1 end
function widget:SetAlpha(a) self.akAlpha = a return self end
function widget:GetSize() return self:GetWidth(), self:GetHeight() end
function widget:GetLeft() return 0 end
function widget:GetRight() return self:GetWidth() end
function widget:GetTop() return self:GetHeight() end
function widget:GetBottom() return 0 end
function widget:GetCenter() return self:GetWidth() / 2, self:GetHeight() / 2 end
function widget:GetParent() return self.akParent end
function widget:GetID() return 0 end
function widget:GetFont() return STANDARD_TEXT_FONT, 12, "OUTLINE" end
function widget:GetTextColor() return 1, 1, 1, 1 end
function widget:GetVertexColor() return 1, 1, 1, 1 end
function widget:GetRegions() return end
function widget:GetChildren() return end
function widget:GetNumRegions() return 0 end
function widget:GetNumChildren() return 0 end
function widget:IsMouseOver() return false end
function widget:IsObjectLoaded() return true end
function widget:GetModelFileID() return 1 end
function widget:GetFacing() return 0 end
function widget:GetTexture() return self.akTexture end
function widget:SetTexture(t) self.akTexture = t return self end
function widget:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
function widget:GetEffectiveAlpha() return 1 end
function widget:GetFrameStrata() return "MEDIUM" end
function widget:GetValue() return 0 end
function widget:GetChecked() return false end

UIParent = newWidget("Frame", "UIParent")
WorldFrame = newWidget("Frame", "WorldFrame")
GameTooltip = newWidget("GameTooltip", "GameTooltip")
function CreateFrame(kind, name, parent, template)
  local f = newWidget(kind, name, parent)
  if name then _G[name] = f end
  return f
end
UISpecialFrames = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
function PlaySound() return true, 1 end
function PlaySoundFile() return true, 0 end
function StopSound() end
-- A CLOCK THAT MATCHES THE SIMULATION, not the CPU.
--
-- This was os.clock(), which is processor time -- so a check that drove ten
-- seconds of race might see two seconds pass on the clock, or twenty on a
-- slower machine. Everything timed against GetTime was therefore measured
-- against a different clock from the one the race runs on: presentation
-- deadlines expired at the wrong moment, and "how many bytes a second does
-- multiplayer send" was bytes per CPU-second, which is not a rate that exists.
--
-- The wrapper further down advances this by exactly the dt handed to
-- Race:Update, so a second of race time is a second here. It also removes the
-- last thing in the harness that varied between runs.
local clockNow = 0
function GetTime() return clockNow end
function advanceClock(by) clockNow = clockNow + by end
function GetLocale() return "enUS" end
function UnitName() return "Tester" end
function UnitFullName() return "Tester", "Testrealm" end
function UnitClass() return "Shaman", "SHAMAN", 7 end
function UnitGUID() return "Player-1-00000001" end
-- The multiplayer round-trip check needs a channel to send on; every other
-- path treats "no group" and "party" identically.
function IsInGroup() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 1 end
function GetRealmName() return "Testrealm" end
function GetCVar() return "1" end
function SetCVar() end
function InCombatLockdown() return false end
function tinsert(...) return table.insert(...) end
function tremove(...) return table.remove(...) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
--- WoW's strsplit, faithfully: it PRESERVES empty fields.
---
--- The old stub used gmatch("([^sep]*)"), which is the classic Lua trap -- a
--- pattern that can match the empty string produces a spurious empty capture
--- between every real one, so "a,b" came back as "a", "", "b", "". A stub that
--- splits differently from the client cannot find a splitting bug and can
--- invent one.
function strsplit(sep, str)
  local out = {}
  local padded = tostring(str) .. sep
  for piece in padded:gmatch("([^" .. sep .. "]*)" .. sep) do out[#out + 1] = piece end
  return unpack(out)
end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function date(fmt) return os.date(fmt) end
function debugprofilestop() return os.clock() * 1000 end
C_Timer = { After = function(_, fn) if fn then fn() end end, NewTicker = function() return newWidget("Ticker") end }
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function() return true end,
}
Enum = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return 1 end }) end })
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
BackdropTemplateMixin = {}
function GetAddOnMetadata() return "0.2.0" end
function IsAddOnLoaded() return true end
function GetScreenWidth() return 1365 end
function GetScreenHeight() return 768 end
function GetPhysicalScreenSize() return 2560, 1440 end
function CreateColor() return newWidget("Color") end
function GetItemIcon() return nil end
function UnitExists(u) return u == "player" end
function UnitIsPlayer(u) return u == "player" end
function UnitIsDeadOrGhost() return false end
function UnitRace() return "Vulpera", "Vulpera", 35 end
function UnitSex() return 2 end
function UnitLevel() return 80 end
function GetPlayerInfoByGUID() return "Vulpera", "Vulpera", "Male", "Horde", nil, "Tester" end
function SetPortraitTexture() end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function GetMouseFocus() return nil end
function GetBuildInfo() return "11.2.0", "60000", "Aug 2025", 110200 end
-- WoW ships BitLib; stock Lua 5.1 does not. Core/RNG.lua's xorshift needs
-- bxor, lshift and rshift with 32-bit wraparound.
bit = {
  bxor = function(a, b)
    local r, bitv = 0, 1
    a, b = a % 4294967296, b % 4294967296
    for _ = 1, 32 do
      local x, y = a % 2, b % 2
      if x ~= y then r = r + bitv end
      a, b, bitv = (a - x) / 2, (b - y) / 2, bitv * 2
    end
    return r
  end,
  band = function(a, b)
    local r, bitv = 0, 1
    a, b = a % 4294967296, b % 4294967296
    for _ = 1, 32 do
      local x, y = a % 2, b % 2
      if x == 1 and y == 1 then r = r + bitv end
      a, b, bitv = (a - x) / 2, (b - y) / 2, bitv * 2
    end
    return r
  end,
  lshift = function(a, n) return (a * 2 ^ n) % 4294967296 end,
  rshift = function(a, n) return math.floor(a % 4294967296 / 2 ^ n) end,
}
_G.print = function() end   -- the addon chats on load; `say` is above

-- ---------------------------------------------------------------------------
-- Load every file the .toc loads, in the order the .toc loads it.
-- ---------------------------------------------------------------------------
local AK = {}
local ADDON = os.getenv("ADDON") or "."
local files = {}
for line in io.lines(ADDON .. "/kart.toc") do
  line = line:gsub("%s+$", "")
  if line ~= "" and line:sub(1, 1) ~= "#" then
    files[#files + 1] = (line:gsub("\\", "/"))
  end
end

local loadFailures = 0
for _, rel in ipairs(files) do
  local chunk, err = loadfile(ADDON .. "/" .. rel)
  if not chunk then
    loadFailures = loadFailures + 1
    say(("  FAIL  compile %s\n          %s"):format(rel, tostring(err)))
  else
    local good, rerr = pcall(chunk, "kart", AK)
    if not good then
      loadFailures = loadFailures + 1
      say(("  FAIL  load %s\n          %s"):format(rel, tostring(rerr)))
    end
  end
end

say("Loading the addon under Lua 5.1, the version WoW runs")
say("")
say(("  %d files, %d failed to load"):format(#files, loadFailures))
say("")
failures = failures + loadFailures

if loadFailures == 0 then
  say("Driving the pure logic for real")
  say("")

  -- EVERY RACE IN THIS SUITE IS SEEDED THE SAME WAY EVERY RUN.
  --
  -- AK.RNG:FreshSeed reads GetTime(), which the stub above answers with
  -- os.clock() -- so every race the harness drove got a different seed, and
  -- every check that drives one could pass or fail on the same code. That is
  -- worse than having no check: a real regression is indistinguishable from
  -- "it did that last week too". A suite whose verdict is not reproducible
  -- cannot be used to decide anything.
  --
  -- A COUNTER, not a constant. One fixed seed would make every race in the run
  -- identical, which throws away most of what driving several of them is for.
  -- This gives the same sequence on every run and a different race each time
  -- inside it, and it covers battles too, which build their race without ever
  -- being handed an options table.
  -- Race time IS clock time in here. See the note on GetTime above.
  local realUpdate = AK.Race.Update
  function AK.Race:Update(elapsed)
    advanceClock(elapsed or 0)
    return realUpdate(self, elapsed)
  end

  local seedTicks = 0
  function AK.RNG:FreshSeed()
    seedTicks = seedTicks + 1
    -- Golden-ratio stride, so consecutive seeds are not consecutive numbers.
    return (0x2545F491 + seedTicks * 0x9E3779B9) % 4294967296
  end

  -- Saved variables and defaults, the way Core does on ADDON_LOADED.
  ok("the database initialises", function()
    AzerothKartDB = nil
    if AK.InitDatabase then AK:InitDatabase() end
    if AK.InitTuning then AK:InitTuning() end
    assert(AK.db, "no AK.db after init")
    assert(AK.db.tuning and AK.db.tuning.camDepth, "tuning did not populate")
  end)

  -- Compiling every circuit, and every branch of every circuit. This is the
  -- code path that runs the instant a race starts.
  ok("every track compiles, with all its branches", function()
    for _, track in ipairs(AK.Tracks) do
      AK.TrackBuilder:Compile(track)
      assert(track.curveTable and #track.curveTable > 0, track.id .. " has no curve table")
      assert(track.centreTable and #track.centreTable > 0, track.id .. " has no centre table")
      for _, branch in ipairs(track.branches or {}) do
        assert(branch.curveTable and #branch.curveTable > 0,
          track.id .. "/" .. tostring(branch.id) .. " has no curve table")
      end
    end
  end)

  ok("every arena compiles", function()
    for _, arena in ipairs(AK.Arenas or {}) do AK.TrackBuilder:Compile(arena) end
  end)

  -- Sampling the whole of every lap: curvature, height, width, terrain, ramps,
  -- tunnels, sections and checkpoints, at every metre.
  ok("every metre of every lap can be sampled", function()
    for _, track in ipairs(AK.Tracks) do
      for d = 0, track.length, 1 do
        AK.Math.RoadCurve(track, d)
        AK.Math.RoadHeight(track, d)
        AK.Math.RoadWidth(track, d)
        AK.TrackBuilder:TunnelDepth(track, d)
        AK.TrackBuilder:RampAt(track, d)
        AK.TrackBuilder:SectionAt(track, d)
        AK.Terrain:Sample(track, d, 0)
        AK.Terrain:Sample(track, d, 1.6)
        AK.TrackBuilder:MapPoint(track, d)
      end
    end
  end)

  -- Every item, from every position, at every gap. RollItem is reached on
  -- every box pickup by every racer.
  ok("items roll from every position and gap", function()
    local rng = AK.RNG:New(1234)
    for position = 1, AK.MAX_RACERS do
      for _, gap in ipairs({ 0, 0.4, 3, 12, 40 }) do
        for luck = 1, 10 do
          local id = AK:RollItem(position, AK.MAX_RACERS, luck, rng, gap, gap)
          assert(AK.Items[id], "rolled an item that does not exist: " .. tostring(id))
          assert(AK.ItemIndex[id], "rolled an item missing from ItemIndex: " .. tostring(id))
        end
      end
    end
  end)

  -- Every racer in every kart: the stat maths behind the grid.
  ok("every racer fits in every kart", function()
    for _, racer in ipairs(AK.Racers) do
      for _, kart in ipairs(AK.Karts) do
        local v = AK.Physics:CreateVehicle(racer, kart, nil, false)
        assert(v.maxSpeed > 0 and v.handling > 0 and v.acceleration > 0,
          racer.id .. "/" .. kart.id .. " produced a dead vehicle")
      end
    end
  end)

  ok("every cup resolves to real tracks", function()
    for _, cup in ipairs(AK.Cups or {}) do
      for _, id in ipairs(cup.tracks) do
        assert(AK:GetTrack(id), cup.id .. " lists a track that does not exist: " .. id)
      end
    end
  end)

  -- THE RENDERER, FOR REAL.
  --
  -- UI/RaceUI.lua is four thousand lines and its Render path touches every
  -- system in the addon on every frame. Nothing has ever executed a line of it:
  -- the offline preview reimplements the projection in JavaScript, which cannot
  -- catch a nil concatenated into a label or an arithmetic on a field that
  -- turned out to be optional. Those are the faults that end a race, and this
  -- runs the real code.
  -- FixedStep runs at most MAX_SLICES (8) of 1/120 per Update, so 1/15 of a
  -- second is exactly one full budget: the most simulated time a single frame
  -- can carry, and therefore the cheapest honest way to cover four minutes of
  -- racing through the real renderer in an interpreter.
  local FRAME = 1 / 15
  local function driveRace(trackId, seconds, mode, drive)
    AK.db.settings.difficulty = "Normal"
    AK.Race:Start(mode or "quick", { track = trackId })
    local race = AK.Race.current
    assert(race, "no race after Start")
    -- SOMEBODY HAS TO DRIVE.
    --
    -- Nobody is at the keyboard, and the race ends when the PLAYER crosses the
    -- line, not when the field does -- which is correct, and which means a
    -- harness that only holds the throttle never reaches the flag. The first
    -- run of this reported "four minutes of Elwynn did not finish"; the player
    -- was bouncing off the scenery at the first corner while seven AI lapped
    -- past. Hand the player's controls to the AI, the way attract mode does, so
    -- the finish, the results and the progression paths are all reached.
    if drive ~= false then
      race.player.ai = race.player.ai or AK.AI:CreatePersonality(9)
    end
    -- Count recoveries by watching the real state change. There is no
    -- `resetCount` on a vehicle -- the first version of this check read one and
    -- would have reported a comfortable zero forever. Falling off the world is
    -- `vehicle.falling`, so a reset is the frame it becomes set.
    race.akWasFalling = race.akWasFalling or {}
    race.akResets = race.akResets or 0
    -- WHERE they fall off, not just how often. A circuit that throws the field
    -- into the void once a lap has one corner doing it, and a bare count can
    -- never say which -- so the corner is named.
    race.akFallSections = race.akFallSections or {}
    for _ = 1, math.ceil(seconds / FRAME) do
      for i, v in ipairs(race.vehicles) do
        local down = v.falling and true or false
        if down and not race.akWasFalling[i] then
          race.akResets = race.akResets + 1
          local section = AK.TrackBuilder:SectionAt(v.route or race.track, v.distance)
          local name = section and section.name or "unnamed"
          race.akFallSections[name] = (race.akFallSections[name] or 0) + 1
        end
        race.akWasFalling[i] = down
      end
      if drive ~= false and race.player.ai then
        local wanted = AK.AI:Controls(race, race.player, FRAME)
        wipe(AK.Race.controls)
        for k, v in pairs(wanted) do AK.Race.controls[k] = v end
        AK.Race.controls.accelerate = true
        AK.Race.controls.throttleAware = true
      end
      AK.Race:Update(FRAME)
      -- Sample the cost of a frame once the race is properly under way: after
      -- the lights, at racing speed, with the field spread out. One frame's
      -- worth of widget traffic, which is the whole of what "smooth" means here.
      if not race.akDrawsPerFrame and race.state == AK.RACE_STATES.RACING
        and (race.elapsed or 0) > 20 then
        local before = widgetCalls
        AK.Race:Update(FRAME)
        race.akDrawsPerFrame = widgetCalls - before
      end
    end
    return race
  end

  ok("a race starts, renders and runs on every circuit", function()
    for _, track in ipairs(AK.Tracks) do
      driveRace(track.id, QUICK and 2 or 6)
      AK.Race:Stop(true)
    end
  end)

  -- Four full races at five simulated minutes each is most of the runtime of
  -- this harness. QUICK=1 skips them, for when the change under test is a
  -- screen rather than the simulation. It is not the default and never should
  -- be: the races are where the real findings come from.
  local QUICK = os.getenv("QUICK") == "1"

  ok("a whole race runs to the flag", function()
    if QUICK then return end
    local race = driveRace("elwynn", 60 * 5)
    assert(race.state == AK.RACE_STATES.FINISHED,
      "five minutes of Elwynn did not finish; state is " .. tostring(race.state))
    for _, vehicle in ipairs(race.vehicles) do
      assert(vehicle.lap >= 1, "a racer lost its lap count")
    end
    AK.Race:Stop(true)
  end)

  --- NOBODY RETIRES.
  ---
  --- The race used to end on the player's flag, so anyone still on circuit --
  --- everyone, if you win -- was printed on the results screen as "DNF". The
  --- cooldown lap exists to fix exactly that. Asserted on every race the
  --- harness runs, rather than as a race of its own.
  local function assertFieldIsHome(race, id)
    local seen = {}
    for _, vehicle in ipairs(race.vehicles) do
      assert(vehicle.finished and vehicle.finishTime,
        id .. ": " .. vehicle.racer.name .. " never finished")
      local place = race.positions[vehicle]
      assert(place and not seen[place],
        id .. ": " .. vehicle.racer.name .. " has no unique finishing place")
      seen[place] = true
    end
    -- And the classification is in crossing order, not some order the standings
    -- sort invented after the fact.
    local previous = -1
    for place = 1, #race.vehicles do
      local vehicle = race.ordered[place]
      assert(vehicle.finishTime >= previous - 0.0001,
        id .. ": the classification is not in crossing order")
      previous = vehicle.finishTime
    end
  end

  -- The cooldown lap drives the player's kart on the AI, and `vehicle.ai` is
  -- what AI:Report uses to tell a human from a rival. Borrowing a brain must
  -- not leave one behind.
  ok("coasting home does not turn the player into an AI", function()
    AK.Race:Start("quick", { track = "elwynn" })
    local race = AK.Race.current
    race.player.ai = nil
    for _ = 1, 20 do AK.Race:CoastHome(race, race.player, 1 / 60) end
    assert(race.player.ai == nil,
      "the player kept the brain it borrowed for the cooldown lap")
    -- Report() draws a panel and returns nothing; Snapshot is what builds the
    -- table, and it is what FinishRace calls.
    AK.AI:Snapshot(race)
    local report = AK.AI.lastReport
    assert(report, "no AI telemetry was built for a race with a full field")
    local sawYou = false
    for _, row in ipairs(report.rows) do if row[1] == "YOU" then sawYou = true end end
    assert(sawYou, "the player lost their own row in the AI report")
    AK.Race:Stop(true)
  end)

  -- Mirror mode flips the centreline. Everything an author placed ACROSS that
  -- centreline is a separate number and used not to flip with it, so a mirrored
  -- circuit kept the original's hazards on the original's side of the road.
  ok("mirror mode mirrors the whole circuit", function()
    AK.db.settings.mirror = false
    AK.Race:Start("quick", { track = "durotar" })
    local plain = {}
    for i, hazard in ipairs(AK.Race.current.hazards) do plain[i] = hazard.lateral end
    local plainCurve = AK.Math.RoadCurve(AK.Race.current.track, 300)
    AK.Race:Stop(true)

    AK.db.settings.mirror = true
    AK.Race:Start("quick", { track = "durotar" })
    local race = AK.Race.current
    assert(#race.hazards == #plain, "mirror mode changed how many hazards there are")
    for i, hazard in ipairs(race.hazards) do
      assert(math.abs(hazard.lateral + plain[i]) < 1e-9,
        "hazard " .. i .. " did not flip with the circuit")
    end
    assert(math.abs(AK.Math.RoadCurve(race.track, 300) + plainCurve) < 1e-9,
      "the centreline itself did not flip")
    -- And it still runs: a mirrored lap has to be drivable, not merely flipped.
    for _ = 1, math.ceil(6 / FRAME) do AK.Race:Update(FRAME) end
    AK.Race:Stop(true)
    AK.db.settings.mirror = false
  end)

  -- A GREEN SHELL IS A SHOT, NOT A TRAM.
  --
  -- Projectiles are stored road-relative -- distance along the lap, lateral
  -- across it -- so one that simply held its lateral followed every bend of the
  -- circuit and could not miss. It carries a heading now. Fired down a straight
  -- it must run true; fired into a bend it must leave the road.
  ok("a green shell flies straight while the road bends away", function()
    AK.Race:Start("quick", { track = "elwynn" })
    local race = AK.Race.current
    local track = race.track

    --- Put a shell on the road at `at` and run it for `seconds`.
    local function fire(at, seconds)
      wipe(race.projectiles)
      local shell = { item = AK.Items.green_shell, owner = race.player,
        distance = at, lateral = 0, speed = 34, life = 20, age = 5,
        armAfter = 0, bounces = 0, heading = 0 }
      table.insert(race.projectiles, shell)
      for _ = 1, math.ceil(seconds * 120) do
        if #race.projectiles == 0 then break end
        AK.Race:UpdateProjectiles(race, 1 / 120)
      end
      return shell
    end

    -- Find the straightest and the tightest metre of the lap to fire from.
    local flat, bend, flatCurve, bendCurve = 0, 0, math.huge, 0
    for at = 0, track.length - 1, 5 do
      local curve = math.abs(AK.Math.RoadCurve(track, at))
      -- Somewhere with room to run before the next corner, either way.
      local ahead = math.abs(AK.Math.RoadCurve(track, at + 60))
      if curve + ahead < flatCurve then flat, flatCurve = at, curve + ahead end
      if curve > bendCurve then bend, bendCurve = at, curve end
    end

    local straight = fire(flat, 1.2)
    assert(math.abs(straight.lateral) < 0.10,
      ("a shell fired down the straightest part of Elwynn drifted to %.2f")
        :format(straight.lateral))

    local cornered = fire(bend, 1.6)
    assert(math.abs(cornered.lateral) > 0.55 or (cornered.bounces or 0) > 0,
      ("a shell fired into a %.1f-curve bend only reached %.2f: it is still on rails")
        :format(bendCurve, cornered.lateral))
    AK.Race:Stop(true)
  end)

  -- A TUNNEL HAS TO HAVE WALLS IN IT.
  --
  -- The offline preview draws them and the client, by report, does not. Only
  -- one of those can be right, and this is the real renderer -- so it is the
  -- one to ask. Drive Deadmines until the camera is properly under cover, then
  -- look at what RenderRoad actually did to the wall textures.
  ok("a tunnel has walls in it", function()
    AK.Race:Start("quick", { track = "deadmines" })
    local race = AK.Race.current
    race.player.ai = race.player.ai or AK.AI:CreatePersonality(9)
    local deepest, deepAt = 0, 0
    for _ = 1, math.ceil(120 / FRAME) do
      local wanted = AK.AI:Controls(race, race.player, FRAME)
      wipe(AK.Race.controls)
      for k, v in pairs(wanted) do AK.Race.controls[k] = v end
      AK.Race.controls.accelerate = true
      AK.Race:Update(FRAME)
      local depth = AK.RaceUI.tunnelDepth or 0
      if depth > deepest then deepest, deepAt = depth, race.player.distance end
      if depth > 0.85 then break end
    end
    assert(deepest > 0.5,
      ("never got under cover on Deadmines; deepest was %.2f"):format(deepest))

    local shown, lit, sized = 0, 0, 0
    local brightest = 0
    --- One wall piece. Called three times per strip rather than iterating a
    --- table of them: `ipairs` over a list built from expressions stops at the
    --- first nil, and check.js is right to refuse it even where the three
    --- fields happen to always exist.
    local function measure(piece)
      if not piece or not piece.akShown then return end
      shown = shown + 1
      local colour = piece.akColor or { 0, 0, 0, 0 }
      local value = math.max(colour[1], colour[2], colour[3])
      brightest = math.max(brightest, value)
      if value > 0.06 then lit = lit + 1 end
      if (piece.akWidth or 0) >= 1 and (piece.akHeight or 0) >= 1 then sized = sized + 1 end
    end
    for _, strip in ipairs(AK.RaceUI.strips) do
      measure(strip.wallLeft)
      measure(strip.wallRight)
      measure(strip.ceiling)
    end
    -- WHAT THE WALL HAS TO BE BRIGHTER THAN. RenderSurround fills the whole
    -- frame with rock behind the per-band walls, so a wall is only visible if
    -- it is clearly brighter than that fill. The two were within fifteen
    -- percent of each other, which is a dark box, not a tunnel.
    local fill = AK.RaceUI.surround.left
    local fillColor = fill.akColor or { 0, 0, 0, 0 }
    local fillValue = math.max(fillColor[1], fillColor[2], fillColor[3])
    say(("        deadmines under %.2f cover: %d wall pieces, brightest %.3f, "
      .. "fill behind them %.3f (%.1fx)"):format(deepest, shown, brightest, fillValue,
      fillValue > 0.001 and brightest / fillValue or 0))
    assert(shown >= 6, "only " .. shown .. " wall pieces were drawn inside a tunnel")
    assert(sized == shown, (shown - sized) .. " wall pieces were drawn with no size")
    assert(brightest > 0.26,
      ("the brightest tunnel wall was %.3f -- that is nearly black"):format(brightest))
    assert(brightest > fillValue * 1.8,
      ("the walls are %.3f against a fill of %.3f: they cannot be seen against it")
        :format(brightest, fillValue))
    AK.Race:Stop(true)
  end)

  -- THE ROAD HAS TO REACH THE HORIZON, AND HAVE DETAIL WHEN IT GETS THERE.
  --
  -- Two faults, one picture. The strips were spread uniformly in 1/z all the
  -- way to the draw distance, which is right for the near road and a
  -- singularity at the far end: measured, the LAST strip covered everything
  -- from 226m to 560m as a single flat quad, at one lateral position and one
  -- width. So the road did not converge, it stopped -- a blunt end hanging in
  -- mid-air with open ground between it and the treeline -- and a corner three
  -- hundred metres out was drawn as a straight smear pointing wherever that
  -- quad's midpoint happened to land.
  --
  -- Both are visible in the geometry the renderer hands the client, so both are
  -- measured rather than described. Strips uniform in 1/z are uniform in screen
  -- height, so the count of them near the horizon IS the far-field resolution:
  -- the old schedule could only ever put four in the last twenty pixels, and
  -- the split schedule puts the whole tail there.
  ok("the road runs all the way to the horizon", function()
    local worstGap, gapAt, worstTail, tailAt = -math.huge, "", math.huge, ""
    for _, id in ipairs({ "elwynn", "durotar", "icecrown" }) do
      AK.Race:Start("quick", { track = id })
      local race = AK.Race.current
      race.player.ai = race.player.ai or AK.AI:CreatePersonality(9)
      -- A CREST IS NOT A FAULT. Over a rise the far road is genuinely behind
      -- the hill and RenderRoad drops those strips, exactly as it should -- as
      -- it does on a descending road, where the far surface projects BELOW its
      -- own near strips. So both numbers are the best the circuit manages over
      -- the run: how close to the horizon the road ever gets, and how finely
      -- the far field is ever sliced. Every circuit has to be able to do both
      -- SOMEWHERE; no circuit has to do them on a blind crest.
      local best, mostTail = math.huge, 0
      for _ = 1, math.ceil(20 / FRAME) do
        local wanted = AK.AI:Controls(race, race.player, FRAME)
        wipe(AK.Race.controls)
        for k, v in pairs(wanted) do AK.Race.controls[k] = v end
        AK.Race.controls.accelerate = true
        AK.Race:Update(FRAME)

        local horizon = AK.db.tuning.horizon
        local top, nearHorizon = nil, 0
        for _, strip in ipairs(AK.RaceUI.strips) do
          local road = strip.road
          if road and road.akShown and road.akY and road.akHeight then
            local edge = road.akY + road.akHeight
            if not top or edge > top then top = edge end
            if edge > horizon - 20 then nearHorizon = nearHorizon + 1 end
          end
        end
        if top then
          local gap = horizon - top
          if gap < best then best = gap end
          if nearHorizon > mostTail then mostTail = nearHorizon end
        end
      end
      if best > worstGap then worstGap, gapAt = best, id end
      if mostTail < worstTail then worstTail, tailAt = mostTail, id end
      AK.Race:Stop(true)
    end
    say(("        road reaches within %.1fpx of the horizon on open ground (%s); "
      .. "at best %d strips in the last 20px (%s)")
      :format(worstGap, gapAt, worstTail, tailAt))
    assert(worstGap < 12,
      ("the road never gets closer than %.1f pixels to the horizon on %s -- "
        .. "it ends in mid-air"):format(worstGap, gapAt))
    -- Uniform 1/z managed four here, whatever the draw distance was set to.
    assert(worstTail >= 10,
      ("only %d road strips are drawn in the last 20 pixels before the horizon "
        .. "on %s: the far road is a handful of flat quads again, and cannot bend")
        :format(worstTail, tailAt))
  end)

  -- A FORK MUST NOT BE A JUMP CUT.
  --
  -- Taking a branch swaps the route the kart is measured against, and every
  -- part of that used to be a discontinuity: the distance was reset to zero
  -- (a forward teleport of however far the kart still was from the split), and
  -- the camera was clamped to zero (so the world froze for camBack metres while
  -- the kart kept moving, sliding it out from under the camera and snapping it
  -- back). The camera-to-kart gap is what the player actually sees, so that is
  -- what this holds to.
  ok("taking a fork is continuous", function()
    local worst, worstAt, crossings = 0, "", 0
    for _, id in ipairs({ "elwynn", "durotar", "oribos" }) do
      AK.Race:Start("quick", { track = id })
      local race = AK.Race.current
      race.player.ai = race.player.ai or AK.AI:CreatePersonality(9)
      -- Take every fork this circuit offers.
      race.player.forkTake = true
      local wasRoute = race.player.route
      for _ = 1, math.ceil(180 / FRAME) do
        local wanted = AK.AI:Controls(race, race.player, FRAME)
        wipe(AK.Race.controls)
        for k, v in pairs(wanted) do AK.Race.controls[k] = v end
        AK.Race.controls.accelerate = true
        AK.Race:Update(FRAME)
        if race.player.route ~= wasRoute then
          crossings = crossings + 1
          wasRoute = race.player.route
          -- The frame the route changed on: the camera has already been placed
          -- for the new route, so the gap must still be the chase distance.
          local gap = race.player.distance - (AK.RaceUI.camZ or 0)
          -- Against where the camera MEANT to be. The chase distance is not a
          -- constant: a boost pushes the camera back, and measuring against
          -- camBack alone reported a boost as a fork glitch.
          local want = AK.RaceUI.camGap or AK.db.tuning.camBack
          local off = math.abs(gap - want)
          if off > worst then worst, worstAt = off, id end
        end
        if race.player.finished then break end
      end
      AK.Race:Stop(true)
    end
    say(("        %d route changes; worst camera slip %.2fm (%s)")
      :format(crossings, worst, worstAt ~= "" and worstAt or "none"))
    assert(crossings >= 2, "never took a fork on three circuits that have them")
    -- One frame of travel at racing speed is about 0.3m; anything past a metre
    -- is the camera jumping rather than following.
    assert(worst < 1.2,
      ("the camera slipped %.2fm from the kart at a fork on %s"):format(worst, worstAt))
  end)

  -- THE CUT HAS TO HAPPEN IN THE DARK.
  --
  -- A recovery moves the kart up to a full respawn spacing BACKWARDS in one
  -- simulation tick. There is nothing continuous between the two places, so it
  -- cannot be smoothed -- it can only be covered. This drives a real fall and
  -- checks the veil is fully shut on the frame the world actually jumps.
  ok("a recovery is covered, not jump cut", function()
    AK.Race:Start("quick", { track = "durotar" })
    local race = AK.Race.current
    race.player.ai = race.player.ai or AK.AI:CreatePersonality(9)
    -- Get properly under way first: a recovery from the grid is not the case
    -- that matters and the respawn point would be behind the start line.
    for _ = 1, math.ceil(20 / FRAME) do
      AK.Race.controls.accelerate = true
      AK.Race:Update(FRAME)
    end
    local before = race.player.distance
    race.player.falling = 0.01
    local jumped, veilAtCut, sawLift = 0, nil, false
    for _ = 1, math.ceil(4 / FRAME) do
      local wasLifted = race.player.lifted
      AK.Race:Update(FRAME)
      if race.player.lifted and not wasLifted then
        sawLift = true
        jumped = math.abs(race.player.distance - before)
        veilAtCut = AK.RaceUI.recoveryVeil.akAlpha or 0
      end
      if not race.player.falling then break end
    end
    assert(sawLift, "the fall never reached the point where the kart is picked up")
    say(("        durotar recovery: the world moved %.0fm, veil %.2f at the cut")
      :format(jumped, veilAtCut or 0))
    assert(jumped > 5, "the recovery did not actually move the kart, so this proves nothing")
    -- And it must not throw you halfway back up the circuit. The penalty for
    -- going off is the pick-up, not a lap.
    assert(jumped < 40,
      ("a recovery moved the kart %.0fm backwards; that is a lap penalty"):format(jumped))
    assert((veilAtCut or 0) > 0.99,
      ("the world jumped %.0fm with the veil at %.2f -- that is a visible cut")
        :format(jumped, veilAtCut or 0))
    -- And it has to open again, or the screen stays black.
    for _ = 1, math.ceil(3 / FRAME) do AK.Race:Update(FRAME) end
    assert((AK.RaceUI.recoveryVeil.akAlpha or 1) < 0.02,
      "the recovery veil never opened again")
    AK.Race:Stop(true)
  end)

  ok("time trial and battle both run", function()
    driveRace("icecrown", 8, "time_trial")
    AK.Race:Stop(true)
    driveRace(nil, 8, "battle")
    AK.Race:Stop(true)
  end)

  -- Presentation beats are fired from RaceManager at moments a short run may
  -- never reach, so they are driven directly -- this is what /kart beats does.
  ok("every presentation beat plays", function()
    driveRace("durotar", 4)
    AK.RaceUI:PlayBeats()
    for _ = 1, 60 do AK.Race:Update(FRAME) end
    AK.Race:Stop(true)
  end)

  ok("the results screen builds and shows", function()
    local race = driveRace("oribos", QUICK and 20 or 60 * 5)
    -- Twenty seconds does not finish a race; the results screen is built from
    -- whatever state it is in, which is the point of the check either way.
    if not QUICK then assertFieldIsHome(race, "oribos") end
    AK.Results:Build()
    AK.Results:Show(race)
    AK.Results:Hide()
    AK.Race:Stop(true)
  end)

  -- A SCREEN MAY NOT BUILD ITSELF TWICE.
  --
  -- CHOOSE YOUR RACER is eleven PlayerModel frames, each streaming a creature
  -- display, and every Show* used to CreateFrame a fresh page on entry. Every
  -- screen did it, but that one is the expensive one. Nothing
  -- in WoW destroys the old one, so ten visits in a session leave a hundred and
  -- ten live PlayerModels behind, the screen gets slower the longer you play,
  -- and each visit re-streams every model from scratch -- which is the second
  -- of blank cards on the way in. The pages are cached and refreshed now, and
  -- this is what says so: open every grid twice and count.
  ok("opening a menu screen twice builds it once", function()
    AK.Menu:Build()
    AK.Menu:Show()
    local function everyScreen()
      for _, kind in ipairs({ "racer", "kart", "track", "cup" }) do
        AK.Menu:ShowSelection(kind)
      end
      AK.Menu:ShowSettings()
      AK.Menu:ShowAchievements()
      AK.Menu:ShowMultiplayer()
      AK.Menu:ShowHome()
    end
    everyScreen()
    local before = {}
    for kind, count in pairs(widgetsMade) do before[kind] = count end
    for _ = 1, 3 do everyScreen() end
    local leaked = {}
    for kind, count in pairs(widgetsMade) do
      local grew = count - (before[kind] or 0)
      if grew > 0 then table.insert(leaked, ("%s +%d"):format(kind, grew)) end
    end
    table.sort(leaked)
    say(("        three more passes over every menu screen: %s"):format(
      #leaked > 0 and table.concat(leaked, ", ") or "nothing new built"))
    assert(#leaked == 0,
      "reopening the menu screens built new widgets: " .. table.concat(leaked, ", "))
    AK.Menu:Hide()
  end)

  -- AND A WORKSHOP EDIT HAS TO REACH THE CARD.
  --
  -- The other half of keeping the pages: a card built once is a snapshot, and
  -- every edit made after it was built used to reach the RACE -- which reads
  -- the racer table at the flag -- and nothing on CHOOSE YOUR RACER. You could
  -- give a racer a new model, watch it drive past on the track, and still see
  -- the old one on the card you picked them from.
  ok("a workshop edit reaches the racer cards", function()
    AK.Menu:Build()
    AK.Menu:Show()
    AK.Menu:ShowSelection("racer")
    local page = AK.Menu.pages["select:racer"]
    assert(page, "no racer page was built")

    --- Every portrait belonging to the LIVE page, found by walking each
    --- widget's parents up to it. The stub keeps one flat list of everything
    --- ever created, and a page that has been dropped and rebuilt leaves its
    --- old portraits in it -- counting those would let a page that never
    --- rebuilt pass.
    local function specs()
      local found = {}
      for _, w in ipairs(everyWidget) do
        if w.akKind == "PlayerModel" then
          local parent, guard = w.akParent, 0
          while parent and guard < 8 do
            if parent == page then found[#found + 1] = w break end
            parent, guard = parent.akParent, guard + 1
          end
        end
      end
      return found
    end

    local before = specs()
    assert(#before >= #AK.Racers,
      ("%d portraits on a page of %d racers"):format(#before, #AK.Racers))

    -- Give a racer a model nothing else is using, then come back to the page
    -- the way a player does: workshop, close, CHOOSE YOUR RACER.
    local target = AK.Racers[3]
    local WANTED = 987654
    AK.Roster:Set("racers", target.id, "model", WANTED)
    assert(target.model and target.model.creature == WANTED,
      "the roster did not take the new model")
    AK.Menu:ShowHome()
    AK.Menu:ShowSelection("racer")
    page = AK.Menu.pages["select:racer"]

    local showing = false
    for _, model in ipairs(specs()) do
      if model.akSpec and model.akSpec.creature == WANTED then showing = true end
    end
    assert(showing,
      "a model chosen in the workshop never reached the racer card")

    -- And a racer ADDED afterwards is not merely stale, it has no card at all:
    -- the grid's columns, card size and card list were all decided from the
    -- entry count when the page was built.
    local countBefore = #AK.Racers
    local added = AK.Roster:AddRacer()
    assert(added, "the workshop could not add a racer")
    AK.Menu:ShowHome()
    AK.Menu:ShowSelection("racer")
    page = AK.Menu.pages["select:racer"]
    assert(#AK.Racers == countBefore + 1, "the roster did not grow")
    assert(#specs() >= #AK.Racers,
      ("a racer was added and the page still has %d portraits for %d racers")
        :format(#specs(), #AK.Racers))
    say(("        %s took the new model; the page rebuilt for %d racers")
      :format(target.name, #AK.Racers))
    AK.Roster:RemoveRacer(added.id)
    AK.Menu:Hide()
  end)

  -- NOTHING MAY BE PRINTED THROUGH ANYTHING ELSE.
  --
  -- The race HUD has verify-hud, which walks a layout table at eight
  -- resolutions and reports every collision. The WINDOWS -- the sound editor,
  -- the workshop -- have no such table: they are built imperatively out of
  -- SetPoint calls with literal offsets, and nobody has ever seen one outside a
  -- WoW client. Read by hand, the sound editor had "GAME AUDIO LIBRARY"
  -- printed through the HEAR IT REPEATED button and BIND overlapping PLAY ID.
  -- Reading by hand does not scale and does not stay true.
  --
  -- The stub records what SetPoint and SetSize were actually given, so the
  -- real geometry is available here without parsing a line of Lua. Siblings
  -- only, and only things that are meant to be distinct: a texture is usually
  -- a background or a highlight and is SUPPOSED to sit under its row.
  ok("no window prints one control through another", function()
    AK.SoundEditor:Toggle()
    AK.SoundEditor:Toggle()
    AK.Workshop:Toggle()
    AK.Workshop:Toggle()

    --- Only these two windows. The race HUD has verify-hud and the menu has
    --- Art/preview-ui.js; both of those deliberately layer things (a glow under
    --- a readout, a plate under a row) that this blunt test would call a fault.
    -- FILLED IN, not empty. Every readout in the debug window is created with
    -- an empty string and written by Update, so measuring it at build time
    -- measures nothing at all -- which is how a 430-wide window full of
    -- sixty-character lines passed.
    AK.RaceUI:Build()
    AK.Debug:Build()
    AK.Debug.frame:Show()
    AK.Race:Start("quick", { track = "elwynn" })
    for _ = 1, math.ceil(3 / FRAME) do AK.Race:Update(FRAME) end
    AK.Debug:Update(AK.Race.current)
    -- PAUSE IT. The pause panel arranges itself when it is shown, so measuring
    -- it without pausing measured three developer buttons still piled at the
    -- construction offset under the title -- a collision the player can never
    -- see, reported instead of the ones they can. Developer tools are on for
    -- this so the fullest version of the panel is the one under the eye.
    local wasDev = AK.db.settings.debug
    AK.db.settings.debug = true
    AK.Race:TogglePause()
    AK.Race:Update(FRAME)
    AK.Race:Stop(true)
    AK.db.settings.debug = wasDev
    -- The AI report and the creature previewer are windows too, and neither had
    -- ever been looked at either.
    AK.AI:Report()
    AK:PreviewNPC(36648)
    local roots = {
      [AK.SoundEditor.frame] = "sound editor",
      [AK.Workshop.frame] = "workshop",
      [AK.Debug.frame] = "debug readout",
      [AK.AI.panel] = "AI report",
      [AK.npcPreview] = "creature preview",
      -- Not a standalone window, but the same kind of thing: a panel of
      -- controls nobody can screenshot without pausing a race first.
      [AK.RaceUI.pause] = "pause panel",
    }
    local function rootOf(w)
      local guard = 0
      while w and guard < 40 do
        if roots[w] then return roots[w] end
        w, guard = w.akParent, guard + 1
      end
    end

    local rootFrames = {}
    for frame, name in pairs(roots) do rootFrames[#rootFrames + 1] = { frame, name } end
    local siblings, windowCount, pairCount = {}, 0, 0
    for root in pairs(roots) do if root then windowCount = windowCount + 1 end end
    for _, w in ipairs(everyWidget) do
      if w.akParent and rootOf(w) then
        siblings[w.akParent] = siblings[w.akParent] or {}
        table.insert(siblings[w.akParent], w)
      end
    end

    --- How big is this thing.
    local function sizeOf(w)
      if w.akWidth and w.akHeight then return w.akWidth, w.akHeight end
      if w.akAllPoints then
        -- Fills something: whatever that is, this is the same size. A frame
        -- with no explicit size at the top of the tree is the screen.
        if type(w.akAllPoints) == "table" then
          local pw, ph = sizeOf(w.akAllPoints)
          if pw then return pw, ph end
        end
        return 1365, 768
      end
      if w.akKind == "FontString" then
        -- FrizQt: ~0.62 of the point size per uppercase character, ~1.2 line
        -- height. Both calibrated in Art/hud-font.js against the real font.
        local size = w.akFontSize or 12
        -- WoW's colour escapes draw NOTHING: "|cffff5555" and its "|r" are ten
        -- and two characters of markup. Counting them as ink made a 42-character
        -- readout measure as 54 and report an overflow that is not there.
        local text = tostring(w.akText or "")
          :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        -- An empty readout draws nothing and cannot be printed through. Several
        -- are created with a width and filled in by a Refresh; measuring their
        -- reserved width as if it were ink reported forty-one phantom
        -- collisions against the buttons beside them.
        if text == "" then return nil end
        local run = #text * size * 0.62
        -- A PARAGRAPH IS NOT A LINE. A blurb given an explicit width wraps, and
        -- measuring it as one long run made a 250-character note fifteen
        -- hundred pixels wide -- which collides with everything on the pane and
        -- is a fault in the ruler, not in the screen.
        if w.akWidth then
          local lines = math.max(1, math.ceil(run / math.max(1, w.akWidth)))
          for _ in text:gmatch("\n") do lines = lines + 1 end
          return w.akWidth, lines * size * 1.2
        end
        return run, size * 1.2
      end
    end

    --- Where the named point of a WxH box sits, as an offset from its TOPLEFT.
    --- WoW's y grows upward and this works in screen coordinates, so every y
    --- here is measured DOWN from the top.
    local function anchorOffset(point, width, height)
      local x = (point:find("LEFT") and 0)
        or (point:find("RIGHT") and width) or width * 0.5
      local y = (point:find("TOP") and 0)
        or (point:find("BOTTOM") and height) or height * 0.5
      return x, y
    end

    --- Top-left corner of a widget, in its window's coordinates. Resolved
    --- recursively: a control anchored to its neighbour is placed once the
    --- neighbour is, and the chain ends at the window itself.
    local boxOf
    local resolving = {}
    boxOf = function(w)
      if not w or resolving[w] then return nil end
      if w.akBox ~= nil then return w.akBox or nil end
      if not w.akAnchor or not w.akX then w.akBox = false return nil end
      local width, height = sizeOf(w)
      if not width or not height or width <= 0 or height <= 0 then
        w.akBox = false
        return nil
      end
      resolving[w] = true
      local host = w.akRelTo or w.akParent
      local hostX, hostY, hostW, hostH = 0, 0, nil, nil
      if roots[host] then
        hostW, hostH = sizeOf(host)
      elseif host then
        local hb = boxOf(host)
        if hb then hostX, hostY, hostW, hostH = hb.x, hb.y, hb.w, hb.h end
      end
      resolving[w] = nil
      if not hostW or not hostH then w.akBox = false return nil end
      -- Anchored to the host's point, offset by (x, y) -- and y is UP.
      local hx, hy = anchorOffset(w.akRelPoint or w.akAnchor, hostW, hostH)
      local sx, sy = anchorOffset(w.akAnchor, width, height)
      local box = {
        x = hostX + hx + w.akX - sx,
        y = hostY + hy - w.akY - sy,
        w = width, h = height,
      }
      w.akBox = box
      return box
    end

    local hits = {}
    for _, group in pairs(siblings) do
      for i = 1, #group do
        for j = i + 1, #group do
          local a, b = group[i], group[j]
          pairCount = pairCount + 1
          if a.akKind ~= "Texture" and b.akKind ~= "Texture"
            and not a.akHidden and not b.akHidden then
            local ra, rb = boxOf(a), boxOf(b)
            -- CONTAINMENT IS NOT COLLISION. A row's click zone is a frame the
            -- full width of the row with the label sitting inside it, and a
            -- panel is a frame with its whole pane inside it. Those are the
            -- structure, not a fault. A PARTIAL overlap -- a heading clipping
            -- the corner of the button above it -- is the fault.
            local inside = ra and rb
              and ((ra.x <= rb.x and ra.y <= rb.y
                    and ra.x + ra.w >= rb.x + rb.w and ra.y + ra.h >= rb.y + rb.h)
                or (rb.x <= ra.x and rb.y <= ra.y
                    and rb.x + rb.w >= ra.x + ra.w and rb.y + rb.h >= ra.y + ra.h))
            local overlap = ra and rb
              and math.min(ra.x + ra.w, rb.x + rb.w) - math.max(ra.x, rb.x) or 0
            local down = ra and rb
              and math.min(ra.y + ra.h, rb.y + rb.h) - math.max(ra.y, rb.y) or 0
            -- Two pixels, because a text box's size is ESTIMATED from its font
            -- and its string: a hairline is inside that estimate's error, and
            -- reporting one would train everyone to ignore the check.
            if ra and rb and not inside and overlap >= 2 and down >= 2 then
              table.insert(hits, ("%s \"%s\" x %s \"%s\" (%dx%dpx)"):format(
                a.akKind, tostring(a.akText or "?"), b.akKind, tostring(b.akText or "?"),
                math.floor(overlap), math.floor(down)))
            end
          end
        end
      end
    end
    -- AND NOTHING MAY RUN OFF THE EDGE OF ITS OWN WINDOW. verify-hud has this
    -- test for the race HUD and it is the other half of the question: a readout
    -- can clear every neighbour and still be written into the air past the
    -- frame's right edge, where WoW simply draws it over whatever is behind.
    for _, entry in ipairs(rootFrames) do
      local frame, name = entry[1], entry[2]
      local fw, fh = sizeOf(frame)
      if fw and fh then
        -- DIRECT CHILDREN ONLY. A sibling comparison is self-consistent -- both
        -- boxes come out of the same resolver, so any error it makes cancels --
        -- but measuring against the window's own edge does not, and a control
        -- three anchors deep inside a scrolling pane is exactly where this
        -- resolver is least sure of itself. One level down it is certain.
        for _, w in ipairs(everyWidget) do
          if w.akParent == frame and not w.akHidden and w.akKind ~= "Texture" then
            local box = boxOf(w)
            -- Scroll panes are clipped and their content is MEANT to be taller
            -- than the view, so only the horizontal edges are asked about.
            if box and (box.x < -0.5 or box.x + box.w > fw + 0.5) then
              table.insert(hits, ("%s \"%s\" runs %dpx outside the %s"):format(
                w.akKind, tostring(w.akText or "?"),
                math.ceil(math.max(-box.x, box.x + box.w - fw)), name))
            end
          end
        end
      end
    end

    table.sort(hits)
    -- HOW MUCH OF THE WINDOW THIS ACTUALLY SAW. Only TOPLEFT-anchored siblings
    -- can be compared without resolving each parent's size, and these windows
    -- are mostly built that way -- but a check that quietly looks at a third of
    -- a screen and reports PASS is worse than no check, so it says.
    local measured, total = 0, 0
    for _, group in pairs(siblings) do
      for _, w in ipairs(group) do
        total = total + 1
        if boxOf(w) then measured = measured + 1 end
      end
    end
    say(("        %d windows, %d of %d controls placed measurably, "
      .. "%d sibling pairs compared, %d collisions"):format(
      windowCount, measured, total, pairCount, #hits))
    for i = 1, math.min(6, #hits) do say("          " .. hits[i]) end
    -- Leave nothing on screen for the checks that follow.
    if AK.AI.panel then AK.AI.panel:Hide() end
    if AK.npcPreview then AK.npcPreview:Hide() end
    AK.Debug.frame:Hide()
    assert(#hits == 0, #hits .. " controls are misplaced")
  end)

  -- A PACKET HAS TO SURVIVE THE ROUND TRIP.
  --
  -- Multiplayer is the one system here that cannot be exercised by playing:
  -- it needs two clients. So nothing had ever run a packet through the sender
  -- and the parser and compared the two ends -- which is how a splitter that
  -- silently DROPS EMPTY FIELDS lived in the file that parses positional
  -- packets. One blank field and every field after it shifts one place left:
  -- the kart id lands in the racer slot and the kart slot comes back nil.
  ok("a multiplayer packet survives the round trip", function()
    local sent = {}
    local realSend = C_ChatInfo.SendAddonMessage
    C_ChatInfo.SendAddonMessage = function(_, message) sent[#sent + 1] = message return true end
    local function lastOfKind(kind)
      for i = #sent, 1, -1 do
        if sent[i]:sub(1, #kind + 1) == kind .. "\t" then return sent[i] end
      end
    end

    -- A joiner whose racer field is BLANK, which is the case that was broken.
    AK.Net.lobby = { id = "S1", host = "Host", track = "elwynn",
      roster = { Host = { name = "Host", racer = "baine", kart = "kodo" } } }
    AK.Net:HandleMessage("JOIN\tS1\tGuest\t\tmechano", "Guest")
    local guest = AK.Net.lobby.roster.Guest
    assert(guest, "a JOIN packet with a blank racer field never reached the roster")
    assert(guest.kart == "mechano",
      ("the kart came back as %q -- the blank racer field shifted the packet")
        :format(tostring(guest.kart)))
    assert(guest.racer ~= "mechano",
      "the KART id was read as the racer: the splitter is renumbering fields")

    -- And the full field state, host to client, through the real batcher.
    AK.Race:Start("quick", { track = "durotar" })
    local race = AK.Race.current
    race.network = { isHost = true, session = "S1", host = "Host" }
    race.delta = 1
    for index, vehicle in ipairs(race.vehicles) do
      vehicle.networkId = "R" .. index
      vehicle.distance = 100 * index
      vehicle.lateral = -0.5 + index * 0.1
      vehicle.speed = 30 + index
    end
    race.byNetworkId = {}
    wipe(sent)
    AK.Net.snapshotClock = 99
    AK.Net:BroadcastSnapshot(race)
    local state = lastOfKind("STATE")
    assert(state, "the host sent no snapshot at all")
    -- WoW drops an addon message over 255 bytes on the floor, silently.
    for _, message in ipairs(sent) do
      assert(#message <= 255,
        ("a snapshot packet is %d bytes -- the client drops it silently"):format(#message))
    end

    -- Receive it as a client with its own copy of the field.
    -- A client's own copy of the grid, addressed BOTH ways: by slot, which is
    -- what a snapshot carries now, and by networkId, which is what one from an
    -- older host carries.
    local mirror = { network = { isHost = false, session = "S1" }, track = race.track,
      byNetworkId = {}, vehicles = {} }
    for index in ipairs(race.vehicles) do
      local copy = { distance = 0, lateral = 0, speed = 0 }
      mirror.byNetworkId["R" .. index] = copy
      mirror.vehicles[index] = copy
    end
    for _, message in ipairs(sent) do
      local values = { strsplit("\t", message) }
      if values[1] == "STATE" then AK.Net:ApplySnapshot(mirror, values[3]) end
    end
    local worst, worstAt = 0, ""
    for index, vehicle in ipairs(race.vehicles) do
      local copy = mirror.byNetworkId["R" .. index]
      -- LATERAL IS COMPARED AS THE WIRE DELIVERED IT, not as the kart is
      -- currently drawn. A client no longer teleports sideways on every
      -- packet -- it eases toward the reported position over about a sixth of
      -- a second -- so `lateral` mid-glide is not what arrived, and
      -- `netLateral` is. What this check is for is whether the number survived
      -- the trip, which it still is.
      local landed = copy.netLateral or copy.lateral
      local off = math.abs(copy.distance - math.floor(vehicle.distance))
        + math.abs(landed - vehicle.lateral) * 100
        + math.abs(copy.speed - vehicle.speed) * 10
      if off > worst then worst, worstAt = off, "R" .. index end
    end
    local longest = 0
    for _, message in ipairs(sent) do longest = math.max(longest, #message) end
    say(("        %d karts in %d packet(s), longest %d of 255 bytes, "
      .. "worst field drift %.2f"):format(#race.vehicles, #sent, longest, worst))
    assert(worst < 1.5,
      ("kart %s came out of the round trip %.2f off"):format(worstAt, worst))
    AK.Race:Stop(true)
    AK.Net.lobby = nil
    C_ChatInfo.SendAddonMessage = realSend
  end)

  -- COMING OUT OF A SHORTCUT MUST NOT BE A CUT.
  --
  -- Taking a branch and rejoining swaps `vehicle.route`, and everything the
  -- renderer draws hangs off that: the centreline, the width, the scenery. The
  -- geometry is anchored so both ends meet the main line exactly -- verify
  -- tracks.js has proved that for a while -- but "the junction is in the right
  -- place" is not the same as "nothing jumps on the frame you cross it", and
  -- the jump is what was reported. This drives a kart onto a branch, out the
  -- far end, and measures the road under it on every tick.
  ok("a shortcut does not jump the world on the way out", function()
    if QUICK then return end
    local Race = AK.Race
    local worstWidth, worstAt = 0, nil
    local checked = 0
    for _, id in ipairs({ "elwynn", "durotar", "oribos", "stranglethorn" }) do
      Race:Start("quick", { track = id })
      local race = Race.current
      local track = race.track
      if track.branches and track.branches[1] then
        checked = checked + 1
        local branch = track.branches[1]
        local player = race.player
        player.ai = player.ai or AK.AI:CreatePersonality(9)
        -- Put the kart on the branch directly rather than driving a whole lap
        -- to the split: what is under test is the far end.
        player.route = branch
        player.distance = math.max(0, branch.length - 40)
        player.lateral = 0.3
        player.prevDistance, player.prevLateral = player.distance, player.lateral
        AK.Race.controls.accelerate = true

        -- PURE ROUTE LOOKUPS ONLY. RaceUI:RoadAt runs the answer through
        -- Bend, which accumulates from the CAMERA along whichever road the
        -- camera is on -- so comparing it either side of a route change
        -- compares two different coordinate spaces and means nothing. Width
        -- and height are properties of the road itself at a distance along it,
        -- which is exactly what has to line up at a junction.
        local lastWidth, lastHeight, crossed = nil, nil, false
        for _ = 1, math.ceil(6 / FRAME) do
          Race:Update(FRAME)
          if not Race.current then break end
          local route = player.route or track
          local width = AK.Math.RoadWidth(route, player.distance)
          local height = AK.Math.RoadHeight(route, player.distance)
          if route == track and not crossed and lastWidth then
            -- The frame the rejoin happened.
            crossed = true
            local jumpW = math.abs(width - lastWidth)
            if jumpW > worstWidth then worstWidth, worstAt = jumpW, id end
            -- A step in the road's HEIGHT is a visible drop through the floor.
            assert(math.abs(height - lastHeight) < 1.2,
              ("%s: the road height stepped %.2f metres at the rejoin")
                :format(id, math.abs(height - lastHeight)))
          end
          lastWidth, lastHeight = width, height
        end
        AK.Race.controls.accelerate = false
        assert(crossed, id .. ": the kart never came off the branch")
      end
      Race:Stop(true)
    end
    assert(checked >= 3, "only " .. checked .. " circuits with a branch were exercised")
    say(("        %d shortcuts rejoined; worst width step %.3f (%s)")
      :format(checked, worstWidth, tostring(worstAt)))
    -- A branch is narrower than the road it leaves, so SOME step is expected --
    -- but the road must not double in width on one tick.
    assert(worstWidth < 0.45,
      ("the road width jumped by %.2f at a rejoin (%s)"):format(worstWidth, tostring(worstAt)))
  end)

  -- THE WHOLE HANDSHAKE, HOST AND JOINER, IN ORDER.
  --
  -- The packet check above proves one message parses. It does not prove that
  -- pressing the four buttons on PARTY & RAID RACING in the order a person
  -- presses them actually gets two people onto a grid -- and that is the only
  -- thing that matters on the day of a test. This plays both ends: the host
  -- opens a lobby, the joiner asks who is out there, joins, the roster comes
  -- back, the host starts, and the joiner's throttle reaches the host.
  ok("two clients get onto the same grid, and the joiner's throttle arrives", function()
    local Net = AK.Net
    local realSend = C_ChatInfo.SendAddonMessage
    -- Two "clients" are the same Lua state wearing different names, so the
    -- name function is swapped rather than the addon being loaded twice.
    local who = "Host-Testrealm"
    local realName = Net.PlayerName
    Net.PlayerName = function() return who end

    -- The wire. Everything sent is queued; delivering it means handing it to
    -- HandleMessage as the OTHER client.
    local wire = {}
    C_ChatInfo.SendAddonMessage = function(_, message, _, target)
      wire[#wire + 1] = { from = who, message = message, target = target }
      return true
    end
    --- Deliver everything on the wire to `to`, skipping what they sent
    --- themselves and anything whispered to somebody else.
    local function deliverTo(to)
      local queue = wire
      wire = {}
      local was = who
      who = to
      for _, packet in ipairs(queue) do
        if packet.from ~= to and (not packet.target or packet.target == to) then
          Net:HandleMessage(packet.message, packet.from)
        end
      end
      who = was
    end
    local function asHost(fn) who = "Host-Testrealm" return fn() end
    local function asGuest(fn) who = "Guest-Testrealm" return fn() end

    -- Two separate clients keep separate lobby state; one Lua state does not,
    -- so each side's fields are parked while the other is talking.
    local side = { ["Host-Testrealm"] = {}, ["Guest-Testrealm"] = {} }
    local function swapIn(name)
      side[who].lobby, side[who].available = Net.lobby, Net.availableLobby
      who = name
      Net.lobby, Net.availableLobby = side[name].lobby, side[name].available
    end

    Net.lobby, Net.availableLobby = nil, nil
    AK.db.selection.racer, AK.db.selection.kart = "thrall", "mechano"

    -- 1. The host opens a lobby.
    asHost(function()
      assert(Net:OpenLobby(), "OpenLobby failed in a party")
      assert(Net.lobby and Net.lobby.host == "Host-Testrealm", "no lobby after OpenLobby")
    end)

    -- 2. The joiner presses REFRESH LOBBIES and hears about it.
    swapIn("Guest-Testrealm")
    deliverTo("Guest-Testrealm")
    assert(Net.availableLobby, "the joiner never heard the lobby announcement")
    assert(Net.availableLobby.host == "Host-Testrealm",
      "the announcement named " .. tostring(Net.availableLobby.host))

    -- 3. The joiner joins, and the host takes them onto the roster.
    Net:JoinLobby()
    local guestLobby, guestAvailable = Net.lobby, Net.availableLobby
    swapIn("Host-Testrealm")
    deliverTo("Host-Testrealm")
    assert(Net.lobby.roster["Guest-Testrealm"],
      "the JOIN never reached the host's roster")
    assert(Net.lobby.roster["Guest-Testrealm"].kart == "mechano",
      "the joiner's kart did not survive the JOIN")

    -- 4. The roster comes back and the joiner can see themselves on it.
    side["Guest-Testrealm"].lobby = guestLobby
    side["Guest-Testrealm"].available = guestAvailable
    swapIn("Guest-Testrealm")
    deliverTo("Guest-Testrealm")
    assert(Net.availableLobby and Net.availableLobby.roster
      and Net.availableLobby.roster["Guest-Testrealm"],
      "the joiner never saw themselves on the host's roster -- "
      .. "the lobby screen can never say they are in")

    -- 5. The host starts. The joiner has to end up in the same session.
    swapIn("Host-Testrealm")
    Net:StartLobbyRace()
    assert(AK.Race.current and AK.Race.current.network
      and AK.Race.current.network.isHost, "the host is not hosting a race")
    local session = AK.Race.current.network.session
    local hostRace = AK.Race.current

    swapIn("Guest-Testrealm")
    AK.Race.current = nil
    deliverTo("Guest-Testrealm")
    assert(AK.Race.current, "START never put the joiner into a race")
    assert(AK.Race.current.network.session == session,
      "the joiner is racing a different session from the host")
    assert(AK.Race.current.network.isHost == false, "the joiner thinks it is the host")
    local guestRace = AK.Race.current

    -- 6. THE THROTTLE. The host drives every remote player from what arrives
    --    here, and this used to carry steering only -- so a joiner on the
    --    host's machine was permanently flat out and could not lift or brake.
    guestRace.delta = 1
    Net.inputClock = 99
    AK.Race.controls.accelerate, AK.Race.controls.brake = false, true
    AK.Race.controls.left, AK.Race.controls.right = true, false
    Net:SendInput(guestRace)
    AK.Race.controls.accelerate, AK.Race.controls.brake = false, false
    AK.Race.controls.left = false

    swapIn("Host-Testrealm")
    AK.Race.current = hostRace
    deliverTo("Host-Testrealm")
    local input = hostRace.remoteInputs["Guest-Testrealm"]
    assert(input, "the host received no input from the joiner at all")
    assert(input.left == true, "the joiner's steering did not arrive")
    assert(input.throttleAware, "the host cannot tell that the throttle was sent")
    assert(input.accelerate == false,
      "the host thinks the joiner is on the throttle when they have lifted off")
    assert(input.brake == true, "the joiner's brake did not arrive")

    say(("        host + joiner on session %s; steering, throttle and brake all arrive")
      :format(tostring(session)))

    AK.Race:Stop(true)
    Net.lobby, Net.availableLobby = nil, nil
    Net.PlayerName = realName
    C_ChatInfo.SendAddonMessage = realSend
  end)

  -- MULTIPLAYER WHEN THINGS GO WRONG.
  --
  -- The handshake check proves the happy path. Nobody tests the happy path in
  -- a party of eight: somebody double-clicks JOIN, somebody's reply is dropped,
  -- somebody alt-tabs into a loading screen, the host closes the game. Every
  -- one of those used to be silent -- the worst possible behaviour, because the
  -- person it happens to cannot tell it from the addon being broken.
  ok("multiplayer survives a party behaving like a party", function()
    local Net, Race = AK.Net, AK.Race
    local realSend = C_ChatInfo.SendAddonMessage
    local sent = {}
    C_ChatInfo.SendAddonMessage = function(_, message, _, target)
      sent[#sent + 1] = { message = message, target = target }
      return true
    end
    local function lastOfKind(kind)
      for i = #sent, 1, -1 do
        local m = sent[i].message
        if m:sub(1, #kind + 1) == kind .. "\t" then return m end
      end
    end
    local said = {}
    local realPrint = AK.Print
    AK.Print = function(_, text) said[#said + 1] = tostring(text) end
    local function saidSomethingAbout(word)
      for _, line in ipairs(said) do if line:lower():find(word, 1, true) then return true end end
      return false
    end

    -- 1. A FULL GRID TURNS THE NEXT ONE AWAY, and says so.
    Net.lobby = { id = "S9", host = "Host-Testrealm", track = "elwynn", roster = {} }
    for i = 1, AK.MAX_RACERS do
      Net.lobby.roster["P" .. i] = { name = "P" .. i, racer = "baine", kart = "kodo" }
    end
    wipe(sent)
    Net:HandleMessage("JOIN\tS9\tLatecomer\tthrall\tmechano", "Latecomer")
    assert(not Net.lobby.roster.Latecomer, "a ninth racer got onto an eight-kart grid")
    assert(lastOfKind("FULL"), "the grid was full and nobody was told")

    -- 2. A DOUBLE-CLICKED JOIN is one racer, not two, and is not announced
    --    twice.
    Net.lobby.roster = { ["Host-Testrealm"] = { name = "Host-Testrealm", racer = "baine", kart = "kodo" } }
    said = {}
    Net:HandleMessage("JOIN\tS9\tGuest\tthrall\tmechano", "Guest")
    Net:HandleMessage("JOIN\tS9\tGuest\tthrall\tmechano", "Guest")
    local size = 0
    for _ in pairs(Net.lobby.roster) do size = size + 1 end
    assert(size == 2, "a double-clicked JOIN put " .. size .. " racers on a two-kart grid")
    local joins = 0
    for _, line in ipairs(said) do if line:find("joined the pit lane", 1, true) then joins = joins + 1 end end
    assert(joins == 1, "a double-clicked JOIN was announced " .. joins .. " times")

    -- 3. A PACKET FOR SOMEBODY ELSE'S LOBBY is ignored outright.
    Net:HandleMessage("JOIN\tSOMEONE-ELSE\tStranger\tthrall\tmechano", "Stranger")
    assert(not Net.lobby.roster.Stranger, "a JOIN for another session reached this lobby")

    -- 4. MALFORMED AND TRUNCATED PACKETS do not throw. A thrown error inside
    --    CHAT_MSG_ADDON takes the whole event handler down with it.
    for _, junk in ipairs({ "", "JOIN", "JOIN\tS9", "JOIN\tS9\t", "STATE",
        "STATE\tS9\t", "STATE\tS9\tgarbage~~~", "INPUT\tS9",
        "ROSTER\tS9\t\t\t", "\t\t\t", "NOPE\t1\t2" }) do
      local good, err = pcall(function() Net:HandleMessage(junk, "Nuisance") end)
      assert(good, ("a malformed packet %q threw: %s"):format(junk, tostring(err)))
    end

    -- 5. THE RACE STARTED WITHOUT YOU. A client that never made it onto the
    --    roster used to get nothing at all -- no race, no message.
    Net.lobby = nil
    Net.availableLobby = { id = "S9", track = "elwynn", host = "Host-Testrealm", roster = {} }
    Race.current = nil
    said = {}
    Net:HandleMessage("START\tS9\telwynn\t12345", "Host-Testrealm")
    assert(not Race.current, "a client not on the roster was put into the race anyway")
    assert(saidSomethingAbout("without you"),
      "the race started without this client and nothing said so")

    -- 6. EVERY CLIENT ROLLS THE SAME GRID. The seed used to be local, and the
    --    AI fillers are shuffled off it -- so two people watched the same race
    --    with a different six bots in it.
    Net.availableLobby.roster = { ["Tester-Testrealm"] = { name = "Tester-Testrealm",
      racer = "thrall", kart = "mechano" } }
    Race.current = nil
    Net:HandleMessage("START\tS9\telwynn\t\t", "Host-Testrealm")
    assert(Race.current, "a rostered client did not start")
    local fromSession = {}
    for _, vehicle in ipairs(Race.current.vehicles) do
      fromSession[#fromSession + 1] = vehicle.racer.id .. "/" .. vehicle.kart.id
    end
    local seedA = Race.current.seed
    Race:Stop(true)
    -- The same session id, built again: identical grid, because the seed comes
    -- from the session rather than from the clock. The lobby has to be put back
    -- first -- entering a race clears it, exactly as it does for a real client.
    Race.current = nil
    Net.availableLobby = { id = "S9", track = "elwynn", host = "Host-Testrealm",
      roster = { ["Tester-Testrealm"] = { name = "Tester-Testrealm",
        racer = "thrall", kart = "mechano" } } }
    Net:HandleMessage("START\tS9\telwynn\t\t", "Host-Testrealm")
    assert(Race.current, "the same client could not rejoin the same session")
    assert(Race.current.seed == seedA, "two clients on one session rolled different seeds")
    for index, vehicle in ipairs(Race.current.vehicles) do
      local now = vehicle.racer.id .. "/" .. vehicle.kart.id
      assert(now == fromSession[index],
        ("grid slot %d is %s on one client and %s on the other")
          :format(index, fromSession[index], now))
    end
    Race:Stop(true)

    -- 7. A PLAYER WHO STOPS SENDING is handed to the AI, not left flooring it.
    Race:Start("quick", { track = "elwynn" })
    local race = Race.current
    race.network = { isHost = true, session = "S9", host = "Tester-Testrealm" }
    local remote = race.vehicles[2]
    remote.owner = "Ghosted-Testrealm"
    remote.networkId = remote.owner
    race.remoteInputs[remote.owner] = { left = false, right = false, accelerate = false,
      brake = true, throttleAware = true }
    race.remoteHeard = { [remote.owner] = GetTime() - 30 }
    said = {}
    for _ = 1, math.ceil(4 / FRAME) do Race:Update(FRAME) end
    assert(remote.abandoned, "a player silent for thirty seconds was still being driven by their last packet")
    assert(remote.ai, "the abandoned kart was not handed to the AI")
    assert(saidSomethingAbout("dropped out"), "nothing said the player had dropped out")
    Race:Stop(true)

    -- 8. ONE PRESS IS ONE ITEM. The last input table a remote player sent
    --    stays in place until the next one, and physics runs at 120Hz -- so a
    --    single tap used to fire on every tick until the next packet.
    Race:Start("quick", { track = "elwynn" })
    local host = Race.current
    host.network = { isHost = true, session = "S9", host = "Tester-Testrealm" }
    local shooter = host.vehicles[3]
    shooter.owner = "Trigger-Testrealm"
    shooter.networkId = shooter.owner
    shooter.item = "triple_green_shell"
    host.remoteInputs[shooter.owner] = { accelerate = true, throttleAware = true,
      itemPulse = true }
    host.remoteHeard = { [shooter.owner] = GetTime() }
    local fired = 0
    local realTrigger = AK.TriggerItem
    AK.TriggerItem = function(selfRef, r, v)
      if v == shooter then fired = fired + 1 end
      return realTrigger(selfRef, r, v)
    end
    for _ = 1, 8 do Race:Update(FRAME) end
    AK.TriggerItem = realTrigger
    assert(fired <= 1,
      ("one item press fired %d times -- a triple shell empties on a tap"):format(fired))
    Race:Stop(true)

    -- 9. THE HOST CAN LEAVE, and the client has to notice. Snapshots simply
    --    stop; there is no goodbye packet and there cannot be one.
    Race:Start("quick", { track = "elwynn" })
    local client = Race.current
    client.network = { isHost = false, session = "S9", host = "Gone-Testrealm" }
    client.lastSnapshot = GetTime() - 60
    said = {}
    Race:Update(FRAME)
    assert(not (Race.current and Race.current.network),
      "the host went away and the client raced on against nobody")
    assert(saidSomethingAbout("lost the host"), "nothing said the host had gone")

    AK.Print = realPrint
    Net.lobby, Net.availableLobby = nil, nil
    C_ChatInfo.SendAddonMessage = realSend
    say("        full grid, double joins, junk packets, a missed start, "
      .. "a dropout and a vanished host: all handled and all reported")
  end)

  -- WHAT MULTIPLAYER ACTUALLY PUTS ON THE WIRE, PER SECOND.
  --
  -- Addon chat is rate limited by the server, and an addon that ignores that
  -- does not get an error -- messages are dropped, or the client is
  -- disconnected for spamming. The community's long-standing safe figure, the
  -- one ChatThrottleLib is built around, is 800 bytes a second. Nothing here
  -- had ever counted, so the only way to find out was to hold a race with eight
  -- karts in it and see whether the host got kicked.
  ok("the wire stays inside what the addon channel will carry", function()
    if QUICK then return end
    local Net, Race = AK.Net, AK.Race
    local realSend = C_ChatInfo.SendAddonMessage
    local bytes, count, biggest = 0, 0, 0
    C_ChatInfo.SendAddonMessage = function(_, message)
      bytes = bytes + #message
      count = count + 1
      biggest = math.max(biggest, #message)
      return true
    end

    -- A full grid, hosted, driven for ten seconds of race time.
    Race:Start("quick", { track = "elwynn" })
    local race = Race.current
    race.network = { isHost = true, session = "1731020304123456", host = "Host-Testrealm" }
    for index, vehicle in ipairs(race.vehicles) do
      vehicle.ai = vehicle.ai or AK.AI:CreatePersonality(9)
      -- Worst case on the wire: every kart owned by a real player, so every
      -- networkId is a full "Name-Realm" rather than the three bytes an AI
      -- filler costs.
      vehicle.owner = ("Aaaaaaaaaaaa%d-Proudmoore"):format(index)
      vehicle.networkId = vehicle.owner
      vehicle.item = vehicle.item or "triple_green_shell"
    end
    race.byNetworkId = {}
    for _, vehicle in ipairs(race.vehicles) do
      race.byNetworkId[vehicle.networkId] = vehicle
    end

    local SECONDS = 10
    for _ = 1, math.ceil(SECONDS / FRAME) do Race:Update(FRAME) end
    local hostRate = bytes / SECONDS
    local hostMsgs = count / SECONDS
    Race:Stop(true)

    -- And a client, which whispers its input to the host.
    bytes, count = 0, 0
    Race:Start("quick", { track = "elwynn" })
    local client = Race.current
    client.network = { isHost = false, session = "1731020304123456", host = "Host-Testrealm" }
    Race.controls.accelerate = true
    for _ = 1, math.ceil(SECONDS / FRAME) do Race:Update(FRAME) end
    Race.controls.accelerate = false
    local clientRate = bytes / SECONDS
    local clientMsgs = count / SECONDS
    Race:Stop(true)
    C_ChatInfo.SendAddonMessage = realSend

    say(("        host %.0f B/s in %.1f msg/s (largest %d B); "
      .. "each client %.0f B/s in %.1f msg/s")
      :format(hostRate, hostMsgs, biggest, clientRate, clientMsgs))

    -- 255 is a hard limit: a longer addon message is dropped silently.
    assert(biggest <= 255,
      ("a %d byte packet goes on the wire; anything over 255 is dropped silently")
        :format(biggest))
    -- 800 B/s is the safe sustained rate. The host is the one at risk: it is
    -- the only machine sending to everybody.
    assert(hostRate <= 800,
      ("the host sends %.0f bytes a second, which is over what the addon "
        .. "channel will carry"):format(hostRate))
    assert(clientRate <= 800,
      ("a client sends %.0f bytes a second"):format(clientRate))
  end)

  -- EVERY COMMAND THE HELP TEXT ADVERTISES HAS TO BE A COMMAND.
  --
  -- `/kart sfxset driftTier1 12345` matched nothing and opened the GARAGE,
  -- because the cue-name pattern was letters-only and every rung of the drift
  -- ladder has a digit in its name. Falling through to the menu is what made it
  -- invisible: a mistyped command and a working one looked the same.
  ok("every slash command the help text advertises works", function()
    local said = {}
    local realPrint = AK.Print
    AK.Print = function(_, text) said[#said + 1] = tostring(text) end
    local function run(command)
      wipe(said)
      SlashCmdList["AZEROTHKART"](command)
      for _, line in ipairs(said) do
        assert(not line:find("is not a command"),
          ("/kart %s is advertised but not handled"):format(command))
      end
    end

    -- One with a digit in the cue name for every command that takes one: that
    -- is the case that was broken.
    for _, command in ipairs({
      "", "help", "race", "stop", "tune", "roster", "debug", "beats",
      "trial", "aireport", "sound", "sfxedit",
      "sfx", "sfx driftTier1", "sfx boost",
      "sfxrate driftTier3", "sfxreport", "sfxstop",
      "sfxset driftTier2 12345", "sfxclear driftTier2",
      "sfxmute", "sfxmute driftTier1", "sfxunmute",
      "sfxid 566000", "sfxtest 566000", "sfxdensity 566000",
      "npc 36648",
    }) do run(command) end

    -- And a genuine typo must SAY so rather than opening a menu.
    wipe(said)
    SlashCmdList["AZEROTHKART"]("sfxsett driftTier1 1")
    local complained = false
    for _, line in ipairs(said) do
      if line:find("is not a command") then complained = true end
    end
    AK.Print = realPrint
    assert(complained, "a mistyped command was swallowed instead of reported")
    AK.Race:Stop(true)
    if AK.Debug.frame and AK.Debug.frame:IsShown() then AK.Debug:Toggle() end
    if AK.Workshop.frame and AK.Workshop.frame:IsShown() then AK.Workshop:Toggle() end
    if AK.SoundEditor.frame and AK.SoundEditor.frame:IsShown() then AK.SoundEditor:Toggle() end
    AK.Menu:Hide()
    say(("        %d commands dispatched, typos reported"):format(27))
  end)

  -- A GRAND PRIX IS THE HEADLINE ITEM ON THE MENU AND NOTHING HAD EVER RUN ONE.
  --
  -- Four races, one points table, one trophy -- and no check anywhere started
  -- a cup, let alone finished one. So the between-races screen could show the
  -- player nothing about the cup they were running (it did), and the
  -- completion screen could put the last race's winner under the cup
  -- champion's name (it did).
  ok("a grand prix runs all four races and crowns the right champion", function()
    AK.db.selection.cup = "wild"
    AK.Race:StartGrandPrix()
    local cup = AK.Race.current.grandPrix.cup
    local seen = {}
    for round = 1, #cup.tracks do
      local race = AK.Race.current
      assert(race and race.grandPrix, "round " .. round .. " is not a grand prix race")
      assert(race.grandPrix.index == round,
        ("round %d thinks it is race %d"):format(round, race.grandPrix.index))
      seen[#seen + 1] = race.track.id
      -- Run it to the flag the way the game does, rather than faking a finish:
      -- the points come off race.positions, which only the real finish fills.
      race.state = AK.RACE_STATES.RACING
      for index, vehicle in ipairs(race.vehicles) do
        vehicle.finished = true
        vehicle.finishTime = 90 + index
        vehicle.lap = race.laps
      end
      AK.Race:UpdatePositions(race)
      AK.Race:FinishRace(race)
      AK.Results:Show(race)
      -- The cup line has to say where the player stands, from race one.
      local line = AK.Results.cupLine:GetText() or ""
      assert(line:find("RACE " .. round .. " OF " .. #cup.tracks),
        ("the results screen after race %d does not say which race it was: %q")
          :format(round, line))
      assert(line:find("YOU ARE"),
        ("the results screen after race %d never says where you stand in the cup")
          :format(round))
      AK.Race:NextGrandPrix()
    end

    -- Every circuit in the cup, in order, and no repeats.
    for index, id in ipairs(cup.tracks) do
      assert(seen[index] == id,
        ("race %d ran %s, the cup says %s"):format(index, tostring(seen[index]), id))
    end
    assert(AK.db.progress.trophies[cup.id], "winning the cup awarded no trophy")
    assert(AK.db.progress.achievements.cup_champion,
      "winning the cup did not unlock Realm First!")
    assert((AK.Results.title:GetText() or ""):find("WON"),
      ("the podium for a cup the player won reads %q")
        :format(tostring(AK.Results.title:GetText())))

    -- And the champion on the podium is the champion in the table.
    local gp = AK.Results.lastGrandPrix
    local top, topPoints
    for key, points in pairs(gp.points) do
      local shown = (gp.names and gp.names[key]) or key
      if not topPoints or points > topPoints
        or (points == topPoints and shown < top) then top, topPoints = shown, points end
    end
    -- "player" is this file's own sentinel for the local kart, not anybody's
    -- name, and it used to be what the trophy screen printed.
    assert(top ~= "player", "the cup champion is the string \"player\"")
    assert(AK.Results.winnerName:GetText() == top,
      ("the podium says %q, the points table says %q"):format(
        tostring(AK.Results.winnerName:GetText()), tostring(top)))
    say(("        %s: %d races, champion %s on %d points"):format(
      cup.name, #cup.tracks, top, topPoints))
    AK.Results:Hide()
    AK.Race:Stop(true)
    AK.Menu:Hide()
  end)

  -- AND THE CUP THE PLAYER LOSES.
  --
  -- The check above drives a cup the player wins every race of, which is the
  -- easy half: it passed just as happily when the trophy was handed out for
  -- turning up. This one comes LAST in every race of a different cup and
  -- insists that nothing is awarded, nothing is unlocked, and the screen does
  -- not congratulate anybody.
  ok("losing a cup awards no trophy", function()
    AK.db.progress.trophies = {}
    AK.db.progress.achievements = {}
    AK.db.selection.cup = "frontier"
    AK.Race:StartGrandPrix()
    local cup = AK.Race.current.grandPrix.cup
    for _ = 1, #cup.tracks do
      local race = AK.Race.current
      race.state = AK.RACE_STATES.RACING
      -- Reverse of the winning run: the player is vehicles[1], so give that
      -- kart the SLOWEST time and the field comes home ahead of it every time.
      local count = #race.vehicles
      for index, vehicle in ipairs(race.vehicles) do
        vehicle.finished = true
        vehicle.finishTime = 90 + (count - index + 1)
        vehicle.lap = race.laps
      end
      AK.Race:UpdatePositions(race)
      assert(race.positions[race.player] == count,
        ("the player should be last, the table says %s")
          :format(tostring(race.positions[race.player])))
      AK.Race:FinishRace(race)
      AK.Race:NextGrandPrix()
    end
    assert(not AK.db.progress.trophies[cup.id],
      "coming last in every race of a cup still put a trophy in the garage")
    assert(not AK.db.progress.achievements.cup_champion,
      "coming last in every race of a cup still unlocked Realm First!")
    local gp = AK.Results.lastGrandPrix
    assert(gp and gp.won == false, "the cup does not know it was lost")
    assert(gp.yourPlace and gp.yourPlace > 1,
      ("the player placed %s in a cup they lost every race of")
        :format(tostring(gp.yourPlace)))
    local title = AK.Results.title:GetText() or ""
    assert(not title:find("WON"),
      ("the podium for a lost cup reads %q"):format(title))
    local reward = AK.Results.reward:GetText() or ""
    assert(not reward:find("UNLOCKED"),
      ("a lost cup still says %q"):format(reward))
    -- And the row the player is actually looking for is marked.
    local marked = 0
    for index = 1, AK.Results.rowCount do
      if AK.Results.rows[index].accent.akShown then marked = marked + 1 end
    end
    assert(marked >= 2,
      ("the championship table marks %d rows; the leader and the player are two")
        :format(marked))
    -- THE TABLE MUST FIT THE SCREEN. Every round of a cup used to roll its own
    -- grid, so the points table accumulated everyone who had ever started --
    -- ten competitors in eight rows, with the player off the bottom of their
    -- own trophy screen.
    assert(#gp.standings <= #AK.Results.rows,
      ("%d competitors in a table with %d rows: the cup changed its field")
        :format(#gp.standings, #AK.Results.rows))
    assert(gp.yourPlace <= #AK.Results.rows, "the player is off the bottom of the table")
    say(("        %s: player %s of %d, no trophy")
      :format(cup.name, tostring(gp.yourPlace), AK.Results.rowCount))
    AK.Results:Hide()
    AK.Race:Stop(true)
    AK.Menu:Hide()
  end)

  ok("the menu, the workshop and the sound editor all build", function()
    AK.Menu:Build()
    AK.Menu:Show()
    -- EVERY PAGE, not just the one Show lands on. Settings, the four
    -- selection grids, the trophy room and the lobby are all built lazily the
    -- first time you open them, so a nil concatenated into a label on any of
    -- them was reachable only by a human clicking the button. The settings
    -- page in particular is the one with per-row logic in it.
    AK.Menu:ShowSettings()
    for _, kind in ipairs({ "racer", "kart", "track", "cup" }) do
      AK.Menu:ShowSelection(kind)
    end
    AK.Menu:ShowAchievements()
    AK.Menu:ShowMultiplayer()
    AK.Menu:ShowHome()
    AK.Menu:Hide()
    AK.Workshop:Toggle()
    AK.Workshop:Toggle()
    if AK.SoundEditor and AK.SoundEditor.Toggle then
      AK.SoundEditor:Toggle()
      AK.SoundEditor:Toggle()
    end
  end)

  -- WHAT ACTUALLY HAPPENS IN A RACE.
  --
  -- Every other harness answers this from a mirror -- a reimplementation of the
  -- physics in JavaScript, which is only ever as honest as the reimplementation.
  -- This is the real engine: real items, real collisions, real resets. It
  -- reports rather than merely passing, because the numbers are the point.
  ok("a real race produces a sane race", function()
    if QUICK then return end
    local report = {}
    for _, id in ipairs({ "elwynn", "durotar", "ironforge" }) do
      local race = driveRace(id, 60 * 5)
      assert(race.state == AK.RACE_STATES.FINISHED, id .. " never reached the flag")
      assertFieldIsHome(race, id)
      local times, hits = {}, 0
      local resets = race.akResets or 0
      for _, v in ipairs(race.vehicles) do
        if v.finishTime then times[#times + 1] = v.finishTime end
        hits = hits + (v.hazardHits or 0)
      end
      table.sort(times)
      local spread = (#times > 1) and (times[#times] - times[1]) or 0
      report[#report + 1] = { id = id, laps = race.laps, winner = times[1] or 0,
        spread = spread, finishers = #times, resets = resets, hits = hits,
        best = race.player.bestLap, place = race.positions[race.player] or 0,
        draws = race.akDrawsPerFrame or 0, falls = race.akFallSections }
      AK.Race:Stop(true)
    end
    say("")
    say("        circuit         winner    spread  crossed   place   resets   hits   best lap    draws/frame")
    for _, r in ipairs(report) do
      say(("        %-14s %7.1fs %8.1fs %8d %7d %8d %6d %10s %14d"):format(
        r.id, r.winner, r.spread, r.finishers, r.place, r.resets, r.hits,
        r.best and ("%.2fs"):format(r.best) or "none", r.draws))
      -- Name the two worst offenders, so a reset count has somewhere to point.
      local worst = {}
      for name, count in pairs(r.falls or {}) do worst[#worst + 1] = { name, count } end
      table.sort(worst, function(a, b) return a[2] > b[2] end)
      if worst[1] then
        local parts = {}
        for index = 1, math.min(3, #worst) do
          parts[#parts + 1] = ("%s x%d"):format(worst[index][1], worst[index][2])
        end
        say(("                 off the road at: %s"):format(table.concat(parts, ",  ")))
      end
      assert(r.place > 0 and r.place <= AK.MAX_RACERS,
        r.id .. ": the player finished in position " .. r.place)
      assert(r.winner > 40 and r.winner < 300,
        r.id .. ": winning time of " .. ("%.1f"):format(r.winner) .. "s is not a kart race")
      assert(r.finishers == AK.MAX_RACERS,
        r.id .. ": only " .. r.finishers .. " of " .. AK.MAX_RACERS .. " racers finished")
      -- Everyone who crossed did so in a tight window. A field strung out over
      -- half the race is not a race.
      assert(r.spread < r.winner * 0.45,
        r.id .. ": the finishers were spread over " .. ("%.0f"):format(r.spread) .. "s")
      assert(r.resets < AK.MAX_RACERS * 12,
        r.id .. ": the field fell off the world " .. r.resets .. " times")
      assert(r.best and r.best > 15 and r.best < 120,
        r.id .. ": the player's best lap was " .. tostring(r.best))
    end
    say("")
  end)

  -- WHERE THE FRAME GOES.
  --
  -- A single number for widget traffic says a frame is expensive; it does not
  -- say what to do about it. This wraps each render phase, counts the calls it
  -- makes, and prints the bill -- so the next optimisation is aimed at the
  -- thing that actually costs, rather than at whatever looks slow.
  ok("a frame's cost is accounted for", function()
    if QUICK then return end
    local race = driveRace("elwynn", 25)
    local phases = { "RenderSky", "RenderArches", "RenderPosts", "RenderFinish",
      "RenderSpectators", "RenderProps", "RenderFork", "RenderRoad", "RenderObjects",
      "RenderHazards", "RenderGhost", "RenderProjectiles", "RenderKarts",
      "UpdateParticles", "UpdateEffects", "RenderWeather", "UpdatePresentation",
      "UpdateLadder" }
    local totals, originals = {}, {}
    for _, name in ipairs(phases) do
      local fn = AK.RaceUI[name]
      originals[name] = fn
      AK.RaceUI[name] = function(selfRef, ...)
        local before = widgetCalls
        local a, b = fn(selfRef, ...)
        totals[name] = (totals[name] or 0) + (widgetCalls - before)
        return a, b
      end
    end
    local before = widgetCalls
    AK.Race:Update(FRAME)
    local total = widgetCalls - before
    for name, fn in pairs(originals) do AK.RaceUI[name] = fn end

    local rows, accounted = {}, 0
    for name, count in pairs(totals) do
      if count > 0 then rows[#rows + 1] = { name, count } end
      accounted = accounted + count
    end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    say("")
    say(("        one frame of Elwynn costs %d widget calls"):format(total))
    for _, row in ipairs(rows) do
      say(("        %-22s %6d  %4.1f%%"):format(row[1], row[2], row[2] / total * 100))
    end
    say(("        %-22s %6d  %4.1f%%"):format("everything else", total - accounted,
      (total - accounted) / total * 100))
    say("")
    assert(total > 0, "a frame apparently cost nothing, so the counter is broken")
    AK.Race:Stop(true)
  end)

  -- THE PAUSE MENU IS THE ONE SCREEN EVERY PLAYER OPENS MID-RACE.
  --
  -- It has two controls that come and go -- RESTART, which is meaningless in a
  -- race other people are in, and the developer row -- and it used to be a
  -- fixed-height box with everything at a hand-measured offset, so hiding
  -- either left a hole in the stack and a void underneath it. It also lets go
  -- of a Grand Prix, which is four races and a points table, and did so on one
  -- unconfirmed click.
  ok("the pause menu has no holes in it, and a cup asks before it goes", function()
    local RaceUI, Race = AK.RaceUI, AK.Race
    local GAP, BOTTOM = 6, 22

    --- Pause a race and read the panel back as a list of visible rows.
    local function pauseAnd(options, dev)
      AK.db.settings.debug = dev and true or false
      Race:Start(options.mode or "quick", options)
      -- ESC ON THE GRID. This did nothing at all until now: the race frame
      -- grabs the keyboard, so the client's own escape never fired either, and
      -- the player sat in a fullscreen window with the HUD telling them to
      -- press a key that was not connected to anything.
      Race:OnKey("ESCAPE", true)
      assert(Race.current.state == AK.RACE_STATES.PAUSED,
        "ESC during the countdown did not pause")
      Race:OnKey("ESCAPE", true)
      assert(Race.current.state == AK.RACE_STATES.COUNTDOWN,
        "resuming from the grid did not hand back the countdown")
      for _ = 1, math.ceil(3.4 / FRAME) do Race:Update(FRAME) end
      assert(Race.current.state == AK.RACE_STATES.RACING, "the lights never went green")
      Race:TogglePause()
      Race:Update(FRAME)
      assert(RaceUI.pause.akHidden ~= true, "the pause panel did not come up")
      return RaceUI
    end

    --- Every visible control on the panel, top edge first.
    local function rows()
      local out = {}
      for _, button in ipairs(RaceUI.pauseStack) do
        if not button.akHidden then
          out[#out + 1] = { name = button.label.akText, top = -button.akY, h = button.akHeight }
        end
      end
      return out
    end

    local function noHoles(what)
      local list = rows()
      assert(#list >= 2, what .. ": the pause menu has " .. #list .. " controls on it")
      for i = 2, #list do
        local expected = list[i - 1].top + list[i - 1].h + GAP
        assert(math.abs(list[i].top - expected) < 0.5,
          ("%s: %s sits %.0fpx down, leaving a %.0fpx hole under %s"):format(
            what, tostring(list[i].name), list[i].top, list[i].top - expected,
            tostring(list[i - 1].name)))
      end
      return list[#list].top + list[#list].h
    end

    -- A single race, shipped settings: three buttons, no tool row, and the
    -- panel ends just under the last of them.
    pauseAnd({ track = "elwynn" }, false)
    local bottom = noHoles("a quick race")
    for _, tool in ipairs(RaceUI.pauseTools) do
      assert(tool.akHidden, "a developer button is on the shipped pause menu")
    end
    local height = RaceUI.pausePanel.akHeight
    assert(math.abs(height - (bottom + BOTTOM)) < 0.5,
      ("the panel is %.0f tall for %.0f of controls -- a %.0fpx void"):format(
        height, bottom, height - bottom - BOTTOM))
    assert(RaceUI.pauseQuit.label.akText == "QUIT TO MENU",
      "a single race asks before letting go of itself")
    Race:Stop(true)

    -- Developer tools on: the row appears and the panel grows to hold it.
    pauseAnd({ track = "elwynn" }, true)
    local devBottom = noHoles("with developer tools on")
    for _, tool in ipairs(RaceUI.pauseTools) do
      assert(not tool.akHidden, "the developer row did not come back")
      assert(-tool.akY > devBottom,
        "a developer button is printed through the buttons above it")
      assert(-tool.akY + tool.akHeight + 1 < RaceUI.pausePanel.akHeight,
        "the developer row hangs off the bottom of the panel")
    end
    Race:Stop(true)

    -- A GRAND PRIX ARMS BEFORE IT QUITS.
    local cup = AK.Cups and AK.Cups[1]
    assert(cup, "there are no cups")
    local gp = { cup = cup, index = 1, points = {}, names = {} }
    pauseAnd({ mode = "grand_prix", track = cup.tracks[1], grandPrix = gp }, false)
    local quit = RaceUI.pauseQuit
    assert(quit.label.akText == "ABANDON CUP",
      "the cup's quit button says '" .. tostring(quit.label.akText) .. "'")
    quit:akClick()
    assert(Race.current and Race.current.grandPrix,
      "one click threw the whole Grand Prix away")
    assert(quit.label.akText ~= "ABANDON CUP", "the armed button says nothing new")
    quit:akClick()
    -- Leaving shows the menu, and the menu starts the attract demo behind
    -- itself -- so "gone" is "no longer the Grand Prix", not "no race at all".
    assert(not (Race.current and Race.current.grandPrix),
      "the second click did not leave the cup")

    -- ...and the arming does not survive into the next pause.
    pauseAnd({ mode = "grand_prix", track = cup.tracks[1], grandPrix = gp }, false)
    assert(not RaceUI.pauseQuit.armed, "the cup came back already armed to quit")
    Race:Stop(true)
    AK.db.settings.debug = false
  end)

  -- A BATTLE, FOUGHT TO THE LAST BALLOON.
  --
  -- The mode had never been driven by anything but a person: the arena pool,
  -- the balloon rules and the standings were all reached only through the
  -- BATTLE button. Both of the things that were wrong with it were invisible
  -- from the code and obvious from one fight -- the winner was ranked last, and
  -- the balloon count the whole mode turns on was on no screen anywhere.
  -- FOUGHT MORE THAN ONCE. A battle is decided entirely by items landing on
  -- people, so whether it resolves at all is a question about the AI and the
  -- item roll, not about one lucky arena -- and "sometimes it never ends" is
  -- exactly the sort of thing a single run reports as a pass.
  ok("a battle ends with the last kart standing on top", function()
    if QUICK then return end
    local Race = AK.Race
    local durations = {}
    for fight = 1, 3 do
    Race:StartBattle()
    local race = Race.current
    assert(race and race.battle, "no battle after StartBattle")
    assert(race.track and race.track.id, "a battle was built with no arena")
    for _, vehicle in ipairs(race.vehicles) do
      vehicle.ai = vehicle.ai or AK.AI:CreatePersonality(9)
      assert(vehicle.balloons == AK.BATTLE_BALLOONS,
        "a kart lined up with " .. tostring(vehicle.balloons) .. " balloons")
    end

    -- The HUD says the two things the mode is about, from the first frame.
    Race:Update(FRAME)
    assert(AK.RaceUI.lapWord.akText == "BALLOONS",
      "the arena HUD still says '" .. tostring(AK.RaceUI.lapWord.akText) .. "'")
    assert(AK.RaceUI.lap.akText == tostring(AK.BATTLE_BALLOONS),
      "the balloon count reads '" .. tostring(AK.RaceUI.lap.akText) .. "'")
    assert(AK.RaceUI.positionOf.akText == "STILL IN",
      "the arena HUD prints a lap-race field size")

    -- Fight it. Nobody may be forced out by hand: the balloons have to come off
    -- through the mode's own rules or the ranking proves nothing.
    local guard, sawPlayerOut = 0, false
    while race.state ~= AK.RACE_STATES.FINISHED and guard < math.ceil(300 / FRAME) do
      Race:Update(FRAME)
      guard = guard + 1
      if race.player.eliminated then sawPlayerOut = true end
      -- A BATTLE NEVER GOES INTO A COOLDOWN LAP. Being knocked out sets the
      -- same `finished` flag that crossing a line does, which used to start the
      -- bring-the-field-home fast-forward -- dimmed world, FINISHING ORDER
      -- panel and all -- on top of a fight that was still being had.
      assert(race.state ~= AK.RACE_STATES.COOLDOWN,
        "the arena went into a cooldown lap")
    end
    assert(race.state == AK.RACE_STATES.FINISHED,
      "five minutes of battle and nobody was knocked out")

    local standing = 0
    for _, vehicle in ipairs(race.vehicles) do
      if not vehicle.eliminated then standing = standing + 1 end
    end
    assert(standing <= 1, standing .. " karts were still in when the battle ended")

    -- FIRST PLACE IS THE SURVIVOR, and last place went out first.
    local first, last = race.ordered[1], race.ordered[#race.ordered]
    assert(not first.eliminated or first.balloons > 0,
      "the battle was won by a kart that had already been knocked out")
    assert(last.eliminated, "the kart in last place is still holding balloons")
    for i = 2, #race.ordered do
      local ahead, behind = race.ordered[i - 1], race.ordered[i]
      if ahead.eliminated and behind.eliminated then
        assert((ahead.finishTime or 0) >= (behind.finishTime or 0),
          "a kart knocked out earlier was placed above one that lasted longer")
      end
    end
    durations[#durations + 1] = race.elapsed
    say(("        %s (%s) took the arena in %.0fs; last out was %s%s"):format(
      first.racer.name, race.track.id, race.elapsed, last.racer.name,
      sawPlayerOut and "; the player was knocked out on the way" or ""))
    Race:Stop(true)
    end
    -- A fight that takes four minutes is not a fight, it is a stalemate with
    -- an eventual winner. The mode is meant to be short.
    for _, seconds in ipairs(durations) do
      assert(seconds < 210,
        ("a battle took %.0f seconds to settle"):format(seconds))
    end
  end)

  ok("the clock formats every duration", function()
    for _, t in ipairs({ 0, 0.001, 9.99, 59.999, 60, 599.99, 3599.9, 5999 }) do
      assert(type(AK.RaceUI:FormatTime(t)) == "string", "FormatTime broke on " .. t)
    end
  end)
end

say("")
if failures > 0 then
  say(("FAIL (%d of %d)"):format(failures, checks + #files))
  os.exit(1)
end
say(("PASS (%d checks, every file loads and every pure path runs)"):format(checks))
