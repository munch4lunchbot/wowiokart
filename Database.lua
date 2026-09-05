local _, AK = ...

local defaults = {
  settings = {
    uiScale = 1, sfx = true, engineNote = true, reducedEffects = false, difficulty = "Normal",
    aiCount = 7, showSpeed = true, showMinimap = true,
    engineClass = "150cc", mirror = false,
    -- DEVELOPER TOOLS. Off, and off is the shipped game: the pause menu is
    -- RESUME, RESTART and QUIT, the way a kart game's pause menu has always
    -- been. On, it also carries the live tuning panel, the presentation-beat
    -- player and the AI telemetry dump. The slash commands reach all three
    -- either way -- this decides what is on screen, not what exists.
    debug = false,
    -- How finely the road is sliced. Balanced draws about a quarter fewer
    -- strips than High and is the single biggest frame-rate dial there is;
    -- at 720p the difference is six pixels a strip against five.
    roadDetail = "Balanced",
    -- OFF. Six labelled pads across the bottom of the screen and a red QUIT in
    -- the corner is what an addon looks like, not what a game looks like, and
    -- every one of them has a key. They are still one toggle away for anyone
    -- who wants to drive with the mouse.
    showControls = false,
  },
  -- Cue -> FileDataID chosen by ear in-game via /kart sfxset. Empty by default;
  -- anything bound here wins over the built-in candidates.
  sfxOverride = {},
  -- bestLap is written on every finish; ghosts hold the Time Trial replays.
  -- `bestRace` used to sit here too and nothing ever read or wrote it -- the
  -- race total already lives in progress.bestTimes.
  records = { bestLap = {}, ghosts = {} },
  selection = { racer = "you", kart = "mechano", track = "oribos", cup = "eastern" },
  progress = { coins = 0, races = 0, wins = 0, podiums = 0, bestTimes = {}, achievements = {}, unlockedRacers = {}, unlockedKarts = {}, trophies = {} },
}

local function merge(target, source)
  for key, value in pairs(source) do
    if type(value) == "table" then
      target[key] = target[key] or {}
      merge(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
end

-- Changing a default above reaches NOBODY who has already played: merge only
-- fills keys that are missing, so a saved value outlives every later decision
-- about what the default should be. That is the same trap the tuning table
-- solved with `rev`, and settings had no equivalent.
--
-- The engine note shipped ON for one build. Measured, it was a click every
-- quarter second, and every player who raced during that build would have kept
-- it for good -- the fix would have looked like it simply did not work. So
-- revision 1 forced it back off for everybody who had raced.
--
-- Revision 2 turns it back on, because the reason it was bad has gone: the
-- engine no longer loops an interface tick. engineLow and engineHigh ask the
-- client's own SOUNDKIT table for something named like an engine, and Audio.lua
-- keeps the whole layer silent on a client where nothing of the sort exists --
-- so ON now means "an engine if this machine has one", not "a click either
-- way". Anyone who turned it off during the bad build had no reason to look at
-- it again, and would never hear the difference.
local SETTINGS_REV = 2
local FORCED = { engineNote = true }

function AK:InitDatabase()
  AzerothKartDB = AzerothKartDB or {}
  merge(AzerothKartDB, defaults)
  if (AzerothKartDB.settingsRev or 0) < SETTINGS_REV then
    for key, value in pairs(FORCED) do AzerothKartDB.settings[key] = value end
    AzerothKartDB.settingsRev = SETTINGS_REV
  end
  self.db = AzerothKartDB
  self:InitTuning()
  -- Roster edits must land BEFORE anything reads AK.Racers -- the menu, a race,
  -- or the workshop itself -- or a custom racer exists only after something
  -- happens to touch it.
  if AK.Roster then AK.Roster:Apply() end
end

function AK:UnlockAchievement(id)
  if self.db.progress.achievements[id] then return false end
  self.db.progress.achievements[id] = true
  local achievement = self.Achievements[id]
  if achievement then self:Print("|cff" .. self:ColorHex(self.COLORS.gold) .. "Achievement unlocked:|r " .. achievement.name) end
  return true
end
