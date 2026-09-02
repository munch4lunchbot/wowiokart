// Port of Builder:Compile + Builder:AnchorBranch, run over the authored tracks
// so the branch geometry can be checked before it ships.
const fs = require("fs");
const SRC = fs.readFileSync("C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/kart/Data/Tracks.lua", "utf8");
const STEP = 2, CURVE_GAIN = 0.0021, GRADE_GAIN = 0.022;

function compile(track) {
  const layout = track.layout;
  let authored = 0;
  for (const p of layout) authored += p.len;
  const scale = track.length / authored;
  const samples = Math.floor(track.length / STEP) + 1;
  const centre = [], height = [], width = [];
  let heading = 0, x = 0, h = 0, pieceIndex = 0, pieceLeft = layout[0].len * scale;
  for (let i = 0; i < samples; i++) {
    const piece = layout[pieceIndex];
    heading += (piece.curve || 0) * CURVE_GAIN * STEP;
    x += heading * STEP;
    h += (piece.grade || 0) * GRADE_GAIN * STEP;
    centre[i] = x; height[i] = h; width[i] = piece.width || 1;
    pieceLeft -= STEP;
    while (pieceLeft <= 0 && pieceIndex < layout.length - 1) {
      pieceIndex++; pieceLeft += layout[pieceIndex].len * scale;
    }
  }
  const dX = centre[samples - 1] - centre[0], dH = height[samples - 1] - height[0];
  for (let i = 0; i < samples; i++) {
    const t = i / (samples - 1);
    centre[i] -= dX * t; height[i] -= dH * t;
  }
  let low = Infinity, high = -Infinity;
  for (let i = 0; i < samples; i++) { low = Math.min(low, centre[i]); high = Math.max(high, centre[i]); }
  const mid = (low + high) / 2;
  let peak = 0;
  for (let i = 0; i < samples; i++) { centre[i] -= mid; peak = Math.max(peak, Math.abs(centre[i])); }
  if (peak > 0) { const f = (track.sweep || 2.6) / peak; for (let i = 0; i < samples; i++) centre[i] *= f; }
  return { centre, height, width, samples, length: track.length };
}

const at = (c, len, d) => {
  const i = Math.max(0, Math.min(c.samples - 1, Math.round(((d % len) + len) % len / STEP)));
  return i;
};

// Mirrors Builder:AnchorBranch. Both ends must land on the main line in
// ABSOLUTE terms, not merely span the right relative offset -- a branch pinned
// to zero has the right shape and still snaps the world the instant you join
// it, because the main line at that point is somewhere else entirely.
function anchor(main, branch, entry, exit) {
  const entryC = main.centre[at(main, main.length, entry)];
  const entryH = main.height[at(main, main.length, entry)];
  const exitC = main.centre[at(main, main.length, exit)];
  const exitH = main.height[at(main, main.length, exit)];
  const wantC = exitC - entryC, wantH = exitH - entryH;
  const n = branch.samples;
  const haveC = branch.centre[n - 1] - branch.centre[0];
  const haveH = branch.height[n - 1] - branch.height[0];
  const bc = branch.centre[0], bh = branch.height[0];
  // OLDANCHOR=1 restores the origin-pinned version, so this harness can be
  // shown to actually catch the teleport rather than merely agreeing with the
  // fix. It must FAIL both junction checks.
  const originC = process.env.OLDANCHOR ? 0 : entryC;
  const originH = process.env.OLDANCHOR ? 0 : entryH;
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    branch.centre[i] = originC + (branch.centre[i] - bc) + (wantC - haveC) * t;
    branch.height[i] = originH + (branch.height[i] - bh) + (wantH - haveH) * t;
  }
  return { wantC, wantH, entryC, entryH, exitC, exitH };
}

