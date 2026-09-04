// Offline renderer harness. Runs the exact projection and draw order from
// UI/RaceUI.lua against the exact shipped TGAs, and writes a PNG -- so the
// scene can actually be looked at without a WoW client in the loop.
//
//   node render.js <artDir> <outPng> [distance]
const fs = require("fs"), zlib = require("zlib"), path = require("path");

const ART = process.argv[2], OUT = process.argv[3];
const PLAYER_DIST = parseFloat(process.argv[4] || "300");
// The projection scales with half-width, so a preview rendered at a different
// resolution than the player's client genuinely does not match their game --
// which is exactly how "your screenshots don't look like mine" happens.
const W = +(process.env.W || 1280), H = +(process.env.H || 720), HW = W / 2, HH = H / 2;

// ---------- framebuffer ----------
const fb = new Float32Array(W * H * 3);
function blend(x, y, r, g, b, a) {
  if (a <= 0 || x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 3, m = a > 1 ? 1 : a;
  fb[i] += (r - fb[i]) * m; fb[i + 1] += (g - fb[i + 1]) * m; fb[i + 2] += (b - fb[i + 2]) * m;
}
function add(x, y, r, g, b, a) {
  if (a <= 0 || x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 3;
  fb[i] += r * a; fb[i + 1] += g * a; fb[i + 2] += b * a;
}
function rect(x0, y0, w, h, r, g, b, a = 1) {
  const xs = Math.max(0, Math.round(x0)), xe = Math.min(W, Math.round(x0 + w));
  const ys = Math.max(0, Math.round(y0)), ye = Math.min(H, Math.round(y0 + h));
  for (let y = ys; y < ye; y++) for (let x = xs; x < xe; x++) blend(x, y, r, g, b, a);
}

// ---------- TGA loading ----------
function loadTGA(name) {
  const b = fs.readFileSync(path.join(ART, name));
  const w = b.readUInt16LE(12), h = b.readUInt16LE(14), off = 18 + b[0];
  const px = new Float32Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    px[i * 4] = b[off + i * 4 + 2] / 255;
    px[i * 4 + 1] = b[off + i * 4 + 1] / 255;
    px[i * 4 + 2] = b[off + i * 4] / 255;
    px[i * 4 + 3] = b[off + i * 4 + 3] / 255;
  }
  return { w, h, px };
}
const tex = {};
for (const f of fs.readdirSync(ART).filter(f => f.endsWith(".tga"))) tex[f.replace(".tga", "")] = loadTGA(f);

function sample(t, u, v) {
  let x = Math.floor(((u % 1) + 1) % 1 * t.w), y = Math.floor(((v % 1) + 1) % 1 * t.h);
  if (x >= t.w) x = t.w - 1; if (y >= t.h) y = t.h - 1;
  const i = (y * t.w + x) * 4;
  return [t.px[i], t.px[i + 1], t.px[i + 2], t.px[i + 3]];
}
/** Textured axis-aligned quad with explicit UV range. */
function blit(t, x0, y0, w, h, u0, u1, v0, v1, tint, alpha = 1, mode = "blend") {
  const xs = Math.max(0, Math.round(x0)), xe = Math.min(W, Math.round(x0 + w));
  const ys = Math.max(0, Math.round(y0)), ye = Math.min(H, Math.round(y0 + h));
  if (xe <= xs || ye <= ys) return;
  for (let y = ys; y < ye; y++) {
    const fy = (y - y0) / h, v = v0 + (v1 - v0) * fy;
    for (let x = xs; x < xe; x++) {
      const fx = (x - x0) / w, u = u0 + (u1 - u0) * fx;
      const [r, g, b, a] = sample(t, u, v);
      if (a <= 0.002) continue;
      const rr = r * Math.min(1, tint[0]), gg = g * Math.min(1, tint[1]), bb = b * Math.min(1, tint[2]);
      if (mode === "add") add(x, y, rr, gg, bb, a * alpha);
      else blend(x, y, rr, gg, bb, a * alpha);
    }
  }
}

// ---------- the addon's constants ----------
//
// Read straight out of Tuning.lua rather than copied. A hand-maintained copy
// drifts the moment a default changes, and then the preview faithfully renders
// a game nobody is playing -- which is worse than having no preview at all.
//
// TUNE="camHeight=6.2,roadHalf=7" overrides individual values, so whatever
// `/kart tune` -> PRINT CHANGES reports can be pasted in to reproduce exactly
// what the player is looking at.
const T = (function () {
  const src = fs.readFileSync(path.join(__dirname, "..", "Tuning.lua"), "utf8");
  const out = {};
  for (const m of src.matchAll(/key = "(\w+)"[^}]*?default = (-?[\d.]+)/g)) out[m[1]] = +m[2];
  for (const pair of (process.env.TUNE || "").split(",")) {
    const [k, v] = pair.split("=");
    if (k && v !== undefined && !Number.isNaN(+v)) out[k.trim()] = +v;
  }
  return out;
})();
// Overridable so a value can be swept and measured rather than argued about.
const SEGMENTS = +(process.env.SEGMENTS || 150), FAR_Z = +(process.env.FAR_Z || T.drawDistance || 560);
// The AIR reaches a fixed distance; only how much of the world you are shown is
// a setting. Mirrors HAZE_Z in UI/RaceUI.lua -- if these two drift, the preview
// starts flattering the game again.
const HAZE_Z = 330;
// Roadside furniture is limited in METRES, not as a fraction of the draw
// distance. Mirrors `reach` in UI/RaceUI.lua.
const furnitureReach = m => Math.min(FAR_Z * 0.9, m);
const MIN_TEXEL = 18;
// Mirrors ROAD_MEAN / GRASS_MEAN in UI/RaceUI.lua -- the baked mean of each
// ground texture, folded in when a strip drops its texture for flat colour.
const ROAD_MEAN = 0.82, GRASS_MEAN = 0.80;
// Mirrors RaceUI:Aerial -- a lit colour blended toward the air, not multiplied
// toward black. Filled in once the haze colour is known (it depends on the
// track's own palette and light), and used by every trackside renderer below.
let AERIAL = null;
const aerialAt = (c, lit, dz) => {
  if (!AERIAL) return c.map(v => v * lit);
  const mix = AERIAL.cap * Math.pow(clamp(dz / HAZE_Z, 0, 1), 0.85);
  return c.map((v, k) => { const t = v * lit; return t + (AERIAL.haze[k] - t) * mix; });
};
const { drawText } = require("./hud-font.js");
const STRIPE = 4.5, CURVE_SCALE = +(process.env.CS || 30);
// NONORM=1 drops the global peak-fit in the compile, so authored curvature
// keeps its absolute size and a hairpin stays a hairpin regardless of what else
// is on the lap.
const NONORM = !!process.env.NONORM;
const ROAD_TILE = 4.2, GRASS_TILE = 3.0, TREES = 44;
const TRACK_ID = process.env.TRACK || "oribos";
// Mirrors UI/RaceUI.lua's kartArt lookup: one body texture per kart id, with
// the generic body as the fallback. KART= picks the player's; the rest of the
// field is given different karts so a render shows the whole fleet at once.
const KART_ID = process.env.KART || "mechano";
const kartTex = id => tex["kart-" + id] || tex.kart;
// Kart body colour comes from Data/Karts.lua, exactly as the addon does
// (vehicle.kart.color). Hard-coded preview colours meant a red rocket rendered
// blue here, so accent hues were being judged against a tint the game never
// applies -- every accent is MULTIPLIED by this, so it can shift hue badly.
const KART_COLOR = (function () {
  const src = fs.readFileSync(path.join(__dirname, "..", "Data", "Karts.lua"), "utf8");
  const out = {};
  for (const m of src.matchAll(/id = "(\w+)"[^}]*?color = \{ ([\d.]+), ([\d.]+), ([\d.]+) \}/g))
    out[m[1]] = [+m[2], +m[3], +m[4]];
  return out;
})();
const kartCol = id => KART_COLOR[id] || [0.8, 0.8, 0.8];
const track = (function () {
  const src = fs.readFileSync(path.join(__dirname, "..", "Data", "Tracks.lua"), "utf8");
  const starts = [];
  const re = /\n  \{\n    id = "(\w+)"/g;
  let m; while ((m = re.exec(src))) starts.push({ id: m[1], at: m.index });
  const i = starts.findIndex(x => x.id === TRACK_ID);
  if (i === -1) throw new Error("no track " + TRACK_ID);
  const body = src.slice(starts[i].at, i + 1 < starts.length ? starts[i + 1].at : src.length);
  const num = (re2, d) => { const q = body.match(re2); return q ? +q[1] : d; };
  const triple = key => {
    const q = body.match(new RegExp(key + " = \\{ ([\\d.]+), ([\\d.]+), ([\\d.]+) \\}"));
    return q ? [+q[1], +q[2], +q[3]] : [1, 1, 1];
  };
  //--- BRANCHES. Same shape as the main route, one indent deeper, and each one
  //--- carries where it leaves the lap and which side it leaves from.
  const branches = [];
  {
    const bs = body.indexOf("branches = {");
    if (bs !== -1) {
      const be = body.indexOf("\n    },", bs);
      const block = body.slice(bs, be === -1 ? body.length : be);
      const re2 = /\n      \{\n        id = "(\w+)"/g;
      const heads = [];
      let bm; while ((bm = re2.exec(block))) heads.push({ id: bm[1], at: bm.index });
      heads.forEach((head, k) => {
        const chunk = block.slice(head.at, k + 1 < heads.length ? heads[k + 1].at : block.length);
        const pick = (re3, d) => { const q = chunk.match(re3); return q ? +q[1] : d; };
        const ls2 = chunk.indexOf("layout = {");
        if (ls2 === -1) return;
        branches.push({
          id: head.id,
          name: (chunk.match(/name = "([^"]+)"/) || [, head.id])[1],
          side: pick(/side = (-?\d+)/, -1),
          from: pick(/from = ([\d.]+)/, 0), to: pick(/to = ([\d.]+)/, 0),
          length: pick(/length = (\d+)/, 250),
          // Builder:CompileBranches defaults a branch's sweep to 1.6.
          sweep: pick(/sweep = ([\d.]+)/, 1.6),
          layout: [...chunk.slice(ls2).matchAll(/\{ len = ([\d.]+),([^}]*)\}/g)].map(x => ({
            len: +x[1],
            curve: +(x[2].match(/curve = (-?[\d.]+)/) || [, 0])[1],
            grade: +(x[2].match(/grade = (-?[\d.]+)/) || [, 0])[1],
            width: +(x[2].match(/width = ([\d.]+)/) || [, 1])[1],
            ramp: /ramp = true/.test(x[2]),
            tunnel: /tunnel = true/.test(x[2]),
            name: (x[2].match(/name = "([^"]+)"/) || [, ""])[1],
          })),
        });
      });
    }
  }
  const ls = body.indexOf("layout = {"), le = body.indexOf("\n    },", ls);
  const layout = [...body.slice(ls, le).matchAll(/\{ len = ([\d.]+),([^}]*)\}/g)].map(x => ({
    len: +x[1],
    curve: +(x[2].match(/curve = (-?[\d.]+)/) || [, 0])[1],
    grade: +(x[2].match(/grade = (-?[\d.]+)/) || [, 0])[1],
    width: +(x[2].match(/width = ([\d.]+)/) || [, 1])[1],
    ramp: /ramp = true/.test(x[2]),
    tunnel: /tunnel = true/.test(x[2]),
    name: (x[2].match(/name = "([^"]+)"/) || [, ""])[1],
  }));
  return {
    name: (body.match(/name = "([^"]+)"/) || [, "Unnamed Circuit"])[1],
    theme: (body.match(/theme = "([^"]+)"/) || [, ""])[1],
    shortcut: (body.match(/shortcut = "([^"]+)"/) || [, ""])[1],
    length: num(/length = (\d+), laps/, 2600), color: triple("color"), road: triple("road"),
    skyTop: triple("skyTop"), skyLow: triple("skyLow"), glow: triple("glow"),
    light: num(/light = ([\d.]+)/, 1), archSpacing: num(/archSpacing = (\d+)/, 0),
    style: (body.match(/style = "(\w+)"/) || [, null])[1],
    sweep: num(/sweep = ([\d.]+)/, 2.6), layout,
    _painted: [...body.matchAll(/\{ from = (\d+), to = (\d+), onRoad = "(\w+)" \}/g)]
      .map(x => ({ from: +x[1], to: +x[2], mat: x[3] })),
    _branches: branches,
  };
})();
// Compile the layout exactly as TrackBuilder does.
//
// A ROUTE, not "the track". Builder:CompileBranches puts a branch through this
// same pipeline because a branch simply IS a small track, and this sheet has to
// be able to do the same or the fork ribbon -- the one part of the scene with
// no offline eye on it at all, and the part the last round of reports was
// about -- stays unpreviewable.
function compile(track){
  const STEP=2,CG=0.0021,GG=0.022;
  const authored=track.layout.reduce((s,p)=>s+p.len,0), scale=track.length/authored;
  const N=Math.floor(track.length/STEP)+1;
  let c=[],h=[],wr=[],cv=[],ramps=[],tuns=[],heading=0,x=0,y=0,cur=0,pi=0,left=track.layout[0].len*scale,rf=null,tf=null;
  for(let i=0;i<N;i++){const pc=track.layout[pi];
    heading+=(pc.curve||0)*CG*STEP; x+=heading*STEP; y+=(pc.grade||0)*GG*STEP;
    c.push(x);h.push(y);wr.push(pc.width||1);cv.push(pc.curve||0);
    if(pc.ramp&&rf===null)rf=cur; else if(rf!==null&&!pc.ramp){ramps.push([rf,cur]);rf=null;}
    if(pc.tunnel&&tf===null)tf=cur; else if(tf!==null&&!pc.tunnel){tuns.push([tf,cur]);tf=null;}
    cur+=STEP;left-=STEP;while(left<=0&&pi<track.layout.length-1){pi++;left+=track.layout[pi].len*scale;}}
  if(rf!==null)ramps.push([rf,cur]);
  if(tf!==null)tuns.push([tf,cur]);
  track._tuns=tuns;
  const dx=c[N-1]-c[0],dy=h[N-1]-h[0];
  for(let i=0;i<N;i++){const t=i/(N-1);c[i]-=dx*t;h[i]-=dy*t;}
  const mn=Math.min(...c),mx=Math.max(...c),mid=(mn+mx)/2;
  let peak=0;for(let i=0;i<N;i++){c[i]-=mid;peak=Math.max(peak,Math.abs(c[i]));}
  track._rawPeak=peak;
  if(!NONORM){const f=track.sweep/peak;for(let i=0;i<N;i++)c[i]*=f;}
  let w=[];for(let i=0;i<N;i++){let t=0,n=0;for(let k=-15;k<=15;k++){t+=wr[((i+k)%N+N)%N];n++;}w.push(t/n);}
  let cs=[];for(let i=0;i<N;i++){let t=0,n=0;for(let k=-15;k<=15;k++){t+=cv[((i+k)%N+N)%N];n++;}cs.push(t/n);}
  track._w=w;track._c=c;track._h=h;track._cv=cs;track._ramps=ramps;track._N=N;track._STEP=STEP;
  return track;
}
compile(track);
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const roadCenter = d => { const i=Math.floor((((d%track.length)+track.length)%track.length)/track._STEP)%track._N; return track._c[i]*CURVE_SCALE; };
const roadHeight = d => { const i=Math.floor((((d%track.length)+track.length)%track.length)/track._STEP)%track._N; return track._h[i]; };
const roadWidth = d => { const i=Math.floor((((d%track.length)+track.length)%track.length)/track._STEP)%track._N; return track._w[i]; };
// Authored corner tightness, the same table the physics steers by.
const curveAt = d => { const i=Math.floor((((d%track.length)+track.length)%track.length)/track._STEP)%track._N; return track._cv[i]; };
const tunnelDepth = d => {
  const z = ((d % track.length) + track.length) % track.length;
  for (const [a, b] of track._tuns) {
    if (z >= a && z <= b) return clamp(Math.min(z - a, b - z) / 14, 0, 1);
  }
  return 0;
};
const TUNNEL_HEIGHT = 7.5, TUNNEL_TILE = 5.0;
const shade = (c, f) => [c[0] * f, c[1] * f, c[2] * f];
// Mirrors RaceUI:RenderRoad -- lift the verge toward its own luminance rather
// than by a per-channel multiply, which brightens by saturating.
const grassLum = track.color[0]*0.30 + track.color[1]*0.59 + track.color[2]*0.11;
const verge = (() => {
  const v = track.color.map(c => (c * 0.58 + grassLum * 0.42) * 2.15 + .05);
  // Scaled, not clamped: SetVertexColor clamps per channel, which changes hue.
  const peak = Math.max(...v);
  return peak > 1 ? v.map(c => c / peak) : v;
})();

