local _, AK = ...

-- The height of a launch, in metres, from the slowest launch that counts to
-- flat out. Read by UI/RaceUI.lua's jump arc; see the note at the launch below.
--
-- CALIBRATED AGAINST THE VERSION THAT WORKED. The arc people liked was 2.1
-- kart-widths of screen offset, and a kart is 2.2m, so that was about 4.6m of
-- apparent height -- with no camera movement at all, which is why it ran off
-- the top of the frame at speed. 5.4 at the top end is a shade more than that,
-- 3.0 at the bottom is a modest hop off a slow launch, and the camera now takes
-- a small share of it, so the biggest jump is bigger than the one that was fun
-- and still ends up inside the picture.
local JUMP_APEX_LOW, JUMP_APEX_HIGH = 3.0, 5.4

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
-- HOW MUCH OF THE SLIDE YOU KEEP WHEN YOU ARE NOT HOLDING IT IN.
--
-- A drift in this genre is a COMMITMENT. Once the kart is sideways it is going
-- round that way, and the stick decides only how tight -- hold it in and the
-- arc closes, fight it and the arc opens, but you never turn the other way
-- until you let the button go. Here the drift was nothing of the sort: it set a
-- direction, kept it for the charge meter, and then went on steering off raw
-- input at full authority in either direction. You could drift left and turn
-- right just as hard as if you were not drifting at all, which makes the whole
-- mechanic a 30% steering bonus with a light show attached.
--
-- Neutral stick still carries most of the turn, because that is what "sliding"
-- means; full countersteer unwinds it to a fifth without ever reversing it.
local DRIFT_NEUTRAL_HOLD = 0.62
local DRIFT_COUNTER_HOLD = 0.20
-- What is left of the wheel while the wheels are off the ground.
local AIR_STEER = 0.30
-- Published, because Race/AI.lua works out how fast it can take a corner and
-- has to use the same physics the corner is actually resolved with.
AK.DRIFT_BITE, AK.DRIFT_STEER = DRIFT_BITE, DRIFT_STEER

-- WHAT A BOOST IS WORTH. Every boost in the game used to be the same 1.30 --
-- the smallest mini-turbo and a Mushroom moved the same needle, and the drift
-- ladder's three rungs differed only in how long the identical boost lasted.
-- The ladder is most of the skill in a kart racer and it has to PAY.
local BOOST_MINI, BOOST_SUPER, BOOST_MEGA = 1.17, 1.25, 1.34
local BOOST_MUSHROOM, BOOST_PAD, BOOST_TRICK = 1.38, 1.30, 1.22
local BOOST_START, BOOST_SLING, BOOST_GHOST = 1.32, 1.20, 1.20
AK.BOOST = {
  mini = BOOST_MINI, super = BOOST_SUPER, mega = BOOST_MEGA,
  mushroom = BOOST_MUSHROOM, pad = BOOST_PAD, trick = BOOST_TRICK,
  start = BOOST_START, sling = BOOST_SLING, ghost = BOOST_GHOST,
}

--- Hand a kart a boost of a given strength.
---
--- Time and strength take the better of what is already running, separately: a
--- Mushroom fired during a mini-turbo does not get shortened by it, and a
--- mini-turbo banked during a Mushroom does not weaken it.
function Physics:Boost(vehicle, seconds, power)
  vehicle.boostTime = math.max(vehicle.boostTime or 0, seconds)
  vehicle.boostPower = math.max(vehicle.boostPower or 0, power or BOOST_PAD)
