class_name HeldWeapon
extends Node2D
## 손에 든 무기(design/19 §6). 렌더 전용 — 시뮬·판정·난수를 바꾸지 않는다. 소유: held_weapon_attack_fx.
## Player 의 자식(트리 순서: 몸 Sprite 다음, 금 테 Rim 앞). 북쪽을 볼 때는 몸 뒤(절대 z1)로 간다.
## 데이터 주도: data/held_weapons.json — 무구 id(없으면 원본 base_id) → 아틀라스 그림·쥐는 점·축·동작(anim)·무게.
##   표에 없는 무구는 손 무기 없이 지금처럼 동작한다.
## 손 규칙(§6.4): 주손 1(선딜 중 > 1.2초 안에 쏜 것 > 칸 순서 첫 붉은 무구) · 보조손 1(칸 순서 첫 off 무구)
##   · 나머지 off 무구는 쏠 때만 0.25초 '번쩍 등장'(1f 한지 테). 두 손 무구(작두)가 주손이면 보조손은 비운다.
## 각도: 조준 방향을 16단(22.5°)으로 끊고 동작 오프셋을 더한다(서쪽을 보면 좌우 반전). 배율은 1(반전 −1)만.
## 그리기 순서: 그림 → 칼끝 스미어(타격 1f) → 잡힘 점·발사 섬광. 무적 점멸 숨김 틱에는 먹 실루엣.

const HOLD_SEC: float = 1.2            # 주손: 마지막으로 쏜 무구를 이만큼 쥐고 있다
const FLASH_SEC: float = 0.25          # 나머지 무구: 쏠 때만 손에 번쩍 등장
const STEP16: float = PI / 8.0
const COL_INK: Color = Color(0.0549, 0.0431, 0.0863)
const COL_HANJI: Color = Color(233.0 / 255.0, 220.0 / 255.0, 192.0 / 255.0)
const COL_JKHI: Color = Color(228.0 / 255.0, 96.0 / 255.0, 79.0 / 255.0)
## 손 기준점 표(발 피벗 기준, anchors 에 없을 때). 0 S · 1 E · 2 N (서쪽 = 동쪽 x 반전)
const HAND_MAIN: Array[Vector2] = [Vector2(10, -11), Vector2(6, -18), Vector2(9, -12)]
const HAND_OFF: Array[Vector2] = [Vector2(-6, -16), Vector2(4, -22), Vector2(-9, -12)]

static var _defs: Dictionary = {}       # weapon_id(String) -> def
static var _atlas: Texture2D = null
static var _rects: Dictionary = {}      # sprite -> Rect2
static var _loaded: bool = false

var player: Player = null
var _hidden: bool = false                # 무적 점멸 숨김 틱(먹 실루엣)
var _last_fire_t: Dictionary = {}        # weapon_id -> 연출 시각(초)
var _anchor: Dictionary = {}             # "walk_south_3" -> [hand_l(Vector2|null), hand_r]
var _anchor_char: StringName = &""
var _catch_tick: Dictionary = {}         # weapon_id -> 마지막 잡힘 연출 틱
var _was_out: Dictionary = {}
var _behind: bool = false
# 이번 프레임 그릴 것(최대 2: 주손·보조손)
var _draw_w: Array[WeaponBase] = []
var _draw_def: Array[Dictionary] = []
var _draw_role: PackedInt32Array = PackedInt32Array()   # 0 주손 1 보조손 2 번쩍 등장


static func load_defs() -> void:
	if _loaded:
		return
	_loaded = true
	var v: Variant = Data.get_value("held_weapons", "weapons", {})
	if v is Dictionary:
		_defs = v
	var ap: String = String(Data.get_value("held_weapons", "atlas", "res://assets/sprites/held/held_atlas.png"))
	_atlas = load(ap) as Texture2D if ResourceLoader.exists(ap) else null
	var mp: String = String(Data.get_value("held_weapons", "atlas_meta", "res://assets/sprites/held/held_atlas.json"))
	if FileAccess.file_exists(mp):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(mp))
		if j is Dictionary and (j as Dictionary).get("sprites") is Dictionary:
			var sp: Dictionary = j["sprites"]
			for k: String in sp:
				var r: Variant = (sp[k] as Dictionary).get("rect", null)
				if r is Array and (r as Array).size() >= 4:
					_rects[k] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## 무구 → 손 무기 정의(없으면 원본 무구 정의, 그래도 없으면 {}).
static func def_for(w: WeaponBase) -> Dictionary:
	load_defs()
	var d: Variant = _defs.get(String(w.id), null)
	if d == null:
		d = _defs.get(String(w.base_id), null)
	return d if d is Dictionary else {}