// Addon anchors from frame CENTRE with +y up; the framebuffer is +y down.
const SX = x => HW + x, SY = y => HH - y;

const YAW_ON = process.argv[5] !== "noyaw";

// ---------- FEEL: the canonical game-feel moments ----------
//
// FEEL=drift1|drift2|drift3|boost|impact|landing renders the frame as it looks
// at the PEAK of that reaction, so each one can be A/B'd against FEEL unset.
// These mirror the impulse values in RaceUI (RaceUI:Feel / :FeelHit /
// :FeelLanding / :DriftRelease) -- the point of the harness is that a change to
// those numbers shows up here as a picture, not as a number nobody can picture.
const FEEL = (process.env.FEEL || "").toLowerCase();
const DRIFT_HUE = { 1: [0.30, 0.70, 1.00], 2: [1.00, 0.58, 0.10], 3: [0.72, 0.42, 1.00] };
const feel = { push: 0, dip: 0, lean: 0, kickX: 0, lens: 0, tier: 0, boosting: false };
if (FEEL === "boost") { feel.push = 2.6; feel.lens = T.boostFov; feel.boosting = true; }
else if (FEEL === "landing") { feel.dip = 1.5; }
else if (FEEL === "impact") { feel.kickX = -36.4; feel.dip = 0.77; }
else if (/^drift[123]$/.test(FEEL)) {
  feel.tier = +FEEL.slice(5);
  // Lean is charge/1.8 clamped, so tier 3 is full lean.
  feel.lean = Math.min(1, [0, 0.35, 0.9, 1.8][feel.tier] / 1.8);
}

const camZ = PLAYER_DIST - (T.camBack + feel.push);
const camY = roadHeight(camZ) + T.camHeight - feel.dip;
const light = track.light * T.nightBoost;

// Where the road sits on screen, measured forward from the kart.
//
// The old path projected the road's ABSOLUTE world position and subtracted the
// camera's. That forces the centreline to stay within a few units of the camera
// axis or the small-angle projection falls apart -- which is exactly why Compile
// renormalises the whole lap down to `sweep`, and exactly why every corner came
// out flat. Worse, the normalisation divides by the lap's global peak, so a
// track with more corners has each of them squashed harder.
//
// Classic pseudo-3D does not track world position at all. The kart is the
// origin, and curvature is integrated FORWARD from it: each step ahead adds to a
// running lateral velocity, which adds to a running offset. A hairpin then bends
// the road by the same amount no matter what else is on the lap, and the road
// may bend arbitrarily far ahead without breaking the projection -- because
// nothing is ever expressed as an angle from the camera axis.
const BEND_GAIN = +(process.env.BEND || (T.bendGain||10)/1000);
const bend = (() => {
  const step = 2, n = Math.ceil(FAR_Z / step) + 4;
  const off = new Float64Array(n);
  let x = 0, dx = 0;
  for (let i = 0; i < n; i++) {
    off[i] = x;
    const cv = curveAt(camZ + i * step);
    dx += cv * BEND_GAIN * step;
    x += dx * step;
  }
  return dz => {
    const t = clamp(dz, 0, (n - 2) * step) / step;
    const i = Math.floor(t), f = t - i;
    return off[i] + (off[i + 1] - off[i]) * f;
  };
})();

