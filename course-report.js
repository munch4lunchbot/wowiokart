// Course analysis.
//
// Ports Builder:Compile and the renderer's projection so a track's shape can be
// measured rather than guessed at: how much elevation it actually has, whether
// any crest is steep enough to hide the road beyond it, how much of the lap is
// spent cornering, and how long each named section lasts at racing speed.
//
//   node course-report.js [trackId]
const fs = require("fs");
const path = require("path");

const SRC = fs.readFileSync(path.join(__dirname, "Data/Tracks.lua"), "utf8");
const STEP = 2;
const CURVE_GAIN = 0.0021;
const GRADE_GAIN = +(process.env.GRADE_GAIN || 0.022);

// Camera/tuning defaults, from Tuning.lua.
const CAM = { depth: 0.95, height: 5.3, back: 6.0, horizon: 150 };
const HALF_H = 400;            // half the race frame height, roughly
const CURVE_SCALE = 30;
const AVG_SPEED = 65;          // m/s at racing pace

function parseTracks() {
  const tracks = [];
  const re = /\n  \{\n    id = "(\w+)", name = "([^"]+)"/g;
  let m;
  const starts = [];
  while ((m = re.exec(SRC))) starts.push({ id: m[1], name: m[2], at: m.index });
  for (let i = 0; i < starts.length; i++) {
    const body = SRC.slice(starts[i].at, i + 1 < starts.length ? starts[i + 1].at : SRC.length);
    const lengthM = body.match(/length = (\d+), laps = (\d+)/);
    if (!lengthM) continue;
    const layoutStart = body.indexOf("layout = {");
    if (layoutStart === -1) continue;
    const layoutEnd = body.indexOf("\n    }", layoutStart);
    const layoutSrc = body.slice(layoutStart, layoutEnd);
    const layout = [...layoutSrc.matchAll(/\{ len = ([\d.]+),([^}]*)\}/g)].map(mm => ({
      len: +mm[1],
      curve: +(mm[2].match(/curve = (-?[\d.]+)/) || [, 0])[1],
      grade: +(mm[2].match(/grade = (-?[\d.]+)/) || [, 0])[1],
      width: +(mm[2].match(/width = ([\d.]+)/) || [, 1])[1],
      ramp: /ramp = true/.test(mm[2]),
      tunnel: /tunnel = true/.test(mm[2]),
      wall: /wall = true/.test(mm[2]),
      name: (mm[2].match(/name = "([^"]+)"/) || [, null])[1],
    }));
    tracks.push({
      id: starts[i].id, name: starts[i].name,
      length: +lengthM[1], laps: +lengthM[2],
      sweep: +(body.match(/sweep = ([\d.]+)/) || [, 2.6])[1],
      layout,
    });
  }
  return tracks;
}

function compile(track) {
  const layout = track.layout;
  const authored = layout.reduce((a, p) => a + p.len, 0);
  const scale = track.length / authored;
  const samples = Math.floor(track.length / STEP) + 1;
  const centre = [], height = [], width = [], owner = [];
  let heading = 0, x = 0, h = 0, pieceIndex = 0, pieceLeft = layout[0].len * scale;
  for (let i = 0; i < samples; i++) {
    const piece = layout[pieceIndex];
    heading += (piece.curve || 0) * CURVE_GAIN * STEP;
    x += heading * STEP;
    h += (piece.grade || 0) * GRADE_GAIN * STEP;
    centre[i] = x; height[i] = h; width[i] = piece.width || 1; owner[i] = pieceIndex;
    pieceLeft -= STEP;
    while (pieceLeft <= 0 && pieceIndex < layout.length - 1) {
      pieceIndex++; pieceLeft += layout[pieceIndex].len * scale;
    }
  }
  const dX = centre[samples - 1] - centre[0], dH = height[samples - 1] - height[0];
  for (let i = 0; i < samples; i++) {
    const t = i / (samples - 1);
    centre[i] -= dX * t; height[i] -= dH * t;
  }
  let low = Infinity, high = -Infinity;
  for (let i = 0; i < samples; i++) { low = Math.min(low, centre[i]); high = Math.max(high, centre[i]); }
  const mid = (low + high) / 2;
  let peak = 0;
  for (let i = 0; i < samples; i++) { centre[i] -= mid; peak = Math.max(peak, Math.abs(centre[i])); }
  if (peak > 0) { const f = track.sweep / peak; for (let i = 0; i < samples; i++) centre[i] *= f; }
  return { centre, height, width, owner, samples, scale };
}

