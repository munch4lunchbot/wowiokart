local _, AK = ...

-- Live-tunable render and feel values. The renderer reads these straight out of
-- the saved variables every frame, so `/kart tune` can dial the camera, the
-- model framing and the handling in mid-race without a reload.
AK.Tuning = {}
local Tuning = AK.Tuning

-- `section` entries are headers, not values.
Tuning.defs = {
  { section = "BAINE" },
  -- THE rider-size knob, and the one I kept missing: modelScale sets the frame,
  -- but this sets how far back the model's own camera sits inside it. At 3.2
  -- the rider was pushed so far back they read as a doll in a large kart.
  { key = "modelZoom", label = "Rider zoom out", default = 2.4, rev = 11, step = 0.1, min = 0.4, max = 6.0,
    hint = "How far back the rider's own camera sits. LOWER makes the rider bigger in the seat.\nThis, not Size, is what fixes a rider who looks small in their kart. Raise it if they are cropped." },
  { key = "modelZ", label = "Height in seat", default = 0.0, step = 0.04, min = -1.5, max = 1.5,
    hint = "Negative sinks him into the kart, positive lifts him out." },
  -- This multiplies the KART's size, so it is a ratio, not an absolute. A saved
  -- 1.65 therefore made every rider twice as big as the kart they sit in -- no
  -- amount of front-chassis can contain that, and it was the third cause of
  -- riders bursting through. Almost certainly set to compensate for the old
  -- far-back camera making everything tiny; that is fixed at the camera now.
  { key = "modelScale", label = "Size", default = 0.80, rev = 10, step = 0.05, min = 0.5, max = 3.0,
    hint = "Rider size RELATIVE to the kart, so 1.0 is already rider-fills-kart.\nRaise the camera lens or Racer footprint to make everything bigger; raise this and the rider outgrows the seat." },
  -- 1.15 read as a toy at real client resolutions; MK64's kart owns a real
  -- slice of the bottom of the screen, and that presence is most of the feel.
  -- Scaled with the wider road: the kart is a fixed 2.2m against a road that is
  -- now 18m across, and it is the RATIO that reads. MK64 sits at 20-25% of the
  -- road's width; 1.60 against roadHalf 9 lands on 20%.
  { key = "kartScale", label = "Racer footprint", default = 1.05, rev = 13, step = 0.05, min = 0.35, max = 3.0,
    hint = "Size of every racer on screen. What matters is the kart's size RELATIVE to the road,\nso raise this whenever you widen the road or you will lose the field in it." },
  { key = "modelLift", label = "Seat offset", default = 0.52, rev = 3, step = 0.02, min = -0.5, max = 0.8,
    hint = "Shifts the model frame up off the road surface." },
  -- Read off the art itself: kart.tga has a SEAT BACK spanning rows 29-86 and
  -- the body/wheels from row 72 down. The seat back is behind the driver from
  -- this camera, so it must stay in the rear pass; only the body belongs in
  -- front. 0.55 cuts at row 72, exactly the body's top edge.
  --
  -- 0.42 cut at row 93, leaving rows 72-93 of the body behind the driver, so
  -- legs showed through it. 0.70 cut at row 48 and dragged the seat back into
  -- the front pass, which drew a slab across the rider's chest -- the kart
  -- looked like a tank with a turret.
  { key = "kartLip", label = "Kart over legs", default = 0.55, rev = 11, step = 0.03, min = 0, max = 0.95,
    hint = "How much of the kart is drawn in FRONT of the driver.\nToo low and legs poke through the bodywork; past ~0.6 the seat back comes forward and buries the rider. 0 disables it." },
  { key = "leanAmount", label = "Lean into corners", default = 1.0, step = 0.1, min = 0, max = 3.0,
    hint = "Rotates the racer as you slide. WoW can only yaw a model, not bank it,\nso this reads as the character turning to face sideways rather than leaning. Set 0 to keep everyone facing forward." },

  { section = "CAMERA" },
  { key = "camHeight", label = "Height", default = 6.10, rev = 9, step = 0.25, min = 1.0, max = 16.0,
    hint = "Higher is more top-down. Past about 9 you are looking down from a drone\nrather than sitting behind a kart, and the sense of speed goes with it." },
  -- THE most consequential value in the panel, and the least obvious.
  --
  -- On-screen road width is camDepth x roadHalf: a wide-angle lens shrinks the
  -- road no matter how far the width slider is pushed. A saved 0.45 here made
  -- roadHalf 12 -- the maximum -- render NARROWER than the stock 0.95 x 6.0,
  -- which is how "the road feels too narrow at 12" happens. It also halves the
  -- kart, the field and the scenery, which is most of a flat, distant scene.
  { key = "camDepth", label = "Lens (zoom)", default = 0.85, rev = 9, step = 0.02, min = 0.25, max = 1.6,
    hint = "Lower is a wider angle -- but it also shrinks EVERYTHING, including the road.\nOn-screen road width is this times Road width, so lowering this then raising Road width fights itself." },
  -- Reset to 6.0 (rev 8). A saved value of 18 -- the slider maximum -- was
  -- putting the kart 6% of the screen wide and drawn 54% of the way UP it,
  -- near the horizon, because both size and height fall off with this value.
  -- That one number was most of "our kart is tiny" and then "we are giant"
  -- once a size floor was added to compensate.
  { key = "camBack", label = "Chase distance", default = 6.0, rev = 8, step = 0.4, min = 2.0, max = 18.0,
    hint = "How far behind the kart the camera sits.\nRaising this shrinks your kart AND slides it up toward the horizon; 6 keeps it low and present." },
  { key = "horizon", label = "Horizon height", default = 150, step = 10, min = -200, max = 400 },
  -- Lives with the camera, not with the AI. Workshop builds one TAB per
  -- section, so sitting in the AI block put "how far down the road is drawn"
  -- on the opponents tab, where nobody tuning the view would ever look for it.
  -- 330 -> 560 (rev 7). At 330 the road did not reach the horizon: it stopped
  -- at a hard horizontal edge partway up the frame with open ground between
  -- its end and the treeline, so the far field read as a painted backdrop with
  -- a strip of tarmac laid on it rather than as a road going somewhere. The
  -- strips are spread uniformly in 1/z, so where the LAST one lands is the
  -- only thing this changes -- the near road is sliced exactly as finely at
  -- 560 as at 330, and the count is identical. It is close to free, and it is
  -- the difference between seeing the corner after next and guessing at it.
  { key = "drawDistance", label = "See ahead (m)", default = 560, rev = 7, step = 20, min = 120, max = 900,
    hint = "How far down the road is drawn. Higher gives more warning before a corner arrives, which is most of what makes a circuit readable.\nThe road is sliced into the same number of strips whatever this says, so raising it costs almost nothing." },
  { key = "shakeScale", label = "Camera shake", default = 1.0, step = 0.1, min = 0, max = 3.0 },
  { key = "boostFov", label = "Speed lens kick", default = 0.075, step = 0.01, min = 0, max = 0.3 },
  { key = "camYaw", label = "Turn into corners", default = 1.0, step = 0.1, min = 0, max = 3.0,
    hint = "How far the camera swings through a bend. 0 is the old flat slide." },
  { key = "camFollow", label = "Chase lag", default = 6.0, rev = 16, step = 0.5, min = 1.0, max = 40.0,
    hint = "How quickly the camera catches up with the kart ACROSS the road.\nLow is a loose chase camera: the kart visibly slides toward the outside of a corner and settles back on the exit.\n40 is rigidly locked, which pins your kart to one column of pixels and makes the world slide under you instead." },
  { key = "camFollowMax", label = "Chase lag limit", default = 0.15, rev = 16, step = 0.01, min = 0, max = 0.6,
    hint = "Ceiling on how far the camera is allowed to trail, as a fraction of the road's half-width.\nStops a long corner walking your kart off the side of the screen where you cannot see what you are about to hit." },

  { section = "CORNERS" },
  -- Stored as a 1-30 dial and divided by 1000 where it is used, because the
  -- underlying gain is ~0.010 and a panel that reads "0.01" for every value in
  -- its range is not a control, it is a decoration.
  { key = "bendGain", label = "Corner drama", default = 10.0, rev = 6, step = 0.5, min = 1.0, max = 30.0,
    hint = "How far a bend swings the road across the screen.\nThis is the single value that decides whether corners read as corners. Raise it until a hairpin sweeps off the side." },
  -- 1.35 -> 1.85 -> 2.60. The rev MUST go up with the number or the change
  -- reaches nobody who has already played: saved tuning outlives every later
  -- decision about what the default should be, which is why the last two
  -- widenings were invisible to anyone mid-session.
  { key = "offroadRoom", label = "Room off track", default = 2.60, rev = 16, step = 0.05, min = 1.0, max = 4.0,
    hint = "How far past the tarmac you can stray before the verge ends, as a multiple of the road's half-width.\nMost of the verge is a wall you bounce off; every other marker span is an opening you fall through instead. Tunnels are never gapped." },
  { key = "brakeForce", label = "Brake strength", default = 2.1, rev = 11, step = 0.1, min = 0.8, max = 4.0,
    hint = "How hard the brake bites, relative to acceleration.\nLifting off the gas now coasts gently on its own, so this is the deliberate, expensive way to slow down." },

  { section = "AI" },
  { key = "aiRubberBand", label = "Catch-up cap", default = 0.07, rev = 15, step = 0.005, min = 0, max = 0.25,
    hint = "Ceiling on the top-speed nudge the AI gets from the gap to you.\n0 makes them entirely honest. Being reeled in is capped at a third of this, so a leader never yo-yos.\nDifficulty scales it: Easy x1.4, Normal x1, Hard x0.35." },

  { section = "TRACK" },
  { key = "roadHalf", label = "Road width", default = 9.0, rev = 9, step = 0.2, min = 2.0, max = 18.0,
    hint = "How wide the tarmac reads, in metres either side of the centre line.\nOn-screen width is this times Lens, so check the lens before raising this." },
  { key = "curvePush", label = "Corner G-force", default = 4.2, step = 0.1, min = 0, max = 9.0, rev = 8,
    hint = "How hard corners throw you outward. 0 makes curves cosmetic.\nAt 4.2 a hairpin taken flat out pushes harder than full steering lock can answer, so you must brake or drift through it." },
  { key = "fogStrength", label = "Distance fog", default = 0.8, step = 0.05, min = 0, max = 1.0 },
  { key = "grassContrast", label = "Grass banding", default = 0.93, step = 0.01, min = 0.7, max = 1.0,
    hint = "Lower is more striped. 1.0 is flat colour." },
  { key = "postSpacing", label = "Marker post gap", default = 7, step = 1, min = 2, max = 40,
    hint = "Metres between roadside posts. Closer reads as faster." },

  { section = "WORLD" },
  { key = "treeHeight", label = "Treeline height", default = 1.0, step = 0.1, min = 0, max = 4.0 },
  { key = "cloudAlpha", label = "Cloud strength", default = 0.34, step = 0.03, min = 0, max = 1.0 },
  { key = "specScale", label = "Crowd size", default = 3.4, step = 0.2, min = 0.5, max = 9.0 },
  { key = "specZoom", label = "Crowd zoom out", default = 2.0, step = 0.1, min = 0.4, max = 6.0 },

  { section = "INTERFACE" },
  { key = "hudScale", label = "HUD size", default = 100, step = 5, min = 50, max = 200,
    hint = "Percentage. The HUD already fits itself to your resolution; this nudges that up or down.\nTakes effect immediately -- open this panel during a race and watch it move." },

  { section = "EFFECTS" },
  { key = "particleScale", label = "Spark size", default = 1.0, step = 0.1, min = 0, max = 3.0 },
  { key = "speedLines", label = "Speed streaks", default = 1.0, step = 0.1, min = 0, max = 2.5 },
  { key = "weatherAmount", label = "Weather density", default = 0.5, step = 0.1, min = 0, max = 2.0,
    hint = "Rain, snow and embers. 0 clears the skies on every track." },
  { key = "nightBoost", label = "Night brightness", default = 1.0, step = 0.05, min = 0.4, max = 2.0,
    hint = "Lifts the darker tracks if Deadmines or Netherstorm read too black." },
}

