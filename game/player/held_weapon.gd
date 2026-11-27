class_name HeldWeapon
extends Node2D
## 손에 든 무기(design/19 §6). 렌더 전용 — 시뮬·판정·난수를 바꾸지 않는다. 소유: held_weapon_attack_fx.
## Player 의 자식(트리 순서: 몸 Sprite 다음, 금 테 Rim 앞). 북쪽을 볼 때는 몸 뒤(절대 z1)로 간다.
## 데이터 주도: data/held_weapons.json — 무구 id(없으면 원본 base_id) → 아틀라스 그림·쥐는 점·축·동작(anim)·무게.
##   표에 없는 무구(또는 hand "none" 공전체)는 손 무기 없이 지금처럼 동작한다.
## 손 규칙(§6.4): 주손 1(선딜 중 > 1.2초 안에 쏜 것 > 칸 순서 첫 주손 무구) · 보조손 1(칸 순서 첫 off 무구)
##   · 나머지는 쏠 때만 보조손 자리에 0.25초 '번쩍 등장'(1f 한지 테) · 두 손 무구(작두)가 주손이면 보조손은 비운다.
##   · 등(§6.4): 주손이 아닌 긴 무기(월도·삼지창·장창)와 호작도 족자를 최대 2개 비스듬히 멘다(z1 몸 뒤, 명도 ×0.7).
##     북쪽을 보면 등이 보이므로 몸 위(z2)에 그린다. 상한: 손 2 + 등 2.
## 몸통 가림(견본 리뷰 B): 남쪽을 볼 때 손은 몸 바깥(x ±12)에 두고, 아래쪽 조준이면 무기를 바깥 아래 대각선으로 돌려
##   휘두르는 호가 몸통을 가로지르지 않게 한다. 활·북·거울 같은 보조손 소품도 바깥으로 비킨다.
## 각도: 조준 방향을 16단(22.5°)으로 끊고 동작 오프셋을 더한다(서쪽을 보면 좌우 반전). 배율은 1(반전 −1)만.
## 동작(§5.0 네 박자): ① 선딜(젖힘·들어 올림) → ② 강한 첫 프레임(타격 각으로 한 번에 + 칼끝 한지) → ③ 칼끝 스미어
##   → ④ 회복. 히트스톱 동안은 연출 시계가 멈춰 타격 자세가 그대로 보인다. 무적 점멸 숨김 틱에는 먹 실루엣.

const HOLD_SEC: float = 1.2            # 주손: 마지막으로 쏜 무구를 이만큼 쥐고 있다
const FLASH_SEC: float = 0.25          # 나머지 무구: 쏠 때만 손에 번쩍 등장
const BACK_MAX: int = 2
const STEP16: float = PI / 8.0
const OUT_X: float = 12.0              # 남쪽을 볼 때 손을 몸 바깥으로(무당 몸 상자 ±9 + 3)
const COL_INK: Color = Color(0.0549, 0.0431, 0.0863)
const COL_HANJI: Color = Color(233.0 / 255.0, 220.0 / 255.0, 192.0 / 255.0)
const COL_HANJI_DK: Color = Color(178.0 / 255.0, 157.0 / 255.0, 118.0 / 255.0)
const COL_JKHI: Color = Color(228.0 / 255.0, 96.0 / 255.0, 79.0 / 255.0)
const COL_IRON: Color = Color(96.0 / 255.0, 96.0 / 255.0, 108.0 / 255.0)
const COL_IRON_HI: Color = Color(160.0 / 255.0, 160.0 / 255.0, 172.0 / 255.0)
const COL_HWANG_DK: Color = Color(169.0 / 255.0, 124.0 / 255.0, 27.0 / 255.0)
const BACK_DIM: Color = Color(0.85, 0.85, 0.85, 1.0)   # 0.7 은 어두운 흙 위에서 무엇인지 읽히지 않았다(검토 11-26)
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
var _strike_tick: Dictionary = {}        # weapon_id -> Events.held_strike 를 보낸 fire_anim_tick(한 번만)
var _ff_drawn: Dictionary = {}           # weapon_id -> '강한 첫 프레임'을 그린 fire_anim_tick — 저fps(웹)에서 1~2틱 창이 통째로 빠지지 않게
var _behind: bool = false
# 이번 프레임 그릴 것(손 최대 2: 주손·보조손, 등 최대 2)
var _draw_w: Array[WeaponBase] = []
var _draw_def: Array[Dictionary] = []
var _draw_role: PackedInt32Array = PackedInt32Array()   # 0 주손 1 보조손 2 번쩍 등장
var _back_w: Array[WeaponBase] = []
var _back_def: Array[Dictionary] = []
var _back_ci: Node2D = null
var _reveal_id: StringName = &""          # 진화·결합 공개(design/19 §5.2 H): 무기 그림이 머리 위 24px 에 0.8초 → 손으로
var _reveal_t: float = -100.0
var _main_side: float = 1.0              # 남쪽을 볼 때 주손 쪽(+1 오른쪽 / −1 왼쪽): 조준 쪽 손으로 든다(몸통을 가로지르지 않게)


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


## 그릴 수 있는 정의인가(그림이 아틀라스에 있거나 코드 그림).
static func _drawable(d: Dictionary) -> bool:
	if d.is_empty() or String(d.get("hand", "main")) == "none" or String(d.get("anim", "")) == "none":
		return false
	var sp: String = String(d.get("sprite", ""))
	return _rects.has(sp) or (sp == "" and String(d.get("code", "")) != "")


var _off_debug: bool = false


