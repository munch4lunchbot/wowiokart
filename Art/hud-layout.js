// The HUD, as rectangles, in screen pixels.
//
// One source for two consumers: Art/preview-render.js draws from this, and
// verify-hud.js checks it for overlap and for running off the display. Both
// used to carry their own copy of the offsets, which is how a mirror ends up
// reporting faults the real thing does not have -- and missing the ones it does.
//
// The panel geometry is parsed straight out of UI/RaceUI.lua's HUD table, so it
// cannot drift from the addon. The text rows are declared here because the Lua
// places them imperatively (SetPoint calls inside Build), and a parser for that
// would be guessing; they are checked against the Lua by check.js instead.
const fs = require("fs"), path = require("path");
const { textWidth, textHeight } = require("./hud-font.js");

const SRC = fs.readFileSync(path.join(__dirname, "..", "UI", "RaceUI.lua"), "utf8");

const HUD = (() => {
  const table = SRC.slice(SRC.indexOf("local HUD = {"), SRC.indexOf("local HUD_PANEL"));
  const entry = /(\w+)\s*=\s*\{\s*point\s*=\s*"(\w+)"\s*,\s*x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)\s*,\s*w\s*=\s*(-?[\d.]+)\s*,\s*h\s*=\s*(-?[\d.]+)\s*\}/g;
  const out = {};
  for (const m of table.matchAll(entry))
    out[m[1]] = { point: m[2], x: +m[3], y: +m[4], w: +m[5], h: +m[6] };
  // A regex that silently stops matching turns every check downstream into a
  // check of nothing, which is worse than no check: it reports PASS. If the
  // table is reformatted, this must fail loudly rather than shrink.
  const want = ["lap", "item", "clock", "place", "map", "drift", "controls", "quit"];
  const missing = want.filter(k => !out[k]);
  if (missing.length)
    throw new Error("hud-layout: could not parse HUD entries from UI/RaceUI.lua: " + missing.join(", "));
  return out;
})();
const num = (re, fallback) => { const m = SRC.match(re); return m ? +m[1] : fallback; };
const DESIGN_W = num(/local HUD_DESIGN_W, HUD_DESIGN_H = (\d+), \d+/, 1600);
const DESIGN_H = num(/local HUD_DESIGN_W, HUD_DESIGN_H = \d+, (\d+)/, 900);
const ITEM_ICON = num(/local ITEM_ICON = (\d+)/, 74);
const DRIFT_MAX = num(/local DRIFT_MAX = ([\d.]+)/, 2.5);
const CTRL_W = num(/local CTRL_W, CTRL_GAP = (\d+), \d+/, 68);
const CTRL_GAP = num(/local CTRL_W, CTRL_GAP = \d+, (\d+)/, 6);

/** Mirrors RaceUI:LayoutHud. */
function scale(W, H) {
  return Math.min(Math.max(Math.min(W / DESIGN_W, H / DESIGN_H), 0.60), 1.70);
}

const GOLD = [1, .82, .25], MUTED = [.58, .64, .74], PALE = [.95, .96, 1];
const LIME = [.55, .95, .45], DIMGOLD = [.72, .62, .40], ICE = [.9, .92, 1];

/**
 * Every HUD element as a screen-space rectangle, worst case.
 *
 * "Worst case" is the point: the strings below are the LONGEST each readout can
 * ever show -- ten racers is impossible so "8TH" is the widest place, but a lap
 * time genuinely can reach "LAP 9:59.99  BEST 9:59.99", and Netherstorm's
 * shortcut really is that sentence. Checking the layout against typical content
 * is how a HUD ships looking fine and then eats itself on one track.
 */
