local _, AK = ...

-- Multiplayer deliberately uses only the sanctioned addon-message channel. It works
-- with party or raid members who also have Azeroth Kart enabled; it never controls
-- WoW characters or communicates with a third-party service.
AK.Net = { prefix = "AZK1", peers = {}, lobby = nil, inputClock = 0, snapshotClock = 0 }
local Net = AK.Net

--- Split a packet into its fields, KEEPING the empty ones.
---
--- This was gmatch("([^\t]+)"), which drops empties -- so a packet with a
--- blank field silently shifted every field after it one place left. The JOIN
--- handler already carries a note about a joiner "whose packet lost its racer
--- field", which is exactly this: the kart id slid into the racer slot and the
--- kart slot came back nil. Positional fields cannot be parsed by a splitter
--- that renumbers them. ApplySnapshot uses the client's own strsplit, which
--- does keep empties -- one file, two splitters, two behaviours.
local function split(message)
  local values = { strsplit("\t", message or "") }
  return values
end

--- A field, or the fallback when the packet did not carry one. An empty string
--- is TRUTHY in Lua, so `values[4] or "you"` never fired on a blank field --
--- only on a missing one, which after the split above no longer happens.
local function field(values, index, fallback)
  local value = values[index]
  if value == nil or value == "" then return fallback end
  return value
end

function Net:PlayerName()
  local name, realm = UnitFullName("player")
  return realm and realm ~= "" and name .. "-" .. realm or name
end

function Net:Channel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

function Net:Send(parts, channel, target)
  channel = channel or self:Channel()
  if not channel then
    AK:Print("Multiplayer needs a party or raid. Invite friends with the addon, then open a lobby.")
    return false
  end
  C_ChatInfo.SendAddonMessage(self.prefix, table.concat(parts, "\t"), channel, target)
  return true
end

function Net:BroadcastRoster()
  if not self.lobby then return end
  -- Individual roster packets keep party races safely below WoW's addon-message
  -- payload limit even when everyone in a full raid joins the grid.
  for name, player in pairs(self.lobby.roster) do
    self:Send({ "ROSTER", self.lobby.id, name, player.racer, player.kart })
  end
end

function Net:OpenLobby()
  local channel = self:Channel()
  if not channel then
    AK:Print("Invite addon users to your party or raid first.")
    return false
  end
  local id = tostring(math.floor(GetTime() * 1000)) .. tostring(math.random(100, 999))
  local localName = self:PlayerName()
  self.lobby = {
    id = id,
    host = localName,
    track = AK.db.selection.track,
    roster = { [localName] = { name = localName, racer = AK.db.selection.racer, kart = AK.db.selection.kart } },
  }
  self:Send({ "LOBBY", id, self.lobby.track, localName })
  self:BroadcastRoster()
  AK:Print("Multiplayer lobby open. Friends can join from /kart > Multiplayer.")
  return true
end

function Net:RefreshLobbies()
  if self:Send({ "FIND" }) then AK:Print("Looking for open Azeroth Kart lobbies...") end
end

function Net:JoinLobby()
  if not self.availableLobby then
    AK:Print("No party race lobby has been announced yet.")
    return
  end
  local invite = self.availableLobby
  self:Send({ "JOIN", invite.id, self:PlayerName(), AK.db.selection.racer, AK.db.selection.kart }, "WHISPER", invite.host)
end

function Net:StartLobbyRace()
  if not self.lobby then
    AK:Print("Open a lobby before starting a multiplayer race.")
    return
  end
  self:BroadcastRoster()
  self:Send({ "START", self.lobby.id, self.lobby.track })
  AK.Race:Start("multiplayer", { session = self.lobby.id, host = self:PlayerName(), roster = self.lobby.roster, isHost = true, track = self.lobby.track })
end

function Net:SendInput(race)
  if not race.network or race.network.isHost then return end
  self.inputClock = self.inputClock + race.delta
  if self.inputClock < .09 then return end
  self.inputClock = 0
  local c = race.controls
  self:Send({ "INPUT", race.network.session, self:PlayerName(), c.left and "1" or "0", c.right and "1" or "0", c.drift and "1" or "0", c.itemPulse and "1" or "0" }, "WHISPER", race.network.host)
