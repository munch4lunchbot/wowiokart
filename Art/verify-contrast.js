// CAN YOU SEE WHERE THE TRACK IS?
//
// The single most important read in a kart game, and the one thing an authored
// palette cannot promise: Data/Tracks.lua says Ironforge is pale snow beside a
// mid-blue road, which sounds like plenty of contrast, but the renderer draws
// the ground plane at 62% and the road at 100%, lifts the verge toward its own
// luminance, then multiplies both by whatever mean brightness their TEXTURE
// happens to have. What comes out the other end is the only thing that matters.
//
// So this renders every circuit through the real projection and measures the
// pixels: road against verge, at three depths.
//
//   node Art/verify-contrast.js
const { execFileSync } = require("child_process");
const fs = require("fs"), zlib = require("zlib"), path = require("path"), os = require("os");

const ROOT = path.join(__dirname, "..");
const tracks = [...fs.readFileSync(path.join(ROOT, "Data", "Tracks.lua"), "utf8")
  .matchAll(/\n  \{\n    id = "(\w+)"/g)].map((m) => m[1]);

function readPNG(file) {
  const b = fs.readFileSync(file);
  let p = 8, w = 0, h = 0; const idat = [];
  while (p < b.length) {
    const len = b.readUInt32BE(p), type = b.toString("ascii", p + 4, p + 8);
    if (type === "IHDR") { w = b.readUInt32BE(p + 8); h = b.readUInt32BE(p + 12); }
    if (type === "IDAT") idat.push(b.slice(p + 8, p + 8 + len));
    p += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat)), bpp = 3, stride = w * bpp;
  const out = Buffer.alloc(h * stride);
  for (let y = 0; y < h; y++) {
    const ft = raw[y * (stride + 1)];
    const line = raw.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? out[y * stride + x - bpp] : 0;
      const up = y > 0 ? out[(y - 1) * stride + x] : 0;
      const ul = (x >= bpp && y > 0) ? out[(y - 1) * stride + x - bpp] : 0;
      let v = line[x];
      if (ft === 1) v += a;
      else if (ft === 2) v += up;
      else if (ft === 3) v += (a + up) >> 1;
      else if (ft === 4) {
        const pp = a + up - ul, pa = Math.abs(pp - a), pb = Math.abs(pp - up), pc = Math.abs(pp - ul);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? up : ul);
      }
      out[y * stride + x] = v & 255;
    }
  }
  return { w, h, out, stride };
}

/** Median colour of a small patch, so one prop or kart cannot move the answer. */
function patch(im, x0, y0, size) {
  const rs = [], gs = [], bs = [];
  for (let y = y0; y < y0 + size; y++) {
    for (let x = x0; x < x0 + size; x++) {
      const i = y * im.stride + x * 3;
      rs.push(im.out[i]); gs.push(im.out[i + 1]); bs.push(im.out[i + 2]);
    }
  }
  const mid = (a) => a.sort((p, q) => p - q)[a.length >> 1] / 255;
  return [mid(rs), mid(gs), mid(bs)];
}

const lum = (c) => 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2];
/** Luminance distance plus chroma distance -- either alone is enough to read. */
function separation(a, b) {
  const la = lum(a), lb = lum(b);
  const ca = a.map((v) => v - la), cb = b.map((v) => v - lb);
  return Math.abs(la - lb) + Math.hypot(ca[0] - cb[0], ca[1] - cb[1], ca[2] - cb[2]);
}

// Sampled from every strip whose verge is actually on screen, in the near half
// of the frame where the distance haze has not yet drained the colour out of
// everything. Where the road IS at each of them comes from the renderer itself:
// a fixed pair of coordinates lands on grass at one bend and on tarmac at the
// next, and the first version of this check duly reported that Elwynn's brown
// road was indistinguishable from its green verge.
const WANT = 0.20;
const WANT_FAR = 0.13;
// A TUNNEL WALL IS A VERGE YOU CANNOT DRIVE ONTO, so it is held to the same
// standard as one. Reported three times as hard to see, and never measured.
const WANT_WALL = 0.20;
const wallWorst = [];

