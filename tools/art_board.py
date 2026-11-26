"""Composes the curated concept-art overview board: python tools/art_board.py (run from art/)."""
from PIL import Image, ImageDraw
SECTIONS = [
    ("KEY ART", ["concept/capsule_soulpath_beomtal.png", "concept/key_art_gutpan.png"], 1),
    ("CORE TWIST / GAMEPLAY", ["concept/core_twist_v2.png", "concept/gameplay_mockup_gildakkeum.png", "concept/gameplay_mockup_rhythm.png", "concept/haewon_consoling_scene.png", "concept/wongwi_return.png", "concept/eodukshini_mechanic.png"], 2),
    ("PLAYABLE MUDANG (64px, walk)", ["characters/_walk_south_all.png"], 1),
    ("SIX DEITIES", ["deities/sansin_a.png", "deities/yongwang_b.png", "deities/chilseong_b.png", "deities/janggun_a.png", "deities/barigongju_a.png", "deities/jeseok_daegam_a.png"], 3),
    ("POSSESSION OVERLAYS", ["concept/possession_variants.png", "concept/possession_janggun_joseon_d.png"], 2),
    ("ENEMIES", ["enemies/lineup_common.png", "enemies/lineup_common_2.png", "enemies/lineup_elite_midboss.png", "enemies/lineup_elite_midboss_2.png", "enemies/_sprites_8dir.png"], 2),
    ("BOSSES", ["bosses/yeoksin_a.png", "bosses/wongyeol_a.png", "bosses/imugi_b.png", "bosses/jeoseung_saja_d.png", "bosses/trial_sansin_tiger_c.png"], 3),
    ("STAGES / LOBBY", ["stages/stage1_guksadang.png", "stages/stage_jindo_ssitgim.png", "stages/stage_east_sea_byeolsin.png", "stages/stage_jeju_chilmeori.png", "stages/stage_final_myeongbu.png", "concept/lobby_sindang.png"], 2),
    ("UI / ITEMS / TILES", ["ui/levelup_blessing_mockup.png", "ui/hud_rhythm_elements.png", "items/icons_sheet_1.png", "items/icons_sheet_2.png", "tilesets/stage1_earth_grass.png", "tilesets/stage1_earth_stone.png"], 3),
]
W, PAD, BG = 1600, 16, (24, 20, 32, 255)
blocks = []
for title, files, cols in SECTIONS:
    cw = (W - PAD * (cols + 1)) // cols
    cells = []
    for f in files:
        im = Image.open(f).convert("RGBA")
        s = max(1, cw // im.width) if im.width <= cw else cw / im.width
        im = im.resize((int(im.width * s), int(im.height * s)), Image.NEAREST)
        cells.append(im)
    rows = [cells[i:i + cols] for i in range(0, len(cells), cols)]
    h = 40 + sum(max(c.height for c in r) + PAD for r in rows)
    blk = Image.new("RGBA", (W, h), BG); d = ImageDraw.Draw(blk)
    d.text((PAD, 12), title, fill=(232, 185, 49, 255))
    y = 40
    for r in rows:
        for i, c in enumerate(r):
            blk.alpha_composite(c, (PAD + i * (cw + PAD) + (cw - c.width) // 2, y))
        y += max(c.height for c in r) + PAD
    blocks.append(blk)
board = Image.new("RGBA", (W, sum(b.height for b in blocks)), BG)
y = 0
for b in blocks:
    board.alpha_composite(b, (0, y)); y += b.height
board.save("ART-BOARD.png")
print(board.size)
