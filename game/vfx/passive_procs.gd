extends Node2D
## 패시브 발동 연출(3~4단 작은 발동 · 5단 완성, design/19 §5.2 E — 렌더 전용, 난수 없음). 소유: kill_ability_fx. HitFeedback 이 VfxPlayer 자식으로 붙인다(z5).
## 기존 시트만 쓴다(새 그림·셰이더 없음). 시뮬 판정은 하지 않는다 — 발동 조건은 기존 신호와 WeaponManager.passive_level 만 읽는다.
##   경면주사 '주사 낙인'  : 붉은 무구 한 파열 퇴치(cause han_pa) 자리 → vfx_toechi_burst scale 2, jk-hi 물들임 + 한지 고리 2px 3f
##   위패 '위패 모심'      : 넋 동무가 수명으로 떠날 때(yeongga_cheondo lifetime) → vfx_cheondo_ascend + 반경 1.5u 한지 고리 2px 3f
##   촛대 '촛불 밝힘'      : 상시 광원 Juice.light_add 무당 3u(난색, 후처리 추가 없음)
##   명주실 '명다리 실'    : 부활 신호가 생기면(Events.has_signal("player_revived")) vfx_gildakkeum_knot + 고리 파동 2px
## 처음 발동할 때 가장자리 레인(왼쪽 위)에 '주사 낙인!' 1회, 그 뒤로는 같은 패시브 30초 간격. 가운데 슬롯은 쓰지 않는다.
## 신호: Events.passive_proc(psv_id, pos) — 발동마다(예산으로 그림을 거른 것도) 1번.
## TODO(시뮬): 주사 낙인 반경 1u 피해·위패 모심 반경 1.5u 백 피해·명다리 실 부활은 아직 시뮬에 없다(리드 결정 요청). 연출만 한다.

const P_JUSA: StringName = &"psv_jusa"
const P_WIPAE: StringName = &"psv_wipae"
const P_CHOT: StringName = &"psv_chotdae"
const P_MYEONG: StringName = &"psv_myeongjusil"
const NAMES: Dictionary = {&"psv_jusa": "주사 낙인!", &"psv_wipae": "위패 모심!", &"psv_chotdae": "촛불 밝힘!", &"psv_myeongjusil": "명다리 실!"}
const LABEL_IV: float = 30.0
const LV_SMALL: int = 3                                   # 3~4단: 작은 발동(검토 11-26 — 20분 판에서 5단을 보기 어렵다). 5단 = 완성(가장자리 글)
const JKHI_MOD: Color = Color(1.0, 0.62, 0.55, 1.0)     # 붉은 파열 시트를 jk-hi 쪽으로(가산이라 한지 심은 남는다)
const COL_HANJI: Color = Color(233.0 / 255.0, 220.0 / 255.0, 192.0 / 255.0)
const COL_JKHI: Color = Color(228.0 / 255.0, 96.0 / 255.0, 79.0 / 255.0)
const RING_CAP: int = 8
const RING_LIFE: float = 3.0 / 60.0 + 0.1               # 2px 3f + 1px 잔상 0.1초
const JUSA_WIN: int = 15                                  # 주사 낙인 시트: 0.25초 창 2장(군중 1)

var vfx: VfxPlayer = null
var _label_t: Dictionary = {}                             # psv_id -> 마지막 가장자리 글 게임 초
var _r_pos: PackedVector2Array = PackedVector2Array()
var _r_rad: PackedFloat32Array = PackedFloat32Array()
var _r_t: PackedFloat32Array = PackedFloat32Array()
var _r_col: PackedByteArray = PackedByteArray()           # 0 한지 / 1 jk-hi 테
var _r_head: int = 0
var _light: int = -1
var _light_full: bool = false
var _jusa_t0: int = -1000
var _jusa_n: int = 0
var stat_procs: Dictionary = {}


func _ready() -> void:
	z_as_relative = false
	z_index = 5
	_r_pos.resize(RING_CAP)
	_r_rad.resize(RING_CAP)
	_r_t.resize(RING_CAP)
	_r_t.fill(-10.0)
	_r_col.resize(RING_CAP)
	Events.enemy_killed.connect(_on_killed)
	Events.yeongga_cheondo.connect(_on_cheondo)
	Events.run_started.connect(_on_run_started)
	if Events.has_signal(&"player_revived"):
		Events.connect(&"player_revived", _on_revived)


func _lv(id: StringName) -> int:
	var wm: Object = Game.weapons
	if wm == null or not wm.has_method(&"passive_level"):
		return 0
	return int(wm.call(&"passive_level", id))


func _on_run_started(_c: StringName) -> void:
	_label_t.clear()
	stat_procs.clear()
	_r_t.fill(-10.0)
	if _light >= 0:
		Juice.light_remove(_light)
		_light = -1


func _proc(id: StringName, pos: Vector2, full: bool = true) -> void:
	stat_procs[id] = int(stat_procs.get(id, 0)) + 1
	Events.passive_proc.emit(id, pos)
	if not full:
		return                                                # 작은 발동(3~4단)은 글 없이 그림만
	var t: float = Game.time_sec()
	if t - float(_label_t.get(id, -1000.0)) < LABEL_IV:
		return
	_label_t[id] = t
	var hud: Object = Game.run_root.get("hud") if Game.run_root != null else null
	if hud == null:
		return
	var s: String = String(NAMES.get(id, ""))
	if s == "":
		return
	# 가장자리 레인(왼쪽 위 공수 자리). hud 분할이 공개 이름을 만들면 그것을, 없으면 지금 이름을 쓴다.
	if hud.has_method(&"push_edge"):
		hud.call(&"push_edge", s, true)
	elif hud.has_method(&"_push_edge"):
		hud.call(&"_push_edge", s, true)


