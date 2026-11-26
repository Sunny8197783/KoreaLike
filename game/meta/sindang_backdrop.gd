extends Node2D
## 신당 본채 실내(굿당) 배경 — 신단·무신도·촛대·연등·오방기·신장대·금줄·넋전·장독·정화수·길베·매듭·짚신.
## 소유: meta. 신당 단장(sindang_danjang) 랭크에 따라 소품이 늘어난다("신당이 채워지는" 감각, 09 §5.5).
## 그리기: _draw 일괄(고정 배열, 프레임당 할당 없음). 빛은 가산 합성 자식(GlowLayer), 불티·종이 조각은 FrontLayer.
## 색: data/art_palette.json 램프만(먹·흙·석간주·한지·황·적·단청). 백(#f2ece0)은 쓰지 않는다(해원 예약).

const PROPS: String = "res://assets/props/"
const W_MIN: float = -96.0
const W_MAX: float = 736.0
const FLOOR_Y: float = 214.0

# 팔레트(art_palette.json)
const C_MK0: Color = Color("0e0b16")
const C_MK1: Color = Color("17131f")
const C_MK2: Color = Color("221c2e")
const C_MK3: Color = Color("2f2840")
const C_MK4: Color = Color("3f3654")
const C_MK5: Color = Color("544a6b")
const C_ET0: Color = Color("1b1511")
const C_ET1: Color = Color("2c221a")
const C_ET2: Color = Color("433426")
const C_ET3: Color = Color("5e4b36")
const C_ET4: Color = Color("7c674b")
const C_DANJU: Color = Color("6b3a2a")
const C_DANJU_HI: Color = Color("7a3a2c")
const C_JK0: Color = Color("561318")
const C_JK1: Color = Color("8c1f22")
const C_JK2: Color = Color("c8322d")
const C_HW0: Color = Color("6a4a12")
const C_HW1: Color = Color("a97c1b")
const C_HW2: Color = Color("e8b931")
const C_HW3: Color = Color("f5d66b")
const C_HW4: Color = Color("fff1b8")
const C_HJ0: Color = Color("5a4a37")
const C_HJ1: Color = Color("857154")
const C_HJ2: Color = Color("b29d76")
const C_HJ3: Color = Color("d2c19c")
const C_HJ4: Color = Color("e9dcc0")
const C_GOLD_DC: Color = Color("8a7440")
const C_NOK: Color = Color("3e6a5a")
const C_GUN: Color = Color("3b4f6e")

const EMBER_N: int = 40
const PAPER_N: int = 48
const DUST_N: int = 24

var ranks: Dictionary = {}            # dj_id -> rank
var shake: float = 0.0                # 0..1 (로비 흔들림, 정수 픽셀)
var dim: float = 0.0                  # 0..1 (패널·연출 때 배경 살짝 어둡게)

var _t: float = 0.0
var _tex: Dictionary = {}             # prop name -> Texture2D
var _candles: PackedVector2Array = PackedVector2Array()   # 불꽃 위치(빛·불티 원천)
var _lanterns: PackedVector2Array = PackedVector2Array()
var _lantern_lit: PackedByteArray = PackedByteArray()
var _prop_rect: Dictionary = {}       # dj_id -> Rect2 (가장 최근에 놓인 소품)
var _flash_id: String = ""
var _flash_t: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# 불티(촛불에서 오르는 불똥)
var _em_pos: PackedVector2Array = PackedVector2Array()
var _em_vel: PackedVector2Array = PackedVector2Array()
var _em_life: PackedFloat32Array = PackedFloat32Array()
var _em_max: PackedFloat32Array = PackedFloat32Array()
# 종이 조각(봉헌 순간 흩날리는 한지·적·황 조각)
var _pp_pos: PackedVector2Array = PackedVector2Array()
var _pp_vel: PackedVector2Array = PackedVector2Array()
var _pp_life: PackedFloat32Array = PackedFloat32Array()
var _pp_col: PackedInt32Array = PackedInt32Array()
# 먼지(빛 속을 떠도는)
var _du_pos: PackedVector2Array = PackedVector2Array()
var _du_ph: PackedFloat32Array = PackedFloat32Array()

