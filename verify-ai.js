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
// A mini-turbo only charges at full rate when the kart is LOADED -- see the
// load gate in Physics:UpdateVehicle. The AI drifts on curvature above 1.5 and
// the gate is full at 1.6, so it is usually near enough all of it; but "usually"
// is not a model, and a harness that charges at full rate everywhere would hide
// the day someone moves either number.
const PHYS_SRC = fs.readFileSync(path.join(__dirname, "Race", "Physics.lua"), "utf8");
const AI_SRC = fs.readFileSync(path.join(__dirname, "Race", "AI.lua"), "utf8");
const LOAD_FLOOR = +(PHYS_SRC.match(/local DRIFT_LOAD_FLOOR = ([\d.]+)/) || [, 1])[1];
const LOAD_FULL = +(PHYS_SRC.match(/local DRIFT_LOAD_FULL = ([\d.]+)/) || [, 1])[1];
const chargeRateAt = curve => CHARGE_RATE *
  (LOAD_FLOOR + (1 - LOAD_FLOOR) * Math.min(Math.abs(curve) / LOAD_FULL, 1));
const TIERS = [[1.8, "mega"], [0.9, "super"], [0.35, "mini"]];
const driftTarget = daring =>
  (daring > 0.85 ? 1.85 : daring > 0.62 ? 0.95 : 0.40) * (1.10 - DRIFT_STAT * 0.02);
const tierOf = charge => (TIERS.find(t => charge > t[0]) || [, null])[1];

// A drifted corner is a different corner: the field commits to a drift above
// curvature DRIFT_CORNER, and while drifting the push is multiplied by
// DRIFT_BITE and the steering by DRIFT_STEER. Modelling the brake against the
// grip-limited speed while the kart is actually drifting through it is how the
// AI ends up braking for a corner it was going to take flat.
const DRIFT_BITE = +(PHYS_SRC.match(/local DRIFT_BITE = ([\d.]+)/) || [, 1])[1];
const DRIFT_STEER = +(PHYS_SRC.match(/local DRIFT_STEER = ([\d.]+)/) || [, 1])[1];
const DRIFT_CORNER = +(AI_SRC.match(/local DRIFT_CORNER = ([\d.]+)/) || [, 1.5])[1];

// Grip at a point on the lap. Ice is steering 1.10 x traction 0.22 -- a QUARTER
// of the authority the same kart has on tarmac -- and Ironforge is 47% ice.
const TERRAIN_TABLE = require("./Art/terrain-table.js").readTerrain(__dirname);
const gripOf = mat => {
  const m = TERRAIN_TABLE[mat];
  return m ? m.steering * m.traction : 1;
};

function cornerSpeed(v, curve, precision, drifting, grip = 1) {
  curve = Math.abs(curve);
  if (curve < 0.12) return Infinity;
  const weightFactor = 0.75 + v.weight * 0.05;
  const authority = v.handling * 0.95 * (drifting ? DRIFT_STEER : 1) * grip;
  const bite = drifting ? DRIFT_BITE : 1;
  return Math.sqrt(authority * v.maxSpeed / (CURVE_GAIN * PUSH * weightFactor * curve * bite))
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
  const painted = [...body.matchAll(/\{ from = (\d+), to = (\d+), onRoad = "(\w+)" \}/g)]
    .map(x => ({ from: +x[1], to: +x[2], grip: gripOf(x[3]) }));
  const gripAt = d => {
    const lapD = ((d % length) + length) % length;
    for (const p of painted) if (lapD >= p.from && lapD <= p.to) return p.grip;
    return 1;
  };

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
        const c = curveAt(d + ahead);
        const l = cornerSpeed(KART, c, precision,
          daring > 0.4 && Math.abs(c) > DRIFT_CORNER, gripAt(d + ahead));
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
        charge = Math.min(2.5, charge + dt * chargeRateAt(curveAt(d)));
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
