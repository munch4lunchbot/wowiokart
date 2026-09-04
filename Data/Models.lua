local _, AK = ...

-- Baine sitting in Oribos is the mascot of this whole thing, so he stays the
-- default and the fallback -- but a racer can now be any creature, or your own
-- character. A model spec is one of:
--   { creature = <npcID> }   a creature display resolved by the client
--   { unit = "player" }      whoever is actually playing
AK.MODEL = {
  baineID = 36648, -- Baine Bloodhoof
  -- AnimationData ids. 96/97/98 are the sit-down, sit-loop and stand-up of the
  -- ground sit; 0 is the plain idle stand, and the 6x block is the emote set.
  -- A kart driver sits. A portrait on a character-select card STANDS -- a
  -- seated figure seen from the fixed portrait camera is a hunched shape you
  -- cannot identify, which is most of why the racer grid did not tell you who
  -- anybody was. And a crowd cheers.
  anim = {
    sitDown = 96, sit = 97, sitUp = 98,
    stand = 0, talk = 60, bow = 66, wave = 67, cheer = 68, dance = 69,
  },
}
AK.MODEL.default = { creature = AK.MODEL.baineID }

AK.Model = {}
local Model = AK.Model

-- Framing lives in the tuning table so it can be corrected live with
-- `/kart tune` rather than guessed at across reloads.
local function framing()
  local tuning = AK.db and AK.db.tuning
  return tuning and tuning.modelZoom or 2.0, tuning and tuning.modelZ or 0
end

local function applyPose(model)
  local zoom, z = framing()
  model:SetFacing(model.akFacing or 0)
  -- Position is (forward, right, up). A negative third component drops the
  -- model through the floor, which is exactly the "riders in the ground" bug.
  -- Per-racer seatZ rides on top of the global tuning value.
  model:SetPosition(0, 0, z + (model.akSeatZ or 0))
  if model.SetCamDistanceScale then
    -- Dividing by the racer's scale zooms IN for small models, so a gnome fills
    -- the same seat a tauren does.
    model:SetCamDistanceScale(zoom * (model.akZoom or 1) / (model.akSeatScale or 1))
  end
  -- Animation has to be re-applied whenever the model finishes streaming in,
  -- otherwise it snaps back to the default stand pose.
  model:SetAnimation(model.akAnim or AK.MODEL.anim.sit)
end

local function loadSpec(model, spec)
  spec = spec or AK.MODEL.default
  model.akSpec = spec
  model:ClearModel()
  model.akLoaded = false
  -- Drop the Reframe cache. Loading a model resets its internal camera, so if
  -- the cache still claims the framing is applied, Reframe skips the re-apply
  -- and the racer ends up wherever the client happened to leave them -- which
  -- is why the driver sat somewhere different every race.
  model.akAppliedZoom, model.akAppliedZ = nil, nil
  if spec.unit and UnitExists(spec.unit) then
    model:SetUnit(spec.unit)
  else
    model:SetCreature(spec.creature or AK.MODEL.baineID)
  end
end

--- Point a model frame at a racer's chosen appearance and pose it.
-- @param facing radians; 0 faces the camera, math.pi shows its back
-- @param zoom extra multiplier on top of the tuned camera distance
-- @param anim an AK.MODEL.anim value; defaults to the seated kart pose
function Model:Dress(model, facing, zoom, spec, anim)
  model.akFacing = facing or 0
  model.akZoom = zoom or 1
  -- Remembered as the frame's POSE, so SetSeat and every later reload keep it.
  if anim then model.akPose, model.akAnim = anim, anim end
  loadSpec(model, spec)
  applyPose(model)
  model:SetScript("OnModelLoaded", function(frame)
    frame.akLoaded = true
    -- Same reason: the load just reset the camera, so invalidate before posing.
    frame.akAppliedZoom, frame.akAppliedZ = nil, nil
    applyPose(frame)
  end)
end

--- Apply a racer's personal seat framing. Cheap, and only touches the model
--- when something actually changed.
function Model:SetSeat(model, racer)
  local seatZ = racer and racer.seatZ or 0
  local seatScale = racer and racer.seatScale or 1
  -- `akPose` is a pose the FRAME was built with -- a standing portrait, a
  -- cheering spectator -- and it outranks the seat. Without it this handed
  -- every model the sit loop the moment a racer was assigned to it, so a card
  -- that asked to stand sat back down as soon as it knew who it was showing.
  local anim = model.akPose or (racer and racer.anim) or AK.MODEL.anim.sit
  if model.akSeatZ == seatZ and model.akSeatScale == seatScale and model.akAnim == anim then return end
  model.akSeatZ, model.akSeatScale, model.akAnim = seatZ, seatScale, anim
  model.akAppliedZoom, model.akAppliedZ = nil, nil
  applyPose(model)