func _ready() -> void:
	load_defs()
	_off_debug = OS.is_debug_build() and DebugTools.arg("no-held") != ""
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_back_ci = Node2D.new()
	_back_ci.name = "Back"
	_back_ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_back_ci.z_as_relative = false
	_back_ci.z_index = 1
	add_child(_back_ci)
	_back_ci.draw.connect(_draw_back)
	Events.weapon_evolved.connect(_on_evolved)


func _on_evolved(_from_id: StringName, to_id: StringName) -> void:
	_reveal_id = to_id
	_reveal_t = Game.anim_time()


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
## 남쪽을 볼 때 주손은 오른쪽(+x), 보조손은 왼쪽(−x)으로 몸 바깥 OUT_X 이상에 둔다(몸통 가림 방지).
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
		if d3 == 0:
			off.x = (OUT_X - 1.0) * _main_side                # 남쪽: 두 손 무기도 조준 쪽 몸 바깥에서 내리찍는다
		elif d3 == 1:
			off.x = maxf(off.x, OUT_X - 2.0)                  # 옆: 몸 앞 가장자리에서
	else:
		off = _pick(a, which != &"off", d3)
		if d3 == 0:
			off.x = maxf(absf(off.x), OUT_X) * (-_main_side if which == &"off" else _main_side)
		elif d3 == 1:
			# 옆을 볼 때: 손 기준점(x+6)은 몸 실루엣 안이라 무기가 홍철릭을 덮는다 → 주손은 몸 앞 가장자리(x+10),
			# 보조손 소품은 그보다 앞(x+12)에 둔다(p_red 측정: 견본 −19% → 목표 −10% 이내)
			off.x = OUT_X if which == &"off" else maxf(off.x, OUT_X - 2.0)
		elif d3 == 2 and which != &"off":
			off.x += 3.0 * (signf(off.x) if absf(off.x) > 0.5 else 1.0)   # 북쪽(몸 뒤): 손점을 바깥으로 3px — 무기 끝이 어깨 위·옆으로 보이게
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
	if _off_debug:
		visible = false                                        # 디버그 --no-held: 같은 시뮬로 손 무기 전/후 비교(몸통 가림 p_red 측정)
		return
	if player != null and player.facing == K.Dir.SOUTH:
		var ax: float = player.aim_dir().x
		if absf(ax) > 0.3:
			_main_side = signf(ax)                             # 이력: |x| ≤ 0.3 이면 직전 쪽 유지
	_pick_weapons()
	_emit_strikes()
	var behind: bool = player != null and player.facing == K.Dir.NORTH
	if behind != _behind:
		_behind = behind
		z_as_relative = not behind
		z_index = 1 if behind else 0
	var alive: bool = player != null and not player.dead
	var revealing: bool = Game.anim_time() - _reveal_t < 0.8
	visible = alive and (revealing or not (_draw_w.is_empty() and _back_w.is_empty()))
	if _back_ci != null:
		_back_ci.z_index = 1                            # 등 무기는 늘 몸 뒤(북쪽에서 몸 위로 올리면 홍철릭을 대각선으로 가렸다 — p_red)
		_back_ci.visible = not _back_w.is_empty()
		_back_ci.queue_redraw()
	queue_redraw()
	if Game.autotest and Game.anim_tick_cur % 120 == 0 and DebugTools.arg("held-trace") != "":
		print("[held] n=%d back=%d vis=%s rects=%d atlas=%s" % [_draw_w.size(), _back_w.size(), visible, _rects.size(), _atlas != null])


## 타격 순간 신호(design/19 §5.2 — 다른 모듈이 손 위치에 반응). _draw 밖에서 발사 틱당 1번(프레임이 틱을 건너뛰어도 6틱 안에 보낸다).
func _emit_strikes() -> void:
	if player == null:
		return
	var now_t: int = Game.anim_tick_cur
	for k in _draw_w.size():
		if _draw_role[k] == 2:
			continue
		var w: WeaponBase = _draw_w[k]
		var age: int = now_t - w.fire_anim_tick
		if age >= 0 and age < 6 and int(_strike_tick.get(w.id, -1)) != w.fire_anim_tick:
			_strike_tick[w.id] = w.fire_anim_tick
			var hd: String = String(_draw_def[k].get("hand", "main"))
			Events.held_strike.emit(w.id, to_global(hand_local(&"both" if hd == "both" else (&"off" if hd == "off" else &"main"))))


func note_fired(id: StringName) -> void:
	_last_fire_t[id] = Game.anim_time()