-- Bumped whenever a default changes in a way players should actually receive.
-- Saved settings win over defaults, so without this a corrected default only
-- ever reached people who had never opened the tuning panel.
local TUNING_REVISION = 16

function AK:InitTuning()
  self.db.tuning = self.db.tuning or {}
  local seen = self.db.tuningRev or 1
  for _, def in ipairs(Tuning.defs) do
    if def.key then
      local value = self.db.tuning[def.key]
      if type(value) ~= "number" then
        self.db.tuning[def.key] = def.default
      elseif (def.rev or 1) > seen then
        -- This default was revised after the saved value was written. Take the
        -- new one; anyone who liked the old number can set it back.
        self.db.tuning[def.key] = def.default
      else
        -- Clamp on load, in case a def's range tightened since it was saved.
        self.db.tuning[def.key] = AK.Math.Clamp(value, def.min, def.max)
      end
    end
  end
  self.db.tuningRev = TUNING_REVISION
end

local function format(def, value)
  return math.abs(value) >= 100 and string.format("%d", value) or string.format("%.2f", value)
end

function Tuning:Set(def, value)
  local clamped = AK.Math.Clamp(value, def.min, def.max)
  AK.db.tuning[def.key] = clamped
  local row = self.rows and self.rows[def.key]
  if row then
    row.value:SetText(format(def, clamped))
    -- Highlight anything moved off its default so it is obvious what changed.
    local modified = math.abs(clamped - def.default) > 1e-6
    row.value:SetTextColor(unpack(modified and AK.COLORS.gold or AK.COLORS.lime))
    row.fill:SetWidth(math.max(1, 56 * ((clamped - def.min) / (def.max - def.min))))
  end
