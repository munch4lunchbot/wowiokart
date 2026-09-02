local _, AK = ...

-- Sound has been the worst part of this addon for three rounds now, and the
-- reason is that the fix kept being "rearrange the cue table". That could never
-- work. SOUNDKIT is an interface library -- checkbox ticks, tab clicks, coin
-- drops. Reshuffling a list of clicks produces a different order of clicks.
--
-- Two things actually matter, and neither is which name sits in which slot:
--
--   1. HOW OFTEN anything plays at all. A drift fired driftStart on the hop and
--      again on the engage, then driftStage three times as the charge stepped
--      up. Eight blips per corner, and you corner constantly. No choice of
--      sample survives that repetition rate; the problem was the rate.
--
--   2. WHETHER we are limited to SOUNDKIT. We are not. PlaySoundFile takes a
--      FileDataID and reaches the whole game audio library -- machinery, impacts,
--      creature noise -- rather than the interface subset. What stopped us using
--      it is that nobody here can hear the result, so picking IDs blind is
--      guesswork.
--
-- So: this file rate-limits by priority, and it makes sound choice something the
-- player can drive from inside the game. Every cue may carry FileDataID
-- candidates; they are validated by actually playing them, because PlaySoundFile
-- reports whether the file existed. A candidate that does not resolve is dropped
-- and the next one is tried in the same call, so a bad guess costs silence for
-- zero frames rather than forever. /kart sfx auditions, /kart sfxset assigns,
-- and assignments persist -- which means the sound set can be tuned by ear by
-- the one person in this loop who has ears.

local PRI = { LOW = 1, NORMAL = 2, HIGH = 3, CRITICAL = 4 }

-- Nothing may play within this of anything else. Purely a stutter guard; it is
-- the per-priority spacing below that does the real work.
local GLOBAL_FLOOR = 0.10
-- Incidental race texture -- drift, bumps, scrapes. One per second, tops. This
-- single number is what turns the machine gun off.
local LOW_SPACING = 1.10
local NORMAL_SPACING = 0.30

local DEFAULT_CD = { [PRI.LOW] = 0.90, [PRI.NORMAL] = 0.25, [PRI.HIGH] = 0.12, [PRI.CRITICAL] = 0 }

