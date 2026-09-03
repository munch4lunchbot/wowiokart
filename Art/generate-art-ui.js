// THE INTERFACE, AS ART RATHER THAN AS RECTANGLES.
//
// Every button in the addon was a filled quad with a one-pixel border round it,
// which is what WoW's BackdropTemplate gives you for free and is exactly what
// every addon dialog in the game looks like. A game's buttons are objects: they
// have a shape, they catch the light along one edge and lose it along the
// other, and they respond to being touched. None of that can be done with a
// border colour, so this generates the plates.
//
// Everything here is NEUTRAL -- greys carrying shape in the alpha -- because it
// is all tinted per state with SetVertexColor, and any hue baked in survives
// the tint. Same rule as tree.tga and grass.tga.
//
//   node Art/generate-art-ui.js <artDir>
const fs = require("fs"), path = require("path");
const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });

function writeTGA(name, w, h, fn) {
  const header = Buffer.alloc(18);
  header[2] = 2; header.writeUInt16LE(w, 12); header.writeUInt16LE(h, 14);
  header[16] = 32; header[17] = 0x28;
  const body = Buffer.alloc(w * h * 4);
  let i = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const [r, g, b, a] = fn(x, y, w, h);
      const q = (v) => Math.max(0, Math.min(255, Math.round(v * 255)));
      body[i++] = q(b); body[i++] = q(g); body[i++] = q(r); body[i++] = q(a);
    }
  }
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([header, body]));
  console.log(name, w + "x" + h);
}

const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
const smooth = (t) => t * t * (3 - 2 * t);

// --- SHAPE ------------------------------------------------------------------
//
// Signed distance to a rounded rectangle, in pixels: negative inside, positive
// outside. Antialiasing then costs one smoothstep rather than a supersample,
// and the same field gives the bevel its direction for free.
function roundedBox(x, y, w, h, radius, inset) {
  const cx = Math.abs(x + 0.5 - w / 2) - (w / 2 - inset - radius);
  const cy = Math.abs(y + 0.5 - h / 2) - (h / 2 - inset - radius);
  const dx = Math.max(cx, 0), dy = Math.max(cy, 0);
  return Math.hypot(dx, dy) + Math.min(Math.max(cx, cy), 0) - radius;
}

// THE THREE-SLICE. A button is any width, and a texture stretched to fit turns
// its rounded corners into ovals. So the plate is authored once at a fixed
// height with square-ish caps, and drawn as three pieces: the two caps keep
// their aspect, the middle strip stretches. That is why the corner radius here
// is in real pixels and why the middle 12 columns are deliberately identical --
// stretching them has to be invisible.
const PLATE_W = 64, PLATE_H = 40, CAP = 26, RADIUS = 9;

/** Column x mapped so the middle of the texture is flat. */
function plateShape(x, y) {
  // Everything within CAP of an edge is real geometry; the middle is a
  // constant slice, so it can stretch to any width without distorting.
  let sx = x;
  if (x >= CAP && x < PLATE_W - CAP) sx = CAP;
  else if (x >= PLATE_W - CAP) sx = x - (PLATE_W - CAP * 2);
  return roundedBox(sx, y, CAP * 2, PLATE_H, RADIUS, 1);
}

