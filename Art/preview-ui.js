// THE INTERFACE, LOOKED AT.
//
// Art/preview-render.js does this for the race scene and it is the reason the
// scene stopped being guesswork. The menus had no equivalent: every button,
// panel and menu row in the addon was authored blind, and "it is a rectangle
// with a one-pixel border" was invisible from inside the code that drew it.
//
// This composites the real shipped TGAs the way UI/MainMenu.lua composites
// them -- same three-slice, same states, same tints -- and writes a PNG.
//
//   node Art/preview-ui.js <artDir> <outPng>
const fs = require("fs"), zlib = require("zlib"), path = require("path");

const ART = process.argv[2] || path.join(__dirname);
const OUT = process.argv[3] || path.join(__dirname, "..", "ui-preview.png");
// THE STAGE IS THE MENU'S OWN STAGE, read out of UI/MainMenu.lua rather than
// picked here. It was 900x560 while the addon has always built the menu at
// 1120x790, so this sheet composited a 960-wide content panel onto a 900-wide
// canvas and then reported the collision that geometry forced -- a fault of the
// mirror, not of the menu. A preview on a canvas the screen never has is worse
// than no preview: it invents faults and hides real ones.
const MENU_LUA = fs.readFileSync(path.join(__dirname, "..", "UI", "MainMenu.lua"), "utf8");
const STAGE = MENU_LUA.match(/local MENU_W, MENU_H = (\d+), (\d+)/);
if (!STAGE) throw new Error("preview-ui: could not find MENU_W/MENU_H in UI/MainMenu.lua");
const W = +(process.env.W || STAGE[1]), H = +(process.env.H || STAGE[2]);

