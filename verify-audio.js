// How often does this game actually make a noise?
//
// "The sounds are repetitive" was the standing complaint for three rounds, and
// every attempt to fix it by rearranging the cue table failed, because which
// blip sits in which slot was never the problem. The problem is RATE, and rate
// was never measured -- so nobody could say whether a change helped.
//
// This simulates a lap of driving against the real gating rules in Audio.lua
// (per-cue cooldowns, per-priority spacing, the global floor, and the engine's
// separate ducked lane) and reports notes-per-second per cue and overall.
//
//   node verify-audio.js              measure the current set
//   node verify-audio.js --no-engine  measure with the engine note off
//
// The pass condition is a rate band, not a taste judgement: under ~1.2 sounds a
// second overall and the race is silent; over ~7 and it is a machine gun.
const fs = require("fs");
const path = require("path");

const SRC = fs.readFileSync(path.join(__dirname, "Audio.lua"), "utf8");
const num = (re, dflt) => { const m = SRC.match(re); return m ? +m[1] : dflt; };

// Read the real gating constants rather than restating them, so this cannot
// drift away from the file it is supposed to be measuring.
const GLOBAL_FLOOR = num(/local GLOBAL_FLOOR = ([\d.]+)/, 0.10);
const LOW_SPACING = num(/local LOW_SPACING = ([\d.]+)/, 1.10);
const NORMAL_SPACING = num(/local NORMAL_SPACING = ([\d.]+)/, 0.30);
const ENGINE_MIN_GAP = num(/local ENGINE_MIN_GAP = ([\d.]+)/, 0.135);
const ENGINE_MAX_GAP = num(/local ENGINE_MAX_GAP = ([\d.]+)/, 0.68);
const ENGINE_DUCK = num(/local ENGINE_DUCK = ([\d.]+)/, 0.28);

const PRI = { LOW: 1, NORMAL: 2, HIGH: 3, CRITICAL: 4 };
const DEFAULT_CD = { 1: 0.90, 2: 0.25, 3: 0.12, 4: 0 };

// Parse the cue table out of Audio.lua.
const CUES = {};
{
  const start = SRC.indexOf("local CUES = {");
  const body = SRC.slice(start, SRC.indexOf("\n}", start));
  for (const m of body.matchAll(/^\s{2}(\w+)\s*=\s*\{([^\n]*)\}/gm)) {
    const [, name, rest] = m;
    const pri = (rest.match(/pri = PRI\.(\w+)/) || [, "NORMAL"])[1];
    const cdm = rest.match(/cd = ([\d.]+)/);
    const kit = [...rest.matchAll(/"([A-Z0-9_]+)"/g)].map(x => x[1]);
    CUES[name] = { pri: PRI[pri], cd: cdm ? +cdm[1] : DEFAULT_CD[PRI[pri]], kit };
  }
}

// Measure what SHIPS. The engine note is a setting, so read its real default
// out of Database.lua rather than assuming it is on -- the first version of
// this harness measured a configuration nobody would actually be playing, and
// then passed it against a 7/sec ceiling that was far too lenient to catch the
// very complaint it exists to prevent.
const DB = fs.readFileSync(path.join(__dirname, "Database.lua"), "utf8");
const ENGINE_DEFAULT = /engineNote = true/.test(DB);
const NO_ENGINE = process.argv.includes("--no-engine")
  || (!ENGINE_DEFAULT && !process.argv.includes("--engine"));

// ---------------------------------------------------------------------------
// The gate, mirroring permitted() + PlaySfx().
const state = { lastPlayed: {}, lastAny: -99, lastLow: -99, lastNormal: -99, lastImportant: -99 };
const counts = {};
let played = 0;

function tryPlay(cue, now, demote) {
  const def = CUES[cue];
  if (!def) return false;
  // Mirrors PlaySfx's `demote`: a rival's cue keeps its cooldown but drops to
  // the incidental class, so what you do always outranks what is done near you.
  const pri = demote && def.pri > demote ? demote : def.pri;
  if (def.cd > 0 && now - (state.lastPlayed[cue] ?? -99) < def.cd) return false;
  if (pri < PRI.CRITICAL) {
    if (now - state.lastAny < GLOBAL_FLOOR) return false;
    if (pri === PRI.LOW && now - state.lastLow < LOW_SPACING) return false;
    if (pri === PRI.NORMAL && now - state.lastNormal < NORMAL_SPACING) return false;
  }
  state.lastPlayed[cue] = now;
  state.lastAny = now;
  if (pri === PRI.LOW) state.lastLow = now;
  else if (pri === PRI.NORMAL) state.lastNormal = now;
  if (pri >= PRI.HIGH) state.lastImportant = now;
  counts[cue] = (counts[cue] || 0) + 1;
  played++;
  return true;
}

