// A 5x7 bitmap font, so the offline preview can render the HUD's actual TEXT.
//
// The preview used to draw the HUD as four unlabelled grey rectangles, which is
// enough to check that panels do not overlap and nothing else. Every real HUD
// question -- does "SHORTCUT: Blink through a portal at maximum speed" fit, does
// the lap number collide with the pips, is 58pt too big for the corner -- is a
// question about glyphs, and none of them could be asked without one.
//
// Five by seven with a one-pixel gap is the smallest grid that keeps every
// letter distinct, and it is drawn as scaled blocks, so it measures the same as
// any other font: width is proportional to size and the layout maths is real
// even though the shapes are not Blizzard's.
const G = {};
function glyph(ch, ...rows) { G[ch] = rows.map(r => parseInt(r, 2)); }
glyph(" ", "00000","00000","00000","00000","00000","00000","00000");
glyph("0", "01110","10001","10011","10101","11001","10001","01110");
glyph("1", "00100","01100","00100","00100","00100","00100","01110");
glyph("2", "01110","10001","00001","00010","00100","01000","11111");
glyph("3", "11111","00010","00100","00010","00001","10001","01110");
glyph("4", "00010","00110","01010","10010","11111","00010","00010");
glyph("5", "11111","10000","11110","00001","00001","10001","01110");
glyph("6", "00110","01000","10000","11110","10001","10001","01110");
glyph("7", "11111","00001","00010","00100","01000","01000","01000");
glyph("8", "01110","10001","10001","01110","10001","10001","01110");
glyph("9", "01110","10001","10001","01111","00001","00010","01100");
glyph("A", "01110","10001","10001","11111","10001","10001","10001");
glyph("B", "11110","10001","10001","11110","10001","10001","11110");
glyph("C", "01110","10001","10000","10000","10000","10001","01110");
glyph("D", "11100","10010","10001","10001","10001","10010","11100");
glyph("E", "11111","10000","10000","11110","10000","10000","11111");
glyph("F", "11111","10000","10000","11110","10000","10000","10000");
glyph("G", "01110","10001","10000","10111","10001","10001","01111");
glyph("H", "10001","10001","10001","11111","10001","10001","10001");
glyph("I", "01110","00100","00100","00100","00100","00100","01110");
glyph("J", "00111","00010","00010","00010","00010","10010","01100");
glyph("K", "10001","10010","10100","11000","10100","10010","10001");
glyph("L", "10000","10000","10000","10000","10000","10000","11111");
glyph("M", "10001","11011","10101","10101","10001","10001","10001");
glyph("N", "10001","11001","10101","10011","10001","10001","10001");
glyph("O", "01110","10001","10001","10001","10001","10001","01110");
glyph("P", "11110","10001","10001","11110","10000","10000","10000");
glyph("Q", "01110","10001","10001","10001","10101","10010","01101");
glyph("R", "11110","10001","10001","11110","10100","10010","10001");
glyph("S", "01111","10000","10000","01110","00001","00001","11110");
glyph("T", "11111","00100","00100","00100","00100","00100","00100");
glyph("U", "10001","10001","10001","10001","10001","10001","01110");
glyph("V", "10001","10001","10001","10001","10001","01010","00100");
glyph("W", "10001","10001","10001","10101","10101","11011","10001");
glyph("X", "10001","10001","01010","00100","01010","10001","10001");
glyph("Y", "10001","10001","01010","00100","00100","00100","00100");
glyph("Z", "11111","00001","00010","00100","01000","10000","11111");
glyph(".", "00000","00000","00000","00000","00000","01100","01100");
glyph(",", "00000","00000","00000","00000","01100","01100","01000");
glyph(":", "00000","01100","01100","00000","01100","01100","00000");
glyph("/", "00001","00010","00010","00100","01000","01000","10000");
glyph("-", "00000","00000","00000","11111","00000","00000","00000");
glyph("!", "00100","00100","00100","00100","00100","00000","00100");
glyph("?", "01110","10001","00001","00110","00100","00000","00100");
glyph("%", "11001","11010","00010","00100","01000","01011","10011");
glyph("+", "00000","00100","00100","11111","00100","00100","00000");

// Calibrated against the real thing, because a mirror with the wrong metrics
// invents faults. Drawing the 5x7 cell at one pixel per point size made every
// string 1.7x too long and reported overlaps that do not exist in game.
//
// FRIZQT__.TTF at an N-point size has a cap height near 0.72N and an average
// uppercase advance near 0.62N. Seven rows of `px` must therefore come to
// 0.72N, which puts one cell pixel at N/9.7 and the 6-cell advance at 0.62N --
// so a string measured here is the length it will actually be on screen.
const CELL = 9.7;

// Measurement is continuous and drawing is not: a glyph has to land on whole
// pixels, but rounding the CELL first collapsed 11pt and 13pt onto the same
// width, which is useless in a harness whose whole job is catching an overlap.
// So strings are measured and ADVANCED at the true fractional pitch, and only
// each glyph's own block size is rounded.
const pitch = size => size / CELL;
const cell = size => Math.max(1, Math.round(size / CELL));

/** Width in pixels a string will occupy at this point size. */
function textWidth(str, size) {
  return Math.max(0, str.length * 6 * pitch(size) - pitch(size));
}

/** Height of the drawn glyph box, i.e. the font's cap height. */
function textHeight(size) { return pitch(size) * 7; }

/**
 * Draw `str` with its baseline box top-left at (x, y).
 * `put(px, py, r, g, b, a)` paints one pixel; the caller supplies it so this
 * file stays independent of the preview's framebuffer.
 */
function drawText(put, str, x, y, size, color, alpha) {
  const px = cell(size), step = 6 * pitch(size);
  let cx = x;
  for (const raw of str.toUpperCase()) {
    const rows = G[raw] || G["?"];
    const gx = Math.round(cx), gy = Math.round(y);
    for (let r = 0; r < 7; r++) {
      for (let c = 0; c < 5; c++) {
        if (!(rows[r] & (1 << (4 - c)))) continue;
        for (let dy = 0; dy < px; dy++) for (let dx = 0; dx < px; dx++)
          put(gx + c * px + dx, gy + r * px + dy, color[0], color[1], color[2], alpha);
      }
    }
    cx += step;
  }
}

module.exports = { drawText, textWidth, textHeight };
