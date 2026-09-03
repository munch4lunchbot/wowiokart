local _, AK = ...

-- Tracks used to be two summed sine waves, which can only ever produce gentle
-- S-bends -- no sustained corners, no hairpins, no crests, no jumps. A real
-- pseudo-3D circuit is authored as a *sequence of segments* and the shape comes
-- from integrating them: turn rate integrates to heading, heading integrates to
-- the road's lateral position. That is what makes a corner feel like a corner
-- rather than a wobble.
--
-- Layout entries:
--   len    metres this piece runs for
--   curve  turn rate; negative is left, positive is right. |4| is a hairpin.
--   grade  climb rate; negative descends
--   ramp   true marks a launch ramp over this piece
--   name   shown when you enter it, for the corner-name callouts
AK.TrackBuilder = {}
local Builder = AK.TrackBuilder

local STEP = 2            -- metres between samples
local CURVE_GAIN = 0.0021 -- turn rate -> heading, radians per metre
local GRADE_GAIN = 0.022  -- climb rate -> metres

--- Walk the layout and bake lookup tables for centreline and height.
-- Published because anything that has to travel in a STRAIGHT LINE across a
-- curving road needs the same figure the road was built with. A green shell is
-- the case: its position is stored road-relative, so holding its lateral steady
-- makes it follow every bend like a tram.
Builder.CURVE_GAIN = CURVE_GAIN

