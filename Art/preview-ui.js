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
const W = +(process.env.W || 900), H = +(process.env.H || 560);

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
function label(x, y, s, size, colour, align) {
  const wpx = textWidth(s, size);
  const sx = align === "center" ? Math.round(x - wpx / 2)
    : (align === "right" ? Math.round(x - wpx) : x);
  drawText((px, py, r, g, b, a) => blend(px, py, r, g, b, a), s, sx, y, size, colour, 1);
}

// ---- the real home screen, parsed from UI/MainMenu.lua ---------------------
//
// Not a mock. The rows, their notes and every offset come out of the addon, so
// this cannot show a menu the game does not draw -- which is the whole reason
// the scene preview is trusted and a hand-built one would not be.
const MENU_SRC = fs.readFileSync(path.join(__dirname, "..", "UI", "MainMenu.lua"), "utf8");
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
const PALE = [0.86, 0.90, 1.0], LIT = [1, 0.95, 0.80];
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

// The menu is authored at 960x520 inside a 1120x790 stage; this sheet is the
// content panel alone, at 1:1, which is what there is to judge.
const CW = home.contentW, CH = home.contentH;
const OX = Math.round((W - CW) / 2), OY = Math.round((H - CH) / 2);
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