// ---- the plate itself ------------------------------------------------------
//
// A vertical gradient with a lit top edge and a shadowed bottom one. The bevel
// is a band that follows the outline rather than a pair of horizontal lines, so
// the corners are lit correctly instead of looking like a sticker.
writeTGA("btn.tga", PLATE_W, PLATE_H, (x, y, w, h) => {
  const d = plateShape(x, y);
  const inside = 1 - smooth(clamp(d + 1, 0, 1));
  if (inside <= 0) return [0, 0, 0, 0];
  const v = (y + 0.5) / h;
  // Body: brighter at the top, so it reads as a surface facing up into light.
  let tone = 0.86 - v * 0.42;
  // The bevel band, just inside the edge. Lit along the top of the outline and
  // dark along the bottom -- it follows the OUTLINE rather than being a pair of
  // horizontal lines, so the rounded corners are lit correctly instead of
  // looking like a sticker with a highlight painted across it.
  const band = clamp(1 - Math.abs(d + 2.6) / 2.6, 0, 1);
  tone += band * (0.5 - v) * 2.1;
  // A soft inner shadow along the very bottom, so the plate sits ON something.
  tone -= clamp((v - 0.78) / 0.22, 0, 1) * 0.22;
  // A DARK RIM around the whole outline. Without it the plate has to rely on
  // its own tint being darker than whatever is behind it, which on a race
  // screen it very often is not -- a blue button over a blue sky simply
  // dissolves. Two pixels of near-black is what separates a control from its
  // background in every game menu ever drawn.
  const rim = clamp(1 - Math.abs(d + 0.9) / 1.9, 0, 1);
  tone = tone * (1 - rim) + 0.06 * rim;
  return [tone, tone, tone, inside];
});

// ---- hover sheen: additive, top-weighted -----------------------------------
//
// The thing that makes a button feel alive is not a colour change, it is a
// specular that arrives when the pointer does. Additive, so it brightens
// whatever the plate is tinted rather than washing it to grey.
writeTGA("btnsheen.tga", PLATE_W, PLATE_H, (x, y, w, h) => {
  const d = plateShape(x, y);
  const inside = 1 - smooth(clamp(d + 1, 0, 1));
  if (inside <= 0) return [0, 0, 0, 0];
  const v = (y + 0.5) / h;
  // Gloss across the top third, falling away fast; a thin return along the
  // bottom edge for bounce light.
  const top = Math.pow(clamp(1 - v / 0.46, 0, 1), 1.6);
  const bounce = Math.pow(clamp((v - 0.80) / 0.20, 0, 1), 2.0) * 0.30;
  return [1, 1, 1, inside * (top * 0.55 + bounce)];
});

// ---- outer glow, for the focused or selected plate -------------------------
writeTGA("btnglow.tga", PLATE_W + 24, PLATE_H + 24, (x, y, w, h) => {
  // Same shape, grown by the padding, then blurred outward by distance.
  const sx = x - 12, sy = y - 12;
  let cx = sx;
  if (sx >= CAP && sx < PLATE_W - CAP) cx = CAP;
  else if (sx >= PLATE_W - CAP) cx = sx - (PLATE_W - CAP * 2);
  const d = roundedBox(cx, sy, CAP * 2, PLATE_H, RADIUS, 1);
  const a = Math.pow(clamp(1 - d / 11, 0, 1), 2.0);
  return [1, 1, 1, a * 0.85];
});

// ---- selection chevron -----------------------------------------------------
//
// A menu row that is merely a different colour when chosen makes you compare
// two colours. A mark beside it does not.
writeTGA("chevron.tga", 24, 32, (x, y, w, h) => {
  const u = (x + 0.5) / w, v = (y + 0.5) / h;
  // Two strokes meeting at a point, thickness in UV so it scales cleanly.
  const arm = Math.abs(Math.abs(v - 0.5) * 2 - (1 - u) * 0.9);
  const a = clamp(1 - arm / 0.13, 0, 1) * clamp(u / 0.12, 0, 1) * clamp((1 - u) / 0.10, 0, 1);
  return [1, 1, 1, Math.pow(a, 0.8)];
});

// ---- panel corner ----------------------------------------------------------
//
// Panels had a one-pixel square border. Four of these in the corners, tinted to
// the border colour and flipped by texcoord, round the whole thing off.
const CORNER = 20;
writeTGA("corner.tga", CORNER, CORNER, (x, y, w, h) => {
  // Distance from the rounded outer edge of a corner of radius CORNER-2.
  const dx = (CORNER - 2) - (x + 0.5), dy = (CORNER - 2) - (y + 0.5);
  const r = Math.hypot(Math.max(dx, 0), Math.max(dy, 0));
  const outside = smooth(clamp((r - (CORNER - 3)) + 1, 0, 1));
  // The corner is the FILL plus a lit rim just inside the curve.
  const rim = clamp(1 - Math.abs(r - (CORNER - 3.6)) / 1.4, 0, 1);
  const fill = 1 - outside;
  return [1, 1, 1, fill * 0.0 + rim * fill];
});

