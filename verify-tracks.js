// Port of Builder:Compile + Builder:AnchorBranch, run over the authored tracks
// so the branch geometry can be checked before it ships.
const fs = require("fs");
const path = require("path");
const SRC = fs.readFileSync(path.join(__dirname, "Data", "Tracks.lua"), "utf8");
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

const slopeAt = (c, len, d) =>
  (c.centre[at(c, len, d + STEP)] - c.centre[at(c, len, d - STEP)]) / (2 * STEP);

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
  // TANGENTS, NOT JUST ENDPOINTS. Matching only position leaves the branch free
  // to set off at whatever angle its own first corner gives it, so the world
  // ROTATES the instant the physics moves you onto it -- pick right at a fork
  // whose first piece bends left and the game turns you left. A cubic
  // correction pins value and slope at both ends instead of a straight line
  // pinning value alone. FLATANCHOR=1 restores the linear version so this
  // harness can be shown to catch the kink rather than merely agree with it.
  const slope = (c, len, d) =>
    (c.centre[at(c, len, d + STEP)] - c.centre[at(c, len, d - STEP)]) / (2 * STEP);
  const grade = (c, len, d) =>
    (c.height[at(c, len, d + STEP)] - c.height[at(c, len, d - STEP)]) / (2 * STEP);
  const span = Math.max(1, (n - 1) * STEP);
  const flat = !!process.env.FLATANCHOR;
  const cM0 = flat ? 0 : (slope(main, main.length, entry) - (branch.centre[1] - branch.centre[0]) / STEP) * span;
  const cM1 = flat ? 0 : (slope(main, main.length, exit) - (branch.centre[n - 1] - branch.centre[n - 2]) / STEP) * span;
  const hM0 = flat ? 0 : (grade(main, main.length, entry) - (branch.height[1] - branch.height[0]) / STEP) * span;
  const hM1 = flat ? 0 : (grade(main, main.length, exit) - (branch.height[n - 1] - branch.height[n - 2]) / STEP) * span;
  const hermite = (t, p1, m0, m1) => {
    const t2 = t * t, t3 = t2 * t;
    return (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * p1 + (t3 - t2) * m1;
  };
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    branch.centre[i] = originC + (branch.centre[i] - bc) + hermite(t, wantC - haveC, cM0, cM1);
    branch.height[i] = originH + (branch.height[i] - bh) + hermite(t, wantH - haveH, hM0, hM1);
  }
  return { wantC, wantH, entryC, entryH, exitC, exitH,
    kinkIn: Math.abs(slope(main, main.length, entry) - (branch.centre[1] - branch.centre[0]) / STEP),
    kinkOut: Math.abs(slope(main, main.length, exit) - (branch.centre[n - 1] - branch.centre[n - 2]) / STEP) };
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

// Every track in the file, not a hand-written list. The old form named three
// ids -- which happened to be exactly the three that had branches -- so adding
// a branch to a fourth track silently went unchecked, and the geometry bugs
// this harness exists to catch could ship freely on any track added later.
const ALL_IDS = [...SRC.matchAll(/\n  \{\n    id = "(\w+)"/g)].map(m => m[1]);

// A track that ADVERTISES a shortcut must actually have one.
//
// RaceUI draws "SHORTCUT: <text>" on the HUD from `track.shortcut`, and five of
// the eight tracks carried that text with no `branches` table behind it -- the
// game told the player about a route through the Deadmines side shaft, a portal
// on Netherstorm and a frozen tunnel on Ironforge, none of which existed. That
// is not a missing feature so much as the HUD lying, and it is exactly the kind
// of thing that is invisible in review and obvious in play.
const advertised = [];
for (const id of ALL_IDS) {
  const start = SRC.indexOf(`id = "${id}"`);
  const next = SRC.indexOf("\n  {", start);
  const body = SRC.slice(start, next === -1 ? SRC.length : next);
  if (/shortcut = "/.test(body) && !/branches = \{/.test(body)) advertised.push(id);
}
if (advertised.length) {
  console.log("\nFAIL  these tracks show a SHORTCUT on the HUD but have no branch to take:");
  for (const id of advertised) console.log("        " + id);
  fail += advertised.length;
}

for (const id of ALL_IDS) {
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
  // The two ends re-differenced AFTER anchoring: how far the branch's own
  // heading is from the main line's where they meet. Position continuity says
  // nothing about this, and a kink here is a rotation of the whole world on the
  // frame the physics moves you across.
  const kinkIn = Math.abs(slopeAt(main, main.length, entry) - (bc.centre[1] - bc.centre[0]) / STEP);
  const kinkOut = Math.abs(slopeAt(main, main.length, exit) - (bc.centre[last] - bc.centre[last - 1]) / STEP);
  console.log(`  junction error  entry ${inC.toFixed(4)}x / ${inH.toFixed(4)}h`
    + `   exit ${outC.toFixed(4)}x / ${outH.toFixed(4)}h  (any of these is a teleport)`);
  console.log(`  junction kink   entry ${kinkIn.toFixed(4)}   exit ${kinkOut.toFixed(4)}`
    + `  (heading mismatch; a kink turns the world for you)`);

  const checks = [
    [saved > 20, `saves ${saved.toFixed(0)}m -- must be a worthwhile shortcut`],
    [saved < span * 0.45, `saving is not absurd (${(saved / span * 100).toFixed(0)}% of the span)`],
    [inC < 0.001 && inH < 0.001, "meets the main line where it leaves it"],
    [outC < 0.001 && outH < 0.001, "meets the main line where it rejoins"],
    [bow > 0.35, `has real shape, not a diagonal cut (bow ${bow.toFixed(2)})`],
    // 0.004 is a residual, not a tolerance for sloppiness. The correction is
    // exact in continuous terms and sampled every 2m, so a one-sided difference
    // at the very last sample keeps an O(STEP x curvature) remainder. What it
    // means on screen: 0.004 of slope over the 120m detail band is half a metre
    // of drift on an 18m road. The linear anchor it replaced ran to 0.12.
    [kinkIn < 0.004, `leaves the main line pointing the same way (kink ${kinkIn.toFixed(4)})`],
    [kinkOut < 0.004, `rejoins it pointing the same way (kink ${kinkOut.toFixed(4)})`],
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
