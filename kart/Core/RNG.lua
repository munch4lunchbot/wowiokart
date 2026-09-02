local _, AK = ...

-- A dedicated pseudo-random generator, seeded per race.
--
-- Gameplay must never call math.random directly: WoW's generator is shared with
-- every other addon, so the same race replayed with the same inputs would roll
-- different items. Determinism is what makes ghosts, replays and reproducible
-- physics bugs possible at all.
AK.RNG = {}
local RNG = AK.RNG

-- xorshift32. Small, fast, and good enough for item rolls and AI jitter.
local function nextState(state)
  state = state % 4294967296
  state = bit.bxor(state, bit.lshift(state, 13) % 4294967296)
  state = bit.bxor(state, bit.rshift(state, 17))
  state = bit.bxor(state, bit.lshift(state, 5) % 4294967296)
  return state % 4294967296
end

local Stream = {}
Stream.__index = Stream

--- 0 <= value < 1
function Stream:Next()
  self.state = nextState(self.state)
  if self.state == 0 then self.state = 0x9E3779B9 end
  self.calls = self.calls + 1
  return self.state / 4294967296
end

--- Integer in [low, high].
function Stream:Range(low, high)
  return low + math.floor(self:Next() * (high - low + 1))
end

--- True with the given probability.
function Stream:Chance(probability)
  return self:Next() < probability
end

--- Pick one entry from a list.
function Stream:Pick(list)
  if #list == 0 then return nil end
  return list[self:Range(1, #list)]
end

--- Weighted pick from { {value = x, weight = n}, ... }.
function Stream:Weighted(entries)
  local total = 0
  for _, entry in ipairs(entries) do total = total + (entry.weight or 0) end
  if total <= 0 then return nil end
  local roll = self:Next() * total
  for _, entry in ipairs(entries) do
    roll = roll - (entry.weight or 0)
    if roll <= 0 then return entry.value end
  end
  return entries[#entries].value
end

--- Independent streams so an extra AI decision cannot shift the item sequence.
function RNG:New(seed)
  local stream = setmetatable({}, Stream)
  stream.seed = seed or 1
  stream.state = (seed or 1) % 4294967296
  if stream.state == 0 then stream.state = 0x9E3779B9 end
  stream.calls = 0
  return stream
end

--- Seed derived from the clock, but recorded so a race can be replayed exactly.
function RNG:FreshSeed()
  return math.floor(GetTime() * 1000) % 4294967296
end
