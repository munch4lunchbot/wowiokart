// Is drifting a decision, or is it just free?
//
// In Mario Kart the drift is the whole game: you give up your line to bank a
// mini-turbo, and the give-up is what makes the bank worth something. Here the
// drift engages on ANY steering input above 18 m/s -- including a wiggle down a
// dead straight -- and the only cost is 3% of speed per second. Charge rate
// while counter-steering is 2.33/s, so a mega-turbo lands in 0.77 seconds and
// pays 1.45 seconds at +30% top speed.
//
// That is not a decision. It is a rhythm you hold for the entire race, and on a
// 650m straight it is strictly the fastest way to travel in a straight line.
//
// This mirrors the lateral and speed integration from Race/Physics.lua and asks
// three questions with numbers:
//
//   1. SNAKING -- drift down a straight to bank a mega. How far off line does it
//      put you, and is the boost worth more than it costs?
//   2. CORNERING -- through a real corner, does drifting hold a TIGHTER line
//      than gripping? If it does not, nobody would ever drift in a corner and
//      the mechanic only exists for straights, which is backwards.
//   3. COMMITMENT -- does a drift you cannot finish cost you anything?
//
// Run: node verify-drift.js
const fs = require("fs");
const path = require("path");

const ADDON = __dirname;
const PHYS = fs.readFileSync(path.join(ADDON, "Race", "Physics.lua"), "utf8");
const TUNE = fs.readFileSync(path.join(ADDON, "Tuning.lua"), "utf8");
const tune = key => {
  const m = TUNE.match(new RegExp('key = "' + key + '"[^}]*?default = (-?[\\d.]+)'));
  if (!m) throw new Error("Tuning.lua has no " + key);
  return +m[1];
};
const num = (re, fallback) => { const m = PHYS.match(re); return m ? +m[1] : fallback; };

const CURVE_PUSH = tune("curvePush");
const RATE = 1 / 120;                       // Core/FixedStep.lua
// Physics constants, read out of the source so this cannot drift from the game.
const DRIFT_STEER = num(/vehicle\.drifting and ([\d.]+) or 1\)? \* grip/, 1.30);
const DRIFT_PUSH_GRIP = +(process.env.BITE ?? num(/local DRIFT_BITE = ([\d.]+)/,
  num(/local grip = vehicle\.drifting and ([\d.]+) or 1/, 1.35)));
const DRIFT_DRAG = num(/vehicle\.speed \* \.(\d+) \* dt/, 30) / 1000;
const COUNTER_SLIDE = num(/vehicle\.driftDirection \* counter \* ([\d.]+) \* dt/, 0.22);
const CURVE_SCALE = num(/RoadCurve\(track, vehicle\.distance\) \* ([\d.]+)/, 0.002);
const BOOST_MULT = num(/local boostMultiplier = vehicle\.boostTime > 0 and ([\d.]+) or 1/, 1.30);
// Leaving the tarmac is the real cost of swinging across a straight, so the
// harness has to model it or it will report snaking as free when it is not.
const TERRAIN = fs.readFileSync(path.join(ADDON, "Data", "Terrain.lua"), "utf8");
const grassBlock = TERRAIN.slice(TERRAIN.indexOf("GRASS = {"), TERRAIN.indexOf("SAND = {"));
const GRASS_SPEED = +(grassBlock.match(/speed = ([\d.]+)/) || [, 0.52])[1];
const GRASS_STEER = +(grassBlock.match(/steering = ([\d.]+)/) || [, 0.90])[1];
const GRASS_TRACTION = +(grassBlock.match(/traction = ([\d.]+)/) || [, 0.85])[1];
const BLEND_RAMP = +(PHYS.match(/offBy \/ \(width \* ([\d.]+)\)/) || [, 0.70])[1] || 0.70;
const OFFROAD_ROOM = tune("offroadRoom");
const MEGA = 1.8, SUPER = 0.9, MINI = 0.35;
// How much of the mini-turbo charge rate a drift earns on a given corner. A
// straight earns the floor; anything at or past DRIFT_LOAD_FULL earns all of it.
const LOAD_FLOOR = +(process.env.FLOOR ?? num(/local DRIFT_LOAD_FLOOR = ([\d.]+)/, 1));
const LOAD_FULL = +(process.env.FULL ?? num(/local DRIFT_LOAD_FULL = ([\d.]+)/, 1));

