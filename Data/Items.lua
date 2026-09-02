local _, AK = ...

local ART = "Interface\\AddOns\\kart\\Art\\"

-- Power-ups are now archetypes you can recognise on sight, and most of them
-- spawn a real object on the track: you watch the shell leave your kart, travel
-- up the road and hit somebody. Previously an item applied an invisible stat
-- change and the only feedback was a line of text hidden behind your own kart.
AK.Items = {
  mushroom = {
    name = "Speed Mushroom", icon = ART .. "mushroom.tga", tier = "minor",
    color = { 1.0, 0.35, 0.30 },
    description = "Instant burst of speed.",
    effect = "boost",
  },
  banana = {
    name = "Banana", icon = ART .. "banana.tga", tier = "minor",
    color = { 1.0, 0.85, 0.20 },
    description = "Drops behind you. Spin out whoever hits it.",
    effect = "drop", reaction = "spin",
  },
  green_shell = {
    name = "Green Shell", icon = ART .. "shell.tga", tier = "normal",
    color = { 0.30, 0.95, 0.35 }, tint = { 0.30, 0.95, 0.35 },
    description = "Fires straight ahead. Hits the first racer in its path.",
    effect = "projectile", speed = 34, life = 6,
  },
  red_shell = {
    name = "Red Shell", icon = ART .. "shell.tga", tier = "strong",
    color = { 1.0, 0.28, 0.24 }, tint = { 1.0, 0.28, 0.24 },
    description = "Homes in on the racer ahead of you.",
    effect = "projectile", speed = 30, life = 7, homing = true,
  },
  bomb = {
    name = "Goblin Bomb", icon = ART .. "bomb.tga", tier = "strong",
    color = { 1.0, 0.60, 0.20 },
    description = "Lobbed forward. Catches everyone near the blast.",
    effect = "projectile", speed = 24, life = 5, blast = 11, reaction = "launch",
  },
  star = {
    name = "Star Power", icon = ART .. "star.tga", tier = "legendary",
    color = { 1.0, 0.85, 0.25 },
    description = "Untouchable and faster, for a while.",
    effect = "star", duration = 6,
  },
  bolt = {
    name = "Lightning", icon = ART .. "bolt.tga", tier = "legendary",
    color = { 1.0, 0.95, 0.35 },
    description = "Shrinks every racer ahead. Run the little ones over.",
    effect = "bolt",
  },
  -- Disguised as a real box. Its whole job is psychological: it works because
  -- players are trained to drive into anything that looks like a pickup.
  fake_box = {
    name = "Fake Item Box", icon = ART .. "itembox.tga", tier = "normal",
    color = { 0.75, 0.30, 0.95 },
    description = "Looks like an item box. Is not.",
    effect = "drop", reaction = "spin", fake = true,
  },
  -- Three separate activations, not three inventory slots. Where you spend
  -- each one is the decision.
  triple_mushroom = {
    name = "Triple Mushroom", icon = ART .. "mushroom.tga", tier = "strong",
    color = { 1.0, 0.35, 0.30 },
    description = "Three boosts. Spend them on shortcuts.",
    effect = "boost", quantity = 3,
  },
  -- The leader's problem. Ignores everyone else and goes for first place.
  spiny_shell = {
    name = "Spiny Shell", icon = ART .. "shell.tga", tier = "legendary",
    color = { 0.35, 0.45, 1.0 }, tint = { 0.35, 0.45, 1.0 },
    description = "Hunts whoever is in first.",
    effect = "projectile", speed = 44, life = 14, homing = true, seeksLeader = true,
    blast = 8, reaction = "launch",
  },
  -- Three shots, not three inventory slots -- same pattern as Triple Mushroom,
  -- just on the shells and the banana instead. These were the one obviously
  -- missing piece of the real item table: every kart racer that has a single
  -- shell or a single banana has the triple version of it too.
  triple_banana = {
    name = "Triple Banana", icon = ART .. "banana.tga", tier = "normal",
    color = { 1.0, 0.85, 0.20 },
    description = "Three bananas. Lay a trail, not just one peel.",
    effect = "drop", reaction = "spin", quantity = 3,
  },
  triple_green_shell = {
    name = "Triple Green Shell", icon = ART .. "shell.tga", tier = "strong",
    color = { 0.30, 0.95, 0.35 }, tint = { 0.30, 0.95, 0.35 },
    description = "Three shells, fired one at a time.",
    effect = "projectile", speed = 34, life = 6, quantity = 3,
  },
  triple_red_shell = {
    name = "Triple Red Shell", icon = ART .. "shell.tga", tier = "legendary",
    color = { 1.0, 0.28, 0.24 }, tint = { 1.0, 0.28, 0.24 },
    description = "Three homing shells. Clear a path through the whole field.",
    effect = "projectile", speed = 30, life = 7, homing = true, quantity = 3,
  },
  -- The steal. MK64's Boo does two things at once: it takes a banked item off
  -- someone else, and it makes you untouchable for a moment while you do it --
  -- the getaway is as much the point as the theft. Reusing `immune` (already
  -- top-priority in Race.HIT_PRIORITY, already respected by every hazard and
  -- projectile) gets the "cannot be punished for pulling this off" half for
  -- free; the steal itself is handled in AK:FireItem.
  boo = {
    name = "Boo", icon = "Interface\\Icons\\Ability_Vanish", tier = "legendary",
    color = { 0.62, 0.42, 0.92 },
    description = "Steals a banked item from the racer ahead. Untouchable while it works.",
    effect = "boo", immunity = 2.0,
  },
}