end

-- Per-racer seat framing. Every model has a different origin and scale, so
-- these are edited against whoever you currently have selected and reported
-- back with PRINT CHANGES to be baked into Data\Racers.lua.
Tuning.seatDefs = {
  { key = "seatZ", label = "Seat height", step = 0.05, min = -2.0, max = 2.0, default = 0 },
  { key = "seatScale", label = "Seat scale", step = 0.05, min = 0.3, max = 3.0, default = 1 },
}

function Tuning:SelectedRacer()
  return AK:GetRacer(AK.db.selection.racer)
end

function Tuning:SetSeat(def, value)
  local racer = self:SelectedRacer()
  if not racer then return end
  racer[def.key] = AK.Math.Clamp(value, def.min, def.max)
  -- Force every live model to re-read the racer's framing.
  if AK.RaceUI and AK.RaceUI.karts then
    for _, kart in ipairs(AK.RaceUI.karts) do
      kart.model.akSeatZ, kart.model.akSeatScale, kart.model.akAnim = nil, nil, nil
    end
  end
  local row = self.seatRows and self.seatRows[def.key]
  if row then row:SetText(string.format("%.2f", racer[def.key])) end
end

function Tuning:Reset()
  for _, def in ipairs(self.defs) do
    if def.key then self:Set(def, def.default) end
  end
  AK:Print("Render tuning reset to defaults.")
