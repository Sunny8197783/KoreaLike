// G5: deity pattern tiles (16x16, seamless mod 16) for vfx_bingui_pattern_sweep (design/13 §5.4, §5.6).
// Writes a DATA mask atlas (12 tiles in a row, 192x16): R=255 primary motif (-> deity ramp at the cloth's own
// light/base/shadow step), G=255 secondary (-> deity dark/secondary colour), B = stripe index*40+20 (saekdong
// palette index, bari only). Alpha 255 where the tile paints, 0 where the cloth stays as is.
// Also writes a coloured preview atlas for art review. Order: [sansin, yongwang, chilseong, janggun, barigongju,
// jeseok_daegam] x [wieom, gaho] -> index = deity*2 + face.
//   node tools/g5_pattern_tiles.mjs <outDir>
import { writeFileSync, mkdirSync } from "node:fs";
import { encodePNG } from "./vendor/pixelfx/tools/lib/png.mjs";

const out = process.argv[2] ?? "game/assets/vfx";
const T = 16, mod = (a, m) => ((a % m) + m) % m;
// each tile: (x, y) -> 0 none, 1 primary, 2 secondary, or {s: stripeIndex}
const checker = (x, y) => (x + y) % 2 === 0;
const zig = (y) => Math.abs(mod(y, 8) - 4); // 0..4..0 zigzag, period 8
// Big Dipper: 7 stars inside the tile (bowl 4 + handle 3)
const DIPPER = [[2, 9], [6, 10], [7, 6], [3, 5], [9, 4], [12, 3], [14, 6]];
const near = (x, y, P, r) => P.some(([a, b]) => Math.abs(mod(x - a + 8, 16) - 8) + Math.abs(mod(y - b + 8, 16) - 8) <= r);
const tiles = [
  // 산신 위엄: bold tiger stripes (secondary black) on gold (primary)
  (x, y) => (mod(x + zig(y) - Math.floor(y / 8) * 2, 8) < 2.5 ? 2 : 1),
  // 산신 가호: thin stripes, dithered
  (x, y) => (mod(x + zig(y), 8) < 1 && checker(x, y) ? 1 : 0),
  // 용왕 위엄: cloud-wave bands (운문), primary crest + secondary trough
  (x, y) => { const w = Math.round(2 * Math.sin((x / 16) * Math.PI * 2)); const r = mod(y - w, 8); return r < 2 ? 1 : r === 2 ? 2 : 0; },
  // 용왕 가호: fine ripples, dithered
  (x, y) => { const w = Math.round(1.5 * Math.sin((x / 16) * Math.PI * 4)); return mod(y - w, 6) === 0 && checker(x, y) ? 1 : 0; },
  // 칠성 위엄: 7 gold stars (primary crosses) on navy (secondary)
  (x, y) => (near(x, y, DIPPER, 0) ? 1 : near(x, y, DIPPER, 1) ? 1 : 2),
  // 칠성 가호: star dots only
  (x, y) => (near(x, y, DIPPER, 0) ? 1 : 0),
  // 장군 위엄: 두정갑 rivets — gold 2x2 studs (primary) on red plates (secondary), stud grid 8px offset rows
  (x, y) => { const ox = Math.floor(y / 8) % 2 ? 4 : 0; return mod(x - ox, 8) < 2 && mod(y, 8) < 2 ? 1 : mod(y, 8) === 7 ? 0 : 2; },
  // 장군 가호: red diagonal sleeve band (구군복 띠), 3px
  (x, y) => (mod(x + y, 16) < 3 ? 1 : 0),
  // 바리공주 위엄: bold saekdong horizontal stripes (6 colours, 2px each, period 12 -> use 16: 5 bands of 3 + 1 gap)
  (x, y) => (mod(y, 16) === 15 ? 2 : { s: Math.floor(mod(y, 16) / 3) % 6 }),
  // 바리공주 가호: thin saekdong lines, dithered
  (x, y) => (mod(y, 4) === 0 && checker(x, y) ? { s: Math.floor(mod(y, 16) / 4) } : 0),
  // 대감 위엄: yeopjeon coins (round with square hole), gold primary, dark rim secondary
  (x, y) => { const cx = mod(x, 8) - 3.5, cy = mod(y, 8) - 3.5, d = Math.hypot(cx, cy); if (Math.abs(cx) < 1 && Math.abs(cy) < 1) return 0; return d < 3.2 ? 1 : d < 4 ? 2 : 0; },
  // 제석 가호: red kasaya band diagonal (붉은 가사 띠 사선), thin, dithered edge
  (x, y) => { const r = mod(x - y, 16); return r < 2 ? 2 : r === 2 && checker(x, y) ? 2 : 0; },
];
const DEITY_COL = [
  ["#e8b931", "#1a1a1a"], ["#55b8aa", "#1d5a58"], ["#e8b931", "#1b3a70"],
  ["#e8b931", "#8c1f22"], ["#f5d66b", "#5a4a37"], ["#e8b931", "#8c1f22"],
];
const SAEK = ["#c8322d", "#f5d66b", "#55b8aa", "#5f93de", "#f4a183", "#e9dcc0"];
const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];

