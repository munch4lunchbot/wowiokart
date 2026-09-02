// Enforces the kart-texture contract, because breaking it is silent at runtime
// and only shows up as "the rider is buried" or "legs poke through the kart"
// in a screenshot two days later.
//
//   node verify-karts.js [artDir]
//
// The rules, measured off the shipped baseline:
//
//  1. FRONT-SLICE COLLAR. UI/RaceUI.lua repeats the bottom kartLip (0.55) of
//     the texture in front of the driver's legs, which by SetTexCoord is rows
//     72-160. If those rows are not solid across the rider's own column, the
//     legs render through the bodywork. Rows 72-100 at x 80-176 must be ~100%
//     opaque, exactly as kart.tga is.
//
//  2. RIDER WINDOW. Rows 0-24 must be clear across the rider column or the
//     texture eats their head -- these rows sit above the seat back entirely.
//
//  3. DISTINCTNESS, measured only where silhouettes are FREE to differ. Rule 1
//     mandates an identical collar and every kart shares wheels and a shadow,
//     so comparing whole masks scores everything ~96% alike no matter how
//     different the karts look. The free region is everything above the body
//     top plus everything outboard of the body -- fins, wings, horns, gears,
//     tail fans. Two karts agreeing on >92% of THAT are not distinct.
const fs = require("fs");
const path = require("path");

const ART = process.argv[2] || __dirname;
const COL = [80, 176];
const IDS = ["rocket", "mechano", "kodo", "griffon", "minecart", "chicken"];

function load(file) {
  const b = fs.readFileSync(path.join(ART, file));
  const w = b.readUInt16LE(12), h = b.readUInt16LE(14), off = 18 + b[0];
  return { w, h, a: (x, y) => b[off + (y * w + x) * 4 + 3] };
}

let failures = 0;
const masks = {};

for (const id of IDS) {
  const file = "kart-" + id + ".tga";
  if (!fs.existsSync(path.join(ART, file))) {
    console.log("  MISSING " + file); failures++; continue;
  }
  const t = load(file);
  if (t.w !== 256 || t.h !== 160) {
    console.log("  " + id + ": wrong size " + t.w + "x" + t.h); failures++; continue;
  }

  let collar = 0, collarTotal = 0;
  for (let y = 72; y < 100; y++) for (let x = COL[0]; x < COL[1]; x++) {
    if (t.a(x, y) > 128) collar++;
    collarTotal++;
  }
  let head = 0, headTotal = 0;
  for (let y = 0; y < 24; y++) for (let x = COL[0]; x < COL[1]; x++) {
    if (t.a(x, y) > 128) head++;
    headTotal++;
  }
  const collarPct = collar / collarTotal * 100;
  const headPct = head / headTotal * 100;

  const bad = [];
  if (collarPct < 99.5) bad.push("collar " + collarPct.toFixed(1) + "% (needs >=99.5, legs will show through)");
  if (headPct > 1) bad.push("head window " + headPct.toFixed(1) + "% blocked (needs <=1)");

  // Only the region a silhouette may actually shape: above the body top, or
  // outboard of the widest permitted body.
  const mask = [];
  for (let y = 0; y < t.h; y++) for (let x = 0; x < t.w; x++) {
    if (y < 72 || x < 50 || x > 206) mask.push(t.a(x, y) > 128 ? 1 : 0);
  }
  masks[id] = mask;

  console.log("  " + id.padEnd(9) + " collar " + collarPct.toFixed(1).padStart(5) + "%   head clear " +
    (100 - headPct).toFixed(1).padStart(5) + "%   " + (bad.length ? "FAIL: " + bad.join("; ") : "ok"));
  if (bad.length) failures++;
}

// Distinctness: every pair must differ somewhere.
const ids = Object.keys(masks);
let worst = { pair: null, same: -1 };
for (let i = 0; i < ids.length; i++) for (let j = i + 1; j < ids.length; j++) {
  // Intersection over union, not raw agreement. Most of the free region is
  // empty in every kart, and counting matching BLANK pixels as agreement
  // scored wildly different shapes at 94% alike.
  const a = masks[ids[i]], b = masks[ids[j]];
  let both = 0, either = 0;
  for (let k = 0; k < a.length; k++) {
    if (a[k] && b[k]) both++;
    if (a[k] || b[k]) either++;
  }
  const pct = either ? both / either * 100 : 100;
  if (pct > worst.same) worst = { pair: ids[i] + "/" + ids[j], same: pct };
  if (pct > 82) {
    console.log("  TOO SIMILAR: " + ids[i] + " and " + ids[j] + " overlap " + pct.toFixed(1) + "% (IoU)");
    failures++;
  }
}
if (worst.pair) console.log("  most alike pair: " + worst.pair + " " + worst.same.toFixed(1) + "% IoU (limit 82)");

console.log(failures ? "FAIL (" + failures + ")" : "PASS");
process.exit(failures ? 1 : 0);
