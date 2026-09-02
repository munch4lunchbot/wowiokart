// Do the camera feel channels actually come home?
//
// Every camera reaction in RaceUI is an offset added to the tuned baseline and
// eased back toward zero. Easing is asymptotic -- it never actually arrives --
// so without a hard snap each boost, landing and hit leaves a sliver behind,
// and those slivers accumulate. A camera that is 3% back and 2% low by lap
// three is unusable, and the player has no way to describe what went wrong.
//
// This mirrors the decay in UI/RaceUI.lua and asserts three things:
//   1. every channel reaches EXACTLY zero, not merely a small number
//   2. it gets there inside a plausible time budget
//   3. a long storm of overlapping impulses still ends at exactly zero
//
// Run: node verify-feel.js
const fs = require("fs");
const path = require("path");

const SRC = fs.readFileSync(path.join(__dirname, "UI", "RaceUI.lua"), "utf8");

// Read the real constants out of the addon rather than restating them, so this
// cannot quietly drift away from what the game actually runs.
const EPSILON = (() => {
  const m = SRC.match(/local FEEL_EPSILON = ([\d.]+)/);
  if (!m) throw new Error("FEEL_EPSILON not found in RaceUI.lua");
  return +m[1];
})();

const RATES = (() => {
  const out = {};
  for (const m of SRC.matchAll(/feel\.(\w+) = decay\(feel\.\1, ([\d.]+), dt\)/g)) {
    out[m[1]] = +m[2];
  }
  if (!Object.keys(out).length) throw new Error("no decay() channels found in RaceUI.lua");
  return out;
})();

// Mirrors `local function decay(value, rate, dt)`.
//
// NOSNAP=1 drops the epsilon snap, reproducing plain asymptotic easing, so this
// harness can be shown to actually catch the residue rather than merely
// agreeing with the current code. It must FAIL every channel.
const NOSNAP = !!process.env.NOSNAP;
const decay = (value, rate, dt) => {
  if (!value) return 0;
  value = value * Math.max(0, 1 - rate * dt);
  if (!NOSNAP && Math.abs(value) < EPSILON) return 0;
  return value;
};

const DT = 1 / 60;
let failures = 0;

console.log("Feel channel decay  (epsilon " + EPSILON + ", dt " + DT.toFixed(4) + "s)");
console.log("");
console.log("channel      rate    settles in   final value      verdict");

// The largest impulse each channel can actually receive, with headroom. Testing
// every channel with the same huge number is not a fair test: `push` maxes out
// around 4.3 (DriftRelease at mega tier), while `kickX` really can reach ~36
// (FeelHit on a launch), so a flat value either lets one off or condemns another
// for something it can never be handed.
const MAX_IMPULSE = { push: 6, dip: 3, kickX: 40 };

for (const [name, rate] of Object.entries(RATES)) {
  let v = MAX_IMPULSE[name] || 10, frames = 0;
  while (v !== 0 && frames < 60 * 30) { v = decay(v, rate, DT); frames++; }
  const seconds = frames / 60;
  const exact = v === 0;
  const quick = seconds < 4;
  const ok = exact && quick;
  if (!ok) failures++;
  console.log("  " + name.padEnd(10) + String(rate).padStart(5) +
    (seconds.toFixed(2) + "s").padStart(12) +
    String(v).padStart(14) + "   " +
    (ok ? "ok" : (!exact ? "FAIL never reaches zero" : "FAIL too slow")));
}

console.log("");

// The real test: a storm. Impulses land on top of each other for a long stretch
// -- boosts, landings, hits, near misses -- and then everything stops. If any
// residue survives, the baseline has moved.
console.log("Storm test: 40s of overlapping impulses, then 5s of quiet.");
const state = {};
for (const name of Object.keys(RATES)) state[name] = 0;
let t = 0;
const impulse = (name, amount) => {
  // Mirrors RaceUI:Feel -- takes the LARGER, never sums.
  if (Math.abs(amount) > Math.abs(state[name])) state[name] = amount;
};
for (let frame = 0; frame < 60 * 40; frame++) {
  t += DT;
  if (frame % 37 === 0) impulse("push", 2.6);
  if (frame % 53 === 0) impulse("dip", 1.5);
  if (frame % 71 === 0) impulse("kickX", -26);
  if (frame % 91 === 0) impulse("dip", 0.55);
  for (const [name, rate] of Object.entries(RATES)) {
    state[name] = decay(state[name], rate, DT);
  }
}
for (let frame = 0; frame < 60 * 5; frame++) {
  for (const [name, rate] of Object.entries(RATES)) {
    state[name] = decay(state[name], rate, DT);
  }
}
let residue = 0;
for (const [name, value] of Object.entries(state)) {
  const ok = value === 0;
  if (!ok) { failures++; residue++; }
  console.log("  " + name.padEnd(10) + "final " + String(value).padStart(14) +
    "   " + (ok ? "ok" : "FAIL -- baseline has permanently moved"));
}

console.log("");
console.log(failures
  ? "FAIL (" + failures + " problem(s)" + (residue ? "; camera does not return to baseline" : "") + ")"
  : "PASS (every channel returns to exactly zero)");
process.exit(failures ? 1 : 0);