func _pick_weapons() -> void:
	_draw_w.clear()
	_draw_def.clear()
	_draw_role.clear()
	_back_w.clear()
	_back_def.clear()
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
	var longs: Array[WeaponBase] = []
	var long_d: Array[Dictionary] = []
	# 가장 무거운 주손 무구의 쉴 때 점수: 이보다 가벼운 무구는 쏘아도 주손을 빼앗지 않고 '번쩍 등장'만 한다
	# (사용자 요구 11-27: 작두처럼 무거운 붉은 무기는 쉴 때도 늘 손에 — 신칼이 1.2초마다 주손을 가져가 작두가 등에만 있었다)
	var best_rest: float = -1.0
	for i0 in wm.slot_count():
		var w0: WeaponBase = wm.weapon_at(i0)
		if w0 == null:
			continue
		var d0: Dictionary = def_for(w0)
		var h0: String = String(d0.get("hand", "main"))
		if _drawable(d0) and (h0 == "main" or h0 == "both"):
			best_rest = maxf(best_rest, _rest_score(w0, d0))
	for i in wm.slot_count():
		var w: WeaponBase = wm.weapon_at(i)
		if w == null:
			continue
		var d: Dictionary = def_for(w)
		if not _drawable(d):
			continue
		var hand: String = String(d.get("hand", "main"))
		var lf: float = float(_last_fire_t.get(w.id, -100.0))
		if hand == "back":
			# 호작도 족자: 펼쳐 있는 동안(arch_aura 세화)은 등에서 숨긴다
			if w.windup_prog() < 0.0 and w.since_fire() >= w.hold_s() + w.recovery_s() + 0.35:
				longs.append(w)
				long_d.append(d)
			continue
		if hand == "off":
			if off_w == null:
				off_w = w
				off_d = d
			elif now - lf < FLASH_SEC and lf > flash_t:
				flash_w = w
				flash_d = d
				flash_t = lf
			continue
		# 주손 점수: 선딜 중 3 > 1.2초 안에 쏨 2(+최근일수록, 가장 무거운 무게 등급만) > 쉴 때 = 가장 무거운 붉은 무기(두 손 작두 우선, 같으면 칸 순서)
		# (예전 '첫 칸'은 신칼을 들고 작두는 쏠 때만 보여 '들고 다닌다'가 읽히지 않았다 — 검토 11-26)
		var sc: float = _rest_score(w, d)
		if w.windup_prog() >= 0.0:
			sc = 3.0
		elif now - lf < HOLD_SEC and sc >= best_rest - 0.001:
			sc = 2.0 + lf * 0.0001
		if sc > main_s:
			if main_w != null:
				_demote(main_w, main_d, now, longs, long_d)
				var lf0: float = float(_last_fire_t.get(main_w.id, -100.0))
				if now - lf0 < FLASH_SEC and lf0 > flash_t and not bool(main_d.get("back", false)):
					flash_w = main_w
					flash_d = main_d
					flash_t = lf0
			main_s = sc
			main_w = w
			main_d = d
		else:
			_demote(w, d, now, longs, long_d)
			if now - lf < FLASH_SEC and lf > flash_t and not bool(d.get("back", false)):
				flash_w = w
				flash_d = d
				flash_t = lf
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
	for k in mini(longs.size(), BACK_MAX):
		_back_w.append(longs[k])
		_back_def.append(long_d[k])


## 쉴 때 주손 점수(0.5~0.99, 쏜 무구 2.0 보다 늘 낮다): 무게 heavy > mid > light, 붉은 무기 +, 두 손 +.
static func _rest_score(w: WeaponBase, d: Dictionary) -> float:
	var sc: float = 0.5
	match String(d.get("weight", "light")):
		"heavy":
			sc += 0.3
		"mid":
			sc += 0.2
		_:
			sc += 0.1
	if not w.is_white():
		sc += 0.1
	if String(d.get("hand", "")) == "both":
		sc += 0.05
	return sc


## 주손에서 밀린 무구: 긴 무기면 등에 멘다.
func _demote(w: WeaponBase, d: Dictionary, _now: float, longs: Array[WeaponBase], long_d: Array[Dictionary]) -> void:
	if bool(d.get("back", false)) and not longs.has(w):
		longs.append(w)
		long_d.append(d)


## 16단으로 끊은 조준 각(라디안).
static func _quant(v: Vector2) -> float:
	if v.length_squared() < 0.0001:
		return 0.0
	return snappedf(atan2(v.y, v.x), STEP16)


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _sprite_rect(w: WeaponBase, d: Dictionary) -> Variant:
	var sp: String = String(d.get("sprite", ""))
	if sp == "":
		return null
	if w.kind != WeaponBase.KIND_WEAPON and _rects.has(sp + "_evo"):
		return _rects[sp + "_evo"]          # 진화·결합: 황 외곽선(design/19 §5.2 H)
	return _rects.get(sp, null)


func _draw() -> void:
	if player == null or _atlas == null:
		return
	var rt: float = Game.anim_time() - _reveal_t
	for k in _draw_w.size():
		if rt < 0.8 and _draw_w[k].id == _reveal_id:
			continue                          # 공개 중인 무기는 머리 위에서 내려온다
		_draw_one(_draw_w[k], _draw_def[k], _draw_role[k])
	if rt >= 0.0 and rt < 0.8:
		_draw_reveal(rt)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## 진화·결합 공개: 황 외곽선 그림이 무당 머리 위 24px 에 떠 있다가(0.6초) 0.2초에 손으로 내려온다. 첫 2f 는 황 테.
func _draw_reveal(rt: float) -> void:
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm == null:
		return
	var w: WeaponBase = null
	for i in wm.slot_count():
		if wm.weapon_at(i) != null and wm.weapon_at(i).id == _reveal_id:
			w = wm.weapon_at(i)
	if w == null:
		return
	var d: Dictionary = def_for(w)
	var rv: Variant = _sprite_rect(w, d) if not d.is_empty() else null
	if rv == null:
		return
	var rect: Rect2 = rv
	var top: Vector2 = player.sprite.position + Vector2(0, -44 - 24) + Vector2(0, -2.0 * sin(rt * 10.0))
	var hand: StringName = &"off" if String(d.get("hand", "main")) == "off" else &"main"
	var hp: Vector2 = hand_local(hand)
	var u: float = clampf((rt - 0.6) / 0.2, 0.0, 1.0)
	var c: Vector2 = K.rndv(top.lerp(hp - rect.size * 0.25, _smooth(u)))
	var dst: Rect2 = Rect2(c - (rect.size * 0.5).round(), rect.size)
	draw_texture_rect_region(_atlas, dst, rect, Color.WHITE)
	if rt < 0.1:
		draw_rect(dst.grow(1.0), Color(232.0 / 255.0, 185.0 / 255.0, 49.0 / 255.0), false, 1.0)


