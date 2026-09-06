---
description: Deep self-directed pass on Azeroth Kart — find the real faults, measure them, fix them, ship the zip
---

Do a deep pass on Azeroth Kart. **Pick the target yourself — do not ask me what
to work on.** If I named a focus below, start there, but if you find something
worse on the way, do that too and tell me why.

$ARGUMENTS

## The standing goal

This has to feel like a kart racer Nintendo shipped, not an addon somebody
wrote. Mario Kart is the reference. Every pass closes the gap between what the
game is and that. I am bad at wording what I want — assume I want the version of
my request that a designer would have asked for, not the literal one.

## Where the real faults have actually been

Work down this list. Every genuine find this project has had came from one of
these, and almost none came from reading code looking for bugs:

1. **Promises the code does not keep.** A comment or a doc describes a mechanic;
   the code does something else, or nothing. *Air steering that the launch code
   swore it reduced and never did. A hop that "clears low hazards" and cleared
   nothing. A dash-panel surface whose comment promised +35% top speed and gave
   zero.*
2. **Data declared and never read.** A field on every entry of a table that
   nothing consumes. *`drift`, `rumble` and `boost` on all ten terrain types.*
3. **Mirrors that have drifted.** `Art/*.js` and the `verify-*.js` harnesses
   reimplement the real Lua. When the Lua moves and they don't, they lie in
   exactly the places I trust them most. *A legend advertising controls the game
   no longer has; a traction formula fixed in the game and not in the mirror.*
4. **Measurements that are deaf.** Before believing a harness that says a thing
   is fine, ask what it would actually fail on. *The quiet-stretch check skipped
   every mini-turbo banked while merely carrying an item — most of a race.*
5. **The reference game, mechanic by mechanic.** Name the Mario Kart behaviour
   out loud, then check ours does it. That is how the drift turned out to be a
   steering bonus with a light show on it.
6. **Anything I sent you.** If there are screenshots or video in my message,
   they outrank every harness in this repo. What I can see is the ground truth.

## How to work

- **Measure, don't assert.** If there is no way to measure the thing, build one
  — and leave it behind as a permanent check so the fault cannot come back.
- **Every fix gets a before-and-after number.** Use negative controls where you
  can (the `OLDANCHOR` / `FLATANCHOR` / `POINTRAMP` / `FLICKER_OFF` pattern).
- **If a change measures ~0, say so plainly** and either drop it or say why it
  stays. Do not describe an effect you have not measured.
- **Never widen a bar to make a check pass.** Tighten bars to what the game
  actually achieves once it is fixed. A bar nothing can fail is not a check.
- **Balance changes ripple.** After any physics, AI or item change, re-run the
  whole-race numbers — lap times, field spread, resets, the battle resolution —
  not just the check you were working on. A Boo tweak once killed Battle Mode
  outright and only a full run caught it.
- **Comments say WHY**, and name the fault they fixed with its measurement, the
  way the rest of these files do. That history is the most valuable thing in the
  repo.
- **Do not stop at the first finding.** A pass is worth doing if it turns up
  something I could not have told you about.

## Before you say you are done

All green, no exceptions:

```
node check.js
node verify-{ai,audio,corners,drama,drift,feel,hud,render,smoothness,tracks}.js
node Art/verify-contrast.js
SCREEN={home,tracks,racers,karts,cups,multiplayer,results,settings,trophies} node Art/preview-ui.js Art out.png
STATE={,countdown,go,pause,finish} TRACK=<id> node Art/preview-render.js Art out.png
lua5.1 verify-runtime.lua
```

Then commit with a real message, `node package.js`, push the branch, and send me
the zip.

## When you report back

- Lead with **what you found**, not what you did.
- Give me the numbers.
- Tell me the **one thing most likely to still feel wrong in my hands**, and what
  you would change if it does.
- Do not pad it. Three real findings reported as three beats three reported as
  nine.