const fb = new Float32Array(W * H * 3);
function blend(x, y, r, g, b, a) {
  if (a <= 0 || x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 3, m = a > 1 ? 1 : a;
  fb[i] += (r - fb[i]) * m; fb[i + 1] += (g - fb[i + 1]) * m; fb[i + 2] += (b - fb[i + 2]) * m;
}
function add(x, y, r, g, b, a) {
  if (a <= 0 || x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 3;
  fb[i] += r * a; fb[i + 1] += g * a; fb[i + 2] += b * a;
}
function loadTGA(name) {
  const b = fs.readFileSync(path.join(ART, name));
  const w = b.readUInt16LE(12), h = b.readUInt16LE(14), off = 18 + b[0];
  const px = new Float32Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    px[i * 4] = b[off + i * 4 + 2] / 255; px[i * 4 + 1] = b[off + i * 4 + 1] / 255;
    px[i * 4 + 2] = b[off + i * 4] / 255; px[i * 4 + 3] = b[off + i * 4 + 3] / 255;
  }
  return { w, h, px };
}
const tex = {};
// Everything, rather than a hand-kept list: the first version of this named
// eight files and silently drew no panel at all because panelplate.tga was not
// one of them. A preview that quietly omits what it cannot find is worse than
// one that fails.
for (const f of fs.readdirSync(ART).filter((f) => f.endsWith(".tga"))) {
  tex[f.replace(".tga", "")] = loadTGA(f);
}
for (const need of ["btn", "btnsheen", "chevron", "panelplate", "panelgleam", "hairline"]) {
  if (!tex[need]) throw new Error("preview-ui: " + need + ".tga is missing from " + ART);
}

// THE THREE-SLICE, exactly as UI:NewButton does it: the two caps keep their
// pixels, the middle column stretches. Getting this wrong is what turns a
// rounded corner into an oval, so the preview has to do it the same way.
const CAP = 26;
function slice(t, x0, y0, bw, bh, tint, alpha, mode) {
  // The framebuffer is a pixel grid; a fractional origin indexes off the end of
  // a row and paints garbage into the next one. WoW happily takes subpixel
  // coordinates, so the addon does not care -- the mirror has to.
  x0 = Math.round(x0); y0 = Math.round(y0); bw = Math.round(bw); bh = Math.round(bh);
  for (let y = 0; y < bh; y++) {
    const v = ((y + 0.5) / bh) * t.h;
    const py = Math.min(t.h - 1, Math.max(0, Math.floor(v)));
    for (let x = 0; x < bw; x++) {
      // Same fixed cap as UI:NewButton's layoutPlate.
      const cap = Math.min(CAP, bh * CAP / 40, bw / 2);
      let u;
      if (x < cap) u = (x + 0.5) * (CAP / cap);
      else if (x >= bw - cap) u = t.w - (bw - x) * (CAP / cap) + 0.5;
      else u = CAP + ((x - cap) / (bw - cap * 2)) * (t.w - CAP * 2);
      const px = Math.min(t.w - 1, Math.max(0, Math.floor(u)));
      const i = (py * t.w + px) * 4;
      const a = t.px[i + 3] * alpha;
      const fn = mode === "add" ? add : blend;
      fn(x0 + x, y0 + y, t.px[i] * tint[0], t.px[i + 1] * tint[1], t.px[i + 2] * tint[2], a);
    }
  }
}
function stretch(t, x0, y0, bw, bh, tint, alpha, mode) {
  for (let y = 0; y < bh; y++) {
    const py = Math.min(t.h - 1, Math.floor(((y + 0.5) / bh) * t.h));
    for (let x = 0; x < bw; x++) {
      const px = Math.min(t.w - 1, Math.floor(((x + 0.5) / bw) * t.w));
      const i = (py * t.w + px) * 4;
      const fn = mode === "add" ? add : blend;
      fn(x0 + x, y0 + y, t.px[i] * tint[0], t.px[i + 1] * tint[1], t.px[i + 2] * tint[2],
        t.px[i + 3] * alpha);
    }
  }
}

const { textWidth, drawText } = require("./hud-font.js");
/** Wrapped to a width, the way a FontString with two horizontal anchors wraps.
 *  Returns the y just below the last line, so what follows can flow from it. */
function labelWrapped(cx, y, str, size, colour, maxWidth) {
  const words = str.split(" ");
  const lines = [];
  let line = "";
  for (const word of words) {
    const candidate = line ? line + " " + word : word;
    if (textWidth(candidate, size) > maxWidth && line) { lines.push(line); line = word; }
    else line = candidate;
  }
  if (line) lines.push(line);
  const step = Math.round(size * 1.45);
  lines.forEach((l, i) => label(cx, y + i * step, l, size, colour, "center"));
  return y + lines.length * step;
}

function label(x, y, s, size, colour, align) {
  const wpx = textWidth(s, size);
  const sx = align === "center" ? Math.round(x - wpx / 2)
    : (align === "right" ? Math.round(x - wpx) : x);
  drawText((px, py, r, g, b, a) => blend(px, py, r, g, b, a), s, sx, y, size, colour, 1);
}

// THE PLAN VIEW, exactly as Builder:Compile builds it.
//
// The first version of this integrated the raw authored turn rate and drew
// ten open squiggles -- which looked like a bug in the game and was a bug in
// the mirror. Compile normalises the layout's TOTAL turn to exactly 2*pi, so
// whatever a circuit is authored as, its map path closes into a loop. Any
// mirror that does not do that is drawing a different game.
const STEP = 2;
function planOf(t) {
  const authored = t.layout.reduce((a, p) => a + p[0], 0);
  const scale = t.len / authored;
  const samples = Math.floor(t.len / STEP) + 1;
  // The residual turn, spread evenly, rather than a multiplicative gain.
  const base = +(process.env.MAPGAIN || 0.0042);   // Builder.MAP_GAIN
  let turnAtBase = 0;
  for (const [len, curve] of t.layout) turnAtBase += curve * len * scale * base;
  const spread = (Math.PI * 2 - turnAtBase) / t.len;
  const path = [];
  let angle = 0, px = 0, py = 0, pieceIndex = 0;
  let pieceLeft = t.layout[0][0] * scale;
  for (let i = 0; i < samples; i++) {
    const curve = t.layout[pieceIndex][1];
    angle += curve * STEP * base + spread * STEP;
    px += Math.cos(angle) * STEP; py += Math.sin(angle) * STEP;
    path.push([px, py]);
    pieceLeft -= STEP;
    while (pieceLeft <= 0 && pieceIndex < t.layout.length - 1) {
      pieceIndex++; pieceLeft += t.layout[pieceIndex][0] * scale;
    }
  }
  // Close the residual gap, then fit into a unit box centred on zero.
  const dx = path[samples - 1][0] - path[0][0], dy = path[samples - 1][1] - path[0][1];
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (let i = 0; i < samples; i++) {
    const tt = i / (samples - 1);
    path[i][0] -= dx * tt; path[i][1] -= dy * tt;
    minX = Math.min(minX, path[i][0]); maxX = Math.max(maxX, path[i][0]);
    minY = Math.min(minY, path[i][1]); maxY = Math.max(maxY, path[i][1]);
  }
  const span = Math.max(Math.max(1e-3, maxX - minX), Math.max(1e-3, maxY - minY));
  const midX = (minX + maxX) / 2, midY = (minY + maxY) / 2;
  return path.map(([x, y]) => [(x - midX) / span, (y - midY) / span]);
}


// ---- the real home screen, parsed from UI/MainMenu.lua ---------------------
//
// Not a mock. The rows, their notes and every offset come out of the addon, so
// this cannot show a menu the game does not draw -- which is the whole reason
// the scene preview is trusted and a hand-built one would not be.
const MENU_SRC = MENU_LUA;
function parseHome() {
  const modes = [...MENU_SRC.slice(MENU_SRC.indexOf("local MODES = {"))
    .slice(0, MENU_SRC.slice(MENU_SRC.indexOf("local MODES = {")).indexOf("\n}\n"))
    .matchAll(/\{ "([^"]+)", "([^"]+)",/g)].map((m) => [m[1], m[2]]);
  const garageBlock = MENU_SRC.slice(MENU_SRC.indexOf("local GARAGE = {"));
  const garage = [...garageBlock.slice(0, garageBlock.indexOf("\n}\n"))
    .matchAll(/\{ "(\w+)", "\w+" \}/g)].map((m) => m[1]);
  const homeBlock = MENU_SRC.slice(MENU_SRC.indexOf("local HOME = {"));
  const home = {};
  for (const m of homeBlock.slice(0, homeBlock.indexOf("\n}\n")).matchAll(/(\w+) = (\d+)/g))
    home[m[1]] = +m[2];
  if (!modes.length || !garage.length || !home.modeW)
    throw new Error("preview-ui: could not parse the home menu out of UI/MainMenu.lua");
  return { modes, garage, home };
}
const { modes, garage, home } = parseHome();

const GOLD = [1.0, 0.78, 0.24], MUTED = [0.50, 0.56, 0.66];
const PALE = [0.86, 0.90, 1.0], LIT = [1, 0.95, 0.80], LIME = [0.45, 0.92, 0.45];
const REST = [0.18, 0.28, 0.42], LEAD = [0.42, 0.31, 0.08], QUIETB = [0.13, 0.17, 0.25];
const PANEL = [0.055, 0.10, 0.17];

// THE SCRIM, over something. A live race runs behind this menu in game, so a
// flat near-black here would flatter the design badly: it would hide the fact
// that the content panel has to hold its own against a moving, lit scene. A
// coarse stand-in for grass, road and sky gets the contrast honest.
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const t = y / H, i = (y * W + x) * 3;
    const sky = [0.22, 0.36, 0.55], ground = [0.16, 0.30, 0.14];
    const horizon = 0.34;
    let c = t < horizon
      ? sky.map((v, k) => v * (0.6 + 0.4 * (t / horizon)))
      : ground.map((v, k) => v * (0.7 + 0.5 * ((t - horizon) / (1 - horizon))));
    // A road running up the middle, so the panel has something bright under it.
    const road = Math.abs(x - W / 2) < (t - horizon) * W * 0.9;
    if (t > horizon && road) c = [0.34, 0.28, 0.18].map((v) => v * (0.7 + 0.5 * t));
    // The menu's own dim, from Menu:Build.
    const scrim = 0.74;
    fb[i] = c[0] * (1 - scrim) + 0.016 * scrim;
    fb[i + 1] = c[1] * (1 - scrim) + 0.024 * scrim;
    fb[i + 2] = c[2] * (1 - scrim) + 0.050 * scrim;
  }
}

