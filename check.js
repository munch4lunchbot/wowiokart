// Static check for the addon.
//
// `--checklevel=Error` alone is not enough: it passes clean on a local that has
// escaped its block, which then reads as a nil global and throws on every
// frame. That is exactly how `edge` shipped. Warning level reports those as
// `undefined-global`, mixed in with the WoW API names that are legitimately
// global, so this filters to the ones that are really leaked locals.
//
//   node check.js
const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const ADDON = __dirname;
const LS = process.env.LUA_LS || "C:/Users/munch/Desktop/CABLAUDELE/tools/lua-ls/bin/lua-language-server.exe";
const logs = fs.mkdtempSync(path.join(os.tmpdir(), "kartcheck-"));

let out = "";
try {
  out = execFileSync(LS, ["--check=" + ADDON, "--checklevel=Warning", "--logpath=" + logs],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
} catch (e) {
  out = (e.stdout || "") + (e.stderr || "");
}
const text = out.replace(new RegExp(String.fromCharCode(27) + "\\[[0-9;]*m", "g"), "");
const lines = text.split("\n");

// Lua stdlib and WoW's own lowercase globals. Anything else lowercase is ours.
const KNOWN = new Set(["bit", "unpack", "table", "string", "math", "ipairs", "pairs",
  "select", "type", "tostring", "tonumber", "pcall", "xpcall", "print", "next",
  "error", "assert", "setmetatable", "getmetatable", "rawget", "rawset", "loadstring",
  "strsplit", "strjoin", "strtrim", "format", "wipe", "date", "time", "tinsert",
  "tremove", "sort", "max", "min", "abs", "floor", "ceil", "random", "hooksecurefunc",
  // Blizzard globals that happen to be UPPER_SNAKE_CASE, which is otherwise
  // this addon's own convention for file constants.
  "SOUNDKIT", "STANDARD_TEXT_FONT", "DEFAULT_CHAT_FRAME"]);

// Naming tells us whose global it is. WoW's are PascalCase (CreateFrame,
// UIParent) or C_-prefixed; ours are lowercase locals or UPPER_SNAKE_CASE
// file constants. So both of those shapes are flagged, and PascalCase is left
// alone -- with the handful of genuinely UPPER_SNAKE Blizzard globals named
// above in KNOWN.
//
// The old rule flagged lowercase only, waving every uppercase name past as
// Blizzard's. That is how `BEND_GAIN` shipped: it was a file constant that got
// replaced by a function, and the one remaining reader kept reading it as a
// nil global -- 28 errors a frame, and this check said PASS.
const isOurs = name => /^[a-z]/.test(name) || /^[A-Z][A-Z0-9_]*$/.test(name);

const errors = [];
const leaks = new Map();
for (let i = 0; i < lines.length; i++) {
  if (/\[Error\]/.test(lines[i])) errors.push(lines[i].trim());
  const m = lines[i].match(/Undefined global .([A-Za-z_][A-Za-z0-9_]*)./);
  if (!m || KNOWN.has(m[1]) || !isOurs(m[1])) continue;
  // The server prints the file:line on the diagnostic's own line, as a path
  // relative to whatever was passed to --check. Matching a leading `kart/`
  // missed it entirely and reported every hit as "?", which turns a useful
  // failure into a scavenger hunt.
  let where = "?";
  for (let j = i; j >= 0 && j > i - 8; j--) {
    const f = lines[j].match(/([\w\\/.-]*\.lua):(\d+)/);
    if (f) { where = f[1] + ":" + f[2]; break; }
  }
  if (!leaks.has(m[1])) leaks.set(m[1], new Set());
  leaks.get(m[1]).add(where);
}

// Button labels that will not fit their button.
//
// "BRAKE" and "RIGHT" shipped on 52px buttons and rendered as "BRA..." and
// "RIG..." -- the two most important controls on screen, unreadable, for
// however many sessions. Truncation is silent at runtime, so it needs catching
// here. UI:NewButton draws at font 15 OUTLINE and the skin eats ~10px of
// padding; uppercase glyphs run about 8.6px at that size, lower case ~7.4px.
const tooNarrow = [];
(function scanButtons(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "Art" || e.name === "node_modules") continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) { scanButtons(full); continue; }
    if (!e.name.endsWith(".lua")) continue;
    fs.readFileSync(full, "utf8").split(/\r?\n/).forEach((line, i) => {
      const m = line.match(/NewButton\(\s*[\w.[\]]+\s*,\s*"([^"]+)"\s*,\s*(\d+)\s*,/);
      if (!m) return;
      // A line that shrinks its own font is opting out of the default metrics.
      if (/SetFont/.test(line)) return;
      const text = m[1], width = +m[2];
      // Calibrated UP after "NEXT SOUND" passed at 104px and still rendered as
      // "NEXT SOU...". The old 8.6 was measured from short labels, where the
      // fixed padding hides an underestimate; over ten characters the per-glyph
      // error compounds past it. A checker that passes a truncated button is
      // worse than no checker, so this errs wide -- a button 10px too generous
      // costs nothing, a silently clipped label costs a bug report.
      // Padding does not scale with the label, so a flat allowance that is right
      // for "NEXT SOUND" is far too harsh on a one-glyph stepper -- the first
      // pass at this flagged every "-" and "+" in the addon, all of which have
      // been fitting fine for months. Short labels get the smaller allowance.
      const perGlyph = /[a-z]/.test(text) ? 8.4 : 9.8;
      const needed = text.length * perGlyph + (text.length <= 2 ? 6 : 14);
      if (needed > width) {
        tooNarrow.push(path.relative(ADDON, full) + ":" + (i + 1) +
          "  \"" + text + "\" needs ~" + Math.ceil(needed) + "px, has " + width);
      }
    });
  }
})(ADDON);

