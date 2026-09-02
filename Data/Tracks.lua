local _, AK = ...

-- Every track must have its own CHARACTER, not just different names on the same
-- template. MK64's secret is that Luigi Raceway, Bowser's Castle and Rainbow
-- Road feel like completely different games. That means different RHYTHM: some
-- tracks are mostly gentle sweeps (beginner), some are all hairpins (expert),
-- some are wide-open speed runs with one terrifying choke point.
--
-- The old layouts were cookie-cutter: 230m straight, turn, hairpin, ramp,
-- tunnel, esses, hairpin, straight. Same curve values, same widths, same
-- segment count. The result was seven identical-feeling tracks with different
-- skyboxes.
--
-- Key variety levers:
--   Segment count:   14 (simple) to 21 (complex)
--   Turn lengths:    50m snap-turn to 260m flowing sweep
--   Consecutive same-direction turns (winding vs alternating)
--   Width profiles:  Deadmines is narrow everywhere, Netherstorm is wide
--   Ramp count:      0 to 3 per lap
--   Tunnel coverage: Elwynn has 100m, Deadmines has 550m+
--   Number of hairpins: Elwynn has 1, Durotar has 4
AK.Tracks = {
  -- ================================================================
  -- ORIBOS RING RUN -- The showcase. Flowing and grand, not technical.
  -- Two consecutive right turns early on create the circular ring feel.
  -- One hairpin, one ramp, one long tunnel. MK64 analogue: Royal Raceway.
  -- ================================================================
  {
    id = "oribos", name = "Oribos Ring Run", subtitle = "The Eternal City, at speed", theme = "ORIBOS",
    style = "oribos", sweep = 3.2,
    length = 2600, laps = 3, color = { 0.17, 0.13, 0.26 }, road = { 0.50, 0.46, 0.42 },
    skyTop = { 0.05, 0.03, 0.12 }, skyLow = { 0.38, 0.22, 0.55 }, glow = { 0.55, 0.85, 1.00 },
    weather = "ember", light = 0.86, archSpacing = 150,
    hazardPlan = {
      { kind = "patrol", name = "Attendant", count = 3, at = 0.18, spacing = 210, sweep = 0.75, radius = 3.2,
        model = { creature = 165498 }, icon = "Interface\\Icons\\Spell_Animabastion_Buff" },
    },
    offroad = "SCREE",
    surfaces = {
      { from = 1160, to = 1490, onRoad = "ICE" },
      { from = 1730, to = 1960, onRoad = "BOOST" },
    },
    layout = {
      { len = 260, curve = 0, name = "Ring of Fates Straight", width = 1.30 },
      -- Two RIGHT turns in a row: you are driving around the ring.
      { len = 210, curve = 1.8, name = "Ring Sweep", width = 1.10 },
      { len = 150, curve = 1.2, name = "Ring Inner", width = 1.06 },
      { len = 100, curve = -0.4, name = "Enclave Approach", width = 1.12 },
      -- The only tight corner on the lap.
      { len = 80, curve = -4.0, name = "Attendant Hairpin", width = 0.78 },
      { len = 180, curve = 0.6, grade = 3.0, name = "Anima Climb", width = 1.04 },
      { len = 55, curve = 0, grade = 6.0, ramp = true, name = "The Leap", width = 1.22 },
      { len = 90, curve = 0, grade = -4.8, name = "Leap Landing", width = 1.16 },
      -- The signature: 320m under the ring. Gentle curve so it is driveable
      -- even though you cannot see anything.
      { len = 130, curve = 0.4, name = "Arcade Entry", width = 1.00, tunnel = true },
      { len = 190, curve = 2.2, name = "Gilded Arcade", width = 0.94, tunnel = true },
      { len = 100, curve = -0.8, name = "Arcade Exit", width = 1.08 },
      { len = 60, curve = -3.2, name = "Broker Chicane", width = 0.84 },
      { len = 60, curve = 3.2, name = "Broker Chicane II", width = 0.84 },
      -- Long overtaking zone after the technical bit.
      { len = 280, curve = 0, name = "Vault Straight", width = 1.28 },
      { len = 200, curve = 2.4, grade = -1.8, name = "Great Vault Curve", width = 0.96 },
      { len = 140, curve = -1.0, name = "Final Approach", width = 1.10 },
      { len = 230, curve = 0, name = "Home Straight", width = 1.30 },
    },
    hazards = { "Anima Surge", "Broker Crate", "Attendant" },
    shortcut = "Cut the inner ring past the Ring of Fates.",
    branches = {
      {
        id = "inner_ring", name = "Inner Ring", side = -1,
        from = 0.060, to = 0.200, length = 268, sweep = 1.5,
        offroad = "SCREE",
        surfaces = {
          { from = 150, to = 214, onRoad = "BOOST" },
        },
        layout = {
          { len = 44, curve = -1.2, name = "Inner Ring", width = 0.70 },
          { len = 58, curve = -3.4, width = 0.62 },
          { len = 40, curve = 1.8, width = 0.66 },
          { len = 64, curve = 2.6, width = 0.70 },
          { len = 62, curve = -1.0, width = 0.78 },
        },
      },
    },
  },
  -- ================================================================
  -- ELWYNN SPRINT -- The beginner track. Almost all gentle curves, wide
  -- road, only ONE hard corner. MK64 analogue: Luigi Raceway / Moo Moo Farm.
  -- ================================================================
  {
    id = "elwynn", name = "Elwynn Sprint", subtitle = "Goldshire's fastest commute", theme = "ELWYNN FOREST",
    sweep = 2.0,
    length = 2400, laps = 3, color = { 0.19, 0.43, 0.20 }, road = { 0.62, 0.53, 0.34 },
    skyTop = { 0.24, 0.46, 0.82 }, skyLow = { 0.72, 0.86, 0.97 }, glow = { 1.00, 0.93, 0.72 },
    weather = "none", light = 1.00,
    hazardPlan = {
      { kind = "patrol", name = "Kobold", count = 3, at = 0.22, spacing = 190, sweep = 0.8, radius = 3.0,
        model = { creature = 6 }, icon = "Interface\\Icons\\INV_Misc_Candle_01" },
    },
    offroad = "GRASS",
    surfaces = {
      { from = 1200, to = 1440, offroad = "WATER" },
      { from = 1920, to = 2088, onRoad = "MUD" },
    },
    -- Beginner does not mean EMPTY. Measured, this lap used to be 71% road the
    -- wheel wins outright, with a 658m unbroken flat-out run -- a quarter of the
    -- lap on which the only correct input is "hold the throttle" -- and only 14%
    -- of it firm enough for a mini-turbo to charge. Luigi Raceway is an easy
    -- track; it is not a track where the drift button does nothing.
    --
    -- So the corners keep their shape and their names and stay wide and
    -- forgiving, but every sweeper is firmed up to where a drift is worth
    -- taking, and the home straight is broken by a kink. Nothing here is a
    -- hairpin: Stonefield is still the only hard corner on the lap.
    layout = {
      { len = 200, curve = 0, name = "Goldshire Straight", width = 1.30 },
      -- A long sweep, now firm enough to be worth drifting rather than merely
      -- worth looking at.
      { len = 200, curve = -1.7, name = "Lion's Pride Sweep", width = 1.14 },
      { len = 100, curve = 1.5, name = "Mill Lane", width = 1.12 },
      { len = 120, curve = -1.2, grade = 2.4, name = "Hill Road", width = 1.10 },
      { len = 45, curve = 0, grade = 4.0, ramp = true, name = "Bridge Jump", width = 1.20 },
      { len = 80, curve = 0, grade = -3.0, name = "Bridge Landing", width = 1.14 },
      { len = 100, curve = 1.4, name = "Covered Bridge", width = 0.96, tunnel = true },
      { len = 240, curve = 1.9, name = "Forest Sweep", width = 1.08 },
      -- Still the one real challenge on the lap.
      { len = 80, curve = 3.6, name = "Stonefield Bend", width = 0.84 },
      { len = 140, curve = -1.5, name = "Eastvale Run", width = 1.18 },
      { len = 180, curve = -1.6, grade = -1.2, name = "Crystal Lake", width = 1.12 },
      { len = 120, curve = 0, name = "Woodland Straight", width = 1.22 },
      { len = 160, curve = 1.8, name = "Forest Curve", width = 1.10 },
      -- The kink that stops the run to the line being a quarter of the lap with
      -- nothing in it.
      { len = 90, curve = -2.2, name = "Smithy Kink", width = 1.00 },
      { len = 190, curve = 0, name = "Home Straight", width = 1.30 },
    },
    hazards = { "Kobold", "Hay Bale", "Defias Bomb" },
    shortcut = "Ford the river for a risky speed strip.",
    branches = {
      {
        id = "river_ford", name = "River Ford", side = 1,
        from = 0.560, to = 0.700, length = 250, sweep = 2.2,
        offroad = "WATER",
        surfaces = {
          { from = 92, to = 158, onRoad = "MUD" },
        },
        layout = {
          { len = 52, curve = 1.6, name = "River Ford", width = 0.74 },
          { len = 44, curve = 0, grade = -3.0, width = 0.68 },
          { len = 72, curve = -0.8, width = 0.64 },
          { len = 46, curve = 0, grade = 3.4, ramp = true, name = "Bank Launch", width = 0.86 },
          { len = 50, curve = -1.8, width = 0.78 },
        },
      },
    },
  },
  -- ================================================================
  -- DUROTAR DEATHLOOP -- The technical nightmare. FOUR hairpins, triple
  -- esses, switchback climb up a volcano. Narrow, dramatic elevation.
  -- MK64 analogue: Bowser's Castle.
  -- ================================================================
  {
    id = "durotar", name = "Durotar Deathloop", subtitle = "Mind the lava", theme = "DUROTAR",
    sweep = 4.0,
    length = 2500, laps = 3, color = { 0.49, 0.20, 0.08 }, road = { 0.42, 0.28, 0.18 },
    skyTop = { 0.30, 0.11, 0.16 }, skyLow = { 0.95, 0.48, 0.20 }, glow = { 1.00, 0.62, 0.24 },
    weather = "ember", light = 0.92,
    hazardPlan = {
      { kind = "static", name = "Lava Vent", count = 4, at = 0.12, spacing = 160, lateral = 0.5, radius = 3.4, slow = 1.4,
        icon = "Interface\\Icons\\Spell_Fire_Volcano" },
    },
    offroad = "SAND",
    surfaces = {
      { from = 550, to = 750, onRoad = "SAND" },
      { from = 1500, to = 1680, onRoad = "BOOST" },
    },
    layout = {
      { len = 210, curve = 0, name = "Razor Hill Straight", width = 1.16 },
      -- Immediately into the switchback climb.
      { len = 80, curve = 3.4, name = "Skull Rock Bend", width = 0.78 },
      { len = 70, curve = -4.2, grade = 3.2, name = "Lava Switchback", width = 0.72 },
      { len = 70, curve = 3.8, grade = 2.8, name = "Crater Rim", width = 0.74 },
      { len = 100, curve = -0.6, grade = 1.4, name = "Scorched Run", width = 0.92 },
      { len = 55, curve = 0, grade = 6.2, ramp = true, name = "Vent Launch", width = 1.18 },
      { len = 80, curve = 0, grade = -5.0, name = "Vent Landing", width = 1.08 },
      -- Magma Cavern: dark, narrow, blind. The volcano's interior.
      { len = 110, curve = -2.0, name = "Cavern Entry", width = 0.82, tunnel = true },
      { len = 140, curve = 2.8, name = "Magma Cavern", width = 0.76, tunnel = true },
      { len = 80, curve = -1.4, name = "Cavern Mouth", width = 0.90, tunnel = true },
      { len = 150, curve = 0, name = "Ashen Straight", width = 1.12 },
      -- Triple esses: three direction changes in quick succession.
      { len = 60, curve = -3.6, name = "Quillboar Kink", width = 0.80 },
      { len = 60, curve = 3.6, name = "Quillboar Kink II", width = 0.80 },
      { len = 60, curve = -3.2, name = "Quillboar Kink III", width = 0.82 },
      { len = 140, curve = 1.4, grade = 2.4, name = "Ridge Climb", width = 0.96 },
      -- THE Deathloop: the tightest hairpin in the game on the narrowest road.
      { len = 90, curve = -4.6, name = "Deathloop Hairpin", width = 0.70 },
      { len = 120, curve = 0.6, grade = -3.2, name = "Deathloop Descent", width = 0.98 },
      { len = 55, curve = 0, grade = 4.4, ramp = true, name = "Chasm Jump", width = 1.16 },
      { len = 90, curve = 0, grade = -3.6, name = "Chasm Landing", width = 1.08 },
      { len = 150, curve = 2.2, name = "Sen'jin Sweep", width = 0.94 },
      { len = 200, curve = 0, name = "Valley Run", width = 1.20 },
    },
    hazards = { "Quillboar", "Lava Vent", "Goblin Bomb" },
    shortcut = "Ride the red-hot ridge, if you dare.",
    branches = {
      {
        id = "lava_ridge", name = "Lava Ridge", side = -1,
        from = 0.480, to = 0.660, length = 320, sweep = 1.4,
        offroad = "SCREE",
        surfaces = {
          { from = 172, to = 242, onRoad = "BOOST" },
        },
        layout = {
          { len = 48, curve = -2.2, name = "Lava Ridge", width = 0.66 },
          { len = 56, curve = 0, grade = 3.2, width = 0.62 },
          { len = 44, curve = 2.8, width = 0.58 },
          { len = 48, curve = 0, grade = -4.6, ramp = true, name = "Ridge Drop", width = 0.82 },
          { len = 50, curve = -1.4, width = 0.76 },
        },
      },
    },
  },
  -- ================================================================
  -- STRANGLETHORN GRAND PRIX -- The winding jungle road. Consecutive
  -- same-direction turns create a snaking path through the trees.
  -- MK64 analogue: DK's Jungle Parkway.
  -- ================================================================
  {
    id = "stranglethorn", name = "Stranglethorn Grand Prix", subtitle = "Jungle rules apply", theme = "STRANGLETHORN",
    sweep = 3.5,
    length = 2650, laps = 3, color = { 0.06, 0.31, 0.20 }, road = { 0.43, 0.31, 0.17 },
    skyTop = { 0.17, 0.26, 0.30 }, skyLow = { 0.52, 0.62, 0.60 }, glow = { 0.72, 0.82, 0.78 },
    weather = "rain", light = 0.78,
    hazardPlan = {
      { kind = "patrol", name = "Raptor", count = 3, at = 0.20, spacing = 200, sweep = 0.9, radius = 3.2,
        model = { creature = 3243 }, icon = "Interface\\Icons\\Ability_Hunter_Pet_Raptor" },
    },
    offroad = "MUD",
    surfaces = {
      { from = 430, to = 695, onRoad = "MUD" },
      { from = 1480, to = 1700, offroad = "WATER" },
    },
    layout = {
      { len = 240, curve = 0, name = "Booty Bay Straight", width = 1.24 },
      -- Two LEFT turns in a row: winding into the jungle.
      { len = 220, curve = -2.0, name = "Harbour Sweep", width = 1.02 },
      { len = 170, curve = -1.4, name = "Nesingwary Trail", width = 0.96 },
      { len = 100, curve = 1.6, name = "Hunter's Run", width = 1.06 },
      { len = 80, curve = 3.8, name = "Panther Hairpin", width = 0.78 },
      { len = 140, curve = 1.5, grade = 2.8, name = "Canopy Climb", width = 1.00 },
      -- Under the canopy: 330m of tree cover.
      { len = 210, curve = 1.4, name = "Canopy Tunnel", width = 0.92, tunnel = true },
      { len = 120, curve = -1.8, grade = -2.8, name = "Vine Drop", width = 0.98, tunnel = true },
      { len = 50, curve = 0, grade = 4.6, ramp = true, name = "Ruins Jump", width = 1.18 },
      { len = 80, curve = 0, grade = -3.4, name = "Ruins Landing", width = 1.10 },
      -- Two RIGHT turns in a row: winding around the troll ruins.
      { len = 240, curve = 1.8, name = "Zul'Gurub Sweep", width = 1.02 },
      { len = 170, curve = 1.6, name = "Troll Passage", width = 0.98 },
      { len = 90, curve = -3.6, name = "Gurubashi Hairpin", width = 0.80 },
      { len = 190, curve = -1.6, name = "River Road", width = 1.16 },
      -- Cape Approach was a 0.4 drift-through-nothing, which put 590m of
      -- unbroken flat-out running between it, Cape Run and the Booty Bay
      -- Straight. It is a real corner onto the run to the line now.
      { len = 140, curve = 1.8, name = "Cape Approach", width = 1.12 },
      { len = 210, curve = 0, name = "Cape Run", width = 1.26 },
    },
    hazards = { "Raptor", "Pirate Barrel", "Murloc" },
    shortcut = "A narrow ruin path skips the river bend.",
    branches = {
      -- The route that line of HUD text has been promising since the track
      -- shipped. Cuts the corner off River Road through the troll ruins: much
      -- narrower, floored with mud so a missed apex costs more than the cut
      -- saves, and it rejoins before the Cape.
      {
        id = "ruin_path", name = "Ruin Path", side = 1,
        from = 0.620, to = 0.750, length = 250, sweep = 1.8,
        offroad = "MUD",
        surfaces = {
          { from = 96, to = 168, onRoad = "MUD" },
        },
        layout = {
          { len = 48, curve = 1.8, name = "Ruin Path", width = 0.68 },
          { len = 54, curve = -2.6, width = 0.62 },
          { len = 46, curve = 0, grade = -2.4, width = 0.66 },
          { len = 52, curve = 2.2, width = 0.64 },
          { len = 50, curve = -1.2, width = 0.72 },
        },
      },
    },
  },
  -- ================================================================
  -- IRONFORGE ICE CIRCUIT -- Wide mountain highway, treacherous on ice.
  -- Easy corners that become lethal when 47% of the lap is frozen.
  -- Only ONE hard turn. MK64 analogue: Frappe Snowland / Sherbet Land.
  -- ================================================================
  {
    id = "ironforge", name = "Ironforge Ice Circuit", subtitle = "No traction? No problem.", theme = "DUN MOROGH",
    sweep = 2.4,
    length = 2450, laps = 3, color = { 0.62, 0.78, 0.88 }, road = { 0.41, 0.53, 0.66 },
    skyTop = { 0.44, 0.55, 0.68 }, skyLow = { 0.84, 0.90, 0.95 }, glow = { 0.92, 0.95, 1.00 },
    weather = "snow", light = 0.95,
    hazardPlan = {
      { kind = "traffic", name = "Mine Cart", count = 3, at = 0.10, spacing = 240, speed = 34, lateral = -0.4, radius = 3.6,
        icon = "Interface\\Icons\\INV_Crate_02" },
    },
    offroad = "SNOW",
    surfaces = {
      { from = 380, to = 980, onRoad = "ICE" },
      { from = 1350, to = 1910, onRoad = "ICE" },
    },
    layout = {
      { len = 260, curve = 0, name = "Great Forge Straight", width = 1.28 },
      -- Wide sweeping arc. Easy on dry road, terrifying on ice.
      { len = 240, curve = 1.6, name = "Anvil Sweep", width = 1.14 },
      { len = 140, curve = -0.8, name = "Forge Run", width = 1.16 },
      -- The Mountain Bore: 480m of blind tunnel. Longest covered section.
      { len = 140, curve = -0.6, name = "Bore Entry", width = 1.00, tunnel = true },
      { len = 220, curve = 1.8, name = "Mountain Bore", width = 0.94, tunnel = true },
      { len = 120, curve = -0.4, grade = -2.0, name = "Bore Mouth", width = 1.08, tunnel = true },
      -- The one sharp turn on the circuit.
      { len = 100, curve = -3.2, name = "Frostmane Bend", width = 0.88 },
      { len = 190, curve = 1.2, grade = 1.4, name = "Glacier Climb", width = 1.12 },
      { len = 50, curve = 0, grade = 5.0, ramp = true, name = "Ice Jump", width = 1.20 },
      { len = 80, curve = 0, grade = -3.8, name = "Ice Landing", width = 1.14 },
      -- The widest, longest straight. Flat out on ice.
      { len = 280, curve = 0, name = "Coldridge Straight", width = 1.26 },
      { len = 170, curve = -1.4, name = "Gnomeregan Curve", width = 1.08 },
      { len = 50, curve = 0, grade = 4.2, ramp = true, name = "Tram Jump", width = 1.18 },
      { len = 70, curve = 0, grade = -3.2, name = "Tram Landing", width = 1.12 },
      { len = 220, curve = 0.6, name = "Hall Run", width = 1.24 },
    },
    hazards = { "Mine Cart", "Ice Patch", "Steam Valve" },
    shortcut = "A frozen tunnel is fast but very slippery.",
    branches = {
      -- Tunnelled end to end, which on a BRANCH is the honest shape: unlike a
      -- closed lap, you genuinely enter at 0 and leave at the far end, so the
      -- two mouths the fade math finds are real openings rather than a seam.
      -- Iced the whole way, so it is quicker only if you can still point the
      -- kart -- ICE barely slows you but takes your steering away.
      {
        id = "frozen_tunnel", name = "Frozen Tunnel", side = -1,
        from = 0.300, to = 0.420, length = 215, sweep = 1.5,
        offroad = "SNOW",
        surfaces = {
          { from = 0, to = 215, onRoad = "ICE" },
        },
        layout = {
          { len = 44, curve = -1.6, name = "Frozen Tunnel", width = 0.70, tunnel = true },
          { len = 48, curve = -2.8, width = 0.64, tunnel = true },
          { len = 40, curve = 1.4, width = 0.66, tunnel = true },
          { len = 45, curve = 2.4, width = 0.68, tunnel = true },
          { len = 38, curve = -0.8, width = 0.74, tunnel = true },
        },
      },
    },
  },
  -- ================================================================
  -- THE DEADMINES RUN -- The claustrophobic maze. Narrow everywhere,
  -- EIGHT tunnel segments across FOUR separate shafts. The most turns,
  -- the smallest road, the least breathing room.
  -- MK64 analogue: Banshee Boardwalk.
  -- ================================================================
  {
    id = "deadmines", name = "The Deadmines Run", subtitle = "Hard hats strongly advised", theme = "WESTFALL",
    sweep = 3.8,
    length = 2500, laps = 3, color = { 0.13, 0.17, 0.23 }, road = { 0.35, 0.27, 0.20 },
    skyTop = { 0.03, 0.04, 0.10 }, skyLow = { 0.16, 0.19, 0.34 }, glow = { 0.42, 0.46, 0.72 },
    -- 0.55 multiplied into every tint turned the whole scene to pitch --
    -- video frames measured the road at RGB ~15. Dark comes from the palette
    -- now; light stays high enough that the art survives it.
    weather = "none", light = 0.72,
    hazardPlan = {
      { kind = "traffic", name = "Mine Cart", count = 3, at = 0.08, spacing = 190, speed = 42, lateral = 0.3, radius = 3.6,
        icon = "Interface\\Icons\\INV_Crate_02" },
      { kind = "static", name = "Falling Rock", count = 3, at = 0.55, spacing = 90, lateral = -0.55, radius = 3.0,
        icon = "Interface\\Icons\\INV_Stone_15" },
    },
    offroad = "SCREE",
    surfaces = {
      { from = 950, to = 1125, onRoad = "WATER" },
    },
    layout = {
      { len = 180, curve = 0, name = "Cutting Straight", width = 1.10 },
      { len = 70, curve = -2.4, name = "Foreman's Turn", width = 0.90 },
      -- SHAFT 1.
      { len = 120, curve = -1.8, name = "Number One Shaft", width = 0.86, tunnel = true },
      { len = 95, curve = 3.0, name = "Shaft Bend", width = 0.80, tunnel = true },
      { len = 60, curve = 0.6, name = "Open Cutting", width = 0.98 },
      -- SHAFT 2: descending.
      { len = 100, curve = -2.6, grade = -2.0, name = "Descent Gallery", width = 0.82, tunnel = true },
      { len = 85, curve = 2.4, name = "Gallery Bend", width = 0.78, tunnel = true },
      -- Rope Bridge: narrowest road in the game.
      { len = 70, curve = 0, grade = 1.4, name = "Rope Bridge", width = 0.72 },
      { len = 65, curve = 4.2, name = "Ore Hairpin", width = 0.72 },
      -- SHAFT 3: deep bore.
      { len = 110, curve = -1.6, name = "Deep Bore", width = 0.84, tunnel = true },
      { len = 75, curve = -2.8, name = "Deep Bend", width = 0.78, tunnel = true },
      { len = 45, curve = 0, grade = 5.0, ramp = true, name = "Powder Jump", width = 1.16 },
      { len = 70, curve = 0, grade = -4.0, name = "Powder Landing", width = 1.08 },
      -- Brief wide section at the dock.
      { len = 160, curve = 0, name = "Ironclad Straight", width = 1.18 },
      { len = 55, curve = 3.4, name = "Dock Esses", width = 0.84 },
      { len = 55, curve = -3.4, name = "Dock Esses II", width = 0.84 },
      -- SHAFT 4: exit tunnel.
      { len = 85, curve = 1.4, name = "Exit Tunnel", width = 0.88, tunnel = true },
      { len = 75, curve = -1.0, name = "Tunnel Mouth", width = 0.94, tunnel = true },
      { len = 70, curve = -3.8, name = "Goblin Hairpin", width = 0.76 },
      { len = 120, curve = 2.0, name = "Cannon Sweep", width = 0.94 },
      { len = 160, curve = 0, name = "Harbour Run", width = 1.14 },
    },
    hazards = { "Falling Rock", "Mine Cart", "Powder Keg" },
    shortcut = "Blast through the unstable side shaft.",
    branches = {
      -- The narrowest road in the game, on the track that is already the
      -- narrowest. Deadmines' whole identity is claustrophobia, so its
      -- shortcut is not a fast open cut -- it is a squeeze that punishes any
      -- line that is not exactly right.
      {
        id = "side_shaft", name = "Side Shaft", side = 1,
        from = 0.400, to = 0.520, length = 225, sweep = 1.4,
        offroad = "SCREE",
        layout = {
          { len = 42, curve = 2.2, name = "Side Shaft", width = 0.62, tunnel = true },
          { len = 50, curve = -3.0, width = 0.58, tunnel = true },
          { len = 44, curve = 0, grade = -3.0, width = 0.62, tunnel = true },
          { len = 48, curve = 2.6, width = 0.60, tunnel = true },
          { len = 41, curve = -1.4, width = 0.68, tunnel = true },
        },
      },
    },
  },
  -- ================================================================
  -- NETHERSTORM TURBO CIRCUIT -- The speed track. Widest road, longest
  -- straights, only ONE hairpin. It is about going fast and being
  -- terrified of the one moment you have to stop.
  -- MK64 analogue: Rainbow Road.
  -- ================================================================
  {
    id = "netherstorm", name = "Netherstorm Turbo Circuit", subtitle = "The road is optional", theme = "NETHERSTORM",
    sweep = 2.5,
    length = 2750, laps = 3, color = { 0.26, 0.12, 0.45 }, road = { 0.28, 0.22, 0.49 },
    skyTop = { 0.07, 0.03, 0.18 }, skyLow = { 0.44, 0.20, 0.62 }, glow = { 0.72, 0.42, 1.00 },
    weather = "ember", light = 0.80,
    hazardPlan = {
      { kind = "patrol", name = "Void Spark", count = 4, at = 0.15, spacing = 210, sweep = 1.0, radius = 3.0, reaction = "launch",
        model = { creature = 1860 }, icon = "Interface\\Icons\\Spell_Shadow_Shadowbolt" },
    },
    offroad = "SCREE",
    surfaces = {
      { from = 1430, to = 1650, onRoad = "BOOST" },
    },
    -- The speed circuit keeps its speed: the Manaforge Straight is still the
    -- longest in the game. What it does not get to keep is THREE of them with
    -- soft bends in between. Measured, only 13% of this lap was firm enough for
    -- a mini-turbo to charge, and Turbo Run running straight into Manaforge
    -- Straight made a 650m unbroken flat-out stretch -- a quarter of the lap on
    -- which nothing happens. The sweepers are firmed up and the run to the line
    -- now arrives through a kink, which is the classic overtaking spot.
    layout = {
      -- 360m straight. The longest in the game. Full speed.
      { len = 360, curve = 0, name = "Manaforge Straight", width = 1.32 },
      { len = 260, curve = 1.9, name = "Arcane Sweep", width = 1.16 },
      { len = 100, curve = -1.6, name = "Ley Run", width = 1.20 },
      { len = 80, curve = -4.0, name = "Nexus Hairpin", width = 0.78 },
      { len = 140, curve = 1.5, grade = 2.8, name = "Rise to the Ring", width = 1.06 },
      -- Conduit Tube: fast tunnel, and now a bend worth drifting through it.
      { len = 250, curve = 1.7, name = "Conduit Tube", width = 0.96, tunnel = true },
      { len = 100, curve = -1.8, name = "Tube Exit", width = 1.08, tunnel = true },
      { len = 60, curve = 0, grade = 6.0, ramp = true, name = "Void Leap", width = 1.22 },
      { len = 95, curve = 0, grade = -4.8, name = "Void Landing", width = 1.14 },
      { len = 240, curve = 0, name = "Ethereum Straight", width = 1.30 },
      { len = 200, curve = -2.0, name = "Sparkfly Sweep", width = 1.08 },
      { len = 120, curve = 2.8, name = "Kirin'Var Bend", width = 0.90 },
      { len = 220, curve = -1.7, name = "Farahlon Sweep", width = 1.12 },
      { len = 150, curve = 0, name = "Turbo Run", width = 1.32 },
      { len = 90, curve = 2.6, name = "Voidshard Kink", width = 1.04 },
    },
    hazards = { "Mana Storm", "Void Spark", "Arcane Mine" },
    shortcut = "Blink through a portal at maximum speed.",
    branches = {
      -- Netherstorm is the speed track, so its shortcut is the only one that
      -- is FAST rather than technical: wide for a branch, gently swept, and
      -- floored with a boost strip. The cost is that it is a committed line at
      -- the speeds this circuit is driven at.
      {
        id = "portal_run", name = "Portal Run", side = -1,
        from = 0.340, to = 0.460, length = 245, sweep = 1.6,
        offroad = "SCREE",
        surfaces = {
          { from = 90, to = 180, onRoad = "BOOST" },
        },
        layout = {
          { len = 56, curve = -1.4, name = "Portal Run", width = 0.78 },
          { len = 52, curve = 0, grade = 2.0, width = 0.74 },
          { len = 48, curve = 2.2, width = 0.70 },
          { len = 50, curve = -2.0, width = 0.72 },
          { len = 39, curve = 0.8, width = 0.80 },
        },
      },
    },
  },
  -- ================================================================
  -- THOUSAND NEEDLES MESA RUN -- The jump track. THREE ramps, the most in
  -- the game, each launching over a real canyon gap rather than a token
  -- rise. Moderate corners throughout; the lap is defined by elevation and
  -- airtime, not by cornering technique. MK64 analogue: Kalimari Desert /
  -- DK's Jungle Parkway's canyon jump, but the whole lap is built around it.
  -- ================================================================
  {
    id = "thousandneedles", name = "Thousand Needles Mesa Run", subtitle = "Mind the gap. All of them.", theme = "THOUSAND NEEDLES",
    sweep = 2.8,
    length = 2100, laps = 3, color = { 0.62, 0.34, 0.20 }, road = { 0.58, 0.42, 0.28 },
    skyTop = { 0.36, 0.20, 0.14 }, skyLow = { 0.92, 0.62, 0.38 }, glow = { 1.00, 0.78, 0.48 },
    weather = "none", light = 0.96,
    hazardPlan = {
      { kind = "static", name = "Rockslide", count = 3, at = 0.30, spacing = 150, lateral = -0.4, radius = 3.2, slow = 1.3,
        icon = "Interface\\Icons\\INV_Stone_15" },
    },
    offroad = "SAND",
    surfaces = {
      { from = 400, to = 620, onRoad = "SAND" },
      { from = 1400, to = 1580, onRoad = "BOOST" },
    },
    layout = {
      { len = 280, curve = 0, name = "Freewind Straight", width = 1.30 },
      { len = 90, curve = -3.4, name = "Mesa Switchback", width = 0.86 },
      { len = 140, curve = 1.2, grade = 4.0, name = "Rise to the Plateau", width = 1.05 },
      -- First leap: the canyon gap that gives the track its name.
      { len = 55, curve = 0, grade = 6.5, ramp = true, name = "Canyon Leap", width = 1.20 },
      { len = 100, curve = 0, grade = -5.5, name = "Canyon Landing", width = 1.10 },
      { len = 160, curve = 2.0, name = "Plateau Sweep", width = 1.08 },
      -- Narrowest point on the lap; no ramp here, just nerve.
      { len = 70, curve = 0, grade = 1.2, name = "Rope Crossing", width = 0.68 },
      { len = 80, curve = -2.8, name = "Grimtotem Bend", width = 0.84 },
      { len = 200, curve = 0, name = "Mirage Straight", width = 1.26 },
      { len = 55, curve = 0, grade = 5.8, ramp = true, name = "Second Leap", width = 1.18 },
      { len = 85, curve = 0, grade = -4.6, name = "Second Landing", width = 1.10 },
      { len = 120, curve = 3.0, name = "Naga Coil", width = 0.92 },
      { len = 90, curve = -1.4, grade = -2.6, name = "Descent Run", width = 1.00 },
      { len = 60, curve = 0, grade = 5.0, ramp = true, name = "Final Leap", width = 1.16 },
      { len = 80, curve = 0, grade = -3.8, name = "Final Landing", width = 1.08 },
      { len = 170, curve = 1.6, name = "Highland Curve", width = 1.10 },
      { len = 240, curve = 0, name = "Home Straight", width = 1.28 },
    },
    hazards = { "Rockslide", "Naga Ambush", "Harpy" },
    shortcut = "Cut across the canyon rim and hope the wind is with you.",
    branches = {
      -- The jump track's shortcut is, of course, a jump: a rim gap taken off a
      -- ramp, which is the one branch in the game you can fail by being too
      -- SLOW rather than too fast.
      {
        id = "canyon_rim", name = "Canyon Rim", side = 1,
        from = 0.300, to = 0.440, length = 220, sweep = 1.7,
        offroad = "SCREE",
        layout = {
          { len = 46, curve = 1.6, name = "Canyon Rim", width = 0.66 },
          { len = 42, curve = 0, grade = 3.2, width = 0.62 },
          { len = 44, curve = 0, grade = -4.0, ramp = true, name = "Rim Gap", width = 0.80 },
          { len = 48, curve = -2.4, width = 0.64 },
          { len = 40, curve = 1.2, width = 0.70 },
        },
      },
    },
  },
  -- ================================================================
  -- ZANGARMARSH SPORE RUN -- The WATER track. Every other circuit treats
  -- water as a hazard at the edge; here it is painted across the road four
  -- times a lap, so the racing line is a series of decisions about which
  -- crossing to take wide and which to take slow. Flat -- the least
  -- elevation of any track -- because the surface is doing the work.
  -- MK64 analogue: Koopa Troopa Beach.
  -- ================================================================
  {
    id = "zangarmarsh", name = "Zangarmarsh Spore Run", subtitle = "The bog always wins", theme = "ZANGARMARSH",
    sweep = 3.0,
    length = 2300, laps = 3, color = { 0.16, 0.34, 0.38 }, road = { 0.40, 0.44, 0.42 },
    skyTop = { 0.08, 0.18, 0.26 }, skyLow = { 0.34, 0.62, 0.60 }, glow = { 0.55, 0.95, 0.85 },
    weather = "rain", light = 0.86,
    hazardPlan = {
      { kind = "static", name = "Spore Cloud", count = 4, at = 0.24, spacing = 170, lateral = 0.45, radius = 3.0, slow = 1.2,
        icon = "Interface\\Icons\\Spell_Nature_Regenerate" },
    },
    offroad = "WATER",
    surfaces = {
      { from = 300, to = 430, onRoad = "WATER" },
      { from = 900, to = 1010, onRoad = "MUD" },
      { from = 1420, to = 1560, onRoad = "WATER" },
      { from = 1980, to = 2080, onRoad = "MUD" },
    },
    layout = {
      { len = 250, curve = 0, name = "Telredor Straight", width = 1.26 },
      { len = 190, curve = 1.6, name = "Sporeggar Sweep", width = 1.10 },
      { len = 120, curve = -1.0, name = "Bog Road", width = 1.06 },
      { len = 90, curve = -3.2, name = "Marsh Hairpin", width = 0.82 },
      { len = 160, curve = 0.8, name = "Fen Crossing", width = 1.04 },
      { len = 130, curve = 1.4, grade = 2.2, name = "Cap Climb", width = 1.00 },
      -- Under a giant mushroom cap rather than through rock.
      { len = 180, curve = -1.2, name = "Under the Cap", width = 0.94, tunnel = true },
      { len = 110, curve = 0.6, grade = -2.0, name = "Cap Exit", width = 1.02, tunnel = true },
      { len = 50, curve = 0, grade = 4.4, ramp = true, name = "Root Launch", width = 1.18 },
      { len = 85, curve = 0, grade = -3.4, name = "Root Landing", width = 1.10 },
      { len = 210, curve = 2.0, name = "Serpent Lake", width = 1.06 },
      { len = 140, curve = -1.6, name = "Lagoon Bend", width = 1.08 },
      { len = 70, curve = 3.4, name = "Reed Kink", width = 0.84 },
      { len = 70, curve = -3.4, name = "Reed Kink II", width = 0.84 },
      { len = 180, curve = 0.8, name = "Umbrafen Run", width = 1.14 },
      { len = 240, curve = 0, name = "Home Straight", width = 1.28 },
    },
    hazards = { "Spore Cloud", "Marsh Strider", "Naga Patrol" },
    shortcut = "Wade the shallows instead of going round the lagoon.",
    branches = {
      {
        id = "the_shallows", name = "The Shallows", side = -1,
        from = 0.550, to = 0.680, length = 225, sweep = 1.6,
        offroad = "WATER",
        surfaces = {
          { from = 0, to = 225, onRoad = "WATER" },
        },
        layout = {
          { len = 46, curve = -1.8, name = "The Shallows", width = 0.68 },
          { len = 50, curve = -2.6, width = 0.62 },
          { len = 42, curve = 1.6, width = 0.66 },
          { len = 47, curve = 2.4, width = 0.64 },
          { len = 40, curve = -1.0, width = 0.72 },
        },
      },
    },
  },
  -- ================================================================
  -- ICECROWN SPIRE DESCENT -- The ELEVATION track. Two long falls and two
  -- hard climbs, so more of this lap is spent going up or down than on the
  -- level -- the crest hides the road ahead more often than anywhere else,
  -- and a corner you cannot see yet is the whole difficulty.
  -- MK64 analogue: Wario Stadium's big rises, on a gothic circuit.
  -- ================================================================
  {
    id = "icecrown", name = "Icecrown Spire Descent", subtitle = "All downhill. Twice.", theme = "ICECROWN",
    sweep = 2.7,
    length = 2250, laps = 3, color = { 0.16, 0.20, 0.30 }, road = { 0.42, 0.46, 0.54 },
    skyTop = { 0.02, 0.04, 0.10 }, skyLow = { 0.20, 0.30, 0.46 }, glow = { 0.58, 0.86, 1.00 },
    weather = "snow", light = 0.76,
    hazardPlan = {
      { kind = "patrol", name = "Gargoyle", count = 3, at = 0.16, spacing = 200, sweep = 0.85, radius = 3.1, reaction = "launch",
        icon = "Interface\\Icons\\Spell_Shadow_RaiseDead" },
    },
    offroad = "SNOW",
    surfaces = {
      { from = 260, to = 560, onRoad = "ICE" },
      { from = 1470, to = 1690, onRoad = "ICE" },
    },
    layout = {
      { len = 260, curve = 0, name = "Ramparts Straight", width = 1.26 },
      -- First fall: 320m of descent, on ice.
      { len = 150, curve = -1.8, grade = -2.6, name = "First Descent", width = 1.10 },
      { len = 170, curve = -1.2, grade = -3.0, name = "Falling Ramp", width = 1.06 },
      { len = 80, curve = 3.6, name = "Gargoyle Hairpin", width = 0.80 },
      { len = 130, curve = 0.6, grade = 4.2, name = "Spire Climb", width = 1.00 },
      { len = 190, curve = 1.4, name = "Frozen Arches", width = 0.94, tunnel = true },
      { len = 120, curve = -0.8, grade = -2.4, name = "Arch Exit", width = 1.02, tunnel = true },
      { len = 55, curve = 0, grade = 5.2, ramp = true, name = "Saronite Jump", width = 1.18 },
      { len = 95, curve = 0, grade = -4.4, name = "Saronite Landing", width = 1.10 },
      -- Second fall, and the longest single descent in the game.
      { len = 220, curve = -1.6, grade = -2.2, name = "The Long Fall", width = 1.12 },
      { len = 60, curve = -3.8, name = "Crypt Kink", width = 0.80 },
      { len = 60, curve = 3.8, name = "Crypt Kink II", width = 0.80 },
      { len = 175, curve = 1.2, grade = 3.4, name = "Return Climb", width = 1.04 },
      { len = 140, curve = -1.0, name = "Upper Terrace", width = 1.10 },
      { len = 90, curve = 2.8, name = "Throne Bend", width = 0.88 },
      { len = 250, curve = 0, name = "The Approach", width = 1.24 },
    },
    hazards = { "Gargoyle", "Ice Shard", "Saronite Chunk" },
    shortcut = "Drop down the broken stair instead of taking the terrace.",
    branches = {
      {
        id = "broken_stair", name = "Broken Stair", side = 1,
        from = 0.240, to = 0.370, length = 220, sweep = 1.5,
        offroad = "SNOW",
        surfaces = {
          { from = 60, to = 150, onRoad = "ICE" },
        },
        layout = {
          { len = 44, curve = 2.0, name = "Broken Stair", width = 0.66, tunnel = true },
          { len = 48, curve = 0, grade = -4.2, width = 0.62, tunnel = true },
          { len = 42, curve = -2.4, width = 0.64, tunnel = true },
          { len = 46, curve = 1.8, width = 0.66, tunnel = true },
          { len = 40, curve = -1.2, width = 0.72, tunnel = true },
        },
      },
    },
  },
}

function AK:GetTrack(id)
  for _, track in ipairs(self.Tracks) do
    if track.id == id then return AK.TrackBuilder:Compile(track) end
  end
  return AK.TrackBuilder:Compile(self.Tracks[1])
end

-- Every track appears in at least one cup. Zangarmarsh and Icecrown were
-- reachable only from QUICK RACE when they were added, which makes a circuit
-- half-shipped: the Grand Prix is where a track is actually driven in anger.
-- Twelve slots over ten tracks means two repeats; they are the two that suit
-- being run twice at different points in a season.
AK.Cups = {
  { id = "eastern", name = "Eastern Kingdoms Cup", tracks = { "oribos", "stranglethorn", "ironforge", "deadmines" } },
  { id = "wild", name = "Wild Worlds Cup", tracks = { "durotar", "elwynn", "zangarmarsh", "netherstorm" } },
  { id = "frontier", name = "Frontier Cup", tracks = { "thousandneedles", "icecrown", "oribos", "durotar" } },
}

function AK:GetCup(id)
  for _, cup in ipairs(self.Cups) do if cup.id == id then return cup end end
  return self.Cups[1]
end
