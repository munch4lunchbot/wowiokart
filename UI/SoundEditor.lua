local _, AK = ...

-- The in-game sound editor.
--
-- Sound is the one part of this addon that cannot be developed the way
-- everything else is. The renderer has an offline harness that draws a PNG, so a
-- change can be looked at. Audio has no equivalent and never will -- the only
-- way to know whether a sound is right is to hear it, and the person who can
-- hear it is the one playing.
--
-- So the editor's job is to hand that judgement over completely. Every cue is
-- listed with what it currently resolves to; any cue can be auditioned on
-- demand; and the whole FileDataID space of the game's audio library can be
-- searched, previewed and bound without leaving the game or editing a file.
--
-- The scanner is the part that makes this practical. Guessing FileDataIDs is
-- hopeless -- most are not sounds at all -- but PlaySoundFile reports whether an
-- id exists, so a range can be probed and reduced to the handful that are real.
-- Those are then auditioned one at a time.
AK.SoundEditor = {}
local Editor = AK.SoundEditor

local ROWS = 14
local ROW_HEIGHT = 20

local PRI_COLOR = {
  incidental = { 0.58, 0.62, 0.70 },
  normal     = { 0.84, 0.90, 1.00 },
  important  = { 0.42, 0.82, 0.98 },
  critical   = { 1.00, 0.82, 0.31 },
}

function Editor:Select(cue)
  self.selected = cue
  self:Refresh()
end

--- Repaint the cue list and the detail pane from current state.
function Editor:Refresh()
  if not self.frame then return end
  local list = AK:CueList()
  self.total = #list
  local maxOffset = math.max(0, self.total - ROWS)
  if (self.offset or 0) > maxOffset then self.offset = maxOffset end

  for i = 1, ROWS do
    local row = self.rows[i]
    local entry = list[i + (self.offset or 0)]
    if entry then
      local info = AK:CueInfo(entry.cue)
      row:Show()
      row.name:SetText(entry.cue)
      row.name:SetTextColor(unpack(PRI_COLOR[info.priority] or PRI_COLOR.normal))
      -- A bound cue is the interesting case, so it is the one that gets colour.
      if info.override then
        row.state:SetText("file " .. info.override
        .. (info.plays > 0 and ("  x" .. info.plays) or ""))
        row.state:SetTextColor(unpack(AK.COLORS.gold))
      elseif info.source == "kit" then
        row.state:SetText("kit " .. tostring(info.id))
        row.state:SetTextColor(0.55, 0.60, 0.68)
      elseif info.source == "none" then
        row.state:SetText("silent")
        row.state:SetTextColor(0.85, 0.33, 0.33)
      else
        row.state:SetText("default")
        row.state:SetTextColor(0.45, 0.50, 0.58)
      end
      row.cue = entry.cue
      row.highlight:SetShown(entry.cue == self.selected)
    else
      row:Hide()
    end
  end

  local info = self.selected and AK:CueInfo(self.selected)
  if info then
    self.detailTitle:SetText(info.cue)
    -- Min gap is what the cue is ALLOWED to do; plays/min is what it actually
    -- did last race. Tuning a sound set by ear needs the second number, because
    -- "too repetitive" is a rate and a single audition cannot show a rate.
    self.detailInfo:SetText(info.plays > 0
      and ("%s  /  min gap %.2fs  /  played %d  (%.1f per min)")
        :format(info.priority, info.cooldown, info.plays, info.perMinute)
      or ("%s  /  min gap %.2fs  /  not played yet"):format(info.priority, info.cooldown))
    self.detailKit:SetText(info.override
      and ("bound to file " .. info.override)
      or ("default: " .. (info.kit ~= "" and info.kit or "none")))
  else
    self.detailTitle:SetText("select a cue")
    self.detailInfo:SetText("")
    self.detailKit:SetText("")
  end

  -- Say WHICH id is being auditioned, and name it when the kit knows the name.
  -- "showing 3" tells you nothing you can write down or bind later.
  local shownId = self.found and self.found[(self.foundIndex or 0) + 1]
  local shownName = shownId and AK:SoundName(shownId)
  self.scanLabel:SetText(shownId
    and ("%d found  -  %d of %d: |cffffd100%d|r%s"):format(#self.found,
      (self.foundIndex or 0) + 1, #self.found, shownId,
      shownName and ("  " .. shownName) or "")
    or "no scan yet")
end

function Editor:CurrentID()
  local text = self.idBox and self.idBox:GetText()
  return tonumber(text and text:match("%d+") or nil)
end