// ---- a solid rounded fill, for panels ---------------------------------------
writeTGA("cornerfill.tga", CORNER, CORNER, (x, y) => {
  const dx = (CORNER - 2) - (x + 0.5), dy = (CORNER - 2) - (y + 0.5);
  const r = Math.hypot(Math.max(dx, 0), Math.max(dy, 0));
  return [1, 1, 1, 1 - smooth(clamp((r - (CORNER - 3)) + 1, 0, 1))];
});

// ---- the panel plate, nine-sliced ------------------------------------------
//
// Panels were a filled quad with a one-pixel square border, plus a gradient
// skin stretched over it. Square corners on a dark rectangle is the single
// most recognisable "this is a configuration window" cue there is.
//
// Nine-sliced rather than three: a panel is arbitrary in BOTH directions, so
// the four corners have to keep their pixels while the edges stretch along
// their own axis and the middle stretches both ways. The body is therefore
// flat -- a gradient over the whole height cannot survive a stretched middle
// row -- and the modelling lives in the top and bottom edges, which is where a
// real panel catches and loses the light anyway.
const PANEL = 56, PANEL_C = 18, PANEL_R = 12;
writeTGA("panelplate.tga", PANEL, PANEL, (x, y, w, h) => {
  let sx = x, sy = y;
  if (x >= PANEL_C && x < w - PANEL_C) sx = PANEL_C;
  else if (x >= w - PANEL_C) sx = x - (w - PANEL_C * 2);
  if (y >= PANEL_C && y < h - PANEL_C) sy = PANEL_C;
  else if (y >= h - PANEL_C) sy = y - (h - PANEL_C * 2);
  const d = roundedBox(sx, sy, PANEL_C * 2, PANEL_C * 2, PANEL_R, 1);
  const inside = 1 - smooth(clamp(d + 1, 0, 1));
  if (inside <= 0) return [0, 0, 0, 0];
  // Flat body. The tint the caller passes is the panel's colour, and it should
  // arrive on screen as that colour rather than as 0.7 of it.
  let tone = 1.0;
  // Inner bevel: lit along the top of the outline, shadowed along the bottom.
  const band = clamp(1 - Math.abs(d + 2.4) / 2.4, 0, 1);
  const v = (sy + 0.5) / (PANEL_C * 2);
  tone += band * (0.5 - v) * 1.5;
  // And the rim, so a panel is separated from whatever is behind it.
  const rim = clamp(1 - Math.abs(d + 0.9) / 1.9, 0, 1);
  tone = tone * (1 - rim) + 0.10 * rim;
  return [tone, tone, tone, inside];
});

// ---- a warm hairline along a panel's top edge -------------------------------
//
// The old one was a straight bar that ran into the square corners. This one
// fades out before the curve starts, so it reads as light catching an edge
// rather than as a line drawn on top of a box.
writeTGA("panelgleam.tga", PANEL, 4, (x, y, w, h) => {
  const u = (x + 0.5) / w, v = (y + 0.5) / h;
  const across = Math.pow(Math.sin(Math.PI * clamp(u, 0, 1)), 0.45);
  const down = Math.pow(1 - v, 2.2);
  return [1, 1, 1, across * down];
});

