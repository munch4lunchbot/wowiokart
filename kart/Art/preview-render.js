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
const SEGMENTS = +(process.env.SEGMENTS || 150), FAR_Z = +(process.env.FAR_Z || T.drawDistance || 330);
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
    length: num(/length = (\d+), laps/, 2600), color: triple("color"), road: triple("road"),
    skyTop: triple("skyTop"), skyLow: triple("skyLow"), glow: triple("glow"),
    light: num(/light = ([\d.]+)/, 1), archSpacing: num(/archSpacing = (\d+)/, 0),
    style: (body.match(/style = "(\w+)"/) || [, null])[1],
    sweep: num(/sweep = ([\d.]+)/, 2.6), layout,
  };
})();
// Compile the layout exactly as TrackBuilder does.
(function(){
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
})();
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
const verge = [track.color[0]*2.3+.06, track.color[1]*2.1+.07, track.color[2]*1.9+.05];

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
const SKYLINE = {
  oribos:        {},
  elwynn:        { mtn: { h: .12, tint: [.55, .64, .80], a: .85 }, hill: { h: .085, tint: [.34, .52, .30] } },
  durotar:       { mtn: { h: .19, tint: [.60, .32, .22], a: .95 }, hill: { h: .07, tint: [.50, .30, .17] },
                   treeTint: [1.0, .60, .34] },
  stranglethorn: { mtn: { h: .11, tint: [.38, .54, .52], a: .80 }, hill: { h: .10, tint: [.16, .36, .25] },
                   treeTint: [.55, 1.0, .62] },
  ironforge:     { mtn: { h: .22, tint: [.80, .87, .97], a: 1.0 }, hill: { h: .08, tint: [.60, .70, .83] },
                   treeTint: [.70, .82, 1.0] },
  deadmines:     { mtn: { h: .10, tint: [.20, .24, .40], a: .90 }, hill: { h: .06, tint: [.15, .19, .30] },
                   treeTint: [.48, .55, .85] },
  netherstorm:   { mtn: { h: .15, tint: [.52, .33, .72], a: .90, float: .05 },
                   treeArt: "shard", treeTint: [.80, .55, 1.15] },
};
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
  const tt = skyline.treeTint || [.80, 1, .86];
  const spread = HW * 2.4, slice = spread / TREES, drift = -camX * 3.4;
  for (let i = 1; i <= TREES; i++) {
    const x = ((i * slice + drift) % spread + spread) % spread - spread / 2;
    let n = Math.sin(i * 12.9898) * 43758.5453; n -= Math.floor(n);
    const back = i % 3 === 0;
    const h0 = (spirey ? (0.10 + n * 0.20) : (0.042 + n * 0.075)) * H * T.treeHeight;
    const w = h0 * (spirey ? 0.26 : 0.5);
    const h = h0 * (back ? (spirey ? .72 : .82) : 1);
    const tone = (back ? (spirey ? .42 : .62) : (spirey ? .66 : .92)) * light;
    const tint = track.style === "oribos" ? [tone * .80, tone * .70, tone * 1.15]
      : [tone * tt[0], tone * tt[1], tone * tt[2]];
    blit(skyArt, SX(x - w / 2), SY(T.horizon - (back ? H * .019 : H * .006)) - h, w, h, 0, 1, 0, 1, tint, 1);
  }
}