// Widgets that are created and never positioned.
//
// A frame with no SetPoint has no anchor, so WoW gives it no size and it simply
// never appears -- silently, with no error. Every stepper in the tuning panel
// vanished this way when an edit dropped the SetPoint lines, and the panel
// looked fine to every other check. If a local is assigned from UI:NewButton or
// CreateFrame, something in the same file must anchor it.
const unanchored = [];
(function scanAnchors(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "Art" || e.name === "node_modules") continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) { scanAnchors(full); continue; }
    if (!e.name.endsWith(".lua")) continue;
    const src = fs.readFileSync(full, "utf8");
    const lines = src.split(/\r?\n/);
    // COUNTED, not "does this name appear anchored somewhere". Two locals in
    // two scopes routinely share a name -- the tuning panel has a `minus` per
    // value row AND a `minus` per seat row -- so a presence test let a dropped
    // anchor hide behind its namesake. Declared N times means N anchors needed.
    const decls = new Map(), anchors = new Map();
    lines.forEach((line, i) => {
      const d = line.match(/local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:UI:NewButton|CreateFrame)\(/);
      if (d) {
        if (!decls.has(d[1])) decls.set(d[1], []);
        decls.get(d[1]).push(i + 1);
      }
      const p = line.match(/\b([A-Za-z_][A-Za-z0-9_]*)\s*[:.]\s*Set(?:All)?Point\b/);
      if (p) anchors.set(p[1], (anchors.get(p[1]) || 0) + 1);
    });
    for (const [name, at] of decls) {
      // An event-only frame is deliberately invisible -- it exists to receive
      // events or drive OnUpdate, and never needs an anchor.
      if (new RegExp("\\b" + name + "\\s*:\\s*Register(All)?Event\\b").test(src)) continue;
      // Handed to a table field and positioned elsewhere.
      if (new RegExp("=\\s*" + name + "\\s*$", "m").test(src)) continue;
      // Returned by a factory (UI:NewButton builds one and hands it back), so
      // the caller owns where it goes.
      if (new RegExp("return\\s+" + name + "\\b").test(src)) continue;
      const have = anchors.get(name) || 0;
      if (have < at.length) {
        unanchored.push(path.relative(ADDON, full) + ":" + at[at.length - 1] +
          "  '" + name + "' declared " + at.length + "x, positioned " + have + "x");
      }
    }
  }
})(ADDON);