# ─── 등에 멘 무기(z1 몸 뒤 · 북쪽이면 몸 위) ───────────────────────

func _draw_back() -> void:
	if player == null or _atlas == null or _back_ci == null:
		return
	var west: bool = player.facing == K.Dir.WEST
	# 어깨 위로 칼끝·창끝이 비죽 나오게(몸 뒤 z1 — 어깨 위·옆으로 나온 부분만 보인다)
	var base: Vector2 = player.sprite.position + Vector2(0, -27)
	for k in _back_w.size():
		var d: Dictionary = _back_def[k]
		var rv: Variant = _sprite_rect(_back_w[k], d)
		if rv == null:
			continue
		var rect: Rect2 = rv
		var mod: Color = COL_INK if _hidden else BACK_DIM
		if bool(d.get("upright", false)):
			# 족자: 등 가운데 위로 비죽(어깨 위 6px)
			# 족자: 등 뒤 한쪽 어깨 위로 비스듬히 반쯤 비죽(몸 뒤 z1 — 가운데에 두면 몸에 다 가려 안 보였다)
			var tl: Vector2 = K.rndv(base + Vector2(-rect.size.x * 0.5 + (9.0 if west else -9.0), -9.0))
			_back_ci.draw_texture_rect_region(_atlas, Rect2(tl, rect.size), rect, mod)
			continue
		# 긴 무기: 둘 다 칼끝 오른쪽 위로 나란히(−62°·−74°, 3px 엇갈림) — X 자로 겹치면 갓 위가 어지럽다. 서쪽은 좌우 반전.
		var ang: float = deg_to_rad(-35.0 if k == 0 else -50.0)   # 눕혀서 어깨 옆으로 날 8~10px 이 나오게(−62°/−74° 는 갓 위 2~3px 끝만 보였다)
		var sx: float = 1.0
		if west:
			ang = PI - ang
			sx = -sx
		var axis: float = deg_to_rad(float(d.get("axis_deg", -45.0)))
		var m: Transform2D = Transform2D(-axis, Vector2.ZERO).scaled(Vector2(1.0, sx)).rotated(ang).translated(K.rndv(base + Vector2(-3.0 * float(k) * (-1.0 if west else 1.0), 2.0 * float(k))))
		_back_ci.draw_set_transform_matrix(m)
		_back_ci.draw_texture_rect_region(_atlas, Rect2(-rect.size * 0.5, rect.size).abs(), rect, mod)
	_back_ci.draw_set_transform_matrix(Transform2D.IDENTITY)


# ─── 손 무기 하나 ─────────────────────────────────────────────────

