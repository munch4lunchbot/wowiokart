local _, AK = ...

AK.Physics = {}
local Physics = AK.Physics

-- Weight classes as real physics, not a label.
--
-- Acceleration, top speed, handling, recovery and collision mass are five
-- SEPARATE characteristics. A light racer is not simply "faster" -- they reach
-- speed quickly and shrug off a hit fast, but get shoved around. A heavy racer
-- takes an age to wind up and to recover, but holds speed and bullies.
-- Collapsing these into one "weight" number is what made the classes cosmetic.
-- How hard a drift bites, as a multiplier on the corner's centrifugal push.
-- Below 1, because a drift is how you get ROUND a corner you cannot grip. See
-- the note at the use site. verify-drift.js reads these three by name.
local DRIFT_BITE = 0.92
-- How much more steering authority a drift gives. Named so the AI's own corner
-- model can read the same number rather than assuming a grip-limited corner.
local DRIFT_STEER = 1.30
-- The share of the mini-turbo charge rate a drift earns off a corner, and the
-- curvature at which it earns all of it. A straight banks almost nothing.
local DRIFT_LOAD_FLOOR = 0.30
local DRIFT_LOAD_FULL = 1.6
-- Published, because Race/AI.lua works out how fast it can take a corner and
-- has to use the same physics the corner is actually resolved with.
AK.DRIFT_BITE, AK.DRIFT_STEER = DRIFT_BITE, DRIFT_STEER

AK.WEIGHT_CLASSES = {
  light  = { accel = 1.22, top = 0.94, handling = 1.14, recovery = 1.35, mass = 0.68 },
  medium = { accel = 1.00, top = 1.00, handling = 1.00, recovery = 1.00, mass = 1.00 },
  heavy  = { accel = 0.80, top = 1.07, handling = 0.88, recovery = 0.72, mass = 1.42 },
}

function AK:WeightClassFor(weight)
  if weight <= 4 then return "light" end
  if weight >= 8 then return "heavy" end
  return "medium"
end

function Physics:CreateVehicle(racer, kart, owner, isPlayer)
  local speed = (racer.speed + kart.speed) * .5
  local acceleration = (racer.acceleration + kart.acceleration) * .5
  local weight = (racer.weight + kart.weight) * .5
  local className = AK:WeightClassFor(weight)
  local class = AK.WEIGHT_CLASSES[className]
  local engine = AK:GetSpeedClass(AK.db and AK.db.settings.engineClass)
  return {
    weightClass = className,
    classAccel = class.accel,
    classTop = class.top,
    classHandling = class.handling,
    classRecovery = class.recovery,
    mass = class.mass * (0.6 + weight * 0.05),
    racer = racer,
    kart = kart,
    owner = owner,
    isPlayer = isPlayer,
    distance = 0,
    lateral = 0,
    speed = 0,
    -- Weight class and engine class both fold in here, so every downstream
    -- system inherits them without needing to know either exists.
    maxSpeed = (56 + speed * 2.65) * class.top * engine.speed,
    acceleration = (24 + acceleration * 3.4) * class.accel * engine.accel,
    handling = (.55 + ((racer.handling + kart.handling) * .5) * .13) * class.handling,
    driftStat = (racer.drift + kart.drift) * .5,
    weight = weight,
    lap = 1,
    driftCharge = 0,
    driftDirection = 0,
    drifting = false,
    -- `slow` caps top speed for a while; `stun` is now only a brief hit
    -- reaction used for feedback. Being frozen solid is never fun.
    slow = 0,
    stun = 0,
    boostTime = 0,
    itemCooldown = 0,
    hazardHits = 0,
  }
end

function Physics:ReleaseDrift(race, vehicle)
  if not vehicle.drifting then return end
  if vehicle.driftCharge > .35 then
    local boost = vehicle.driftCharge > 1.8 and 1.45 or (vehicle.driftCharge > .9 and .85 or .42)
    vehicle.boostTime = math.max(vehicle.boostTime, boost)
    vehicle.speed = math.max(vehicle.speed, vehicle.maxSpeed * (1.04 + boost * .055))
    if vehicle == race.player then
      -- Tier from the SAME thresholds that chose the boost, so the burst, the
      -- spark colour you were just watching and the boost you actually got can
      -- never disagree with each other.
      local tier = vehicle.driftCharge > 1.8 and 3 or (vehicle.driftCharge > .9 and 2 or 1)
      -- Purple sparks. Most players cash out at orange and never see the top
      -- rung, so this is the achievement that teaches the drift ladder exists.
      --
      -- `isPlayer`, not `== race.player`: the attract demo behind the main menu
      -- hands the player's own kart to the AI and clears isPlayer, so keying off
      -- identity alone would hand out achievements for watching the title screen.
      if tier >= 3 and vehicle.isPlayer then AK:UnlockAchievement("mega_turbo") end
      -- Burst, shove, sound -- in that order, same frame.
      AK.RaceUI:DriftRelease(tier)
      AK.RaceUI:Announce(boost > 1.2 and "MEGA BOOST!" or (boost > .7 and "SUPER BOOST!" or "MINI BOOST!"), boost > 1.2 and AK.COLORS.gold or AK.COLORS.lime)
      AK.RaceUI:Flash(boost > 1.2 and AK.COLORS.gold or AK.COLORS.lime, boost > 1.2 and .16 or .09)
      if AK.PlaySfx then AK:PlaySfx(boost > 1.2 and "megaBoost" or "boost") end
    end
  end
  vehicle.drifting, vehicle.driftCharge, vehicle.driftDirection = false, 0, 0
