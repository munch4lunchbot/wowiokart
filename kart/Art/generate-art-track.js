// Track furniture, Mario Kart style: the floating item cube and the dash panel.
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

// ---- item cube: translucent shell, bright edges, floating "?" ----
// Drawn as an isometric cube so it reads as a solid object at any distance.
writeTGA("itembox.tga", 128, 128, (x, y, w, h) => {
  const u = (x + .5) / w, v = (y + .5) / h;
  const cx = 0.5, cy = 0.52, R = 0.40;
  // Isometric hexagon silhouette.
  const dx = Math.abs(u - cx), dy = v - cy;
  const hex = dx / R + Math.abs(dy) / (R * 1.12);
  if (hex > 1.0) return [0, 0, 0, 0];

  // Three visible faces: top, left, right.
  const topFace = dy < -R * 0.30 + dx * 0.62;
  const leftFace = !topFace && u < cx;
  let tone = topFace ? 1.0 : (leftFace ? 0.68 : 0.84);
  // Rim brightening near the silhouette edge.
  const rim = Math.pow(hex, 6) * 0.6;
  tone = Math.min(1.4, tone + rim);

  let col = [0.98 * tone, 0.80 * tone, 0.22 * tone];
  // Edge wires.
  if (Math.abs(hex - 1.0) < 0.055) col = [1.0, 0.96, 0.72];
  if (Math.abs(dy + R * 0.30 - dx * 0.62) < 0.03 && !topFace) col = [1.0, 0.93, 0.62];

  // "?" glyph on the front faces.
  if (!topFace) {
    const gx = (u - cx) / 0.30, gy = (v - cy - 0.04) / 0.30;
    const ring = Math.sqrt(gx * gx + (gy + 0.42) * (gy + 0.42));
    const onHook = ring > 0.34 && ring < 0.62 && gy < 0.05 && !(gx < 0 && gy > -0.30);
    const stem = Math.abs(gx) < 0.13 && gy > 0.02 && gy < 0.34;
    const dot = Math.abs(gx) < 0.15 && gy > 0.50 && gy < 0.78;
    if (onHook || stem || dot) col = [0.16, 0.10, 0.04];
  }
  // Slightly translucent so it reads as a shell, not a brick.
  return [col[0], col[1], col[2], 0.92];
});

// ---- dash panel: chevrons pointing up the road ----
writeTGA("dashpad.tga", 128, 128, (x, y, w, h) => {
  const u = (x + .5) / w, v = (y + .5) / h;
  // Base plate.
  if (u < 0.04 || u > 0.96 || v < 0.02 || v > 0.98) return [0, 0, 0, 0];
  let col = [0.10, 0.05, 0.02], a = 0.85;
  // Three chevrons, apex toward the top (up-road).
  for (let k = 0; k < 3; k++) {
    const base = 0.86 - k * 0.30;
    const dv = base - v;
    if (dv < 0 || dv > 0.20) continue;
    const spread = dv * 1.5;
    if (Math.abs(u - 0.5) < spread + 0.10 && Math.abs(u - 0.5) > spread - 0.10) {
      const hot = 1 - k * 0.22;
      col = [1.0 * hot, 0.72 * hot, 0.12 * hot];
      a = 1;
    }
  }
  return [col[0], col[1], col[2], a];
});
