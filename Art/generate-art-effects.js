// Effect art: the pieces that make an item look like it *fired* rather than
// silently changing a number.
const fs = require("fs"), path = require("path");
const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });
function writeTGA(name, w, h, fn) {
  const header = Buffer.alloc(18);
  header[2] = 2; header.writeUInt16LE(w, 12); header.writeUInt16LE(h, 14);
  header[16] = 32; header[17] = 0x28;
  const body = Buffer.alloc(w * h * 4); let i = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const [r, g, b, a] = fn(x, y, w, h);
    body[i++] = Math.round(Math.max(0, Math.min(1, b)) * 255);
    body[i++] = Math.round(Math.max(0, Math.min(1, g)) * 255);
    body[i++] = Math.round(Math.max(0, Math.min(1, r)) * 255);
    body[i++] = Math.round(Math.max(0, Math.min(1, a)) * 255);
  }
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([header, body]));
  console.log(name, w + "x" + h);
}
function hash(x, y, s) {
  let n = x * 374761393 + y * 668265263 + s * 1442695040888963407;
  n = (n ^ (n >> 13)) * 1274126177;
  return ((n ^ (n >> 16)) >>> 0) / 4294967295;
}

// ---- expanding shockwave: thin bright annulus, soft on both edges ----
writeTGA("shock.tga", 256, 256, (x, y, w, h) => {
  const dx = (x + .5) / w * 2 - 1, dy = (y + .5) / h * 2 - 1;
  const d = Math.sqrt(dx * dx + dy * dy);
  const band = Math.abs(d - 0.80);
  let a = Math.max(0, 1 - band / 0.19);
  a = Math.pow(a, 2.4);
  // Slight ripple so it is not a perfect mathematical ring.
  const ang = Math.atan2(dy, dx);
  a *= 0.85 + 0.15 * Math.sin(ang * 9);
  if (d > 1) a = 0;
  return [1, 1, 1, a];
});

// ---- launch burst: radial spokes, for the moment a shot leaves the kart ----
writeTGA("burst.tga", 256, 256, (x, y, w, h) => {
  const dx = (x + .5) / w * 2 - 1, dy = (y + .5) / h * 2 - 1;
  const d = Math.sqrt(dx * dx + dy * dy);
  if (d > 1) return [0, 0, 0, 0];
  const ang = Math.atan2(dy, dx);
  // 12 tapering spokes plus a hot core.
  const spoke = Math.pow(Math.abs(Math.cos(ang * 6)), 8);
  const falloff = Math.pow(Math.max(0, 1 - d), 1.6);
  const core = Math.pow(Math.max(0, 1 - d * 3.2), 2.2);
  const a = Math.min(1, falloff * spoke * 1.5 + core);
  return [1, 1, 1, a];
});

// ---- shatter shards, for an item box breaking open ----
writeTGA("shard.tga", 64, 64, (x, y, w, h) => {
  const u = (x + .5) / w, v = (y + .5) / h;
  // Irregular quad tapering to a point.
  const width = 0.42 * (1 - v) + 0.05;
  if (Math.abs(u - 0.5) > width) return [0, 0, 0, 0];
  const lit = 0.55 + (0.5 - Math.abs(u - 0.38)) * 0.9 + hash(x >> 2, y >> 2, 3) * 0.2;
  return [lit, lit, lit, 1];
});

// ---- boulder: a rounded lump of rock, for roadside scenery ----
//
// shard.tga was being used for this and it is a crystal: a downward-tapering
// spike. Rendered as a rock beside a road it reads as an upside-down cone
// hovering over the ground, which is what the Durotar preview showed. A rock is
// wider than it is tall and sits ON something.
//
// NEUTRAL, like tree.tga: this is tinted per circuit, so any colour baked in
// here would survive every tint and every biome would get the same rock.
writeTGA("boulder.tga", 96, 64, (x, y, w, h) => {
  const u = (x + .5) / w, v = (y + .5) / h;
  // Two overlapping domes, so the silhouette is a lump rather than an egg.
  const dome = (cx, cy, rx, ry) => {
    const dx = (u - cx) / rx, dy = (v - cy) / ry;
    return dx * dx + dy * dy;
  };
  const inside = Math.min(dome(0.44, 0.92, 0.42, 0.78), dome(0.68, 0.95, 0.28, 0.52));
  if (inside > 1 || v > 0.99) return [0, 0, 0, 0];
  // Lit from the upper left, with a coarse facet break so it is not a pebble.
  const lit = 0.58 + (1 - v) * 0.34 + (0.5 - Math.abs(u - 0.34)) * 0.30
    + hash(x >> 3, y >> 3, 11) * 0.16;
  const tone = Math.max(0.25, Math.min(1, lit));
  return [tone, tone, tone, 1];
});

// ---- spore cap: the giant mushroom that IS Zangarmarsh ----
//
// Not mushroom.tga -- that is the ITEM, and it is red-and-white on purpose,
// which means a per-track tint cannot restyle it: Zangarmarsh's teal and violet
// caps came out as the same Mario mushroom with a colour cast. Scenery needs its
// own neutral silhouette.
writeTGA("sporecap.tga", 96, 96, (x, y, w, h) => {
  const u = (x + .5) / w, v = (y + .5) / h;
  // Stem below, cap above.
  if (v > 0.46) {
    const waist = 0.085 + (v - 0.46) * 0.10;
    if (Math.abs(u - 0.5) > waist) return [0, 0, 0, 0];
    const lit = 0.52 + (0.5 - Math.abs(u - 0.44)) * 0.7;
    const tone = Math.max(0.25, Math.min(1, lit));
    return [tone, tone, tone, 1];
  }
  // A wide, low dome with a soft underside lip.
  const dx = (u - 0.5) / 0.48, dy = (v - 0.46) / 0.42;
  if (dx * dx + dy * dy > 1) return [0, 0, 0, 0];
  const lit = 0.60 + (0.46 - v) * 0.55 + (0.5 - Math.abs(u - 0.36)) * 0.34
    + hash(x >> 3, y >> 3, 17) * 0.12;
  const tone = Math.max(0.25, Math.min(1, lit));
  return [tone, tone, tone, 1];
});

// ---- speed streak with soft ends, for boost lines ----
writeTGA("streak.tga", 16, 128, (x, y, w, h) => {
  const u = (x + .5) / w, v = (y + .5) / h;
  const across = 1 - Math.abs(u * 2 - 1);
  const along = Math.sin(v * Math.PI);
  return [1, 1, 1, Math.pow(across, 1.4) * Math.pow(along, 1.1)];
});
