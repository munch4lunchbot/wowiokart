local _, AK = ...

-- `throttleAware` marks a control table that actually reports its throttle.
-- The player's does; the AI's does not, and neither does a bare {} used for a
-- remote racer. Physics needs to tell those apart, because "no accelerate
-- field" has to mean full power for everyone else while meaning coasting for
-- the player. Keying off `accelerate == false` alone made the player's kart
-- drive itself out of the gate until the first time they touched the brake.
AK.Race = { controls = { throttleAware = true }, current = nil }
local Race = AK.Race

--- Clear the player's inputs between races WITHOUT losing the marker that says
--- this table reports its throttle. A bare wipe() took `throttleAware` with it,
--- so every race began with the kart at full power until the first brake press
--- re-established... nothing, because the flag was already gone.
function Race:ResetControls()
  wipe(self.controls)
  self.controls.throttleAware = true
  self.controls.accelerate = false
end

function Race:Init()
  if self.updateFrame then return end
  self.updateFrame = CreateFrame("Frame")
  self.updateFrame:Hide()
  self.updateFrame:SetScript("OnUpdate", function(_, elapsed) self:Update(elapsed) end)
end

function Race:BuildObjects(track)
  local objects = {}
  -- Item gates, kart-racer style: a row of boxes spanning the track so you pick
  -- your lane through them, rather than boxes scattered at random where finding
  -- one is luck. Five across, six gates to the lap.
  -- Density scales with lap length, so a 2600m circuit is not as barren as the
  -- old 1180m one was crowded.
  local GATES = math.max(4, math.floor(track.length / 420))
  local PER_GATE = 5
  for gate = 1, GATES do
    local at = 70 + (gate - 1) * (track.length / GATES)
    for slot = 1, PER_GATE do
      table.insert(objects, {
        kind = "box", name = "Item Box",
        distance = at,
        lateral = (slot - (PER_GATE + 1) / 2) * 0.36,
        hidden = false, respawn = 0,
      })
    end
  end

  -- Dash panels. A reason to take a specific line, and a reward for holding it.
  local PADS = { 0.14, 0.31, 0.48, 0.66, 0.86 }
  for index, fraction in ipairs(PADS) do
    for lane = -1, 1 do
      table.insert(objects, {
        kind = "boost", name = "Dash Panel",
        distance = track.length * fraction + lane * 6,
        lateral = lane * 0.34 + (index % 2 == 0 and 0.18 or -0.18),
        hidden = false, respawn = 0,
      })
    end
  end
  table.insert(objects, { kind = "shortcut", name = "Risky Shortcut", distance = track.length * .46, lateral = 1.02, hidden = false })
  -- Mirror mode flips the road; the furniture standing on it has to flip too.
  -- Done once here rather than at every read, so nothing downstream -- physics,
  -- renderer, AI, minimap -- has to know the mode exists.
  for _, object in ipairs(objects) do
    object.lateral = AK.Math.Mirrored(object.lateral)
  end
  return objects
end

function Race:AddVehicle(race, racer, kart, owner, isPlayer, index)
  local vehicle = AK.Physics:CreateVehicle(racer, kart, owner, isPlayer)
  vehicle.networkId = owner or ("ai" .. index)
  vehicle.distance = -(index - 1) * 11
  vehicle.lap = 1
  vehicle.seed = index * 1.618
  -- Remote racers render as the actual player behind them. A group member's
  -- name resolves as a unit token.
  --
  -- The solo player is added with the literal owner "player", which is ALSO a
  -- valid unit token -- so this test passed for the local player and forced
  -- their own character model over whichever racer they had chosen. Exclude the
  -- token explicitly as well as the local character's name.
  if owner and owner ~= "player" and owner ~= AK.Net:PlayerName()
    and not isPlayer and UnitExists(owner) then
    vehicle.unit = owner
  end
  -- Per-lap splits and a running stat line, for the HUD and the results screen.
  vehicle.lapTimes = {}
  vehicle.lapStart = 0
  vehicle.bestLap = nil
  vehicle.topSpeed = 0
  vehicle.driftTime = 0
  vehicle.airTime = 0
  if not isPlayer and not owner then vehicle.ai = AK.AI:CreatePersonality(index) end
  table.insert(race.vehicles, vehicle)
  if owner then race.byOwner[owner] = vehicle end
  race.byNetworkId[vehicle.networkId] = vehicle
  if isPlayer then race.player = vehicle end
  return vehicle
end

