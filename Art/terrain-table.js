// Read Data/Terrain.lua's material table.
//
// Split into per-material BLOCKS rather than scanned with a fixed-size window
// after each id. The window version broke the first time a material grew a
// comment longer than it: the tint was still there, the regex just could not
// reach it any more, and the check went quietly green on a real defect.
const fs = require("fs");
const path = require("path");

function readTerrain(addonDir) {
  const src = fs.readFileSync(path.join(addonDir, "Data", "Terrain.lua"), "utf8");
  const table = src.slice(src.indexOf("Terrain.TYPES = {"));
  const out = {};
  const heads = [...table.matchAll(/^  (\w+) = \{$/gm)];
  for (let i = 0; i < heads.length; i++) {
    const body = table.slice(heads[i].index,
      i + 1 < heads.length ? heads[i + 1].index : table.length);
    const tint = body.match(/tint = \{ ([\d.]+), ([\d.]+), ([\d.]+) \}/);
    const num = k => { const m = body.match(new RegExp(k + " = ([\\d.]+)")); return m ? +m[1] : 1; };
    out[heads[i][1]] = {
      id: heads[i][1],
      tint: tint ? [+tint[1], +tint[2], +tint[3]] : null,
      speed: num("speed"), steering: num("steering"), traction: num("traction"),
    };
  }
  return out;
}

module.exports = { readTerrain };
