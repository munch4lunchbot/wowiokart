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

function Roster:Set(domain, id, key, value)
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

--- Append a racer. Deliberately middling and model-less: it is a blank to be
--- filled in on the MODELS tab, not a guess at what somebody wanted.
function Roster:AddRacer()
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
