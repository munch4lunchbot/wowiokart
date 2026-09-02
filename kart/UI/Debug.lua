local _, AK = ...

-- Developer readout.
--
-- Tuning a kart by feel alone is guesswork; you need to see what the simulation
-- actually thinks is happening. This shows the live state of every system that
-- has caused a bug so far -- terrain, drift charge, checkpoint order, the fixed
-- step, the RNG seed -- so a wrong number is visible instead of inferred.
AK.Debug = {}
local Debug = AK.Debug

local ROWS = {
  { "speed",     function(r, v) return ("%.1f / %.1f  (%d km/h)"):format(v.speed, v.maxSpeed, v.speed * 2.2) end },
  { "state",     function(r, v)
      if v.falling then return "|cffff5555FALLING|r" end
      if (v.recovering or 0) > 0 then return "recovering" end
      if (v.air or 0) > 0 then return "|cff6bf0ffAIRBORNE|r" end
      if v.drifting then return "|cffffc233DRIFT|r" end
      if (v.spin or 0) > 0 then return "|cffff5555SPIN|r" end
      if (v.stalled or 0) > 0 then return "|cffff5555STALLED|r" end
      return "normal"
    end },
  { "drift",     function(r, v) return ("dir %d  charge %.2f / 2.50"):format(v.driftDirection or 0, v.driftCharge or 0) end },
  { "lateral",   function(r, v) return ("%.3f  (edge %.2f)"):format(v.lateral, v.roadEdge or 1) end },
  -- The cornering readout. "The road steers itself" has been reported three
  -- times and argued against with arithmetic three times; this shows which of
  -- the two forces is actually winning, live, instead of either of us guessing.
  { "cornering", function(r, v)
      local route = v.route or r.track
      local curve = AK.Math.RoadCurve(route, v.distance)
      local ratio = v.speed / math.max(1, v.maxSpeed)
      local push = curve * 0.002 * v.speed * ratio * (AK.db.tuning.curvePush or 0)
        * (v.drifting and 1.35 or 1) * (0.75 + (v.weight or 5) * 0.05)
      local steer = (AK.Race.controls.left and -1 or 0) + (AK.Race.controls.right and 1 or 0)
      local authority = v.handling * (v.drifting and 1.30 or 1)
      return ("curve %+.2f   push %+.2f/s   steer %d (max %.2f/s)   %s"):format(
        curve, -push, steer, authority,
        math.abs(push) > authority and "|cffff5555CORNER WINS|r" or "wheel wins")
    end },
  { "verge",     function(r, v)
      local route = v.route or r.track
      local cover = AK.TrackBuilder:TunnelDepth(route, v.distance)
      local wall, why = AK.Physics:VergeHasWall(route, v.distance)
      local room = AK.db.tuning.offroadRoom or 1.35
      return ("%s   barrier %.2f   cover %.2f"):format(
        wall and ("|cff6bf06bwall (" .. why .. ") - you bounce|r")
          or "|cffff5555open - you fall|r",
        room * (1 - 0.30 * cover) * (v.roadEdge or 1), cover)
    end },
  { "terrain",   function(r, v)
      local m = v.material or AK.Terrain.TYPES.ROAD
      return ("%s  blend %.2f"):format(m.id, v.materialBlend or 0)
    end },
  { "boost",     function(r, v) return ("boost %.2f  star %.2f  slow %.2f"):format(v.boostTime or 0, v.star or 0, v.slow or 0) end },
  { "slipstream", function(r, v) return ("%.2f  (+%.1f%% top)"):format(v.slipstream or 0, (v.slipstream or 0) * 5.6) end },
  { "immunity",  function(r, v) return ("%.2f   brakeGuard %s"):format(v.immune or 0, tostring(v.brakeGuard)) end },
  { "checkpoint", function(r, v)
      return ("%d / %d   cleared %d   laps %d"):format(v.checkpoint or 0,
        r.track.checkpointCount or 0, v.cleared or 0, v.validLaps or 0)
    end },
  { "item",      function(r, v)
      return ("%s x%d   held %s"):format(tostring(v.item), v.itemCount or 0, tostring(v.held))
    end },
  { "class",     function(r, v) return ("%s   mass %.2f   recovery %.2f"):format(v.weightClass or "?", v.mass or 1, v.classRecovery or 1) end },
  { "sim",       function(r)
      local c = r.clock or {}
      return ("%d slices  %d dropped  seed %d"):format(c.slices or 0, c.dropped or 0, r.seed or 0)
    end },
  { "world",     function(r, v)
      return ("dist %.0f / %.0f   proj %d   hazards %d"):format(v.distance,
        r.track.length * r.laps, #r.projectiles, #(r.hazards or {}))
    end },
  { "route",     function(r, v)
      local route = v.route or r.track
      local name = (route == r.track) and "main line" or ("|cff66ff88" .. (route.name or route.id) .. "|r")
      local fork, gap = AK.TrackBuilder:ForkAt(r.track, v.distance, 200)
      local ahead = (route == r.track and fork and gap)
        and ("   fork in %.0fm (%s)"):format(gap, (fork.side or -1) < 0 and "left" or "right") or ""
      return ("%s   progress %.0f   odo %.0f%s"):format(name, v.progress or 0, v.odometer or 0, ahead)
    end },
}

function Debug:Build()
  if self.frame then return end
  local frame = CreateFrame("Frame", "AzerothKartDebug", UIParent, "BackdropTemplate")
  frame:SetSize(430, 40 + #ROWS * 16)
  frame:SetPoint("TOPLEFT", 200, -40)
  frame:SetFrameStrata("TOOLTIP")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(0.02, 0.03, 0.05, 0.92)
  frame:SetBackdropBorderColor(0.3, 0.9, 0.5, 0.9)
  frame:Hide()
  self.frame = frame

  local title = AK.UI:NewText(frame, "AZEROTH KART - DEBUG", 12, { .4, 1, .6 }, "LEFT")
  title:SetPoint("TOPLEFT", 10, -8)

  self.rows = {}
  for index, row in ipairs(ROWS) do
    local y = -26 - (index - 1) * 16
    local label = AK.UI:NewText(frame, row[1], 11, AK.COLORS.muted, "LEFT")
    label:SetPoint("TOPLEFT", 12, y)
    local value = AK.UI:NewText(frame, "", 11, { .88, .94, 1 }, "LEFT")
    value:SetPoint("TOPLEFT", 108, y)
    self.rows[index] = value
  end
end

function Debug:Update(race)
  if not self.frame or not self.frame:IsShown() then return end
  local vehicle = race and race.player
  if not vehicle then return end
  for index, row in ipairs(ROWS) do
    local ok, text = pcall(row[2], race, vehicle)
    self.rows[index]:SetText(ok and text or "|cffff5555err|r")
  end
end

function Debug:Toggle()
  self:Build()
  local show = not self.frame:IsShown()
  self.frame:SetShown(show)
  AK.db.settings.debug = show
  AK:Print("Debug readout " .. (show and "on" or "off") .. ".")
end
