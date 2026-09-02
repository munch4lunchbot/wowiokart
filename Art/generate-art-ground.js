// Ground and UI surfaces. The road covers most of the screen, so its texture is
// the single biggest lever on whether this reads as a rendered world or as
// coloured bars. The old one was 0.72-1.1 luminance noise: essentially flat.
const fs = require("fs"), path = require("path");
const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });

// In-game these textures are tinted with SetVertexColor, which CLAMPS at 1.0.
// The offline preview used to multiply its tints past 1.0 to get a readable
// image, which the game can never reproduce -- so the brightness the scene
// needs is baked into the art itself and every tint stays inside [0,1].
const OUTPUT_GAIN = {"road.tga":1.9,"grass.tga":1.65};
function writeTGA(name, w, h, fn) {
  const gain = OUTPUT_GAIN[name] || 1;
  const header = Buffer.alloc(18);
  header[2] = 2; header.writeUInt16LE(w, 12); header.writeUInt16LE(h, 14);
  header[16] = 32; header[17] = 0x28;
  const body = Buffer.alloc(w * h * 4); let i = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const [r, g, b, a] = fn(x, y, w, h);
    body[i++] = Math.round(Math.max(0, Math.min(1, b * gain)) * 255);
    body[i++] = Math.round(Math.max(0, Math.min(1, g * gain)) * 255);
    body[i++] = Math.round(Math.max(0, Math.min(1, r * gain)) * 255);
    body[i++] = Math.round(Math.max(0, Math.min(1, a)) * 255);
  }
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([header, body]));
  console.log(name, w + "x" + h);
}
function hash(x, y, p, s) {
  x = ((x % p) + p) % p; y = ((y % p) + p) % p;
  let n = x * 374761393 + y * 668265263 + s * 1442695040888963407;
  n = (n ^ (n >> 13)) * 1274126177;
  return ((n ^ (n >> 16)) >>> 0) / 4294967295;
}
const sm = t => t * t * (3 - 2 * t);
function noise(x, y, p, s) {
  const xi = Math.floor(x), yi = Math.floor(y), xf = sm(x - xi), yf = sm(y - yi);
  const a = hash(xi, yi, p, s), b = hash(xi + 1, yi, p, s), c = hash(xi, yi + 1, p, s), d = hash(xi + 1, yi + 1, p, s);
  return (a * (1 - xf) + b * xf) * (1 - yf) + (c * (1 - xf) + d * xf) * yf;
}
function fbm(x, y, p, s, o) {
  let sum = 0, amp = .5, f = 1, n = 0;
  for (let i = 0; i < o; i++) { sum += noise(x * f, y * f, p * f, s + i) * amp; n += amp; amp *= .5; f *= 2; }
  return sum / n;
}

const R = 256;

// ---- road: cut stone slabs, 4x4 to the tile, with seams and wear ----
// Real seams give the eye something to track as it rushes past, which is what
// actually conveys speed. Uniform noise conveys nothing.
// THE ROAD IS A SURFACE, NOT A FLOOR.
//
// This was 64px slabs -- four across a tile that repeats every 4.2m, so about
// one seam per metre in BOTH directions -- with the groove darkening to 42%.
// Rendered, that is seventeen hard dark lines across the road converging on the
// vanishing point, on every track: it read as tiled paving, and on a forest
// dirt road it read as tiled paving in a forest. The tile is also tinted per
// track, so whatever is baked here has to work as asphalt, packed dirt, ice and
// cavern floor at once -- which argues for aggregate and grain, and against
// masonry.
//
// So: fewer and far softer seams (two slabs a tile, and a groove that shades
// rather than draws a line), with the fine aggregate carrying the detail. The
// surface still moves under you -- that is what sells speed -- without the road
// being a grid.
writeTGA("road.tga", R, R, (x, y) => {
  const cell = R / 2;                       // 128px slabs -- ~2.1m on the road
  const gx = Math.floor(x / cell), gy = Math.floor(y / cell);
  const lx = (x % cell) / cell, ly = (y % cell) / cell;

  // Per-slab tone, kept gentle: big flat patches of differing brightness read
  // as panelling. This is a hint of unevenness, not a chequerboard.
  const slab = hash(gx, gy, 4, 7);
  let v = 0.70 + slab * 0.10;

  // Coarse staining and fine aggregate -- now the main event.
  v += (fbm(x / 30, y / 30, 8, 11, 4) - 0.5) * 0.20;
  v += (fbm(x / 2.2, y / 2.2, 116, 23, 2) - 0.5) * 0.17;

  // Seams, as a soft shading trough rather than a drawn line. Widened and
  // lightened together: a wide gentle dip disappears into the aggregate at
  // speed, where a narrow black line stays crisp and stripes the whole road.
  const wob = (fbm(x / 12, y / 12, 20, 31, 2) - 0.5) * 0.06;
  const dEdge = Math.min(lx, 1 - lx, ly, 1 - ly) + wob;
  if (dEdge < 0.05) v *= 0.90 + dEdge * 2.0;

  // The old "worn tyre paths" were keyed to TEXTURE space, so they repeated
  // with the tile -- a pair of darker bands every 4.2m across the road, which
  // is not what a tyre path is. Removed; the road's own shading (roadshade.tga)
  // is what darkens toward the verges, and it is applied in world space.

  // Occasional crack, softened so it is a mark on the surface rather than a
  // seam competing with the slab edges.
  const crack = fbm(x / 18, y / 90, 14, 41, 3);
  if (crack > 0.80) v *= 0.90;

  v = Math.max(0.12, Math.min(1.35, v));
  // Very slight warm cast so grey does not read as dead.
  return [v * 1.01, v, v * 0.97, 1];
});

// ---- verge: clumped ground cover with real tonal range ----
writeTGA("grass.tga", R, R, (x, y) => {
  const clump = fbm(x / 34, y / 22, 8, 51, 4);
  const blade = fbm(x / 3.4, y / 8, 75, 61, 3);
  const patch = fbm(x / 90, y / 90, 3, 71, 2);
  let v = 0.44 + clump * 0.40 + blade * 0.22 + (patch - 0.5) * 0.24;
  // Scattered darker tufts.
  if (fbm(x / 7, y / 5, 37, 81, 2) > 0.70) v *= 0.80;
  v = Math.max(0.10, Math.min(1.3, v));
  return [v * 0.90, v, v * 0.80, 1];
});

// ---- road edge shading: dark at the verge, clear in the middle ----
// Multiplied over the road so the surface reads as a raised, lit object.
writeTGA("roadshade.tga", 64, 8, (x, y, w) => {
  const u = (x + 0.5) / w * 2 - 1;
  const edge = Math.pow(Math.abs(u), 3.2);
  return [0, 0, 0, edge * 0.55];
});

// ---- HUD panel: bevelled vertical gradient, stretched horizontally ----
writeTGA("panel.tga", 8, 64, (x, y, w, h) => {
  const v = (y + 0.5) / h;
  let a = 0.86 - v * 0.10;
  let tone = 0.10 + (1 - v) * 0.07;
  if (y === 0) { tone = 0.55; a = 0.95; }          // top highlight
  else if (y === 1) { tone = 0.26; a = 0.92; }
  else if (y === h - 1) { tone = 0.02; a = 0.95; } // bottom shadow
  return [tone * 0.86, tone * 0.92, tone * 1.15, a];
});

// ---- soft horizontal divider / underline ----
writeTGA("hairline.tga", 8, 4, (x, y, w, h) => {
  const v = (y + 0.5) / h;
  return [1, 1, 1, Math.pow(1 - Math.abs(v * 2 - 1), 1.5)];
});