end

-- Route handling for branching courses.
--
-- `vehicle.route` is whatever road the kart is physically on -- the main track
-- or one of its branches. `vehicle.distance` is measured along THAT route, so
-- every existing system keeps working unchanged. `vehicle.progress` is the
-- shared scale used for ranking, because two racers on different-length routes
-- cannot be compared by raw distance.
function Physics:UpdateRoute(race, vehicle)
  local track = race.track
  vehicle.route = vehicle.route or track

  -- A kart another client owns does not get to choose its own road here: the
  -- host decides, and the answer arrives in the snapshot. Guessing locally
  -- would put it on a branch the host never took, and then every distance we
  -- were sent would be measured against the wrong road.
  if vehicle.remote then
    vehicle.progress = AK.TrackBuilder:GlobalProgress(track, vehicle.route, vehicle.distance)
    local previous = vehicle.lastProgress
    if previous then
      local delta = vehicle.progress - previous
      if delta > track.length * 0.5 then
        delta = delta - track.length
      elseif delta < -track.length * 0.5 then
        delta = delta + track.length
      end
      vehicle.odometer = (vehicle.odometer or 0) + delta
    elseif vehicle.odometer == nil then
      vehicle.odometer = vehicle.distance
    end
    vehicle.lastProgress = vehicle.progress
    vehicle.lapProgress = vehicle.odometer
    vehicle.lapsDone = math.max(0, math.floor(vehicle.odometer / track.length))
    vehicle.lap = vehicle.lapsDone + 1
    return
  end

  if vehicle.route == track then
    -- Approaching a fork: your lateral position at the split decides your line.
    -- Committing by where you already are is what makes the choice a driving
    -- decision rather than a menu.
    local branch, gap = AK.TrackBuilder:ForkAt(track, vehicle.distance, 6)
    if branch and gap and gap <= 6 then
      local wants = AK.Math.ForkSide(branch)
      local committed = (wants < 0 and vehicle.lateral < -0.15)
        or (wants > 0 and vehicle.lateral > 0.15)
      -- The AI states its intent explicitly; a human just steers.
      if vehicle.branchIntent == branch.id then committed = true end
      if vehicle.branchIntent and vehicle.branchIntent ~= branch.id then committed = false end
      if committed then
        -- isPlayer, so the attract demo taking a branch does not earn it.
        if vehicle.isPlayer then AK:UnlockAchievement("shortcut_run") end
        vehicle.route = branch
        -- NEGATIVE, and deliberately so. A kart commits while it is still `gap`
        -- metres SHORT of the split, and setting its branch distance to zero
        -- teleported it forward by that much -- then the camera, which trails
        -- by camBack, had to be clamped at zero because a negative branch
        -- distance used to wrap round to the branch's exit. That clamp froze
        -- the world for six metres while the kart kept moving, so the kart slid
        -- out from under the camera and snapped back. Builder:At clamps the
        -- LOOKUP now instead, which lets the position stay continuous: the kart
        -- crosses onto the branch at exactly the point it was already at.
        vehicle.distance = -gap
        -- Carry the lateral position across rather than halving it. `lateral`
        -- is measured in the same units on both routes, so scaling it slid the
        -- kart sideways at the split for no reason; it only needs containing
        -- inside a branch that is usually narrower than the road it leaves.
        local edge = AK.Math.RoadWidth(branch, 0)
        vehicle.lateral = AK.Math.Clamp(vehicle.lateral, -edge * 0.8, edge * 0.8)
        -- The render interpolates between the last two simulated positions, and
        -- these two are now in different coordinate spaces. Snap the history so
        -- no frame can draw a blend of the two.
        vehicle.prevDistance, vehicle.prevLateral = vehicle.distance, vehicle.lateral
        vehicle.branchIntent = nil
        if vehicle == race.player then
          AK.RaceUI:Announce(branch.name and branch.name:upper() or "SHORTCUT", AK.COLORS.lime)
        end
      end
    end
  elseif vehicle.distance >= vehicle.route.length then
    -- Rejoining the main line where the branch was authored to come back.
    local branch = vehicle.route
    local overshoot = vehicle.distance - branch.length
    vehicle.route = track
    vehicle.distance = branch.exit + overshoot
    -- CARRIED, not scaled. The split was fixed to carry the lateral across for
    -- exactly this reason -- scaling slides the kart sideways for no reason --
    -- and the rejoin was left multiplying by 0.6, so every shortcut ended with
    -- a lurch toward the centreline. Contained inside the main road's width,
    -- which is the only thing that actually needs saying here.
    local edge = AK.Math.RoadWidth(track, vehicle.distance)
    vehicle.lateral = AK.Math.Clamp(vehicle.lateral, -edge * 0.9, edge * 0.9)
    vehicle.branchIntent = nil
    vehicle.prevDistance, vehicle.prevLateral = vehicle.distance, vehicle.lateral
  end

  local progress = AK.TrackBuilder:GlobalProgress(track, vehicle.route, vehicle.distance)

  -- An odometer of total ground covered on the shared scale.
  --
  -- Progress alone cannot rank or count laps: it wraps at the start line, and
  -- the grid starts BEHIND that line at negative distance, so the back row
  -- would read as nearly a full lap ahead. Accumulating the per-frame change
  -- instead -- unwrapped, so a step across the line is small and positive --
  -- gives one monotonic number that works for ranking, laps and AI targets
  -- whichever route a kart happens to be on.
  local previous = vehicle.lastProgress
  if previous then
    local delta = progress - previous
    if delta > track.length * 0.5 then
      delta = delta - track.length
    elseif delta < -track.length * 0.5 then
      delta = delta + track.length
    end
    vehicle.odometer = (vehicle.odometer or 0) + delta
  elseif vehicle.odometer == nil then
    -- Seed from the grid slot so every kart turns the lap over at the line,
    -- not after each has driven one track length from wherever it started.
    vehicle.odometer = vehicle.distance
  end
  vehicle.lastProgress = progress
  vehicle.progress = progress
  vehicle.lapProgress = vehicle.odometer
  vehicle.lapsDone = math.max(0, math.floor(vehicle.odometer / track.length))
  vehicle.lap = vehicle.lapsDone + 1