function Race:BuildRace(mode, options)
  options = options or {}
  -- Battle draws from the dedicated arena pool, never the circuit list: an
  -- arena is authored short and tight on purpose, and picking it up from
  -- AK.db.selection.track would silently hand a battle a full-length race
  -- circuit again the moment the player had a normal track selected.
  local track = mode == "battle"
    and AK:GetArena(options.arena or AK.Arenas[1].id)
    or AK:GetTrack(options.track or AK.db.selection.track)
  local race = {
    mode = mode,
    track = track,
    laps = track.laps,
    state = AK.RACE_STATES.COUNTDOWN,
    countdown = 3.0,
    elapsed = 0,
    delta = 0,
    vehicles = {},
    byOwner = {},
    byNetworkId = {},
    positions = {},
    objects = self:BuildObjects(track),
    hazards = self:BuildHazards(track),
    projectiles = {},
    controls = self.controls,
    remoteInputs = {},
    lastLap = 1,
    lastPosition = nil,
    grandPrix = options.grandPrix,
    network = options.session and { session = options.session, host = options.host, isHost = options.isHost } or nil,
  }
  -- Separate streams so an extra AI decision cannot shift the item sequence.
  -- The seed is recorded, which is what makes a race reproducible for ghosts
  -- and for chasing down a physics bug.
  race.seed = options.seed or AK.RNG:FreshSeed()
  race.rngItems = AK.RNG:New(race.seed)
  race.rngAI = AK.RNG:New(race.seed + 0x9E3779B9)
  local localName = race.network and AK.Net:PlayerName() or "player"
  if race.network then
    -- SORTED, because pairs() has no order and every client builds its own grid
    -- from its own copy of the roster. Unsorted, each machine dealt the starting
    -- slots differently -- AddVehicle spaces the grid by index, so the same
    -- racer sat in a different place on every screen until the host's first
    -- snapshot arrived and yanked everyone into line. Sorting by name is
    -- arbitrary but identical everywhere, which is the only property that
    -- matters here.
    local roster = options.roster or {}
    local owners = {}
    for owner in pairs(roster) do owners[#owners + 1] = owner end
    table.sort(owners)
    for count, owner in ipairs(owners) do
      local entry = roster[owner]
      self:AddVehicle(race, AK:GetRacer(entry.racer), AK:GetKart(entry.kart), owner, owner == localName, count)
    end
    -- Filler bots for the empty grid slots nobody joined. This used to index
    -- AK.Racers directly by position, which does not exclude "you" -- entry 2
    -- in the roster -- so a filler bot could be dealt the "you" spec, whose
    -- model is `{ unit = "player" }`. Model:Dress resolves that unit locally on
    -- EVERY client, so every viewer would have seen that bot driving around
    -- wearing their OWN character, uncontrolled. BuildAIField already excludes
    -- "you" for exactly this reason; the fill-in loop just was not using it.
    local startCount = #race.vehicles
    local filler = AK:BuildAIField(nil, AK.MAX_RACERS - startCount, race.rngAI)
    while #race.vehicles < AK.MAX_RACERS do
      local aiIndex = #race.vehicles + 1
      self:AddVehicle(race, filler[aiIndex - startCount], AK.Karts[(aiIndex - 1) % #AK.Karts + 1], nil, false, aiIndex)
    end
  else
    local chosen = AK:GetRacer(AK.db.selection.racer)
    self:AddVehicle(race, chosen, AK:GetKart(AK.db.selection.kart), "player", true, 1)
    local total = (mode == "time_trial" or mode == "practice") and 1 or math.min(AK.MAX_RACERS, (AK.db.settings.aiCount or 7) + 1)
    -- Shuffled per race off the seeded AI stream: without this the grid was the
    -- same faces in the same order every single race, no matter how many
    -- racers the roster actually holds -- see BuildAIField.
    local field = AK:BuildAIField(chosen, total - 1, race.rngAI)
    while #race.vehicles < total do
      local index = #race.vehicles + 1
      self:AddVehicle(race, field[index - 1], AK.Karts[(index + 1) % #AK.Karts + 1], nil, false, index)
    end
  end
  if mode == "time_trial" then
    -- No item boxes at all, and you start with three Mushrooms. Time Trial is
    -- where the driving model is judged with nothing else in the way.
    for i = #race.objects, 1, -1 do
      if race.objects[i].kind == "box" then table.remove(race.objects, i) end
    end
    race.player.item, race.player.itemCount = "triple_mushroom", 3
    race.recorder = AK.Ghost:NewRecorder(track, AK.db.selection.racer)
    race.ghost = AK.Ghost:NewPlayer(AK.Ghost:Best(track.id))
  end
  if not race.player then
    -- A race invitation may arrive before the player's lobby JOIN was echoed. Do not
    -- create a broken spectator state; the local entry remains a usable fallback.
    self:AddVehicle(race, AK:GetRacer(AK.db.selection.racer), AK:GetKart(AK.db.selection.kart), localName, true, #race.vehicles + 1)
  end
  return race
end

function Race:Start(mode, options)
  self:Init()
  self:StopAttract()
  if self.current then self:Stop(false) end
  self:ResetControls()
  -- Count sound from zero, so the rate the editor reports describes THIS race
  -- rather than everything since login.
  if AK.ResetSfxStats then AK:ResetSfxStats() end
  self.current = self:BuildRace(mode, options)
  AK.Menu:Hide()
  AK.Results:Hide()
  AK.RaceUI:Show(self.current)
  AK.RaceUI:Announce(mode == "multiplayer" and "SYNCING START GRID" or "LINE UP FOR THE COUNTDOWN", AK.COLORS.muted)
  self.updateFrame:Show()
  if AK.PlaySfx then AK:PlaySfx("countdown") end
end

--- Run the same race again, from the lights.
---
--- Every kart game has this on the pause menu and it was the one thing missing
--- from ours: a bad start or a shell on the last corner meant quitting to the
--- menu and rebuilding the whole selection. Multiplayer is excluded -- you
--- cannot restart a race other people are in -- and a Grand Prix restarts the
--- CURRENT heat rather than the cup, which is what the pause menu of one is.
function Race:Restart()
  local race = self.current
  if not race or race.mode == "attract" or race.mode == "multiplayer" then return end
  -- A battle has no track id to hand back -- it is built from the arena pool by
  -- its own entry point, which also re-rolls the stage.
  if race.battle then return self:StartBattle() end
  self:Start(race.mode, {
    track = race.track and race.track.id,
    grandPrix = race.grandPrix,
  })
end

--- Attract mode: a real race running behind the menu with nobody driving.
--- It reuses the entire renderer, so the title screen shows the actual game
--- rather than a static panel.
function Race:StartAttract()
  if self.current and self.current.mode == "attract" then return end
  if self.current then return end
  self:Init()
  self:ResetControls()
  local tracks = AK.Tracks
  local pick = tracks[math.random(#tracks)]
  self.current = self:BuildRace("attract", { track = pick.id })
  -- Nobody is at the wheel: hand the player's kart to the AI too.
  local player = self.current.player
  if player then
    player.ai = AK.AI:CreatePersonality(9)
    player.isPlayer = false
  end
  AK.RaceUI:Show(self.current)
  AK.RaceUI:SetHudShown(false)
  self.updateFrame:Show()
end

function Race:StopAttract()
  if self.current and self.current.mode == "attract" then
    self.updateFrame:Hide()
    self.current = nil
    AK.RaceUI:Hide()
    AK.RaceUI:SetHudShown(true)
  end
end

-- Hazards: independent entities that live on the track and attack you.
--
-- These are NOT items. Nobody chose to put them there, they belong to the
-- course, and each course's hazard is a large part of its identity -- the point
-- is that the track itself is a participant, not just a shape.
function Race:BuildHazards(track)
  local hazards = {}
  if not track.hazardPlan then return hazards end
  for _, plan in ipairs(track.hazardPlan) do
    for i = 1, (plan.count or 1) do
      table.insert(hazards, {
        kind = plan.kind,
        name = plan.name or track.hazards[1],
        distance = (plan.at or 0) * track.length + (i - 1) * (plan.spacing or 40),
        lateral = plan.lateral or 0,
        -- Traffic runs along the road; patrols sweep side to side.
        speed = plan.speed or 0,
        sweep = plan.sweep or 0,
        phase = i * 1.7,
        radius = plan.radius or 3.0,
        slow = plan.slow or 1.1,
        reaction = plan.reaction or "spin",
        -- Optional creature appearance. Absent, or unresolvable on this
        -- client, and the hazard falls back to its icon.
        model = plan.model,
        icon = plan.icon,
      })
    end
  end
  for _, hazard in ipairs(hazards) do
    hazard.lateral = AK.Math.Mirrored(hazard.lateral)
  end
  return hazards
end

--- Which road an entity lives on. Everything authored into a course sits on the
--- main line unless it says otherwise, and a kart can only meet what is on the
--- road it is currently driving. Without this, a kart 90m down a branch would
--- collide with the item box 90m along the main track, which it cannot see and
--- is nowhere near.
function Race:RouteOf(race, entity)
  return entity.route or race.track
end

function Race:UpdateHazards(race, dt)
  local length = race.track.length
  for _, hazard in ipairs(race.hazards or {}) do
    -- Traffic moves down the road; everything else holds station.
    if hazard.speed ~= 0 then
      hazard.distance = (hazard.distance + hazard.speed * dt) % length
    end
    if hazard.sweep ~= 0 then
      hazard.phase = hazard.phase + dt * 1.4
      hazard.lateral = math.sin(hazard.phase) * hazard.sweep
    end
    for _, vehicle in ipairs(race.vehicles) do
      if not vehicle.finished and not vehicle.falling and (vehicle.air or 0) <= 0
        and self:RouteOf(race, vehicle) == self:RouteOf(race, hazard) then
        local gap = AK.Math.DistanceOnLoop(vehicle.distance % length, hazard.distance, length)
        if gap < hazard.radius and math.abs(vehicle.lateral - hazard.lateral) < .34 then
          -- Hazards route through the same hit resolver as items, so star
          -- power and the brake dodge work against them too.
          local outcome = self:ResolveHit(vehicle)
          if outcome == "vulnerable" then
            self:SlowVehicle(vehicle, hazard.slow, hazard.name:upper() .. "!", hazard.reaction)
            if race.battle then self:PopBalloon(race, vehicle, nil) end
          elseif outcome == "brake" and vehicle == race.player then
            AK.RaceUI:Announce("DODGED!", AK.COLORS.lime)
            vehicle.immune = 0.6
          end
        end
      end
    end
  end
end

-- Battle Mode.
--
-- Not a race with the finish line removed: there is no lap, no position and no
-- progress. Everyone carries three balloons, items take them, and the last
-- racer with any left wins. Collisions and item placement carry the whole mode,
-- so the arena is short and everyone is packed together on purpose.
function Race:StartBattle()
  self:Init()
  self:StopAttract()
  if self.current then self:Stop(false) end
  self:ResetControls()
  -- The same two things Race:Start does and this did not. A battle counts down
  -- on the grid exactly like a race does, and started in silence; and the sound
  -- editor's firing rates are meant to describe ONE fixture, so they have to be
  -- zeroed by every entry point into the world, not just the circuit one.
  if AK.ResetSfxStats then AK:ResetSfxStats() end
  -- A fresh arena each fight, so back-to-back battles do not open on the same
  -- stage every time. Not fed through a seeded stream: this decides which
  -- fixture gets played at all, not an outcome inside one, so it does not need
  -- to be reproducible the way an item roll or an AI's line does.
  --
  -- Never the one just played, though. With two stages in the pool a fair coin
  -- repeats half the time, so "a fresh arena each fight" was a coin flip
  -- describing itself -- and pressing BATTLE AGAIN, which is exactly when the
  -- player is asking for something else, opened the same cave as often as not.
  local pool = {}
  for _, arena in ipairs(AK.Arenas) do
    if arena.id ~= self.lastArena or #AK.Arenas == 1 then pool[#pool + 1] = arena end
  end
  local arena = pool[math.random(#pool)]
  self.lastArena = arena.id
  local race = self:BuildRace("battle", { arena = arena.id })
  race.laps = 999                       -- never completes by distance
  race.battle = true
  -- Spread the field around the loop so nobody starts in anyone's lap.
  local spacing = race.track.length / math.max(1, #race.vehicles)
  for index, vehicle in ipairs(race.vehicles) do
    vehicle.balloons = AK.BATTLE_BALLOONS
    vehicle.distance = (index - 1) * spacing
    vehicle.lateral = ((index % 3) - 1) * 0.4
  end
  self.current = race
  AK.Menu:Hide()
  AK.Results:Hide()
  AK.RaceUI:Show(race)
  AK.RaceUI:Announce(("BATTLE!  %d BALLOONS EACH"):format(AK.BATTLE_BALLOONS), AK.COLORS.gold)
  self.updateFrame:Show()
  if AK.PlaySfx then AK:PlaySfx("countdown") end
end

--- A balloon pops. Returns true when that racer is out.
function Race:PopBalloon(race, vehicle, attacker)
  if not race.battle or vehicle.eliminated then return false end
  vehicle.balloons = math.max(0, (vehicle.balloons or AK.BATTLE_BALLOONS) - 1)
  if vehicle == race.player then
    AK.RaceUI:Announce(("BALLOON POPPED  %d LEFT"):format(vehicle.balloons), AK.COLORS.danger)
    AK.RaceUI:Flash(AK.COLORS.danger, .28)
    AK.RaceUI:Shake(18)
  elseif attacker == race.player then
    AK.RaceUI:Announce("POPPED " .. vehicle.racer.name:upper() .. "!", AK.COLORS.lime)
  end
  if vehicle.balloons <= 0 then
    vehicle.eliminated = true
    vehicle.finished = true
    vehicle.finishTime = race.elapsed
    if vehicle == race.player then
      AK.RaceUI:Announce("ELIMINATED", AK.COLORS.danger)
    end
    return true
  end
  return false
end

--- Battle ends when one racer is left standing.
function Race:CheckBattleEnd(race)
  if not race.battle then return end
  local alive, last = 0, nil
  for _, vehicle in ipairs(race.vehicles) do
    if not vehicle.eliminated then alive = alive + 1; last = vehicle end
  end
  if alive <= 1 then
    -- The winner never crossed anything, so nothing had ever marked them home.
    -- The results screen builds its table from finishers.
    if last then
      last.finishTime = race.elapsed
      last.finished = true
    end
    -- Last one standing, and never touched: the battle equivalent of a clean
    -- sheet. Balloons are only ever decremented by PopBalloon, so three left
    -- means nothing ever landed on you.
    if last and last == race.player and (last.balloons or 0) >= AK.BATTLE_BALLOONS then
      AK:UnlockAchievement("flawless_battle")
    end
    self:FinishRace(race)
  end
end

function Race:StartGrandPrix()
  -- Used to always be AK.Cups[1]: there was no selection UI and nothing else
  -- read a chosen cup, so every other one authored (the Wild Worlds Cup, and
  -- now the Frontier Cup) was dead data -- present in the file, unreachable in
  -- the game. MainMenu's SELECT CUP screen now writes AK.db.selection.cup.
  local cup = AK:GetCup(AK.db.selection.cup)
  local gp = { cup = cup, index = 1, points = {} }
  self:Start("grand_prix", { track = cup.tracks[1], grandPrix = gp })
end

function Race:NextGrandPrix()
  local race = self.current
  local gp = race and race.grandPrix
  if not gp then AK.Menu:Show(); return end
  gp.index = gp.index + 1
  if gp.index > #gp.cup.tracks then
    AK.db.progress.trophies[gp.cup.id] = true
    AK:UnlockAchievement("cup_champion")
    AK.Results:ShowGrandPrix(gp)
    return
  end
  self:Start("grand_prix", { track = gp.cup.tracks[gp.index], grandPrix = gp })
end

function Race:Stop(showMenu)
  if self.updateFrame then self.updateFrame:Hide() end
  self.current = nil
  AK.RaceUI:Hide()
  if showMenu then AK.Menu:Show() end
end

function Race:OnKey(key, down)
  if not self.current then return end
  key = key:upper()
  if key == "ESCAPE" and down then
    -- Multiplayer cannot pause, so ESC has to be a straight exit there or the
    -- fullscreen frame traps the player with no way out.
    if self.current.mode == "multiplayer" then
      self:Stop(true)
    else
      self:TogglePause()
    end
    return
  end
  if key == "W" or key == "UP" then self:SetControl("accelerate", down)
  elseif key == "S" or key == "DOWN" then self:SetControl("brake", down)
  elseif key == "A" or key == "LEFT" then self:SetControl("left", down)
  elseif key == "D" or key == "RIGHT" then self:SetControl("right", down)
  elseif key == "SPACE" then self:SetControl("drift", down)
  elseif (key == "LSHIFT" or key == "RSHIFT") and down then self:UseItem() end
end

function Race:SetControl(control, value)
  local race = self.current
  if not race then return end
  if race.state == AK.RACE_STATES.COUNTDOWN and control == "accelerate" and value then race.launchPress = race.countdown end
  -- Rising edge on the drift key is a hop in its own right. In Mario Kart the
  -- hop button is not just "start a drift" -- it clears low hazards, adjusts
  -- your line and crosses small gaps, and drift is what it becomes if you are
  -- also steering.
  if control == "drift" and value and not self.controls.drift then
    self.controls.hopPressed = true
  end
  if control == "drift" and self.controls.drift and not value and race.player then AK.Physics:ReleaseDrift(race, race.player) end
  self.controls[control] = value
end

function Race:UseItem()
  local race = self.current
  if not race or race.state ~= AK.RACE_STATES.RACING then return end
  if not race.player.item and not race.player.held then return end
  self.controls.itemPulse = true
  self.controls.itemPulseTTL = .22
  if race.network and not race.network.isHost then AK.RaceUI:Announce("ITEM SENT TO HOST", AK.COLORS.muted) end
end

--- WHICH STATES CAN BE PAUSED.
---
--- The countdown is on this list, and did not used to be. ESC during the three
--- seconds on the grid did nothing at all: the race frame grabs the keyboard,
--- so the client's own escape did not fire either, and the player sat in a
--- fullscreen window with no way out and no response to the one key the HUD
--- tells them to press. A dead key is worse than a wrong one -- it reads as a
--- frozen game.
local PAUSABLE = {
  [AK.RACE_STATES.COUNTDOWN] = true,
  [AK.RACE_STATES.RACING] = true,
  [AK.RACE_STATES.COOLDOWN] = true,
}

function Race:TogglePause()
  local race = self.current
  if not race or race.mode == "multiplayer" or race.mode == "attract" then return end
  if race.state == AK.RACE_STATES.PAUSED then
    -- Resume to whatever was running, not blindly to RACING: pausing during
    -- the cooldown lap and unpausing used to hand the player back a kart that
    -- had already finished, and the field never came home.
    race.state = race.resumeState or AK.RACE_STATES.RACING
    race.resumeState = nil
    -- NO ANNOUNCEMENT EITHER WAY.
    --
    -- Pausing used to shout "PAUSED" across the banner -- underneath a
    -- full-screen dim with the word PAUSED written on it in 28pt gold -- and
    -- resuming shouted "GO!", which is the countdown's word and nobody else's:
    -- coming back from the pause menu on lap three read as though the race had
    -- restarted, and coming back during the cooldown lap read as nonsense. The
    -- banner is for things that happen in the race. A menu is not one of them.
    if AK.PlaySfx then AK:PlaySfx("uiClose") end
  elseif PAUSABLE[race.state] then
    race.resumeState = race.state
    race.state = AK.RACE_STATES.PAUSED
    if AK.PlaySfx then AK:PlaySfx("uiOpen") end
  end
end

--- True when `other` is somewhere up the road from `vehicle`, within half a lap.
function Race:IsAhead(race, vehicle, other)
  local delta = AK.Math.SignedLoopDistance(vehicle.distance % race.track.length,
    other.distance % race.track.length, race.track.length)
  return delta > 0
end

--- Launch an item into the world. `direction` is 1 for something thrown up the
--- road and -1 for something dropped behind you.
function Race:SpawnProjectile(race, owner, itemID, direction)
  local item = AK.Items[itemID]
  if not item then return end
  local projectile = {
    id = itemID,
    item = item,
    owner = owner,
    -- Inherit the firer's road: a shell thrown on a branch stays on that
    -- branch and cannot strike someone over on the main line.
    route = owner and owner.route or nil,
    distance = owner.distance + direction * 5,
    lateral = owner.lateral,
    speed = direction > 0 and (owner.speed + (item.speed or 30)) or 0,
    life = item.life or 22,
    -- A dropped banana must not immediately hit the racer who dropped it.
    armAfter = direction > 0 and 0.10 or 0.85,
    age = 0,
  }
  if item.fake then
    -- Not a projectile: it becomes a stationary object that renders as a real
    -- item box until somebody drives into it.
    -- Dropped BEHIND, owned, and armed -- the same three things `armAfter` does
    -- for a dropped banana.
    --
    -- This used to land 5m back with none of them, straight into CheckObjects'
    -- 7m-plus hit window at a lateral offset copied verbatim from the dropper.
    -- The test could not miss: you spun out on your own Fake Item Box on the
    -- very frame you dropped it, every single time.
    table.insert(race.objects, {
      kind = "box", name = "Fake Item Box", fake = true,
      distance = (owner.distance - 11) % race.track.length,
      lateral = owner.lateral, hidden = false, respawn = 0, spawned = true,
      owner = owner, arm = 0.9,
    })
    return nil
  end
  if item.seeksLeader then
    -- The Spiny Shell ignores everyone in between and goes for the leader.
    projectile.target = self:GetLeader(owner)
    projectile.speed = item.speed
  elseif item.homing then
    projectile.target = self:GetAheadTarget(owner)
  elseif direction > 0 then
    -- Thrown straight items leave along the road's tangent, plus whatever angle
    -- the thrower's own slide gives them. This used to be a lateral DRIFT rate,
    -- which made a shell curve gently forever; it is an initial heading now, so
    -- a shell fired mid-drift leaves at an angle and then flies straight.
    projectile.heading = (owner.driftDirection or 0) * 0.045
  end
  table.insert(race.projectiles, projectile)
  return projectile
end

--- Move every live projectile, test it against the field, and resolve hits.
function Race:UpdateProjectiles(race, dt)
  local length = race.track.length
  -- Recomputed from scratch each tick by whichever shell is actually hunting
  -- you, so it cannot linger after the shell is gone or the lead changes hands.
  local hadSpiny = race.spinyEta ~= nil
  race.spinyEta = nil
  for index = #race.projectiles, 1, -1 do
    local projectile = race.projectiles[index]
    local item = projectile.item
    projectile.age = projectile.age + dt
    projectile.life = projectile.life - dt
    projectile.distance = projectile.distance + projectile.speed * dt

    if item.homing then
      -- Red shells re-acquire if their target finishes or is passed, and steer
      -- hard enough to actually connect rather than trailing behind.
      if not projectile.target or projectile.target.finished then
        projectile.target = item.seeksLeader and self:GetLeader(projectile.owner)
          or self:GetAheadTarget(projectile.owner)
      elseif item.seeksLeader then
        -- Re-aim every tick: if the lead changes hands mid-flight the shell
        -- follows the position, not the racer it originally locked.
        projectile.target = self:GetLeader(projectile.owner) or projectile.target
      end
      if projectile.target then
        local delta = projectile.target.lateral - projectile.lateral
        projectile.lateral = projectile.lateral + AK.Math.Clamp(delta, -2.6 * dt, 2.6 * dt)
        -- Close the gap: a homing shell should always be gaining.
        local gap = AK.Math.SignedLoopDistance(projectile.distance % length,
          projectile.target.distance % length, length)
        if gap > 0 then
          projectile.speed = math.max(projectile.speed, projectile.target.speed + 22)
        end
        -- TELEGRAPH. The spiny shell hunting YOU is the single most dramatic
        -- thing that happens in a kart race, and it was arriving in silence --
        -- which makes it a punishment for leading rather than a moment worth
        -- surviving. Publish the closing time so the HUD can build dread, and
        -- so the player knows when to spend a boost on the dodge.
        if item.seeksLeader and projectile.target == race.player then
          local closing = math.max(4, (projectile.speed or 0) - (projectile.target.speed or 0))
          race.spinyEta = math.max(0, gap) / closing
        end
      end
    else
      -- A GREEN SHELL IS A SHOT, NOT A TRAM.
      --
      -- A projectile's position is stored road-relative -- distance along the
      -- lap and lateral across it -- so a shell that simply holds its lateral
      -- follows every bend the road takes, all the way round the circuit. It
      -- never misses, and there is nothing to aim.
      --
      -- What it should do is fly straight through the world while the road
      -- curves away underneath it. That is the same forward integration the
      -- renderer uses to bend the road: carry a heading relative to the road's
      -- tangent, turn it by the road's own curvature as the shell advances, and
      -- let the lateral follow from it. Fired down a straight it goes dead
      -- straight; fired into a bend it runs wide and finds the outside wall,
      -- which is what makes lining one up worth doing.
      local route = self:RouteOf(race, projectile)
      local curve = AK.Math.RoadCurve(route, projectile.distance)
      local travelled = projectile.speed * dt
      projectile.heading = (projectile.heading or 0)
        - curve * AK.TrackBuilder.CURVE_GAIN * travelled
      -- Lateral is measured in road half-widths, so metres have to be scaled.
      projectile.lateral = projectile.lateral
        + projectile.heading * travelled / (AK.db.tuning.roadHalf or 9)
      -- The verge is where the road actually ENDS, which is not a constant:
      -- Durotar's cavern is 0.76 of a road-width and its start straight is
      -- 1.16, so a shell bouncing at a fixed 1.0 either ricocheted off thin air
      -- or flew through the rock.
      local wall = AK.Math.RoadWidth(route, projectile.distance)
      if projectile.lateral > wall or projectile.lateral < -wall then
        projectile.lateral = AK.Math.Clamp(projectile.lateral, -wall, wall)
        -- Reflect off the verge. A shell that keeps its heading through a wall
        -- would grind along it instead of ricocheting away.
        projectile.heading = -(projectile.heading or 0)
        projectile.bounces = (projectile.bounces or 0) + 1
        if projectile.bounces > 3 then projectile.life = 0 end
        -- Only for shells near the player: a ricochet on the far side of the
        -- track is not information, it is noise, and the LOW lane would spend
        -- its budget on it.
        local near = AK.Math.DistanceOnLoop(projectile.distance % length,
          (race.player and race.player.distance or 0) % length, length)
        if near < 60 and AK.PlaySfx then AK:PlaySfx("shellBounce") end
      end
    end

    local spent = projectile.life <= 0
    if not spent and projectile.age >= projectile.armAfter then
      for _, vehicle in ipairs(race.vehicles) do
        local skip = vehicle.finished or (vehicle == projectile.owner and projectile.age < 1.2)
        if not skip then
          local gap = self:RouteOf(race, vehicle) == self:RouteOf(race, projectile)
            and AK.Math.DistanceOnLoop(vehicle.distance % length, projectile.distance % length, length)
            or math.huge
          if gap < 4.0 and math.abs(vehicle.lateral - projectile.lateral) < .30 then
            -- One resolver decides the outcome of every overlap, in a
            -- documented order, instead of a chain of ad-hoc checks.
            local outcome = self:ResolveHit(vehicle, item)
            if outcome == "star" or outcome == "immune" then
              -- Shrugged off; the projectile is still consumed.
              spent = true
            elseif outcome == "boostDodge" then
              spent = true
              vehicle.immune = 0.8
              if vehicle == race.player then
                -- isPlayer, so the attract demo cannot earn it (see Physics).
                if vehicle.isPlayer then AK:UnlockAchievement("boost_dodge") end
                AK.RaceUI:Announce("BOOSTED CLEAR!", AK.COLORS.gold)
                AK.RaceUI:Flash(AK.COLORS.gold, .18)
                AK.RaceUI:Shake(10)
                if AK.PlaySfx then AK:PlaySfx("blocked") end
              end
            elseif outcome == "brake" then
              -- Rode it out. Rewarded, and briefly protected so the same trap
              -- cannot immediately catch you again.
              spent = true
              vehicle.immune = 0.6
              if vehicle == race.player then
                AK.RaceUI:Announce("DODGED!", AK.COLORS.lime)
                if AK.PlaySfx then AK:PlaySfx("blocked") end
              end
            elseif outcome == "shield" then
              -- A trailing item is a shield: it eats the hit and is destroyed.
              local blocked = AK.Items[vehicle.held]
              vehicle.held = nil
              spent = true
              if vehicle == race.player then
                AK.RaceUI:Announce("BLOCKED!", AK.COLORS.lime, blocked and blocked.icon)
                AK.RaceUI:Shake(9)
                AK.RaceUI:PlayEffect("shock", AK.RaceUI.playerX or 0,
                  (AK.RaceUI.playerY or 0) + (AK.RaceUI.playerWidth or 60) * 0.4,
                  (AK.RaceUI.playerWidth or 60) * 1.8, AK.COLORS.lime)
                if AK.PlaySfx then AK:PlaySfx("blocked") end
              end
            else
              local reaction = item.reaction or "spin"
              self:SlowVehicle(vehicle, item.blast and 1.4 or 1.15, item.name:upper() .. "!", reaction)
              -- Tell the THROWER what they just did.
              --
              -- SlowVehicle only ever speaks to the victim, so landing a shell
              -- on somebody produced no announcement, no sound and no shake for
              -- the player who threw it. The best moment in the genre was
              -- passing in complete silence, which is most of "we don't notice
              -- who or how you hit".
              if projectile.owner == race.player and vehicle ~= race.player then
                local who = vehicle.racer and (vehicle.racer.tag or vehicle.racer.name)
                AK.RaceUI:Announce("HIT " .. (who and who:upper() or "A RIVAL") .. "!",
                  AK.COLORS.lime, item.icon)
                -- Deliberately NOT FeelHit: landing one is a light gold pop with
                -- no dip and no directional shove. Being hit is heavy, red and
                -- pushes you; hitting someone is quick, bright and costs you
                -- nothing. If the two ever feel alike, neither reads.
                AK.RaceUI:HitConfirmed()
                if AK.PlaySfx then AK:PlaySfx("hitConfirm") end
              end
              -- In battle a clean hit costs a balloon, which is the entire mode.
              if race.battle then
                self:PopBalloon(race, vehicle, projectile.owner)
                self:CheckBattleEnd(race)
              end
              if item.blast then
                for _, other in ipairs(race.vehicles) do
                  if other ~= vehicle and not other.finished and (other.star or 0) <= 0
                    and self:RouteOf(race, other) == self:RouteOf(race, projectile)
                    and AK.Math.DistanceOnLoop(other.distance % length, projectile.distance % length, length) < item.blast then
                    self:SlowVehicle(other, 1.0, "CAUGHT IN THE BLAST", "launch")
                  end
                end
              end
              spent = true
            end
            AK.RaceUI:ProjectileHit(projectile, vehicle == race.player)
            break
          end
        end
      end
    end
    if spent then table.remove(race.projectiles, index) end
  end

  -- The warning itself. Fired once as the shell locks on rather than every
  -- tick, then escalated by the HUD as the clock runs down.
  if race.spinyEta and not hadSpiny then
    AK.RaceUI:Announce("SPINY SHELL INCOMING", AK.COLORS.danger)
    if AK.PlaySfx then AK:PlaySfx("spinyWarn") end
  end

  -- Items collide with each other: a shell cancels an oncoming shell, and
  -- anything moving detonates a dropped banana. Without this, projectiles slid
  -- through one another and a banana was unavoidable once laid.
  for a = #race.projectiles, 2, -1 do
    local first = race.projectiles[a]
    if first then
      for b = a - 1, 1, -1 do
        local second = race.projectiles[b]
        if second and first.owner ~= second.owner then
          local gap = self:RouteOf(race, first) == self:RouteOf(race, second)
            and AK.Math.DistanceOnLoop(first.distance % length, second.distance % length, length)
            or math.huge
          if gap < 3.2 and math.abs(first.lateral - second.lateral) < .28 then
            -- Only a moving item can destroy something; two parked bananas
            -- lying near each other should just sit there.
            if first.speed > 0 or second.speed > 0 then
              AK.RaceUI:ProjectileClash(first, second)
              table.remove(race.projectiles, a)
              table.remove(race.projectiles, b)
              break
            end
          end
        end
      end
    end
  end
end

function Race:VehicleDistance(first, second)
  local length = self.current.track.length
  local a = (first.progress or first.distance) % length
  local b = (second.progress or second.distance) % length
  return AK.Math.DistanceOnLoop(a, b, length)
end

function Race:GetAheadTarget(vehicle)
  local best, distance
  for _, other in ipairs(self.current.vehicles) do
    if other ~= vehicle and not other.finished then
      local delta = other.distance - vehicle.distance
      while delta <= 0 do delta = delta + self.current.track.length end
      if (not distance or delta < distance) then best, distance = other, delta end
    end
  end
  return best
end

function Race:GetLeader(except)
  local leader
  for _, vehicle in ipairs(self.current.vehicles) do
    if vehicle ~= except and not vehicle.finished and (not leader or vehicle.distance > leader.distance) then leader = vehicle end
  end
  return leader
end

--- Impede a racer: caps their speed for `duration`, scrubs a little off the
--- top, and flags a brief hit reaction for the visuals. Deliberately does not
--- take away control -- getting frozen in place is the least fun thing a kart
--- game can do to you, especially repeatedly.
-- Item collision priority. Resolved in this order, so the outcome of any
-- overlap is defined rather than depending on iteration order.
AK.HIT_PRIORITY = {
  { id = "star",     test = function(v) return (v.star or 0) > 0 end },
  { id = "immune",   test = function(v) return (v.immune or 0) > 0 end },
  -- The spiny shell's skill-based out. It hunts the leader by design and there
  -- is no avoiding it by driving well, which makes it a punishment for being in
  -- front rather than a moment. Being on a boost as it arrives carries you clear
  -- of the blast -- and because a boost is a resource you spend, dodging costs
  -- something. It sits ABOVE the shield so a good dodge keeps the shield too.
  { id = "boostDodge", test = function(v, item)
      return item and item.seeksLeader and (v.boostTime or 0) > 0 end },
  { id = "shield",   test = function(v) return v.held ~= nil end },
  { id = "brake",    test = function(v) return v.brakeGuard end },
  { id = "vulnerable", test = function() return true end },
}

--- What happens when `vehicle` is struck right now. `item` is optional; rules
--- that do not care about which item struck simply ignore it.
function Race:ResolveHit(vehicle, item)
  for _, rule in ipairs(AK.HIT_PRIORITY) do
    if rule.test(vehicle, item) then return rule.id end
  end
  return "vulnerable"
end

function Race:SlowVehicle(vehicle, duration, message, reaction)
  -- Post-hit immunity. Without a window, a single hazard re-triggers on every
  -- frame you are inside it and one banana becomes an infinite spin.
  if (vehicle.immune or 0) > 0 then return end
  vehicle.immune = 0.9
  -- Recovery is a class characteristic: a light racer is back up to speed
  -- quickly, a heavy one wears the hit. This is the counterweight to heavies
  -- holding more top speed and winning every collision.
  duration = duration / (vehicle.classRecovery or 1)
  vehicle.slow = math.max(vehicle.slow or 0, duration)
  vehicle.stun = math.max(vehicle.stun or 0, .22)
  vehicle.speed = vehicle.speed * .80
  -- Visible reactions. Getting hit should look like something happened to the
  -- kart, not like it quietly lost speed.
  if reaction == "launch" then
    vehicle.hop = 1.15
    vehicle.hopMax = 1.15
    vehicle.spin = 1.15
    vehicle.spinMax = 1.15
    vehicle.speed = vehicle.speed * .55
  elseif reaction == "squash" then
    vehicle.squash = 0.85
    vehicle.squashMax = 0.85
  else
    vehicle.spin = math.max(vehicle.spin or 0, duration * 0.85)
    vehicle.spinMax = vehicle.spin
  end
  if vehicle == self.current.player then
    vehicle.hazardHits = vehicle.hazardHits + 1
    AK.RaceUI:Announce(message, AK.COLORS.danger)
    AK.RaceUI:Flash(AK.COLORS.danger, .15)
    -- Shove the camera AWAY from the side that was struck, and dip it. Taking a
    -- hit and landing one must not feel the same: this is red, heavy and
    -- directional, where a hit confirmed on someone else is a light gold pop.
    -- Severity follows the reaction, so a launch is not a scrape.
    local side = (vehicle.lateral or 0) >= 0 and 1 or -1
    local severity = reaction == "launch" and 1.4 or (reaction == "squash" and 1.1 or 0.85)
    AK.RaceUI:FeelHit(side, severity)
    if AK.PlaySfx then AK:PlaySfx("collision") end
  end
end

function Race:UpdatePositions(race)
  local ordered = {}
  for _, vehicle in ipairs(race.vehicles) do table.insert(ordered, vehicle) end
  -- A BATTLE IS RANKED BACKWARDS FROM A RACE, and was being ranked forwards.
  --
  -- Being eliminated sets `finished` and stamps a `finishTime`, exactly as
  -- crossing a line does -- so the racing comparator read the FIRST kart
  -- knocked out as the first one home and put it 1st, and the last one
  -- standing, who has no finish time at all until the fight ends, last. The
  -- results screen showed the winner of every battle in eighth place.
  --
  -- Surviving beats being out, more balloons beats fewer, and among those
  -- already out, lasting longer beats going early.
  local battleOrder = race.battle and function(a, b)
    local aOut, bOut = a.eliminated and 1 or 0, b.eliminated and 1 or 0
    if aOut ~= bOut then return aOut < bOut end
    if aOut == 0 then
      local aB, bB = a.balloons or 0, b.balloons or 0
      if aB ~= bB then return aB > bB end
    else
      local aT, bT = a.finishTime or 0, b.finishTime or 0
      if aT ~= bT then return aT > bT end
    end
    return tostring(a.networkId) < tostring(b.networkId)
  end
  table.sort(ordered, battleOrder or function(a, b)
    local aDone, bDone = a.finished and 1 or 0, b.finished and 1 or 0
    if aDone ~= bDone then return aDone > bDone end
    if aDone == 1 then
      -- Both have crossed: whoever crossed FIRST is ahead. This used to fall
      -- through to distance, and since a racer's distance keeps climbing until
      -- the moment they finish, the LAST person over the line had the greatest
      -- distance and was promoted to 1st. That is the "4th, then 1st at the
      -- finish line" jump.
      return (a.finishTime or math.huge) < (b.finishTime or math.huge)
    end
    -- Rank on the odometer. Raw distance cannot be compared once racers are on
    -- branches of different physical length -- a kart 300m down a 400m branch
    -- is far further round the lap than one 300m into the 900m main line -- and
    -- it already counts laps, so no separate lap tier is needed.
    local aAt = a.lapProgress or a.distance
    local bAt = b.lapProgress or b.distance
    if aAt ~= bAt then return aAt > bAt end
    -- Comparator must be a strict weak ordering, so break ties deterministically.
    return tostring(a.networkId) < tostring(b.networkId)
  end)
  wipe(race.positions)
  for index, vehicle in ipairs(ordered) do race.positions[vehicle] = index end
  race.ordered = ordered

  -- Time gaps to the racers immediately ahead and behind, in SECONDS.
  --
  -- Seconds rather than metres because a gap only means anything relative to
  -- the pace being run, and because seconds are the unit the player actually
  -- experiences. Item weighting, slipstream and the photo finish all want this
  -- same number, so it is computed once here rather than three times badly.
  --
  -- MEASURED DOWN THE ROAD, NOT DOWN THE STANDINGS. In a race those are the
  -- same list and this costs nothing. In an arena they are not: the standings
  -- are who has balloons left, so "the vehicle above me in the table" is
  -- whoever is winning, not whoever is in front of my bumper -- and every
  -- consumer of these gaps, item weighting included, was being handed the
  -- distance between two karts that had nothing to do with each other.
  local byRoad = ordered
  if race.battle then
    byRoad = {}
    for index, vehicle in ipairs(ordered) do byRoad[index] = vehicle end
    table.sort(byRoad, function(a, b)
      local aAt = a.lapProgress or a.distance
      local bAt = b.lapProgress or b.distance
      if aAt ~= bAt then return aAt > bAt end
      return tostring(a.networkId) < tostring(b.networkId)
    end)
  end
  for index, vehicle in ipairs(byRoad) do
    local pace = math.max(8, vehicle.speed or 0)
    local at = vehicle.lapProgress or vehicle.distance
    local ahead, behind = byRoad[index - 1], byRoad[index + 1]
    vehicle.gapAhead = ahead
      and math.abs((ahead.lapProgress or ahead.distance) - at) / pace or nil
    vehicle.gapBehind = behind
      and math.abs(at - (behind.lapProgress or behind.distance)) / pace or nil
  end
end

-- Falling off the course, and the recovery that follows.
--
-- A VOID surface is not "slow terrain you should avoid" -- it is off the world.
-- Control is taken away, the kart is lifted, carried back to the last valid
-- point on the road and dropped. The recovery is deliberately slow enough that
-- a failed shortcut is genuinely worse than driving the long way round, which
-- is what gives risky lines their risk.
-- Published on Race so the renderer can veil exactly this timeline rather than
-- keeping a second copy of it. Shortened from 0.55/0.85/0.45: 1.85 seconds of
-- being put back was a long time to spend watching a stationary kart, and most
-- of it used to be spent watching nothing at all happen.
local FALL_TIME, LIFT_TIME, DROP_TIME = 0.42, 0.34, 0.52
Race.FALL_TIME, Race.LIFT_TIME, Race.DROP_TIME = FALL_TIME, LIFT_TIME, DROP_TIME

--- The last valid road position at or before `distance`.
--- How far back a recovery puts you. Short on purpose.
local RECOVERY_BACK = 18

function Race:RespawnPointFor(track, distance)
  -- BACK TO WHERE YOU LEFT, not to the last checkpoint.
  --
  -- Recovery points are built one per authored layout piece, and pieces run
  -- from 55 to 210 metres -- so going off at the end of a long one sent you
  -- back the whole length of it. Measured on Durotar, a single recovery moved
  -- the kart SIXTY-SIX METRES up the track. That is a second and a half of
  -- driving handed back on top of the second and a half spent being picked up,
  -- for a mistake that in every kart game ever made costs you the pick-up and
  -- nothing else.
  --
  -- The road is solid wherever you were -- a fall is leaving it SIDEWAYS -- so
  -- a short step back is safe by construction.
  local near = distance - RECOVERY_BACK
  if not AK.TrackBuilder:RampAt(track, near) then
    return { distance = near, lateral = 0 }
  end
  -- Unless that lands mid-launch, which is exactly what the authored points
  -- exist to avoid: they are placed at the start of every piece that is not a
  -- ramp, so the nearest one behind you is always before the ramp.
  if track.respawns then
    local best, bestGap = nil, math.huge
    for _, point in ipairs(track.respawns) do
      local gap = (distance - point.distance) % track.length
      if gap < bestGap then best, bestGap = point, gap end
    end
    if best then return best end
  end
  return { distance = near, lateral = 0 }
end

function Race:UpdateFalls(race, dt)
  for _, vehicle in ipairs(race.vehicles) do
    if vehicle.falling and vehicle.falling > 0 and not vehicle.finished then
      vehicle.falling = vehicle.falling + dt
      local total = FALL_TIME + LIFT_TIME + DROP_TIME

      if vehicle.falling >= FALL_TIME and not vehicle.lifted then
        -- Picked up: park the kart at its recovery point immediately so the
        -- race ordering settles, but keep control suppressed.
        vehicle.lifted = true
        local point = self:RespawnPointFor(vehicle.route or race.track, vehicle.distance)
        vehicle.distance = point.distance
        vehicle.lateral = point.lateral or 0
        vehicle.speed = 0
        vehicle.drifting, vehicle.driftCharge = false, 0
        vehicle.held = nil
      end

      if vehicle.falling >= total then
        vehicle.falling, vehicle.lifted = nil, nil
        vehicle.recovering = 0.6
        if vehicle == race.player then
          AK.RaceUI:Announce("BACK ON TRACK", AK.COLORS.muted)
          AK.RaceUI:Shake(8)
        end
      elseif vehicle == race.player and not vehicle.announcedFall then
        vehicle.announcedFall = true
        AK.RaceUI:Announce("OFF THE COURSE!", AK.COLORS.danger)
        AK.RaceUI:Flash(AK.COLORS.danger, .3)
        if AK.PlaySfx then AK:PlaySfx("defeat") end
      end
    elseif vehicle.announcedFall and not vehicle.falling then
      vehicle.announcedFall = nil
    end
  end
end

--- Checkpoint and lap validation.
---
--- Lap counting used to be `distance >= length * laps`, which trusts a number
--- the player can manipulate. Progress is now only credited when checkpoints
--- are taken in order, so reversing over the line or cutting most of the course
--- cannot bank a lap. It also gives us a "wrong way" signal for free.
function Race:UpdateCheckpoints(race, dt)
  local track = race.track
  if not track.checkpointCount then return end
  for _, vehicle in ipairs(race.vehicles) do
    if not vehicle.finished and not vehicle.falling then
      local at = AK.TrackBuilder:CheckpointAt(track, vehicle.progress or vehicle.distance)
      vehicle.checkpoint = vehicle.checkpoint or 1
      vehicle.cleared = vehicle.cleared or 1

      local expected = (vehicle.checkpoint % track.checkpointCount) + 1
      if at == expected then
        vehicle.checkpoint = at
        vehicle.cleared = vehicle.cleared + 1
        vehicle.wrongWay = 0
        -- A full ring of checkpoints is a real lap.
        if vehicle.cleared > track.checkpointCount then
          vehicle.cleared = 1
          vehicle.validLaps = (vehicle.validLaps or 0) + 1
        end
      elseif at ~= vehicle.checkpoint then
        -- Went somewhere out of sequence. Only complain if it is behind us.
        local behind = ((vehicle.checkpoint - at) % track.checkpointCount)
        if behind > 0 and behind < track.checkpointCount * 0.5 then
          vehicle.wrongWay = (vehicle.wrongWay or 0) + dt
          if vehicle == race.player and vehicle.wrongWay > 0.8
            and not vehicle.warnedWrongWay then
            vehicle.warnedWrongWay = true
            AK.RaceUI:Announce("WRONG WAY", AK.COLORS.danger)
          end
        end
      end
      if (vehicle.wrongWay or 0) <= 0 then vehicle.warnedWrongWay = nil end
      vehicle.wrongWay = math.max(0, (vehicle.wrongWay or 0) - dt * 0.5)
    end
  end
end

--- Slipstream. Sitting in the dirty air behind another kart builds a tow that
--- pays out as extra top speed, so following is an active choice rather than a
--- consolation prize. It is the single best comeback mechanic that does not
--- involve an item, and it makes packs race instead of string out.
function Race:UpdateSlipstream(race, dt)
  local length = race.track.length
  for _, vehicle in ipairs(race.vehicles) do
    if not vehicle.finished then
      local towing = false
      for _, other in ipairs(race.vehicles) do
        if other ~= vehicle and not other.finished then
          local gap = AK.Math.SignedLoopDistance((vehicle.progress or vehicle.distance) % length,
            (other.progress or other.distance) % length, length)
          -- Directly behind, close, and roughly in line. Slipstream works across
          -- routes because it compares shared progress, not route-local metres.
          if gap > 2 and gap < 17 and math.abs(other.lateral - vehicle.lateral) < .34 then
            towing = true
            break
          end
        end
      end
      local wasTowing = vehicle.towing
      vehicle.towing = towing
      vehicle.slipstream = AK.Math.Clamp((vehicle.slipstream or 0) + (towing and dt or -dt * 1.8), 0, 1.6)

      -- THE SLINGSHOT. Sitting in the tow was a slow passive trickle of top
      -- speed with a banner on it -- a mechanic with no moment, so nobody ever
      -- felt it. Breaking a FULL tow now pays out a real boost, which turns
      -- following into a two-part decision: commit to the dirty air long enough
      -- to charge, then choose when to pull out and spend it. That is the whole
      -- difference between a passive bonus and something you do on purpose.
      if wasTowing and not towing and (vehicle.slipstream or 0) > 1.10 then
        vehicle.boostTime = math.max(vehicle.boostTime or 0, 0.55)
        vehicle.speed = math.max(vehicle.speed, vehicle.maxSpeed * 1.06)
        vehicle.slipstream = 0
        if vehicle == race.player then
          AK.RaceUI:Announce("SLINGSHOT!", AK.COLORS.gold)
          AK.RaceUI:Feel("push", 2.4)
          AK.RaceUI:Shake(8)
          -- isPlayer, so the attract demo cannot earn it (see Physics).
          if vehicle.isPlayer then AK:UnlockAchievement("slingshot") end
          if AK.PlaySfx then AK:PlaySfx("boost") end
        end
      end

      if vehicle == race.player then
        if towing and not race.wasTowing and vehicle.slipstream > .35 then
          AK.RaceUI:Announce("SLIPSTREAM", AK.COLORS.lime)
        end
        -- The build-up needs a top end you can hear arriving, or "pull out now"
        -- is information the player never receives.
        local ready = (vehicle.slipstream or 0) > 1.10
        if ready and not race.towReady then
          AK.RaceUI:Announce("TOW READY - PULL OUT", AK.COLORS.gold)
          if AK.PlaySfx then AK:PlaySfx("driftTier2") end
        end
        race.towReady = ready
        race.wasTowing = towing
      end
    end
  end
end

--- Running per-vehicle telemetry: top speed, time spent drifting, lap splits.
function Race:UpdateTelemetry(race, dt)
  for _, vehicle in ipairs(race.vehicles) do
    if not vehicle.finished then
      if vehicle.speed > vehicle.topSpeed then vehicle.topSpeed = vehicle.speed end
      if vehicle.drifting then vehicle.driftTime = vehicle.driftTime + dt end
      local completed = #vehicle.lapTimes + 1
      if vehicle.lap > completed and completed <= race.laps then
        local split = race.elapsed - vehicle.lapStart
        vehicle.lapTimes[completed] = split
        vehicle.lapStart = race.elapsed
        -- Your split against your best, before bestLap is updated below --
        -- comparing after would always read as dead level on an improvement.
        if vehicle == race.player then
          AK.RaceUI:ShowLapSplit(completed, split, vehicle.bestLap)
        end
        if not vehicle.bestLap or split < vehicle.bestLap then
          vehicle.bestLap = split
          if vehicle == race.player and completed > 1 then
            AK.RaceUI:Announce("BEST LAP  " .. AK.RaceUI:FormatTime(split), AK.COLORS.lime)
          end
        end
      end
    end
  end
end

function Race:ReportRaceMoments(race)
  local player = race.player
  local position = race.positions[player] or #race.vehicles

  -- Wrong way: the checkpoint you are in going BACKWARDS, held long enough to
  -- be a direction rather than a wobble across a boundary.
  --
  -- Note this cannot currently fire. Physics clamps speed to >= 0 and distance
  -- only ever accumulates, so a racer has no way to travel backwards down the
  -- course. The detector and the banner are wired and testable via /kart beats,
  -- ready for the day reversing exists; until then it is deliberately inert
  -- rather than quietly absent.
  local checkpoint = AK.TrackBuilder:CheckpointAt(player.route or race.track, player.distance)
  if race.lastCheckpointSeen and checkpoint < race.lastCheckpointSeen
    and (race.lastCheckpointSeen - checkpoint) < (race.track.checkpointCount or 8) * 0.5 then
    race.wrongWayTime = (race.wrongWayTime or 0) + (race.delta or 0)
  else
    race.wrongWayTime = 0
  end
  race.lastCheckpointSeen = checkpoint
  AK.RaceUI:ShowWrongWay((race.wrongWayTime or 0) > 2)
  if player.lap > race.lastLap and player.lap <= race.laps then
    race.lastLap = player.lap
    if player.lap == race.laps then
      AK.RaceUI:Announce("FINAL LAP!", AK.COLORS.gold)
      AK.RaceUI:Flash(AK.COLORS.gold, .18)
    else
      AK.RaceUI:Announce("LAP " .. player.lap .. " - KEEP PUSHING!", AK.COLORS.lime)
    end
    if AK.PlaySfx then AK:PlaySfx(player.lap == race.laps and "finalLap" or "lap") end
  end
  if race.lastPosition and position ~= race.lastPosition and race.elapsed > 2 then
    if position == 1 then
      AK.RaceUI:Announce("YOU TAKE THE LEAD!", AK.COLORS.gold)
      AK.RaceUI:Flash(AK.COLORS.gold, .12)
      if AK.PlaySfx then AK:PlaySfx("overtake") end
      -- "That's Mine!" is earned on the pass itself, not merely by winning: it
      -- has to be the final lap when the lead changes hands. Defined in
      -- Data/Achievements.lua since the addon shipped, this was the only one of
      -- the five with no code path that ever called UnlockAchievement for it.
      if player.lap == race.laps then AK:UnlockAchievement("late_pass") end
    elseif position < race.lastPosition then
      AK.RaceUI:Announce("POSITION " .. position, AK.COLORS.lime)
      if AK.PlaySfx then AK:PlaySfx("overtake") end
    elseif position > race.lastPosition then
      AK.RaceUI:Announce("POSITION " .. position, AK.COLORS.muted)
      if AK.PlaySfx then AK:PlaySfx("passed") end
    end
  end
  race.lastPosition = position
end

function Race:CheckObjects(race, dt)
  for _, object in ipairs(race.objects) do
    if object.hidden and object.respawn then
      object.respawn = object.respawn - dt
      if object.respawn <= 0 then object.hidden, object.respawn = false, 0 end
    elseif not object.hidden then
      -- Arming window for anything a racer just dropped. Counts down once per
      -- frame, and only ever protects the racer who dropped it -- everyone else
      -- can hit it immediately, which is the point of leaving it there.
      if object.arm and object.arm > 0 then
        object.arm = object.arm - dt
        if object.arm <= 0 then object.arm, object.owner = nil, nil end
      end
      for _, vehicle in ipairs(race.vehicles) do
        if object.owner == vehicle and (object.arm or 0) > 0 then
          -- Still the dropper's own, still arming: no collision this frame.
        elseif not vehicle.finished and self:RouteOf(race, vehicle) == self:RouteOf(race, object) then
          local route = self:RouteOf(race, vehicle)
          local distance = AK.Math.DistanceOnLoop(vehicle.distance % route.length, object.distance, route.length)
          if distance < 7 + vehicle.speed * dt * .6 and math.abs(vehicle.lateral - object.lateral) < .33 then
            if object.kind == "boost" then
              -- Dash panels never expire; they are terrain, not a pickup.
              if (vehicle.padCooldown or 0) <= 0 then
                vehicle.padCooldown = 0.6
                vehicle.boostTime = math.max(vehicle.boostTime or 0, 1.5)
                vehicle.speed = math.max(vehicle.speed, vehicle.maxSpeed * 1.22)
                if vehicle == race.player then
                  AK.RaceUI:Announce("DASH PANEL!", AK.COLORS.gold)
                  AK.RaceUI:Shake(8)
                  AK.RaceUI:LaunchEffect({ 1, .72, .18 }, false)
                  if AK.PlaySfx then AK:PlaySfx("dash") end
                end
              end
            elseif object.kind == "box" and object.fake then
              -- The payoff for the disguise.
              self:SlowVehicle(vehicle, 1.3, "FAKE ITEM BOX!", "spin")
              object.hidden, object.respawn = true, 6
              if vehicle == race.player then
                AK.RaceUI:Flash({ .75, .3, .95 }, .22)
                AK.RaceUI:Shake(16)
              end
              break
            elseif object.kind == "box" then
              if not vehicle.item then
                local pos = race.positions[vehicle] or 1
                vehicle.item = AK:RollItem(pos, #race.vehicles, vehicle.racer.luck,
                  race.rngItems, vehicle.gapAhead, vehicle.gapBehind)
                vehicle.itemCount = AK.Items[vehicle.item] and AK.Items[vehicle.item].quantity or 1
                object.hidden, object.respawn = true, 7
                if vehicle == race.player then AK.RaceUI:Announce(AK.Items[vehicle.item].name .. " acquired!", AK.COLORS.lime) end
                break
              end
            elseif object.kind == "hazard" then
              self:SlowVehicle(vehicle, object.spawned and .8 or 1.15, object.name)
              object.hidden, object.respawn = true, object.spawned and 9 or 5
              break
            elseif object.kind == "shortcut" then
              vehicle.shortcuts = vehicle.shortcuts or {}
              if not vehicle.shortcuts[vehicle.lap] and math.abs(vehicle.lateral) > .78 then
                vehicle.shortcuts[vehicle.lap] = true
                vehicle.distance = vehicle.distance + 36
                vehicle.speed = math.min(vehicle.maxSpeed * 1.18, vehicle.speed + 18)
                if vehicle == race.player then AK.RaceUI:Announce("SHORTCUT!", AK.COLORS.lime) end
              end
            end
          end
        end
      end
    end
  end
end

function Race:CheckCollisions(race)
  for i = 1, #race.vehicles - 1 do
    for j = i + 1, #race.vehicles do
      local first, second = race.vehicles[i], race.vehicles[j]
      -- Running over a shrunk racer. A full-size kart flattens them and drives
      -- straight on; the tiny one loses everything for a moment.
      local firstSmall, secondSmall = (first.shrunk or 0) > 0, (second.shrunk or 0) > 0
      if not first.finished and not second.finished and firstSmall ~= secondSmall
        and self:VehicleDistance(first, second) < 7 and math.abs(first.lateral - second.lateral) < .30 then
        local squashed = firstSmall and first or second
        if (squashed.flattened or 0) <= 0 then
          squashed.flattened = 1.4
          self:SlowVehicle(squashed, 1.8, "FLATTENED!", "squash")
          squashed.speed = squashed.speed * .25
          if squashed == race.player then
            AK.RaceUI:Shake(22)
            AK.RaceUI:Flash(AK.COLORS.danger, .26)
          elseif AK.RaceUI.playerX then
            AK.RaceUI:Shake(6)
          end
          -- Two rivals flattening each other on the far side of the circuit
          -- sounded exactly like being flattened yourself.
          if AK.PlaySfxNear then AK:PlaySfxNear("bump", race, squashed) end
        end
      elseif not first.finished and not second.finished and self:VehicleDistance(first, second) < 7 and math.abs(first.lateral - second.lateral) < .20 then
        -- Weight decides who gets moved. A fixed shove made a heavy kart and a
        -- gnome bounce off each other identically, which made the weight stat
        -- meaningless in the one place it should matter most.
        -- Collision mass is its own class characteristic.
        local m1, m2 = first.mass or 1, second.mass or 1
        local total = m1 + m2
        local firstShare = m2 / total
        local secondShare = m1 / total
        local direction = first.lateral <= second.lateral and -1 or 1
        -- Overlap depth drives the impulse, so a glancing touch nudges and a
        -- committed barge shoves.
        local overlap = math.max(0.04, .22 - math.abs(first.lateral - second.lateral))
        local impulse = overlap * 0.9
        first.lateral = first.lateral + direction * impulse * firstShare * 2
        second.lateral = second.lateral - direction * impulse * secondShare * 2
        -- The lighter kart also loses more speed in the exchange.
        first.speed = first.speed * (1 - 0.10 * firstShare)
        second.speed = second.speed * (1 - 0.10 * secondShare)
        -- Trading paint was completely silent and invisible.
        if first == race.player or second == race.player then
          local other = (first == race.player) and second or first
          if (race.player.bumpCooldown or 0) <= 0 then
            race.player.bumpCooldown = 0.35
            AK.RaceUI:Shake(6)
            AK.RaceUI:PlayEffect("pop", AK.RaceUI.playerX or 0,
              (AK.RaceUI.playerY or 0) + (AK.RaceUI.playerWidth or 60) * 0.4,
              (AK.RaceUI.playerWidth or 60) * 1.1, other.kart.color)
            if AK.PlaySfx then AK:PlaySfx("bump") end
          end
        end
      end
    end
  end
end

--- Carry a kart somebody else owns forward between snapshots.
---
--- A client simulates nothing but its own racer: every other kart moved ONLY
--- when a packet landed, so at a snapshot every 0.10s the entire field advanced
--- in ten visible steps a second while the player's own kart ran smooth. The
--- host stays authoritative -- this only fills the gap between its packets with
--- the last speed it reported, and the next snapshot corrects whatever drifted.
---
--- Marked `remote` so Physics:UpdateRoute does not try to make route decisions
--- on this kart's behalf: which road it is on is the host's call, and it comes
--- down in the snapshot.
function Race:DeadReckon(race, vehicle, dt)
  vehicle.remote = true
  vehicle.distance = vehicle.distance + (vehicle.speed or 0) * dt
  -- Recompute progress, lap and odometer from the new distance, so standings
  -- and the minimap keep moving between packets instead of stepping too.
  AK.Physics:UpdateRoute(race, vehicle)
  -- Reaction timers have to run down locally or a spin-out freezes mid-spin
  -- until the next packet happens to arrive.
  vehicle.spin = math.max(0, (vehicle.spin or 0) - dt)
  vehicle.air = math.max(0, (vehicle.air or 0) - dt)
  vehicle.boostTime = math.max(0, (vehicle.boostTime or 0) - dt)
  vehicle.shrunk = math.max(0, (vehicle.shrunk or 0) - dt)
end

function Race:UpdateRacing(race, dt)
  race.elapsed = race.elapsed + dt
  local hostOrSolo = not race.network or race.network.isHost
  for _, vehicle in ipairs(race.vehicles) do
    if not vehicle.finished then
      if race.mode == "attract" then
        -- Title-screen demo: nobody is driving, so every kart is on the AI.
        AK.Physics:UpdateVehicle(race, vehicle, AK.AI:Controls(race, vehicle, dt), dt)
      elseif vehicle == race.player then
        if race.network and not race.network.isHost then
          -- The host consumes multiplayer items. Clients predict steering only so a
          -- delayed snapshot cannot accidentally activate the same item twice.
          -- Carries the throttle too, or a predicted local racer accelerates
          -- flat out while the real one is coasting.
          local predicted = { left = self.controls.left, right = self.controls.right,
            drift = self.controls.drift, brake = self.controls.brake,
            accelerate = self.controls.accelerate, throttleAware = true }
          AK.Physics:UpdateVehicle(race, vehicle, predicted, dt)
        else
          AK.Physics:UpdateVehicle(race, vehicle, self.controls, dt)
        end
      elseif vehicle.owner then
        if hostOrSolo then
          AK.Physics:UpdateVehicle(race, vehicle, race.remoteInputs[vehicle.owner] or {}, dt)
        else
          self:DeadReckon(race, vehicle, dt)
        end
      elseif hostOrSolo then
        AK.Physics:UpdateVehicle(race, vehicle, AK.AI:Controls(race, vehicle, dt), dt)
      else
        self:DeadReckon(race, vehicle, dt)
      end
      -- Distance alone is not enough: the lap only counts if the checkpoint
      -- ring was completed in order.
      local lapsValid = (vehicle.validLaps or 0) >= race.laps
        or not race.track.checkpointCount
      if hostOrSolo and not race.battle and lapsValid and (vehicle.lapsDone or 0) >= race.laps then
        if race.mode == "attract" then
          -- The title-screen demo never ends; it just keeps lapping.
          -- lapsDone is derived from the odometer, so the odometer is what has
          -- to be wound back or the demo would finish again immediately.
          vehicle.odometer = 0
          vehicle.lapsDone = 0
          vehicle.validLaps = 0
          vehicle.lap = 1
          vehicle.lapTimes = {}
        else
          vehicle.finished = true
          vehicle.finishTime = race.elapsed
          -- The order they actually crossed in, recorded as it happens. The
          -- standings are recomputed every tick from distance and can only
          -- infer a finishing order after the fact; this is the real thing,
          -- and it is what the ladder fills in from as the field comes home.
          race.finishOrder = race.finishOrder or {}
          table.insert(race.finishOrder, vehicle)
          vehicle.finishPlace = #race.finishOrder
        end
      end
    else
      -- CROSSING THE LINE DOES NOT PARK THE KART.
      --
      -- A finished racer used to be skipped by this loop entirely, which meant
      -- it stopped dead on the spot the instant it crossed -- a row of statues
      -- on the start-finish straight while everyone else was still racing. In
      -- every kart game ever made the winner keeps rolling, hands off the
      -- wheel, and coasts away up the road. So do that: hand the kart to the
      -- AI and let it drive on. It cannot be hit, it cannot hit anyone and it
      -- cannot score another lap (all of that is already gated on `finished`),
      -- so this is pure scenery -- but it is the difference between a race
      -- ending and a race freezing.
      self:CoastHome(race, vehicle, dt)
    end
  end
  -- Stop recording the ghost the moment the player is home. Past the flag the
  -- kart is on autopilot, and a Time Trial ghost that includes a driverless
  -- cooldown lap is not a ghost of anything.
  if race.recorder and not race.player.finished then
    AK.Ghost:Record(race.recorder, race.player, dt)
  end
  if race.ghost then race.ghostState = AK.Ghost:Advance(race.ghost, dt) end
  if hostOrSolo then self:UpdateHazards(race, dt) end
  self:UpdateCheckpoints(race, dt)
  self:UpdateFalls(race, dt)
  if race.mode ~= "attract" and AK.UpdateEngine and not race.player.finished then
    AK:UpdateEngine(race.player, dt)
  end
  self:UpdateTelemetry(race, dt)
  if hostOrSolo then
    self:UpdateSlipstream(race, dt)
    self:UpdateProjectiles(race, dt)
  end
  if hostOrSolo then
    self:CheckCollisions(race)
    self:UpdatePositions(race)
    self:CheckObjects(race, dt)
    -- Race commentary is for a driver. Past the flag there is no driver.
    if race.mode ~= "attract" and not race.player.finished then
      self:ReportRaceMoments(race)
    end
    if race.player.finished then self:AfterPlayerFinish(race) end
  else
    self:UpdatePositions(race)
    self:ReportRaceMoments(race)
  end
  if race.network then
    AK.Net:SendInput(race)
    AK.Net:BroadcastSnapshot(race)
  end
  if self.controls.itemPulseTTL then
    self.controls.itemPulseTTL = self.controls.itemPulseTTL - dt
    if self.controls.itemPulseTTL <= 0 then
      self.controls.itemPulse, self.controls.itemPulseTTL = false, nil
    end
  else
    self.controls.itemPulse = false
  end
  -- Hop is an edge, not a held state: clear it once the frame has consumed it.
  self.controls.hopPressed = false
end

--- Hands a kart that has already crossed the line to the AI so it rolls on.
--- Items are stripped: nobody wants a shell from someone who has finished.
function Race:CoastHome(race, vehicle, dt)
  if race.mode == "attract" then return end
  -- A kart that has finished must never be left hanging in the void. The
  -- recovery pass deliberately skips finished racers -- so that crossing the
  -- line mid-fall is not answered by being yanked back onto the track -- which
  -- means nothing at all would put this one back. It is scenery now, so set it
  -- down on the centreline and let it drive on.
  if vehicle.falling then
    vehicle.falling, vehicle.lifted = nil, nil
    vehicle.lateral = 0
  end
  -- The player has no AI brain, and must not be GIVEN one. `vehicle.ai` is
  -- exactly what AI:Report uses to tell a rival from a human: parking a
  -- personality on the player for the cooldown lap would file them as a ninth
  -- AI, list the autopilot's drifts and mistakes as theirs, and delete their
  -- own comparison row from the telemetry. So the brain is BORROWED for the
  -- length of the call and handed straight back.
  local borrowed = not vehicle.ai
  if borrowed then
    vehicle.coastBrain = vehicle.coastBrain or AK.AI:CreatePersonality(9)
    vehicle.ai = vehicle.coastBrain
  end
  local controls = AK.AI:Controls(race, vehicle, dt)
  if borrowed then vehicle.ai = nil end
  controls.itemPulse = false
  AK.Physics:UpdateVehicle(race, vehicle, controls, dt)
end

--- True once every racer has a finish time.
function Race:FieldIsHome(race)
  for _, vehicle in ipairs(race.vehicles) do
    if not vehicle.finished then return false end
  end
  return true
end

--- The player has crossed the line. The RACE has not ended.
---
--- This is the whole reason DNF existed. The old code ended the race on the
--- player's flag and went straight to the results table, so anyone still on
--- circuit -- which, if you win, is everybody -- never got a finish time and
--- was printed as "DNF". Nobody has ever finished a kart race and been told
--- the other seven retired.
---
--- So the flag starts a COOLDOWN instead: the player's kart goes on autopilot,
--- the camera stays where it is, and the field comes home while a ladder fills
--- in at the side of the screen. Only when the last kart is in does the race
--- actually end.
function Race:BeginCooldown(race)
  if race.state ~= AK.RACE_STATES.RACING then return end
  if race.battle or race.mode == "attract" then return self:FinishRace(race) end
  race.state = AK.RACE_STATES.COOLDOWN
  race.cooldown = { wall = 0, rate = 1 }
  self:UpdatePositions(race)
  AK.RaceUI:BeginCooldown(race, race.player.finishPlace or race.positions[race.player] or #race.vehicles)
  if AK.PlaySfx then AK:PlaySfx("lap") end
end

--- Called every tick once the player is home, from inside UpdateRacing.
function Race:AfterPlayerFinish(race)
  -- NOT IN AN ARENA. The cooldown is the machinery for "the player crossed the
  -- line, now bring the rest of the field home" -- it dims the world, winds the
  -- clock forward several times over and slides in a panel headed FINISHING
  -- ORDER. Being knocked out of a battle set the same `finished` flag, so all
  -- of that fired in the middle of a fight that was still going on, and the
  -- last two karts settled it under a fast-forward behind a scrim. A battle is
  -- short and worth watching: the player's kart coasts, the HUD says OUT, and
  -- CheckBattleEnd ends it when the last balloon goes.
  if race.battle then return end
  if race.state == AK.RACE_STATES.RACING then
    self:BeginCooldown(race)
  elseif race.state == AK.RACE_STATES.COOLDOWN and self:FieldIsHome(race) then
    self:FinishRace(race)
  end
end

--- Everyone still out there gets a time, even if the cooldown ran out of
--- patience. Extrapolated from where they are and how fast they are going, so
--- the classification is complete and the gaps are still honest.
function Race:ProjectRemainingFinishes(race)
  local lapLength = race.track.length or 1000
  for _, vehicle in ipairs(race.vehicles) do
    if not vehicle.finished then
      local togo = math.max(0, race.laps * lapLength - (vehicle.odometer or 0))
      -- Never divide by a stopped kart.
      local pace = math.max(12, vehicle.speed or 0)
      vehicle.finished = true
      vehicle.finishTime = race.elapsed + togo / pace
      vehicle.projected = true
      race.finishOrder = race.finishOrder or {}
      table.insert(race.finishOrder, vehicle)
      vehicle.finishPlace = #race.finishOrder
    end
  end
end

--- The cooldown lap. Real time at first, so a rival crossing two tenths behind
--- you plays out at the speed it happened; then it winds on, because watching
--- a straggler tour half a circuit is not entertainment.
function Race:UpdateCooldown(race, dt)
  local cool = race.cooldown
  cool.wall = cool.wall + dt
  -- Honest for the first beat and a half, then accelerating hard. race.elapsed
  -- advances with the simulation, so finishing times stay true -- this is a
  -- fast-forward, not a shortcut.
  cool.rate = AK.Math.Clamp(1 + math.max(0, cool.wall - 1.5) * 4, 1, 12)
  local slices = math.max(1, math.floor(cool.rate + 0.5))
  for _ = 1, slices do
    if race.state ~= AK.RACE_STATES.COOLDOWN then return end
    self:UpdateRacing(race, dt)
  end
  if race.state ~= AK.RACE_STATES.COOLDOWN then return end
  -- Hard stop. Twelve seconds of real time is already generous, and something
  -- pathological -- a kart wedged against scenery on a track with no reset --
  -- must never be able to hold the results screen hostage.
  if cool.wall > 12 then
    self:ProjectRemainingFinishes(race)
    self:UpdatePositions(race)
    self:FinishRace(race)
  end
end

function Race:FinishRace(race)
  if race.state == AK.RACE_STATES.FINISHED then return end
  race.state = AK.RACE_STATES.FINISHED
  self:UpdatePositions(race)
  local position = race.positions[race.player] or #race.vehicles

  -- PHOTO FINISH. A race decided by a third of a second is the best thing that
  -- can happen in a kart game, and it was being reported as a row in a table
  -- one place above or below another. Detect it while the finish times are
  -- still to hand and hand it to the presentation layer as a moment.
  local ahead = race.ordered and race.ordered[position - 1]
  local behind = race.ordered and race.ordered[position + 1]
  -- NOT ipairs. `ipairs` stops at the first nil, and when the player WINS there
  -- is nobody ahead -- so `{ nil, behind }` iterated zero times and a photo
  -- finish was never detected for the one case this whole block exists for.
  -- Winning by two tenths is the best thing that can happen in a kart game, and
  -- the achievement below is explicitly "only for taking it".
  for _, rival in pairs({ ahead, behind }) do
    local mine, theirs = race.player.finishTime, rival and rival.finishTime
    if mine and theirs and math.abs(mine - theirs) <= 0.30 then
      race.photoFinish = {
        margin = math.abs(mine - theirs),
        rival = rival.racer and (rival.racer.tag or rival.racer.name) or "a rival",
        won = mine < theirs,
      }
      -- Only for taking it, not for losing it by the same margin.
      if race.photoFinish.won then AK:UnlockAchievement("photo_finish") end
      break
    end
  end

  if race.grandPrix then
    -- KEYED BY OWNER, DISPLAYED BY NAME. "player" is the sentinel this file
    -- gives the local kart in AddVehicle -- it is not anybody's name -- so the
    -- cup table keyed the player as the literal string "player", and the
    -- trophy screen then printed that as the champion. The key has to stay the
    -- owner so a multiplayer grid cannot merge two people driving the same
    -- racer; what gets shown is a separate question.
    local gp = race.grandPrix
    gp.names = gp.names or {}
    for vehicle, place in pairs(race.positions) do
      local owner = vehicle.owner
      local key = owner or vehicle.racer.name
      gp.points[key] = (gp.points[key] or 0) + math.max(1, 9 - place)
      gp.names[key] = (owner and owner ~= "player" and owner) or vehicle.racer.name
    end
  end
  -- A Time Trial run only replaces the stored ghost if it was actually faster.
  if race.recorder and race.player.finishTime then
    local data = AK.Ghost:Finish(race.recorder, race.player.finishTime)
    if AK.Ghost:Store(data) then
      AK.RaceUI:Announce("NEW RECORD!", AK.COLORS.gold)
      AK:UnlockAchievement("trial_record")
    end
  end
  -- Freeze the AI telemetry now, while the race still exists: Stop() throws it
  -- away, and the report is only ever read after the flag.
  AK.AI:Snapshot(race)
  self:RecordProgress(race, position)
  if race.network and race.network.isHost then
    for owner, vehicle in pairs(race.byOwner) do
      if owner ~= AK.Net:PlayerName() then AK.Net:Send({ "FINISH", race.network.session, tostring(race.positions[vehicle] or #race.vehicles) }, "WHISPER", owner) end
    end
  end
  -- Hold on the finish for a beat before the results screen takes over: the
  -- chequered flash and the position card need somewhere to land, and cutting
  -- straight to a table of numbers threw away the only moment the race has
  -- been building to. The simulation keeps running underneath, so the kart
  -- rolls on driverless while the card is up.
  --
  -- After a cooldown lap the card has ALREADY played -- it played when the
  -- player crossed, which is when it means something. Firing the whole
  -- sequence again here would flash the screen a second time for no event. All
  -- that is new at this point is the photo finish, which could not be known
  -- until the rival behind was home, so that is the only thing shown.
  local hold = 2.2
  if race.cooldown then
    hold = race.photoFinish and 2.6 or 1.4
    if race.photoFinish then AK.RaceUI:PhotoFinishCard(race.photoFinish) end
  else
    AK.RaceUI:FinishSequence(position, race.photoFinish)
  end
  C_Timer.After(hold, function()
    if self.current ~= race then return end
    self.updateFrame:Hide()
    -- Take the race scene down before showing results. Both frames sit at
    -- FULLSCREEN_DIALOG and the race's children climb to +500 frame level for
    -- depth sorting, so leaving it up painted karts, name tags, the finish-line
    -- checkerboard and stray "MINI BOOST!" banners straight over the results.
    AK.RaceUI:ClearBanner()
    AK.RaceUI:Hide()
    AK.Results:Show(race)
  end)
end

function Race:FinishFromHost(data)
  local race = self.current
  if not race or race.state == AK.RACE_STATES.FINISHED then return end
  self:UpdatePositions(race)
  local finalPlace = tonumber(data)
  if finalPlace then race.positions[race.player] = finalPlace end
  race.state = AK.RACE_STATES.FINISHED
  self:RecordProgress(race, race.positions[race.player] or #race.vehicles)
  self.updateFrame:Hide()
  -- Take the race scene down before showing results. Both frames sit at
  -- FULLSCREEN_DIALOG and the race's children climb to +500 frame level for
  -- depth sorting, so leaving it up painted karts, name tags, the finish-line
  -- checkerboard and stray "MINI BOOST!" banners straight over the results.
  AK.RaceUI:ClearBanner()
  AK.RaceUI:Hide()
  AK.Results:Show(race)
end

function Race:RecordProgress(race, position)
  local progress = AK.db.progress
  race.rewardCoins = math.max(5, 55 - position * 6)
  progress.races = progress.races + 1
  progress.coins = progress.coins + race.rewardCoins
  if progress.races >= 25 then AK:UnlockAchievement("veteran") end
  if position == 1 then
    progress.wins = progress.wins + 1
    AK:UnlockAchievement("first_win")
    if race.player.hazardHits == 0 then AK:UnlockAchievement("kart_speed") end
  end
  if position <= 3 then progress.podiums = progress.podiums + 1 end
  if race.player.launchBoost then AK:UnlockAchievement("perfect_launch") end
  if race.player.usedStar then AK:UnlockAchievement("star_run") end
  -- TIMES ARE A CIRCUIT'S BUSINESS. A battle's elapsed clock is how long the
  -- fight lasted, and a fight that ended quickly is not a fast lap -- but it
  -- was being filed as a personal best against the arena's id all the same, and
  -- "faster is better" made a one-sided massacre the record to beat.
  if not race.battle then
    local best = progress.bestTimes[race.track.id]
    if not best or race.elapsed < best then progress.bestTimes[race.track.id] = race.elapsed end
    -- The best LAP, per circuit, kept for good. `records.bestLap` has been in
    -- the saved-variable defaults since the addon shipped and nothing ever
    -- wrote a single value into it, so the track cards had no record to show
    -- and the table was pure dead weight.
    AK.db.records = AK.db.records or { bestLap = {}, ghosts = {} }
    AK.db.records.bestLap = AK.db.records.bestLap or {}
    local lap = race.player.bestLap
    local bestLap = AK.db.records.bestLap[race.track.id]
    if lap and (not bestLap or lap < bestLap) then
      AK.db.records.bestLap[race.track.id] = lap
    end
  end
end

--- One fixed simulation slice. Never called with a variable dt.
function Race:Step(race, dt)
  -- Snapshot for render interpolation, before anything moves.
  --
  -- The simulation advances in fixed 1/120 slices and the display does not: a
  -- 60fps frame usually consumes exactly two slices, but real frame times
  -- jitter, so sometimes it consumes one and sometimes three. Drawing raw
  -- simulation state therefore draws whichever slice happened to land last --
  -- up to 8ms of travel either way, every frame. Since the camera is derived
  -- from the player's distance, that is a permanent low-level judder on the
  -- entire world scroll, and it is exactly the kind of thing that reads as
  -- "clunky" without ever being visible as a discrete fault. See RaceUI:Lerped.
  for _, vehicle in ipairs(race.vehicles) do
    vehicle.prevDistance, vehicle.prevLateral = vehicle.distance, vehicle.lateral
  end
  for _, projectile in ipairs(race.projectiles or {}) do
    projectile.prevDistance, projectile.prevLateral = projectile.distance, projectile.lateral
  end
  race.delta = dt
  if race.state == AK.RACE_STATES.COUNTDOWN then
    local before = math.ceil(race.countdown)
    race.countdown = race.countdown - dt
    if math.ceil(math.max(0, race.countdown)) ~= before and AK.PlaySfx then AK:PlaySfx("countdown") end
    -- Light one lamp per tick as the countdown runs down: 3.0s left is none
    -- lit, and the third lands just as the lights go green.
    AK.RaceUI:SetStartLights(3 - math.ceil(AK.Math.Clamp(race.countdown, 0, 3)), false)
    if race.countdown <= 0 then
      race.state = AK.RACE_STATES.RACING
      -- Rocket start. The window is a real risk: hold the throttle too early
      -- and the engine floods, which costs you the whole start. Without a
      -- penalty for going early there is no decision, and the countdown is the
      -- first skill test of a Mario Kart race.
      local press = race.launchPress
      if press and press > .10 and press < .42 then
        race.player.boostTime, race.player.launchBoost = 1.1, true
        AK.RaceUI:Announce("ROCKET START!", AK.COLORS.gold)
        AK.RaceUI:LaunchEffect(AK.COLORS.gold, true)
        AK.RaceUI:Shake(14)
        if AK.PlaySfx then AK:PlayStinger("megaBoost", 2, 0.05) end
      elseif press and press >= 1.15 then
        -- Jumped the lights: stall, and everyone else leaves.
        race.player.stalled = 1.6
        race.player.speed = 0
        AK.RaceUI:Announce("FALSE START!", AK.COLORS.danger)
        AK.RaceUI:Shake(10)
        if AK.PlaySfx then AK:PlaySfx("defeat") end
      else
        AK.RaceUI:Announce("GO!", AK.COLORS.lime)
      end
      -- All three green, and a flash on the line.
      AK.RaceUI:SetStartLights(3, true)
      AK.RaceUI:Flash(AK.COLORS.lime, .22)
      if AK.PlaySfx then AK:PlaySfx("countdownGo") end
    end
  elseif race.state == AK.RACE_STATES.RACING then
    self:UpdateRacing(race, dt)
  elseif race.state == AK.RACE_STATES.COOLDOWN then
    self:UpdateCooldown(race, dt)
  end
end

--- Frame entry point. Physics advances in fixed slices so that drift charge,
--- acceleration curves and collision windows behave identically at 30fps and
--- 144fps; only rendering runs per frame.
function Race:Update(elapsed)
  local race = self.current
  if not race then return end
  race.clock = race.clock or AK.FixedStep:New()
  AK.FixedStep:Advance(race.clock, elapsed, function(dt)
    if self.current == race then self:Step(race, dt) end
  end)
  -- How much of the CURRENT slice has not been simulated yet, 0..1. Rendering
  -- draws between the last two simulated states by this much, which is what
  -- decouples the picture from the simulation's tick boundaries.
  race.alpha = AK.Math.Clamp(race.clock.accumulator / AK.FixedStep.RATE, 0, 1)
  -- Render with the real frame delta so visual easing stays smooth.
  race.renderDelta = math.min(elapsed, 0.1)
  AK.RaceUI:Render(race)
end
