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
  const seps = [], farSeps = [];
  let taken = 0;
  for (const at of [180, 420, 900]) {
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
  const low = seps[seps.length >> 1];
  const far = farSeps.length ? farSeps[farSeps.length >> 1] : low;
  // The far field is allowed to be softer than the near field -- that is what
  // distance looks like -- but not to vanish.
  const bad = low < WANT || far < WANT_FAR;
  const flag = low < WANT ? "  <-- the road disappears into the verge"
    : (far < WANT_FAR ? "  <-- the road vanishes into the distance" : "");
  console.log(`  ${id.padEnd(16)} near ${low.toFixed(3)}   far ${far.toFixed(3)}${flag}`);
  if (bad) worst.push(id);
}
fs.rmSync(shots, { recursive: true, force: true });
console.log(worst.length
  ? `FAIL: ${worst.join(", ")} -- want ${WANT} separation between road and verge`
  : `PASS: every circuit's road reads against its own verge (want ${WANT}+)`);
process.exit(worst.length ? 1 : 0);