// haze band softening the horizon seam
{
  const g0 = track.glow;
  const span = Math.round(H * 0.12);
  for (let dy = -span; dy <= Math.round(H * 0.02); dy++) {
    const t = (dy + span) / (span + H * 0.02);
    const a = 0.30 * Math.pow(t, 1.5);
    const yy = SY(T.horizon + dy);
    for (let x = 0; x < W; x++) blend(x, yy, g0[0] * .8, g0[1] * .8, g0[2] * .85, a);
  }
}
// ---------- road ----------
const lift = T.camDepth * T.camHeight * HH;
const nearZ = Math.max(1.2, lift / (T.horizon + HH + 60));
const nu = 1 / nearZ, fu = 1 / FAR_Z, step = (nu - fu) / (SEGMENTS - 1);
const rows = [];
let pX = null, pY = null, pW = null, pZ = null, pCeil = null;
for (let i = 0; i < SEGMENTS; i++) {
  const dz = 1 / (nu - i * step), segZ = camZ + dz;
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
  const fog = clamp(1 - (row.dz / FAR_Z) * T.fogStrength, .22, 1) * light;
  const idx = Math.floor(row.segZ / STRIPE), dark = idx % 2 === 0;
  const rz=((row.segZ%track.length)+track.length)%track.length;
  const onRamp = track._ramps.some(r=>rz>=r[0]&&rz<=r[1]);
  const yTop = SY(row.y + row.h), hpx = row.h + 1;
  const v0 = row.prevZ, v1 = row.segZ;

  if (tex.grass) {
    const f = (dark ? T.grassContrast : 1) * fog;
    const uG = (HW / Math.max(1, row.ppm)) / GRASS_TILE;
    blit(tex.grass, 0, yTop, W, hpx, -uG, uG, v0 / GRASS_TILE, v1 / GRASS_TILE,
      shade(verge, f), 1);
  }
  if (tex.road) {
    const f = (dark ? .96 : 1) * fog;
    const uR = T.roadHalf / ROAD_TILE;
    blit(tex.road, SX(row.midX - row.midHalf), yTop, row.midHalf * 2, hpx,
      -uR, uR, v0 / ROAD_TILE, v1 / ROAD_TILE, onRamp ? (()=>{const band=Math.floor(row.segZ/2.2)%2===0,hot=band?1.0:0.55;return [Math.min(1,1.0*fog*hot),Math.min(1,0.74*fog*hot),Math.min(1,0.16*fog*hot)];})() : shade(track.road, f), 1);
    if (tex.roadshade)
      blit(tex.roadshade, SX(row.midX - row.midHalf), yTop, row.midHalf * 2, hpx,
        0, 1, 0, 1, [0, 0, 0], 0.85 * fog);
  }
  const rw = clamp(row.midHalf * (track.style === "oribos" ? .055 : .05), 1, 20);
  let rr, rg, rb;
  if (track.style === "oribos") {
    const pulse = .55 + .45 * Math.sin(row.segZ * .28);
    [rr, rg, rb] = dark ? [1 * pulse, .72 * pulse, .28 * pulse] : [.30 * pulse, .82 * pulse, 1 * pulse];
  } else [rr, rg, rb] = dark ? [.95,.95,.96] : [.82,.22,.18];
  if(onRamp){ const fl=0.8; rr=1.0*fl; rg=0.85*fl; rb=0.25*fl; }
  rect(SX(row.midX - row.midHalf - rw), yTop, rw, hpx, rr * fog, rg * fog, rb * fog, 1);
  rect(SX(row.midX + row.midHalf), yTop, rw, hpx, rr * fog, rg * fog, rb * fog, 1);
  if (idx % 4 < 2 && row.midHalf > 6) {
    const lw = clamp(row.midHalf * .04, 1, 14);
    rect(SX(row.midX - lw / 2), yTop, lw, hpx, .96 * fog, .95 * fog, .82 * fog, .75);
  }

  if (row.cover > 0 && row.prevCeilY !== null && tex.rock) {
    const ceilTop = Math.max(row.prevCeilY, row.ceilY + 1);
    const wallOut = row.midHalf * 1.4;
    const wallH = Math.max(1, ceilTop - row.y);
    const k = fog * (0.46 + 0.30 * (1 - row.cover));
    const tint = [k * 1.02, k * 0.97, k * 0.92];
    const ctint = [k * 0.82, k * 0.79, k * 0.76];
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

// ---------- arches ----------
if (tex.arch && track.archSpacing) {
  const first = Math.ceil(camZ / track.archSpacing);
  for (let s = 3; s >= 0; s--) {
    const az = (first + s) * track.archSpacing, dz = az - camZ;
    if (dz > 0.6 && dz < FAR_Z * 0.9) {
      const [x, y, ppm] = project(dz, bend(dz), roadHeight(az));
      const w = ppm * 17, h = w * 0.95;
      const f = clamp(1 - (dz / FAR_Z) * T.fogStrength * .8, .3, 1) * light;
      blit(tex.arch, SX(x - w / 2), SY(y) - h, w, h, 0, 1, 0, 1, [f, f * .98, f * 1.02], 1);
    }
  }
}

// ---------- posts ----------
const firstPost = Math.ceil(camZ / T.postSpacing);
for (let s = 23; s >= 0; s--) {
  const pz = (firstPost + s) * T.postSpacing, dz = pz - camZ;
  if (dz > 1 && dz < FAR_Z * .8) {
    const [x, y, ppm] = project(dz, bend(dz), roadHeight(pz));
    const hwp = ppm * T.roadHalf, w = Math.max(1, ppm * .18), h = Math.max(2, ppm * 1.15);
    const fog = clamp(1 - (dz / FAR_Z) * T.fogStrength, .22, 1);
    const red = (firstPost + s) % 2 === 0;
    const c = red ? [.88 * fog, .26 * fog, .20 * fog] : [.95 * fog, .95 * fog, .96 * fog];
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
  const fog = clamp(1 - (dz / FAR_Z) * T.fogStrength, 0.22, 1);
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
if (tex.vignette) blit(tex.vignette, 0, 0, W, H, 0, 1, 0, 1, [0, 0, 0], 1);
function panel(x, y, w, h) {
  if (tex.panel) blit(tex.panel, x, y, w, h, 0, 1, 0, 1, [1, 1, 1], 1);
  else rect(x, y, w, h, .04, .06, .10, .9);
  rect(x, y, w, 1, 1, .76, .20, .85); rect(x, y + h - 1, w, 1, 1, .76, .20, .85);
  rect(x, y, 1, h, 1, .76, .20, .85); rect(x + w - 1, y, 1, h, 1, .76, .20, .85);
}
panel(HW - 310, 20, 620, 73);
panel(30, 28, 128, 128);
panel(W - 150, 28, 120, 106);
panel(HW - 130, H - 67, 260, 32);

// ---------- encode ----------
function crc32(buf) { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } let crc = 0xffffffff; for (const b of buf) crc = t[(crc ^ b) & 0xff] ^ (crc >>> 8); return (crc ^ 0xffffffff) >>> 0; }
function chunk(type, data) { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, c]); }
const rgb = Buffer.alloc(H * (W * 3 + 1));
for (let y = 0; y < H; y++) { rgb[y * (W * 3 + 1)] = 0; for (let x = 0; x < W; x++) { const i = (y * W + x) * 3, o = y * (W * 3 + 1) + 1 + x * 3; for (let k = 0; k < 3; k++) rgb[o + k] = Math.round(Math.max(0, Math.min(1, fb[i + k])) * 255); } }
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
fs.writeFileSync(OUT, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(rgb)), chunk("IEND", Buffer.alloc(0))]));
console.log("rendered", OUT, "at distance", PLAYER_DIST);
