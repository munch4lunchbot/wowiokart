local _, AK = ...

-- The grid used to be eight Baines. It is now a proper roster -- but Baine
-- sitting in Oribos is still the mascot, so he is entry one, the default pick,
-- and the fallback whenever a creature id fails to resolve.
--
-- Per-racer framing, because every model has a different origin and scale:
--   seatZ     nudges the model up or down in the kart (negative sinks it)
--   seatScale resizes just this racer
--   anim      overrides the sit animation; some models have no SitGround at all
-- Creature ids resolve at runtime; a bad one falls back to the flat icon.
AK.Racers = {
  { id = "baine", name = "Baine Bloodhoof", race = "Tauren", tag = "BAINE",
    model = { creature = 36648 }, icon = "Interface\\Icons\\Achievement_Character_Tauren_Male",
    seatZ = -0.15, seatScale = 0.88,
    color = { 0.55, 0.31, 0.13 }, speed = 6, acceleration = 5, handling = 6, weight = 9, drift = 6, luck = 6,
    quip = "Has not stood up since Oribos. Will not start now." },

  { id = "you", name = "Yourself", race = "You", tag = "YOU",
    model = { unit = "player" }, icon = "Interface\\Icons\\Achievement_Character_Human_Male",
    seatZ = 0.00, seatScale = 1.00,
    color = { 0.28, 0.62, 0.96 }, speed = 6, acceleration = 6, handling = 6, weight = 5, drift = 6, luck = 6,
    quip = "Your own character, seated, with all your gear on." },

  { id = "thrall", name = "Thrall", race = "Orc", tag = "THRALL",
    model = { creature = 17852 }, icon = "Interface\\Icons\\Achievement_Character_Orc_Male",
    seatZ = -0.05, seatScale = 0.92,
    color = { 0.42, 0.68, 0.30 }, speed = 7, acceleration = 6, handling = 5, weight = 7, drift = 5, luck = 5,
    quip = "The elements are, on balance, against this." },

  { id = "jaina", name = "Jaina Proudmoore", race = "Human", tag = "JAINA",
    model = { creature = 4968 }, icon = "Interface\\Icons\\Achievement_Character_Human_Female",
    seatZ = 0.08, seatScale = 1.05,
    color = { 0.62, 0.82, 0.98 }, speed = 6, acceleration = 8, handling = 8, weight = 3, drift = 7, luck = 5,
    quip = "Blinks the corners. Everyone agrees this is cheating." },

  { id = "illidan", name = "Illidan Stormrage", race = "Demon Hunter", tag = "ILLIDAN",
    model = { creature = 116697 }, icon = "Interface\\Icons\\Achievement_Character_Nightelf_Male",
    seatZ = -0.20, seatScale = 0.72, anim = 96,
    color = { 0.55, 0.28, 0.85 }, speed = 8, acceleration = 7, handling = 5, weight = 4, drift = 8, luck = 4,
    quip = "Was prepared for this. Refuses to sit down." },

  { id = "chromie", name = "Chromie", race = "Gnome", tag = "CHROMIE",
    model = { creature = 10667 }, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze",
    -- Sat visibly above the kart rather than in it. A tiny model needs zooming
    -- in (seatScale), not lifting up (seatZ) -- lifting just floats her.
    seatZ = -0.04, seatScale = 1.45,
    color = { 0.95, 0.78, 0.32 }, speed = 5, acceleration = 9, handling = 9, weight = 2, drift = 8, luck = 8,
    quip = "Already knows how this race ends. Races anyway." },

  { id = "hogger", name = "Hogger", race = "Gnoll", tag = "HOGGER",
    model = { creature = 448 }, icon = "Interface\\Icons\\Ability_Warrior_Rampage",
    seatZ = -0.08, seatScale = 0.95,
    color = { 0.72, 0.55, 0.22 }, speed = 6, acceleration = 4, handling = 4, weight = 10, drift = 4, luck = 7,
    quip = "Genuinely the hardest thing on this track." },

  -- "The Other Baine" -- a second entry with Baine's own creature id and stats
  -- under a different name -- used to sit here. It existed purely to pad the
  -- AI pool out to seven so a full grid never repeated a face, which stopped
  -- mattering the moment BuildAIField actually shuffles (see Racers.lua). Four
  -- real characters replace it; three tie directly into content already in
  -- the game rather than floating free of it.
  --
  -- Creature ids below are the best entries on hand, not verified against a
  -- live client from here. `/kart npc <id>` (Data/Models.lua's AK:PreviewNPC)
  -- and `/kart roster` (AK:ReportRoster) exist for exactly this: confirming
  -- what a creature id actually resolves to in-game and swapping in a
  -- corrected one, without needing a reload.
  { id = "mankrik", name = "Mankrik", race = "Orc", tag = "MANKRIK",
    model = { creature = 3299 }, icon = "Interface\\Icons\\Achievement_Character_Orc_Male",
    seatZ = -0.05, seatScale = 0.94,
    color = { 0.58, 0.42, 0.30 }, speed = 6, acceleration = 6, handling = 6, weight = 6, drift = 5, luck = 3,
    quip = "Still looking for his wife. Sees the finish line instead." },

  -- The achievement this addon already ships is named after him. Not adding
  -- the actual Leeroy Jenkins to a game with a Leeroy Jenkins achievement was
  -- the gap.
  { id = "leeroy", name = "Leeroy Jenkins", race = "Human", tag = "LEEROY",
    model = { creature = 24296 }, icon = "Interface\\Icons\\Achievement_Character_Human_Male",
    seatZ = 0.02, seatScale = 1.00,
    color = { 0.95, 0.62, 0.18 }, speed = 8, acceleration = 9, handling = 3, weight = 5, drift = 6, luck = 6,
    quip = "Skipped the pre-race briefing. Is already at full throttle." },

  -- Baine's father. Sits next to the mascot joke rather than beside it.
  { id = "cairne", name = "Cairne Bloodhoof", race = "Tauren", tag = "CAIRNE",
    model = { creature = 3057 }, icon = "Interface\\Icons\\Achievement_Character_Tauren_Male",
    seatZ = -0.16, seatScale = 0.90,
    color = { 0.38, 0.30, 0.22 }, speed = 4, acceleration = 4, handling = 6, weight = 10, drift = 5, luck = 8,
    quip = "Outlived three of these karts already." },

  -- The Deadmines Run is already in the game; its final boss was not.
  { id = "vancleef", name = "Edwin VanCleef", race = "Human", tag = "VANCLEEF",
    model = { creature = 1774 }, icon = "Interface\\Icons\\Achievement_Character_Human_Male",
    seatZ = -0.02, seatScale = 0.96,
    color = { 0.22, 0.22, 0.28 }, speed = 7, acceleration = 6, handling = 8, weight = 4, drift = 7, luck = 4,
    quip = "Left the mine once. Regrets coming back for this." },
}

function AK:GetRacer(id)
  for _, racer in ipairs(self.Racers) do if racer.id == id then return racer end end
  return self.Racers[1]
end

--- Pick `count` distinct opponents. The old grid indexed AK.Racers directly,
--- which handed slot 2 the "Yourself" entry -- so an AI raced as a copy of the
--- player -- and repeated entries once the list wrapped.
---
--- `rng` shuffles the pool before it is walked, seeded per race like every
--- other roll. Without it this always returned the SAME faces in the SAME
--- order: pool[1], pool[2], pool[3]... every single race, forever, because the
--- walk started from the front of a list that never moved. Growing the roster
--- past the grid size did nothing at all -- the extra racers were never
--- reached. A stream is optional so callers without one (previews, tooling)
--- still get a deterministic, order-stable answer.
function AK:BuildAIField(exclude, count, rng)
  local pool = {}
  for _, racer in ipairs(self.Racers) do
    -- "you" is the player's own model and must never be given to an AI.
    if racer.id ~= "you" and racer ~= exclude then table.insert(pool, racer) end
  end
  if rng then
    -- Fisher-Yates, off the race's own seeded stream so the grid is
    -- reproducible for ghosts and bug reports like everything else it rolls.
    for i = #pool, 2, -1 do
      local j = rng:Range(1, i)
      pool[i], pool[j] = pool[j], pool[i]
    end
  end
  local field = {}
  for i = 1, count do
    -- Walk the (now shuffled) pool rather than repeating, so a full grid shows
    -- every face before any of them repeat.
    field[i] = pool[((i - 1) % #pool) + 1]
  end
  return field
end

--- Ground truth for what each racer actually resolved to in-game. Model ids can
--- silently fail to load, and guessing why the grid looks wrong has cost us
--- several rounds -- this reports it instead.
function AK:ReportRoster()
  local race = AK.Race and AK.Race.current
  if not race then
    self:Print("Roster (no race running -- showing configured models):")
    for _, racer in ipairs(self.Racers) do
      local spec = racer.model or {}
      self:Print(("  %-18s %s"):format(racer.name,
        spec.unit and ("unit=" .. spec.unit) or ("creature=" .. tostring(spec.creature))))
    end
    return
  end
  self:Print("Roster in this race:")
  for index, vehicle in ipairs(race.vehicles) do
    local model = AK.RaceUI.karts[index] and AK.RaceUI.karts[index].model
    local spec = AK:GetRacerModel(vehicle)
    local ready = model and AK.Model:IsReady(model)
    local fileID = model and model.GetModelFileID and model:GetModelFileID()
    self:Print(("  %d. %-18s %-16s %s%s"):format(index, vehicle.racer.name,
      spec.unit and ("unit=" .. spec.unit) or ("creature=" .. tostring(spec.creature)),
      ready and "|cff6bf06bloaded|r" or "|cffff5555NO MODEL|r",
      fileID and ("  file=" .. tostring(fileID)) or ""))
  end
end

--- The appearance to render for a vehicle. Remote multiplayer racers show the
--- real player's model when that unit is actually resolvable in our group.
function AK:GetRacerModel(vehicle)
  local racer = vehicle.racer
  if vehicle.unit and UnitExists(vehicle.unit) then return { unit = vehicle.unit } end
  return racer and racer.model or AK.MODEL.default
end