-- kit  = SOUNDKIT names, tried in order
-- file = FileDataID candidates, tried BEFORE the kit names when present
-- pri  = suppression class under load
-- cd   = per-cue cooldown, defaulted from pri when omitted
local CUES = {
  -- Race structure. These are the beats the player is actually listening for,
  -- so they are exempt from crowding out.
  -- The battleground countdown is, almost exactly, a race countdown -- three
  -- timer beats and a start horn. Leading with it costs nothing if the name is
  -- missing on a client, and if it resolves it is the single biggest upgrade in
  -- this table.
  countdown   = { kit = { "UI_BATTLEGROUND_COUNTDOWN_TIMER", "MAP_PING", "IG_CHARACTER_INFO_TAB" }, pri = PRI.CRITICAL },
  countdownGo = { kit = { "UI_BATTLEGROUND_COUNTDOWN_FINISHED", "READY_CHECK", "RAID_WARNING" }, pri = PRI.CRITICAL },
  lap         = { kit = { "IG_QUEST_LIST_COMPLETE" }, pri = PRI.CRITICAL },
  finalLap    = { kit = { "RAID_WARNING", "IG_QUEST_LIST_COMPLETE" }, pri = PRI.CRITICAL },
  victory     = { kit = { "LEVELUPSOUND", "UI_70_ARTIFACT_FORGE_TRAIT_RANK_UP" }, pri = PRI.CRITICAL },
  defeat      = { kit = { "IG_QUEST_FAILED" }, pri = PRI.CRITICAL },

  -- Items. Frequent but meaningful -- you need to know you got one and that it
  -- fired, so these sit above the incidental layer.
  --
  -- CANDIDATE ORDER IS THE WHOLE POINT. playCue tries each name by actually
  -- playing it and falls through the moment one does not resolve, at zero cost
  -- -- so a list can lead with the sound we WANT and keep the old interface
  -- blip as the last resort. Everything below is ordered best-first: weighty,
  -- physical, and drawn from the parts of the library that are not checkbox
  -- ticks. If a name does not exist on a given client, nothing breaks, the next
  -- one is tried, and `/kart sfxreport` says what actually resolved.
  item        = { kit = { "UI_TOYBOX_TABS", "UI_EPICLOOT_TOAST", "IG_BACKPACK_COIN_UP" }, pri = PRI.HIGH, cd = 0.20 },
  itemUse     = { kit = { "UI_TRANSMOG_ITEM_CLICK", "IG_SPELLBOOK_CLOSE" }, pri = PRI.HIGH, cd = 0.20 },
  throw       = { kit = { "UI_PVP_KILLBLOW", "IG_MAINMENU_OPEN" }, pri = PRI.NORMAL },
  throwHoming = { kit = { "UI_WORLDQUEST_START", "GS_CHARACTER_SELECTION_ENTER_WORLD", "IG_MAINMENU_OPEN" }, pri = PRI.NORMAL },
  throwHeavy  = { kit = { "UI_RAID_BOSS_DEFEATED", "IG_MAINMENU_QUIT", "IG_PLAYER_INVITE_DECLINE" }, pri = PRI.NORMAL },
  drop        = { kit = { "UI_ETHEREAL_WINDOW_CLOSE", "IG_BACKPACK_COIN_DOWN" }, pri = PRI.NORMAL },
  deploy      = { kit = { "UI_VOID_STORAGE_UNLOCK", "IG_CHARACTER_INFO_TAB" }, pri = PRI.NORMAL },
  starPower   = { kit = { "UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST", "LEVELUPSOUND" }, pri = PRI.HIGH },
  -- The shell has locked onto you. CRITICAL: this is the one warning in the
  -- game where being crowded out costs the player the chance to react.
  spinyWarn   = { kit = { "RAID_WARNING", "READY_CHECK" }, pri = PRI.CRITICAL },
  -- Landing a shot on somebody is the best moment the genre has. It had no cue
  -- at all, because every hit sound was played to the VICTIM.
  hitConfirm  = { kit = { "UI_RAID_BOSS_DEFEATED", "LOOT_WINDOW_COIN_SOUND" }, pri = PRI.HIGH, cd = 0.25 },

  -- Speed. Boosts are earned, so they get to be heard.
  boost       = { kit = { "UI_70_ARTIFACT_FORGE_TRAIT_RANK_UP" }, pri = PRI.HIGH, cd = 0.35 },
  megaBoost   = { kit = { "LEVELUPSOUND", "UI_70_ARTIFACT_FORGE_TRAIT_RANK_UP" }, pri = PRI.HIGH, cd = 0.35 },
  dash        = { kit = { "IG_SPELLBOOK_OPEN" }, pri = PRI.NORMAL, cd = 0.40 },
  landing     = { kit = { "UI_70_ARTIFACT_FORGE_TRAIT_RANK_UP" }, pri = PRI.NORMAL, cd = 0.40 },

  -- ENGINE. Its own lane -- see UpdateEngine. These never route through
  -- permitted(), so their pri/cd are documentation rather than gating, and they
  -- must stay LOW so nothing else treats them as meaningful.
  engineLow    = { kit = { "IG_ABILITY_ICON_DROP", "IG_MAINMENU_OPTION" }, pri = PRI.LOW, cd = 0 },
  engineHigh   = { kit = { "IG_ABILITY_ICON_PICKUP", "IG_CHARACTER_INFO_TAB" }, pri = PRI.LOW, cd = 0 },

  -- THE DRIFT LADDER. One cue per tier, fired once as the charge CROSSES each
  -- threshold rather than repeatedly while it sits there. That is what makes
  -- three sounds a corner instead of eight, and it is the single most valuable
  -- cue in the game: it tells you the mini-turbo has arrived while your eyes
  -- are still on the corner. Rising through the set must be audibly a LADDER,
  -- so these are deliberately three different pitches of the same idea.
  -- Three rungs that must sound like a RISING set, not three unrelated blips.
  -- Ordered so each tier leads with something brighter and more emphatic than
  -- the one below it, with the old interface tick kept last as a fallback.
  driftTier1   = { kit = { "UI_TOYBOX_TABS", "IG_ABILITY_ICON_PICKUP" }, pri = PRI.NORMAL, cd = 0.25 },
  driftTier2   = { kit = { "UI_WORLDQUEST_COMPLETE", "UI_TRANSMOG_ITEM_CLICK", "IG_CHARACTER_INFO_TAB" }, pri = PRI.HIGH, cd = 0.25 },
  driftTier3   = { kit = { "UI_LEGENDARY_LOOT_TOAST", "UI_70_ARTIFACT_FORGE_TRAIT_RANK_UP" }, pri = PRI.HIGH, cd = 0.25 },

  -- driftStart is GONE, on density grounds. It fired the moment the drift
  -- engaged, and driftTier1 follows about 0.3s later once the charge crosses
  -- 0.35 -- two blips at every corner entry, on a circuit where you corner
  -- constantly. That is the "eight blips per corner" complaint in miniature.
  -- The hop is carried visually; the first rung of the ladder is the beat that
  -- actually tells you something.

  -- Incidental texture. Everything below fires many times a lap and is the
  -- entire source of the complaint. Long cooldowns, first to be suppressed.
  bump         = { kit = { "UI_ETHEREAL_WINDOW_CLOSE", "IG_PLAYER_INVITE_DECLINE" }, pri = PRI.LOW, cd = 1.20 },
  -- Being hit has to land like something hit you, not like a window closing.
  collision    = { kit = { "UI_PVP_KILLBLOW", "UI_RAID_BOSS_DEFEATED", "IG_MAINMENU_CLOSE" }, pri = PRI.NORMAL, cd = 0.70 },
  blocked      = { kit = { "UI_VOID_STORAGE_UNLOCK", "IG_CHARACTER_NPC_SELECT" }, pri = PRI.LOW, cd = 1.50 },
  offroad      = { kit = { "IG_MAINMENU_OPTION" }, pri = PRI.LOW, cd = 1.60 },
  surfaceEnter = { kit = { "IG_MAINMENU_OPTION_CHECKBOX_OFF" }, pri = PRI.LOW, cd = 1.40 },
  overtake     = { kit = { "UI_WORLDQUEST_COMPLETE", "LOOT_WINDOW_COIN_SOUND", "IG_BACKPACK_COIN_UP" }, pri = PRI.NORMAL, cd = 0.80 },
  -- Losing a place was completely silent -- the banner changed colour and that
  -- was all. Gaining one and losing one are the two halves of the same beat and
  -- a race where only the good half is audible reads as though nothing is at
  -- stake. Deliberately duller and lower than `overtake`.
  passed       = { kit = { "UI_ETHEREAL_WINDOW_CLOSE", "IG_QUEST_FAILED", "IG_MAINMENU_CLOSE" }, pri = PRI.NORMAL, cd = 0.80 },
  -- A green shell ricocheting off the verge. It happens constantly and made no
  -- noise at all, so a shell you fired simply vanished from the world.
  shellBounce  = { kit = { "UI_PVP_KILLBLOW", "IG_ABILITY_ICON_DROP" }, pri = PRI.LOW, cd = 0.45 },
  -- Whoosh as somebody flicks past. Low priority and a long cooldown on purpose
  -- -- in a tight pack this can trigger several times a second, and it is
  -- texture, not information.
  nearMiss     = { kit = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", "IG_ABILITY_ICON_DROP" }, pri = PRI.LOW, cd = 0.90 },
  thunder      = { kit = { "READY_CHECK" }, pri = PRI.LOW, cd = 4.00 },

  -- Menus. Outside a race there is no budget pressure, but the hover cue still
  -- needs its own cooldown or sweeping the mouse across a list machine-guns.
  -- `menu = true` puts these outside the race's crowding budget entirely. The
  -- hover keeps a small cooldown of its own, because sweeping a mouse down a
  -- list really does machine-gun it; the rest fire whenever they are asked to.
  uiHover     = { kit = { "IG_MAINMENU_OPTION" }, pri = PRI.LOW, cd = 0.06, menu = true },
  uiClick     = { kit = { "IG_MAINMENU_OPTION_CHECKBOX_ON" }, pri = PRI.NORMAL, cd = 0, menu = true },
  uiOpen      = { kit = { "IG_CHARACTER_INFO_OPEN" }, pri = PRI.NORMAL, cd = 0, menu = true },
  uiClose     = { kit = { "IG_CHARACTER_INFO_CLOSE" }, pri = PRI.NORMAL, cd = 0, menu = true },
}

-- What each cue settled on, once proven to actually make a noise.
local chosen = {}
local lastPlayed, lastAny, lastLow, lastNormal = {}, 0, 0, 0
-- Declared HERE, not down with the engine: a `local` further down the file is
-- invisible to functions defined above it, so PlaySfx would have been writing a
-- global of the same name and the engine duck would never have connected.
local lastImportant = -99
-- What actually played, and over how long. The editor needs the real firing
-- rate: a cue's cooldown says what it is permitted to do, not what it does.
local playCounts, statsStart = {}, GetTime()

--- Start counting again. Called when a race begins, so the numbers the editor
--- shows always describe one race rather than the whole session.
function AK:ResetSfxStats()
  playCounts, statsStart = {}, GetTime()
end

local function enabled()
  return AK.db and AK.db.settings and AK.db.settings.sfx
end

--- Play one candidate, reporting whether the client actually had it. Both APIs
--- return willPlay first, which is the only honest signal available about
--- whether an id exists on this client.
--- Did this id ACTUALLY make a noise? The handle is the only honest answer.
---
--- `willPlay` is not a success signal. Measured on a live client:
---
---   PlaySoundFile(50111, "SFX")  ->  willPlay = true,  handle = 0
---   PlaySound(50111, "SFX")      ->  willPlay = true,  handle = 180876
---
--- Both claim success; only the second makes a sound. PlaySoundFile answers
--- `true` for practically any number and returns a ZERO handle when there is no
--- file behind it -- so trusting willPlay meant every id "worked", the first
--- thing tried was cached as the cue's sound, and it then played silence
--- forever without ever falling through to the kit id that would have worked.
--- It also made the id scanner stop on its first probe, which is why "next
--- sound" never found anything.
---
--- A non-zero handle means the client started a sound. Nothing else does.
local function emit(source, id)
  local fn = source == "file" and PlaySoundFile or PlaySound
  local ok, willPlay, handle = pcall(fn, id, "SFX")
  -- Remembered so the bench can stop it. Some library entries run for minutes.
  if ok and handle and handle ~= 0 then AK.lastSoundHandle = handle end
  -- Retry with no channel argument: some calls reject an explicit channel and
  -- answer with nothing, which is indistinguishable from a bad id.
  if not (ok and willPlay and handle and handle ~= 0) then
    ok, willPlay, handle = pcall(fn, id)
  end
  return (ok and willPlay and handle and handle ~= 0) and true or false
end

--- Resolve and play in one pass. Candidates are only ever proven by playing
--- them, so resolution and playback cannot be separated -- but once a candidate
--- works it is cached and every later call is a single call.
local function playCue(cue, def)
  -- MUTED. Stored as the sentinel 0 rather than by removing the override,
  -- because "no override" already means "use the built-in" -- there was no way
  -- to say "make this one silent" at all, only a way to put it back.
  local override = AK.db and AK.db.sfxOverride and AK.db.sfxOverride[cue]
  if override == 0 then return false end

  local hit = chosen[cue]
  if hit then return emit(hit.source, hit.id) end

  -- An override is tried as a SOUNDKIT id FIRST, then as a file id.
  --
  -- Kit first because that is what every id a player can actually see is: the
  -- built-in each cue resolves to, which is what gets copied between rows. File
  -- ids remain supported for anything found elsewhere, but they are the rarer
  -- case and must not get first refusal -- PlaySoundFile claims success for
  -- almost any number, so letting it go first meant it swallowed kit ids and
  -- played silence.
  if override then
    if emit("kit", override) then
      chosen[cue] = { source = "kit", id = override }
      return true
    end
    if emit("file", override) then
      chosen[cue] = { source = "file", id = override }
      return true
    end
  end

  for _, id in ipairs(def.file or {}) do
    if emit("file", id) then
      chosen[cue] = { source = "file", id = id }
      return true
    end
  end

  for _, name in ipairs(def.kit or {}) do
    local id = SOUNDKIT and SOUNDKIT[name]
    if id and emit("kit", id) then
      chosen[cue] = { source = "kit", id = id }
      return true
    end
  end

  -- Nothing resolved. Cache the failure so a dead cue is not re-probed every
  -- time it fires; that probing is itself audible when a partial match exists.
  chosen[cue] = { source = "none", id = 0 }
  return false
end

--- Is this cue allowed to make a noise right now? Everything about not being
--- annoying lives in this function.
local function permitted(cue, def, now)
  local pri = def.pri or PRI.NORMAL

  local cd = def.cd or DEFAULT_CD[pri]
  if cd > 0 and now - (lastPlayed[cue] or -99) < cd then return false end

  -- MENU CUES ARE NOT RACE TEXTURE.
  --
  -- These went through the same crowding budget as the race, which was only
  -- ever a guard against not knowing which sounds fired how often. That is no
  -- longer a guess -- the rate is measured -- and outside a race there is no
  -- budget to protect: a click that does not click because a race cue happened
  -- to fire recently just reads as the button not working.
  if def.menu then return true end

  -- Critical beats ignore crowding entirely -- if the lap completes while you
  -- are being shelled, you still hear the lap.
  if pri >= PRI.CRITICAL then return true end

  if now - lastAny < GLOBAL_FLOOR then return false end
  if pri == PRI.LOW and now - lastLow < LOW_SPACING then return false end
  if pri == PRI.NORMAL and now - lastNormal < NORMAL_SPACING then return false end
  return true
end

function AK:PlaySfx(cue)
  if not enabled() then return end
  local def = CUES[cue]
  if not def then return end

  local now = GetTime()
  if not permitted(cue, def, now) then return end
  if not playCue(cue, def) then return end

  local pri = def.pri or PRI.NORMAL
  playCounts[cue] = (playCounts[cue] or 0) + 1
  lastPlayed[cue], lastAny = now, now
  if pri == PRI.LOW then lastLow = now elseif pri == PRI.NORMAL then lastNormal = now end
  -- Duck the engine for anything that carries meaning, so a boost or a lap is
  -- heard against near-silence instead of competing with the revs.
  if pri >= PRI.HIGH then lastImportant = now end
end

-- ---------------------------------------------------------------------------
-- ENGINE
--
-- A retriggered one-shot standing in for a loop we cannot have. The previous
-- attempt was removed outright because it was "pure repetition" -- which was
-- true of the implementation, not of the idea. Three things make the difference
-- between an engine and a machine gun, and none of them is the sample:
--
--   RATE CURVE. Interval against speed is a curve, not a line, and it FLATTENS
--   at the top. Most of the audible change happens in the low-mid range where
--   you are actually accelerating; near top speed it stops speeding up, because
--   past roughly 8 notes a second the ear stops hearing events and starts
--   hearing a rattle.
--
--   JITTER. A fixed interval locks into a beat, and a beat is what "repetitive"
--   actually means -- the ear latches onto the grid and then cannot let go.
--   +/-14% of randomised spacing is enough to stop that without sounding loose.
--
--   TWO NOTES, CROSSFADED. One sample repeated is a stutter no matter how it is
--   spaced. Low and high notes with a probabilistic blend band in the middle
--   means the texture keeps changing even at constant speed.
--
-- It also runs in its OWN LANE. It must not go through permitted(): LOW_SPACING
-- is 1.10s, so the engine would be capped at under one note a second, and worse,
-- it would consume lastAny and suppress the cues that actually carry meaning.
-- Instead it ducks -- a HIGH or CRITICAL cue silences it briefly, so the engine
-- gets out of the way of the boost, the lap and the hit rather than fighting
-- them for the same budget.
-- Sparse, and OFF by default. The rate curve, the jitter and the crossfade are
-- all sound engineering, and none of them saves this: the only palette we have
-- is SOUNDKIT, which is UI blips, and a click retriggered four times a second
-- is precisely the "repetitive clicking" that has been the complaint for four
-- rounds. Measured at the original 0.135 the engine alone ran at 3.93/sec.
--
-- The machinery stays because it becomes genuinely good the moment a real
-- engine sample is bound to engineLow/engineHigh with /kart sfxset -- but it
-- has to be opted into, with a sound worth looping, rather than shipped on with
-- a checkbox tick standing in for an engine.
local ENGINE_MIN_GAP = 0.24       -- flat out
local ENGINE_MAX_GAP = 0.85       -- crawling
local ENGINE_DUCK = 0.28          -- silence after anything important
local engineNext = 0
local lastSurface

--- Seconds until the next note. Curved and flattened, never linear.
local function engineGap(ratio)
  local t = AK.Math.Clamp(ratio or 0, 0, 1) ^ 0.62
  return ENGINE_MAX_GAP + (ENGINE_MIN_GAP - ENGINE_MAX_GAP) * t
end

--- Which note. The weighting between the two IS the crossfade.
---
--- Crucially the blend NEVER reaches 0 or 1. A straight clamp made everything
--- above ratio 0.76 pick the high note every single time -- measured, 285 high
--- against 75 low over a lap -- so at racing speed, which is most of a lap, it
--- was one sample repeated three times a second. That is the machine gun, and
--- no choice of sample survives it. Holding the extremes at 6%/82% means the
--- texture keeps moving even at a constant speed.
local function engineNote(ratio, rng)
  local blend = 0.06 + 0.76 * AK.Math.Clamp(((ratio or 0) - 0.30) / 0.45, 0, 1)
  return (rng or math.random()) < blend and "engineHigh" or "engineLow"
end

function AK:UpdateEngine(vehicle, dt)
  if not enabled() or not vehicle then return end

  local material = vehicle.material and vehicle.material.id or "ROAD"
  if material ~= lastSurface then
    lastSurface = material
    if material ~= "ROAD" and material ~= "BOOST" then self:PlaySfx("surfaceEnter") end
  end

  -- Written plainly: the engine is OFF unless switched on. The old double
  -- negative (`not (engineNote ~= false)`) turned a MISSING setting into "on",
  -- which is the opposite of the off-by-default this whole section argues for
  -- -- it only behaved because Database.lua happens to seed the key.
  if not AK.db.settings.engineNote then return end
  local now = GetTime()
  if now - lastImportant < ENGINE_DUCK then return end
  if now < engineNext then return end

  local ratio = AK.Math.Clamp((vehicle.speed or 0) / math.max(1, vehicle.maxSpeed or 1), 0, 1)
  -- Boosting revs past the top of the normal range.
  if (vehicle.boostTime or 0) > 0 then ratio = math.min(1, ratio + 0.18) end
  -- Nothing at a standstill. An idle tick is the most repetitive sound there is
  -- because nothing else is changing to distract from it.
  if ratio < 0.08 then engineNext = now + 0.25 return end

  local cue = engineNote(ratio)
  local def = CUES[cue]
  if def and playCue(cue, def) then
    -- Deliberately does NOT touch lastAny/lastLow/lastNormal. The engine has its
    -- own lane and must never spend the budget the meaningful cues draw on.
    lastPlayed[cue] = now
    playCounts[cue] = (playCounts[cue] or 0) + 1
  end
  engineNext = now + engineGap(ratio) * (0.86 + math.random() * 0.28)
end

--- Layering the same sample a few milliseconds apart is the only way to build
--- weight out of one-shots. Restricted to results and finishes -- layering an
--- incidental cue is just the machine gun with extra steps.
function AK:PlayStinger(cue, layers, spacing)
  if not enabled() then return end
  local def = CUES[cue]
  if not def or not playCue(cue, def) then return end
  lastPlayed[cue], lastAny = GetTime(), GetTime()
  for i = 1, (layers or 3) - 1 do
    C_Timer.After(i * (spacing or 0.055), function()
      local hit = chosen[cue]
      if hit and hit.source ~= "none" then emit(hit.source, hit.id) end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Audition tools. The point of these is that choosing sounds requires hearing
-- them, and the only listener in this loop is the player.
-- ---------------------------------------------------------------------------

local function cueNames()
  local names = {}
  for cue in pairs(CUES) do names[#names + 1] = cue end
  table.sort(names)
  return names
end

--- The slash handler lowercases everything it receives, so "driftStart" arrives
--- as "driftstart" and would never match. Resolve case-insensitively.
local function findCue(name)
  if not name then return nil end
  if CUES[name] then return name end
  local wanted = name:lower()
  for cue in pairs(CUES) do
    if cue:lower() == wanted then return cue end
  end
  return nil
end

--- Walk every cue, announcing each just before it plays, so a bad sample can be
--- identified by name rather than by guessing which of thirty it was.
function AK:AuditionSfx(only)
  if only then
    local cue = findCue(only)
    if not cue then self:Print("No such cue: " .. only) return end
    self:Print("Playing |cffffd100" .. cue .. "|r")
    chosen[cue] = nil
    playCue(cue, CUES[cue])
    return
  end
  local names, delay = cueNames(), 0
  self:Print("Auditioning " .. #names .. " cues, one per second. |cffffd100/kart sfxset <cue> <fileID>|r to replace one.")
  for _, cue in ipairs(names) do
    C_Timer.After(delay, function()
      AK:Print("  " .. cue)
      chosen[cue] = nil
      playCue(cue, CUES[cue])
    end)
    delay = delay + 1.0
  end
end

--- Play a bare FileDataID so the game's own audio library can be explored.
--- Anything that sounds right can be bound to a cue with sfxset.
---
--- Judged on the HANDLE, never on willPlay. This function used to accept
--- `willPlay ~= false` as success, which is precisely the trap documented at
--- emit() above: PlaySoundFile answers true for practically any number and
--- returns a ZERO handle when there is nothing behind it. So `/kart sfxid` and
--- the editor's PLAY ID both reported "played" for every id anyone typed, and
--- the one tool for telling a real sound from a dead number always said yes.
function AK:TrySoundFile(id)
  local ok, _, handle = pcall(PlaySoundFile, id, "SFX")
  if ok and handle and handle ~= 0 then
    self.lastSoundHandle = handle
    self:Print("|cff6bf06bplayed|r file " .. id)
    return true
  end
  -- Nearly everything that has ever actually worked in this addon is a SOUNDKIT
  -- id, so a file miss is worth one try through the kit path -- and the kit
  -- space is named, so a hit there can say what it found.
  local kitOk, _, kitHandle = pcall(PlaySound, id, "SFX")
  if kitOk and kitHandle and kitHandle ~= 0 then
    self.lastSoundHandle = kitHandle
    local name = self:SoundName(id)
    self:Print(("|cff6bf06bplayed|r kit %d%s"):format(id, name and ("  " .. name) or ""))
    return true
  end
  self:Print("|cffff5555nothing plays at|r " .. id)
  return false
end

function AK:SetCueSound(name, id)
  local cue = findCue(name)
  if not cue then self:Print("No such cue: " .. tostring(name)) return end
  self.db.sfxOverride = self.db.sfxOverride or {}
  if id and id > 0 then
    self.db.sfxOverride[cue] = id
    chosen[cue] = nil
    self:Print("Bound |cffffd100" .. cue .. "|r to file " .. id)
    playCue(cue, CUES[cue])
  elseif id == 0 then
    -- Explicitly silent, which is a different thing from having no override.
    self.db.sfxOverride[cue] = 0
    chosen[cue] = nil
    self:Print("Muted |cffffd100" .. cue .. "|r")
  else
    self.db.sfxOverride[cue] = nil
    chosen[cue] = nil
    self:Print("Cleared |cffffd100" .. cue .. "|r back to its default")
  end
end

--- Silence one cue, or every cue at once.
---
--- Reachable now. Nothing called this -- no button, no slash command -- so the
--- one blunt instrument for "the sounds are too much, quiet down while I sort
--- them out" existed only as text in this file. `/kart sfxmute` runs it.
function AK:MuteCue(name)
  if name == "all" then
    self.db.sfxOverride = self.db.sfxOverride or {}
    local muted = 0
    -- Written straight to the override rather than through SetCueSound, which
    -- prints a line per cue: thirty-odd chat lines is its own kind of noise.
    for _, entry in ipairs(self:CueList()) do
      self.db.sfxOverride[entry.cue] = 0
      chosen[entry.cue] = nil
      muted = muted + 1
    end
    self:Print(("Muted all %d cues. |cffffd100/kart sfxclear <cue>|r or the workshop's DEFAULT brings one back."):format(muted))
    return
  end
  self:SetCueSound(name, 0)
end

--- Unmute everything muted by `sfxmute all`, without disturbing real bindings.
function AK:UnmuteAll()
  local overrides = self.db and self.db.sfxOverride
  if not overrides then return end
  local cleared = 0
  for cue, value in pairs(overrides) do
    if value == 0 then
      overrides[cue] = nil
      chosen[cue] = nil
      cleared = cleared + 1
    end
  end
  self:Print(("Unmuted %d cues."):format(cleared))
end

-- ---------------------------------------------------------------------------
-- API for the in-game sound editor (UI/SoundEditor.lua).
-- ---------------------------------------------------------------------------

--- Every cue, sorted, with enough detail to draw a row.
function AK:CueList()
  local list = {}
  for _, cue in ipairs(cueNames()) do
    local def = CUES[cue]
    list[#list + 1] = { cue = cue, pri = def.pri or PRI.NORMAL, cd = def.cd or DEFAULT_CD[def.pri or PRI.NORMAL] }
  end
  return list
end

local PRI_NAME = { [1] = "incidental", [2] = "normal", [3] = "important", [4] = "critical" }

function AK:CueInfo(cue)
  cue = findCue(cue)
  if not cue then return nil end
  local def = CUES[cue]
  local override = self.db and self.db.sfxOverride and self.db.sfxOverride[cue]
  local hit = chosen[cue]
  return {
    cue = cue,
    override = override,
    priority = PRI_NAME[def.pri or PRI.NORMAL],
    cooldown = def.cd or DEFAULT_CD[def.pri or PRI.NORMAL],
    source = hit and hit.source or nil,
    id = hit and hit.id or nil,
    kit = def.kit and table.concat(def.kit, ", ") or "",
    -- How hard this cue actually worked last race. Min-gap is what the cue is
    -- ALLOWED to do; this is what it DID, which is the number that matters when
    -- deciding whether a sample is too present. Repetition is a rate, and a
    -- rate cannot be judged from the single audition the editor plays.
    plays = playCounts[cue] or 0,
    perMinute = (GetTime() - statsStart) > 1
      and (playCounts[cue] or 0) * 60 / (GetTime() - statsStart) or 0,
  }
end

--- Walk forward from an id until one actually MAKES A NOISE, and bind it.
---
--- "Next built-in idea" is close to useless when a cue has two candidates and
--- neither is right. What is actually wanted is a way to sweep the library: the
--- vast majority of FileDataIDs are not sounds, so stepping one at a time is
--- mostly pressing a button that does nothing.
---
--- PlaySoundFile reports whether the file existed, so probing is exact and, for
--- everything that does not resolve, silent -- the scan makes noise only when it
--- finds something, which is the moment it stops. Capped per press so a sparse
--- stretch of ids cannot lock the client up.
--- Every SOUNDKIT entry, sorted by id. Built once.
---
--- This is the space worth searching. FileDataIDs are sparse -- the vast
--- majority of numbers are not sounds at all -- so stepping through them is
--- hunting for needles, and every sound in this addon that has ever actually
--- worked is a SOUNDKIT id played through PlaySound. The kit table is dense,
--- every entry is real, and each one has a NAME, which turns "step a number and
--- hope" into browsing a labelled library.
local kitList
local function kitEntries()
  if kitList then return kitList end
  kitList = {}
  for name, id in pairs(SOUNDKIT or {}) do
    if type(id) == "number" then kitList[#kitList + 1] = { name = name, id = id } end
  end
  table.sort(kitList, function(a, b) return a.id < b.id end)
  return kitList
end

--- The SOUNDKIT name for an id, when there is one.
function AK:SoundName(id)
  for _, entry in ipairs(kitEntries()) do
    if entry.id == id then return entry.name end
  end
end

-- How far a single NEXT SOUND press will hunt before giving up.
local SCAN_LIMIT = 4000

-- The last thing the bench started, so it can be stopped again. Some sounds in
-- the library are minutes long -- music beds, ambience loops -- and auditioning
-- one with no way to stop it means sitting through it or reloading.
local lastPreview

--- Stop whatever the bench is currently playing.
function AK:StopPreview()
  -- Checked separately, NOT via ipairs over a table of both: ipairs stops at
  -- the first nil, so a missing first handle would silently skip the second.
  if lastPreview and StopSound then pcall(StopSound, lastPreview) end
  if self.lastSoundHandle and StopSound then pcall(StopSound, self.lastSoundHandle) end
  lastPreview, self.lastSoundHandle = nil, nil
end

--- Probe an id without leaving a sound ringing.
---
--- The only way to ask "is this a sound" is to play it, but a scan that plays
--- every candidate is a wall of noise. Playing and immediately stopping by
--- handle makes a probe near-silent, and a dead id has no handle to stop
--- anyway. Returns the handle, or nil.
local function probe(id)
  local ok, willPlay, handle = pcall(PlaySound, id, "SFX")
  if ok and willPlay and handle and handle ~= 0 then
    if StopSound then pcall(StopSound, handle) end
    return handle
  end
end

--- Bind the next id after `from` that actually makes a noise.
---
--- Walks EVERY SoundKitID, not just the named ones. The named SOUNDKIT
--- constants are a small subset that Blizzard's own UI happens to use -- the
--- game has far more valid kit ids in between, and stepping only the named ones
--- skipped most of the library, which is exactly the "skips a lot of sounds"
--- report. Kit ids are dense enough that this usually moves only a few numbers.
function AK:NextAvailableSound(cue, from)
  cue = findCue(cue)
  if not cue then return nil end
  local id = math.max(0, from or 0)
  for _ = 1, SCAN_LIMIT do
    id = id + 1
    if probe(id) then
      self.db.sfxOverride = self.db.sfxOverride or {}
      self.db.sfxOverride[cue] = id
      chosen[cue] = nil
      -- Play it properly now that it is the chosen one; the probe was stopped.
      -- Anything already ringing is cut first, so stepping quickly does not
      -- stack half a dozen overlapping sounds on top of each other.
      self:StopPreview()
      local _, _, handle = pcall(PlaySound, id, "SFX")
      lastPreview = handle
      return id, self:SoundName(id)
    end
  end
  return nil
end

--- How dense is the sound library around here?
---
--- Answers "do all the numbers have sounds" with a measurement instead of an
--- opinion. Probes a run of ids and reports how many actually played -- each
--- probe is stopped immediately, so this is a search, not a performance.
function AK:SoundDensity(from, count)
  from = tonumber(from) or 1
  count = math.min(tonumber(count) or 200, 1000)
  local hits, names, first = 0, 0, nil
  for id = from, from + count - 1 do
    if probe(id) then
      hits = hits + 1
      first = first or id
      if self:SoundName(id) then names = names + 1 end
    end
  end
  self:Print(("|cffffd100sound density|r %d..%d: %d of %d play (%.0f%%), %d of those are named")
    :format(from, from + count - 1, hits, count, hits / count * 100, names))
  if first then self:Print(("  first playable here: %d %s"):format(first, self:SoundName(first) or "")) end
end

--- Report exactly what the client does with an id, instead of guessing.
---
--- Sound is the one system here with no offline harness and no visible failure
--- mode: a call that does nothing and a call that plays something look
--- identical from the outside, and the return values are the only evidence
--- there is. Two rounds of reasoning about why "nothing plays" produced two
--- wrong answers, so this prints the raw truth -- the pcall status, the exact
--- value and type each API returned, and whether the game's own sound is even
--- switched on -- and hands it to the person who can hear the result.
function AK:TestSound(id)
  id = tonumber(id)
  if not id then self:Print("Usage: /kart sfxtest <id>") return end

  local function report(label, fn)
    local ok, a, b = pcall(fn, id, "SFX")
    self:Print(("  %s -> ok=%s  willPlay=%s (%s)  handle=%s"):format(
      label, tostring(ok), tostring(a), type(a), tostring(b)))
    return ok and a
  end

  self:Print(("|cffffd100sfxtest %d|r"):format(id))
  report("PlaySoundFile", PlaySoundFile)
  report("PlaySound", PlaySound)
  -- No channel argument at all: if the two above are silent but this is not,
  -- the channel name is the problem rather than the id.
  local ok, a = pcall(PlaySoundFile, id)
  self:Print(("  PlaySoundFile (no channel) -> ok=%s  willPlay=%s"):format(
    tostring(ok), tostring(a)))

  self:Print(("  addon sfx setting: %s"):format(tostring(AK.db.settings.sfx)))
  self:Print(("  SOUNDKIT table: %s"):format(SOUNDKIT and "present" or "MISSING"))
  if GetCVar then
    self:Print(("  CVars  Sound_EnableAllSound=%s  Sound_EnableSFX=%s  Sound_SFXVolume=%s"):format(
      tostring(GetCVar("Sound_EnableAllSound")), tostring(GetCVar("Sound_EnableSFX")),
      tostring(GetCVar("Sound_SFXVolume"))))
  end
end

--- Hear a cue AT ITS OWN RATE, not once.
---
--- Auditioning a sample once tells you what it sounds like; it tells you
--- nothing about whether it will drive you mad, and "repetitive" is precisely a
--- property you cannot hear in a single play. This fires the cue eight times at
--- the minimum gap it is actually allowed, which is the worst case the player
--- will ever be exposed to.
function AK:AuditionRate(cue)
  cue = findCue(cue)
  if not cue then return false end
  local def = CUES[cue]
  local gap = math.max(0.08, def.cd or DEFAULT_CD[def.pri or PRI.NORMAL])
  -- The engine has no cooldown because it is gated by its own rate curve, so
  -- audition it at the fastest spacing that curve can actually produce.
  if cue == "engineLow" or cue == "engineHigh" then gap = ENGINE_MIN_GAP end
  for i = 0, 7 do
    C_Timer.After(i * gap, function() self:PreviewCue(cue) end)
  end
  self:Print(("%s x8 at %.2fs -- its worst case"):format(cue, gap))
  return true
end

--- Play a cue immediately, ignoring the rate limiter. Auditioning must never be
--- suppressed by the very throttling it is being used to tune.
function AK:PreviewCue(cue)
  cue = findCue(cue)
  if not cue then return false end
  chosen[cue] = nil
  return playCue(cue, CUES[cue])
end

--- Which FileDataIDs in a range actually exist on this client.
---
--- PlaySoundFile is the only way to ask, and it answers by starting playback --
--- so each hit is stopped again immediately. That leaves a scan audible as a
--- short flurry rather than as every sound in the range playing in full.
--- Judged on the HANDLE, for the same reason TrySoundFile is: willPlay is true
--- for practically any number, so the old test kept EVERY id in the range and
--- reported "200 of 200 playable". That is the scanner's entire job done
--- backwards -- it turned "here are the real ones" back into "guess a number",
--- and every PREV/NEXT step through the results then played silence.
function AK:ScanSoundFiles(startID, count)
  local found = {}
  count = math.min(count or 100, 400)
  for id = startID, startID + count - 1 do
    local ok, _, handle = pcall(PlaySoundFile, id, "SFX")
    if ok and handle and handle ~= 0 then
      found[#found + 1] = id
      if StopSound then pcall(StopSound, handle) end
    end
  end
  return found
end

--- Ground truth for what every cue actually resolved to, plus any bindings, in
--- a form that can be pasted straight back into a conversation.
function AK:DebugSfx()
  self:Print("Cue -> resolved source (|cffffd100*|r = your binding):")
  for _, cue in ipairs(cueNames()) do
    local override = self.db and self.db.sfxOverride and self.db.sfxOverride[cue]
    local hit = chosen[cue]
    local what
    if override then
      what = "|cffffd100*file " .. override .. "|r"
    elseif hit and hit.source ~= "none" then
      what = hit.source .. " " .. hit.id
    elseif hit then
      what = "|cffff5555unresolved|r"
    else
      what = "|cff808080not yet played|r"
    end
    self:Print(("  %-14s %s"):format(cue, what))
  end
end
