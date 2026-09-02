// Oribos set: structures the track is actually built out of.
const fs = require("fs");
const path = require("path");
const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });

function writeTGA(name, w, h, fn) {
  const header = Buffer.alloc(18);
  header[2] = 2; header.writeUInt16LE(w, 12); header.writeUInt16LE(h, 14);
  header[16] = 32; header[17] = 0x28;
  const body = Buffer.alloc(w * h * 4);
  let i = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const [r, g, b, a] = fn(x, y, w, h);
    body[i++] = Math.max(0, Math.min(255, Math.round(b * 255)));
    body[i++] = Math.max(0, Math.min(255, Math.round(g * 255)));
    body[i++] = Math.max(0, Math.min(255, Math.round(r * 255)));
    body[i++] = Math.max(0, Math.min(255, Math.round(a * 255)));
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

// Oribos palette: pale bone stone, gold trim, anima cyan.
const STONE = [0.82, 0.78, 0.70];
const GOLD = [1.00, 0.78, 0.30];
const ANIMA = [0.45, 0.92, 1.00];

// ---- drive-through arch: two pillars and an arched span ----
writeTGA("arch.tga", 256, 256, (x, y, w, h) => {
  const u = (x + 0.5) / w, v = (y + 0.5) / h;
  const dx = Math.abs(u - 0.5);
  if (v < 0.05 || dx > 0.48) return [0, 0, 0, 0];

  // The opening: rectangular below, elliptical arch above.
  const openW = 0.355, archTop = 0.40, archH = 0.30;
  let open = false;
  if (dx < openW && v > archTop) open = true;
  else if (v <= archTop && v > archTop - archH) {
    const ex = dx / openW, ey = (archTop - v) / archH;
    if (ex * ex + ey * ey < 1) open = true;
  }
  if (open) return [0, 0, 0, 0];

  const grain = fbm(x / 9, y / 9, 28, 5, 4);
  let col = STONE.map(c => c * (0.72 + grain * 0.5));

  // Gold banding on the pillars and along the span underside.
  const band = (v > 0.52 && v < 0.57) || (v > 0.74 && v < 0.78) || (v > 0.10 && v < 0.14);
  if (band) col = GOLD.map((c, i) => c * (0.65 + grain * 0.5));

  // Anima conduit running the inner edge of each pillar.
  const innerEdge = Math.abs(dx - openW) < 0.022 && v > archTop - 0.02;
  if (innerEdge) col = ANIMA.map(c => c * (0.85 + grain * 0.3));

  // Rim light on the outer silhouette.
  if (dx > 0.44) col = col.map(c => c * 1.25);
  return [col[0], col[1], col[2], 1];
});

// ---- distant spire, for the Oribos skyline ----
writeTGA("spire.tga", 128, 256, (x, y, w, h) => {
  const u = (x + 0.5) / w, v = (y + 0.5) / h;
  const dx = Math.abs(u - 0.5);
  // Tapering shaft with a bulb near the top, tiered like Oribos.
  let width;
  if (v < 0.10) width = 0.03;
  else if (v < 0.22) width = 0.03 + (v - 0.10) * 1.5;
  else if (v < 0.30) width = 0.21 - (v - 0.22) * 1.1;
  else width = 0.12 + (v - 0.30) * 0.30;
  const tier = Math.abs((v * 7) % 1 - 0.5) < 0.42 ? 1 : 1.13;
  if (dx > width * tier) return [0, 0, 0, 0];

  const grain = fbm(x / 7, y / 11, 18, 9, 3);
  let col = STONE.map(c => c * (0.5 + grain * 0.45));
  // Lit windows.
  const win = hash(Math.floor(x / 6), Math.floor(y / 9), 64, 3);
  if (win > 0.86 && dx < width * 0.7) col = GOLD.map(c => c * 0.9);
  // Anima ring near the bulb.
  if (v > 0.235 && v < 0.255) col = ANIMA.map(c => c * 0.95);
  return [col[0], col[1], col[2], 1];
});

// ---- the Oribos ring, hanging on the horizon ----
writeTGA("ring.tga", 256, 256, (x, y, w, h) => {
  const dx = (x + 0.5) / w * 2 - 1, dy = ((y + 0.5) / h * 2 - 1) * 2.6;
  const d = Math.sqrt(dx * dx + dy * dy);
  const band = Math.abs(d - 0.72);
  if (band > 0.16) return [0, 0, 0, 0];
  const t = 1 - band / 0.16;
  const grain = fbm(x / 10, y / 10, 24, 13, 3);
  let col = STONE.map(c => c * (0.42 + grain * 0.4));
  if (band < 0.045) col = GOLD.map(c => c * (0.55 + grain * 0.4));
  return [col[0], col[1], col[2], Math.pow(t, 0.6) * 0.92];
});

// ---- banner cloth for the gantry and roadside ----
writeTGA("banner.tga", 64, 128, (x, y, w, h) => {
  const u = (x + 0.5) / w, v = (y + 0.5) / h;
  if (u < 0.08 || u > 0.92) return [0, 0, 0, 0];
  // Torn lower edge.
  const tear = 0.86 + fbm(x / 6, 0, 16, 17, 2) * 0.13;
  if (v > tear) return [0, 0, 0, 0];
  const fold = 0.72 + Math.sin(u * Math.PI * 3) * 0.16;
  const grain = fbm(x / 5, y / 14, 14, 19, 3);
  let col = [0.30 * fold, 0.16 * fold, 0.42 * fold];
  if (v > 0.16 && v < 0.24) col = GOLD.map(c => c * fold);
  if (v > 0.34 && v < 0.62 && Math.abs(u - 0.5) < 0.22) col = ANIMA.map(c => c * fold * (0.7 + grain * 0.4));
  return [col[0], col[1], col[2], 1];
});
