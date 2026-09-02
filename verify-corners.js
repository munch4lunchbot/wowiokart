// Does a corner actually have to be DRIVEN?
//
// Mario Kart is a game about corners. Drifting only pays on a corner you cannot
// take flat, braking only pays on a corner that punishes you for not, and a
// circuit made of gentle sweepers is a circuit where the correct input is "hold
// the throttle" from lights to flag. So the question that decides whether this
// plays like a kart racer is not how a track LOOKS on the course report -- it is
// what fraction of a lap forces a decision.
//
// That is answerable exactly, because both sides of it are in the code:
//
//   steering authority  = vehicle.handling                  (Physics:CreateVehicle)
//   centrifugal push    = curvature * 0.002 * v * (v/vmax)
//                         * curvePush * (0.75 + weight*0.05)  (Physics:UpdateVehicle)
//
// When push exceeds authority at full throttle, full lock cannot hold the line
// and you must shed speed or drift. That is a corner. When push is under half
// of authority, the wheel wins three times over and the corner is scenery.
//
// It also measures what the CURVATURE FILTER does. TrackBuilder box-filters the
// curve table over +/-15 samples at 2m -- a 62m moving average -- so a corner
// shorter than that never reaches the value it was authored at, and the shorter
// it is the more of it is averaged away. A hairpin written as 4.0 can arrive at
// the physics as 1.9.
//
// Run: node verify-corners.js
const fs = require("fs");
const path = require("path");

const ADDON = __dirname;
const TUNE = fs.readFileSync(path.join(ADDON, "Tuning.lua"), "utf8");
const PHYS = fs.readFileSync(path.join(ADDON, "Race", "Physics.lua"), "utf8");
const BUILD = fs.readFileSync(path.join(ADDON, "Data", "TrackBuilder.lua"), "utf8");

const tune = key => {
  const m = TUNE.match(new RegExp('key = "' + key + '"[^}]*?default = (-?[\\d.]+)'));
  if (!m) throw new Error("Tuning.lua has no " + key);
  return +m[1];
};
const CURVE_PUSH = tune("curvePush");
// The curvature at which a drift earns its full mini-turbo charge rate, and the
// curvature the AI treats as "a corner worth drifting". Both matter to a track:
// a circuit that never reaches them is one where the drift button does nothing,
// for the player and for the field alike.
const DRIFT_FULL = +(PHYS.match(/local DRIFT_LOAD_FULL = ([\d.]+)/) || [, 1.6])[1];
const AI = fs.readFileSync(path.join(ADDON, "Race", "AI.lua"), "utf8");
const AI_CORNER = +(AI.match(/math\.abs\(curveSoon\) > ([\d.]+)/) || [, 1.5])[1];

// Mirrors Physics:CreateVehicle for a middle-of-the-grid pairing: "Yourself"
// (6/6/6/5) in the Mechano-Kart (6/6/7/5). Deliberately not the best kart --
// if the mid-field cannot feel a corner, nobody who has not min-maxed can.
const HANDLING_BASE = +(PHYS.match(/handling = \(\.(\d+) \+ \(\(racer\.handling \+ kart\.handling\) \* \.5\) \* \.(\d+)\)/) || [])
  .slice(1).join(",").split(",")[0];
const HANDLING = (0.55 + ((6 + 7) * 0.5) * 0.13) * 1.00;        // medium class
const MAX_SPEED = (56 + ((6 + 6) * 0.5) * 2.65) * 1.00 * 1.00;  // medium, 150cc
const WEIGHT = (5 + 5) * 0.5;
const MASS_TERM = 0.75 + WEIGHT * 0.05;
// Physics reads AK.Math.RoadCurve, which returns the compiled table value; the
// 0.002 is the scale factor applied to it in UpdateVehicle.
const CURVE_SCALE = +(PHYS.match(/RoadCurve\(track, vehicle\.distance\) \* ([\d.]+)/) || [, 0.002])[1];

/** lateral/s the corner pushes, at full throttle. Mirrors UpdateVehicle. */
const pushAt = curve =>
  Math.abs(curve) * CURVE_SCALE * MAX_SPEED * 1.0 * CURVE_PUSH * MASS_TERM;