// ---- THE LOGO --------------------------------------------------------------
//
// "AZEROTH KART" was a 54pt gold FontString with a drop shadow: a word, not a
// logo. Every game has a wordmark, and the difference between the two is the
// clearest single signal of whether something was designed or merely labelled.
//
// Drawn from letterforms authored here rather than set in a font, because the
// rest of this game's art is chunky and low-resolution on purpose -- the karts,
// the props, the skyline -- and a smooth typeface floating above it would
// belong to a different product. Slab-bold, sheared into italic because it is a
// racing game, bevelled and outlined so it reads on any background.
const LOGO_GLYPHS = {
  A: ["00111100", "01111110", "11000011", "11000011", "11111111", "11111111",
      "11000011", "11000011", "11000011", "11000011", "11000011"],
  Z: ["11111111", "11111111", "00000110", "00001100", "00011000", "00110000",
      "01100000", "11000000", "11000000", "11111111", "11111111"],
  E: ["11111111", "11111111", "11000000", "11000000", "11111100", "11111100",
      "11000000", "11000000", "11000000", "11111111", "11111111"],
  R: ["11111100", "11111110", "11000011", "11000011", "11111110", "11111100",
      "11011000", "11001100", "11000110", "11000011", "11000011"],
  O: ["00111100", "01111110", "11000011", "11000011", "11000011", "11000011",
      "11000011", "11000011", "11000011", "01111110", "00111100"],
  T: ["11111111", "11111111", "00011000", "00011000", "00011000", "00011000",
      "00011000", "00011000", "00011000", "00011000", "00011000"],
  H: ["11000011", "11000011", "11000011", "11000011", "11111111", "11111111",
      "11000011", "11000011", "11000011", "11000011", "11000011"],
  K: ["11000110", "11001100", "11011000", "11110000", "11100000", "11110000",
      "11011000", "11001100", "11000110", "11000011", "11000011"],
  " ": ["00000000", "00000000", "00000000", "00000000", "00000000", "00000000",
        "00000000", "00000000", "00000000", "00000000", "00000000"],
};

