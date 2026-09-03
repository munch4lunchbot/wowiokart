local _, AK = ...

-- One place to edit the whole game.
--
-- Tuning was a flat two-column dump of thirty-four sliders with the sound
-- editor in a separate window and the racer models editable nowhere at all --
-- so tuning anything meant knowing which of three surfaces owned it, and the
-- sliders that belonged together were separated by whichever ones happened to
-- be declared nearby.
--
-- This is a tabbed workshop over the SAME data and the same setters: it reuses
-- AK.Tuning.defs, AK.Tuning:Set/Reset/Report and the audio cue API rather than
-- copying any of them, so there is exactly one definition of what a value is
-- and what changing it does. Everything here is presentation.
local Workshop = {}
AK.Workshop = Workshop

local UI = AK.UI
local RAIL = 158           -- tab rail width
local PANE_X = RAIL + 14
local ROW_H = 27
local WIDTH, HEIGHT = 1120, 720
-- Height available to a pane's CONTENT. Every pane scrolls, so a section that
-- outgrows this scrolls instead of drawing past the bottom of the window --
-- which is what the seat rows were doing, out over the race behind it.
local PANE_H = HEIGHT - 76 - 14

-- Sections in Tuning.defs are declaration order; these are the names worth
-- showing and the order a person would look for them in.
local TAB_LABEL = {
  BAINE = "RACER", CAMERA = "CAMERA", CORNERS = "HANDLING",
  AI = "OPPONENTS", TRACK = "TRACK", WORLD = "WORLD", EFFECTS = "EFFECTS",
}

--- A clipped, wheel-scrollable content frame. Ported from WoWDoom's bench,
--- which is the pattern that actually works for browsing at scale: lists there
--- outgrew every fixed window the moment more entries were added.
local function ScrollBox(parent, w, h)
  local view = CreateFrame("Frame", nil, parent)
  view:SetSize(w, h)
  if view.SetClipsChildren then view:SetClipsChildren(true) end
  view:EnableMouseWheel(true)

  local content = CreateFrame("Frame", nil, view)
  content:SetSize(w, h)
  content:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
  view.content = content
  view.offset, view.contentHeight = 0, h

  view:SetScript("OnMouseWheel", function(self, delta)
    local limit = math.max(0, self.contentHeight - h)
    self.offset = AK.Math.Clamp(self.offset - delta * 40, 0, limit)
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, self.offset)
  end)
  function view:SetContentHeight(value)
    self.contentHeight = value
    content:SetHeight(value)
  end
  return view
end

