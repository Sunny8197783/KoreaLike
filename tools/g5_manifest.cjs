// G5 manifest part writer: game/assets/manifest_parts/vfx_G5_deity_bingui_trial_hapil.json
const fs = require('fs');
const spec = require('../data/art_vfx_list.json');
const rows = Object.fromEntries(spec.vfx.map(r => [r[0], r]));
const V = 'game/assets/vfx/';
const ids = ['vfx_sinjangdae_descend','vfx_hwasin_won','vfx_confirm_ring','vfx_trial_block_wall','vfx_bingui_pillar','vfx_bingui_pattern_sweep','vfx_sinmyeong_oreum_border','vfx_sinmyeong_oreum_aura','vfx_eolssigu_slam','vfx_union_neoksinkal','vfx_union_sogeumsal','vfx_union_jakdu_dari_ring','vfx_union_chilseong_mgg','vfx_union_obang_cheoljin','vfx_union_sanullim'];
const deities = ['sansin','yongwang','chilseong','janggun','barigongju','jeseok_daegam'];
const items = [];
for (const id of ids) {
  const r = rows[id];
  if (!r) throw new Error('not in spec: ' + id);
  const base = { kind: 'vfx', source: 'pixelfx', source_file: 'tools/vendor/pixelfx/src/fx/korean/' + id + '.js', license: 'original (project-made; pixelfx tool MIT)', status: r[11] === 'x1' ? 'placeholder_x1' : 'done', timing: r[6], blend: r[7], layer: r[8], beat_snap: r[9], max_concurrent: r[10], color_role: r[3], scope: r[11] };
  if (id === 'vfx_bingui_pattern_sweep') {
    items.push({ id, path: V + id + '.gdshader', json: V + id + '.json', ...base, kind: 'vfx_shader', source: 'handwritten', source_file: V + id + '.gdshader', frames: 0, note: 'Compile + visual test on Godot 4.7.2 (Compatibility). Tween zone_progress 0->1 over 0.3s at t=0.60s.' });
    items.push({ id: 'vfx_bingui_pattern_tiles', path: V + 'vfx_bingui_pattern_tiles.png', json: V + 'vfx_bingui_pattern_tiles.json', ...base, kind: 'vfx_shader_texture', source: 'handwritten (procedural pixel tiles)', source_file: 'tools/g5_pattern_tiles.mjs', frames: 1, frame_size: [16, 16], note: '12 data-mask tiles 16x16, seamless (R primary, G secondary, B saekdong index). Review image: vfx_bingui_pattern_tiles_preview.png' });
    continue;
  }
  const j = JSON.parse(fs.readFileSync(V + id + '.json', 'utf8')).meta.pixelfx;
  const it = { id, path: V + id + '.png', json: V + id + '.json', ...base, frames: j.frames, frame_size: j.frameSize, fps: j.fps, loop: j.loop, pivot: j.pivot };
  for (const k of ['holdLast','holdLoop','textRect','subtitleRect','rotate','hit','beat']) if (j[k] !== undefined) it[k] = j[k];
  if (fs.existsSync(V + id + '_sansin.png')) { it.variants = deities.map(d => ({ deity: 'deity_' + d, path: V + id + '_' + d + '.png', json: V + id + '_' + d + '.json' })); it.note = 'bare file = sansin default; per-deity palette variants (color role D)'; }
  items.push(it);
}
const out = {
  agent: 'vfx_G5_deity_bingui_trial_hapil', group: 'G5_deity_bingui_trial_hapil',
  tools: ['pixelfx (tools/vendor/pixelfx/src/fx/korean/vfx_*.js + _g5.js helpers)', 'tools/g5_vfx_export.mjs (sheet export, deity variants, trailing-empty-frame trim)', 'tools/g5_pattern_tiles.mjs', 'tools/g5_crop.mjs (zoomed review crops)', 'tools/g5_manifest.cjs', 'Godot 4.7.2 compile/visual test of the shader'],
  pixellab_generations_used_estimate: 0, items,
  known_issues: [
    'vfx_hwasin_won / vfx_trial_block_wall: 404px canvases for the r=6u (192px) circle. Under add blend the charcoal (숯) only shows as an ember dot; normal blend for the rope would read better',
    'vfx_eolssigu_slam: text NOT baked. Engine renders real calligraphy font text in meta.pixelfx.textRect (canvas px) and the localized subtitle in subtitleRect',
    'vfx_union_sogeumsal: rotate=16 in engine (2-frame sheet faces right)',
    'vfx_union_obang_cheoljin (canon rename of jin_obangjin) / vfx_union_sanullim: x1 placeholders (frame/timing only)',
    'hold semantics: holdLast = keep the last frame until removed; holdLoop [a,b] = after one play, loop frames a..b',
    'beat-synced loops (hwasin_won beat 2, sinmyeong border/aura beat 1, obang_cheoljin): sheet fps is nominal, the engine should step frames from the beat clock (frame 0 = on the beat)'
  ]
};
fs.writeFileSync('game/assets/manifest_parts/vfx_G5_deity_bingui_trial_hapil.json', JSON.stringify(out, null, 1));
console.log(items.length, 'items');
