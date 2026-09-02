// Rear-view go-karts, one silhouette per kart id, so racers read as people
// sitting IN something specific rather than in the same tinted slab six times.
//
// THE CONTRACT, measured off the shipped art and enforced by verify-karts.js:
//
//   rows   0-28   transparent      the rider's head and shoulders show here
//   rows  28-72   seat-back zone   drawn BEHIND the rider; frames them
//   rows  72-160  front slice      drawn IN FRONT of the rider (kartLip 0.55)
//
// UI/RaceUI.lua draws the whole texture once behind the driver and then repeats
// the bottom `kartLip` fraction in front of their legs. With kartLip = 0.55 the
// front slice is exactly rows 72-160, set by SetTexCoord -- so nothing above
// row 72 can ever cover the rider, whatever a silhouette does up there.
//
// The real hazard is the opposite one: if a kart's bodywork does not START at
// row 72 and span the rider's own column, the front slice is transparent where
// their legs are and the legs render through the bodywork. So every kart keeps
// a solid "collar" across rows 72-100 at x 80-176. Personality goes:
//
//   * outboard of the body (x < 50, x > 206) -- fins, wings, gears, horns
//   * into the seat-back zone, rows 28-72     -- behind the rider, frames them
//   * below row 100                           -- prows, exhausts, rails, rivets
//   * in the body's own outline below row 72  -- boxy vs rounded vs tapered
//
// Luminance carries the structure. The chassis is painted near-white because
// SetVertexColor multiplies it by the kart's colour; accents are baked dark or
// coloured so a bright tint cannot wash them out.
const fs = require("fs");
const path = require("path");
const OUT = process.argv[2] || ".";
fs.mkdirSync(OUT, { recursive: true });

// In-game these textures are tinted with SetVertexColor, which CLAMPS at 1.0.
// The offline preview used to multiply its tints past 1.0 to get a readable
// image, which the game can never reproduce -- so the brightness the scene
// needs is baked into the art itself and every tint stays inside [0,1].
const GAIN = 1.6;

function writeTGA(name, w, h, fn) {
  const header = Buffer.alloc(18);
  header[2] = 2; header.writeUInt16LE(w, 12); header.writeUInt16LE(h, 14);
  header[16] = 32; header[17] = 0x28;
  const body = Buffer.alloc(w * h * 4);
  let i = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const [r, g, b, a] = fn(x, y, w, h);
    body[i++] = Math.max(0, Math.min(255, Math.round(b * GAIN * 255)));
    body[i++] = Math.max(0, Math.min(255, Math.round(g * GAIN * 255)));
    body[i++] = Math.max(0, Math.min(255, Math.round(r * GAIN * 255)));
    body[i++] = Math.max(0, Math.min(255, Math.round(a * 255)));
  }
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([header, body]));
  console.log(name, w + "x" + h);
}

// ---- signed distance helpers, all in pixels ----
function roundRect(px, py, cx, cy, hw, hh, r) {
  const dx = Math.abs(px - cx) - (hw - r);
  const dy = Math.abs(py - cy) - (hh - r);
  const ax = Math.max(dx, 0), ay = Math.max(dy, 0);
  return Math.sqrt(ax * ax + ay * ay) + Math.min(Math.max(dx, dy), 0) - r;
}
/** Thick line between two points -- horns, fins, rails, piston rods. */
function capsule(px, py, x1, y1, x2, y2, r) {
  const dx = x2 - x1, dy = y2 - y1;
  const l2 = dx * dx + dy * dy;
  let t = l2 > 0 ? ((px - x1) * dx + (py - y1) * dy) / l2 : 0;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  return Math.hypot(px - (x1 + dx * t), py - (y1 + dy * t)) - r;
}
function disc(px, py, cx, cy, r) {
  return Math.hypot(px - cx, py - cy) - r;
}
/** Toothed disc. tanh squares off the cosine so teeth read at small sizes. */
function gear(px, py, cx, cy, radius, teeth, depth) {
  const d = Math.hypot(px - cx, py - cy);
  const wave = Math.tanh(Math.cos(Math.atan2(py - cy, px - cx) * teeth) * 3);
  return d - (radius + depth * wave);
}
/** Downward-tapering wedge -- beaks and prows. */
function wedge(px, py, cx, topY, botY, halfW) {
  const t = (py - topY) / (botY - topY);
  if (t < 0 || t > 1) return 1e3;
  return Math.abs(px - cx) - halfW * (1 - t);
}
const solid = d => Math.max(0, Math.min(1, 0.5 - d));

