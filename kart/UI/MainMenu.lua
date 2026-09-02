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

function UI:StatLine(parent, y, label, value)
  local left = self:NewText(parent, label, 13, AK.COLORS.muted)
  left:SetPoint("TOPLEFT", 18, y)
  local right = self:NewText(parent, tostring(value), 13, AK.COLORS.gold, "RIGHT")
  right:SetPoint("TOPRIGHT", -18, y)
  return right
end

AK.Menu = {}
local Menu = AK.Menu

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

  local close = UI:NewButton(frame, "EXIT  (ESC)", 130, 32, function() self:Hide() end)
  close:SetPoint("TOPRIGHT", -30, -28)
  close:SetRestStyle({ .28, .09, .09, .95 }, AK.COLORS.danger)

  local glow = frame:CreateTexture(nil, "BACKGROUND")
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
  local titleGlow = frame:CreateTexture(nil, "ARTWORK")
  titleGlow:SetTexture(ART .. "glow.tga")
  titleGlow:SetBlendMode("ADD")
  titleGlow:SetVertexColor(1, 0.72, 0.20, 1)
  titleGlow:SetPoint("TOP", 0, 20)
  titleGlow:SetSize(900, 300)
  titleGlow:SetAlpha(0.22)
  local title = UI:NewText(frame, "AZEROTH KART", 54, AK.COLORS.gold, "CENTER")
  title:SetPoint("TOP", 0, -56)
  title:SetShadowColor(0, 0, 0, 1)
  title:SetShadowOffset(4, -4)
  local titleRule = frame:CreateTexture(nil, "ARTWORK")
  titleRule:SetTexture(ART .. "hairline.tga")
  titleRule:SetPoint("TOP", title, "BOTTOM", 0, -2)
  titleRule:SetSize(560, 3)
  titleRule:SetVertexColor(1, 0.76, 0.20, 0.8)
  local tag = UI:NewText(frame, "THE MOST QUESTIONABLY SANCTIONED RACE IN AZEROTH", 14, AK.COLORS.muted, "CENTER")
  tag:SetPoint("TOP", titleRule, "BOTTOM", 0, -8)

  local content = UI:NewPanel(frame, 960, 520, { 0.045, 0.075, 0.125, 0.95 })
  content:SetPoint("CENTER", 0, -45)
  self.content = content
  self.dynamic = {}
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
    { "GRAND PRIX", "Four races. One moderately shiny trophy.", function() AK.Race:StartGrandPrix() end },
    { "MULTIPLAYER", "Host or join a party/raid race with other addon users.", function() self:ShowMultiplayer() end },
    { "TIME TRIAL", "No rivals, no items, race your own ghost.", function() AK.Race:Start("time_trial") end },
    { "BATTLE", "Three balloons each. Last one standing wins.", function() AK.Race:StartBattle() end },
    { "PRACTICE", "Learn the course without a finish pressure.", function() AK.Race:Start("practice") end },
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
  self.previewStats = UI:NewText(preview, "", 14, { .86, .92, 1 }, "LEFT")
  self.previewStats:SetPoint("TOPLEFT", 32, -215)
  self.previewStats:SetPoint("TOPRIGHT", -32, -215)
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
  local names = { racer = "CHOOSE YOUR RACER", kart = "CHOOSE YOUR KART", track = "CHOOSE YOUR TRACK" }
  local header = UI:NewText(page, names[kind], 25, AK.COLORS.gold, "CENTER")
  header:SetPoint("TOP", 0, -28)
  local back = UI:NewButton(page, "BACK", 120, 32, function() self:ShowHome() end)
  back:SetPoint("TOPLEFT", 25, -25)

  local entries = kind == "racer" and AK.Racers or (kind == "kart" and AK.Karts or AK.Tracks)

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
    else
      detail:SetText(("%s\n%s\n3 laps / %dm"):format(entry.subtitle, entry.shortcut, entry.length))
    end
  end
  page:Show()
end

function Menu:ShowSettings()
  self:HideDynamic()
  local page = self:AddDynamic(CreateFrame("Frame", nil, self.content))
  page:SetAllPoints()
  local header = UI:NewText(page, "GARAGE SETTINGS", 25, AK.COLORS.gold, "CENTER")
  header:SetPoint("TOP", 0, -35)
  -- Tall enough for the rows AND the help text. Nine rows at 47px end 431px
  -- down, and the two-line footer sat at 435 -- so "Racing scale" was rendered
  -- underneath the keyboard legend, with both unreadable.
  local panel = UI:NewPanel(page, 560, 524, { .055, .10, .17, .98 })
  panel:SetPoint("CENTER", 0, 15)
  local back = UI:NewButton(page, "BACK", 120, 32, function() self:ShowHome() end)
  back:SetPoint("TOPLEFT", 25, -25)
  local settings = AK.db.settings
  local rows = {
    { "Sound effects", "sfx", function(value) return value and "ON" or "OFF" end },
    { "Reduced effects", "reducedEffects", function(value) return value and "ON" or "OFF" end },
    { "Show speed", "showSpeed", function(value) return value and "ON" or "OFF" end },
    { "Show mini-map", "showMinimap", function(value) return value and "ON" or "OFF" end },
    { "Engine class", "engineClass", function(value) return value end },
    { "Mirror mode", "mirror", function(value) return value and "ON" or "OFF" end },
    { "AI difficulty", "difficulty", function(value) return value end },
    { "AI racers", "aiCount", function(value) return tostring(value) end },
    { "Racing scale", "uiScale", function(value) return string.format("%d%%", value * 100) end },
  }
  for i, row in ipairs(rows) do
    local label = UI:NewText(panel, row[1], 16, { .86, .92, 1 })
    label:SetPoint("TOPLEFT", 45, -30 - (i - 1) * 47)
    local button = UI:NewButton(panel, row[3](settings[row[2]]), 145, 34, function(button)
      if row[2] == "engineClass" then
        settings.engineClass = settings.engineClass == "50cc" and "100cc"
          or (settings.engineClass == "100cc" and "150cc" or "50cc")
      elseif row[2] == "difficulty" then
        settings.difficulty = settings.difficulty == "Easy" and "Normal" or (settings.difficulty == "Normal" and "Hard" or "Easy")
      elseif row[2] == "aiCount" then
        settings.aiCount = settings.aiCount >= 7 and 3 or settings.aiCount + 2
      elseif row[2] == "uiScale" then
        settings.uiScale = settings.uiScale >= 1.2 and .8 or settings.uiScale + .1
      else
        settings[row[2]] = not settings[row[2]]
      end
      button.label:SetText(row[3](settings[row[2]]))
    end)
    button:SetPoint("TOPRIGHT", -45, -21 - (i - 1) * 47)
  end
  -- A hairline above the footer, so it reads as a separate zone rather than as
  -- a tenth settings row that lost its button.
  local rule = panel:CreateTexture(nil, "ARTWORK")
  rule:SetTexture("Interface\\Buttons\\WHITE8x8")
  rule:SetVertexColor(0.38, 0.65, 0.92, 0.30)
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", 45, 62)
  rule:SetPoint("BOTTOMRIGHT", -45, 62)
  local help = UI:NewText(panel, "Keyboard: W/Up accelerate / A-D or Left-Right steer / Space drift / Shift use item\nOn-screen controls are always available.", 13, AK.COLORS.muted, "CENTER")
  help:SetPoint("BOTTOM", 0, 20)
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