func _ready() -> void:
	load_defs()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# ─── 손 기준점(§6.2) ─────────────────────────────────────────────────

func _load_anchors() -> void:
	_anchor_char = player.char_id
	_anchor.clear()
	var cid: String = String(player.char_id)
	var tbl: Variant = Data.tables.get("anchors/" + cid, null)
	if not (tbl is Dictionary):
		return
	var ent: Variant = (tbl as Dictionary).get(cid, tbl)
	if not (ent is Dictionary) or not ((ent as Dictionary).get("frames") is Dictionary):
		return
	var piv: Array = (ent as Dictionary).get("pivot", [32, 58])
	var pv: Vector2 = Vector2(float(piv[0]), float(piv[1]))
	var frames: Dictionary = ent["frames"]
	for k: String in frames:
		var fr: Variant = frames[k]
		if not (fr is Dictionary):
			continue
		var hl: Variant = (fr as Dictionary).get("hand_l", null)
		var hr: Variant = (fr as Dictionary).get("hand_r", null)
		_anchor[k] = [Vector2(float(hl[0]), float(hl[1])) - pv if hl is Array else null,
			Vector2(float(hr[0]), float(hr[1])) - pv if hr is Array else null]


## 손 위치(플레이어 노드 로컬). which: &"main" | &"off" | &"both"
func hand_local(which: StringName) -> Vector2:
	if player == null:
		return Vector2(0, -16)
	if _anchor_char != player.char_id:
		_load_anchors()
	var f: int = player.facing
	var west: bool = f == K.Dir.WEST
	var d3: int = 0
	var dname: String = "south"
	if f == K.Dir.EAST or west:
		d3 = 1
		dname = "east"
	elif f == K.Dir.NORTH:
		d3 = 2
		dname = "north"
	var key: String = "%s_%s_%d" % [player.cell_anim, dname, player.cell_frame]
	var a: Variant = _anchor.get(key, null)
	if a == null:
		a = _anchor.get("%s_%s_0" % [player.cell_anim, dname], null)
	var off: Vector2
	if which == &"both":
		off = (_pick(a, true, d3) + _pick(a, false, d3)) * 0.5
	else:
		off = _pick(a, which != &"off", d3)
	if west:
		off.x = -off.x
	return player.sprite.position + K.rndv(off)


func _pick(a: Variant, main: bool, d3: int) -> Vector2:
	if a is Array:
		var v: Variant = (a as Array)[1] if main else (a as Array)[0]
		if v == null:
			v = (a as Array)[0] if main else (a as Array)[1]
			if v != null and d3 == 2:
				v = Vector2(-(v as Vector2).x, (v as Vector2).y)   # 북쪽 오른손 없음 → 왼손 좌우 반전
		if v != null:
			return v
	return HAND_MAIN[d3] if main else HAND_OFF[d3]


# ─── 매 프레임(Player.render 가 부른다) ─────────────────────────────

func sync(hidden: bool) -> void:
	_hidden = hidden
	_pick_weapons()
	var behind: bool = player != null and player.facing == K.Dir.NORTH
	if behind != _behind:
		_behind = behind
		z_as_relative = not behind
		z_index = 1 if behind else 0
	visible = not _draw_w.is_empty() and player != null and not player.dead
	queue_redraw()


func note_fired(id: StringName) -> void:
	_last_fire_t[id] = Game.anim_time()


func _pick_weapons() -> void:
	_draw_w.clear()
	_draw_def.clear()
	_draw_role.clear()
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm == null:
		return
	var now: float = Game.anim_time()
	var main_w: WeaponBase = null
	var main_d: Dictionary = {}
	var main_s: float = -1.0
	var off_w: WeaponBase = null
	var off_d: Dictionary = {}
	var flash_w: WeaponBase = null
	var flash_d: Dictionary = {}
	var flash_t: float = -1.0
	for i in wm.slot_count():
		var w: WeaponBase = wm.weapon_at(i)
		if w == null:
			continue
		var d: Dictionary = def_for(w)
		if d.is_empty() or not _rects.has(String(d.get("sprite", ""))):
			continue
		var hand: String = String(d.get("hand", "main"))
		var lf: float = float(_last_fire_t.get(w.id, -100.0))
		if hand == "off":
			if off_w == null:
				off_w = w
				off_d = d
			elif now - lf < FLASH_SEC and lf > flash_t:
				flash_w = w
				flash_d = d
				flash_t = lf
			continue
		# 주손 점수: 선딜 중 3 > 1.2초 안에 쏨 2(+최근일수록) > 첫 칸 1
		var sc: float = 0.5 if main_w == null else 0.0
		if w.windup_prog() >= 0.0:
			sc = 3.0
		elif now - lf < HOLD_SEC:
			sc = 2.0 + lf * 0.0001
		if sc > main_s:
			main_s = sc
			main_w = w
			main_d = d
	var both: bool = main_w != null and String(main_d.get("hand", "")) == "both" and main_s >= 2.0
	if main_w != null:
		_draw_w.append(main_w)
		_draw_def.append(main_d)
		_draw_role.append(0)
	if not both:
		if flash_w != null:
			_draw_w.append(flash_w)
			_draw_def.append(flash_d)
			_draw_role.append(2)
		elif off_w != null:
			_draw_w.append(off_w)
			_draw_def.append(off_d)
			_draw_role.append(1)


