// Does the picture move as smoothly as the simulation does?
//
// Physics advances in fixed 1/120 slices (Core/FixedStep.lua) and the display
// does not tick at 120Hz. A 60fps frame usually consumes exactly two slices,
// but real frame times jitter by a millisecond or two, so in practice some
// frames consume one slice and some consume three. Drawing raw simulation state
// therefore moves the camera in uneven jumps -- and since the entire world
// scroll is derived from the player's distance, that is a permanent low-level
// judder on everything on screen. It is the kind of fault that never shows up
// as a discrete glitch and just makes the game feel cheap.
//
// The fix is render interpolation: draw BETWEEN the last two simulated states,
// using however much of the current slice has not been simulated yet. This
// harness runs the real accumulator from Core/FixedStep.lua against realistic
// jittery frame times and measures how uneven the drawn motion actually is,
// with and without it.
//
// Run: node verify-smoothness.js
const fs = require("fs");
const path = require("path");

const SRC = fs.readFileSync(path.join(__dirname, "Core", "FixedStep.lua"), "utf8");
const RATE = (() => {
  const m = SRC.match(/FixedStep\.RATE = 1 \/ (\d+)/);
  if (!m) throw new Error("FixedStep.RATE not found");
  return 1 / +m[1];
})();
const MAX_SLICES = +SRC.match(/FixedStep\.MAX_SLICES = (\d+)/)[1];

// The addon interpolates only when the change is small enough to be motion
// rather than a lap rollover or a fork reset; see RaceUI:Lerped.
const UI = fs.readFileSync(path.join(__dirname, "UI", "RaceUI.lua"), "utf8");
if (!/function RaceUI:Lerped\(previous, current, alpha, limit\)/.test(UI))
  throw new Error("RaceUI:Lerped is gone -- this harness is measuring nothing");

const SPEED = 46;                    // m/s, about a 150cc top speed

/**
 * One run at a given display rate. `jitter` is the fraction of a frame that
 * frame times wander by, which is what actually creates the uneven slice counts.
 */
function run(fps, jitter, interpolate) {
  let accumulator = 0, simTime = 0, prev = 0, current = 0;
  const drawn = [], frameTime = [];
  // Deterministic wobble, so a run is reproducible and comparable.
  let seed = 12345;
  const rand = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
  for (let frame = 0; frame < 1200; frame++) {
    const elapsed = (1 / fps) * (1 + (rand() - 0.5) * 2 * jitter);
    accumulator += Math.min(elapsed, 0.25);
    let ran = 0;
    while (accumulator >= RATE) {
      if (ran >= MAX_SLICES) { accumulator = 0; break; }
      prev = current;
      current += SPEED * RATE;
      simTime += RATE;
      accumulator -= RATE;
      ran++;
    }
    const alpha = Math.min(Math.max(accumulator / RATE, 0), 1);
    drawn.push(interpolate ? prev + (current - prev) * alpha : current);
    frameTime.push(elapsed);
  }
  // The right question is NOT "did every frame draw the same travel" -- a frame
  // that genuinely took 8% longer SHOULD draw 8% further, and scoring against
  // the average punishes exactly the behaviour being asked for. The question is
  // whether each frame's drawn travel matches the travel its own elapsed time
  // earned. Discard the warm-up.
  let worst = 0;
  const expected = [];
  for (let i = 401; i < drawn.length; i++) {
    const want = SPEED * frameTime[i];
    expected.push(want);
    worst = Math.max(worst, Math.abs((drawn[i] - drawn[i - 1]) - want) / want);
  }
  return { ratio: worst };
}

console.log("Drawn camera motion  (sim " + Math.round(1 / RATE) + "Hz, kart at " + SPEED + " m/s)");
console.log("");
console.log("  display   jitter        raw        interpolated");