end

--- Dump current values as a copyable line, so good settings can be reported
--- back and baked in as new defaults.
function Tuning:Report()
  local parts = {}
  for _, def in ipairs(self.defs) do
    if def.key then
      local value = AK.db.tuning[def.key]
      if math.abs(value - def.default) > 1e-6 then
        table.insert(parts, def.key .. "=" .. format(def, value))
      end
    end
  end
  if #parts == 0 then
    AK:Print("All render tuning is at defaults.")
  else
    AK:Print("Changed from defaults: " .. table.concat(parts, "  "))
  end
  -- Seat framing is per racer, so report it separately and in a form that can
  -- be pasted straight into Data\Racers.lua.
  for _, racer in ipairs(AK.Racers) do
    if (racer.seatZ or 0) ~= 0 or (racer.seatScale or 1) ~= 1 then
      AK:Print(("%s: seatZ = %.2f, seatScale = %.2f,"):format(racer.id, racer.seatZ or 0, racer.seatScale or 1))
    end
  end
end

-- The standalone RENDER TUNING window that used to live here is gone.
--
-- Nothing called Tuning:Toggle(). UI/Workshop.lua superseded this panel: it
-- reuses everything ABOVE -- Tuning.defs, Set, Reset, Report, seatDefs,
-- SelectedRacer, SetSeat -- and builds its own tabbed UI over them, so the
-- window here had been unreachable dead weight, a second copy of the same
-- panel that could drift out of step with the one people actually see.
-- Workshop:RefreshModels repaints the seat rows, which is what RefreshSeat
-- existed for.
--
-- What that panel did own was the only in-UI link to the sound editor. That
-- link now lives on the Workshop's SOUND tab, where the rest of the audio
-- tools already are.
