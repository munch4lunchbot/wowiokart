local _, AK = ...

-- Roster edits that survive a reload.
--
-- Racer and kart stats live in Data\Racers.lua and Data\Karts.lua, which are
-- code: editing them meant opening a file and reloading, so in practice nobody
-- tuned the grid at all. The Workshop writes through here instead.
--
-- Two separate things are stored, and they behave differently:
--
--   OVERRIDES are per-id, per-field changes to a shipped entry. They are held
--   apart from the entry itself so "what did this ship as" is never lost and
--   RESET is always possible -- the same reason the tuning table keeps its
--   defaults rather than overwriting them.
--
--   CUSTOM RACERS are whole entries that do not exist in the shipped data. They
--   have to be recreated on every load, before anything reads AK.Racers.
AK.Roster = {}
local Roster = AK.Roster

-- Every editable data table, described once.
--
-- `list` tables are arrays whose entries carry their own id; `map` tables are
-- keyed by id. Adding a new editable domain means adding a line here, not
-- another bespoke editor and another copy of the persistence.
local DOMAINS = {
  racers  = { list = function() return AK.Racers end },
  karts   = { list = function() return AK.Karts end },
  tracks  = { list = function() return AK.Tracks end },
  items   = { map  = function() return AK.Items end },
  terrain = { map  = function() return AK.Terrain and AK.Terrain.TYPES end },
}
AK.Roster.DOMAINS = DOMAINS

local function store()
  AK.db.roster = AK.db.roster or {}
  local saved = AK.db.roster
  for domain in pairs(DOMAINS) do saved[domain] = saved[domain] or {} end
  saved.custom = saved.custom or {}
  saved.hazards = saved.hazards or {}
  return saved
end

