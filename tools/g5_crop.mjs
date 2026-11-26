// G5 helper: render an effect and save zoomed crops of chosen frames side by side (for inspecting big canvases).
//   node tools/g5_crop.mjs <id> <x> <y> <w> <h> <zoom> <frames comma> [optsJSON] [out.png]
import { loadEffect, renderFrames, save } from "./vendor/pixelfx/tools/lib/fxlib.mjs";
import { encodePNG } from "./vendor/pixelfx/tools/lib/png.mjs";

const [id, X, Y, W, H, Z, FR, OPTS, OUT] = process.argv.slice(2);
const x0 = +X, y0 = +Y, w = +W, h = +H, z = +Z, frames = FR.split(",").map(Number);
const fx = await loadEffect(id);
const r = renderFrames(fx, { actor: false, options: OPTS ? JSON.parse(OPTS) : undefined });
const gap = 4, CW = w * z, OW = frames.length * (CW + gap), OH = h * z;
const out = new Uint8ClampedArray(OW * OH * 4);
frames.forEach((fi, k) => {
  const src = r.frames[Math.min(fi, r.n - 1)].color;
  for (let yy = 0; yy < OH; yy++)
    for (let xx = 0; xx < CW; xx++) {
      const sx = x0 + Math.floor(xx / z), sy = y0 + Math.floor(yy / z);
      if (sx < 0 || sy < 0 || sx >= r.w || sy >= r.h) continue;
      const si = (sy * r.w + sx) * 4, di = (yy * OW + k * (CW + gap) + xx) * 4;
      out[di] = src[si]; out[di + 1] = src[si + 1]; out[di + 2] = src[si + 2]; out[di + 3] = 255;
    }
});
const file = OUT ?? `C:/Users/김태양/AppData/Local/Temp/claude/753e94647db49f01/1fd1a688-e4b3-466e-b94a-06f22ba391be/scratchpad/crop.png`;
save(file, encodePNG(OW, OH, out));
console.log(file);