function Builder:Compile(track)
  if track.compiled then return track end
  local layout = track.layout
  if not layout then
    track.compiled = true
    return track
  end

  -- Total the authored length and rescale it onto the track's stated length, so
  -- a layout can be written in readable round numbers.
  local authored = 0
  for _, piece in ipairs(layout) do authored = authored + piece.len end
  local scale = track.length / authored

  local samples = math.floor(track.length / STEP) + 1
  local centre, height, ramps, width = {}, {}, {}, {}
  local tunnels = {}
  -- Corner tightness, recorded as authored rather than recovered afterwards.
  --
  -- The physics used to differentiate the baked centreline to find its corner
  -- force, which is wrong twice over: one difference gives the road's HEADING,
  -- so a straight that merely runs diagonally pushed the kart sideways forever;
  -- and two differences pick up the seam where the lap closes and the step at
  -- every segment join, producing enormous spikes on pieces authored as
  -- perfectly straight. The layout already states the curvature exactly, so it
  -- is simply kept.
  local curve = {}
  -- Named stretches of road. The layout format has always carried a name per
  -- piece and promised callouts, but nothing ever read them except the respawn
  -- table -- so every corner on every circuit was anonymous to the player.
  local sections, sectionOpen = {}, nil
  local heading, x, h = 0, 0, 0
  local cursor, pieceIndex, pieceLeft = 0, 1, layout[1].len * scale
  local rampFrom, tunnelFrom = nil, nil

  for i = 1, samples do
    local piece = layout[pieceIndex]
    -- Integrate twice: turn rate into heading, heading into lateral offset.
    heading = heading + (piece.curve or 0) * CURVE_GAIN * STEP
    x = x + heading * STEP
    h = h + (piece.grade or 0) * GRADE_GAIN * STEP
    centre[i], height[i] = x, h
    -- Road width multiplier. Narrowing a hairpin and opening a straight is one
    -- of the strongest tools a circuit has, and the old track format could not
    -- express it at all.
    width[i] = piece.width or 1
    curve[i] = piece.curve or 0
    if piece.name and sectionOpen ~= piece.name then
      if #sections > 0 then sections[#sections].to = cursor end
      table.insert(sections, { from = cursor, to = track.length, name = piece.name })
      sectionOpen = piece.name
    end

    if piece.ramp and not rampFrom then
      rampFrom = cursor
    elseif rampFrom and not piece.ramp then
      table.insert(ramps, { from = rampFrom, to = cursor })
      rampFrom = nil
    end

    -- Covered sections are spans, exactly like ramps: consecutive pieces
    -- flagged `tunnel` merge into one, so a tunnel can bend and climb through
    -- several authored segments and still read as a single place.
    if piece.tunnel and not tunnelFrom then
      tunnelFrom = cursor
    elseif tunnelFrom and not piece.tunnel then
      table.insert(tunnels, { from = tunnelFrom, to = cursor, name = layout[pieceIndex - 1] and layout[pieceIndex - 1].name })
      tunnelFrom = nil
    end

    cursor = cursor + STEP
    pieceLeft = pieceLeft - STEP
    while pieceLeft <= 0 and pieceIndex < #layout do
      pieceIndex = pieceIndex + 1
      pieceLeft = pieceLeft + layout[pieceIndex].len * scale
    end
  end
  if rampFrom then table.insert(ramps, { from = rampFrom, to = cursor }) end
  if tunnelFrom then table.insert(tunnels, { from = tunnelFrom, to = cursor }) end

  -- Close the loop. Any residual drift is removed linearly so the end of the
  -- lap lines up with the start; without this the track spirals away and lap
  -- two renders somewhere else entirely.
  local driftX, driftH = centre[samples] - centre[1], height[samples] - height[1]
  for i = 1, samples do
    local t = (i - 1) / (samples - 1)
    centre[i] = centre[i] - driftX * t
    height[i] = height[i] - driftH * t
  end

  -- Centre the course on zero BEFORE normalising. Scaling by peak alone meant a
  -- single big corner ate the whole budget and every other bend was squashed
  -- flat around the origin -- measured, only 35% of the lap had meaningful
  -- lateral offset. Centring first uses the sweep symmetrically and takes that
  -- to 61%, which is the difference between "a few turns" and a real circuit.
  local low, high = math.huge, -math.huge
  for i = 1, samples do
    low, high = math.min(low, centre[i]), math.max(high, centre[i])
  end
  local mid = (low + high) * 0.5
  local peak = 0
  for i = 1, samples do
    centre[i] = centre[i] - mid
    peak = math.max(peak, math.abs(centre[i]))
  end
  if peak > 0 then
    local factor = (track.sweep or 2.6) / peak
    for i = 1, samples do centre[i] = centre[i] * factor end
  end

  -- Smooth the width so the road tapers into a corner instead of stepping.
  -- A 34m window still changed 0.02 per 2m sample, which reads as a staircase
  -- along the verge; 60m halves that and the taper disappears.
  local smoothed = {}
  local span = 15
  for i = 1, samples do
    local total, count = 0, 0
    for k = -span, span do
      local j = ((i - 1 + k) % samples) + 1
      total, count = total + width[j], count + 1
    end
    smoothed[i] = total / count
  end
  -- Smooth the curvature over ~30m for the same reason width is smoothed: a
  -- step change in corner force at a segment boundary yanks the kart sideways.
  -- A real corner loads up over its entry.
  local curveSmooth = {}
  for i = 1, samples do
    local total, count = 0, 0
    for k = -span, span do
      local j = ((i - 1 + k) % samples) + 1
      total, count = total + curve[j], count + 1
    end
    curveSmooth[i] = total / count
  end
  track.curveTable = curveSmooth
  track.widthTable = smoothed
  track.centreTable, track.heightTable, track.ramps = centre, height, ramps
  track.tunnels = tunnels
  track.sections = sections
  track.sampleStep, track.sampleCount = STEP, samples
  self:BuildCheckpoints(track)
  self:BuildRespawns(track, layout, scale)
  self:BuildMapPath(track, layout, scale, samples)
  self:CompileBranches(track)
  track.compiled = true
  return track
end

-- Branching routes.
--
-- A branch is compiled by the SAME pipeline as the main route, so it comes out
-- with identical fields: centreTable, heightTable, widthTable, ramps, length.
-- That is the whole trick -- every system that reads a route (the renderer, the
-- terrain sampler, the physics, the AI) works on a branch unchanged, because a
-- branch simply IS a small track.
--
-- Authored on a track as:
--   branches = {
--     { from = 0.34, to = 0.52, side = -1, name = "High Road",
--       length = 380, sweep = 1.4, layout = { ... } },
--   }
-- `from`/`to` are fractions of the main lap where the route leaves and rejoins.
--- The name of the stretch of road at this point, if it has one.
--- A distance mapped into a route's own space.
---
--- A LAP LOOPS. A BRANCH DOES NOT.
---
--- Every lookup in this file wrapped with `distance % length`, which is right
--- for the main line -- three metres before the start line really is three
--- metres from the end of the lap. A branch starts at the split and stops at
--- the rejoin and there is nothing behind zero, but Lua's `%` is floored, so a
--- negative distance on a branch wrapped round to its EXIT: the wrong
--- curvature, the wrong width, the wrong height and the wrong scenery.
---
--- That matters because a kart commits to a fork while it is still up to six
--- metres SHORT of the split, and the camera trails it by six more. Both of
--- those are negative branch distances, at exactly the moment the player is
--- looking hardest at the fork. The old workaround was to clamp the camera
--- instead, which froze the world for six metres and slid the kart out from
--- under the camera. Clamping the LOOKUP is the honest version of the same
--- idea and costs nothing.
function Builder:At(route, distance)
  if route.parent then
    if distance < 0 then return 0 end
    if distance > route.length then return route.length end
    return distance
  end
  return (distance % route.length + route.length) % route.length