// A middle-of-the-grid pairing: "Yourself" in the Mechano-Kart.
const KART = {
  handling: (0.55 + ((6 + 7) * 0.5) * 0.13),
  maxSpeed: (56 + ((6 + 6) * 0.5) * 2.65),
  accel: (24 + ((6 + 6) * 0.5) * 3.4),
  weight: 5,
  driftStat: (6 + 6) * 0.5,
};
const MASS_TERM = 0.75 + KART.weight * 0.05;

/**
 * Run the kart for `seconds` on a road of constant `curve`, with a strategy.
 * Mirrors the lateral/speed integration in Physics:UpdateVehicle closely enough
 * to answer a question about their relative sizes.
 */
function run({ curve, seconds, drift, steer, throttle = 1, speed = null }) {
  const v = {
    speed: speed === null ? KART.maxSpeed : speed,
    lateral: 0, charge: 0, drifting: false, direction: 0, boostTime: 0,
  };
  let peakLateral = 0, megas = 0, boosted = 0, offRoadTime = 0, recoveries = 0, travelled = 0;
  const steps = Math.round(seconds / RATE);
  for (let i = 0; i < steps; i++) {
    const t = i * RATE;
    const turning = steer(t, v);
    v.boostTime = Math.max(0, v.boostTime - RATE);
    const top = KART.maxSpeed * (v.boostTime > 0 ? BOOST_MULT : 1);
    if (v.boostTime > 0) boosted += RATE;

    // Surface. Mirrors Terrain:Sample -- past the verge the penalty ramps in
    // over 0.7 of a road-width, and a boost overrules most of it.
    const offBy = Math.abs(v.lateral) - 1.0;
    let blend = offBy <= 0 ? 0 : Math.min(Math.max(offBy / BLEND_RAMP, 0), 1);
    if (v.boostTime > 0) blend *= 0.20;
    const surfSpeed = 1 + (GRASS_SPEED - 1) * blend;
    const surfSteer = (1 + (GRASS_STEER - 1) * blend) * (1 + (GRASS_TRACTION - 1) * blend);

    // throttle / rolling resistance
    const ratio = Math.min(Math.max(v.speed / Math.max(1, top), 0), 1.4);
    v.speed += KART.accel * (1 - ratio * ratio * 0.86) * throttle * RATE;
    v.speed -= (2.2 + v.speed * 0.022) * RATE;

    // drift engage / hold / release
    const wantDrift = drift(t, v) && turning !== 0 && v.speed > 18;
    if (wantDrift) {
      if (!v.drifting) { v.drifting = true; v.direction = turning; }
      const counter = turning !== v.direction ? 1 : 0;
      let rate = (0.30 + KART.driftStat * 0.05) + counter * (0.22 + KART.driftStat * 0.04);
      // A mini-turbo comes from LOADING the kart in a corner, not from holding a
      // button. Without this, weaving down a straight banks one every 0.8s.
      const load = LOAD_FULL > 0
        ? Math.min(Math.max(Math.abs(curve) / LOAD_FULL, 0), 1) : 1;
      rate *= LOAD_FLOOR + (1 - LOAD_FLOOR) * load;
      v.charge = Math.min(v.charge + RATE * rate * 2.2, 2.5);
      v.lateral += v.direction * counter * COUNTER_SLIDE * RATE;
      v.speed -= v.speed * DRIFT_DRAG * RATE;
      offRoadTime += blend > 0.05 ? RATE : 0;
    } else if (v.drifting) {
      if (v.charge > MINI) {
        const boost = v.charge > MEGA ? 1.45 : (v.charge > SUPER ? 0.85 : 0.42);
        if (v.charge > MEGA) megas++;
        v.boostTime = Math.max(v.boostTime, boost);
        v.speed = Math.max(v.speed, KART.maxSpeed * (1.04 + boost * 0.055));
      }
      v.drifting = false; v.charge = 0; v.direction = 0;
    }

    // steering authority, then the corner's push
    const grip = (0.30 + 1.55 * ratio - 1.35 * ratio * ratio) * 1.35;
    const strength = KART.handling * (v.drifting ? DRIFT_STEER : 1) * grip * surfSteer;
    v.lateral += turning * strength * RATE;
    // Signed exactly as Physics does it: a positive curve is a right-hand bend
    // and the push is NEGATIVE, i.e. outward, against the driver steering into
    // it. Getting this backwards makes the corner help you round itself.
    const pushGrip = v.drifting ? DRIFT_PUSH_GRIP : 1;
    v.lateral -= curve * CURVE_SCALE * v.speed * (v.speed / KART.maxSpeed)
      * CURVE_PUSH * pushGrip * MASS_TERM * RATE;

    // The material's own speed ceiling, scrubbed toward rather than applied flat.
    const ceiling = KART.maxSpeed * surfSpeed;
    if (v.speed > ceiling) v.speed -= (v.speed - ceiling) * 3.2 * RATE;
    // The barrier: past this you are off the course entirely and get picked up.
    if (Math.abs(v.lateral) > OFFROAD_ROOM) { v.lateral = Math.sign(v.lateral) * OFFROAD_ROOM; recoveries++; }
    peakLateral = Math.max(peakLateral, Math.abs(v.lateral));
    travelled += v.speed * RATE;
  }
  return { ...v, peakLateral, megas, boosted, seconds, offRoadTime, recoveries, travelled };
}

