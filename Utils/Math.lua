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

--- How wide the road is here, as a multiple of the nominal width. Corners can
--- pinch and straights can open out, which is one of the strongest tools a
--- circuit layout has.
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
  return (table_[index] or 0) * flip
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
