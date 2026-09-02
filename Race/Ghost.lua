local _, AK = ...

-- Ghost recording and playback for Time Trial.
--
-- The ghost is a recording of where the kart WAS, not a second simulation. It
-- has no physics, no collision, no race position and cannot be interacted with;
-- it exists purely so you can see your previous best.
--
-- Samples are taken on a fixed interval rather than every frame: a three-minute
-- race at 120Hz would be 20,000 samples, and the difference is invisible once
-- the playback interpolates.
AK.Ghost = {}
local Ghost = AK.Ghost

Ghost.INTERVAL = 0.10   -- seconds between samples

function Ghost:NewRecorder(track, racerId)
  return {
    track = track.id, racer = racerId,
    samples = {}, clock = 0, elapsed = 0,
  }
end

function Ghost:Record(recorder, vehicle, dt)
  if not recorder then return end
  recorder.elapsed = recorder.elapsed + dt
  recorder.clock = recorder.clock + dt
  if recorder.clock < self.INTERVAL then return end
  recorder.clock = recorder.clock - self.INTERVAL
  -- Only what playback actually needs to draw the kart convincingly.
  table.insert(recorder.samples, {
    t = recorder.elapsed,
    d = vehicle.progress or vehicle.distance,
    l = vehicle.lateral,
    s = vehicle.speed,
    -- Drift state is recorded so the ghost visibly slides through corners
    -- rather than gliding, which is most of what makes it read as a driver.
    dr = vehicle.drifting and (vehicle.driftDirection or 0) or 0,
    a = (vehicle.air or 0) > 0 and 1 or 0,
  })
end

--- Trim to the finish and hand back a storable table.
function Ghost:Finish(recorder, finishTime)
  if not recorder or #recorder.samples < 2 then return nil end
  recorder.time = finishTime
  return {
    track = recorder.track, racer = recorder.racer,
    time = finishTime, interval = self.INTERVAL,
    samples = recorder.samples,
  }
end

function Ghost:NewPlayer(data)
  if not data or not data.samples or #data.samples < 2 then return nil end
  return { data = data, elapsed = 0, index = 1 }
end

--- Advance the ghost and return its interpolated state, or nil once it has
--- finished its run.
function Ghost:Advance(player, dt)
  if not player then return nil end
  player.elapsed = player.elapsed + dt
  local samples = player.data.samples
  -- Walk forward to the bracketing pair.
  while player.index < #samples - 1 and samples[player.index + 1].t < player.elapsed do
    player.index = player.index + 1
  end
  local a = samples[player.index]
  local b = samples[player.index + 1]
  if not b then return nil end
  local span = math.max(1e-4, b.t - a.t)
  local blend = AK.Math.Clamp((player.elapsed - a.t) / span, 0, 1)
  return {
    distance = a.d + (b.d - a.d) * blend,
    lateral = a.l + (b.l - a.l) * blend,
    speed = a.s + (b.s - a.s) * blend,
    drifting = a.dr ~= 0,
    driftDirection = a.dr,
    air = a.a,
  }
end

--- Saved best ghost for a track/engine-class combination.
local function key(trackId)
  return trackId .. "|" .. (AK.db.settings.engineClass or "150cc")
    .. (AK.db.settings.mirror and "|mirror" or "")
end

function Ghost:Best(trackId)
  return AK.db.records and AK.db.records.ghosts and AK.db.records.ghosts[key(trackId)]
end

function Ghost:Store(data)
  if not data then return false end
  AK.db.records = AK.db.records or { bestLap = {}, bestRace = {}, ghosts = {} }
  AK.db.records.ghosts = AK.db.records.ghosts or {}
  local slot = key(data.track)
  local existing = AK.db.records.ghosts[slot]
  -- Only keep a run that actually beat the stored one.
  if existing and existing.time and existing.time <= data.time then return false end
  AK.db.records.ghosts[slot] = data
  return true
end