// The content panel, nine-sliced like UI:NewPanel.
function panel(x0, y0, bw, bh, tint, alpha) {
  const t = tex.panelplate;
  if (!t) return;
  const C = 18, TW = t.w;
  const cw = Math.min(C, bw / 2), ch = Math.min(C, bh / 2);
  const u = [[0, C / TW], [C / TW, 1 - C / TW], [1 - C / TW, 1]];
  const xs = [x0, x0 + cw, x0 + bw - cw], ws = [cw, Math.max(1, bw - cw * 2), cw];
  const ys = [y0, y0 + ch, y0 + bh - ch], hs = [ch, Math.max(1, bh - ch * 2), ch];
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 3; c++) {
      // blit takes u0,u1,v0,v1 -- the nine pieces differ only in those.
      blitUV(t, xs[c], ys[r], ws[c], hs[r], u[c][0], u[c][1], u[r][0], u[r][1], tint, alpha);
    }
  }
  if (tex.panelgleam) blitUV(tex.panelgleam, x0 + 3, y0 + 1, bw - 6, 3, 0, 1, 0, 1, [1, .86, .55], 0.40);
}
function blitUV(t, x0, y0, bw, bh, u0, u1, v0, v1, tint, alpha) {
  x0 = Math.round(x0); y0 = Math.round(y0); bw = Math.round(bw); bh = Math.round(bh);
  for (let y = 0; y < bh; y++) {
    const py = Math.min(t.h - 1, Math.floor((v0 + ((y + 0.5) / bh) * (v1 - v0)) * t.h));
    for (let x = 0; x < bw; x++) {
      const px = Math.min(t.w - 1, Math.floor((u0 + ((x + 0.5) / bw) * (u1 - u0)) * t.w));
      const i = (py * t.w + px) * 4;
      blend(x0 + x, y0 + y, t.px[i] * tint[0], t.px[i + 1] * tint[1], t.px[i + 2] * tint[2],
        t.px[i + 3] * alpha);
    }
  }
}

