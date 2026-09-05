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

--- THE LOBBY SCREEN IS LIVE, OR IT IS USELESS.
---
--- Every readout on PARTY & RAID RACING was refreshed only when the local
--- player pressed something. So the host opened a lobby, a friend joined, and
--- the host's screen went on saying "1 racer ready" until they walked out of it
--- and back in -- and the joiner, whose whole question is "did that work", got
--- nothing at all. Every handler that moves lobby state calls this.
function Net:LobbyChanged()
  local menu = AK.Menu
  if not (menu and menu.frame and menu.frame:IsShown()) then return end
  local page = menu.pages and menu.pages.multiplayer
  if page and page.akRefresh and page:IsShown() then page:akRefresh() end
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
    -- ONCE EVERY FEW SECONDS, NOT SIX TIMES A SECOND. Leaving the party in the
    -- middle of a hosted race does not stop the snapshot loop -- it just makes
    -- every send fail -- so this printed the same sentence into chat at the
    -- snapshot rate until the race ended.
    local now = GetTime()
    if not self.lastChannelWarning or now - self.lastChannelWarning > 5 then
      self.lastChannelWarning = now
      AK:Print("Multiplayer needs a party or raid. Invite friends with the addon, then open a lobby.")
    end
    return false
  end
  C_ChatInfo.SendAddonMessage(self.prefix, table.concat(parts, "\t"), channel, target)
  return true
end

