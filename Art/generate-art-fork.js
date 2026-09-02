// Fork signage: the arrow board planted at a branch entry.
//
// Tinted white at runtime, so the art carries shape and shading only. The
// renderer flips it by choosing which way the arrow points at draw time, which
// is why two files are generated rather than one rotated texture -- WoW's
// SetRotation turns the UVs inside a fixed rectangle, not the quad itself.
const fs = require("fs");
const path = require("path");

const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });

function writeTGA(name, w, h, fn) {
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
      body[i++] = Math.max(0, Math.min(255, Math.round(b * 255)));
      body[i++] = Math.max(0, Math.min(255, Math.round(g * 255)));
      body[i++] = Math.max(0, Math.min(255, Math.round(r * 255)));
      body[i++] = Math.max(0, Math.min(255, Math.round(a * 255)));
    }
  }
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([header, body]));
  console.log(name, w + "x" + h);
}

const smooth = (e0, e1, v) => {
  const t = Math.max(0, Math.min(1, (v - e0) / (e1 - e0)));
  return t * t * (3 - 2 * t);
};

// A signpost: board on top, narrow pole below, with a chevron cut into the
// board. Antialiased throughout -- a hard-edged sign shimmers badly once the
// projection scales it down toward the horizon.
function sign(flip) {
  return (x, y, w, h) => {
    const u = x / (w - 1);
    const v = y / (h - 1);
    const boardBottom = 0.62;

    // The pole.
    if (v > boardBottom) {
      const pole = 1 - smooth(0.028, 0.055, Math.abs(u - 0.5));
      const shade = 0.34 + 0.16 * (1 - Math.abs(u - 0.5) / 0.055);
      return [shade, shade * 0.95, shade * 0.9, pole];
    }

    // The board, with rounded corners.
    const bx = Math.abs(u - 0.5) / 0.46;
    const by = Math.abs(v - boardBottom * 0.5) / (boardBottom * 0.46);
    const corner = Math.pow(Math.pow(bx, 6) + Math.pow(by, 6), 1 / 6);
    const board = 1 - smooth(0.94, 1.0, corner);
    if (board <= 0) return [0, 0, 0, 0];

    // Chevron. Two stacked arrowheads pointing along the branch direction.
    const cu = flip ? 1 - u : u;
    let arrow = 0;
    for (const centre of [0.36, 0.62]) {
      // Distance to a "<" shape: the arm bends at the vertical midline.
      const dy = Math.abs(v - boardBottom * 0.5) / (boardBottom * 0.5);
      const armX = centre - 0.16 * (1 - dy);
      arrow = Math.max(arrow, 1 - smooth(0.035, 0.075, Math.abs(cu - armX)));
    }

    // Border ring inside the board edge.
    const border = smooth(0.80, 0.88, corner) * (1 - smooth(0.94, 1.0, corner));

    const lit = 0.55 + 0.45 * (1 - v / boardBottom);
    if (arrow > 0.02) {
      // Arrow is the bright element; it is what reads at distance.
      return [1.0 * lit, 1.0 * lit, 1.0 * lit, board * (0.55 + 0.45 * arrow)];
    }
    const base = 0.30 + 0.22 * border;
    return [base * lit, base * lit * 1.05, base * lit, board];
  };
}

writeTGA("forkleft.tga", 64, 96, sign(false));
writeTGA("forkright.tga", 64, 96, sign(true));
