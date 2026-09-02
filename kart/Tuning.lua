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
  { key = "shakeScale", label = "Camera shake", default = 1.0, step = 0.1, min = 0, max = 3.0 },
  { key = "boostFov", label = "Speed lens kick", default = 0.075, step = 0.01, min = 0, max = 0.3 },
  { key = "camYaw", label = "Turn into corners", default = 1.0, step = 0.1, min = 0, max = 3.0,
    hint = "How far the camera swings through a bend. 0 is the old flat slide." },

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

  { key = "drawDistance", label = "See ahead (m)", default = 330, rev = 6, step = 20, min = 120, max = 620,
    hint = "How far down the road is drawn. Higher gives more warning before a corner arrives, which is most of what makes a circuit readable." },

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
local TUNING_REVISION = 15

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

function Tuning:Build()
  if self.frame then return end
  local UI = AK.UI

  -- Lay out by SECTION, never by raw row index.
  --
  -- Splitting on a row count stranded the CORNERS header at the foot of the
  -- first column while its rows appeared at the top of the second under no
  -- heading at all -- "Brake strength" floated above the TRACK header looking
  -- like it belonged to it.
  local sections, current = {}, nil
  for _, def in ipairs(self.defs) do
    if def.section then
      current = { header = def, rows = {} }
      sections[#sections + 1] = current
    elseif current then
      current.rows[#current.rows + 1] = def
    end
  end
  local total = 0
  for _, section in ipairs(sections) do total = total + 1 + #section.rows end

  -- Fill the first column to roughly half the total, but only ever break
  -- BETWEEN sections, so a heading always travels with its rows.
  local entries, column, slot, used, tallest = {}, 0, 0, 0, 0
  for _, section in ipairs(sections) do
    local cost = 1 + #section.rows
    if column == 0 and used > 0 and used + cost > math.ceil(total / 2) then
      column, slot = 1, 0
    end
    for position, def in ipairs({ section.header, unpack(section.rows) }) do
      slot = slot + (position == 1 and 1 or 1)
      entries[#entries + 1] = { def = def, column = column, slot = slot }
      if slot > tallest then tallest = slot end
    end
    if column == 0 then used = used + cost end
  end

  local rowHeight, columnWidth = 26, 320
  local height = 132 + tallest * rowHeight

  local frame = CreateFrame("Frame", "AzerothKartTuning", UIParent, "BackdropTemplate")
  frame:SetSize(columnWidth * 2 + 24, height)
  frame:SetPoint("CENTER", 0, -60)
  -- FULLSCREEN_DIALOG, not TOOLTIP: GameTooltip itself lives at TOOLTIP strata,
  -- so a panel parked there drew OVER its own tooltips and every hint in this
  -- window was unreadable. Level 900 clears the race (max 500) and the main
  -- menu (700) while leaving the tooltip strata to tooltips.
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(900)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(0.03, 0.05, 0.09, 0.96)
  frame:SetBackdropBorderColor(unpack(AK.COLORS.gold))
  frame:Hide()
  self.frame = frame
  self.rows = {}

  local title = UI:NewText(frame, "RENDER TUNING", 14, AK.COLORS.gold, "CENTER")
  title:SetPoint("TOP", 0, -9)
  local hint = UI:NewText(frame, "drag to move  /  changes apply live  /  gold = changed", 10, AK.COLORS.muted, "CENTER")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -2)

  for _, entry in ipairs(entries) do
    local def, column, slot = entry.def, entry.column, entry.slot
    local x = 12 + column * columnWidth
    local y = -40 - (slot - 1) * rowHeight

    if def.section then
      local header = UI:NewText(frame, def.section, 11, AK.COLORS.blue, "LEFT")
      header:SetPoint("TOPLEFT", x, y - 4)
      local rule = frame:CreateTexture(nil, "ARTWORK")
      rule:SetTexture("Interface\\Buttons\\WHITE8x8")
      rule:SetVertexColor(0.13, 0.56, 0.93, 0.45)
      rule:SetHeight(1)
      rule:SetPoint("TOPLEFT", x + 68, y - 10)
      rule:SetPoint("TOPRIGHT", frame, "TOPLEFT", x + columnWidth - 16, y - 10)
    else
      local label = UI:NewText(frame, def.label, 11, { .84, .90, 1 }, "LEFT")
      label:SetPoint("TOPLEFT", x + 6, y)
      if def.hint then
        -- Covers the label and the value, and STOPS before the steppers.
        -- Stretching it the full column width put an invisible frame on top of
        -- the - and + buttons, so half the panel stopped responding to clicks.
        local zone = CreateFrame("Frame", nil, frame)
        zone:SetPoint("TOPLEFT", x, y)
        zone:SetSize(250, rowHeight)
        zone:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
          GameTooltip:SetText(def.hint, 1, 1, 1, 1, true)
          GameTooltip:Show()
        end)
        zone:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end

      -- A thin bar showing where the value sits inside its range.
      local track = frame:CreateTexture(nil, "ARTWORK")
      track:SetTexture("Interface\\Buttons\\WHITE8x8")
      track:SetVertexColor(0.14, 0.19, 0.28, 1)
      track:SetSize(60, 3)
      track:SetPoint("TOPLEFT", x + 150, y - 7)
      local fill = frame:CreateTexture(nil, "OVERLAY")
      fill:SetTexture("Interface\\Buttons\\WHITE8x8")
      fill:SetVertexColor(unpack(AK.COLORS.lime))
      fill:SetSize(1, 3)
      fill:SetPoint("TOPLEFT", x + 150, y - 7)

      local value = UI:NewText(frame, "", 11, AK.COLORS.lime, "RIGHT")
      value:SetPoint("TOPRIGHT", frame, "TOPLEFT", x + 256, y)
      self.rows[def.key] = { value = value, fill = fill }

      local minus = UI:NewButton(frame, "-", 20, 17, function()
        self:Set(def, AK.db.tuning[def.key] - def.step)
      end)
      minus:SetPoint("TOPLEFT", x + 264, y + 3)
      minus.quiet = true
      local plus = UI:NewButton(frame, "+", 20, 17, function()
        self:Set(def, AK.db.tuning[def.key] + def.step)
      end)
      plus:SetPoint("TOPLEFT", x + 288, y + 3)
      plus.quiet = true
      -- Right-click either stepper to restore just this value.
      for _, button in ipairs({ minus, plus }) do
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:HookScript("OnClick", function(_, mouseButton)
          if mouseButton == "RightButton" then self:Set(def, def.default) end
        end)
        button.tooltip = (def.hint and def.hint .. "\n" or "") .. "Right-click to reset this value."
      end
    end
  end

  -- Seat row for whoever is selected, along the bottom of the panel.
  self.seatRows = {}
  self.seatTitle = UI:NewText(frame, "", 11, AK.COLORS.gold, "LEFT")
  self.seatTitle:SetPoint("BOTTOMLEFT", 14, 62)
  -- Right-aligned value with room before the steppers; the old spacing let a
  -- negative value such as "-0.15" run under the minus button.
  local seatX = 180
  for _, def in ipairs(self.seatDefs) do
    local label = UI:NewText(frame, def.label, 11, { .84, .90, 1 }, "LEFT")
    label:SetPoint("BOTTOMLEFT", seatX, 62)
    local value = UI:NewText(frame, "", 11, AK.COLORS.lime, "RIGHT")
    value:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", seatX + 148, 62)
    self.seatRows[def.key] = value
    local minus = UI:NewButton(frame, "-", 20, 17, function()
      local racer = self:SelectedRacer()
      self:SetSeat(def, (racer[def.key] or def.default) - def.step)
    end)
    minus:SetPoint("BOTTOMLEFT", seatX + 156, 60)
    minus.quiet = true
    local plus = UI:NewButton(frame, "+", 20, 17, function()
      local racer = self:SelectedRacer()
      self:SetSeat(def, (racer[def.key] or def.default) + def.step)
    end)
    plus:SetPoint("BOTTOMLEFT", seatX + 180, 60)
    plus.quiet = true
    seatX = seatX + 230
  end
  frame:HookScript("OnShow", function() self:RefreshSeat() end)

  -- Four footer buttons, spaced from the panel's real width. Hard-coded points
  -- had them totalling 640px inside a 624px panel, so RESET overlapped SOUND
  -- EDITOR and PRINT CHANGES overlapped CLOSE -- they could not have fitted at
  -- any position.
  local footer = {
    { "RESET ALL", function() self:Reset() end,
      "Put every value in this panel back to its shipped default." },
    { "SOUND EDITOR", function() AK.SoundEditor:Toggle() end,
      "Audition every cue, browse the game's audio library and bind your own sounds." },
    { "PRINT CHANGES", function() self:Report() end,
      "Prints every value you have changed, so it can be shared and baked in as a new default." },
    { "CLOSE", function() frame:Hide() end, nil },
  }
  local footerWidth = 142
  local footerGap = (frame:GetWidth() - #footer * footerWidth) / (#footer + 1)
  for index, spec in ipairs(footer) do
    local button = UI:NewButton(frame, spec[1], footerWidth, 22, spec[2])
    button.label:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    button:SetPoint("BOTTOMLEFT", footerGap * index + footerWidth * (index - 1), 8)
    button.tooltip = spec[3]
  end

  -- Paint initial values through Set so bars and colours match the saved state.
  for _, def in ipairs(self.defs) do
    if def.key then self:Set(def, AK.db.tuning[def.key]) end
  end
end

function Tuning:RefreshSeat()
  local racer = self:SelectedRacer()
  if not racer or not self.seatTitle then return end
  self.seatTitle:SetText("SEAT: " .. racer.name)
  for _, def in ipairs(self.seatDefs) do
    local row = self.seatRows[def.key]
    if row then row:SetText(string.format("%.2f", racer[def.key] or def.default)) end
  end
end

function Tuning:Toggle()
  self:Build()
  self:RefreshSeat()
  self.frame:SetShown(not self.frame:IsShown())
end