end

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
    local power = vehicle.driftCharge > 1.8 and BOOST_MEGA
      or (vehicle.driftCharge > .9 and BOOST_SUPER or BOOST_MINI)
    self:Boost(vehicle, boost, power)
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
    -- AIMED AT, NOT CAUGHT OUT.
    --
    -- The decision used to be taken inside six metres of the split, on where
    -- the kart happened to be at that instant -- a tenth of a second at racing
    -- speed, with nothing on screen saying whether you were on the right side
    -- of the road for it. You did not choose a shortcut, you found out whether
    -- you had taken one. That is most of what is awkward about a fork.
    --
    -- Lining up is now something you do over the whole approach: from sixty
    -- metres out the kart remembers the last moment it was on the branch's
    -- side, the sign says whether it is (see RenderFork), and a wobble in the
    -- last third of a second no longer throws the choice away.
    local branch, gap = AK.TrackBuilder:ForkAt(track, vehicle.distance, 60)
    if branch and gap then
      local aimed = AK.Math.ForkAimed(branch, vehicle.lateral)
      -- REMEMBERED IN METRES, not in seconds. A time window does not expire
      -- while the clock is not running -- during the countdown, or on any frame
      -- the race is paused -- so a kart that had once been on the branch's side
      -- kept its claim to the shortcut indefinitely. Distance always advances,
      -- and eighteen metres is the same forgiveness at racing speed with the
      -- useful property of being MORE forgiving when you are going slowly.
      if aimed then vehicle.forkAim = vehicle.distance end
      vehicle.forkAt = branch.id
    end
    if branch and gap and gap <= 10 then
      local committed = AK.Math.ForkAimed(branch, vehicle.lateral)
        or (vehicle.forkAt == branch.id and vehicle.forkAim
          and vehicle.distance - vehicle.forkAim < 18)
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
        vehicle.forkAim, vehicle.forkAt = nil, nil
        if vehicle == race.player then
          AK.RaceUI:Announce(branch.name and branch.name:upper() or "SHORTCUT", AK.COLORS.lime)
          -- WHERE YOU WERE WHEN YOU TOOK IT, so the rejoin can say whether it
          -- worked. A shortcut that saves eighty metres and changes nothing you
          -- can see is a shortcut that "kind of doesn't do much" -- and the one
          -- fact the player cannot work out for themselves is what would have
          -- happened if they had stayed on the main line. The nearest honest
          -- answer is what it did to their position.
          race.forkPlace = race.lastPosition
          race.forkName = branch.name
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
    -- And what it bought. Only when it actually moved you: a card that says
    -- "no change" every time is the chatter this game does not need, and the
    -- two cases worth hearing are the two that make the choice a choice.
    if vehicle == race.player and race.forkPlace then
      local gained = race.forkPlace - (race.lastPosition or race.forkPlace)
      local name = (race.forkName or "SHORTCUT"):upper()
      if gained > 0 then
        AK.RaceUI:Announce(("%s  +%d"):format(name, gained), AK.COLORS.lime)
      elseif gained < 0 then
        AK.RaceUI:Announce(("%s  %d"):format(name, gained), AK.COLORS.muted)
      end
      race.forkPlace, race.forkName = nil, nil
    end
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
    -- LONGER IN THE AIR. 0.55 to 1.30 seconds was a hop; the flight is the
    -- best thing a ramp gives you and it was over before you had looked at it.
    -- 0.62 to 1.52 is about a sixth longer at every speed, and the arc's height
    -- in RaceUI scales off this same number, so a full-speed launch is both
    -- longer and higher than a scrappy one -- which is the whole reason to
    -- carry speed into a jump.
    vehicle.air = 0.62 + (vehicle.speed / math.max(1, vehicle.maxSpeed)) * 0.90
    vehicle.airMax = vehicle.air
    -- HOW HIGH, in metres, decided here rather than in the renderer.
    --
    -- The arc used to be a screen offset -- so many kart-widths up the picture
    -- -- which meant its size was a fight with the frame rather than a property
    -- of the jump: at 2.1 widths it left the top of the screen, and cutting it
    -- to 0.8 to fix that took the jump with it. A height in metres is projected
    -- like anything else in the world, so it is right at any distance, and it
    -- belongs to the launch, where the speed that earned it is known.
    vehicle.airApex = JUMP_APEX_LOW + (JUMP_APEX_HIGH - JUMP_APEX_LOW)
      * AK.Math.Clamp((vehicle.air - 0.62) / 0.90, 0, 1)
    -- One trick per flight, and it has not been done yet.
    vehicle.tricked = false
    if vehicle == race.player then
      -- TEACH IT, THEN TRUST THEM.
      --
      -- The landing boost now depends on an input nobody has ever been asked
      -- for, so the first jumps have to say so -- and a game that is still
      -- explaining its controls on your fortieth race is nagging, not
      -- teaching. The prompt retires itself once you have actually landed a
      -- few, which is the only evidence that you know.
      local learned = (AK.db and AK.db.progress and AK.db.progress.tricks or 0) >= 5
      AK.RaceUI:Announce(learned and "JUMP!" or "JUMP!  HOP TO TRICK", AK.COLORS.gold)
      -- The shake, the shove and the burst all live in RaceUI:FeelLaunch, which
      -- fires off the same rising edge the landing's dip fires off. Shaking
      -- from here as well double-counted it.
      if AK.PlaySfx then AK:PlaySfx("jump") end
    end
  elseif not ramp then
    if vehicle.launched and (vehicle.air or 0) <= 0 then
      vehicle.launched = false
      -- THE LANDING PAYS FOR THE TRICK, NOT FOR THE JUMP.
      --
      -- Every landing used to hand out the same boost automatically, so the
      -- most eventful thing on most of these circuits asked the player for
      -- nothing at all: you drove at a ramp and a boost happened. A ramp is
      -- supposed to be a beat you PLAY -- flick the hop button while you are up
      -- there and land it, or come down with nothing.
      if vehicle.tricked then
        self:Boost(vehicle, 0.85, BOOST_TRICK)
        if vehicle == race.player and vehicle.isPlayer and AK.db and AK.db.progress then
          AK.db.progress.tricks = (AK.db.progress.tricks or 0) + 1
        end
        -- THREE IN A LAP. Thousand Needles is built around its leaps and there
        -- are exactly three of them, so this is the circuit's own mastery test:
        -- not "did you ever press the button" but "did you remember it every
        -- time, on the lap where remembering is hardest".
        if vehicle == race.player and vehicle.isPlayer then
          if vehicle.trickLap ~= vehicle.lap then
            vehicle.trickLap, vehicle.trickCount = vehicle.lap, 0
          end
          vehicle.trickCount = (vehicle.trickCount or 0) + 1
          if vehicle.trickCount >= 3 then AK:UnlockAchievement("air_show") end
        end
      end
      -- The kart takes the impact, not just the camera. Its own channel rather
      -- than the lightning squash: that one flattens you to half height, which
      -- is being hit by something, not landing on your suspension.
      vehicle.land = 0.20
      vehicle.landMax = 0.20
      if vehicle == race.player then
        -- A MISSED TRICK IS NOT WORTH A CAPTION.
        --
        -- Landing without one used to print "LANDED" in grey, which on a
        -- circuit with three ramps is nine notices a race whose entire content
        -- is that you failed to do something. Telling a player off for missing
        -- an optional flourish, over and over, is the surest way to make the
        -- flourish feel like a chore. The trick is celebrated; the plain
        -- landing just lands, with its own thump and shake and nothing said.
        if vehicle.tricked then
          AK.RaceUI:Announce("TRICK!", AK.COLORS.lime)
        end
        AK.RaceUI:Shake(vehicle.tricked and 14 or 9)
        if AK.PlaySfx then AK:PlaySfx("landing") end
      end
      vehicle.tricked = false
    elseif (vehicle.air or 0) <= 0 then
      vehicle.launched = false
    end
  end

  -- The trick itself. Any moment in the air will do -- the skill is remembering
  -- to do it at all while a corner is arriving -- but only once per flight, and
  -- the spin is visual, decided here so the renderer has something to read.
  if (vehicle.air or 0) > 0 and controls.hopPressed and not vehicle.tricked then
    vehicle.tricked = true
    vehicle.trick = math.max(vehicle.air, 0.30)
    vehicle.trickMax = vehicle.trick
    if vehicle == race.player then
      AK.RaceUI:Flash(AK.COLORS.gold, .10)
      if AK.PlaySfx then AK:PlaySfx("trick") end
    end
  end
  vehicle.trick = math.max(0, (vehicle.trick or 0) - dt)

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
  -- Strength comes off the boost that granted it; the field is cleared when the
  -- clock runs out so a spent Mushroom cannot lend its power to the next
  -- mini-turbo.
  if (vehicle.boostTime or 0) <= 0 then vehicle.boostPower = nil end
  local boostMultiplier = vehicle.boostTime > 0 and (vehicle.boostPower or BOOST_PAD) or 1
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
    --
    -- Only a surface that PUNISHES, though. This damped everything the wheels
    -- were on, so a Mushroom fired along Oribos's dash-panel road threw away
    -- four fifths of the strip's own advantage -- the boost overruling the
    -- thing that was helping it.
    if ((vehicle.boostTime or 0) > 0 or (vehicle.star or 0) > 0)
      and (material.speed or 1) < 1 then
      blend = blend * 0.20
    end
    -- A PAINTED BOOST STRIP HAS TO BOOST.
    --
    -- Every material carries a `boost` and only the dash panel sets one, and
    -- nothing anywhere read it. What the strip actually did was raise
    -- acceleration and nothing else: the top-speed side of it went through the
    -- `drag` branch further down, which only ever applies a material's speed
    -- figure when it is BELOW one -- so a surface meant to make you faster was
    -- silently ignored, and the comment in Data/Terrain.lua promising "+35% top
    -- speed" described nothing. 230m of Oribos is painted with this.
    --
    -- Granted as a real boost, so it also lights the flame, kicks the lens and
    -- reads on the HUD as a boost, which is what driving down a gold strip is
    -- supposed to look like. Short, and renewed every frame you stay on it.
    if (material.boost or 0) > 1 and blend > 0.5 then
      self:Boost(vehicle, 0.25, material.boost)
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
      -- AND A HOP MOVES YOU. In the games this is modelled on, tapping the hop
      -- button while turning shifts the kart across a little -- it is how you
      -- make the small adjustment that the wheel is too coarse for, edge onto a
      -- boost pad, or step around a banana you saw too late. Here the hop was
      -- purely a picture: it bounced the sprite and changed nothing at all,
      -- which is the whole of what the button does when you are not drifting.
      --
      -- Gated by the hop's own 0.3s, and it costs a sliver of speed, so
      -- crabbing sideways down the road stays a poor way to travel.
      if turning ~= 0 then
        vehicle.lateral = vehicle.lateral + turning * 0.10
        vehicle.speed = vehicle.speed * 0.985
      end
    end

    -- A DRIFT DOES NOT SNAP OFF WHEN THE STICK PASSES THROUGH CENTRE.
    --
    -- Entry needs a steering input -- you cannot start a slide going straight
    -- -- but staying in one does not, and requiring it meant a single frame at
    -- neutral between two corners of the same direction threw the mini-turbo
    -- away. No kart racer works that way: the button holds the drift, and the
    -- stick shapes it. Airborne karts cannot start one at all; there is nothing
    -- under the wheels to break traction.
    if controls.drift and vehicle.speed > 18
      and (vehicle.drifting or (turning ~= 0 and (vehicle.air or 0) <= 0)) then
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
      -- A NEUTRAL STICK IS NOT COUNTERSTEER. Both of these read `turning`
      -- directly, so releasing the wheel scored as holding it against the slide
      -- -- the largest charge bonus there is -- and letting go and grabbing it
      -- again scored as a rock. Now that a drift survives centre, that would
      -- have been the fastest way to bank a mega: do nothing.
      local counter = (turning ~= 0 and turning ~= vehicle.driftDirection) and 1 or 0
      local rocked = (turning ~= 0 and vehicle.lastSteer and vehicle.lastSteer ~= 0
        and turning ~= vehicle.lastSteer) and 1 or 0
      if turning ~= 0 then vehicle.lastSteer = turning end
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
      -- AND THE GROUND DECIDES WHETHER YOU CAN WORK A SLIDE AT ALL. Every
      -- material carries a `drift` figure -- ice 1.35, mud 0.40, scree 0.25 --
      -- and nothing had ever read one, so a mini-turbo charged at exactly the
      -- same rate on a glacier and in a bog. It is the cheapest way to make two
      -- surfaces feel like different places, and the file that declares them
      -- says in its own header that this is what the number is for.
      rate = rate * AK.Terrain:Mix(vehicle.material or AK.Terrain.TYPES.ROAD,
        "drift", vehicle.materialBlend or 0)
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
    -- WHERE THE WHEEL ACTUALLY POINTS THIS FRAME.
    --
    -- Gripping, that is simply the stick. Drifting, the kart is committed: it
    -- keeps turning the way it is sliding whatever the stick says, and the
    -- stick only chooses how tight -- all of it holding in, most of it at
    -- neutral, a fifth of it fighting the slide. It never crosses zero, which
    -- is the difference between a drift and a steering bonus.
    local steerInput = turning
    if vehicle.drifting then
      local hold = DRIFT_NEUTRAL_HOLD
      if turning == vehicle.driftDirection then hold = 1
      elseif turning ~= 0 then hold = DRIFT_COUNTER_HOLD end
      steerInput = vehicle.driftDirection * hold
      -- PUBLISHED, so the kart can be SEEN doing this. A commitment the player
      -- cannot see is indistinguishable from steering that has stopped working
      -- -- which is exactly how a drift that ignores half your inputs reads if
      -- nothing on screen says why. UI/RaceUI.lua leans the kart by this.
      vehicle.driftHold = hold
    else
      vehicle.driftHold = nil
    end
    if steerInput ~= 0 then
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
      --
      -- AND THEY WERE BEING MULTIPLIED TOGETHER AT FULL STRENGTH, which is not
      -- two knobs, it is one knob squared. Ice reads steering 1.10, traction
      -- 0.22 -- "you can still point it, you just slide" -- and came out at
      -- 0.24 of normal: a quarter of the wheel. Measured against the corner
      -- force on Ironforge, which is 47% ice, full lock lost to a moderate bend
      -- at almost any speed, so the kart went off and stayed off and the player
      -- was a passenger. Nine seconds of footage of exactly that is what this
      -- comment is here for.
      --
      -- Traction now enters through a floor: it can take away at most 55% of
      -- the wheel however slippery the surface is. Tarmac is untouched, ice is
      -- still comfortably the worst thing to corner on, and the answer to it is
      -- to carry about seventy per cent pace rather than twenty-five.
      local surface = vehicle.material or AK.Terrain.TYPES.ROAD
      local surfaceBlend = vehicle.materialBlend or 0
      turnStrength = turnStrength
        * AK.Terrain:Mix(surface, "steering", surfaceBlend)
        * (0.45 + 0.55 * AK.Terrain:Mix(surface, "traction", surfaceBlend))
      -- A spin-out takes the wheel away for its duration; that is the cost.
      if vehicle.spin > 0 then turnStrength = turnStrength * 0.22 end
      -- NOTHING TO STEER AGAINST IN MID-AIR. The launch above says in as many
      -- words that a jump costs you steering, and nothing anywhere implemented
      -- it: a kart off a ramp had the full wheel and no centrifugal push at
      -- all, which made the biggest jump on the lap the easiest place in the
      -- game to change lanes. A flight is meant to be a commitment you make on
      -- the run-up.
      if (vehicle.air or 0) > 0 then turnStrength = turnStrength * AIR_STEER end
      vehicle.lateral = vehicle.lateral + steerInput * turnStrength * dt
      -- The skid itself: the kart washes toward the OUTSIDE of the corner, on
      -- top of the grip it has already lost. Reduced authority alone reads as
      -- vague steering; an actual outward slide reads as breaking traction.
      if (vehicle.skidding or 0) > 0 then
        vehicle.lateral = vehicle.lateral - steerInput * vehicle.skidding * 0.46 * dt
      end
    else
      -- Coasting straight: no brake load, so no skid to carry into the next
      -- corner. This used to keep whatever the last steering frame left behind.
      vehicle.skidding = 0
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
  -- A BOOST DOES NOT END WITH A HANDBRAKE.
  --
  -- This was a hard clamp to the current ceiling, so the frame a Mushroom ran
  -- out the kart lost 38% of its speed instantly -- a wall you drive into with
  -- nothing on screen to explain it, and the better the boost the harder the
  -- wall. Every kart racer lets you carry the overspeed out and bleed it off.
  -- Nothing below the ceiling is affected: the power taper is what stops a kart
  -- there under its own steam, and always was.
  if vehicle.speed > topSpeed then
    vehicle.speed = math.max(topSpeed, vehicle.speed - (vehicle.speed - topSpeed) * 2.6 * dt)
  end
  vehicle.speed = math.max(0, vehicle.speed)
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
