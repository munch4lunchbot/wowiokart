local _, AK = ...

AK.UI = AK.UI or {}
local UI = AK.UI

local function backdrop(color, border)
  return {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
    bgColor = color,
    edgeColor = border or AK.COLORS.gold,
  }
end

local function applyBackdrop(frame, color, border)
  frame:SetBackdrop(backdrop())
  frame:SetBackdropColor(unpack(color or AK.COLORS.panel))
  frame:SetBackdropBorderColor(unpack(border or AK.COLORS.gold))
end

local ART = "Interface\\AddOns\\kart\\Art\\"

--- Panels get a bevelled gradient skin and a lit top edge. A flat rectangle
--- with a one-pixel border is the single most "unfinished" thing on screen,
--- and every panel in the addon goes through here.
function UI:NewPanel(parent, width, height, color)
  local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  panel:SetSize(width, height)
  applyBackdrop(panel, color or AK.COLORS.panel)
  local skin = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
  skin:SetTexture(ART .. "panel.tga")
  skin:SetPoint("TOPLEFT", 1, -1)
  skin:SetPoint("BOTTOMRIGHT", -1, 1)
  skin:SetAlpha(0.85)
  panel.skin = skin
  -- Warm hairline along the top, catching the light.
  local gleam = panel:CreateTexture(nil, "BORDER")
  gleam:SetTexture(ART .. "hairline.tga")
  gleam:SetPoint("TOPLEFT", 2, -1)
  gleam:SetPoint("TOPRIGHT", -2, -1)
  gleam:SetHeight(2)
  gleam:SetVertexColor(1, 0.86, 0.55, 0.34)
  panel.gleam = gleam
  return panel
end

function UI:NewText(parent, text, size, color, justify)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetFont(STANDARD_TEXT_FONT, size or 14, "OUTLINE")
  label:SetTextColor(unpack(color or { 1, 1, 1 }))
  label:SetJustifyH(justify or "LEFT")
  label:SetText(text or "")
  return label
end