// Does a crest actually hide the road behind it?
//
// The camera sits camHeight above the road under it. Looking forward, a sample
// is occluded when the ground between the camera and that sample rises above
// the sight line to it. That is the thing that makes a hill read as a hill
// instead of as a gentle tint change.
function crestOcclusion(c, samples) {
  let occluded = 0, deepest = 0;
  for (let i = 0; i < samples; i++) {
    const camH = c.height[i] + CAM.height;
    let blockedFrom = null;
    for (let j = 1; j < 90; j++) {          // out to 180m
      const k = (i + j) % samples;
      const dz = j * STEP;
      // Sight line from the camera to this sample.
      const slope = (c.height[k] - camH) / dz;
      // Anything nearer that rises above that line blocks it.
      let blocked = false;
      for (let m = 1; m < j; m++) {
        const km = (i + m) % samples;
        if (c.height[km] > camH + slope * (m * STEP) + 0.05) { blocked = true; break; }
      }
      if (blocked) { blockedFrom = dz; break; }
    }
    if (blockedFrom !== null) { occluded++; deepest = Math.max(deepest, 180 - blockedFrom); }
  }
  return { fraction: occluded / samples, deepest };
}

const tracks = parseTracks();
const only = process.argv[2];
console.log("GRADE_GAIN = " + GRADE_GAIN + "\n");

for (const t of tracks) {
  if (only && t.id !== only) continue;
  const c = compile(t);
  const n = c.samples;

  let hLow = Infinity, hHigh = -Infinity;
  for (let i = 0; i < n; i++) { hLow = Math.min(hLow, c.height[i]); hHigh = Math.max(hHigh, c.height[i]); }
  const relief = hHigh - hLow;

  // Steepest sustained gradient, as a percentage.
  let steepest = 0;
  for (let i = 0; i < n; i++) {
    const j = (i + 5) % n;                   // over 10m
    steepest = Math.max(steepest, Math.abs(c.height[j] - c.height[i]) / 10);
  }

  // Rhythm, measured on the AUTHORED curvature -- the thing the driver has to
  // fight. Measuring lateral movement of the centreline instead counted a
  // diagonal straight as a corner, which is the same mistake the physics made.
  let flat = 0, gentle = 0, hard = 0;
  for (let i = 0; i < n; i++) {
    const k = Math.abs(t.layout[c.owner[i]].curve || 0);
    if (k < 0.3) flat++; else if (k < 2.2) gentle++; else hard++;
  }

  // Screen rise of a 1m step at a typical mid-distance, so relief can be read
  // in pixels rather than in abstract metres.
  const dzMid = 40;
  const pxPerMetreRise = (CAM.depth / dzMid) * HALF_H;

  const occ = crestOcclusion(c, n);

  console.log(`${t.name}  [${t.id}]`);
  console.log(`  ${t.length}m x ${t.laps} laps   lap ~${(t.length / AVG_SPEED).toFixed(0)}s   race ~${(t.length * t.laps / AVG_SPEED / 60).toFixed(1)}min`);
  console.log(`  relief          ${relief.toFixed(1)}m  (${(relief * pxPerMetreRise).toFixed(0)}px of screen rise at 40m out)`);
  console.log(`  steepest grade  ${(steepest * 100).toFixed(1)}%`);
  console.log(`  rhythm          ${(flat/n*100).toFixed(0)}% straight / ${(gentle/n*100).toFixed(0)}% gentle / ${(hard/n*100).toFixed(0)}% hard cornering`);
  console.log(`  crest hides road on ${(occ.fraction * 100).toFixed(0)}% of the lap` +
    (occ.deepest > 0 ? `, up to ${occ.deepest.toFixed(0)}m of road out of sight` : ""));
  const named = t.layout.filter(p => p.name).length;
  const ramps = t.layout.filter(p => p.ramp).length;
  const tunnels = t.layout.filter(p => p.tunnel).length;
  console.log(`  ${t.layout.length} segments, ${named} named, ${ramps} ramps, ${tunnels} tunnels`);
  console.log("");
}
