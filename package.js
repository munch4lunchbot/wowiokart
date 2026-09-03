// Build the shippable addon zip.
//
// This was a shell one-liner retyped each time: `find . -name '*.lua' -o -name
// '*.tga'`. That is a filter over whatever happens to be in the tree, and the
// moment verify-runtime.lua appeared -- a test harness that loads the whole
// addon under a stubbed WoW API -- the one-liner would have shipped it inside
// the player's client. It would not have loaded, being absent from the .toc,
// but nothing about that is obvious to whoever finds it.
//
// So the zip is built from the .toc itself: exactly the files the addon loads,
// plus the art they reference, plus the manifest. Nothing can slip in.
//
// Run: node package.js [outPath]
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ADDON = __dirname;
const OUT = process.argv[2] || path.join(ADDON, "AzerothKart.zip");
const FOLDER = "kart";               // must match the .toc's own name

const toc = fs.readFileSync(path.join(ADDON, "kart.toc"), "utf8")
  .split(/\r?\n/).map(l => l.trim())
  .filter(l => l && !l.startsWith("#"));

const files = ["kart.toc"];
const missing = [];
for (const entry of toc) {
  const rel = entry.replace(/\\/g, "/");
  if (!fs.existsSync(path.join(ADDON, rel))) { missing.push(rel); continue; }
  files.push(rel);
}
for (const f of fs.readdirSync(path.join(ADDON, "Art")).sort())
  if (f.endsWith(".tga")) files.push("Art/" + f);

// Every texture the Lua asks for has to be in the box.
const referenced = new Set();
for (const rel of files) {
  if (!rel.endsWith(".lua")) continue;
  for (const m of fs.readFileSync(path.join(ADDON, rel), "utf8").matchAll(/([\w-]+\.tga)/g))
    referenced.add(m[1]);
}
const shipped = new Set(files.filter(f => f.startsWith("Art/")).map(f => f.slice(4)));
const absentArt = [...referenced].filter(a => !shipped.has(a));

if (missing.length || absentArt.length) {
  for (const m of missing) console.error("  .toc lists a file that is not on disk: " + m);
  for (const a of absentArt) console.error("  the Lua asks for art that is not in the zip: " + a);
  process.exit(1);
}

const staging = fs.mkdtempSync(path.join(require("os").tmpdir(), "kartpkg-"));
for (const rel of files) {
  const dest = path.join(staging, FOLDER, rel);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(path.join(ADDON, rel), dest);
}
fs.rmSync(OUT, { force: true });
execFileSync("zip", ["-rq", OUT, FOLDER], { cwd: staging });
fs.rmSync(staging, { recursive: true, force: true });

const size = fs.statSync(OUT).size;
console.log("packaged " + files.length + " files -> " + OUT +
  "  (" + (size / 1024).toFixed(0) + " KB)");
console.log("  " + files.filter(f => f.endsWith(".lua")).length + " lua, " +
  files.filter(f => f.endsWith(".tga")).length + " tga, 1 toc");
console.log("  extracts to a single \"" + FOLDER + "\" folder");
