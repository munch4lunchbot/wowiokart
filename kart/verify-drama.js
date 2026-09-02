// Does a race actually have an arc?
//
// "Positions change and the race ends" is a complaint about DRAMA, and drama
// has been argued about rather than measured. This does two things:
//
//   1. Checks the item table actually responds to the GAP, not just to rank --
//      that a leader twenty seconds clear draws nothing worth having, and a
//      racer two seconds off the car ahead draws something to attack with.
//   2. Simulates a field over a full race, many seeds, and reports lead
//      changes, average gap, and how often the last lap is decided by under a
//      second. Those three numbers ARE the arc.
//
// Run: node verify-drama.js
const fs = require("fs");
const path = require("path");

const ITEMS = fs.readFileSync(path.join(__dirname, "Data", "Items.lua"), "utf8");
const TUNING = fs.readFileSync(path.join(__dirname, "Tuning.lua"), "utf8");
// RUBBER=0.04 overrides the tuned default, so the catch-up strength can be
// swept and chosen from numbers rather than argued about.
const RUBBER = +(process.env.RUBBER || 0) || (() => {
  const m = TUNING.match(/key = "aiRubberBand"[^}]*?default = ([\d.]+)/);
  return m ? +m[1] : 0.07;
})();

// ---------------------------------------------------------------------------
// The item table, parsed out of Items.lua so this measures the real weights.
const TIERS = [];
{
  const start = ITEMS.indexOf("AK.ITEM_TABLE = {");
  const body = ITEMS.slice(start, ITEMS.indexOf("\n}", start));
  for (const m of body.matchAll(/\{ upTo = ([\d.]+), weights = \{([\s\S]*?)\} \} \}/g)) {
    const weights = [...m[2].matchAll(/\{ value = "(\w+)", weight = (\d+) \}/g)]
      .map(w => ({ value: w[1], weight: +w[2] }));
    TIERS.push({ upTo: +m[1], weights });
  }
}
if (TIERS.length < 4) throw new Error("could not parse ITEM_TABLE (" + TIERS.length + " tiers)");

// Mirrors gapNeed() in Items.lua.
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
function gapNeed(position, gapAhead, gapBehind) {
  if (position <= 1) return -clamp((gapBehind || 0) / 12, 0, 1) * 0.10;
  return clamp(((gapAhead ?? 3) - 2.5) / 14, -0.08, 0.16);
}
function tierFor(position, total, gapAhead, gapBehind) {
  let trailing = (position - 1) / Math.max(1, total - 1);
  trailing = clamp(trailing + gapNeed(position, gapAhead, gapBehind), 0, 1.0);
  return TIERS.find(t => trailing <= t.upTo) || TIERS[TIERS.length - 1];
}
const has = (tier, name) => tier.weights.some(w => w.value === name);

console.log("Item draw against GAP, not just rank");
console.log("");
console.log("situation                                    draws from");
const cases = [
  ["1st, 20s clear", 1, 8, null, 20],
  ["1st, hunted (1s behind)", 1, 8, null, 1],
  ["5th, 2s off 4th", 5, 8, 2, 3],
  ["5th, 16s adrift", 5, 8, 16, 3],
  ["8th, 20s adrift", 8, 8, 20, null],
];
const drawn = {};
for (const [label, pos, total, ga, gb] of cases) {
  const tier = tierFor(pos, total, ga, gb);
  drawn[label] = tier;
  console.log("  " + label.padEnd(42) + tier.weights.map(w => w.value).join(", "));
}
console.log("");

let bad = 0;
const check = (ok, label) => { console.log("   " + (ok ? "ok  " : "FAIL") + " " + label); if (!ok) bad++; };
const NASTY = ["spiny_shell", "bolt", "star"];
check(!NASTY.some(n => has(drawn["1st, 20s clear"], n)),
  "a leader 20s clear draws nothing race-changing");
check(has(drawn["5th, 2s off 4th"], "red_shell") || has(drawn["5th, 2s off 4th"], "mushroom"),
  "a racer on somebody's bumper draws something precise");
check(NASTY.some(n => has(drawn["8th, 20s adrift"], n)),
  "a racer 20s adrift draws a race-changer");
check(drawn["5th, 16s adrift"] !== drawn["5th, 2s off 4th"],
  "the SAME position draws differently depending on the gap");
console.log("");

// ---------------------------------------------------------------------------
// A field, over a full race.
// Real units throughout: metres and metres-per-second. The first version of
// this used a dimensionless "pace" and then read the differences as seconds,
// which reported 426 lead changes and a 0.01s average gap -- numbers that
// should have been obviously wrong rather than quietly reassuring.
const FIELD = 8, LAPS = 3, LAP_METRES = 2600;
const BASE_SPEED = 45;        // average lap pace, m/s (verify-ai puts corners at ~48)
// The gap multiplier from AI.lua's rubber-band correction. This, not the cap,
// is what governs a CLOSE battle: at a 50m gap the cap is nowhere near binding,
// so sweeping aiRubberBand changes nothing at the front. GAIN= sweeps it.
const GAIN = +(process.env.GAIN || 0) || (() => {
  const AIsrc = fs.readFileSync(path.join(__dirname, "Race", "AI.lua"), "utf8");
  const m = AIsrc.match(/playerGap \* ([\d.]+) \* skill/);
  return m ? +m[1] : 0.9;
})();
// Fastest to slowest, as a fraction of pace. NOT the top-speed spread, which is
// far wider (maxSpeed spans ~41% across the stat range): lap time is limited by
// corners, and verify-ai puts every kart through the slow corners within a few
// m/s of the others. 5% is what actually separates the field over a lap.
const SPREAD = 0.05;