// ---- shared palette ----
//
// SetVertexColor MULTIPLIES, so on a saturated kart colour every hue collapses
// toward that colour and only LIGHTNESS survives as a distinguishing signal.
// An orange flame accent on the red rocket came out near-black (0.95 x 0.27 in
// green), and on the blue mechano it came out olive. So accents are graded by
// brightness -- near-white reads as hot/lit, mid as worn metal, dark as shadow
// -- with only a gentle hue bias on top.
const TYRE = [0.10, 0.10, 0.12];
const HUB = [0.55, 0.56, 0.60];
const STEEL = [0.44, 0.46, 0.52];
const DARK = [0.18, 0.18, 0.21];
const WOOD = [0.34, 0.26, 0.18];
const BONE = [0.86, 0.83, 0.72];
const COPPER = [0.80, 0.68, 0.50];
const HOT = [1.0, 0.94, 0.82];

// The collar every kart must keep solid so legs cannot show through the front
// slice. Anything narrower or lower than this and verify-karts.js fails.
const BODY_TOP = 72;

// The seat back is the structure closest to the rider and the most visible
// thing in the frame after the bodywork, so it is per-kart too. Sharing one
// seat across all six made every silhouette 85%+ identical however dramatic
// the outboard decoration got.
const KARTS = {
  // Narrow and pointed: steeply swept fins and a big exhaust bell.
  rocket: {
    halfW: 76, radius: 18, wheelX: [32, 224], wheelR: 28,
    seat: { cy: 62, hw: 38, hh: 26, r: 17 },
    behind(put, x, y) {
      for (const dir of [-1, 1]) {
        const rx = 128 + dir * 58, tx = 128 + dir * 128;
        put(solid(capsule(x, y, rx, 112, tx, 30, 16)) * 0.95, ...STEEL);
        put(solid(capsule(x, y, rx, 112, tx, 30, 8)) * 0.65, 0.78, 0.80, 0.86);
        put(solid(capsule(x, y, tx - dir * 26, 60, tx, 30, 6)) * 0.9, ...HOT);
      }
    },
    front(put, x, y) {
      // Exhaust bell, dead centre and low: reads instantly as a rocket.
      put(solid(roundRect(x, y, 128, 138, 34, 17, 12)), ...DARK);
      put(solid(roundRect(x, y, 128, 138, 25, 11, 9)), 0.08, 0.08, 0.09);
      put(solid(disc(x, y, 128, 138, 8)) * 0.9, ...HOT);
      for (const cx of [82, 174]) put(solid(roundRect(x, y, cx, 132, 10, 9, 5)), ...DARK);
    },
  },

  // Boxy and industrial: exposed gears outboard, piston rods behind the seat.
  mechano: {
    halfW: 80, radius: 8, wheelX: [34, 222], wheelR: 27, customWheels: true,
    seat: { cy: 56, hw: 48, hh: 32, r: 4 },
    behind(put, x, y) {
      // The gears ARE the wheels. Sitting them beside the standard tyres just
      // hid them -- the tyres draw after this and swallowed all but the teeth.
      for (const cx of [36, 220]) {
        put(solid(gear(x, y, cx, 108, 33, 10, 6)), ...STEEL);
        put(solid(gear(x, y, cx, 108, 27, 10, 5)) * 0.6, 0.24, 0.25, 0.29);
        put(solid(disc(x, y, cx, 108, 17)), 0.32, 0.34, 0.38);
        put(solid(disc(x, y, cx, 108, 8)), ...COPPER);
        put(solid(disc(x, y, cx, 108, 3)), 0.15, 0.10, 0.05);
      }
      for (const cx of [92, 164]) {
        put(solid(capsule(x, y, cx, 72, cx, 36, 6)), ...STEEL);
        put(solid(roundRect(x, y, cx, 36, 9, 6, 3)), ...COPPER);
      }
    },
    front(put, x, y) {
      put(solid(roundRect(x, y, 128, 134, 66, 11, 3)), ...DARK);
      // Rivet line along the lower bodywork.
      for (let cx = 66; cx <= 190; cx += 15.5) put(solid(disc(x, y, cx, 112, 3.2)) * 0.85, ...COPPER);
    },
  },

  // Wide wooden cart, bone horns curving up and out from the flanks.
  kodo: {
    halfW: 88, radius: 10, wheelX: [30, 226], wheelR: 31,
    seat: { cy: 58, hw: 54, hh: 30, r: 3 },
    behind(put, x, y) {
      for (const [x1, x2, x3] of [[54, 26, 16], [202, 230, 240]]) {
        put(solid(capsule(x, y, x1, 108, x2, 76, 10)), ...BONE);
        put(solid(capsule(x, y, x2, 76, x3, 46, 7)), 0.86, 0.83, 0.70);
      }
    },
    front(put, x, y) {
      // Plank seams. Warm but low-saturation so the racer tint still reads.
      for (const cx of [92, 128, 164]) put(solid(roundRect(x, y, cx, 116, 2.2, 40, 1)) * 0.55, ...WOOD);
      put(solid(roundRect(x, y, 128, 96, 84, 4, 2)) * 0.7, ...WOOD);
      put(solid(roundRect(x, y, 128, 138, 74, 10, 4)), ...WOOD);
    },
  },

  // Swept wings well outboard of the body, with feather notches.
  griffon: {
    halfW: 72, radius: 20, wheelX: [36, 220], wheelR: 26,
    seat: { cy: 60, hw: 40, hh: 32, r: 20 },
    behind(put, x, y) {
      for (const dir of [-1, 1]) {
        const root = 128 + dir * 56;
        const tip = 128 + dir * 124;
        put(solid(capsule(x, y, root, 100, tip, 46, 15)) * 0.97, 0.74, 0.70, 0.60);
        put(solid(capsule(x, y, root, 100, tip, 46, 8)) * 0.7, 0.92, 0.90, 0.82);
        // Trailing-edge feathers.
        for (let k = 0; k < 4; k++) {
          const t = 0.25 + k * 0.2;
          const fx = root + (tip - root) * t, fy = 100 + (46 - 100) * t;
          put(solid(capsule(x, y, fx, fy, fx + dir * 12, fy + 20, 5)) * 0.85, 0.60, 0.56, 0.46);
        }
      }
    },
    front(put, x, y) {
      put(solid(roundRect(x, y, 128, 136, 58, 10, 8)), 0.62, 0.52, 0.24);
      for (const cx of [104, 152]) put(solid(disc(x, y, cx, 118, 7)) * 0.9, 0.86, 0.72, 0.34);
    },
  },

  // Hard rectangles, flanged rail wheels and a rail underneath. The only kart
  // with no rounded corners at all, which is most of what makes it read.
  minecart: {
    halfW: 82, radius: 3, wheelX: [40, 216], wheelR: 22, customWheels: true,
    seat: { cy: 56, hw: 52, hh: 30, r: 2 },
    behind(put, x, y) {
      for (const cx of [40, 216]) {
        put(solid(disc(x, y, cx, 112, 21)), 0.16, 0.16, 0.19);
        put(solid(disc(x, y, cx, 112, 13)), ...STEEL);
        put(solid(disc(x, y, cx, 112, 5)), 0.22, 0.22, 0.25);
      }
    },
    front(put, x, y) {
      // Rivets around the box edge -- the signature of a riveted iron cart.
      for (let cx = 54; cx <= 202; cx += 16.4) {
        put(solid(disc(x, y, cx, 80, 3)) * 0.9, ...STEEL);
        put(solid(disc(x, y, cx, 130, 3)) * 0.9, ...STEEL);
      }
      for (const cx of [50, 206]) for (let cy = 92; cy <= 122; cy += 15) {
        put(solid(disc(x, y, cx, cy, 3)) * 0.9, ...STEEL);
      }
      // Vertical panel seams.
      for (const cx of [86, 128, 170]) put(solid(roundRect(x, y, cx, 104, 1.8, 28, 1)) * 0.6, 0.20, 0.20, 0.24);
      // The rail it runs on.
      put(solid(roundRect(x, y, 128, 150, 112, 4, 2)) * 0.9, 0.30, 0.30, 0.34);
      for (let cx = 30; cx <= 226; cx += 28) put(solid(roundRect(x, y, cx, 154, 7, 4, 2)) * 0.8, ...WOOD);
    },
  },

  // Low and clawed, a tail counterweight sweeping out back-low and small
  // raptor feet gripping the flanks. Aggressive and narrow, unlike anything
  // else in the roster -- the closest thing here (griffon) reads as wings
  // swept UP and OUT, where this reads as a body swept BACK and DOWN.
  raptor: {
    halfW: 70, radius: 12, wheelX: [32, 220], wheelR: 26,
    seat: { cy: 58, hw: 34, hh: 26, r: 10 },
    behind(put, x, y) {
      // Tail: three tapering segments low and behind, well clear of the
      // rider's head -- every point of it sits below row 96.
      put(solid(capsule(x, y, 128, 70, 128, 96, 15)) * 0.95, 0.24, 0.42, 0.22);
      put(solid(capsule(x, y, 128, 88, 108, 108, 10)) * 0.9, 0.22, 0.38, 0.20);
      put(solid(capsule(x, y, 108, 104, 90, 118, 6)) * 0.85, 0.20, 0.34, 0.18);
      // Clawed forearms, outboard and reaching UP well past the body top --
      // the one part of this kart that lives in the scored "free" region, and
      // shaped nothing like a feather fan or a swept wing: two bent limbs
      // ending in a three-claw hand, elbow out and away from the centreline.
      for (const dir of [-1, 1]) {
        const ex = 128 + dir * 94;
        put(solid(capsule(x, y, 128 + dir * 60, 96, ex, 50, 9)) * 0.95, 0.26, 0.44, 0.24);
        put(solid(capsule(x, y, ex, 50, ex + dir * 8, 20, 7)) * 0.95, 0.28, 0.46, 0.25);
        for (let k = -1; k <= 1; k++) {
          put(solid(capsule(x, y, ex + dir * 8, 20, ex + dir * (8 + k * 9), 4, 3)) * 0.9, 0.14, 0.14, 0.16);
        }
      }
      // Clawed feet, outboard and low -- pure personality, never near the
      // rider column at all.
      for (const dir of [-1, 1]) {
        const fx = 128 + dir * 92;
        put(solid(capsule(x, y, fx, 96, fx + dir * 14, 122, 9)) * 0.95, 0.26, 0.44, 0.24);
        for (let k = 0; k < 3; k++) {
          put(solid(capsule(x, y, fx + dir * 14, 122, fx + dir * (20 + k * 5), 134, 3)) * 0.9, 0.14, 0.14, 0.16);
        }
      }
    },
    front(put, x, y) {
      // Toothy snout ornament, low-centre, and clawed tread marks.
      put(solid(wedge(x, y, 128, 116, 148, 22)), 0.30, 0.48, 0.26);
      for (const cx of [116, 140]) put(solid(wedge(x, y, cx, 132, 146, 4)) * 0.9, 0.92, 0.90, 0.80);
      for (let cx = 70; cx <= 186; cx += 19) put(solid(capsule(x, y, cx, 104, cx + 6, 96, 3)) * 0.7, 0.16, 0.28, 0.15);
    },
  },

  // Stocky and wide, with big curled horns rising well outboard of the body --
  // the docs say horns belong outboard, and nothing else in the roster takes
  // them this far up. Dwarf ram cavalry, not a kodo's straight bone spread.
  ram: {
    halfW: 84, radius: 6, wheelX: [30, 226], wheelR: 30,
    seat: { cy: 56, hw: 50, hh: 30, r: 5 },
    behind(put, x, y) {
      for (const dir of [-1, 1]) {
        const bx = 128 + dir * 66;
        // Three-segment curl: out, up, and back in toward the centreline --
        // outboard the whole way, so height is free to use.
        put(solid(capsule(x, y, bx, 90, bx + dir * 26, 54, 11)) * 0.95, ...BONE);
        put(solid(capsule(x, y, bx + dir * 26, 54, bx + dir * 14, 20, 9)) * 0.95, 0.90, 0.87, 0.76);
        put(solid(capsule(x, y, bx + dir * 14, 20, bx - dir * 4, 8, 7)) * 0.9, 0.94, 0.91, 0.80);
        // Ridged texture along the curl.
        for (let k = 0; k < 4; k++) {
          const t = 0.2 + k * 0.22;
          put(solid(disc(x, y, bx + dir * 26 * t, 90 - t * 36, 3)) * 0.6, 0.68, 0.64, 0.52);
        }
      }
    },
    front(put, x, y) {
      // Battering-ram faceplate, low and centred.
      put(solid(roundRect(x, y, 128, 132, 44, 14, 6)), ...STEEL);
      put(solid(roundRect(x, y, 128, 132, 34, 8, 4)), 0.30, 0.30, 0.34);
      for (const cx of [96, 160]) put(solid(disc(x, y, cx, 132, 5)) * 0.9, ...COPPER);
      // Wool tufts along the flanks.
      for (let cx = 66; cx <= 190; cx += 14) put(solid(disc(x, y, cx, 118, 5)) * 0.5, 0.88, 0.86, 0.80);
    },
  },

  // Tail feathers fanning up BEHIND the rider, beak prow below.
  chicken: {
    halfW: 74, radius: 22, wheelX: [36, 220], wheelR: 26,
    seat: { cy: 64, hw: 34, hh: 24, r: 16 },
    behind(put, x, y) {
      // Fan sits in the seat-back zone, so it frames the rider instead of
      // covering them -- rows 28-72 are always drawn behind. Every blade's
      // topmost point (ty - r) stays below row 30: reaching higher puts feathers
      // across the rider's head, which verify-karts.js rejects.
      for (const [dx, ty, r] of [[-50, 58, 12], [-25, 50, 13], [0, 46, 14], [25, 50, 13], [50, 58, 12]]) {
        put(solid(capsule(x, y, 128 + dx * 0.5, 78, 128 + dx, ty, r)) * 0.95, 0.88, 0.80, 0.34);
        put(solid(capsule(x, y, 128 + dx * 0.5, 78, 128 + dx, ty + 8, r * 0.5)) * 0.7, 0.98, 0.93, 0.58);
      }
    },
    front(put, x, y) {
      put(solid(wedge(x, y, 128, 118, 158, 30)), 0.95, 0.58, 0.10);
      put(solid(wedge(x, y, 128, 124, 150, 18)) * 0.8, 1.0, 0.74, 0.24);
      for (const cx of [96, 160]) put(solid(disc(x, y, cx, 104, 9)) * 0.9, 0.98, 0.93, 0.58);
    },
  },
};