// Pull the three tracks and their branches straight out of the Lua source.
function grabTrack(id) {
  const start = SRC.indexOf(`id = "${id}"`);
  const next = SRC.indexOf("\n  {", start);
  const body = SRC.slice(start, next === -1 ? SRC.length : next);
  const length = +body.match(/length = (\d+), laps/)[1];
  const sweep = +(body.match(/sweep = ([\d.]+)/) || [, 2.6])[1];
  const layoutSrc = body.slice(body.indexOf("layout = {"), body.indexOf("hazards = {"));
  const layout = [...layoutSrc.matchAll(/\{ len = ([\d.]+),([^}]*)\}/g)].map(m => ({
    len: +m[1],
    curve: +(m[2].match(/curve = (-?[\d.]+)/) || [, 0])[1],
    grade: +(m[2].match(/grade = (-?[\d.]+)/) || [, 0])[1],
    width: +(m[2].match(/width = ([\d.]+)/) || [, 1])[1],
  }));
  const bIdx = body.indexOf("branches = {");
  let branch = null;
  if (bIdx !== -1) {
    const b = body.slice(bIdx);
    const bLayout = b.slice(b.indexOf("layout = {"));
    branch = {
      id: b.match(/id = "(\w+)"/)[1],
      name: b.match(/name = "([^"]+)"/)[1],
      side: +b.match(/side = (-?\d)/)[1],
      from: +b.match(/from = ([\d.]+)/)[1],
      to: +b.match(/to = ([\d.]+)/)[1],
      length: +b.match(/length = (\d+)/)[1],
      sweep: +b.match(/sweep = ([\d.]+)/)[1],
      layout: [...bLayout.matchAll(/\{ len = ([\d.]+),([^}]*)\}/g)].map(m => ({
        len: +m[1],
        curve: +(m[2].match(/curve = (-?[\d.]+)/) || [, 0])[1],
        grade: +(m[2].match(/grade = (-?[\d.]+)/) || [, 0])[1],
        width: +(m[2].match(/width = ([\d.]+)/) || [, 1])[1],
      })),
    };
  }
  return { id, length, sweep, layout, branch };
}

const AVG_SPEED = 65; // metres/second, from the 40s lap target
let fail = 0;
for (const id of ["oribos", "elwynn", "durotar"]) {
  const t = grabTrack(id);
  const main = compile(t);
  console.log(`\n${id}  (${t.length}m main lap)`);
  if (!t.branch) { console.log("  no branch"); continue; }
  const b = t.branch;
  const entry = b.from * t.length, exit = b.to * t.length;
  const span = ((exit - entry) % t.length + t.length) % t.length;
  const authored = b.layout.reduce((a, p) => a + p.len, 0);
  const bc = compile(b);
  const want = anchor(main, bc, entry, exit);

  // Deviation from the straight chord between the two ends. Raw peak is not the
  // measure: after anchoring it necessarily includes however far apart the entry
  // and exit are on the main line, which is geometry, not shape.
  let peak = 0, bow = 0;
  const c0 = bc.centre[0], c1 = bc.centre[bc.samples - 1];
  for (let i = 0; i < bc.samples; i++) {
    peak = Math.max(peak, Math.abs(bc.centre[i]));
    const chord = c0 + (c1 - c0) * (i / (bc.samples - 1));
    bow = Math.max(bow, Math.abs(bc.centre[i] - chord));
  }
  // Continuity at BOTH ends, in absolute terms. The entry used to go unchecked,
  // which is precisely where the branch was pinned to the wrong origin and the
  // fork "teleported" you the moment you took it.
  const last = bc.samples - 1;
  const inC = Math.abs(bc.centre[0] - want.entryC);
  const inH = Math.abs(bc.height[0] - want.entryH);
  const outC = Math.abs(bc.centre[last] - want.exitC);
  const outH = Math.abs(bc.height[last] - want.exitH);
  const saved = span - b.length;

  console.log(`  ${b.name}: entry ${entry.toFixed(0)}m -> exit ${exit.toFixed(0)}m, replaces ${span.toFixed(0)}m`);
  console.log(`  branch road ${b.length}m (layout sums ${authored}m, scaled x${(b.length / authored).toFixed(2)})`);
  console.log(`  saves ${saved.toFixed(0)}m  =  ${(saved / AVG_SPEED).toFixed(2)}s at racing pace`);
  console.log(`  side ${b.side < 0 ? "LEFT" : "RIGHT"}, peak ${peak.toFixed(2)}, bow off the chord ${bow.toFixed(2)}`);
  console.log(`  junction error  entry ${inC.toFixed(4)}x / ${inH.toFixed(4)}h`
    + `   exit ${outC.toFixed(4)}x / ${outH.toFixed(4)}h  (any of these is a teleport)`);

  const checks = [
    [saved > 20, `saves ${saved.toFixed(0)}m -- must be a worthwhile shortcut`],
    [saved < span * 0.45, `saving is not absurd (${(saved / span * 100).toFixed(0)}% of the span)`],
    [inC < 0.001 && inH < 0.001, "meets the main line where it leaves it"],
    [outC < 0.001 && outH < 0.001, "meets the main line where it rejoins"],
    [bow > 0.35, `has real shape, not a diagonal cut (bow ${bow.toFixed(2)})`],
    [peak < 8, "stays within the rendered world"],
    [span > b.length, "branch is physically shorter than what it replaces"],
    [b.from < b.to, "entry comes before exit"],
  ];
  for (const [pass, what] of checks) {
    console.log(`   ${pass ? "ok  " : "FAIL"} ${what}`);
    if (!pass) fail++;
  }
}
console.log(fail ? `\n${fail} FAILURES` : "\nall branch geometry checks passed");
