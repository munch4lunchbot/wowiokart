// Power-up art. Readable at 24px on a moving road, which means bold silhouette,
// dark outline, flat colour. Shells are white-cored so a vertex tint makes the
// green and red variants from one texture.
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

const S = 128;
// Painter with a baked dark outline: silhouette first, then fill inside it.
function painter() {
  const px = new Float32Array(S * S * 4);
  return {
    px,
    put(x, y, c, a = 1) {
      if (x < 0 || y < 0 || x >= S || y >= S || a <= 0) return;
      const i = (y * S + x) * 4, m = Math.min(1, a);
      px[i] = px[i] * (1 - m) + c[0] * m;
      px[i + 1] = px[i + 1] * (1 - m) + c[1] * m;
      px[i + 2] = px[i + 2] * (1 - m) + c[2] * m;
      px[i + 3] = Math.max(px[i + 3], m);
    },
    read: (x, y) => {
      const i = (y * S + x) * 4;
      return [px[i], px[i + 1], px[i + 2], px[i + 3]];
    },
  };
}
// Grow a dark border around whatever is already drawn.
function outline(p, width, col) {
  const src = Float32Array.from(p.px);
  const alphaAt = (x, y) => (x < 0 || y < 0 || x >= S || y >= S) ? 0 : src[(y * S + x) * 4 + 3];
  const out = painter();
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (alphaAt(x, y) > 0.5) continue;
    let near = 0;
    for (let dy = -width; dy <= width && !near; dy++)
      for (let dx = -width; dx <= width; dx++)
        if (dx * dx + dy * dy <= width * width && alphaAt(x + dx, y + dy) > 0.5) { near = 1; break; }
    if (near) out.put(x, y, col, 1);
  }
  // Outline underneath the original.
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const o = out.read(x, y), s = [src[(y * S + x) * 4], src[(y * S + x) * 4 + 1], src[(y * S + x) * 4 + 2], src[(y * S + x) * 4 + 3]];
    const i = (y * S + x) * 4;
    if (s[3] > 0) { p.px[i] = s[0]; p.px[i + 1] = s[1]; p.px[i + 2] = s[2]; p.px[i + 3] = s[3]; }
    else if (o[3] > 0) { p.px[i] = o[0]; p.px[i + 1] = o[1]; p.px[i + 2] = o[2]; p.px[i + 3] = o[3]; }
  }
}
function emit(name, draw) {
  const p = painter();
  draw(p);
  outline(p, 4, [0.05, 0.04, 0.07]);
  writeTGA(name, S, S, (x, y) => p.read(x, y));
}
const dist = (x, y, cx, cy, sx = 1, sy = 1) => Math.sqrt(((x - cx) / sx) ** 2 + ((y - cy) / sy) ** 2);

// ---- shell: white core so a tint makes green or red ----
emit("shell.tga", p => {
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const dTop = dist(x, y, 64, 70, 1, 0.92);
    if (dTop < 42 && y < 82) {
      // Domed shell: bright at the top-left, darker at the rim.
      const lit = 1 - dist(x, y, 48, 50) / 90;
      let c = [0.95 * lit + 0.12, 0.95 * lit + 0.12, 0.95 * lit + 0.14];
      // Hexagon plates.
      const hx = Math.round((x - 64) / 17), hy = Math.round((y - 60) / 15);
      const cx = 64 + hx * 17 + (hy % 2 ? 8 : 0), cy = 60 + hy * 15;
      if (dist(x, y, cx, cy) > 7.4) c = c.map(v => v * 0.72);
      p.put(x, y, c, 1);
    }
    // Cream underbelly.
    if (y >= 76 && dist(x, y, 64, 78, 1, 0.5) < 40) {
      const lit = 1 - (y - 76) / 60;
      p.put(x, y, [0.99, 0.94 * lit + 0.5, 0.72 * lit + 0.35], 1);
    }
  }
});

// ---- banana ----
emit("banana.tga", p => {
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    // Crescent: between two offset circles.
    const outer = dist(x, y, 64, 46, 1, 1) ;
    const inner = dist(x, y, 64, 20, 1, 1);
    if (outer < 46 && inner > 40 && y > 34) {
      const lit = 1 - dist(x, y, 44, 60) / 130;
      p.put(x, y, [1.0 * lit + 0.15, 0.85 * lit + 0.12, 0.18 * lit], 1);
    }
  }
  // Stem.
  for (let y = 30; y < 52; y++) for (let x = 96; x < 112; x++) {
    if (dist(x, y, 104, 42, 1, 1.4) < 9) p.put(x, y, [0.35, 0.24, 0.10], 1);
  }
});

// ---- mushroom ----
emit("mushroom.tga", p => {
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (y < 74 && dist(x, y, 64, 74, 1, 1.05) < 46) {
      const lit = 1 - dist(x, y, 46, 44) / 110;
      let c = [0.95 * lit + 0.2, 0.22 * lit, 0.20 * lit];
      for (const [sx, sy, r] of [[42, 46, 13], [88, 50, 11], [64, 32, 10]]) {
        if (dist(x, y, sx, sy) < r) c = [0.99, 0.96, 0.90];
      }
      p.put(x, y, c, 1);
    }
    if (y >= 70 && y < 110 && dist(x, y, 64, 88, 1, 1.6) < 27) {
      const lit = 1 - dist(x, y, 52, 90) / 90;
      p.put(x, y, [0.98 * lit + 0.15, 0.92 * lit + 0.12, 0.80 * lit + 0.1], 1);
    }
  }
});

// ---- star ----
emit("star.tga", p => {
  const pts = 5, R = 54, r = 23;
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const dx = x - 64, dy = y - 66;
    let a = Math.atan2(dy, dx) + Math.PI / 2;
    if (a < 0) a += Math.PI * 2;
    const seg = (a % (Math.PI * 2 / pts)) / (Math.PI * 2 / pts);
    const t = seg < 0.5 ? seg * 2 : (1 - seg) * 2;
    const edge = r + (R - r) * (1 - t);
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d < edge) {
      const lit = 1 - d / 100;
      p.put(x, y, [1.0, 0.88 * lit + 0.22, 0.25 * lit + 0.05], 1);
    }
  }
});

// ---- lightning bolt ----
emit("bolt.tga", p => {
  const poly = [[74, 8], [34, 68], [58, 68], [44, 120], [96, 52], [68, 52], [92, 8]];
  const inside = (x, y) => {
    let c = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const [xi, yi] = poly[i], [xj, yj] = poly[j];
      if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
    }
    return c;
  };
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (inside(x, y)) {
      const lit = 1 - dist(x, y, 50, 40) / 140;
      p.put(x, y, [1.0, 0.94 * lit + 0.2, 0.35 * lit], 1);
    }
  }
});

// ---- bomb ----
emit("bomb.tga", p => {
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (dist(x, y, 62, 78, 1, 1) < 40) {
      const lit = 1 - dist(x, y, 46, 60) / 120;
      p.put(x, y, [0.20 * lit + 0.06, 0.21 * lit + 0.06, 0.26 * lit + 0.08], 1);
    }
    // Fuse.
    if (dist(x, y, 82 + (y - 30) * 0.25, y, 1, 1) < 5 && y > 22 && y < 44) p.put(x, y, [0.55, 0.42, 0.22], 1);
  }
  // Spark at the fuse tip.
  for (let y = 8; y < 30; y++) for (let x = 74; x < 100; x++) {
    const d = dist(x, y, 86, 18);
    if (d < 11) p.put(x, y, [1.0, 0.85 - d * 0.03, 0.25], 1);
  }
});