// Every file the .toc lists must exist, and every file on disk must be listed.
const toc = fs.readFileSync(path.join(ADDON, "kart.toc"), "utf8")
  .split(/\r?\n/).map(l => l.trim()).filter(l => l.endsWith(".lua"));
const onDisk = [];
(function walk(dir, rel) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "Art" || e.name === "node_modules") continue;
    const r = rel ? rel + "\\" + e.name : e.name;
    if (e.isDirectory()) walk(path.join(dir, e.name), r);
    else if (e.name.endsWith(".lua")) onDisk.push(r);
  }
})(ADDON, "");
const missing = toc.filter(f => !onDisk.includes(f));
const unlisted = onDisk.filter(f => !toc.includes(f));

// `rel` entries use the .toc's own "\"-joined convention (so they compare
// against it directly), which is not a valid path segment separator on
// non-Windows fs calls -- path.join() there would treat the whole string as
// one literal filename and throw ENOENT. Split on "\" before joining so this
// check runs the same on Windows, Linux and macOS.
const absPath = rel => path.join(ADDON, ...rel.split("\\"));

// --- textures that tile by world position but were never told to REPEAT ------
//
// A SetTexCoord above 1 CLAMPS unless the texture was created with REPEAT
// wrapping, and clamping makes the whole quad sample a single edge pixel. It
// raises no error and draws something, so it is invisible in review: the road,
// the grass and every tunnel wall shipped like this: world-locked V coordinates
// in the hundreds (distance / tile-size) resolving to one pixel. The offline
// preview blits with real tiling, so it looked correct there the whole time.
//
// Heuristic: a SetTexCoord argument containing a division is world-locked, so
// the texture it is called on must have been created asking for tiling.
// Only judge textures whose creation this file actually shows. A texture
// arriving as a function parameter cannot be resolved here, and guessing at it
// produces false alarms (the skyline ridges take one and are correctly REPEAT).
const clamped = [];
for (const rel of onDisk) {
  const src = fs.readFileSync(absPath(rel), "utf8");
  const name = s => s.replace(/^self\./, "");
  // Counted, not just flagged. Sibling tables reuse field names -- the main road
  // strip and the fork road strip are both `road` -- so a single tiled sibling
  // was masking an untiled one. Every creation of a name must be tiled.
  const createdN = new Map(), tiledN = new Map();
  const bump = (map, k) => map.set(k, (map.get(k) || 0) + 1);
  // Line-based: a lazy cross-line match silently mis-anchors and the rule then
  // reports nothing, which is the worst possible failure for a checker.
  for (const line of src.split("\n")) {
    const m = line.match(/([\w.]+)\s*=\s*makeTexture\(/);
    if (!m) continue;
    bump(createdN, name(m[1]));
    if (/,\s*true\s*\)/.test(line)) bump(tiledN, name(m[1]));
  }
  for (const m of src.matchAll(/([\w.]+)\s*=\s*[\w.]+:CreateTexture\(/g)) bump(createdN, name(m[1]));
  for (const m of src.matchAll(/([\w.]+):SetTexture\([^)]*,\s*"REPEAT"/g)) bump(tiledN, name(m[1]));
  const created = new Set(createdN.keys());
  const tiled = new Set([...createdN.keys()].filter(k => (tiledN.get(k) || 0) >= createdN.get(k)));

  // A texcoord is "world-locked" when it divides a distance by a tile size --
  // either inline, or through a local that was computed that way earlier
  // (`local vNear, vFar = previousZ / ROAD_TILE, segZ / ROAD_TILE`). Checking
  // only for an inline "/" missed the road, which is how this shipped.
  const worldLocked = new Set();
  for (const m of src.matchAll(/local\s+([\w\s,]+?)\s*=\s*([^\n]*\/[^\n]*)/g)) {
    if (!/\/\s*[A-Z_]*TILE|\/\s*[\d.]+/.test(m[2])) continue;
    for (const v of m[1].split(",")) worldLocked.add(v.trim());
  }

  for (const m of src.matchAll(/([\w.]+):SetTexCoord\(([^)]*)\)/g)) {
    const [, target, args] = m;
    // Only dotted targets (strip.road, surround.left, self.mountain) can be tied
    // back to a creation. A bare `texture:` is the local inside a factory or a
    // function parameter, and guessing at those is how this rule first produced
    // a false alarm on the skyline ridges, which are correctly REPEAT.
    if (!target.includes(".")) continue;
    const tokens = args.split(/[^\w.]+/).filter(Boolean);
    if (!args.includes("/") && !tokens.some(t => worldLocked.has(t))) continue;
    const field = name(target).split(".").pop();
    if (!created.has(field) && !created.has(name(target))) continue;   // unresolvable
    if (tiled.has(field) || tiled.has(name(target))) continue;
    const line = src.slice(0, m.index).split("\n").length;
    clamped.push(rel + ":" + line + "  " + target + " tiles by world position but was not created with REPEAT");
  }
}

