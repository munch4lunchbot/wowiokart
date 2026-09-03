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
    -- Show/Hide/SetShown are hot too, and they are real methods below.
    if key == "Show" or key == "Hide" or key == "SetShown" then
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
local function newWidget(kind, name, parent)
  local w = setmetatable({ akKind = kind, akName = name, akParent = parent,
    akShown = false, akPoints = {} }, widget)
  return w
end
function widget:GetWidth() return 1365 end
function widget:GetHeight() return 768 end
function widget:GetFrameLevel() return 1 end
function widget:GetEffectiveScale() return 1 end
function widget:IsShown() return self.akShown and true or false end
function widget:IsVisible() return self.akShown and true or false end
function widget:SetShown(v) self.akShown = v and true or false return self end
function widget:Show() self.akShown = true return self end
function widget:Hide() self.akShown = false return self end
function widget:CreateTexture(...) return newWidget("Texture") end
function widget:CreateFontString(...) return newWidget("FontString") end
function widget:CreateAnimationGroup(...) return newWidget("AnimGroup") end
function widget:CreateAnimation(...) return newWidget("Anim") end
function widget:GetName() return self.akName end
function widget:GetObjectType() return self.akKind end
function widget:GetText() return self.akText or "" end
function widget:SetText(t) self.akText = t return self end
function widget:GetNumPoints() return 0 end
function widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function widget:GetStringWidth() return 40 end
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
function GetTime() return os.clock() end
function GetLocale() return "enUS" end
function UnitName() return "Tester" end
function UnitClass() return "Shaman", "SHAMAN", 7 end
function UnitGUID() return "Player-1-00000001" end
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 1 end
function GetRealmName() return "Testrealm" end
function GetCVar() return "1" end
function SetCVar() end
function InCombatLockdown() return false end
function tinsert(...) return table.insert(...) end
function tremove(...) return table.remove(...) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, str)
  local out = {}
  for piece in tostring(str):gmatch("([^" .. sep .. "]*)") do out[#out + 1] = piece end
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
      driveRace(track.id, 6)
      AK.Race:Stop(true)
    end
  end)

  ok("a whole race runs to the flag", function()
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
    local race = driveRace("oribos", 60 * 5)
    assertFieldIsHome(race, "oribos")
    AK.Results:Build()
    AK.Results:Show(race)
    AK.Results:Hide()
    AK.Race:Stop(true)
  end)

  ok("the menu, the workshop and the sound editor all build", function()
    AK.Menu:Build()
    AK.Menu:Show()
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