var glow: Node2D
var front: Node2D
var char_sprite: Sprite2D
var _shadow_tex: Texture2D
var _glow_tex: Texture2D
var _glow_big: Texture2D
var _char_frames: Array[Texture2D] = []
var _char_hop: float = 0.0
var _char_flash: float = 0.0
var _char_id: StringName = &""
var base_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_rng.seed = 7041
	for n: String in ["prop_gutsang", "prop_musindo_hanging", "prop_chotdae_pair", "prop_chotdae_pair_sheet",
			"prop_obanggi_bundle", "prop_obanggi_bundle_sheet", "prop_sinjangdae", "prop_sinjangdae_sheet",
			"prop_neokjeon_line", "prop_neokjeon_line_sheet", "prop_yeondeung", "prop_yeondeung_sheet", "prop_yeondeung_off",
			"prop_jangdok", "prop_geumjul_seg", "obj_gongmulsang_full", "prop_seokdeung_sheet", "prop_seokdeung"]:
		_tex[n] = SpriteLib.tex(PROPS + n + ".png")
	_shadow_tex = SpriteLib.shadow_tex(28, 8)
	_glow_tex = SpriteLib.dot(24, C_HW2, true)
	_glow_big = SpriteLib.dot(96, C_HW1, true)
	glow = Node2D.new()
	glow.name = "GlowLayer"
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.draw.connect(_draw_glow)
	add_child(glow)
	char_sprite = Sprite2D.new()
	char_sprite.name = "Char"
	char_sprite.centered = true
	add_child(char_sprite)
	front = Node2D.new()
	front.name = "FrontLayer"
	front.draw.connect(_draw_front)
	add_child(front)
	_em_pos.resize(EMBER_N)
	_em_vel.resize(EMBER_N)
	_em_life.resize(EMBER_N)
	_em_max.resize(EMBER_N)
	_em_life.fill(0.0)
	_pp_pos.resize(PAPER_N)
	_pp_vel.resize(PAPER_N)
	_pp_life.resize(PAPER_N)
	_pp_col.resize(PAPER_N)
	_pp_life.fill(0.0)
	_du_pos.resize(DUST_N)
	_du_ph.resize(DUST_N)
	for i in DUST_N:
		_du_pos[i] = Vector2(_rng.randf_range(150.0, 490.0), _rng.randf_range(40.0, 200.0))
		_du_ph[i] = _rng.randf() * TAU
	refresh({})


## 단장 랭크 반영(소품 배치 다시 계산).
func refresh(p_ranks: Dictionary) -> void:
	ranks = p_ranks.duplicate()
	_layout()
	queue_redraw()


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func set_character(id: StringName, celebrate: bool = false) -> void:
	if id != _char_id:
		_char_id = id
		_char_frames = SpriteLib.anim_frames_any(String(id), "idle", "south")
		if _char_frames.is_empty():
			_char_frames = [SpriteLib.dir_tex(String(id), "south", 64)]
		var t: Texture2D = _char_frames[0]
		var piv: Variant = SpriteLib.anchor_meta(String(id)).get("pivot", null)
		var py: float = float((piv as Vector2i).y) if piv is Vector2i else float(t.get_height() - 6)
		char_sprite.offset = Vector2(0.0, roundf(float(t.get_height()) * 0.5 - py))
	if celebrate:
		_char_hop = 1.0
		_char_flash = 1.0


## 단장 봉헌 연출: 그 소품이 빛나며 내려앉고 한지 조각이 흩날린다.
func celebrate(dj_id: String) -> void:
	_flash_id = dj_id
	_flash_t = 1.0
	shake = maxf(shake, 0.6)
	var r: Rect2 = _prop_rect.get(dj_id, Rect2(300, 120, 40, 40))
	burst(r.get_center(), 28)


func burst(at: Vector2, n: int) -> void:
	var made: int = 0
	for i in PAPER_N:
		if made >= n:
			break
		if _pp_life[i] > 0.0:
			continue
		var a: float = _rng.randf_range(-PI, 0.0)
		var sp: float = _rng.randf_range(40.0, 110.0)
		_pp_pos[i] = at + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))
		_pp_vel[i] = Vector2(cos(a) * sp, sin(a) * sp - 20.0)
		_pp_life[i] = _rng.randf_range(0.9, 1.6)
		_pp_col[i] = _rng.randi_range(0, 3)
		made += 1


