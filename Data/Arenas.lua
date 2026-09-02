local _, AK = ...

-- ====================================================================
-- BATTLE ARENAS.
--
-- Battle Mode used to just hand StartBattle whatever circuit was already
-- selected for racing -- a full 2500m+ lap with everyone spread around it.
-- That is not a battle stage, it is a race with the finish line switched off:
-- the field strings out around the loop exactly like it does in a real race,
-- so most of a match is spent alone, driving toward someone you cannot yet
-- see. The genre's actual battle stages are the opposite on every axis: SHORT,
-- WIDE, and looping back on themselves fast enough that the whole grid stays
-- in the same stretch of road for the entire match.
--
-- This engine's track is fundamentally one road -- a distance plus a lateral
-- offset, the same "endless highway" model every pseudo-3D racer since the
-- 80s uses -- so a true free-roam, multi-platform MK64 battle arena (Block
-- Fort, Double Deck) is not representable without rebuilding the renderer and
-- physics around a real 2D plane. What IS achievable with this same one-road
-- model, and gets most of the way there: a loop under 400m with wide, mostly
-- symmetric turns, so the whole field is perpetually a few kart-lengths apart
-- and never more than a couple of seconds from colliding again. The item-box
-- and dash-panel density in Race:BuildObjects already scales with track
-- length, so a short arena is automatically densely stocked without any
-- extra work.
--
-- NOT flagged `tunnel` to wall off the verge. A lap-long tunnel span sounded
-- right for "walled arena" until the geometry was worked through: Compile
-- merges consecutive `tunnel` pieces into one span, so tunnel on every piece
-- of a closed loop produces exactly one span from 0 to the full length --
-- which the fade math (`TunnelDepth`, measuring distance to the nearer of the
-- span's two ends) reads as two mouths meeting at the start/finish line. On a
-- 2500m circuit that seam is crossed once every 40-odd seconds and easy to
-- miss; on a 320-380m loop it recurs every few seconds, so the lighting would
-- visibly brighten and dim right at the line, over and over, for the entire
-- fight. Left as open verge instead: the same fall-and-recover an ordinary
-- circuit already uses, and with a piece every 50-70m here the respawn points
-- Builder:BuildRespawns lays down one per piece are proportionally much
-- denser than on a full-length track, so a knock off the edge is back in the
-- fight in moments. A ring-out risk at the verge is also just an authentic
-- battle-arena stake, not a gap to design away.
--
-- Deliberately its own file rather than another entry in Data/Tracks.lua: the
-- offline verification tools (verify-render.js, course-report.js) find
-- "tracks" by scanning Data/Tracks.lua's text for `{ id = "..." }` blocks, not
-- by which Lua table they end up in. An arena in that file would be silently
-- swept into every one of those reports and judged against thresholds tuned
-- for a 2500m circuit -- render-visibility at 140m-260m out means nothing on
-- a 320m loop nobody laps.
AK.Arenas = {
  {
    -- Not named for the actual Crossroads -- that is a Barrens waypost, and
    -- pairing its name with a dwarven theme would be exactly the kind of
    -- mismatch this file's own tracks are careful never to make. Anvilmar is
    -- the old dwarven settlement this circuit's own straights are named for.
    id = "anvilmar", name = "Anvilmar Coliseum", subtitle = "Four turns, nowhere to hide", theme = "IRONFORGE",
    arena = true, style = "arena",
    sweep = 2.0, length = 380, laps = 999,
    color = { 0.30, 0.24, 0.16 }, road = { 0.52, 0.46, 0.38 },
    skyTop = { 0.10, 0.07, 0.05 }, skyLow = { 0.42, 0.28, 0.14 }, glow = { 1.00, 0.72, 0.32 },
    weather = "none", light = 0.90,
    offroad = "SCREE",
    shortcut = "There isn't one. Fight for the middle of the road.",
    layout = {
      { len = 70, curve = 0, name = "Anvilmar Straight", width = 1.34 },
      { len = 60, curve = 2.6, name = "East Colonnade", width = 1.16 },
      { len = 60, curve = 2.6, name = "East Colonnade II", width = 1.16 },
      { len = 70, curve = 0, name = "Concourse Straight", width = 1.34 },
      { len = 60, curve = 2.6, name = "West Colonnade", width = 1.16 },
      { len = 60, curve = 2.6, name = "West Colonnade II", width = 1.16 },
    },
  },
  {
    id = "grotto", name = "Sunken Grotto Scrap", subtitle = "Tight, dark, and mutual", theme = "DEEPHOLM",
    arena = true, style = "arena",
    sweep = 2.6, length = 320, laps = 999,
    color = { 0.14, 0.20, 0.24 }, road = { 0.34, 0.42, 0.46 },
    skyTop = { 0.03, 0.05, 0.09 }, skyLow = { 0.10, 0.22, 0.30 }, glow = { 0.42, 0.78, 0.95 },
    weather = "none", light = 0.68,
    offroad = "WATER",
    shortcut = "There isn't one. The cave decides who meets who.",
    layout = {
      { len = 50, curve = 0, name = "Grotto Mouth", width = 1.20 },
      { len = 55, curve = -3.2, name = "Left Fang", width = 1.02 },
      { len = 55, curve = 3.2, name = "Right Fang", width = 1.02 },
      { len = 50, curve = 0, name = "Pool Straight", width = 1.20 },
      { len = 55, curve = -3.2, name = "Left Fang II", width = 1.02 },
      { len = 55, curve = 3.2, name = "Right Fang II", width = 1.02 },
    },
  },
}

function AK:GetArena(id)
  for _, arena in ipairs(self.Arenas) do
    if arena.id == id then return AK.TrackBuilder:Compile(arena) end
  end
  return AK.TrackBuilder:Compile(self.Arenas[1])
end
