local _, AK = ...

AK.RaceUI = {}
local RaceUI = AK.RaceUI
local UI = AK.UI

-- Pseudo-3D projection. Segments are sampled at even steps of 1/z rather than
-- of z: perspective maps 1/z linearly to screen height, so every quad ends up
-- the same few pixels tall instead of piling slivers onto the horizon.
-- Camera and road figures live in AK.db.tuning so `/kart tune` can correct them
-- live; only values that never need tweaking are constants here.
-- More, thinner strips. The road edge is built from axis-aligned quads, so the
-- visible staircase along the verge is exactly one strip tall: halving the
-- strip height halves the step. 110 puts them at roughly 6px.
local SEGMENTS = 150
local FORK_SEGMENTS = 40
local TUNNEL_HEIGHT = 7.5        -- metres from road to tunnel ceiling
local TUNNEL_TILE = 5.0          -- metres per repeat of the rock texture
local PROPS = 54                 -- roadside scenery frames in flight at once
local PROP_SPACING = 9           -- metres between props on each side
-- How far ahead the road is drawn. At racing pace this is the difference
-- between three seconds of warning and five: you cannot read a corner you
-- cannot see yet, and every track felt like a straight partly because the bend
-- only appeared once you were already in it.
local FAR_Z = 330
--- Nearer than this, a trackside object is never faded for being off-axis: it
--- is genuinely sweeping past you, not stranded off the road by a corner.
---
--- Solved rather than guessed. An object reaches the screen edge when
--- `(camDepth / dz) * worldX >= 1`, so with camDepth 0.85 a pickup on the
--- centreline half of the road (4.5m out of roadHalf 9) only leaves the frame
--- inside 3.8m, and one right on the verge (9m) inside 7.7m. Anything further
--- away than that which is off-axis was put there by the corner, not by you
--- driving past it. The first attempt used 45m, which left everything from 8m
--- to 45m unfaded -- the entire band where the road has already begun to swing
--- away -- so things carried on sliding in from the edge.
local EDGE_FADE_MIN_Z = 12
local STRIPE_LENGTH = 4.5
-- Metres covered by one repeat of the ground textures. The road art is 4 slabs
-- square, so 4.8m gives roughly 1.2m paving stones.
local ROAD_TILE = 4.2
local GRASS_TILE = 3.0
local BOOST_FOV = 0.075
local SPECTATOR_SPACING = 42
local SPECTATOR_SLOTS = 6
local PARTICLES = 110
local TREES = 44

local ORDINALS = { "1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH" }

-- Drift charge stages, Mario-Kart style: the spark colour tells you how big the
-- boost will be before you release it.
--- The drift ladder. These thresholds MUST match Physics:ReleaseDrift exactly
--- (0.35 mini / 0.9 super / 1.8 mega) or the colour lies about the boost you
--- are about to get: the meter used to turn at 0.75 and 1.70, so it promised a
--- tier you had not banked yet and you released early. Blue, orange, purple --
--- three unmistakably different hues, because the whole point is reading it in
--- peripheral vision with your eyes on the corner.
local DRIFT_STAGES = {
  { threshold = 1.80, color = { 0.72, 0.42, 1.00 }, tier = 3 },   -- mega
  { threshold = 0.90, color = { 1.00, 0.58, 0.10 }, tier = 2 },   -- super
  { threshold = 0.35, color = { 0.30, 0.70, 1.00 }, tier = 1 },   -- mini
  { threshold = 0.00, color = { 0.92, 0.94, 1.00 }, tier = 0 },   -- nothing banked
}