function UI:NewButton(parent, text, width, height, onClick)
  local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
  button:SetSize(width, height)
  button.restColor = { 0.10, 0.19, 0.31, 0.98 }
  button.restBorder = { 0.38, 0.65, 0.92 }
  applyBackdrop(button, button.restColor, button.restBorder)
  function button:SetRestStyle(color, border)
    self.restColor, self.restBorder = color, border
    applyBackdrop(self, color, border)
  end
  button.label = self:NewText(button, text, 15, AK.COLORS.gold, "CENTER")
  button.label:SetAllPoints()
  button:SetScript("OnEnter", function(frame)
    applyBackdrop(frame, { 0.16, 0.31, 0.48, 1 }, AK.COLORS.gold)
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
    applyBackdrop(frame, frame.restColor, frame.restBorder)
    GameTooltip:Hide()
  end)
  button:SetScript("OnClick", function(frame, ...)
    if AK.PlaySfx and not frame.quiet then AK:PlaySfx("uiClick") end
    if onClick then onClick(frame, ...) end
  end)
  button:SetScript("OnMouseDown", function(frame)
    frame.label:ClearAllPoints()
    frame.label:SetPoint("CENTER", 1, -1)
  end)
  button:SetScript("OnMouseUp", function(frame)
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
    for _, button in ipairs(self.cells) do
      local on = button.value == current
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
  local down = self:NewButton(group, "<", height, height, function() nudge(-1) end)
  down:SetPoint("LEFT", 0, 0)
  down.quiet = true
  local up = self:NewButton(group, ">", height, height, function() nudge(1) end)
  up:SetPoint("RIGHT", 0, 0)
  up.quiet = true
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

AK.Menu = {}
local Menu = AK.Menu

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
  local title = UI:NewText(stage, "AZEROTH KART", 54, AK.COLORS.gold, "CENTER")
  title:SetPoint("TOP", 0, -56)
  title:SetShadowColor(0, 0, 0, 1)
  title:SetShadowOffset(4, -4)
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

function Menu:BuildHome()
  local home = CreateFrame("Frame", nil, self.content)
  home:SetAllPoints()
  self.home = home
  local welcome = UI:NewText(home, "Warm up your engines. No actual mounts were harmed.", 17, { .82, .88, .96 }, "CENTER")
  welcome:SetPoint("TOP", 0, -35)

  -- Listed first so the panel can be sized from the list. Ten buttons at 43px
  -- needed 467px and the panel was hard-coded to 410, so PRACTICE and SETTINGS
  -- rendered outside it as two stray bars below the frame.
  local actions = {
    { "QUICK RACE", "Race your selected track against the field.", function() AK.Race:Start("quick") end },
    { "SELECT RACER", "Choose a pilot with a distinct handling profile.", function() self:ShowSelection("racer") end },
    { "SELECT KART", "Pick an impossibly unsafe vehicle.", function() self:ShowSelection("kart") end },
    { "SELECT TRACK", "Choose a course from across Azeroth.", function() self:ShowSelection("track") end },
    { "SELECT CUP", "Choose which four-race Grand Prix you'll run.", function() self:ShowSelection("cup") end },
    { "GRAND PRIX", "Four races. One moderately shiny trophy.", function() AK.Race:StartGrandPrix() end },
    { "MULTIPLAYER", "Host or join a party/raid race with other addon users.", function() self:ShowMultiplayer() end },
    { "TIME TRIAL", "No rivals, no items, race your own ghost.", function() AK.Race:Start("time_trial") end },
    { "BATTLE", "Three balloons each. Last one standing wins.", function() AK.Race:StartBattle() end },
    { "PRACTICE", "Learn the course without a finish pressure.", function() AK.Race:Start("practice") end },
    { "TROPHY ROOM", "Every achievement, and which ones you have.", function() self:ShowAchievements() end },
    { "SETTINGS", "Adjust this tiny game's options.", function() self:ShowSettings() end },
  }
  local ROW, GAP, TOP = 36, 7, 22
  local panelHeight = TOP * 2 + #actions * ROW + (#actions - 1) * GAP

  local menu = UI:NewPanel(home, 400, panelHeight, { 0.055, 0.10, 0.17, .98 })
  menu:SetPoint("TOPLEFT", 40, -80)
  for index, spec in ipairs(actions) do
    local button = UI:NewButton(menu, spec[1], 350, ROW, spec[3])
    button.tooltip = spec[2]
    button:SetPoint("TOP", 0, -TOP - (index - 1) * (ROW + GAP))
  end

  local preview = UI:NewPanel(home, 410, panelHeight, { 0.055, 0.10, 0.17, .98 })
  preview:SetPoint("TOPRIGHT", -40, -80)
  self.preview = preview
  self.previewIcon = preview:CreateTexture(nil, "ARTWORK")
  self.previewIcon:SetSize(86, 86)
  self.previewIcon:SetPoint("TOP", 0, -22)
  -- Seated Baine, three-quarter view, in the slot the flat icon used to hold.
  self.previewModel = AK.Model:New(preview, 150, 150, -0.5, 1)
  self.previewModel:SetPoint("TOP", 0, -6)
  self.previewTitle = UI:NewText(preview, "", 21, AK.COLORS.gold, "CENTER")
  self.previewTitle:SetPoint("TOP", 0, -160)
  self.previewSub = UI:NewText(preview, "", 14, AK.COLORS.muted, "CENTER")
  self.previewSub:SetPoint("TOP", self.previewTitle, "BOTTOM", 0, -5)
  self.previewRecord = UI:NewText(preview, "", 12, AK.COLORS.gold, "CENTER")
  self.previewRecord:SetPoint("TOP", self.previewSub, "BOTTOM", 0, -6)
  self.previewStats = UI:NewText(preview, "", 14, { .86, .92, 1 }, "LEFT")
  self.previewStats:SetPoint("TOPLEFT", 32, -232)
  self.previewStats:SetPoint("TOPRIGHT", -32, -232)
  self.previewStats:SetJustifyV("TOP")
end

function Menu:ShowMultiplayer()
  self:HideDynamic()
  local page = self:AddDynamic(CreateFrame("Frame", nil, self.content))
  page:SetAllPoints()
  local header = UI:NewText(page, "PARTY & RAID RACING", 25, AK.COLORS.gold, "CENTER")
  header:SetPoint("TOP", 0, -35)
  local panel = UI:NewPanel(page, 680, 340, { .055, .10, .17, .98 })
  panel:SetPoint("CENTER", 0, 8)
  local back = UI:NewButton(page, "BACK", 120, 32, function() self:ShowHome() end)
  back:SetPoint("TOPLEFT", 25, -25)
  local description = UI:NewText(panel, "Race with people in your current party or raid who also have Azeroth Kart installed.\nThe host runs the race simulation and shares synchronized kart states through WoW's built-in addon channel.", 15, { .86, .92, 1 }, "CENTER")
  description:SetPoint("TOPLEFT", 35, -36)
  description:SetPoint("TOPRIGHT", -35, -36)
  local host = UI:NewButton(panel, "OPEN PARTY LOBBY", 280, 42, function()
    if AK.Net:OpenLobby() then self:ShowMultiplayer() end
  end)
  host:SetPoint("TOP", -150, -125)
  local start = UI:NewButton(panel, "START HOST RACE", 280, 42, function() AK.Net:StartLobbyRace() end)
  start:SetPoint("TOP", -150, -178)
  local join = UI:NewButton(panel, "JOIN ANNOUNCED LOBBY", 280, 42, function() AK.Net:JoinLobby() end)
  join:SetPoint("TOP", 150, -125)
  local refresh = UI:NewButton(panel, "REFRESH LOBBIES", 280, 42, function()
    AK.Net:RefreshLobbies()
    C_Timer.After(.35, function()
      if self.frame and self.frame:IsShown() then self:ShowMultiplayer() end
    end)
  end)
  refresh:SetPoint("TOP", 150, -178)
  local lobbyText = UI:NewText(panel, "", 14, AK.COLORS.muted, "CENTER")
  lobbyText:SetPoint("TOPLEFT", 340, -183)
  lobbyText:SetPoint("TOPRIGHT", -25, -183)
  local own = AK.Net.lobby
  local found = AK.Net.availableLobby
  if own then
    local count = 0
    for _ in pairs(own.roster) do count = count + 1 end
    lobbyText:SetText(("Hosting |cff%s%s|r\n%d racer%s ready\nTrack: %s"):format(AK:ColorHex(AK.COLORS.lime), own.id, count, count == 1 and "" or "s", AK:GetTrack(own.track).name))
  elseif found then
    local count = 0
    for _ in pairs(found.roster or {}) do count = count + 1 end
    lobbyText:SetText(("Lobby found\nHost: %s\nTrack: %s\n%d racer%s announced"):format(found.host, AK:GetTrack(found.track).name, count, count == 1 and "" or "s"))
  else
    lobbyText:SetText("No lobby announced yet.\nHave a friend open one, then revisit this screen.")
  end
  local note = UI:NewText(panel, "Multiplayer fills empty grid spots with AI racers. Results and unlocks are saved locally for every participant.", 13, AK.COLORS.muted, "CENTER")
  note:SetPoint("BOTTOMLEFT", 35, 25)
  note:SetPoint("BOTTOMRIGHT", -35, 25)
  page:Show()
end

function Menu:UpdateSummary()
  local racer = AK:GetRacer(AK.db.selection.racer)
  local kart = AK:GetKart(AK.db.selection.kart)
  local track = AK:GetTrack(AK.db.selection.track)
  self.previewIcon:SetTexture(racer.icon)
  AK.Model:SetSpec(self.previewModel, racer.model)
  AK.Model:Reframe(self.previewModel)
  self.previewModel:Show()
  self.previewIcon:Hide()
  C_Timer.After(1, function()
    if AK.Model:IsReady(self.previewModel) then return end
    self.previewModel:Hide()
    self.previewIcon:Show()
  end)
  self.previewTitle:SetText(racer.name .. " in the " .. kart.name)
  self.previewSub:SetText(track.name .. "  /  " .. track.subtitle)
  -- Your record on the circuit you are about to race, on the screen you press
  -- QUICK RACE from. It was two menus away.
  self.previewRecord:SetText(trackRecord(track.id))
  self.previewStats:SetText(("|cff%sSPEED|r  %d    |cff%sACCEL|r  %d\n|cff%sHANDLING|r  %d    |cff%sDRIFT|r  %d\n\n|cff%s%s|r\n%s\n\nCoins: |cff%s%d|r    Wins: |cff%s%d|r")
    :format(AK:ColorHex(AK.COLORS.lime), math.floor((racer.speed + kart.speed) / 2), AK:ColorHex(AK.COLORS.lime), math.floor((racer.acceleration + kart.acceleration) / 2), AK:ColorHex(AK.COLORS.lime), math.floor((racer.handling + kart.handling) / 2), AK:ColorHex(AK.COLORS.lime), math.floor((racer.drift + kart.drift) / 2), AK:ColorHex(AK.COLORS.gold), track.theme, track.shortcut, AK:ColorHex(AK.COLORS.gold), AK.db.progress.coins, AK:ColorHex(AK.COLORS.gold), AK.db.progress.wins))
end

function Menu:ShowHome()
  self:HideDynamic()
  self.home:Show()
  self:UpdateSummary()
end

function Menu:AddDynamic(frame)
  table.insert(self.dynamic, frame)
  return frame
end

function Menu:ShowSelection(kind)
  self:HideDynamic()
  local page = self:AddDynamic(CreateFrame("Frame", nil, self.content))
  page:SetAllPoints()
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
  local MARGIN, TOP, GAP, BOTTOM, MIN_CARD = 42, 82, 18, 22, 150
  local availableW, availableH = 960 - MARGIN * 2, 520 - TOP - BOTTOM
  local columns = kind == "racer" and 4 or 3
  local function rowsFor(n) return math.ceil(#entries / n) end
  local function heightFor(n)
    local rows = rowsFor(n)
    return math.floor((availableH - GAP * (rows - 1)) / rows)
  end
  while columns < 5 and heightFor(columns) < MIN_CARD do columns = columns + 1 end
  local cardWidth = math.floor((availableW - GAP * (columns - 1)) / columns)
  local cardHeight = heightFor(columns)

  for index, entry in ipairs(entries) do
    local card = UI:NewButton(page, "", cardWidth, cardHeight, function()
      AK.db.selection[kind] = entry.id
      self:ShowHome()
    end)
    if AK.db.selection[kind] == entry.id then card:SetRestStyle({ .13, .22, .25, 1 }, AK.COLORS.gold) end
    local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
    card:SetPoint("TOPLEFT", MARGIN + col * (cardWidth + GAP), -TOP - row * (cardHeight + GAP))
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(50, 50)
    icon:SetPoint("TOP", 0, -15)
    icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_Map_01")
    if kind == "racer" then
      local model = AK.Model:New(card, 78, 78, -0.6, 1, entry.model)
      model:SetPoint("TOP", 0, -2)
      icon:Hide()
      -- Model streaming is async; fall back to the flat icon if it never lands.
      C_Timer.After(1, function()
        if AK.Model:IsReady(model) then return end
        model:Hide()
        icon:Show()
      end)
    end
    local name = UI:NewText(card, entry.name, 16, AK.COLORS.gold, "CENTER")
    name:SetPoint("TOPLEFT", 7, -72)
    name:SetPoint("TOPRIGHT", -7, -72)
    if AK.db.selection[kind] == entry.id then
      local selected = UI:NewText(card, "SELECTED", 10, AK.COLORS.lime, "CENTER")
      selected:SetPoint("BOTTOM", 0, 8)
    end
    local detail = UI:NewText(card, "", 12, AK.COLORS.muted, "CENTER")
    detail:SetPoint("TOPLEFT", 9, -99)
    detail:SetPoint("TOPRIGHT", -9, -99)
    if kind == "racer" then
      detail:SetText(("%s\nSPD %d  ACC %d  HND %d\nDRIFT %d  LUCK %d\n\n|cff%s%s|r"):format(
        entry.race, entry.speed, entry.acceleration, entry.handling, entry.drift, entry.luck,
        AK:ColorHex(AK.COLORS.muted), entry.quip or ""))
    elseif kind == "kart" then
      detail:SetText(("%s\nSPD %d  ACC %d  HND %d\nWEIGHT %d  DRIFT %d"):format(entry.description, entry.speed, entry.acceleration, entry.handling, entry.weight, entry.drift))
    elseif kind == "cup" then
      local names = {}
      for _, trackId in ipairs(entry.tracks) do table.insert(names, AK:GetTrack(trackId).name) end
      detail:SetText(("%d races\n%s"):format(#entry.tracks, table.concat(names, "\n")))
    else
      -- Lap count came off a hard-coded "3 laps" that would have lied the
      -- moment a circuit was authored with a different one.
      detail:SetText(("%s\n%s\n%d laps / %dm\n\n|cff%s%s|r"):format(
        entry.subtitle, entry.shortcut, entry.laps or 3, entry.length,
        AK:ColorHex(AK.COLORS.gold), trackRecord(entry.id)))
    end
  end
  page:Show()
end

--- The trophy room.
---
--- Achievements were write-only: unlocking one printed a single chat line that
--- scrolled away, and nothing anywhere ever listed them again. The player could
--- not see what existed, what they had, or what was left -- so the whole system
--- may as well not have been there. This is that list.
function Menu:ShowAchievements()
  self:HideDynamic()
  local page = self:AddDynamic(CreateFrame("Frame", nil, self.content))
  page:SetAllPoints()
  local header = UI:NewText(page, "TROPHY ROOM", 25, AK.COLORS.gold, "CENTER")
  header:SetPoint("TOP", 0, -28)
  local back = UI:NewButton(page, "BACK", 120, 32, function() self:ShowHome() end)
  back:SetPoint("TOPLEFT", 25, -25)

  local progress = AK.db.progress
  local earned = progress.achievements or {}
  local order = AK.AchievementOrder or {}
  local have = 0
  for _, id in ipairs(order) do if earned[id] then have = have + 1 end end

  local summary = UI:NewText(page,
    ("%d of %d earned"):format(have, #order), 14, AK.COLORS.lime, "CENTER")
  summary:SetPoint("TOP", header, "BOTTOM", 0, -4)

  -- Two columns, sized from the entry count rather than hard-coded, so adding
  -- an achievement re-flows instead of spilling off the panel.
  local COLUMNS, MARGIN, TOP, GAP = 2, 40, 92, 6
  local cardWidth = math.floor((960 - MARGIN * 2 - GAP * (COLUMNS - 1)) / COLUMNS)
  local rows = math.ceil(#order / COLUMNS)
  local cardHeight = math.min(52, math.floor((520 - TOP - 56 - GAP * (rows - 1)) / math.max(1, rows)))

  for index, id in ipairs(order) do
    local achievement = AK.Achievements[id]
    if achievement then
      local got = earned[id] and true or false
      local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
      local card = UI:NewPanel(page, cardWidth, cardHeight,
        got and { .10, .18, .12, .96 } or { .07, .09, .14, .94 })
      card:SetPoint("TOPLEFT", MARGIN + column * (cardWidth + GAP), -TOP - row * (cardHeight + GAP))

      -- A filled versus hollow marker, so earned reads at a glance without
      -- relying on colour alone.
      local mark = UI:NewText(card, got and "*" or "-", 16,
        got and AK.COLORS.gold or { .34, .38, .46 }, "LEFT")
      mark:SetPoint("LEFT", 12, 0)

      local name = UI:NewText(card, achievement.name, 14,
        got and AK.COLORS.gold or { .62, .66, .74 }, "LEFT")
      name:SetPoint("TOPLEFT", 30, -7)
      local description = UI:NewText(card, achievement.description, 11,
        got and { .78, .86, .78 } or { .44, .48, .56 }, "LEFT")
      description:SetPoint("TOPLEFT", 30, -25)
      description:SetWidth(cardWidth - 42)
      description:SetJustifyH("LEFT")
    end
  end

  local trophies = 0
  for _ in pairs(progress.trophies or {}) do trophies = trophies + 1 end
  local stats = UI:NewText(page,
    ("RACES %d      WINS %d      PODIUMS %d      CUPS %d      TOKENS %d")
      :format(progress.races or 0, progress.wins or 0, progress.podiums or 0,
        trophies, progress.coins or 0),
    13, AK.COLORS.muted, "CENTER")
  stats:SetPoint("BOTTOM", 0, 18)
  page:Show()
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
  roadDetail = "Balanced",
}
--- The two rows on this screen that write to the render tuning instead.
local TUNING_DEFAULTS = { camBack = 6.0, hudScale = 100 }

-- Sized so the tallest column -- five race rows plus two sound rows, each with
-- its explanation under it -- clears the keyboard legend along the bottom.
-- Every previous version of this screen was laid out by hand-counted pixels
-- and something always ended up printed underneath something else.
local ROW_H, GROUP_GAP, COLUMN_W = 44, 18, 434

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
    local blurb = UI:NewText(parent, row.blurb, 10, { .50, .56, .66 }, "LEFT")
    blurb:SetPoint("TOPLEFT", x + 2, top - 24)
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
  if AK.PlaySfx then AK:PlaySfx("uiClick") end
end

function Menu:ShowSettings()
  self:HideDynamic()
  local page = self:AddDynamic(CreateFrame("Frame", nil, self.content))
  page:SetAllPoints()
  local header = UI:NewText(page, "SETTINGS", 25, AK.COLORS.gold, "CENTER")
  header:SetPoint("TOP", 0, -22)
  local back = UI:NewButton(page, "BACK", 120, 32, function() self:ShowHome() end)
  back:SetPoint("TOPLEFT", 25, -20)

  local controls = {}
  -- Two columns. Nine settings in one column is a scroll bar waiting to happen;
  -- two columns of grouped rows fits the panel exactly and reads as a page.
  local leftX, rightX, top = 34, 34 + COLUMN_W + 30, -52
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
  local advanced = UI:NewText(page,
    "Camera, road and handling dials live in the workshop:  /kart tune",
    11, { .44, .50, .60 }, "CENTER")
  advanced:SetPoint("BOTTOM", 0, 14)
  -- The layout is derived, not hand-placed, but a group can still be added
  -- that does not fit. Say so in the log rather than printing it over the
  -- keyboard legend and hoping somebody notices.
  local deepest = math.max(top - nextY[1], top - nextY[2])
  if -math.min(nextY[1], nextY[2]) > 520 - 80 then
    AK:Print("Settings page overflows its panel by "
      .. math.ceil(-math.min(nextY[1], nextY[2]) - (520 - 80)) .. "px.")
  end
  local _ = deepest
  page:Show()
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