const W = T * tiles.length, mask = new Uint8ClampedArray(W * T * 4), prev = new Uint8ClampedArray(W * T * 4);
const PW = W, PH = T;
tiles.forEach((fn, i) => {
  const dc = DEITY_COL[Math.floor(i / 2)];
  for (let y = 0; y < T; y++)
    for (let x = 0; x < T; x++) {
      const v = fn(x, y), o = (y * W + i * T + x) * 4;
      // preview: cloth base #3f3654 (mk4) so the motif reads
      let pc = hex("#3f3654");
      if (v === 1) { mask.set([255, 0, 0, 255], o); pc = hex(dc[0]); }
      else if (v === 2) { mask.set([0, 255, 0, 255], o); pc = hex(dc[1]); }
      else if (v && typeof v === "object") { mask.set([0, 0, v.s * 40 + 20, 255], o); pc = hex(SAEK[v.s]); }
      prev.set([...pc, 255], o);
    }
});
mkdirSync(out, { recursive: true });
writeFileSync(`${out}/vfx_bingui_pattern_tiles.png`, encodePNG(W, T, mask));
// preview at 2x2 repeat x 4 zoom so seams are visible
const Z = 4, RW = W * 2 * Z, RH = T * 2 * Z, big = new Uint8ClampedArray(RW * RH * 4);
for (let y = 0; y < RH; y++)
  for (let x = 0; x < RW; x++) {
    const tx = Math.floor(x / Z), ty = Math.floor(y / Z);
    const tile = Math.floor(tx / (T * 2)), lx = mod(tx, T), ly = mod(ty, T);
    const s = (ly * W + tile * T + lx) * 4;
    big.set([prev[s], prev[s + 1], prev[s + 2], 255], (y * RW + x) * 4);
  }
writeFileSync(`${out}/vfx_bingui_pattern_tiles_preview.png`, encodePNG(RW, RH, big));
writeFileSync(`${out}/vfx_bingui_pattern_tiles.json`, JSON.stringify({
  image: "vfx_bingui_pattern_tiles.png", tile: [16, 16], count: 12, encoding: "R=primary(deity ramp step), G=secondary, B=saekdong index*40+20, A=paint",
  order: ["sansin_wieom", "sansin_gaho", "yongwang_wieom", "yongwang_gaho", "chilseong_wieom", "chilseong_gaho", "janggun_wieom", "janggun_gaho", "barigongju_wieom", "barigongju_gaho", "daegam_wieom", "jeseok_gaho"],
  saekdong: SAEK, deity_colors: DEITY_COL,
}, null, 1));
console.log("tiles ->", out);
