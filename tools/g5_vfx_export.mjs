// G5 (deity / bingui / trial / hapil) VFX exporter: pixelfx --sheet format, plus
//  - one-shots: the trailing empty frame pixelfx adds is dropped so frame counts match data/art_vfx_list.json;
//  - deity colour variants (신령 고유색 D) as <vfx_id>_<deity>.png/.json; the bare <vfx_id> is the sansin default;
//  - extra meta.pixelfx fields: blend, layer, beat, holdLast, holdLoop, textRect, variant ...
//   node tools/g5_vfx_export.mjs [id ...]
import { join } from "node:path";
import { loadEffect, renderFrames, spriteSheet, save } from "./vendor/pixelfx/tools/lib/fxlib.mjs";
import { DEITY, DEITY_IDS } from "./vendor/pixelfx/src/fx/korean/_g5.js";

const OUT = "C:/Users/김태양/Desktop/KoreaLike/game/assets/vfx";
const D = (id) => ({ palette: DEITY[id].palette, acc: DEITY[id].acc, motif: DEITY[id].motif });
const deityVariants = [{ suffix: "", opts: D("sansin"), variant: "default(sansin)" }, ...DEITY_IDS.map((d) => ({ suffix: `_${d}`, opts: D(d), variant: d }))];
const plain = [{ suffix: "", opts: {}, variant: null }];

export const JOBS = {
  vfx_sinjangdae_descend: deityVariants,
  vfx_hwasin_won: deityVariants,
  vfx_confirm_ring: deityVariants,
  vfx_trial_block_wall: deityVariants,
  vfx_bingui_pillar: deityVariants,
  vfx_sinmyeong_oreum_border: plain,
  vfx_sinmyeong_oreum_aura: plain,
  vfx_eolssigu_slam: plain,
  vfx_union_neoksinkal: plain,
  vfx_union_sogeumsal: plain,
  vfx_union_jakdu_dari_ring: plain,
  vfx_union_chilseong_mgg: plain,
  vfx_union_obang_cheoljin: plain,
  vfx_union_sanullim: plain,
};

const empty = (f) => { for (let i = 3; i < f.clear.length; i += 4) if (f.clear[i]) return false; return true; };
const want = process.argv.slice(2);
const made = [];
for (const [vid, variants] of Object.entries(JOBS)) {
  if (want.length && !want.includes(vid)) continue;
  const fx = await loadEffect(`korean/${vid}`);
  for (const v of variants) {
    const r = renderFrames(fx, { actor: false, options: v.opts });
    if (!fx.meta.loop && r.frames.length > 1 && empty(r.frames[r.frames.length - 1])) { r.frames.pop(); r.n = r.frames.length; }
    const name = vid + v.suffix;
    const s = spriteSheet(fx, r, name);
    const m = fx.meta, px = s.json.meta.pixelfx;
    px.id = vid; px.frameWidth = r.w; px.frameHeight = r.h;
    for (const k of ["blend", "layer", "beat", "holdLast", "holdLoop", "textRect", "subtitleRect", "rotate", "hit", "scope"]) if (m[k] !== undefined) px[k] = m[k];
    if (v.variant) px.variant = v.variant;
    save(join(OUT, `${name}.png`), s.png);
    save(join(OUT, `${name}.json`), JSON.stringify(s.json, null, 1));
    made.push({ name, frames: r.n, w: r.w, h: r.h });
  }
}
for (const m of made) console.log(`${m.name}  ${m.frames}f  ${m.w}x${m.h}`);
