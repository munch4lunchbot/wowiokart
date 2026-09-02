local _, AK = ...

-- Fixed-timestep accumulator.
--
-- Physics ran directly on OnUpdate's elapsed time, which means the simulation
-- behaved differently at 30fps and 144fps: drift charge, acceleration curves and
-- collision windows all silently depended on the player's frame rate. A kart
-- racer cannot be tuned that way, and ghosts could never replay accurately.
--
-- Simulation now advances in fixed slices; rendering keeps running every frame
-- and interpolates nothing (the step is short enough that it does not show).
AK.FixedStep = {}
local FixedStep = AK.FixedStep

FixedStep.RATE = 1 / 120        -- simulation slices per second
FixedStep.MAX_SLICES = 8        -- ceiling so a hitch cannot spiral

function FixedStep:New()
  return { accumulator = 0, slices = 0, dropped = 0 }
end

--- Feed real elapsed time; calls `step(RATE)` however many times are due.
--- Returns the number of slices run, for debug readouts.
function FixedStep:Advance(clock, elapsed, step)
  -- Clamp the incoming frame: alt-tabbing must not deliver a five second dt
  -- and fast-forward the whole race.
  clock.accumulator = clock.accumulator + math.min(elapsed, 0.25)
  local ran = 0
  while clock.accumulator >= self.RATE do
    if ran >= self.MAX_SLICES then
      -- Too far behind to catch up. Drop the debt rather than freezing.
      clock.dropped = clock.dropped + math.floor(clock.accumulator / self.RATE)
      clock.accumulator = 0
      break
    end
    step(self.RATE)
    clock.accumulator = clock.accumulator - self.RATE
    ran = ran + 1
  end
  clock.slices = clock.slices + ran
  return ran
end