// Distant scenery drifts with where the road is TAKING you, which in the
// forward-accumulated model is simply how far it has bent by the mid-field.
// This is what makes a corner feel like the world rotating around you rather
// than the road sliding sideways underneath a fixed backdrop.
const camX = bend(FAR_Z * 0.55) * 0.06;

// Lens widens on boost (RaceUI lerps camDepth toward camDepth - boostFov), and
// the whole frame shifts on a lean or an impact kick.
const camDepth = T.camDepth - feel.lens;
const feelShiftX = -feel.lean * T.camYaw * 0.20 * camDepth * HW + feel.kickX;

function project(dz, lateral, worldY) {
  const s = camDepth / dz;
  return [s * lateral * HW + feelShiftX, T.horizon - s * (camY - worldY) * HH, s * HW];
}

// PROBE=1 reports how far the road actually walks across the screen between the
// kart and the draw limit, instead of rendering. "Corners feel like straight
// lines" is a measurable claim: if the far end of the road never leaves the
// middle of the screen, there is no corner on screen no matter what the layout
// says. Screen half-width is 640px, so a real bend wants hundreds, not tens.
if (process.env.PROBE) {
  const out = [];
  for (const ahead of [10, 40, 80, 120, 160, 200, 260, 340]) {
    if (ahead > FAR_Z) continue;
    const segZ = camZ + ahead;
    const [x] = project(ahead, bend(ahead), roadHeight(segZ));
    out.push(`${String(ahead).padStart(4)}m  x=${x.toFixed(0).padStart(6)}px`);
  }
  console.log(`${TRACK_ID} @${PLAYER_DIST}m  sweep=${track.sweep} CS=${CURVE_SCALE} FAR_Z=${FAR_Z} rawPeak=${track._rawPeak.toFixed(1)} norm=${NONORM ? "OFF" : "on"}`);
  console.log(out.join("\n"));
  process.exit(0);
}

// ---------- sky ----------
const horizonPx = SY(T.horizon);
for (let y = 0; y < horizonPx; y++) {
  const f = y / Math.max(1, horizonPx);
  const r = track.skyTop[0] + (track.skyLow[0] - track.skyTop[0]) * f;
  const g = track.skyTop[1] + (track.skyLow[1] - track.skyTop[1]) * f;
  const b = track.skyTop[2] + (track.skyLow[2] - track.skyTop[2]) * f;
  for (let x = 0; x < W; x++) blend(x, y, r, g, b, 1);
}
// ring
if (tex.ring) {
  const rs = HW * 1.9;
  blit(tex.ring, SX(-camX * 0.9 - rs / 2), SY(T.horizon - 40) - rs, rs, rs, 0, 1, 0, 1,
    [.72 * light, .66 * light, .86 * light], 0.55);
}
// clouds, sized against the screen rather than in absolute pixels
if (tex.cloud) {
  for (let i = 1; i <= 14; i++) {
    const spread = HW * 3, scale = 0.55 + ((i * 37) % 70) / 70;
    const x = ((i * 263 - camX * 3) % spread + spread) % spread - spread / 2;
    const y = T.horizon + H * 0.08 + ((i * 83) % Math.round(H * 0.38));
    const w = W * 0.20 * scale, h = w * 0.5;
    const tint = [0.55 + track.skyLow[0] * 0.45, 0.55 + track.skyLow[1] * 0.45, 0.58 + track.skyLow[2] * 0.42];
    blit(tex.cloud, SX(x - w / 2), SY(y) - h / 2, w, h, 0, 1, 0, 1, tint, T.cloudAlpha);
  }
}

// ---------- layered distant terrain ----------
// Depth is faked with parallax LAYERS, each tinted toward the sky the further
// back it sits: far ridge (slowest), mid hills, then the near tree wall. One
// row of cones on a hard seam was the strongest "flat cardboard" tell we had.
// Heights are fractions of screen height, never absolute pixels -- absolute
// sizes are how the skyline shrank to nothing on larger client resolutions.
// SKYLINE, PARSED FROM RaceUI.lua RATHER THAN COPIED FROM IT.
//
// It used to be a hand-transcribed duplicate, and a duplicate of authored data
// is a duplicate that drifts: three circuits were added to the game's table and
// never to this one, so a preview of them showed a ridge line the game did not
// draw (or the other way round) and the harness that exists to catch scenery
// faults was itself wearing the wrong scenery.
const SKYLINE = (() => {
  const src = fs.readFileSync(path.join(__dirname, "..", "UI", "RaceUI.lua"), "utf8");
  const table = src.slice(src.indexOf("local SKYLINE = {"));
  const body = table.slice(0, table.indexOf("\n}\n"));
  const out = {};
  const heads = [...body.matchAll(/^  (\w+)\s+= \{/gm)];
  const rgb = (t) => t.split(",").map(Number);
  for (let i = 0; i < heads.length; i++) {
    const chunk = body.slice(heads[i].index,
      i + 1 < heads.length ? heads[i + 1].index : body.length);
    const entry = {};
    for (const layer of ["mtn", "hill"]) {
      const m = chunk.match(new RegExp(layer +
        " = \\{ h = ([\\d.]+), tint = \\{ ([\\d.,\\s]+) \\}(?:, a = ([\\d.]+))?(?:, float = ([\\d.]+))? \\}"));
      if (m) {
        entry[layer] = { h: +m[1], tint: rgb(m[2]) };
        if (m[3] !== undefined) entry[layer].a = +m[3];
        if (m[4] !== undefined) entry[layer].float = +m[4];
      }
    }
    const art = chunk.match(/treeArt = "([\w.]+)"/);
    if (art) entry.treeArt = art[1].replace(".tga", "");
    const tint = chunk.match(/treeTint = \{ ([\d.,\s]+) \}/);
    if (tint) entry.treeTint = rgb(tint[1]);
    out[heads[i][1]] = entry;
  }
  return out;
})();
const skyline = SKYLINE[TRACK_ID] || {};
// One full-width quad per layer, the ridge sliding inside it via texture
// coordinates -- identical to the addon's SetTexCoord scroll.
function ridgeLayer(art, cfg, drift) {
  if (!art || !cfg) return;
  const hgt = H * cfg.h;
  const repeatPx = Math.max(1, hgt * 4); // the art is 4:1
  const u0 = -drift / repeatPx;
  const tint = [cfg.tint[0] * light, cfg.tint[1] * light, cfg.tint[2] * light];
  blit(art, 0, SY(T.horizon + H * (cfg.float || 0)) - hgt, W, hgt,
    u0, u0 + W / repeatPx, 0, 1, tint, cfg.a || 1);
}
ridgeLayer(tex.mountain, skyline.mtn, -camX * 1.1);
ridgeLayer(tex.hills, skyline.hill, -camX * 2.0);

// ground plane with aerial perspective: pale and sky-tinted at the horizon,
// full colour at the bottom edge. Linear, because WoW's SetGradient is linear
// and the preview must not look better than the game can.
{
  const ground = shade(track.color, 0.62 * light);
  const hazeC = [
    (track.skyLow[0] * .5 + track.glow[0] * .5) * light,
    (track.skyLow[1] * .5 + track.glow[1] * .5) * light,
    (track.skyLow[2] * .5 + track.glow[2] * .5) * light];
  for (let y = horizonPx; y < H; y++) {
    const t = (y - horizonPx) / Math.max(1, H - horizonPx);
    const mix = 0.72 * (1 - t);
    const r = ground[0] + (hazeC[0] - ground[0]) * mix;
    const g = ground[1] + (hazeC[1] - ground[1]) * mix;
    const b = ground[2] + (hazeC[2] - ground[2]) * mix;
    for (let x = 0; x < W; x++) blend(x, y, r, g, b, 1);
  }
}

// near tree wall, scaled against the screen and tinted per track
const spirey = track.style === "oribos" || skyline.treeArt === "shard";
const skyArt = track.style === "oribos" ? tex.spire : (skyline.treeArt && tex[skyline.treeArt]) || tex.tree;
if (skyArt) {
  const tt = skyline.treeTint || [.30, .52, .31];
  const spread = HW * 2.4, slice = spread / TREES, drift = -camX * 3.4;
  const jit = (i, a, b) => { const v = Math.sin(i * a) * b; return v - Math.floor(v); };
  // Mirrors RaceUI:RenderSky's treeline: per-slot jitter, continuous depth, and
  // an aerial-perspective wash toward the horizon rather than a darker back row.
  const wash = [
    (track.skyLow[0] * 0.6 + track.glow[0] * 0.4) * light,
    (track.skyLow[1] * 0.6 + track.glow[1] * 0.4) * light,
    (track.skyLow[2] * 0.6 + track.glow[2] * 0.4) * light,
  ];
  for (let i = 1; i <= TREES; i++) {
    const jx = jit(i, 12.9898, 43758.5453) - 0.5;
    const jh = jit(i, 78.2330, 24634.6345);
    const jw = jit(i, 45.1640, 15731.7430);
    const depth = jit(i, 94.6730, 39871.2930);
    const px = i * slice + jx * slice * 0.9 + drift;
    const x = ((px % spread) + spread) % spread - spread / 2;
    const h = (spirey ? (0.085 + jh * 0.240) : (0.034 + jh * 0.105))
      * H * T.treeHeight * (1 - depth * 0.34);
    const w = h * (spirey ? 0.26 : 0.5) * (0.80 + jw * 0.44);
    const tone = (spirey ? .68 : .92) * (1 - depth * 0.12) * light;
    const base = track.style === "oribos" ? [tone * .80, tone * .70, tone * 1.15]
      : [tone * tt[0], tone * tt[1], tone * tt[2]];
    const haze = depth * 0.40;
    const tint = base.map((c, k) => c + (wash[k] - c) * haze);
    blit(skyArt, SX(x - w / 2), SY(T.horizon - H * (0.004 + depth * 0.017)) - h, w, h, 0, 1, 0, 1, tint, 1);
  }
}

// haze band softening the horizon seam
//
// In TWO halves that both fade to nothing at their outer edge. One gradient
// could only run 0 -> peak, so the softener ended in a hard cut of its own at
// 30% opacity -- a pale band ruled straight across the horizon on every track.
{
  const g0 = track.glow;
  const below = Math.round(H * 0.12), above = Math.round(H * 0.05);
  for (let dy = -below; dy <= above; dy++) {
    const t = dy <= 0 ? (dy + below) / below : 1 - dy / above;
    const a = 0.30 * Math.pow(Math.max(0, t), 1.5);
    const yy = SY(T.horizon + dy);
    for (let x = 0; x < W; x++) blend(x, yy, g0[0] * .8, g0[1] * .8, g0[2] * .85, a);
  }
}
// THE ROCK'S HUE, as ApplyTrackPalette derives it: the track's road colour
// lifted halfway to neutral, then normalised to a peak of 1 so the tint carries
// only hue and never a second helping of darkness.
const ROCK_TINT = (() => {
  const road = track.road || [0.4, 0.4, 0.44];
  const mid = (road[0] + road[1] + road[2]) / 3;
  const t = road.map((c) => c * 0.55 + mid * 0.45 + 0.10);
  const peak = Math.max(...t);
  return peak > 0.001 ? t.map((c) => c / peak) : t;
})();

// HOW LIT THE SCENE IS UNDER COVER. Declared here rather than beside the road
// because the surround fill is drawn FIRST and needs the same numbers -- and a
// const read above its declaration is a ReferenceError, not a zero.
const roadCamDepth = tunnelDepth(camZ);
const roadLight = light * (1 - roadCamDepth * 0.48);
// The road takes far less of the cover dimming than the rest of the scene --
// see RaceUI:RenderRoad. Under a shaft the walls carry the dark; the tarmac
// stays the lit ribbon running through it.
const tarmacLight = light * (1 - roadCamDepth * 0.20);

// ---------- surround: rock over the whole frame once actually under cover ----
//
// Mirrors RaceUI:RenderSurround, which this harness did not implement at all.
// The per-band walls draw the tunnel as a portal, which is right on approach;
// once inside, everything the portal does not cover -- outboard of the walls and
// above the ceiling -- is also rock. Without it the preview showed open sky
// above every tunnel roof, which is a defect in the PREVIEW that reads exactly
// like a defect in the game, and a mirror that invents faults is worse than no
// mirror at all.
{
  const depth = tunnelDepth(camZ);
  if (depth > 0 && tex.rock) {
    const tileP = Math.max(64, HH * 0.85);
    // RenderSurround fills from the NEAREST BAND's rock value times 0.42, not
    // from the track's undimmed light. This used to be `0.86 * light`, roughly
    // four times what the game draws, and it is the single reason a preview of
    // Deadmines came back with a handsomely lit shaft while the client showed a
    // black box. A mirror that flatters is worse than no mirror.
    const bandRock = tarmacLight * (0.50 + 0.26 * (1 - depth));
    const band = bandRock * 0.42;
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const t = sample(tex.rock, (x / tileP) % 1, (y / tileP) % 1);
        blend(x, y, t[0] * band * ROCK_TINT[0], t[1] * band * ROCK_TINT[1],
          t[2] * band * ROCK_TINT[2], depth * t[3]);
      }
    }
  }
}