-- Stable order for the pickup roulette. pairs() order is undefined, and a reel
-- that jumps around at random reads as a glitch rather than a spin.
AK.ItemOrder = {
  "mushroom", "banana", "green_shell", "red_shell", "bomb",
  "triple_mushroom", "triple_banana", "triple_green_shell", "triple_red_shell",
  "fake_box", "spiny_shell", "boo", "star", "bolt",
}

-- Reverse lookup, for anything that has to say WHICH item in as few characters
-- as possible. The multiplayer snapshot is the caller that matters: it used to
-- put the raw id on the wire, and "triple_green_shell" is eighteen bytes of a
-- 255-byte addon message, twice over (carried item and held item). check.js
-- verifies this covers every entry in AK.Items, because an item missing from
-- the order would encode as nothing and arrive as nothing.
AK.ItemIndex = {}
for index, id in ipairs(AK.ItemOrder) do AK.ItemIndex[id] = index end

-- Each power-up gets its own voice, so you can tell what fired without looking.
AK.ITEM_SOUND = {
  mushroom = "boost",
  triple_mushroom = "boost",
  banana = "drop",
  triple_banana = "drop",
  fake_box = "drop",
  green_shell = "throw",
  triple_green_shell = "throw",
  red_shell = "throwHoming",
  triple_red_shell = "throwHoming",
  spiny_shell = "throwHoming",
  bomb = "throwHeavy",
  star = "starPower",
  bolt = "thunder",
  -- No dedicated cue exists for a steal yet; Audio.lua's fallback ("itemUse")
  -- covers it until one is authored and bound here.
}

--- Weighted draw. Trailing racers get the heavy hitters, the leader mostly gets
--- bananas and mushrooms -- the standard kart-racer rubber band.
-- Position-based item tiers. Mario Kart's comeback structure is not "random
-- item": the leader is meant to get defensive scraps and the tail is meant to
-- get race-changing weapons. Weights are per-tier and data-driven so they can
-- be tuned against reference play.
AK.ITEM_TABLE = {
  -- fraction of the field behind you -> weighted draw
  { upTo = 0.14, weights = {                                    -- 1st
    { value = "banana", weight = 42 }, { value = "green_shell", weight = 30 },
    { value = "mushroom", weight = 18 }, { value = "fake_box", weight = 10 },
    { value = "triple_banana", weight = 10 } } },
  { upTo = 0.35, weights = {                                    -- 2nd-3rd
    { value = "banana", weight = 24 }, { value = "green_shell", weight = 28 },
    { value = "red_shell", weight = 22 }, { value = "mushroom", weight = 16 },
    { value = "fake_box", weight = 10 }, { value = "triple_green_shell", weight = 10 } } },
  { upTo = 0.60, weights = {                                    -- midfield
    { value = "green_shell", weight = 18 }, { value = "red_shell", weight = 26 },
    { value = "mushroom", weight = 20 }, { value = "bomb", weight = 14 },
    { value = "banana", weight = 12 }, { value = "triple_mushroom", weight = 10 },
    { value = "triple_green_shell", weight = 8 }, { value = "boo", weight = 6 } } },
  { upTo = 0.82, weights = {                                    -- back half
    { value = "red_shell", weight = 20 }, { value = "triple_mushroom", weight = 22 },
    { value = "bomb", weight = 16 }, { value = "star", weight = 16 },
    { value = "bolt", weight = 10 }, { value = "spiny_shell", weight = 16 },
    { value = "triple_red_shell", weight = 14 }, { value = "boo", weight = 12 } } },
  { upTo = 1.01, weights = {                                    -- last
    { value = "star", weight = 24 }, { value = "bolt", weight = 20 },
    { value = "spiny_shell", weight = 22 }, { value = "triple_mushroom", weight = 22 },
    { value = "bomb", weight = 12 }, { value = "triple_red_shell", weight = 18 },
    { value = "boo", weight = 16 } } },
}