--- A row of coarse jump buttons. Display ids and file ids are scattered, so
--- browsing them one at a time is useless -- the big steps are the point.
--- Sized from the WIDEST label, not a fixed guess.
---
--- check.js catches truncated button text only for literal strings, and these
--- labels are computed -- so "-1000" silently rendered as "-10..." with nothing
--- to flag it. Measuring the labels here is the same arithmetic the checker
--- does, applied where it can actually see them.
local function Stepper(parent, steps, onStep)
  local widest = 0
  for _, delta in ipairs(steps) do
    widest = math.max(widest, #((delta > 0 and "+" or "") .. tostring(delta)))
  end
  local w = math.max(34, widest * 9 + 12)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(#steps * (w + 2), 22)
  for i, delta in ipairs(steps) do
    local button = UI:NewButton(holder, (delta > 0 and "+" or "") .. tostring(delta), w, 20,
      function() onStep(delta) end)
    button:SetPoint("LEFT", (i - 1) * (w + 2), 0)
    button.quiet = true
  end
  return holder
end

--- The shaped panel plate, not a filled quad with a one-pixel square border.
--- The workshop is reached by a slash command and was the last screen still
--- made of BackdropTemplate; every window in the addon now wears the same
--- object. `border` is kept in the signature because callers pass one, and is
--- now what the plate is TINTED with when a cell wants to look picked.
local function backdrop(frame, r, g, b, a)
  AK.UI:SkinWindow(frame, { r, g, b, a })
end

--- One tuning value: label, range bar, number, and a pair of steppers.
---
--- Registers into AK.Tuning.rows, which is what Tuning:Set already updates --
--- so a value changed from anywhere (a slash command, a reset, this panel)
--- refreshes here with no extra wiring.
function Workshop:TuningRow(parent, def, y)
  local label = UI:NewText(parent, def.label, 12, { .84, .90, 1 }, "LEFT")
  label:SetPoint("TOPLEFT", 4, y)

  if def.hint then
    -- Stops short of the steppers: a hover zone stretched the full width put an
    -- invisible frame over the - and + and swallowed every click.
    local zone = CreateFrame("Frame", nil, parent)
    zone:SetPoint("TOPLEFT", 0, y)
    zone:SetSize(430, ROW_H)
    zone:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
      GameTooltip:SetText(def.hint, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    zone:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  local track = parent:CreateTexture(nil, "ARTWORK")
  track:SetTexture("Interface\\Buttons\\WHITE8x8")
  track:SetVertexColor(0.14, 0.19, 0.28, 1)
  track:SetSize(190, 4)
  track:SetPoint("TOPLEFT", 240, y - 7)
  local fill = parent:CreateTexture(nil, "OVERLAY")
  fill:SetTexture("Interface\\Buttons\\WHITE8x8")
  fill:SetVertexColor(unpack(AK.COLORS.lime))
  fill:SetSize(1, 4)
  fill:SetPoint("TOPLEFT", 240, y - 7)

  local value = UI:NewText(parent, "", 12, AK.COLORS.lime, "RIGHT")
  value:SetPoint("TOPRIGHT", parent, "TOPLEFT", 508, y)

  AK.Tuning.rows = AK.Tuning.rows or {}
  AK.Tuning.rows[def.key] = { value = value, fill = fill, wide = true }

  local minus = UI:NewButton(parent, "-", 22, 19, function()
    AK.Tuning:Set(def, AK.db.tuning[def.key] - def.step)
  end)
  minus:SetPoint("TOPLEFT", 518, y + 3)
  minus.quiet = true
  local plus = UI:NewButton(parent, "+", 22, 19, function()
    AK.Tuning:Set(def, AK.db.tuning[def.key] + def.step)
  end)
  plus:SetPoint("TOPLEFT", 544, y + 3)
  plus.quiet = true
  local reset = UI:NewButton(parent, "RESET", 66, 19, function()
    AK.Tuning:Set(def, def.default)
  end)
  reset:SetPoint("TOPLEFT", 572, y + 3)
  reset.quiet = true
  reset.tooltip = ("Back to %s."):format(tostring(def.default))
  -- pairs, not ipairs: see the note on forEachPresent in UI/RaceUI.lua. These
  -- two cannot be nil today, but the idiom is the trap, not the instance.
  for _, button in pairs({ minus, plus }) do
    button.tooltip = (def.hint and def.hint .. "\n" or "") .. "Right-click to reset this value."
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:HookScript("OnClick", function(_, mouseButton)
      if mouseButton == "RightButton" then AK.Tuning:Set(def, def.default) end
    end)
  end
end

--- A pane per tuning section.
function Workshop:BuildTuningPane(parent, rows)
  local y = -10
  for _, def in ipairs(rows) do
    self:TuningRow(parent, def, y)
    y = y - ROW_H
  end
  return y
end

-- ---------------------------------------------------------------------------
-- ROSTER: racers and karts, every stat editable, and racers can be added
-- ---------------------------------------------------------------------------
--
-- These are the numbers that decide how the whole field behaves and they were
-- editable nowhere -- you had to open Data\Racers.lua and reload. Everything
-- here writes through AK.Roster so it persists, because a stat you have to
-- re-enter after every reload is not tunable in any useful sense.
local STAT_FIELDS = {
  { key = "speed", label = "Top speed" },
  { key = "acceleration", label = "Acceleration" },
  { key = "handling", label = "Handling" },
  { key = "weight", label = "Weight" },
  { key = "drift", label = "Drift" },
  { key = "luck", label = "Luck", racerOnly = true },
}

function Workshop:BuildRosterPane(pane, kind)
  local isRacer = kind == "racers"
  local entries = isRacer and AK.Racers or AK.Karts
  self.roster = self.roster or {}
  self.roster[kind] = { pane = pane, buttons = {}, rows = {}, index = 1 }
  local state = self.roster[kind]

  local heading = UI:NewText(pane,
    isRacer
      and "Every stat is 1-10 and feeds the physics directly. ADD RACER appends a new one -- give it a model on the MODELS tab.\nChanges persist through a reload; RESET puts one back to how it shipped."
      or "Kart stats are 1-10. Weight decides who wins a collision and how long a hit costs you.",
    11, AK.COLORS.muted, "LEFT")
  heading:SetPoint("TOPLEFT", 4, -4)
  heading:SetWidth(880)
  heading:SetJustifyH("LEFT")

  -- Picker down the left, rebuilt on demand so an added racer appears.
  state.listHolder = CreateFrame("Frame", nil, pane)
  state.listHolder:SetPoint("TOPLEFT", 0, -46)
  state.listHolder:SetSize(150, 400)

  local dx = 168
  state.title = UI:NewText(pane, "", 15, AK.COLORS.gold, "LEFT")
  state.title:SetPoint("TOPLEFT", dx, -46)
  state.sub = UI:NewText(pane, "", 11, AK.COLORS.muted, "LEFT")
  state.sub:SetPoint("TOPLEFT", dx, -66)
  state.sub:SetWidth(560)
  state.sub:SetJustifyH("LEFT")

  local y = -96
  for _, spec in ipairs(STAT_FIELDS) do
    if not (spec.racerOnly and not isRacer) then
      local label = UI:NewText(pane, spec.label, 12, { .84, .90, 1 }, "LEFT")
      label:SetPoint("TOPLEFT", dx, y)
      local track = pane:CreateTexture(nil, "ARTWORK")
      track:SetTexture("Interface\\Buttons\\WHITE8x8")
      track:SetVertexColor(0.14, 0.19, 0.28, 1)
      track:SetSize(190, 4)
      track:SetPoint("TOPLEFT", dx + 150, y - 7)
      local fill = pane:CreateTexture(nil, "OVERLAY")
      fill:SetTexture("Interface\\Buttons\\WHITE8x8")
      fill:SetVertexColor(unpack(AK.COLORS.lime))
      fill:SetSize(1, 4)
      fill:SetPoint("TOPLEFT", dx + 150, y - 7)
      local value = UI:NewText(pane, "", 12, AK.COLORS.lime, "RIGHT")
      value:SetPoint("TOPRIGHT", pane, "TOPLEFT", dx + 396, y)

      local function bump(delta)
        local entry = self:RosterEntry(kind)
        if not entry then return end
        AK.Roster:Set(kind, entry.id, spec.key,
          AK.Math.Clamp((entry[spec.key] or 5) + delta, 1, 10))
        self:RefreshRoster(kind)
      end
      local minus = UI:NewButton(pane, "-", 22, 19, function() bump(-1) end)
      minus:SetPoint("TOPLEFT", dx + 406, y + 3)
      minus.quiet = true
      local plus = UI:NewButton(pane, "+", 22, 19, function() bump(1) end)
      plus:SetPoint("TOPLEFT", dx + 432, y + 3)
      plus.quiet = true

      state.rows[spec.key] = { value = value, fill = fill }
      y = y - ROW_H
    end
  end

  y = y - 12
  if isRacer then
    -- Seat framing lives with the racer it belongs to, not on a separate tab:
    -- it is meaningless except as "how does THIS model sit".
    local seatTitle = UI:NewText(pane, "SEAT FRAMING", 11, AK.COLORS.blue, "LEFT")
    seatTitle:SetPoint("TOPLEFT", dx, y)
    y = y - 24
    for _, def in ipairs(AK.Tuning.seatDefs) do
      local label = UI:NewText(pane, def.label, 12, { .84, .90, 1 }, "LEFT")
      label:SetPoint("TOPLEFT", dx, y)
      local value = UI:NewText(pane, "", 12, AK.COLORS.lime, "RIGHT")
      value:SetPoint("TOPRIGHT", pane, "TOPLEFT", dx + 396, y)
      state.rows["seat_" .. def.key] = { value = value }
      local function seat(delta)
        local entry = self:RosterEntry(kind)
        if not entry then return end
        AK.Roster:Set(kind, entry.id, def.key,
          AK.Math.Clamp((entry[def.key] or def.default) + delta, def.min, def.max))
        AK.Roster:InvalidateModels()
        self:RefreshRoster(kind)
      end
      local minus = UI:NewButton(pane, "-", 22, 19, function() seat(-def.step) end)
      minus:SetPoint("TOPLEFT", dx + 406, y + 3)
      minus.quiet = true
      local plus = UI:NewButton(pane, "+", 22, 19, function() seat(def.step) end)
      plus:SetPoint("TOPLEFT", dx + 432, y + 3)
      plus.quiet = true
      y = y - ROW_H
    end

    y = y - 14
    local add = UI:NewButton(pane, "ADD RACER", 130, 24, function()
      local entry = AK.Roster:AddRacer()
      self:RebuildRosterList(kind)
      for index, racer in ipairs(AK.Racers) do
        if racer.id == entry.id then state.index = index end
      end
      self:RefreshRoster(kind)
      AK:Print("Added " .. entry.name .. " -- give it a model on the MODELS tab.")
    end)
    add:SetPoint("TOPLEFT", dx, y)
    add.tooltip = "Append a new racer to the grid. It starts with middling stats and no model."
    local remove = UI:NewButton(pane, "REMOVE", 110, 24, function()
      local entry = self:RosterEntry(kind)
      if entry and AK.Roster:RemoveRacer(entry.id) then
        state.index = 1
        self:RebuildRosterList(kind)
        self:RefreshRoster(kind)
      end
    end)
    remove:SetPoint("TOPLEFT", dx + 138, y)
    remove:SetRestStyle({ .22, .08, .08, .95 }, AK.COLORS.danger)
    remove.tooltip = "Only racers you added can be removed; the shipped roster stays."
    y = y - 32
  end

  local reset = UI:NewButton(pane, "RESET THIS ONE", 160, 24, function()
    local entry = self:RosterEntry(kind)
    if entry then
      AK.Roster:Clear(kind, entry.id)
      AK.Roster:InvalidateModels()
      self:RefreshRoster(kind)
    end
  end)
  reset:SetPoint("TOPLEFT", dx, y)
  y = y - 34

  state.bottom = y
  self:RebuildRosterList(kind)
end

--- The currently selected entry on a roster tab.
function Workshop:RosterEntry(kind)
  local list = kind == "racers" and AK.Racers or AK.Karts
  local state = self.roster and self.roster[kind]
  return state and list[state.index or 1]
end

--- Rebuilt rather than refreshed, because the list can GROW.
function Workshop:RebuildRosterList(kind)
  local state = self.roster[kind]
  local list = kind == "racers" and AK.Racers or AK.Karts
  for _, button in ipairs(state.buttons) do button:Hide() end
  wipe(state.buttons)
  for index, entry in ipairs(list) do
    local button = UI:NewButton(state.listHolder, entry.tag or entry.name, 148, 22, function()
      state.index = index
      if kind == "racers" then AK.db.selection.racer = entry.id
      else AK.db.selection.kart = entry.id end
      self:RefreshRoster(kind)
    end)
    button:SetPoint("TOPLEFT", 0, -(index - 1) * 25)
    state.buttons[index] = button
  end
  state.listHolder:SetHeight(math.max(1, #list * 25))
  self:PaneHeight(kind == "racers" and "RACERS" or "KARTS",
    math.min(state.bottom or -400, -46 - #list * 25))
end

function Workshop:RefreshRoster(kind)
  local state = self.roster and self.roster[kind]
  if not state then return end
  local entry = self:RosterEntry(kind)
  if not entry then return end

  state.title:SetText(entry.name)
  state.sub:SetText(kind == "racers"
    and ("%s  /  creature %s%s"):format(entry.race or "?",
      tostring(entry.model and entry.model.creature or (entry.model and entry.model.unit) or "-"),
      entry.custom and "   (added by you)" or "")
    or (entry.description or ""))

  for _, spec in ipairs(STAT_FIELDS) do
    local row = state.rows[spec.key]
    if row then
      local value = entry[spec.key] or 5
      row.value:SetText(tostring(value))
      row.value:SetTextColor(unpack(AK.Roster:IsChanged(kind, entry.id, spec.key)
        and AK.COLORS.gold or AK.COLORS.lime))
      row.fill:SetWidth(math.max(1, 188 * ((value - 1) / 9)))
    end
  end
  for _, def in ipairs(AK.Tuning.seatDefs) do
    local row = state.rows["seat_" .. def.key]
    if row then row.value:SetText(("%.2f"):format(entry[def.key] or def.default)) end
  end
  for index, button in ipairs(state.buttons) do
    local on = index == state.index
    button:SetRestStyle(on and { .13, .22, .25, 1 } or { .06, .09, .14, .95 },
      on and AK.COLORS.gold or { .18, .24, .34 })
  end
end

-- ---------------------------------------------------------------------------
-- DATA: items, tracks, terrain -- one editor, driven by field specs
-- ---------------------------------------------------------------------------
--
-- These three are the last of the game that was not editable anywhere, and they
-- are the same shape: a table of entries with numeric fields. Rather than three
-- more bespoke panes, one generic editor reads a spec. Adding another editable
-- table is a spec, not another copy of this.
--
-- Fields are declared with their own ranges because the magnitudes have nothing
-- in common -- a track is 2600 metres long and a terrain multiplier is 0.52,
-- and a shared step would make one uneditable and the other unusable.
local DATA_TABS = {
  {
    key = "ITEMS", domain = "items", label = "ITEMS",
    blurb = "How each power-up behaves. Speed and life decide whether a shell ever "
      .. "reaches anybody; blast is the radius that catches bystanders.\n"
      .. "Item DISTRIBUTION -- who draws what -- is on the OPPONENTS tab.",
    fields = {
      { key = "speed", label = "Travel speed", min = 5, max = 120, step = 2 },
      { key = "life", label = "Lifetime (s)", min = 1, max = 40, step = 1 },
      { key = "blast", label = "Blast radius", min = 0, max = 40, step = 1 },
      { key = "quantity", label = "Uses", min = 1, max = 10, step = 1 },
      { key = "duration", label = "Duration (s)", min = 1, max = 30, step = 1 },
    },
  },
  {
    key = "TRACKS", domain = "tracks", label = "TRACKS",
    blurb = "Per-circuit shape and mood. Length and laps change how long a race lasts; "
      .. "light is the circuit's ambient brightness and feeds the fog and the tunnels.\n"
      .. "Changing length recompiles the track, so the next race picks it up.",
    fields = {
      { key = "length", label = "Lap length (m)", min = 800, max = 6000, step = 50 },
      { key = "laps", label = "Laps", min = 1, max = 9, step = 1 },
      { key = "light", label = "Ambient light", min = 0.3, max = 1.4, step = 0.02 },
      { key = "sweep", label = "Corner sweep", min = 0.5, max = 8, step = 0.1 },
      { key = "archSpacing", label = "Arch spacing (m)", min = 0, max = 400, step = 10 },
    },
  },
  {
    key = "TERRAIN", domain = "terrain", label = "SURFACES",
    blurb = "What each surface does to a kart. These are MULTIPLIERS on your own stats, "
      .. "so 1.00 is 'no penalty at all'.\nSteering is the one that decides whether a "
      .. "mistake is recoverable -- too low and going wide takes away the means of getting back.",
    fields = {
      { key = "speed", label = "Top speed", min = 0, max = 1.2, step = 0.02 },
      { key = "acceleration", label = "Acceleration", min = 0, max = 1.2, step = 0.02 },
      { key = "steering", label = "Steering", min = 0, max = 1.2, step = 0.02 },
      { key = "traction", label = "Traction", min = 0, max = 1.2, step = 0.02 },
      { key = "drift", label = "Drift", min = 0, max = 1.2, step = 0.02 },
      { key = "rumble", label = "Rumble", min = 0, max = 1.5, step = 0.05 },
    },
  },
}

function Workshop:BuildDataPane(pane, spec)
  self.data = self.data or {}
  local state = { pane = pane, buttons = {}, rows = {}, index = 1, spec = spec }
  self.data[spec.key] = state

  local heading = UI:NewText(pane, spec.blurb, 11, AK.COLORS.muted, "LEFT")
  heading:SetPoint("TOPLEFT", 4, -4)
  heading:SetWidth(880)
  heading:SetJustifyH("LEFT")

  state.listBox = ScrollBox(pane, 160, PANE_H - 70)
  state.listBox:SetPoint("TOPLEFT", 0, -52)

  local dx = 178
  state.title = UI:NewText(pane, "", 15, AK.COLORS.gold, "LEFT")
  state.title:SetPoint("TOPLEFT", dx, -52)
  state.sub = UI:NewText(pane, "", 11, AK.COLORS.muted, "LEFT")
  state.sub:SetPoint("TOPLEFT", dx, -72)
  state.sub:SetWidth(560)
  state.sub:SetJustifyH("LEFT")

  local y = -104
  for _, field in ipairs(spec.fields) do
    local label = UI:NewText(pane, field.label, 12, { .84, .90, 1 }, "LEFT")
    label:SetPoint("TOPLEFT", dx, y)
    local track = pane:CreateTexture(nil, "ARTWORK")
    track:SetTexture("Interface\\Buttons\\WHITE8x8")
    track:SetVertexColor(0.14, 0.19, 0.28, 1)
    track:SetSize(190, 4)
    track:SetPoint("TOPLEFT", dx + 170, y - 7)
    local fill = pane:CreateTexture(nil, "OVERLAY")
    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    fill:SetVertexColor(unpack(AK.COLORS.lime))
    fill:SetSize(1, 4)
    fill:SetPoint("TOPLEFT", dx + 170, y - 7)
    local value = UI:NewText(pane, "", 12, AK.COLORS.lime, "RIGHT")
    value:SetPoint("TOPRIGHT", pane, "TOPLEFT", dx + 420, y)

    local function bump(delta)
      local row = self:DataEntry(spec.key)
      if not row then return end
      -- A field the entry does not have is not editable on it: a banana has no
      -- travel speed, and inventing one would put a number into the physics
      -- that nothing reads.
      if row.entry[field.key] == nil then
        AK:Print(row.id .. " has no " .. field.label:lower() .. ".")
        return
      end
      AK.Roster:Set(spec.domain, row.id, field.key,
        AK.Math.Clamp(row.entry[field.key] + delta, field.min, field.max))
      self:RefreshData(spec.key)
    end
    local minus = UI:NewButton(pane, "-", 22, 19, function() bump(-field.step) end)
    minus:SetPoint("TOPLEFT", dx + 430, y + 3)
    minus.quiet = true
    local plus = UI:NewButton(pane, "+", 22, 19, function() bump(field.step) end)
    plus:SetPoint("TOPLEFT", dx + 456, y + 3)
    plus.quiet = true

    state.rows[field.key] = { value = value, fill = fill, field = field }
    y = y - ROW_H
  end

  y = y - 16
  local reset = UI:NewButton(pane, "RESET THIS ONE", 160, 24, function()
    local row = self:DataEntry(spec.key)
    if row then
      AK.Roster:Clear(spec.domain, row.id)
      self:RefreshData(spec.key)
    end
  end)
  reset:SetPoint("TOPLEFT", dx, y)
  state.bottom = y - 34
end

function Workshop:DataEntry(key)
  local state = self.data and self.data[key]
  if not state then return nil end
  local rows = AK.Roster:Entries(state.spec.domain)
  return rows[state.index or 1]
end

function Workshop:RefreshData(key)
  local state = self.data and self.data[key]
  if not state then return end
  local rows = AK.Roster:Entries(state.spec.domain)

  -- The list is rebuilt rather than refreshed: a domain can gain entries.
  for _, button in ipairs(state.buttons) do button:Hide() end
  wipe(state.buttons)
  for index, row in ipairs(rows) do
    local entry = row.entry
    local button = UI:NewButton(state.listBox.content, entry.name or row.id, 152, 22, function()
      state.index = index
      self:RefreshData(key)
    end)
    button:SetPoint("TOPLEFT", 0, -(index - 1) * 25)
    local on = index == state.index
    button:SetRestStyle(on and { .13, .22, .25, 1 } or { .06, .09, .14, .95 },
      on and AK.COLORS.gold or { .18, .24, .34 })
    state.buttons[index] = button
  end
  state.listBox:SetContentHeight(math.max(PANE_H - 70, #rows * 25 + 8))

  local row = rows[state.index or 1]
  if not row then return end
  state.title:SetText(row.entry.name or row.id)
  state.sub:SetText(row.entry.description or row.entry.subtitle or row.id)

  for fieldKey, widget in pairs(state.rows) do
    local value = row.entry[fieldKey]
    local field = widget.field
    if value == nil then
      -- Shown as absent rather than as zero, so nobody tunes a field the entry
      -- does not actually have.
      widget.value:SetText("--")
      widget.value:SetTextColor(0.38, 0.42, 0.50)
      widget.fill:SetWidth(1)
    else
      widget.value:SetText(field.step < 1 and ("%.2f"):format(value) or tostring(value))
      widget.value:SetTextColor(unpack(AK.Roster:IsChanged(state.spec.domain, row.id, fieldKey)
        and AK.COLORS.gold or AK.COLORS.lime))
      widget.fill:SetWidth(math.max(1,
        188 * AK.Math.Clamp((value - field.min) / (field.max - field.min), 0, 1)))
    end
  end
end

-- ---------------------------------------------------------------------------
-- SOUND
-- ---------------------------------------------------------------------------
--- Every cue on one scrolling page, each with the loop that actually works:
--- STEP the id, PLAY it, keep it if it sounds right.
---
--- The previous version had a single bind box for a selected cue, which is the
--- wrong shape entirely: nobody in the build loop can hear these, so choosing a
--- sound is a search, and a search needs to be fast and side by side. Silence
--- on Play is the honest signal that an id has no file behind it -- the same
--- check WoWDoom's bench uses for display ids.
function Workshop:BuildSoundPane(pane)
  -- Always reachable, and deliberately at the top rather than per row: the
  -- library has entries that run for minutes, and the one thing you need when
  -- one starts is a stop you do not have to go hunting for.
  local stop = UI:NewButton(pane, "STOP SOUND", 130, 22, function() AK:StopPreview() end)
  stop:SetPoint("TOPRIGHT", -8, -2)
  stop:SetRestStyle({ .22, .08, .08, .95 }, AK.COLORS.danger)
  stop.tooltip = "Cut whatever is currently playing. Some library entries are minutes long."

  -- The only link to the focused editor used to sit on the standalone tuning
  -- window, which nothing opened -- so in practice it was reachable solely by
  -- typing /kart sound. This bench is for sweeping every cue at once; that one
  -- is for hunting a single sound through the file library.
  local editor = UI:NewButton(pane, "SOUND EDITOR", 140, 22, function() AK.SoundEditor:Toggle() end)
  editor:SetPoint("TOPRIGHT", -146, -2)
  editor.tooltip = "Open the focused editor: one cue at a time, with a scanner for the game's file library."

  local heading = UI:NewText(pane,
    "Nobody building this can hear these, so choosing a sound is a SEARCH. Step an id, "
    .. "play it, keep it. Silence means that id has no file.\n"
    .. "NEXT IDEA walks the built-in candidates. x12 is how many times it fired last race "
    .. "-- that is the number that says whether a sample will wear out.",
    11, AK.COLORS.muted, "LEFT")
  heading:SetPoint("TOPLEFT", 4, -4)
  heading:SetWidth(760)
  heading:SetJustifyH("LEFT")

  local list = ScrollBox(pane, 920, PANE_H - 52)
  list:SetPoint("TOPLEFT", 0, -44)
  self.soundRows = {}

  local cues = AK:CueList()
  for i, entry in ipairs(cues) do
    local cue = entry.cue
    local row = CreateFrame("Frame", nil, list.content)
    row:SetSize(860, 26)
    row:SetPoint("TOPLEFT", 4, -(i - 1) * 28)

    -- The NAME is a play button too. This is a listening bench: the thing you
    -- do most is hear a cue, and making that a small button off to the right
    -- while a big inert label sits under the cursor is backwards.
    local nameButton = CreateFrame("Button", nil, row)
    nameButton:SetPoint("LEFT", 0, 0)
    nameButton:SetSize(160, 24)
    nameButton:SetScript("OnClick", function() AK:PreviewCue(cue) end)
    local name = UI:NewText(nameButton, cue, 12, { .88, .93, 1 }, "LEFT")
    name:SetPoint("LEFT", 0, 0)
    name:SetWidth(110)
    name:SetJustifyH("LEFT")
    nameButton:SetScript("OnEnter", function()
      name:SetTextColor(unpack(AK.COLORS.gold))
      GameTooltip:SetOwner(nameButton, "ANCHOR_RIGHT")
      GameTooltip:SetText("Click to hear " .. cue, 1, 1, 1)
      GameTooltip:Show()
    end)
    nameButton:SetScript("OnLeave", function()
      name:SetTextColor(.88, .93, 1)
      GameTooltip:Hide()
    end)

    local plays = UI:NewText(row, "", 11, AK.COLORS.muted, "LEFT")
    plays:SetPoint("LEFT", 112, 0)
    plays:SetWidth(52)
    plays:SetJustifyH("LEFT")

    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(78, 22)
    box:SetPoint("LEFT", 168, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetScript("OnEnterPressed", function(self)
      local id = tonumber(self:GetText())
      if id and id > 0 then AK:SetCueSound(cue, id) end
      self:ClearFocus()
      Workshop:RefreshSound()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local stepper = Stepper(row, { -100, -1, 1, 100 }, function(delta)
      local current = (AK.db.sfxOverride and AK.db.sfxOverride[cue]) or 0
      AK:SetCueSound(cue, math.max(1, current + delta))
      AK:PreviewCue(cue)
      Workshop:RefreshSound()
    end)
    -- LAID OUT WITH A CURSOR, not with hand-written x positions.
    --
    -- Widening the stepper pushed it straight over PLAY, and an invisible
    -- overlap means the click lands on the wrong button -- PLAY was firing
    -- "+100" instead of playing anything, which is why nothing could be heard.
    -- A cursor that each widget advances cannot silently overlap the next one.
    local x = 252
    stepper:SetPoint("LEFT", x, 0)
    x = x + stepper:GetWidth() + 10

    -- Refreshes afterwards: resolution only happens ON play, so without this
    -- the source column said "unplayed" forever no matter how many times you
    -- pressed it -- which reads as the button doing nothing even when it works.
    local play = UI:NewButton(row, "PLAY", 54, 20, function()
      AK:PreviewCue(cue)
      Workshop:RefreshSound()
    end)
    play:SetPoint("LEFT", x, 0)
    play.quiet = true
    x = x + 60
    -- Repetition is a RATE, and a single audition cannot show one.
    local rate = UI:NewButton(row, "x8", 34, 20, function() AK:AuditionRate(cue) end)
    rate:SetPoint("LEFT", x, 0)
    rate.quiet = true
    rate.tooltip = "Play it eight times at the fastest rate it is allowed -- its worst case."
    x = x + 40

    -- Walks the built-in candidate list one per click, so a whole cue can be
    -- auditioned without typing anything or knowing a single id.
    -- Sweeps forward until it finds an id that actually plays, and binds it.
    -- Most file ids are not sounds, so stepping by one is mostly pressing a
    -- button that does nothing; this is the search that "next idea" was not.
    local next_ = UI:NewButton(row, "NEXT SOUND", 122, 20, function()
      local from = (AK.db.sfxOverride and AK.db.sfxOverride[cue])
        or (AK:CueInfo(cue) or {}).id or 0
      local id, name = AK:NextAvailableSound(cue, from)
      if id then
        AK:Print(("%s -> %d  |cffffd100%s|r"):format(cue, id, name or "?"))
      else
        AK:Print(cue .. ": that is the end of the sound library -- DEFAULT to start over.")
      end
      Workshop:RefreshSound()
    end)
    next_.tooltip = "Sweep forward for the next id that actually makes a noise, and bind it.\nStarts from whatever is in the box, so type a number to search from there."
    next_:SetPoint("LEFT", x, 0)
    next_.quiet = true
    x = x + 128

    local mute = UI:NewButton(row, "MUTE", 58, 20, function()
      -- Toggle: a second press is the obvious way to undo it.
      local bound = AK.db.sfxOverride and AK.db.sfxOverride[cue]
      AK:SetCueSound(cue, bound == 0 and nil or 0)
      Workshop:RefreshSound()
    end)
    mute:SetPoint("LEFT", x, 0)
    mute.quiet = true
    mute.tooltip = "Silence this cue. Press again to bring it back."
    x = x + 64

    local reset = UI:NewButton(row, "DEFAULT", 86, 20, function()
      AK:SetCueSound(cue, nil)
      row.idea = 0
      Workshop:RefreshSound()
    end)
    reset:SetPoint("LEFT", x, 0)
    reset.quiet = true
    x = x + 94

    local source = UI:NewText(row, "", 10, { .55, .85, .68 }, "LEFT")
    source:SetPoint("LEFT", x, 0)
    source:SetWidth(150)
    source:SetJustifyH("LEFT")
    row:SetWidth(x + 156)

    row.cue, row.box, row.plays, row.source = cue, box, plays, source
    self.soundRows[#self.soundRows + 1] = row
  end
  list:SetContentHeight(#cues * 28 + 12)
end

function Workshop:RefreshSound()
  for _, row in ipairs(self.soundRows or {}) do
    local info = AK:CueInfo(row.cue)
    if info then
      local bound = AK.db.sfxOverride and AK.db.sfxOverride[row.cue]
      -- SHOW THE RESOLVED ID, even for a built-in.
      --
      -- The box used to be blank unless you had bound something, so the id a
      -- cue actually settled on was invisible -- you could hear that two cues
      -- should swap and have no way to write down either one. A built-in shows
      -- its number dimmed, so it reads as "this is what it resolved to", not as
      -- something you chose; the source column keeps that distinction too.
      -- Resolution only happens on PLAY, so an unplayed cue has nothing to show
      -- until it is heard once.
      if not row.box:HasFocus() then
        if bound and bound ~= 0 then
          row.box:SetText(tostring(bound))
          row.box:SetTextColor(1, 0.82, 0.25)
        elseif bound == 0 then
          row.box:SetText("")
          row.box:SetTextColor(1, 1, 1)
        else
          row.box:SetText(info.id and info.id > 0 and tostring(info.id) or "")
          row.box:SetTextColor(0.52, 0.58, 0.68)
        end
      end
      if info.plays > 0 then
        row.plays:SetText(("x%d"):format(info.plays))
        row.plays:SetTextColor(unpack(info.plays > 40 and AK.COLORS.danger or AK.COLORS.lime))
      else
        row.plays:SetText("")
      end
      -- What it ACTUALLY resolved to on this client, which is the only honest
      -- answer -- a candidate that does not exist here silently falls through.
      if bound == 0 then
        row.source:SetText("MUTED")
        row.source:SetTextColor(0.62, 0.40, 0.40)
      elseif bound then
        -- The NAME, not "yours". A number tells you nothing about what you are
        -- listening to; SOUNDKIT names are descriptive, and seeing one is how
        -- you know whether a cue has landed on something sensible.
        row.source:SetText(AK:SoundName(bound) or ("file " .. bound))
        row.source:SetTextColor(unpack(AK.COLORS.gold))
      elseif info.source == "kit" or info.source == "file" then
        row.source:SetText(AK:SoundName(info.id) or (info.source .. " " .. tostring(info.id)))
        row.source:SetTextColor(0.55, 0.62, 0.72)
      elseif info.source == "none" then
        row.source:SetText("SILENT")
        row.source:SetTextColor(unpack(AK.COLORS.danger))
      else
        row.source:SetText("unplayed")
        row.source:SetTextColor(0.45, 0.50, 0.58)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- MODELS
-- ---------------------------------------------------------------------------
function Workshop:BuildModelPane(pane)
  local header = UI:NewText(pane,
    "Framing is per racer -- every model has its own origin and scale.\nPRINT CHANGES reports these ready to paste into Data\\Racers.lua.",
    11, AK.COLORS.muted, "LEFT")
  header:SetPoint("TOPLEFT", 4, -6)

  -- Racer picker down the left.
  self.racerButtons = {}
  for index, racer in ipairs(AK.Racers) do
    local button = UI:NewButton(pane, racer.tag or racer.name, 132, 22, function()
      AK.db.selection.racer = racer.id
      self:RefreshModels()
    end)
    button:SetPoint("TOPLEFT", 0, -46 - (index - 1) * 25)
    self.racerButtons[index] = { button = button, id = racer.id }
  end
  self.previewName = UI:NewText(pane, "", 12, AK.COLORS.gold, "LEFT")
  self.previewName:SetPoint("TOPLEFT", 0, -46 - #AK.Racers * 25 - 8)

  -- THE GALLERY. Eight live models at a time, each labelled with its id.
  --
  -- This is the part that makes choosing a model possible at all: a creature id
  -- means nothing written down, and there are tens of thousands of them. Seeing
  -- eight at once and paging in coarse jumps turns "guess an id and reload"
  -- into browsing. A BLANK cell is information too -- it proves that id has no
  -- model behind it, which is the check that stops a wrong guess shipping.
  self.cells = {}
  local gx = 150
  for i = 1, 8 do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local cell = CreateFrame("Button", nil, pane)
    cell:SetSize(150, 186)
    cell:SetPoint("TOPLEFT", gx + col * 156, -46 - row * 194)
    backdrop(cell, 0.05, 0.07, 0.11, 1)
    cell.model = CreateFrame("PlayerModel", nil, cell)
    -- EXPLICIT SIZE, not two anchors.
    --
    -- Anchored TOPLEFT+BOTTOMRIGHT, a PlayerModel has ZERO size until a layout
    -- pass has run -- and a zero-size model never begins loading, so SetCreature
    -- was being dropped outright. Only ids already cached elsewhere in the addon
    -- ever appeared, which is why exactly one cell filled in; clicking one
    -- refreshed it after layout had happened, which is what made it work and
    -- made this look like a load-timing problem rather than a sizing one.
    -- Model:New has always passed a real size for this reason.
    cell.model:SetSize(140, 161)
    cell.model:SetPoint("TOPLEFT", 5, -5)
    -- Model loads are ASYNCHRONOUS. Framing applied in the same frame as
    -- SetCreature is applied to a model that is not there yet and is simply
    -- lost, so a paged cell stayed blank until something forced a re-apply --
    -- which is what clicking it was doing. Re-pose on the load event instead.
    cell.model:SetScript("OnModelLoaded", function(self)
      self:SetPosition(0, 0, -0.35)
      self:SetFacing(0.4)
    end)
    cell.label = UI:NewText(cell, "", 11, { .9, .85, .7 }, "CENTER")
    cell.label:SetPoint("BOTTOM", 0, 5)
    cell:SetScript("OnClick", function()
      local racer = AK.Tuning:SelectedRacer()
      if cell.displayId and racer then
        racer.model = { creature = cell.displayId }
        -- Every live kart caches its spec, so drop those or the change is
        -- invisible until something else happens to invalidate them.
        if AK.RaceUI and AK.RaceUI.karts then
          for _, kart in ipairs(AK.RaceUI.karts) do AK.Model:Invalidate(kart.model) end
        end
        AK:Print(("%s now uses creature %d."):format(racer.name, cell.displayId))
        self:RefreshModels()
      end
    end)
    -- Lit rather than outlined: the plate has no border to recolour.
    cell:SetScript("OnEnter", function() cell:SetPlateColor({ 0.13, 0.17, 0.25, 1 }) end)
    cell:SetScript("OnLeave", function()
      cell:SetPlateColor(cell.akPicked and { 0.40, 0.30, 0.09, 1 } or { 0.05, 0.07, 0.11, 1 })
    end)
    self.cells[i] = cell
  end

  -- Coarse first: creature ids are scattered, so stepping one at a time is
  -- useless for finding anything.
  local stepper = Stepper(pane, { -1000, -100, -8, 8, 100, 1000 }, function(delta)
    self.baseId = math.max(1, (self.baseId or 1) + delta)
    self:RefreshModels()
  end)
  stepper:SetPoint("TOPLEFT", gx, -434)

  local goLabel = UI:NewText(pane, "jump to id", 11, AK.COLORS.muted, "LEFT")
  goLabel:SetPoint("TOPLEFT", gx + 290, -434)
  local goBox = CreateFrame("EditBox", nil, pane, "InputBoxTemplate")
  goBox:SetSize(80, 22)
  goBox:SetPoint("TOPLEFT", gx + 358, -432)
  goBox:SetAutoFocus(false)
  goBox:SetNumeric(true)
  goBox:SetScript("OnEnterPressed", function(box)
    self.baseId = math.max(1, tonumber(box:GetText()) or 1)
    box:ClearFocus()
    self:RefreshModels()
  end)
  goBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

  local here = UI:NewButton(pane, "JUMP TO CURRENT", 164, 22, function()
    local racer = AK.Tuning:SelectedRacer()
    self.baseId = (racer and racer.model and racer.model.creature) or 1
    self:RefreshModels()
  end)
  here:SetPoint("TOPLEFT", gx + 450, -433)

  local note = UI:NewText(pane,
    "Pick a racer, page or type an id, then CLICK a model to give it to them. "
    .. "A blank cell means that id has no model -- which is the check that stops a wrong guess.",
    10, { .55, .60, .70 }, "LEFT")
  note:SetPoint("TOPLEFT", gx, -462)
  note:SetWidth(620)
  note:SetJustifyH("LEFT")

  -- Seat framing for whoever is selected.
  self.seatRows = {}
  -- Below the gallery, the paging row and the note beneath it.
  local sy = -496
  local seatTitle = UI:NewText(pane, "SEAT FRAMING", 11, AK.COLORS.blue, "LEFT")
  seatTitle:SetPoint("TOPLEFT", gx, sy)
  sy = sy - 22
  for _, def in ipairs(AK.Tuning.seatDefs) do
    local label = UI:NewText(pane, def.label, 12, { .84, .90, 1 }, "LEFT")
    label:SetPoint("TOPLEFT", gx, sy)
    local value = UI:NewText(pane, "", 12, AK.COLORS.lime, "RIGHT")
    value:SetPoint("TOPRIGHT", pane, "TOPLEFT", gx + 210, sy)
    self.seatRows[def.key] = value
    AK.Tuning.seatRows = AK.Tuning.seatRows or {}
    AK.Tuning.seatRows[def.key] = value
    local minus = UI:NewButton(pane, "-", 22, 19, function()
      local racer = AK.Tuning:SelectedRacer()
      AK.Tuning:SetSeat(def, (racer and racer[def.key] or def.default) - def.step)
      self:RefreshModels()
    end)
    minus:SetPoint("TOPLEFT", gx + 220, sy + 3)
    minus.quiet = true
    local plus = UI:NewButton(pane, "+", 22, 19, function()
      local racer = AK.Tuning:SelectedRacer()
      AK.Tuning:SetSeat(def, (racer and racer[def.key] or def.default) + def.step)
      self:RefreshModels()
    end)
    plus:SetPoint("TOPLEFT", gx + 246, sy + 3)
    plus.quiet = true
    sy = sy - ROW_H
  end

  -- The rider/kart relationship lives in the RACER tab, but it is meaningless
  -- without something to look at, so the same values are repeated here beside
  -- the preview rather than making people flip tabs to judge a change.
  sy = sy - 10
  local shared = UI:NewText(pane, "RIDER IN THE KART", 11, AK.COLORS.blue, "LEFT")
  shared:SetPoint("TOPLEFT", gx, sy)
  sy = sy - 22
  for _, key in ipairs({ "modelZoom", "modelScale", "modelLift", "kartLip" }) do
    for _, def in ipairs(AK.Tuning.defs) do
      if def.key == key then
        local label = UI:NewText(pane, def.label, 12, { .84, .90, 1 }, "LEFT")
        label:SetPoint("TOPLEFT", gx, sy)
        local value = UI:NewText(pane, "", 12, AK.COLORS.lime, "RIGHT")
        value:SetPoint("TOPRIGHT", pane, "TOPLEFT", gx + 210, sy)
        -- Not registered into Tuning.rows: that table holds ONE widget per key
        -- and the RACER tab already owns these. Refreshed by hand instead.
        self.modelEcho = self.modelEcho or {}
        self.modelEcho[key] = { value = value, def = def }
        local minus = UI:NewButton(pane, "-", 22, 19, function()
          AK.Tuning:Set(def, AK.db.tuning[def.key] - def.step)
          self:RefreshModels()
        end)
        minus:SetPoint("TOPLEFT", gx + 220, sy + 3)
        minus.quiet = true
        local plus = UI:NewButton(pane, "+", 22, 19, function()
          AK.Tuning:Set(def, AK.db.tuning[def.key] + def.step)
          self:RefreshModels()
        end)
        plus:SetPoint("TOPLEFT", gx + 246, sy + 3)
        plus.quiet = true
        sy = sy - ROW_H
      end
    end
  end
end

function Workshop:RefreshModels()
  if not self.cells then return end
  local racer = AK.Tuning:SelectedRacer()
  self.baseId = self.baseId or (racer and racer.model and racer.model.creature) or 1
  if racer then
    self.previewName:SetText(("%s\ncreature %s"):format(racer.name,
      tostring(racer.model and racer.model.creature or "-")))
  end

  -- Load each cell straight from a creature id. An id with nothing behind it
  -- simply renders empty, and that emptiness is the answer.
  for i, cell in ipairs(self.cells) do
    local id = (self.baseId or 1) + i - 1
    cell.displayId = id
    cell.model:ClearModel()
    cell.model:SetCreature(id)
    -- Applied now for anything already cached, and again from OnModelLoaded for
    -- everything that has to stream in.
    cell.model:SetPosition(0, 0, -0.35)
    cell.model:SetFacing(0.4)
    cell.label:SetText(tostring(id))
    local mine = racer and racer.model and racer.model.creature == id
    cell.label:SetTextColor(unpack(mine and AK.COLORS.gold or { .9, .85, .7 }))
    -- Remembered on the cell so OnLeave can put the right colour back rather
    -- than always resetting to unpicked.
    cell.akPicked = mine
    cell:SetPlateColor(mine and { 0.40, 0.30, 0.09, 1 } or { 0.05, 0.07, 0.11, 1 })
  end
  for _, entry in ipairs(self.racerButtons or {}) do
    local selected = entry.id == AK.db.selection.racer
    entry.button:SetRestStyle(selected and { .13, .22, .25, 1 } or { .06, .09, .14, .95 },
      selected and AK.COLORS.gold or { .18, .24, .34 })
  end
  for key, value in pairs(self.seatRows or {}) do
    value:SetText(("%.2f"):format(racer and racer[key] or 0))
  end
  for _, echo in pairs(self.modelEcho or {}) do
    echo.value:SetText(("%.2f"):format(AK.db.tuning[echo.def.key] or 0))
  end
end

-- ---------------------------------------------------------------------------
function Workshop:SelectTab(name)
  self.tab = name
  for tabName, pane in pairs(self.panes) do pane:SetShown(tabName == name) end
  for tabName, button in pairs(self.tabs) do
    local on = tabName == name
    button:SetRestStyle(on and { .13, .22, .25, 1 } or { .05, .08, .12, .9 },
      on and AK.COLORS.gold or { .16, .21, .30 })
  end
  if name == "SOUND" then self:RefreshSound() end
  if name == "MODELS" then self:RefreshModels() end
  if name == "RACERS" then self:RebuildRosterList("racers") self:RefreshRoster("racers") end
  if name == "KARTS" then self:RebuildRosterList("karts") self:RefreshRoster("karts") end
  if self.data and self.data[name] then self:RefreshData(name) end
end

function Workshop:Build()
  if self.frame then return end

  local frame = CreateFrame("Frame", "AzerothKartWorkshop", UIParent)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER", 0, 0)
  -- FULLSCREEN_DIALOG, never TOOLTIP: GameTooltip lives at TOOLTIP strata, so a
  -- panel parked there draws over its own hints. 900 clears the race (max 500)
  -- and the menu (700); the AI report sits above at 960 on purpose.
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(900)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  backdrop(frame, 0.045, 0.075, 0.125, 0.97)
  -- 1120x720 is wider than a 4:3 client's UIParent (1024) and within 48px of a
  -- 16:9 one's height, so the panel hung off both edges on the first and had no
  -- margin at all on the second. It is a fixed-size centred frame, so scaling
  -- the frame itself is the whole fix -- no container needed. Re-run whenever
  -- the client is resized or the master UI scale changes.
  -- Refitted every time the panel is opened rather than hooked to UIParent:
  -- the panel is only ever shown by an explicit action, so that is early enough
  -- to catch a resolution or UI-scale change, and it keeps this addon out of a
  -- Blizzard frame's script chain.
  frame:Hide()
  self.frame = frame

  local title = UI:NewText(frame, "WORKSHOP", 16, AK.COLORS.gold, "LEFT")
  title:SetPoint("TOPLEFT", 16, -12)
  local hint = UI:NewText(frame, "drag to move  /  every change applies live  /  gold means changed from default",
    10, AK.COLORS.muted, "LEFT")
  hint:SetPoint("TOPLEFT", 16, -32)

  local close = UI:NewButton(frame, "CLOSE", 90, 24, function() self:Toggle() end)
  close:SetPoint("TOPRIGHT", -14, -12)
  local report = UI:NewButton(frame, "PRINT CHANGES", 150, 24, function() AK.Tuning:Report() end)
  report:SetPoint("TOPRIGHT", -110, -12)
  report.tooltip = "Print everything you have moved off its default, ready to paste back."
  local reset = UI:NewButton(frame, "RESET ALL", 110, 24, function()
    AK.Tuning:Reset()
    self:RefreshModels()
  end)
  reset:SetPoint("TOPRIGHT", -266, -12)
  reset:SetRestStyle({ .22, .08, .08, .95 }, AK.COLORS.danger)
  reset.tooltip = "Put every tuning value back to its shipped default."

  -- Group the flat def list into its sections, then one tab per section.
  local sections, current = {}, nil
  for _, def in ipairs(AK.Tuning.defs) do
    if def.section then
      current = { name = def.section, rows = {} }
      sections[#sections + 1] = current
    elseif current then
      current.rows[#current.rows + 1] = def
    end
  end

  self.tabs, self.panes = {}, {}
  local order = {}
  for _, section in ipairs(sections) do order[#order + 1] = section end

  local y = -62
  -- Every pane is a SCROLL BOX, not a bare frame.
  --
  -- A fixed pane silently lets a section draw past the bottom of the window and
  -- out over the game -- the seat rows did exactly that, floating on the track
  -- below the panel. Making the container scroll means the failure mode of
  -- adding one more row is a scrollbar, not content spilling into the world.
  -- `Workshop:PaneHeight` records what each pane actually needs.
  local function addTab(key, label)
    local button = UI:NewButton(frame, label, RAIL - 24, 26, function() self:SelectTab(key) end)
    button:SetPoint("TOPLEFT", 12, y)
    y = y - 30
    self.tabs[key] = button
    local box = ScrollBox(frame, WIDTH - PANE_X - 20, PANE_H)
    box:SetPoint("TOPLEFT", PANE_X, -62)
    box:Hide()
    self.panes[key] = box
    return box.content, box
  end

  --- Tell a pane how tall its contents actually are, so it can scroll to them.
  function self:PaneHeight(key, bottomY)
    local box = self.panes[key]
    if box then box:SetContentHeight(math.max(PANE_H, math.abs(bottomY) + 24)) end
  end

  for _, section in ipairs(order) do
    local pane = addTab(section.name, TAB_LABEL[section.name] or section.name)
    self:PaneHeight(section.name, self:BuildTuningPane(pane, section.rows))
  end
  self:BuildRosterPane(addTab("RACERS", "RACERS"), "racers")
  self:BuildRosterPane(addTab("KARTS", "KARTS"), "karts")
  for _, spec in ipairs(DATA_TABS) do
    self:BuildDataPane(addTab(spec.key, spec.label), spec)
    self:PaneHeight(spec.key, self.data[spec.key].bottom)
  end
  self:BuildModelPane(addTab("MODELS", "MODELS"))
  -- The gallery, its paging row and the note beneath it all sit above this.
  self:PaneHeight("MODELS", -540)
  self:BuildSoundPane(addTab("SOUND", "SOUND"))
  -- The sound pane owns its own inner scroll box, so the outer one only ever
  -- needs to fit the pane itself.
  self:PaneHeight("SOUND", -PANE_H)

  -- Paint every row with its current value the moment the panel exists, rather
  -- than waiting for something to be nudged.
  for _, def in ipairs(AK.Tuning.defs) do
    if def.key then AK.Tuning:Set(def, AK.db.tuning[def.key]) end
  end
  self:SelectTab(order[1] and order[1].name or "SOUND")
end

--- Fit the panel to the client. It is a fixed-size centred frame, so scaling
--- the frame itself is the whole fix.
function Workshop:Fit()
  if not self.frame then return end
  local width, height = UIParent:GetWidth(), UIParent:GetHeight()
  if not width or width <= 0 or not height or height <= 0 then return end
  self.frame:SetScale(AK.Math.Clamp(
    math.min(width / (WIDTH + 48), height / (HEIGHT + 48)), 0.50, 1.50))
end

function Workshop:Toggle()
  self:Build()
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self:Fit()
    self.frame:Show()
    self:SelectTab(self.tab or "CAMERA")
  end
end