func _layout() -> void:
	_candles.clear()
	_lanterns.clear()
	_lantern_lit.clear()
	_prop_rect.clear()
	# 촛대: 기본 1쌍씩 양 끝, 촛불 랭크마다 더한다
	var cx: PackedFloat32Array = PackedFloat32Array([214.0, 410.0, 234.0, 390.0, 252.0, 372.0, 270.0, 354.0])
	var n_pairs: int = 2 + rank("dj_chotbul") * 2
	for i in mini(n_pairs, cx.size()):
		var top: float = 126.0 if i < 2 else (128.0 if i < 4 else 110.0)
		_candles.append(Vector2(cx[i], top))
	if rank("dj_chotbul") > 0:
		_prop_rect["dj_chotbul"] = Rect2(cx[n_pairs - 2] - 8.0, 120.0, 16.0, 24.0)
	var lx: PackedFloat32Array = PackedFloat32Array([118.0, 522.0, 82.0, 558.0])
	for i in 4:
		var lit: bool = i < rank("dj_yeondeung") * 2
		if i < 2 or lit:
			_lanterns.append(Vector2(lx[i], 58.0 + (8.0 if i >= 2 else 0.0)))
			_lantern_lit.append(1 if lit else 0)
	_prop_rect["dj_yeondeung"] = Rect2(lx[mini(3, maxi(0, rank("dj_yeondeung") * 2 - 1))] - 8.0, 46.0, 16.0, 24.0)
	var nm: int = 3 + rank("dj_musindo")
	_prop_rect["dj_musindo"] = Rect2(_musindo_x(nm - 1, nm), 26.0, 32.0, 48.0)
	_prop_rect["dj_jeonghwasu"] = Rect2(304.0, 136.0, 32.0, 16.0)
	_prop_rect["dj_neokjeon"] = Rect2(200.0, 14.0, 240.0, 16.0)
	_prop_rect["dj_obanggi"] = Rect2(134.0 if rank("dj_obanggi") <= 1 else 474.0, 150.0, 32.0, 64.0)
	_prop_rect["dj_sinjangdae"] = Rect2(458.0 if rank("dj_sinjangdae") <= 1 else 166.0, 150.0, 16.0, 64.0)
	_prop_rect["dj_geumjul"] = Rect2(208.0, 196.0, 224.0, 16.0)
	_prop_rect["dj_jangdok"] = Rect2(548.0, 252.0, 32.0, 32.0)
	_prop_rect["dj_gilbe"] = Rect2(58.0, 20.0, 14.0, 170.0)
	_prop_rect["dj_puri"] = Rect2(590.0, 70.0, 14.0, 60.0)
	_prop_rect["dj_jipsin"] = Rect2(250.0, 300.0, 24.0, 10.0)


func _musindo_x(i: int, n: int) -> float:
	var spacing: float = 42.0
	return roundf(320.0 - spacing * float(n - 1) * 0.5 + spacing * float(i) - 16.0)


func _process(delta: float) -> void:
	_t += delta
	shake = maxf(0.0, shake - delta * 2.5)
	_flash_t = maxf(0.0, _flash_t - delta * 1.4)
	_char_hop = maxf(0.0, _char_hop - delta * 3.0)
	_char_flash = maxf(0.0, _char_flash - delta * 2.0)
	var sx: float = 0.0
	var sy: float = 0.0
	if shake > 0.0:
		var a: float = shake * shake * 3.0
		sx = roundf(sin(_t * 61.0) * a)
		sy = roundf(cos(_t * 47.0) * a)
	position = (base_pos + Vector2(sx, sy)).round()
	# 캐릭터 idle(6fps) + 깡충(정수 픽셀)
	if not _char_frames.is_empty():
		var fi: int = int(_t * 6.0) % _char_frames.size()
		char_sprite.texture = _char_frames[fi]
	var hop: float = -roundf(sin(_char_hop * PI) * 5.0)
	char_sprite.position = Vector2(320.0, 292.0 + hop)
	char_sprite.modulate = Color(1, 1, 1, 1)
	# 불티
	for i in EMBER_N:
		if _em_life[i] > 0.0:
			_em_life[i] -= delta
			var v: Vector2 = _em_vel[i]
			v.x += sin(_t * 3.0 + float(i)) * 6.0 * delta
			_em_vel[i] = v
			_em_pos[i] += v * delta
		elif not _candles.is_empty() and _rng.randf() < delta * 2.2:
			var c: Vector2 = _candles[_rng.randi_range(0, _candles.size() - 1)]
			_em_pos[i] = c + Vector2(_rng.randf_range(-3.0, 3.0), -4.0)
			_em_vel[i] = Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-16.0, -8.0))
			_em_max[i] = _rng.randf_range(1.4, 3.2)
			_em_life[i] = _em_max[i]
	for i in PAPER_N:
		if _pp_life[i] > 0.0:
			_pp_life[i] -= delta
			var v2: Vector2 = _pp_vel[i]
			v2.y += 120.0 * delta
			v2.x *= 1.0 - 1.8 * delta
			v2.y = minf(v2.y, 50.0)
			_pp_vel[i] = v2
			_pp_pos[i] += v2 * delta + Vector2(sin(_t * 9.0 + float(i)) * 12.0 * delta, 0.0)
	for i in DUST_N:
		_du_ph[i] += delta * 0.4
		var p: Vector2 = _du_pos[i]
		p.y -= delta * 2.0
		p.x += sin(_du_ph[i]) * delta * 3.0
		if p.y < 30.0:
			p = Vector2(_rng.randf_range(150.0, 490.0), 210.0)
		_du_pos[i] = p
	queue_redraw()
	glow.queue_redraw()
	front.queue_redraw()