--- Every entry in a domain, as { id, entry } pairs in a stable order.
function Roster:Entries(domain)
  local spec = DOMAINS[domain]
  local out = {}
  if not spec then return out end
  if spec.list then
    for _, entry in ipairs(spec.list() or {}) do
      out[#out + 1] = { id = entry.id, entry = entry }
    end
  else
    local map = spec.map() or {}
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do out[#out + 1] = { id = key, entry = map[key] } end
  end
  return out
end

local function find(domain, id)
  for _, row in ipairs(Roster:Entries(domain)) do
    if row.id == id then return row.entry end
  end
end
Roster.Find = function(_, domain, id) return find(domain, id) end

--- Apply everything saved. Called once at load, before the menu or a race can
--- read the roster.
function Roster:Apply()
  self:Reshape()
  local saved = store()

  -- Custom racers first: an override may target one of them.
  for _, spec in ipairs(saved.custom) do
    if not find("racers", spec.id) then
      local racer = {
        id = spec.id, name = spec.name, race = spec.race or "Unknown",
        tag = spec.tag or spec.name:upper(),
        model = spec.model or { creature = 1 },
        icon = spec.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        color = spec.color or { 0.7, 0.7, 0.75 },
        seatZ = 0, seatScale = 1,
        speed = 5, acceleration = 5, handling = 5, weight = 5, drift = 5, luck = 5,
        quip = spec.quip or "Added in the workshop.",
        custom = true,
      }
      table.insert(AK.Racers, racer)
    end
  end

  for name, creatureID in pairs(saved.hazards or {}) do
    for _, track in ipairs(AK.Tracks or {}) do
      for _, plan in ipairs(track.hazardPlan or {}) do
        if plan.name == name then plan.model = { creature = creatureID } end
      end
    end
  end

  for domain in pairs(DOMAINS) do
    for id, fields in pairs(saved[domain] or {}) do
      local entry = find(domain, id)
      if entry then
        for key, value in pairs(fields) do
          -- `model` is a table, not a number; it is stored as its creature id.
          if key == "model" then entry.model = { creature = value }
          else entry[key] = value end
        end
      end
    end
  end
end

--- Was this field moved off what it shipped as?
function Roster:IsChanged(domain, id, key)
  local byId = store()[domain]
  return byId and byId[id] ~= nil and byId[id][key] ~= nil
end

-- WHAT THE MENU WATCHES.
--
-- The selection screens are built once and kept -- rebuilding a grid of eleven
-- 3D portraits on every visit is exactly the stutter that keeping them was
-- meant to avoid -- so a card is a snapshot of the roster at the moment the
-- page was first opened. Every edit made in the workshop after that reached
-- the race (which reads the racer table at the flag) and reached nothing on
-- CHOOSE YOUR RACER: you could give Leeroy a new model, watch it drive past on
-- the track, and still see the old one on the card you picked him from.
--
-- Anything that changes the roster bumps `revision`; only something that
-- changes its SHAPE -- a racer added or removed -- bumps `shape`.
--
-- The difference decides how hard the menu has to work. An edited field is a
-- refresh: the card exists, it just has to re-read the racer. A racer that has
-- come or gone is a rebuild, because the grid's column count, card size and
-- card list were all settled from the entry count. Bumping one number for both
-- would rebuild eleven 3D portraits every time somebody nudged a stat slider,
-- which is exactly the stutter keeping the pages was meant to avoid.
Roster.revision = 0
Roster.shape = 0

function Roster:Touch()
  self.revision = (self.revision or 0) + 1
end

function Roster:Reshape()
  self.shape = (self.shape or 0) + 1
  self:Touch()
end

function Roster:Set(domain, id, key, value)
  self:Touch()
  local saved = store()
  saved[domain] = saved[domain] or {}
  saved[domain][id] = saved[domain][id] or {}
  saved[domain][id][key] = value
  local entry = find(domain, id)
  if entry then
    if key == "model" then entry.model = { creature = value } else entry[key] = value end
  end
  -- Track geometry is compiled once and cached, so a length or sweep change is
  -- invisible until the cache is dropped.
  if domain == "tracks" then
    local track = entry
    if track then track.compiled, track.centreTable, track.curveTable = nil, nil, nil end
  end
end

--- Drop every override for one entry and put the shipped values back.
---
--- The shipped values are not kept anywhere, so this rebuilds them by reloading
--- the data file's own table -- which is why RESET says it needs a reload for
--- anything it cannot restore in place.
function Roster:Clear(domain, id)
  self:Touch()
  local saved = store()
  if saved[domain] then saved[domain][id] = nil end
  AK:Print("Reset " .. id .. " -- /reload to see the shipped values restored.")
end

function Roster:InvalidateModels()
  if AK.RaceUI and AK.RaceUI.karts then
    for _, kart in ipairs(AK.RaceUI.karts) do
      kart.model.akSeatZ, kart.model.akSeatScale, kart.model.akAnim = nil, nil, nil
      AK.Model:Invalidate(kart.model)
    end
  end
end

-- ---------------------------------------------------------------------------
-- HAZARD APPEARANCES.
--
-- A hazard's model is a creature display id written into the track file, and
-- five of the twelve hazards never had one -- a mine cart, a lava vent, a
-- falling rock -- so they drew a raw ability icon on the road instead: a
-- square, bordered piece of inventory UI sitting in the world. The ones that DO
-- have an id are only as good as the guess behind it, and an id that resolves
-- to nothing renders blank and falls back to the same icon.
--
-- Guessing display ids from outside a client is exactly the thing this project
-- has learned not to do, so instead the ids are editable, by eye, in the same
-- gallery that picks racer models -- and they persist, keyed by the hazard's
-- NAME so the two Mine Carts on two different circuits stay the same object.
-- ---------------------------------------------------------------------------

--- Every distinct hazard in the game, by name, with whatever model it has.
function Roster:Hazards()
  local seen, out = {}, {}
  for _, track in ipairs(AK.Tracks or {}) do
    for _, plan in ipairs(track.hazardPlan or {}) do
      local name = plan.name
      if name and not seen[name] then
        seen[name] = true
        out[#out + 1] = { name = name, plan = plan,
          creature = plan.model and plan.model.creature }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function Roster:SetHazardModel(name, creatureID)
  self:Touch()
  local saved = store()
  saved.hazards = saved.hazards or {}
  saved.hazards[name] = creatureID
  -- Applied to every plan of that name across every circuit, and to any race
  -- already running, so the change is visible without leaving the track.
  for _, track in ipairs(AK.Tracks or {}) do
    for _, plan in ipairs(track.hazardPlan or {}) do
      if plan.name == name then plan.model = { creature = creatureID } end
    end
  end
  local race = AK.Race and AK.Race.current
  for _, hazard in ipairs(race and race.hazards or {}) do
    if hazard.name == name then hazard.model = { creature = creatureID } end
  end
  if AK.RaceUI and AK.RaceUI.hazardFrames then
    for _, frame in ipairs(AK.RaceUI.hazardFrames) do AK.Model:Invalidate(frame.model) end
  end
end

--- Append a racer. Deliberately middling and model-less: it is a blank to be
--- filled in on the MODELS tab, not a guess at what somebody wanted.
function Roster:AddRacer()
  self:Reshape()
  local saved = store()
  local n = #saved.custom + 1
  local id = "custom" .. n
  while find("racers", id) do n = n + 1 id = "custom" .. n end
  local spec = { id = id, name = "New Racer " .. n, tag = "NEW " .. n, race = "Unknown" }
  table.insert(saved.custom, spec)
  self:Apply()
  return find("racers", id)
end

function Roster:RemoveRacer(id)
  self:Reshape()
  local saved = store()
  for index, spec in ipairs(saved.custom) do
    if spec.id == id then
      table.remove(saved.custom, index)
      for i, racer in ipairs(AK.Racers) do
        if racer.id == id then table.remove(AK.Racers, i) break end
      end
      saved.racers[id] = nil
      if AK.db.selection.racer == id then AK.db.selection.racer = AK.Racers[1].id end
      return true
    end
  end
  AK:Print("Only racers you added can be removed.")
  return false
end
