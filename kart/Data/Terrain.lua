local _, AK = ...

-- Surface materials.
--
-- Previously there were exactly two states: on the road, or "offroad" with one
-- flat speed penalty. That collapses the entire shortcut game -- if grass, sand
-- and mud all cost the same, there is no decision in cutting a corner, and a
-- Mushroom has nothing meaningful to overrule.
--
-- Each material controls speed, acceleration, steering authority, traction (how
-- fast the kart's heading follows its steering) and how much drift it allows.
AK.Terrain = {}
local Terrain = AK.Terrain

Terrain.TYPES = {
  ROAD = {
    id = "ROAD", name = "Road",
    speed = 1.00, acceleration = 1.00, steering = 1.00, traction = 1.00,
    drift = 1.00, rumble = 0.00, drivable = true,
  },
  BOOST = {
    id = "BOOST", name = "Dash Panel",
    speed = 1.35, acceleration = 1.60, steering = 0.90, traction = 1.00,
    drift = 1.00, rumble = 0.05, drivable = true, boost = 1.4,
  },
  -- Cuttable, but it costs you. This is the shortcut currency.
  GRASS = {
    id = "GRASS", name = "Grass",
    speed = 0.52, acceleration = 0.68, steering = 0.90, traction = 0.85,
    drift = 0.70, rumble = 0.55, drivable = true, tint = { .38, .62, .30 },
  },
  SAND = {
    id = "SAND", name = "Sand",
    speed = 0.46, acceleration = 0.56, steering = 0.82, traction = 0.75,
    drift = 0.55, rumble = 0.70, drivable = true, tint = { .82, .72, .44 },
  },
  MUD = {
    id = "MUD", name = "Mud",
    speed = 0.38, acceleration = 0.44, steering = 0.75, traction = 0.70,
    drift = 0.40, rumble = 0.85, drivable = true, tint = { .40, .30, .20 },
  },
  SNOW = {
    id = "SNOW", name = "Snow",
    speed = 0.62, acceleration = 0.70, steering = 0.85, traction = 0.60,
    drift = 0.80, rumble = 0.45, drivable = true, tint = { .86, .90, .96 },
  },
  -- Barely slows you, but you lose the ability to point the kart. Completely
  -- different problem to grass, and that contrast is the point.
  ICE = {
    id = "ICE", name = "Ice",
    speed = 0.96, acceleration = 0.85, steering = 1.10, traction = 0.22,
    drift = 1.35, rumble = 0.10, drivable = true, tint = { .78, .90, 1.0 },
  },
  WATER = {
    id = "WATER", name = "Water",
    speed = 0.30, acceleration = 0.35, steering = 0.70, traction = 0.55,
    drift = 0.30, rumble = 0.60, drivable = true, tint = { .30, .55, .78 },
  },
  -- The verge: loose rock and rubble at the edge of the tarmac.
  --
  -- Four of the seven tracks used VOID as their general off-road surface, and
  -- VOID is absolute -- steering 0, traction 0, speed 0, drivable false (so it
  -- blends to full instantly with no gradient) and fall true. The moment a
  -- wheel left the road you stopped dead, could not steer, and were respawned.
  -- That is why widening the barrier appeared to do nothing whatsoever: three
  -- separate mechanisms ended the excursion long before the fence mattered.
  --
  -- SCREE is what those tracks actually wanted: badly punishing, and entirely
  -- survivable if you know what you are doing.
  SCREE = {
    id = "SCREE", name = "Scree",
    -- Steering was the real problem, not speed. At 0.66 you lost a third of
    -- your authority exactly when you were already running wide, so the mistake
    -- that put you on the scree also removed the means of getting off it --
    -- "sometimes it's impossible to make the turn in time". Off-road should
    -- cost you the corner, not the car. 0.82 still feels loose and slow but you
    -- can always steer your way back.
    speed = 0.52, acceleration = 0.50, steering = 0.82, traction = 0.58,
    drift = 0.25, rumble = 0.95, drivable = true, tint = { .34, .30, .34 },
  },
  -- Reserved for a genuine drop. Nothing should use this as its general
  -- off-road surface; it means "there is no ground here".
  VOID = {
    id = "VOID", name = "Void",
    speed = 0, acceleration = 0, steering = 0, traction = 0,
    drift = 0, rumble = 0, drivable = false, fall = true,
  },
}

Terrain.DEFAULT = Terrain.TYPES.ROAD

function Terrain:Get(id)
  return self.TYPES[id or "ROAD"] or self.DEFAULT
end

--- The material under a kart, and how much of it applies.
---
--- Terrain is deliberately NOT binary. A kart clipping the verge is 70% on road
--- and 30% on grass, and blending the two is what makes the edge of the track
--- feel like a surface rather than a trigger line.
---@return table material, number blend  -- blend 0 = fully road, 1 = fully off
function Terrain:Sample(track, distance, lateral)
  local width = AK.Math.RoadWidth(track, distance)
  local edge = width                       -- |lateral| == width is the verge
  local offBy = math.abs(lateral) - edge
  if offBy <= 0 then
    -- Still on the tarmac, unless the track paints a surface over the road
    -- (an icy patch, a mud strip) at this point.
    local painted = self:Painted(track, distance, lateral)
    if painted then return painted, 1 end
    return self.TYPES.ROAD, 0
  end
  -- Beyond the verge: which material, and how committed are we to it?
  local material = self:Get(self:OffroadAt(track, distance))
  if not material.drivable then return material, 1 end
  -- Ramp the penalty in over most of a road-width so brushing the edge is a
  -- warning rather than a wall.
  --
  -- A third of a road-width meant the surface hit its full penalty almost the
  -- instant a wheel left the tarmac, so running slightly wide out of a corner
  -- cost as much as ploughing into a field -- and with the verge itself being
  -- narrow, "off the course" arrived with no usable margin in between. A longer
  -- ramp is what makes clipping the verge a decision rather than an accident.
  local blend = AK.Math.Clamp(offBy / (width * 0.70), 0, 1)
  return material, blend
end

--- The material just off the road at this point in the lap.
function Terrain:OffroadAt(track, distance)
  if track.surfaces then
    local d = distance % track.length
    for _, zone in ipairs(track.surfaces) do
      if d >= zone.from and d <= zone.to then return zone.offroad or track.offroad end
    end
  end
  return track.offroad or "GRASS"
end

--- A surface painted across the road itself (ice patch, mud strip, water).
function Terrain:Painted(track, distance, lateral)
  if not track.surfaces then return nil end
  local d = distance % track.length
  for _, zone in ipairs(track.surfaces) do
    if zone.onRoad and d >= zone.from and d <= zone.to then
      if not zone.lateralFrom or (lateral >= zone.lateralFrom and lateral <= zone.lateralTo) then
        return self:Get(zone.onRoad)
      end
    end
  end
  return nil
end

--- Blend a material's modifier toward road by `blend`.
--- blend 0 returns 1.0 (pure road), blend 1 returns the material's own value.
function Terrain:Mix(material, field, blend)
  local value = material[field] or 1
  return 1 + (value - 1) * blend
end
