local _, AK = ...

local defaults = {
  settings = {
    uiScale = 1, sfx = true, engineNote = false, reducedEffects = false, difficulty = "Normal",
    aiCount = 7, showSpeed = true, showMinimap = true,
    engineClass = "150cc", mirror = false, debug = false,
  },
  -- Cue -> FileDataID chosen by ear in-game via /kart sfxset. Empty by default;
  -- anything bound here wins over the built-in candidates.
  sfxOverride = {},
  records = { bestLap = {}, bestRace = {}, ghosts = {} },
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
-- it for good -- the fix would have looked like it simply did not work.
local SETTINGS_REV = 1
local FORCED = { engineNote = false }

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