{
  const WORD = "AZEROTH KART";
  const S = 5;                       // pixels per authored bit
  const GW = 8 * S, GH = 11 * S;     // glyph box
  const GAP = S;
  const SHEAR = 0.20;                // italic lean, in x per y
  const LOGO_W = 640, LOGO_H = 128;
  // A full glyph box for the word space put 55px of nothing in the middle of a
  // twelve-letter wordmark, which reads as two words rather than one title.
  const advance = GW + GAP;
  const spaceAdvance = Math.round(advance * 0.45);
  const advanceOf = (ch) => (ch === " " ? spaceAdvance : advance);
  let wordW = -GAP;
  for (const ch of WORD) wordW += advanceOf(ch);
  const x0 = Math.round((LOGO_W - wordW - GH * SHEAR) / 2);
  const y0 = Math.round((LOGO_H - GH) / 2);

  // The solid mask first; the bevel and the outline are both derived from it,
  // which is what keeps them consistent across every letter.
  const mask = new Float32Array(LOGO_W * LOGO_H);
  let pen = 0;
  for (let i = 0; i < WORD.length; i++) {
    const rows = LOGO_GLYPHS[WORD[i]] || LOGO_GLYPHS[" "];
    const penX = pen;
    pen += advanceOf(WORD[i]);
    for (let r = 0; r < rows.length; r++) {
      for (let c = 0; c < 8; c++) {
        if (rows[r][c] !== "1") continue;
        for (let dy = 0; dy < S; dy++) {
          const py = y0 + r * S + dy;
          // Lean from the BASELINE, so the letters stand on the same line.
          const lean = Math.round((GH - (r * S + dy)) * SHEAR);
          for (let dx = 0; dx < S; dx++) {
            const px = x0 + penX + c * S + dx + lean;
            if (px >= 0 && px < LOGO_W && py >= 0 && py < LOGO_H) mask[py * LOGO_W + px] = 1;
          }
        }
      }
    }
  }
  // Distance outward from the mask, for the outline; and inward, for the bevel.
  function spread(src, radius) {
    let cur = Float32Array.from(src);
    const out = Float32Array.from(src);
    for (let step = 1; step <= radius; step++) {
      const next = Float32Array.from(cur);
      for (let y = 0; y < LOGO_H; y++) {
        for (let x = 0; x < LOGO_W; x++) {
          if (cur[y * LOGO_W + x] > 0) continue;
          const near = (cur[(y - 1 >= 0 ? y - 1 : 0) * LOGO_W + x] > 0)
            || (cur[(y + 1 < LOGO_H ? y + 1 : y) * LOGO_W + x] > 0)
            || (cur[y * LOGO_W + (x - 1 >= 0 ? x - 1 : 0)] > 0)
            || (cur[y * LOGO_W + (x + 1 < LOGO_W ? x + 1 : x)] > 0);
          if (near) { next[y * LOGO_W + x] = 1; out[y * LOGO_W + x] = Math.max(out[y * LOGO_W + x], 1 - step / (radius + 1)); }
        }
      }
      cur = next;
    }
    return out;
  }
  const outline = spread(mask, 4);

  writeTGA("logo.tga", LOGO_W, LOGO_H, (x, y, w, h) => {
    const i = y * w + x;
    const solid = mask[i];
    const halo = outline[i];
    if (solid <= 0 && halo <= 0) return [0, 0, 0, 0];
    if (solid <= 0) {
      // Outline: near-black, fading out, so the wordmark holds against the live
      // race running behind the menu.
      return [0.03, 0.03, 0.05, Math.min(1, halo * 1.6)];
    }
    // Face: a warm vertical gradient, gold at the top into a deeper amber.
    const v = clamp((y - y0) / GH, 0, 1);
    let r = 1.00 - v * 0.20, g = 0.86 - v * 0.42, b = 0.36 - v * 0.28;
    // Top-lit bevel. Anything within two pixels of the top of the letterform is
    // catching light; the bottom two are in shadow.
    const above = mask[(y - 3 >= 0 ? y - 3 : 0) * w + x];
    const below = mask[(y + 3 < h ? y + 3 : y) * w + x];
    if (above <= 0) { r = Math.min(1, r + 0.30); g = Math.min(1, g + 0.34); b = Math.min(1, b + 0.40); }
    if (below <= 0) { r *= 0.52; g *= 0.42; b *= 0.36; }
    return [r, g, b, 1];
  });
}

// ---- earned / not earned ---------------------------------------------------
//
// The trophy room marked an unlocked achievement with the character "*" and a
// locked one with "-". Typing a shape instead of drawing one is the single most
// legible sign that nobody looked at the screen -- and the comment beside it
// was right that the marker has to differ in SHAPE, not just colour, so this is
// a real tick and a real empty socket.
writeTGA("tick.tga", 28, 28, (x, y, w, h) => {
  const u = (x + 0.5) / w, v = (y + 0.5) / h;
  // Two strokes: the short down-stroke and the long up-stroke of a check.
  function stroke(ax, ay, bx, by, thickness) {
    const dx = bx - ax, dy = by - ay;
    const t = clamp(((u - ax) * dx + (v - ay) * dy) / (dx * dx + dy * dy), 0, 1);
    const px = ax + dx * t - u, py = ay + dy * t - v;
    return clamp(1 - Math.hypot(px, py) / thickness, 0, 1);
  }
  const a = Math.max(stroke(0.16, 0.52, 0.40, 0.76, 0.11),
                     stroke(0.40, 0.76, 0.86, 0.22, 0.11));
  return [1, 1, 1, Math.pow(a, 0.65)];
});

writeTGA("socket.tga", 28, 28, (x, y, w, h) => {
  const u = (x + 0.5) / w - 0.5, v = (y + 0.5) / h - 0.5;
  // A hollow ring: the same footprint as the tick, obviously empty.
  const r = Math.hypot(u, v);
  const ring = clamp(1 - Math.abs(r - 0.30) / 0.075, 0, 1);
  return [1, 1, 1, Math.pow(ring, 0.8)];
});