// WHERE EACH CIRCUIT GOES UNDER COVER.
//
// The road/verge measurement below deliberately skips covered strips: outside a
// shaft there is no verge to compare against. That left the tunnels measured by
// nobody -- and "the walls are hard to see" has now been reported three times.
// The wall is what the verge is, underground, so it gets the same treatment: a
// number, sampled from the rendered frame, at a distance chosen from the
// circuit's own layout rather than guessed.
const trackSrc = fs.readFileSync(path.join(ROOT, "Data", "Tracks.lua"), "utf8");
function tunnelMidpoint(id) {
  const at = trackSrc.indexOf(`id = "${id}"`);
  if (at < 0) return null;
  const next = trackSrc.indexOf('\n  {\n    id = "', at);
  const body = trackSrc.slice(at, next < 0 ? trackSrc.length : next);
  const length = +((body.match(/length = (\d+)/) || [, 2600])[1]);
  const pieces = [...body.matchAll(/\{ len = (\d+),([^}]*)\}/g)]
    .map((m) => ({ len: +m[1], tunnel: /tunnel = true/.test(m[2]) }));
  if (!pieces.length) return null;
  const authored = pieces.reduce((sum, p) => sum + p.len, 0);
  const scale = length / authored;
  // The middle of the LONGEST span, so the sample is deep inside rather than in
  // a mouth where the fade is still coming up.
  let best = null, spanFrom = null, walked = 0;
  for (const piece of pieces) {
    const from = walked, to = walked + piece.len * scale;
    if (piece.tunnel && spanFrom === null) spanFrom = from;
    if (!piece.tunnel && spanFrom !== null) {
      if (!best || from - spanFrom > best.len) best = { at: (spanFrom + from) / 2, len: from - spanFrom };
      spanFrom = null;
    }
    walked = to;
  }
  if (spanFrom !== null && (!best || walked - spanFrom > best.len)) {
    best = { at: (spanFrom + walked) / 2, len: walked - spanFrom };
  }
  return best && best.len > 30 ? Math.round(best.at) : null;
}