function rects(W, H) {
  const s = scale(W, H), u = n => n * s, HW = W / 2;
  const out = [];
  const put = (name, kind, x, y, w, h, extra) =>
    out.push(Object.assign({ name, kind, x, y, w, h }, extra || {}));

  /** Resolve a HUD table entry to a top-left screen box. */
  const box = key => {
    const e = HUD[key], w = u(e.w), h = u(e.h), p = e.point;
    const x = p.includes("LEFT") ? u(e.x) : p.includes("RIGHT") ? W + u(e.x) - w : HW + u(e.x) - w / 2;
    const y = p.startsWith("TOP") ? -u(e.y) : p.startsWith("BOTTOM") ? H - u(e.y) - h : H / 2 - u(e.y) - h / 2;
    return { x, y, w, h };
  };
  /** A text row, placed by which of its own edges the coordinate names. */
  // `outside` marks a row that is deliberately anchored beyond its own panel --
  // the drift tier name sits above the meter, on driftPanel's TOP edge -- so the
  // containment check does not report it as spilling out of a box it was never
  // meant to be in.
  const text = (name, str, x, y, size, color, ax, ay, outside) => {
    const w = textWidth(str, size), h = textHeight(size);
    const px = ax === "RIGHT" ? x - w : ax === "CENTER" ? x - w / 2 : x;
    const py = ay === "BOTTOM" ? y - h : ay === "CENTER" ? y - h / 2 : y;
    put(name, "text", px, py, w, h, { text: str, size, color, outside: !!outside });
    return { x: px, y: py, w, h };
  };

  const lap = box("lap");
  put("lap.panel", "panel", lap.x, lap.y, lap.w, lap.h);
  text("lap.title", "LAP", lap.x + u(14), lap.y + u(9), u(12), GOLD, "LEFT", "TOP");
  text("lap.count", "3 / 3", lap.x + u(52), lap.y + u(6), u(27), PALE, "LEFT", "TOP");
  put("lap.pips", "pips", lap.x + u(14), lap.y + lap.h - u(16), u(4 * 34 + 30), u(5),
    { count: 5, pitch: u(34), each: u(30) });

  const item = box("item");
  put("item.panel", "panel", item.x, item.y, item.w, item.h);
  put("item.icon", "icon", item.x + (item.w - u(ITEM_ICON)) / 2,
    item.y + item.h / 2 - u(ITEM_ICON) / 2 - u(7), u(ITEM_ICON), u(ITEM_ICON));
  text("item.count", "X3", item.x + item.w / 2, item.y + item.h - u(9), u(12), GOLD, "CENTER", "BOTTOM");

  const clock = box("clock");
  put("clock.panel", "panel", clock.x, clock.y, clock.w, clock.h);
  const right = clock.x + clock.w - u(14);
  text("clock.timer", "59:59.999", right, clock.y + u(8), u(22), PALE, "RIGHT", "TOP");
  text("clock.split", "LAP 9:59.99  BEST 9:59.99", right, clock.y + u(38), u(11), MUTED, "RIGHT", "TOP");
  text("clock.speed", "188 km/h", right, clock.y + u(56), u(13), LIME, "RIGHT", "TOP");

  const place = HUD.place;
  put("place.glow", "glow", u(place.x - 46), H - u(place.y - 34) - u(place.h), u(place.w), u(place.h));
  text("place.ordinal", "8TH", u(place.x), H - u(place.y + 20), u(58), GOLD, "LEFT", "BOTTOM");
  text("place.of", "/ 8", u(place.x + 3), H - u(place.y), u(14), MUTED, "LEFT", "BOTTOM");

  text("status", "OFF ROAD", u(place.x + 3), H - u(place.y - 26), u(15), GOLD, "LEFT", "BOTTOM");

  text("shortcut", "SHORTCUT: Blink through a portal at maximum speed",
    HW, item.y + item.h + u(10), u(12), ICE, "CENTER", "TOP");

  const map = box("map");
  put("map.panel", "panel", map.x, map.y, map.w, map.h);

  const drift = box("drift");
  put("drift.panel", "panel", drift.x, drift.y, drift.w, drift.h);
  text("drift.tier", "SUPER", drift.x + drift.w / 2, drift.y - u(5), u(13), GOLD, "CENTER", "BOTTOM", true);

  const name = text("track.name", "Netherstorm Turbo Circuit  /  ARCANE",
    lap.x + u(3), lap.y + lap.h + u(7), u(13), DIMGOLD, "LEFT", "TOP");
  text("track.section", "THE COLLAPSED SPAN", name.x, name.y + name.h + u(4), u(17), GOLD, "LEFT", "TOP");

  const c = HUD.controls;
  const edge = c.w / 2 - CTRL_W / 2, pitch = CTRL_W + CTRL_GAP;
  const btnY = H - u(c.y) - u(c.h);
  const labels = [[-edge, "LEFT"], [-edge + pitch, "RIGHT"], [edge - pitch * 3, "BRAKE"],
    [edge - pitch * 2, "GAS"], [edge - pitch, "DRIFT"], [edge, "ITEM"]];
  for (const [dx, str] of labels)
    put("control." + str, "button", HW + u(dx) - u(CTRL_W) / 2, btnY, u(CTRL_W), u(c.h), { text: str });
  text("control.hint",
    "W / UP  GAS      S / DOWN  BRAKE      A D  or  LEFT RIGHT  STEER      "
    + "SPACE  DRIFT      SHIFT  ITEM      ESC  PAUSE",
    HW, H - u(8), u(11), MUTED, "CENTER", "BOTTOM");

  const quit = box("quit");
  put("quit", "button", quit.x, quit.y, quit.w, quit.h, { text: "QUIT" });
  return out;
}

module.exports = { HUD, rects, scale, DESIGN_W, DESIGN_H, ITEM_ICON, DRIFT_MAX, CTRL_W, CTRL_GAP,
  COLORS: { GOLD, MUTED, PALE, LIME, DIMGOLD, ICE } };
