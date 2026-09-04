local _, AK = ...

AK.Results = {}
local Results = AK.Results
local UI = AK.UI
local ART = AK.ART

local ORDINALS = { "1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH" }

--- A racer, found by the name the Grand Prix table stores.
local function racerByName(name)
  for _, racer in ipairs(AK.Racers or {}) do
    if racer.name == name then return racer end
  end
end
local ROW_HEIGHT, ROW_GAP = 38, 4

-- The size this screen is authored at, and the size it therefore needs.
--
-- The layout is a 300px podium beside a 760px table, anchored 120px from the
-- left edge: 1222px of content before any right margin at all. UIParent is
-- 1365x768 on a default 16:9 client, so that JUST fit -- and on 4:3 or 5:4,
-- where UIParent is 1024 wide, the standings table ran clean off the screen.
-- Vertically it was as tight, with the buttons pinned to the bottom edge and
-- the stat strip growing down to meet them.
--
-- Same fix as the race HUD: author it once, scale the whole thing to fit, and
-- centre the block rather than hanging it off the left edge.
local DESIGN_W, DESIGN_H = 1340, 830
local BLOCK = 300 + 22 + 760          -- podium + gap + table

--- Fit the whole screen to the client. One SetScale on one container.
function Results:Layout()
  if not self.content or not self.frame then return end
  local width, height = self.frame:GetWidth(), self.frame:GetHeight()
  if not width or width <= 0 or not height or height <= 0 then return end
  self.content:SetScale(AK.Math.Clamp(math.min(width / DESIGN_W, height / DESIGN_H), 0.50, 1.40))
end

