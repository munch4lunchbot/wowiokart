local _, AK = ...

AK.Math = {}

function AK.Math.Clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

function AK.Math.Lerp(a, b, amount)
  return a + (b - a) * amount
end

function AK.Math.Wrap(value, length)
  value = value % length
  if value < 0 then value = value + length end
  return value
end

function AK.Math.DistanceOnLoop(a, b, length)
  local distance = math.abs(a - b) % length
  return math.min(distance, length - distance)
end

function AK.Math.SignedLoopDistance(from, to, length)
  local distance = (to - from) % length
  if distance > length * 0.5 then distance = distance - length end
  return distance
end

--- Height of the road surface, in metres. Crests rise to hide what is beyond
--- them, dips fall away underneath you.
function AK.Math.RoadHeight(track, distance)
  if track.heightTable then return AK.TrackBuilder:Height(track, distance) end
  -- Legacy sine tracks, kept so an un-authored track still renders.
  local hills = track.hills
  if not hills then return 0 end
  local p = distance / track.length
  local y = 0
  for _, hill in ipairs(hills) do
    y = y + math.sin((p * hill.frequency + hill.phase) * math.pi * 2) * hill.amount
  end
  return y
end

-- A FORK HAS TO ACTUALLY GO SOMEWHERE.
--
-- A branch was pinned to the main line at both ends and given nothing but its
-- own gentle curvature in between, so it stayed within a couple of metres of
-- the road it supposedly left. You picked a side, drove for six seconds past
-- the same scenery and arrived where you would have arrived anyway: "they just
-- are pick left or right and in a few seconds end up in the same spot".
--
-- So a branch now carries a turn of its own at each end -- out at the split,
-- back at the rejoin -- and it is expressed as CURVATURE, in the same units a
-- layout piece is authored in, rather than as an offset painted onto the
-- ribbon. That matters for three reasons: the renderer integrates curvature to
-- find where the road is, so the road you drive and the ribbon you were shown
-- come out in the same place and committing changes nothing; the physics reads
-- curvature for its centrifugal push, so leaving the main line is something you
-- have to steer through rather than something that happens to the picture; and
-- a full sine over the run leaves the heading exactly where it found it, so the
-- branch ends up displaced without ending up crooked.
--
-- 2.4 sits inside the authored range (layouts run 0.6 to 4.6), so a branch is
-- no harder to steer through than a corner the circuit already has -- the turn
-- is simply held for longer. Over 95 metres that puts about 35 metres between
-- the two roads, which is two road widths: far enough that the line you did not
-- take leaves the screen through the middle of a shortcut instead of running
-- alongside it. Twenty metres was one road width, and one road width away is
-- still "the same place with a different texture", which is what "an illusion
-- of choice" means.
local FORK_TURN = 2.4
local FORK_TURN_RUN = 95

--- The branch's own departure from the road it left, as authored curvature.
--- Zero on the main line, and zero through the middle of a branch: all of it
--- happens in the opening and closing stretches.
function AK.Math.ForkTurn(route, distance)
  if not route or not route.parent then return 0 end
  local length = route.length or 0
  local run = math.min(FORK_TURN_RUN, length * 0.4)
  if run <= 1 then return 0 end
  local d = distance or 0
  -- Out at the split. A whole sine, so the heading it adds is given back.
  if d >= 0 and d <= run then
    return AK.Math.ForkSide(route) * FORK_TURN * math.sin(2 * math.pi * d / run)
  end
  -- And back at the rejoin, the same turn the other way.
  if d >= length - run and d <= length then
    return -AK.Math.ForkSide(route) * FORK_TURN
      * math.sin(2 * math.pi * (d - (length - run)) / run)
  end
  return 0
end

--- Authored corner tightness at a point. Negative turns left.
function AK.Math.RoadCurve(track, distance)
  local table_ = track.curveTable
  if not table_ then return 0 end
  local samples = track.sampleCount or #table_
  local step = track.sampleStep or 2
  -- Through the route's own mapping: a branch does not loop, so a negative
  -- distance on one must clamp to its start rather than wrap to its exit.
  local index = math.floor(AK.TrackBuilder:At(track, distance) / step) + 1
  if index < 1 then index = 1 elseif index > samples then index = samples end
  -- Mirror mode flips the centreline, so the corner force has to flip with it
  -- or every bend on a mirrored track would push the wrong way.
  local flip = (AK.db and AK.db.settings.mirror) and -1 or 1
  -- ForkTurn is already mirrored through ForkSide, so it is added after the
  -- flip rather than through it.
  return (table_[index] or 0) * flip + AK.Math.ForkTurn(track, distance)
end

--- Flip an AUTHORED lateral for mirror mode.
---
--- The mirror flips the centreline, so every corner goes the other way -- but
--- everything placed by hand against that centreline is a separate number, and
--- those did not flip. A mirrored Durotar put its lava vents on the same side
--- of the road as the original, which is to say on the opposite side of the
--- corner they were authored to guard; a mirrored circuit's shortcut still left
--- from the side the unmirrored one did. Anything positioned across the road by
--- an author goes through here.
function AK.Math.Mirrored(lateral)
  if AK.db and AK.db.settings.mirror then return -(lateral or 0) end
  return lateral or 0
end

--- Which side of the road a branch leaves from, mirror included.
function AK.Math.ForkSide(branch)
  return AK.Math.Mirrored(branch and branch.side or -1)
end

-- How far off centre counts as choosing a side. In half-widths, so a fifth of
-- the way over from the middle -- deliberately small, because the choice should
-- be "I moved over" and not "I hugged the verge".
local FORK_AIM = 0.15

--- Is this kart lined up for the branch? One predicate, read by the physics to
--- decide and by the renderer to SAY SO -- the two disagreeing about what counts
--- as lined up would be worse than either being wrong.
function AK.Math.ForkAimed(branch, lateral)
  local wants = AK.Math.ForkSide(branch)
  if wants < 0 then return (lateral or 0) < -FORK_AIM end
  return (lateral or 0) > FORK_AIM
end

--- How wide the road is here, as a multiple of the nominal width. Corners can
--- pinch and straights can open out, which is one of the strongest tools a
--- circuit layout has.
function AK.Math.RoadWidth(track, distance)
  if not track.widthTable then return 1 end
  return AK.TrackBuilder:Width(track, distance)
end

--- Lateral position of the road centreline. Compiled layouts integrate turn
--- rate twice, which is what produces sustained corners and hairpins instead of
--- the gentle wobble a summed sine can manage.
function AK.Math.RoadCenter(track, distance)
  -- Mirror mode negates the centreline, which flips every corner left-for-right
  -- without touching the layout data. Everything downstream -- rendering, AI,
  -- centrifugal force, the track map -- inherits it for free.
  local flip = (AK.db and AK.db.settings.mirror) and -1 or 1
  if track.centreTable then return AK.TrackBuilder:Centre(track, distance) * flip end
  local curves = track.curves
  if not curves then return 0 end
  local p = distance / track.length
  local x = 0
  for _, curve in ipairs(curves) do
    x = x + math.sin((p * curve.frequency + curve.phase) * math.pi * 2) * curve.amount
  end
  return AK.Math.Clamp(x, -0.78, 0.78) * flip
end