end

function Builder:SectionAt(track, distance)
  local sections = track.sections
  if not sections then return nil end
  local d = self:At(track, distance)
  for _, section in ipairs(sections) do
    if d >= section.from and d < section.to then return section end
  end
  return sections[#sections]
end

--- Is this point inside a covered section, and how far from daylight?
---
--- Returns the tunnel plus the distance to the nearer mouth, which the renderer
--- uses to fade the lighting in and out. A tunnel that switches on the instant
--- you cross the threshold looks like a bug; real ones swallow you gradually.
function Builder:TunnelAt(track, distance)
  local tunnels = track.tunnels
  if not tunnels or #tunnels == 0 then return nil end
  local d = self:At(track, distance)
  for _, tunnel in ipairs(tunnels) do
    if d >= tunnel.from and d <= tunnel.to then
      return tunnel, math.min(d - tunnel.from, tunnel.to - d)
    end
  end
  return nil
end

--- How enclosed a point is, 0 outside to 1 deep inside. Ramped over the mouth
--- so entering and leaving is a transition rather than a switch.
function Builder:TunnelDepth(track, distance, fade)
  local tunnel, toMouth = self:TunnelAt(track, distance)
  if not tunnel then return 0, nil end
  return AK.Math.Clamp(toMouth / (fade or 14), 0, 1), tunnel
end

function Builder:CompileBranches(track)
  if not track.branches then return end
  for index, branch in ipairs(track.branches) do
    branch.id = branch.id or ("branch" .. index)
    branch.parent = track
    branch.index = index
    -- Absolute distances on the main route.
    branch.entry = branch.from * track.length
    branch.exit = branch.to * track.length
    -- How much of the main lap this branch replaces. Progress along the branch
    -- maps onto this span so racers on different routes stay comparable.
    branch.span = (branch.exit - branch.entry) % track.length
    if branch.span <= 0 then branch.span = branch.span + track.length end
    -- Inherit anything the branch does not override, so a route only has to
    -- state what makes it different.
    branch.laps = 1
    branch.offroad = branch.offroad or track.offroad
    branch.surfaces = branch.surfaces or nil
    branch.sweep = branch.sweep or 1.6
    branch.style = track.style
    branch.compiled = false
    -- Compile it exactly like a track. It has no branches of its own, so this
    -- cannot recurse.
    local nested = branch.branches
    branch.branches = nil
    self:Compile(branch)
    branch.branches = nested
    self:AnchorBranch(track, branch)
  end
end

--- The fork a racer is approaching on the main route, if any.
--- Pin a branch's two ends onto the main road.
---
--- Compile closes every route into a loop, which is right for a circuit and
--- wrong for a branch: a branch starts at one point on the main line and ends
--- at a different one. Left as a loop it would rejoin at the wrong lateral
--- offset and the road would visibly snap sideways under the kart. Adding the
--- missing displacement linearly along the branch spreads the correction over
--- its whole length, where it reads as part of the curve.
function Builder:AnchorBranch(track, branch)
  local centre, height = branch.centreTable, branch.heightTable
  local samples = branch.sampleCount
  if not centre or not samples or samples < 2 then return end

  -- Both ends must land ON the main line, in absolute terms.
  --
  -- This used to normalise the branch to start at zero and merely END at the
  -- right RELATIVE offset, so a branch always began at centre 0 and height 0
  -- while the main line at that point was somewhere else entirely. Switching
  -- route therefore snapped the road vertically by whatever the entry height
  -- was -- which is the "the fork just teleports you" report. The shape was
  -- always right; it was pinned to the wrong origin.
  local entryCentre = AK.Math.RoadCenter(track, branch.entry)
  local entryHeight = AK.Math.RoadHeight(track, branch.entry)
  local wantCentre = AK.Math.RoadCenter(track, branch.exit) - entryCentre
  local wantHeight = AK.Math.RoadHeight(track, branch.exit) - entryHeight
  local haveCentre = centre[samples] - centre[1]
  local haveHeight = height[samples] - height[1]
  local baseCentre, baseHeight = centre[1], height[1]

  for i = 1, samples do
    local t = (i - 1) / (samples - 1)
    centre[i] = entryCentre + (centre[i] - baseCentre) + (wantCentre - haveCentre) * t
    height[i] = entryHeight + (height[i] - baseHeight) + (wantHeight - haveHeight) * t
  end
end

function Builder:ForkAt(track, distance, window)
  if not track.branches then return nil end
  local d = self:At(track, distance)
  for _, branch in ipairs(track.branches) do
    local gap = (branch.entry - d) % track.length
    if gap >= 0 and gap <= (window or 0) then return branch, gap end
  end
  return nil
end

--- Global lap progress for a racer, so routes of different physical lengths can
--- still be ranked against each other. Without this, a racer 300m down a 400m
--- branch and one 300m down the 900m main line look identical to a sort.
function Builder:GlobalProgress(track, route, distance)
  if not route or route == track then
    return (distance % track.length + track.length) % track.length
  end
  -- The low end allows a little NEGATIVE, because a kart commits to a fork
  -- while it is still short of the split and its branch distance is genuinely
  -- below zero for those few metres. Clamping at zero reported it as already at
  -- the entry, which put a small forward step into the odometer -- which is
  -- accumulated from the frame-to-frame delta, so a step is a free metre. Held
  -- well inside the commit window so nothing wild can run away with it.
  local fraction = AK.Math.Clamp(distance / math.max(1, route.length), -0.05, 1)
  return (route.entry + fraction * route.span) % track.length
end

--- Ordered checkpoints around the lap.
---
--- A lap must not be completable by nudging backwards over the line, and a
--- shortcut must not be allowed to skip half the course. Requiring checkpoints
--- to be taken in order is what makes lap counting trustworthy -- distance
--- alone can always be gamed.
function Builder:BuildCheckpoints(track)
  local count = math.max(8, math.floor(track.length / 180))
  local points = {}
  for i = 1, count do
    points[i] = { index = i, distance = (i - 1) * (track.length / count) }
  end
  track.checkpoints = points
  track.checkpointCount = count
end

--- Which checkpoint a distance falls into.
function Builder:CheckpointAt(track, distance)
  if not track.checkpointCount then return 1 end
  local d = self:At(track, distance)
  return math.floor(d / (track.length / track.checkpointCount)) + 1
end

--- Recovery points, one at the start of each authored segment. Lakitu drops you
--- at the last one you passed, so a failed jump returns you before the ramp
--- rather than teleporting you past it.
function Builder:BuildRespawns(track, layout, scale)
  local points, cursor = {}, 0
  for _, piece in ipairs(layout) do
    -- Never place a recovery point on a ramp; you would be dropped mid-launch.
    if not piece.ramp then
      table.insert(points, { distance = cursor, lateral = 0, name = piece.name })
    end
    cursor = cursor + piece.len * scale
  end
  track.respawns = points
end

--- Trace the circuit's actual plan-view shape, so the track map can draw the
--- real course instead of a generic ring. Total heading is normalised to a full
--- turn, which is what makes the path close back on itself.
function Builder:BuildMapPath(track, layout, scale, samples)
  -- THE PLAN VIEW HAS TO CLOSE, AND IT HAS TO LOOK LIKE THE CIRCUIT.
  --
  -- This used to scale every corner by (2*pi / the layout's total turn), which
  -- closes the loop by construction and is fine right up until a circuit turns
  -- nearly as far one way as the other. Durotar does: +3.4, -4.2, +3.8, -0.6,
  -- a switchback climb followed by triple esses. Its total turn is close to
  -- zero, the gain that normalises it is therefore enormous, and the map
  -- spiralled into an unreadable scribble. Eight of the ten circuits did.
  --
  -- Instead: turn by the road's OWN curvature, and spread whatever turn is
  -- left over to make 2*pi evenly along the lap. Corners then appear where the
  -- track actually corners, the shape still closes, and nothing blows up when
  -- the curves cancel.
  --
  -- MAP_GAIN is deliberately twice the road's real CURVE_GAIN. A faithful plan
  -- view of a 2.5km lap at these corner rates is a sliver, so the turn is
  -- exaggerated to make ten circuits ten recognisable SHAPES at 56 pixels.
  --
  -- Twice, and not more. At three times the shapes have far more character --
  -- real hairpins, proper kinks -- and they also start CROSSING THEMSELVES,
  -- which invents junctions the road does not have. A course map is a thing you
  -- orient by: a crossing asks "am I on the near strand or the far one" about
  -- a place where the question is meaningless. Character loses to legibility.
  local MAP_GAIN = 0.0042
  local turnAtGain = 0
  for _, piece in ipairs(layout) do
    turnAtGain = turnAtGain + (piece.curve or 0) * piece.len * scale * MAP_GAIN
  end
  local spread = (math.pi * 2 - turnAtGain) / track.length
  local path = {}
  local angle, px, py = 0, 0, 0
  local pieceIndex, pieceLeft = 1, layout[1].len * scale
  for i = 1, samples do
    local piece = layout[pieceIndex]
    angle = angle + (piece.curve or 0) * STEP * MAP_GAIN + spread * STEP
    px = px + math.cos(angle) * STEP
    py = py + math.sin(angle) * STEP
    path[i] = { x = px, y = py }
    pieceLeft = pieceLeft - STEP
    while pieceLeft <= 0 and pieceIndex < #layout do
      pieceIndex = pieceIndex + 1
      pieceLeft = pieceLeft + layout[pieceIndex].len * scale
    end
  end
  -- Close any residual gap, then fit the shape into a unit box centred on zero.
  local dx, dy = path[samples].x - path[1].x, path[samples].y - path[1].y
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  for i = 1, samples do
    local t = (i - 1) / (samples - 1)
    path[i].x = path[i].x - dx * t
    path[i].y = path[i].y - dy * t
    minX, maxX = math.min(minX, path[i].x), math.max(maxX, path[i].x)
    minY, maxY = math.min(minY, path[i].y), math.max(maxY, path[i].y)
  end
  local spanX, spanY = math.max(1e-3, maxX - minX), math.max(1e-3, maxY - minY)
  local span = math.max(spanX, spanY)
  local midX, midY = (minX + maxX) * .5, (minY + maxY) * .5
  for i = 1, samples do
    path[i].x = (path[i].x - midX) / span
    path[i].y = (path[i].y - midY) / span
  end
  track.mapPath = path
end

--- Normalised progress-to-map-position lookup, for drawing racers on the map.
function Builder:MapPoint(track, distance)
  local path = track.mapPath
  if not path then return 0, 0 end
  local count = #path
  local index = math.floor(Builder:At(track, distance) / track.sampleStep) % count + 1
  return path[index].x, path[index].y
end

--- Interpolated lookup into a compiled table, wrapping at the lap boundary.
local function sampleTable(track, list, distance)
  local count = track.sampleCount
  local position = Builder:At(track, distance) / track.sampleStep
  local index = math.floor(position)
  local fraction = position - index
  local a = list[(index % count) + 1]
  local b = list[((index + 1) % count) + 1]
  return a + (b - a) * fraction
end

function Builder:Centre(track, distance)
  if not track.centreTable then return 0 end
  return sampleTable(track, track.centreTable, distance)
end

function Builder:Height(track, distance)
  if not track.heightTable then return 0 end
  return sampleTable(track, track.heightTable, distance)
end

--- Road width multiplier at a point. 1.0 is the track's nominal width.
function Builder:Width(track, distance)
  if not track.widthTable then return 1 end
  return sampleTable(track, track.widthTable, distance)
end

--- True while `distance` sits on a launch ramp.
function Builder:RampAt(track, distance)
  if not track.ramps then return nil end
  local d = self:At(track, distance)
  for _, ramp in ipairs(track.ramps) do
    if d >= ramp.from and d <= ramp.to then return ramp end
  end
  return nil
end