function Results:Build()
  if self.frame then return end
  local frame = CreateFrame("Frame", "AzerothKartResults", UIParent)
  frame:SetAllPoints(UIParent)
  -- Above everything the race puts up. The race frame's children climb to +500
  -- for depth sorting, so results has to clear that bar or the finish line and
  -- the karts paint straight over this screen.
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(900)
  frame:EnableMouse(true)
  frame:Hide()
  self.frame = frame

  -- Opaque ground. Anything left showing through reads as a bug.
  local backdrop = frame:CreateTexture(nil, "BACKGROUND")
  backdrop:SetTexture("Interface\\Buttons\\WHITE8x8")
  backdrop:SetVertexColor(0.020, 0.028, 0.052, 1)
  backdrop:SetAllPoints()
  local wash = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  wash:SetTexture(ART .. "glow.tga")
  wash:SetBlendMode("ADD")
  wash:SetVertexColor(0.30, 0.22, 0.55, 1)
  wash:SetPoint("CENTER", 0, 120)
  wash:SetSize(1500, 900)
  wash:SetAlpha(0.30)
  local vignette = frame:CreateTexture(nil, "OVERLAY", nil, 5)
  vignette:SetTexture(ART .. "vignette.tga")
  vignette:SetAllPoints()

  -- Everything except the opaque ground lives on one scaled container, so the
  -- screen is the same shape on a 1024-wide client and a 4K one.
  local content = CreateFrame("Frame", nil, frame)
  content:SetAllPoints()
  self.content = content
  frame:SetScript("OnSizeChanged", function() Results:Layout() end)

  -- Header.
  self.title = UI:NewText(content, "RACE RESULTS", 42, AK.COLORS.gold, "CENTER")
  self.title:SetPoint("TOP", 0, -46)
  self.title:SetShadowColor(0, 0, 0, 1)
  self.title:SetShadowOffset(3, -3)
  local rule = content:CreateTexture(nil, "ARTWORK")
  rule:SetTexture(ART .. "hairline.tga")
  rule:SetPoint("TOP", self.title, "BOTTOM", 0, -6)
  rule:SetSize(520, 3)
  rule:SetVertexColor(1, 0.76, 0.20, 0.75)
  self.subtitle = UI:NewText(content, "", 16, AK.COLORS.muted, "CENTER")
  self.subtitle:SetPoint("TOP", rule, "BOTTOM", 0, -8)

  -- Winner podium, left of the table.
  self.podium = UI:NewPanel(content, 300, 400, { .05, .08, .14, .96 })
  -- Centred as a block. Anchored 120px from the LEFT edge, the podium and table
  -- together needed more width than a 4:3 client has, and on a wide one the
  -- whole screen sat left with a hole beside it.
  self.podium:SetPoint("TOPLEFT", content, "TOP", -BLOCK * 0.5, -170)
  self.winner = AK.Model:New(self.podium, 260, 260, -0.45, 1)
  self.winner:SetPoint("TOP", 0, -14)
  self.winnerName = UI:NewText(self.podium, "", 18, AK.COLORS.gold, "CENTER")
  self.winnerName:SetPoint("BOTTOM", 0, 62)
  self.winnerName:SetShadowColor(0, 0, 0, 1)
  self.winnerName:SetShadowOffset(1, -1)
  -- The kart, where the word "WINNER" used to be. A caption reading "winner"
  -- under the winner's model on the podium panel is a label on a thing that is
  -- already unambiguous; which kart took it is not written anywhere else on
  -- this screen at that size.
  --
  -- Anchored to the name's top rather than to a second measurement from the
  -- bottom edge, so the two can never be laid out into each other.
  self.winnerTag = UI:NewText(self.podium, "", 12, AK.COLORS.muted, "CENTER")
  self.winnerTag:SetPoint("BOTTOM", self.winnerName, "TOP", 0, 4)

  -- Standings table.
  self.table = UI:NewPanel(content, 760, 400, { .05, .08, .14, .96 })
  self.table:SetPoint("TOPLEFT", self.podium, "TOPRIGHT", 22, 0)
  -- Column headers. Without them the right-hand pair of numbers is two
  -- unlabelled columns and the reader has to work out which is which -- and
  -- now that everyone but the winner is shown as a GAP, "+1.42s" against
  -- "best 33.70s" is genuinely ambiguous until it is named.
  local head = UI:NewText(self.table, "POS", 10, { .45, .52, .62 }, "LEFT")
  head:SetPoint("TOPLEFT", 32, -4)
  local headWho = UI:NewText(self.table, "RACER", 10, { .45, .52, .62 }, "LEFT")
  headWho:SetPoint("TOPLEFT", 94, -4)
  -- The time and the best lap are stacked in one right-hand column, and the
  -- best lap already says "best" on it, so one header does for both.
  local headTime = UI:NewText(self.table, "TIME / GAP TO WINNER", 10, { .45, .52, .62 }, "RIGHT")
  headTime:SetPoint("TOPRIGHT", -34, -4)
  self.rows = {}
  for i = 1, AK.MAX_RACERS do
    local row = CreateFrame("Frame", nil, self.table)
    row:SetSize(724, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 18, -20 - (i - 1) * (ROW_HEIGHT + ROW_GAP))
    -- The same shaped plate the buttons wear. A standings row used to be a
    -- stretched gradient with a square 4px bar down its left edge, which is
    -- what a list widget looks like; these are the eight lines the whole race
    -- was for and they should look like part of the same object family.
    row.plate = UI:NewPlate(row, "BACKGROUND", 0)
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetTexture(ART .. "chevron.tga")
    row.accent:SetSize(9, 13)
    row.accent:SetPoint("LEFT", 8, 0)
    row.place = UI:NewText(row, "", 17, AK.COLORS.gold, "LEFT")
    row.place:SetPoint("LEFT", 24, 0)
    row.name = UI:NewText(row, "", 15, { .92, .95, 1 }, "LEFT")
    row.name:SetPoint("LEFT", 76, 0)
    row.kart = UI:NewText(row, "", 12, AK.COLORS.muted, "LEFT")
    row.kart:SetPoint("LEFT", 76, -13)
    row.time = UI:NewText(row, "", 15, { .95, .96, 1 }, "RIGHT")
    row.time:SetPoint("RIGHT", -16, 7)
    row.best = UI:NewText(row, "", 11, AK.COLORS.muted, "RIGHT")
    row.best:SetPoint("RIGHT", -16, -8)
    row:Hide()
    self.rows[i] = row
  end

  -- Stat strip, inside the layout rather than dangling off the bottom.
  self.statPanel = UI:NewPanel(content, BLOCK, 62, { .04, .065, .11, .96 })
  -- On the block's own centre line. It used to hang off the table with a -161
  -- nudge to fake being centred under a pair of panels it was not anchored to.
  self.statPanel:SetPoint("TOP", self.podium, "BOTTOM", BLOCK * 0.5 - 150, -14)
  self.stats = UI:NewText(self.statPanel, "", 14, { .88, .93, 1 }, "CENTER")
  self.stats:SetPoint("TOP", 0, -10)
  self.splits = UI:NewText(self.statPanel, "", 12, AK.COLORS.muted, "CENTER")
  self.splits:SetPoint("BOTTOM", 0, 10)

  self.reward = UI:NewText(content, "", 15, AK.COLORS.lime, "CENTER")
  self.reward:SetPoint("TOP", self.statPanel, "BOTTOM", 0, -14)
  -- WHERE YOU STAND IN THE CUP, after every race in it.
  --
  -- A Grand Prix is four races and one table, and that table was shown exactly
  -- once: at the very end. Between races the player was told their finishing
  -- position in the race they had just run and nothing at all about the cup
  -- they were running it for -- so the structure that makes a cup a cup, the
  -- points adding up, was invisible for three quarters of it.
  self.cupLine = UI:NewText(content, "", 14, AK.COLORS.gold, "CENTER")
  self.cupLine:SetPoint("TOP", self.reward, "BOTTOM", 0, -12)
  self.cupLine:Hide()

  self.primary = UI:NewButton(content, "RACE AGAIN", 240, 44, function()
    local race = AK.Race.current
    if self.grandPrixComplete then AK.Race:Stop(true); self:Hide()
    elseif race and race.grandPrix then AK.Race:NextGrandPrix()
    elseif race and race.mode == "multiplayer" then AK.Race:Stop(true); self:Hide()
    else AK.Race:Start(race and race.mode or "quick") end
  end)
  self.primary:SetPoint("BOTTOM", -132, 40)
  self.back = UI:NewButton(content, "MAIN MENU", 240, 44, function()
    AK.Race:Stop(true); self:Hide()
  end)
  self.back:SetPoint("BOTTOM", 132, 40)
  -- This screen covers the whole display at frame level 900, so the chat
  -- window is behind it -- a slash command could never be typed OR read here.
  -- The telemetry needs a button and its own panel above this one.
  self.aiReport = UI:NewButton(content, "AI REPORT", 150, 24, function() AK.AI:Report() end)
  self.aiReport:SetPoint("BOTTOM", 0, 10)
  self.aiReport:SetRestStyle({ .10, .16, .26, .95 }, { .38, .55, .78 })
  self.aiReport.tooltip = "What the AI field actually did: drifts completed, braking, mistakes and how much catch-up assistance they were given."

  self:Layout()

  -- Rows fly in one at a time; the ticker drives that.
  self.ticker = CreateFrame("Frame", nil, frame)
  self.ticker:Hide()
  self.ticker:SetScript("OnUpdate", function(_, elapsed) self:Animate(elapsed) end)