// The whole stage: wordmark, rule, tagline and the content panel below, laid
// out the way Menu:Build does it against a 1120x790 authored size.
const CW = home.contentW, CH = home.contentH;
// Menu:Build puts the content panel at CENTER, 0, -45 on the stage. WoW's y
// grows UPWARD, so a -45 offset moves it 45px DOWN the screen -- the opposite
// of the sign a top-left framebuffer wants, and getting it backwards is how
// this sheet first drew the panel 90px too high and hid the very collision it
// exists to find.
const OY = Math.round(H / 2 + 45 - CH / 2);
const OX = Math.round((W - CW) / 2);
{
  const logoW = 520, logoH = 104, lx = Math.round((W - logoW) / 2), ly = 26;
  blitUV(tex.logo, lx, ly, logoW, logoH, 0, 1, 0, 1, [1, 1, 1], 1);
  blitUV(tex.hairline, Math.round((W - 560) / 2), ly + logoH + 2, 560, 3, 0, 1, 0, 1,
    [1, .76, .20], 0.8);
  label(W / 2, ly + logoH + 13, "THE MOST QUESTIONABLY SANCTIONED RACE IN AZEROTH",
    12, MUTED, "center");
  if (ly + logoH + 13 + 12 > OY) {
    throw new Error("preview-ui: the tagline runs under the content panel by "
      + Math.ceil(ly + logoH + 25 - OY) + "px");
  }
}
panel(OX, OY, CW, CH, [0.045, 0.075, 0.125], 0.97);

const M = home.margin;
label(OX + M, OY + 22, "Warm up your engines. No actual mounts were harmed.", 15, [.74, .80, .90]);
function section(title, top, width) {
  label(OX + M + 2, OY + top, title, 11, GOLD);
  if (tex.hairline) blitUV(tex.hairline, OX + M, OY + top + 16, width, 2, 0, 1, 0, 1, [1, .78, .30], 0.35);
}
section("RACE", 66, home.modeW);

modes.forEach(([name, note], i) => {
  const y = OY + home.modeTop + i * (home.modeH + home.modeGap);
  const lead = i === 0;
  slice(tex.btn, OX + M, y, home.modeW, home.modeH, lead ? LEAD : REST, 1);
  if (lead && tex.btnsheen) slice(tex.btnsheen, OX + M, y, home.modeW, home.modeH, [.9, .86, .72], 1, "add");
  if (lead && tex.chevron) blitUV(tex.chevron, OX + M + 15, y + (home.modeH - 15) / 2, 11, 15, 0, 1, 0, 1, GOLD, 1);
  label(OX + M + 34, y + (home.modeH - 11) / 2, name, 16, lead ? LIT : PALE);
  label(OX + M + home.modeW - 16, y + (home.modeH - 8) / 2, note, 11, MUTED, "right");
});

const garageTop = home.modeTop + modes.length * (home.modeH + home.modeGap) + home.sectionGap;
section("GARAGE", garageTop, home.modeW);
const cell = (home.modeW - 3 * 8) / 4;
garage.forEach((name, i) => {
  const x = OX + M + i * (cell + 8), y = OY + garageTop + home.rowGap;
  slice(tex.btn, x, y, cell, home.garageH, REST, 1);
  label(x + cell / 2, y + (home.garageH - 9) / 2, name, 13, GOLD, "center");
});

const footTop = garageTop + home.rowGap + home.garageH + home.footGap;
// The whole left column has to stop above the panel's bottom edge. BuildHome
// prints a warning about this to the chat frame, which nobody reads; here it
// is a failure, and check.js runs it.
if (footTop + home.footH > CH - 10) {
  throw new Error("preview-ui: the home menu overflows its panel by "
    + Math.ceil(footTop + home.footH - (CH - 10)) + "px");
}
const half = (home.modeW - 8) / 2;
[["TROPHY ROOM", 0], ["SETTINGS", half + 8]].forEach(([name, dx]) => {
  const x = OX + M + dx, y = OY + footTop;
  slice(tex.btn, x, y, half, home.footH, QUIETB, 1);
  label(x + half / 2, y + (home.footH - 8) / 2, name, 12, MUTED, "center");
});