--- Tell everyone who is on the grid.
---
--- ONE PACKET PER MEMBER WAS A BURST WAITING TO HAPPEN. This fired the whole
--- roster on every join, so the eighth person joining an eight-kart lobby set
--- off eight messages at once -- and eight people joining in the same few
--- seconds is sixty-four, which is exactly the shape of traffic the server
--- throttles. Batched to the same 250-byte ceiling the snapshot uses, an eight
--- kart roster is two packets.
function Net:BroadcastRoster()
  if not self.lobby then return end
  local id = self.lobby.id
  local header = 6 + 1 + #tostring(id) + 1     -- "ROSTER" + tab + id + tab
  local batch, size = {}, 0
  local function flush()
    if #batch == 0 then return end
    self:Send({ "ROSTER", id, table.concat(batch, "~") })
    wipe(batch)
    size = 0
  end
  -- Sorted, so the packets are the same every time and a re-broadcast does not
  -- reshuffle which member lands in which message.
  local names = {}
  for name in pairs(self.lobby.roster) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local player = self.lobby.roster[name]
    local entry = table.concat({ name, player.racer or "you", player.kart or "mechano" }, ",")
    if size > 0 and header + size + #entry + 1 > 250 then flush() end
    batch[#batch + 1] = entry
    size = size + #entry + 1
  end
  flush()
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
  self:LobbyChanged()
  AK:Print("Multiplayer lobby open. Friends can join from /kart > Multiplayer.")
  return true
end

--- The host is leaving a race in progress.
---
--- Clients notice a silent host after eight seconds, which is the safety net
--- for a crash or a disconnect. When the host quits deliberately there is no
--- reason to make everybody sit through it.
function Net:AnnounceHostLeft(race)
  if not race or not race.network or not race.network.isHost then return end
  self:Send({ "HOSTGONE", race.network.session })
end

--- Stop hosting, and tell the party so their screens stop offering it.
---
--- There was no way to do this at all. A lobby opened once stayed open for the
--- rest of the session: the host's screen said HOSTING forever, START HOST RACE
--- kept working with a roster that might be half people who had logged out, and
--- everyone else's screen kept advertising a lobby that no longer meant
--- anything. Leaving a lobby is a thing people do.
function Net:CloseLobby()
  if not self.lobby then
    -- Not hosting: this is the button that clears somebody else's stale
    -- announcement off your own screen.
    if self.availableLobby then
      self.availableLobby = nil
      AK:Print("Forgot the announced lobby.")
      self:LobbyChanged()
      return true
    end
    AK:Print("You are not hosting a lobby.")
    return false
  end
  self:Send({ "CLOSED", self.lobby.id })
  self.lobby = nil
  AK:Print("Lobby closed.")
  self:LobbyChanged()
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
  if self:Send({ "JOIN", invite.id, self:PlayerName(), AK.db.selection.racer, AK.db.selection.kart }, "WHISPER", invite.host) then
    -- SAY SOMETHING. Joining printed nothing, showed nothing and changed
    -- nothing on screen: the host got "X joined the pit lane" and the person
    -- who actually pressed the button had no way to tell whether it had
    -- worked. The confirmation proper arrives when the host's roster comes
    -- back with this name in it, which the ROSTER handler reports.
    AK:Print("Asking " .. tostring(invite.host) .. " for a place on the grid...")
  end
end

function Net:StartLobbyRace()
  if not self.lobby then
    AK:Print("Open a lobby before starting a multiplayer race.")
    return
  end
  self:BroadcastRoster()
  -- The seed goes on the wire as well as being derivable from the session id.
  -- Derivation is the safety net for a packet that never arrives or a client on
  -- an older build; this is the authoritative copy, so the host stays the one
  -- deciding what the grid looks like.
  local seed = AK.RNG:SeedFrom(self.lobby.id)
  self:Send({ "START", self.lobby.id, self.lobby.track, tostring(seed) })
  AK.Race:Start("multiplayer", { session = self.lobby.id, host = self:PlayerName(),
    roster = self.lobby.roster, isHost = true, track = self.lobby.track, seed = seed })
end

--- THE THROTTLE GOES ON THE WIRE.
---
--- This carried left, right, drift and the item press, and nothing else -- so
--- the host, which is authoritative, drove every remote player with a control
--- table that had no `accelerate` and no `brake` in it. Physics treats a
--- missing throttle as "held", so a joiner on the host's machine was
--- permanently flat out: they could steer and they could drift, and lifting off
--- or braking did nothing at all. Their own client predicts WITH the throttle
--- (`throttleAware`), so the moment they lifted, the picture in front of them
--- and the state the host was actually simulating pulled apart, and the next
--- snapshot snapped them forward again.
function Net:SendInput(race)
  if not race.network or race.network.isHost then return end
  self.inputClock = self.inputClock + race.delta
  if self.inputClock < .09 then return end
  self.inputClock = 0
  local c = race.controls
  self:Send({ "INPUT", race.network.session, self:PlayerName(),
    c.left and "1" or "0", c.right and "1" or "0", c.drift and "1" or "0",
    c.itemPulse and "1" or "0",
    c.accelerate and "1" or "0", c.brake and "1" or "0" }, "WHISPER", race.network.host)
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

-- HOW MUCH THE ADDON CHANNEL WILL ACTUALLY CARRY.
--
-- Addon chat is rate limited by the server, and going over it does not produce
-- an error: messages are dropped, or the client is disconnected for spamming.
-- The figure the whole addon ecosystem is built around -- it is what
-- ChatThrottleLib holds itself to -- is 800 bytes a second.
--
-- Measured, once something finally counted: a hosted eight-kart race was
-- sending TWO THOUSAND NINE HUNDRED. The host of every full grid was on course
-- to be throttled or kicked, and the failure would have looked like "the other
-- karts stopped moving", which is unfixable from inside the game.
--
-- Three things bring it down, and a fourth guarantees it:
--   a kart is addressed by its GRID INDEX rather than by "Name-Realm", which
--   is twenty-odd bytes ten times a second per kart, and is only safe now that
--   every client provably builds the same grid from the same seed;
--   trailing zeros are dropped, and a kart that is not holding, spinning,
--   flying or shrinking is almost all trailing zeros;
--   snapshots go out at 6.7Hz instead of 10Hz -- clients dead-reckon between
--   them, so this is invisible;
--   and the governor below simply refuses to send once the second's budget is
--   spent, whatever the grid size turns out to be.
local WIRE_BUDGET = 800
local SNAPSHOT_PERIOD = 0.15

--- Bytes sent in the last rolling second, and whether there is room for more.
function Net:WireRoom(bytes)
  local now = GetTime()
  if not self.wireWindow or now - self.wireWindow >= 1 then
    self.wireWindow, self.wireSpent = now, 0
  end
  return (self.wireSpent or 0) + bytes <= WIRE_BUDGET
end

function Net:WireSpend(bytes)
  self.wireSpent = (self.wireSpent or 0) + bytes
end

--- Drop trailing zeros from a snapshot entry. ApplySnapshot already defaults
--- every optional field, so a shorter row means exactly the same thing.
local function trimZeros(fields)
  local last = #fields
  while last > 4 and (fields[last] == "0" or fields[last] == 0) do last = last - 1 end
  local out = {}
  for i = 1, last do out[i] = fields[i] end
  return table.concat(out, ",")
end

function Net:BroadcastSnapshot(race)
  if not race.network or not race.network.isHost then return end
  self.snapshotClock = self.snapshotClock + race.delta
  if self.snapshotClock < SNAPSHOT_PERIOD then return end
  self.snapshotClock = 0
  local batch, size = {}, 0
  local session = race.network.session
  -- "STATE" + tab + session + tab
  local header = 5 + 1 + #tostring(session) + 1
  local budget = MAX_MESSAGE - header
  local function flush()
    if #batch == 0 then return end
    local body = table.concat(batch, "~")
    -- The governor. A skipped snapshot costs a client a sixth of a second of
    -- dead reckoning; a throttled host costs everyone the race.
    if self:WireRoom(header + #body) then
      self:WireSpend(header + #body)
      self:Send({ "STATE", session, body })
    end
    wipe(batch)
    size = 0
  end
  for slot, vehicle in ipairs(race.vehicles) do
    -- Held item and the hit-reaction timers ride along, or none of the new
    -- mechanics (trailing shields, spin-outs, airtime, shrinking) are visible
    -- to anyone but the host.
    local entry = trimZeros({
      -- THE GRID SLOT, not the name. Every client sorts the roster the same way
      -- and fills the rest from the same seed, so slot N is the same kart on
      -- every machine -- and a slot is one byte where "Aaaaaaaaaaaa-Proudmoore"
      -- is twenty-three, ten times a second, for every kart on the grid.
      slot, math.floor(vehicle.distance), math.floor(vehicle.lateral * 100),
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
    })
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
    -- EITHER FORM. A slot is a bare integer; a networkId is "Name-Realm" or
    -- "ai3", and neither can ever be one. So a client on this build understands
    -- a host on the previous one, and a host on this build addressing a slot an
    -- older client cannot resolve leaves that kart dead-reckoning rather than
    -- drawing it somewhere wrong.
    local slot = tonumber(owner)
    local vehicle = (slot and race.vehicles and race.vehicles[slot])
      or race.byNetworkId[owner]
    if vehicle then
      -- Set the road BEFORE the distance, since the distance is measured along
      -- it. A packet from an older build has no route field, which reads as 0
      -- and puts the kart on the main line -- the old behaviour exactly.
      local branchIndex = tonumber(routeIndex) or 0
      local branches = race.track.branches
      vehicle.route = (branchIndex > 0 and branches and branches[branchIndex]) or race.track
      vehicle.distance = tonumber(distance) or vehicle.distance
      -- LATERAL IS A TARGET, NOT A TELEPORT. Dead reckoning carries `distance`
      -- forward at the last known speed between packets, so distance moves
      -- smoothly -- but nothing carried `lateral`, so a kart weaving across the
      -- road jumped sideways once per snapshot. At ten a second that read as
      -- jitter; at the slower rate the wire budget allows it would read as
      -- teleporting. Race:DeadReckon eases toward this.
      local want = (tonumber(lateral) or 0) / 100
      vehicle.netLateral = want
      if not vehicle.lateral or math.abs(want - vehicle.lateral) > 0.9 then
        -- A correction that large is not a weave, it is a respawn or a fork.
        vehicle.lateral = want
      end
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
  -- YOUR OWN PARTY MESSAGES COME BACK TO YOU.
  --
  -- CHAT_MSG_ADDON fires for what you sent as well as for what you received, so
  -- opening a lobby announced it to yourself: the LOBBY handler filed your own
  -- lobby as an AVAILABLE one, and the roster broadcast that followed then told
  -- the host "You are on the grid. Waiting for the host to start." There is
  -- nothing in your own broadcast you do not already know.
  if sender and sender == self:PlayerName() then return end
  local values = split(message)
  local kind = values[1]
  if kind == "LOBBY" then
    self.availableLobby =
      { id = values[2], track = values[3], host = field(values, 4, sender) }
    if self.availableLobby.host ~= self:PlayerName() then AK:Print("Party race lobby found: " .. AK:GetTrack(values[3]).name .. ". Open /kart to join.") end
    self:LobbyChanged()
  elseif kind == "ROSTER" and self.availableLobby and self.availableLobby.id == values[2] then
    self.availableLobby.roster = self.availableLobby.roster or {}
    local me = self:PlayerName()
    local first = false
    -- EITHER FORM. A batched body carries commas; the old one-member-per-packet
    -- form put the name in field 3 on its own, and a WoW name cannot contain a
    -- comma -- so a host on the previous build is still understood.
    local body = values[3] or ""
    if body:find(",", 1, true) then
      for entry in body:gmatch("([^~]+)") do
        local name, racer, kart = strsplit(",", entry)
        if name and name ~= "" then
          if name == me and not self.availableLobby.roster[name] then first = true end
          self.availableLobby.roster[name] = { name = name,
            racer = (racer ~= "" and racer) or "you",
            kart = (kart ~= "" and kart) or "mechano" }
        end
      end
    elseif body ~= "" then
      if body == me and not self.availableLobby.roster[body] then first = true end
      self.availableLobby.roster[body] =
        { name = body, racer = field(values, 4, "you"), kart = field(values, 5, "mechano") }
    end
    -- The host's roster coming back with your own name on it is the only
    -- confirmation there is that you are actually in the race.
    if first then
      AK:Print("|cff6bf06bYou are on the grid.|r Waiting for the host to start.")
    end
    self:LobbyChanged()
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
      self:LobbyChanged()
    end
  elseif kind == "FIND" and self.lobby then
    self:Send({ "LOBBY", self.lobby.id, self.lobby.track, self.lobby.host })
    self:BroadcastRoster()
  elseif kind == "START" then
    if self.lobby and self.lobby.id == values[2] and self.lobby.host == self:PlayerName() then return end
    -- TWO PEOPLE BOTH PRESSED OPEN LOBBY. It happens: the button is the first
    -- one on the screen. Whoever starts second should not be dragged into the
    -- other person's race, and should certainly not be told theirs "started
    -- without them" -- they are hosting their own.
    if self.lobby then return end
    local roster = self.availableLobby and self.availableLobby.roster or {}
    -- LEFT BEHIND IN SILENCE. If the roster never came back with this player on
    -- it -- they never pressed JOIN, or the reply was dropped -- the race
    -- started for everybody else and this client did nothing whatsoever: no
    -- message, no screen change, just a menu while their friends drove off. Say
    -- what happened and what to do about it.
    if not roster[self:PlayerName()] then
      if self.availableLobby and self.availableLobby.id == values[2] then
        AK:Print("|cffff5555The race started without you.|r You are not on that "
          .. "lobby's grid -- press JOIN ANNOUNCED LOBBY before the host starts.")
      end
      return
    end
    self.availableLobby = nil
    AK.Race:Start("multiplayer", { session = values[2], host = sender, roster = roster,
      isHost = false, track = values[3], seed = tonumber(values[4]) })
  elseif kind == "INPUT" and AK.Race.current and AK.Race.current.network and AK.Race.current.network.isHost and values[2] == AK.Race.current.network.session then
    local race = AK.Race.current
    -- A packet from a build that predates the throttle fields has nothing in
    -- slot 8, and the honest answer for it is the old behaviour -- held down --
    -- rather than a kart that will not move. `throttleAware` is what tells
    -- Physics to obey the flag at all, so it is only set when the flag is
    -- really there.
    local throttled = values[8] ~= nil and values[8] ~= ""
    -- WHEN, as well as what. A player who alt-tabs, disconnects or walks out
    -- of range stops sending, and their kart was left with the last table they
    -- ever sent -- which physics reads as the throttle held down, so an absent
    -- player's kart drove into the scenery at full speed for the rest of the
    -- race. Race:Step hands a kart nobody is driving back to the AI.
    race.remoteHeard = race.remoteHeard or {}
    race.remoteHeard[values[3]] = GetTime()
    race.remoteInputs[values[3]] = {
      left = values[4] == "1", right = values[5] == "1",
      drift = values[6] == "1", itemPulse = values[7] == "1",
      accelerate = (not throttled) or values[8] == "1",
      brake = values[9] == "1",
      throttleAware = throttled,
    }
  elseif kind == "STATE" and AK.Race.current and AK.Race.current.network and values[2] == AK.Race.current.network.session then
    AK.Race.current.lastSnapshot = GetTime()
    self:ApplySnapshot(AK.Race.current, values[3])
  elseif kind == "FINISH" and AK.Race.current and AK.Race.current.network and values[2] == AK.Race.current.network.session then
    AK.Race:FinishFromHost(values[3])
  elseif kind == "HOSTGONE" then
    local race = AK.Race.current
    if race and race.network and not race.network.isHost
      and race.network.session == values[2] then
      AK:Print("|cffff5555The host left the race.|r")
      AK.RaceUI:Announce("HOST LEFT THE RACE", AK.COLORS.danger)
      AK.Race:Stop(true)
    end
  elseif kind == "CLOSED" then
    if self.availableLobby and self.availableLobby.id == values[2] then
      self.availableLobby = nil
      AK:Print("The party race lobby was closed.")
      self:LobbyChanged()
    end
  elseif kind == "FULL" then
    AK:Print("That multiplayer grid is already full.")
  end
end

function Net:Init()
  C_ChatInfo.RegisterAddonMessagePrefix(self.prefix)
end