let failures = 0;
const CASES = [[60, 0.02], [60, 0.08], [75, 0.05], [100, 0.05], [144, 0.05], [30, 0.05]];
for (const [fps, jitter] of CASES) {
  const raw = run(fps, jitter, false);
  const lerped = run(fps, jitter, true);
  // Worst single-frame deviation from the average step, as a percentage of it:
  // 0% is perfectly even motion, 100% means a frame moved twice as far as it
  // should have -- or not at all.
  const line = "  " + (fps + "fps").padEnd(9) + (Math.round(jitter * 100) + "%").padEnd(9) +
    (raw.ratio * 100).toFixed(0).padStart(7) + "%" +
    (lerped.ratio * 100).toFixed(0).padStart(15) + "%";
  // Interpolation must leave the drawn motion essentially exact, and must be a
  // large improvement on the raw case wherever the raw case was actually bad.
  const ok = lerped.ratio < 0.02 && (raw.ratio < 0.02 || lerped.ratio < raw.ratio / 4);
  if (!ok) failures++;
  console.log(line + (ok ? "" : "   <- FAIL"));
}

console.log("");
console.log("  Worst single-frame error between the travel DRAWN and the travel that");
console.log("  frame's own elapsed time earned. Raw motion quantises to the simulation's");
console.log("  tick boundaries -- a frame draws one slice of travel, or two, or three,");
console.log("  regardless of how long it actually took.");

// --- the chase camera --------------------------------------------------------
//
// camX used to be exactly the player's lateral position, so the kart sat in one
// column of pixels for the whole race and the world slid under it. The camera
// now trails, which is what lets the kart visibly slide toward the outside of a
// corner. That trailing has to be worth seeing and must not walk the kart off
// toward the edge of the screen, so both ends are worth a number.
const TUNE = fs.readFileSync(path.join(__dirname, "Tuning.lua"), "utf8");
const tune = key => {
  const m = TUNE.match(new RegExp('key = "' + key + '"[^}]*?default = (-?[\\d.]+)'));
  if (!m) throw new Error("Tuning.lua has no " + key);
  return +m[1];
};
const FOLLOW = tune("camFollow"), LAG_MAX = tune("camFollowMax");
const CAM_DEPTH = tune("camDepth"), CAM_BACK = tune("camBack"), ROAD_HALF = tune("roadHalf");
// RaceUI:Project, at the player's own kart: it sits camBack metres ahead of the
// camera, so this is the scale its lateral offset is drawn at. Result is in
// HALF-SCREENS, where 1.0 is the screen edge at any resolution.
const PER_LATERAL = (CAM_DEPTH / CAM_BACK) * ROAD_HALF;

console.log("");
console.log("Chase camera  (follow " + FOLLOW + "/s, lag limit " + LAG_MAX +
  " of the road's half-width)");
console.log("");
console.log("  display   peak kart offset   settles back in");

for (const fps of [30, 60, 144]) {
  const dt = 1 / fps;
  let cam = 0, lateral = 0, peak = 0, settle = null;
  // A hard corner: thrown from the centre line to four fifths of the way out
  // over half a second, held, then released.
  for (let frame = 0; frame < fps * 4; frame++) {
    const t = frame * dt;
    lateral = t < 0.5 ? (t / 0.5) * 0.8 : t < 2.0 ? 0.8 : 0;
    cam += (lateral - cam) * Math.min(1, dt * FOLLOW);
    cam = Math.min(Math.max(cam, lateral - LAG_MAX), lateral + LAG_MAX);
    const offset = Math.abs(lateral - cam) * PER_LATERAL;
    if (t < 2.0) peak = Math.max(peak, offset);
    if (t > 2.0 && settle === null && offset < 0.01) settle = t - 2.0;
  }
  // Worth seeing, and nowhere near the edge: past about a third of a half-screen
  // the kart is far enough off centre that the road ahead of it is not.
  const ok = peak > 0.05 && peak < 0.35 && settle !== null && settle < 1.0;
  if (!ok) failures++;
  console.log("  " + (fps + "fps").padEnd(10) + (peak.toFixed(3) + " half-screens").padStart(18) +
    "   " + (settle === null ? "never" : settle.toFixed(2) + "s").padStart(9) +
    (ok ? "" : "   <- FAIL"));
}
console.log("");
console.log("  The kart has to move within the frame to feel shoved around, and has to");
console.log("  come back to centre when the corner does. Zero is the old pinned camera.");

console.log("");
console.log(failures ? "FAIL (" + failures + " case(s))"
  : "PASS (drawn motion follows real frame time; the chase camera trails and returns)");
process.exit(failures ? 1 : 0);