end

--- Staggered entrance. A standings table that simply appears reads as a debug
--- dump; revealing it a line at a time reads as a results screen.
function Results:Animate(elapsed)
  self.animTime = (self.animTime or 0) + elapsed
  local revealed = math.floor(self.animTime / 0.085)
  if revealed > (self.revealed or 0) then
    for index = (self.revealed or 0) + 1, math.min(revealed, self.rowCount or 0) do
      local row = self.rows[index]
      if row then
        row:Show()
        row:SetAlpha(0)
        row.slide = 1
        if AK.PlaySfx then AK:PlaySfx(index == 1 and "overtake" or "item") end
      end
    end
    self.revealed = revealed
  end
  local done = true
  for index = 1, (self.rowCount or 0) do
    local row = self.rows[index]
    if row and row.slide and row.slide > 0 then
      row.slide = math.max(0, row.slide - elapsed * 5.5)
      local t = 1 - row.slide
      row:SetAlpha(t)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 18 + row.slide * 90, -20 - (index - 1) * (ROW_HEIGHT + ROW_GAP))
      if row.slide > 0 then done = false end
    end
  end
  if done and revealed >= (self.rowCount or 0) then self.ticker:Hide() end
end

local function styleRow(row, place, isPlayer)
  -- The chevron only marks YOUR row and the winner's. Marking all eight makes
  -- it decoration; marking two makes it information.
  if isPlayer then
    row.plate:Tint({ 0.14, 0.40, 0.26 })
    row.accent:SetVertexColor(unpack(AK.COLORS.lime))
    row.accent:Show()
  elseif place == 1 then
    row.plate:Tint({ 0.46, 0.34, 0.09 })
    row.accent:SetVertexColor(unpack(AK.COLORS.gold))
    row.accent:Show()
  elseif place <= 3 then
    row.plate:Tint({ 0.15, 0.21, 0.33 })
    row.accent:Hide()
  else
    row.plate:Tint({ 0.10, 0.13, 0.20 })
    row.accent:Hide()
  end