let failures = 0;
console.log("Drift economy  (mid-field kart, road edge at lateral 1.0)");
console.log("");

// --- 1. snaking a straight ---------------------------------------------------
// A real snaker does not just hold the stick over: they engage the drift, hold
// until the mega lands, RELEASE to cash it, and immediately re-engage the other
// way. Modelling it as one endless drift never collects anything, which would
// make snaking look harmless when it is the thing being tested for.
let snakeFlip = 1;
const snake = run({
  curve: 0, seconds: 12,
  drift: (t, v) => v.charge < MEGA,          // release the instant the mega lands
  steer: (t, v) => {
    if (!v.drifting && v.charge === 0) snakeFlip = -snakeFlip;
    return snakeFlip;
  },
});
const cruise = run({ curve: 0, seconds: 12, drift: () => false, steer: () => 0 });
const snakeGain = snake.boosted / snake.seconds;
console.log("1. SNAKING a dead straight for 12s");
console.log("     mega-turbos banked   " + String(snake.megas).padStart(6));
console.log("     time spent boosted   " + (snakeGain * 100).toFixed(0).padStart(5) + "%");
console.log("     peak off line        " + snake.peakLateral.toFixed(2).padStart(6) +
  "  (1.00 is the verge)");
console.log("     time off the tarmac  " + (snake.offRoadTime / snake.seconds * 100)
  .toFixed(0).padStart(5) + "%");
console.log("     distance covered     " + snake.travelled.toFixed(0).padStart(6) +
  "m  vs " + cruise.travelled.toFixed(0) + "m just holding the throttle");
// The only question that matters: is weaving FASTER than driving straight? If it
// is, it is the correct input on every straight in the game and there is nothing
// to decide. Leaving the tarmac is what is supposed to make it a trade.
const snakePayoff = snake.travelled / cruise.travelled;
console.log("     net                  " + ((snakePayoff - 1) * 100).toFixed(1).padStart(5) +
  "%  " + (snakePayoff > 1 ? "FASTER than a straight line" : "slower than a straight line"));
const snakeOK = snakePayoff <= 1.02;
if (!snakeOK) { failures++; console.log("     <- FAIL: weaving beats driving straight, so it is the correct input everywhere"); }
console.log("");

