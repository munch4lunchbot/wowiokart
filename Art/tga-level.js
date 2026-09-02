// Bake a texture's brightness to a TARGET rather than by a blind multiply.
//
// These ground textures are tinted with SetVertexColor in game, which clamps at
// 1.0, so the brightness the scene needs has to live in the art. That used to be
// done with a hand-set gain -- road.tga got x1.9 -- and nothing checked the
// result. Measured, it put 99.1% of the road texture at pure white with a
// standard deviation of 0.0026: every slab, seam, stain and crack the generator
// carefully computed was clipped clean off, and the road in game was a flat
// colour with a stripe down it. The gain had been chosen against an earlier,
// darker version of the function and was never re-checked when it changed.
//
// A target cannot go stale that way. Art/verify-textures.js holds it to it.

/** Luminance, the weighting the eye actually uses. */
const lum = (r, g, b) => r * 0.30 + g * 0.59 + b * 0.11;

/**
 * Rescale an RGBA Float64Array in place so its luminance lands on `wantMean`
 * with spread `wantSd`, then pull it under the clipping budget.
 *
 * The scale is measured on luminance and applied to all three channels, so
 * whatever hue the generator chose survives exactly.
 *
 * `clipBudget` is checked on whichever channel is HIGHEST, not on luminance.
 * Grass is (0.90, 1.00, 0.80) x v, so its green channel runs above its own
 * luminance and clips while the luminance still looks healthy -- which is
 * exactly what happened on the first attempt at this, taking grass from 3%
 * clipped to 18% while the numbers it was being judged by looked fine.
 */
function levelTo(px, count, wantMean, wantSd, clipBudget = 0.005) {
  let sum = 0;
  for (let i = 0; i < count; i++) sum += lum(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]);
  const mean = sum / count;
  let varSum = 0;
  for (let i = 0; i < count; i++) {
    const l = lum(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]) - mean;
    varSum += l * l;
  }
  const sd = Math.sqrt(varSum / count) || 1e-6;
  const spread = wantSd / sd;
  for (let i = 0; i < count; i++) {
    const l = lum(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]);
    const k = l > 1e-6 ? (wantMean + (l - mean) * spread) / l : 0;
    for (let c = 0; c < 3; c++) px[i * 4 + c] *= k;
  }

  // Headroom: find where the brightest channel sits at the top of the budget
  // and bring the whole texture under it, so the detail just created is not
  // thrown away by the clamp on the way out.
  const peaks = new Float64Array(count);
  for (let i = 0; i < count; i++)
    peaks[i] = Math.max(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]);
  peaks.sort();
  const cap = peaks[Math.floor((1 - clipBudget) * (count - 1))];
  if (cap > 1) {
    const k = 1 / cap;
    for (let i = 0; i < count; i++)
      for (let c = 0; c < 3; c++) px[i * 4 + c] *= k;
  }
}

module.exports = { levelTo, lum };