// --- widget methods called on plain tables -----------------------------------
//
// `self.checker` is a LIST of 24 textures, not a texture. Calling :Hide() on the
// table itself throws "attempt to call a nil value" the first time that line
// runs, which may be a rarely-taken branch -- teardown code especially.
const tableCalls = [];
const WIDGET_METHODS = /^(Hide|Show|SetAlpha|SetShown|SetPoint|ClearAllPoints|SetTexture|SetVertexColor|SetText|SetSize|SetWidth|SetHeight|SetTexCoord)$/;
for (const rel of onDisk) {
  const src = fs.readFileSync(absPath(rel), "utf8");
  const plainTables = new Set();
  for (const m of src.matchAll(/self\.(\w+)\s*=\s*\{\s*\}/g)) plainTables.add(m[1]);
  // A field later assigned a real widget is not a plain table.
  for (const m of src.matchAll(/self\.(\w+)\s*=\s*(makeTexture|makeGlow|CreateFrame|UI:New|[\w.]+:CreateTexture)/g)) {
    plainTables.delete(m[1]);
  }
  for (const m of src.matchAll(/self\.(\w+):(\w+)\(/g)) {
    if (!plainTables.has(m[1]) || !WIDGET_METHODS.test(m[2])) continue;
    const line = src.slice(0, m.index).split("\n").length;
    tableCalls.push(rel + ":" + line + "  self." + m[1] + ":" + m[2] + "() -- that field is a plain table, not a widget");
  }
}

// --- lap-relative distances handed to an absolute-space function -------------
//
// RaceUI:Bend measures from `bendFrom = camZ`, an ABSOLUTE distance that keeps
// accumulating across laps. Props, objects, hazards and the ghost all store
// LAP-RELATIVE distances (0..length). Passing one to RoadAt/Bend goes hugely
// negative from lap two onward, clamps to t = 0, and silently pins the thing to
// the road's centreline AT THE CAMERA -- it appears off the track at distance
// and only slides into place as you reach it. No error, and it looks almost
// right on lap one, which is why it survived so long.
//
// `dz` is the forward distance from the camera, so `camZ + dz` is the correct
// absolute position. Vehicles and projectiles genuinely carry absolute
// distances and are exempt.
const ABSOLUTE_OK = /^(vehicle|projectile|other|first|second)$/;
const lapRelative = [];
for (const rel of onDisk) {
  const src = fs.readFileSync(absPath(rel), "utf8");
  for (const m of src.matchAll(/:(?:RoadAt|Bend)\([^)]*?(\w+)\.distance\s*[,)]/g)) {
    if (ABSOLUTE_OK.test(m[1])) continue;
    const line = src.slice(0, m.index).split("\n").length;
    lapRelative.push(rel + ":" + line + "  " + m[1] +
      ".distance is lap-relative; Bend measures from an absolute camZ (use camZ + dz)");
  }
}