// --- 2. drifting a real corner ----------------------------------------------
//
// The question is not "where does the kart end up after three seconds" -- past a
// certain speed both answers are "in the grass". It is the one a driver asks:
// HOW FAST CAN I TAKE THIS AND STAY ON THE ROAD? If drifting does not raise that
// number, drifting is not a cornering tool and the only reason to ever press the
// button is to farm boosts on straights.
function fastestThrough(curve, drifting, seconds = 2.4) {
  // Steering is a KEYBOARD input in this game: left, right, or nothing. So the
  // driver is modelled as bang-bang control with a deadband -- hold the key
  // while the kart is being pushed off the line, let go once it is back --
  // rather than as a permanently pinned full lock, which simply oversteers into
  // the grass on the inside and measures nothing.
  const driver = (t, v) => {
    if (v.lateral < -0.04) return 1;
    if (v.lateral > 0.10) return -1;
    // Drifting needs a live steering input to stay engaged; releasing the key
    // mid-corner would cash the boost out early and confuse the comparison.
    return drifting ? 1 : 0;
  };
  let lo = 5, hi = KART.maxSpeed * 2.4;
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    // Enter at `mid`, coasting: no throttle, so this measures the corner alone.
    const r = run({
      curve, seconds, speed: mid, throttle: 0,
      drift: () => drifting, steer: driver,
    });
    if (r.peakLateral <= 1.0) lo = mid; else hi = mid;
  }
  return lo;
}

console.log("2. HOW FAST YOU CAN TAKE A CORNER and stay on the tarmac");
console.log("");
console.log("     curve    gripping   drifting   drifting buys you");
let cornerFail = false;
for (const curve of [0.8, 1.2, 1.6, 2.0, 2.4, 2.8, 3.2, 3.6, 4.0, 4.4]) {
  const g = fastestThrough(curve, false);
  const d = fastestThrough(curve, true);
  const gain = (d / g - 1) * 100;
  // A bend both strategies can take faster than the kart will ever go is not a
  // corner, and comparing two saturated searches would report a flat 0% that
  // reads as a failure. Skip it, and say so.
  const flatOut = g >= KART.maxSpeed * 2.3;
  const ok = flatOut || gain > 1.0;
  if (!ok) cornerFail = true;
  console.log("     " + curve.toFixed(1).padStart(5) +
    (flatOut ? "  takeable flat out, at any speed this kart reaches"
      : g.toFixed(1).padStart(11) + d.toFixed(1).padStart(11) +
        (gain >= 0 ? "   +" : "   ") + gain.toFixed(1) + "%" +
        (ok ? "" : "   <- drifting is no help here")));
}
if (cornerFail) {
  failures++;
  console.log("");
  console.log("     <- FAIL: drifting does not let you carry more speed through a corner.");
  console.log("        Physics multiplies the centrifugal push by " + DRIFT_PUSH_GRIP +
    " while drifting and the");
  console.log("        steering by only " + DRIFT_STEER + ", so a drift makes the corner WIDER, not tighter.");
}
console.log("");

// --- 3. what a drift costs -------------------------------------------------
//
// A drift that only ever helped would be a button you hold for the whole race.
// The trade is meant to be: a better line, for less speed and for a commitment
// you have to finish. Test 2 measured the line; this measures the bill.
const CORNER = 2.8;
const held = run({ curve: CORNER, seconds: 2.0, speed: 60, drift: () => true, steer: () => 1 });
const grippedSame = run({ curve: CORNER, seconds: 2.0, speed: 60, drift: () => false, steer: () => 1 });
const bailed = run({ curve: CORNER, seconds: 2.0, speed: 60, drift: t => t < 0.25, steer: () => 1 });
console.log("3. WHAT A DRIFT COSTS through a curve-" + CORNER + " corner, entering at 60");
console.log("     gripping, exits at   " + grippedSame.speed.toFixed(1).padStart(6));
console.log("     drifting,  exits at  " + held.speed.toFixed(1).padStart(6) +
  "   banking " + held.charge.toFixed(2) + " of charge");
console.log("     bailed at 0.25s      " + bailed.speed.toFixed(1).padStart(6) +
  "   banking " + bailed.charge.toFixed(2) + "  (under the " + MINI + " mini threshold: nothing)");
const costsSpeed = held.speed < grippedSame.speed;
if (!costsSpeed) {
  failures++;
  console.log("     <- FAIL: drifting costs no speed, so there is no reason not to hold it");
}
console.log("");

console.log(failures ? "FAIL (" + failures + " -- the drift is not a decision)"
  : "PASS (drifting buys a corner and cannot be farmed on a straight)");
process.exit(failures ? 1 : 0);