end

--- Who is on top of the cup, and where you are in it.
---
--- Points are keyed by NAME (a multiplayer owner, or the racer's own name), so
--- the player's line is found the same way.
local function cupStandingLine(gp, player)
  if not gp or not gp.points then return "" end
  local standings = {}
  for key, points in pairs(gp.points) do
    standings[#standings + 1] =
      { key = key, name = (gp.names and gp.names[key]) or key, points = points }
  end
  -- Sorted by points, then by name so the order cannot wobble between two
  -- racers on the same score -- pairs() deals in a different order every time.
  table.sort(standings, function(a, b)
    if a.points ~= b.points then return a.points > b.points end
    return a.name < b.name
  end)
  local mine = player and (player.owner or (player.racer and player.racer.name))
  local yourPlace, yourPoints
  for index, entry in ipairs(standings) do
    if entry.key == mine then yourPlace, yourPoints = index, entry.points end
  end
  local leader = standings[1]
  local line = ("%s  --  RACE %d OF %d"):format(
    gp.cup.name:upper(), gp.index, #gp.cup.tracks)
  if yourPlace then
    line = line .. ("  --  YOU ARE %s ON %d PTS"):format(
      ORDINALS[yourPlace] or (yourPlace .. "TH"), yourPoints)
    if yourPlace > 1 and leader then
      line = line .. ("  (%s LEADS ON %d)"):format(leader.name:upper(), leader.points)
    end
  end
  return line
end

function Results:Show(race)
  self:Build()
  self.grandPrixComplete = false
  local position = race.positions[race.player] or #race.vehicles
  -- AN ARENA IS NOT A CIRCUIT, and this screen was written as though every
  -- fixture were a race. A battle came home headed "RACE COMPLETE" over the
  -- line "150cc  999 LAPS" -- 999 being the sentinel lap count that stops a
  -- battle ever ending by distance, printed to the player as a fact about the
  -- fight they had just had.
  local battle = race.battle
  if battle then
    self.title:SetText(position == 1 and "LAST ONE STANDING" or "KNOCKED OUT")
    self.title:SetTextColor(unpack(position == 1 and AK.COLORS.gold or AK.COLORS.danger))
  else
    self.title:SetText(position == 1 and "VICTORY" or (position <= 3 and "PODIUM FINISH" or "RACE COMPLETE"))
    self.title:SetTextColor(unpack(position == 1 and AK.COLORS.gold or (position <= 3 and AK.COLORS.lime or { .86, .90, 1 })))
  end
  -- Name the conditions the race was actually run under. A results screen that
  -- does not say it was 150cc mirror with hard rivals is throwing away the
  -- context that makes the time mean anything.
  local conditions = { AK.db.settings.engineClass or "150cc",
    battle and (AK.BATTLE_BALLOONS .. " BALLOONS") or ((race.laps or 3) .. " LAPS"),
    (AK.db.settings.difficulty or "Normal"):upper() }
  if AK.db.settings.mirror then table.insert(conditions, "MIRROR") end
  self.subtitle:SetText(("%s  /  %s %s of %d  /  %s"):format(
    race.track.name, battle and "placed" or "finished",
    ORDINALS[position] or (position .. "TH"), #race.vehicles,
    table.concat(conditions, "  ")))

  local ordered = {}
  for _, vehicle in ipairs(race.vehicles) do table.insert(ordered, vehicle) end
  table.sort(ordered, function(a, b) return (race.positions[a] or 99) < (race.positions[b] or 99) end)

  local champion = ordered[1]
  -- Whoever actually crossed first, for the gap column below.
  local leader = ordered[1]
  if champion then AK.Model:SetSpec(self.winner, AK:GetRacerModel(champion)) end
  AK.Model:SetSeat(self.winner, champion and champion.racer)
  AK.Model:Reframe(self.winner)
  self.winner:SetShown(champion ~= nil and AK.Model:IsReady(self.winner))
  self.winnerName:SetText(champion and champion.racer.name or "")
  self.winnerTag:SetText(champion and champion.kart.name:upper() or "")

  self.rowCount = 0
  for index, row in ipairs(self.rows) do
    local vehicle = ordered[index]
    if vehicle then
      local place = race.positions[vehicle] or index
      row.place:SetText(ORDINALS[place] or (place .. "TH"))
      row.name:SetText(vehicle.racer.name)
      row.kart:SetText(vehicle.kart.name)
      -- The winner's total, then everybody else as a GAP to it. A column of
      -- eight near-identical three-figure times tells you nothing; "+1.42s"
      -- tells you the whole story of the race at a glance. Anyone without a
      -- time at all should now be impossible -- the cooldown lap brings the
      -- whole field home -- but the fallback stays honest if one ever is.
      local leadTime = leader and leader.finishTime
      if not vehicle.finishTime then
        row.time:SetText("--")
      elseif battle then
        -- In an arena the column is HOW LONG YOU LASTED, and the winner lasted
        -- longest -- so a gap to the leader is negative for everybody, and the
        -- gap branch below printed a whole field of "+-42.10s".
        row.time:SetText(AK.RaceUI:FormatTime(vehicle.finishTime))
      elseif not leadTime or vehicle == leader then
        row.time:SetText(AK.RaceUI:FormatTime(vehicle.finishTime))
      else
        row.time:SetText(("+%.2fs"):format(vehicle.finishTime - leadTime))
      end
      row.best:SetText(vehicle.bestLap and ("best " .. AK.RaceUI:FormatTime(vehicle.bestLap)) or "")
      styleRow(row, place, vehicle == race.player)
      row:Hide()
      row.slide = nil
      self.rowCount = index
    else
      row:Hide()
      row.slide = nil
    end
  end

  local player = race.player
  self.stats:SetText(("TOP SPEED  |cff%s%d km/h|r      DRIFTING  |cff%s%.1fs|r      HITS TAKEN  |cff%s%d|r"):format(
    AK:ColorHex(AK.COLORS.gold), math.floor((player.topSpeed or 0) * 2.2),
    AK:ColorHex(AK.COLORS.gold), player.driftTime or 0,
    AK:ColorHex(AK.COLORS.gold), player.hazardHits or 0))
  local splits = {}
  for lap, split in ipairs(player.lapTimes or {}) do
    table.insert(splits, ("L%d %s"):format(lap, AK.RaceUI:FormatTime(split)))
  end
  self.splits:SetText(table.concat(splits, "     "))
  self.reward:SetText(("+%d RACE TOKENS   /   GARAGE TOTAL: %d"):format(
    race.rewardCoins or 0, AK.db.progress.coins))

  if race.grandPrix then
    local gp = race.grandPrix
    local isFinal = gp.index >= #gp.cup.tracks
    self.primary.label:SetText(isFinal and "CLAIM TROPHY" or "NEXT RACE")
    self.cupLine:SetText(cupStandingLine(gp, race.player))
    self.cupLine:Show()
  elseif race.mode == "multiplayer" then
    self.primary.label:SetText("RETURN TO PITS")
  elseif battle then
    self.primary.label:SetText("BATTLE AGAIN")
  else
    self.primary.label:SetText("RACE AGAIN")
  end
  if not race.grandPrix then self.cupLine:Hide() end

  self.animTime, self.revealed = 0, 0
  self.ticker:Show()
  self.frame:Show()
  if AK.PlayStinger then AK:PlayStinger(position <= 3 and "victory" or "defeat", position == 1 and 3 or 1, 0.07) end
end

function Results:ShowGrandPrix(gp)
  self:Build()
  self.grandPrixComplete = true
  -- Kept so the finished cup can be inspected after the race is torn down.
  self.lastGrandPrix = gp
  self.title:SetText(gp.cup.name:upper() .. " COMPLETE")
  self.title:SetTextColor(unpack(AK.COLORS.gold))
  self.subtitle:SetText("Trophy added to your garage.")

  local standings = {}
  for key, points in pairs(gp.points) do
    table.insert(standings,
      { key = key, name = (gp.names and gp.names[key]) or key, points = points })
  end
  -- Name as the tiebreak, so two racers level on points cannot swap places
  -- every time the screen is opened: pairs() deals in a different order each
  -- run, and the cup champion is not something to leave to that.
  table.sort(standings, function(a, b)
    if a.points ~= b.points then return a.points > b.points end
    return a.name < b.name
  end)

  -- THE CHAMPION, NOT WHOEVER WON THE LAST RACE. This reframed whatever model
  -- happened to be loaded -- which is the winner of the final race -- and put
  -- the cup champion's NAME under it. They are frequently not the same person.
  local championName = standings[1] and standings[1].name
  local champion = championName and racerByName(championName)
  if champion then
    AK.Model:SetSpec(self.winner, champion.model)
    AK.Model:SetSeat(self.winner, champion)
  end
  AK.Model:Reframe(self.winner)
  self.winner:SetShown(AK.Model:IsReady(self.winner))
  self.winnerName:SetText(championName or "")
  self.winnerTag:SetText("CUP CHAMPION")

  self.rowCount = 0
  for index, row in ipairs(self.rows) do
    local entry = standings[index]
    if entry then
      row.place:SetText(ORDINALS[index] or (index .. "TH"))
      row.name:SetText(entry.name)
      row.kart:SetText("")
      row.time:SetText(entry.points .. " pts")
      row.best:SetText("")
      styleRow(row, index, false)
      row:Hide()
      row.slide = nil
      self.rowCount = index
    else
      row:Hide()
      row.slide = nil
    end
  end
  -- The four circuits it took, rather than an empty strip where the race stats
  -- were: a cup is the set of tracks, and this is the one screen that can say
  -- so without the player having to remember.
  local names = {}
  for _, trackId in ipairs(gp.cup.tracks) do
    names[#names + 1] = AK:GetTrack(trackId).name:upper()
  end
  self.stats:SetText(table.concat(names, "     "))
  self.splits:SetText(("%d RACES  --  %d POINTS AVAILABLE"):format(
    #gp.cup.tracks, #gp.cup.tracks * 8))
  self.reward:SetText("CUP TROPHY UNLOCKED")
  self.cupLine:Hide()
  self.primary.label:SetText("BACK TO GARAGE")
  self.animTime, self.revealed = 0, 0
  self.ticker:Show()
  self.frame:Show()
  if AK.PlayStinger then AK:PlayStinger("victory", 3, 0.07) end
end

function Results:Hide()
  if self.frame then self.frame:Hide() end
  if self.ticker then self.ticker:Hide() end
end