func _draw_one(w: WeaponBase, d: Dictionary, role: int) -> void:
	var anim: String = String(d.get("anim", "swing"))
	var hand: String = String(d.get("hand", "main"))
	var rv: Variant = _sprite_rect(w, d)
	var has_sp: bool = rv != null
	var rect: Rect2 = rv if has_sp else Rect2()
	var gp: Array = d.get("grip", [3, 13])
	var grip: Vector2 = Vector2(float(gp[0]), float(gp[1]))
	var axis: float = deg_to_rad(float(d.get("axis_deg", -45.0)))
	var rest: float = deg_to_rad(float(d.get("rest_deg", 30.0)))
	var reach: float = float(d.get("reach", 0.0))
	var upright: bool = bool(d.get("upright", false))
	var ph: Dictionary = w.held_phase()
	var phase: StringName = ph["phase"]
	var t: float = float(ph["t"])
	# 던진 칼(신칼): 날아가 있는 동안 손에서 사라진다. 돌아와 잡히는 순간 1f 한지 점.
	var out: bool = anim == "throw_return" and w.held_out()
	var was_out: bool = bool(_was_out.get(w.id, false))
	if was_out and not out:
		_catch_tick[w.id] = Game.anim_tick_cur
	_was_out[w.id] = out
	var which: StringName = &"both" if hand == "both" else (&"off" if (hand == "off" or role == 2) else &"main")
	# 활은 표적 쪽 손(남쪽 = 조준 쪽 몸 바깥, 옆 = 몸 앞)에서 표적을 향한다 — 가슴 가운데·반대손에 두면 홍철릭을 가렸다(p_red −15%)
	if anim == "bow":
		which = &"main"
		if player.facing != K.Dir.SOUTH:
			which = &"off"
	var hp: Vector2 = hand_local(which)
	if anim == "bow" and player.facing != K.Dir.NORTH:
		# 활: 표적이 있는 쪽 몸 바깥(x ±12)으로 — 등 뒤 표적을 겨눌 때 활이 몸을 가로지르지 않게
		var ba: Vector2 = w.aim_dir(w.s("area", 12.0) + 2.0)
		if absf(ba.x) > 0.3:
			hp.x = player.sprite.position.x + signf(ba.x) * OUT_X
	var side: float = 1.0 if hp.x >= player.sprite.position.x else -1.0
	# 조준: 활·거울은 늘 표적, 나머지는 쏜 방향(쏜 지 오래면 플레이어 조준)
	var aim: Vector2 = w.fire_dir
	if anim == "bow":
		aim = w.aim_dir(w.s("area", 12.0) + 2.0)
	elif phase == &"idle":
		aim = player.aim_dir()
	if aim.length_squared() < 0.0001:
		aim = Vector2.RIGHT * side
	# 쉴 때(남·동·서)는 손 바깥쪽을 향해 든다 — 쉬는 무기가 몸통 앞을 가로지르지 않게(견본 리뷰 B)
	if phase == &"idle" and player.facing != K.Dir.NORTH and anim != "bow":
		aim = Vector2(side, 0.0)
	# 아래쪽 조준(남·동·서): 칼날이 몸통을 가로지르지 않게 바깥 아래 대각선으로(견본 리뷰 B)
	var down_out: bool = player.facing != K.Dir.NORTH and aim.y > 0.45 and anim != "bow" and not upright
	if down_out:
		aim = Vector2(side * 0.8, 0.6)
	var a: float = _quant(aim)
	var sgn: float = 1.0
	if down_out:
		sgn = side
	elif absf(aim.x) < 0.2:
		sgn = -1.0 if player.facing == K.Dir.WEST else 1.0
	elif aim.x < 0.0:
		sgn = -1.0
	var off_deg: float = rest
	var lift: float = 0.0
	var jit: Vector2 = Vector2.ZERO
	var push: float = 0.0                    # 조준 방향으로 더 내미는 거리(찌르기)
	var smear_from: float = 999.0
	var hide_sprite: bool = false
	var now_t: int = Game.anim_tick_cur
	var hit_age: int = now_t - w.fire_anim_tick
	var sf: float = w.since_fire()
	# ② 강한 첫 프레임: 발사 뒤 0~1틱, 또는 그 창을 프레임이 건너뛰었으면(저fps) 6틱 안 첫 렌더 프레임 1장을 보장한다.
	var ff: bool = hit_age >= 0 and (hit_age < 2 or (hit_age < 6 and int(_ff_drawn.get(w.id, -1)) != w.fire_anim_tick))
	if ff:
		_ff_drawn[w.id] = w.fire_anim_tick
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
				if ff:
					smear_from = up
			elif phase == &"recover":
				off_deg = lerpf(down, rest, _smooth(t))
		"spin":
			# 월도: 선딜 −110° 젖힘 → 손을 축으로 회전(회전 수 × 0.15초에 한 바퀴씩) → 회복
			var back_a: float = deg_to_rad(-110.0)
			var spins: int = maxi(1, int(w.s("spins", 1))) + mini(w.sinjang(), 4)
			var spin_len: float = 0.15 * float(spins)
			if phase == &"windup":
				off_deg = lerpf(rest, back_a, _ease_out(t))
			elif sf < spin_len and w.fire_anim_tick >= 0:
				off_deg = back_a + TAU * (sf / 0.15)
				smear_from = off_deg - 1.2
			elif phase == &"recover" or phase == &"hit":
				off_deg = lerpf(back_a, rest, _smooth(clampf((sf - spin_len) / maxf(0.05, w.recovery_s()), 0.0, 1.0)))
		"thrust":
			# 삼지창·장창: 조준 쪽으로 곧게 → 선딜 3px 당김 → 찌를 때마다 8px 내밀고 끝 한지 점 1f
			off_deg = rest
			var n_th: int = maxi(1, int(w.s("thrusts", 1)))
			var iv: float = maxf(0.05, w.s("thrust_iv", 0.2 if w.stem == "samjichang" else 0.1))
			if phase == &"windup":
				off_deg = lerpf(rest, 0.0, _ease_out(t))
				push = -3.0 * t
			elif sf < float(n_th) * iv and w.fire_anim_tick >= 0:
				off_deg = 0.0
				var loc: float = fmod(sf, iv) / iv
				push = 8.0 * (1.0 - _smooth(loc))
				if loc < 0.3:
					smear_from = -1000.0   # 끝 한지 점 표시(아래)
			elif phase == &"hit" or phase == &"recover":
				off_deg = lerpf(0.0, rest, _smooth(clampf((sf - float(n_th) * iv) / maxf(0.05, w.recovery_s()), 0.0, 1.0)))
		"bow":
			off_deg = 0.0
			if phase == &"windup":
				jit = -Vector2.from_angle(a) * 2.0 * minf(1.0, t * 2.0)   # 시위를 당기며 2px 뒤로
			elif hit_age >= 0 and hit_age < 3:
				jit = -Vector2.from_angle(a) * 1.0                        # 쏜 반동 1px
		"shake":
			# 방울: 박마다 ±2px 3f 떨림
			if hit_age >= 0 and hit_age < 9:
				var f3: int = hit_age / 3
				jit = Vector2(2.0 if f3 == 0 else (-2.0 if f3 == 1 else 1.0), -1.0 if f3 == 0 else 0.0)
		"fan":
			# 부채: 젖혔다가(−90°) 90° 부친다(+35°) → 한지 바람줄 3개 1f
			var fb: float = deg_to_rad(-95.0)
			var fwd: float = deg_to_rad(35.0)
			if phase == &"windup":
				off_deg = lerpf(rest, fb, _ease_out(t))
			elif phase == &"hit":
				off_deg = fwd
				if ff:
					smear_from = fb
			elif phase == &"recover":
				off_deg = lerpf(fwd, rest, _smooth(t))
		"throw":
			# 쑥물 바가지: 뒤로 젖혔다(−80°) 앞으로 던지듯(+40°)
			var tb: float = deg_to_rad(-80.0)
			var tf: float = deg_to_rad(40.0)
			if phase == &"windup":
				off_deg = lerpf(rest, tb, _ease_out(t))
				lift = 3.0 * t
			elif phase == &"hit":
				off_deg = tf
			elif phase == &"recover":
				off_deg = lerpf(tf, rest, _smooth(t))
		"scatter", "salt":
			# 손짓: 선딜에 손을 올렸다(4px) 타격에 아래로 턴다(+3px). 뿌린 뒤 0.3초는 손에 든 것이 비어 있다.
			if phase == &"windup":
				lift = 4.0 * _ease_out(t)
			elif hit_age >= 0 and hit_age < 6:
				lift = -3.0
			if hit_age >= 0 and sf < 0.3:
				hide_sprite = true
		"plant":
			# 오방기: 깃대를 세워 들고(축이 위) 선딜에 3px 들었다가 4px 꽂는다
			if phase == &"windup":
				lift = 3.0 * t
			elif hit_age >= 0 and hit_age < 8:
				lift = -4.0
		"strike", "mirror", "cloth":
			pass
		_:
			# swing · throw_return: 선딜 −110° → 타격 +20°(1f) → 2f 멈춤 → 회복
			var back: float = deg_to_rad(-110.0)
			var hit_a: float = deg_to_rad(20.0)
			if phase == &"windup":
				off_deg = lerpf(rest, back, _ease_out(t))
			elif phase == &"hit":
				off_deg = hit_a
				if ff:
					smear_from = back
			elif phase == &"recover":
				off_deg = lerpf(hit_a, rest, _smooth(t))
	var fin: float = a + sgn * off_deg
	var pos: Vector2 = K.rndv(hp + Vector2(0, -lift) + Vector2.from_angle(a) * (reach + push) + jit)
	var tip_len: float = 10.0
	if has_sp:
		tip_len = maxf(8.0, Vector2(rect.size.x - grip.x, grip.y).length() - 2.0)
	var fxa: float = WeaponBase.fx_alpha()
	# 칼끝 스미어(타격 1f 한지 → 2f jk-hi, 2px): 선딜 끝 각 → 타격 각 사이 호(궤적 ③ — '내 무기 효과' α)
	if smear_from > -900.0 and smear_from < 900.0 and not _hidden and not upright:
		var c0: float = a + sgn * smear_from
		var col: Color = COL_HANJI if (hit_age == 0 or ff) else COL_JKHI
		var prev: Vector2 = pos + Vector2.from_angle(c0) * tip_len
		for s in range(1, 7):
			var ang: float = lerpf(c0, fin, float(s) / 6.0)
			var q: Vector2 = pos + Vector2.from_angle(ang) * tip_len
			draw_line(K.rndv(prev), K.rndv(q), Color(COL_JKHI, (1.0 if (hit_age == 0 or ff) else 0.6) * fxa), 3.0)
			draw_line(K.rndv(prev), K.rndv(q), Color(col, fxa), 1.0)
			prev = q
	if out:
		return
	var code: String = String(d.get("code", ""))
	# 그림: 쥐는 점이 손에 오도록, 축을 조준 쪽으로 돌린다(서쪽은 축 기준 좌우 반전 — 칼날 면 유지)
	var mod: Color = COL_INK if _hidden else (Color(0.75, 0.75, 0.75, 1.0) if role == 2 and hit_age > 3 else Color.WHITE)
	if has_sp and not hide_sprite:
		var m: Transform2D
		if upright:
			m = Transform2D(0.0, Vector2(-1.0 if player.facing == K.Dir.WEST else 1.0, 1.0), 0.0, pos)
		elif anim == "plant":
			# 깃대는 늘 위로(축 −90°) — 서쪽이면 좌우 반전
			var fl: float = -1.0 if player.facing == K.Dir.WEST else 1.0
			m = Transform2D(-axis, Vector2.ZERO).scaled(Vector2(1.0, fl)).rotated(deg_to_rad(-90.0)).translated(pos)
		else:
			m = Transform2D(-axis, Vector2.ZERO).scaled(Vector2(1.0, sgn)).rotated(fin).translated(pos)
		draw_set_transform_matrix(m)
		var dst: Rect2 = Rect2(-grip, rect.size)
		draw_texture_rect_region(_atlas, dst, rect, mod)
		# 번쩍 등장 1f: 한지 테 — 방울은 박마다 같은 테(후반 무리 속에서도 '흔들었다'가 보이게, 검토 11-26)
		if (ff and role == 2 or (anim == "shake" and (ff or (hit_age >= 0 and hit_age < 4)))) and not _hidden:
			draw_rect(dst.grow(1.0), COL_HANJI, false, 1.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	if _hidden:
		return
	var tip: Vector2 = pos + Vector2.from_angle(fin) * tip_len
	# ② 강한 첫 프레임: 칼끝 1px 한지 번쩍(타격 1f)
	if ff and anim in ["swing", "throw_return", "slam", "spin", "fan"]:
		draw_rect(Rect2(K.rndv(tip) - Vector2(1, 1), Vector2(3, 3)), COL_HANJI)
	if anim == "thrust" and smear_from < -900.0:
		var tp: Vector2 = K.rndv(tip)
		draw_rect(Rect2(tp - Vector2(1, 1), Vector2(3, 3)), COL_HANJI)
		if w.stem == "samjichang":
			# 세 끝 한지 점
			var pr: Vector2 = Vector2.from_angle(fin).orthogonal() * 3.0
			draw_rect(Rect2(K.rndv(tip + pr - Vector2.from_angle(fin) * 2.0), Vector2.ONE), COL_HANJI)
			draw_rect(Rect2(K.rndv(tip - pr - Vector2.from_angle(fin) * 2.0), Vector2.ONE), COL_HANJI)
	# 잡힘 1f 한지 점(신칼 귀환)
	var ct: int = int(_catch_tick.get(w.id, -1000))
	if now_t - ct >= 0 and now_t - ct < 2:
		draw_rect(Rect2(pos - Vector2(1, 1), Vector2(3, 3)), COL_HANJI)
	match code:
		"flail":
			_draw_flail(pos, fin, tip_len, phase, hit_age, sgn)
		"stick":
			_draw_stick(pos, phase, t, hit_age)
		"cloth":
			_draw_cloth(pos, a, hit_age, phase, t)
		"salt":
			_draw_grains(pos, a, hit_age, COL_HANJI, 6, true)
	if anim == "scatter" and hit_age >= 0 and hit_age < 12:
		_draw_grains(pos, a, hit_age, COL_HANJI if w.is_white() else COL_IRON_HI, 4, w.is_white())
	if anim == "fan" and ff:
		# 한지 바람줄 3개(1f): 부채 앞에서 조준 쪽으로 8px
		var av: Vector2 = Vector2.from_angle(a)
		for k in 3:
			var o: Vector2 = pos + av * 8.0 + av.orthogonal() * float(k - 1) * 4.0
			draw_line(K.rndv(o), K.rndv(o + av * (8.0 - absf(float(k - 1)) * 2.0)), COL_HANJI, 1.0)
	if anim == "throw" and hit_age >= 0 and hit_age < 9:
		# 던지는 포물선 점 3개(쑥물 — 청 금지, 황 어둠)
		var av2: Vector2 = Vector2.from_angle(a)
		for k in 3:
			var u: float = float(hit_age) / 9.0 + float(k) * 0.12
			var q: Vector2 = pos + av2 * (6.0 + 20.0 * u) + Vector2(0, -10.0 * 4.0 * u * (1.0 - u))
			draw_rect(Rect2(K.rndv(q), Vector2(2, 2)), COL_HWANG_DK if k > 0 else COL_HANJI)
	if anim == "plant" and hit_age >= 0 and hit_age < 4:
		# 꽂는 순간 깃대 밑 한지 점선 2px
		draw_rect(Rect2(K.rndv(pos + Vector2(-3, 2)), Vector2(7, 1)), COL_HANJI)
	if anim == "mirror" and hit_age >= 0 and hit_age < 2 and has_sp:
		# 손 거울 번쩍 1f: 거울 둘레 한지 테 + 십자
		var c: Vector2 = pos - grip + rect.size * 0.5
		draw_rect(Rect2(K.rndv(c) - Vector2(6, 6), Vector2(13, 13)), COL_HANJI, false, 1.0)
		draw_rect(Rect2(K.rndv(c) + Vector2(-4, 0), Vector2(9, 1)), COL_HANJI)
		draw_rect(Rect2(K.rndv(c) + Vector2(0, -4), Vector2(1, 9)), COL_HANJI)
	# 활 시위(한지 1px): 쉴 때는 활대 바로 뒤 곧은 줄, 선딜 동안 가운데를 4px 당겨 V, 쏜 1f 는 앞으로 튕김.
	if anim == "bow":
		var av3: Vector2 = Vector2.from_angle(a)
		var pv: Vector2 = av3.orthogonal() * 8.0
		var nock: float = -1.0
		if phase == &"windup":
			nock = -1.0 - 4.0 * minf(1.0, t * 1.5)
		elif hit_age >= 0 and hit_age < 2:
			nock = 1.0
		var t1: Vector2 = K.rndv(pos + pv - av3)
		var t2: Vector2 = K.rndv(pos - pv - av3)
		var nk: Vector2 = K.rndv(pos + av3 * nock)
		draw_line(t1, nk, COL_HANJI, 1.0)
		draw_line(nk, t2, COL_HANJI, 1.0)
		# 발사 손 섬광(활 끝 6px 한지 십자, 2f)
		if hit_age >= 0 and hit_age < 2:
			var fp: Vector2 = K.rndv(pos + av3 * 4.0)
			draw_rect(Rect2(fp + Vector2(-3, 0), Vector2(7, 1)), COL_HANJI)
			draw_rect(Rect2(fp + Vector2(0, -3), Vector2(1, 7)), COL_HANJI)
			draw_rect(Rect2(fp - Vector2(1, 1), Vector2(3, 3)), COL_JKHI if hit_age == 1 else COL_HANJI)


## 편곤 사슬·도리깨 머리(코드 그림): 자루 끝에서 사슬 3마디 → 쇠 머리 4×4(먹 테). 휘두를 때 머리가 뒤로 처진다.
func _draw_flail(pos: Vector2, fin: float, tip_len: float, phase: StringName, hit_age: int, sgn: float) -> void:
	var end: Vector2 = pos + Vector2.from_angle(fin) * (tip_len + 1.0)
	var lag: float = 0.0
	if phase == &"windup":
		lag = -0.8 * sgn
	elif phase == &"hit" and hit_age < 3:
		lag = 0.9 * sgn                       # 내려친 순간 머리가 앞으로 넘어간다
	var ca: float = fin + lag + (0.0 if phase != &"idle" else 0.9 * sgn)
	var head: Vector2 = end + Vector2.from_angle(ca) * 7.0
	for k in 3:
		var q: Vector2 = end.lerp(head, float(k + 1) / 4.0)
		draw_rect(Rect2(K.rndv(q), Vector2.ONE), COL_IRON_HI)
	var hq: Vector2 = K.rndv(head) - Vector2(2, 2)
	draw_rect(Rect2(hq - Vector2.ONE, Vector2(6, 6)), COL_INK)
	draw_rect(Rect2(hq, Vector2(4, 4)), COL_IRON_HI)        # 머리 밝은 쇠(어두운 흙 위에서 묻히던 것 — 검토 11-26)
	draw_rect(Rect2(hq + Vector2(2, 2), Vector2(2, 2)), COL_IRON)
	draw_rect(Rect2(hq, Vector2(3, 1)), COL_HANJI_DK if hit_age < 0 or hit_age >= 2 else COL_HANJI)


## 장구채(열채): 북 위 오른쪽에서 −40°(선딜) → 0°(덩, 타격) → −20°(쉼).
func _draw_stick(pos: Vector2, phase: StringName, t: float, hit_age: int) -> void:
	var sr: Variant = _rects.get("janggu_chae", null)
	if sr == null:
		return
	var rect: Rect2 = sr
	var west: bool = player.facing == K.Dir.WEST
	var ang: float = deg_to_rad(-20.0)
	if phase == &"windup":
		ang = deg_to_rad(lerpf(-20.0, -40.0, t))
	elif hit_age >= 0 and hit_age < 6:
		ang = 0.0
	var piv: Vector2 = pos + Vector2(-6.0 if west else 6.0, -9.0)
	var fl: float = -1.0 if west else 1.0
	var m: Transform2D = Transform2D(0.0, Vector2(fl, 1.0), 0.0, Vector2.ZERO).rotated(ang * fl).translated(K.rndv(piv))
	draw_set_transform_matrix(m)
	draw_texture_rect_region(_atlas, Rect2(-Vector2(rect.size.x - 2.0, 2.0), rect.size), rect, Color.WHITE)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if hit_age >= 0 and hit_age < 2:
		draw_rect(Rect2(K.rndv(pos + Vector2(-2, -9)), Vector2(5, 1)), COL_HANJI)


## 길베 천(코드 그림 2px 흰 띠): 쉴 때는 손에서 늘어져 흔들리고, 펼칠 때 3f 동안 앞으로 휙(16px).
func _draw_cloth(pos: Vector2, a: float, hit_age: int, phase: StringName, t: float) -> void:
	var at: float = Game.anim_time()
	var dirv: Vector2 = Vector2.DOWN
	var ln: float = 13.0
	if hit_age >= 0 and hit_age < 9:
		dirv = Vector2.from_angle(a)
		ln = 13.0 + 9.0 * _ease_out(float(hit_age) / 9.0)
	elif phase == &"windup":
		dirv = Vector2.from_angle(a + PI).lerp(Vector2.DOWN, 1.0 - t).normalized()
	var perp: Vector2 = dirv.orthogonal()
	var prev: Vector2 = pos
	var n: int = 5
	for k in n:
		var u: float = float(k + 1) / float(n)
		var wave: float = sin(at * 9.0 + u * 5.0) * 1.5 * u
		var q: Vector2 = pos + dirv * ln * u + perp * wave
		# 2px 흰 띠(한지) + 바깥 먹 1px(어두운 바닥·붉은 철릭 위에서 띠로 읽히게)
		var o: Vector2 = perp.round() if perp.round() != Vector2.ZERO else Vector2.RIGHT
		draw_line(K.rndv(prev) - o, K.rndv(q) - o, COL_INK, 1.0)
		draw_line(K.rndv(prev) + o * 2.0, K.rndv(q) + o * 2.0, COL_INK, 1.0)
		draw_line(K.rndv(prev), K.rndv(q), COL_HANJI, 1.0)
		draw_line(K.rndv(prev) + o, K.rndv(q) + o, COL_HANJI_DK if k == n - 1 else COL_HANJI, 1.0)
		prev = q


## 손 끝 알갱이(소금·지전 종이·마름쇠): 타격 뒤 0.2초 동안 조준 쪽 부채꼴로 흩어진다(난수 없음 — 각도는 번호로 정함).
func _draw_grains(pos: Vector2, a: float, hit_age: int, col: Color, n: int, light: bool) -> void:
	if hit_age < 0 or hit_age >= 12:
		var at: float = Game.anim_time()
		if light and n >= 6:
			# 쉴 때: 손 끝 소금 한 줌(먹 받침 5×3 위 한지 알갱이 5)
			var c0: Vector2 = K.rndv(pos + Vector2(0, -2))
			draw_rect(Rect2(c0 + Vector2(-3, -2), Vector2(7, 4)), COL_INK)
			for k in 5:
				var q0: Vector2 = c0 + Vector2(float(k) - 2.0, -1.0 + float(k % 2)) + Vector2(0, roundf(sin(at * 4.0 + float(k)) * 0.5))
				draw_rect(Rect2(q0, Vector2.ONE), COL_HANJI)
		return
	var u: float = float(hit_age) / 12.0
	var e: float = _ease_out(u)
	for k in n:
		var spread: float = (float(k) / float(maxi(1, n - 1)) - 0.5) * 1.2
		var q: Vector2 = pos + Vector2.from_angle(a + spread) * (3.0 + 16.0 * e) + Vector2(0, 6.0 * u * u)
		var c: Color = Color(col, 1.0 - u * u * WeaponBase.fx_alpha() if u > 0.5 else 1.0)
		draw_rect(Rect2(K.rndv(q), Vector2(2, 1) if u < 0.5 else Vector2.ONE), c)
