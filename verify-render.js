// Where does the renderer actually PUT things?
//
// The bend model integrates curvature twice, so the road's screen offset grows
// quadratically with how far ahead you look. Past a certain depth the road has
// swung clean off the side of the screen -- and any pickup sitting on it goes
// with it, then swings back in as you close. That is the "things slide in from
// off screen" read, and it is a geometry fact, not a taste question, so it is
// worth having a number for.
//
// This mirrors RaceUI:BuildBend / :Bend / :Project and reports, per track, the
// worst-case lateral offset in units of half-screens at a series of depths.
// >1.0 half-screens means it is off the edge of the display.
//
// Run: node verify-render.js
const fs = require("fs");
const path = require("path");

const ADDON = __dirname;
const tuneSrc = fs.readFileSync(path.join(ADDON, "Tuning.lua"), "utf8");
const def = key => {
  const m = tuneSrc.match(new RegExp('key = "' + key + '"[^}]*?default = (-?[\\d.]+)'));
  return m ? +m[1] : null;
};
const CAM_DEPTH = def("camDepth");
const DRAW = def("drawDistance");
const BEND_DIAL = def("bendGain");
const GAIN = (BEND_DIAL === null ? 10 : BEND_DIAL) / 1000;
const BEND_STEP = 2;

// Mirrors Data/TrackBuilder.lua's smoothed curve table.
function curveTable(body, length) {
  const ls = body.indexOf("layout = {"), le = body.indexOf("\n    },", ls);
  const layout = [...body.slice(ls, le).matchAll(/\{ len = ([\d.]+),([^}]*)\}/g)].map(x => ({
    len: +x[1],
    curve: +((x[2].match(/curve = (-?[\d.]+)/) || [, 0])[1]),
  }));
  const authored = layout.reduce((s, p) => s + p.len, 0), scale = length / authored;
  const STEP = 2, N = Math.floor(length / STEP) + 1;
  const raw = [];
  let pi = 0, left = layout[0].len * scale;
  for (let i = 0; i < N; i++) {
    raw.push(layout[pi].curve || 0);
    left -= STEP;
    while (left <= 0 && pi < layout.length - 1) { pi++; left += layout[pi].len * scale; }
  }
  const sm = [];
  for (let i = 0; i < N; i++) {
    let t = 0;
    for (let k = -15; k <= 15; k++) t += raw[((i + k) % N + N) % N];
    sm.push(t / 31);
  }
  return { table: sm, step: STEP, n: N };
}

// RaceUI:BuildBend -- double integral of curvature, forward from the camera.
function bendFrom(curveAt, camZ, far) {
  const samples = Math.ceil(far / BEND_STEP) + 4;
  const bend = [];
  let offset = 0, lateral = 0;
  for (let i = 0; i < samples; i++) {
    bend.push(offset);
    lateral += curveAt(camZ + i * BEND_STEP) * GAIN * BEND_STEP;
    offset += lateral * BEND_STEP;
  }
  return bend;
}

// RaceUI:Project -- x in HALF-SCREENS, which is the unit that matters here:
// 1.0 is exactly the screen edge regardless of the player's resolution.
const projectHalfScreens = (dz, worldX) => (CAM_DEPTH / dz) * worldX;

