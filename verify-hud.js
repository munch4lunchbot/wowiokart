// Does the HUD fit, at every resolution a player might actually have?
//
// Every HUD offset used to be an absolute pixel figure authored against one
// 1280-wide window. Nothing checked what happened on any other, and the answers
// were bad in both directions: the control row spanned 816px of a screen that
// can be 800 wide, and on a 1440p client the whole interface sat at half its
// intended size in the corners. Worse, nothing checked what happened when a
// readout showed its LONGEST possible content rather than its typical content
// -- which is how "LAP 28.44  BEST 27.90" fits and "LAP 9:59.99  BEST 9:59.99"
// runs off the panel on the one track where a lap takes that long.
//
// So this walks the real layout (Art/hud-layout.js, which parses the HUD table
// out of UI/RaceUI.lua) at a spread of real resolutions, with every string at
// its worst case, and reports anything off the display or on top of anything
// else.
//
// Run: node verify-hud.js
const { rects, scale } = require("./Art/hud-layout.js");

const SCREENS = [
  [1024, 768, "small windowed"],
  [1280, 720, "720p"],
  [1366, 768, "common laptop"],
  [1600, 900, "design size"],
  [1920, 1080, "1080p"],
  [2560, 1440, "1440p"],
  [3440, 1440, "ultrawide"],
  [1280, 1024, "5:4"],
];

// A soft halo is meant to sit under things; a text row is meant to sit inside
// the panel it belongs to. Everything else sharing pixels is a defect.
const family = name => name.split(".")[0];
const overlaps = (a, b) =>
  a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

let failures = 0;
console.log("HUD fit  (worst-case content, real layout, mirrored from UI/RaceUI.lua)");
console.log("");
console.log("screen                 scale   off-screen   collisions   spill");

for (const [W, H, note] of SCREENS) {
  const all = rects(W, H);
  const off = [];
  for (const r of all) {
    if (r.kind === "glow") continue;             // deliberately bleeds off-corner
    if (r.x < -0.5 || r.y < -0.5 || r.x + r.w > W + 0.5 || r.y + r.h > H + 0.5)
      off.push(r.name);
  }
  // Text running out of its OWN panel is invisible to a cross-family collision
  // test -- it is the same family, and it need not reach a screen edge to be
  // broken. It is also the likeliest failure: a readout grows with its content,
  // a panel does not.
  const spill = [];
  const panels = {};
  for (const r of all) if (r.kind === "panel") panels[family(r.name)] = r;
  for (const r of all) {
    const host = panels[family(r.name)];
    if (!host || r === host || r.kind === "glow" || r.outside) continue;
    if (r.x < host.x - 0.5 || r.y < host.y - 0.5 ||
        r.x + r.w > host.x + host.w + 0.5 || r.y + r.h > host.y + host.h + 0.5)
      spill.push(r.name + " out of " + host.name);
  }

  // A COLUMN IS A PANEL FOR ONE ROW OF TEXT.
  //
  // The spill test above asks whether a readout stays inside its PANEL, which
  // a ladder row's name does easily -- the panel is 250 wide. What it has to
  // stay inside is its own 138-wide column, and "Illidan Stormrage" did not:
  // at twelve point that is 126 against the 120 the column used to be, so the
  // longest name on the grid wrapped to a second line inside a 22-pixel row.
  const columns = {};
  for (const r of all) if (r.kind === "column") columns[r.name.replace(".col", ".name")] = r;
  for (const r of all) {
    const col = columns[r.name];
    if (!col) continue;
    if (r.x + r.w > col.x + col.w + 0.5) {
      spill.push(r.name + " out of its column by "
        + Math.ceil(r.x + r.w - (col.x + col.w)) + "px");
    }
  }

  const hits = [];
  for (let i = 0; i < all.length; i++) {
    for (let j = i + 1; j < all.length; j++) {
      const a = all[i], b = all[j];
      if (a.kind === "glow" || b.kind === "glow") continue;
      // A column is a measuring box, not a drawn thing.
      if (a.kind === "column" || b.kind === "column") continue;
      if (family(a.name) === family(b.name)) continue;
      if (overlaps(a, b)) hits.push(a.name + " x " + b.name);
    }
  }
  const bad = off.length + hits.length + spill.length;
  if (bad) failures++;
  console.log("  " + (W + "x" + H).padEnd(11) + note.padEnd(11) +
    scale(W, H).toFixed(2).padStart(5) + "   " +
    String(off.length).padStart(10) + "   " + String(hits.length).padStart(10) +
    "   " + String(spill.length).padStart(6));
  for (const n of off) console.log("        off-screen: " + n);
  for (const n of hits) console.log("        collision:  " + n);
  for (const n of spill) console.log("        overflows:  " + n);
}

console.log("");
if (failures) {
  console.log("FAIL (" + failures + " of " + SCREENS.length + " screens have a HUD that does not fit)");
  process.exit(1);
}
console.log("PASS (the HUD fits, with worst-case content, on every screen tested)");