-- --------------------------------------------------------------------------
-- HUD layout
-- --------------------------------------------------------------------------
--
-- Every HUD offset used to be an absolute pixel figure authored against a
-- 1280-wide window: a 620x73 header, a 128px map, a control row spanning 816px
-- of a screen that may only be 800 wide. On a 1440p client the whole interface
-- shrivelled into the corners at half its intended size; on a small one it ran
-- off both edges. The SKYLINE was fixed for exactly this reason -- there is a
-- comment about it forty lines up -- and the HUD, which the player actually
-- reads, never was.
--
-- So: the HUD is authored once at a design resolution and the whole thing is
-- scaled as one frame to fit whatever the player has (RaceUI:LayoutHud). One
-- SetScale on one container handles every child, so the offsets below stay
-- readable numbers rather than becoming screen fractions.
--
-- The arrangement is Mario Kart's grammar, not a settings panel's. The three
-- things you need without looking are WHICH LAP, WHAT ITEM and WHAT PLACE, so
-- those get the corners, the centre and the size. The clock and the map are
-- reference material you consult between corners, so they get the far corners.
-- Everything used to live in one 620x73 strip of eight readouts across the top.
local HUD_DESIGN_W, HUD_DESIGN_H = 1600, 900
local HUD = {
  lap      = { point = "TOPLEFT",     x =   26, y =  -22, w = 196, h =  74 },
  item     = { point = "TOP",         x =    0, y =  -22, w = 124, h = 124 },
  clock    = { point = "TOPRIGHT",    x =  -26, y =  -22, w = 236, h =  84 },
  place    = { point = "BOTTOMLEFT",  x =   30, y =  116, w = 210, h = 132 },
  map      = { point = "BOTTOMRIGHT", x =  -26, y =  110, w = 168, h = 168 },
  drift    = { point = "BOTTOM",      x =    0, y =  112, w = 320, h =  18 },
  controls = { point = "BOTTOM",      x =    0, y =   26, w = 872, h =  44 },
  quit     = { point = "TOPRIGHT",    x =  -26, y = -116, w =   76, h = 26 },
}
local HUD_PANEL = { .025, .05, .10, .88 }
local ITEM_ICON = 74
-- Drift tick positions as a FRACTION of the meter, derived from the ladder
-- above rather than from three hand-placed pixel offsets that had drifted out
-- of step with it: the ticks used to sit at even thirds while the tiers turned
-- at 0.35, 0.90 and 1.80 of a 2.5 scale, so the bar's rungs marked nothing.
local DRIFT_MAX = 2.5
-- Named rungs. The colour tells you which tier you are on in peripheral vision;
-- the name confirms it when you have a moment to look.
local DRIFT_TIER_NAMES = { [1] = "MINI", [2] = "SUPER", [3] = "MEGA" }
local DRIFT_TRACK = HUD.drift.w - 8
local DRIFT_TICKS = {}
for i = #DRIFT_STAGES - 1, 1, -1 do
  DRIFT_TICKS[#DRIFT_TICKS + 1] = DRIFT_STAGES[i].threshold / DRIFT_MAX
end

local ART_PREFIX = "Interface\\AddOns\\kart\\Art\\"
local OBJECT_STYLE = {
  -- Item cubes float and bob; dash panels lie flat on the tarmac.
  box = { icon = ART_PREFIX .. "itembox.tga", color = { 1.00, 0.82, 0.25 }, label = "", size = 2.2, float = true, spin = true },
  boost = { icon = ART_PREFIX .. "dashpad.tga", color = { 1.00, 0.72, 0.18 }, label = "", size = 3.8, flat = true },
  shortcut = { icon = "Interface\\Icons\\Spell_Arcane_PortalStormWind", color = { 0.35, 0.85, 1.00 }, label = "SHORTCUT", size = 3.4 },
  hazard = { icon = ART_PREFIX .. "banana.tga", color = { 1.00, 0.85, 0.22 }, label = "", size = 2.2 },
}

-- A widget texture is always an axis-aligned rectangle: SetRotation turns the
-- UVs, not the quad, so flat colour can never be round or soft-edged. The fix
-- is real art with an alpha channel, so the addon ships its own generated TGAs
-- rather than guessing at Blizzard asset names that may not exist.
local ART = "Interface\\AddOns\\kart\\Art\\"

-- One body texture per kart id, so the six karts are six silhouettes instead of
-- one slab tinted six ways. Keyed off AK.Karts because that is exactly the set
-- Art/generate-art-kart.js emits art for; anything unknown (the ghost before a
-- selection exists, a future kart without art) falls back to the generic body
-- rather than showing WoW's missing-texture green.
local kartArt = {}
for _, entry in ipairs(AK.Karts or {}) do
  kartArt[entry.id] = ART .. "kart-" .. entry.id .. ".tga"
end
local function kartTexture(id)
  return kartArt[id] or (ART .. "kart.tga")
end
local SOLID = "Interface\\Buttons\\WHITE8x8"

--- `tile` asks for REPEAT wrapping, without which a SetTexCoord above 1 clamps
--- instead of repeating and the art just stretches.
local function makeTexture(parent, layer, color, sublayer, file, tile)
  local texture = parent:CreateTexture(nil, layer, nil, sublayer)
  if file and tile then
    texture:SetTexture(ART .. file, "REPEAT", "REPEAT")
  else
    texture:SetTexture(file and (ART .. file) or SOLID)
  end
  texture:SetVertexColor(unpack(color))
  return texture
end

-- Additive blending plus a soft radial falloff is what makes something read as
-- emitted light rather than a painted rectangle.
local function makeGlow(parent, layer, color, sublayer, file)
  local texture = parent:CreateTexture(nil, layer, nil, sublayer)
  texture:SetTexture(ART .. (file or "glow.tga"))
  texture:SetVertexColor(unpack(color))
  texture:SetBlendMode("ADD")
  return texture
end

-- Additive, but filling its whole rect: for washes and bar fills, where a
-- radial falloff would leave dark corners.
local function makeWash(parent, layer, color, sublayer)
  local texture = parent:CreateTexture(nil, layer, nil, sublayer)
  texture:SetTexture(SOLID)
  texture:SetVertexColor(unpack(color))
  texture:SetBlendMode("ADD")
  return texture
end

local function shade(color, factor, alpha)
  return { color[1] * factor, color[2] * factor, color[3] * factor, alpha or 1 }
end

-- SetGradient's signature moved to colour objects in 10.0; skip the flourish
-- rather than error on clients that disagree.
local function applyGradient(texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
  if not texture.SetGradient or not CreateColor then return end
  pcall(texture.SetGradient, texture, orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
end

local function vehicleIsDrifting(vehicle)
  return vehicle and vehicle.drifting
end

local function driftColor(charge)
  for _, stage in ipairs(DRIFT_STAGES) do
    if charge >= stage.threshold then return stage.color end
  end
  return DRIFT_STAGES[#DRIFT_STAGES].color
end

--- Which boost tier this charge would currently bank: 0 (none) to 3 (mega).
local function driftTier(charge)
  for _, stage in ipairs(DRIFT_STAGES) do
    if (charge or 0) >= stage.threshold then return stage.tier end
  end
  return 0
end

--- Project a point ahead of the camera onto the screen.
-- @param dz metres ahead of the camera (must be > 0)
-- @param worldX lateral world offset in metres
-- @return screen x, screen y (frame-centre relative), pixels-per-metre scale
-- @param worldY road surface height at that point, in metres. The camera rides
-- at camHeight above the road beneath it, so a crest ahead pushes toward the
-- horizon and a dip falls away below.
-- Camera yaw. Rotating the camera by a small angle shifts every projected point
-- by the SAME screen distance (the Z terms cancel against 1/z), so a yaw is a
-- uniform horizontal slide of the world -- which is exactly the swinging
-- vanishing point that makes a corner feel like turning rather than like the
-- road sliding sideways underneath you. This is the single biggest difference
-- between an OutRun-style renderer and a kart racer.
function RaceUI:Project(dz, worldX, camX, worldY)
  local tuning = self.T
  local scale = (self.camDepth or tuning.camDepth) / dz
  local x = scale * (worldX - camX) * self.halfWidth
    + (self.yawShift or 0) + (self.shakeX or 0)
  local rise = (self.camWorldY or tuning.camHeight) - (worldY or 0)
  local y = tuning.horizon - scale * rise * self.halfHeight + (self.shakeY or 0)
  return x, y, scale * self.halfWidth
end

-- Where the road sits on screen, accumulated FORWARD from the kart.
--
-- This replaces projecting the road's absolute world position. That older model
-- required the centreline to stay within a few units of the camera axis for the
-- small-angle projection to hold, which is why Compile renormalises the entire
-- lap down to `sweep` -- and why every corner rendered nearly flat. Worse, the
-- normalisation divides by the lap's GLOBAL peak, so the more corners a track
-- had, the harder each one was squashed: making a circuit more technical made
-- it look more like a straight line. Measured, the tightest hairpin in the game
-- moved the road 90px out of a 640px half-screen, and Elwynn's sweep moved it
-- exactly 0px.
--
-- Classic pseudo-3D never tracks world position. The kart is the origin and
-- curvature integrates forward from it: each step ahead adds to a running
-- lateral velocity, which adds to a running offset. A hairpin then bends the
-- road by the same amount regardless of what else is on the lap, and the road
-- may bend arbitrarily far ahead without leaving the projection's valid range.
--
-- It also reads the same curveTable the physics already steers by, so what you
-- see and what the kart feels finally come from one source.
local BEND_STEP = 2

--- The tuned gain, as a plain number. The panel stores a 1-30 dial so it has
--- usable resolution on screen; the renderer wants the small real value.
local function bendGain()
  local dial = AK.db and AK.db.tuning and AK.db.tuning.bendGain
  return (dial or 10.0) / 1000
end

function RaceUI:BuildBend(track, camZ)
  local samples = math.ceil(FAR_Z / BEND_STEP) + 4
  local bend = self.bendTable
  if not bend then bend = {} self.bendTable = bend end
  local gain = bendGain()
  local offset, lateral = 0, 0
  for i = 1, samples do
    bend[i] = offset
    lateral = lateral + AK.Math.RoadCurve(track, camZ + (i - 1) * BEND_STEP) * gain * BEND_STEP
    offset = offset + lateral * BEND_STEP
  end
  self.bendTable, self.bendCount, self.bendFrom = bend, samples, camZ
end

--- Lateral screen offset of the centreline at an absolute distance. Clamped at
--- both ends so anything sampled outside the drawn window still resolves.
function RaceUI:Bend(distance)
  local bend = self.bendTable
  if not bend or not self.bendCount then return 0 end
  local t = (distance - (self.bendFrom or 0)) / BEND_STEP
  local maxT = self.bendCount - 2
  if t < 0 then t = 0 elseif t > maxT then t = maxT end
  local index = math.floor(t)
  local fraction = t - index
  local a, b = bend[index + 1] or 0, bend[index + 2] or 0
  return a + (b - a) * fraction
end

--- World-space helpers so every projected thing agrees on where the road is.
function RaceUI:RoadAt(track, distance)
  return self:Bend(distance), AK.Math.RoadHeight(track, distance)
end

--- Fade for anything the corner has swung off-axis.
---
--- One implementation for objects, hazards and props, because three copies of
--- the same thresholds drifted apart -- props ended up with no fade at all and
--- were drawn to 2.2 half-widths off screen, which is what was still sliding in
--- after the distance-space fix.
---
--- The band starts at 0.62 rather than 0.86 of a half-screen. At 0.86 a thing
--- was fully opaque until it was practically at the edge, so the eye caught it
--- travelling before it began to dim; starting the fade well inside the frame
--- means anything drifting outward is already going before it can be tracked.
--- Inside EDGE_FADE_MIN_Z nothing fades: that is a pickup genuinely sweeping
--- past you, and hiding it is worse than the slide ever was.
function RaceUI:EdgeFade(x, dz)
  if (dz or 0) <= EDGE_FADE_MIN_Z then return 1 end
  local off = math.abs(x)
  local from, gone = self.halfWidth * 0.62, self.halfWidth * 1.02
  if off <= from then return 1 end
  return AK.Math.Clamp((gone - off) / (gone - from), 0, 1)
end

--- Fade in over the last stretch of a class's own draw range.
---
--- Pulling a draw range back to where the road actually still is on screen is
--- only half a fix: a hard cutoff swaps things sliding in from the side for
--- things popping into existence, which is not obviously better. Everything
--- discrete therefore arrives over the last 30% of its range.
---
--- RenderObjects had this inline and nothing else had it at all, which is why
--- posts, arches, the finish gantry and the crowd were all left drawn out to
--- 200-300m -- depths where, measured (verify-render.js), the road is off the
--- side of the screen more than half the lap.
function RaceUI:DepthFade(dz, far)
  local from = far * 0.70
  if dz <= from then return 1 end
  return AK.Math.Clamp((far - dz) / (far - from), 0, 1)
end

--- On-screen size of something `metres` across, at this depth.
---
--- The floor and ceiling are fractions of the screen, never pixel constants.
--- Trackside objects were clamped to (22, 260) absolute pixels, which is the
--- same mistake that shrank the skyline to specks on a 1440p client: a 260px
--- ceiling is a third of a 720p preview and a tenth of the player's screen, so
--- everything quietly flattened out at high resolution.
--- The FLOOR was set too low when it was made screen-relative. The absolute
--- value it replaced was 22px, which on the 1280-wide reference is 0.034 of a
--- half-screen; 0.012 is barely a third of that, so every distant pickup came
--- out roughly three times smaller than before the change. Rendered against
--- OLDOBJ, that is plainly visible. 0.020 lands near the old 22px on a 2560
--- client while staying resolution-independent, which was the point.
function RaceUI:ObjectSize(pixelsPerMetre, metres)
  return AK.Math.Clamp(pixelsPerMetre * metres, self.halfWidth * 0.020, self.halfWidth * 0.46)
end

--- How much the distance haze has eaten this far out. Shared so an object's
--- shadow fades on exactly the same curve as the road it is sitting on.
function RaceUI:FogAt(dz)
  return AK.Math.Clamp(1 - (dz / FAR_Z) * self.T.fogStrength, 0.22, 1)
end

--- Depth-sorted frame level for a trackside thing.
---
--- Everything shares one banding so a nearer object really does draw over a
--- farther kart. Depth is bucketed to 2m and strided by 3 because a kart owns
--- THREE consecutive levels (body / rider / front chassis); `base` separates
--- the categories at equal depth. The whole band must stay under 400, which is
--- where the tag and HUD layers begin -- pushing race content above that once
--- drew karts over the main menu.
local DEPTH_BASE = { shot = 150, object = 152, hazard = 156, kart = 160 }
local DEPTH_BUCKETS = 74

--- Which of the 74 depth buckets this distance falls in, 0 furthest.
---
--- Spread across the WHOLE draw distance. The old form clamped `FAR_Z - dz` at
--- 148, which was fine when FAR_Z was 210 but silently broke when it went to
--- 330: everything nearer than 182m saturated into a single bucket, so the
--- entire near field -- where things actually overlap -- had no depth sorting
--- at all and fell back to creation order.
local function depthBucket(dz)
  return math.floor(AK.Math.Clamp((FAR_Z - dz) / FAR_Z, 0, 1) * (DEPTH_BUCKETS - 1))
end

function RaceUI:DepthLevel(kind, dz)
  return self.frame:GetFrameLevel() + (DEPTH_BASE[kind] or 152) + depthBucket(dz) * 3
end

--- Kick the camera. Impacts, boosts and rough ground all route through here.
function RaceUI:Shake(amount)
  if AK.db.settings.reducedEffects then return end
  self.shake = math.max(self.shake or 0, amount)
end

-- ---------------------------------------------------------------------------
-- FEEL CHANNELS
--
-- Every camera reaction is an OFFSET added to the tuned baseline at read time
-- and eased back to zero. Nothing here is ever written back into AK.db.tuning,
-- and each channel is snapped hard to zero once it falls under an epsilon.
--
-- Both of those rules exist for one reason: a camera that keeps a fraction of
-- every boost, landing and hit is a camera that has silently moved somewhere
-- else by lap three, and the player cannot tell you why the game stopped
-- feeling right. Easing toward zero asymptotically never actually arrives, so
-- without the snap the residue is real -- small, permanent, and cumulative.
local FEEL_EPSILON = 0.0005

--- Ease a channel toward zero and snap it when it is close enough to gone.
local function decay(value, rate, dt)
  if not value or value == 0 then return 0 end
  value = value * math.max(0, 1 - rate * dt)
  if math.abs(value) < FEEL_EPSILON then return 0 end
  return value
end

--- Add an impulse to a feel channel. Impulses take the LARGER of what is there
--- and what is arriving rather than summing, so a burst of events in the same
--- frame cannot stack into something violent.
function RaceUI:Feel(channel, amount)
  if AK.db.settings.reducedEffects then return end
  self.feel = self.feel or {}
  local current = self.feel[channel] or 0
  if math.abs(amount) > math.abs(current) then self.feel[channel] = amount end
end

--- Being hit: the camera is shoved AWAY from whatever hit you, and the world
--- dips. `side` is -1 or 1, or 0 for a hit with no direction to it.
function RaceUI:FeelHit(side, severity)
  severity = severity or 1
  self:Feel("kickX", -(side or 0) * 26 * severity)
  self:Feel("dip", 0.55 * severity)
  self:Shake(14 * severity)
end

--- You landed one on somebody. Light, bright, and over quickly -- the opposite
--- shape to FeelHit, which is heavy, red and shoves you sideways.
function RaceUI:HitConfirmed()
  local x, y, width = self.playerX or 0, self.playerY or 0, self.playerWidth or 60
  self:PlayEffect("pop", x, y + width * 0.55, width * 1.1, AK.COLORS.lime)
  self:Shake(5)
end

--- Landing. The dip is scaled by how long you were in the air, so a kerb hop
--- and a ramp landing are not the same event.
function RaceUI:FeelLanding(airtime)
  local weight = AK.Math.Clamp((airtime or 0) / 1.1, 0.15, 1)
  self:Feel("dip", 1.5 * weight)
  self:Shake(6 + 10 * weight)
end

--- The mini-turbo landing. This is the payoff for the entire drift loop and it
--- has to SNAP: burst, shove, sound, in that order and inside two frames.
--- Anything that ramps here reads as the boost "arriving" rather than firing.
function RaceUI:DriftRelease(tier)
  if (tier or 0) <= 0 then return end
  local x, y, width = self.playerX or 0, self.playerY or 0, self.playerWidth or 60
  -- DRIFT_STAGES is ordered highest-threshold first, so tier 3 is entry 1.
  local hue = DRIFT_STAGES[4 - tier].color
  self:PlayEffect("burst", x, y + width * 0.35, width * (1.4 + tier * 0.5), hue)
  self:Feel("push", 1.6 + tier * 0.9)
  self:Shake(5 + tier * 4)
end

function RaceUI:Build()
  if self.frame then return end
  local frame = CreateFrame("Frame", "AzerothKartRace", UIParent, "BackdropTemplate")
  frame:SetAllPoints(UIParent)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:EnableKeyboard(true)
  frame:Hide()
  self.frame = frame
  self.T = AK.db.tuning
  self.camDepth = self.T.camDepth
  self.shake, self.shakeX, self.shakeY = 0, 0, 0
  self.previous = {}

  self.sky = makeTexture(frame, "BACKGROUND", { .30, .58, .86, 1 }, 0)
  applyGradient(self.sky, "VERTICAL", .70, .84, .96, 1, .10, .26, .55, 1)
  -- Warm brightening just above the horizon instead of a literal sun quad,
  -- which read as a glowing box.
  self.skyGlow = makeWash(frame, "BACKGROUND", { 1, .88, .62, 1 }, 1)
  applyGradient(self.skyGlow, "VERTICAL", 1, .86, .55, 0, 1, .92, .70, .40)

  -- Clouds as thin banded haze. Wide, soft and low contrast reads as sky depth;
  -- fat opaque quads read as floating bricks.
  -- The Oribos ring, hung on the horizon and parallaxed against the curve.
  self.ring = makeTexture(frame, "BACKGROUND", { 1, 1, 1, 1 }, 2, "ring.tga")
  self.ring:Hide()

  -- Drive-through arches. Pooled and projected like any other track object, so
  -- they scale up and pass overhead as you reach them.
  self.arches = {}
  for i = 1, 4 do
    local arch = makeTexture(frame, "ARTWORK", { 1, 1, 1, 1 }, 3, "arch.tga")
    arch:Hide()
    self.arches[i] = arch
  end

  -- Real cloud art with a soft alpha edge, not banded quads.
  self.clouds = {}
  for i = 1, 14 do
    self.clouds[i] = makeTexture(frame, "BACKGROUND", { 1, 1, 1, 1 }, 2, "cloud.tga")
  end

  -- Distant terrain: a far mountain ridge and a mid hill line, each one
  -- horizontally-wrapping texture spanning the full screen. Created after the
  -- clouds so they draw over them, under the tree wall. These two layers plus
  -- their differing parallax rates are what turn "a row of cones on a seam"
  -- into a world with depth.
  self.mountain = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
  self.mountain:SetTexture(ART .. "mountain.tga", "REPEAT", "CLAMP")
  self.mountain:Hide()
  self.hillLine = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
  self.hillLine:SetTexture(ART .. "hills.tga", "REPEAT", "CLAMP")
  self.hillLine:Hide()

  -- Treeline built from actual conifer silhouettes.
  --
  -- Evenly spaced, near-identical trees read as a picket fence -- which is
  -- exactly what the offline renders showed: a row of clones at one pitch with
  -- every third one shorter. So each slot gets a fixed personality: its own
  -- horizontal offset, height, width and depth. It is drawn once, here, rather
  -- than re-derived from sin() every frame, because none of it ever changes.
  local function jitter(i, a, b)
    local v = math.sin(i * a) * b
    return v - math.floor(v)
  end
  self.trees = {}
  self.treeSeed = {}
  for i = 1, TREES do
    self.trees[i] = makeTexture(frame, "BACKGROUND", { 1, 1, 1, 1 }, 3, "tree.tga")
    self.treeSeed[i] = {
      x = jitter(i, 12.9898, 43758.5453) - 0.5,   -- offset within its own slot
      h = jitter(i, 78.2330, 24634.6345),         -- height
      w = jitter(i, 45.1640, 15731.7430),         -- width
      d = jitter(i, 94.6730, 39871.2930),         -- depth: 0 near, 1 far
    }
  end

  self.ground = makeTexture(frame, "BACKGROUND", { .16, .40, .18, 1 }, 4)
  self.haze = makeTexture(frame, "BORDER", { 1, 1, 1, .32 }, 3)
  applyGradient(self.haze, "VERTICAL", 1, 1, 1, 0, 1, 1, 1, .5)

  -- One strip of textures per road segment, reused every frame.
  -- Built far-to-near: textures in the same layer draw in creation order, and
  -- with hills the nearer strip has to paint over the farther one or a crest
  -- will not hide the road behind it.
  self.strips = {}
  for i = SEGMENTS, 1, -1 do
    self.strips[i] = {
      -- Every one of these is drawn with WORLD-LOCKED texcoords (distance /
      -- tile-size), so at 1150m along a lap the V range is ~230..231 -- and a
      -- texcoord above 1 CLAMPS unless the texture was created with REPEAT
      -- wrapping. Without it the whole quad samples a single edge pixel: the
      -- road and grass art never tiled at all in game (the road only looked
      -- patterned because of the per-strip light/dark banding), and the tunnel
      -- walls sampled one pixel of rock, which is why covered sections had no
      -- walls in them. The offline preview blits with real tiling, which is why
      -- it has always looked better than the game it is supposed to mirror.
      grass = makeTexture(frame, "BACKGROUND", { .16, .40, .18, 1 }, 5, "grass.tga", true),
      road = makeTexture(frame, "ARTWORK", { .34, .34, .38, 1 }, 0, "road.tga", true),
      rumbleLeft = makeTexture(frame, "ARTWORK", { .90, .22, .18, 1 }, 1),
      rumbleRight = makeTexture(frame, "ARTWORK", { .90, .22, .18, 1 }, 1),
      lane = makeTexture(frame, "ARTWORK", { .95, .95, .95, 1 }, 2),
      -- Darkens toward both verges so the road reads as a lit solid rather
      -- than a flat cut-out.
      shade = makeTexture(frame, "ARTWORK", { 1, 1, 1, 1 }, 3, "roadshade.tga"),
      -- Covered sections. Hidden on open road, which is most of the time.
      -- Sublevel 7: ABOVE the full-screen surround fill at 6, so the converging
      -- portal still reads once you are properly under cover.
      wallLeft = makeTexture(frame, "BACKGROUND", { 1, 1, 1, 1 }, 7, "rock.tga", true),
      wallRight = makeTexture(frame, "BACKGROUND", { 1, 1, 1, 1 }, 7, "rock.tga", true),
      ceiling = makeTexture(frame, "BACKGROUND", { 1, 1, 1, 1 }, 7, "rock.tga", true),
    }
  end

  -- The alternate ribbon at a fork. Fewer strips than the main road because it
  -- is only ever drawn for the stretch between the split and the horizon.
  self.forkStrips = {}
  for i = FORK_SEGMENTS, 1, -1 do
    self.forkStrips[i] = {
      -- World-locked texcoords here too (see the main strips above), so this
      -- needs REPEAT wrapping or the branch road clamps to one pixel.
      road = makeTexture(frame, "ARTWORK", { .34, .34, .38, 1 }, 4, "road.tga", true),
      edgeLeft = makeTexture(frame, "ARTWORK", { 1, 1, 1, 1 }, 5),
      edgeRight = makeTexture(frame, "ARTWORK", { 1, 1, 1, 1 }, 5),
    }
  end
  -- The sign at the split. A fork you cannot see coming is just a wall.
  self.forkSign = makeTexture(frame, "OVERLAY", { 1, 1, 1, 1 }, 4, "forkleft.tga")
  self.forkSign:Hide()
  self.forkLabel = UI:NewText(frame, "", 15, AK.COLORS.lime, "CENTER")
  self.forkLabel:Hide()

  -- When the camera is inside a tunnel there is rock in every direction, not
  -- just the ribbon receding ahead. The per-band walls draw the portal from
  -- outside; these three fill the rest of the screen once you are through it.
  self.surround = {
    -- Sublevel 6: above the grass (5), below the per-band walls (7).
    left = makeTexture(frame, "BACKGROUND", { 1, 1, 1, 1 }, 6, "rock.tga", true),
    right = makeTexture(frame, "BACKGROUND", { 1, 1, 1, 1 }, 6, "rock.tga", true),
    top = makeTexture(frame, "BACKGROUND", { 1, 1, 1, 1 }, 6, "rock.tga", true),
  }
  for _, region in pairs(self.surround) do region:Hide() end

  -- Roadside props: the scenery that actually comes AT you.
  --
  -- The "trees" above are skyline decoration pinned to the horizon; they drift
  -- but never approach, which is why the world read as a painted backdrop. A
  -- kart racer sells speed with solid objects rushing past just outside the
  -- verge, at real parallax. That is what these are.
  self.props = {}
  for i = 1, PROPS do
    local prop = CreateFrame("Frame", nil, frame)
    prop.art = prop:CreateTexture(nil, "ARTWORK")
    prop.art:SetAllPoints()
    prop.shadow = prop:CreateTexture(nil, "BACKGROUND")
    prop.shadow:SetTexture(ART .. "shadow.tga")
    prop:Hide()
    self.props[i] = prop
  end

  -- Roadside marker posts. Regular objects rushing past the edge of frame are
  -- the strongest speed cue available; the road surface alone reads as static.
  self.posts = {}
  for i = 1, 24 do
    self.posts[i] = {
      left = makeTexture(frame, "ARTWORK", { 1, 1, 1, 1 }, 3),
      right = makeTexture(frame, "ARTWORK", { 1, 1, 1, 1 }, 3),
    }
  end

  -- Start/finish line: a checkered band plus an overhead gantry.
  self.finish = CreateFrame("Frame", nil, frame)
  self.finish:SetSize(1, 1)
  self.finish:Hide()
  self.finish.blocks = {}
  for i = 1, 28 do
    self.finish.blocks[i] = makeTexture(self.finish, "ARTWORK", { 1, 1, 1, 1 }, 4)
  end
  self.finish.leftPost = makeTexture(self.finish, "ARTWORK", { .82, .84, .90, 1 }, 5)
  self.finish.rightPost = makeTexture(self.finish, "ARTWORK", { .82, .84, .90, 1 }, 5)
  self.finish.banner = makeTexture(self.finish, "ARTWORK", { .10, .14, .22, 1 }, 5)
  self.finish.bannerEdge = makeTexture(self.finish, "OVERLAY", AK.COLORS.gold, 0)
  self.finish.label = UI:NewText(self.finish, "FINISH", 14, AK.COLORS.gold, "CENTER")
  self.finish.label:SetShadowColor(0, 0, 0, 1)
  self.finish.label:SetShadowOffset(1, -1)

  -- Roadside crowd. They are all Baine too, because of course they are.
  self.spectators = {}
  for i = 1, SPECTATOR_SLOTS do
    local seat = CreateFrame("Frame", nil, frame)
    seat:SetSize(60, 60)
    seat.model = AK.Model:New(seat, 60, 60, 0, 1)
    seat.model:SetAllPoints()
    self.spectators[i] = seat
  end

  self.speedLines = {}
  for i = 1, 22 do
    local line = makeGlow(frame, "OVERLAY", { .85, .95, 1, 1 }, 3)
    line:SetAlpha(0)
    self.speedLines[i] = line
  end

  -- Screen-space particle pool: drift sparks, boost embers, dust, impacts.
  self.particlePool = {}
  self.particles = {}
  for i = 1, PARTICLES do
    local particle = makeGlow(frame, "OVERLAY", { 1, 1, 1, 1 }, 4, "spark.tga")
    particle:Hide()
    self.particlePool[i] = particle
  end

  -- Weather layer. These persist and wrap rather than being spawned and killed,
  -- which keeps a steady downpour from thrashing the particle pool.
  self.weather = {}
  for i = 1, 90 do
    local drop = makeTexture(frame, "OVERLAY", { 1, 1, 1, 1 }, 2)
    drop:Hide()
    self.weather[i] = { texture = drop, x = 0, y = 0, speed = 0, sway = 0, size = 1 }
  end

  -- A single radial vignette reads far better than two gradient bands.
  self.vignette = makeTexture(frame, "OVERLAY", { 1, 1, 1, 1 }, 5, "vignette.tga")
  self.vignette:SetAllPoints()

  self.boostTint = makeWash(frame, "OVERLAY", { 1, .72, .25, 1 }, 6)
  self.boostTint:SetAllPoints()
  self.boostTint:SetAlpha(0)

  self.flash = makeTexture(frame, "OVERLAY", { 1, 1, 1, 0 }, 7)
  self.flash:SetAllPoints()
  self.flash:SetAlpha(0)

  -- Final-lap urgency: a gold pulse in the corners, on the last lap only.
  -- A full-screen wash, so it belongs on the race frame beside the vignette
  -- rather than on the HUD layer.
  self.urgency = makeTexture(frame, "OVERLAY", { 1, .82, .30, 1 }, 6, "vignette.tga")
  self.urgency:SetAllPoints()
  self.urgency:SetBlendMode("ADD")
  self.urgency:SetAlpha(0)

  -- Chequered flash at the line, built from alternating cells rather than art.
  self.checker = {}
  for i = 1, 24 do
    self.checker[i] = makeTexture(frame, "OVERLAY", { 1, 1, 1, 1 }, 7)
    self.checker[i]:Hide()
  end

  -- ---- HUD ---------------------------------------------------------------
  --
  -- Everything below hangs off self.hud, which is scaled as one piece by
  -- RaceUI:LayoutHud(). See the HUD table at the top of the file for why.
  self.hud = CreateFrame("Frame", nil, frame)
  self.hud:SetAllPoints()
  local hud = self.hud

  -- WHICH LAP -- top left. The lap you are on is the thing you glance at most
  -- and it used to be 15pt text buried in the middle of a bar of eight
  -- readouts, which is why nobody could find it.
  local lapPanel = UI:NewPanel(hud, HUD.lap.w, HUD.lap.h, HUD_PANEL)
  lapPanel:SetPoint(HUD.lap.point, HUD.lap.x, HUD.lap.y)
  self.headerPanel = lapPanel
  UI:NewText(lapPanel, "LAP", 12, AK.COLORS.gold, "LEFT"):SetPoint("TOPLEFT", 14, -9)
  self.lap = UI:NewText(lapPanel, "1 / 3", 27, { .95, .96, 1 }, "LEFT")
  self.lap:SetPoint("TOPLEFT", 52, -4)
  -- One pip per lap, filling as you complete them: the count in the abstract is
  -- a number to read, the pips are a progress bar you take in without reading.
  self.lapPips = {}
  for i = 1, 5 do
    local pip = makeTexture(lapPanel, "OVERLAY", { .25, .32, .42, 1 })
    pip:SetSize(30, 5)
    pip:SetPoint("BOTTOMLEFT", 14 + (i - 1) * 34, 11)
    self.lapPips[i] = pip
  end

  -- WHAT ITEM -- top centre, where Mario Kart has always put it, and big enough
  -- to read the icon in peripheral vision. It used to be a 120px box in the
  -- corner with the words "NO ITEM" printed in it, which is a form field.
  local itemPanel = UI:NewPanel(hud, HUD.item.w, HUD.item.h, HUD_PANEL)
  itemPanel:SetPoint(HUD.item.point, HUD.item.x, HUD.item.y)
  self.itemPanel = itemPanel
  self.itemGlow = makeWash(itemPanel, "BACKGROUND", { 1, .82, .25, 1 })
  self.itemGlow:SetPoint("TOPLEFT", 3, -3)
  self.itemGlow:SetPoint("BOTTOMRIGHT", -3, 3)
  self.itemGlow:SetAlpha(0)
  self.itemIcon = itemPanel:CreateTexture(nil, "ARTWORK")
  self.itemIcon:SetSize(ITEM_ICON, ITEM_ICON)
  self.itemIcon:SetPoint("CENTER", 0, 7)
  -- An empty slot is a dim empty frame, not a caption. The label carries the
  -- one thing an icon cannot: how many are left, and "FIRE!" when one is armed.
  self.itemLabel = UI:NewText(itemPanel, "", 12, AK.COLORS.muted, "CENTER")
  self.itemLabel:SetPoint("BOTTOMLEFT", 5, 9)
  self.itemLabel:SetPoint("BOTTOMRIGHT", -5, 9)

  -- THE CLOCK -- top right. Reference material: you look at it between corners,
  -- never during one, so it gets the corner furthest from the racing line.
  local clockPanel = UI:NewPanel(hud, HUD.clock.w, HUD.clock.h, HUD_PANEL)
  clockPanel:SetPoint(HUD.clock.point, HUD.clock.x, HUD.clock.y)
  self.clockPanel = clockPanel
  -- Three rows, all right-aligned off the same edge. Sharing one row between a
  -- left-aligned speed and a right-aligned split meant the two grew toward each
  -- other and, on a long lap time, straight through each other.
  self.timer = UI:NewText(clockPanel, "00:00.000", 22, { .95, .96, 1 }, "RIGHT")
  self.timer:SetPoint("TOPRIGHT", -14, -8)
  self.lapTime = UI:NewText(clockPanel, "", 11, AK.COLORS.muted, "RIGHT")
  self.lapTime:SetPoint("TOPRIGHT", -14, -38)
  self.speed = UI:NewText(clockPanel, "0 km/h", 13, AK.COLORS.lime, "RIGHT")
  self.speed:SetPoint("TOPRIGHT", -14, -56)

  -- WHAT PLACE -- bottom left, and by a wide margin the largest thing on the
  -- screen. This is the single most Mario Kart element there is and it was a
  -- 30pt string sharing a bar with the speedometer. No panel behind it: a plate
  -- reads as an addon window, where bare outlined type reads as a game. A soft
  -- dark halo does the legibility work a plate was doing.
  self.placeGlow = makeTexture(hud, "BACKGROUND", { 0, 0, 0, 1 }, 0, "glow.tga")
  self.placeGlow:SetSize(HUD.place.w, HUD.place.h)
  self.placeGlow:SetPoint("BOTTOMLEFT", HUD.place.x - 46, HUD.place.y - 34)
  self.placeGlow:SetAlpha(0.55)
  self.position = UI:NewText(hud, "1ST", 58, AK.COLORS.gold, "LEFT")
  self.position:SetPoint("BOTTOMLEFT", HUD.place.x, HUD.place.y + 20)
  self.position:SetShadowColor(0, 0, 0, 1)
  self.position:SetShadowOffset(2, -2)
  self.positionOf = UI:NewText(hud, "/ 8", 14, AK.COLORS.muted, "LEFT")
  self.positionOf:SetPoint("BOTTOMLEFT", HUD.place.x + 3, HUD.place.y)

  -- THE MAP -- bottom right, mirroring the place readout. It used to spend a
  -- fifth of its own height on a caption reading "TRACK MAP".
  self.minimapPanel = UI:NewPanel(hud, HUD.map.w, HUD.map.h, HUD_PANEL)
  self.minimap = self.minimapPanel
  self.minimap:SetPoint(HUD.map.point, HUD.map.x, HUD.map.y)
  self.mapRoute = {}
  for i = 1, 48 do
    local node = self.minimap:CreateTexture(nil, "ARTWORK")
    node:SetTexture("Interface\\Buttons\\WHITE8x8")
    node:SetVertexColor(.32, .44, .58, .95)
    node:SetSize(5, 5)
    self.mapRoute[i] = node
  end
  self.mapDots = {}
  for i = 1, AK.MAX_RACERS do
    local dot = self.minimap:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8x8")
    dot:SetSize(8, 8)
    self.mapDots[i] = dot
  end

  -- DRIFT CHARGE -- a thin bar low and centred, right under the kart, so it can
  -- be read without moving your eyes off the corner you are drifting through.
  -- It used to be a 260px plate with the words "DRIFT BOOST" printed across it
  -- at all times, and "RELEASE FOR BOOST" while charging: a tutorial pinned to
  -- the screen for the whole race. The bar shows the charge; the label now only
  -- names the tier you have actually banked, which is the part you cannot infer.
  local driftPanel = UI:NewPanel(hud, HUD.drift.w, HUD.drift.h, { .02, .04, .08, .78 })
  driftPanel:SetPoint(HUD.drift.point, HUD.drift.x, HUD.drift.y)
  self.driftPanel = driftPanel
  local driftInner = HUD.drift.h - 8
  self.driftFill = makeTexture(driftPanel, "ARTWORK", AK.COLORS.lime)
  self.driftFill:SetPoint("LEFT", 4, 0)
  self.driftFill:SetHeight(driftInner)
  self.driftFill:SetWidth(0)
  self.driftGlow = makeWash(driftPanel, "ARTWORK", { 1, 1, 1, 1 }, 1)
  self.driftGlow:SetPoint("LEFT", 4, 0)
  self.driftGlow:SetHeight(driftInner)
  self.driftGlow:SetWidth(0)
  self.driftGlow:SetAlpha(0)
  self.driftLabel = UI:NewText(driftPanel, "", 13, AK.COLORS.gold, "CENTER")
  self.driftLabel:SetPoint("BOTTOM", driftPanel, "TOP", 0, 5)
  -- Ticks at the three tier thresholds, so the bar reads as a ladder with rungs
  -- rather than as a bar that changes colour for reasons.
  self.driftTicks = {}
  for i, stage in ipairs(DRIFT_TICKS) do
    local tick = makeTexture(driftPanel, "OVERLAY", { .08, .13, .20, 1 })
    tick:SetSize(2, driftInner)
    tick:SetPoint("LEFT", 4 + DRIFT_TRACK * stage, 0)
    self.driftTicks[i] = tick
  end

  -- Surface and effect state, stacked under the place readout rather than over
  -- the middle of the road. Centred above the drift meter it landed squarely on
  -- the player's own kart, and the bigger the client the worse it got: the kart
  -- is drawn in world space and grows with the resolution, so at 1440p "TURBO!"
  -- was printed across the driver. Bottom left is empty, and the eye is already
  -- there reading the position.
  self.status = UI:NewText(hud, "", 15, AK.COLORS.muted, "LEFT")
  self.status:SetPoint("BOTTOMLEFT", HUD.place.x + 3, HUD.place.y - 26)

  -- Track identity, tucked under the lap block rather than centred in the road.
  self.trackName = UI:NewText(hud, "", 13, { .72, .62, .40 }, "LEFT")
  self.trackName:SetPoint("TOPLEFT", lapPanel, "BOTTOMLEFT", 3, -7)
  -- The shortcut blurb, under the item box. It is race-start onboarding -- it
  -- fades out once you are driving -- so it belongs where you are looking
  -- before the lights go out, not across the bottom of the road.
  --
  -- Width-bounded, whatever else moves. Centred on the drift meter with no
  -- width set, it grew outward from its anchor until it ran under the BRAKE and
  -- GAS buttons flanking the meter, and Netherstorm's "SHORTCUT: Blink through
  -- a portal at maximum speed" was cut off mid-word. A fontstring with no width
  -- has no reason to stop.
  self.shortcut = UI:NewText(hud, "", 12, { .9, .92, 1 }, "CENTER")
  self.shortcut:SetPoint("TOP", itemPanel, "BOTTOM", 0, -10)
  self.shortcut:SetWidth(HUD_DESIGN_W * 0.44)
  -- Announcements sat at -250, which is exactly where the player's own kart is
  -- drawn -- and a model frame paints over its parent's fontstrings, so every
  -- "ITEM ACQUIRED" and "BOOST!" was rendering behind the driver. They now live
  -- in a layer above every model, high on screen where nothing can cover them.
  -- A child of the SCALED container, so the countdown, the lap banners and the
  -- FINISHED card are the same size relative to the screen as everything else.
  -- Frame level is absolute within a strata, so the explicit level below still
  -- puts it above the field regardless of who its parent is.
  self.hudLayer = CreateFrame("Frame", nil, hud)
  self.hudLayer:SetAllPoints()
  -- Above the whole depth-sorted field, which tops out at +382.
  self.hudLayer:SetFrameLevel(frame:GetFrameLevel() + 420)

  -- ---- presentation layer ----------------------------------------------
  --
  -- The race had no orchestrated moments: the countdown, the start, the final
  -- lap and the finish were all the same line of centred text. These are the
  -- beats that make a lap feel like an event. They sit on the HUD layer, are
  -- sized from the screen every frame rather than in fixed pixels, and drive
  -- the existing Announce/Flash/Shake plumbing instead of duplicating it.
  --
  -- Start gantry: three lamps that light one per countdown tick and go green
  -- together on GO. A countdown you can SEE beats a number you have to read.
  self.startLights = CreateFrame("Frame", nil, self.hudLayer)
  self.startLights:Hide()
  self.startLights.bar = makeTexture(self.startLights, "ARTWORK", { .06, .07, .10, .95 }, 0)
  self.startLights.bar:SetAllPoints()
  self.startLights.lamps = {}
  for i = 1, 3 do
    self.startLights.lamps[i] = makeGlow(self.startLights, "OVERLAY", { 1, .22, .18, 1 }, i)
  end

  -- Lap split against your best, shown for a couple of seconds on each cross.
  self.splitText = UI:NewText(self.hudLayer, "", 20, AK.COLORS.lime, "CENTER")
  self.splitText:SetShadowColor(0, 0, 0, 1)
  self.splitText:SetShadowOffset(1, -1)
  self.splitText:SetAlpha(0)

  -- "FINISHED 2ND", held long enough to land before the results screen.
  self.finishCard = UI:NewText(self.hudLayer, "", 40, AK.COLORS.gold, "CENTER")
  self.finishCard:SetShadowColor(0, 0, 0, 1)
  self.finishCard:SetShadowOffset(2, -2)
  self.finishCard:SetAlpha(0)

  self.wrongWay = UI:NewText(self.hudLayer, "", 30, AK.COLORS.danger, "CENTER")
  self.wrongWay:SetShadowColor(0, 0, 0, 1)
  self.wrongWay:SetShadowOffset(2, -2)
  self.wrongWay:SetAlpha(0)

  -- Names the beat currently playing during /kart beats. It has to be on
  -- screen: the race frame eats keyboard input, so the chat window is behind
  -- the race and unreadable exactly when this matters.
  self.beatLabel = UI:NewText(self.hudLayer, "", 15, AK.COLORS.blue, "CENTER")
  self.beatLabel:SetShadowColor(0, 0, 0, 1)
  self.beatLabel:SetShadowOffset(1, -1)
  self.beatLabel:SetAlpha(0)
  self.spinyWarn = UI:NewText(self.hudLayer, "", 26, AK.COLORS.danger, "CENTER")
  self.spinyWarn:SetShadowColor(0, 0, 0, 1)
  self.spinyWarn:SetShadowOffset(2, -2)
  self.spinyWarn:SetAlpha(0)

  self.noticePlate = makeTexture(self.hudLayer, "BACKGROUND", { 0, 0, 0, .55 })
  self.noticePlate:SetPoint("CENTER", self.hudLayer, "CENTER", 0, 258)
  self.noticePlate:Hide()
  self.noticeEdge = makeTexture(self.hudLayer, "BORDER", AK.COLORS.gold)
  self.noticeEdge:SetPoint("TOP", self.noticePlate, "BOTTOM", 0, 0)
  self.noticeEdge:Hide()
  self.notice = UI:NewText(self.hudLayer, "", 30, AK.COLORS.gold, "CENTER")
  self.notice:SetPoint("CENTER", 0, 258)
  self.notice:SetShadowColor(0, 0, 0, 1)
  self.notice:SetShadowOffset(2, -2)
  -- Item icon that pops alongside the banner when something is used.
  self.noticeIcon = self.hudLayer:CreateTexture(nil, "ARTWORK")
  self.noticeIcon:SetPoint("RIGHT", self.notice, "LEFT", -12, 0)
  self.noticeIcon:Hide()
  self.countdown = UI:NewText(frame, "", 74, AK.COLORS.gold, "CENTER")
  self.countdown:SetPoint("CENTER", 0, 40)
  self.countdown:SetShadowColor(0, 0, 0, 1)
  self.countdown:SetShadowOffset(3, -3)

  -- Starting lights. Three reds arm one per second, then all snap green on GO.
  self.lights = {}
  self.lightRig = UI:NewPanel(frame, 214, 62, { .02, .03, .06, .92 })
  self.lightRig:SetPoint("CENTER", 0, 150)
  self.lightRig:Hide()
  for i = 1, 3 do
    local housing = makeTexture(self.lightRig, "ARTWORK", { .06, .07, .10, 1 })
    housing:SetSize(54, 44)
    housing:SetPoint("LEFT", 10 + (i - 1) * 66, 0)
    local lamp = makeTexture(self.lightRig, "OVERLAY", { .16, .05, .05, 1 }, 1)
    lamp:SetSize(42, 32)
    lamp:SetPoint("CENTER", housing, "CENTER")
    local halo = makeGlow(self.lightRig, "OVERLAY", { 1, .2, .15, 1 }, 2)
    halo:SetSize(74, 60)
    halo:SetPoint("CENTER", housing, "CENTER")
    halo:SetAlpha(0)
    self.lights[i] = { lamp = lamp, halo = halo }
  end

  -- Name tags live in their own frame above every kart. A PlayerModel is a
  -- child frame, and child frames always draw over their parent's layers, so a
  -- tag parented to the kart is painted over by that kart's own model.
  self.tagLayer = CreateFrame("Frame", nil, frame)
  self.tagLayer:SetAllPoints()
  self.tagLayer:SetFrameLevel(frame:GetFrameLevel() + 400)

  self.karts = {}
  for i = 1, AK.MAX_RACERS do
    local kart = CreateFrame("Frame", nil, frame)
    kart:SetSize(42, 42)
    kart.shadow = makeTexture(kart, "BACKGROUND", { 0, 0, 0, .55 }, 0, "shadow.tga")
    kart.shadow:SetPoint("BOTTOM", 0, 0)
    kart.trail = makeGlow(kart, "BACKGROUND", { 1, .7, .2, 1 }, 1)
    kart.trail:SetPoint("BOTTOM", kart, "BOTTOM", 0, 0)
    kart.trail:SetAlpha(0)
    kart.flame = makeGlow(kart, "ARTWORK", { 1, .52, .12, 1 }, 0)
    kart.flame:SetPoint("TOP", kart, "BOTTOM", 0, 8)
    kart.flame:SetAlpha(0)
    -- Drift sparks, one per rear wheel. These live ON the kart rather than only
    -- in the HUD meter: the meter is at the bottom of the screen and the corner
    -- is not, so a ladder you can only read by looking away is a ladder nobody
    -- reads. Additive, so they light the road rather than sitting on it.
    kart.sparkL = makeGlow(kart, "OVERLAY", { 1, 1, 1, 1 }, 1, "spark.tga")
    kart.sparkR = makeGlow(kart, "OVERLAY", { 1, 1, 1, 1 }, 1, "spark.tga")
    kart.sparkL:SetAlpha(0)
    kart.sparkR:SetAlpha(0)
    -- Seated racer, seen from behind since the camera chases the field.
    kart.model = AK.Model:New(kart, 72, 72, math.pi, 1)
    -- The kart is drawn in two passes. The whole thing sits BEHIND the driver
    -- (so nothing hides them -- putting the full chassis in front buried every
    -- racer from the waist up), and only the bottom slice, the wheels and
    -- bumper, is repeated in front of their legs. That is what sells sitting in
    -- it without covering the person.
    kart.body = makeTexture(kart, "ARTWORK", { .5, .5, .5, 1 }, 1, "kart.tga")
    kart.body:SetPoint("BOTTOM", 0, 0)
    kart.chassis = CreateFrame("Frame", nil, kart)
    kart.chassis:SetAllPoints()
    kart.lip = makeTexture(kart.chassis, "ARTWORK", { .5, .5, .5, 1 }, 1, "kart.tga")
    kart.lip:SetPoint("BOTTOM", 0, 0)
    kart.icon = kart:CreateTexture(nil, "OVERLAY")
    kart.icon:SetPoint("CENTER", 0, 1)
    -- Item trailing behind the kart, deployed but not yet fired. It doubles as
    -- a shield, so it has to be visible to be a readable decision.
    kart.heldGlow = makeGlow(kart, "BACKGROUND", { 1, 1, 1, 1 }, 2)
    kart.heldGlow:Hide()
    kart.heldIcon = kart:CreateTexture(nil, "ARTWORK", nil, 0)
    kart.heldIcon:Hide()
    kart.tag = UI:NewText(self.tagLayer, "", 11, { 1, 1, 1 }, "CENTER")
    kart.tag:SetShadowColor(0, 0, 0, 1)
    kart.tag:SetShadowOffset(1, -1)
    kart.tagPlate = makeTexture(self.tagLayer, "ARTWORK", { 0, 0, 0, .55 })
    kart.tagPlate:SetPoint("CENTER", kart.tag, "CENTER", 0, 0)
    -- Battle marker: appears over a rival who has been in your pocket for more
    -- than a moment, so a fight for position is legible before it costs you.
    kart.warn = UI:NewText(self.tagLayer, "", 22, AK.COLORS.danger, "CENTER")
    kart.warn:SetShadowColor(0, 0, 0, 1)
    kart.warn:SetShadowOffset(1, -1)
    kart.warn:SetAlpha(0)
    self.karts[i] = kart
  end

  -- One-shot effect sprites: launch flashes, shockwaves, impact stars. These
  -- are what make an item read as *fired* rather than as a silent stat change.
  self.effectPool = {}
  self.effects = {}
  for i = 1, 20 do
    local fx = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    fx:SetBlendMode("ADD")
    fx:Hide()
    self.effectPool[i] = fx
  end

  -- Live power-ups in the world: shells, bananas, bombs.
  self.projectileFrames = {}
  for i = 1, 14 do
    local shot = CreateFrame("Frame", nil, frame)
    shot:SetSize(30, 30)
    shot.glow = makeGlow(shot, "BACKGROUND", { 1, 1, 1, 1 })
    shot.glow:SetPoint("CENTER")
    shot.shadow = makeTexture(shot, "BACKGROUND", { 0, 0, 0, .5 }, 1, "shadow.tga")
    shot.shadow:SetPoint("BOTTOM", 0, -2)
    shot.icon = shot:CreateTexture(nil, "ARTWORK")
    shot.icon:SetAllPoints()
    self.projectileFrames[i] = shot
  end

  -- Course hazards. Red so they can never be mistaken for a pickup.
  self.hazardFrames = {}
  for i = 1, 12 do
    local hz = CreateFrame("Frame", nil, frame)
    hz:SetSize(30, 30)
    -- Contact shadow. Anchored to the RACE frame each tick rather than to this
    -- one, so it stays welded to the road while the hazard above it moves.
    hz.shadow = makeTexture(hz, "BACKGROUND", { 0, 0, 0, .5 }, -3, "shadow.tga")
    hz.glow = makeGlow(hz, "BACKGROUND", { 1, .32, .18, 1 })
    hz.glow:SetPoint("BOTTOM", 0, 0)
    hz.icon = hz:CreateTexture(nil, "ARTWORK")
    hz.icon:SetTexture("Interface\\Icons\\Spell_Fire_SelfDestruct")
    hz.icon:SetPoint("BOTTOM", 0, 0)
    -- A hazard you can identify at a glance is one you can plan around; a red
    -- fire icon is just an abstract "bad". Creature hazards get the actual
    -- creature, and the icon stays as the fallback for anything that has no
    -- model or whose id does not resolve on this client.
    hz.model = CreateFrame("PlayerModel", nil, hz)
    hz.model:SetPoint("CENTER", hz, "CENTER")
    hz.model:Hide()
    hz.label = UI:NewText(hz, "", 11, { 1, .5, .35 }, "CENTER")
    hz.label:SetPoint("BOTTOM", hz, "TOP", 0, 2)
    hz.label:SetShadowColor(0, 0, 0, 1)
    hz.label:SetShadowOffset(1, -1)
    hz:Hide()
    self.hazardFrames[i] = hz
  end

  -- Ghost kart: a sprite only, no model, so it costs nothing and can never be
  -- mistaken for a live racer.
  self.ghostKart = CreateFrame("Frame", nil, frame)
  self.ghostKart:SetSize(40, 40)
  self.ghostKart:Hide()
  self.ghostBody = makeTexture(self.ghostKart, "ARTWORK", { .55, .85, 1, 1 }, 1, "kart.tga")
  self.ghostBody:SetPoint("BOTTOM", 0, 0)

  self.objectFrames = {}
  for i = 1, 16 do
    local object = CreateFrame("Frame", nil, frame)
    object:SetSize(30, 30)
    -- Contact shadow, and the single biggest reason these read as objects in
    -- the world rather than icons pasted on the picture. It is anchored to the
    -- RACE frame every tick, not to this frame, so an item box can bob while
    -- its shadow stays pinned to the tarmac -- that contrast is what sells the
    -- height. A sprite with no shadow always hovers.
    object.shadow = makeTexture(object, "BACKGROUND", { 0, 0, 0, .5 }, -3, "shadow.tga")
    object.pad = makeGlow(object, "BACKGROUND", { 1, .82, .25, 1 }, 0)
    object.pad:SetPoint("BOTTOM", 0, 0)
    object.beam = makeGlow(object, "BORDER", { 1, .82, .25, 1 })
    object.beam:SetPoint("BOTTOM", 0, 0)
    object.icon = object:CreateTexture(nil, "ARTWORK")
    object.icon:SetPoint("BOTTOM", 0, 0)
    object.ring = makeGlow(object, "OVERLAY", { 1, 1, 1, 1 })
    object.ring:SetPoint("BOTTOM", 0, 0)
    object.label = UI:NewText(object, "", 11, { 1, 1, 1 }, "CENTER")
    object.label:SetPoint("BOTTOM", object, "TOP", 0, 2)
    object.label:SetShadowColor(0, 0, 0, 1)
    object.label:SetShadowOffset(1, -1)
    self.objectFrames[i] = object
  end

  -- Grouped in one frame so the whole control bar can be hidden at once. On the
  -- scaled HUD container, so the row is the same fraction of the screen at any
  -- resolution -- it used to span a fixed 816px, which simply does not fit on a
  -- 800-wide window.
  self.controlBar = CreateFrame("Frame", nil, hud)
  self.controlBar:SetAllPoints()
  -- 52px could not fit "BRAKE" or "RIGHT" at the button font, so the two most
  -- important controls on screen read "BRA..." and "RIG...". Wider, with a
  -- slightly smaller label, and the spacing opened to match so nothing touches.
  local CTRL_W, CTRL_GAP = 68, 6
  local function control(text, x, down, up)
    local button = UI:NewButton(self.controlBar, text, CTRL_W, HUD.controls.h, function() end)
    button.label:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    button:SetPoint("BOTTOM", x, HUD.controls.y)
    button:SetScript("OnMouseDown", down)
    button:SetScript("OnMouseUp", up or function() end)
    return button
  end
  -- Steering on the left hand, throttle and actions on the right, mirroring the
  -- keyboard layout. There was previously no on-screen throttle at all, so a
  -- player driving with the mouse simply could not move.
  --
  -- The two clusters are now mirrored about the centre and derived from the
  -- row's own width, so the drift meter sits in the gap between them instead of
  -- the row being two hand-placed groups with a 490px hole in the middle.
  local edge = HUD.controls.w * 0.5 - CTRL_W * 0.5
  local pitch = CTRL_W + CTRL_GAP
  control("LEFT", -edge, function() AK.Race:SetControl("left", true) end, function() AK.Race:SetControl("left", false) end)
  control("RIGHT", -edge + pitch, function() AK.Race:SetControl("right", true) end, function() AK.Race:SetControl("right", false) end)
  local brake = control("BRAKE", edge - pitch * 3, function() AK.Race:SetControl("brake", true) end, function() AK.Race:SetControl("brake", false) end)
  brake:SetRestStyle({ .26, .10, .10, .95 }, AK.COLORS.danger)
  local gas = control("GAS", edge - pitch * 2, function() AK.Race:SetControl("accelerate", true) end, function() AK.Race:SetControl("accelerate", false) end)
  gas:SetRestStyle({ .10, .24, .12, .95 }, AK.COLORS.lime)
  control("DRIFT", edge - pitch, function() AK.Race:SetControl("drift", true) end, function() AK.Race:SetControl("drift", false) end)
  control("ITEM", edge, function() AK.Race:UseItem() end)

  -- The name of the corner you are in. Rally-style, and the cheapest possible
  -- way to turn a sequence of bends into a place with landmarks you remember.
  -- Stacked UNDER the track name rather than pinned 86px from the top edge.
  -- That fixed offset took no account of the header's height, so the corner
  -- callout and the track name -- both gold, both centred -- were drawn on top
  -- of each other every time a corner was entered.
  self.sectionLabel = UI:NewText(self.hudLayer, "", 17, AK.COLORS.gold, "LEFT")
  self.sectionLabel:SetPoint("TOPLEFT", self.trackName, "BOTTOMLEFT", 0, -4)
  self.sectionLabel:SetShadowColor(0, 0, 0, 1)
  self.sectionLabel:SetShadowOffset(1, -1)

  -- A legend, because every control above also has a key and none of them were
  -- discoverable. Sits under the buttons so it never covers the road.
  self.controlHint = UI:NewText(self.controlBar,
    "W / UP  GAS      S / DOWN  BRAKE      A D  or  LEFT RIGHT  STEER      "
    .. "SPACE  DRIFT      SHIFT  ITEM      ESC  PAUSE", 11, AK.COLORS.muted, "CENTER")
  self.controlHint:SetPoint("BOTTOM", 0, 8)

  -- Always-visible exit. The race frame swallows keyboard input, so a mouse
  -- route out has to exist no matter what state the simulation is in.
  local quit = UI:NewButton(hud, "QUIT", HUD.quit.w, HUD.quit.h, function() AK.Race:Stop(true) end)
  quit:SetPoint(HUD.quit.point, HUD.quit.x, HUD.quit.y)
  quit:SetRestStyle({ .28, .09, .09, .95 }, AK.COLORS.danger)
  -- TUNE, BEATS and AI used to be a column of buttons stacked down the right
  -- edge for the whole race -- three developer tools permanently occupying the
  -- screen you are trying to look through. They live on the pause panel now,
  -- which is one key away and is where you go when you are not driving.
  self.raceButtons = {}
  local pause = CreateFrame("Frame", nil, frame)
  pause:SetAllPoints()
  -- Above the karts, which climb to +308 for depth sorting.
  pause:SetFrameLevel(frame:GetFrameLevel() + 500)
  pause:Hide()
  self.pause = pause
  local dim = makeTexture(pause, "BACKGROUND", { 0, 0, 0, .6 })
  dim:SetAllPoints()
  local pausePanel = UI:NewPanel(pause, 320, 254, { .045, .075, .125, .98 })
  pausePanel:SetPoint("CENTER", 0, -30)
  local pauseTitle = UI:NewText(pausePanel, "PAUSED", 28, AK.COLORS.gold, "CENTER")
  pauseTitle:SetPoint("TOP", 0, -22)
  local resume = UI:NewButton(pausePanel, "RESUME", 240, 40, function() AK.Race:TogglePause() end)
  resume:SetPoint("TOP", 0, -75)
  local abandon = UI:NewButton(pausePanel, "QUIT TO MENU", 240, 40, function() AK.Race:Stop(true) end)
  abandon:SetPoint("TOP", 0, -123)
  abandon:SetRestStyle({ .28, .09, .09, .95 }, AK.COLORS.danger)
  -- The race tools, rehomed off the racing screen. They can only be judged
  -- while the race frame is up -- the frame swallows keyboard input, so there
  -- is no chat line to type a slash command into -- but that is an argument for
  -- them being reachable, not for them sitting on the track for the whole race.
  local tools = {
    { "TUNE", function() AK.Workshop:Toggle() end,
      "Camera, feel, audio and difficulty, live, while the race runs." },
    { "BEATS", function() self:PlayBeats() end,
      "Play every race moment in sequence -- start lights, splits, final lap, finish -- so they can be seen and screenshotted on demand." },
    { "AI", function() AK.AI:Report() end,
      "Live AI telemetry: drifts, braking, mistakes and catch-up assistance, per opponent." },
  }
  for i, entry in ipairs(tools) do
    local tool = UI:NewButton(pausePanel, entry[1], 76, 28, entry[2])
    tool:SetPoint("TOP", (i - 2) * 80, -175)
    tool.tooltip = entry[3]
  end

  self:LayoutHud()
  -- The race frame is pinned to UIParent, so this fires whenever the client is
  -- resized or the master UI scale changes -- the two things that used to leave
  -- the HUD at the wrong size until a reload.
  frame:SetScript("OnSizeChanged", function() RaceUI:LayoutHud() end)

  frame:SetScript("OnKeyDown", function(_, key) AK.Race:OnKey(key, true) end)
  frame:SetScript("OnKeyUp", function(_, key) AK.Race:OnKey(key, false) end)
  -- Release the keyboard grab whenever the frame goes away, including on error.
  frame:SetScript("OnHide", function(self)
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
  end)
  frame:SetScript("OnShow", function(self)
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
  end)
end

-- Per-track distant terrain. Heights are fractions of SCREEN height -- the
-- skyline used to be sized in absolute pixels, tuned against a 1280-wide
-- preview, which is why it shrank to a row of specks on larger clients.
-- `float` lifts the ridge off the horizon: Netherstorm's islands hang in the
-- void. `treeArt`/`treeTint` restyle the near wall so a volcanic waste is not
-- ringed by the same green conifers as a summer forest.
local SKYLINE = {
  oribos        = {},
  elwynn        = { mtn = { h = .12, tint = { .55, .64, .80 }, a = .85 }, hill = { h = .085, tint = { .34, .52, .30 } } },
  durotar       = { mtn = { h = .19, tint = { .60, .32, .22 }, a = .95 }, hill = { h = .07, tint = { .50, .30, .17 } },
                    treeTint = { 1.0, .60, .34 } },
  stranglethorn = { mtn = { h = .11, tint = { .38, .54, .52 }, a = .80 }, hill = { h = .10, tint = { .16, .36, .25 } },
                    treeTint = { .55, 1.0, .62 } },
  ironforge     = { mtn = { h = .22, tint = { .80, .87, .97 }, a = 1.0 }, hill = { h = .08, tint = { .60, .70, .83 } },
                    treeTint = { .70, .82, 1.0 } },
  deadmines     = { mtn = { h = .10, tint = { .20, .24, .40 }, a = .90 }, hill = { h = .06, tint = { .15, .19, .30 } },
                    treeTint = { .48, .55, .85 } },
  netherstorm   = { mtn = { h = .15, tint = { .52, .33, .72 }, a = .90, float = .05 },
                    treeArt = "shard.tga", treeTint = { .80, .55, 1.15 } },
}

--- Re-anchor everything pinned to the horizon. Called whenever the tuned
--- horizon moves, which is the one value that changes static layout.
--- Fit the whole HUD to the screen.
---
--- One SetScale on one container, rather than a screen fraction threaded
--- through fifty offsets. The container is pinned to UIParent, so scaling it
--- leaves its corners on the screen's corners and grows everything anchored to
--- them -- which is exactly the behaviour wanted and exactly what a per-widget
--- rewrite would have had to reimplement by hand.
---
--- Clamped at both ends: below ~0.6 the type stops being legible at all, and
--- above ~1.7 the HUD starts eating the road on an ultrawide, where the height
--- is the binding constraint and the extra width should become view, not chrome.
function RaceUI:LayoutHud()
  if not self.hud then return end
  local frame = self.frame
  local width, height = frame:GetWidth(), frame:GetHeight()
  if not width or width <= 0 or not height or height <= 0 then return end
  local fit = math.min(width / HUD_DESIGN_W, height / HUD_DESIGN_H)
  local dial = (self.T and self.T.hudScale or 100) / 100
  self.hudFit = AK.Math.Clamp(fit, 0.60, 1.70) * AK.Math.Clamp(dial, 0.5, 2.0)
  self.hud:SetScale(self.hudFit)
end

function RaceUI:LayoutHorizon(horizon)
  self.appliedHorizon = horizon
  local frame = self.frame
  local screenH = frame:GetHeight()
  self.sky:ClearAllPoints()
  self.sky:SetPoint("TOPLEFT")
  self.sky:SetPoint("BOTTOMRIGHT", frame, "RIGHT", 0, horizon)
  self.skyGlow:ClearAllPoints()
  self.skyGlow:SetPoint("BOTTOMLEFT", frame, "LEFT", 0, horizon - 4)
  self.skyGlow:SetPoint("TOPRIGHT", frame, "RIGHT", 0, horizon + screenH * 0.17)
  self.ground:ClearAllPoints()
  self.ground:SetPoint("TOPLEFT", frame, "LEFT", 0, horizon)
  self.ground:SetPoint("BOTTOMRIGHT")
  -- Tall and faint: a narrow opaque band reads as a purple stripe painted
  -- across the sky rather than as atmosphere. Scaled with the screen so it
  -- stays atmosphere at any resolution.
  self.haze:ClearAllPoints()
  self.haze:SetPoint("BOTTOMLEFT", frame, "LEFT", 0, horizon - screenH * 0.12)
  self.haze:SetPoint("TOPRIGHT", frame, "RIGHT", 0, horizon + screenH * 0.02)
end

--- Sky, horizon glow and weather are per-track, so a night circuit reads as
--- night rather than as a day track with a dark sky pasted above it.
function RaceUI:ApplyTrackPalette(track)
  local top = track.skyTop or { 0.24, 0.46, 0.82 }
  local low = track.skyLow or { 0.72, 0.86, 0.97 }
  local glow = track.glow or { 1.00, 0.93, 0.72 }
  applyGradient(self.sky, "VERTICAL", low[1], low[2], low[3], 1, top[1], top[2], top[3], 1)
  -- Strongest AT the horizon, fading upward. This was inverted -- strongest at
  -- the band's top edge with a hard cutoff -- which painted a grey stripe
  -- floating in the sky above the mountains in every daytime video frame.
  applyGradient(self.skyGlow, "VERTICAL", glow[1], glow[2], glow[3], .45, glow[1], glow[2], glow[3], 0)
  self.light = track.light or 1
  self.weatherKind = track.weather or "none"
  self.style = track.style

  -- Distant terrain layers and the near wall's art, all per track.
  self.skyline = SKYLINE[track.id] or {}
  local treeArt = track.style == "oribos" and "spire.tga" or self.skyline.treeArt or "tree.tga"
  for _, tree in ipairs(self.trees) do
    tree:SetTexture(ART .. treeArt)
  end

  -- Anchor the ridge layers for this track. Parallax happens through texture
  -- coordinates in RenderSky, so the quads themselves never move.
  local frame = self.frame
  local screenH = frame:GetHeight()
  local horizon = self.T.horizon
  local function placeRidge(texture, cfg)
    if not cfg then texture:Hide() return end
    local lift = screenH * (cfg.float or 0)
    texture:ClearAllPoints()
    texture:SetPoint("BOTTOMLEFT", frame, "LEFT", 0, horizon + lift)
    texture:SetPoint("BOTTOMRIGHT", frame, "RIGHT", 0, horizon + lift)
    texture:SetHeight(screenH * cfg.h)
    texture:Show()
  end
  placeRidge(self.mountain, self.skyline.mtn)
  placeRidge(self.hillLine, self.skyline.hill)

  local conduit = track.style == "oribos"
  for _, strip in ipairs(self.strips) do
    strip.rumbleLeft:SetTexture(conduit and (ART .. "glow.tga") or SOLID)
    strip.rumbleRight:SetTexture(conduit and (ART .. "glow.tga") or SOLID)
    strip.rumbleLeft:SetBlendMode(conduit and "ADD" or "BLEND")
    strip.rumbleRight:SetBlendMode(conduit and "ADD" or "BLEND")
  end

  -- Seed the weather field across the whole screen so it is already falling
  -- when the countdown starts, rather than sweeping in from the top edge.
  local kind = self.weatherKind
  for _, drop in ipairs(self.weather) do
    if kind == "none" then
      drop.texture:Hide()
    else
      drop.x = (math.random() - .5) * self.halfWidth * 2.4
      drop.y = (math.random() - .5) * self.halfHeight * 2.4
      drop.phase = math.random() * math.pi * 2
      if kind == "rain" then
        drop.speed = -900 - math.random() * 500
        drop.size, drop.sway = 1.6, 0
        -- Reset the texture each time: a track switch must not inherit the
        -- previous weather's art.
        drop.texture:SetTexture(SOLID)
        drop.texture:SetSize(1.6, 22 + math.random() * 16)
        drop.texture:SetVertexColor(.62, .74, .92, 1)
        drop.texture:SetAlpha(.34)
        drop.texture:SetBlendMode("BLEND")
      elseif kind == "snow" then
        drop.speed = -70 - math.random() * 70
        drop.sway = 24 + math.random() * 34
        local size = 4 + math.random() * 6
        drop.texture:SetTexture(ART .. "spark.tga")
        drop.texture:SetSize(size, size)
        drop.texture:SetVertexColor(1, 1, 1, 1)
        drop.texture:SetAlpha(.6 + math.random() * .35)
        drop.texture:SetBlendMode("BLEND")
      else -- ember
        drop.speed = 46 + math.random() * 90
        drop.sway = 16 + math.random() * 26
        -- Soft and dim: hard bright dots read as dust on the monitor.
        local size = 4 + math.random() * 7
        drop.texture:SetTexture(ART .. "spark.tga")
        drop.texture:SetSize(size, size)
        drop.texture:SetVertexColor(1, .58 + math.random() * .3, .22, 1)
        drop.texture:SetAlpha(.18 + math.random() * .22)
        drop.texture:SetBlendMode("ADD")
      end
      drop.texture:Show()
    end
  end
end

--- Weather wraps around the viewport instead of respawning, so the field stays
--- constant density no matter how long the race runs.
function RaceUI:RenderWeather(race, dt)
  if self.weatherKind == "none" or AK.db.settings.reducedEffects then return end
  local limitX, limitY = self.halfWidth * 1.2, self.halfHeight * 1.2
  -- Density is a tuning value, so the field is thinned by hiding drops rather
  -- than by rebuilding the pool.
  local amount = self.T.weatherAmount
  local visible = math.floor(#self.weather * math.min(1, amount))
  for index, drop in ipairs(self.weather) do
    drop.texture:SetShown(index <= visible)
  end
  for _, drop in ipairs(self.weather) do
    drop.phase = drop.phase + dt * 2.2
    drop.y = drop.y + drop.speed * dt
    drop.x = drop.x + math.sin(drop.phase) * drop.sway * dt
    if drop.y < -limitY then
      drop.y = limitY
      drop.x = (math.random() - .5) * limitX * 2
    elseif drop.y > limitY then
      drop.y = -limitY
      drop.x = (math.random() - .5) * limitX * 2
    end
    if drop.x < -limitX then drop.x = limitX elseif drop.x > limitX then drop.x = -limitX end
    drop.texture:ClearAllPoints()
    drop.texture:SetPoint("CENTER", self.frame, "CENTER", drop.x, drop.y)
  end
end

function RaceUI:Show(race)
  self:Build()
  -- The race itself decides whether models run, rather than a sticky toggle
  -- that some other path is trusted to reset. Only the attract demo goes
  -- sprites-only, and a single missed restore used to leave every racer as a
  -- flat icon for the rest of the session.
  self:SetModelsEnabled(race.mode ~= "attract")
  self.T = AK.db.tuning
  self.frame:SetScale(AK.db.settings.uiScale or 1)
  self.halfWidth = self.frame:GetWidth() * .5
  self.halfHeight = self.frame:GetHeight() * .5
  self.camDepth = self.T.camDepth
  self.shake, self.shakeX, self.shakeY = 0, 0, 0
  -- Every presentation deadline is stored in race time, so starting a race
  -- resets the clock underneath any beat still counting down from the last one
  -- and it can never expire. Clear them before the new race's clock begins.
  self:ClearPresentation()
  -- Hand live particles back before clearing, or their textures stay visible
  -- and are lost to the pool for the rest of the session.
  for _, particle in ipairs(self.particles) do
    particle.texture:Hide()
    table.insert(self.particlePool, particle.texture)
  end
  wipe(self.particles)
  wipe(self.previous)
  self:LayoutHorizon(self.T.horizon)
  self:LayoutHud()
  self:ApplyTrackPalette(race.track)
  self.roulette, self.lastItem = nil, race.player and race.player.item or nil
  -- Only name the theme when it adds something. "Netherstorm Turbo Circuit  /
  -- NETHERSTORM" reads like a debug string, and most circuits are named after
  -- the zone they run through.
  local theme = race.track.theme
  local redundant = theme and race.track.name:upper():find(theme:upper(), 1, true)
  self.trackName:SetText(redundant and race.track.name
    or (race.track.name .. "  /  " .. theme))
  -- Concatenating a nil `shortcut` throws here and takes the whole race start
  -- down with it -- and a battle arena has no shortcut to speak of, so this
  -- would fire on the very first fixture. Every circuit happens to define one
  -- today, but a HUD line should not be a landmine for the next track that
  -- forgets to.
  self.shortcut:SetText(race.track.shortcut and ("SHORTCUT: " .. race.track.shortcut) or "")
  self.notice:SetText("")
  self.countdown:SetText("")
  self:BuildMinimapRoute(race.track)
  self.frame:Show()
end

function RaceUI:Hide()
  if self.frame then self.frame:Hide() end
end

--- Attract mode shows the world but none of the interface: no HUD, no controls,
--- no banners. The menu sits on top of it.
--- Whether racer models run at all. Nothing protected here, so this is safe to
--- call from any path -- including a slash command typed into chat.
---
--- Attract mode runs behind the menu, which already has its own preview model
--- plus one per racer card. Adding 8 karts and 6 spectators on top pushed the
--- client past the number of PlayerModels it will render at once and models
--- started dropping out everywhere, so the demo runs on sprites only.
function RaceUI:SetModelsEnabled(enabled)
  self:Build()
  local wasSuppressed = self.suppressModels
  self.suppressModels = not enabled
  if not enabled then
    for _, kart in ipairs(self.karts) do kart.model:Hide() end
    for _, seat in ipairs(self.spectators) do seat:Hide() end
  elseif wasSuppressed then
    -- Coming back from sprites-only: the models were hidden and may have been
    -- unloaded underneath us, so drop the caches and let them load again.
    for _, kart in ipairs(self.karts) do AK.Model:Invalidate(kart.model) end
    for _, seat in ipairs(self.spectators) do AK.Model:Invalidate(seat.model or seat) end
  end
end

function RaceUI:SetHudShown(shown)
  self:Build()
  self.hudShown = shown
  self:SetModelsEnabled(shown)
  for _, region in ipairs({ self.hudLayer, self.tagLayer, self.minimapPanel,
    self.headerPanel, self.clockPanel, self.itemPanel, self.driftPanel,
    self.placeGlow, self.position, self.positionOf, self.status,
    self.controlBar, self.trackName, self.shortcut, self.countdown,
    self.lightRig }) do
    if region then region:SetShown(shown) end
  end
  for _, button in ipairs(self.raceButtons or {}) do button:SetShown(shown) end
  -- Any beat still counting down when the race ended stays up over the results
  -- and then over the menu -- "LAP 2" was sitting on the title screen. Announce
  -- already refuses to fire while the HUD is hidden, but nothing ever cleared
  -- what was ALREADY on screen when attract mode started.
  if not shown then self:ClearPresentation() end
  if self.frame then
    -- Attract mode must not swallow the keyboard; the menu needs it.
    -- Release the keyboard grab in attract mode so the menu stays usable.
    -- Mouse state is deliberately untouched: the race frame never captured the
    -- mouse, and enabling it here would start swallowing clicks.
    -- Protected, and blocked outright when this is reached from Blizzard's
    -- chat edit box. Failing to release the grab is survivable; throwing here
    -- is not, so the call is guarded.
    if self.frame.SetPropagateKeyboardInput then
      pcall(self.frame.SetPropagateKeyboardInput, self.frame, not shown)
    end
    pcall(self.frame.EnableKeyboard, self.frame, shown)
  end
end

--- Wipe any in-flight announcement. Without this a banner fired in the last
--- moments of a race stays on screen over the results.
--- Drop every live presentation beat. Call this whenever a race begins or ends.
---
--- Every deadline in here is stored in RACE TIME, not wall-clock -- `now()`
--- returns `race.elapsed`. So "finishUntil = elapsed + 2.4" on a race that ended
--- at 93s is 95.4, and the NEXT race restarts elapsed at zero: the deadline is
--- still 95 seconds in the "future", and the FINISHED 1ST card, the chequered
--- flash and every other beat sat on screen through the following race's
--- countdown and most of the race itself. Nothing expires them, because from
--- their point of view they have not happened yet.
function RaceUI:ClearPresentation()
  self.finishUntil, self.checkerUntil, self.lightsUntil = nil, nil, nil
  self.splitUntil, self.wrongWayUntil, self.beatUntil = nil, nil, nil
  self.noticeUntil, self.sectionUntil = nil, nil
  self.lightsLit, self.lightsGreen = nil, nil
  self.flashAlpha, self.urgencyAlpha = 0, 0
  -- Feel channels are offsets on the camera baseline; a race must never inherit
  -- one still easing out of the last one.
  self.feel = { push = 0, dip = 0, lean = 0, kickX = 0 }

  -- These are driven purely by ALPHA in UpdatePresentation and never by
  -- SetShown, so hiding them would leave them permanently invisible -- the beat
  -- would fire again and set an alpha on a hidden widget forever after.
  for _, region in ipairs({ self.finishCard, self.splitText, self.wrongWay,
    self.beatLabel, self.urgency, self.flash, self.spinyWarn }) do
    if region then region:SetAlpha(0) end
  end
  -- These two manage their own shown state, so they have to actually be hidden:
  -- UpdatePresentation only runs during a race, and between races nothing would
  -- take them down. `checker` is a LIST of 24 cells, not a single texture --
  -- calling :Hide() on the table itself is what threw "attempt to call a nil
  -- value" here.
  if self.startLights then self.startLights:Hide() end
  for _, tile in ipairs(self.checker or {}) do tile:Hide() end
  self:ClearBanner()
end

function RaceUI:ClearBanner()
  if not self.notice then return end
  self.noticeUntil = nil
  self.notice:SetText("")
  self.noticePlate:Hide()
  self.noticeEdge:Hide()
  self.noticeIcon:Hide()
end

--- Draw the circuit's real plan-view shape. This used to be a fixed ellipse
--- with the centreline offset added on top, which drew the same ring for every
--- track and now overflows the panel entirely at real corner amplitudes.
-- Half the span the route drawing may use inside the map panel, derived from
-- the panel rather than fixed at 46 against a 128px box that no longer exists.
local MAP_RADIUS = HUD.map.w * 0.36

function RaceUI:BuildMinimapRoute(track)
  local count = #self.mapRoute
  for index, node in ipairs(self.mapRoute) do
    local fraction = (index - 1) / count
    local x, y
    if track.mapPath then
      x, y = AK.TrackBuilder:MapPoint(track, fraction * track.length)
      x, y = x * MAP_RADIUS * 2, y * MAP_RADIUS * 2
    else
      local angle = fraction * math.pi * 2 - math.pi * .5
      x, y = math.cos(angle) * MAP_RADIUS, math.sin(angle) * MAP_RADIUS * 0.71
    end
    node:ClearAllPoints()
    -- Dead centre. The old -7 shift made room for a "TRACK MAP" caption that
    -- the panel no longer carries, so the route sat low in its own box.
    node:SetPoint("CENTER", self.minimap, "CENTER", x, y)
    node:Show()
  end
end

--- Where a racer sits on the track map.
function RaceUI:MapPosition(track, distance)
  if track.mapPath then
    local x, y = AK.TrackBuilder:MapPoint(track, distance)
    return x * MAP_RADIUS * 2, y * MAP_RADIUS * 2
  end
  local angle = (distance % track.length) / track.length * math.pi * 2 - math.pi * .5
  return math.cos(angle) * MAP_RADIUS, math.sin(angle) * MAP_RADIUS * 0.71
end

--- Banner announcement. `icon` gives it a matching item icon, which is what
--- makes using something feel like it actually happened.
function RaceUI:Announce(message, color, icon)
  -- The title-screen demo runs the full simulation; it must stay silent.
  if self.hudShown == false then return end
  color = color or AK.COLORS.gold
  self.notice:SetTextColor(unpack(color))
  self.notice:SetText(message)
  self.notice:SetAlpha(1)
  self.noticeIcon:SetShown(icon ~= nil)
  if icon then self.noticeIcon:SetTexture(icon) end
  self.noticeUntil = (AK.Race.current and AK.Race.current.elapsed or 0) + 1.9
  self.noticeStart = (AK.Race.current and AK.Race.current.elapsed or 0)
  self.noticeColor = color
end

-- ---- presentation beats -------------------------------------------------
--
-- Each of these sets a deadline; UpdatePresentation draws whatever is still
-- live. Keeping the trigger and the drawing apart means a beat can be fired
-- from RaceManager, or from /kart beats with no race running at all, and look
-- identical either way.

--- Presentation deadlines run on a MONOTONIC clock, never on race time.
---
--- This used to return `race.elapsed`, which restarts at zero every race. A
--- beat set at "elapsed + 2.4" near the end of a 93-second race therefore held
--- a deadline of 95.4, and the next race's clock began at 0 -- so from the
--- beat's point of view it had not happened yet, and the FINISHED 1ST card and
--- the chequered flash sat on screen through the whole following race. Nothing
--- could expire them. A clock that only ever moves forward makes the entire
--- class of bug impossible; the `race` argument is kept so callers read the
--- same, and is deliberately ignored.
local function now(_race)
  return GetTime()
end

--- Light `lit` of the three lamps. 3 lit and green means GO.
function RaceUI:SetStartLights(lit, green)
  self.lightsLit, self.lightsGreen = lit, green
  self.lightsUntil = green and (now() + 1.4) or nil
  if self.startLights then self.startLights:SetShown(lit ~= nil) end
end

--- Your split for the lap just completed, against your best so far.
function RaceUI:ShowLapSplit(lapNumber, split, best)
  if not self.splitText then return end
  local delta = best and (split - best) or nil
  local text = ("LAP %d   %s"):format(lapNumber, self:FormatTime(split))
  if delta and math.abs(delta) > 0.005 then
    text = text .. ("   %s%.2fs"):format(delta < 0 and "-" or "+", math.abs(delta))
  elseif not best then
    text = text .. "   FIRST LAP"
  end
  self.splitText:SetText(text)
  -- Green when you improved, gold when you did not: readable at a glance
  -- without having to parse the number.
  self.splitText:SetTextColor(unpack((not delta or delta <= 0) and AK.COLORS.lime or AK.COLORS.gold))
  self.splitUntil = now() + 2.2
end

--- Chequered flash plus the position card, held before the results screen.
function RaceUI:FinishSequence(position, photo)
  local ordinal = { "1ST", "2ND", "3RD" }
  self.checkerUntil = now() + 1.1
  if self.finishCard then
    local text = "FINISHED " .. (ordinal[position] or (position .. "TH"))
    -- A race decided by a third of a second deserves to be named as such. This
    -- is the difference between "you came 3rd" and a story you retell.
    if photo then
      text = text .. "\n" .. ("PHOTO FINISH -- %s %s BY %.2fs")
        :format(photo.won and "BEAT" or "LOST TO", photo.rival:upper(), photo.margin)
    end
    self.finishCard:SetText(text)
    self.finishCard:SetTextColor(unpack(photo and AK.COLORS.lime
      or (position <= 3 and AK.COLORS.gold or AK.COLORS.muted)))
  end
  if photo then self:Shake(14) end
  self.finishUntil = now() + 2.4
  self:Flash({ 1, 1, 1 }, .25)
  self:Shake(10)
end

function RaceUI:ShowWrongWay(active)
  self.wrongWayUntil = active and (now() + 0.6) or nil
end

--- Draw whatever beats are still live. Sizes come off the screen every frame,
--- so nothing here can shrink into specks at a higher resolution.
function RaceUI:UpdatePresentation(race, dt)
  local t = now(race)
  local w, h = self.halfWidth * 2, self.halfHeight * 2
  local reduced = AK.db.settings.reducedEffects

  -- Start gantry.
  if self.startLights then
    local live = self.lightsLit ~= nil and (not self.lightsUntil or t < self.lightsUntil)
    self.startLights:SetShown(live)
    if live then
      local lampSize = h * 0.055
      local gap = lampSize * 1.5
      self.startLights:ClearAllPoints()
      self.startLights:SetPoint("TOP", self.frame, "TOP", 0, -h * 0.20)
      self.startLights:SetSize(gap * 3 + lampSize, lampSize * 1.7)
      for i, lamp in ipairs(self.startLights.lamps) do
        lamp:SetSize(lampSize, lampSize)
        lamp:ClearAllPoints()
        lamp:SetPoint("CENTER", self.startLights, "CENTER", (i - 2) * gap, 0)
        local on = i <= (self.lightsLit or 0)
        if self.lightsGreen then
          lamp:SetVertexColor(0.30, 1.0, 0.38, 1)
          lamp:SetAlpha(0.95)
        else
          lamp:SetVertexColor(1.0, 0.22, 0.18, 1)
          lamp:SetAlpha(on and 0.95 or 0.14)
        end
      end
    end
  end

  -- Final-lap urgency: gold corners, breathing. Suppressed entirely under
  -- reduced effects, like every other full-screen treatment.
  if self.urgency then
    local finalLap = race and race.player and race.laps
      and race.player.lap == race.laps and not race.player.finished
    local target = (finalLap and not reduced) and (0.10 + 0.06 * math.sin(t * 3.4)) or 0
    self.urgencyAlpha = AK.Math.Lerp(self.urgencyAlpha or 0, target, math.min(1, (dt or 0.016) * 3))
    self.urgency:SetAlpha(self.urgencyAlpha)
    self.finalLapUrgency = finalLap and not reduced
  end

  -- Lap split.
  if self.splitText then
    local left = (self.splitUntil or 0) - t
    self.splitText:ClearAllPoints()
    self.splitText:SetPoint("TOP", self.frame, "TOP", 0, -h * 0.155)
    self.splitText:SetAlpha(AK.Math.Clamp(left / 0.5, 0, 1))
  end

  -- Chequered flash: alternating cells sweeping the top and bottom edges.
  if self.checker then
    local left = (self.checkerUntil or 0) - t
    local live = left > 0
    local cell = w / 12
    for i, tile in ipairs(self.checker) do
      tile:SetShown(live)
      if live then
        local col = (i - 1) % 12
        local row = math.floor((i - 1) / 12)
        local dark = ((col + row) % 2) == 0
        tile:SetVertexColor(dark and 0.05 or 1, dark and 0.05 or 1, dark and 0.06 or 1, 1)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", self.frame, "TOPLEFT", col * cell,
          row == 0 and 0 or -(h - cell * 0.7))
        tile:SetSize(cell, cell * 0.7)
        tile:SetAlpha(AK.Math.Clamp(left / 0.35, 0, 1) * 0.85)
      end
    end
  end

  -- Position card.
  if self.finishCard then
    local left = (self.finishUntil or 0) - t
    self.finishCard:ClearAllPoints()
    self.finishCard:SetPoint("CENTER", self.frame, "CENTER", 0, h * 0.06)
    self.finishCard:SetAlpha(AK.Math.Clamp(left / 0.4, 0, 1))
  end

  -- Beat name, while /kart beats is running.
  if self.beatLabel then
    local left = (self.beatUntil or 0) - t
    self.beatLabel:ClearAllPoints()
    self.beatLabel:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, h * 0.13)
    self.beatLabel:SetAlpha(AK.Math.Clamp(left / 0.4, 0, 1))
  end

  -- SPINY SHELL INCOMING. Dread has to build, so this is driven by the shell's
  -- closing TIME rather than by a fixed flash: the pulse accelerates and the
  -- vignette deepens as it arrives, and the caption tells you the out. A player
  -- who knows a boost saves them has a decision; one who does not just loses.
  if self.spinyWarn then
    local eta = race and race.spinyEta
    local live = eta ~= nil and eta < 6
    self.spinyWarn:ClearAllPoints()
    self.spinyWarn:SetPoint("TOP", self.frame, "TOP", 0, -h * 0.36)
    if live then
      local urgency = AK.Math.Clamp(1 - eta / 6, 0, 1)
      local beat = 0.5 + 0.5 * math.sin(t * (7 + urgency * 22))
      self.spinyWarn:SetText(eta < 2.2 and "BOOST NOW" or "SPINY SHELL INCOMING")
      self.spinyWarn:SetTextColor(1, 0.30 + 0.25 * (1 - urgency), 0.22)
      self.spinyWarn:SetAlpha((0.45 + 0.55 * beat) * (0.5 + 0.5 * urgency))
    else
      self.spinyWarn:SetAlpha(0)
    end
  end

  -- Wrong way.
  if self.wrongWay then
    local live = self.wrongWayUntil and t < self.wrongWayUntil
    self.wrongWay:ClearAllPoints()
    self.wrongWay:SetPoint("TOP", self.frame, "TOP", 0, -h * 0.28)
    self.wrongWay:SetText(live and "WRONG WAY" or "")
    self.wrongWay:SetAlpha(live and (0.55 + 0.45 * math.sin(t * 14)) or 0)
  end
end

--- Fire every beat in sequence, two seconds apart, with no race running.
---
--- These moments are, by nature, things you see once a lap at most and cannot
--- summon on demand -- which makes them almost impossible to judge or to
--- screenshot. This plays the whole set to an empty track.
function RaceUI:PlayBeats()
  if not self.frame or not self.frame:IsShown() then
    AK:Print("The beats play over the race scene, so start a race first "
      .. "(|cffffd100/kart race|r) and press the |cffffd100BEATS|r button on the right.")
    return
  end
  local steps = {
    { "start lights: 1", function() self:SetStartLights(1, false) end },
    { "start lights: 2", function() self:SetStartLights(2, false) end },
    { "start lights: 3", function() self:SetStartLights(3, false) end },
    { "GO", function()
        self:SetStartLights(3, true)
        self:Flash(AK.COLORS.lime, .22)
        self:Announce("GO!", AK.COLORS.lime)
      end },
    { "rocket start", function()
        self:Announce("ROCKET START!", AK.COLORS.gold)
        self:LaunchEffect(AK.COLORS.gold, true)
        self:Shake(14)
      end },
    { "false start", function()
        self:Announce("FALSE START!", AK.COLORS.danger)
        self:Shake(10)
      end },
    { "lap split (improved)", function() self:ShowLapSplit(2, 41.28, 42.60) end },
    { "lap split (slower)", function() self:ShowLapSplit(3, 43.90, 41.28) end },
    { "final lap", function()
        self:Announce("FINAL LAP!", AK.COLORS.gold)
        self:Flash(AK.COLORS.gold, .18)
      end },
    { "wrong way", function() self.wrongWayUntil = (AK.Race.current and AK.Race.current.elapsed or GetTime()) + 2.0 end },
    { "finish", function() self:FinishSequence(2) end },
  }
  AK:Print("Playing " .. #steps .. " race beats, one every 2s.")
  for index, step in ipairs(steps) do
    C_Timer.After((index - 1) * 2, function()
      if not self.frame or not self.frame:IsShown() then return end
      AK:Print("  " .. step[1])
      if self.beatLabel then
        self.beatLabel:SetText(("%d/%d   %s"):format(index, #steps, step[1]:upper()))
        self.beatUntil = ((AK.Race.current or {}).elapsed or GetTime()) + 1.9
      end
      step[2]()
    end)
  end
  -- Put the gantry away once the run is over so it does not sit on screen.
  C_Timer.After(#steps * 2 + 1, function()
    self:SetStartLights(nil, false)
    if self.beatLabel then self.beatLabel:SetText("") end
  end)
end

function RaceUI:Flash(color, alpha)
  if not self.flash or AK.db.settings.reducedEffects then return end
  self.flash:SetVertexColor(unpack(color or AK.COLORS.gold))
  self.flashAlpha = math.max(self.flashAlpha or 0, alpha or .12)
end

function RaceUI:FormatTime(seconds)
  local minutes = math.floor(seconds / 60)
  return string.format("%02d:%05.2f", minutes, seconds - minutes * 60)
end

-- --------------------------------------------------------------------------
-- Particles
-- --------------------------------------------------------------------------

--- Emit one screen-space particle. Positions are already projected, so sparks
--- inherit the perspective of whatever spawned them without extra maths.
function RaceUI:Emit(x, y, size, color, life, vx, vy, gravity)
  if AK.db.settings.reducedEffects then return end
  local texture = table.remove(self.particlePool)
  if not texture then return end
  local particle = {
    texture = texture, x = x, y = y, vx = vx, vy = vy,
    gravity = gravity or -420, size = size, life = life, maxLife = life, color = color,
  }
  texture:SetVertexColor(color[1], color[2], color[3], 1)
  texture:Show()
  table.insert(self.particles, particle)
end

-- Effect presets: start scale, end scale, lifetime, spin per second.
local EFFECTS = {
  burst   = { file = "burst.tga", from = 0.35, to = 2.10, life = 0.34, spin = 2.2 },
  shock   = { file = "shock.tga", from = 0.15, to = 3.20, life = 0.50, spin = 0.0 },
  pop     = { file = "burst.tga", from = 0.20, to = 1.15, life = 0.26, spin = -3.0 },
  bloom   = { file = "glow.tga",  from = 0.60, to = 2.60, life = 0.55, spin = 0.0 },
}

--- Fire a one-shot effect sprite at a screen position.
function RaceUI:PlayEffect(kind, x, y, size, color)
  if AK.db.settings.reducedEffects then return end
  local preset = EFFECTS[kind]
  if not preset then return end
  local texture = table.remove(self.effectPool)
  if not texture then return end
  texture:SetTexture(ART .. preset.file)
  texture:SetVertexColor(color[1], color[2], color[3], 1)
  texture:Show()
  table.insert(self.effects, {
    texture = texture, x = x, y = y, size = size, preset = preset,
    life = preset.life, maxLife = preset.life, rotation = 0,
  })
end

function RaceUI:UpdateEffects(dt)
  for i = #self.effects, 1, -1 do
    local fx = self.effects[i]
    fx.life = fx.life - dt
    if fx.life <= 0 then
      fx.texture:Hide()
      table.insert(self.effectPool, fx.texture)
      table.remove(self.effects, i)
    else
      local t = 1 - fx.life / fx.maxLife
      -- Ease out, so it snaps open and then drifts: a linear expand reads soft.
      local eased = 1 - (1 - t) * (1 - t) * (1 - t)
      local scale = fx.preset.from + (fx.preset.to - fx.preset.from) * eased
      local size = fx.size * scale
      fx.texture:ClearAllPoints()
      fx.texture:SetPoint("CENTER", self.frame, "CENTER", fx.x, fx.y)
      fx.texture:SetSize(size, size)
      fx.texture:SetAlpha((1 - t) * (1 - t))
      if fx.preset.spin ~= 0 and fx.texture.SetRotation then
        fx.rotation = fx.rotation + fx.preset.spin * dt
        fx.texture:SetRotation(fx.rotation)
      end
    end
  end
end

--- The full "something just launched" package at the player's kart.
function RaceUI:LaunchEffect(color, big)
  local x, y, width = self.playerX or 0, self.playerY or 0, self.playerWidth or 60
  self:PlayEffect("burst", x, y + width * 0.45, width * (big and 2.2 or 1.5), color)
  self:PlayEffect("shock", x, y + width * 0.30, width * (big and 2.0 or 1.3), color)
end

--- Ring of sparks off the player's kart when they fire something.
function RaceUI:ItemBurst(color)
  local x, y, width = self.playerX or 0, self.playerY or 0, self.playerWidth or 60
  for i = 1, 26 do
    local angle = (i / 26) * math.pi * 2
    self:Emit(x, y + width * 0.35, width * 0.20, color or AK.COLORS.gold,
      0.45 + math.random() * 0.3,
      math.cos(angle) * (280 + math.random() * 160),
      math.sin(angle) * (240 + math.random() * 160) + 120, -420)
  end
end

function RaceUI:UpdateParticles(dt)
  for i = #self.particles, 1, -1 do
    local particle = self.particles[i]
    particle.life = particle.life - dt
    if particle.life <= 0 then
      particle.texture:Hide()
      table.insert(self.particlePool, particle.texture)
      table.remove(self.particles, i)
    else
      particle.vy = particle.vy + particle.gravity * dt
      particle.x = particle.x + particle.vx * dt
      particle.y = particle.y + particle.vy * dt
      local fade = particle.life / particle.maxLife
      local size = particle.size * (0.3 + fade * 0.7) * self.T.particleScale
      particle.texture:ClearAllPoints()
      particle.texture:SetPoint("CENTER", self.frame, "CENTER", particle.x, particle.y)
      particle.texture:SetSize(size, size)
      particle.texture:SetAlpha(fade * fade)
    end
  end
end

--- Per-vehicle effects driven by state changes since the previous frame.
function RaceUI:VehicleEffects(vehicle, index, x, y, width, isPlayer)
  local previous = self.previous[index]
  if not previous then
    self.previous[index] = { stun = vehicle.stun, boost = vehicle.boostTime, charge = vehicle.driftCharge, lateral = vehicle.lateral }
    return
  end

  local rear = y - width * 0.08
  if vehicle.drifting and vehicle.driftCharge > 0.12 and width > 18 then
    local color = driftColor(vehicle.driftCharge)
    for side = -1, 1, 2 do
      self:Emit(x + side * width * 0.42, rear, width * (0.09 + math.random() * 0.09), color,
        0.26 + math.random() * 0.2,
        side * (40 + math.random() * 110), 60 + math.random() * 150, -520)
    end
  end

  -- Drift charge crossing into a new colour stage. This is the beat the whole
  -- drift mechanic is built around and it had no feedback whatsoever.
  if isPlayer and vehicle.drifting then
    for _, stage in ipairs(DRIFT_STAGES) do
      if stage.threshold > 0 and previous.charge < stage.threshold and vehicle.driftCharge >= stage.threshold then
        -- One cue PER TIER, not one cue for "a tier changed". Rising through
        -- the ladder has to be audibly a ladder: hearing the same blip three
        -- times tells you something happened, not what you have earned. This is
        -- the beat you need with your eyes still on the corner.
        if AK.PlaySfx then AK:PlaySfx("driftTier" .. stage.tier) end
        self:PlayEffect("pop", x, rear, width * 1.1, stage.color)
        self:Shake(2 + stage.tier * 2)
      end
    end
  end

  if previous.charge > 0.5 and vehicle.driftCharge < previous.charge - 0.3 then
    local color = driftColor(previous.charge)
    for _ = 1, 16 do
      local angle = math.random() * math.pi * 2
      self:Emit(x, rear, width * 0.14, color, 0.4 + math.random() * 0.3,
        math.cos(angle) * 260, math.abs(math.sin(angle)) * 300 + 60, -560)
    end
    if isPlayer then self:Shake(7) end
  end

  if vehicle.boostTime > 0 and width > 16 then
    for _ = 1, 2 do
      self:Emit(x + (math.random() - .5) * width * 0.7, rear, width * (0.10 + math.random() * 0.12),
        { 1, 0.55 + math.random() * 0.35, 0.15 }, 0.3 + math.random() * 0.25,
        (math.random() - .5) * 90, 130 + math.random() * 190, -430)
    end
    if previous.boost <= 0 and isPlayer then self:Shake(9) end
  end

  if vehicle.offroad and width > 16 then
    self:Emit(x + (math.random() - .5) * width * 0.9, rear, width * 0.11,
      { 0.62, 0.52, 0.34 }, 0.35, (math.random() - .5) * 130, 90 + math.random() * 120, -480)
  end

  if vehicle.stun > previous.stun + 0.05 then
    for _ = 1, 14 do
      local angle = math.random() * math.pi * 2
      self:Emit(x, y + width * 0.3, width * 0.16, { 1, 0.85, 0.45 }, 0.35 + math.random() * 0.25,
        math.cos(angle) * 320, math.sin(angle) * 320 + 90, -600)
    end
    if isPlayer then self:Shake(18) end
  end

  previous.stun, previous.boost, previous.charge = vehicle.stun, vehicle.boostTime, vehicle.driftCharge
end

-- --------------------------------------------------------------------------
-- Scene
-- --------------------------------------------------------------------------

function RaceUI:RenderSky(race, camX)
  local horizon = self.T.horizon
  local screenW = self.halfWidth * 2
  local screenH = self.halfHeight * 2
  local grassColor = race.track.color or { .16, .40, .18 }
  local glow = race.track.glow or { 1, .93, .72 }
  local light = (self.light or 1) * self.T.nightBoost
  local drift = -camX * 6

  self.skyGlow:SetAlpha(0.55)

  local skyTint = race.track.skyLow or { .8, .88, .96 }
  for i, band in ipairs(self.clouds) do
    local spread = self.halfWidth * 3
    local scale = 0.55 + ((i * 37) % 70) / 70
    local x = ((i * 263 + drift * .5 + race.elapsed * (2 + i % 5)) % spread) - spread * .5
    local y = horizon + screenH * 0.08 + ((i * 83) % math.floor(screenH * 0.38))
    band:ClearAllPoints()
    band:SetPoint("CENTER", self.frame, "CENTER", x, y)
    -- Cloud size follows the screen; absolute pixels shrink into specks on a
    -- large client, which is exactly what happened to the whole old skyline.
    band:SetSize(screenW * 0.20 * scale, screenW * 0.10 * scale)
    band:SetVertexColor(0.55 + skyTint[1] * 0.45, 0.55 + skyTint[2] * 0.45, 0.58 + skyTint[3] * 0.42, 1)
    band:SetAlpha(self.T.cloudAlpha)
  end

  -- Distant terrain, parallaxed through texture coordinates: the quad never
  -- moves, the ridge slides inside it. Each layer drifts at its own rate --
  -- far ridge slowest, hills faster, tree wall fastest -- which is the whole
  -- trick that turns three flat strips into depth.
  local skyline = self.skyline or {}
  local function scrollRidge(texture, cfg, ridgeDrift)
    if not cfg or not texture:IsShown() then return end
    -- The art is 4:1, so one repeat covers four times its drawn height.
    local repeatPx = math.max(1, screenH * cfg.h * 4)
    local u0 = -ridgeDrift / repeatPx
    texture:SetTexCoord(u0, u0 + screenW / repeatPx, 0, 1)
    local tint = cfg.tint
    texture:SetVertexColor(tint[1] * light, tint[2] * light, tint[3] * light, 1)
    texture:SetAlpha(cfg.a or 1)
  end
  scrollRidge(self.mountain, skyline.mtn, -camX * 1.1)
  scrollRidge(self.hillLine, skyline.hill, -camX * 2.0)

  -- Near wall: conifers, spires or void-shards depending on the track.
  local treeDrift = -camX * 3.4
  local spread = self.halfWidth * 2.4
  local slice = spread / TREES
  local oribos = race.track.style == "oribos"
  local spirey = oribos or skyline.treeArt ~= nil
  local treeTint = skyline.treeTint

  -- The ring hangs behind everything, drifting only slightly: it is enormous
  -- and far away, so it must barely move relative to the spires.
  self.ring:SetShown(oribos)
  if oribos then
    self.ring:ClearAllPoints()
    self.ring:SetPoint("BOTTOM", self.frame, "CENTER", -camX * 0.9, horizon - 40)
    self.ring:SetSize(self.halfWidth * 1.9, self.halfWidth * 1.9)
    self.ring:SetVertexColor(0.72 * light, 0.66 * light, 0.86 * light, 1)
    self.ring:SetAlpha(0.55)
  end

  -- Aerial perspective on the near wall. The old code made far trees DARKER,
  -- which raises their contrast against a pale horizon -- the opposite of what
  -- distance does, and why the back row read as a stencil cut out of the sky.
  -- Distance washes a silhouette toward the colour of the air in front of it,
  -- so that is what this does, mixing toward the horizon between sky and glow.
  local wash = {
    (skyTint[1] * 0.6 + glow[1] * 0.4) * light,
    (skyTint[2] * 0.6 + glow[2] * 0.4) * light,
    (skyTint[3] * 0.6 + glow[3] * 0.4) * light,
  }
  for i, tree in ipairs(self.trees) do
    local seed = self.treeSeed[i]
    -- The offset belongs to the SLOT, not to a position, so a tree keeps its
    -- own spacing as the row wraps: irregular, but it never crawls or shuffles.
    local x = ((i * slice + seed.x * slice * 0.9 + treeDrift) % spread) - spread * .5
    -- Depth is continuous rather than "every third one is a back row". Two
    -- discrete rows is still a pattern, and the eye finds a pattern instantly.
    local depth = seed.d
    tree:ClearAllPoints()
    -- All heights are fractions of the screen, never absolute pixels.
    local height = (spirey and (0.085 + seed.h * 0.240) or (0.034 + seed.h * 0.105))
      * screenH * self.T.treeHeight * (1 - depth * 0.34)
    tree:SetPoint("BOTTOM", self.frame, "CENTER", x, horizon - screenH * (0.004 + depth * 0.017))
    tree:SetSize(height * (spirey and 0.26 or 0.5) * (0.80 + seed.w * 0.44), height)
    local tone = (spirey and 0.68 or 0.92) * (1 - depth * 0.12) * light
    local r, g, b
    if oribos then
      r, g, b = tone * 0.80, tone * 0.70, tone * 1.15
    elseif treeTint then
      r, g, b = tone * treeTint[1], tone * treeTint[2], tone * treeTint[3]
    else
      r, g, b = tone * 0.8, tone, tone * 0.86
    end
    local haze = depth * 0.40
    tree:SetVertexColor(
      r + (wash[1] - r) * haze,
      g + (wash[2] - g) * haze,
      b + (wash[3] - b) * haze, 1)
  end

  -- Enough haze to soften the horizon seam. Too little and ground meets sky on
  -- a hard cut line, which is the strongest "flat 2D" tell in the scene.
  self.haze:SetVertexColor(glow[1] * .8, glow[2] * .8, glow[3] * .85, .30)
  -- Aerial perspective on the ground itself: sky-tinted and pale at the
  -- horizon, full colour at the bottom edge. A flat fill was the single
  -- biggest "the world is a sheet" tell in every screenshot.
  local ground = shade(grassColor, 0.62 * light)
  local hazeMix = {
    (skyTint[1] * .5 + glow[1] * .5) * light,
    (skyTint[2] * .5 + glow[2] * .5) * light,
    (skyTint[3] * .5 + glow[3] * .5) * light,
  }
  self.ground:SetVertexColor(1, 1, 1, 1)
  applyGradient(self.ground, "VERTICAL",
    ground[1], ground[2], ground[3], 1,
    ground[1] * .28 + hazeMix[1] * .72, ground[2] * .28 + hazeMix[2] * .72, ground[3] * .28 + hazeMix[3] * .72, 1)
end

--- Drive-through arches. Same rolling-window trick as the posts.
---
--- This used to let the quad grow until it engulfed the screen, on the argument
--- that engulfing you is what sells "you went under that". Rendered, it does
--- not: a billboard cannot pass overhead, so all the growth buys is two hard
--- vertical bars pinned to the edges of the display. It is dropped at 6m
--- instead -- see the note at the near cutoff below.
function RaceUI:RenderArches(race, camX, camZ)
  local spacing = race.track.archSpacing
  if not spacing then
    for _, arch in ipairs(self.arches) do arch:Hide() end
    return
  end
  local tuning = self.T
  local light = (self.light or 1) * tuning.nightBoost
  -- Further out than the posts, because an arch is a 17m structure you drive
  -- through and want to see coming -- but nothing like the 297m it used to use,
  -- where the road is on screen only 40% of a lap.
  local archFar = FAR_Z * 0.45
  local first = math.ceil(camZ / spacing)
  for slot, arch in ipairs(self.arches) do
    local index = first + slot - 1
    local archZ = index * spacing
    local dz = archZ - camZ
    -- Dropped once you are underneath it, not at 0.6m. An arch is a flat
    -- billboard 17m wide, and its projected size grows without bound as dz
    -- falls -- at a metre out it is thousands of pixels across, so what the
    -- player actually saw was two hard vertical bars pinned to the left and
    -- right edges of the screen, sliding as they passed. A real gateway leaves
    -- the frame overhead; a billboard cannot, so it stops being drawn instead.
    -- By 6m the top of a 13m arch is already well above the screen.
    if dz > 6 and dz < archFar then
      local worldX, worldY = self:RoadAt(self.route or race.track, archZ)
      local x, y, pixelsPerMetre = self:Project(dz, worldX, camX, worldY)
      -- 17m wide, 13m tall; the art's opening lines up with the road.
      local width = pixelsPerMetre * 17
      local fog = AK.Math.Clamp(1 - (dz / FAR_Z) * tuning.fogStrength * 0.8, 0.3, 1) * light
      arch:ClearAllPoints()
      arch:SetPoint("BOTTOM", self.frame, "CENTER", x, y)
      arch:SetSize(width, width * 0.95)
      arch:SetVertexColor(fog, fog * 0.98, fog * 1.02, 1)
      arch:SetAlpha(self:DepthFade(dz, archFar) * self:EdgeFade(x, dz))
      arch:Show()
    else
      arch:Hide()
    end
  end
end

--- Marker posts along both verges, from a rolling window ahead of the camera.
function RaceUI:RenderPosts(race, camX, camZ)
  local tuning = self.T
  local spacing = math.max(2, tuning.postSpacing)
  -- 0.36 of the draw distance, the same band the pickups use, because it is the
  -- same question: how far ahead is the road still ON SCREEN? Measured, the
  -- worst track keeps it there 63% of the lap at 119m and 42% at the 264m these
  -- were drawn to -- so well over half of every post spawned out there was
  -- never seen, and the ones that were came in from the side of the display.
  -- The speed cue posts exist for comes from the ones sweeping past inside 40m.
  local postFar = FAR_Z * 0.36
  local first = math.ceil(camZ / spacing)
  for slot, pair in ipairs(self.posts) do
    local index = first + slot - 1
    local segZ = index * spacing
    local dz = segZ - camZ
    if dz > 1 and dz < postFar then
      local worldX, worldY = self:RoadAt(self.route or race.track, segZ)
      local x, y, pixelsPerMetre = self:Project(dz, worldX, camX, worldY)
      local halfWidthPixels = pixelsPerMetre * tuning.roadHalf * AK.Math.RoadWidth(self.route or race.track, segZ)
      local width = math.max(1, pixelsPerMetre * 0.18)
      local height = math.max(2, pixelsPerMetre * 1.15)
      local fog = AK.Math.Clamp(1 - (dz / FAR_Z) * tuning.fogStrength, 0.22, 1)
      -- Alternating colour so the posts strobe past rather than blur together.
      local red = (index % 2 == 0)
      local r, g, b = red and .88 or .95, red and .26 or .95, red and .20 or .96
      local offset = halfWidthPixels + width * 2.2
      -- Faded on each post's OWN screen position, not the road centre's: on the
      -- outside of a bend the far verge is a long way further off-axis than the
      -- middle of the road, and it is the outer post that streams in from the
      -- edge first. These are the most numerous thing in the scene -- a pair
      -- every `postSpacing` metres, out to 0.8 of the draw distance -- so they
      -- were the loudest source of "stuff sliding in from the side".
      pair.left:ClearAllPoints()
      pair.left:SetPoint("BOTTOM", self.frame, "CENTER", x - offset, y)
      pair.left:SetSize(width, height)
      pair.left:SetVertexColor(r * fog, g * fog, b * fog, 1)
      local near = self:DepthFade(dz, postFar)
      pair.left:SetAlpha(near * self:EdgeFade(x - offset, dz))
      pair.left:Show()
      pair.right:ClearAllPoints()
      pair.right:SetPoint("BOTTOM", self.frame, "CENTER", x + offset, y)
      pair.right:SetSize(width, height)
      pair.right:SetVertexColor(r * fog, g * fog, b * fog, 1)
      pair.right:SetAlpha(near * self:EdgeFade(x + offset, dz))
      pair.right:Show()
    else
      pair.left:Hide()
      pair.right:Hide()
    end
  end
end

--- Start/finish line, drawn at the next lap boundary ahead of the camera.
function RaceUI:RenderFinish(race, camX, camZ)
  local tuning = self.T
  local finish = self.finish
  local length = race.track.length
  local lineZ = math.ceil(camZ / length) * length
  local dz = lineZ - camZ
  -- Kept longer than the scenery -- knowing the line is coming is information,
  -- not decoration -- but pulled in from 248m, where it was on screen under
  -- half the lap and arrived by sliding in from the edge.
  local finishFar = FAR_Z * 0.55
  if dz < 0.5 or dz > finishFar then
    finish:Hide()
    return
  end

  local worldX, worldY = self:RoadAt(self.route or race.track, lineZ)
  local x, y, pixelsPerMetre = self:Project(dz, worldX, camX, worldY)
  local farWorldX, farWorldY = self:RoadAt(self.route or race.track, lineZ + 2.5)
  local farX, farY = self:Project(dz + 2.5, farWorldX, camX, farWorldY)
  local halfWidthPixels = pixelsPerMetre * tuning.roadHalf * AK.Math.RoadWidth(self.route or race.track, lineZ)
  local bandHeight = math.max(2, farY - y)
  local fog = AK.Math.Clamp(1 - (dz / FAR_Z) * tuning.fogStrength, 0.25, 1)

  finish:SetFrameLevel(self.frame:GetFrameLevel() + 2 + math.floor(AK.Math.Clamp(FAR_Z - dz, 1, 150)))
  -- One alpha on the parent, so the checkerboard, both gantry posts, the banner
  -- and the label all fade together rather than the line dissolving in pieces.
  finish:SetAlpha(self:DepthFade(dz, finishFar) * self:EdgeFade(x, dz))
  finish:ClearAllPoints()
  finish:SetPoint("BOTTOM", self.frame, "CENTER", 0, 0)
  finish:SetSize(1, 1)

  -- Checkerboard: 14 columns across the road, two rows deep.
  local columns, rows = 14, 2
  local columnWidth = (halfWidthPixels * 2) / columns
  local rowHeight = bandHeight / rows
  for index, block in ipairs(finish.blocks) do
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    if row < rows then
      -- Lerp toward the far edge so the band follows the road's curve.
      local blend = (row + 0.5) / rows
      local centre = x + (farX - x) * blend
      local shadeValue = ((column + row) % 2 == 0) and 0.97 or 0.09
      block:ClearAllPoints()
      block:SetPoint("BOTTOM", self.frame, "CENTER",
        centre - halfWidthPixels + columnWidth * (column + 0.5), y + rowHeight * row)
      block:SetSize(columnWidth + 1, rowHeight + 1)
      block:SetVertexColor(shadeValue * fog, shadeValue * fog, shadeValue * fog, 1)
      block:Show()
    else
      block:Hide()
    end
  end

  -- Overhead gantry. Only worth drawing once it is close enough to read.
  local postWidth = math.max(1, pixelsPerMetre * 0.34)
  local postHeight = pixelsPerMetre * 5.2
  -- Big enough to read, and not so close that the billboard has swollen past
  -- the frame -- the same unbounded near-field growth the arches had. The
  -- checkerboard on the ground keeps drawing right up to the line; it lies flat
  -- and stays where it should. It is the upright gantry that blows up.
  local showGantry = postHeight > 16 and dz > 6
  finish.leftPost:SetShown(showGantry)
  finish.rightPost:SetShown(showGantry)
  finish.banner:SetShown(showGantry)
  finish.bannerEdge:SetShown(showGantry)
  finish.label:SetShown(postHeight > 90)
  if showGantry then
    local span = halfWidthPixels + postWidth * 2
    finish.leftPost:ClearAllPoints()
    finish.leftPost:SetPoint("BOTTOM", self.frame, "CENTER", x - span, y)
    finish.leftPost:SetSize(postWidth, postHeight)
    finish.leftPost:SetVertexColor(.82 * fog, .84 * fog, .90 * fog, 1)
    finish.rightPost:ClearAllPoints()
    finish.rightPost:SetPoint("BOTTOM", self.frame, "CENTER", x + span, y)
    finish.rightPost:SetSize(postWidth, postHeight)
    finish.rightPost:SetVertexColor(.82 * fog, .84 * fog, .90 * fog, 1)
    local bannerHeight = math.max(3, pixelsPerMetre * 1.1)
    finish.banner:ClearAllPoints()
    finish.banner:SetPoint("BOTTOM", self.frame, "CENTER", x, y + postHeight - bannerHeight)
    finish.banner:SetSize(span * 2 + postWidth, bannerHeight)
    finish.banner:SetVertexColor(.10 * fog, .14 * fog, .22 * fog, 1)
    finish.bannerEdge:ClearAllPoints()
    finish.bannerEdge:SetPoint("BOTTOM", self.frame, "CENTER", x, y + postHeight - bannerHeight)
    finish.bannerEdge:SetSize(span * 2 + postWidth, math.max(1, bannerHeight * 0.14))
    finish.bannerEdge:SetVertexColor(1 * fog, .76 * fog, .20 * fog, 1)
    finish.label:ClearAllPoints()
    finish.label:SetPoint("CENTER", self.frame, "CENTER", x, y + postHeight - bannerHeight * 0.5)
    local player = race.player
    finish.label:SetText(player.lap >= race.laps and "FINISH" or ("LAP " .. math.min(player.lap + 1, race.laps)))
  end
  finish:Show()
end

--- Roadside crowd, projected like everything else. Slots are assigned from a
--- rolling window ahead of the camera so six models cover the whole track.
function RaceUI:RenderSpectators(race, camX, camZ)
  local tuning = self.T
  -- Skip entirely in attract mode: model budget is reserved for the menu.
  if AK.db.settings.reducedEffects or self.suppressModels then
    for _, seat in ipairs(self.spectators) do seat:Hide() end
    return
  end
  -- The crowd is decoration, so it gets the shortest range of the scenery: a
  -- spectator at the old 205m was a faded speck off the side of the screen
  -- half the time, and these are MODELS -- the most expensive thing per head.
  local crowdFar = FAR_Z * 0.40
  local first = math.ceil(camZ / SPECTATOR_SPACING)
  for slot, seat in ipairs(self.spectators) do
    local index = first + slot - 1
    local dz = index * SPECTATOR_SPACING - camZ
    if dz > 4 and dz < crowdFar then
      local side = (index % 2 == 0) and -1 or 1
      local lateral = side * (tuning.roadHalf + 1.8 + ((index * 37) % 20) * 0.06)
      local baseX, worldY = self:RoadAt(self.route or race.track, index * SPECTATOR_SPACING)
      local x, y, pixelsPerMetre = self:Project(dz, baseX + lateral, camX, worldY)
      local size = AK.Math.Clamp(pixelsPerMetre * tuning.specScale, 14, 300)
      seat:ClearAllPoints()
      -- Anchored by CENTRE: a model renders about its own origin, so anchoring
      -- the frame's bottom to the road buries the lower half of the body.
      seat:SetPoint("CENTER", self.frame, "CENTER", x, y + size * 0.34)
      seat:SetSize(size * 2.2, size * 2.2)
      seat:SetFrameLevel(self.frame:GetFrameLevel() + 2 + math.floor(AK.Math.Clamp(FAR_Z - dz, 1, 140)))
      seat:SetAlpha(self:DepthFade(dz, crowdFar) * self:EdgeFade(x, dz))
      seat.model.akZoom = tuning.specZoom / math.max(0.01, tuning.modelZoom)
      AK.Model:Reframe(seat.model)
      seat.model:SetFacing(side > 0 and -1.35 or 1.35)
      -- Shown regardless of load state, for the same reason the karts are: a
      -- hidden PlayerModel never streams in, so gating on IsReady kept the
      -- crowd permanently invisible.
      seat:Show()
    else
      seat:Hide()
    end
  end
end

--- Draw the road strip. Returns the camera position so sprites project against
--- exactly the same camera the road used.
--- Everything in the world sits on some route. The camera is on the player's,
--- so a racer who took the other side of a fork is not merely far away -- they
--- are on a different piece of road and must not be drawn on this one at all.
function RaceUI:OnRoute(race, entity)
  local route = self.route or race.track
  return (entity.route or race.track) == route
end

--- The alternate route at a fork.
---
--- A branch is compiled exactly like a track, so it exposes the same centre,
--- height and width tables and can be projected with the same maths. It is
--- drawn peeling off the side of the main road it leaves from, which is the
--- only thing that tells a driver the split is coming while they can still
--- choose it.
--- Lay out a route's roadside scenery.
---
--- Deterministic from the track id, so the world is identical every lap and
--- every session -- scenery that reshuffles is worse than none, because you
--- stop trusting what you are looking at. Built once and cached on the route.
local PROP_KINDS = {
  oribos = {
    { art = "spire.tga", w = 0.30, h = 1.00, tint = { 0.62, 0.55, 0.85 }, min = 5.5, max = 13.0 },
    { art = "shard.tga", w = 0.70, h = 0.70, tint = { 0.45, 0.85, 1.00 }, min = 1.4, max = 3.0 },
  },
  default = {
    { art = "tree.tga",  w = 0.55, h = 1.00, tint = { 0.72, 0.92, 0.70 }, min = 4.5, max = 11.0 },
    { art = "tree.tga",  w = 0.60, h = 0.90, tint = { 0.50, 0.74, 0.52 }, min = 6.0, max = 14.0 },
    { art = "shard.tga", w = 0.90, h = 0.75, tint = { 0.62, 0.58, 0.52 }, min = 1.2, max = 2.6 },
  },
}

function RaceUI:BuildProps(route, style)
  if route.props then return route.props end
  local kinds = PROP_KINDS[style or "default"] or PROP_KINDS.default
  -- Resolve each art path ONCE. RenderProps used to build it with a concat per
  -- prop per frame, which is 54 short-lived strings every frame for a value
  -- that never changes.
  for _, kind in ipairs(kinds) do kind.artPath = kind.artPath or (ART .. kind.art) end
  -- Seed from the whole id, not its length: half the tracks share a name
  -- length and would otherwise grow byte-identical forests.
  local name = route.id or route.name or "route"
  local seed = math.floor(route.length)
  for i = 1, #name do seed = (seed * 31 + name:byte(i)) % 2147483647 end
  local rng = AK.RNG:New(seed)
  local props = {}
  local distance = 0
  while distance < route.length do
    for _, side in ipairs({ -1, 1 }) do
      -- Skip some slots outright, so the verge has clearings and thickets
      -- rather than a metronome of identical trunks.
      if rng:Next() > 0.22 then
        local kind = kinds[rng:Range(1, #kinds)]
        props[#props + 1] = {
          distance = (distance + rng:Next() * PROP_SPACING) % route.length,
          side = side,
          -- Just beyond the verge, with a scattering set further back.
          offset = 1.35 + rng:Next() * (rng:Next() < 0.3 and 3.2 or 0.9),
          size = kind.min + rng:Next() * (kind.max - kind.min),
          kind = kind,
          -- Slight per-prop tint variation so a stand of trees is not one
          -- colour stamped repeatedly.
          shade = 0.82 + rng:Next() * 0.36,
        }
      end
    end
    distance = distance + PROP_SPACING
  end
  table.sort(props, function(a, b) return a.distance < b.distance end)
  route.props = props
  return props
end

--- Draw the scenery nearest the camera, sorted so near props occlude far ones.
function RaceUI:RenderProps(race, camX, camZ)
  local tuning = self.T
  local route = self.route or race.track
  local props = self:BuildProps(route, race.track.style)
  local light = (self.light or 1) * tuning.nightBoost
  local shown = 0
  local length = route.length

  for _, prop in ipairs(props) do
    if shown >= PROPS then break end
    local dz = AK.Math.SignedLoopDistance(camZ % length, prop.distance, length)
    if dz > 0.8 and dz < FAR_Z then
      shown = shown + 1
      local frame = self.props[shown]
      -- camZ + dz, NOT prop.distance.
      --
      -- `Bend` measures from `bendFrom = camZ`, which is an ABSOLUTE distance
      -- that keeps accumulating across laps, while props/objects/hazards store
      -- LAP-RELATIVE distances (0..length). From lap two onward the subtraction
      -- goes hugely negative, clamps to t = 0, and every one of them is handed
      -- bend 0 -- pinned to the road's centreline AT THE CAMERA while the road
      -- curves away from it. They then appear off the track at distance and
      -- only slide into place as you arrive on top of them. `dz` is already the
      -- forward distance from the camera, so camZ + dz is the honest position.
      local propZ = camZ + dz
      local baseX, worldY = self:RoadAt(route, propZ)
      local edge = AK.Math.RoadWidth(route, propZ)
      -- Anchored outside the road edge, so props never encroach on the racing
      -- surface however much the road narrows or widens.
      local lateral = prop.side * (edge + prop.offset) * tuning.roadHalf
      local x, y, pixelsPerMetre = self:Project(dz, baseX + lateral, camX, worldY)
      local height = pixelsPerMetre * prop.size
      if height > 2 and x > -self.halfWidth * 2.2 and x < self.halfWidth * 2.2 then
        local kind = prop.kind
        local width = height * (kind.w / kind.h)
        local fog = AK.Math.Clamp(1 - (dz / FAR_Z) * tuning.fogStrength, 0.20, 1) * light
        local tint = kind.tint
        local shade = prop.shade * fog

        frame:ClearAllPoints()
        frame:SetPoint("BOTTOM", self.frame, "CENTER", x, y)
        frame:SetSize(math.max(1, width), math.max(1, height))
        -- Nearer props draw over farther ones, matching the road strips.
        frame:SetFrameLevel(self.frame:GetFrameLevel() + 1
          + math.floor(AK.Math.Clamp(FAR_Z - dz, 1, 150)))
        -- Only when it actually changes, for the reason RenderKarts already
        -- states: re-binding the same file every frame costs for nothing. Props
        -- are the worse case of the two -- 54 of them against eight karts -- and
        -- the path was being CONCATENATED here as well, so a fresh string was
        -- allocated per prop per frame purely to hand back a texture the widget
        -- was already showing. `artPath` is resolved once in BuildProps.
        if frame.artApplied ~= kind.artPath then
          frame.artApplied = kind.artPath
          frame.art:SetTexture(kind.artPath)
        end
        frame.art:SetVertexColor(tint[1] * shade, tint[2] * shade, tint[3] * shade, 1)
        -- A contact shadow is what stops a sprite looking pasted onto the
        -- grass; without one everything hovers.
        frame.shadow:ClearAllPoints()
        frame.shadow:SetPoint("CENTER", frame, "BOTTOM", 0, height * 0.02)
        frame.shadow:SetSize(width * 1.15, math.max(1, height * 0.14))
        frame.shadow:SetVertexColor(0, 0, 0, 0.34 * fog)
        -- Props had NO edge fade and were drawn out to 2.2 half-widths off
        -- axis, which is well past the display -- so a tree the corner had
        -- swung aside stayed fully opaque and could be watched travelling in
        -- from nowhere. Objects and hazards already fade; scenery is the most
        -- numerous thing on screen and needed it most.
        frame:SetAlpha(self:EdgeFade(x, dz))
        frame:Show()
      else
        shown = shown - 1
      end
    end
  end
  for i = shown + 1, PROPS do self.props[i]:Hide() end
end

function RaceUI:RenderFork(race, player, camX, camZ)
  local tuning = self.T
  local track = race.track
  local shown = 0
  local signShown = false

  -- Only from the main line: once committed to a branch there is no fork left
  -- to advertise, and the branch's own road is already the one being drawn.
  if (player.route or track) == track then
    local branch, gap = AK.TrackBuilder:ForkAt(track, player.distance, FAR_Z)
    if branch and gap then
      -- Distance from the camera to the split. camBack is added because the
      -- camera trails the kart, so the split is that much further away again.
      local entryDz = gap + tuning.camBack
      -- Where the main road has already bent to by the time it reaches the
      -- split; the ribbon has to leave from exactly there or it detaches.
      local entryCentre = self:Bend(branch.entry)
      local entryWidth = AK.Math.RoadWidth(track, branch.entry)
      -- The branch's own curvature, accumulated along the branch the same way
      -- the main road is accumulated along itself.
      local branchBend
      do
        -- Read the tuned gain once per fork rather than per step, and from the
        -- same accessor the main road uses -- the branch must bend by exactly
        -- the amount the road it leaves does, or the ribbon peels away wrong.
        local gain = bendGain()
        local cache, lateral, offset, built = {}, 0, 0, 0
        branchBend = function(bd)
          while built * BEND_STEP <= bd + BEND_STEP do
            cache[built + 1] = offset
            lateral = lateral + AK.Math.RoadCurve(branch, built * BEND_STEP) * gain * BEND_STEP
            offset = offset + lateral * BEND_STEP
            built = built + 1
          end
          local t = bd / BEND_STEP
          local index = math.floor(t)
          local a, b = cache[index + 1] or 0, cache[index + 2] or 0
          return a + (b - a) * (t - index)
        end
      end
      -- The ribbon leaves from the edge of the main road on its own side, then
      -- follows wherever the branch was authored to curve.
      local side = (branch.side or -1)
      local offset = side * tuning.roadHalf * entryWidth * 0.92
      local span = math.min(branch.length, math.max(0, FAR_Z - entryDz))
      local light = (self.light or 1) * tuning.nightBoost
      local roadColor = track.road or { .34, .34, .38 }
      local previousX, previousY, previousW

      if span > 2 then
        for i = 0, FORK_SEGMENTS - 1 do
          local bd = span * (i / (FORK_SEGMENTS - 1))
          local dz = entryDz + bd
          if dz > 1.2 then
            -- Blend the ribbon out of the main road over the first few metres
            -- so it grows from the tarmac rather than appearing beside it.
            local emerge = AK.Math.Clamp(bd / 12, 0, 1)
            -- The ribbon starts where the main road has bent to by the split,
            -- then accumulates the branch's own curvature from there.
            local worldX = entryCentre + branchBend(bd) + offset * emerge
            local worldY = AK.Math.RoadHeight(branch, bd) - AK.Math.RoadHeight(branch, 0)
              + AK.Math.RoadHeight(track, branch.entry)
            local x, y, pixelsPerMetre = self:Project(dz, worldX, camX, worldY)
            local halfWidthPixels = pixelsPerMetre * tuning.roadHalf * AK.Math.RoadWidth(branch, bd)

            if previousY and y > previousY and shown < FORK_SEGMENTS then
              shown = shown + 1
              local strip = self.forkStrips[shown]
              local height = math.max(1, y - previousY)
              local midX = (x + previousX) * .5
              local midHalf = (halfWidthPixels + previousW) * .5
              local fog = AK.Math.Clamp(1 - (dz / FAR_Z) * tuning.fogStrength, 0.22, 1) * light
              local uRoad = tuning.roadHalf / ROAD_TILE
              strip.road:SetTexCoord(-uRoad, uRoad, (bd - span / FORK_SEGMENTS) / ROAD_TILE, bd / ROAD_TILE)
              strip.road:ClearAllPoints()
              strip.road:SetPoint("BOTTOM", self.frame, "CENTER", midX, previousY)
              strip.road:SetSize(math.max(2, midHalf * 2), height)
              strip.road:SetVertexColor(unpack(shade(roadColor, 0.94 * fog + (1 - fog) * 1.1)))
              strip.road:Show()

              -- Bright rails so the alternate line reads as a road and not as
              -- a shadow on the grass.
              local rail = AK.Math.Clamp(midHalf * 0.055, 1, 18)
              local glow = 0.6 + 0.4 * math.sin(race.elapsed * 6 - bd * 0.2)
              for _, pair in ipairs({ { strip.edgeLeft, -1 }, { strip.edgeRight, 1 } }) do
                local texture = pair[1]
                texture:ClearAllPoints()
                texture:SetPoint("BOTTOM", self.frame, "CENTER", midX + pair[2] * midHalf, previousY)
                texture:SetSize(rail, height)
                texture:SetVertexColor(0.35 * glow * fog, 1.0 * glow * fog, 0.45 * glow * fog)
                texture:Show()
              end
            end
            previousX, previousY, previousW = x, y, halfWidthPixels
          end
        end
      end

      -- The sign, planted on the branch's side of the split.
      if entryDz > 2 and entryDz < FAR_Z then
        local signX, signY = self:RoadAt(track, branch.entry)
        local x, y, pixelsPerMetre = self:Project(entryDz,
          signX + side * tuning.roadHalf * entryWidth * 1.05, camX, signY)
        local size = AK.Math.Clamp(pixelsPerMetre * 2.6, 16, 190)
        self.forkSign:ClearAllPoints()
        self.forkSign:SetPoint("BOTTOM", self.frame, "CENTER", x, y)
        self.forkSign:SetSize(size * 0.9, size)
        -- Two files rather than one flipped texture: SetRotation turns the UVs
        -- inside a fixed rectangle, it does not mirror the quad.
        self.forkSign:SetTexture(ART .. (side < 0 and "forkleft.tga" or "forkright.tga"))
        local flash = 0.72 + 0.28 * math.sin(race.elapsed * 7)
        self.forkSign:SetVertexColor(0.55 * flash, 1.0 * flash, 0.62 * flash, 1)
        self.forkSign:Show()
        self.forkLabel:ClearAllPoints()
        self.forkLabel:SetPoint("BOTTOM", self.frame, "CENTER", x, y + size * 1.05)
        self.forkLabel:SetText((branch.name or "SHORTCUT"):upper()
          .. (side < 0 and "  <<" or "  >>"))
        self.forkLabel:SetAlpha(AK.Math.Clamp((FAR_Z - entryDz) / 90, 0, 1))
        self.forkLabel:Show()
        signShown = true
      end
    end
  end

  if not signShown then
    self.forkSign:Hide()
    self.forkLabel:Hide()
  end
  for i = shown + 1, FORK_SEGMENTS do
    local strip = self.forkStrips[i]
    strip.road:Hide()
    strip.edgeLeft:Hide()
    strip.edgeRight:Hide()
  end
end

function RaceUI:RenderRoad(race, player)
  local tuning = self.T
  -- The road drawn is the road the player is on, branch or main line.
  local track = player.route or race.track
  self.route = track
  local roadHalf = tuning.roadHalf
  -- The feel channels are OFFSETS on the tuned baseline, applied here at read
  -- time and never stored back. `push` pulls the camera away from the kart on a
  -- boost; `dip` drops it on a landing.
  local feel = self.feel or {}
  local camZ = player.distance - (tuning.camBack + (feel.push or 0))
  -- A BRANCH IS A LINE, NOT A LOOP.
  --
  -- Taking a fork sets `vehicle.distance = 0`, and the camera trails the kart
  -- by camBack -- so for the first several metres of every branch camZ is
  -- NEGATIVE. Every lookup downstream does `% length`, which wraps a negative
  -- distance round to the branch's EXIT: the wrong curvature, the wrong height
  -- and the wrong props, for exactly the moment the player is looking hardest
  -- at the split. On the main line the wrap is correct because a lap really
  -- does loop; on a branch there is nothing behind zero.
  if track ~= race.track then camZ = math.max(0, camZ) end
  -- Draw distance is tunable, and everything downstream -- props, posts, arches,
  -- the fork ribbon, the fog curve -- reads this same upvalue, so setting it
  -- here is what makes the slider apply live.
  FAR_Z = tuning.drawDistance or 330
  -- Rebuild the forward bend for this frame before anything is projected; every
  -- road, prop, post and racer position below reads from it.
  self:BuildBend(track, camZ)
  -- The bend is already measured from the kart, so the only lateral the camera
  -- still owns is how far across the road the player has moved.
  local camX = player.lateral * roadHalf
  -- The camera rides above the road beneath it, so it crests and dips with the
  -- terrain instead of flying level through hills.
  self.camWorldY = AK.Math.RoadHeight(track, camZ) + tuning.camHeight - (feel.dip or 0)
  local roadColor = track.road or { .34, .34, .38 }
  local grassColor = track.color or { .16, .40, .18 }
  local light = (self.light or 1) * tuning.nightBoost
  -- The verge has to be lifted well above the track's base colour or the grass
  -- texture has nothing to show through. The old lift was a per-channel
  -- multiply (2.3/2.1/1.9), which brightens by SATURATING: Elwynn's green came
  -- out at (0.50, 0.97, 0.43) -- a 2:1 channel ratio that reads as poster paint
  -- rather than as turf, and it did the same to every other track's ground.
  -- Lift toward the colour's own luminance instead: same brightness, far less
  -- scream, hue preserved so the tracks still look nothing like each other.
  local grassLum = grassColor[1] * 0.30 + grassColor[2] * 0.59 + grassColor[3] * 0.11
  local vergeColor = {
    (grassColor[1] * 0.58 + grassLum * 0.42) * 2.15 + .05,
    (grassColor[2] * 0.58 + grassLum * 0.42) * 2.15 + .05,
    (grassColor[3] * 0.58 + grassLum * 0.42) * 2.15 + .05,
  }

  -- Derive the nearest sampled distance from the camera rather than fixing it:
  -- any tuned camera height or horizon must still put the first segment below
  -- the bottom edge, or a band of bare ground shows under the road.
  local lift = (self.camDepth or tuning.camDepth) * tuning.camHeight * self.halfHeight
  local nearZ = math.max(1.2, lift / (tuning.horizon + self.halfHeight + 60))
  local nearU, farU = 1 / nearZ, 1 / FAR_Z
  local step = (nearU - farU) / (SEGMENTS - 1)
  local previousX, previousY, previousW, previousZ
  local previousCeilY
  -- How enclosed the CAMERA is, which drives the whole scene's lighting.
  local camDepth = AK.TrackBuilder:TunnelDepth(track, camZ)
  self.tunnelDepth = camDepth
  -- Under cover the whole scene loses its daylight, which is most of what
  -- sells a tunnel as a place rather than as a differently textured road.
  light = light * (1 - camDepth * 0.48)

  -- Aerial perspective on the ground plane.
  --
  -- Distance used to be expressed only as `fog`, a brightness scale -- and then
  -- both ground tints added the brightness straight back: the road's
  -- `+ (1 - fog) * 1.1` term actually made the FAR road BRIGHTER than the road
  -- under your own bumper, and the verge's `+ (1 - fog) * 0.9` left grass at
  -- the horizon 8% darker than grass at your front wheels. So the two surfaces
  -- that fill most of the screen carried no depth cue whatsoever, which is most
  -- of why the world read as painted flats no matter what else was fixed.
  --
  -- What distance actually does is drain contrast and pull hue toward the
  -- colour of the air, so that is what this does: lerp the lit surface toward
  -- the horizon. It is the same wash the treeline and the sky already use, so
  -- ground, verge and skyline now recede together instead of arguing.
  local skyLow = track.skyLow or { .8, .88, .96 }
  local trackGlow = track.glow or { 1, .93, .72 }
  local haze = {
    (skyLow[1] * 0.58 + trackGlow[1] * 0.42) * light,
    (skyLow[2] * 0.58 + trackGlow[2] * 0.42) * light,
    (skyLow[3] * 0.58 + trackGlow[3] * 0.42) * light,
  }
  -- Under cover there is no sky to wash toward; the tunnel fill carries depth
  -- there instead. Capped so the far road never washes out entirely -- you
  -- still have to be able to read where it goes.
  local hazeCap = AK.Math.Clamp(0.62 * tuning.fogStrength, 0, 0.72) * (1 - camDepth)
  --- Lit surface colour blended toward the horizon. Returns r, g, b, a so it
  --- drops straight into SetVertexColor.
  local function aerial(r, g, b, lit, mix)
    r, g, b = r * lit, g * lit, b * lit
    return r + (haze[1] - r) * mix, g + (haze[2] - g) * mix, b + (haze[3] - b) * mix, 1
  end

  local nearestTunnelBand

  for i = 0, SEGMENTS - 1 do
    local dz = 1 / (nearU - i * step)
    local segZ = camZ + dz
    local strip = self.strips[i + 1]
    local worldX, worldY = self:RoadAt(track, segZ)
    local x, y, pixelsPerMetre = self:Project(dz, worldX, camX, worldY)
    local halfWidthPixels = pixelsPerMetre * roadHalf * AK.Math.RoadWidth(track, segZ)
    -- Where the roof would be at this sample, projected through the same
    -- camera as the ground so the two converge on the horizon together.
    local coverage = AK.TrackBuilder:TunnelDepth(track, segZ)
    local ceilY
    if coverage > 0 then
      local _
      _, ceilY = self:Project(dz, worldX, camX, worldY + TUNNEL_HEIGHT)
    end

    if previousY and y > previousY then
      local height = math.max(1, y - previousY)
      local midX = (x + previousX) * .5
      local midHalf = (halfWidthPixels + previousW) * .5
      -- Stripes keyed to world position, so they scroll toward the camera
      -- rather than sitting still relative to the player.
      local index = math.floor(segZ / STRIPE_LENGTH)
      local dark = (index % 2 == 0)
      -- Launch ramps get their own surface. Without this the road just tilted
      -- slightly and you took off with nothing on screen explaining why.
      local onRamp = AK.TrackBuilder:RampAt(track, segZ) ~= nil
      -- Distance fog, scaled by the track's ambient light so night circuits go
      -- dark into the distance instead of staying flatly lit.
      local fog = AK.Math.Clamp(1 - (dz / FAR_Z) * tuning.fogStrength, 0.22, 1) * light
      -- How much air is between the camera and this strip, 0 at the bumper.
      -- Slightly super-linear so the near half of the road stays crisp and the
      -- wash concentrates where the depth cue is actually needed.
      local mix = hazeCap * (AK.Math.Clamp(dz / FAR_Z, 0, 1) ^ 0.85)

      -- Subtle banding. High contrast turned the field into a striped lawn.
      -- World-locked UVs. Tying the texture to metres rather than to pixels is
      -- what keeps the paving a constant real size: the old pixel-based repeat
      -- crammed ~15 tilings across the near road, so the slabs were a blur.
      -- The strip spans prevSegZ..segZ, so map exactly that range.
      local vNear, vFar = previousZ / ROAD_TILE, segZ / ROAD_TILE
      local uRoad = roadHalf / ROAD_TILE
      strip.road:SetTexCoord(-uRoad, uRoad, vNear, vFar)
      local uGrass = (self.halfWidth / math.max(1, pixelsPerMetre)) / GRASS_TILE
      strip.grass:SetTexCoord(-uGrass, uGrass, previousZ / GRASS_TILE, segZ / GRASS_TILE)

      strip.grass:ClearAllPoints()
      strip.grass:SetPoint("BOTTOM", self.frame, "CENTER", 0, previousY)
      strip.grass:SetSize(self.halfWidth * 2, height)
      -- The verge is lifted well above the track's base colour. Tinting the
      -- texture by the raw colour produced a flat slab with no visible detail
      -- at all -- the ground read as void rather than as terrain.
      strip.grass:SetVertexColor(aerial(vergeColor[1], vergeColor[2], vergeColor[3],
        (dark and tuning.grassContrast or 1.0) * light, mix))
      strip.grass:Show()

      strip.road:ClearAllPoints()
      strip.road:SetPoint("BOTTOM", self.frame, "CENTER", midX, previousY)
      strip.road:SetSize(math.max(2, midHalf * 2), height)
      if onRamp then
        -- Hazard-striped launch surface: unmistakable, and it scrolls at you.
        local band = (math.floor(segZ / 2.2) % 2 == 0)
        local hot = band and 1.0 or 0.55
        strip.road:SetVertexColor(aerial(1.0, 0.74, 0.16, hot * light, mix))
      else
        strip.road:SetVertexColor(aerial(roadColor[1], roadColor[2], roadColor[3],
          (dark and 0.96 or 1.0) * light, mix))
      end
      strip.road:Show()

      strip.shade:ClearAllPoints()
      strip.shade:SetPoint("BOTTOM", self.frame, "CENTER", midX, previousY)
      strip.shade:SetSize(math.max(2, midHalf * 2), height)
      -- The verge darkening is a property of the surface, so it washes out
      -- with the surface rather than staying crisp on a hazed-out far road.
      strip.shade:SetAlpha(0.85 * (1 - mix))
      strip.shade:Show()

      -- Rumble width is capped: proportional-only made the near strips into
      -- enormous red slabs across the bottom of the screen.
      local rumbleWidth = AK.Math.Clamp(midHalf * (self.style == "oribos" and 0.055 or 0.05), 1, 20)
      local rr, rg, rb = .82, .22, .18
      if dark then rr, rg, rb = .95, .95, .96 end
      if self.style == "oribos" then
        -- Anima light pulsing along the verge, travelling with the stripes.
        local pulse = 0.55 + 0.45 * math.sin(segZ * 0.28 - race.elapsed * 5)
        rr, rg, rb = 0.30 * pulse, 0.82 * pulse, 1.00 * pulse
        if dark then rr, rg, rb = 1.00 * pulse, 0.72 * pulse, 0.28 * pulse end
      end
      if onRamp then
        -- Blazing rails either side of the launch, so it reads from far off.
        local flash = 0.65 + 0.35 * math.sin(race.elapsed * 12)
        rr, rg, rb = 1.0 * flash, 0.85 * flash, 0.25 * flash
      end
      rr, rg, rb = aerial(rr, rg, rb, light, mix)
      strip.rumbleLeft:ClearAllPoints()
      strip.rumbleLeft:SetPoint("BOTTOM", self.frame, "CENTER", midX - (midHalf + rumbleWidth * .5), previousY)
      strip.rumbleLeft:SetSize(rumbleWidth, height)
      strip.rumbleLeft:SetVertexColor(rr, rg, rb, 1)
      strip.rumbleLeft:Show()
      strip.rumbleRight:ClearAllPoints()
      strip.rumbleRight:SetPoint("BOTTOM", self.frame, "CENTER", midX + (midHalf + rumbleWidth * .5), previousY)
      strip.rumbleRight:SetSize(rumbleWidth, height)
      strip.rumbleRight:SetVertexColor(rr, rg, rb, 1)
      strip.rumbleRight:Show()

      if index % 4 < 2 and midHalf > 6 then
        strip.lane:ClearAllPoints()
        strip.lane:SetPoint("BOTTOM", self.frame, "CENTER", midX, previousY)
        strip.lane:SetSize(AK.Math.Clamp(midHalf * 0.04, 1, 14), height)
        local lr, lg, lb = aerial(.96, .95, .82, light, mix)
        strip.lane:SetVertexColor(lr, lg, lb, .75)
        strip.lane:Show()
      else
        strip.lane:Hide()
      end

      -- Covered section: rock overhead and to both sides.
      --
      -- The walls reach outward a fixed multiple of the road's own half-width
      -- rather than to the edge of the screen. Spanning the screen would mean a
      -- tunnel 120m away painting rock over grass 20m away; scaling with the
      -- road keeps it a compact portal that grows correctly as you approach.
      if coverage > 0 and ceilY and previousCeilY then
        local ceilTop = math.max(previousCeilY, ceilY + 1)
        local wallOut = midHalf * 1.4
        local wallHeight = math.max(1, ceilTop - previousY)
        -- Deeper in is darker, and the rock is lit far less than the road --
        -- but it must not bottom out into black. Measured, the old 0.30 floor
        -- put deep tunnel rock at 59/255 on Netherstorm and 53/255 on Deadmines
        -- once the track's own ambient light was folded in, so the covered
        -- sections read as an unlit void with no walls in them at all. 0.46
        -- lands at 90/255 while keeping the mouth (148/255) plainly brighter,
        -- so the depth gradient survives and the rock is actually visible.
        local rock = fog * (0.46 + 0.30 * (1 - coverage))
        local vNear, vFar = previousZ / TUNNEL_TILE, segZ / TUNNEL_TILE

        strip.wallLeft:SetTexCoord(0, 1.6, vNear, vFar)
        strip.wallLeft:ClearAllPoints()
        strip.wallLeft:SetPoint("BOTTOM", self.frame, "CENTER",
          midX - midHalf - wallOut * 0.5, previousY)
        strip.wallLeft:SetSize(wallOut, wallHeight)
        strip.wallLeft:SetVertexColor(rock * 1.02, rock * 0.97, rock * 0.92, 1)
        strip.wallLeft:Show()

        strip.wallRight:SetTexCoord(1.6, 0, vNear, vFar)
        strip.wallRight:ClearAllPoints()
        strip.wallRight:SetPoint("BOTTOM", self.frame, "CENTER",
          midX + midHalf + wallOut * 0.5, previousY)
        strip.wallRight:SetSize(wallOut, wallHeight)
        strip.wallRight:SetVertexColor(rock * 1.02, rock * 0.97, rock * 0.92, 1)
        strip.wallRight:Show()

        -- The ceiling ribbon spans this band's ceiling up to the nearer one,
        -- exactly as the road spans this band's ground down to the nearer one.
        local uCeil = tuning.roadHalf / TUNNEL_TILE
        strip.ceiling:SetTexCoord(-uCeil, uCeil, vNear, vFar)
        strip.ceiling:ClearAllPoints()
        strip.ceiling:SetPoint("BOTTOM", self.frame, "CENTER", midX, ceilY)
        strip.ceiling:SetSize(math.max(2, (midHalf + wallOut) * 2), math.max(1, ceilTop - ceilY))
        strip.ceiling:SetVertexColor(rock * 0.82, rock * 0.79, rock * 0.76, 1)
        strip.ceiling:Show()

        if not nearestTunnelBand then
          nearestTunnelBand = { midX = midX, midHalf = midHalf, ceil = ceilTop,
            ground = previousY, rock = rock, vNear = vNear }
        end
      elseif onRamp then
        -- Ramps are the other place the physics puts a wall, so they get one
        -- you can see: solid side rails along the launch. A barrier the player
        -- cannot see reads as a bug no matter how well it is tuned, so the two
        -- must agree -- Physics:VergeHasWall walls exactly tunnels and ramps.
        -- Sized in METRES and projected, never as a fraction of the road's
        -- on-screen half-width: midHalf is enormous in the near field, so a
        -- fraction of it drew a rail three storeys tall across half the screen.
        local railHeight = math.max(2, pixelsPerMetre * 1.15)
        local railOut = math.max(1, pixelsPerMetre * 0.40)
        local flash = 0.70 + 0.30 * math.sin(race.elapsed * 12)
        local rr2, rg2, rb2 = 0.95 * flash * fog, 0.80 * flash * fog, 0.26 * flash * fog
        for side, texture in pairs({ [-1] = strip.wallLeft, [1] = strip.wallRight }) do
          texture:SetTexCoord(0, 1, 0, 1)
          texture:ClearAllPoints()
          texture:SetPoint("BOTTOM", self.frame, "CENTER",
            midX + side * (midHalf + railOut * 0.5), previousY)
          texture:SetSize(railOut, railHeight)
          texture:SetVertexColor(rr2, rg2, rb2, 1)
          texture:Show()
        end
        strip.ceiling:Hide()
      else
        strip.wallLeft:Hide(); strip.wallRight:Hide(); strip.ceiling:Hide()
      end
    else
      strip.grass:Hide(); strip.road:Hide(); strip.lane:Hide(); strip.shade:Hide()
      strip.rumbleLeft:Hide(); strip.rumbleRight:Hide()
      strip.wallLeft:Hide(); strip.wallRight:Hide(); strip.ceiling:Hide()
    end
    previousX, previousY, previousW, previousZ = x, y, halfWidthPixels, segZ
    previousCeilY = ceilY
  end

  self:RenderSurround(camDepth, nearestTunnelBand)
  return camX, camZ
end

--- Fill the screen with rock once the camera is actually under cover.
---
--- The per-band walls draw the tunnel as a portal, which is what you want while
--- you are still approaching it. Once inside, everything the portal does not
--- cover -- outboard of the walls, above the ceiling -- is also rock, and
--- without this you would see sky through it.
function RaceUI:RenderSurround(depth, band)
  local surround = self.surround
  if not band or depth <= 0 then
    surround.left:Hide(); surround.right:Hide(); surround.top:Hide()
    if self.haze then self.haze:SetAlpha(1) end
    return
  end
  local w, h = self.halfWidth, self.halfHeight
  local rock = band.rock * 0.86

  -- ONE full-screen fill, with no edge arithmetic at all.
  --
  -- This used to compute side panels reaching inward to the outer edge of the
  -- tunnel walls, at `midX +/- midHalf * 2.4`. Inside a tunnel `nearestTunnelBand`
  -- is a NEAR band, and a near band's on-screen half-width is several times the
  -- width of the display -- so both edges clamped to the screen and both side
  -- fills collapsed to ZERO WIDTH. Only the ceiling ever drew: rock hanging
  -- overhead with open sky, trees and grass still showing to either side, which
  -- is exactly the "walls are getting closer and very transparent" report.
  --
  -- Filling the whole frame instead is simpler and cannot degenerate. The road
  -- is ARTWORK and the karts are higher still, so they draw over this on their
  -- own; the per-band walls sit just above it and keep the converging portal.
  local tileP = math.max(64, h * 0.85)
  surround.left:ClearAllPoints()
  surround.left:SetPoint("BOTTOMLEFT", self.frame, "CENTER", -w, -h)
  surround.left:SetPoint("TOPRIGHT", self.frame, "CENTER", w, h)
  surround.left:SetTexCoord(0, (w * 2) / tileP, 0, (h * 2) / tileP)
  -- Faded in over the mouth so entering is a transition, not a switch.
  surround.left:SetVertexColor(rock * 1.02, rock * 0.97, rock * 0.92, depth)
  surround.left:Show()
  surround.right:Hide()
  surround.top:Hide()

  -- The horizon haze lives on BORDER, which is a whole layer above BACKGROUND,
  -- so it paints straight over the rock. Under cover there is no horizon to
  -- soften, and leaving it up put a bright band across the middle of a tunnel.
  -- SetVertexColor already carries the haze's own .30 alpha and SetAlpha
  -- multiplies it, so this is a plain 1..0 scale, not a second alpha value.
  if self.haze then self.haze:SetAlpha(1 - depth) end
end

function RaceUI:RenderObjects(race, player, camX, camZ)
  local tuning = self.T
  local pulse = 0.5 + 0.5 * math.sin(race.elapsed * 5)
  local route = self.route or race.track

  -- Work out what is visible, then give every object a frame it KEEPS.
  --
  -- Pool slots used to be handed out by position in a per-frame list, so which
  -- frame an object landed in changed whenever anything else entered or left
  -- view. One frame would be a hovering item box on one tick and a flat dash
  -- pad on the next, and the panels appeared to jump about and swap places.
  -- Sorting the list first did NOT fix it: objects leave at the NEAR end, so
  -- every index behind them shifts regardless of which way it is ordered.
  --
  -- The fix is identity. An object claims a slot when it comes into view and
  -- holds that same slot until it leaves, so its frame never changes underneath
  -- it. The sort now only decides WHO gets drawn when more objects are in view
  -- than there are frames -- nearest wins, since those are the readable ones.
  self.visibleObjects = self.visibleObjects or {}
  self.slotOwner = self.slotOwner or {}
  self.slotOf = self.slotOf or {}
  self.slotLive = self.slotLive or {}
  self.slotDrawn = self.slotDrawn or {}
  local visible, slotOwner, slotOf = self.visibleObjects, self.slotOwner, self.slotOf
  local live, drawn = self.slotLive, self.slotDrawn
  local capacity = #self.objectFrames

  -- Trackside objects get a SHORTER draw distance than the road, and fade in
  -- over the end of it.
  --
  -- The bend model integrates curvature twice, so the road's screen offset grows
  -- quadratically with how far ahead you look. Measured (verify-render.js), the
  -- road is already past the screen edge by 80m on every track in this game and
  -- reaches 2.1-2.9 half-screens at the full 330m draw distance. Objects were
  -- drawn that whole way, so a far pickup sat as a chip near the screen edge
  -- with no road under it and then swung inward as you closed -- which is the
  -- "things slide in from off screen" read. The size floor in :ObjectSize and
  -- the 0.22 alpha floor in :FogAt are what kept those chips visible instead of
  -- letting them disappear into the haze.
  -- Measured (verify-render.js): the road is fully on screen 96-100% of a lap at
  -- 60m, 76-97% at 100m, but only 61-89% at 140m and 52-74% at 191m. Objects
  -- drawn out to 191m therefore spent much of a lap appearing where the road
  -- had already swung off the display, so they entered at the screen edge and
  -- travelled inward -- "sliding in from the distance instead of just being on
  -- the track". Pulling the draw distance back to where the road is reliably on
  -- screen is what makes a pickup appear ON the road and simply grow.
  local objectFar = FAR_Z * 0.36

  local count = 0
  for _, object in ipairs(race.objects) do
    local dz = AK.Math.SignedLoopDistance(camZ % route.length, object.distance, route.length)
    if dz > 1.5 and dz < objectFar and not object.hidden and self:OnRoute(race, object) then
      count = count + 1
      local entry = visible[count]
      if not entry then entry = {} visible[count] = entry end
      entry.object, entry.dz = object, dz
    end
  end
  -- Entries are reused rather than rebuilt; spares are parked at math.huge so
  -- one sort over the whole array leaves them harmlessly at the end.
  for i = count + 1, #visible do visible[i].object, visible[i].dz = nil, math.huge end
  table.sort(visible, function(a, b) return a.dz < b.dz end)
  local showCount = math.min(count, capacity)

  -- Release the slots of anything that has left view, THEN fill the gaps. Doing
  -- it in that order is what lets a departing object hand its frame straight to
  -- an arriving one without disturbing everybody in between.
  wipe(live)
  for i = 1, showCount do
    local object = visible[i].object
    local slot = slotOf[object]
    if slot and slotOwner[slot] == object then live[slot] = true end
  end
  for slot = 1, capacity do
    local owner = slotOwner[slot]
    if owner and not live[slot] then slotOf[owner], slotOwner[slot] = nil, nil end
  end
  local free = 1
  for i = 1, showCount do
    local object = visible[i].object
    if not slotOf[object] then
      while free <= capacity and slotOwner[free] do free = free + 1 end
      if free > capacity then break end
      slotOwner[free], slotOf[object] = object, free
    end
  end

  wipe(drawn)
  for index = 1, showCount do
    local object, dz = visible[index].object, visible[index].dz
    local slot = object and slotOf[object]
    if slot then
      drawn[slot] = true
      local frame = self.objectFrames[slot]
      local style = OBJECT_STYLE[object.kind] or OBJECT_STYLE.hazard
      -- A Fake Item Box must be indistinguishable from a real one. Its entire
      -- function is that players are trained to drive into anything box-shaped;
      -- tinting it or labelling it would defeat the item completely.
      if object.fake then style = OBJECT_STYLE.box end
      -- camZ + dz, not object.distance -- see the note in RenderProps. Object
      -- distances are lap-relative and `Bend` measures from an absolute camZ.
      local baseX, worldY = self:RoadAt(self.route or race.track, camZ + dz)
      local x, y, pixelsPerMetre = self:Project(dz, baseX + object.lateral * tuning.roadHalf, camX, worldY)
      -- Floor the size well above zero: a pickup you cannot see is a pickup you
      -- cannot dodge, and the whole point is reading them early.
      local size = self:ObjectSize(pixelsPerMetre, style.size)
      local color = style.color
      local fog = self:FogAt(dz)
      local flat = style.flat

      -- Fade in from the far end, and fade out towards the screen edge, so
      -- anything the corner has swung off-axis is gone before it can be seen
      -- travelling. Applied to the frame so every layer -- pad, ring, icon,
      -- shadow, label -- fades together on exactly the same curve.
      frame:SetAlpha(self:DepthFade(dz, objectFar) * self:EdgeFade(x, dz))
      -- Cubes hover and bob; pads are painted on the tarmac and never leave it.
      -- Low. A box that floats half its own height off the tarmac reads as a
      -- sticker hanging in the air; MK64's barely leave the ground and the bob
      -- is small. The SHADOW does the work of selling the gap, not the height.
      local hover = style.float
        and (size * 0.20 + math.sin(race.elapsed * 2.4 + object.distance) * size * 0.06) or 0

      frame:ClearAllPoints()
      frame:SetPoint("BOTTOM", self.frame, "CENTER", x, y + hover)
      frame:SetSize(size, size)
      frame:SetFrameLevel(self:DepthLevel("object", dz))

      -- Contact shadow, pinned to the ROAD rather than to the frame above it.
      -- It shrinks and fades as the box rises, which is what reads as height --
      -- a shadow that bobs along with the object just looks like part of it.
      local lift = size > 0 and hover / size or 0
      frame.shadow:ClearAllPoints()
      frame.shadow:SetPoint("CENTER", self.frame, "CENTER", x, y + size * 0.05)
      frame.shadow:SetSize(size * (flat and 1.30 or 1.02) * (1 - lift * 0.30),
        math.max(2, size * (flat and 0.36 or 0.34) * (1 - lift * 0.30)))
      frame.shadow:SetAlpha((flat and 0.34 or 0.62) * fog * (1 - lift * 0.45))

      -- Rotation is POOLED STATE and must be written on every path.
      --
      -- Only the item-box branch below ever touched it, so the first time a
      -- frame that had been a spinning box was handed to a dash pad, the pad
      -- inherited the box's rotation -- a wide flat quad drawn with a spin on
      -- it, tumbling as the box's angle kept advancing. THAT is what "the dash
      -- pads flip about and move around strangely" actually was. Reordering the
      -- draw list never had a chance of fixing it; churn only decided how often
      -- a frame changed hands and so how often the bug fired.
      if frame.icon.SetRotation then
        frame.icon:SetRotation(style.spin
          and ((race.elapsed * 0.9 + object.distance * 0.05) % (math.pi * 2)) or 0)
      end

      if flat then
        -- A dash panel is PAINTED ON the road. Drawn as a wide, short quad at
        -- ground level, so it lies in the surface instead of standing up out of
        -- it like a signpost -- an upright square was most of why these read as
        -- icons on a shelf.
        -- Height floors must be SCREEN-RELATIVE, like every other size here.
        --
        -- Laying the panel flat multiplies its size by ~0.3, and the floor left
        -- behind was an absolute 3px. Rendered and compared against OLDOBJ, a
        -- distant dash panel collapsed to a 3px sliver where the upright icon it
        -- replaced was a readable 22px plate -- so flattening them, which fixed
        -- the "icons on a shelf" read, quietly cost most of their visibility.
        -- That is the "dash panels used to be good and have got worse" report,
        -- and it is a floor bug, not a case against flat panels.
        local minH = self.halfWidth * 0.009
        frame.pad:SetSize(size * 1.50, math.max(minH, size * 0.34))
        frame.pad:SetVertexColor(color[1], color[2], color[3], 1)
        frame.pad:SetAlpha((.34 + pulse * .30) * fog)
        frame.beam:Hide()
        frame.icon:SetSize(size * 1.42, math.max(minH, size * 0.32))
        if frame.iconApplied ~= style.icon then
          frame.iconApplied = style.icon
          frame.icon:SetTexture(style.icon)
        end
        frame.icon:SetVertexColor(color[1] * fog, color[2] * fog, color[3] * fog)
        -- Fixed width, pulsing only in brightness. A flat plate that also
        -- breathes in and out reads as sliding around on the road.
        frame.ring:SetSize(size * 1.46, math.max(2, size * 0.06))
        frame.ring:SetAlpha((.30 + pulse * .35) * fog)
      else
        frame.pad:SetSize(size * 1.2, math.max(3, size * 0.26))
        frame.pad:SetVertexColor(color[1], color[2], color[3], 1)
        frame.pad:SetAlpha((.30 + pulse * .28) * fog)
        -- Narrow, faint shaft. The old wide one read as a solid blue box.
        frame.beam:Show()
        frame.beam:SetSize(math.max(2, size * 0.10), size * 1.25)
        frame.beam:SetVertexColor(color[1], color[2], color[3], 1)
        frame.beam:SetAlpha((.10 + pulse * .12) * fog)
        frame.icon:SetSize(size, size)
        if frame.iconApplied ~= style.icon then
          frame.iconApplied = style.icon
          frame.icon:SetTexture(style.icon)
        end
        frame.icon:SetVertexColor(fog, fog, fog)
        frame.ring:SetSize(size * (1.05 + pulse * .10), math.max(2, size * 0.05))
        frame.ring:SetAlpha((.45 + pulse * .45) * fog)
      end
      frame.ring:SetVertexColor(color[1], color[2], color[3], 1)
      frame.label:SetText(size > self.halfWidth * 0.04 and style.label or "")
      frame.label:SetTextColor(color[1], color[2], color[3])
      frame:Show()
    end
  end
  for slot = 1, capacity do
    if not drawn[slot] then self.objectFrames[slot]:Hide() end
  end
end

--- Course hazards: the track's own antagonists, drawn like any other object.
function RaceUI:RenderHazards(race, camX, camZ)
  local tuning = self.T
  local pulse = 0.5 + 0.5 * math.sin(race.elapsed * 4)
  -- Same identity rule as RenderObjects, and it matters even more here: every
  -- hazard frame carries a creature MODEL, so a hazard that gets handed a
  -- different pool slot re-specs that model and pops through a reload. One
  -- hazard dropping out of view used to shift every hazard behind it by a slot.
  self.hazardSlotOwner = self.hazardSlotOwner or {}
  self.hazardSlotOf = self.hazardSlotOf or {}
  self.hazardLive = self.hazardLive or {}
  self.hazardDrawn = self.hazardDrawn or {}
  self.visibleHazards = self.visibleHazards or {}
  local hOwner, hOf = self.hazardSlotOwner, self.hazardSlotOf
  local hLive, hDrawn, hVisible = self.hazardLive, self.hazardDrawn, self.visibleHazards
  local hazardCap = #self.hazardFrames
  local routeLength = (self.route or race.track).length
  -- Same shortened draw distance as the trackside objects, for the same reason:
  -- past it the road has bent off-screen and a hazard out there is a creature
  -- model floating at the display edge. See RenderObjects for the measurements.
  local hazardFar = FAR_Z * 0.36
  local hFadeFrom = hazardFar * 0.70

  local hCount = 0
  for _, hazard in ipairs(race.hazards or {}) do
    local dz = AK.Math.SignedLoopDistance(camZ % routeLength,
      hazard.distance % routeLength, routeLength)
    if dz > 1.5 and dz < hazardFar then
      hCount = hCount + 1
      local entry = hVisible[hCount]
      if not entry then entry = {} hVisible[hCount] = entry end
      entry.hazard, entry.dz = hazard, dz
    end
  end
  for i = hCount + 1, #hVisible do hVisible[i].hazard, hVisible[i].dz = nil, math.huge end
  table.sort(hVisible, function(a, b) return a.dz < b.dz end)
  local hShow = math.min(hCount, hazardCap)

  wipe(hLive)
  for i = 1, hShow do
    local slot = hOf[hVisible[i].hazard]
    if slot and hOwner[slot] == hVisible[i].hazard then hLive[slot] = true end
  end
  for slot = 1, hazardCap do
    local owner = hOwner[slot]
    if owner and not hLive[slot] then hOf[owner], hOwner[slot] = nil, nil end
  end
  local hFree = 1
  for i = 1, hShow do
    local hazard = hVisible[i].hazard
    if not hOf[hazard] then
      while hFree <= hazardCap and hOwner[hFree] do hFree = hFree + 1 end
      if hFree > hazardCap then break end
      hOwner[hFree], hOf[hazard] = hazard, hFree
    end
  end

  wipe(hDrawn)
  for index = 1, hShow do
    local hazard, dz = hVisible[index].hazard, hVisible[index].dz
    local slot = hazard and hOf[hazard]
    if slot then
      hDrawn[slot] = true
      local frame = self.hazardFrames[slot]
      -- camZ + dz, not hazard.distance -- see the note in RenderProps.
      local baseX, worldY = self:RoadAt(self.route or race.track, camZ + dz)
      local x, y, ppm = self:Project(dz, baseX + hazard.lateral * tuning.roadHalf, camX, worldY)
      local size = self:ObjectSize(ppm, 2.6)
      local fog = self:FogAt(dz)
      local appear = 1
      if dz > hFadeFrom then
        appear = AK.Math.Clamp((hazardFar - dz) / (hazardFar - hFadeFrom), 0, 1)
      end
      frame:SetAlpha(appear * self:EdgeFade(x, dz))
      frame:ClearAllPoints()
      frame:SetPoint("BOTTOM", self.frame, "CENTER", x, y)
      frame:SetSize(size, size)
      frame:SetFrameLevel(self:DepthLevel("hazard", dz))
      -- Contact shadow so the creature stands on the road instead of hovering
      -- in front of it. Anchored to the race frame at ground height.
      frame.shadow:ClearAllPoints()
      frame.shadow:SetPoint("CENTER", self.frame, "CENTER", x, y + size * 0.05)
      frame.shadow:SetSize(size * 0.92, math.max(2, size * 0.30))
      frame.shadow:SetAlpha(0.58 * fog)
      frame.glow:SetSize(size * 1.7, size * 1.7)
      frame.glow:SetAlpha((0.18 + pulse * 0.20) * fog)
      frame.label:SetText(size > self.halfWidth * 0.042 and hazard.name:upper() or "")

      -- Same rule as the karts: show the frame so it can stream in, and let the
      -- icon cover the gap until it has.
      local ready = false
      if hazard.model and not self.suppressModels then
        AK.Model:SetSpec(frame.model, hazard.model)
        frame.model:SetSize(size * 2.4, size * 2.4)
        frame.model:SetPoint("CENTER", frame, "BOTTOM", 0, size * 0.42)
        -- Creature hazards face the oncoming field, and the moving ones lean
        -- into their sweep so a patrol reads as walking rather than sliding.
        frame.model:SetFacing(math.pi + (hazard.lateral or 0) * 0.6)
        AK.Model:Reframe(frame.model)
        frame.model:Show()
        ready = AK.Model:IsReady(frame.model)
      else
        frame.model:Hide()
      end
      -- Not every hazard has a creature to be, and the ones that do not were
      -- drawing a raw ability icon -- square, bordered, unmistakably a piece of
      -- inventory UI sitting on the track. Trimming the border off and tinting
      -- it with the hazard's own colour at least makes it read as an object in
      -- the world rather than a spellbook button someone dropped.
      frame.icon:SetShown(not ready)
      local hazardIcon = hazard.icon or "Interface\\Icons\\Spell_Fire_SelfDestruct"
      if frame.iconApplied ~= hazardIcon then
        frame.iconApplied = hazardIcon
        frame.icon:SetTexture(hazardIcon)
      end
      frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      local tint = hazard.color or { 1, 1, 1 }
      frame.icon:SetVertexColor(tint[1], tint[2], tint[3])
      frame.icon:SetSize(size, size)
      frame:Show()
    end
  end
  for slot = 1, hazardCap do
    if not hDrawn[slot] then self.hazardFrames[slot]:Hide() end
  end
end

--- Your previous best, replayed. Deliberately ghostly: translucent, no name
--- tag, no shadow, and it takes no part in the race whatsoever.
function RaceUI:RenderGhost(race, camX, camZ)
  local state = race.ghostState
  if not state or not self.ghostKart then
    if self.ghostKart then self.ghostKart:Hide() end
    return
  end
  local tuning = self.T
  local dz = AK.Math.SignedLoopDistance(camZ % (self.route or race.track).length,
    state.distance % (self.route or race.track).length, (self.route or race.track).length)
  if dz <= 0.9 or dz >= FAR_Z then self.ghostKart:Hide() return end

  -- camZ + dz: the ghost's recorded distance is lap-relative, so it hits the
  -- same clamp as the props did. See the note in RenderProps.
  local baseX, worldY = self:RoadAt(self.route or race.track, camZ + dz)
  local x, y, ppm = self:Project(dz, baseX + state.lateral * tuning.roadHalf, camX, worldY)
  local width = AK.Math.Clamp(ppm * 2.2 * tuning.kartScale, 14, self.halfWidth * 0.72)
  self.ghostKart:ClearAllPoints()
  self.ghostKart:SetPoint("BOTTOM", self.frame, "CENTER", x, y)
  self.ghostKart:SetSize(width, width)
  self.ghostKart:SetFrameLevel(self.frame:GetFrameLevel() + 140)
  -- The ghost is your own previous run, so it wears the kart you are driving.
  local ghostArt = kartTexture(state.kartId or AK.db.selection.kart)
  if self.ghostArtApplied ~= ghostArt then
    self.ghostArtApplied = ghostArt
    self.ghostBody:SetTexture(ghostArt)
  end
  self.ghostBody:SetSize(width * 1.05, width * 1.05 * 0.625)
  self.ghostBody:SetVertexColor(0.55, 0.85, 1.0)
  -- Ghostly by design, and faded again by how far off-axis a corner has thrown
  -- it -- otherwise the one kart you are racing against in a Time Trial is the
  -- one thing still sliding in from the screen edge.
  self.ghostKart:SetAlpha(0.38 * self:EdgeFade(x, dz))
  self.ghostKart:Show()
end

--- Shells, bananas and bombs, projected onto the road like anything else.
function RaceUI:RenderProjectiles(race, camX, camZ)
  local tuning = self.T
  local shown = 0
  for _, projectile in ipairs(race.projectiles) do
    if shown >= #self.projectileFrames then break end
    local dz = AK.Math.SignedLoopDistance(camZ % (self.route or race.track).length,
      projectile.distance % (self.route or race.track).length, (self.route or race.track).length)
    if dz > 1 and dz < FAR_Z then
      shown = shown + 1
      local shot = self.projectileFrames[shown]
      local item = projectile.item
      local baseX, worldY = self:RoadAt(self.route or race.track, projectile.distance)
      local x, y, pixelsPerMetre = self:Project(dz, baseX + projectile.lateral * tuning.roadHalf, camX, worldY)
      local size = self:ObjectSize(pixelsPerMetre, 1.5)
      local fog = self:FogAt(dz)
      -- Thrown items hop and spin along; a dropped banana sits still.
      local moving = projectile.speed > 0
      local bob = moving and math.abs(math.sin(projectile.age * 11)) * size * 0.22 or 0
      projectile.screenX, projectile.screenY = x, y + bob

      shot:ClearAllPoints()
      shot:SetPoint("BOTTOM", self.frame, "CENTER", x, y + bob)
      shot:SetSize(size, size)
      -- Same stride as the karts so a shell still sorts against the field by
      -- depth; the constant 40 below a kart at equal depth is preserved.
      -- Same bucketing and stride as the karts, 10 below a kart at equal depth
      -- as before, so shells still sort against the field. A kart's three
      -- levels cover all residues mod 3, so a shot CAN tie with one of them at
      -- certain relative depths; the only consequence is undefined order
      -- between a shell and a bumper, which is not worth another band.
      shot:SetFrameLevel(self:DepthLevel("shot", dz))
      if shot.iconApplied ~= item.icon then
        shot.iconApplied = item.icon
        shot.icon:SetTexture(item.icon)
      end
      -- Item icons are WoW ability art with a baked border. Trimmed so a shell
      -- on the road stops reading as a spellbook button someone dropped.
      shot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      local tint = item.tint or { 1, 1, 1 }
      shot.icon:SetVertexColor(tint[1] * fog, tint[2] * fog, tint[3] * fog)
      shot.glow:SetSize(size * 1.9, size * 1.9)
      shot.glow:SetVertexColor(item.color[1], item.color[2], item.color[3], 1)
      shot.glow:SetAlpha((moving and (0.35 + 0.25 * math.sin(projectile.age * 14)) or 0.18) * fog)
      -- Ground shadow: anchored to the RACE frame, not to this bobbing one, so
      -- a hopping shell throws a shadow that stays on the tarmac. Previously it
      -- was a child of the frame and rose with the item, which is exactly the
      -- "floating" read -- the item and its shadow moved as one sticker.
      local lift = size > 0 and bob / size or 0
      shot.shadow:ClearAllPoints()
      shot.shadow:SetPoint("CENTER", self.frame, "CENTER", x, y + size * 0.05)
      shot.shadow:SetSize(size * 0.9 * (1 - lift * 0.35), math.max(2, size * 0.30 * (1 - lift * 0.35)))
      shot.shadow:SetAlpha(0.5 * fog * (1 - lift * 0.5))
      -- On the frame, so the icon, its glow and the shadow all go together. The
      -- shadow is ANCHORED to the race frame but PARENTED to this one, so it
      -- inherits this; multiplying the fade into it as well would square it.
      shot:SetAlpha(self:EdgeFade(x, dz))
      shot:Show()

      -- Sparks trailing a live shot so it reads as fast, not floating.
      if moving and math.random() < 0.55 then
        self:Emit(x, y + bob + size * 0.3, size * 0.22, item.color, 0.28,
          (math.random() - .5) * 60, -40 - math.random() * 60, -260)
      end
    end
  end
  for i = shown + 1, #self.projectileFrames do self.projectileFrames[i]:Hide() end
end

--- Called by the simulation when a projectile connects.
function RaceUI:ProjectileHit(projectile, hitThePlayer)
  local color = projectile.item.color
  local x, y, width = self.playerX or 0, self.playerY or 0, self.playerWidth or 60
  -- Explosion at the point of contact.
  self:PlayEffect("burst", x, y + width * 0.4, width * 2.4, color)
  self:PlayEffect("shock", x, y + width * 0.3, width * 2.0, color)
  if hitThePlayer then
    self:Flash(color, .20)
    self:Shake(20)
  end
  for i = 1, 22 do
    local angle = math.random() * math.pi * 2
    self:Emit(x, y + width * 0.35, width * 0.20, color, 0.4 + math.random() * 0.3,
      math.cos(angle) * 340, math.sin(angle) * 300 + 140, -520)
  end
  -- Three layers a few milliseconds apart: the only way to build weight out of
  -- a fixed library of one-shot UI blips.
  if AK.PlayStinger then AK:PlayStinger("collision", 3, 0.045) end
end

--- Two items destroying each other out on the track.
function RaceUI:ProjectileClash(first, second)
  -- Projectiles record where they were last drawn, so the blast lands on the
  -- items rather than guessing at a screen position.
  local x = first.screenX or second.screenX or 0
  local y = first.screenY or second.screenY or (self.playerY or 0)
  local color = first.item.color
  self:PlayEffect("burst", x, y + 40, 120, color)
  self:PlayEffect("shock", x, y + 30, 100, second.item.color)
  for i = 1, 12 do
    local angle = math.random() * math.pi * 2
    self:Emit(x, y + 40, 14, color, 0.32,
      math.cos(angle) * 220, math.sin(angle) * 200 + 80, -460)
  end
  if AK.PlaySfx then AK:PlaySfx("collision") end
end

--- Item box breaking open: shards flying off plus a quick pop.
function RaceUI:BoxShatter()
  local x, y, width = self.playerX or 0, self.playerY or 0, self.playerWidth or 60
  self:PlayEffect("pop", x, y + width * 0.6, width * 1.4, { 1, .86, .35 })
  for i = 1, 14 do
    local angle = math.random() * math.pi * 2
    self:Emit(x, y + width * 0.6, width * 0.16, { 1, .88, .45 }, 0.35 + math.random() * 0.25,
      math.cos(angle) * 300, math.sin(angle) * 260 + 130, -540)
  end
end

function RaceUI:RenderKarts(race, player, camX, camZ)
  local tuning = self.T
  for index, vehicle in ipairs(race.vehicles) do
    local kart = self.karts[index]
    local dz = AK.Math.SignedLoopDistance(camZ % (self.route or race.track).length, vehicle.distance % (self.route or race.track).length, (self.route or race.track).length)
    if dz > 0.9 and dz < FAR_Z and not vehicle.finished and self:OnRoute(race, vehicle) then
      local baseX, worldY = self:RoadAt(self.route or race.track, vehicle.distance)
      local x, y, pixelsPerMetre = self:Project(dz, baseX + vehicle.lateral * tuning.roadHalf, camX, worldY)
      -- A kart is about 2.2m wide; scale the sprite by the same projection as
      -- the road so near racers loom and distant ones shrink correctly.
      -- Lightning leaves you tiny; flattening squashes you further still.
      local sizeScale = 1
      if (vehicle.shrunk or 0) > 0 then sizeScale = 0.46 end
      if (vehicle.flattened or 0) > 0 then sizeScale = sizeScale * 0.60 end
      -- Screen-relative cap, not an absolute pixel cap -- 460px was a third of
      -- a 1280 preview and a sixth of a 1440p client.
      --
      -- There is deliberately no minimum size. A floor was tried and it was a
      -- mistake: the kart's projected size is 2.2m of road seen from camBack
      -- metres, so it is already correct by construction -- roughly a quarter
      -- of the road's width, at any resolution. Forcing a screen-relative
      -- minimum on top of that fought the perspective, and when the camera sat
      -- far back it inflated a kart that was still drawn up near the horizon.
      -- If the kart looks wrong, the camera is wrong; fix it there.
      local width = AK.Math.Clamp(pixelsPerMetre * 2.2 * tuning.kartScale * sizeScale, 10, self.halfWidth * 0.72)
      local height = width

      -- Suspension. A kart travelling over paving should never sit perfectly
      -- still: bounce scales with speed and doubles over rough ground.
      local travel = vehicle.speed / math.max(1, vehicle.maxSpeed)
      local bumpRate = 13 + travel * 16
      local bump = math.sin(vehicle.distance * 0.9 + (vehicle.seed or 0)) * travel
      if vehicle.offroad then bump = bump + math.sin(race.elapsed * bumpRate) * 1.6 end
      local bounce = bump * width * 0.022
      -- Airtime from a blast: a clean arc up and back down.
      local hop = vehicle.hop or 0
      if hop > 0 then
        local t = 1 - hop / math.max(0.01, vehicle.hopMax or 1)
        bounce = bounce + math.sin(t * math.pi) * width * 1.15
      end
      -- Standalone hop from tapping the drift key without steering.
      local plainHop = vehicle.hopAir or 0
      if plainHop > 0 then
        local t = 1 - plainHop / math.max(0.01, vehicle.hopAirMax or 1)
        bounce = bounce + math.sin(t * math.pi) * width * 0.42
      end
      -- Drift hop: short, snappy, at the moment the drift engages.
      local dhop = vehicle.driftHop or 0
      if dhop > 0 then
        local t = 1 - dhop / math.max(0.01, vehicle.driftHopMax or 1)
        bounce = bounce + math.sin(t * math.pi) * width * 0.30
      end
      -- Ramp airtime: a long, high arc, well above the blast hop.
      local air = vehicle.air or 0
      if air > 0 then
        local t = 1 - air / math.max(0.01, vehicle.airMax or 1)
        bounce = bounce + math.sin(t * math.pi) * width * 2.1
      end

      -- The world yaws around the player, so take most of the yaw back off
      -- their own kart. Leaving a little in lets it drift toward the outside of
      -- the corner, which is what a chase camera actually does.
      local drawX = x
      if vehicle == player then drawX = x - (self.yawShift or 0) * 0.85 end

      kart:ClearAllPoints()
      kart:SetPoint("BOTTOM", self.frame, "CENTER", drawX, y + bounce)
      kart:SetSize(width, height)
      -- Nearer karts must draw over further ones -- and each kart needs THREE
      -- exclusive levels, because it is three stacked frames: chassis behind,
      -- driver, chassis-front.
      --
      -- The stride used to be 1. Two karts a metre apart therefore overlapped:
      -- the further kart's driver sat on the same level as the nearer kart's
      -- body, and its front chassis on the same level as the nearer driver. So
      -- riders rendered through neighbouring karts, which is why it happened
      -- across the whole field rather than on one racer. A stride of 4 leaves
      -- each kart a level of headroom and cannot interleave.
      -- Depth is bucketed to 2m so a stride of 3 still fits the layer budget:
      -- 160..382, comfortably under the tag layer at 400. Widening the stride
      -- without shrinking the range instead pushed karts past 1200, over the
      -- main menu at 700 -- a worse bug than the one being fixed.
      local level = self:DepthLevel("kart", dz)
      kart:SetFrameLevel(level)
      -- Driver behind, chassis in front, so they are sitting in the kart.
      kart.model:SetFrameLevel(level + 1)
      kart.chassis:SetFrameLevel(level + 2)

      -- Lean: derived from how fast the racer is sliding across the road, plus
      -- an extra kick while drifting. This is what makes Baine look alive.
      local memory = self.previous[index]
      local lastLateral = memory and memory.lateral or vehicle.lateral
      local slide = vehicle.lateral - lastLateral
      local lean = AK.Math.Clamp(slide * 26, -0.55, 0.55) * tuning.leanAmount
      if vehicle.drifting then lean = lean + (vehicle.driftDirection or 0) * 0.4 * tuning.leanAmount end
      if memory then memory.lateral = vehicle.lateral end
      -- Spin-out: whole kart rotates through several turns, easing to a stop.
      local spin = vehicle.spin or 0
      local spinTurns = 0
      if spin > 0 then
        local t = spin / math.max(0.01, vehicle.spinMax or 1)
        spinTurns = t * t * math.pi * 2 * 2.5
      end

      -- The shadow stays on the ground and tightens as the kart lifts, which is
      -- what makes the bounce read as height rather than as sliding.
      kart.shadow:ClearAllPoints()
      kart.shadow:SetPoint("BOTTOM", self.frame, "CENTER", drawX, y - 1)
      kart.shadow:SetSize(width * (1.15 - math.abs(bounce) / math.max(1, width) * 1.2), math.max(3, height * .22))
      kart.shadow:SetAlpha(0.55 - math.abs(bounce) / math.max(1, width) * 0.8)
      -- Kart art is 256x160, so keep that ratio or the wheels distort.
      local bodyWidth = width * 1.05
      local bodyHeight = bodyWidth * 0.625
      -- Lightning squashes you flat for a moment.
      local squash = vehicle.squash or 0
      if squash > 0 then
        local t = squash / math.max(0.01, vehicle.squashMax or 1)
        bodyWidth = bodyWidth * (1 + t * 0.35)
        bodyHeight = bodyHeight * (1 - t * 0.45)
      end
      -- A spin-out narrows the kart as it turns side-on to the camera.
      if spinTurns > 0 then
        bodyWidth = bodyWidth * (0.35 + 0.65 * math.abs(math.cos(spinTurns)))
      end
      -- Body art follows the kart, and only when it actually changes: SetTexture
      -- every frame on eight racers would re-bind the same file 480 times a
      -- second for nothing.
      local art = kartTexture(vehicle.kart.id)
      if kart.artApplied ~= art then
        kart.artApplied = art
        kart.body:SetTexture(art)
        kart.lip:SetTexture(art)
      end
      kart.body:SetSize(bodyWidth, bodyHeight)

      -- Star power flickers gold through the whole kart.
      local br, bg, bb = unpack(vehicle.kart.color)
      if (vehicle.star or 0) > 0 then
        local flash = 0.6 + 0.4 * math.sin(race.elapsed * 22)
        br, bg, bb = 1, 0.75 * flash + 0.25, 0.25 * flash
      end
      kart.body:SetVertexColor(br, bg, bb)
      kart.body:SetDesaturated(vehicle.stun > 0)

      -- Front slice: the bottom `kartLip` fraction of the same texture, drawn
      -- over the driver's legs. Zero the knob to disable it entirely.
      local lip = AK.Math.Clamp(tuning.kartLip, 0, 0.95)
      kart.lip:SetShown(lip > 0.01)
      if lip > 0.01 then
        kart.lip:SetTexCoord(0, 1, 1 - lip, 1)
        kart.lip:SetSize(bodyWidth, bodyHeight * lip)
        kart.lip:SetVertexColor(br, bg, bb)
        kart.lip:SetDesaturated(vehicle.stun > 0)
      end
      kart.flame:SetSize(math.max(3, width * .38), math.max(3, height * .22))
      kart.flame:SetAlpha((vehicle.boostTime > 0 or vehicle.speed > vehicle.maxSpeed * .91) and (AK.db.settings.reducedEffects and .3 or .8) or 0)
      kart.flame:SetVertexColor(unpack(vehicle.boostTime > 0 and AK.COLORS.gold or { 1, .35, .12 }))
      kart.trail:SetSize(width * 1.1, height * 0.42)
      kart.trail:SetAlpha(vehicle.boostTime > 0 and (AK.db.settings.reducedEffects and .08 or .22) or 0)

      -- Drift sparks. Everything here is a fraction of the kart's drawn width,
      -- so they scale with distance and resolution like the kart itself.
      local sparkTier = vehicleIsDrifting(vehicle) and driftTier(vehicle.driftCharge) or 0
      if sparkTier > 0 and not AK.db.settings.reducedEffects then
        local hue = driftColor(vehicle.driftCharge)
        -- Bigger and busier with each tier, and flickering faster -- the rate is
        -- as much of the read as the colour.
        local flicker = 0.62 + 0.38 * math.sin(race.elapsed * (16 + sparkTier * 9)
          + (vehicle.seed or 0))
        local size = width * (0.20 + sparkTier * 0.07)
        -- Outboard of the bodywork and down at road level, NOT tucked under the
        -- kart. Rendered, tier 1's blue sparks vanished completely against a
        -- blue kart -- and since the player picks the kart colour, no tier hue
        -- is safe from that. Putting them beside the silhouette means they are
        -- always read against tarmac, whatever colour the kart is.
        for side, spark in pairs({ [-1] = kart.sparkL, [1] = kart.sparkR }) do
          spark:ClearAllPoints()
          spark:SetPoint("CENTER", kart, "BOTTOM", side * width * 0.46, height * 0.02)
          spark:SetSize(size, size)
          spark:SetVertexColor(hue[1], hue[2], hue[3], 1)
          spark:SetAlpha((0.45 + 0.30 * sparkTier / 3) * flicker)
        end
      else
        kart.sparkL:SetAlpha(0)
        kart.sparkR:SetAlpha(0)
      end

      -- Each racer wears their own appearance and sits at their own height;
      -- both calls no-op unless something actually changed.
      -- A PlayerModel that is never shown never streams its model in. Gating
      -- the Show() on IsReady() therefore deadlocked: hidden, so it never
      -- loaded, so it was never ready, so it stayed hidden -- and every racer
      -- fell back to the flat kart icon no matter which racer was chosen.
      -- The frame is shown as soon as it has a spec; an unloaded model simply
      -- draws nothing, and the icon covers that gap.
      local modelReady = false
      if not self.suppressModels then
        AK.Model:SetSpec(kart.model, AK:GetRacerModel(vehicle))
        AK.Model:SetSeat(kart.model, vehicle.racer)
        modelReady = AK.Model:IsReady(kart.model)
        kart.model:Show()
        -- RETRY A STUCK MODEL.
        --
        -- Loading is asynchronous and the completion can simply be lost: a
        -- PlayerModel hidden part-way through a stream may never fire
        -- OnModelLoaded, so `akLoaded` stays false -- and because `akSpec` was
        -- already set, SetSpec early-returns on every subsequent frame and
        -- never retries. The racer is then a flat icon for the rest of the
        -- session with no path back, which is the "everyone lost their models
        -- again" report. Attract mode hides every model by design, so this is
        -- reachable on any menu-to-race transition.
        if modelReady then
          kart.modelStuck = 0
        else
          kart.modelStuck = (kart.modelStuck or 0) + (race.renderDelta or race.delta or 0)
          if kart.modelStuck > 1.5 then
            AK.Model:Invalidate(kart.model)
            kart.modelStuck = 0
          end
        end
      else
        kart.model:Hide()
      end
      -- Centre-anchored and generously sized: model frames clip to their bounds
      -- and render about the model's own origin, so a bottom-anchored frame
      -- chopped Baine off at the waist and sank him into the road.
      local modelSize = width * tuning.modelScale * 2.4
      kart.model:ClearAllPoints()
      kart.model:SetPoint("CENTER", kart, "BOTTOM", 0, width * tuning.modelLift)
      kart.model:SetSize(modelSize, modelSize)
      AK.Model:Reframe(kart.model)
      -- The driver spins with the kart.
      kart.model:SetFacing(math.pi + lean + spinTurns)
      if kart.model.SetDesaturation then kart.model:SetDesaturation(vehicle.stun > 0 and 1 or 0) end
      kart.icon:SetShown(not modelReady)
      kart.icon:SetSize(width * .6, width * .6)
      if kart.iconApplied ~= vehicle.kart.icon then
        kart.iconApplied = vehicle.kart.icon
        kart.icon:SetTexture(vehicle.kart.icon)
      end

      -- Deployed item, orbiting just behind the rear bumper.
      local held = vehicle.held and AK.Items[vehicle.held]
      kart.heldIcon:SetShown(held ~= nil)
      kart.heldGlow:SetShown(held ~= nil)
      if held then
        local size = width * 0.42
        local sway = math.sin(race.elapsed * 3.1 + index) * width * 0.06
        kart.heldIcon:ClearAllPoints()
        kart.heldIcon:SetPoint("CENTER", kart, "BOTTOM", sway, -width * 0.16)
        kart.heldIcon:SetSize(size, size)
        if kart.heldApplied ~= held.icon then
          kart.heldApplied = held.icon
          kart.heldIcon:SetTexture(held.icon)
        end
        kart.heldIcon:SetVertexColor(unpack(held.tint or { 1, 1, 1 }))
        kart.heldGlow:ClearAllPoints()
        kart.heldGlow:SetPoint("CENTER", kart.heldIcon, "CENTER")
        kart.heldGlow:SetSize(size * 2.0, size * 2.0)
        kart.heldGlow:SetVertexColor(held.color[1], held.color[2], held.color[3], 1)
        kart.heldGlow:SetAlpha(0.25 + 0.15 * math.sin(race.elapsed * 7))
      end

      -- Name tags float above the model, in their own always-on-top layer.
      local tagVisible = width > 34
      kart.tag:SetShown(tagVisible)
      kart.tagPlate:SetShown(tagVisible)
      if tagVisible then
        kart.tag:SetText(vehicle == player and "YOU" or (vehicle.racer.tag or "CPU"))
        kart.tag:SetTextColor(unpack(vehicle == player and AK.COLORS.gold or { 1, 1, 1 }))
        kart.tag:ClearAllPoints()
        -- Above the racer's HEAD, not above the frame. The kart frame is a
        -- square as tall as it is wide, while the kart and rider only fill
        -- roughly its lower two thirds -- so 1.10 of the frame height threw the
        -- tag far above the art. That was invisible while karts were small and
        -- became "YOU floating on the horizon" as soon as they were not.
        -- `bounce` carries every vertical offset the kart has -- road bump, the
        -- drift hop, and the long ramp arc. The kart frame is placed at
        -- `y + bounce` but the tag was placed at plain `y`, so launching off a
        -- ramp left "YOU" sitting on the tarmac while the kart flew up the
        -- screen without it.
        kart.tag:SetPoint("CENTER", self.frame, "CENTER", drawX, y + bounce + height * 0.70)
        kart.tagPlate:SetSize(kart.tag:GetStringWidth() + 10, kart.tag:GetStringHeight() + 5)
        -- Tags live on `tagLayer` so they always draw over the field, which
        -- also means they do NOT inherit the kart's alpha. Faded by hand, or a
        -- rival fading out at the screen edge leaves a name floating there on
        -- its own -- which is the sliding artefact with a label on it.
        local tagFade = vehicle == player and 1 or self:EdgeFade(drawX, dz)
        kart.tag:SetAlpha(tagFade)
        kart.tagPlate:SetAlpha(0.55 * tagFade)
      end

      -- Battle marker. A rival counts as fighting you once they have been
      -- within a few metres for more than a moment -- the dwell is what stops
      -- it strobing every time someone flicks past on a straight.
      if vehicle ~= player and not vehicle.finished and player and not player.finished then
        local gap = math.abs(vehicle.distance - player.distance)
        if gap < 6 and math.abs((vehicle.lateral or 0) - (player.lateral or 0)) < 0.9 then
          vehicle.battleTime = (vehicle.battleTime or 0) + (race.renderDelta or race.delta or 0)
        else
          vehicle.battleTime = 0
        end

        -- NEAR MISS. Passing close at speed is most of what makes a crowded
        -- pack exciting, and nothing acknowledged it at all. Fires once per
        -- rival per pass: `nearMissed` latches while you are alongside and only
        -- clears once you are properly apart, so a kart you sit beside down a
        -- straight cannot machine-gun the cue.
        local alongside = gap < 2.2
          and math.abs((vehicle.lateral or 0) - (player.lateral or 0)) < 0.85
        if alongside and not vehicle.nearMissed then
          vehicle.nearMissed = true
          if (player.speed or 0) > (player.maxSpeed or 1) * 0.70 then
            self:Feel("kickX", ((vehicle.lateral or 0) < (player.lateral or 0) and 1 or -1) * 7)
            self:Shake(4)
            if AK.PlaySfx then AK:PlaySfx("nearMiss") end
          end
        elseif not alongside and gap > 5 then
          vehicle.nearMissed = false
        end
      else
        vehicle.battleTime = 0
        vehicle.nearMissed = false
      end
      local battling = (vehicle.battleTime or 0) > 1.5 and tagVisible
      kart.warn:ClearAllPoints()
      kart.warn:SetPoint("CENTER", self.frame, "CENTER", drawX, y + height * 0.95)
      kart.warn:SetText(battling and "!" or "")
      kart.warn:SetAlpha(battling and (0.55 + 0.45 * math.sin(race.elapsed * 9)) or 0)

      -- A rival thrown off-axis by a corner fades like everything else standing
      -- in the world. Your OWN kart never does: it sits at camBack metres, well
      -- inside EdgeFade's near exemption, but it is the one thing on screen that
      -- must never dim under any circumstances, so it is excluded outright
      -- rather than left to depend on a tuning value staying where it is.
      kart:SetAlpha(vehicle == player and 1 or self:EdgeFade(drawX, dz))
      kart:Show()
      if vehicle == player then
        self.playerX, self.playerY, self.playerWidth = drawX, y, width
      end

      self:VehicleEffects(vehicle, index, x, y, width, vehicle == player)
    else
      kart:Hide()
      kart.tag:Hide()
      kart.tagPlate:Hide()
      self.previous[index] = nil
    end
  end
end

function RaceUI:Render(race)
  if not self.frame or not self.frame:IsShown() then return end
  local player = race.player
  if not player then return end
  local tuning = AK.db.tuning
  self.T = tuning
  self.halfWidth = self.frame:GetWidth() * .5
  self.halfHeight = self.frame:GetHeight() * .5
  -- Visual easing uses the real frame delta; the simulation uses fixed slices.
  local dt = race.renderDelta or race.delta
  if self.appliedHorizon ~= tuning.horizon then self:LayoutHorizon(tuning.horizon) end
  -- Same deal for the HUD dial: nudging it in the tuning panel during a race
  -- should move the HUD while you watch, not on the next reload.
  if self.appliedHudScale ~= tuning.hudScale then
    self.appliedHudScale = tuning.hudScale
    self:LayoutHud()
  end

  local speedRatio = AK.Math.Clamp(player.speed / player.maxSpeed, 0, 1.3)
  -- Lens widens with speed and boost. Cheap, and it is most of what makes going
  -- fast actually feel fast.
  local boostFov = tuning.boostFov
  local targetDepth = tuning.camDepth - boostFov * AK.Math.Clamp(speedRatio - .45, 0, 1) / .55
  if player.boostTime > 0 then targetDepth = tuning.camDepth - boostFov end
  if AK.db.settings.reducedEffects then targetDepth = tuning.camDepth end
  -- Asymmetric: the lens snaps open when the boost lands and relaxes slowly
  -- afterwards. Equal rates make a boost feel like a setting changing rather
  -- than something hitting you.
  local widening = targetDepth < (self.camDepth or tuning.camDepth)
  local lensRate = widening and 12 or 4.5    -- ~0.15s in, ~0.4s out
  self.camDepth = AK.Math.Lerp(self.camDepth or tuning.camDepth, targetDepth,
    math.min(1, dt * lensRate))

  -- Feel channels: triggers, then decay. Read every frame from the player's own
  -- state, so nothing has to remember to call in from the simulation.
  self.feel = self.feel or {}
  local feel = self.feel
  local was = self.previous

  -- Boost begins: shove the camera back. Ending it needs no impulse -- the
  -- channel is already easing home on its own.
  local boosting = (player.boostTime or 0) > 0
  if boosting and not was.boosting then self:Feel("push", 2.6) end
  was.boosting = boosting

  -- Landing: the airtime that just ended is the weight of the dip.
  local air = (player.air or 0)
  if (was.air or 0) > 0 and air <= 0 then self:FeelLanding(was.airMax or was.air) end
  was.air, was.airMax = air, air > 0 and math.max(was.airMax or 0, player.airMax or air) or 0

  -- Drift lean, PROPORTIONAL TO CHARGE rather than a flat tilt the moment a
  -- drift starts. The lean growing as the mini-turbo builds is the readable
  -- part -- it tells you how close the boost is without looking at the meter.
  local charge = vehicleIsDrifting(player) and (player.driftCharge or 0) or 0
  local leanTarget = (player.driftDirection or 0) * AK.Math.Clamp(charge / 1.8, 0, 1)
  if AK.db.settings.reducedEffects then leanTarget = 0 end
  feel.lean = AK.Math.Lerp(feel.lean or 0, leanTarget, math.min(1, dt * 6))
  if math.abs(feel.lean) < FEEL_EPSILON then feel.lean = 0 end

  -- Rates are "how fast this comes home", verified by verify-feel.js. `push`
  -- was 2.6, which took 4.25s to fully settle -- with boosts landing every few
  -- seconds the camera then sat pulled back permanently instead of punching and
  -- recovering, which is the opposite of the intended read.
  feel.push = decay(feel.push, 5.0, dt)     -- ~0.6s to imperceptible
  feel.dip = decay(feel.dip, 7.0, dt)       -- fast, it is a landing thump
  feel.kickX = decay(feel.kickX, 6.0, dt)

  -- Camera shake: decays fast, plus a constant rumble while off the tarmac.
  local rumble = player.offroad and 3.5 or 0
  self.shake = math.max((self.shake or 0) * math.max(0, 1 - dt * 7) - dt * 4, rumble)
  if AK.db.settings.reducedEffects then self.shake = 0 end
  local shake = self.shake * tuning.shakeScale
  self.shakeX = (math.random() - .5) * 2 * shake + (feel.kickX or 0)
  self.shakeY = (math.random() - .5) * 2 * shake

  -- Aim the camera down the road ahead, plus a kick from your own steering.
  -- The result is that the world swings through a corner instead of sliding.
  -- No heading term any more: the forward-accumulated bend already swings the
  -- road through the corner, and yawing on top of it would cancel exactly the
  -- curvature we just went to the trouble of showing. What is left is the part
  -- yaw was always actually good for -- a kick from your own input.
  local steer = (AK.Race.controls.right and 1 or 0) - (AK.Race.controls.left and 1 or 0)
  if not player.isPlayer then steer = 0 end
  local targetYaw = steer * tuning.camYaw * 0.16 * speedRatio
  -- Lean into the slide, scaled by how much mini-turbo is banked. `feel.lean`
  -- is already eased and already zeroed when the drift ends.
  targetYaw = targetYaw + (feel.lean or 0) * tuning.camYaw * 0.20
  self.camYawValue = AK.Math.Lerp(self.camYawValue or targetYaw, targetYaw, math.min(1, dt * 4.5))
  self.yawShift = -self.camYawValue * (self.camDepth or tuning.camDepth) * self.halfWidth

  local camX, camZ = self:RenderRoad(race, player)
  self:RenderFork(race, player, camX, camZ)
  -- Props are child frames, so they draw above the rock rather than behind it.
  -- Underground there is no roadside to decorate anyway.
  if (self.tunnelDepth or 0) < 0.85 then self:RenderProps(race, camX, camZ) end
  self:RenderSky(race, camX)
  self:RenderPosts(race, camX, camZ)
  self:RenderArches(race, camX, camZ)
  self:RenderFinish(race, camX, camZ)
  self:RenderSpectators(race, camX, camZ)
  self:RenderObjects(race, player, camX, camZ)
  self:RenderHazards(race, camX, camZ)
  self:RenderGhost(race, camX, camZ)
  self:RenderProjectiles(race, camX, camZ)
  self:RenderKarts(race, player, camX, camZ)
  self:UpdateParticles(dt)
  self:UpdateEffects(dt)
  self:RenderWeather(race, dt)

  self:UpdatePresentation(race, dt)

  local lineAlpha = AK.db.settings.reducedEffects and 0 or AK.Math.Clamp((speedRatio - .55) * 1.8, 0, .5)
  if player.boostTime > 0 then lineAlpha = math.max(lineAlpha, .5) end
  -- The last lap is louder: streaks bite lower down the speed range and run
  -- harder, so the final lap reads as urgent even at the same pace.
  if self.finalLapUrgency then
    lineAlpha = math.max(lineAlpha, AK.Math.Clamp((speedRatio - .30) * 1.6, 0, .62))
  end
  lineAlpha = lineAlpha * tuning.speedLines
  for index, line in ipairs(self.speedLines) do
    -- Streaks radiate from the vanishing point, and only in the periphery --
    -- scattered through the middle they read as scratches on the screen.
    local angle = index * 2.399
    local travel = ((race.elapsed * (.9 + speedRatio * 1.7) + index * .137) % 1)
    local reach = travel * travel
    local x = math.cos(angle) * reach * self.halfWidth * 1.9
    local y = tuning.horizon + math.sin(angle) * reach * self.halfHeight * 1.9
    local peripheral = math.abs(x) / self.halfWidth
    line:ClearAllPoints()
    line:SetPoint("CENTER", self.frame, "CENTER", x, y)
    -- Length scales with actual pace, not just opacity. Streaks that only fade
    -- in read as a filter switching on; streaks that STRETCH read as speed.
    -- Screen-relative, so they are the same streak at any resolution.
    local stretch = 0.55 + speedRatio * 0.85 + (boosting and 0.5 or 0)
    line:SetSize(math.max(1, self.halfWidth * 0.0012 * (1 + reach * 3)),
      self.halfHeight * (0.017 + reach * 0.092) * stretch)
    line:SetAlpha(lineAlpha * math.min(1, travel * 2.5) * AK.Math.Clamp((peripheral - .32) * 2.2, 0, 1))
  end

  -- Edge warp, boost only. A dark vignette that tightens as the boost runs,
  -- which pinches the frame inward without touching the middle of the screen
  -- where the player is actually looking.
  if self.vignette then
    local boostLeft = AK.db.settings.reducedEffects and 0
      or AK.Math.Clamp((player.boostTime or 0) / 0.8, 0, 1)
    self.boostWarp = AK.Math.Lerp(self.boostWarp or 0, boostLeft, math.min(1, dt * 9))
    if self.boostWarp < 0.001 then self.boostWarp = 0 end
    -- 0.22 is the resting vignette this texture was built for; the boost only
    -- ever adds on top, so turning effects off leaves exactly the old look.
    self.vignette:SetAlpha(0.22 + self.boostWarp * 0.30)
  end
  self.boostTint:SetAlpha(player.boostTime > 0 and (AK.db.settings.reducedEffects and 0 or .08) or 0)

  local position = race.positions[player] or 1
  -- Pulse the ordinal whenever it changes, so a gained place registers even if
  -- you were watching the road instead of the HUD.
  if self.shownPosition and position ~= self.shownPosition then
    self.positionPulse = 1
  end
  self.shownPosition = position
  self.positionPulse = math.max(0, (self.positionPulse or 0) - dt * 2.6)
  self.position:SetText(ORDINALS[position] or (position .. "TH"))
  local pulseTint = self.positionPulse
  local base = position == 1 and AK.COLORS.gold or (position <= 3 and AK.COLORS.lime or { .9, .94, 1 })
  self.position:SetTextColor(
    base[1] + (1 - base[1]) * pulseTint,
    base[2] + (1 - base[2]) * pulseTint,
    base[3] + (1 - base[3]) * pulseTint)
  self.positionOf:SetText("/ " .. #race.vehicles)
  self.lap:SetText(math.min(player.lap, race.laps) .. " / " .. race.laps)
  for i, pip in ipairs(self.lapPips) do
    pip:SetShown(i <= race.laps)
    pip:SetVertexColor(unpack(i < player.lap and AK.COLORS.gold or { .25, .32, .42, 1 }))
  end
  self.timer:SetText(self:FormatTime(race.elapsed))
  self.speed:SetShown(AK.db.settings.showSpeed)
  self.speed:SetText(math.floor(player.speed * 2.2) .. " km/h")
  self.speed:SetTextColor(unpack(player.boostTime > 0 and AK.COLORS.gold or AK.COLORS.lime))
  local slowed = (player.slow or 0) > 0
  self.status:SetText(slowed and "SLOWED" or (player.offroad and "OFF ROAD" or (player.boostTime > 0 and "TURBO!" or "")))
  self.status:SetTextColor(unpack(slowed and AK.COLORS.danger or (player.offroad and AK.COLORS.gold or AK.COLORS.lime)))

  -- The keyboard legend and the shortcut blurb are onboarding, not HUD. They
  -- are exactly what you want while the lights are counting down, and pure
  -- clutter across the bottom of the screen for the other ninety seconds. So
  -- they fade out once you are actually driving, and come back whenever the
  -- race is not running -- the countdown, a pause, the moment after the flag.
  local settled = race.state == AK.RACE_STATES.RACING and race.elapsed > 6
  local onboarding = settled and AK.Math.Clamp(1 - (race.elapsed - 6) / 1.5, 0, 1) or 1
  self.controlHint:SetAlpha(onboarding)
  self.shortcut:SetAlpha(onboarding)

  -- Item roulette: picking up a box spins the slot before locking in, which is
  -- half the fun of getting one.
  if player.item and not self.lastItem then
    self.roulette = race.elapsed + 0.95
    self:BoxShatter()
    if AK.PlaySfx then AK:PlaySfx("item") end
  elseif not player.item then
    self.roulette = nil
  end
  self.lastItem = player.item
  local spinning = self.roulette and race.elapsed < self.roulette
  if spinning then
    -- Slow the cycle as it settles, so it lands rather than cuts.
    local remaining = self.roulette - race.elapsed
    local rate = 26 - 20 * (1 - remaining / 0.95)
    local pool = AK.ItemOrder
    local shown = pool[(math.floor(race.elapsed * rate) % #pool) + 1]
    self.itemIcon:SetTexture(AK.Items[shown].icon)
    self.itemIcon:SetDesaturated(false)
    self.itemLabel:SetText("???")
    self.itemGlow:SetAlpha(0.30)
    local pop = ITEM_ICON + 9 * math.sin(race.elapsed * 24)
    self.itemIcon:SetSize(pop, pop)
  else
    if self.roulette then
      self.roulette = nil
      self:Flash(AK.COLORS.gold, .08)
    end
    self.itemIcon:SetSize(ITEM_ICON, ITEM_ICON)
    -- The slot shows what is banked; a deployed item shows as "READY - FIRE".
    local slot = player.item and AK.Items[player.item]
    local held = player.held and AK.Items[player.held]
    local shown = slot or held
    self.itemIcon:SetTexture(shown and shown.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.itemIcon:SetDesaturated(not shown)
    if held and not slot then
      self.itemLabel:SetText("FIRE!")
      self.itemLabel:SetTextColor(unpack(AK.COLORS.lime))
    elseif shown then
      -- Multi-activation items show how many are left, not three icons.
      -- Through the helper rather than reimplementing it here: AK:ItemCount was
      -- the documented way to ask, and this was the only place that asked.
      local count = slot and AK:ItemCount(player) or 1
      -- The icon already says WHAT it is. The label carries the only thing an
      -- icon cannot: how many are left.
      self.itemLabel:SetText(count > 1 and ("x" .. count) or "")
      self.itemLabel:SetTextColor(unpack(AK.COLORS.gold))
    else
      -- An empty box is an empty box. It used to print "NO ITEM" in it, which
      -- is a form field telling you what you can already see.
      self.itemLabel:SetText("")
    end
    self.itemGlow:SetAlpha(shown and (0.14 + 0.12 * math.sin(race.elapsed * (held and 11 or 6))) or 0)
  end

  -- Current lap split, with the best lap so far alongside it.
  -- Corner callout. Only fires on a change, and fades rather than sitting on
  -- screen, so it reads as a signpost going past instead of as a HUD element.
  if self.sectionLabel then
    local section = AK.TrackBuilder:SectionAt(player.route or race.track, player.distance)
    local name = section and section.name
    if name ~= self.sectionShown then
      self.sectionShown = name
      self.sectionUntil = race.elapsed + 2.4
      self.sectionLabel:SetText(name and name:upper() or "")
    end
    local left = (self.sectionUntil or 0) - race.elapsed
    self.sectionLabel:SetAlpha(AK.Math.Clamp(left / 0.9, 0, 1) * 0.92)
  end

  local lapElapsed = race.elapsed - (player.lapStart or 0)
  if race.state == AK.RACE_STATES.RACING or race.state == AK.RACE_STATES.PAUSED then
    self.lapTime:SetText(("LAP %s   BEST %s"):format(
      self:FormatTime(math.max(0, lapElapsed)),
      player.bestLap and self:FormatTime(player.bestLap) or "--:--.--"))
  else
    self.lapTime:SetText("")
  end

  local charge = AK.Math.Clamp(player.driftCharge / DRIFT_MAX, 0, 1)
  local chargeColor = driftColor(player.driftCharge)
  self.driftFill:SetWidth(math.max(0.01, DRIFT_TRACK * charge))
  self.driftFill:SetVertexColor(chargeColor[1], chargeColor[2], chargeColor[3], 1)
  self.driftGlow:SetWidth(math.max(0.01, DRIFT_TRACK * charge))
  self.driftGlow:SetVertexColor(chargeColor[1], chargeColor[2], chargeColor[3], 1)
  self.driftGlow:SetAlpha(charge > 0 and (0.18 + 0.22 * math.sin(race.elapsed * 9)) * charge or 0)
  -- The tier you have BANKED, in the tier's own colour -- not an instruction.
  -- "DRIFT BOOST" and "RELEASE FOR BOOST" were a tutorial pinned to the screen
  -- for the whole race; what you actually cannot see is which rung you are on.
  local tier = driftTier(player.driftCharge)
  self.driftLabel:SetText(DRIFT_TIER_NAMES[tier] or "")
  self.driftLabel:SetTextColor(chargeColor[1], chargeColor[2], chargeColor[3])
  self.driftPanel:SetAlpha(player.drifting and 1 or (charge > 0 and 1 or 0.45))
  -- Each tick lights when the charge passes the threshold it actually marks.
  for i, tick in ipairs(self.driftTicks) do
    local lit = charge >= DRIFT_TICKS[i] - 0.001
    tick:SetVertexColor(unpack(lit and AK.COLORS.gold or { .08, .13, .20, 1 }))
  end

  self.minimap:SetShown(AK.db.settings.showMinimap)
  if AK.db.settings.showMinimap then
    for index, vehicle in ipairs(race.vehicles) do
      local mapX, mapY = self:MapPosition(race.track, vehicle.progress or vehicle.distance)
      local dot = self.mapDots[index]
      dot:ClearAllPoints()
      dot:SetPoint("CENTER", self.minimap, "CENTER", mapX, mapY)
      dot:SetVertexColor(unpack(vehicle == player and AK.COLORS.gold or vehicle.kart.color))
      dot:SetSize(vehicle == player and 9 or 6, vehicle == player and 9 or 6)
      dot:Show()
    end
  end

  self.pause:SetShown(race.state == AK.RACE_STATES.PAUSED)
  if race.state == AK.RACE_STATES.COUNTDOWN then
    local counting = race.countdown > 0.15
    self.countdown:SetText(counting and tostring(math.ceil(race.countdown)) or "GO!")
    local phase = counting and (math.ceil(race.countdown) - race.countdown) or 0
    if self.countdown.SetScale then self.countdown:SetScale(1.35 - AK.Math.Clamp(phase, 0, .35)) end
    self.countdown:SetTextColor(unpack(counting and AK.COLORS.gold or AK.COLORS.lime))
    -- Lights arm from left to right as the count runs down, then all go green.
    self.lightRig:Show()
    for i, light in ipairs(self.lights) do
      local armed = race.countdown <= (3 - i + 1)
      if not counting then
        light.lamp:SetVertexColor(.25, 1, .35, 1)
        light.halo:SetVertexColor(.3, 1, .4, 1)
        light.halo:SetAlpha(.75)
      elseif armed then
        light.lamp:SetVertexColor(1, .18, .12, 1)
        light.halo:SetVertexColor(1, .2, .15, 1)
        light.halo:SetAlpha(.6)
      else
        light.lamp:SetVertexColor(.16, .05, .05, 1)
        light.halo:SetAlpha(0)
      end
    end
  else
    self.countdown:SetText("")
    self.lightRig:Hide()
  end

  if self.noticeUntil then
    local remaining = self.noticeUntil - race.elapsed
    if remaining <= 0 then
      self.notice:SetText("")
      self.noticePlate:Hide(); self.noticeEdge:Hide(); self.noticeIcon:Hide()
    else
      local fade = AK.Math.Clamp(remaining / .35, 0, 1)
      -- Punch in over the first 120ms so it reads as an event, not a caption.
      -- The pop drives the plate rather than the text: SetScale on a region
      -- scales its anchor offset too, which would fling a banner anchored at
      -- +258 up the screen as it grew.
      local age = race.elapsed - (self.noticeStart or 0)
      local pop = 1 + 0.30 * math.max(0, 1 - age / 0.12)
      self.notice:SetAlpha(fade)
      local textWidth = self.notice:GetStringWidth()
      local iconSize = self.noticeIcon:IsShown() and 42 or 0
      self.noticePlate:SetSize((textWidth + 56 + iconSize) * pop, 52 * pop)
      self.noticePlate:SetAlpha(fade * .62)
      self.noticePlate:Show()
      self.noticeEdge:SetSize((textWidth + 56 + iconSize) * pop, 2)
      self.noticeEdge:SetVertexColor(unpack(self.noticeColor or AK.COLORS.gold))
      self.noticeEdge:SetAlpha(fade)
      self.noticeEdge:Show()
      if iconSize > 0 then
        self.noticeIcon:SetSize(iconSize, iconSize)
        self.noticeIcon:SetAlpha(fade)
      end
    end
  end
  self.flashAlpha = math.max(0, (self.flashAlpha or 0) - dt * 1.9)
  self.flash:SetAlpha(self.flashAlpha)
  if AK.Debug then AK.Debug:Update(race) end
end