// --- achievements that can never be earned ----------------------------------
//
// "That's Mine!" (late_pass) sat in Data/Achievements.lua for the addon's whole
// life with no code path anywhere that called UnlockAchievement for it. It had
// a name, a description and a slot on the list, and it was simply impossible --
// which is worse than not shipping it, because the player can see it.
//
// Nothing about that is visible at runtime: an achievement that never fires
// looks exactly like one you have not earned yet.
const orphanAchievements = [];
{
  const file = path.join(ADDON, "Data", "Achievements.lua");
  if (fs.existsSync(file)) {
    const src = fs.readFileSync(file, "utf8");
    // Keys are one indent inside `AK.Achievements = {`.
    const ids = [...src.matchAll(/^\s{2}(\w+)\s*=\s*\{/gm)].map(m => m[1]);
    const everything = onDisk.map(rel => fs.readFileSync(absPath(rel), "utf8")).join("\n");
    // The trophy room draws from AK.AchievementOrder, not from the map, because
    // pairs() has no order. An achievement missing from that list is earnable
    // but never shown, which is the same invisibility bug wearing a hat.
    const orderBlock = (src.match(/AK\.AchievementOrder\s*=\s*\{([\s\S]*?)\}/) || [, ""])[1];
    const ordered = new Set([...orderBlock.matchAll(/"(\w+)"/g)].map(m => m[1]));
    for (const id of ids) {
      if (!new RegExp('UnlockAchievement\\(\\s*"' + id + '"').test(everything)) {
        orphanAchievements.push(id + "  -- defined, but nothing ever unlocks it");
      } else if (ordered.size && !ordered.has(id)) {
        orphanAchievements.push(id + "  -- earnable, but missing from AK.AchievementOrder so it never shows");
      }
    }
  }
}

// --- world renderers that forget the off-axis fade ---------------------------
//
// The bend model integrates curvature twice, so the road's screen offset grows
// quadratically with depth -- measured, it is already past the screen edge by
// 80m on every track. Anything DISCRETE standing out there therefore appears at
// the edge of the display and travels inward as you close, which is the
// "everything slides in from the side" complaint.
//
// EdgeFade is the answer, and it was applied to pickups, props and hazards
// only. Posts (a pair every few metres, out to 0.8 of the draw distance),
// arches, the finish gantry, spectators, the ghost, shells and the other KARTS
// were all still drawn hard at whatever off-axis position they landed on. That
// is not a thing to fix once: it is a rule every world renderer has to follow,
// so it is checked.
//
// The exemptions are the CONTINUOUS surfaces -- a road ribbon swinging off the
// side of the screen reads as a road going round a bend, which is correct and
// wanted -- plus the backdrop and screen-space effects.
const FADE_EXEMPT = /^(RenderRoad|RenderSky|RenderSurround|RenderFork|RenderWeather)$/;
const unfaded = [];
{
  const file = path.join(ADDON, "UI", "RaceUI.lua");
  if (fs.existsSync(file)) {
    const src = fs.readFileSync(file, "utf8");
    const bounds = [...src.matchAll(/^function RaceUI:(\w+)\(/gm)];
    for (let i = 0; i < bounds.length; i++) {
      const name = bounds[i][1];
      if (!/^Render/.test(name) || FADE_EXEMPT.test(name)) continue;
      const body = src.slice(bounds[i].index,
        i + 1 < bounds.length ? bounds[i + 1].index : src.length);
      if (/:Project\(/.test(body) && !/:EdgeFade\(/.test(body)) {
        const line = src.slice(0, bounds[i].index).split("\n").length;
        unfaded.push("UI/RaceUI.lua:" + line + "  RaceUI:" + name +
          " projects world positions but never calls EdgeFade -- it will slide in from the screen edge");
      }
    }
  }
}

// --- items missing from AK.ItemOrder ----------------------------------------
//
// ItemOrder is not just the roulette's display order any more: Network.lua puts
// an item on the wire as its index into it. An item absent from the list encodes
// as 0, which decodes as "no item" -- so a shell nobody can see, held by a racer
// who appears to be carrying nothing. It also silently drops out of the pickup
// reel. Both failures are invisible until someone wonders where their item went.
const unorderedItems = [];
{
  const file = path.join(ADDON, "Data", "Items.lua");
  if (fs.existsSync(file)) {
    const src = fs.readFileSync(file, "utf8");
    const itemsBlock = (src.match(/AK\.Items\s*=\s*\{([\s\S]*?)\n\}/) || [, ""])[1];
    const ids = [...itemsBlock.matchAll(/^\s{2}(\w+)\s*=\s*\{/gm)].map(m => m[1]);
    const orderBlock = (src.match(/AK\.ItemOrder\s*=\s*\{([\s\S]*?)\}/) || [, ""])[1];
    const ordered = new Set([...orderBlock.matchAll(/"(\w+)"/g)].map(m => m[1]));
    for (const id of ids) {
      if (!ordered.has(id)) unorderedItems.push(id + "  -- in AK.Items but not AK.ItemOrder");
    }
  }
}

// --- screens authored bigger than the screen ---------------------------------
//
// Every top-level UI in this addon was laid out in absolute pixels against one
// developer's window, and none of them checked what happens on anyone else's.
// UIParent is 1365x768 on a default 16:9 client and 1024x768 on a 4:3 one, so a
// 1120-wide panel hangs off both edges of the second, and a client with the UI
// scale set to 1 on a 4K monitor gets a 3840x2160 UIParent that shrinks the
// same panel to a postage stamp in the middle.
//
// The fix in every case is the same one line -- fit the whole screen with a
// SetScale -- so the rule is simply that a file laying out anything that big
// must contain one. Files that only ever draw INTO a scaled container, or that
// size things against the screen rather than in fixed pixels, are unaffected.
const unscaled = [];
{
  for (const rel of ["UI/MainMenu.lua", "UI/Results.lua", "UI/Workshop.lua",
                     "UI/RaceUI.lua", "UI/SoundEditor.lua"]) {
    const file = path.join(ADDON, rel);
    if (!fs.existsSync(file)) continue;
    const src = fs.readFileSync(file, "utf8");
    // The widest literal size or layout constant this file lays out with.
    let widest = 0;
    for (const m of src.matchAll(/SetSize\((\d{3,}),\s*(\d{2,})\)/g))
      widest = Math.max(widest, +m[1]);
    for (const m of src.matchAll(/^local \w*(?:WIDTH|_W)\w*,\s*\w+ = (\d{3,}),/gm))
      widest = Math.max(widest, +m[1]);
    if (widest >= 1000 && !/:SetScale\(/.test(src))
      unscaled.push(rel + "  lays out " + widest + "px wide with no SetScale -- " +
        "it will not fit a 4:3 client and will shrink to a card on a 4K one");
  }
}

console.log("files: " + toc.length + " listed, " + onDisk.length + " on disk");
if (missing.length) console.log("  MISSING (in toc, not on disk): " + missing.join(", "));
if (unlisted.length) console.log("  UNLISTED (on disk, not loaded): " + unlisted.join(", "));
console.log("syntax errors: " + errors.length);
for (const e of errors.slice(0, 20)) console.log("  " + e);
console.log("leaked locals: " + leaks.size);
for (const [name, where] of leaks) console.log("  " + name + " -> " + [...where].join(", "));
console.log("truncated button labels: " + tooNarrow.length);
for (const t of tooNarrow) console.log("  " + t);
console.log("unpositioned widgets: " + unanchored.length);
for (const u of unanchored) console.log("  " + u);
console.log("clamped tiling textures: " + clamped.length);
for (const c of clamped) console.log("  " + c);
console.log("widget calls on plain tables: " + tableCalls.length);
for (const t of tableCalls) console.log("  " + t);
console.log("lap-relative distances in absolute space: " + lapRelative.length);
for (const l of lapRelative) console.log("  " + l);
console.log("unearnable achievements: " + orphanAchievements.length);
for (const a of orphanAchievements) console.log("  " + a);
console.log("items missing from ItemOrder: " + unorderedItems.length);
for (const i of unorderedItems) console.log("  " + i);
console.log("world renderers without an edge fade: " + unfaded.length);
for (const u of unfaded) console.log("  " + u);
console.log("screens that never fit themselves to the client: " + unscaled.length);
for (const u of unscaled) console.log("  " + u);

const bad = errors.length + leaks.size + missing.length + unlisted.length
  + tooNarrow.length + unanchored.length + clamped.length + tableCalls.length
  + lapRelative.length + orphanAchievements.length + unorderedItems.length
  + unfaded.length + unscaled.length;
console.log(bad ? "FAIL" : "PASS");
process.exit(bad ? 1 : 0);
