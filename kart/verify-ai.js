// Does the AI's corner model actually do anything, on the real tracks?
//
//   node verify-ai.js
//
// Race/AI.lua derives a corner speed from the physics -- solving the point at
// which centrifugal push exactly consumes full steering lock -- and brakes when
// it cannot make the next corner at its current speed. Two ways that can be
// silently wrong: a model that never brakes (the AI ploughs wide everywhere and
// looks drunk) and one that brakes constantly (the field crawls). Neither is
// visible from a screenshot and neither trips a syntax check.
//
// This mirrors cornerSpeed/brakeTarget against the shipped curveTable and runs
// a crude lap, reporting how much of each circuit is spent braking. The
// interesting number is the SPREAD: Elwynn is a beginner track and should
// barely brake, Durotar is four hairpins and should brake a lot.
const fs = require("fs");
const path = require("path");

const ADDON = __dirname;

// Kept in step with Race/AI.lua and Race/Physics.lua by hand; if these drift
// the report is fiction, so they are read from source where possible.
const tuning = (function () {
  const src = fs.readFileSync(path.join(ADDON, "Tuning.lua"), "utf8");
  const out = {};
  for (const m of src.matchAll(/key = "(\w+)"[^}]*?default = (-?[\d.]+)/g)) out[m[1]] = +m[2];
  return out;
})();
const CURVE_GAIN = 0.002;
const PUSH = tuning.curvePush;
const BRAKE = tuning.brakeForce;

// A mid-stat kart, matching Physics:CreateVehicle for stats of 6.
const KART = {
  maxSpeed: 56 + 6 * 2.65,
  acceleration: 24 + 6 * 3.4,
  handling: 0.55 + 6 * 0.13,
  weight: 5,
};

// --- Drift model, mirroring the state machine in AI.lua and the charge rate in
// Physics.lua. This exists because an in-game AI report showed the field
// drifting for 12-27% of a race while completing 0-2 drifts: all of the speed
// scrub, none of the mini-turbos. Time spent drifting is NOT the measure --
// boosts banked is.
const DRIFT_STAT = 5;
const CHARGE_RATE = (0.30 + DRIFT_STAT * 0.05) * 2.2;   // per second, holding in
const TIERS = [[1.8, "mega"], [0.9, "super"], [0.35, "mini"]];
const driftTarget = daring =>
  (daring > 0.85 ? 1.85 : daring > 0.62 ? 0.95 : 0.40) * (1.10 - DRIFT_STAT * 0.02);
const tierOf = charge => (TIERS.find(t => charge > t[0]) || [, null])[1];

function cornerSpeed(v, curve, precision) {
  curve = Math.abs(curve);
  if (curve < 0.12) return Infinity;
  const weightFactor = 0.75 + v.weight * 0.05;
  const authority = v.handling * 0.95;
  return Math.sqrt(authority * v.maxSpeed / (CURVE_GAIN * PUSH * weightFactor * curve))
    * (0.82 + precision * 0.16);
}

// Compile a track's smoothed curveTable exactly as Data/TrackBuilder.lua does.
function curveTable(body, length) {
  const ls = body.indexOf("layout = {"), le = body.indexOf("\n    },", ls);
  const layout = [...body.slice(ls, le).matchAll(/\{ len = ([\d.]+),([^}]*)\}/g)].map(x => ({
    len: +x[1],
    curve: +((x[2].match(/curve = (-?[\d.]+)/) || [, 0])[1]),
  }));
  const authored = layout.reduce((s, p) => s + p.len, 0), scale = length / authored;
  const STEP = 2, N = Math.floor(length / STEP) + 1;
  const raw = [];
  let pi = 0, left = layout[0].len * scale;
  for (let i = 0; i < N; i++) {
    raw.push(layout[pi].curve || 0);
    left -= STEP;
    while (left <= 0 && pi < layout.length - 1) { pi++; left += layout[pi].len * scale; }
  }
  const sm = [];
  for (let i = 0; i < N; i++) {
    let t = 0;
    for (let k = -15; k <= 15; k++) t += raw[((i + k) % N + N) % N];
    sm.push(t / 31);
  }
  return { table: sm, step: STEP, n: N };
}