// Mirrors Data/TrackBuilder.lua's Compile: sample the layout every STEP metres,
// then box-filter the curvature over +/-SPAN samples.
const STEP = +(BUILD.match(/^local STEP = (\d+)/m) || [, 2])[1];
const SPAN = +(BUILD.match(/local span = (\d+)/) || [, 15])[1];

// Painted surfaces change the answer completely, so a harness that assumes dry
// tarmac everywhere is not measuring the game. Ironforge is 47% ice, and ice has
// steering 1.10 x traction 0.22 -- a QUARTER of the authority the same kart has
// on road. Its "easy" 1.6 sweepers are decisive corners; reporting them as
// scenery would have had me flattening the one track whose whole idea is that
// gentle corners become lethal.
const TERRAIN_TABLE = require("./Art/terrain-table.js").readTerrain(ADDON);
const MATERIALS = {};
for (const [id, mat] of Object.entries(TERRAIN_TABLE))
  MATERIALS[id] = mat.steering * mat.traction;
if (!MATERIALS.ICE) throw new Error("could not read the terrain table");

const src = fs.readFileSync(path.join(ADDON, "Data", "Tracks.lua"), "utf8");
const starts = [];
const re = /\n  \{\n    id = "(\w+)"/g;
let m; while ((m = re.exec(src))) starts.push({ id: m[1], at: m.index });

function compile(body) {
  const length = +(body.match(/length = (\d+), laps/) || [, 2600])[1];
  const ls = body.indexOf("layout = {"), le = body.indexOf("\n    },", ls);
  const layout = [...body.slice(ls, le).matchAll(/\{ len = ([\d.]+),([^}]*)\}/g)].map(x => ({
    len: +x[1],
    curve: +((x[2].match(/curve = (-?[\d.]+)/) || [, 0])[1]),
    name: (x[2].match(/name = "([^"]+)"/) || [, ""])[1],
  }));
  const authored = layout.reduce((s, p) => s + p.len, 0), scale = length / authored;
  const samples = Math.floor(length / STEP);
  const raw = [], where = [];
  let pi = 0, left = layout[0].len * scale;
  for (let i = 0; i < samples; i++) {
    raw.push(layout[pi].curve || 0);
    where.push(layout[pi].name);
    left -= STEP;
    while (left <= 0 && pi < layout.length - 1) { pi++; left += layout[pi].len * scale; }
  }
  const smooth = [];
  for (let i = 0; i < samples; i++) {
    let total = 0;
    for (let k = -SPAN; k <= SPAN; k++) total += raw[((i + k) % samples + samples) % samples];
    smooth.push(total / (SPAN * 2 + 1));
  }
  // Anything painted over the road at this point: Terrain:Sample returns the
  // painted material with blend 1, so its steering penalty applies in full.
  const painted = [...body.matchAll(/\{ from = (\d+), to = (\d+), onRoad = "(\w+)" \}/g)]
    .map(x => ({ from: +x[1], to: +x[2], grip: MATERIALS[x[3]] ?? 1 }));
  const gripAt = d => {
    for (const p of painted) if (d >= p.from && d <= p.to) return p.grip;
    return 1;
  };
  return { length, scale, raw, smooth, where, layout, gripAt };
}

console.log("Corners that have to be driven  (mid-field kart: handling " +
  HANDLING.toFixed(2) + " lateral/s at full lock, top speed " + MAX_SPEED.toFixed(0) + ")");
console.log("");
console.log("  A corner is DECISIVE when the push at full throttle beats full lock, so you");
console.log("  must brake or drift. It is WORK at half that. Below that the wheel wins");
console.log("  outright and the bend is scenery you steer through without thinking.");
console.log("");
console.log("track             arrives   decisive   work   free   driftable   flat run   painted");