func _ring(pos: Vector2, r: float, col: int) -> void:
	_r_pos[_r_head] = pos
	_r_rad[_r_head] = r
	_r_t[_r_head] = Game.anim_time()
	_r_col[_r_head] = col
	_r_head = (_r_head + 1) % RING_CAP


func _on_killed(_h: int, _sp: StringName, pos: Vector2, kind: StringName, cause: StringName, _tier: StringName) -> void:
	var lv: int = _lv(P_JUSA)
	if kind != K.KIND_TOECHI or cause != &"han_pa" or lv < LV_SMALL:
		return
	_proc(P_JUSA, pos, lv >= 5)
	if vfx == null:
		return
	var t: int = Game.game_tick
	if t - _jusa_t0 >= JUSA_WIN:
		_jusa_t0 = t
		_jusa_n = 0
	if _jusa_n >= (1 if Juice.fx_crowd else 2):
		return
	_jusa_n += 1
	vfx.play(&"vfx_toechi_burst", pos + Vector2(0, -8), 0.0, 2.0 if lv >= 5 else 1.0, {"modulate": JKHI_MOD, "snap": false})
	_ring(pos + Vector2(0, -8), (1.0 if lv >= 5 else 0.6) * K.UNIT_PX, 1)


func _on_cheondo(count: int, reason: StringName) -> void:
	var lv: int = _lv(P_WIPAE)
	if reason != &"lifetime" or count <= 0 or lv < LV_SMALL:
		return
	var pl: Node2D = Game.player
	if pl == null:
		return
	var p: Vector2 = pl.global_position
	_proc(P_WIPAE, p, lv >= 5)
	if vfx != null and lv >= 5:
		vfx.play(&"vfx_cheondo_ascend", p + Vector2(0, -6), 0.0, 1.0, {"additive": true, "snap": false})
	_ring(p, (1.5 if lv >= 5 else 1.0) * K.UNIT_PX, 0)


func _on_revived(_a: Variant = null, _b: Variant = null) -> void:
	var lv: int = _lv(P_MYEONG)
	if lv < LV_SMALL:
		return
	var pl: Node2D = Game.player
	if pl == null:
		return
	var p: Vector2 = pl.global_position
	_proc(P_MYEONG, p, lv >= 5)
	if vfx != null:
		vfx.play(&"vfx_gildakkeum_knot", p + Vector2(0, -16), 0.0, 2.0, {"additive": true, "snap": false})
	_ring(p, 3.0 * K.UNIT_PX, 0)


func _process(_dt: float) -> void:
	# 촛불 밝힘: 상시 광원(무당 3u). 처음 켜질 때 1회 발동 표시
	var pl: Node2D = Game.player
	var clv: int = _lv(P_CHOT) if (Game.run_active and pl != null) else 0
	var on: bool = clv >= LV_SMALL
	if on and _light >= 0 and _light_full != (clv >= 5):
		Juice.light_remove(_light)                             # 3~4단 작은 빛 → 5단 큰 빛으로 갈아 끼운다
		_light = -1
	if on:
		var lp: Vector2 = pl.global_position + Vector2(0, -14)
		if _light < 0:
			_light_full = clv >= 5
			_light = Juice.light_add(lp, (3.0 if _light_full else 2.0) * K.UNIT_PX, 0.55 if _light_full else 0.35, 0)
			_proc(P_CHOT, pl.global_position, _light_full)
		else:
			Juice.light_move(_light, lp)
	elif _light >= 0:
		Juice.light_remove(_light)
		_light = -1
	queue_redraw()


func _draw() -> void:
	var now: float = Game.anim_time()
	var my_a: float = clampf(float(Juice.my_fx_alpha), 0.0, 1.0)
	for i in RING_CAP:
		var age: float = now - _r_t[i]
		if age < 0.0 or age >= RING_LIFE:
			continue
		var c: Vector2 = K.rndv(_r_pos[i] + Vector2(0, -6))
		var r: float = roundf(_r_rad[i] * (0.7 + 0.3 * minf(1.0, age / (3.0 / 60.0))))
		var seg: int = clampi(int(r * 0.6), 16, 64)
		if age < 3.0 / 60.0:
			# 2px 3f: 바깥 jk-hi(주사) 또는 한지_dk + 안 한지 1px — 첫 프레임이라 my_fx 를 곱하지 않는다
			draw_arc(c, r + 0.5, 0.0, TAU, seg, COL_JKHI if _r_col[i] == 1 else Color(0.698, 0.616, 0.463), 1.0, false)
			draw_arc(c, r - 0.5, 0.0, TAU, seg, COL_HANJI, 1.0, false)
		else:
			draw_arc(c, r + 2.0, 0.0, TAU, seg, Color(COL_HANJI, 0.45 * my_a), 1.0, false)


func stats_line() -> String:
	return "procs %s" % str(stat_procs)


func _exit_tree() -> void:
	if _light >= 0:
		Juice.light_remove(_light)
		_light = -1