const src = fs.readFileSync(path.join(ADDON, "Data", "Tracks.lua"), "utf8");
const starts = [];
const re = /\n  \{\n    id = "(\w+)"/g;
let m; while ((m = re.exec(src))) starts.push({ id: m[1], at: m.index });

console.log("AI corner model  (curvePush " + PUSH + ", brakeForce " + BRAKE + ")");
console.log("kart: vmax " + KART.maxSpeed.toFixed(1) + "  accel " + KART.acceleration.toFixed(1) +
  "  handling " + KART.handling.toFixed(2));
console.log("");
// Note the last column counts brake APPLICATIONS, not distinct corners -- the
// throttle flutters on and off through a long bend, so one hairpin can show as
// several. The braking percentage is the number that means something.
console.log("track            braking %   slowest corner   brake apps   boosts   mix          drift%");

let failures = 0;
for (let i = 0; i < starts.length; i++) {
  const body = src.slice(starts[i].at, i + 1 < starts.length ? starts[i + 1].at : src.length);
  const length = +(body.match(/length = (\d+), laps/) || [, 2600])[1];
  const cv = curveTable(body, length);
  const curveAt = d => cv.table[Math.floor(((d % length) + length) % length / cv.step) % cv.n];

  // Two laps, so the sim starts the second one at a realistic speed.
  // DARING=0.95 to check the mega-hunters, who hold out for the top tier and so
  // are the profile most at risk of running out of corner with nothing banked.
  const precision = 0.82, daring = +(process.env.DARING || 0.75);
  const decel = KART.acceleration * BRAKE;
  const margin = 14 - daring * 6;
  let speed = KART.maxSpeed * 0.6, braking = 0, total = 0, slowest = Infinity, zones = 0, wasBraking = false;
  const target = driftTarget(daring);
  let wantDrift = false, driftCool = 0, charge = 0, driftTime = 0;
  const banked = { mini: 0, super: 0, mega: 0, thrown: 0 };
  for (let lap = 0; lap < 2; lap++) {
    for (let d = 0; d < length; d += 2) {
      let limit = null;
      for (let ahead = 6; ahead <= 110; ahead += 7) {
        const l = cornerSpeed(KART, curveAt(d + ahead), precision);
        if (speed > l) {
          const needed = (speed * speed - l * l) / (2 * decel);
          if (needed >= ahead - margin) { limit = l; break; }
        }
      }
      const dt = 2 / Math.max(1, speed);
      if (limit && speed > limit) {
        speed = Math.max(limit, speed - decel * dt);
        if (lap === 1) { braking += 2; if (!wasBraking) zones++; }
        wasBraking = true;
        if (lap === 1) slowest = Math.min(slowest, limit);
      } else {
        speed = Math.min(KART.maxSpeed, speed + KART.acceleration * dt);
        wasBraking = false;
      }

      // Drift, stepped on the same clock as the braking model above.
      const corner = Math.abs(curveAt(d + 26)) > 1.5 || Math.abs(curveAt(d)) > 1.2;
      driftCool = Math.max(0, driftCool - dt);
      const wasDrifting = wantDrift;
      if (corner && speed > 26 && daring > 0.4 && driftCool <= 0) wantDrift = true;
      if (!corner) wantDrift = false;
      if (wantDrift && charge >= target) { wantDrift = false; driftCool = 0.35; }
      if (wantDrift) {
        charge = Math.min(2.5, charge + dt * CHARGE_RATE);
        if (lap === 1) driftTime += dt;
      } else if (wasDrifting) {
        // Released -- either at the target or because the corner ran out. Both
        // paths bank whatever has accumulated; only a charge under the mini
        // threshold is genuinely thrown away.
        const tier = tierOf(charge);
        if (lap === 1) { if (tier) banked[tier]++; else banked.thrown++; }
        charge = 0;
      }

      if (lap === 1) total += 2;
    }
  }
  const pct = braking / total * 100;
  const boosts = banked.mini + banked.super + banked.mega;
  let flag = pct < 1 ? "  <-- never brakes" : (pct > 55 ? "  <-- brakes constantly" : "");
  if (pct < 1 || pct > 55) failures++;
  // The regression this guards: drifting a lot and banking nothing. A lap with
  // corners in it must convert them into boosts.
  if (zones > 0 && boosts < 1) { flag += "  <-- drifts but banks nothing"; failures++; }
  console.log("  " + starts[i].id.padEnd(15) + pct.toFixed(1).padStart(6) + "%   " +
    (slowest === Infinity ? "   --" : slowest.toFixed(1).padStart(5) + " m/s") +
    "        " + String(zones).padStart(3) +
    String(boosts).padStart(9) + "   " +
    (banked.mini + "/" + banked.super + "/" + banked.mega + "/" + banked.thrown).padEnd(11) +
    (driftTime / (total / Math.max(1, speed)) * 100).toFixed(0).padStart(4) + "%" + flag);
}
console.log("");
console.log("  boosts = mini-turbos banked per lap;  mix = mini/super/mega/thrown away");
console.log("");
console.log(failures ? "FAIL (" + failures + " problem(s))" : "PASS");
process.exit(failures ? 1 : 0);