const src = fs.readFileSync(path.join(ADDON, "Data", "Tracks.lua"), "utf8");
const starts = [];
const re = /\n  \{\n    id = "(\w+)"/g;
let m; while ((m = re.exec(src))) starts.push({ id: m[1], at: m.index });

const DEPTHS = [80, 140, 200, 260, 330];

console.log("How far off-axis the road projects  (camDepth " + CAM_DEPTH +
  ", bend gain " + GAIN + ", draw " + DRAW + "m)");
console.log("");
console.log("Units are HALF-SCREENS: 1.00 is the screen edge at any resolution.");
console.log("Worst case over a whole lap, so this is the tightest corner on each track.");
console.log("");
console.log("track            " + DEPTHS.map(d => (d + "m").padStart(8)).join(""));

let offscreen = 0;
const worst = {};
for (let i = 0; i < starts.length; i++) {
  const body = src.slice(starts[i].at, i + 1 < starts.length ? starts[i + 1].at : src.length);
  const length = +(body.match(/length = (\d+), laps/) || [, 2600])[1];
  const cv = curveTable(body, length);
  const curveAt = d => cv.table[Math.floor(((d % length) + length) % length / cv.step) % cv.n];

  const peak = DEPTHS.map(() => 0);
  for (let camZ = 0; camZ < length; camZ += 10) {
    const bend = bendFrom(curveAt, camZ, Math.max(...DEPTHS));
    DEPTHS.forEach((dz, k) => {
      const off = Math.abs(projectHalfScreens(dz, bend[Math.round(dz / BEND_STEP)] || 0));
      if (off > peak[k]) peak[k] = off;
    });
  }
  DEPTHS.forEach((d, k) => { worst[d] = Math.max(worst[d] || 0, peak[k]); });
  console.log("  " + starts[i].id.padEnd(15) +
    peak.map(p => (p.toFixed(2) + (p > 1 ? "*" : " ")).padStart(8)).join(""));
}

console.log("");
console.log("  * = past the screen edge; an object at that depth is drawn off-display");
console.log("");
for (const d of DEPTHS) {
  if (worst[d] > 1) offscreen = Math.max(offscreen, d);
}
if (offscreen) {
  const safe = DEPTHS.filter(d => worst[d] <= 1).pop();
  console.log("Road leaves the screen by " + offscreen + "m. Last fully on-screen depth: " +
    (safe ? safe + "m" : "none of the sampled depths"));
}
console.log("");

// Demanding that objects NEVER go off-axis is impossible and wrong: in a hairpin
// the road genuinely does leave the screen, and it should. The edge fade in
// RenderObjects is what stops an off-axis object being seen travelling.
//
// So the question worth checking is the opposite one -- whether that fade is so
// eager that pickups vanish in corners, exactly when the player needs to read
// them. This reports how much of each lap an object at a given depth is fully
// visible, partly faded, or gone.
const EDGE_FADE = 0.62, EDGE_GONE = 1.02;   // must match RaceUI:EdgeFade
const OBJ_FAR = Math.round(DRAW * 0.36);
const SAMPLE = [60, 100, 140, OBJ_FAR];

console.log("Object visibility over a lap  (edge fade " + EDGE_FADE + "-" + EDGE_GONE +
  " half-screens, objects drawn to " + OBJ_FAR + "m)");
console.log("");
// Mirrors RaceUI:EdgeFade. The band is a RAMP, not a cliff -- an object at 0.7
// half-screens is at ~80% alpha and perfectly readable -- so "still readable"
// is alpha >= 0.5, not "has not started fading at all". Counting the start of
// the ramp as invisible made a wider, gentler fade look like a regression.
const edgeAlpha = off => off <= EDGE_FADE ? 1
  : Math.max(0, Math.min(1, (EDGE_GONE - off) / (EDGE_GONE - EDGE_FADE)));

console.log("track            " + SAMPLE.map(d => (d + "m").padStart(9)).join("") +
  "     <- % of lap readable (alpha >= 0.5)");

let worstVisible = 100;
for (let i = 0; i < starts.length; i++) {
  const body = src.slice(starts[i].at, i + 1 < starts.length ? starts[i + 1].at : src.length);
  const length = +(body.match(/length = (\d+), laps/) || [, 2600])[1];
  const cv = curveTable(body, length);
  const curveAt = d => cv.table[Math.floor(((d % length) + length) % length / cv.step) % cv.n];

  const full = SAMPLE.map(() => 0);
  let n = 0;
  for (let camZ = 0; camZ < length; camZ += 5) {
    const bend = bendFrom(curveAt, camZ, Math.max(...SAMPLE) + 8);
    SAMPLE.forEach((dz, k) => {
      const off = Math.abs(projectHalfScreens(dz, bend[Math.round(dz / BEND_STEP)] || 0));
      if (edgeAlpha(off) >= 0.5) full[k]++;
    });
    n++;
  }
  const pct = full.map(f => f / n * 100);
  worstVisible = Math.min(worstVisible, pct[0]);
  console.log("  " + starts[i].id.padEnd(15) +
    pct.map(p => (p.toFixed(0) + "%").padStart(9)).join(""));
}

console.log("");
console.log("  A near pickup (60m) must be readable nearly all the time -- that is the");
console.log("  one the player actually steers at. Depth only costs visibility in corners.");
console.log("");
// --- how much of each element class is actually ON SCREEN at its own range ---
//
// Pickups are not the only discrete thing in the world, and until now they were
// the only ones this harness looked at. Posts are drawn to 0.8 of the draw
// distance, arches to 0.9, the finish gantry to 0.75 -- all far beyond where the
// road reliably still is. Everything out there either slid in from the screen
// edge (before the fade was applied to them) or is simply faded away most of the
// time (after), and neither is a scene: one is ugly, the other is bare.
//
// So the range each class is drawn to is a real decision, and this is the
// number it should be made from -- what fraction of a lap something at the FAR
// end of that range is actually readable.
console.log("Scene elements at the far end of their own draw range");
console.log("");
console.log("  element        range      readable at that range");

// These must match the `*Far` values in UI/RaceUI.lua.
const CLASSES = [
  { name: "objects", far: 0.36 },
  { name: "posts", far: 0.36 },
  { name: "spectators", far: 0.40 },
  { name: "arches", far: 0.38 },
  { name: "finish", far: 0.40 },
];

const tracks = [];
for (let i = 0; i < starts.length; i++) {
  const body = src.slice(starts[i].at, i + 1 < starts.length ? starts[i + 1].at : src.length);
  const length = +(body.match(/length = (\d+), laps/) || [, 2600])[1];
  const cv = curveTable(body, length);
  tracks.push({ length, curveAt: d => cv.table[Math.floor(((d % length) + length) % length / cv.step) % cv.n] });
}

let thinnest = { name: "-", pct: 100 };
for (const cls of CLASSES) {
  const dz = Math.round(DRAW * cls.far);
  let worst = 100;
  for (const t of tracks) {
    let seen = 0, n = 0;
    for (let camZ = 0; camZ < t.length; camZ += 5) {
      const bend = bendFrom(t.curveAt, camZ, dz + 8);
      const off = Math.abs(projectHalfScreens(dz, bend[Math.round(dz / BEND_STEP)] || 0));
      if (edgeAlpha(off) >= 0.5) seen++;
      n++;
    }
    worst = Math.min(worst, seen / n * 100);
  }
  if (worst < thinnest.pct) thinnest = { name: cls.name, pct: worst };
  console.log("  " + cls.name.padEnd(14) + (dz + "m").padStart(6) + "   " +
    worst.toFixed(0).padStart(3) + "%  " + (worst >= 50 ? "" : "<- mostly faded away; drawn past where the road is"));
}
console.log("");
console.log("  Anything under 50% is being drawn into space the road has already left,");
console.log("  so most of what is spawned out there is never seen. Pull the range in.");
console.log("");

const pass = worstVisible >= 85 && thinnest.pct >= 50;
console.log(pass
  ? "PASS (nearest objects visible " + worstVisible.toFixed(0) +
    "% of the lap; thinnest class " + thinnest.name + " at " + thinnest.pct.toFixed(0) + "%)"
  : (worstVisible < 85
    ? "FAIL (nearest objects fade out too often: " + worstVisible.toFixed(0) + "% of the lap)"
    : "FAIL (" + thinnest.name + " is drawn to a range where it is only visible " +
      thinnest.pct.toFixed(0) + "% of the lap)"));
process.exit(pass ? 0 : 1);