func _frame(sheet: String, single: String, fps: float, phase: float = 0.0) -> Vector2i:
	var st: Texture2D = _tex.get(sheet)
	var sg: Texture2D = _tex.get(single)
	if st == null or sg == null:
		return Vector2i(0, 1)
	var n: int = maxi(1, st.get_width() / maxi(1, sg.get_width()))
	return Vector2i(int(_t * fps + phase) % n, n)


func _draw_sheet(sheet: String, single: String, pos: Vector2, fps: float, phase: float = 0.0, mod: Color = Color.WHITE) -> void:
	var st: Texture2D = _tex.get(sheet)
	var sg: Texture2D = _tex.get(single)
	if st == null:
		if sg != null:
			draw_texture(sg, pos.round(), mod)
		return
	var f: Vector2i = _frame(sheet, single, fps, phase)
	var w: float = float(sg.get_width())
	draw_texture_rect_region(st, Rect2(pos.round(), Vector2(w, float(sg.get_height()))), Rect2(float(f.x) * w, 0.0, w, float(sg.get_height())), mod)


func _draw() -> void:
	# ── 바닥(마루) ──
	draw_rect(Rect2(W_MIN, FLOOR_Y, W_MAX - W_MIN, 360.0 - FLOOR_Y), C_ET1)
	var row: int = 0
	var y: float = FLOOR_Y + 2.0
	while y < 360.0:
		draw_rect(Rect2(W_MIN, y, W_MAX - W_MIN, 1.0), C_ET0)
		var off: float = 37.0 * float(row % 3)
		var x: float = W_MIN + off
		while x < W_MAX:
			draw_rect(Rect2(x, y + 1.0, 1.0, 11.0), C_ET0)
			x += 113.0
		if row % 2 == 0:
			draw_rect(Rect2(W_MIN, y + 1.0, W_MAX - W_MIN, 1.0), Color(C_ET2, 0.5))
		y += 12.0
		row += 1
	# 돗자리
	var mat: Rect2 = Rect2(236.0, 246.0, 168.0, 64.0)
	draw_rect(mat.grow(1.0), C_ET0)
	draw_rect(mat, C_HW0)
	var my: float = mat.position.y + 2.0
	while my < mat.end.y - 1.0:
		draw_rect(Rect2(mat.position.x + 2.0, my, mat.size.x - 4.0, 1.0), C_GOLD_DC)
		my += 3.0
	draw_rect(Rect2(mat.position.x, mat.position.y, mat.size.x, 3.0), C_JK0)
	draw_rect(Rect2(mat.position.x, mat.end.y - 3.0, mat.size.x, 3.0), C_JK0)
	# ── 벽(판벽) ──
	draw_rect(Rect2(W_MIN, 0.0, W_MAX - W_MIN, FLOOR_Y), C_MK1)
	var bx: float = 52.0
	while bx < 588.0:
		draw_rect(Rect2(bx, 14.0, 15.0, FLOOR_Y - 14.0), C_MK2)
		bx += 16.0
	draw_rect(Rect2(52.0, 98.0, 536.0, 3.0), C_MK3)      # 인방
	# 창호(달빛): 좌우
	_draw_window(Rect2(W_MIN, 30.0, 126.0 + 2.0, 150.0))
	_draw_window(Rect2(606.0, 30.0, W_MAX - 606.0, 150.0))
	# 기둥
	for px: float in [36.0, 590.0]:
		draw_rect(Rect2(px, 0.0, 16.0, FLOOR_Y + 2.0), C_DANJU)
		draw_rect(Rect2(px, 0.0, 2.0, FLOOR_Y + 2.0), C_DANJU_HI)
		draw_rect(Rect2(px + 14.0, 0.0, 2.0, FLOOR_Y + 2.0), C_ET1)
		# 부적 한 장
		draw_rect(Rect2(px + 4.0, 112.0, 8.0, 20.0), C_HJ3)
		draw_rect(Rect2(px + 5.0, 114.0, 6.0, 1.0), C_JK2)
		draw_rect(Rect2(px + 7.0, 116.0, 2.0, 12.0), C_JK1)
		draw_rect(Rect2(px + 5.0, 129.0, 6.0, 1.0), C_JK2)
	# 걸레받이
	draw_rect(Rect2(W_MIN, FLOOR_Y - 2.0, W_MAX - W_MIN, 3.0), C_ET0)
	# 들보 + 단청
	draw_rect(Rect2(W_MIN, 0.0, W_MAX - W_MIN, 14.0), C_MK3)
	UiKit.draw_dancheong(self, Rect2(W_MIN, 2.0, W_MAX - W_MIN, 6.0))
	draw_rect(Rect2(W_MIN, 13.0, W_MAX - W_MIN, 1.0), C_MK0)
	# ── 무신도 ──
	var nm: int = 3 + rank("dj_musindo")
	var mt: Texture2D = _tex.get("prop_musindo_hanging")
	for i in nm:
		var mx: float = _musindo_x(i, nm)
		draw_rect(Rect2(mx + 15.0, 14.0, 2.0, 12.0), C_HJ1)          # 걸개 끈
		if mt != null:
			draw_texture(mt, Vector2(mx, 26.0))
	# ── 넋전 줄 ──
	var nr: int = rank("dj_neokjeon")
	for r in nr:
		var ly: float = 16.0 + float(r) * 10.0
		var lx0: float = 192.0 - float(r) * 64.0
		var segs: int = 4 + r * 2
		for s in segs:
			_draw_sheet("prop_neokjeon_line_sheet", "prop_neokjeon_line", Vector2(lx0 + float(s) * 64.0, ly), 1.5, float(s + r))
	# ── 금줄(들보) ──
	if rank("dj_geumjul") >= 2:
		var gt: Texture2D = _tex.get("prop_geumjul_seg")
		if gt != null:
			var gx: float = 64.0
			while gx < 576.0:
				draw_texture(gt, Vector2(gx, 84.0))
				gx += 32.0
	# ── 신단(뒤 선반 + 상) ──
	draw_rect(Rect2(236.0, 104.0, 168.0, 24.0), C_ET1)
	draw_rect(Rect2(236.0, 104.0, 168.0, 2.0), C_ET3)
	draw_rect(Rect2(232.0, 102.0, 176.0, 2.0), C_ET4)
	var gs: Texture2D = _tex.get("prop_gutsang")
	if gs != null:
		draw_texture(gs, Vector2(256.0, 96.0 - 0.0) + Vector2(0.0, -2.0))
		draw_texture(gs, Vector2(320.0, 94.0))
	# 상 위판·치마
	draw_rect(Rect2(200.0, 150.0, 240.0, 6.0), C_ET3)
	draw_rect(Rect2(200.0, 150.0, 240.0, 1.0), C_ET4)
	draw_rect(Rect2(204.0, 156.0, 232.0, 40.0), C_JK0)
	draw_rect(Rect2(204.0, 158.0, 232.0, 6.0), C_JK1)
	UiKit.draw_dancheong(self, Rect2(204.0, 156.0, 232.0, 4.0))
	draw_rect(Rect2(204.0, 192.0, 232.0, 4.0), C_HJ0)
	for k in 6:
		draw_rect(Rect2(214.0 + float(k) * 40.0, 166.0, 1.0, 26.0), Color(C_JK1, 0.6))
	# 공물
	var gm: Texture2D = _tex.get("obj_gongmulsang_full")
	if gm != null:
		draw_texture(gm, Vector2(288.0, 120.0))
	# 정화수
	var jr: int = rank("dj_jeonghwasu")
	for k in jr:
		var bxp: float = 312.0 + (float(k) * 2.0 - float(jr - 1)) * 14.0
		draw_rect(Rect2(bxp - 1.0, 146.0, 10.0, 4.0), C_HJ1)
		draw_rect(Rect2(bxp, 145.0, 8.0, 2.0), C_HJ4)
		draw_rect(Rect2(bxp + 1.0, 145.0, 6.0, 1.0), C_NOK)
	# 촛대
	for i in _candles.size():
		var c: Vector2 = _candles[i]
		_draw_sheet("prop_chotdae_pair_sheet", "prop_chotdae_pair", c + Vector2(-8.0, -2.0), 8.0, float(i) * 1.7)
	# ── 금줄(상 앞) ──
	if rank("dj_geumjul") >= 1:
		var gt2: Texture2D = _tex.get("prop_geumjul_seg")
		if gt2 != null:
			var gx2: float = 208.0
			while gx2 < 432.0:
				draw_texture(gt2, Vector2(gx2, 196.0))
				gx2 += 32.0
	# ── 연등 ──
	for i in _lanterns.size():
		var lp: Vector2 = _lanterns[i]
		draw_rect(Rect2(lp.x, 14.0, 1.0, lp.y - 14.0), C_HJ0)
		var sway: float = roundf(sin(_t * 1.3 + float(i)) * 1.0)
		if _lantern_lit[i] == 1:
			_draw_sheet("prop_yeondeung_sheet", "prop_yeondeung", Vector2(lp.x - 8.0 + sway, lp.y), 3.0, float(i))
		else:
			var off_t: Texture2D = _tex.get("prop_yeondeung_off")
			if off_t != null:
				draw_texture(off_t, Vector2(lp.x - 8.0 + sway, lp.y))
	# ── 길베(한지 무명 자락) ──
	var gr: int = rank("dj_gilbe")
	if gr > 0:
		var gl: float = 120.0 + 50.0 * float(gr)
		var gwav: float = roundf(sin(_t * 0.9) * 1.0)
		draw_rect(Rect2(60.0 + gwav, 14.0, 10.0, gl), C_HJ3)
		draw_rect(Rect2(60.0 + gwav, 14.0, 2.0, gl), C_HJ4)
		draw_rect(Rect2(68.0 + gwav, 14.0, 2.0, gl), C_HJ2)
		if gr >= 2:
			draw_rect(Rect2(60.0, FLOOR_Y + 2.0, 96.0, 6.0), C_HJ3)
			draw_rect(Rect2(60.0, FLOOR_Y + 2.0, 96.0, 1.0), C_HJ4)
	# ── 고풀이 매듭(기둥에 매단 붉은 끈) ──
	var pr: int = rank("dj_puri")
	for k in pr:
		var kx: float = 597.0 if k == 0 else 43.0
		draw_rect(Rect2(kx, 60.0, 1.0, 60.0), C_JK1)
		for m in 3:
			var ky: float = 72.0 + float(m) * 16.0
			draw_rect(Rect2(kx - 2.0, ky, 5.0, 4.0), C_JK2)
			draw_rect(Rect2(kx - 1.0, ky + 1.0, 3.0, 1.0), C_HJ4)
	# ── 오방기·신장대 ──
	var orank: int = rank("dj_obanggi")
	for k in orank:
		var ox: float = 134.0 if k == 0 else 474.0
		_draw_sheet("prop_obanggi_bundle_sheet", "prop_obanggi_bundle", Vector2(ox, 150.0), 2.0, float(k))
	var srank: int = rank("dj_sinjangdae")
	for k in srank:
		var sx2: float = 458.0 if k == 0 else 166.0
		_draw_sheet("prop_sinjangdae_sheet", "prop_sinjangdae", Vector2(sx2, 150.0), 2.5, float(k) + 0.5)
	# ── 장독 ──
	var jt: Texture2D = _tex.get("prop_jangdok")
	if jt != null:
		for k in rank("dj_jangdok"):
			draw_texture(jt, Vector2(548.0 - float(k) * 30.0, 252.0 + float(k) * 6.0))
	# ── 짚신 ──
	for k in rank("dj_jipsin"):
		var zx: float = 252.0 - float(k) * 0.0 + float(k) * 128.0
		for s in 2:
			var zr: Rect2 = Rect2(zx + float(s) * 9.0, 300.0 + float(s), 7.0, 4.0)
			draw_rect(zr.grow(1.0), C_ET0)
			draw_rect(zr, C_HW1)
			draw_rect(Rect2(zr.position + Vector2(1, 1), Vector2(5, 1)), C_HW0)
	# ── 바닥 그림자(캐릭터) ──
	if _shadow_tex != null:
		draw_texture(_shadow_tex, Vector2(306.0, 288.0), Color(1, 1, 1, 0.8))
	# 화면 아래·가장자리 어둡게(먹)
	for i in 6:
		draw_rect(Rect2(W_MIN, 360.0 - 6.0 * float(i + 1), W_MAX - W_MIN, 6.0), Color(C_MK0, 0.1 * float(6 - i)))