const shots = fs.mkdtempSync(path.join(os.tmpdir(), "kartcontrast-"));
const worst = [];
// One circuit at a time while tuning: ONLY=deadmines node Art/verify-contrast.js
const only = process.env.ONLY;
for (const id of tracks) {
  if (only && id !== only) continue;
  // Three points around the lap. One is not enough: at 420m Deadmines is inside
  // a shaft from horizon to bumper, so every strip is covered and there is
  // nothing to measure -- which the first version of this reported, accurately,
  // as "0 usable samples".
  const seps = [], farSeps = [], wallSeps = [];
  let taken = 0, wallTaken = 0;
  const underground = tunnelMidpoint(id);
  const stops = [180, 420, 900];
  if (underground && !stops.includes(underground)) stops.push(underground);
  for (const at of stops) {
    const out = path.join(shots, id + "-" + at + ".png");
    const rowFile = path.join(shots, id + "-" + at + ".json");
    execFileSync("node", [path.join(__dirname, "preview-render.js"), __dirname, out, String(at)],
      { env: { ...process.env, TRACK: id, ROAD_ROWS: rowFile, NOFORK: "1" }, stdio: "ignore" });
    const im = readPNG(out);
    // NEAR and FAR are different questions. Near, the road is most of the
    // screen and it is obvious; far, both it and the ground beside it are
    // washed most of the way to the same haze colour, and "where does the road
    // go" is exactly what stops being answerable. Only the near half was ever
    // measured, so the far half was never a number at all.
    const all = JSON.parse(fs.readFileSync(rowFile, "utf8"))
      // Under cover there is no verge to compare against -- outside the shaft
      // is solid rock -- so a tunnel is measured on the open sections only.
      .filter((r) => r.y < im.h - 8 && (r.cover || 0) < 0.15);
    // THE WALL IS THE VERGE, UNDERGROUND. Sampled just outboard of the road
    // edge on a covered strip, against the road beside it.
    for (const row of JSON.parse(fs.readFileSync(rowFile, "utf8"))) {
      if ((row.cover || 0) < 0.6) continue;
      if (row.y >= im.h - 8 || row.y < im.h * 0.28) continue;
      const half = (row.right - row.left) / 2;
      if (half < 40) continue;
      const roadX = Math.round(row.left + half * 0.5);
      // Far enough out to clear the rumble strip at the road's own edge, close
      // enough to still be wall rather than the dark fill beyond it.
      let wallX = Math.round(row.right + Math.min(26, half * 0.22));
      if (wallX + 8 >= im.w) wallX = Math.round(row.left - Math.min(26, half * 0.22)) - 8;
      if (roadX < 0 || roadX + 8 >= im.w || wallX < 0 || wallX + 8 >= im.w) continue;
      wallSeps.push(separation(patch(im, roadX, row.y, 8), patch(im, wallX, row.y, 8)));
      wallTaken++;
    }

    const rows = all.filter((r) => r.y > im.h * 0.42);
    const farRows = all.filter((r) => r.y <= im.h * 0.42 && r.y > im.h * 0.20);
    for (const row of rows.concat(farRows)) {
      const isFar = row.y <= im.h * 0.42;
      const half = (row.right - row.left) / 2;
      if (half < 40) continue;
      const roadX = Math.round(row.left + half * 0.45);
      // Whichever verge is actually on screen: in the near field the road is
      // wider than the frame on one side.
      let vergeX = Math.round(row.right + half * 0.30);
      if (vergeX + 8 >= im.w) vergeX = Math.round(row.left - half * 0.30) - 8;
      if (roadX < 0 || roadX + 8 >= im.w || vergeX < 0 || vergeX + 8 >= im.w) continue;
      const r = patch(im, roadX, row.y, 8), v = patch(im, vergeX, row.y, 8);
      const sep = separation(r, v);
      taken++;
      if (process.env.DEBUG) {
        console.log("   @" + at + " y" + row.y, "road", r.map((x) => x.toFixed(2)).join(","),
          "verge", v.map((x) => x.toFixed(2)).join(","), "sep", sep.toFixed(3));
      }
      (isFar ? farSeps : seps).push(sep);
    }
  }
  if (taken < 8) {
    console.log(`  ${id.padEnd(16)} only ${taken} usable samples -- check the frame size`);
    worst.push(id);
    continue;
  }
  seps.sort((a, b) => a - b);
  farSeps.sort((a, b) => a - b);
  wallSeps.sort((a, b) => a - b);
  const wall = wallSeps.length ? wallSeps[wallSeps.length >> 1] : null;
  const low = seps[seps.length >> 1];
  const far = farSeps.length ? farSeps[farSeps.length >> 1] : low;
  // The far field is allowed to be softer than the near field -- that is what
  // distance looks like -- but not to vanish.
  const bad = low < WANT || far < WANT_FAR;
  const flag = low < WANT ? "  <-- the road disappears into the verge"
    : (far < WANT_FAR ? "  <-- the road vanishes into the distance" : "");
  // A wall is what you steer away from, so it has to read at least as well as a
  // verge does. Reported for every circuit that has a tunnel; circuits that do
  // not simply say so.
  const wallText = wall === null ? "wall    --"
    : `wall ${wall.toFixed(3)}${wall < WANT_WALL ? " <-- you cannot see the walls" : ""}`;
  console.log(`  ${id.padEnd(16)} near ${low.toFixed(3)}   far ${far.toFixed(3)}   ${wallText}${flag}`);
  if (bad) worst.push(id);
  if (wall !== null && wall < WANT_WALL) wallWorst.push(id);
}
fs.rmSync(shots, { recursive: true, force: true });
if (wallWorst.length) {
  console.log(`  tunnel walls too close to the road: ${wallWorst.join(", ")}`);
}
const failed = worst.concat(wallWorst.filter((id) => !worst.includes(id)));
console.log(failed.length
  ? `FAIL: ${failed.join(", ")} -- want ${WANT} separation from road to verge and wall`
  : `PASS: every circuit's road reads against its verge and its tunnel walls (want ${WANT}+)`);
process.exit(worst.length ? 1 : 0);
