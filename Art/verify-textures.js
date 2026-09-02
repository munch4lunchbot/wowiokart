// Do the ground textures actually carry any detail?
//
// The road, the verge and the tunnel rock are TILED and TINTED: the game
// multiplies each by a per-track colour, which clamps at 1.0, so the brightness
// the scene needs has to be baked into the art. That baking used to be a
// hand-set gain, and nothing checked what came out of it.
//
// What came out of it was a blank texture. road.tga was on x1.9: 99.1% of it
// was pure white, standard deviation 0.0026. Every slab edge, stain, aggregate
// grain and crack the generator computes -- the things that make a surface
// rush past you and sell speed -- was clipped clean off, and the road in game
// was a flat colour with a stripe down the middle. rock.tga was 20.5% white.
// Nobody noticed because a flat road still looks like a road in a screenshot;
// it just does not look like it is moving.
//
// This is only asked of the tiled ground surfaces. A sprite is allowed to be
// mostly white -- a spark IS white -- so shells, sparks and icons are not here.
//
// Run: node Art/verify-textures.js [artDir]
const fs = require("fs");
const path = require("path");

const ART = process.argv[2] || path.join(__dirname, "..", "Art");

// name: the least spread it may have, and the most of it that may be clipped.
const SURFACES = {
  "road.tga":  { minSd: 0.055, maxClip: 0.02 },
  "grass.tga": { minSd: 0.060, maxClip: 0.02 },
  "rock.tga":  { minSd: 0.060, maxClip: 0.02 },
};

function stats(name) {
  const b = fs.readFileSync(path.join(ART, name));
  const w = b.readUInt16LE(12), h = b.readUInt16LE(14), off = 18 + b[0];
  const n = w * h;
  let sum = 0, clipped = 0, black = 0;
  const l = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const bl = b[off + i * 4], g = b[off + i * 4 + 1], r = b[off + i * 4 + 2];
    l[i] = (r * 0.30 + g * 0.59 + bl * 0.11) / 255;
    sum += l[i];
    if (Math.max(r, g, bl) >= 255) clipped++;
    if (Math.max(r, g, bl) <= 0) black++;
  }
  const mean = sum / n;
  let v = 0;
  for (let i = 0; i < n; i++) v += (l[i] - mean) * (l[i] - mean);
  return { w, h, mean, sd: Math.sqrt(v / n), clip: clipped / n, black: black / n };
}

console.log("Ground textures  (tiled and tinted, so they must carry their own detail)");
console.log("");
console.log("  texture       size       mean     spread    clipped white");

let failures = 0;
for (const [name, limit] of Object.entries(SURFACES)) {
  if (!fs.existsSync(path.join(ART, name))) {
    console.log("  " + name.padEnd(13) + "MISSING");
    failures++;
    continue;
  }
  const s = stats(name);
  const flat = s.sd < limit.minSd;
  const blown = s.clip > limit.maxClip;
  if (flat || blown) failures++;
  console.log("  " + name.padEnd(13) + (s.w + "x" + s.h).padEnd(11) +
    s.mean.toFixed(3).padStart(6) + s.sd.toFixed(4).padStart(11) +
    (s.clip * 100).toFixed(1).padStart(12) + "%" +
    (flat ? "   <- FLAT: no detail survives to be seen" : "") +
    (blown ? "   <- BLOWN OUT: detail clipped away" : ""));
}

console.log("");
console.log("  Spread is the standard deviation of luminance. Under " +
  SURFACES["road.tga"].minSd + " there is nothing");
console.log("  on the surface for the eye to track as it rushes past, which is what actually");
console.log("  conveys speed -- a flat road still looks like a road, it just does not look");
console.log("  like it is moving.");
console.log("");
console.log(failures ? "FAIL (" + failures + " surface(s) carry no usable detail)"
  : "PASS (every tiled ground surface keeps its detail)");
process.exit(failures ? 1 : 0);