// Painted road surfaces, read from Data/Terrain.lua, so the preview shows the
// ice the player has to be able to see coming.
const PAINT = (() => {
  const table = require("./terrain-table.js").readTerrain(path.join(__dirname, ".."));
  const out = {};
  for (const [id, mat] of Object.entries(table)) if (mat.tint) out[id] = mat.tint;
  return out;
})();

// ---------- road ----------
// Mirrors RaceUI:RenderRoad: under cover the whole scene loses its daylight,
// and every ground surface washes toward the horizon as it recedes rather than
// merely dimming. `fog` alone put no depth cue on the two surfaces that fill
// most of the screen.
/** RaceUI's legibility floor: a dark palette times a dark track times a tunnel
 *  can compound to a road at RGB 13, so the tarmac keeps a minimum value. */
function legible(c, lit) {
  const v = c.map((x) => x * lit);
  const peak = Math.max(...v);
  return (peak > 0.001 && peak < 0.17) ? v.map((x) => x * (0.17 / peak)) : v;
}
const roadHaze = [
  (track.skyLow[0] * 0.58 + track.glow[0] * 0.42) * roadLight,
  (track.skyLow[1] * 0.58 + track.glow[1] * 0.42) * roadLight,
  (track.skyLow[2] * 0.58 + track.glow[2] * 0.42) * roadLight,
];
const hazeCap = clamp(0.62 * T.fogStrength, 0, 0.72) * (1 - roadCamDepth);
const aerial = (c, lit, mix) => c.map((v, k) => {
  const s = v * lit;
  return s + (roadHaze[k] - s) * mix;
});
AERIAL = { haze: roadHaze, cap: hazeCap };

const lift = T.camDepth * T.camHeight * HH;
const nearZ = Math.max(1.2, lift / (T.horizon + HH + 60));
// Split strip budget -- near band in 1/z, far tail in metres. Mirrors
// DETAIL_Z / TAIL_SEGMENTS and the loop in UI/RaceUI.lua:RenderRoad.
const DETAIL_Z = 120, TAIL_SEGMENTS = 22;
const tailCount = FAR_Z > DETAIL_Z * 1.15
  ? Math.min(TAIL_SEGMENTS, Math.floor(SEGMENTS * 0.16)) : 0;