--- Weighted draw from the tier matching your race position.
--- How much help the GAP says you need, on top of what your rank says.
---
--- Rank alone makes the item box a lottery you have already won or lost by
--- standing where you stand. The gap is what turns it into a decision:
---
---   * A leader twenty seconds clear is not in a race, and handing them a
---     weapon is handing it to nobody. Their cushion pushes them further UP the
---     table, toward the pure-defensive end.
---   * Being ADRIFT is the case the comeback structure exists for, so a long
---     gap to the racer ahead pushes down the table toward the race-changers.
---   * Being on somebody's BUMPER is the opposite: two seconds back you do not
---     need a nuke, you need something precise you can place right now. That
---     pulls slightly up the table, to shells and mushrooms.
---
--- Returned as an offset on `trailing`, deliberately small. This modulates the
--- rank-based structure; it must never overturn it, or the leader starts
--- drawing spiny shells whenever somebody closes on them.
local function gapNeed(position, gapAhead, gapBehind)
  if position <= 1 then
    -- Inverted for the leader: a big cushion means LESS, not more.
    return -AK.Math.Clamp((gapBehind or 0) / 12, 0, 1) * 0.10
  end
  return AK.Math.Clamp(((gapAhead or 3) - 2.5) / 14, -0.08, 0.16)
end