function Editor:ShowFound(index)
  if not self.found or #self.found == 0 then return end
  index = math.max(1, math.min(#self.found, index))
  self.foundIndex = index - 1
  self.idBox:SetText(tostring(self.found[index]))
  AK:TrySoundFile(self.found[index])
  self:Refresh()
end

function Editor:Build()
  if self.frame then return end
  local UI = AK.UI

  local frame = CreateFrame("Frame", "AzerothKartSoundEditor", UIParent, "BackdropTemplate")
  frame:SetSize(620, 116 + ROWS * ROW_HEIGHT)
  frame:SetPoint("CENTER", 0, -40)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(950)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(0.03, 0.05, 0.09, 0.97)
  frame:SetBackdropBorderColor(unpack(AK.COLORS.gold))
  frame:Hide()
  self.frame = frame
  self.rows = {}
  self.offset = 0

  local title = UI:NewText(frame, "SOUND EDITOR", 14, AK.COLORS.gold, "CENTER")
  title:SetPoint("TOP", 0, -9)
  local hint = UI:NewText(frame, "click a cue to select  /  PLAY auditions  /  BIND assigns the id on the right", 10, AK.COLORS.muted, "CENTER")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -2)

  -- ---- cue list ----
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(300, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 12, -40 - (i - 1) * ROW_HEIGHT)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
    highlight:SetVertexColor(0.13, 0.40, 0.68, 0.55)
    highlight:SetAllPoints()
    highlight:Hide()
    row.highlight = highlight

    row.name = UI:NewText(row, "", 11, { .84, .90, 1 }, "LEFT")
    row.name:SetPoint("LEFT", 6, 0)
    row.state = UI:NewText(row, "", 10, AK.COLORS.muted, "RIGHT")
    row.state:SetPoint("RIGHT", -6, 0)

    row:SetScript("OnClick", function(self_)
      Editor:Select(self_.cue)
      AK:PreviewCue(self_.cue)
    end)
    row:SetScript("OnEnter", function(self_) if not self_.highlight:IsShown() then highlight:SetVertexColor(0.20, 0.28, 0.40, 0.5) highlight:Show() end end)
    row:SetScript("OnLeave", function(self_)
      highlight:SetVertexColor(0.13, 0.40, 0.68, 0.55)
      highlight:SetShown(self_.cue == Editor.selected)
    end)
    self.rows[i] = row
  end

  local up = UI:NewButton(frame, "^", 22, 20, function()
    self.offset = math.max(0, (self.offset or 0) - ROWS)
    self:Refresh()
  end)
  up:SetPoint("TOPLEFT", 316, -40)
  local down = UI:NewButton(frame, "v", 22, 20, function()
    self.offset = math.min(math.max(0, (self.total or 0) - ROWS), (self.offset or 0) + ROWS)
    self:Refresh()
  end)
  down:SetPoint("TOPLEFT", 316, -40 - ROW_HEIGHT)

  -- ---- detail pane ----
  local dx = 350
  self.detailTitle = UI:NewText(frame, "select a cue", 13, AK.COLORS.gold, "LEFT")
  self.detailTitle:SetPoint("TOPLEFT", dx, -42)
  self.detailInfo = UI:NewText(frame, "", 10, AK.COLORS.muted, "LEFT")
  self.detailInfo:SetPoint("TOPLEFT", dx, -60)
  self.detailKit = UI:NewText(frame, "", 10, { .55, .62, .72 }, "LEFT")
  self.detailKit:SetPoint("TOPLEFT", dx, -74)
  self.detailKit:SetWidth(250)
  self.detailKit:SetJustifyH("LEFT")

  local play = UI:NewButton(frame, "PLAY CUE", 120, 20, function()
    if self.selected then AK:PreviewCue(self.selected) end
  end)
  play:SetPoint("TOPLEFT", dx, -98)
  local clear = UI:NewButton(frame, "UNBIND", 110, 20, function()
    if self.selected then AK:SetCueSound(self.selected, nil) self:Refresh() end
  end)
  clear:SetPoint("TOPLEFT", dx + 126, -98)
  clear.tooltip = "Drop your binding and go back to this cue's built-in sound."

  -- The button that actually answers the question the player is asking. One
  -- play tells you the timbre; eight at the cue's own minimum gap tells you
  -- whether it will drive you mad, and that is the complaint being tuned out.
  local rate = UI:NewButton(frame, "HEAR IT REPEATED", 180, 20, function()
    if self.selected then AK:AuditionRate(self.selected) end
  end)
  rate:SetPoint("TOPLEFT", dx, -122)
  rate.tooltip = "Play this cue eight times at the fastest rate it is allowed.\nA sample that is fine once can still be unbearable at its real density -- this is the worst case you will actually hear in a race."

  -- Silencing one cue was implemented and had no way in: the sentinel-0
  -- override existed, AK:MuteCue existed, and nothing anywhere called either.
  -- A toggle, because a mute you cannot undo is a trap.
  local mute = UI:NewButton(frame, "MUTE", 60, 20, function()
    if not self.selected then AK:Print("Pick a cue on the left first.") return end
    local bound = AK.db.sfxOverride and AK.db.sfxOverride[self.selected]
    AK:SetCueSound(self.selected, bound == 0 and nil or 0)
    self:Refresh()
  end)
  mute:SetPoint("TOPLEFT", dx + 186, -122)
  mute.tooltip = "Silence this cue. Press again to bring it back."

  -- ---- file id browser ----
  local browseTitle = UI:NewText(frame, "GAME AUDIO LIBRARY", 11, AK.COLORS.blue, "LEFT")
  browseTitle:SetPoint("TOPLEFT", dx, -132)

  local idBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  idBox:SetSize(96, 20)
  idBox:SetPoint("TOPLEFT", dx + 6, -150)
  idBox:SetAutoFocus(false)
  idBox:SetNumeric(true)
  idBox:SetText("566000")
  idBox:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
    local id = Editor:CurrentID()
    if id then AK:TrySoundFile(id) end
  end)
  self.idBox = idBox

  local tryButton = UI:NewButton(frame, "PLAY ID", 86, 20, function()
    local id = self:CurrentID()
    if id then AK:TrySoundFile(id) end
  end)
  tryButton:SetPoint("TOPLEFT", dx + 110, -150)

  local bind = UI:NewButton(frame, "BIND", 60, 20, function()
    local id = self:CurrentID()
    if id and self.selected then
      AK:SetCueSound(self.selected, id)
      self:Refresh()
    elseif not self.selected then
      AK:Print("Pick a cue on the left first.")
    end
  end)
  bind:SetPoint("TOPLEFT", dx + 192, -150)
  bind.tooltip = "Bind the id on the left to the cue selected in the list."

  -- Scanning turns "guess a number" into "here are the real ones".
  local scan = UI:NewButton(frame, "SCAN 200 FROM HERE", 194, 20, function()
    local start = self:CurrentID()
    if not start then return end
    self.found = AK:ScanSoundFiles(start, 200)
    self.foundIndex = 0
    AK:Print(("Scanned %d-%d: |cff6bf06b%d|r playable."):format(start, start + 199, #self.found))
    if #self.found > 0 then self:ShowFound(1) else self:Refresh() end
  end)
  scan:SetPoint("TOPLEFT", dx + 6, -176)
  scan.tooltip = "Probes 200 ids from the box above and keeps the ones that exist.\nEach hit is cut off immediately, so this is a short flurry, not 200 full sounds."

  self.scanLabel = UI:NewText(frame, "no scan yet", 10, AK.COLORS.muted, "LEFT")
  self.scanLabel:SetPoint("TOPLEFT", dx + 6, -200)

  local prev = UI:NewButton(frame, "< PREV", 84, 20, function()
    self:ShowFound((self.foundIndex or 0))
  end)
  prev:SetPoint("TOPLEFT", dx + 6, -216)
  local next_ = UI:NewButton(frame, "NEXT >", 84, 20, function()
    self:ShowFound((self.foundIndex or 0) + 2)
  end)
  next_:SetPoint("TOPLEFT", dx + 94, -216)
  prev.tooltip = "Step back through the scan results, playing each."
  next_.tooltip = "Step forward through the scan results, playing each."

  -- ---- footer ----
  local report = UI:NewButton(frame, "PRINT BINDINGS", 170, 22, function() AK:DebugSfx() end)
  report:SetPoint("BOTTOMLEFT", 12, 8)
  report.tooltip = "Prints every cue and what it resolved to, ready to paste back."
  -- The one control this window most needed and did not have. Scanning plays
  -- whatever it finds, and the library is full of minute-long ambience beds --
  -- without a stop you sit through it or reload. The workshop's sound bench has
  -- had one at the top of the pane the whole time.
  local stop = UI:NewButton(frame, "STOP SOUND", 130, 22, function() AK:StopPreview() end)
  stop:SetPoint("BOTTOM", 0, 8)
  stop:SetRestStyle({ .22, .08, .08, .95 }, AK.COLORS.danger)
  stop.tooltip = "Cut whatever is playing right now."
  local close = UI:NewButton(frame, "CLOSE", 130, 22, function() frame:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -12, 8)

  frame:HookScript("OnShow", function() self:Refresh() end)
end

function Editor:Toggle()
  self:Build()
  self:Refresh()
  self.frame:SetShown(not self.frame:IsShown())
end
