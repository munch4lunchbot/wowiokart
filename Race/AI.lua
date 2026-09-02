local _, AK = ...

-- CPU racers.
--
-- The AI drives through the SAME physics as the player: it submits steering,
-- throttle, brake, drift and item presses and nothing else. It gets no secret
-- speed, no teleporting and no ability to ignore terrain. Everything that makes
-- a CPU quick has to be something a human could also do, which is the only way
-- a race stays honest -- and it means any handling change tunes them too.
AK.AI = {}
local AI = AK.AI

local STYLES = {
  -- aggression: how hard they chase the racing line and use items
  -- precision:  how accurately they hold it
  -- daring:     willingness to drift and take a tight line
  { name = "Aggressive", aggression = 1.00, precision = 0.82, daring = 0.95, mistake = 0.05 },
  { name = "Technical",  aggression = 0.72, precision = 0.96, daring = 0.75, mistake = 0.03 },
  { name = "Heavy",      aggression = 0.85, precision = 0.78, daring = 0.55, mistake = 0.06 },
  { name = "Chaotic",    aggression = 0.95, precision = 0.55, daring = 1.00, mistake = 0.13 },
  { name = "Beginner",   aggression = 0.55, precision = 0.60, daring = 0.35, mistake = 0.20 },
}

function AI:CreatePersonality(index)
  local style = STYLES[(index - 1) % #STYLES + 1]
  -- A persistent lane preference. Without it every AI chases the same line and
  -- the whole field stacks into one clump on screen.
  local lane = ((index % 7) - 3) * 0.20
  return {
    style = style.name,
    aggression = style.aggression,
    precision = style.precision,
    daring = style.daring,
    mistakeRate = style.mistake,
    lane = lane, target = lane, think = 0, mistake = 0,
    driftCool = 0, wantDrift = false, itemPlan = 0,
    -- Corner state. `cornerSpeed` is the speed the physics will actually let
    -- this kart hold through whatever is coming; `peakCharge` remembers how
    -- much mini-turbo was banked before a drift is released, because
    -- ReleaseDrift zeroes the charge before anything could read it.
    limitSpeed = nil, peakCharge = 0, mistakeKind = nil,
    -- Everything /kart aireport prints. I cannot watch a race, so an AI that
    -- silently never brakes and one that brakes perfectly look identical from
    -- here -- these counters are the only way to tell them apart.
    stats = { drifts = 0, brakes = 0, mistakes = 0, rubber = 0, brakeTime = 0, driftTime = 0 },
  }
end

--- Difficulty scales the SAME dials a human would be judged on, rather than
--- handing out free speed.
--- Returns skill, mistake multiplier, and how much rubber-banding is allowed.
--- Hard is very nearly honest: it wins by braking later and drifting better,
--- not by being handed speed.
local function difficultyScale()
  local setting = AK.db.settings.difficulty
  if setting == "Easy" then return 0.72, 1.9, 1.40 end
  if setting == "Hard" then return 1.10, 0.45, 0.35 end
  return 1.0, 1.0, 1.0
end

--- Where the racing line wants to be, this far ahead.
--- Corners are anticipated: the AI aims at where the road WILL be, which is why
--- it turns in early instead of sawing at the apex.
local function lineAt(race, vehicle, ai, lookahead)
  -- The racing line is read off whichever road this kart is actually on.
  local track = vehicle.route or race.track
  local here = AK.Math.RoadCenter(track, vehicle.distance)
  local ahead = AK.Math.RoadCenter(track, vehicle.distance + lookahead)
  local bend = ahead - here
  -- Aim to the inside of the bend, scaled by how committed this racer is.
  local width = AK.Math.RoadWidth(track, vehicle.distance + lookahead)
  local inside = -AK.Math.Clamp(bend * 2.2, -1, 1) * width * 0.62 * ai.precision
  return AK.Math.Clamp(inside + ai.lane * width * 0.5, -width * 0.92, width * 0.92), bend
end

-- How fast this kart can actually get through a corner of this tightness.
--
-- Solved from the physics rather than invented. Physics pushes a kart outward
-- at `curve * CURVE_GAIN * v * (v/vmax) * curvePush * weightFactor` per second,
-- and it can answer with at most `handling` of steering. Setting those equal
-- and solving for v gives the speed at which the corner exactly consumes full
-- lock:
--
--     v = sqrt( authority * vmax / (CURVE_GAIN * curvePush * weightFactor * curve) )
--
-- That is the honest limit, so an AI that ignores it ploughs wide for real --
-- which is the whole point. No grip is handed out; they simply have to slow
-- down like anyone else.
--
-- Precision sets how close to that limit a driver dares run: a technical racer
-- carries 87% of the theoretical corner speed, a chaotic one only 82%, so the
-- tidy ones really are quicker through the turns. The wild ones get it back by
-- braking later -- see `margin` in brakeTarget, which shrinks with daring.
-- Measured on a mid-stat kart: a 4.6 hairpin caps at 47 m/s against a 72 m/s
-- top speed, so they must shed a third of it, exactly as a player must.
local CURVE_GAIN = 0.002

local function cornerSpeed(vehicle, curve, ai)
  curve = math.abs(curve)
  if curve < 0.12 then return math.huge end
  local push = AK.db.tuning.curvePush or 4.2
  if push <= 0 then return math.huge end
  local weightFactor = 0.75 + (vehicle.weight or 5) * 0.05
  local authority = (vehicle.handling or 1) * 0.95
  local limit = math.sqrt(authority * vehicle.maxSpeed
    / (CURVE_GAIN * push * weightFactor * curve))
  return limit * (0.82 + (ai and ai.precision or 0.8) * 0.16)
end

--- The speed to be down to, if anything in braking range demands one.
---
--- Scans forward and asks, for each sample, whether the kart could still shed
--- enough speed in the distance remaining. Returning only when the answer is
--- "only just" is what produces a late, committed braking point instead of
--- lifting off the moment a bend appears on the horizon.
local function brakeTarget(race, vehicle, ai)
  local track = vehicle.route or race.track
  local decel = (vehicle.acceleration or 40) * (AK.db.tuning.brakeForce or 2.1)
  if decel <= 0 then return nil end
  -- A confident driver leaves it later; a nervous one brakes early.
  local margin = 14 - ai.daring * 6
  for ahead = 6, 110, 7 do
    local limit = cornerSpeed(vehicle, AK.Math.RoadCurve(track, vehicle.distance + ahead), ai)
    if vehicle.speed > limit then
      local needed = (vehicle.speed * vehicle.speed - limit * limit) / (2 * decel)
      if needed >= ahead - margin then return limit end
    end
  end
  return nil
end

--- Item decisions by category rather than by name, so a new item slots in.
local function chooseItem(race, vehicle, ai, skill)
  local id = vehicle.held or vehicle.item
  if not id then return false end
  local item = AK.Items[id]
  if not item then return false end
  local length = race.track.length

  -- Something already deployed behind us: fire it when a target is reachable.
  if vehicle.held then
    local ahead = AK.Race:GetAheadTarget(vehicle)
    if ahead then
      local gap = AK.Math.SignedLoopDistance(vehicle.distance % length,
        ahead.distance % length, length)
      -- Fire only when the shot can actually connect: close enough that the
      -- target cannot simply drive out of the way, and lined up. Loosing a
      -- shell down an empty straight at someone 50m away just donates it, and
      -- a good player reads that as the AI being dumb rather than unlucky.
      -- Sharper drivers wait for a better window.
      local range = 26 + ai.aggression * 16
      if gap > 0 and gap < range and math.abs(ahead.lateral - vehicle.lateral) < 0.42 then
        return true
      end
    end
    -- Otherwise keep holding it as a shield, which is the correct play.
    return false
  end

  if item.effect == "boost" then
    -- Spend a boost on a straight, where it converts into the most distance.
    local _, bend = lineAt(race, vehicle, ai, 40)
    return math.abs(bend) < 0.25 and vehicle.speed > vehicle.maxSpeed * 0.7
  end
  if item.effect == "star" then
    -- Save it for traffic.
    local near = 0
    for _, other in ipairs(race.vehicles) do
      if other ~= vehicle and AK.Race:VehicleDistance(vehicle, other) < 30 then
        near = near + 1
      end
    end
    return near > 0
  end
  if item.effect == "bolt" then
    return (race.positions[vehicle] or 8) > 2
  end
  if item.effect == "drop" then
    -- Drop a trap when somebody is close behind.
    for _, other in ipairs(race.vehicles) do
      if other ~= vehicle and not other.finished then
        local gap = AK.Math.SignedLoopDistance(vehicle.distance % length,
          other.distance % length, length)
        if gap < 0 and gap > -30 then return true end
      end
    end
    -- Otherwise leave it on an apex rather than a straight. A banana on a
    -- corner sits exactly where everyone behind is committed and cannot dodge;
    -- the same banana on a straight is scenery. Placing them properly is most
    -- of what separates a driver from a dispenser.
    local track = vehicle.route or race.track
    local entering = math.abs(AK.Math.RoadCurve(track, vehicle.distance + 18)) > 1.6
    if entering and math.abs(AK.Math.RoadCurve(track, vehicle.distance)) < 2.4 then
      return race.rngAI:Chance(0.16 * skill)
    end
    return race.rngAI:Chance(0.002 * skill)
  end
  -- Projectiles: deploy so they trail as a shield, then fire when useful.
  return true
end

function AI:Controls(race, vehicle, dt)
  local ai = vehicle.ai
  if not ai then return {} end
  local skill, mistakeScale, rubberScale = difficultyScale()
  local rng = race.rngAI
  local length = race.track.length

  ai.think = ai.think - dt
  if ai.think <= 0 then
    ai.think = (0.16 + rng:Next() * 0.18) / skill

    local target = lineAt(race, vehicle, ai, 34 + vehicle.speed * 0.5)

    -- Forks. A branch is shorter in metres than the main line it replaces, so
    -- it always saves time -- the cost is that it is narrower and usually
    -- floored with something that punishes a missed apex. Daring decides who
    -- takes it, and the decision has to be made early enough to still reach
    -- the right side of the road, so this looks a long way ahead.
    if (vehicle.route or race.track) == race.track then
      local branch, gap = AK.TrackBuilder:ForkAt(race.track, vehicle.distance, 120)
      if branch and gap then
        if vehicle.forkChoice ~= branch.id then
          vehicle.forkChoice = branch.id
          -- Trailing racers gamble more; a leader has no reason to risk it.
          local desperation = (race.positions[vehicle] or 1) > 3 and 0.22 or 0
          vehicle.forkTake = rng:Next() < (ai.daring * 0.65 + desperation)
        end
        if vehicle.forkTake then
          vehicle.branchIntent = branch.id
          -- Commit to that side of the road well before the split.
          local side = (branch.side or -1)
          target = side * 0.85
        else
          vehicle.branchIntent = "none"
        end
      else
        vehicle.forkChoice, vehicle.branchIntent = nil, nil
      end
    end

    -- Ease away from whoever is alongside, so the field separates instead of
    -- grinding down the road in one lump.
    for _, other in ipairs(race.vehicles) do
      if other ~= vehicle and not other.finished
        and math.abs(other.distance - vehicle.distance) < 9
        and math.abs(other.lateral - vehicle.lateral) < .30 then
        target = target + (vehicle.lateral >= other.lateral and .34 or -.34)
      end
    end

    -- Avoid live hazards on the racing line.
    for _, projectile in ipairs(race.projectiles) do
      if projectile.owner ~= vehicle then
        local gap = AK.Math.SignedLoopDistance(vehicle.distance % length,
          projectile.distance % length, length)
        if gap > 0 and gap < 45 and math.abs(projectile.lateral - target) < .34 then
          target = projectile.lateral + (projectile.lateral > 0 and -0.55 or 0.55)
        end
      end
    end

    -- Chase item boxes when it is cheap to do so.
    if not vehicle.item and not vehicle.held and ai.aggression > 0.6 then
      for _, object in ipairs(race.objects) do
        if object.kind == "box" and not object.hidden and not object.fake then
          local gap = AK.Math.SignedLoopDistance(vehicle.distance % length,
            object.distance % length, length)
          if gap > 8 and gap < 60 and math.abs(object.lateral - target) < 0.55 then
            target = object.lateral
            break
          end
        end
      end
    end

    -- Deliberate mistakes. A field that never errs reads as a machine, and
    -- difficulty scales how often rather than how fast.
    --
    -- Three kinds, because one kind repeated is its own tell. Every roll comes
    -- off race.rngAI, never math.random: the seed is recorded so a race can be
    -- replayed exactly for ghosts, and a stray math.random would desynchronise
    -- that the moment anything else consumed a number.
    if rng:Chance(ai.mistakeRate * mistakeScale * 0.35) then
      ai.mistake = 0.35 + rng:Next() * 0.5
      local roll = rng:Next()
      -- A tidy driver's error is a small overshoot; a sloppy one gets it
      -- properly wrong.
      ai.mistakeKind = roll < 0.45 and "overshoot"
        or (roll < 0.78 and "lateDrift" or "fumble")
      ai.stats.mistakes = ai.stats.mistakes + 1
    end
    ai.target = AK.Math.Clamp(target, -1.1, 1.1)
  end

  ai.mistake = math.max(0, ai.mistake - dt)

  local delta = ai.target - vehicle.lateral
  local controls = {
    left = delta < -.055,
    right = delta > .055,
  }

  local track = vehicle.route or race.track
  local curveHere = AK.Math.RoadCurve(track, vehicle.distance)
  local curveSoon = AK.Math.RoadCurve(track, vehicle.distance + 26)

  -- BRAKING. Recomputed on the physics' own terms every tick rather than on
  -- the think timer: a braking point 200ms stale is a missed corner.
  ai.limitSpeed = brakeTarget(race, vehicle, ai)
  if ai.limitSpeed and vehicle.speed > ai.limitSpeed then
    controls.brake = true
    if not ai.wasBraking then ai.stats.brakes = ai.stats.brakes + 1 end
    ai.stats.brakeTime = ai.stats.brakeTime + dt
  end
  ai.wasBraking = controls.brake or false

  -- DRIFTING. Hold through anything sustained enough to bank a mini-turbo,
  -- and let go on the exit so the boost actually lands. Dropping controls.drift
  -- is what triggers Physics:ReleaseDrift, so the release runs through exactly
  -- the same path as a player letting go of the button.
  --
  -- Entry used to key off `delta`, the lateral steering error -- which is large
  -- almost all the time, because these karts are forever correcting their line
  -- around traffic and item boxes. That re-armed the hold every tick and made
  -- the release condition effectively unreachable, so the field sat drifting
  -- for a fifth of the race and banked almost no mini-turbos: all of the scrub,
  -- none of the boost. Curvature decides now, and the release is a decision
  -- about CHARGE rather than about the road running out.
  local corner = math.abs(curveSoon) > 1.5 or math.abs(curveHere) > 1.2
  ai.driftCool = math.max(0, (ai.driftCool or 0) - dt)
  -- How long a driver is willing to wait before cashing in. The bold hold out
  -- for a mega, the cautious take the mini and go; the tiers mirror the
  -- thresholds in Physics:ReleaseDrift, and a high drift stat charges sooner.
  local target = (ai.daring > 0.85 and 1.85 or (ai.daring > 0.62 and 0.95 or 0.40))
    * (1.10 - (vehicle.driftStat or 5) * 0.02)
  if corner and vehicle.speed > 26 and ai.daring > 0.4 and ai.driftCool <= 0 then
    ai.wantDrift = true
  end
  if not corner then ai.wantDrift = false end
  if ai.wantDrift and (vehicle.driftCharge or 0) >= target
    and ai.mistakeKind ~= "lateDrift" then
    -- Banked. Sit out a beat before re-arming so a chain of corners reads as a
    -- deliberate flick-flick rather than a stutter on the button.
    ai.wantDrift, ai.driftCool = false, 0.35
  end
  controls.drift = (ai.wantDrift and (controls.left or controls.right)) or false

  -- Remember the charge before it is banked: ReleaseDrift zeroes it, so this
  -- is the only moment a completed drift can be counted.
  if vehicle.drifting then
    ai.peakCharge = math.max(ai.peakCharge or 0, vehicle.driftCharge or 0)
    ai.stats.driftTime = ai.stats.driftTime + dt
  elseif (ai.peakCharge or 0) > 0 then
    if ai.peakCharge > 0.35 then ai.stats.drifts = ai.stats.drifts + 1 end
    ai.peakCharge = 0
  end

  -- MISTAKES, by kind.
  if ai.mistake > 0 then
    if ai.mistakeKind == "overshoot" then
      -- Turned in too hard and ran wide: the input is right, the amount is not.
      controls.left = delta < -.02
      controls.right = delta > .02
    elseif ai.mistakeKind == "lateDrift" then
      -- Held the drift past the exit, scrubbing speed down the next straight.
      controls.drift = controls.left or controls.right
    else
      -- Fumbled it completely.
      controls.left, controls.right = controls.right, controls.left
      controls.drift = false
    end
  else
    ai.mistakeKind = nil
  end

  ai.itemPlan = ai.itemPlan - dt
  if ai.itemPlan <= 0 and vehicle.itemCooldown <= 0 then
    if chooseItem(race, vehicle, ai, skill) then
      controls.itemPulse = true
      ai.itemPlan = 0.4
    else
      ai.itemPlan = 0.25
    end
  end

  -- RUBBER-BANDING. A small top-speed nudge proportional to the signed gap to
  -- the player. It never exceeds what a clean lap would achieve and it never
  -- teleports anyone.
  --
  -- The leash is deliberately ASYMMETRIC. Catching up gets the full cap;
  -- being reeled in gets a third of it. Symmetric correction is what makes a
  -- leader yo-yo -- slowed until caught, released until clear, slowed again --
  -- and that pattern is far more obvious, and more insulting, than simply
  -- being beaten.
  -- Guarded: this runs for every AI every frame, so a missing player here would
  -- break the entire field rather than one racer. Battle and attract both build
  -- a player vehicle, but a network race can be mid-handshake.
  local cap = AK.db.tuning.aiRubberBand or 0.07
  local reference = race.player or vehicle
  local playerGap = (reference.distance - vehicle.distance) / length
  -- 0.9 -> 0.4. THIS multiplier, not `aiRubberBand`, is what governs a close
  -- battle: at a 50m gap on a 2600m lap the cap is nowhere near binding, so
  -- sweeping the cap changes nothing at the front -- verify-drama.js shows an
  -- identical result at 0.02 and 0.07. Measured against a no-band baseline on
  -- identical seeds, 0.9 took races decided by under a second from 49% to 92%.
  -- That is not catch-up keeping the field honest, that is the band choosing
  -- the winner, and it is invisible precisely because it looks like a close
  -- race. At 0.4 the field still closes up (0.63s -> 0.45s average gap) and the
  -- lead still changes hands three times a race, but driving well decides it.
  local correction = AK.Math.Clamp(playerGap * 0.4 * skill * rubberScale,
    -cap * 0.35, cap * rubberScale)
  ai.stats.rubber = ai.stats.rubber + math.abs(correction) * dt
  vehicle.aiBoost = correction + AK:GetSpeedClass(AK.db.settings.engineClass).ai
  if ai.style == "Heavy" then vehicle.aiBoost = vehicle.aiBoost - .012 end
  return controls
end

--- What the field actually did, per racer.
---
--- I cannot watch a race. An AI that never brakes and one that brakes
--- perfectly are indistinguishable from here, and "the AI feels better" is not
--- something either of us can check by eye at 70 m/s. These counters are the
--- only honest read on whether any of this is firing.
-- Columns rather than one padded string per row.
--
-- A padded table only lines up in a monospace font, and WoW ships none that can
-- be relied on -- STANDARD_TEXT_FONT is proportional, so %-16s produces a
-- ragged mess. Laying each field out as its own left-aligned fontstring at a
-- fixed x keeps the table readable whatever the font does.
local REPORT_COLUMNS = {
  { title = "racer",   width = 132 },
  { title = "style",   width = 86 },
  { title = "drifts",  width = 52 },
  { title = "brakes",  width = 52 },
  { title = "miss",    width = 44 },
  { title = "brake%",  width = 56 },
  { title = "drift%",  width = 56 },
  { title = "rubber",  width = 58 },
  { title = "best lap", width = 74 },
}

local function buildReport(race)
  local skill, mistakeScale, rubberScale = difficultyScale()
  local report = {
    header = ("%s   skill x%.2f   mistakes x%.2f   rubber x%.2f   cap %.3f")
      :format(AK.db.settings.difficulty or "Normal", skill, mistakeScale, rubberScale,
        AK.db.tuning.aiRubberBand or 0.07),
    rows = {},
  }
  local elapsed = math.max(0.001, race.elapsed)
  for _, vehicle in ipairs(race.vehicles) do
    local ai = vehicle.ai
    if ai and ai.stats then
      local s = ai.stats
      report.rows[#report.rows + 1] = {
        (vehicle.racer and vehicle.racer.name or "?"):sub(1, 15), ai.style,
        tostring(s.drifts), tostring(s.brakes), tostring(s.mistakes),
        ("%.1f%%"):format(s.brakeTime / elapsed * 100),
        ("%.1f%%"):format(s.driftTime / elapsed * 100),
        ("%.2f"):format(s.rubber),
        vehicle.bestLap and AK.RaceUI:FormatTime(vehicle.bestLap) or "--",
      }
    end
  end
  if #report.rows == 0 then
    report.rows[1] = { "(no AI in this race)", "", "", "", "", "", "", "", "" }
  end
  -- The player's own line. The AI numbers only mean something measured against
  -- what a human actually does on the same circuit.
  local p = race.player
  if p and not p.ai then
    report.rows[#report.rows + 1] = {
      "YOU", "-", "-", "-", "-", "-", "-", "-",
      p.bestLap and AK.RaceUI:FormatTime(p.bestLap) or "--",
    }
  end
  return report
end

--- On-screen panel, because chat is not reachable when it matters.
---
--- The race frame swallows keyboard input, and the results screen sits at frame
--- level 900 covering the whole screen -- so the chat window is behind both.
--- Printing telemetry to chat meant the one moment you want to read it is the
--- one moment you cannot. This draws over both.
function AI:ShowPanel(report)
  local UI = AK.UI
  if not self.panel then
    local ROW, TOP, PAD = 18, 62, 14
    local width = PAD * 2
    for _, column in ipairs(REPORT_COLUMNS) do width = width + column.width end

    local frame = CreateFrame("Frame", "AzerothKartAIReport", UIParent, "BackdropTemplate")
    -- Sized from the column list and the biggest field we can ever show, never
    -- hard-coded: 8 AI plus a player row plus the header.
    frame:SetSize(width, TOP + ROW * (AK.MAX_RACERS + 2) + 46)
    frame:SetPoint("CENTER", 0, 0)
    -- Above the results screen (900) and the sound editor (950).
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(960)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
      edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.03, 0.05, 0.09, 0.97)
    frame:SetBackdropBorderColor(unpack(AK.COLORS.gold))
    frame:Hide()
    self.panel = frame

    frame.title = UI:NewText(frame, "AI REPORT", 14, AK.COLORS.gold, "CENTER")
    frame.title:SetPoint("TOP", 0, -9)
    frame.subtitle = UI:NewText(frame, "", 11, AK.COLORS.muted, "CENTER")
    frame.subtitle:SetPoint("TOP", frame.title, "BOTTOM", 0, -3)

    -- Column headings, then a grid of cells reused every time it opens.
    frame.cells = {}
    local x = PAD
    for index, column in ipairs(REPORT_COLUMNS) do
      local head = UI:NewText(frame, column.title, 11, AK.COLORS.blue, "LEFT")
      head:SetPoint("TOPLEFT", x, -TOP + 16)
      column.x = x
      x = x + column.width
      frame.cells[index] = {}
    end
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetVertexColor(0.38, 0.65, 0.92, 0.35)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", PAD, -TOP + 4)
    rule:SetPoint("TOPRIGHT", -PAD, -TOP + 4)

    for row = 1, AK.MAX_RACERS + 1 do
      for index, column in ipairs(REPORT_COLUMNS) do
        local cell = UI:NewText(frame, "", 11, { .84, .90, 1 }, "LEFT")
        cell:SetPoint("TOPLEFT", column.x, -TOP - (row - 1) * ROW)
        frame.cells[index][row] = cell
      end
    end

    local close = UI:NewButton(frame, "CLOSE", 130, 22, function() frame:Hide() end)
    close:SetPoint("BOTTOM", 0, 10)
  end

  self.panel.subtitle:SetText(report.header)
  for index in ipairs(REPORT_COLUMNS) do
    for row = 1, AK.MAX_RACERS + 1 do
      local value = report.rows[row] and report.rows[row][index] or ""
      local cell = self.panel.cells[index][row]
      cell:SetText(value)
      -- The player's own row is the comparison, so it reads as gold.
      cell:SetTextColor(unpack(report.rows[row] and report.rows[row][1] == "YOU"
        and AK.COLORS.gold or { .84, .90, 1 }))
    end
  end
  self.panel:Show()
end

--- Freeze the report at the flag, so it survives the race being torn down.
function AI:Snapshot(race)
  if race then self.lastReport = buildReport(race) end
end

--- Print the report for the running race, or the last one that finished.
---
--- There is no chat during a race -- the race frame swallows keyboard input --
--- so in practice this is read at the results screen or back at the menu. That
--- is exactly when Race:Stop has thrown the race away, hence the snapshot.
function AI:Report()
  local race = AK.Race.current
  local report = race and buildReport(race) or self.lastReport
  if not report then
    AK:Print("No AI data yet. Run a race with opponents, then press AI REPORT.")
    return
  end
  if not race then report.header = report.header .. "   (last finished race)" end
  self:ShowPanel(report)
end