end

--- Is there a wall at the edge of the road here?
---
--- Only where one can actually be SEEN: the rock sides of a tunnel, and the
--- rails of a launch ramp. Bouncing off nothing in open country reads as a bug
--- however carefully it is tuned -- there is visibly no wall there -- so in the
--- open the road simply ends and you go over the edge.
function Physics:VergeHasWall(track, distance)
  if AK.TrackBuilder:RampAt(track, distance) then return true, "ramp" end
  local cover = AK.TrackBuilder:TunnelDepth(track, distance)
  if cover > 0.05 then return true, "tunnel" end
  return false
end

function Physics:UpdateVehicle(race, vehicle, controls, dt)
  controls = controls or {}
  self:UpdateRoute(race, vehicle)
  -- Off the world: control is taken away entirely until Lakitu puts you back.
  if vehicle.falling then
    vehicle.speed = math.max(0, vehicle.speed - vehicle.speed * 4 * dt)
    vehicle.drifting = false
    return
  end
  -- Just dropped back on: throttle is limited while you gather yourself.
  vehicle.recovering = math.max(0, (vehicle.recovering or 0) - dt)
  vehicle.itemCooldown = math.max(0, vehicle.itemCooldown - dt)
  vehicle.boostTime = math.max(0, vehicle.boostTime - dt)
  vehicle.stun = math.max(0, vehicle.stun - dt)
  vehicle.slow = math.max(0, (vehicle.slow or 0) - dt)
  vehicle.star = math.max(0, (vehicle.star or 0) - dt)
  -- Hit reactions: spin-out, airtime, squash. Purely visual except that a
  -- spin-out costs you steering authority while it plays out.
  -- Launch ramps. Hitting one with speed puts you in the air: no grip, no
  -- off-road penalty, reduced steering, and a boost for landing clean.
  vehicle.air = math.max(0, (vehicle.air or 0) - dt)
  local ramp = AK.TrackBuilder:RampAt(vehicle.route or race.track, vehicle.distance)
  if ramp and vehicle.speed > 26 and (vehicle.air or 0) <= 0 and not vehicle.launched then
    vehicle.launched = true
    vehicle.air = 0.55 + (vehicle.speed / math.max(1, vehicle.maxSpeed)) * 0.75
    vehicle.airMax = vehicle.air
    if vehicle == race.player then
      AK.RaceUI:Announce("JUMP!", AK.COLORS.gold)
      -- The shake, the shove and the burst all live in RaceUI:FeelLaunch, which
      -- fires off the same rising edge the landing's dip fires off. Shaking
      -- from here as well double-counted it.
      if AK.PlaySfx then AK:PlaySfx("jump") end
    end
  elseif not ramp then
    if vehicle.launched and (vehicle.air or 0) <= 0 then
      vehicle.launched = false
      -- Clean landing pays out a short boost.
      vehicle.boostTime = math.max(vehicle.boostTime or 0, 0.8)
      -- The kart takes the impact, not just the camera. Its own channel rather
      -- than the lightning squash: that one flattens you to half height, which
      -- is being hit by something, not landing on your suspension.
      vehicle.land = 0.20
      vehicle.landMax = 0.20
      if vehicle == race.player then
        AK.RaceUI:Announce("CLEAN LANDING!", AK.COLORS.lime)
        AK.RaceUI:Shake(14)
        if AK.PlaySfx then AK:PlaySfx("landing") end
      end
    elseif (vehicle.air or 0) <= 0 then
      vehicle.launched = false
    end
  end

  vehicle.spin = math.max(0, (vehicle.spin or 0) - dt)
  vehicle.hop = math.max(0, (vehicle.hop or 0) - dt)
  vehicle.squash = math.max(0, (vehicle.squash or 0) - dt)
  vehicle.land = math.max(0, (vehicle.land or 0) - dt)
  vehicle.driftHop = math.max(0, (vehicle.driftHop or 0) - dt)
  vehicle.hopAir = math.max(0, (vehicle.hopAir or 0) - dt)
  vehicle.immune = math.max(0, (vehicle.immune or 0) - dt)
  -- The banana brake. Braking hard for a beat lets you ride out a trap instead
  -- of spinning: a timing-sensitive escape rather than "contact always spins".
  -- The window is deliberately short so it is a read, not a habit.
  if controls.brake and vehicle.speed > 8 then
    vehicle.brakeWindow = math.min(0.35, (vehicle.brakeWindow or 0) + dt)
  else
    vehicle.brakeWindow = 0
  end
  vehicle.brakeGuard = (vehicle.brakeWindow or 0) > 0.06 and (vehicle.brakeWindow or 0) < 0.30
  -- Star power outruns everything and cannot be slowed at all.
  if vehicle.star > 0 then vehicle.slow = 0 end
  local turning = (controls.left and -1 or 0) + (controls.right and 1 or 0)
  local boostMultiplier = vehicle.boostTime > 0 and 1.30 or 1
  if vehicle.star > 0 then boostMultiplier = boostMultiplier * 1.10 end
  -- Tow from running in someone's dirty air: up to +9% top speed.
  boostMultiplier = boostMultiplier * (1 + (vehicle.slipstream or 0) * 0.056)
  -- Being hit caps your speed for a moment. It never takes the wheel away, so
  -- you can always keep driving and recover the line.
  local slowFactor = vehicle.slow > 0 and .62 or 1
  -- Shrunk racers are slow and vulnerable until they grow back.
  vehicle.shrunk = math.max(0, (vehicle.shrunk or 0) - dt)
  if vehicle.shrunk > 0 then slowFactor = slowFactor * .60 end
  local topSpeed = vehicle.maxSpeed * boostMultiplier * slowFactor * (1 + (vehicle.aiBoost or 0))
  -- Sample the surface BEFORE anything reads it, or acceleration and steering
  -- run a frame behind the ground they are actually on.
  -- Function-scoped: the wall barrier below reads `edge`, and having it local to
  -- the block below made it a nil global every frame.
  local route = vehicle.route or race.track
  local edge = AK.Math.RoadWidth(route, vehicle.distance)
  vehicle.roadEdge = edge
  do
    local material, blend, onRoad = AK.Terrain.TYPES.ROAD, 0, true
    -- Airborne karts touch nothing, so they are always on clean air.
    if (vehicle.air or 0) <= 0 then
      material, blend, onRoad = AK.Terrain:Sample(route, vehicle.distance, vehicle.lateral)
    end
    if material.fall and blend > 0.9 then
      vehicle.falling = vehicle.falling or 0.01
    end
    -- A Mushroom overrules the surface. This is the whole reason a shortcut
    -- across grass is a decision rather than a mistake: the boost has to WIN
    -- the interaction, not be cancelled out by the terrain penalty.
    if (vehicle.boostTime or 0) > 0 or (vehicle.star or 0) > 0 then
      blend = blend * 0.20
    end
    vehicle.material = material
    vehicle.materialBlend = blend
    -- OFF ROAD means the wheels have LEFT THE ROAD, which Sample now answers
    -- directly. Deriving it from the material meant every surface the track
    -- paints across its own tarmac counted as leaving the course.
    vehicle.offroad = not onRoad and blend > 0.05
  end

  do
    -- Three pedal states, not two.
    --
    -- Throttle used to ignore `accelerate` entirely: the kart was at full power
    -- whenever it was not braking, so releasing the gas did nothing at all and
    -- the only way to shed speed was the brake. Coasting is the gentlest of the
    -- three ways to make a corner, and it was simply missing.
    --
    -- Only a control table that reports its throttle can coast. The AI never
    -- sets `accelerate` at all, so treating a missing field as "no throttle"
    -- would coast the entire field to a standstill -- but treating it as full
    -- power for the PLAYER too meant the kart drove itself off the line until
    -- the first brake press. `throttleAware` is what separates the two.
    local throttle
    if controls.brake then
      throttle = -1
    elseif controls.throttleAware and not controls.accelerate then
      throttle = 0        -- coasting: rolling resistance alone slows you
    else
      throttle = 1
    end
    if vehicle.slow > 0 then throttle = throttle * .55 end
    -- A flooded engine from a false start: no drive at all until it clears.
    vehicle.stalled = math.max(0, (vehicle.stalled or 0) - dt)
    if vehicle.stalled > 0 then throttle = 0 end
    if (vehicle.recovering or 0) > 0 then throttle = throttle * 0.45 end
    -- Power tapers as you approach terminal speed. Flat acceleration into a
    -- hard clamp is what made this feel like a spreadsheet: you hit the ceiling
    -- and stopped, with no sense of straining for the last few km/h.
    local ratio = AK.Math.Clamp(vehicle.speed / math.max(1, topSpeed), 0, 1.4)
    local surfaceAccel = AK.Terrain:Mix(vehicle.material or AK.Terrain.TYPES.ROAD,
      "acceleration", vehicle.materialBlend or 0)
    local power = vehicle.acceleration * (1 - ratio * ratio * 0.86) * surfaceAccel
    if throttle < 0 then power = vehicle.acceleration * (AK.db.tuning.brakeForce or 2.1) end
    vehicle.speed = vehicle.speed + power * throttle * dt
    -- Rolling resistance, so lifting off coasts down rather than braking hard.
    vehicle.speed = vehicle.speed - (2.2 + vehicle.speed * .022) * dt

    -- Spin-turn. Holding accelerate AND brake at a standstill rotates the kart
    -- in place instead of driving. It is how you recover from completely
    -- missing a turn, and it has to be its own state rather than the accidental
    -- result of two opposing forces cancelling out.
    if controls.brake and controls.accelerate ~= false and vehicle.speed < 6 and turning ~= 0 then
      vehicle.spinTurn = (vehicle.spinTurn or 0) + turning * 2.6 * dt
      vehicle.lateral = vehicle.lateral + turning * 0.55 * dt
      vehicle.speed = 0
    else
      vehicle.spinTurn = 0
    end

    -- A standalone hop, whether or not it becomes a drift. Deliberately silent:
    -- the same button press engages the drift a few lines below, and sounding
    -- both meant every single corner opened with a double blip.
    if controls.hopPressed and (vehicle.air or 0) <= 0 and (vehicle.hopAir or 0) <= 0 then
      vehicle.hopAir = 0.30
      vehicle.hopAirMax = 0.30
    end

    if controls.drift and turning ~= 0 and vehicle.speed > 18 then
      if not vehicle.drifting then
        -- Every kart racer starts a drift with a hop. It reads as commitment
        -- and it is the clearest signal that the drift actually engaged.
        vehicle.driftHop = 0.26
        vehicle.driftHopMax = 0.26
        if vehicle == race.player then
          -- No cue on the hop. driftTier1 follows ~0.3s later, and two blips at
          -- every corner entry is the density problem this round is about; the
          -- hop is carried visually instead.
          AK.RaceUI:Shake(5)
        end
      end
      vehicle.drifting = true
      if vehicle.driftDirection == 0 then vehicle.driftDirection = turning end

      -- Countersteering. This is the heart of the Mario Kart drift: rocking the
      -- stick against and back into the slide is what charges the mini-turbo.
      -- Simply holding the stick down through a corner should charge slowly;
      -- working the slide should charge fast.
      local counter = (turning ~= vehicle.driftDirection) and 1 or 0
      local rocked = (vehicle.lastSteer and turning ~= vehicle.lastSteer) and 1 or 0
      vehicle.lastSteer = turning
      local rate = (.30 + vehicle.driftStat * .05)      -- baseline, holding in
        + counter * (.22 + vehicle.driftStat * .04)     -- holding counter-steer
        + rocked * 0.55                                  -- the moment you rock it
      -- A mini-turbo comes from LOADING THE KART IN A CORNER, not from holding
      -- a button down. The drift engaged on any steering input at any time, so
      -- rocking the stick along a dead straight banked a mega-turbo every 0.8
      -- seconds for a 3%/s speed cost -- measured at 4.1% faster than simply
      -- driving in a straight line. That makes weaving the correct input on
      -- every straight in the game, and Elwynn has a 658m one. Off a corner the
      -- charge trickles instead: enough that setting a drift up a moment before
      -- turn-in still counts, nowhere near enough to farm.
      local load = AK.Math.Clamp(
        math.abs(AK.Math.RoadCurve(vehicle.route or race.track, vehicle.distance))
          / DRIFT_LOAD_FULL, 0, 1)
      rate = rate * (DRIFT_LOAD_FLOOR + (1 - DRIFT_LOAD_FLOOR) * load)
      -- The ladder cue fires from RaceUI's existing threshold-crossing check in
      -- VehicleEffects, which already tracks `previous.charge` and owns the
      -- matching spark pop. Detecting the same crossing here as well would
      -- simply double every rung.
      vehicle.driftCharge = AK.Math.Clamp(vehicle.driftCharge + dt * rate * 2.2, 0, 2.5)
      -- Countersteering also widens the slide, which is the risk half of it.
      vehicle.lateral = vehicle.lateral + vehicle.driftDirection * counter * 0.22 * dt
      vehicle.speed = vehicle.speed - vehicle.speed * .030 * dt
    elseif vehicle.drifting then
      self:ReleaseDrift(race, vehicle)
    end
    if turning ~= 0 then
      -- Turn-in authority peaks in the middle of the rev range and falls away
      -- at the top end.
      --
      -- This used to be a straight line rising with speed, which meant going
      -- faster made you turn BETTER -- so slowing down was strictly punished
      -- and the brake had no purpose whatsoever. Now arriving at a hairpin flat
      -- out washes the nose wide, and shedding speed (on the brake, or by
      -- drifting) is what makes the kart bite. That trade is the whole reason
      -- corners are interesting.
      local grip = (0.30 + 1.55 * ratio - 1.35 * ratio * ratio) * 1.35
      -- Weight transfer: braking loads the front and sharpens turn-in further,
      -- so trail-braking into a tight corner is a real technique rather than
      -- just a way to go slower.
      -- The brake is a third cornering tool, sitting between lifting off and
      -- committing to a drift.
      --
      -- It used to be a flat grip BONUS at every speed, so it only ever slowed
      -- you down -- no reason to prefer it to simply coasting. Now it is
      -- speed-dependent: below about half pace it still loads the front and
      -- sharpens turn-in, which is trail-braking and is genuinely quick. Push
      -- past that and the tyres let go, grip falls away and the kart skids
      -- wide. You trade a lot of speed for a line you no longer fully own,
      -- which is exactly the "skidding when going really fast" feel -- less
      -- controlled than a drift, far more urgent than lifting off.
      if controls.brake then
        vehicle.skidding = AK.Math.Clamp((ratio - 0.50) / 0.42, 0, 1)
        grip = grip * (1.24 - 0.66 * vehicle.skidding)
      else
        vehicle.skidding = 0
      end
      local turnStrength = vehicle.handling * (vehicle.drifting and DRIFT_STEER or 1) * grip
      -- Ice barely slows you but takes away your ability to point the kart;
      -- mud does the opposite. Steering and traction are separate knobs.
      local surface = vehicle.material or AK.Terrain.TYPES.ROAD
      local surfaceBlend = vehicle.materialBlend or 0
      turnStrength = turnStrength
        * AK.Terrain:Mix(surface, "steering", surfaceBlend)
        * AK.Terrain:Mix(surface, "traction", surfaceBlend)
      -- A spin-out takes the wheel away for its duration; that is the cost.
      if vehicle.spin > 0 then turnStrength = turnStrength * 0.22 end
      vehicle.lateral = vehicle.lateral + turning * turnStrength * dt
      -- The skid itself: the kart washes toward the OUTSIDE of the corner, on
      -- top of the grip it has already lost. Reduced authority alone reads as
      -- vague steering; an actual outward slide reads as breaking traction.
      if (vehicle.skidding or 0) > 0 then
        vehicle.lateral = vehicle.lateral - turning * vehicle.skidding * 0.46 * dt
      end
    end
    -- Spinning karts drift sideways off their own momentum.
    if vehicle.spin > 0 then
      vehicle.lateral = vehicle.lateral + math.sin(vehicle.spin * 9) * 0.35 * dt
    end
    -- Centrifugal push. Without this the curves are pure decoration: the road
    -- bends on screen but nothing about the corner has to be driven. Heavier
    -- karts wash out wider, which is what the weight stat should be buying.
    local push = AK.db.tuning.curvePush or 0
    if push > 0 and (vehicle.air or 0) <= 0 then
      local track = vehicle.route or race.track
      -- Read the authored curvature rather than differentiating the centreline.
      -- The old derivation measured the road's heading, so a diagonal straight
      -- shoved you sideways as hard as a corner did -- on Oribos that was 0.70
      -- lateral/s of push on a piece authored as dead straight, against only
      -- 0.81 of steering at top speed. Most of the wheel was being spent going
      -- straight ahead. 0.002 keeps the tuning knob a human-sized number.
      local curvature = AK.Math.RoadCurve(track, vehicle.distance) * 0.002
      -- DRIFTING HAS TO BEAT THE CORNER. This was 1.35, under a local named
      -- `grip` -- so a drift multiplied the centrifugal push by 1.35 while
      -- multiplying steering by only 1.30, and the two cancelled almost exactly.
      -- Measured (verify-drift.js), drifting bought 0.0% cornering speed at
      -- every severity, and -12% on a gentle bend: it made the corner WIDER.
      --
      -- A variable called `grip` set to a number that reduces grip is a sign
      -- error, not a design. In every kart racer the drift is how you get round
      -- something you cannot grip -- and here the only reason to ever press the
      -- button was to farm boosts on straights, which is exactly what the
      -- fastest line turned out to be.
      local grip = vehicle.drifting and DRIFT_BITE or 1
      -- Centrifugal force goes as v^2/r, not v. That distinction is the whole
      -- reason a corner is a decision.
      --
      -- Linear in speed, the push was ~0.49 lateral/s on a moderate bend
      -- against ~1.33/s of steering authority: the wheel beat the corner three
      -- times over at every speed, so holding any line was free and the road
      -- appeared to simply steer itself. Squaring it (normalised so top speed
      -- keeps roughly the old magnitude) means a hairpin taken flat out now
      -- pushes harder than full lock can answer -- you have to shed speed or
      -- drift -- while the same corner at half pace barely tugs at all. Slowing
      -- down becomes the thing that buys you the corner.
      local speedRatio = vehicle.speed / math.max(1, vehicle.maxSpeed)
      vehicle.lateral = vehicle.lateral
        - curvature * vehicle.speed * speedRatio * push * grip * (0.75 + vehicle.weight * 0.05) * dt
    end
    local drag = AK.Terrain:Mix(vehicle.material, "speed", vehicle.materialBlend)
    if drag < 1 then
      -- Scrub toward the material's own ceiling rather than applying a flat
      -- penalty, so mud and grass feel like genuinely different surfaces.
      local ceiling = vehicle.maxSpeed * drag
      if vehicle.speed > ceiling then
        vehicle.speed = vehicle.speed - (vehicle.speed - ceiling) * 3.2 * dt
      end
    end

    -- The edge of the world: mostly a wall you bounce off, periodically a gap
    -- you fall through.
    --
    -- Letting racers roam far off the tarmac was a mistake. The open ground
    -- beside these circuits is not really there -- it is skybox and scenery --
    -- so a wide allowance let you drive out into nothing and get wedged, and
    -- inside a tunnel it let you leave the shaft entirely. Falling and being
    -- lifted back is the honest answer to leaving the road.
    --
    -- But a drop everywhere is relentless, so the verge alternates: for most of
    -- its length there is a solid wall that costs you speed and the corner, and
    -- at regular intervals the wall is missing and the drop is real. Covered
    -- road is never gapped -- a hole in a mine shaft is where "stuck in the
    -- tunnel" came from.
    -- Rebound velocity from the last wall, decaying. Applied BEFORE the barrier
    -- test below so it actually moves the kart off what it hit; a one-off
    -- position nudge alone left you resting against the wall again on the very
    -- next frame, which is what made a wall feel like flypaper.
    if (vehicle.wallKick or 0) ~= 0 then
      vehicle.lateral = vehicle.lateral + vehicle.wallKick * dt
      vehicle.wallKick = vehicle.wallKick * math.max(0, 1 - dt * 6)
      if math.abs(vehicle.wallKick) < 0.01 then vehicle.wallKick = 0 end
    end

    local cover = AK.TrackBuilder:TunnelDepth(route, vehicle.distance)
    local room = AK.db.tuning.offroadRoom or 1.35
    -- A TUNNEL IS A SHAFT CUT TO THE ROAD. There is no verge inside one to run
    -- along, and the walls are drawn hard against the tarmac -- so the room to
    -- run wide shrinks to a graze allowance the moment the cover closes in.
    local covered = cover > 0.35
    local barrier = covered and (edge * 1.15) or (room * (1 - 0.30 * cover) * edge)

    -- A TUNNEL WALL IS A WALL.
    --
    -- Being off the road under cover used to set `falling` -- lifted out and
    -- dropped back like going over a cliff. There is no cliff: outside the
    -- shaft is solid rock. Worse, it was a trap. Durotar's Magma Cavern is a
    -- 140m 2.8-curve bend on the narrowest road in the game, and measured over
    -- a full race the field went into the void there THIRTY-FOUR times, each
    -- reset dropping the kart straight back into the same corner: one racer
    -- came home four minutes down. Scraping a tunnel wall costs you speed and
    -- the corner, which is punishment enough and is what the wall impact below
    -- was already tuned to deliver -- VergeHasWall walls tunnels already, so
    -- this branch was only ever pre-empting it with something harsher.
    if math.abs(vehicle.lateral) > barrier and (vehicle.air or 0) <= 0 then
      if not self:VergeHasWall(route, vehicle.distance) then
        -- Open country: nothing to hit, so you go over the edge and Lakitu
        -- brings you back.
        vehicle.falling = vehicle.falling or 0.01
      else
        local side = vehicle.lateral > 0 and 1 or -1
        local overshoot = math.abs(vehicle.lateral) - barrier
        vehicle.lateral = side * barrier
        if (vehicle.wallCooldown or 0) <= 0 then
          -- FIRST CONTACT is the only place a big speed penalty belongs, and
          -- it scales with how hard you arrived. The old code applied *0.70
          -- every frame you were still touching, which at 60fps compounds to a
          -- dead stop in about a tenth of a second -- that is the "it just
          -- makes me stop moving" feeling, not the impact itself.
          vehicle.wallCooldown = 0.45
          local bite = AK.Math.Clamp(overshoot / 0.30, 0.15, 1)
          vehicle.speed = vehicle.speed * (1 - 0.26 * bite)
          -- REBOUND, not a nudge. 0.09-0.20 of a road-half was small enough
          -- that hitting a wall read as sticking to it: you stopped, and then
          -- had to steer out of it yourself. A wall should give the kart back.
          -- Speed loss is deliberately unchanged -- the complaint was that the
          -- hit had no FORCE, not that it was too cheap.
          vehicle.lateral = vehicle.lateral - side * (0.22 + 0.34 * bite)
          -- And a lateral kick on the way out, so the impulse carries you clear
          -- rather than dropping you back against the same wall next frame.
          vehicle.wallKick = -side * (2.2 + 3.4 * bite)
          if vehicle == race.player then
            AK.RaceUI:Shake(10 + 18 * bite)
            AK.RaceUI:Flash({ 1, .8, .5 }, .08 + .09 * bite)
            -- Shove the CAMERA away from the wall too. Being hit by the world
            -- and being hit by an item should feel like the same kind of event.
            AK.RaceUI:Feel("kickX", side * (14 + 20 * bite))
            AK.RaceUI:Feel("dip", 0.30 * bite)
            if AK.PlaySfx then AK:PlaySfx("collision") end
          end
        else
          -- Still leaning on it: a scrape, expressed as a RATE so the frame
          -- rate cannot turn a graze into a handbrake. You keep driving, you
          -- just lose ground doing it.
          vehicle.speed = vehicle.speed - vehicle.speed * 1.1 * dt
          vehicle.lateral = vehicle.lateral - side * 0.35 * dt
        end
      end
    end
  end
  -- Wide enough that the barrier above is always what stops you, never this.
  -- At 1.42 the clamp was tighter than a lenient fence would be, so raising
  -- the fence alone would have done nothing on the widest sections. Sized off
  -- the tuning knob's own ceiling so the two can never disagree again.
  vehicle.lateral = AK.Math.Clamp(vehicle.lateral, -8, 8)
  vehicle.speed = AK.Math.Clamp(vehicle.speed, 0, topSpeed)
  vehicle.distance = vehicle.distance + vehicle.speed * dt
  vehicle.padCooldown = math.max(0, (vehicle.padCooldown or 0) - dt)
  vehicle.bumpCooldown = math.max(0, (vehicle.bumpCooldown or 0) - dt)
  vehicle.flattened = math.max(0, (vehicle.flattened or 0) - dt)
  vehicle.wallCooldown = math.max(0, (vehicle.wallCooldown or 0) - dt)
  -- Cleared on a fall so a rebound cannot survive being lifted back onto the
  -- road and fling the kart sideways the moment it lands.
  if vehicle.falling then vehicle.wallKick = 0 end
  -- Rolling scrape while off the tarmac, throttled so it does not machine-gun.
  if vehicle.offroad and vehicle == race.player and vehicle.speed > 12 then
    vehicle.scrape = (vehicle.scrape or 0) - dt
    if vehicle.scrape <= 0 then
      vehicle.scrape = 0.80
      if AK.PlaySfx then AK:PlaySfx("offroad") end
    end
  else
    vehicle.scrape = 0
  end
  -- One press deploys, the next fires. TriggerItem owns that decision.
  if controls.itemPulse and (vehicle.item or vehicle.held) then AK:TriggerItem(race, vehicle) end
end
