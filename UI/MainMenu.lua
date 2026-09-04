local _, AK = ...

AK.UI = AK.UI or {}
local UI = AK.UI

-- BackdropTemplate is gone from this file. It was how both the panel and the
-- button got their look -- a filled quad with a one-pixel border -- and that
-- look is the reason the whole interface read as a configuration window rather
-- than as a game. Shape comes from art now; see Art/generate-art-ui.js.

local ART = AK.ART

-- THE PANEL PLATE, nine-sliced.
--
-- A panel is arbitrary in both directions, so the four corners keep their
-- pixels while the edges stretch along their own axis and the middle stretches
-- both ways. Nothing else gives a rounded corner that stays round.
local PANEL_TEX, PANEL_CORNER = 56, 18
local PC0 = PANEL_CORNER / PANEL_TEX
local PC1 = (PANEL_TEX - PANEL_CORNER) / PANEL_TEX
-- Column and row texcoord spans, in the order the nine pieces are built.
local PANEL_U = { { 0, PC0 }, { PC0, PC1 }, { PC1, 1 } }

--- Panels are OBJECTS now, not filled rectangles with a one-pixel square
--- border. That border is what BackdropTemplate gives you for free and it is
--- what every configuration window in World of Warcraft is made of; square
--- corners on a dark rectangle is the most recognisable "this is an addon" cue
--- there is. See Art/generate-art-ui.js.
--- The nine pieces, plus the two methods that place and colour them.
local function buildPanelPlate(frame)
  frame.pieces = frame.pieces or {}
  for row = 1, 3 do
    for col = 1, 3 do
      local piece = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
      piece:SetTexture(ART .. "panelplate.tga")
      piece:SetTexCoord(PANEL_U[col][1], PANEL_U[col][2], PANEL_U[row][1], PANEL_U[row][2])
      frame.pieces[#frame.pieces + 1] = piece
      piece.row, piece.col = row, col
    end
  end
  --- Corners keep the texture's pixels; edges stretch along one axis; the
  --- middle stretches both. Capped at half the panel so a small one does not
  --- have its corners overlap into a smear.
  function frame:LayoutPlate()
    local w, h = self:GetWidth(), self:GetHeight()
    if not w or w <= 0 or not h or h <= 0 then return end
    local cw = math.min(PANEL_CORNER, w * 0.5)
    local ch = math.min(PANEL_CORNER, h * 0.5)
    for _, piece in ipairs(self.pieces) do
      piece:ClearAllPoints()
      local left = piece.col == 1 and 0 or (piece.col == 2 and cw or w - cw)
      local top = piece.row == 1 and 0 or (piece.row == 2 and ch or h - ch)
      piece:SetPoint("TOPLEFT", left, -top)
      piece:SetSize(piece.col == 2 and math.max(1, w - cw * 2) or cw,
        piece.row == 2 and math.max(1, h - ch * 2) or ch)
    end
  end
  function frame:SetPlateColor(c)
    for _, piece in ipairs(self.pieces) do
      piece:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
  end
  frame:LayoutPlate()
  frame:HookScript("OnSizeChanged", function(self) self:LayoutPlate() end)
end

--- Give an EXISTING frame the panel plate. Windows that build their own frame
--- -- the workshop, the sound editor, the AI report -- were all still made of
--- BackdropTemplate and a one-pixel square border, so the parts of the product
--- a player reaches through a slash command looked like a different, older
--- program from the parts they reach through the menu.
function UI:SkinWindow(frame, color)
  frame.pieces = {}
  buildPanelPlate(frame)
  frame:SetPlateColor(color or AK.COLORS.panel)
  return frame
end

function UI:NewPanel(parent, width, height, color)
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetSize(width, height)
  local tint = color or AK.COLORS.panel
  panel.pieces = {}
  buildPanelPlate(panel)
  panel:SetPlateColor(tint)
  -- Warm light catching the top edge. It fades out before the corner curve
  -- starts, so it reads as an edge rather than as a line drawn across a box.
  local gleam = panel:CreateTexture(nil, "BORDER")
  gleam:SetTexture(ART .. "panelgleam.tga")
  gleam:SetPoint("TOPLEFT", 3, -1)
  gleam:SetPoint("TOPRIGHT", -3, -1)
  gleam:SetHeight(3)
  gleam:SetVertexColor(1, 0.86, 0.55, 0.40)
  panel.gleam = gleam
  return panel
end

--- What a button looks like at rest. Named because the selection grid has to
--- be able to put a card BACK to it when the player picks a different one.
UI.BUTTON_REST = { 0.18, 0.28, 0.42 }

function UI:NewText(parent, text, size, color, justify)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetFont(STANDARD_TEXT_FONT, size or 14, "OUTLINE")
  label:SetTextColor(unpack(color or { 1, 1, 1 }))
  label:SetJustifyH(justify or "LEFT")
  label:SetText(text or "")
  return label
end

-- THE BUTTON PLATE.
--
-- Authored 64x40 with 26px caps, so it is drawn as THREE pieces: the two caps
-- keep their pixels and the middle strip stretches. A single texture scaled to
-- fit turns the rounded corners into ovals, which is worse than having no
-- rounding at all -- see Art/generate-art-ui.js, and Art/preview-ui.js for
-- what it looks like.
local BTN = { texW = 64, texH = 40, cap = 26 }
BTN.u0 = BTN.cap / BTN.texW
BTN.u1 = (BTN.texW - BTN.cap) / BTN.texW

--- Three textures making one plate. `blend` for the body, "ADD" for the sheen.
---
--- Exposed on UI as well as used here: results rows, the finishing ladder and
--- anything else that wants to be an object rather than a filled rectangle
--- needs the same three-slice, and a second copy of it would drift.
local function newPlate(frame, layer, file, sublevel, mode)
  local pieces = {}
  for index = 1, 3 do
    local piece = frame:CreateTexture(nil, layer, nil, sublevel)
    piece:SetTexture(ART .. file)
    if mode then piece:SetBlendMode(mode) end
    pieces[index] = piece
  end
  pieces[1]:SetTexCoord(0, BTN.u0, 0, 1)
  pieces[2]:SetTexCoord(BTN.u0, BTN.u1, 0, 1)
  pieces[3]:SetTexCoord(BTN.u1, 1, 0, 1)
  return pieces
end

--- Lay a plate out across the frame. The caps keep the texture's aspect, so a
--- tall button gets proportionally rounder corners, which is what you want.
local function layoutPlate(pieces, width, height)
  -- A FIXED corner radius, whatever the button's size. Scaling the cap with
  -- height alone is right up to about the plate's authored height and absurd
  -- past it: a 150px-tall selection card would take a 97px cap and come out as
  -- a stadium, which is a different shape from every other control on screen.
  -- Real interfaces round every corner by the same amount.
  local cap = math.min(BTN.cap, height * BTN.cap / BTN.texH, width * 0.5)
  pieces[1]:ClearAllPoints()
  pieces[1]:SetPoint("TOPLEFT")
  pieces[1]:SetSize(cap, height)
  pieces[3]:ClearAllPoints()
  pieces[3]:SetPoint("TOPRIGHT")
  pieces[3]:SetSize(cap, height)
  pieces[2]:ClearAllPoints()
  pieces[2]:SetPoint("TOPLEFT", cap, 0)
  pieces[2]:SetPoint("BOTTOMRIGHT", -cap, 0)
end

local function tintPlate(pieces, color, alpha)
  for _, piece in ipairs(pieces) do
    piece:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
  end
end

--- A button that is an OBJECT, not a filled rectangle with a border.
---
--- What was here before was CreateFrame + BackdropTemplate + a one-pixel edge,
--- which is the default look of every configuration dialog in World of Warcraft
--- and reads as exactly that: an addon panel. A game's button has a shape, it
--- catches the light along its top edge and loses it along the bottom, it is
--- separated from whatever is behind it by its own dark rim, and it answers
--- when you touch it. All four of those are art and none of them are a border
--- colour.
function UI:NewButton(parent, text, width, height, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(width, height)
  button.restColor = { UI.BUTTON_REST[1], UI.BUTTON_REST[2], UI.BUTTON_REST[3] }
  button.restText = AK.COLORS.gold

  button.plate = newPlate(button, "BACKGROUND", "btn.tga", 0)
  -- The specular that arrives with the pointer. Additive, so it brightens the
  -- plate's own colour rather than washing it toward grey.
  button.sheen = newPlate(button, "ARTWORK", "btnsheen.tga", 0, "ADD")
  layoutPlate(button.plate, width, height)
  layoutPlate(button.sheen, width, height)
  tintPlate(button.plate, button.restColor)
  tintPlate(button.sheen, { 1, 1, 1 }, 0)

  button.label = self:NewText(button, text, 15, button.restText, "CENTER")
  button.label:SetAllPoints()

  --- Re-tint for a state. Kept as one entry point so hover, press and the
  --- disabled look cannot drift apart.
  function button:Paint(color, sheenAlpha, textColor)
    tintPlate(self.plate, color)
    tintPlate(self.sheen, { 0.92, 0.94, 1.0 }, sheenAlpha or 0)
    self.label:SetTextColor(unpack(textColor or self.restText))
  end

  --- Callers set a button's resting colour to say what it DOES -- danger red on
  --- a quit, green on the throttle. The second argument used to be a border
  --- colour; the plate has no border, so it is the label colour now, which is
  --- what a caller passing "danger" actually wanted to convey.
  function button:SetRestStyle(color, textColor)
    self.restColor = { color[1], color[2], color[3] }
    if textColor then self.restText = { textColor[1], textColor[2], textColor[3] } end
    self:Paint(self.restColor, 0)
  end

  --- Buttons get resized after construction (the settings screen sizes its
  --- pickers from the column width), and a plate laid out for the old size is
  --- a stretched cap.
  function button:Resize(w, h)
    self:SetSize(w, h)
    layoutPlate(self.plate, w, h)
    layoutPlate(self.sheen, w, h)
  end

  local function brighten(color, by)
    return { math.min(1, color[1] + by), math.min(1, color[2] + by), math.min(1, color[3] + by) }
  end
  local function darken(color, by)
    return { color[1] * by, color[2] * by, color[3] * by }
  end

  button:SetScript("OnEnter", function(frame)
    frame:Paint(brighten(frame.restColor, 0.10), 1)
    -- Every button in the addon routes through here. That is fine for a menu of
    -- ten, and awful in the tuning panel, where sixty steppers sit shoulder to
    -- shoulder and simply moving the mouse across the window machine-guns the
    -- same blip. Dense panels set `quiet` and stay silent.
    if AK.PlaySfx and not frame.quiet then AK:PlaySfx("uiHover") end
    if frame.tooltip then
      GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
      -- SetText is (text, r, g, b, alpha, wrap) -- passing wrap in the alpha slot errors.
      GameTooltip:SetText(frame.tooltip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function(frame)
    frame:Paint(frame.restColor, 0)
    GameTooltip:Hide()
  end)
  button:SetScript("OnClick", function(frame, ...)
    if AK.PlaySfx and not frame.quiet then AK:PlaySfx("uiClick") end
    if onClick then onClick(frame, ...) end
  end)
  -- Pressed: the plate darkens and the label sinks a pixel, so the press is
  -- felt rather than merely registered.
  button:SetScript("OnMouseDown", function(frame)
    frame:Paint(darken(frame.restColor, 0.62), 0)
    frame.label:ClearAllPoints()
    frame.label:SetPoint("CENTER", 1, -1)
  end)
  button:SetScript("OnMouseUp", function(frame)
    frame:Paint(frame:IsMouseOver() and brighten(frame.restColor, 0.10) or frame.restColor,
      frame:IsMouseOver() and 1 or 0)
    frame.label:ClearAllPoints()
    frame.label:SetAllPoints()
  end)
  return button
end

--- A SEGMENTED PICKER, the way a console settings screen does it.
---
--- Every option in this addon used to be a single button you clicked to cycle:
--- one label, no idea what the other choices were, and no way back except all
--- the way round. A segmented control shows the whole choice at once, says
--- which one you are on, and gets you to any of them in one click.
---
--- `options` is a list of { value, label }. `get` returns the live value and
--- `set` is handed the chosen one.
function UI:NewSegmented(parent, width, height, options, get, set)
  local group = CreateFrame("Frame", nil, parent)
  group:SetSize(width, height)
  local count = #options
  local gap = 4
  local cell = (width - gap * (count - 1)) / count
  group.cells = {}
  for index, option in ipairs(options) do
    local button = self:NewButton(group, option.label, cell, height, function()
      set(option.value)
      group:Refresh()
    end)
    button:SetPoint("LEFT", (index - 1) * (cell + gap), 0)
    button.quiet = true
    button.value = option.value
    button.tooltip = option.tooltip
    group.cells[index] = button
  end
  function group:Refresh()
    local current = get()
    -- A NUMERIC choice matches by NEAREST, not by equality. Camera distance is
    -- also a workshop dial, so a value nudged to 6.4 there would light none of
    -- CLOSE/STANDARD/FAR at all -- a row of dead buttons, which reads as
    -- broken rather than as "you are between presets".
    local best
    if type(current) == "number" then
      for _, button in ipairs(self.cells) do
        if type(button.value) == "number"
          and (not best or math.abs(button.value - current) < math.abs(best - current)) then
          best = button.value
        end
      end
    end
    for _, button in ipairs(self.cells) do
      local on = button.value == (best or current)
      button:SetRestStyle(on and { 0.55, 0.42, 0.10, 1 } or { 0.07, 0.11, 0.18, 0.95 },
        on and AK.COLORS.gold or { 0.22, 0.30, 0.40 })
      button.label:SetTextColor(unpack(on and { 1, 0.94, 0.72 } or { 0.52, 0.58, 0.68 }))
    end
  end
  group:Refresh()
  return group
end

--- A value with an arrow either side. For anything that is a number rather than
--- a short list -- you can go down as well as up, which a cycle button cannot.
function UI:NewStepper(parent, width, height, get, set, format)
  local group = CreateFrame("Frame", nil, parent)
  group:SetSize(width, height)
  local function nudge(direction)
    set(direction)
    group:Refresh()
  end
  --- An arrow, not the character ">". A chevron flipped through its texcoords
  --- gives both directions from one file and is the same mark the menu rows and
  --- the standings use, so every "this way" in the game is one shape.
  local function arrow(button, pointsRight)
    button.label:Hide()
    local mark = button:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(ART .. "chevron.tga")
    mark:SetSize(7, 10)
    mark:SetPoint("CENTER")
    mark:SetTexCoord(pointsRight and 0 or 1, pointsRight and 1 or 0, 0, 1)
    mark:SetVertexColor(unpack(AK.COLORS.gold))
    button.mark = mark
  end
  local down = self:NewButton(group, "", height, height, function() nudge(-1) end)
  down:SetPoint("LEFT", 0, 0)
  down.quiet = true
  arrow(down, false)
  local up = self:NewButton(group, "", height, height, function() nudge(1) end)
  up:SetPoint("RIGHT", 0, 0)
  up.quiet = true
  arrow(up, true)
  local plate = self:NewButton(group, "", width - height * 2 - 8, height, function() nudge(1) end)
  plate:SetPoint("CENTER", 0, 0)
  plate.quiet = true
  plate:SetRestStyle({ 0.07, 0.11, 0.18, 0.95 }, { 0.22, 0.30, 0.40 })
  function group:Refresh()
    plate.label:SetText(format(get()))
    plate.label:SetTextColor(1, 0.94, 0.72)
  end
  group:Refresh()
  return group
end

--- What you have done on a circuit, in one line. A track card with no record
--- on it is a track you have never raced, and saying so is more useful than
--- saying nothing.
local function trackRecord(trackId)
  local lap = AK.db.records and AK.db.records.bestLap and AK.db.records.bestLap[trackId]
  local race = AK.db.progress.bestTimes and AK.db.progress.bestTimes[trackId]
  if not lap and not race then return "NO TIME SET" end
  local parts = {}
  if lap then parts[#parts + 1] = "LAP " .. AK.RaceUI:FormatTime(lap) end
  if race then parts[#parts + 1] = "RACE " .. AK.RaceUI:FormatTime(race) end
  return table.concat(parts, "   ")
end

--- Attach a button plate to any frame. Returns a handle with Layout and Tint,
--- so a row in a table can wear the same shape as a button without being one.
function UI:NewPlate(frame, layer, sublevel, file)
  local pieces = newPlate(frame, layer or "BACKGROUND", file or "btn.tga", sublevel or 0)
  local handle = { pieces = pieces }
  function handle:Layout(width, height) layoutPlate(self.pieces, width, height) end
  function handle:Tint(color, alpha) tintPlate(self.pieces, color, alpha) end
  handle:Layout(frame:GetWidth(), frame:GetHeight())
  return handle
end

--- THE SHAPE OF A CIRCUIT, drawn small.
---
--- You choose a track by its shape. The selection grid showed a generic map
--- icon, a subtitle and a length in metres for all ten, so the one thing that
--- actually distinguishes Durotar's switchback climb from Thousand Needles'
--- mesa run -- the plan view, which the HUD has drawn for the whole race the
--- entire time -- was the one thing the screen you pick them on did not show.
function UI:NewTrackShape(parent, track, size)
  local shape = CreateFrame("Frame", nil, parent)
  shape:SetSize(size, size)
  -- Tracks are compiled lazily at race start, and this is a menu: without
  -- this, every card would draw the fallback ellipse.
  AK.TrackBuilder:Compile(track)
  local radius = size * 0.42
  local NODES = 56
  for index = 1, NODES do
    local node = shape:CreateTexture(nil, "ARTWORK")
    node:SetTexture("Interface\\Buttons\\WHITE8x8")
    local fraction = (index - 1) / NODES
    local x, y
    if track.mapPath then
      x, y = AK.TrackBuilder:MapPoint(track, fraction * track.length)
      x, y = x * radius * 2, y * radius * 2
    else
      local angle = fraction * math.pi * 2 - math.pi * 0.5
      x, y = math.cos(angle) * radius, math.sin(angle) * radius * 0.71
    end
    node:SetSize(3, 3)
    node:SetPoint("CENTER", shape, "CENTER", x, y)
    -- The start line is marked, so a shape is a circuit rather than a blob.
    if index == 1 then
      node:SetSize(5, 5)
      node:SetVertexColor(1, 0.82, 0.25, 1)
    else
      node:SetVertexColor(0.42, 0.56, 0.72, 0.95)
    end
  end
  return shape
end

--- A STAT BAR: ten segments, lit to the value.
---
--- "SPEED 7    ACCEL 6" is a table, and a table has to be read. A row of
--- segments is the shape of the build, and every kart game shows it that way
--- because you can compare two of them without doing any arithmetic.
function UI:NewStatBar(parent, width, label)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(width, 12)
  bar.label = self:NewText(bar, label, 11, AK.COLORS.muted, "LEFT")
  bar.label:SetPoint("LEFT", 0, 0)
  bar.label:SetWidth(66)
  bar.cells = {}
  local track = width - 72
  local gap = 2
  local cell = (track - gap * 9) / 10
  for i = 1, 10 do
    local segment = bar:CreateTexture(nil, "ARTWORK")
    segment:SetTexture("Interface\\Buttons\\WHITE8x8")
    segment:SetSize(cell, 7)
    segment:SetPoint("LEFT", 72 + (i - 1) * (cell + gap), 0)
    bar.cells[i] = segment
  end
  --- `value` is 0..10. The lit run is a gradient from lime to gold, so the top
  --- of a bar reads as the expensive end rather than as more of the same.
  function bar:Set(value)
    for i, segment in ipairs(self.cells) do
      if i <= value then
        local t = (i - 1) / 9
        segment:SetVertexColor(0.35 + 0.62 * t, 0.88 - 0.10 * t, 0.36 - 0.14 * t, 1)
      else
        segment:SetVertexColor(0.13, 0.17, 0.24, 1)
      end
    end
  end
  bar:Set(0)
  return bar
end

--- A MENU ROW: a name, what it is, and a mark when you are on it.
---
--- Twelve identical bars stacked in a column is a list of settings, not a game
--- menu. A row here says what it does on the right-hand side and grows a
--- chevron when the pointer is on it, so the modes read as things you choose
--- between rather than as twelve equally weighted commands.
function UI:NewMenuRow(parent, width, height, title, note, onClick)
  local row = self:NewButton(parent, "", width, height, onClick)
  row.label:Hide()
  row.title = self:NewText(row, title, 16, { .86, .90, 1 }, "LEFT")
  row.title:SetPoint("LEFT", 34, 0)
  row.note = self:NewText(row, note or "", 11, AK.COLORS.muted, "RIGHT")
  row.note:SetPoint("RIGHT", -16, 0)
  row.chevron = row:CreateTexture(nil, "OVERLAY")
  row.chevron:SetTexture(ART .. "chevron.tga")
  row.chevron:SetSize(11, 15)
  row.chevron:SetPoint("LEFT", 15, 0)
  row.chevron:SetVertexColor(unpack(AK.COLORS.gold))
  row.chevron:Hide()
  row:HookScript("OnEnter", function(frame)
    frame.chevron:Show()
    frame.title:SetTextColor(1, 0.95, 0.80)
  end)
  row:HookScript("OnLeave", function(frame)
    frame.chevron:Hide()
    frame.title:SetTextColor(.86, .90, 1)
  end)
  return row
end

AK.Menu = {}
local Menu = AK.Menu

--- Pages ARRIVE rather than appearing.
---
--- Every menu screen in the addon was swapped by hiding one frame and showing
--- another on the same tick, which is instant and free and reads as a form
--- being replaced. An eighth of a second of fade is the whole difference
--- between a page change and a screen transition; it is the cheapest polish
--- there is and it was simply never done.
local function fadeIn(frame, seconds)
  frame.akFade = 0
  frame:SetAlpha(0)
  frame:SetScript("OnUpdate", function(self, elapsed)
    self.akFade = math.min(1, (self.akFade or 0) + elapsed / (seconds or 0.13))
    -- Ease out, so it settles rather than stopping.
    self:SetAlpha(1 - (1 - self.akFade) * (1 - self.akFade))
    if self.akFade >= 1 then self:SetScript("OnUpdate", nil) end
  end)
end


-- The size the menu is authored at, and the size it therefore needs: a 960x520
-- panel centred a little low, with the title stack above it and the exit button
-- in the corner. That leaves the panel's top edge 215 units below the screen's
-- centre, so anything under about 750 units tall prints the tagline across the
-- top of the menu -- and on a client whose UIParent is much LARGER (a 4K screen
-- with the UI scale set to 1) the whole menu shrank to a card in the middle.
--
-- Same fix as the race HUD and the results screen: author once, scale to fit.
local MENU_W, MENU_H = 1120, 790

--- Fit the menu to the client. One SetScale on one container.
function Menu:Layout()
  if not self.stage or not self.frame then return end
  local width, height = self.frame:GetWidth(), self.frame:GetHeight()
  if not width or width <= 0 or not height or height <= 0 then return end
  self.stage:SetScale(AK.Math.Clamp(math.min(width / MENU_W, height / MENU_H), 0.50, 1.40))
end

function Menu:Build()
  if self.frame then return end
  local frame = CreateFrame("Frame", "AzerothKartMenu", UIParent)
  frame:SetAllPoints(UIParent)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  -- Above the race scene, which climbs to +500 for depth sorting. The menu is
  -- a scrim over a live demo race rather than an opaque wall.
  frame:SetFrameLevel(700)
  frame:EnableMouse(true)
  frame:Hide()
  self.frame = frame

  local scrim = frame:CreateTexture(nil, "BACKGROUND")
  scrim:SetTexture("Interface\\Buttons\\WHITE8x8")
  scrim:SetVertexColor(0.016, 0.024, 0.050, 0.74)
  scrim:SetAllPoints()
  local menuVignette = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  menuVignette:SetTexture(ART .. "vignette.tga")
  menuVignette:SetAllPoints()
  -- Lets the game's own ESC handling close the menu.
  tinsert(UISpecialFrames, "AzerothKartMenu")
  -- ...but UISpecialFrames calls Hide() on the FRAME, not Menu:Hide(), so the
  -- teardown has to live here or ESC skips it entirely. It did: the attract-mode
  -- race kept simulating and rendering the world with the menu gone and no way
  -- back to it. Every close path now runs the same teardown. OnHide only fires
  -- on a real shown -> hidden transition, so this cannot double-fire.
  frame:SetScript("OnHide", function()
    if AK.Race and AK.Race.StopAttract then AK.Race:StopAttract() end
    if AK.PlaySfx then AK:PlaySfx("uiClose") end
  end)

  -- Everything but the full-screen scrim rides one scaled container.
  local stage = CreateFrame("Frame", nil, frame)
  stage:SetAllPoints()
  self.stage = stage
  frame:SetScript("OnSizeChanged", function() Menu:Layout() end)

  local close = UI:NewButton(stage, "EXIT  (ESC)", 130, 32, function() self:Hide() end)
  close:SetPoint("TOPRIGHT", -30, -28)
  close:SetRestStyle({ .28, .09, .09, .95 }, AK.COLORS.danger)

  local glow = stage:CreateTexture(nil, "BACKGROUND")
  glow:SetTexture("Interface\\Buttons\\WHITE8x8")
  glow:SetVertexColor(0.08, 0.28, 0.45, 0.24)
  glow:SetSize(1200, 430)
  glow:SetPoint("TOP", 0, 70)
  local glowAnimation = glow:CreateAnimationGroup()
  local glowAlpha = glowAnimation:CreateAnimation("Alpha")
  glowAlpha:SetFromAlpha(.18)
  glowAlpha:SetToAlpha(.52)
  glowAlpha:SetDuration(2.2)
  glowAnimation:SetLooping("BOUNCE")
  glowAnimation:Play()

  -- Title treatment: glow behind, heavy shadow, rule beneath.
  local titleGlow = stage:CreateTexture(nil, "ARTWORK")
  titleGlow:SetTexture(ART .. "glow.tga")
  titleGlow:SetBlendMode("ADD")
  titleGlow:SetVertexColor(1, 0.72, 0.20, 1)
  titleGlow:SetPoint("TOP", 0, 20)
  titleGlow:SetSize(900, 300)
  titleGlow:SetAlpha(0.22)
  -- A WORDMARK, not a word. This was a 54pt gold FontString with a drop shadow;
  -- every game has a logo, and the difference between a logo and a label is the
  -- clearest single signal of whether a thing was designed. Drawn chunky and
  -- sheared into italic to match the rest of the art, which is low-resolution
  -- on purpose -- see Art/generate-art-ui.js.
  local title = stage:CreateTexture(nil, "ARTWORK")
  title:SetTexture(ART .. "logo.tga")
  -- 520x104 keeps the wordmark's 5:1 aspect and leaves the tagline clear of
  -- the content panel below. The 54pt FontString this replaced was shorter, so
  -- sizing the logo to look right in isolation put the tagline underneath the
  -- panel's top edge -- which is what Art/preview-ui.js is for.
  title:SetSize(520, 104)
  title:SetPoint("TOP", 0, -26)
  local titleRule = stage:CreateTexture(nil, "ARTWORK")
  titleRule:SetTexture(ART .. "hairline.tga")
  titleRule:SetPoint("TOP", title, "BOTTOM", 0, -2)
  titleRule:SetSize(560, 3)
  titleRule:SetVertexColor(1, 0.76, 0.20, 0.8)
  local tag = UI:NewText(stage, "THE MOST QUESTIONABLY SANCTIONED RACE IN AZEROTH", 14, AK.COLORS.muted, "CENTER")
  tag:SetPoint("TOP", titleRule, "BOTTOM", 0, -8)

  local content = UI:NewPanel(stage, 960, 520, { 0.045, 0.075, 0.125, 0.95 })
  content:SetPoint("CENTER", 0, -45)
  self.content = content
  self.dynamic = {}
  self:Layout()
  self:BuildHome()
end

function Menu:HideDynamic()
  for _, frame in ipairs(self.dynamic) do frame:Hide() end
  wipe(self.dynamic)
  if self.home then self.home:Hide() end
end

-- WHAT THIS GAME LETS YOU DO, IN THE ORDER YOU CARE.
--
-- The home screen used to be twelve identical bars in a column: RACE, then four
-- SELECT screens, then a cup, then four more modes, then a trophy room and the
-- settings -- all the same size, all the same colour, in the order they
-- happened to be written. That is a list of commands, not a menu. You cannot
-- tell what the game IS from it.
--
-- Three tiers now. The MODES are what you came for, so they get the weight and
-- a line each saying what they are. The GARAGE is what you change before
-- racing, so it is a row of four small buttons rather than four full-width
-- decisions. Trophies and settings are neither, so they sit small at the foot.
--
-- Declared as data because Art/preview-ui.js renders this screen from the same
-- table -- a hand-copied duplicate in the preview is a duplicate that drifts,
-- which is exactly what happened to the skyline.
local MODES = {
  { "GRAND PRIX", "four races, one trophy", function() AK.Race:StartGrandPrix() end,
    "Four races on the selected cup. Points after each; the trophy goes to the total." },
  { "QUICK RACE", "one race, full grid", function() AK.Race:Start("quick") end,
    "Your selected circuit against the full field." },
  { "TIME TRIAL", "you against your ghost", function() AK.Race:Start("time_trial") end,
    "No rivals and no items. Beat your own recorded lap." },
  { "BATTLE", "three balloons each", function() AK.Race:StartBattle() end,
    "An arena, not a circuit. Last kart with a balloon wins." },
  { "MULTIPLAYER", "your party or raid", function() AK.Menu:ShowMultiplayer() end,
    "Race other people who have the addon, over WoW's own addon channel." },
  { "PRACTICE", "no clock, no pressure", function() AK.Race:Start("practice") end,
    "Learn a circuit with nothing riding on it." },
}
local GARAGE = {
  { "RACER", "racer" }, { "KART", "kart" }, { "TRACK", "track" }, { "CUP", "cup" },
}

-- Every offset below is derived from these, and the whole stack is measured
-- against the content panel at the end of BuildHome. The settings screen had
-- to learn this the hard way: hand-counted pixels put "Racing scale"
-- underneath the keyboard legend and nobody noticed for a long time.
local HOME = {
  -- 468 rather than a rounder 470 so the four garage cells and the two footer
  -- buttons both divide into WHOLE pixels. A plate whose cap lands on a half
  -- pixel has a soft edge on one side and a hard one on the other, which is
  -- precisely the kind of thing that reads as "not quite right" without ever
  -- being nameable.
  modeW = 468, modeH = 42, modeGap = 5, modeTop = 88,
  headGap = 16, sectionGap = 16, rowGap = 24,
  garageH = 36, footH = 30, footGap = 12, gutter = 30,
  contentW = 960, contentH = 520, margin = 40,
}

function Menu:BuildHome()
  local home = CreateFrame("Frame", nil, self.content)
  home:SetAllPoints()
  self.home = home
  local welcome = UI:NewText(home, "Warm up your engines. No actual mounts were harmed.",
    15, { .74, .80, .90 }, "LEFT")
  welcome:SetPoint("TOPLEFT", 40, -30)

  local heading = UI:NewText(home, "RACE", 11, AK.COLORS.gold, "LEFT")
  heading:SetPoint("TOPLEFT", 42, -66)
  local rule = home:CreateTexture(nil, "ARTWORK")
  rule:SetTexture(ART .. "hairline.tga")
  rule:SetPoint("TOPLEFT", 40, -82)
  rule:SetSize(HOME.modeW, 2)
  rule:SetVertexColor(1, 0.78, 0.30, 0.35)

  for index, mode in ipairs(MODES) do
    local row = UI:NewMenuRow(home, HOME.modeW, HOME.modeH, mode[1], mode[2], mode[3])
    row:SetPoint("TOPLEFT", 40, -HOME.modeTop - (index - 1) * (HOME.modeH + HOME.modeGap))
    row.tooltip = mode[4]
    -- The headline mode is the one the game is FOR, so it is the one that is
    -- already lit rather than one of six identical dark bars.
    if index == 1 then
      row:SetRestStyle({ 0.42, 0.31, 0.08 }, { 1, 0.95, 0.80 })
      row.title:SetTextColor(1, 0.95, 0.80)
      row:HookScript("OnLeave", function(frame) frame.title:SetTextColor(1, 0.95, 0.80) end)
    end
  end

  local garageTop = HOME.modeTop + #MODES * (HOME.modeH + HOME.modeGap) + HOME.sectionGap
  local garageHead = UI:NewText(home, "GARAGE", 11, AK.COLORS.gold, "LEFT")
  garageHead:SetPoint("TOPLEFT", 42, -garageTop)
  local garageRule = home:CreateTexture(nil, "ARTWORK")
  garageRule:SetTexture(ART .. "hairline.tga")
  garageRule:SetPoint("TOPLEFT", 40, -garageTop - HOME.headGap)
  garageRule:SetSize(HOME.modeW, 2)
  garageRule:SetVertexColor(1, 0.78, 0.30, 0.35)

  local cell = (HOME.modeW - 3 * 8) / 4
  for index, entry in ipairs(GARAGE) do
    local button = UI:NewButton(home, entry[1], cell, HOME.garageH,
      function() self:ShowSelection(entry[2]) end)
    button:SetPoint("TOPLEFT", 40 + (index - 1) * (cell + 8), -garageTop - HOME.rowGap)
    button.label:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    button.tooltip = "Change your " .. entry[1]:lower() .. " before the next race."
  end

  local footTop = garageTop + HOME.rowGap + HOME.garageH + HOME.footGap
  local trophies = UI:NewButton(home, "TROPHY ROOM", (HOME.modeW - 8) / 2, HOME.footH,
    function() self:ShowAchievements() end)
  trophies:SetPoint("TOPLEFT", 40, -footTop)
  trophies:SetRestStyle({ 0.13, 0.17, 0.25 }, AK.COLORS.muted)
  trophies.label:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
  local settings = UI:NewButton(home, "SETTINGS", (HOME.modeW - 8) / 2, HOME.footH,
    function() self:ShowSettings() end)
  settings:SetPoint("TOPLEFT", 40 + (HOME.modeW - 8) / 2 + 8, -footTop)
  settings:SetRestStyle({ 0.13, 0.17, 0.25 }, AK.COLORS.muted)
  settings.label:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")

  -- WHAT YOU ARE ABOUT TO RACE, on the same screen as the button that starts
  -- it. The model, the circuit, your record on it and the combined stat line.
  local previewW = HOME.contentW - HOME.modeW - HOME.margin * 2 - HOME.gutter
  -- 420, not 400. The panel gained the racer's own line, and everything under
  -- it is anchored rather than hand-placed, so a two-line quip pushes the stack
  -- down -- which put the tokens-and-wins footer nine pixels through the bottom
  -- edge. There is room: the panel starts 66 down a 520-tall content area.
  local preview = UI:NewPanel(home, previewW, 420, { 0.055, 0.10, 0.17, .98 })
  preview:SetPoint("TOPRIGHT", -40, -66)
  self.preview = preview
  self.previewIcon = preview:CreateTexture(nil, "ARTWORK")
  self.previewIcon:SetSize(86, 86)
  self.previewIcon:SetPoint("TOP", 0, -22)
  -- The racer you have chosen, standing, three-quarter view, in the slot the
  -- flat icon used to hold. Standing for the same reason the cards are: this is
  -- a portrait of a person, not of someone sitting in a kart, and the seated
  -- pose at portrait distance is an unreadable hunch.
  self.previewModel = AK.Model:New(preview, 150, 150, -0.5,
    AK.Model:PortraitZoom(), nil, AK.MODEL.anim.stand)
  self.previewModel:SetPoint("TOP", 0, -6)
  self.previewTitle = UI:NewText(preview, "", 19, AK.COLORS.gold, "CENTER")
  self.previewTitle:SetPoint("TOP", 0, -158)
  -- The racer's line, next to the racer. It used to be printed on their card
  -- in CHOOSE YOUR RACER, where eleven cards share a 960x520 panel and there
  -- was no room for it -- so it went off the bottom of the card along with two
  -- stat lines. Here there is exactly one racer and they are standing above it.
  self.previewQuip = UI:NewText(preview, "", 11, { .58, .64, .74 }, "CENTER")
  self.previewQuip:SetPoint("TOPLEFT", 20, -186)
  self.previewQuip:SetPoint("TOPRIGHT", -20, -186)
  self.previewSub = UI:NewText(preview, "", 13, AK.COLORS.muted, "CENTER")
  self.previewSub:SetPoint("TOP", self.previewQuip, "BOTTOM", 0, -8)
  self.previewRecord = UI:NewText(preview, "", 12, AK.COLORS.gold, "CENTER")
  self.previewRecord:SetPoint("TOP", self.previewSub, "BOTTOM", 0, -6)
  -- ANCHORED, not hand-counted. A quip that wraps to two lines pushes
  -- everything under it down, and a stack of fixed offsets would just draw the
  -- bars through the text instead of moving out of its way.
  self.previewBars = {}
  -- ONE point each, because two would fight: a TOPLEFT and a TOPRIGHT both
  -- name a top, and the bars are already the panel's width less its margins,
  -- so centring them on the record is the same x with none of the argument.
  for index, name in ipairs({ "SPEED", "ACCEL", "HANDLING", "DRIFT" }) do
    local bar = UI:NewStatBar(preview, previewW - 48, name)
    if index == 1 then
      bar:SetPoint("TOP", self.previewRecord, "BOTTOM", 0, -9)
    else
      bar:SetPoint("TOP", self.previewBars[index - 1], "BOTTOM", 0, -4)
    end
    self.previewBars[index] = bar
  end
  self.previewStats = UI:NewText(preview, "", 12, { .86, .92, 1 }, "LEFT")
  self.previewStats:SetPoint("TOPLEFT", self.previewBars[4], "BOTTOMLEFT", 0, -10)
  self.previewStats:SetWidth(previewW - 48)
  self.previewStats:SetJustifyV("TOP")

  -- Say so rather than printing the footer over the edge of the panel.
  local used = footTop + HOME.footH
  if used > HOME.contentH - 10 then
    AK:Print("Home menu overflows its panel by " .. math.ceil(used - (HOME.contentH - 10)) .. "px.")
  end
end

function Menu:ShowMultiplayer()
  self:HideDynamic()
  self:Page("multiplayer", function(page) self:BuildMultiplayer(page) end):Show()
end

function Menu:BuildMultiplayer(page)
  local header = UI:NewText(page, "PARTY & RAID RACING", 25, AK.COLORS.gold, "CENTER")
  header:SetPoint("TOP", 0, -35)
  -- 680x400, and the buttons stacked down the left with the lobby status
  -- beside them. At 340 tall with the four buttons in a 2x2 block, the status
  -- text was anchored at (340, -183) and REFRESH LOBBIES occupied (350..630,
  -- 178..220): the one line telling you whether a lobby was found was printed
  -- straight through the button you press to look for one.
  local panel = UI:NewPanel(page, 680, 400, { .055, .10, .17, .98 })
  panel:SetPoint("CENTER", 0, 8)
  local back = UI:NewButton(page, "BACK", 120, 32, function() self:ShowHome() end)
  back:SetPoint("TOPLEFT", 25, -25)
  local description = UI:NewText(panel, "Race with people in your current party or raid who also have Azeroth Kart installed.\nThe host runs the race simulation and shares synchronized kart states through WoW's built-in addon channel.", 15, { .86, .92, 1 }, "CENTER")
  description:SetPoint("TOPLEFT", 35, -36)
  description:SetPoint("TOPRIGHT", -35, -36)
  -- Four actions, in the order you would take them, stacked. A 2x2 grid of
  -- four buttons has no reading order at all: which of the top two comes
  -- first is a coin toss, and one of them only makes sense after the other.
  local ACTIONS = {
    { "OPEN PARTY LOBBY", function() if AK.Net:OpenLobby() then page:akRefresh() end end },
    { "START HOST RACE", function() AK.Net:StartLobbyRace() end },
    { "JOIN ANNOUNCED LOBBY", function() AK.Net:JoinLobby() end },
    { "REFRESH LOBBIES", function()
        AK.Net:RefreshLobbies()
        -- Replies come back over the addon channel, so there is a beat before
        -- there is anything new to say. It only has to re-read the lobby now,
        -- not tear the screen down and build it again.
        C_Timer.After(.35, function()
          if self.frame and self.frame:IsShown() then page:akRefresh() end
        end)
      end },
  }
  for index, action in ipairs(ACTIONS) do
    local button = UI:NewButton(panel, action[1], 280, 42, action[2])
    button:SetPoint("TOPLEFT", 25, -112 - (index - 1) * 52)
    if index == 1 then button:SetRestStyle({ 0.42, 0.31, 0.08 }, { 1, 0.95, 0.80 }) end
  end
  -- The status column gets a heading, the same way the home screen's sections
  -- do, so it reads as a place rather than as a paragraph that happens to be
  -- over there.
  local lobbyHead = UI:NewText(panel, "LOBBY", 11, AK.COLORS.gold, "LEFT")
  lobbyHead:SetPoint("TOPLEFT", 332, -112)
  local lobbyRule = panel:CreateTexture(nil, "ARTWORK")
  lobbyRule:SetTexture(ART .. "hairline.tga")
  lobbyRule:SetPoint("TOPLEFT", 330, -128)
  lobbyRule:SetPoint("TOPRIGHT", -25, -128)
  lobbyRule:SetHeight(2)
  lobbyRule:SetVertexColor(1, 0.78, 0.30, 0.35)
  local lobbyText = UI:NewText(panel, "", 14, AK.COLORS.muted, "LEFT")
  lobbyText:SetPoint("TOPLEFT", 330, -140)
  lobbyText:SetPoint("TOPRIGHT", -25, -140)
  lobbyText:SetJustifyV("TOP")
  -- LIVE. This is the one readout on the screen that changes while you sit on
  -- it: a lobby opens, a friend announces one, a racer joins. It was baked in
  -- at build time and the four actions each rebuilt the whole page to update
  -- it -- which is why REFRESH LOBBIES had to wait a third of a second and then
  -- reconstruct everything. The page is kept now, so this is a refresh.
  --- WHO IS ON THE GRID, BY NAME.
  ---
  --- "3 racers ready" is the wrong readout for the one screen where the whole
  --- question is whether your friends got in. Names, sorted so the list does
  --- not reshuffle itself every time somebody joins, with the local player
  --- marked -- and capped, because a full raid lobby would otherwise run the
  --- list off the bottom of the panel.
  local function rosterLines(roster)
    local names = {}
    for name in pairs(roster or {}) do names[#names + 1] = name end
    table.sort(names)
    local me, lines = AK.Net:PlayerName(), {}
    for index, name in ipairs(names) do
      if index > 6 then
        lines[#lines + 1] = ("...and %d more"):format(#names - 6)
        break
      end
      -- Realm suffixes make every line the same length and unreadable.
      local short = name:match("^([^-]+)") or name
      lines[#lines + 1] = name == me
        and ("|cff%s%s (you)|r"):format(AK:ColorHex(AK.COLORS.gold), short)
        or ("  " .. short)
    end
    if #lines == 0 then lines[1] = "  nobody yet" end
    return table.concat(lines, "\n"), #names
  end

  function page:akRefresh()
    local own = AK.Net.lobby
    local found = AK.Net.availableLobby
    if own then
      local list, count = rosterLines(own.roster)
      lobbyText:SetText(("|cff%sHOSTING|r  --  %s\n%d of %d on the grid\n\n%s"):format(
        AK:ColorHex(AK.COLORS.lime), AK:GetTrack(own.track).name,
        count, AK.MAX_RACERS, list))
    elseif found then
      local list, count = rosterLines(found.roster)
      local joined = found.roster and found.roster[AK.Net:PlayerName()]
      lobbyText:SetText(("%s\nHost: %s  --  %s\n%d of %d on the grid\n\n%s"):format(
        joined and ("|cff" .. AK:ColorHex(AK.COLORS.lime) .. "YOU ARE IN|r")
          or ("|cff" .. AK:ColorHex(AK.COLORS.gold) .. "LOBBY FOUND|r"),
        found.host:match("^([^-]+)") or found.host,
        AK:GetTrack(found.track).name, count, AK.MAX_RACERS, list))
    else
      lobbyText:SetText(
        "No lobby announced yet.\nOpen one yourself, or press REFRESH LOBBIES\nonce a friend has opened theirs.")
    end
  end
  local note = UI:NewText(panel, "Multiplayer fills empty grid spots with AI racers. Results and unlocks are saved locally for every participant.", 13, AK.COLORS.muted, "CENTER")
  note:SetPoint("BOTTOMLEFT", 35, 25)
  note:SetPoint("BOTTOMRIGHT", -35, 25)
end

function Menu:UpdateSummary()
  local racer = AK:GetRacer(AK.db.selection.racer)
  local kart = AK:GetKart(AK.db.selection.kart)
  local track = AK:GetTrack(AK.db.selection.track)
  self.previewIcon:SetTexture(racer.icon)
  AK.Model:SetSpec(self.previewModel, racer.model)
  -- Re-read every visit: the portrait dial is live in the workshop, and the
  -- racer's own scale decides whether a gnome or a tauren fills the slot.
  self.previewModel.akZoom = AK.Model:PortraitZoom()
  self.previewModel.akSeatScale = racer.seatScale or 1
  AK.Model:Reframe(self.previewModel)
  self.previewModel:Show()
  self.previewIcon:Hide()
  C_Timer.After(1, function()
    if AK.Model:IsReady(self.previewModel) then return end
    self.previewModel:Hide()
    self.previewIcon:Show()
  end)
  self.previewTitle:SetText(racer.name .. " in the " .. kart.name)
  self.previewQuip:SetText(racer.quip or "")
  self.previewSub:SetText(track.name .. "  /  " .. track.subtitle)
  -- Your record on the circuit you are about to race, on the screen you press
  -- QUICK RACE from. It was two menus away.
  self.previewRecord:SetText(trackRecord(track.id))
  -- The build, as four bars rather than four numbers.
  local combined = {
    math.floor((racer.speed + kart.speed) / 2),
    math.floor((racer.acceleration + kart.acceleration) / 2),
    math.floor((racer.handling + kart.handling) / 2),
    math.floor((racer.drift + kart.drift) / 2),
  }
  for index, bar in ipairs(self.previewBars) do bar:Set(combined[index]) end
  self.previewStats:SetText(("|cff%s%s|r\n%s\n\nTOKENS |cff%s%d|r     WINS |cff%s%d|r")
    :format(AK:ColorHex(AK.COLORS.gold), track.theme, track.shortcut,
      AK:ColorHex(AK.COLORS.gold), AK.db.progress.coins,
      AK:ColorHex(AK.COLORS.gold), AK.db.progress.wins))
end

function Menu:ShowHome()
  self:HideDynamic()
  self.home:Show()
  fadeIn(self.home)
  self:UpdateSummary()
end

function Menu:AddDynamic(frame)
  table.insert(self.dynamic, frame)
  fadeIn(frame)
  return frame
end

--- A dynamic page, built once and kept.
---
--- A FRAME IS FOREVER. WoW has no way to destroy one -- Hide is all there is --
--- so every Show* that called CreateFrame on entry was leaving its entire page
--- behind on the way out and building another. CHOOSE YOUR RACER is eleven
--- PlayerModel frames, each holding a streamed creature display: open it ten
--- times in a session and a hundred and ten of them are alive and hidden, all
--- still owned by the client. That is the compounding cost behind "racer
--- select has some glitchyness" -- the screen gets slower and the models get
--- less reliable the longer you play, and a fresh visit re-streams every model
--- from scratch, which is the second of blank cards you see on the way in.
---
--- Built once, then refreshed. `akRefresh` is where anything that can change
--- between visits gets re-read.
function Menu:Page(key, build)
  self.pages = self.pages or {}
  local page = self.pages[key]
  if not page then
    page = CreateFrame("Frame", nil, self.content)
    page:SetAllPoints()
    self.pages[key] = page
    build(page)
  end
  if page.akRefresh then page:akRefresh() end
  return self:AddDynamic(page)
end

function Menu:ShowSelection(kind)
  self:HideDynamic()
  local page = self:Page("select:" .. kind, function(page) self:BuildSelection(page, kind) end)
  page:Show()
end

function Menu:BuildSelection(page, kind)
  local names = { racer = "CHOOSE YOUR RACER", kart = "CHOOSE YOUR KART", track = "CHOOSE YOUR TRACK", cup = "CHOOSE YOUR CUP" }
  local header = UI:NewText(page, names[kind], 25, AK.COLORS.gold, "CENTER")
  header:SetPoint("TOP", 0, -28)
  local back = UI:NewButton(page, "BACK", 120, 32, function() self:ShowHome() end)
  back:SetPoint("TOPLEFT", 25, -25)

  local entries = kind == "racer" and AK.Racers
    or (kind == "kart" and AK.Karts)
    or (kind == "cup" and AK.Cups)
    or AK.Tracks

  -- Size the grid from the entry count, never from hard-coded card dimensions.
  --
  -- Tracks outgrew this: seven entries at three columns is THREE rows, and the
  -- cards were a fixed 270x185 anchored into a content panel that is a fixed
  -- 960x520. The last row started 488px down and ran to 673px, so the whole
  -- third row hung ~150px outside the panel, floating on the world behind the
  -- menu. Growing WIDER rather than taller keeps the grid inside a panel whose
  -- height cannot change, so adding an eighth track re-flows instead of
  -- spilling.
  local MARGIN, TOP, GAP, BOTTOM, MIN_CARD, MAX_CARD = 42, 82, 18, 22, 150, 210
  -- What a racer card's text needs under the portrait: a name that may wrap to
  -- two lines at 14pt, the gap, two short stat lines at 11pt, and a margin.
  -- The portrait gets everything else, so adding a twelfth racer shrinks the
  -- picture rather than pushing the words off the bottom of the card.
  local RACER_TEXT = 92
  local availableW, availableH = 960 - MARGIN * 2, 520 - TOP - BOTTOM
  -- RACERS GO WIDE, BECAUSE A CHARACTER SELECT IS A WALL OF FACES.
  --
  -- Eleven racers at four columns is three rows, and three rows of a 416px
  -- space is a card ONE HUNDRED AND TWENTY-SIX pixels tall. Everything else on
  -- this screen fitted -- but the thing a racer card is actually for did not:
  -- the portrait got 64 of those pixels and the racer inside it was a
  -- centimetre tall, so the screen whose entire job is "who do you want to be"
  -- could not tell a tauren from a gnome.
  --
  -- Six columns is two rows, and two rows is a 131x199 card -- the tall tile
  -- every kart game's character select has used since the N64. The name wraps
  -- to two lines at that width, which is fine on a tall card and was the only
  -- reason four was ever chosen.
  local columns = kind == "racer" and 6 or 3
  local function rowsFor(n) return math.ceil(#entries / n) end
  local function heightFor(n)
    local rows = rowsFor(n)
    return math.floor((availableH - GAP * (rows - 1)) / rows)
  end
  if kind ~= "racer" then
    while columns < 5 and heightFor(columns) < MIN_CARD do columns = columns + 1 end
  end
  local cardWidth = math.floor((availableW - GAP * (columns - 1)) / columns)
  -- A CARD IS AS TALL AS ITS CONTENTS, NOT AS TALL AS THE PANEL.
  --
  -- heightFor divides the whole available height between the rows, which is
  -- right when there are three or four of them and absurd when there is one:
  -- the three cup cards came out 270 by FOUR HUNDRED AND SIXTEEN, with their
  -- text in the top forty per cent and two hundred and thirty pixels of empty
  -- plate below it -- and the button plate's caps, stretched over that, read as
  -- dark bands across the top and bottom of every card. The tallest thing any
  -- of these cards carries is a cup's four circuit names under an icon and a
  -- title, which comes to about a hundred and eighty.
  local cardHeight = math.min(heightFor(columns), MAX_CARD)
  -- Whatever height that leaves over goes above and below the grid, so a short
  -- grid sits in the middle of the panel instead of hanging from its top edge.
  local rows = rowsFor(columns)
  local RACER_PORTRAIT = math.max(32,
    math.min(cardWidth - 14, cardHeight - RACER_TEXT - 6))
  local used = rows * cardHeight + GAP * (rows - 1)
  local top = TOP + math.max(0, math.floor((availableH - used) / 2))

  local cards = {}
  for index, entry in ipairs(entries) do
    local card = UI:NewButton(page, "", cardWidth, cardHeight, function()
      AK.db.selection[kind] = entry.id
      self:ShowHome()
    end)
    cards[index] = { card = card, entry = entry }
    local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
    card:SetPoint("TOPLEFT", MARGIN + col * (cardWidth + GAP), -top - row * (cardHeight + GAP))
    -- A KART CARD IS A PICTURE OF A KART. Every card in this grid was given a
    -- 50px icon regardless of how much room it had: on a 205x199 kart card that
    -- is a stamp in the middle of an empty top third, with the text crammed
    -- under it and seventy pixels of bare plate below. The racer cards keep the
    -- small one -- there it is only the fallback for a model that has not
    -- streamed, and it has to sit in the model's own 64px slot.
    local iconSize = kind == "kart" and 68 or 50
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("TOP", 0, kind == "kart" and -10 or -15)
    icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_Map_01")
    if kind == "track" then
      -- The circuit itself, not a map icon shared with nine other circuits.
      icon:Hide()
      local shape = UI:NewTrackShape(card, entry, 56)
      shape:SetPoint("TOP", 0, -6)
    end
    if kind == "cup" then
      -- THE FOUR CIRCUITS, DRAWN. A cup has no icon of its own, so all three
      -- fell back to the same generic map -- three identical pictures above
      -- three different lists, which is worse than no picture at all. The names
      -- are already underneath; what a shape adds is the shape of the cup: how
      -- many hairpins, how many long sweeps, whether it is a fast set or a
      -- technical one, at a glance.
      icon:Hide()
      local plan = 44
      local span = #entry.tracks * plan
      for slot, trackId in ipairs(entry.tracks) do
        local shape = UI:NewTrackShape(card, AK:GetTrack(trackId), plan)
        shape:SetPoint("TOP", -span * 0.5 + plan * (slot - 0.5), -8)
      end
    end
    if kind == "racer" then
      -- A CHARACTER-SELECT CARD IS A PICTURE OF THE CHARACTER.
      --
      -- This was a 64px seated model at the top of a 205x210 card: a hunched
      -- figure a couple of centimetres tall with a hundred and ten pixels of
      -- bare plate under it, on the screen whose entire job is "who do you want
      -- to be". You could not tell a tauren from a gnome. The portrait now
      -- takes the whole upper card and the racer STANDS in it -- the seated
      -- pose belongs in a kart, and reads as a shape rather than a person from
      -- a fixed portrait camera.
      local model = AK.Model:New(card, RACER_PORTRAIT, RACER_PORTRAIT, -0.45,
        AK.Model:PortraitZoom(), entry.model, AK.MODEL.anim.stand)
      model:SetPoint("TOP", 0, -6)
      -- The racer's own scale still applies, so a gnome and a tauren fill the
      -- same card -- but not their SEAT height, which is a nudge for sitting in
      -- a kart and has nothing to say about standing in a portrait.
      model.akSeatScale = entry.seatScale or 1
      AK.Model:Reframe(model)
      icon:Hide()
      icon:SetSize(72, 72)
      icon:ClearAllPoints()
      icon:SetPoint("TOP", 0, -RACER_PORTRAIT * 0.5 + 36)
      cards[index].model, cards[index].icon = model, icon
    end
    local name = UI:NewText(card, entry.name, kind == "racer" and 14 or 16,
      AK.COLORS.gold, "CENTER")
    cards[index].name = name
    -- The track cards carry a 64px plan view where the others carry a 50px
    -- icon, so the name starts a little lower on those; the racer cards carry
    -- a model and are the shortest, so theirs starts higher still.
    local nameTop = (kind == "track" and 68)
      or (kind == "racer" and (RACER_PORTRAIT + 8))
      or (kind == "cup" and 58)
      or (kind == "kart" and 84) or 72
    name:SetPoint("TOPLEFT", 7, -nameTop)
    name:SetPoint("TOPRIGHT", -7, -nameTop)
    -- A gold card IS the selection. Printing the word "SELECTED" under it as
    -- well is a caption on a picture of itself; a mark in the corner is how a
    -- game says it. Built for every card and SHOWN for the chosen one, because
    -- the page outlives the choice now.
    local tick = card:CreateTexture(nil, "OVERLAY")
    tick:SetTexture(ART .. "chevron.tga")
    tick:SetSize(12, 16)
    tick:SetPoint("TOPLEFT", 9, -9)
    tick:SetVertexColor(1, 0.95, 0.80, 1)
    cards[index].tick = tick
    -- ANCHORED TO THE NAME, not to a hand-counted -99. At five columns a card
    -- is 160px wide and "Stranglethorn Grand Prix" wraps to two lines, which
    -- ran the name straight through the detail underneath it. Flowing from the
    -- name's own bottom edge cannot collide however long a name gets.
    -- 11pt on a racer card: at 12 the four-stat line is 190px wide against a
    -- 187px card and wraps to a second line the card has no room for.
    local detail = UI:NewText(card, "", kind == "racer" and 11 or 12, AK.COLORS.muted, "CENTER")
    if kind == "racer" then
      -- PINNED TO THE FLOOR, not flowed from the name. Six of the eleven names
      -- fit on one line at this width and five wrap to two, so a stat block
      -- hanging off the name's bottom edge sat at two different heights across
      -- the grid -- a ragged row of numbers that reads as a layout accident.
      -- Every card's stats are on the same line now, whatever the name did.
      detail:SetPoint("BOTTOMLEFT", 2, 9)
      detail:SetPoint("BOTTOMRIGHT", -2, 9)
    else
      detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 2, -7)
      detail:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", -2, -7)
    end
    if kind == "racer" then
      -- ONE LINE. The race, two stat lines, a blank and the quip is five lines
      -- of text under a model on a 126px card, and it did not fit by a factor
      -- of two. The quip has a home on the setup panel, where the racer you
      -- have actually chosen is standing and there is room to read it; the
      -- rest of the stats are on the bars there too. What a card in a grid of
      -- eleven has to answer is "who is this and what are they good at".
      -- TWO SHORT LINES, not one wide one. "SPD 6  ACC 5  HND 6  DRF 6" is
      -- about 155px at 11pt and the card is 131 wide, so it wrapped wherever
      -- the client felt like -- usually leaving a single orphaned "DRF 6" on
      -- the second line. Broken deliberately down the middle instead.
      detail:SetText(("SPD %d   ACC %d\nHND %d   DRF %d"):format(
        entry.speed, entry.acceleration, entry.handling, entry.drift))
    elseif kind == "kart" then
      detail:SetText(("%s\nSPD %d  ACC %d  HND %d\nWEIGHT %d  DRIFT %d"):format(entry.description, entry.speed, entry.acceleration, entry.handling, entry.weight, entry.drift))
    elseif kind == "cup" then
      local names = {}
      for _, trackId in ipairs(entry.tracks) do table.insert(names, AK:GetTrack(trackId).name) end
      detail:SetText(("%d races\n%s"):format(#entry.tracks, table.concat(names, "\n")))
    else
      cards[index].detail = detail
      -- Lap count came off a hard-coded "3 laps" that would have lied the
      -- moment a circuit was authored with a different one.
      -- THREE LINES, not five. This used to carry the subtitle, the shortcut
      -- blurb, the lap count, a blank and the record -- and with five columns
      -- the cards are 160px wide, so the subtitle wraps and the name wraps and
      -- the whole stack ran off the bottom of the card. The shortcut already
      -- has a home on the setup panel, where there is room to read it.
      detail:SetText(("%s\n%d LAPS  /  %dM\n|cff%s%s|r"):format(
        entry.subtitle, entry.laps or 3, entry.length,
        AK:ColorHex(AK.COLORS.gold), trackRecord(entry.id)))
    end
  end

  --- A model that has not streamed yet falls back to its flat icon.
  ---
  --- This used to be a single C_Timer.After(1) fired at build time, which was
  --- survivable only because the page was rebuilt on every visit. Now that it
  --- is kept, one shot at one second would decide a card's appearance FOREVER:
  --- a creature that took 1.1s to resolve on the first ever visit would show
  --- its icon for the rest of the session. Asked again on the way in, and once
  --- more a second later to catch what is still in flight.
  local function settleModels()
    for _, slot in ipairs(cards) do
      if slot.model then
        local ready = AK.Model:IsReady(slot.model)
        slot.model:SetShown(ready)
        slot.icon:SetShown(not ready)
      end
    end
  end

  --- Everything that can have changed since the last visit.
  function page:akRefresh()
    settleModels()
    C_Timer.After(1, settleModels)
    for _, slot in ipairs(cards) do
      local chosen = AK.db.selection[kind] == slot.entry.id
      -- The unchosen colour is NewButton's own default, not a second copy of
      -- it typed here: a card that has just been deselected has to go back to
      -- looking exactly like one that was never chosen.
      slot.card:SetRestStyle(chosen and { 0.44, 0.33, 0.09 } or UI.BUTTON_REST,
        chosen and { 1, 0.95, 0.80 } or AK.COLORS.gold)
      slot.name:SetTextColor(unpack(chosen and { 1, 0.95, 0.80 } or AK.COLORS.gold))
      slot.tick:SetShown(chosen)
      -- A lap record set since the page was built has to appear on it.
      if slot.detail then
        slot.detail:SetText(("%s\n%d LAPS  /  %dM\n|cff%s%s|r"):format(
          slot.entry.subtitle, slot.entry.laps or 3, slot.entry.length,
          AK:ColorHex(AK.COLORS.gold), trackRecord(slot.entry.id)))
      end
    end
  end
end

--- The trophy room.
---
--- Achievements were write-only: unlocking one printed a single chat line that
--- scrolled away, and nothing anywhere ever listed them again. The player could
--- not see what existed, what they had, or what was left -- so the whole system
--- may as well not have been there. This is that list.
function Menu:ShowAchievements()
  self:HideDynamic()
  self:Page("trophies", function(page) self:BuildAchievements(page) end):Show()
end

function Menu:BuildAchievements(page)
  local header = UI:NewText(page, "TROPHY ROOM", 25, AK.COLORS.gold, "CENTER")
  header:SetPoint("TOP", 0, -28)
  local back = UI:NewButton(page, "BACK", 120, 32, function() self:ShowHome() end)
  back:SetPoint("TOPLEFT", 25, -25)

  local order = AK.AchievementOrder or {}

  local summary = UI:NewText(page, "", 14, AK.COLORS.lime, "CENTER")
  summary:SetPoint("TOP", header, "BOTTOM", 0, -4)
  -- The whole point of this screen is what you have EARNED, and that changes
  -- every race. Colours, marks, the count and the career line are all set in
  -- akRefresh below rather than baked in at build time.
  local slots = {}

  -- Two columns, sized from the entry count rather than hard-coded, so adding
  -- an achievement re-flows instead of spilling off the panel.
  local COLUMNS, MARGIN, TOP, GAP = 2, 40, 92, 6
  local cardWidth = math.floor((960 - MARGIN * 2 - GAP * (COLUMNS - 1)) / COLUMNS)
  local rows = math.ceil(#order / COLUMNS)
  local cardHeight = math.min(52, math.floor((520 - TOP - 56 - GAP * (rows - 1)) / math.max(1, rows)))

  for index, id in ipairs(order) do
    local achievement = AK.Achievements[id]
    if achievement then
      local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
      local card = UI:NewPanel(page, cardWidth, cardHeight, { .07, .09, .14, .94 })
      card:SetPoint("TOPLEFT", MARGIN + column * (cardWidth + GAP), -TOP - row * (cardHeight + GAP))

      -- A tick versus an empty socket, so earned reads at a glance without
      -- relying on colour alone. These were the characters "*" and "-": typing
      -- a shape rather than drawing one is the loudest possible sign that
      -- nobody ever looked at the screen.
      local mark = card:CreateTexture(nil, "ARTWORK")
      mark:SetSize(14, 14)
      mark:SetPoint("LEFT", 11, 0)

      local name = UI:NewText(card, achievement.name, 14, { .62, .66, .74 }, "LEFT")
      name:SetPoint("TOPLEFT", 30, -7)
      local description = UI:NewText(card, achievement.description, 11, { .44, .48, .56 }, "LEFT")
      description:SetPoint("TOPLEFT", 30, -25)
      description:SetWidth(cardWidth - 42)
      description:SetJustifyH("LEFT")
      slots[#slots + 1] =
        { id = id, card = card, mark = mark, name = name, description = description }
    end
  end

  local stats = UI:NewText(page, "", 13, AK.COLORS.muted, "CENTER")
  stats:SetPoint("BOTTOM", 0, 18)

  function page:akRefresh()
    local progress = AK.db.progress
    local earned = progress.achievements or {}
    local have = 0
    for _, slot in ipairs(slots) do
      local got = earned[slot.id] and true or false
      if got then have = have + 1 end
      slot.card:SetPlateColor(got and { .10, .18, .12, .96 } or { .07, .09, .14, .94 })
      slot.mark:SetTexture(ART .. (got and "tick.tga" or "socket.tga"))
      slot.mark:SetVertexColor(unpack(got and AK.COLORS.gold or { .34, .38, .46 }))
      slot.name:SetTextColor(unpack(got and AK.COLORS.gold or { .62, .66, .74 }))
      slot.description:SetTextColor(unpack(got and { .78, .86, .78 } or { .44, .48, .56 }))
    end
    summary:SetText(("%d of %d earned"):format(have, #order))
    local trophies = 0
    for _ in pairs(progress.trophies or {}) do trophies = trophies + 1 end
    stats:SetText(("RACES %d      WINS %d      PODIUMS %d      CUPS %d      TOKENS %d")
      :format(progress.races or 0, progress.wins or 0, progress.podiums or 0,
        trophies, progress.coins or 0))
  end
end

--- WHAT EVERY SETTING ACTUALLY DOES.
---
--- The old settings screen was nine rows of "Reduced effects  [OFF]". That
--- tells you the state of a switch and nothing else: not what it changes, not
--- what it costs, not why you would want it. Every row here says what it is
--- for in one line, and the rows are grouped so the screen has a shape rather
--- than being a list nine items long.
local SETTING_GROUPS = {
  {
    title = "THE RACE",
    rows = {
      { key = "engineClass", name = "Engine class",
        blurb = "How fast the whole field goes. 150cc is the real thing.",
        choices = { { value = "50cc", label = "50cc" }, { value = "100cc", label = "100cc" },
          { value = "150cc", label = "150cc" } } },
      { key = "difficulty", name = "Rival skill",
        blurb = "Hard brakes later and drifts better. It is not handed speed.",
        choices = { { value = "Easy", label = "EASY" }, { value = "Normal", label = "NORMAL" },
          { value = "Hard", label = "HARD" } } },
      { key = "aiCount", name = "Field size",
        blurb = "How many rivals line up alongside you.",
        step = { min = 3, max = AK.MAX_RACERS - 1, by = 1,
          format = function(value) return value .. " RIVALS" end } },
      { key = "camBack", tuning = true, name = "Camera",
        blurb = "How far the camera trails your kart. Close is busier; far sees more.",
        choices = { { value = 4.2, label = "CLOSE" }, { value = 6.0, label = "STANDARD" },
          { value = 8.4, label = "FAR" } } },
      { key = "mirror", name = "Mirror mode",
        blurb = "Every circuit flipped left to right. Everything you know is wrong.",
        choices = { { value = false, label = "OFF" }, { value = true, label = "ON" } } },
    },
  },
  {
    title = "SOUND",
    rows = {
      { key = "sfx", name = "Sound effects",
        blurb = "Item hits, boosts, the countdown and the flag.",
        choices = { { value = false, label = "OFF" }, { value = true, label = "ON" } } },
      { key = "engineNote", name = "Engine note",
        blurb = "A revving tone tied to your speed. Repetitive by nature -- off by default.",
        choices = { { value = false, label = "OFF" }, { value = true, label = "ON" } } },
    },
  },
  {
    title = "THE PICTURE", column = 2,
    rows = {
      { key = "roadDetail", name = "Road detail",
        blurb = "How finely the road is sliced. The biggest frame-rate dial there is.",
        choices = { { value = "Low", label = "LOW" }, { value = "Balanced", label = "BALANCED" },
          { value = "High", label = "HIGH" } } },
      { key = "reducedEffects", name = "Reduced effects",
        blurb = "Drops sparks, speed lines and lens motion. Use it if the frame rate dips.",
        choices = { { value = false, label = "FULL" }, { value = true, label = "REDUCED" } } },
      { key = "showControls", name = "On-screen controls",
        blurb = "Steering and throttle pads along the bottom. Every one has a key.",
        choices = { { value = false, label = "OFF" }, { value = true, label = "ON" } } },
      { key = "showSpeed", name = "Speedometer",
        blurb = "The km/h readout under the clock.",
        choices = { { value = false, label = "OFF" }, { value = true, label = "ON" } } },
      { key = "showMinimap", name = "Circuit map",
        blurb = "The plan view in the bottom corner, with every kart on it.",
        choices = { { value = false, label = "OFF" }, { value = true, label = "ON" } } },
      { key = "uiScale", name = "Screen scale",
        blurb = "Sizes the whole race against your monitor.",
        step = { min = 0.8, max = 1.4, by = 0.05,
          format = function(value) return ("%d%%"):format(value * 100 + 0.5) end } },
      -- Lived only in the workshop, which is a developer panel reached by a
      -- slash command. How big the HUD is on your monitor is not a developer
      -- question.
      { key = "hudScale", tuning = true, name = "HUD size",
        blurb = "How large the lap counter, clock and place readout are drawn.",
        step = { min = 60, max = 160, by = 10,
          format = function(value) return ("%d%%"):format(value) end } },
    },
  },
}

local SETTING_DEFAULTS = {
  engineClass = "150cc", difficulty = "Normal", aiCount = 7, mirror = false,
  sfx = true, engineNote = false,
  reducedEffects = false, showSpeed = true, showMinimap = true, uiScale = 1,
  roadDetail = "Balanced", showControls = false, debug = false,
}
--- The two rows on this screen that write to the render tuning instead.
local TUNING_DEFAULTS = { camBack = 6.0, hudScale = 100 }

-- Sized so the tallest column -- five race rows plus two sound rows, each with
-- its explanation under it -- clears the keyboard legend along the bottom.
-- Every previous version of this screen was laid out by hand-counted pixels
-- and something always ended up printed underneath something else.
-- GROUP_GAP is 14 rather than 18 because at 18 the left column -- five race
-- rows plus two sound rows, each with its explanation -- overflowed the panel
-- by four pixels. The screen printed a warning about it to the chat frame,
-- where nobody was ever going to see it; Art/preview-ui.js fails outright now.
local ROW_H, GROUP_GAP, COLUMN_W = 44, 14, 434
--- Air between the buttons along the bottom of the settings page.
local FOOTER_GAP = 16

--- Draws one group of settings into `parent`, top-left at (x, y). Returns the
--- height it used, so the next group can be stacked under it without anybody
--- hand-counting pixels -- which is how "Racing scale" ended up printed
--- underneath the keyboard legend on the old screen.
function Menu:BuildSettingGroup(parent, group, x, y, controls)
  local title = UI:NewText(parent, group.title, 12, AK.COLORS.gold, "LEFT")
  title:SetPoint("TOPLEFT", x, y)
  local rule = parent:CreateTexture(nil, "ARTWORK")
  rule:SetTexture("Interface\\Buttons\\WHITE8x8")
  rule:SetVertexColor(0.85, 0.70, 0.35, 0.30)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", x, y - 16)
  rule:SetWidth(COLUMN_W)

  for index, row in ipairs(group.rows) do
    -- Two stores behind one screen: most rows are gameplay settings, a couple
    -- are render dials that used to be reachable only through /kart tune.
    local settings = row.tuning and AK.db.tuning or AK.db.settings
    local top = y - 24 - (index - 1) * ROW_H
    local label = UI:NewText(parent, row.name, 14, { .90, .94, 1 }, "LEFT")
    label:SetPoint("TOPLEFT", x + 2, top - 6)
    -- Below the CONTROL, not just below the name. The picker occupies the
    -- right 168px of the row from top-4 to top-26, and an explanation starting
    -- at top-24 ran its last two pixels underneath it.
    local blurb = UI:NewText(parent, row.blurb, 10, { .50, .56, .66 }, "LEFT")
    blurb:SetPoint("TOPLEFT", x + 2, top - 27)
    blurb:SetWidth(COLUMN_W - 8)
    blurb:SetJustifyH("LEFT")

    local control
    if row.choices then
      control = UI:NewSegmented(parent, 168, 22, row.choices,
        function() return settings[row.key] end,
        function(value) settings[row.key] = value; Menu:SettingChanged(row.key) end)
    else
      local spec = row.step
      control = UI:NewStepper(parent, 168, 22,
        function() return settings[row.key] end,
        function(direction)
          local value = (settings[row.key] or spec.min) + direction * spec.by
          -- Wrap rather than stop dead at the ends: a stepper that silently
          -- does nothing reads as broken.
          if value > spec.max + 0.0001 then value = spec.min end
          if value < spec.min - 0.0001 then value = spec.max end
          -- Snap, or repeated 0.05 steps drift into 0.9500000000000001.
          settings[row.key] = math.floor(value / spec.by + 0.5) * spec.by
          Menu:SettingChanged(row.key)
        end,
        spec.format)
    end
    control:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + COLUMN_W, top - 4)
    controls[#controls + 1] = control
  end
  return 24 + #group.rows * ROW_H + GROUP_GAP
end

--- Some settings have to reach something that is already on screen.
function Menu:SettingChanged(key)
  if key == "uiScale" and AK.RaceUI and AK.RaceUI.frame then
    AK.RaceUI.frame:SetScale(AK.db.settings.uiScale or 1)
  end
  -- The developer switch changes this very page while it is open.
  local settings = self.pages and self.pages.settings
  if key == "debug" and settings and settings.akLayoutFooter then settings:akLayoutFooter() end
  if AK.PlaySfx then AK:PlaySfx("uiClick") end
end

function Menu:ShowSettings()
  self:HideDynamic()
  self:Page("settings", function(page) self:BuildSettings(page) end):Show()
end

function Menu:BuildSettings(page)
  local header = UI:NewText(page, "SETTINGS", 25, AK.COLORS.gold, "CENTER")
  header:SetPoint("TOP", 0, -22)
  local back = UI:NewButton(page, "BACK", 120, 32, function() self:ShowHome() end)
  back:SetPoint("TOPLEFT", 25, -20)

  local controls = {}
  -- Two columns. Nine settings in one column is a scroll bar waiting to happen;
  -- two columns of grouped rows fits the panel exactly and reads as a page.
  -- -62 clears the BACK button, which is 32px tall at -20. At -48 the first
  -- section heading was printed through it.
  local leftX, rightX, top = 34, 34 + COLUMN_W + 30, -62
  local nextY = { top, top }
  for _, group in ipairs(SETTING_GROUPS) do
    local column = group.column or 1
    local x = column == 1 and leftX or rightX
    nextY[column] = nextY[column]
      - self:BuildSettingGroup(page, group, x, nextY[column], controls)
  end

  local restore = UI:NewButton(page, "RESTORE DEFAULTS", 180, 30, function()
    for key, value in pairs(SETTING_DEFAULTS) do AK.db.settings[key] = value end
    for key, value in pairs(TUNING_DEFAULTS) do AK.db.tuning[key] = value end
    for _, control in ipairs(controls) do control:Refresh() end
    if page.akLayoutFooter then page:akLayoutFooter() end
    self:SettingChanged("uiScale")
  end)
  restore:SetPoint("TOPRIGHT", -25, -20)
  restore.tooltip = "Puts every setting on this page back to how it shipped."

  -- The keyboard legend, along the bottom of the whole page rather than inside
  -- one column's panel.
  local rule = page:CreateTexture(nil, "ARTWORK")
  rule:SetTexture("Interface\\Buttons\\WHITE8x8")
  rule:SetVertexColor(0.38, 0.65, 0.92, 0.26)
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", 34, 52)
  rule:SetPoint("BOTTOMRIGHT", -34, 52)
  local help = UI:NewText(page,
    "W or UP accelerate     A D or LEFT RIGHT steer     SPACE hop and drift     SHIFT use item     S or DOWN brake and reverse     ESC pause",
    12, AK.COLORS.muted, "CENTER")
  help:SetPoint("BOTTOM", 0, 32)
  -- BUTTONS, NOT A SLASH COMMAND PRINTED ON A SCREEN.
  --
  -- This line said "Camera, road and handling dials live in the workshop: /kart
  -- tune" and left it there. The sound editor -- the only way to replace the
  -- interface blips this game ships with, and the answer to the loudest
  -- standing complaint about it -- was reachable ONLY from inside that
  -- workshop or by typing /kart sfx. A tool nobody can find is not a tool, and
  -- a player who has just read two rows about sound is exactly the player
  -- looking for it.
  -- The keyboard legend sits at BOTTOM 32 and is about fifteen tall, so the
  -- buttons have the bottom thirty pixels and no more.
  -- The workshop is a DEVELOPER panel -- it edits the roster and adds racers --
  -- so it travels with the developer switch. The sound editor does not: picking
  -- which noise the game makes when you hit a boost pad is a player's business,
  -- and it is the answer to the loudest standing complaint about this game.
  -- When the workshop is away the sound editor takes the middle rather than
  -- sitting off to one side of a gap.
  local workshop = UI:NewButton(page, "WORKSHOP", 150, 24, function()
    self:Hide()
    AK.Workshop:Toggle()
  end)
  -- Anchored here as well as in the layout below, so a footer control is never
  -- an unplaced widget stacked in the corner of the page.
  workshop:SetPoint("BOTTOM", 196, 4)
  workshop.tooltip = "Camera, road and handling dials."
  local sounds = UI:NewButton(page, "SOUND EDITOR", 150, 24, function()
    self:Hide()
    AK.SoundEditor:Toggle()
  end)
  -- THE DEVELOPER SWITCH LIVES IN THE FOOTER, not in a column.
  --
  -- It was a row in a settings group first, and the group's heading pushed the
  -- left column seventy pixels past the keyboard legend -- the two columns are
  -- laid out to fill the panel exactly, and there is no eighth row's worth of
  -- room in either of them. It also does not belong beside "Mirror mode": every
  -- other row on this page changes how the game plays or looks, and this one
  -- changes which tools are on screen. The bottom of a settings page is where
  -- the advanced door has always been.
  local dev = UI:NewButton(page, "DEVELOPER TOOLS: OFF", 220, 24, function()
    AK.db.settings.debug = not AK.db.settings.debug
    self:SettingChanged("debug")
  end)
  dev:SetPoint("BOTTOM", -196, 4)
  dev.tooltip = "Adds the live tuning panel, the presentation-beat player and "
    .. "AI telemetry to the pause menu. Off is the shipped game."

  function page:akLayoutFooter()
    local on = AK.db.settings.debug and true or false
    dev.label:SetText(on and "DEVELOPER TOOLS: ON" or "DEVELOPER TOOLS: OFF")
    dev:SetRestStyle(on and { .16, .36, .24 } or UI.BUTTON_REST,
      on and AK.COLORS.lime or AK.COLORS.gold)
    workshop:SetShown(on)
    -- Centred as a row, measured from the buttons' own widths. Hand-picked
    -- offsets were how the last version worked and they were wrong the moment
    -- one of the three came or went, or a label got a word longer.
    local row = { dev, sounds }
    if on then row[3] = workshop end
    local total = -FOOTER_GAP
    for _, button in ipairs(row) do total = total + button:GetWidth() + FOOTER_GAP end
    local x = -total * 0.5
    for _, button in ipairs(row) do
      local w = button:GetWidth()
      button:ClearAllPoints()
      button:SetPoint("BOTTOM", x + w * 0.5, 4)
      x = x + w + FOOTER_GAP
    end
  end
  sounds:SetPoint("BOTTOM", 0, 4)
  sounds.tooltip =
    "Every cue in the game, auditioned and rebound by ear. The game's whole "
    .. "audio library is searchable from here."
  -- The layout is derived, not hand-placed, but a group can still be added
  -- that does not fit. Say so in the log rather than printing it over the
  -- keyboard legend and hoping somebody notices.
  -- The footer rule sits 52px off the bottom of a 520-tall page, so the
  -- columns have 468 minus a little breathing room. The old 440 was a guess
  -- and it was pessimistic by twenty pixels, which is exactly enough to have
  -- forced the layout tighter than it needed to be.
  local used = -math.min(nextY[1], nextY[2])
  if used > 458 then
    AK:Print("Settings page overflows its panel by " .. math.ceil(used - 458) .. "px.")
  end

  --- The page outlives a visit now, and a setting can be changed from outside
  --- it -- RESTORE DEFAULTS, /kart tune, a fresh profile -- so every control
  --- re-reads its value on the way in rather than on the way out.
  function page:akRefresh()
    for _, control in ipairs(controls) do control:Refresh() end
    self:akLayoutFooter()
  end
  page:akLayoutFooter()
end

function Menu:Show()
  self:Build()
  local wasShown = self.frame:IsShown()
  self.frame:Show()
  self:ShowHome()
  -- A live demo race runs behind the menu instead of a dead backdrop.
  if AK.Race and AK.Race.StartAttract then AK.Race:StartAttract() end
  if not wasShown and AK.PlaySfx then AK:PlaySfx("uiOpen") end
end

function Menu:Hide()
  -- The teardown lives on the frame's OnHide so that ESC, which closes this
  -- through UISpecialFrames without ever calling here, tears down identically.
  if not self.frame then return end
  self.frame:Hide()
end