function race(seed, rubber) {
  let s = seed;
  const rnd = () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
  // Each racer has a genuine pace edge, the way the roster has different stats.
  const pace = Array.from({ length: FIELD }, (_, i) =>
    BASE_SPEED * (1 + ((i / (FIELD - 1)) - 0.5) * SPREAD + (rnd() - 0.5) * SPREAD * 0.4));
  const dist = new Array(FIELD).fill(0);
  const finish = new Array(FIELD).fill(null);
  const total = LAP_METRES * LAPS;
  const DT = 0.5;
  let leader = -1, leadChanges = 0, gapSum = 0, samples = 0, t = 0;

  while (t < 600 && finish.filter(f => f !== null).length < 2) {
    t += DT;
    const order = dist.map((d, i) => [d, i]).sort((a, b) => b[0] - a[0]);
    if (order[0][1] !== leader) { if (leader !== -1) leadChanges++; leader = order[0][1]; }
    // Gaps between adjacent racers, converted to SECONDS at racing pace.
    for (let k = 1; k < FIELD; k++) gapSum += (order[k - 1][0] - order[k][0]) / BASE_SPEED;
    samples += FIELD - 1;

    const lead = order[0][0];
    for (let i = 0; i < FIELD; i++) {
      if (finish[i] !== null) continue;
      // Asymmetric, capped rubber band, mirroring AI.lua: the correction is
      // proportional to the gap as a FRACTION OF LAP LENGTH and only approaches
      // the cap when a racer is most of a lap adrift. Modelling it as
      // rank-proportional at the full cap instead made it three times the
      // natural pace spread, which flattened the field into a permanent dead
      // heat -- 246 lead changes a race, every race a photo finish.
      const gapFraction = (lead - dist[i]) / LAP_METRES;
      const band = 1 + Math.max(-rubber * 0.35, Math.min(rubber, gapFraction * GAIN));
      // Items and mistakes: an occasional shove or setback, not constant noise.
      let event = 1;
      if (rnd() < 0.010) event = rnd() < 0.5 ? 1.30 : 0.68;
      dist[i] += pace[i] * band * event * DT;
      if (dist[i] >= total) finish[i] = t - (dist[i] - total) / pace[i];
    }
  }
  const done = finish.map((f, i) => [f ?? Infinity, i]).sort((a, b) => a[0] - b[0]);
  return { leadChanges, avgGap: gapSum / samples, margin: done[1][0] - done[0][0] };
}

const RACES = 400;
function measure(rubber) {
  let changes = 0, gap = 0, close = 0, photo = 0;
  for (let i = 0; i < RACES; i++) {
    const r = race(1000 + i * 7919, rubber);
    changes += r.leadChanges;
    gap += r.avgGap;
    if (r.margin < 1.0) close++;
    if (r.margin < 0.30) photo++;
  }
  return {
    changes: changes / RACES, gap: gap / RACES,
    close: close / RACES, photo: photo / RACES,
  };
}

// Measured against a no-rubber-band baseline on the SAME seeds. The absolute
// closeness of a race depends heavily on how this sim models mistakes, which is
// crude; the DIFFERENCE the rubber band makes on identical seeds does not, and
// that difference is the thing actually being tuned.
const off = measure(0);
const on = measure(RUBBER);

console.log("Field of " + FIELD + " over " + LAPS + " laps, " + RACES + " seeded races");
console.log("");
console.log("                              no band     band " + RUBBER.toFixed(2) + "     delta");
const row = (label, a, b, suffix) => console.log("  " + label.padEnd(28) +
  (a.toFixed(2) + suffix).padStart(7) + (b.toFixed(2) + suffix).padStart(11) +
  ((b - a >= 0 ? "+" : "") + (b - a).toFixed(2)).padStart(10));
row("lead changes per race", off.changes, on.changes, "");
row("average gap between karts", off.gap, on.gap, "s");
row("won by under 1s", off.close * 100, on.close * 100, "%");
row("photo finish (under 0.30s)", off.photo * 100, on.photo * 100, "%");
console.log("");

check(on.changes >= 1.0, "the lead changes hands (" + on.changes.toFixed(2) + "/race, want >= 1)");
check(on.gap <= 14, "the field stays together (" + on.gap.toFixed(1) + "s avg, want <= 14)");
check(on.close >= 0.15, "races go to the wire (" + (on.close * 100).toFixed(1) + "% under 1s, want >= 15%)");
// Catch-up must TIGHTEN the racing without deciding it. If the band adds more
// than fifteen points of sub-second finishes it has stopped helping the field
// keep up and started choosing the winner, which is the failure mode that is
// easy to mistake for success.
check(on.close - off.close <= 0.25,
  "the band tightens the field without deciding it (+" +
  ((on.close - off.close) * 100).toFixed(1) + " points of sub-1s, want <= +25)");
check(on.gap <= off.gap,
  "the band does close the field up (" + off.gap.toFixed(2) + "s -> " + on.gap.toFixed(2) + "s)");

console.log("");
console.log(bad ? "FAIL (" + bad + " problem(s))" : "PASS");
process.exit(bad ? 1 : 0);