// The engine's own lane: no permitted(), no budget spend, but ducked.
let engineNext = 0;
const engineGap = r => ENGINE_MAX_GAP + (ENGINE_MIN_GAP - ENGINE_MAX_GAP) * Math.pow(Math.max(0, Math.min(1, r)), 0.62);
function engineTick(now, ratio, rnd) {
  if (NO_ENGINE) return;
  if (now - state.lastImportant < ENGINE_DUCK) return;
  if (now < engineNext) return;
  if (ratio < 0.08) { engineNext = now + 0.25; return; }
  // Mirrors engineNote: never reaches 0 or 1, so both notes keep appearing.
  const blend = 0.06 + 0.76 * Math.max(0, Math.min(1, (ratio - 0.30) / 0.45));
  const cue = rnd() < blend ? "engineHigh" : "engineLow";
  counts[cue] = (counts[cue] || 0) + 1;
  played++;
  engineNext = now + engineGap(ratio) * (0.86 + rnd() * 0.28);
}

// ---------------------------------------------------------------------------
// A lap of driving. Deterministic, so a change in the numbers is a change in
// the rules and never in the dice.
let seed = 20260825;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };

const LAP = 92;            // seconds, roughly a real lap
const DT = 1 / 60;
let t = 0;

// A corner every ~7s, each with a drift that ladders up; item boxes every ~18s;
// contact every ~11s. These rates come from watching real laps, not from taste.
let nextCorner = 3, nextItem = 8, nextBump = 6, driftEnd = -1, tierNext = 0, tier = 0;
let wasCornering = false;

// --no-crowd-gate measures what shipped before AK:PlaySfxNear existed: every
// rival's item and every rival-on-rival squash played to the player at full
// priority, wherever on the circuit it happened.
const CROWD_GATE = !process.argv.includes("--no-crowd-gate");
// NEIGHBOUR_METRES is 45 on a ~2400m lap with eight karts. A quarter of the
// field being inside that at any moment is generous to the gate's cost, not
// to its benefit.
const NEAR_FRACTION = 0.25;
const RIVALS = 7;
const rivals = [];
for (let i = 0; i < RIVALS; i++) rivals.push({ nextItem: 4 + i * 1.3, nextBump: 9 + i * 2.1 });
let rivalHeard = 0;

for (let frame = 0; frame * DT < LAP; frame++) {
  t = frame * DT;
  // Speed: accelerate on straights, scrub through corners.
  const cornering = t < driftEnd;
  const ratio = cornering ? 0.62 + 0.1 * Math.sin(t * 3) : Math.min(1, 0.72 + 0.28 * Math.sin(t * 0.7));

  if (t >= nextCorner) {
    driftEnd = t + 1.6 + rnd() * 0.9;
    nextCorner = t + 6.0 + rnd() * 3.0;
    tier = 0; tierNext = t;

  }
  // The ladder: three rungs across the drift, once each.
  if (cornering && tier < 3 && t >= tierNext) {
    tier++;
    tryPlay("driftTier" + tier, t);
    tierNext = t + 0.55;
  }
  // Boost fires on the drift's FALLING edge. `t - driftEnd < DT` was true for
  // every frame before the drift ended, so the boost was firing at the corner
  // ENTRY and its global floor then swallowed driftTier1 -- a bug in this
  // simulation, not in the game, and one that would have had me "fixing" the
  // cue table to chase a phantom.
  if (wasCornering && !cornering) {
    tryPlay(tier >= 3 ? "megaBoost" : "boost", t);
  }
  wasCornering = cornering;
  if (t >= nextItem) { tryPlay("item", t); nextItem = t + 14 + rnd() * 9; }
  if (t >= nextBump) {
    tryPlay(rnd() < 0.4 ? "collision" : "bump", t);
    if (rnd() < 0.3) tryPlay("nearMiss", t);
    nextBump = t + 8 + rnd() * 6;
  }
  if (Math.abs(t - LAP / 3) < DT || Math.abs(t - 2 * LAP / 3) < DT) tryPlay("lap", t);

  // THE REST OF THE GRID.
  //
  // This lap used to be a solo time trial: it modelled only what the PLAYER
  // did, which is why the largest single source of noise in a real race sat
  // unmeasured for four rounds. Seven rivals draw an item every few seconds
  // and fire it the moment they have one, and Items.lua played that cue for
  // every vehicle -- so the player heard the whole field's item use at
  // identical volume, on a library that offers no panning and no distance
  // falloff. They also flatten each other, and that bump was played too.
  //
  // Only a quarter of the field is near you at any moment; the rest are
  // somewhere round the circuit and not on screen.
  for (const rival of rivals) {
    if (t >= rival.nextItem) {
      rival.nextItem = t + 6 + rnd() * 7;
      const near = rnd() < NEAR_FRACTION;
      if (near || !CROWD_GATE) {
        // ITEM_SOUND maps most items onto these three.
        const cue = rnd() < 0.45 ? "throw" : (rnd() < 0.6 ? "drop" : "boost");
        if (tryPlay(cue, t, CROWD_GATE ? PRI.LOW : undefined)) rivalHeard++;
      }
    }
    if (t >= rival.nextBump) {
      rival.nextBump = t + 11 + rnd() * 9;
      const near = rnd() < NEAR_FRACTION;
      if (near || !CROWD_GATE) {
        if (tryPlay("bump", t, CROWD_GATE ? PRI.LOW : undefined)) rivalHeard++;
      }
    }
  }

  engineTick(t, ratio, rnd);
}