function AK:RollItem(position, total, luck, stream, gapAhead, gapBehind)
  local trailing = (position - 1) / math.max(1, total - 1)
  -- Luck nudges you one notch further down the table, no more.
  trailing = math.min(1.0, trailing + ((luck or 5) - 5) * 0.012)
  trailing = AK.Math.Clamp(trailing + gapNeed(position, gapAhead, gapBehind), 0, 1.0)
  local tier = self.ITEM_TABLE[#self.ITEM_TABLE]
  for _, entry in ipairs(self.ITEM_TABLE) do
    if trailing <= entry.upTo then tier = entry break end
  end
  if stream then return stream:Weighted(tier.weights) end
  -- Fallback for any caller without a race stream.
  local total_ = 0
  for _, e in ipairs(tier.weights) do total_ = total_ + e.weight end
  local roll = math.random() * total_
  for _, e in ipairs(tier.weights) do
    roll = roll - e.weight
    if roll <= 0 then return e.value end
  end
  return "banana"
end

-- Anything you can trail behind the kart before firing. Instant effects
-- (mushroom, star, lightning) always fire on the spot.
AK.DEPLOYABLE = {
  banana = true, green_shell = true, red_shell = true, bomb = true,
  fake_box = true, spiny_shell = true,
  triple_banana = true, triple_green_shell = true, triple_red_shell = true,
}

--- Items with multiple activations report how many are left.
function AK:ItemCount(vehicle)
  return vehicle.itemCount or 1
end

--- Consume one activation. Returns true when the slot is now empty.
function AK:ConsumeItem(vehicle)
  local remaining = (vehicle.itemCount or 1) - 1
  if remaining > 0 then
    vehicle.itemCount = remaining
    return false
  end
  vehicle.item, vehicle.itemCount = nil, nil
  return true
end

--- Kart-racer item flow: the first press *deploys* the item so it trails your
--- kart, where it shields you from one hit and can be aimed; the second press
--- fires it. Holding also frees the slot, so you can bank a second item.
function AK:TriggerItem(race, vehicle)
  if vehicle.itemCooldown and vehicle.itemCooldown > 0 then return false end
  -- Already trailing something: this press launches it.
  if vehicle.held then
    local id = vehicle.held
    vehicle.held = nil
    vehicle.itemCooldown = .25
    return self:FireItem(race, vehicle, id)
  end
  local id = vehicle.item
  if not id or not self.Items[id] then return false end
  if AK.DEPLOYABLE[id] then
    -- Multi-activation items deploy one at a time and keep the rest banked.
    self:ConsumeItem(vehicle)
    vehicle.held = id
    vehicle.itemCooldown = .22
    if vehicle == race.player then
      local item = self.Items[id]
      AK.RaceUI:Announce(item.name:upper() .. " READY", item.color, item.icon)
      if AK.PlaySfx then AK:PlaySfx("deploy") end
    end
    return true
  end
  self:ConsumeItem(vehicle)
  vehicle.itemCooldown = .35
  return self:FireItem(race, vehicle, id)
end

function AK:FireItem(race, vehicle, id)
  if not id or not self.Items[id] then return false end
  local item = self.Items[id]
  local isPlayer = (vehicle == race.player)

  if item.effect == "boost" then
    vehicle.boostTime = math.max(vehicle.boostTime or 0, 2.0)
    vehicle.speed = math.max(vehicle.speed, vehicle.maxSpeed * 1.20)

  elseif item.effect == "star" then
    vehicle.star = math.max(vehicle.star or 0, item.duration)
    vehicle.boostTime = math.max(vehicle.boostTime or 0, item.duration)
    vehicle.usedStar = true

  elseif item.effect == "bolt" then
    -- Everyone in front of you, all at once.
    local struck = 0
    for _, other in ipairs(race.vehicles) do
      if other ~= vehicle and not other.finished and (other.star or 0) <= 0
        and AK.Race:IsAhead(race, vehicle, other) then
        -- Lightning shrinks rather than just slowing: everyone ahead is left
        -- tiny and slow, and anyone full-size who catches them flattens them.
        AK.Race:SlowVehicle(other, 1.2, "STRUCK BY LIGHTNING", "squash")
        other.shrunk = math.max(other.shrunk or 0, 8)
        struck = struck + 1
      end
    end
    if isPlayer then AK.RaceUI:Flash({ 1, 1, .7 }, .34) end

  elseif item.effect == "boo" then
    -- Steal whatever the racer directly ahead is banking -- their queued item
    -- if they have one, otherwise whatever they have trailing as a shield --
    -- and vanish from every hazard and projectile for a beat regardless of
    -- whether there was anything to take. `ConsumeItem` already cleared this
    -- vehicle's own slot before FireItem ran, so it is safe to hand the loot
    -- straight into `vehicle.item` here.
    local target = AK.Race:GetAheadTarget(vehicle)
    local stolen = target and (target.item or target.held)
    if stolen then
      if target.held == stolen then target.held = nil else target.item, target.itemCount = nil, nil end
      vehicle.item = stolen
      vehicle.itemCount = AK.Items[stolen] and AK.Items[stolen].quantity or 1
      if target == race.player then
        AK.RaceUI:Announce("BOO STOLE YOUR ITEM!", AK.COLORS.danger)
        AK.RaceUI:Flash({ .62, .42, .92 }, .18)
      elseif isPlayer then
        AK.RaceUI:Announce("STOLE " .. AK.Items[stolen].name:upper() .. "!", item.color)
      end
    end
    vehicle.immune = math.max(vehicle.immune or 0, item.immunity or 2.0)

  elseif item.effect == "drop" then
    AK.Race:SpawnProjectile(race, vehicle, id, -1)

  elseif item.effect == "projectile" then
    -- Directional throw: holding back fires it behind you. Being able to shoot
    -- a shell backwards at whoever is hounding you is half of what makes shells
    -- a defensive tool rather than only an offensive one.
    local backward = AK.Race.controls.brake or AK.Race.controls.aimBack
    AK.Race:SpawnProjectile(race, vehicle, id, (backward and vehicle == race.player) and -1 or 1)
  end

  if isPlayer then
    -- Loud, unmissable confirmation: banner, launch flash, expanding shockwave,
    -- spark ring, screen flash and a kick. This used to be a line of text drawn
    -- behind the player's own kart.
    local legendary = item.tier == "legendary"
    AK.RaceUI:Announce(item.name:upper() .. "!", item.color, item.icon)
    AK.RaceUI:Flash(item.color, legendary and .22 or .13)
    AK.RaceUI:Shake(legendary and 14 or 8)
    AK.RaceUI:LaunchEffect(item.color, legendary)
    AK.RaceUI:ItemBurst(item.color)
    if item.effect == "star" then
      -- Star gets a second, slower bloom so it reads as a state, not a hit.
      AK.RaceUI:PlayEffect("bloom", 0, 0, 900, item.color)
    elseif item.effect == "bolt" then
      -- Lightning sweeps the whole screen.
      AK.RaceUI:PlayEffect("shock", 0, 0, 1400, item.color)
    end
  end
  if AK.PlaySfx then AK:PlaySfx(AK.ITEM_SOUND[id] or "itemUse") end
  return true
end