function build(id, spec) {
  writeTGA("kart-" + id + ".tga", 256, 160, (x, y) => {
    let r = 0, g = 0, b = 0, a = 0;
    const put = (mask, cr, cg, cb) => {
      if (mask <= 0) return;
      const m = Math.min(1, mask);
      r = r * (1 - m) + cr * m; g = g * (1 - m) + cg * m; b = b * (1 - m) + cb * m;
      a = Math.max(a, m);
    };

    // Ground shadow, widest and lowest.
    put(solid(roundRect(x, y, 128, 146, 104, 12, 12)) * 0.55, 0.02, 0.02, 0.03);

    // Anything that belongs behind the wheels and body.
    if (spec.behind) spec.behind(put, x, y);

    // Wheels, unless this kart brings its own.
    if (!spec.customWheels) {
      for (const cx of spec.wheelX) {
        put(solid(roundRect(x, y, cx, 108, spec.wheelR, 34, 12)), ...TYRE);
        put(solid(roundRect(x, y, cx, 108, spec.wheelR - 6, 28, 10)) * 0.5, 0.16, 0.16, 0.19);
        put(solid(roundRect(x, y, cx, 106, 12, 13, 6)), ...HUB);
        put(solid(roundRect(x, y, cx, 106, 4, 4, 2)), 0.28, 0.28, 0.31);
        put(solid(roundRect(x, y, cx, 84, spec.wheelR - 8, 5, 4)) * 0.35, 0.45, 0.47, 0.52);
      }
    }

    // Rear axle behind the body.
    put(solid(roundRect(x, y, 128, 116, 96, 6, 3)), 0.22, 0.22, 0.25);

    // THE COLLAR. Top edge pinned to BODY_TOP and always wider than the rider's
    // column, so the front slice is never transparent over their legs.
    put(solid(roundRect(x, y, 128, BODY_TOP + 32, spec.halfW, 32, spec.radius)), 0.95, 0.95, 0.95);
    put(solid(roundRect(x, y, 128, 122, spec.halfW - 2, 15, Math.min(8, spec.radius))) * 0.55, 0.42, 0.42, 0.46);
    put(solid(roundRect(x, y, 128, BODY_TOP + 4, spec.halfW - 4, 5, 4)) * 0.85, 1.0, 1.0, 1.0);

    // Seat back, framing whoever is sitting in it. Always behind the rider, and
    // shaped per kart -- a rocket's low bucket and a minecart's plank board are
    // the difference between six silhouettes and one silhouette six times.
    const s = spec.seat || { cy: 58, hw: 44, hh: 30, r: 14 };
    put(solid(roundRect(x, y, 128, s.cy, s.hw, s.hh, s.r)), 0.20, 0.20, 0.24);
    put(solid(roundRect(x, y, 128, s.cy - 2, s.hw - 8, s.hh - 6, Math.max(1, s.r - 3))), 0.33, 0.33, 0.38);

    // Per-kart detail that lives in the front slice.
    if (spec.front) spec.front(put, x, y);

    return [r, g, b, a];
  });
}

for (const [id, spec] of Object.entries(KARTS)) build(id, spec);

// The original single kart stays as the fallback for anything without art.
build("default", { halfW: 78, radius: 14, wheelX: [36, 220], wheelR: 30,
  front(put, x, y) {
    put(solid(roundRect(x, y, 128, 132, 62, 8, 5)), 0.30, 0.30, 0.34);
    for (const cx of [104, 152]) {
      put(solid(roundRect(x, y, cx, 136, 9, 7, 4)), 0.18, 0.18, 0.21);
      put(solid(roundRect(x, y, cx, 136, 5, 4, 3)), 0.06, 0.06, 0.07);
    }
  } });
fs.copyFileSync(path.join(OUT, "kart-default.tga"), path.join(OUT, "kart.tga"));
console.log("kart.tga (copy of kart-default.tga, fallback)");