// ---------------------------------------------------------------------------
const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]);
console.log("Sound rate over one " + LAP + "s lap" + (NO_ENGINE ? "  (engine note OFF)" : ""));
console.log("");
console.log("cue              plays   per second   gap");
for (const [cue, n] of rows) {
  const per = n / LAP;
  console.log("  " + cue.padEnd(14) + String(n).padStart(6) +
    per.toFixed(2).padStart(13) + "   " + (n > 1 ? (LAP / n).toFixed(2) + "s" : "--"));
}

const perSec = played / LAP;
console.log("");
console.log("  TOTAL          " + String(played).padStart(6) + perSec.toFixed(2).padStart(13) +
  "   one sound every " + (LAP / played).toFixed(2) + "s");
console.log("");

// Unwired cues are reported but never failed -- plenty exist for the results
// screen and the menus, which this lap does not touch.
const fired = new Set(Object.keys(counts));
const idle = Object.keys(CUES).filter(c => !fired.has(c) && !c.startsWith("ui"));
if (idle.length) console.log("  not exercised by this lap: " + idle.join(", "));
console.log("");

let bad = 0;
const check = (ok, label) => { console.log("   " + (ok ? "ok  " : "FAIL") + " " + label); if (!ok) bad++; };
check(perSec >= 0.5, "the race makes a noise at all (" + perSec.toFixed(2) + "/s, want >= 0.5)");
// 7.0 was far too generous. A UI blip every quarter second is a machine gun
// whatever the rate curve says, and the ceiling has to reflect the palette we
// actually have rather than the one an engine loop would give us.
check(perSec <= 2.5, "not a machine gun (" + perSec.toFixed(2) + "/s, want <= 2.5)");
console.log("        of which " + rivalHeard + " came from the other seven karts ("
  + (rivalHeard / LAP).toFixed(2) + "/s)"
  + (CROWD_GATE ? "" : "   [--no-crowd-gate: every rival, wherever they are]"));
// The field should be present and never the loudest thing in the race. Run
// with --no-crowd-gate to see what it was: the grid out-shouting the player.
check(rivalHeard / LAP <= 0.6,
  "the field is heard, not the whole grid (" + (rivalHeard / LAP).toFixed(2) + "/s from rivals)");
const ladder = ["driftTier1", "driftTier2", "driftTier3"].every(c => counts[c] > 0);
check(ladder, "every rung of the drift ladder is audible");
const worst = rows.filter(([c]) => !c.startsWith("engine"))[0];
check(!worst || worst[1] / LAP <= 1.2,
  "no single meaningful cue dominates (" + (worst ? worst[0] + " at " + (worst[1] / LAP).toFixed(2) + "/s" : "n/a") + ")");

// TWO EVENTS THAT SOUND THE SAME ARE ONE EVENT.
//
// The candidate lists are tried in order and the FIRST name that resolves is
// what the player hears, so what matters is the lead. Twelve pairs of cues led
// with the same one: firing a shell, being hit by something and a shell
// ricocheting off the verge were all UI_PVP_KILLBLOW, so the three commonest
// events in a race were a single noise. Dropping a banana, scraping a wall and
// losing a place were another. The sound design cannot be judged, let alone
// improved, while the game is saying the same word for different things.
//
// Menu cues are a separate space: they carry `menu = true` and only ever play
// outside a race, so a menu cue and a race cue sharing a lead is not a
// collision anybody can hear.
{
  const table = SRC.slice(SRC.indexOf("local CUES = {"),
    SRC.indexOf("\n}\n", SRC.indexOf("local CUES = {")));
  const leads = { race: {}, menu: {} };
  let parsed = 0;
  for (const m of table.matchAll(/^\s{2}(\w+)\s*=\s*\{([^}]*kit = \{ ([^}]*) \}[^}]*)/gm)) {
    const names = [...m[3].matchAll(/"([^"]+)"/g)].map((x) => x[1]);
    if (!names.length) continue;
    parsed++;
    const space = /menu = true/.test(m[2]) ? "menu" : "race";
    (leads[space][names[0]] = leads[space][names[0]] || []).push(m[1]);
  }
  check(parsed > 30, "the cue table parsed (" + parsed + " cues)");
  const clashes = [];
  for (const space of ["race", "menu"]) {
    for (const [name, cues] of Object.entries(leads[space])) {
      if (cues.length > 1) clashes.push(cues.join(" / ") + " all lead with " + name);
    }
  }
  for (const c of clashes) console.log("        " + c);
  check(clashes.length === 0,
    "every cue leads with a sound of its own (" + clashes.length + " clash(es))");
}

console.log("");
console.log(bad ? "FAIL (" + bad + " problem(s))" : "PASS");
process.exit(bad ? 1 : 0);
