// Distant-terrain silhouettes: a jagged mountain ridge and a soft hill line.
//
// The world used to end at one row of identical conifers on a hard horizon
// seam, which is the single strongest "flat cardboard" tell a pseudo-3D scene
// can have. Real depth is faked with LAYERS: far ridge, mid hills, near tree
// wall, each parallaxing at its own rate and each tinted closer to the sky the
// further back it sits. These two textures are the missing layers.
//
// Both are near-white so per-track VertexColor owns the hue, and both wrap
// seamlessly (periodic noise) so they can be tiled and drifted forever.
//
//   node generate-art-skyline.js <outDir>
const fs = require("fs");
const path = require("path");

const OUT = process.argv[2] || ".";

function writeTGA(name, w, h, fn) {
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(w, 12);
  header.writeUInt16LE(h, 14);
  header[16] = 32;
  header[17] = 0x28; // 8-bit alpha + top-left origin
  const body = Buffer.alloc(w * h * 4);
  let i = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const [r, g, b, a] = fn(x, y, w, h);
      body[i++] = Math.max(0, Math.min(255, Math.round(b * 255)));
      body[i++] = Math.max(0, Math.min(255, Math.round(g * 255)));
      body[i++] = Math.max(0, Math.min(255, Math.round(r * 255)));
      body[i++] = Math.max(0, Math.min(255, Math.round(a * 255)));
    }
  }
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([header, body]));
  console.log(name, w + "x" + h);
}

// Periodic value noise so every tile wraps.
function hash(x, period, seed) {
  x = ((x % period) + period) % period;
  let n = x * 374761393 + seed * 668265263;
  n = (n ^ (n >> 13)) * 1274126177;
  return ((n ^ (n >> 16)) >>> 0) / 4294967295;
}
function smooth(t) { return t * t * (3 - 2 * t); }
function noise1(x, period, seed) {
  const xi = Math.floor(x), xf = smooth(x - xi);
  return hash(xi, period, seed) * (1 - xf) + hash(xi + 1, period, seed) * xf;
}
function fbm1(x, basePeriod, seed, octaves) {
  let sum = 0, amp = 0.5, freq = 1, norm = 0;
  for (let o = 0; o < octaves; o++) {
    sum += noise1(x * freq, basePeriod * freq, seed + o * 7) * amp;
    norm += amp;
    amp *= 0.5; freq *= 2;
  }
  return sum / norm;
}
// 2D periodic-in-x noise for interior texture.
function hash2(x, y, period, seed) {
  x = ((x % period) + period) % period;
  let n = x * 374761393 + y * 668265263 + seed * 1442695041;
  n = (n ^ (n >> 13)) * 1274126177;
  return ((n ^ (n >> 16)) >>> 0) / 4294967295;
}
function noise2(x, y, period, seed) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = smooth(x - xi), yf = smooth(y - yi);
  const a = hash2(xi, yi, period, seed), b = hash2(xi + 1, yi, period, seed);
  const c = hash2(xi, yi + 1, period, seed), d = hash2(xi + 1, yi + 1, period, seed);
  return (a * (1 - xf) + b * xf) * (1 - yf) + (c * (1 - xf) + d * xf) * yf;
}

// ---- mountain.tga: sharp ridge, snow-capped peaks ----
// Ridged noise (folded) gives the sharp alpine profile that plain fbm cannot.
writeTGA("mountain.tga", 1024, 256, (x, y, w, h) => {
  const u = x / w;
  // pow() sharpens the folded peaks; without it the fold leaves flat-topped
  // plateaus that read as rectangular towers on the horizon.
  const ridged = Math.pow(1 - Math.abs(2 * noise1(u * 6, 6, 11) - 1), 1.3);
  const detail = fbm1(u * 24, 24, 31, 3);
  const rh = 0.24 + 0.64 * (0.55 * ridged + 0.45 * detail);
  const fb = (h - 1 - y) / h; // 0 at base, 1 at top
  const edge = (rh - fb) * h;  // px below the ridge line
  if (edge < 0) return [0, 0, 0, 0];
  const alpha = Math.min(1, edge / 2);
  // Interior: faceted rock via coarse noise, lighter toward the base so the
  // whole sheet sits back in the haze once tinted.
  let c = 0.66 + 0.22 * noise2(u * 40, y / h * 10, 40, 5);
  c *= 0.78 + 0.30 * (1 - fb);
  // Snow caps on the taller peaks only: brighten the top tenth of any ridge
  // that reaches high enough. Tinted blue it reads as snow, tinted red as
  // sunlit rock -- either way the peaks catch light.
  if (rh > 0.55 && fb > rh - 0.09) c = Math.min(1.35, c * 1.45);
  return [c, c, c * 1.04, alpha];
});

// ---- hills.tga: soft rolling line, no drama ----
writeTGA("hills.tga", 1024, 128, (x, y, w, h) => {
  const u = x / w;
  const rh = 0.30 + 0.50 * fbm1(u * 5, 5, 71, 2);
  const fb = (h - 1 - y) / h;
  const edge = (rh - fb) * h;
  if (edge < 0) return [0, 0, 0, 0];
  const alpha = Math.min(1, edge / 2.5);
  let c = 0.80 + 0.14 * noise2(u * 30, y / h * 6, 30, 9);
  c *= 0.82 + 0.24 * (1 - fb);
  // A hint of canopy clumping along the crest.
  if (fb > rh - 0.12) c *= 0.90 + 0.16 * noise2(u * 90, fb * 20, 90, 13);
  return [c, c, c, alpha];
});