end

-- WoW drops an addon message over 255 bytes on the floor, silently. The
-- snapshot used to flush every THREE vehicles regardless of how long those
-- three actually were, which is not a size limit -- it is a guess that happens
-- to hold for short names and short item ids. A full-length character name plus
-- two eighteen-character item ids ("triple_green_shell") puts one entry at 89
-- bytes; three of those plus the header is 292, and the whole snapshot vanishes
-- with no error anywhere. The player just sees the field stop moving.
--
-- So: items go on the wire as their AK.ItemIndex number rather than their name,
-- and the batch flushes on MEASURED length instead of a count.
--
-- The budget covers the whole message body -- "STATE", the session id and the
-- batch, joined by tabs -- not the batch alone. Sizing only the batch is how a
-- first attempt at this still overflowed: 240 bytes of entries plus a 23-byte
-- header is 263. The session id is the part whose length is not known up front,
-- so it is measured rather than assumed, and 250 leaves margin under the 255.
local MAX_MESSAGE = 250

function Net:BroadcastSnapshot(race)
  if not race.network or not race.network.isHost then return end
  self.snapshotClock = self.snapshotClock + race.delta
  if self.snapshotClock < .10 then return end
  self.snapshotClock = 0
  local batch, size = {}, 0
  local session = race.network.session
  -- "STATE" + tab + session + tab
  local budget = MAX_MESSAGE - (5 + 1 + #tostring(session) + 1)
  local function flush()
    if #batch == 0 then return end
    self:Send({ "STATE", session, table.concat(batch, "~") })
    wipe(batch)
    size = 0
  end
  for _, vehicle in ipairs(race.vehicles) do
    -- Held item and the hit-reaction timers ride along, or none of the new
    -- mechanics (trailing shields, spin-outs, airtime, shrinking) are visible
    -- to anyone but the host.
    local entry = table.concat({
      vehicle.networkId, math.floor(vehicle.distance), math.floor(vehicle.lateral * 100),
      math.floor(vehicle.speed * 10),
      vehicle.item and AK.ItemIndex[vehicle.item] or 0,
      math.floor((vehicle.boostTime or 0) * 10),
      vehicle.finished and "1" or "0",
      vehicle.held and AK.ItemIndex[vehicle.held] or 0,
      math.floor((vehicle.spin or 0) * 10), math.floor((vehicle.air or 0) * 10),
      math.floor((vehicle.shrunk or 0) * 10),
      -- WHICH ROAD that distance is measured along. `distance` is route-local
      -- and resets to 0 the moment a kart commits to a branch, so without this
      -- a racer taking a shortcut was drawn on everyone else's screen at the
      -- same number of metres along the MAIN line -- flung back to near the
      -- start and then snapping forward again when they rejoined. Harmless
      -- while three tracks had branches and nobody used them; now every track
      -- has one.
      (vehicle.route and vehicle.route ~= race.track and vehicle.route.index) or 0,
    }, ",")
    -- +1 for the "~" this entry will need once it is not the first.
    if size > 0 and size + #entry + 1 > budget then flush() end
    batch[#batch + 1] = entry
    size = size + #entry + 1
  end
  flush()
end

function Net:ApplySnapshot(race, data)
  if not race.network or race.network.isHost then return end
  for entry in string.gmatch(data or "", "([^~]+)") do
    local owner, distance, lateral, speed, item, boost, finished,
      held, spin, air, shrunk, routeIndex = strsplit(",", entry)
    local vehicle = race.byNetworkId[owner]
    if vehicle then
      -- Set the road BEFORE the distance, since the distance is measured along
      -- it. A packet from an older build has no route field, which reads as 0
      -- and puts the kart on the main line -- the old behaviour exactly.
      local branchIndex = tonumber(routeIndex) or 0
      local branches = race.track.branches
      vehicle.route = (branchIndex > 0 and branches and branches[branchIndex]) or race.track
      vehicle.distance = tonumber(distance) or vehicle.distance
      vehicle.lateral = (tonumber(lateral) or 0) / 100
      vehicle.speed = (tonumber(speed) or 0) / 10
      -- Items arrive as an AK.ItemIndex number; 0 is "none". A packet from an
      -- older build carrying a raw id or "-" tonumbers to nil and reads as no
      -- item, which is a cosmetic miss rather than a desync.
      vehicle.item = AK.ItemOrder[tonumber(item) or 0]
      vehicle.boostTime = (tonumber(boost) or 0) / 10
      vehicle.finished = finished == "1"
      -- Newer fields are optional so a client on an older build still races.
      vehicle.held = AK.ItemOrder[tonumber(held) or 0]
      vehicle.spin = (tonumber(spin) or 0) / 10
      vehicle.air = (tonumber(air) or 0) / 10
      vehicle.shrunk = (tonumber(shrunk) or 0) / 10
      -- The reaction animations need their peak value to ease from.
      if vehicle.spin > 0 then vehicle.spinMax = math.max(vehicle.spinMax or 0, vehicle.spin) end
      if vehicle.air > 0 then vehicle.airMax = math.max(vehicle.airMax or 0, vehicle.air) end
    end
  end
end

function Net:HandleMessage(message, sender)
  local values = split(message)
  local kind = values[1]
  if kind == "LOBBY" then
    self.availableLobby =
      { id = values[2], track = values[3], host = field(values, 4, sender) }
    if self.availableLobby.host ~= self:PlayerName() then AK:Print("Party race lobby found: " .. AK:GetTrack(values[3]).name .. ". Open /kart to join.") end
  elseif kind == "ROSTER" and self.availableLobby and self.availableLobby.id == values[2] then
    self.availableLobby.roster = self.availableLobby.roster or {}
    self.availableLobby.roster[values[3]] =
      { name = values[3], racer = field(values, 4, "you"), kart = field(values, 5, "mechano") }
  elseif kind == "JOIN" and self.lobby and values[2] == self.lobby.id then
    local name = values[3]
    if name and name ~= self:PlayerName() then
      local rosterSize = 0
      for _ in pairs(self.lobby.roster) do rosterSize = rosterSize + 1 end
      if not self.lobby.roster[name] and rosterSize >= AK.MAX_RACERS then
        self:Send({ "FULL", self.lobby.id }, "WHISPER", name)
        return
      end
      local isNew = not self.lobby.roster[name]
      -- "goblin" was a racer id from the original roster and no longer exists,
      -- so a joiner whose packet lost its racer field silently became Baine.
      self.lobby.roster[name] = { name = name,
        racer = field(values, 4, "you"), kart = field(values, 5, "mechano") }
      self:BroadcastRoster()
      if isNew then AK:Print(name .. " joined the pit lane.") end
    end
  elseif kind == "FIND" and self.lobby then
    self:Send({ "LOBBY", self.lobby.id, self.lobby.track, self.lobby.host })
    self:BroadcastRoster()
  elseif kind == "START" then
    if self.lobby and self.lobby.id == values[2] and self.lobby.host == self:PlayerName() then return end
    local roster = self.availableLobby and self.availableLobby.roster or {}
    if not roster[self:PlayerName()] then return end
    self.availableLobby = nil
    AK.Race:Start("multiplayer", { session = values[2], host = sender, roster = roster, isHost = false, track = values[3] })
  elseif kind == "INPUT" and AK.Race.current and AK.Race.current.network and AK.Race.current.network.isHost and values[2] == AK.Race.current.network.session then
    local race = AK.Race.current
    race.remoteInputs[values[3]] = { left = values[4] == "1", right = values[5] == "1", drift = values[6] == "1", itemPulse = values[7] == "1" }
  elseif kind == "STATE" and AK.Race.current and AK.Race.current.network and values[2] == AK.Race.current.network.session then
    self:ApplySnapshot(AK.Race.current, values[3])
  elseif kind == "FINISH" and AK.Race.current and AK.Race.current.network and values[2] == AK.Race.current.network.session then
    AK.Race:FinishFromHost(values[3])
  elseif kind == "FULL" then
    AK:Print("That multiplayer grid is already full.")
  end
end

function Net:Init()
  C_ChatInfo.RegisterAddonMessagePrefix(self.prefix)
end