// The setup preview on the right.
const previewW = CW - home.modeW - M * 2 - home.gutter;
panel(OX + CW - M - previewW, OY + 66, previewW, 400, PANEL, 0.98);
{
  const px = OX + CW - M - previewW + previewW / 2, py = OY + 66;
  label(px, py + 66, "[ RACER MODEL ]", 12, [.30, .36, .46], "center");
  label(px, py + 158, "BAINE IN THE KODO", 19, GOLD, "center");
  label(px, py + 186, "ELWYNN SPRINT  /  GOLDSHIRE'S FASTEST", 11, MUTED, "center");
  label(px, py + 206, "LAP 33.46   RACE 1:44.21", 12, GOLD, "center");
  // The four stat bars, laid out exactly as UI:NewStatBar does.
  const bx = OX + CW - M - previewW + 24, barW = previewW - 48;
  const track = barW - 72, gap = 2, cellW = (track - gap * 9) / 10;
  [["SPEED", 7], ["ACCEL", 6], ["HANDLING", 5], ["DRIFT", 8]].forEach(([name, v], i) => {
    const y = py + 226 + i * 18;
    label(bx, y + 2, name, 11, MUTED);
    for (let c = 0; c < 10; c++) {
      const t = c / 9;
      const on = c < v;
      const col = on ? [0.35 + 0.62 * t, 0.88 - 0.10 * t, 0.36 - 0.14 * t] : [0.13, 0.17, 0.24];
      for (let yy = 0; yy < 7; yy++) {
        for (let xx = 0; xx < Math.round(cellW); xx++) {
          blend(Math.round(bx + 72 + c * (cellW + gap) + xx), y + yy, col[0], col[1], col[2], 1);
        }
      }
    }
  });
  label(bx, py + 308, "ELWYNN FOREST", 12, GOLD);
  label(bx, py + 326, "Cut the river ford", 12, MUTED);
  label(bx, py + 360, "TOKENS 240     WINS 12", 12, GOLD);
}