func _draw_window(r: Rect2) -> void:
	draw_rect(r, C_MK3)
	var x: float = r.position.x + 2.0
	while x < r.end.x:
		draw_rect(Rect2(x, r.position.y, 1.0, r.size.y), C_MK1)
		x += 9.0
	var y: float = r.position.y + 2.0
	while y < r.end.y:
		draw_rect(Rect2(r.position.x, y, r.size.x, 1.0), C_MK1)
		y += 11.0
	draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 3.0), C_ET1)


func _draw_glow() -> void:
	var flick: float = 0.0
	for i in _candles.size():
		var c: Vector2 = _candles[i]
		flick = 0.82 + 0.18 * sin(_t * (9.0 + float(i)) + float(i) * 2.1) * sin(_t * 3.7 + float(i))
		glow.draw_texture(_glow_tex, (c - Vector2(12.0, 14.0)).round(), Color(1, 1, 1, 0.55 * flick))
	# 신단 전체 은은한 빛
	var n: float = float(_candles.size())
	glow.draw_texture_rect(_glow_big, Rect2(320.0 - 150.0, 30.0, 300.0, 210.0), false, Color(1, 1, 1, clampf(0.10 + 0.03 * n, 0.1, 0.4) * (0.9 + 0.1 * sin(_t * 2.3))))
	for i in _lanterns.size():
		if _lantern_lit[i] == 1:
			var lp: Vector2 = _lanterns[i]
			glow.draw_texture(_glow_tex, lp + Vector2(-12.0, 0.0), Color(1, 0.7, 0.6, 0.5 + 0.08 * sin(_t * 4.0 + float(i))))
	# 봉헌한 소품 번쩍임
	if _flash_t > 0.0 and _prop_rect.has(_flash_id):
		var r: Rect2 = _prop_rect[_flash_id]
		var a: float = _flash_t * _flash_t
		glow.draw_texture_rect(_glow_big, r.grow(18.0), false, Color(1, 1, 1, 0.9 * a))
		glow.draw_rect(r, Color(C_HW3, 0.5 * a))
	if _char_flash > 0.0:
		glow.draw_texture_rect(_glow_big, Rect2(280.0, 220.0, 80.0, 90.0), false, Color(1, 1, 1, _char_flash))
	# 불티
	for i in EMBER_N:
		if _em_life[i] > 0.0:
			var k: float = _em_life[i] / maxf(0.01, _em_max[i])
			glow.draw_rect(Rect2(_em_pos[i].round(), Vector2.ONE), Color(C_HW3 if k > 0.5 else C_HW1, k))


func _draw_front() -> void:
	# 먼지(빛 속)
	for i in DUST_N:
		var a: float = 0.25 + 0.2 * sin(_du_ph[i] * 3.0)
		front.draw_rect(Rect2(_du_pos[i].round(), Vector2.ONE), Color(C_HJ2, a))
	# 종이 조각
	for i in PAPER_N:
		if _pp_life[i] > 0.0:
			var col: Color = C_HJ4
			match _pp_col[i]:
				1: col = C_JK2
				2: col = C_HW2
				3: col = C_HJ3
			var flip: bool = int(_pp_life[i] * 12.0 + float(i)) % 2 == 0
			front.draw_rect(Rect2(_pp_pos[i].round(), Vector2(2.0, 3.0) if flip else Vector2(3.0, 1.0)), Color(col, clampf(_pp_life[i] * 2.0, 0.0, 1.0)))
	# 패널이 열리면 배경을 살짝 눌러 둔다
	if dim > 0.0:
		front.draw_rect(Rect2(W_MIN, 0.0, W_MAX - W_MIN, 360.0), Color(C_MK0, 0.35 * dim))