end

--- Swap an existing model to a different racer without rebuilding the frame.
--- No-ops when the spec has not actually changed, since reloading a model every
--- frame would stutter badly.
function Model:Invalidate(model)
  if not model then return end
  model.akSpec = nil
  model.akLoaded = nil
  model.akAppliedZoom = nil
  model.akAppliedSeat = nil
end

function Model:SetSpec(model, spec)
  spec = spec or AK.MODEL.default
  local current = model.akSpec
  if current and current.unit == spec.unit and current.creature == spec.creature then return end
  loadSpec(model, spec)
  applyPose(model)
end

--- A PORTRAIT'S ZOOM, independent of the kart's.
---
--- Every model in the addon was framed off `modelZoom`, which is tuned so a
--- rider and the kart around them both fit in the shot. A card that shows only
--- a person inherited that and drew them a fraction of the frame tall. This
--- converts the portrait dial into the multiplier `akZoom` expects, so both
--- stay live in the workshop and neither drags the other around.
function Model:PortraitZoom()
  local tuning = AK.db and AK.db.tuning
  local rider = (tuning and tuning.modelZoom) or 2.4
  local portrait = (tuning and tuning.portraitZoom) or 1.15
  return portrait / math.max(0.01, rider)
end

--- Create a posed racer inside `parent`. Seated unless `anim` says otherwise.
function Model:New(parent, width, height, facing, zoom, spec, anim)
  local model = CreateFrame("PlayerModel", nil, parent)
  model:SetSize(width, height)
  self:Dress(model, facing, zoom, spec, anim)
  return model
end

--- Re-apply framing when the tuning values change. Cheap enough to call every
--- frame, but it only touches the model when a value actually moved.
function Model:Reframe(model)
  local zoom, z = framing()
  local wanted = zoom * (model.akZoom or 1) / (model.akSeatScale or 1)
  if model.akAppliedZoom ~= wanted then
    model.akAppliedZoom = wanted
    if model.SetCamDistanceScale then model:SetCamDistanceScale(wanted) end
  end
  local wantedZ = z + (model.akSeatZ or 0)
  if model.akAppliedZ ~= wantedZ then
    model.akAppliedZ = wantedZ
    model:SetPosition(0, 0, wantedZ)
  end
end

--- Preview any creature id in a draggable window, standing, so new racers can be
--- scouted in-game and pasted into Data\Racers.lua without a reload cycle.
function AK:PreviewNPC(creatureID)
  local preview = self.npcPreview
  if not preview then
    preview = CreateFrame("Frame", "AzerothKartNPCPreview", UIParent)
    preview:SetSize(300, 340)
    preview:SetPoint("CENTER")
    preview:SetFrameStrata("DIALOG")
    preview:SetMovable(true)
    preview:EnableMouse(true)
    preview:RegisterForDrag("LeftButton")
    preview:SetScript("OnDragStart", preview.StartMoving)
    preview:SetScript("OnDragStop", preview.StopMovingOrSizing)
    self.UI:SkinWindow(preview, { 0.045, 0.075, 0.125, 0.96 })
    preview.model = Model:New(preview, 260, 260, -0.5, 1, nil, AK.MODEL.anim.stand)
    preview.model:SetPoint("TOP", 0, -34)
    preview.label = self.UI:NewText(preview, "", 13, self.COLORS.gold, "CENTER")
    preview.label:SetPoint("TOP", 0, -10)
    preview.status = self.UI:NewText(preview, "", 11, self.COLORS.muted, "CENTER")
    preview.status:SetPoint("BOTTOM", 0, 34)
    local close = self.UI:NewButton(preview, "CLOSE", 120, 24, function() preview:Hide() end)
    close:SetPoint("BOTTOM", 0, 8)
    self.npcPreview = preview
  end
  Model:SetSpec(preview.model, { creature = creatureID })
  Model:Reframe(preview.model)
  preview.label:SetText("creature = " .. creatureID)
  preview.status:SetText("Checking...")
  preview:Show()
  -- Models stream in asynchronously, so report success a beat later.
  C_Timer.After(1.2, function()
    if not preview:IsShown() then return end
    local ok = Model:IsReady(preview.model)
    preview.status:SetText(ok and "|cff6bf06bModel loaded|r" or "|cffff5555No model for that id|r")
  end)
end

--- True once the client actually streamed the model in. Callers fall back to a
--- flat icon when this stays false (bad creature id, low-detail settings).
function Model:IsReady(model)
  if not model then return false end
  if model.akLoaded then return true end
  if model.GetModelFileID then return model:GetModelFileID() ~= nil end
  return false
end
