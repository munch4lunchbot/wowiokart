// Build every texture, in order, then check the result.
//
// There was no runner: the generators were invoked by hand. Two of them wrote
// road.tga and grass.tga, at different sizes and with different levelling, so
// which road the game shipped with depended on which file happened to run last.
// Running generate-art.js on its own silently replaced a levelled 256px road
// with a flat 128px one. The duplicates are gone and this is the entry point.
//
// Run: node Art/build-art.js [artDir]
const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const OUT = process.argv[2] || path.join(__dirname, "..", "Art");
const HERE = __dirname;

// Order matters only in that the checks run last; no file is written twice.
const GENERATORS = [
  "generate-art.js",
  "generate-art-ground.js",
  "generate-art-skyline.js",
  "generate-art-tunnel.js",
  "generate-art-track.js",
  "generate-art-effects.js",
  "generate-art-fork.js",
  "generate-art-oribos.js",
  "generate-art-items.js",
  "generate-art-kart.js",
];

for (const g of GENERATORS) {
  const file = path.join(HERE, g);
  if (!fs.existsSync(file)) { console.log("skip (missing) " + g); continue; }
  process.stdout.write("--- " + g + "\n");
  execFileSync(process.execPath, [file, OUT], { stdio: "inherit" });
}

console.log("");
for (const check of ["verify-textures.js", "verify-karts.js"]) {
  const file = path.join(HERE, check);
  if (!fs.existsSync(file)) continue;
  execFileSync(process.execPath, [file, OUT], { stdio: "inherit" });
}
