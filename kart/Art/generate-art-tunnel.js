// Tunnel interior surfaces.
//
// Tiled across the walls and ceiling of a covered section, so the texture must
// wrap seamlessly in both axes -- any seam becomes a bright vertical line
// racing toward the camera. Periodic value noise gives that for free.
const fs = require("fs");
const path = require("path");

const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });

// In-game these textures are tinted with SetVertexColor, which CLAMPS at 1.0.
// The offline preview used to multiply its tints past 1.0 to get a readable
// image, which the game can never reproduce -- so the brightness the scene
// needs is baked into the art itself and every tint stays inside [0,1].
const OUTPUT_GAIN = {"rock.tga":1.4};
function writeTGA(name, w, h, fn) {
  const gain = OUTPUT_GAIN[name] || 1;
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(w, 12);
  header.writeUInt16LE(h, 14);
  header[16] = 32;
  header[17] = 0x28;
  const body = Buffer.alloc(w * h * 4);
  let i = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const [r, g, b, a] = fn(x, y, w, h);
      body[i++] = Math.max(0, Math.min(255, Math.round(b * gain * 255)));
      body[i++] = Math.max(0, Math.min(255, Math.round(g * gain * 255)));
      body[i++] = Math.max(0, Math.min(255, Math.round(r * gain * 255)));
      body[i++] = Math.max(0, Math.min(255, Math.round(a * 255)));
    }
  }
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([header, body]));
  console.log(name, w + "x" + h);
}

// Periodic value noise: lattice indices wrap at `period`, so the tile repeats.
function makeNoise(period, seed) {
  const grid = new Float64Array(period * period);
  let s = seed >>> 0;
  for (let i = 0; i < grid.length; i++) {
    s = (s * 1664525 + 1013904223) >>> 0;
    grid[i] = s / 4294967296;
  }
  const smooth = t => t * t * (3 - 2 * t);
  return (u, v) => {
    const fx = u * period, fy = v * period;
    const x0 = Math.floor(fx) % period, y0 = Math.floor(fy) % period;
    const x1 = (x0 + 1) % period, y1 = (y0 + 1) % period;
    const tx = smooth(fx - Math.floor(fx)), ty = smooth(fy - Math.floor(fy));
    const a = grid[y0 * period + x0], b = grid[y0 * period + x1];
    const c = grid[y1 * period + x0], d = grid[y1 * period + x1];
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
  };
}

const n1 = makeNoise(4, 0x51ed27);
const n2 = makeNoise(8, 0x9e3779);
const n3 = makeNoise(16, 0x2545f4);
const n4 = makeNoise(32, 0x85ebca);

// Hewn rock.
//
// Weighted toward the HIGH octaves on purpose. Low-frequency blobs are what
// make a tiled texture announce its repeat -- the eye locks onto the big shapes
// and sees the grid. Fine grain plus horizontal bedding reads as cut stone and
// hides the tile. The first attempt darkened a noise isoline to make "cracks",
// which drew closed loops and looked like jigsaw pieces.
writeTGA("rock.tga", 128, 128, (x, y, w, h) => {
  const u = x / w, v = y / h;
  const grain = n2(u, v) * 0.12 + n3(u, v) * 0.30 + n4(u, v) * 0.58;

  // Bedding planes, heavily warped and kept faint. At full strength this reads
  // as corduroy, and the regular horizontal banding advertises the tile's
  // vertical repeat -- the exact thing the high-frequency weighting is for.
  const phase = v * 4 + n2(u, v) * 1.9 + n1(u, v) * 0.9;
  const bed = Math.sin(phase * Math.PI * 2) * 0.5 + 0.5;

  // Fissures sit in the deepest troughs only, and are gated by grain so they
  // appear as scattered fractures rather than a stripe on every bed.
  const trough = Math.pow(1 - bed, 9);
  const gate = Math.max(0, n4(u * 2.3, v * 2.3) - 0.35) * 1.6;
  const fissure = trough * gate;

  let value = 0.38 + bed * 0.06 + grain * 0.52 - fissure * 0.30;
  value = Math.max(0.05, Math.min(1, value));

  // Very slightly warm, so lamp light on it looks like light rather than tint.
  return [value * 1.02, value * 0.98, value * 0.94, 1];
});

// Tunnel mouth glow: a soft vertical gradient laid over the opening so daylight
// spills into the entrance instead of the tunnel starting on a hard edge.
writeTGA("tunnelmouth.tga", 64, 64, (x, y, w, h) => {
  const v = y / (h - 1);
  const u = x / (w - 1);
  const edge = 1 - Math.abs(u - 0.5) * 2;
  const fall = Math.pow(1 - v, 1.7);
  return [1, 0.97, 0.9, Math.max(0, edge * fall)];
});