const nearCount = SEGMENTS - tailCount;
const detailZ = tailCount > 0 ? DETAIL_Z : FAR_Z;
const nu = 1 / nearZ, fu = 1 / detailZ, step = (nu - fu) / Math.max(1, nearCount - 1);
const tailStep = tailCount > 0 ? (FAR_Z - detailZ) / tailCount : 0;
const rows = [];
let pX = null, pY = null, pW = null, pZ = null, pCeil = null;
for (let i = 0; i < SEGMENTS; i++) {
  const dz = i < nearCount ? 1 / (nu - i * step) : detailZ + tailStep * (i - nearCount + 1);
  const segZ = camZ + dz;
  const [x, y, ppm] = project(dz, bend(dz), roadHeight(segZ));
  const hwPx = ppm * T.roadHalf * roadWidth(segZ);
  if (pY !== null && y > pY) {
    rows.push({ y: pY, h: Math.max(1, y - pY), midX: (x + pX) / 2, midHalf: (hwPx + pW) / 2,
      segZ, prevZ: pZ, dz, ppm,
      cover: tunnelDepth(segZ), ceilY: project(dz, bend(dz), roadHeight(segZ) + TUNNEL_HEIGHT)[1],
      prevCeilY: pCeil });
  }
  pX = x; pY = y; pW = hwPx; pZ = segZ; pCeil = project(dz, bend(dz), roadHeight(segZ) + TUNNEL_HEIGHT)[1];
}
// far to near, so crests occlude
for (let r = rows.length - 1; r >= 0; r--) {
  const row = rows[r];
  const fog = clamp(1 - (row.dz / HAZE_Z) * T.fogStrength, .22, 1) * roadLight;
  const mix = hazeCap * Math.pow(clamp(row.dz / HAZE_Z, 0, 1), 0.85);
  const idx = Math.floor(row.segZ / STRIPE), dark = idx % 2 === 0;
  const rz=((row.segZ%track.length)+track.length)%track.length;
  const onRamp = track._ramps.some(r=>rz>=r[0]&&rz<=r[1]);
  const yTop = SY(row.y + row.h), hpx = row.h + 1;
  const v0 = row.prevZ, v1 = row.segZ;
  const vSpanCap = Math.max(0.08, row.h / MIN_TEXEL);

  if (tex.grass) {
    if (row.ppm * GRASS_TILE < MIN_TEXEL) {
      // One repeat is now smaller than MIN_TEXEL pixels: flat colour with the
      // texture's mean folded in, because there is nothing left to tile but a
      // moire pattern. Mirrors the flatGround branch in UI/RaceUI.lua.
      rect(0, yTop, W, hpx, ...aerial(verge, GRASS_MEAN * roadLight, mix), 1);
    } else {
      // Repeat cap mirrors MIN_TEXEL in UI/RaceUI.lua: past one repeat per
      // MIN_TEXEL pixels the tiling is a moire pattern, not terrain.
      const uG = (HW / Math.max(1, row.ppm)) / GRASS_TILE;
      const gv0 = v0 / GRASS_TILE;
      const gv1 = Math.min(v1 / GRASS_TILE, gv0 + vSpanCap);
      blit(tex.grass, 0, yTop, W, hpx, -uG, uG, gv0, gv1,
        aerial(verge, (dark ? T.grassContrast : 1) * roadLight, mix), 1);
    }
  }
  if (tex.road) {
    const uR = T.roadHalf / ROAD_TILE;
    const band = Math.floor(row.segZ / 2.2) % 2 === 0;
    // Mirrors RaceUI:RenderRoad -- a surface painted on the road is drawn.
    const lapZ = ((row.segZ % track.length) + track.length) % track.length;
    const zone = (track._painted || []).find(z => lapZ >= z.from && lapZ <= z.to);
    // Ramped at the ends of the zone, mirroring Terrain.PAINT_FADE. Without
    // this the join is a hard line straight across the road -- which is exactly
    // what a preview render of Zangarmarsh's water crossing used to show.
    const fade = zone ? Math.min(12, (zone.to - zone.from) * 0.5) : 0;
    const reach = zone
      ? 0.72 * (fade > 0 ? clamp(Math.min(lapZ - zone.from, zone.to - lapZ) / fade, 0, 1) : 1)
      : 0;
    const base = (zone && PAINT[zone.mat])
      ? track.road.map((c, k) => c + (PAINT[zone.mat][k] - c) * reach)
      : track.road;
    const flatRoad = row.ppm * ROAD_TILE < MIN_TEXEL;
    const meanFix = flatRoad ? ROAD_MEAN : 1;
    const tint = onRamp
      ? aerial([1.0, 0.74, 0.16], (band ? 1.0 : 0.55) * tarmacLight * meanFix, mix)
      : aerial(legible(base, tarmacLight), (dark ? .96 : 1) * meanFix, mix);
    if (flatRoad) {
      rect(SX(row.midX - row.midHalf), yTop, row.midHalf * 2, hpx, ...tint, 1);
    } else {
      const rv0 = v0 / ROAD_TILE;
      const rv1 = Math.min(v1 / ROAD_TILE, rv0 + vSpanCap);
      blit(tex.road, SX(row.midX - row.midHalf), yTop, row.midHalf * 2, hpx,
        -uR, uR, rv0, rv1, tint, 1);
    }
    if (tex.roadshade)
      blit(tex.roadshade, SX(row.midX - row.midHalf), yTop, row.midHalf * 2, hpx,
        0, 1, 0, 1, [0, 0, 0], 0.85 * (1 - mix));
  }
  const rw = clamp(row.midHalf * (track.style === "oribos" ? .055 : .05), 1, 20);
  let rr, rg, rb;
  if (track.style === "oribos") {
    const pulse = .55 + .45 * Math.sin(row.segZ * .28);
    [rr, rg, rb] = dark ? [1 * pulse, .72 * pulse, .28 * pulse] : [.30 * pulse, .82 * pulse, 1 * pulse];
  } else [rr, rg, rb] = dark ? [.95,.95,.96] : [.82,.22,.18];
  if(onRamp){ const fl=0.8; rr=1.0*fl; rg=0.85*fl; rb=0.25*fl; }
  // Kerbs are part of the road surface: they take the tarmac's lighting, not
  // the rock's. In a tunnel they are the only thing marking where the edge is.
  const rc = aerial([rr, rg, rb], tarmacLight, mix);
  rect(SX(row.midX - row.midHalf - rw), yTop, rw, hpx, rc[0], rc[1], rc[2], 1);
  rect(SX(row.midX + row.midHalf), yTop, rw, hpx, rc[0], rc[1], rc[2], 1);
  if (idx % 4 < 2 && row.midHalf > 6) {
    const lw = clamp(row.midHalf * .04, 1, 14);
    const lc = aerial([.96, .95, .82], tarmacLight, mix);
    rect(SX(row.midX - lw / 2), yTop, lw, hpx, lc[0], lc[1], lc[2], .75);
  }

  if (row.cover > 0 && row.prevCeilY !== null && tex.rock) {
    const ceilTop = Math.max(row.prevCeilY, row.ceilY + 1);
    const wallOut = row.midHalf * 1.4;
    const wallH = Math.max(1, ceilTop - row.y);
    // Lit from the ROAD, as RenderRoad does it -- `fog` already carries the
    // scene light after the full cover dimming, so using it here reduced the
    // rock a third time and then the rock texture's own mean reduced it a
    // fourth.
    const k = tarmacLight * (0.50 + 0.26 * (1 - row.cover));
    const tint = ROCK_TINT.map((c) => k * c);
    const ctint = [k * ROCK_TINT[0] * 0.62, k * ROCK_TINT[1] * 0.60, k * ROCK_TINT[2] * 0.58];
    const v0 = row.prevZ / TUNNEL_TILE, v1 = row.segZ / TUNNEL_TILE;
    blit(tex.rock, SX(row.midX - row.midHalf - wallOut), SY(row.y + wallH), wallOut, wallH,
      0, 1.6, v0, v1, tint, 1);
    blit(tex.rock, SX(row.midX + row.midHalf), SY(row.y + wallH), wallOut, wallH,
      1.6, 0, v0, v1, tint, 1);
    const ch = Math.max(1, ceilTop - row.ceilY);
    const uC = T.roadHalf / TUNNEL_TILE;
    blit(tex.rock, SX(row.midX - row.midHalf - wallOut), SY(row.ceilY + ch),
      (row.midHalf + wallOut) * 2, ch, -uC, uC, v0, v1, ctint, 1);
  } else if (onRamp) {
    // Side rails along a launch ramp. Physics:VergeHasWall walls exactly
    // tunnels and ramps, so these are the other place a barrier exists and the
    // player has to be able to see it.
    // Metres, projected -- see the note in RaceUI: sizing off midHalf made the
    // near-field rails span half the screen.
    const railH = Math.max(2, row.ppm * 1.15);
    const railW = Math.max(1, row.ppm * 0.40);
    const c = [0.95 * fog, 0.80 * fog, 0.26 * fog];
    rect(SX(row.midX - row.midHalf - railW), SY(row.y + railH), railW, railH, ...c, 1);
    rect(SX(row.midX + row.midHalf), SY(row.y + railH), railW, railH, ...c, 1);
  }
}

// ---------- the fork ribbon ----------
//
// THE ONE PART OF THE SCENE THAT HAD NO PICTURE.
//
// Every other thing on screen is drawn here and can be looked at offline. The
// shortcut ribbon -- the alternate line that peels off the main road, with its
// bright rails and its sign -- was not, which is exactly why "our multi track
// things where there are forks in the road are very disorienting and glitchy"
// arrived as a bug report from a player instead of as an obviously wrong
// picture. Mirrors RaceUI:RenderFork step for step.
const FORK_SEGMENTS = 40;
{
  const branch = (track._branches || []).map(b => {
    const entry = b.from * track.length;
    let gap = (entry - PLAYER_DIST) % track.length;
    if (gap < 0) gap += track.length;
    return { b, entry, gap };
  }).filter(x => x.gap < FAR_Z).sort((a, b2) => a.gap - b2.gap)[0];

  if (branch) {
    const B = compile(Object.assign({}, branch.b));
    // A BRANCH IS A LINE, NOT A LOOP -- Builder:At clamps rather than wrapping,
    // and a sampler that wrapped here would fetch the branch's EXIT for any
    // distance just short of its start.
    const at = d => Math.max(0, Math.min(B.length, d));
    const bCurve = d => B._cv[Math.min(B._N - 1, Math.floor(at(d) / B._STEP))];
    const bHeight = d => B._h[Math.min(B._N - 1, Math.floor(at(d) / B._STEP))];
    const bWidth = d => B._w[Math.min(B._N - 1, Math.floor(at(d) / B._STEP))];

    const entryDz = branch.gap + T.camBack;
    const entryCentre = bend(entryDz);
    const entryWidth = roadWidth(branch.entry);
    // The branch's own curvature, accumulated along the branch exactly as the
    // main road's is accumulated along itself.
    const branchBend = (() => {
      const step = 2, n = Math.ceil(B.length / step) + 4;
      const off = new Float64Array(n);
      let x = 0, dx = 0;
      for (let i = 0; i < n; i++) {
        off[i] = x;
        dx += bCurve(i * step) * BEND_GAIN * step;
        x += dx * step;
      }
      return bd => {
        const t = clamp(bd, 0, (n - 2) * step) / step;
        const i = Math.floor(t), f = t - i;
        return off[i] + (off[i + 1] - off[i]) * f;
      };
    })();

    const side = branch.b.side || -1;
    const offset = side * T.roadHalf * entryWidth * 0.92;
    const span = Math.min(B.length, Math.max(0, FAR_Z - entryDz));
    const baseY = roadHeight(branch.entry) - bHeight(0);
    let pX = null, pY = null, pW = null;
    if (span > 2) {
      // Far to near, so the ribbon occludes itself the way the road does.
      const ribs = [];
      for (let i = 0; i < FORK_SEGMENTS; i++) {
        const bd = span * (i / (FORK_SEGMENTS - 1));
        const dz = entryDz + bd;
        if (dz <= 1.2) continue;
        // Blended out of the main road over the first few metres so it grows
        // from the tarmac rather than appearing beside it.
        const emerge = clamp(bd / 12, 0, 1);
        const worldX = entryCentre + branchBend(bd) + offset * emerge;
        const [x, y, ppm] = project(dz, worldX, baseY + bHeight(bd));
        const hwPx = ppm * T.roadHalf * bWidth(bd);
        if (pY !== null && y > pY) {
          ribs.push({ y: pY, h: Math.max(1, y - pY), midX: (x + pX) / 2,
            midHalf: (hwPx + pW) / 2, dz, bd, ppm });
        }
        pX = x; pY = y; pW = hwPx;
      }
      for (let k = ribs.length - 1; k >= 0; k--) {
        const rib = ribs[k];
        // Textured until it is minified past MIN_TEXEL, exactly as the main
        // road and RaceUI's ribbon are. Filling flat all the way in was a
        // mirror-only shortcut and it showed: the near ribbon came out as a
        // pale slab laid across the road instead of as more tarmac.
        const flatRibbon = rib.ppm * ROAD_TILE < MIN_TEXEL;
        const tint = aerialAt(track.road, 0.94 * light * (flatRibbon ? ROAD_MEAN : 1), rib.dz);
        const rw = Math.max(2, rib.midHalf * 2);
        if (flatRibbon || !tex.road) {
          rect(SX(rib.midX - rib.midHalf), SY(rib.y + rib.h), rw, rib.h + 1, ...tint, 1);
        } else {
          const uR = T.roadHalf / ROAD_TILE;
          const v0 = (rib.bd - span / FORK_SEGMENTS) / ROAD_TILE;
          const v1 = Math.min(rib.bd / ROAD_TILE, v0 + Math.max(0.08, rib.h / MIN_TEXEL));
          blit(tex.road, SX(rib.midX - rib.midHalf), SY(rib.y + rib.h), rw, rib.h + 1,
            -uR, uR, v0, v1, tint, 1);
        }
        // Bright rails, so the alternate line reads as a road and not as a
        // shadow on the grass.
        const rail = clamp(rib.midHalf * 0.055, 2.5, 18);
        const glow = 0.75 + 0.25 * Math.sin(-rib.bd * 0.2);
        const rc = aerialAt([0.48 * glow, 1.0 * glow, 0.30 * glow], light, rib.dz);
        rect(SX(rib.midX - rib.midHalf), SY(rib.y + rib.h), rail, rib.h + 1, ...rc, 1);
        rect(SX(rib.midX + rib.midHalf), SY(rib.y + rib.h), rail, rib.h + 1, ...rc, 1);
      }
    }

    // The sign, planted on the branch's side of the split. Noticed at a fixed
    // distance, not at the draw distance -- mirrors FORK_NOTICE in RaceUI.
    const FORK_NOTICE = 200;
    if (entryDz > 2 && entryDz < FORK_NOTICE) {
      const [x, y, ppm] = project(entryDz,
        bend(entryDz) + side * T.roadHalf * entryWidth * 1.05, roadHeight(branch.entry));
      const size = clamp(ppm * 2.6, 16, 190);
      const art = tex[side < 0 ? "forkleft" : "forkright"];
      if (art) {
        blit(art, SX(x - size * 0.45), SY(y) - size, size * 0.9, size, 0, 1, 0, 1,
          [0.55, 1.0, 0.62], 1);
      }
      const label = (branch.b.name || "SHORTCUT").toUpperCase();
      const alpha = clamp((FORK_NOTICE - entryDz) / 90, 0, 1);
      // Clamped on screen, mirroring RaceUI: on a bend the sign is off at the
      // display edge long before the split arrives, and the label went with it.
      const labelX = clamp(x, -HW + 130, HW - 130);
      // The font's real advance -- 6 cells at size/9.7 px each, the same
      // metric hud-font.js lays out with. Guessing "8 per character" put the
      // arrow through the last two letters of the name.
      const adv = 6 * 15 / 9.7, textW = label.length * adv;
      const textY = SY(y) - size * 1.05 - 16;
      const textX = SX(labelX) - textW / 2;
      drawText((px, py, r, g, b, a) => rect(px, py, 1, 1, r, g, b, a),
        label, textX, textY, 15, [0.62, 1.0, 0.70], alpha);
      // The arrow beside the name, which is what actually says which way --
      // RaceUI anchors chevron.tga to the label's outer edge and flips it
      // through its texcoords. Without it here the sheet showed a name
      // floating over the treeline with no direction attached.
      if (tex.chevron) {
        const aw = 9, ah = 13;
        const ax = side < 0 ? textX - 6 - aw : textX + textW + 6;
        blit(tex.chevron, ax, textY + 1, aw, ah,
          side < 0 ? 1 : 0, side < 0 ? 0 : 1, 0, 1, [0.62, 1.0, 0.70], alpha);
      }
    }
  }
}