## 16단으로 끊은 조준 각(라디안).
static func _quant(v: Vector2) -> float:
	if v.length_squared() < 0.0001:
		return 0.0
	return snappedf(atan2(v.y, v.x), STEP16)


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


func _draw() -> void:
	if player == null or _atlas == null:
		return
	for k in _draw_w.size():
		_draw_one(_draw_w[k], _draw_def[k], _draw_role[k])
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_one(w: WeaponBase, d: Dictionary, role: int) -> void:
	var anim: String = String(d.get("anim", "swing"))
	var hand: String = String(d.get("hand", "main"))
	var rect: Rect2 = _rects[String(d.get("sprite", ""))]
	var gp: Array = d.get("grip", [3, 13])
	var grip: Vector2 = Vector2(float(gp[0]), float(gp[1]))
	var axis: float = deg_to_rad(float(d.get("axis_deg", -45.0)))
	var rest: float = deg_to_rad(float(d.get("rest_deg", 30.0)))
	var reach: float = float(d.get("reach", 0.0))
	var ph: Dictionary = w.held_phase()
	var phase: StringName = ph["phase"]
	var t: float = float(ph["t"])
	# 던진 칼(신칼): 날아가 있는 동안 손에서 사라진다. 돌아와 잡히는 순간 1f 한지 점.
	var out: bool = anim == "throw_return" and w.held_out()
	var was_out: bool = bool(_was_out.get(w.id, false))
	if was_out and not out:
		_catch_tick[w.id] = Game.anim_tick_cur
	_was_out[w.id] = out
	var which: StringName = &"both" if hand == "both" else (&"off" if hand == "off" else &"main")
	if anim == "bow":
		which = &"both"      # 활은 가슴 가운데에서 표적 쪽으로 내민다(보조손 기준이면 조준이 반대쪽일 때 몸통을 가린다)
	var hp: Vector2 = hand_local(which)
	# 조준: 활은 늘 표적, 나머지는 쏜 방향(쏜 지 오래면 플레이어 조준)
	var aim: Vector2 = w.fire_dir
	if anim == "bow":
		aim = w.aim_dir(w.s("area", 12.0) + 2.0)
	elif phase == &"idle":
		aim = player.aim_dir()
	var a: float = _quant(aim)
	var sgn: float = 1.0
	if absf(aim.x) < 0.2:
		sgn = -1.0 if player.facing == K.Dir.WEST else 1.0
	elif aim.x < 0.0:
		sgn = -1.0
	var off_deg: float = rest
	var lift: float = 0.0
	var jit: Vector2 = Vector2.ZERO
	var smear_from: float = 999.0
	var now_t: int = Game.anim_tick_cur
	var hit_age: int = now_t - w.fire_anim_tick
	match anim:
		"slam":
			# 작두: 두 손으로 머리 위까지 들어 올림(선딜 전체) → 수직 내리찍기 +60° → 멈춤 → 회복
			var up: float = deg_to_rad(-150.0)
			var down: float = deg_to_rad(60.0)
			if phase == &"windup":
				off_deg = lerpf(rest, up, _ease_out(t))
				lift = 8.0 * _ease_out(t)
			elif phase == &"hit":
				off_deg = down
				if hit_age < 2:
					smear_from = up
			elif phase == &"recover":
				off_deg = lerpf(down, rest, t * t * (3.0 - 2.0 * t))
		"bow":
			off_deg = 0.0
			if phase == &"windup":
				jit = -Vector2.from_angle(a) * 2.0 * minf(1.0, t * 2.0)   # 시위를 당기며 2px 뒤로
		"shake":
			# 방울: 박마다 ±2px 3f 떨림
			if hit_age >= 0 and hit_age < 9:
				var f3: int = hit_age / 3
				jit = Vector2(2.0 if f3 == 0 else (-2.0 if f3 == 1 else 1.0), -1.0 if f3 == 0 else 0.0)
		_:
			# swing · throw_return: 선딜 −110° → 타격 +20°(1f) → 2f 멈춤 → 회복
			var back: float = deg_to_rad(-110.0)
			var hit_a: float = deg_to_rad(20.0)
			if phase == &"windup":
				off_deg = lerpf(rest, back, _ease_out(t))
			elif phase == &"hit":
				off_deg = hit_a
				if hit_age < 2:
					smear_from = back
			elif phase == &"recover":
				off_deg = lerpf(hit_a, rest, t * t * (3.0 - 2.0 * t))
	var fin: float = a + sgn * off_deg
	var pos: Vector2 = K.rndv(hp + Vector2(0, -lift) + Vector2.from_angle(a) * reach + jit)
	var tip_len: float = maxf(8.0, Vector2(rect.size.x - grip.x, grip.y).length() - 2.0)
	# 칼끝 스미어(타격 1f 한지 → 2f jk-hi, 2px): 선딜 끝 각 → 타격 각 사이 호
	if smear_from < 900.0 and not _hidden:
		var c0: float = a + sgn * smear_from
		var col: Color = COL_HANJI if hit_age == 0 else COL_JKHI
		var prev: Vector2 = pos + Vector2.from_angle(c0) * tip_len
		for s in range(1, 7):
			var ang: float = lerpf(c0, fin, float(s) / 6.0)
			var q: Vector2 = pos + Vector2.from_angle(ang) * tip_len
			draw_line(K.rndv(prev), K.rndv(q), COL_JKHI if hit_age == 0 else Color(COL_JKHI, 0.6), 3.0)
			draw_line(K.rndv(prev), K.rndv(q), col, 1.0)
			prev = q
	if out:
		return
	# 그림: 쥐는 점이 손에 오도록, 축을 조준 쪽으로 돌린다(서쪽은 축 기준 좌우 반전 — 칼날 면 유지)
	var m: Transform2D = Transform2D(-axis, Vector2.ZERO).scaled(Vector2(1.0, sgn)).rotated(fin).translated(pos)
	draw_set_transform_matrix(m)
	var dst: Rect2 = Rect2(-grip, rect.size)
	if _hidden:
		draw_texture_rect_region(_atlas, dst, rect, COL_INK)
	else:
		var lit: Color = Color(0.7, 0.7, 0.7, 1.0) if role == 2 and hit_age > 1 else Color.WHITE
		draw_texture_rect_region(_atlas, dst, rect, lit)
		# 번쩍 등장 1f: 한지 테
		if role == 2 and hit_age >= 0 and hit_age < 2:
			draw_rect(dst.grow(1.0), COL_HANJI, false, 1.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if _hidden:
		return
	# 잡힘 1f 한지 점(신칼 귀환)
	var ct: int = int(_catch_tick.get(w.id, -1000))
	if now_t - ct >= 0 and now_t - ct < 2:
		draw_rect(Rect2(pos - Vector2(1, 1), Vector2(3, 3)), COL_HANJI)
	# 활 시위(한지 1px): 쉴 때는 활대 바로 뒤 곧은 줄, 선딜 동안 가운데를 4px 당겨 V, 쏜 1f 는 앞으로 튕김.
	#   어두운 활 그림이 붉은 철릭·흙바닥 위에서도 '활'로 읽히게 하는 밝은 선 하나(design/19 §5.2 B ① 반동과 같은 박자).
	if anim == "bow":
		var av: Vector2 = Vector2.from_angle(a)
		var pv: Vector2 = av.orthogonal() * 8.0
		var nock: float = -1.0
		if phase == &"windup":
			nock = -1.0 - 4.0 * minf(1.0, t * 1.5)
		elif hit_age >= 0 and hit_age < 2:
			nock = 1.0
		var t1: Vector2 = K.rndv(pos + pv - av)
		var t2: Vector2 = K.rndv(pos - pv - av)
		var nk: Vector2 = K.rndv(pos + av * nock)
		var sc: Color = COL_HANJI
		draw_line(t1, nk, sc, 1.0)
		draw_line(nk, t2, sc, 1.0)
	# 활: 발사 손 섬광(활 끝 6px 한지 십자, 2f)
	if anim == "bow" and hit_age >= 0 and hit_age < 2:
		var fp: Vector2 = K.rndv(pos + Vector2.from_angle(a) * 4.0)
		draw_rect(Rect2(fp + Vector2(-3, 0), Vector2(7, 1)), COL_HANJI)
		draw_rect(Rect2(fp + Vector2(0, -3), Vector2(1, 7)), COL_HANJI)
		draw_rect(Rect2(fp - Vector2(1, 1), Vector2(3, 3)), COL_JKHI if hit_age == 1 else COL_HANJI)
