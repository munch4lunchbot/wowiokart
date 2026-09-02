// Generates uncompressed 32-bit TGA art for the kart addon.
// WoW addons load .tga from Interface\AddOns\<name>\... so this gives us real
// soft-edged, textured art instead of flat colour quads.
const fs = require("fs");
const path = require("path");

const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });

function writeTGA(name, w, h, fn) {
  const header = Buffer.alloc(18);
  header[2] = 2;                    // uncompressed true-colour
  header.writeUInt16LE(w, 12);
  header.writeUInt16LE(h, 14);
  header[16] = 32;                  // bits per pixel
  header[17] = 0x28;                // 8-bit alpha + top-left origin
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

// ---- periodic value noise, so tiles wrap seamlessly ----
function hash(x, y, period, seed) {
  x = ((x % period) + period) % period;
  y = ((y % period) + period) % period;
  let n = x * 374761393 + y * 668265263 + seed * 1442695040888963407;
  n = (n ^ (n >> 13)) * 1274126177;
  return ((n ^ (n >> 16)) >>> 0) / 4294967295;
}
function smooth(t) { return t * t * (3 - 2 * t); }
function valueNoise(x, y, period, seed) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = smooth(x - xi), yf = smooth(y - yi);
  const a = hash(xi, yi, period, seed), b = hash(xi + 1, yi, period, seed);
  const c = hash(xi, yi + 1, period, seed), d = hash(xi + 1, yi + 1, period, seed);
  return (a * (1 - xf) + b * xf) * (1 - yf) + (c * (1 - xf) + d * xf) * yf;
}
function fbm(x, y, basePeriod, seed, octaves) {
  let sum = 0, amp = 0.5, freq = 1, norm = 0;
  for (let o = 0; o < octaves; o++) {
    sum += valueNoise(x * freq, y * freq, basePeriod * freq, seed + o) * amp;
    norm += amp;
    amp *= 0.5; freq *= 2;
  }
  return sum / norm;
}

// ---- soft radial glow: particles, halos, item beams, sun ----
function radial(power) {
  return (x, y, w, h) => {
    const dx = (x + 0.5) / w * 2 - 1, dy = (y + 0.5) / h * 2 - 1;
    const d = Math.sqrt(dx * dx + dy * dy);
    const a = Math.pow(Math.max(0, 1 - d), power);
    return [1, 1, 1, a];
  };
}
writeTGA("glow.tga", 128, 128, radial(2.2));
writeTGA("spark.tga", 32, 32, radial(1.6));

// ---- soft contact shadow ----
writeTGA("shadow.tga", 64, 64, (x, y, w, h) => {
  const dx = (x + 0.5) / w * 2 - 1, dy = (y + 0.5) / h * 2 - 1;
  const d = Math.sqrt(dx * dx + dy * dy * 2.6);
  return [0, 0, 0, Math.pow(Math.max(0, 1 - d), 1.7)];
});

// ---- cloud puff: fbm-modulated blob with a soft edge ----
writeTGA("cloud.tga", 256, 128, (x, y, w, h) => {
  const dx = (x + 0.5) / w * 2 - 1, dy = (y + 0.5) / h * 2 - 1;
  const d = Math.sqrt(dx * dx * 0.8 + dy * dy * 2.2);
  const n = fbm(x / 26, y / 20, 10, 7, 4);
  let a = Math.max(0, 1 - d) * (0.45 + n * 0.85);
  a = Math.pow(Math.max(0, Math.min(1, a)), 1.5);
  return [1, 1, 1, a];
});

// ---- conifer silhouette, so the treeline stops being green boxes ----
//
// NEUTRAL, deliberately. This used to return a hardcoded dark green -- canopy
// (0.16, 0.34, 0.20), trunk (0.34, 0.26, 0.18) -- which meant every per-track
// `treeTint` in RaceUI's SKYLINE table did nothing at all: multiplying dark
// green by orange gives dark olive. Durotar's volcanic waste, Ironforge's
// frost, the Deadmines' blue-grey and Stranglethorn's jungle were the same
// green conifer with the brightness nudged. It is also why the treeline read as
// a near-black cut-out on every track -- the art's own luminance was 0.24
// BEFORE any tint was applied.
//
// A silhouette that exists to be tinted has to be pale and neutral, the way
// hills.tga and mountain.tga already are. The colour lives in the track.
writeTGA("tree.tga", 64, 128, (x, y, w, h) => {
  const u = (x + 0.5) / w, v = (y + 0.5) / h;
  // Trunk below, canopy above. A trunk reads as a trunk by being in shadow, not
  // by being brown: brown baked in here would survive every tint.
  if (v > 0.82) {
    const trunk = Math.abs(u - 0.5) < 0.055 ? 1 : 0;
    return [0.52, 0.50, 0.48, trunk];
  }
  const t = v / 0.82;                       // 0 at tip, 1 at base
  const width = 0.06 + t * 0.42;
  // Ragged edge: three stacked tiers with noise.
  const tier = (t * 3) % 1;
  const bulge = 1 - tier * 0.28;
  const noise = fbm(x / 5, y / 5, 16, 3, 3) * 0.09;
  const edge = width * bulge + noise;
  const inside = Math.abs(u - 0.5) < edge ? 1 : 0;
  if (!inside) return [0, 0, 0, 0];
  // Shade so the left side catches light.
  const shade = 0.55 + (0.5 - Math.abs(u - 0.42)) * 0.7 + fbm(x / 7, y / 7, 12, 11, 3) * 0.25;
  const tone = Math.min(1, 0.50 + shade * 0.42);
  return [tone, tone, tone, 1];
});

// road.tga and grass.tga are NOT written here any more. They used to be, at
// 128px and with no levelling, and generate-art-ground.js writes the real
// 256px ones -- so whichever generator happened to run last decided which road
// the game shipped with. Running this file alone silently replaced a levelled
// road texture with a flat one that Art/verify-textures.js would then reject.
// Art/build-art.js runs the whole set in order; there is one road now.

// ---- vignette ----
writeTGA("vignette.tga", 256, 256, (x, y, w, h) => {
  const dx = (x + 0.5) / w * 2 - 1, dy = (y + 0.5) / h * 2 - 1;
  const d = Math.sqrt(dx * dx + dy * dy) / Math.SQRT2;
  return [0, 0, 0, Math.pow(Math.max(0, d - 0.35) / 0.65, 1.9) * 0.85];
});