// ---------- roadside props ----------
//
// This harness had NO prop renderer at all, which is why it could not show the
// bug the gameplay footage showed in its first frame: conifers standing inside
// the Frozen Tunnel. Props are child FRAMES in the addon, so they draw above
// the tunnel rock rather than behind it -- and this file draws its rock fill in
// a completely different place in the order, so even adding them naively would
// have mirrored the wrong thing. They are drawn here after the surround, which
// is where the game puts them, and gated exactly as RaceUI:RenderProps gates
// them: per prop, on the cover where that prop stands.
const PROP_KINDS = (() => {
  const src = fs.readFileSync(path.join(__dirname, "..", "UI", "RaceUI.lua"), "utf8");
  const table = src.slice(src.indexOf("local PROP_KINDS = {"));
  const out = {};
  const heads = [...table.slice(0, table.indexOf("\n}\n")).matchAll(/^  (\w+) = \{$/gm)];
  for (let i = 0; i < heads.length; i++) {
    const body = table.slice(heads[i].index,
      i + 1 < heads.length ? heads[i + 1].index : table.indexOf("\n}\n"));
    out[heads[i][1]] = [...body.matchAll(
      /art = "([\w.]+)", w = ([\d.]+), h = ([\d.]+), tint = \{ ([\d.]+), ([\d.]+), ([\d.]+) \}, min = ([\d.]+), max = ([\d.]+)/g)]
      .map(m => ({ art: m[1].replace(".tga", ""), w: +m[2], h: +m[3],
        tint: [+m[4], +m[5], +m[6]], min: +m[7], max: +m[8] }));
  }
  return out;
})();
{
  const PROP_SPACING = 9;
  const kinds = PROP_KINDS[track.style || TRACK_ID] || PROP_KINDS.default;
  // Mirrors AK.RNG's xorshift32 and RaceUI:BuildProps' seeding, so the preview
  // stands the same trees in the same places the game does.
  let seed = Math.floor(track.length);
  for (const ch of TRACK_ID) seed = (seed * 31 + ch.charCodeAt(0)) % 2147483647;
  let st = seed >>> 0 || 1;
  const rnd = () => { st ^= st << 13; st >>>= 0; st ^= st >>> 17; st ^= st << 5; st >>>= 0; return st / 4294967296; };
  const props = [];
  for (let d = 0; d < track.length; d += PROP_SPACING) {
    for (const side of [-1, 1]) {
      if (rnd() <= 0.22) continue;
      const kind = kinds[Math.floor(rnd() * kinds.length) % kinds.length];
      props.push({
        distance: (d + rnd() * PROP_SPACING) % track.length, side,
        offset: 1.35 + rnd() * (rnd() < 0.3 ? 3.2 : 0.9),
        size: kind.min + rnd() * (kind.max - kind.min),
        kind, shade: 0.82 + rnd() * 0.36,
      });
    }
  }
  // Far to near, so a nearer tree occludes a further one.
  const drawable = props
    .map(pr => ({ pr, dz: ((pr.distance - (camZ % track.length)) % track.length + track.length) % track.length }))
    .filter(o => o.dz > 0.8 && o.dz < FAR_Z && tunnelDepth(o.pr.distance) < 0.5)
    .sort((a, b) => b.dz - a.dz);
  for (const { pr, dz } of drawable) {
    const art = tex[pr.kind.art];
    if (!art) continue;
    const propZ = camZ + dz;
    const edge = roadWidth(propZ);
    const lat = pr.side * (edge + pr.offset) * T.roadHalf;
    const [x, y, ppm] = project(dz, bend(dz) + lat, roadHeight(propZ));
    const height = ppm * pr.size;
    if (height <= 2 || x < -HW * 2.2 || x > HW * 2.2) continue;
    const width = height * (pr.kind.w / pr.kind.h);
    const fog = clamp(1 - (dz / HAZE_Z) * T.fogStrength, 0.20, 1) * light;
    const shade = pr.shade * fog;
    blit(art, SX(x - width / 2), SY(y) - height, width, height, 0, 1, 0, 1,
      aerialAt(pr.kind.tint, shade, dz), 1);
  }
}

// ---------- arches ----------
if (tex.arch && track.archSpacing) {
  const first = Math.ceil(camZ / track.archSpacing);
  for (let s = 3; s >= 0; s--) {
    const az = (first + s) * track.archSpacing, dz = az - camZ;
    // Mirrors RaceUI:RenderArches -- dropped once you are under it (a billboard
    // cannot leave the frame overhead, it just smears across the screen edges)
    // and pulled in to where the road is still reliably on screen.
    if (dz > 6 && dz < furnitureReach(125)) {
      const [x, y, ppm] = project(dz, bend(dz), roadHeight(az));
      const w = ppm * 17, h = w * 0.95;
      const f = clamp(1 - (dz / HAZE_Z) * T.fogStrength * .8, .3, 1) * light;
      blit(tex.arch, SX(x - w / 2), SY(y) - h, w, h, 0, 1, 0, 1, aerialAt([1, .98, 1.02], f, dz), 1);
    }
  }
}

// ---------- posts ----------
const firstPost = Math.ceil(camZ / T.postSpacing);
for (let s = 23; s >= 0; s--) {
  const pz = (firstPost + s) * T.postSpacing, dz = pz - camZ;
  if (dz > 1 && dz < furnitureReach(119)) {
    const [x, y, ppm] = project(dz, bend(dz), roadHeight(pz));
    const hwp = ppm * T.roadHalf, w = Math.max(1, ppm * .18), h = Math.max(2, ppm * 1.15);
    const fog = clamp(1 - (dz / HAZE_Z) * T.fogStrength, .22, 1);
    const red = (firstPost + s) % 2 === 0;
    const c = aerialAt(red ? [.88, .26, .20] : [.95, .95, .96], fog, dz);
    const off = hwp + w * 2.2;
    rect(SX(x - off), SY(y) - h, w, h, ...c, 1);
    rect(SX(x + off), SY(y) - h, w, h, ...c, 1);
  }
}

// ---------- trackside objects ----------
//
// Item-box gates, dash panels and hazards, placed by the same arithmetic as
// Race:BuildObjects and Race:BuildHazards so the preview shows the real course
// furniture rather than an empty road. Drawn far-to-near, exactly as the addon
// depth-sorts them by frame level.
//
// OLDOBJ=1 renders them the way they used to be -- upright square icons, no
// contact shadow, absolute pixel clamps -- so the change can be compared rather
// than asserted.
const OLDOBJ = !!process.env.OLDOBJ;
const objects = (function () {
  const out = [];
  const L = track.length;
  const GATES = Math.max(4, Math.floor(L / 420)), PER_GATE = 5;
  for (let g = 1; g <= GATES; g++) {
    const at = 70 + (g - 1) * (L / GATES);
    for (let s = 1; s <= PER_GATE; s++) {
      out.push({ kind: "box", distance: at, lateral: (s - (PER_GATE + 1) / 2) * 0.36 });
    }
  }
  for (const [i, f] of [0.14, 0.31, 0.48, 0.66, 0.86].entries()) {
    for (let lane = -1; lane <= 1; lane++) {
      out.push({ kind: "boost", distance: L * f + lane * 6,
        lateral: lane * 0.34 + ((i + 1) % 2 === 0 ? 0.18 : -0.18) });
    }
  }
  // Hazards, from the track's own hazardPlan.
  const src = fs.readFileSync(path.join(__dirname, "..", "Data", "Tracks.lua"), "utf8");
  const starts = [];
  const re2 = /\n  \{\n    id = "(\w+)"/g;
  let mm; while ((mm = re2.exec(src))) starts.push({ id: mm[1], at: mm.index });
  const idx = starts.findIndex(s => s.id === TRACK_ID);
  const body = src.slice(starts[idx].at, idx + 1 < starts.length ? starts[idx + 1].at : src.length);
  const hp = body.indexOf("hazardPlan = {");
  if (hp >= 0) {
    const chunk = body.slice(hp, body.indexOf("\n    },", hp));
    for (const h of chunk.matchAll(/\{ kind = "(\w+)"[^\n]*\n?[^\n]*/g)) {
      const line = h[0];
      const num = (k, d) => { const q = line.match(new RegExp(k + " = (-?[\\d.]+)")); return q ? +q[1] : d; };
      const count = num("count", 1), at = num("at", 0), spacing = num("spacing", 40);
      const lateral = num("lateral", 0);
      for (let i = 0; i < count; i++) {
        out.push({ kind: "hazard", distance: at * L + i * spacing, lateral });
      }
    }
  }
  return out;
})();

const OBJ_STYLE = {
  box:    { tex: "itembox", col: [1.00, 0.82, 0.25], size: 2.2, float: true, spin: true },
  boost:  { tex: "dashpad", col: [1.00, 0.72, 0.18], size: 3.8, flat: true },
  hazard: { tex: "bomb",    col: [1.00, 0.42, 0.26], size: 2.6 },
};
// Screen-relative floor/ceiling, matching RaceUI:ObjectSize. The old absolute
// (22, 260) clamp is what OLDOBJ reproduces.
const objSize = (ppm, m) => OLDOBJ
  ? clamp(ppm * m, 22, 260)
  : clamp(ppm * m, HW * 0.020, HW * 0.46);

const visibleObjects = objects.map(o => {
  let d = o.distance - (camZ % track.length);
  if (d < -track.length / 2) d += track.length;
  if (d > track.length / 2) d -= track.length;
  return { o, dz: d };
}).filter(e => e.dz > 1.5 && e.dz < FAR_Z).sort((a, b) => b.dz - a.dz);

for (const entry of visibleObjects) {
  const o = entry.o, dz = entry.dz;
  const st = OBJ_STYLE[o.kind] || OBJ_STYLE.hazard;
  const az = camZ + dz;
  const [x, y, ppm] = project(dz, bend(dz) + o.lateral * T.roadHalf, roadHeight(az));
  const size = objSize(ppm, st.size);
  const fog = clamp(1 - (dz / HAZE_Z) * T.fogStrength, 0.22, 1);
  const t = tex[st.tex];
  const hover = (!OLDOBJ && st.float) ? size * 0.20 : (OLDOBJ && st.float ? size * 0.55 : 0);

  if (!OLDOBJ) {
    // Contact shadow on the ROAD, independent of the object's hover.
    const lift = size > 0 ? hover / size : 0;
    const sw = size * (st.flat ? 1.30 : 1.02) * (1 - lift * 0.30);
    const sh = Math.max(2, size * (st.flat ? 0.36 : 0.34) * (1 - lift * 0.30));
    if (tex.shadow) blit(tex.shadow, SX(x - sw / 2), SY(y + size * 0.05) - sh / 2, sw, sh,
      0, 1, 0, 1, [0, 0, 0], (st.flat ? 0.34 : 0.62) * fog * (1 - lift * 0.45));
  }

  if (!t) continue;
  const c = [st.col[0] * fog, st.col[1] * fog, st.col[2] * fog];
  if (!OLDOBJ && st.flat) {
    // Painted flat on the tarmac: wide and short, at ground level. The height
    // floor is screen-relative, matching RaceUI -- an absolute 3px floor made a
    // distant panel a sliver, which is most of why flattening them read as a
    // downgrade against OLDOBJ.
    const w = size * 1.42, h = Math.max(HW * 0.009, size * 0.32);
    blit(t, SX(x - w / 2), SY(y) - h, w, h, 0, 1, 0, 1, c, 1);
  } else {
    blit(t, SX(x - size / 2), SY(y + hover) - size, size, size, 0, 1, 0, 1, c, 1);
  }
}

// ---------- field ----------
const field = [
  { dz: T.camBack, lat: 0.0, col: [0.29, 0.62, 0.94], you: true, kart: KART_ID },
  { dz: 20, lat: -0.45, col: [0.96, 0.27, 0.14], kart: "rocket" },
  { dz: 36, lat: 0.42, col: [0.42, 0.68, 0.30], kart: "chicken" },
  { dz: 72, lat: -0.20, col: [0.90, 0.72, 0.31], kart: "griffon" },
  { dz: 128, lat: 0.30, col: [0.55, 0.28, 0.85], kart: "minecart" },
].sort((a, b) => b.dz - a.dz);
for (const v of field) {
  const az = camZ + v.dz;
  let [x, y, ppm] = project(v.dz, bend(v.dz) + v.lat * T.roadHalf, roadHeight(az));
  const w = clamp(ppm * 2.2 * T.kartScale, 14, HW * 0.72);
  const bw = w * 1.05, bh = bw * .625;
  if (tex.shadow) blit(tex.shadow, SX(x - w * .575), SY(y) - Math.max(3, w * .11), w * 1.15,
    Math.max(3, w * .22), 0, 1, 0, 1, [0, 0, 0], 0.55);
  const kt = kartTex(v.kart);
  const kcol = kartCol(v.kart);
  if (kt) {
    blit(kt, SX(x - bw / 2), SY(y) - bh, bw, bh, 0, 1, 0, 1, kcol, 1);
    // Driver stand-in: a capsule where the WoW model renders, to judge the
    // seat relationship without a client.
    const dh = w * 0.95, dw = w * 0.42;
    rect(SX(x - dw / 2), SY(y + w * T.modelLift) - dh * 0.62, dw, dh, 0.84, 0.77, 0.67, 0.95);
    if (T.kartLip > 0.01)
      blit(kt, SX(x - bw / 2), SY(y) - bh * T.kartLip, bw, bh * T.kartLip,
        0, 1, 1 - T.kartLip, 1, kcol, 1);

    // Drift sparks on the player's kart, one per rear wheel, sized and coloured
    // exactly as RaceUI does. The whole reason these exist is to be readable
    // without looking at the HUD meter, so this render is the actual test.
    if (v.you && feel.tier > 0 && tex.spark) {
      const hue = DRIFT_HUE[feel.tier];
      const size = w * (0.20 + feel.tier * 0.07);
      const alpha = 0.45 + 0.30 * feel.tier / 3;
      for (const side of [-1, 1]) {
        blit(tex.spark, SX(x + side * w * 0.46 - size / 2), SY(y + w * 0.02) - size / 2,
          size, size, 0, 1, 0, 1, hue, alpha, "add");
      }
    }
    // The release burst, at the moment the mini-turbo fires.
    if (v.you && FEEL === "boost" && tex.burst) {
      const bs = w * 2.9;
      blit(tex.burst, SX(x - bs / 2), SY(y + w * 0.35) - bs / 2, bs, bs,
        0, 1, 0, 1, [1, 0.82, 0.30], 0.85);
    }
  }
}

// ---------- vignette + HUD ----------
//
// The HUD used to be four unlabelled grey rectangles at hard-coded pixel
// offsets: it could not answer a single question about the interface, and it
// went stale the moment the Lua moved. This reads the layout table straight out
// of UI/RaceUI.lua and renders the real thing, text included, at the same scale
// the addon would pick for a window this size.
if (tex.vignette) blit(tex.vignette, 0, 0, W, H, 0, 1, 0, 1, [0, 0, 0], 1);
const LAYOUT = require("./hud-layout.js");

// Drawn straight from Art/hud-layout.js, which is the same list verify-hud.js
// checks and which parses its geometry out of UI/RaceUI.lua. Two mirrors of one
// layout is how a preview ends up disagreeing with both the game and the test.
const HS = LAYOUT.scale(W, H);
const u = n => n * HS;
// THE HUD HAS TO NAME THE CIRCUIT IT IS DRAWN OVER.
//
// hud-layout.js carries the LONGEST string each readout can ever show, because
// that is what the layout has to survive and what verify-hud.js checks. On a
// picture of one circuit those placeholders are a different problem: every
// sheet in this repo said "NETHERSTORM TURBO CIRCUIT / ARCANE / THE COLLAPSED
// SPAN" over whatever road was actually rendered, which makes the sheet argue
// with itself. Real strings here, worst-case ones in the test.
const sectionHere = (() => {
  const authored = track.layout.reduce((sum, p) => sum + p.len, 0);
  const scale = track.length / authored;
  let at = 0;
  for (const piece of track.layout) {
    at += piece.len * scale;
    if (PLAYER_DIST % track.length < at) return piece.name || "";
  }
  return track.layout[0].name || "";
})();
const HUD_SAMPLE = {
  "track.name": track.theme ? track.name + "  /  " + track.theme : track.name,
  "track.section": sectionHere.toUpperCase(),
  shortcut: track.shortcut ? "SHORTCUT: " + track.shortcut : "",
};
const R = {};
for (const r of LAYOUT.rects(W, H, HUD_SAMPLE)) R[r.name] = r;
const GOLD = LAYOUT.COLORS.GOLD;

function panel(r, alpha = 1) {
  // NINE-SLICED, exactly as UI:NewPanel draws it: corners keep their pixels,
  // edges stretch along one axis, the middle stretches both. Stretching the
  // whole texture is what turns a rounded corner into an oval.
  if (tex.panelplate) {
    const C = 18, TW = tex.panelplate.w;
    const cw = Math.min(C, r.w / 2), ch = Math.min(C, r.h / 2);
    const u = [[0, C / TW], [C / TW, 1 - C / TW], [1 - C / TW, 1]];
    const xs = [r.x, r.x + cw, r.x + r.w - cw], ws = [cw, Math.max(1, r.w - cw * 2), cw];
    const ys = [r.y, r.y + ch, r.y + r.h - ch], hs = [ch, Math.max(1, r.h - ch * 2), ch];
    for (let row = 0; row < 3; row++) {
      for (let col = 0; col < 3; col++) {
        blit(tex.panelplate, xs[col], ys[row], ws[col], hs[row],
          u[col][0], u[col][1], u[row][0], u[row][1], PANEL_TINT, alpha);
      }
    }
    if (tex.panelgleam) {
      blit(tex.panelgleam, r.x + 3, r.y + 1, r.w - 6, 3, 0, 1, 0, 1, [1, .86, .55], 0.40 * alpha);
    }
  } else {
    rect(r.x, r.y, r.w, r.h, .04, .06, .10, .9 * alpha);
    rect(r.x, r.y, r.w, 1, 1, .76, .20, .34 * alpha);
  }
}
const put = (qx, qy, r, g, b, a) => blend(qx, qy, r, g, b, a);
const SHOW_CONTROLS = !!process.env.CONTROLS;
// HUD_PANEL from UI/RaceUI.lua. The alpha travels separately, in `alpha`.
const PANEL_TINT = [.025, .05, .10];

// THE BUTTON PLATE, three-sliced exactly as UI:NewButton draws it: the two caps
// keep their pixels and the middle stretches. A single texture scaled to fit
// turns the rounded corners into ovals, so the mirror has to slice it the same
// way or it is showing a shape the game never draws.
function plate(x0, y0, bw, bh, tint) {
  if (!tex.btn) { rect(x0, y0, bw, bh, tint[0], tint[1], tint[2], .96); return; }
  const CAP_PX = 26, capW = Math.min(CAP_PX, bh * CAP_PX / 40, bw / 2);
  const cu = CAP_PX / tex.btn.w;
  blit(tex.btn, x0, y0, capW, bh, 0, cu, 0, 1, tint, 1);
  blit(tex.btn, x0 + capW, y0, bw - capW * 2, bh, cu, 1 - cu, 0, 1, tint, 1);
  blit(tex.btn, x0 + bw - capW, y0, capW, bh, 1 - cu, 1, 0, 1, tint, 1);
}

// Panels and buttons first, then every text row on top of them.
for (const r of LAYOUT.rects(W, H, HUD_SAMPLE)) {
  if (r.kind === "panel") panel(r);
  else if (r.kind === "glow" && tex.glow)
    blit(tex.glow, r.x, r.y, r.w, r.h, 0, 1, 0, 1, [0, 0, 0], 0.55);
  else if (r.kind === "button") {
    // The on-screen pads and the corner quit are OFF by default now -- see
    // AK.db.settings.showControls. CONTROLS=1 draws them, the way a player who
    // turned them on would see them.
    if (!SHOW_CONTROLS) continue;
    const col = r.text === "BRAKE" ? [.34, .12, .10] : r.text === "GAS" ? [.10, .30, .14]
      : r.text === "QUIT" ? [.38, .12, .11] : [.18, .28, .42];
    plate(r.x, r.y, r.w, r.h, col);
  } else if (r.kind === "pips") {
    for (let i = 0; i < 3; i++)
      rect(r.x + i * r.pitch, r.y, r.each, r.h, ...(i < 2 ? GOLD : [.25, .32, .42]), 1);
  } else if (r.kind === "icon" && tex.mushroom) {
    blit(tex.mushroom, r.x, r.y, r.w, r.h, 0, 1, 0, 1, [1, 1, 1], 1);
  }
}
{ // THE ROUTE, as Builder:Compile actually lays it out.
  //
  // This drew a fixed ellipse: forty-eight dots on a circle, for every circuit.
  // The minimap is on screen for the entire race and the mirror was showing a
  // shape the game has never drawn -- which is how the real plan view stayed an
  // unreadable scribble on eight of the ten circuits without anyone noticing.
  const m = R["map.panel"], rad = u(LAYOUT.HUD.map.w * 0.36);
  const MAP_GAIN = 0.0042;                      // Builder's MAP_GAIN
  const authored = track.layout.reduce((a, p) => a + p.len, 0);
  const scale = track.length / authored;
  let turnAtGain = 0;
  for (const piece of track.layout) turnAtGain += (piece.curve || 0) * piece.len * scale * MAP_GAIN;
  const spreadTurn = (Math.PI * 2 - turnAtGain) / track.length;
  const samples = Math.floor(track.length / 2) + 1;
  const path = [];
  let angle = 0, px = 0, py = 0, pi = 0, left = track.layout[0].len * scale;
  for (let i = 0; i < samples; i++) {
    angle += (track.layout[pi].curve || 0) * 2 * MAP_GAIN + spreadTurn * 2;
    px += Math.cos(angle) * 2; py += Math.sin(angle) * 2;
    path.push([px, py]);
    left -= 2;
    while (left <= 0 && pi < track.layout.length - 1) { pi++; left += track.layout[pi].len * scale; }
  }
  const dx = path[samples - 1][0] - path[0][0], dy = path[samples - 1][1] - path[0][1];
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (let i = 0; i < samples; i++) {
    const t = i / (samples - 1);
    path[i][0] -= dx * t; path[i][1] -= dy * t;
    minX = Math.min(minX, path[i][0]); maxX = Math.max(maxX, path[i][0]);
    minY = Math.min(minY, path[i][1]); maxY = Math.max(maxY, path[i][1]);
  }
  const span = Math.max(Math.max(1e-3, maxX - minX), Math.max(1e-3, maxY - minY));
  const midX = (minX + maxX) / 2, midY = (minY + maxY) / 2;
  // NEGATE Y. The game anchors these with SetPoint, where +y is UP; this
  // framebuffer's +y is down. Without the flip the mirror draws every circuit
  // upside down, which is invisible until you compare it with the same shape
  // drawn correctly somewhere else -- as the track cards do.
  const at = (d) => {
    const p2 = path[Math.floor((((d % track.length) + track.length) % track.length) / 2) % samples];
    return [(p2[0] - midX) / span * rad * 2, -(p2[1] - midY) / span * rad * 2];
  };
  const ROUTE_NODES = 72;
  for (let i = 0; i < ROUTE_NODES; i++) {
    const [ax, ay] = at(i / ROUTE_NODES * track.length);
    rect(m.x + m.w / 2 + ax - u(2.5), m.y + m.h / 2 + ay - u(2.5), u(5), u(5), .32, .44, .58, .95);
  }
  for (let i = 0; i < 4; i++) {
    const [ax, ay] = at((PLAYER_DIST + i * 90) % track.length);
    rect(m.x + m.w / 2 + ax - u(4), m.y + m.h / 2 + ay - u(4),
      u(8), u(8), i ? .9 : 1, i ? .4 : .82, i ? .3 : .25, 1);
  }
}
{ // drift charge fill and its tier ticks
  const d = R["drift.panel"], track = d.w - u(8);
  rect(d.x + u(4), d.y + u(4), track * (1.30 / LAYOUT.DRIFT_MAX), d.h - u(8), 1, .58, .10, 1);
  for (const t of [0.35, 0.90, 1.80])
    rect(d.x + u(4) + track * (t / LAYOUT.DRIFT_MAX), d.y + u(4), Math.max(1, u(2)), d.h - u(8), .08, .13, .20, 1);
}
for (const r of LAYOUT.rects(W, H, HUD_SAMPLE)) {
  if (r.kind === "text") drawText(put, r.text, r.x, r.y, r.size, r.color, 1);
  else if (r.kind === "button" && SHOW_CONTROLS)
    drawText(put, r.text, r.x + (r.w - r.text.length * 6 * u(13) / 9.7) / 2,
      r.y + (r.h - u(13) * 7 / 9.7) / 2, u(13), GOLD, 1);
}

// ---------- encode ----------
function crc32(buf) { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } let crc = 0xffffffff; for (const b of buf) crc = t[(crc ^ b) & 0xff] ^ (crc >>> 8); return (crc ^ 0xffffffff) >>> 0; }
function chunk(type, data) { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, c]); }
const rgb = Buffer.alloc(H * (W * 3 + 1));
for (let y = 0; y < H; y++) { rgb[y * (W * 3 + 1)] = 0; for (let x = 0; x < W; x++) { const i = (y * W + x) * 3, o = y * (W * 3 + 1) + 1 + x * 3; for (let k = 0; k < 3; k++) rgb[o + k] = Math.round(Math.max(0, Math.min(1, fb[i + k])) * 255); } }
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
fs.writeFileSync(OUT, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(rgb)), chunk("IEND", Buffer.alloc(0))]));
// Where the road actually IS on screen, per strip. Anything measuring the
// rendered frame -- "can you tell the road from the verge" -- has to sample
// inside and outside the tarmac, and on a bending circuit those places are
// nowhere near a fixed pair of coordinates.
if (process.env.ROAD_ROWS) {
  fs.writeFileSync(process.env.ROAD_ROWS, JSON.stringify(rows.map((r) => ({
    y: Math.round(SY(r.y)), left: Math.round(SX(r.midX - r.midHalf)),
    right: Math.round(SX(r.midX + r.midHalf)),
    // Under cover there is no verge at all -- outside the shaft is rock -- so
    // anything asking "can you tell the road from the grass" has to skip these.
    cover: r.cover || 0,
  }))));
}
console.log("rendered", OUT, "at distance", PLAYER_DIST);