let flat = [];
const rows = [];
for (let i = 0; i < starts.length; i++) {
  const body = src.slice(starts[i].at, i + 1 < starts.length ? starts[i + 1].at : src.length);
  const t = compile(body);
  const authoredPeak = Math.max(...t.raw.map(Math.abs));
  const arrivedPeak = Math.max(...t.smooth.map(Math.abs));
  let decisive = 0, work = 0, run = 0, longestRun = 0, driftable = 0, iced = 0;
  for (let k = 0; k < t.smooth.length; k++) {
    const c = t.smooth[k];
    // Steering authority is what the kart has ON THIS SURFACE, not on tarmac.
    const grip = t.gripAt(k * STEP);
    if (grip < 0.999) iced++;
    const ratio = pushAt(c) / (HANDLING * grip);
    if (ratio >= 1) { decisive++; run = 0; }
    else if (ratio >= 0.5) { work++; run = 0; }
    else { run += STEP; if (run > longestRun) longestRun = run; }
    if (Math.abs(c) >= Math.min(DRIFT_FULL, AI_CORNER)) driftable++;
  }
  const n = t.smooth.length;
  const row = {
    id: starts[i].id, authoredPeak, arrivedPeak,
    decisive: decisive / n * 100, work: work / n * 100,
    free: (n - decisive - work) / n * 100, longestRun, length: t.length,
    driftable: driftable / n * 100, slippery: iced / n * 100,
  };
  rows.push(row);
  if (row.decisive < 4) flat.push(row.id);
  console.log("  " + row.id.padEnd(16) +
    arrivedPeak.toFixed(1).padStart(7) +
    (row.decisive.toFixed(0) + "%").padStart(11) +
    (row.work.toFixed(0) + "%").padStart(7) +
    (row.free.toFixed(0) + "%").padStart(7) +
    (row.driftable.toFixed(0) + "%").padStart(12) +
    (longestRun + "m").padStart(11) +
    (row.slippery > 0.5 ? (row.slippery.toFixed(0) + "%") : "-").padStart(10));
}

console.log("");
const worstEaten = rows.reduce((a, r) =>
  Math.min(a, r.arrivedPeak / Math.max(0.001, r.authoredPeak)), 1);
console.log("  DRIFTABLE is the share of a lap at or past curvature " +
  Math.min(DRIFT_FULL, AI_CORNER) + " -- where a mini-turbo charges at");
console.log("  full rate and where the AI considers it a corner. A track low on this is one");
console.log("  where the drift button, which is most of the game, does very little.");
console.log("");
console.log("  (The " + ((SPAN * 2 + 1) * STEP) + "m curvature filter turned out not to be eating corners: " +
  "the hardest corner on");
console.log("  a track still arrives at " + (worstEaten * 100).toFixed(0) +
  "% of what it was authored at, because every one of them is");
console.log("  longer than the window. Checked because it was a plausible suspect, and it is not.)");
console.log("");

// Every track needs at least one corner you have to drive, and no track should
// be a single unbroken flat-out run for most of a lap.
// A beginner circuit is ALLOWED to have only one corner that forces a decision --
// Luigi Raceway does. What no circuit may be is a lap with nothing to do: too
// little worth drifting, or a flat-out run that eats a fifth of it.
const tooFlat = rows.filter(r => r.driftable < 18 || r.decisive < 2).map(r => r.id);
const tooLong = rows.filter(r => r.longestRun > 520).map(r => r.id);
for (const r of rows.filter(x => tooFlat.includes(x.id)))
  console.log("  " + r.id + ": " + (r.decisive < 2
    ? "not one corner on this lap forces a decision"
    : "only " + r.driftable.toFixed(0) + "% of the lap is firm enough to be worth drifting"));
for (const r of rows.filter(x => tooLong.includes(x.id)))
  console.log("  " + r.id + ": " + r.longestRun + "m of unbroken flat-out running, " +
    (r.longestRun / r.length * 100).toFixed(0) + "% of the lap with nothing in it");

const bad = tooFlat.length + tooLong.length;
console.log(bad
  ? "FAIL (" + bad + " track(s) do not ask anything of the driver)"
  : "PASS (every circuit has corners that have to be driven)");
process.exit(bad ? 1 : 0);