// ---- the track grid, on demand: SCREEN=tracks --------------------------------
//
// The circuit shapes are computed the way Data/TrackBuilder.lua computes them,
// from the same authored layout, so this shows the shapes the cards will draw.
if (process.env.SCREEN === "tracks") {
  for (let i = 0; i < W * H; i++) { fb[i * 3] = 0.030; fb[i * 3 + 1] = 0.040; fb[i * 3 + 2] = 0.070; }
  panel(OX, OY - 40, CW, CH, [0.045, 0.075, 0.125], 0.97);
  label(OX + CW / 2, OY - 12, "CHOOSE YOUR TRACK", 20, GOLD, "center");

  const TRACKS = fs.readFileSync(path.join(__dirname, "..", "Data", "Tracks.lua"), "utf8");
  const tracks = [];
  for (const block of TRACKS.split(/\n  \{\n    id = "/).slice(1)) {
    const id = block.slice(0, block.indexOf('"'));
    const name = (block.match(/name = "([^"]+)"/) || [])[1] || id;
    const sub = (block.match(/subtitle = "([^"]+)"/) || [])[1] || "";
    const len = +((block.match(/length = (\d+)/) || [])[1] || 2400);
    const sweep = +((block.match(/sweep = ([\d.]+)/) || [])[1] || 3);
    const layout = [...block.slice(block.indexOf("layout = {")).matchAll(
      /len = ([\d.]+), curve = (-?[\d.]+)/g)].map((m) => [+m[1], +m[2]]);
    if (layout.length) tracks.push({ id, name, sub, len, sweep, layout });
  }

  // Menu:ShowSelection grows the column count until the cards are tall enough,
  // rather than fixing it -- so a preview that hardcodes three columns reports
  // overflowing cards the game does not have.
  const MARGIN = 42, TOP = 82, BOTTOM = 22, GAP = 18, MIN_CARD = 150;
  const availableH = CH - TOP - BOTTOM;
  const heightFor = (n) => Math.floor((availableH - GAP * (Math.ceil(tracks.length / n) - 1))
    / Math.ceil(tracks.length / n));
  let columns = 3;
  while (columns < 5 && heightFor(columns) < MIN_CARD) columns++;
  const cardW = Math.floor((CW - MARGIN * 2 - GAP * (columns - 1)) / columns);
  const cardH = heightFor(columns);
  tracks.forEach((t, i) => {
    const col = i % columns, row = Math.floor(i / columns);
    const x = OX + MARGIN + col * (cardW + GAP), y = OY - 40 + TOP + row * (cardH + GAP);
    const chosen = t.id === "elwynn";
    slice(tex.btn, x, y, cardW, cardH, chosen ? [0.44, 0.33, 0.09] : REST, 1);
    if (chosen && tex.chevron) blitUV(tex.chevron, x + 9, y + 9, 12, 16, 0, 1, 0, 1, LIT, 1);
    // The circuit's shape, 56 nodes with the start line marked.
    const plan = planOf(t), radius = 56 * 0.42;
    for (let n = 0; n < 56; n++) {
      const [px, py] = plan[Math.floor(n / 56 * plan.length)];
      const sx = Math.round(x + cardW / 2 + px * radius * 2);
      const sy = Math.round(y + 8 + 32 - py * radius * 2);
      const size = n === 0 ? 5 : 3;
      const col2 = n === 0 ? [1, 0.82, 0.25] : [0.42, 0.56, 0.72];
      for (let dy = 0; dy < size; dy++) for (let dx = 0; dx < size; dx++)
        blend(sx + dx - (size >> 1), sy + dy - (size >> 1), col2[0], col2[1], col2[2], 0.95);
    }
    let ny = labelWrapped(x + cardW / 2, y + 68, t.name, 13, chosen ? LIT : GOLD, cardW - 14);
    ny = labelWrapped(x + cardW / 2, ny + 7, t.sub, 10, MUTED, cardW - 18);
    ny = labelWrapped(x + cardW / 2, ny + 2, "3 LAPS  /  " + t.len + "M", 10, MUTED, cardW - 18);
    ny = labelWrapped(x + cardW / 2, ny + 2, "LAP 33.46", 10, GOLD, cardW - 18);
    // The whole point of drawing this is to find out whether it fits.
    if (ny > y + cardH - 4) {
      throw new Error("preview-ui: " + t.id + "'s card overflows by "
        + Math.ceil(ny - (y + cardH - 4)) + "px");
    }
  });
}

// ---- the results screen, on demand: SCREEN=results ---------------------------
//
// Seen after every race, and never once looked at outside a WoW client. The
// geometry constants are parsed out of UI/Results.lua so the sheet cannot
// drift from the screen it is describing.
if (process.env.SCREEN === "results") {
  const RES = fs.readFileSync(path.join(__dirname, "..", "UI", "Results.lua"), "utf8");
  const num = (re, fallback) => { const m = RES.match(re); return m ? +m[1] : fallback; };
  const ROW_H = num(/local ROW_HEIGHT, ROW_GAP = (\d+)/, 38);
  const ROW_GAP = num(/local ROW_HEIGHT, ROW_GAP = \d+, (\d+)/, 4);
  const DW = num(/local DESIGN_W, DESIGN_H = (\d+)/, 1340);
  const DH = num(/local DESIGN_W, DESIGN_H = \d+, (\d+)/, 830);
  const BLOCK = 300 + 22 + 760;

  for (let i = 0; i < W * H; i++) {
    fb[i * 3] = 0.020; fb[i * 3 + 1] = 0.028; fb[i * 3 + 2] = 0.052;
  }
  const sx = Math.round((W - DW) / 2), sy = Math.round((H - DH) / 2);
  // THE SHEET HAS TO AGREE WITH ITSELF. It said VICTORY and "finished 1st"
  // over a ladder that put the player fourth, which makes every judgement about
  // the screen -- which row reads as yours, whether the headline sits right --
  // an argument with the mock rather than with the design. Fourth is also the
  // more useful case to look at: it is the one that has to show BOTH the
  // winner's gold row and the player's green one.
  const PLACE = 4;
  label(W / 2, sy + 34,
    PLACE === 1 ? "VICTORY" : PLACE <= 3 ? "PODIUM FINISH" : "RACE COMPLETE",
    34, GOLD, "center");
  blitUV(tex.hairline, Math.round(W / 2 - 260), sy + 76, 520, 3, 0, 1, 0, 1, [1, .76, .20], 0.75);
  label(W / 2, sy + 88,
    "ELWYNN SPRINT  /  FINISHED " + ["1ST", "2ND", "3RD", "4TH"][PLACE - 1]
      + " OF 8  /  150CC  3 LAPS  HARD", 12, MUTED, "center");

  const bx = Math.round(W / 2 - BLOCK / 2), by = sy + 170;
  panel(bx, by, 300, 400, [0.05, 0.08, 0.14], 0.96);
  label(bx + 150, by + 120, "[ WINNER MODEL ]", 12, [.30, .36, .46], "center");
  label(bx + 150, by + 400 - 62 - 9, "BAINE", 16, GOLD, "center");
  label(bx + 150, by + 400 - 62 - 9 - 20, "MECHANO-HOG", 11, MUTED, "center");

  const tx = bx + 322;
  panel(tx, by, 760, 400, [0.05, 0.08, 0.14], 0.96);
  label(tx + 32, by + 6, "POS", 9, [.45, .52, .62]);
  label(tx + 94, by + 6, "RACER", 9, [.45, .52, .62]);
  label(tx + 760 - 34, by + 6, "TIME / GAP TO WINNER", 9, [.45, .52, .62], "right");
  const NAMES = [["BAINE", "Mechano-Hog", "1:44.21", "best 33.46", 1],
    ["THRALL", "Kodo Cruiser", "+0.42s", "best 33.71", 0],
    ["JAINA", "Rocket 9", "+1.18s", "best 33.90", 0],
    ["YOURSELF", "Mechano-Hog", "+1.93s", "best 33.52", 2],
    ["REXXAR", "Raptor GT", "+4.06s", "best 34.40", 0],
    ["SYLVANAS", "Griffon X", "+6.71s", "best 34.88", 0],
    ["ARTHAS", "Ram Rod", "+9.02s", "best 35.30", 0],
    ["CHEN", "Minecart", "+12.55s", "best 35.91", 0]];
  NAMES.forEach(([name, kart, time, best, kind], i) => {
    const y = by + 20 + i * (ROW_H + ROW_GAP);
    const tint = kind === 2 ? [0.14, 0.40, 0.26] : kind === 1 ? [0.46, 0.34, 0.09]
      : (i < 3 ? [0.15, 0.21, 0.33] : [0.10, 0.13, 0.20]);
    slice(tex.btn, tx + 18, y, 724, ROW_H, tint, 1);
    if (kind) blitUV(tex.chevron, tx + 26, y + (ROW_H - 13) / 2, 9, 13, 0, 1, 0, 1,
      kind === 2 ? [0.45, 0.92, 0.45] : GOLD, 1);
    label(tx + 42, y + 12, ["1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH"][i], 13, GOLD);
    label(tx + 94, y + 8, name, 12, PALE);
    label(tx + 94, y + 22, kart, 9, MUTED);
    label(tx + 724, y + 7, time, 12, PALE, "right");
    label(tx + 724, y + 23, best, 8, MUTED, "right");
  });

  const stx = bx, sty = by + 414;
  panel(stx, sty, BLOCK, 62, [0.04, 0.065, 0.11], 0.96);
  label(stx + BLOCK / 2, sty + 12, "TOP SPEED  188 KM/H       DRIFTING  22.4S       HITS TAKEN  3",
    12, PALE, "center");
  label(stx + BLOCK / 2, sty + 38, "L1 34.02     L2 33.46     L3 36.73", 10, MUTED, "center");
  label(W / 2, sty + 78, "+49 RACE TOKENS   /   GARAGE TOTAL: 289", 12, LIME, "center");

  const by2 = sty + 106;
  slice(tex.btn, Math.round(W / 2 - 132 - 120), by2, 240, 44, [0.20, 0.32, 0.46], 1);
  label(Math.round(W / 2 - 132), by2 + 15, "RACE AGAIN", 15, GOLD, "center");
  slice(tex.btn, Math.round(W / 2 + 132 - 120), by2, 240, 44, [0.13, 0.17, 0.25], 1);
  label(Math.round(W / 2 + 132), by2 + 15, "MAIN MENU", 15, MUTED, "center");
}

// ---- the settings screen, on demand: SCREEN=settings -------------------------
//
// Parsed from SETTING_GROUPS, so the rows, their explanations and the pickers
// are the ones the game builds. The layout maths is BuildSettingGroup's.
if (process.env.SCREEN === "settings") {
  const src = MENU_SRC;
  const groupsBlock = src.slice(src.indexOf("local SETTING_GROUPS = {"));
  const body = groupsBlock.slice(0, groupsBlock.indexOf("\n}\n"));
  const groups = [];
  for (const chunk of body.split(/\n  \{\n/).slice(1)) {
    const title = (chunk.match(/title = "([^"]+)"/) || [])[1];
    if (!title) continue;
    const column = +((chunk.match(/column = (\d)/) || [])[1] || 1);
    const rows = [];
    for (const rowChunk of chunk.split(/\{ key = "/).slice(1)) {
      const name = (rowChunk.match(/name = "([^"]+)"/) || [])[1] || "";
      const blurb = (rowChunk.match(/blurb = "([^"]+)"/) || [])[1] || "";
      const labels = [...rowChunk.matchAll(/label = "([^"]+)"/g)].map((m) => m[1]);
      rows.push({ name, blurb, labels });
    }
    groups.push({ title, column, rows });
  }
  const g = (re, d) => { const m = src.match(re); return m ? +m[1] : d; };
  const ROW_H = g(/local ROW_H, GROUP_GAP, COLUMN_W = (\d+)/, 44);
  const GROUP_GAP = g(/local ROW_H, GROUP_GAP, COLUMN_W = \d+, (\d+)/, 18);
  const COLUMN_W = g(/local ROW_H, GROUP_GAP, COLUMN_W = \d+, \d+, (\d+)/, 434);
  if (!groups.length) throw new Error("preview-ui: could not parse SETTING_GROUPS");

  for (let i = 0; i < W * H; i++) {
    fb[i * 3] = 0.030; fb[i * 3 + 1] = 0.040; fb[i * 3 + 2] = 0.070;
  }
  panel(OX, OY - 40, CW, CH, [0.045, 0.075, 0.125], 0.97);
  label(OX + CW / 2, OY - 18, "SETTINGS", 20, GOLD, "center");
  slice(tex.btn, OX + 25, OY - 20, 120, 32, [0.18, 0.28, 0.42], 1);
  label(OX + 85, OY - 10, "BACK", 12, GOLD, "center");
  slice(tex.btn, OX + CW - 25 - 180, OY - 20, 180, 30, [0.13, 0.17, 0.25], 1);
  label(OX + CW - 115, OY - 11, "RESTORE DEFAULTS", 11, MUTED, "center");

  const leftX = OX + 34, rightX = OX + 34 + COLUMN_W + 30;
  // BuildSettingGroup stacks from -52 inside the page and returns the height it
  // used; these two accumulate it exactly the same way.
  const top = OY - 40 + 62;
  const yTop = [top, top];
  for (const group of groups) {
    const col = group.column - 1;
    const x = col === 0 ? leftX : rightX;
    const y = yTop[col];
    label(x + 2, y, group.title, 11, GOLD);
    blitUV(tex.hairline, x, y + 16, COLUMN_W, 2, 0, 1, 0, 1, [1, .78, .30], 0.35);
    group.rows.forEach((row, index) => {
      const rowTop = y + 24 + index * ROW_H;
      label(x + 2, rowTop + 6, row.name, 13, PALE);
      // Left-aligned, as the game sets it -- centring here would hide how much
      // room a long explanation actually takes on the left of the column.
      label(x + 2, rowTop + 27, row.blurb, 9, [.50, .56, .66]);
      // The control: a segmented picker, or a stepper.
      const cw = 168, cx = x + COLUMN_W - cw, cy = rowTop + 4;
      if (row.labels.length) {
        const gap = 4, cell = (cw - gap * (row.labels.length - 1)) / row.labels.length;
        row.labels.forEach((lab, k) => {
          const on = k === row.labels.length - 1;
          slice(tex.btn, cx + k * (cell + gap), cy, cell, 22,
            on ? [0.55, 0.42, 0.10] : [0.07, 0.11, 0.18], 1);
          label(cx + k * (cell + gap) + cell / 2, cy + 7, lab, 9,
            on ? [1, 0.94, 0.72] : [0.52, 0.58, 0.68], "center");
        });
      } else {
        // ARROWS, not the characters "<" and ">" -- UI:NewStepper draws
        // chevron.tga flipped through its texcoords, so drawing letters here
        // was a different shape from the one that ships, and made the sheet
        // useless for judging the control it is supposed to be showing.
        slice(tex.btn, cx, cy, 22, 22, [0.18, 0.28, 0.42], 1);
        blitUV(tex.chevron, cx + 7, cy + 6, 7, 10, 1, 0, 0, 1, GOLD, 1);
        slice(tex.btn, cx + cw - 22, cy, 22, 22, [0.18, 0.28, 0.42], 1);
        blitUV(tex.chevron, cx + cw - 15, cy + 6, 7, 10, 0, 1, 0, 1, GOLD, 1);
        slice(tex.btn, cx + (cw - (cw - 52)) / 2, cy, cw - 52, 22, [0.07, 0.11, 0.18], 1);
        label(cx + cw / 2, cy + 7, "100%", 9, [1, 0.94, 0.72], "center");
      }
    });
    yTop[col] = y + 24 + group.rows.length * ROW_H + GROUP_GAP;
  }
  const used = Math.max(yTop[0], yTop[1]) - (OY - 40);
  blitUV(tex.hairline, OX + 34, OY - 40 + CH - 52, CW - 68, 2, 0, 1, 0, 1, [.38, .65, .92], 0.26);
  label(OX + CW / 2, OY - 40 + CH - 42,
    "W OR UP ACCELERATE     A D STEER     SPACE HOP AND DRIFT     SHIFT ITEM     ESC PAUSE",
    10, MUTED, "center");
  // The panel's own height less the footer band, not a number typed here: the
  // limit has to move when the panel does.
  const room = CH - 62;
  if (used > room) {
    throw new Error("preview-ui: settings overflows by " + Math.ceil(used - room) + "px");
  }
}

// ---- write ------------------------------------------------------------------
const crcTable = [];
for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crcTable[n] = c >>> 0; }
function chunk(type, data) {
  const b = Buffer.alloc(8 + data.length + 4);
  b.writeUInt32BE(data.length, 0); b.write(type, 4); data.copy(b, 8);
  let c = 0xffffffff;
  for (let i = 4; i < 8 + data.length; i++) c = crcTable[(c ^ b[i]) & 255] ^ (c >>> 8);
  b.writeUInt32BE((c ^ 0xffffffff) >>> 0, 8 + data.length);
  return b;
}
const raw = Buffer.alloc(H * (W * 3 + 1));
for (let y = 0; y < H; y++) {
  raw[y * (W * 3 + 1)] = 0;
  for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 3, o = y * (W * 3 + 1) + 1 + x * 3;
    for (let k = 0; k < 3; k++) raw[o + k] = Math.round(Math.max(0, Math.min(1, fb[i + k])) * 255);
  }
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
fs.writeFileSync(OUT, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
console.log("rendered", OUT);
