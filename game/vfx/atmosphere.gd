class_name Atmosphere
extends Node2D
## 분위기 층(오컬트 후처리의 월드 쪽 입력). 소유: vfx. VfxPlayer 가 _ready 에서 자식으로 만든다(run.tscn 무변경).
##   1 굿판 조명 소품: 촛대(prop_chotdae_pair 4f)·석등(prop_seokdeung 4f)·연등 줄(prop_sinjangdae 두 기둥 + 금줄 + prop_yeondeung)
##     + 제상(prop_gutsang)과 향 연기. 성역(원점) 배치 + 바깥 셀 해시 배치(결정론, Rng 미사용 — 시뮬 무관).
##     '선바위 굿당' 장소감(리뷰 vfx#16): 당집(성역 북쪽, 창 등불 난색 광원)·선바위(waves_stage1.obj_seonbawi.position)·
##     마당 입구 장승 한 쌍 고정 + 바깥 셀에 솟대 8%·서낭 돌탑 6%·소나무 언덕 4%. 충돌 없음(시각 전용).
##     선바위 넋 보너스(neok_bonus_per_haewon)는 미구현 — 데이터 키는 읽지 않는다.
##     광원은 Juice.light_frame 으로 매 프레임 넣는다(screen_fx 가 화면 좌표로 바꿔 occult_post 에 보낸다).
##   2 한지 재·향 연기·불티 파티클(SoA, 노드 없음, _draw 1px 사각형). 알파 반투명 없음(소멸은 점멸·픽셀 탈락).
##   4 풀릴 기색 표지: 박마다 적 머티리얼 유니폼 pullil_pulse(바깥 테 백↔황), 밀집(crowd_dim>0.3 또는 화면 잡귀>40)일 때
##     풀릴 기색 머리 위 3×3 백 점(먹 테). 무당 32px 안은 건너뛰고, 가까운 순 12개까지(design/18 §1.3).
##   3 밀도 감광(design/13 §2.10.6 → design/18 §1.2): 화면 안 일반 잡귀(풀릴 기색·정예+ 제외) N 을 4Hz 로 세어
##     d = clamp((N − 24) / 96, 0, 1) × 설정 배율(Juice.crowd_dim_scale) 을 0.5초 선형 보간 → Juice.crowd_dim,
##     일반 잡귀 머티리얼 유니폼 crowd_dim.
## 시계: 연출 시계(Game.anim_dt) — 히트스톱·일시정지에서 재·연기가 멈춘다(정지 화면). 런 밖에서는 실시간.
## 매 프레임 할당 없음: 모든 버퍼는 _ready 에서 크기를 잡는다.

const PROP_ROOT: String = "res://assets/props/"
const U: float = 32.0                       # 1u (K.UNIT_PX)
const CELL_U: float = 14.0                  # 바깥 소품 배치 셀(u)
const SANCTUM_R_U: float = 13.0             # 이 반경 안 셀은 해시 배치 안 함(성역 고정 배치)

# 소품 종류
enum P { CANDLE, SEOKDEUNG, ALTAR, POLE, SEONBAWI, DANGJIP, JANGSEUNG, SOTDAE, DOLTAP, PINE }
const PROP_CAP: int = 96
const C_BAEK: Color = Color(0.949, 0.925, 0.878)          # #f2ece0 (풀릴 기색 전용)
const C_MEOK: Color = Color(0.1333, 0.1098, 0.1804)       # #221c2e

# 색(마스터 팔레트)
const C_HANJI: Color = Color(0.9137, 0.8627, 0.7529)      # #e9dcc0
const C_HANJI_DK: Color = Color(0.698, 0.6157, 0.4627)    # #b29d76
const C_ASH: Color = Color(0.4353, 0.4667, 0.502)         # #6f7780
const C_ASH_DK: Color = Color(0.2902, 0.3098, 0.3412)     # #4a4f57
const C_EMBER: Color = Color(0.8941, 0.3765, 0.3098)      # #e4604f
const C_EMBER_HW: Color = Color(0.9608, 0.8392, 0.4196)   # #f5d66b
const C_ROPE: Color = Color(0.3686, 0.2941, 0.2118)       # #5e4b36
const C_OUTLINE: Color = Color(0.102, 0.102, 0.102)       # #1a1a1a

# 파티클 종류
enum M { ASH, SMOKE, EMBER, PAPER }
const MOTE_CAP: int = 320

var _props_node: Node2D
var _motes_node: Node2D

# 소품 SoA (성역 고정 + 이번 프레임 화면 근처 해시 소품을 같은 버퍼에 다시 채운다)
var _pk: PackedByteArray = PackedByteArray()
var _px: PackedFloat32Array = PackedFloat32Array()
var _py: PackedFloat32Array = PackedFloat32Array()
var _pph: PackedFloat32Array = PackedFloat32Array()       # 애니 위상(초)
var _pw: PackedFloat32Array = PackedFloat32Array()        # 연등 줄: 폭(px)
var _pn: int = 0
var _sanctum_n: int = 0

# 시트
var _candle: Dictionary = {}
var _seok: Dictionary = {}
var _lantern_tex: Texture2D
var _lantern_off_tex: Texture2D
var _pole_tex: Texture2D
var _altar_tex: Texture2D
var _seonbawi_tex: Texture2D
var _pine_tex: Texture2D
var _jangseung_tex: Texture2D
var _sotdae_tex: Texture2D
var _dangjip: Dictionary = {}
var _doltap: Dictionary = {}
var _pulse_on: bool = false

# 파티클 SoA
var _mk: PackedByteArray = PackedByteArray()
var _mx: PackedFloat32Array = PackedFloat32Array()
var _my: PackedFloat32Array = PackedFloat32Array()
var _mvx: PackedFloat32Array = PackedFloat32Array()
var _mvy: PackedFloat32Array = PackedFloat32Array()
var _mage: PackedFloat32Array = PackedFloat32Array()
var _mlife: PackedFloat32Array = PackedFloat32Array()
var _mph: PackedFloat32Array = PackedFloat32Array()
var _mon: PackedByteArray = PackedByteArray()
var _mhead: int = 0
var mote_count: int = 0

var _t: float = 0.0
var _ash_acc: float = 0.0
var _smoke_acc: float = 0.0
var _seed: int = 17

# 밀도 감광
var _dim_acc: float = 0.0
var _dim_target: float = 0.0
var _dim_sent: float = -1.0
var _dim_mat_n: int = -1                    # crowd_dim 을 보낸 머티리얼 수
var crowd_n: int = 0
var _dim_n0: float = 24.0
var _dim_span: float = 96.0
const MARK_CAP: int = 12                    # 풀릴 기색 머리 점 상한(가까운 순)
const MARK_SKIP_R: float = 32.0             # 무당 이 반경 안은 머리 점 생략(무당 몸을 가리지 않게)
var _mk_d: PackedFloat32Array = PackedFloat32Array()
var _mk_i: PackedInt32Array = PackedInt32Array()

# 점등(design/08 §4.3: 00:00~00:03 먹색 화면, 장구 덩에 등불 점화). 성역 소품만 꺼진 채 시작한다.
const IGNITE_AT_S: float = 3.0
const IGNITE_STAGGER_S: float = 0.07
var _ignite_t: float = -1.0
var _gt: float = 0.0

# 계측
var stat_max_motes: int = 0
var stat_lights_max: int = 0


func _ready() -> void:
	_props_node = Node2D.new()
	_props_node.name = "Props"
	_props_node.z_as_relative = false
	_props_node.z_index = -6                    # 지면(−10) 위, 행위자(0~3) 아래
	add_child(_props_node)
	_props_node.draw.connect(_draw_props)
	_motes_node = Node2D.new()
	_motes_node.name = "Motes"
	_motes_node.z_as_relative = false
	_motes_node.z_index = 6                     # 행위자 위, 데미지 숫자(20) 아래
	add_child(_motes_node)
	_motes_node.draw.connect(_draw_motes)
	_candle = _sheet("prop_chotdae_pair_sheet")
	_seok = _sheet("prop_seokdeung_sheet")
	_lantern_tex = SpriteLib.tex(PROP_ROOT + "prop_yeondeung.png")
	_lantern_off_tex = SpriteLib.tex(PROP_ROOT + "prop_yeondeung_off.png")
	_pole_tex = SpriteLib.tex(PROP_ROOT + "prop_sinjangdae.png")
	_altar_tex = SpriteLib.tex(PROP_ROOT + "prop_gutsang.png")
	_seonbawi_tex = SpriteLib.tex(PROP_ROOT + "lm_guksadang_seonbawi.png")
	_pine_tex = SpriteLib.tex(PROP_ROOT + "lm_guksadang_pine_hill.png")
	_jangseung_tex = SpriteLib.tex(PROP_ROOT + "prop_jangseung_pair.png")
	_sotdae_tex = SpriteLib.tex(PROP_ROOT + "prop_sotdae.png")
	_dangjip = _sheet("lm_guksadang_dangjip_sheet")
	_doltap = _sheet("prop_seonang_doltap_sheet")
	_pk.resize(PROP_CAP)
	_px.resize(PROP_CAP)
	_py.resize(PROP_CAP)
	_pph.resize(PROP_CAP)
	_pw.resize(PROP_CAP)
	_mk.resize(MOTE_CAP)
	_mx.resize(MOTE_CAP)
	_my.resize(MOTE_CAP)
	_mvx.resize(MOTE_CAP)
	_mvy.resize(MOTE_CAP)
	_mage.resize(MOTE_CAP)
	_mlife.resize(MOTE_CAP)
	_mph.resize(MOTE_CAP)
	_mon.resize(MOTE_CAP)
	_mon.fill(0)
	_dim_n0 = Data.num("art_palette", "crowd_dim.n0", 24.0)
	_dim_span = maxf(1.0, Data.num("art_palette", "crowd_dim.span", 96.0))
	_mk_d.resize(MARK_CAP)
	_mk_i.resize(MARK_CAP)
	_build_sanctum()
	Events.run_started.connect(func(_c: StringName) -> void: _reset())
	Events.beat.connect(_on_beat)


## 풀릴 기색 바깥 테 맥동: 박마다 백 ↔ 황 밝음(적 머티리얼 전부, 박당 1회 — 매 프레임 아님).
## 밀집(_draw_pullil_marks 와 같은 조건)일 때는 테 맥동을 끄고(보낼 값 0) 머리 위 백 점의 bob 이 박을 탄다 —
## 수십 개 테가 박마다 번쩍이면 무당 금 테·해원 백을 덮는다(design/18 §1.1, 리뷰 hitfeel/regression).
var _pulse_sent: float = -1.0


func _on_beat(bi: int, _down: bool) -> void:
	var on: bool = (bi & 1) == 0
	_pulse_on = on
	var dense: bool = Juice.crowd_dim > 0.3 or crowd_n > 40
	var v: float = 1.0 if (on and not dense) else 0.0
	if v == _pulse_sent:
		return
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	_pulse_sent = v
	for m: ShaderMaterial in em.sp_mat:
		if m != null:
			m.set_shader_parameter("pullil_pulse", v)


func _sheet(name_: String) -> Dictionary:
	var jp: String = PROP_ROOT + name_ + ".json"
	var tex: Texture2D = SpriteLib.tex(PROP_ROOT + name_ + ".png")
	if tex == null or not FileAccess.file_exists(jp):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if not (d is Dictionary):
		return {}
	var fx: Dictionary = VfxLib.parse_aseprite(d, tex)
	if (fx["regions"] as Array).is_empty():
		return {}
	return fx


func _reset() -> void:
	_ignite_t = -1.0
	_mon.fill(0)
	mote_count = 0
	_dim_target = 0.0
	_dim_sent = -1.0
	Juice.crowd_dim = 0.0
	stat_max_motes = 0
	stat_lights_max = 0


# ─── 성역 배치: 원점 둘레 굿판 ─────────────────────────────────────────

func _add_prop(kind: int, x: float, y: float, w: float = 0.0) -> void:
	if _pn >= PROP_CAP:
		return
	_pk[_pn] = kind
	_px[_pn] = roundf(x)
	_py[_pn] = roundf(y)
	_pph[_pn] = float(_hash2(int(x), int(y)) % 997) * 0.013
	_pw[_pn] = w
	_pn += 1


func _build_sanctum() -> void:
	_pn = 0
	# 제상(북쪽 중앙) + 연등 줄(제상 뒤, 두 신장대 사이 금줄에 연등 4개)
	_add_prop(P.ALTAR, 0.0, -5.0 * U)
	_add_prop(P.POLE, -3.5 * U, -6.0 * U, 7.0 * U)
	# 촛대 8쌍: 가로로 긴 타원(7u × 5u) 둘레 — 굿판 마당
	for i in 8:
		var a: float = TAU * (float(i) + 0.5) / 8.0
		_add_prop(P.CANDLE, cos(a) * 7.0 * U, sin(a) * 5.0 * U)
	# 석등 4기: 마당 바깥 모서리
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_add_prop(P.SEOKDEUNG, sx * 10.0 * U, sy * 7.5 * U)
	# 국사당 장소감: 당집(북), 선바위(waves_stage1.obj_seonbawi), 마당 입구 장승 한 쌍(남)
	_add_prop(P.DANGJIP, 0.0, -11.0 * U)
	var sb: Vector2 = Vector2(6.0, 12.0)
	var sv: Variant = Data.get_value("waves_stage1", "objects.obj_seonbawi.position", [6.0, 12.0])
	if sv is Array and (sv as Array).size() >= 2:
		sb = Vector2(float(sv[0]), float(sv[1]))
	_add_prop(P.SEONBAWI, sb.x * U, sb.y * U)
	_add_prop(P.JANGSEUNG, -2.5 * U, 9.0 * U)
	_add_prop(P.JANGSEUNG, 2.5 * U, 9.0 * U)
	_sanctum_n = _pn


func _hash2(x: int, y: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (_seed * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


## 화면 근처 셀의 해시 소품을 _sanctum_n 뒤에 다시 채운다(카메라가 셀을 넘을 때만 바뀌지만 매 프레임 계산해도 셀 ≤ 12개).
func _fill_world_props(view: Rect2) -> void:
	_pn = _sanctum_n
	var cs: float = CELL_U * U
	var x0: int = int(floorf((view.position.x - 64.0) / cs))
	var y0: int = int(floorf((view.position.y - 64.0) / cs))
	var x1: int = int(floorf((view.end.x + 64.0) / cs))
	var y1: int = int(floorf((view.end.y + 64.0) / cs))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var h: int = _hash2(cx, cy)
			var cxp: float = (float(cx) + 0.5) * cs
			var cyp: float = (float(cy) + 0.5) * cs
			if Vector2(cxp, cyp).length() < SANCTUM_R_U * U:
				continue
			var r: int = h % 100
			if r >= 64:
				continue                            # 셀 36% 는 빈 들판(어둠이 있어야 불빛이 산다)
			var ox: float = float((h >> 8) % 200 - 100) / 100.0 * cs * 0.32
			var oy: float = float((h >> 16) % 200 - 100) / 100.0 * cs * 0.32
			if r < 30:
				_add_prop(P.CANDLE, cxp + ox, cyp + oy)
			elif r < 42:
				_add_prop(P.SEOKDEUNG, cxp + ox, cyp + oy)
			elif r < 46:
				_add_prop(P.POLE, cxp + ox - 2.5 * U, cyp + oy, 5.0 * U)
			elif r < 54:
				_add_prop(P.SOTDAE, cxp + ox, cyp + oy)          # 솟대 8%
			elif r < 60:
				_add_prop(P.DOLTAP, cxp + ox, cyp + oy)          # 서낭 돌탑 6%
			else:
				_add_prop(P.PINE, cxp + ox, cyp + oy)            # 소나무 언덕 4%


# ─── 갱신 ─────────────────────────────────────────────────────────────

func _view_rect() -> Rect2:
	var vs: Vector2 = get_viewport_rect().size
	var cam: Camera2D = Game.camera
	var c: Vector2 = cam.get_screen_center_position() if cam != null else Vector2.ZERO
	return Rect2(c - vs * 0.5, vs)


func _process(delta: float) -> void:
	var dt: float = delta
	if Game.run_active:
		dt = Game.anim_dt
	_t += dt
	_gt = Game.time_sec() if Game.run_active else 1.0e9
	if Game.run_active and _ignite_t < 0.0 and _gt >= IGNITE_AT_S:
		_ignite()
	var view: Rect2 = _view_rect()
	_fill_world_props(view)
	_emit_prop_lights(view)
	if dt > 0.0:
		_spawn_ambient(view, dt)
		_step_motes(dt)
	_update_crowd_dim(delta)
	_props_node.queue_redraw()
	_motes_node.queue_redraw()


func _flick(i: int, rate: float) -> float:
	# 촛불 깜빡임: rate Hz 계단 난수(−1..1), 소품마다 위상이 다르다
	var step: int = int(floorf(_t * rate + _pph[i] * 7.0))
	return float(_hash2(step, i * 31 + 5) % 2001) / 1000.0 - 1.0


func _emit_prop_lights(view: Rect2) -> void:
	var grow: Rect2 = view.grow(140.0)
	var n: int = 0
	for i in _pn:
		var p: Vector2 = Vector2(_px[i], _py[i])
		if not grow.has_point(p) or not _is_lit(i):
			continue
		var f: float = _flick(i, 10.0)
		match _pk[i]:
			P.CANDLE:
				Juice.light_frame(p + Vector2(0, -16), 2.6 * U + f * 3.0, 0.70 + f * 0.05, 0)
			P.SEOKDEUNG:
				Juice.light_frame(p + Vector2(0, -27), 3.2 * U + f * 2.0, 0.75 + f * 0.04, 0)
			P.ALTAR:
				Juice.light_frame(p + Vector2(0, -10), 3.0 * U + f * 2.0, 0.60 + f * 0.04, 0)
			P.POLE:
				Juice.light_frame(p + Vector2(_pw[i] * 0.5, -40), 2.2 * U + f * 2.0, 0.55 + f * 0.05, 0)
			P.DANGJIP:
				# 당집 창 세 칸의 등불(가운데 문 + 양 창)
				Juice.light_frame(p + Vector2(0, -36), 3.4 * U + f * 3.0, 0.72 + f * 0.05, 0)
				Juice.light_frame(p + Vector2(-36, -36), 2.2 * U + f * 2.0, 0.55 + f * 0.04, 0)
				Juice.light_frame(p + Vector2(36, -36), 2.2 * U - f * 2.0, 0.55 - f * 0.04, 0)
			_:
				continue                               # 장승·선바위·솟대·돌탑·소나무: 광원 없음(어둠 속 실루엣)
		n += 1
	stat_lights_max = maxi(stat_lights_max, n)


## 성역 소품 i 가 켜졌는가(바깥 해시 소품은 늘 켜져 있다).
func _is_lit(i: int) -> bool:
	if i >= _sanctum_n or not Game.run_active:
		return true
	return _ignite_t >= 0.0 and _gt >= _ignite_t + float(i) * IGNITE_STAGGER_S


func _ignite() -> void:
	_ignite_t = _gt
	var vp: VfxPlayer = get_parent() as VfxPlayer
	if vp == null or _gt > IGNITE_AT_S + 1.0:
		return                                     # 중간 시작(--start-sec)은 연출 없이 켠다
	for i in _sanctum_n:
		var at: Vector2 = Vector2(_px[i], _py[i])
		match _pk[i]:
			P.CANDLE:
				at += Vector2(0, -12)
			P.SEOKDEUNG:
				at += Vector2(0, -18)
			P.POLE:
				at += Vector2(_pw[i] * 0.5, -36)
			P.ALTAR:
				at += Vector2(0, -6)
			P.DANGJIP:
				at += Vector2(0, -36)
			_:
				continue
		vp.play(&"vfx_lamp_ignite", at, 0.0, 1.0, {"delay": float(i) * IGNITE_STAGGER_S, "snap": false})


func _alloc_mote() -> int:
	for k in MOTE_CAP:
		var j: int = (_mhead + k) % MOTE_CAP
		if _mon[j] == 0:
			_mhead = (j + 1) % MOTE_CAP
			return j
	var j2: int = _mhead                         # 가득 차면 가장 오래된 자리부터 덮는다
	_mhead = (_mhead + 1) % MOTE_CAP
	return j2


func _rnd(a: float, b: float) -> float:
	return a + randf() * (b - a)                 # 연출 전용 난수(시뮬 Rng 스트림을 소모하지 않는다)


func spawn_mote(kind: int, pos: Vector2, vel: Vector2, life: float) -> void:
	var j: int = _alloc_mote()
	if _mon[j] == 0:
		mote_count += 1
	_mon[j] = 1
	_mk[j] = kind
	_mx[j] = pos.x
	_my[j] = pos.y
	_mvx[j] = vel.x
	_mvy[j] = vel.y
	_mage[j] = 0.0
	_mlife[j] = life
	_mph[j] = randf() * TAU
	stat_max_motes = maxi(stat_max_motes, mote_count)


## 해원 연출: 한지 재(넋전 조각)가 위로 흩날린다. 퇴치: 불티가 튀었다가 꺼진다.
func burst(pos: Vector2, haewon: bool, n: int = 5) -> void:
	for k in n:
		if haewon:
			spawn_mote(M.PAPER, pos + Vector2(_rnd(-6, 6), _rnd(-18, -4)), Vector2(_rnd(-10, 10), _rnd(-34, -18)), _rnd(0.9, 1.6))
		else:
			spawn_mote(M.EMBER, pos + Vector2(_rnd(-4, 4), _rnd(-14, -4)), Vector2(_rnd(-30, 30), _rnd(-40, -10)), _rnd(0.35, 0.6))


func _spawn_ambient(view: Rect2, dt: float) -> void:
	# 한지 재: 화면 전체에 초당 약 5개, 아래에서 위로 천천히(밤바람)
	_ash_acc += dt * 5.0
	while _ash_acc >= 1.0:
		_ash_acc -= 1.0
		var p: Vector2 = Vector2(_rnd(view.position.x, view.end.x), _rnd(view.position.y + view.size.y * 0.3, view.end.y + 8.0))
		spawn_mote(M.ASH, p, Vector2(_rnd(-4, 5), _rnd(-9, -4)), _rnd(4.0, 7.5))
	# 향 연기·불티: 화면 안 촛대·석등·제상에서
	_smoke_acc += dt * 2.6
	var emit: bool = _smoke_acc >= 1.0
	if emit:
		_smoke_acc -= 1.0
	for i in _pn:
		var p2: Vector2 = Vector2(_px[i], _py[i])
		if not view.has_point(p2):
			continue
		var k: int = _pk[i]
		if not _is_lit(i):
			continue
		if k == P.ALTAR and randf() < dt * 7.0:
			# 제상 향 두 대: 가늘고 끊이지 않는 연기 기둥
			var hx: float = -10.0 if randf() < 0.5 else 9.0
			spawn_mote(M.SMOKE, p2 + Vector2(hx, -20), Vector2(_rnd(-1.5, 1.5), _rnd(-13, -9)), _rnd(2.8, 4.0))
		elif emit and k == P.CANDLE and randf() < 0.45:
			spawn_mote(M.SMOKE, p2 + Vector2(_rnd(-4, 4), -20), Vector2(_rnd(-2, 2), _rnd(-12, -8)), _rnd(2.4, 3.6))
		if (k == P.CANDLE or k == P.SEOKDEUNG) and randf() < dt * 0.9:
			var ep: Vector2 = p2 + (Vector2(_rnd(-5, 5), -21) if k == P.CANDLE else Vector2(0, -30))
			spawn_mote(M.EMBER, ep, Vector2(_rnd(-6, 6), _rnd(-22, -12)), _rnd(0.5, 0.9))


func _step_motes(dt: float) -> void:
	for j in MOTE_CAP:
		if _mon[j] == 0:
			continue
		_mage[j] += dt
		if _mage[j] >= _mlife[j]:
			_mon[j] = 0
			mote_count -= 1
			continue
		var k: int = _mk[j]
		var sway: float = 0.0
		match k:
			M.ASH:
				sway = sin(_mage[j] * 1.3 + _mph[j]) * 6.0
			M.SMOKE:
				sway = sin(_mage[j] * 1.7 + _mph[j]) * (2.0 + _mage[j] * 3.0)   # 위로 갈수록 크게 흔들리며 풀린다
			M.PAPER:
				sway = sin(_mage[j] * 4.0 + _mph[j]) * 14.0
				_mvy[j] *= 1.0 - 0.9 * dt                                        # 떠오르다 느려짐
			M.EMBER:
				_mvy[j] += 40.0 * dt                                             # 불티는 튀었다 떨어짐
		_mx[j] += (_mvx[j] + sway) * dt
		_my[j] += _mvy[j] * dt


# ─── 밀도 감광 ───────────────────────────────────────────────────────

func _update_crowd_dim(real_dt: float) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	_dim_acc += real_dt
	if _dim_acc >= 0.25:
		_dim_acc = 0.0
		var view: Rect2 = _view_rect()
		var n: int = 0
		var skip: int = EnemyManager.F_PULLIL | EnemyManager.F_ELITE_PLUS | EnemyManager.F_DYING | EnemyManager.F_HIDDEN
		for k in em.active_count:
			var i: int = em.active[k]
			if (em.flags[i] & skip) != 0:
				continue
			if view.has_point(Vector2(em.px[i], em.py[i])):
				n += 1
		crowd_n = n
		var sc_v: Variant = Juice.get(&"crowd_dim_scale")
		var sc: float = 1.0 if sc_v == null else float(sc_v)
		_dim_target = clampf((float(n) - _dim_n0) / _dim_span * sc, 0.0, 1.0)
	# 0.5초 선형 보간(초당 2.0)
	var d: float = move_toward(Juice.crowd_dim, _dim_target, real_dt * 2.0)
	Juice.crowd_dim = d
	# 새 종 머티리얼(감광이 멈춰 있을 때 처음 나온 종)도 같은 d 를 받게 머티리얼 수가 바뀌면 다시 보낸다
	if absf(d - _dim_sent) > 0.004 or (d == 0.0 and _dim_sent != 0.0) or em.sp_mat.size() != _dim_mat_n:
		_dim_sent = d
		_dim_mat_n = em.sp_mat.size()
		var nmat: int = mini(em.sp_mat.size(), em.sp_tier.size())
		for s in nmat:
			var tr: StringName = em.sp_tier[s]
			if tr == K.TIER_COMMON or tr == K.TIER_MINION:
				em.sp_mat[s].set_shader_parameter("crowd_dim", d)


# ─── 그리기 ──────────────────────────────────────────────────────────

## 밀집 때 풀릴 기색 머리 위 3×3 백 점(먹 1px 테) — 수백 마리 속에서도 '풀 수 있는 적'이 보이게(리뷰 vfx#10).
func _draw_pullil_marks() -> void:
	if not Game.run_active or (Juice.crowd_dim <= 0.3 and crowd_n <= 40):
		return
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	var view: Rect2 = _view_rect().grow(16.0)
	var need: int = EnemyManager.F_PULLIL
	var skip: int = EnemyManager.F_DYING | EnemyManager.F_HIDDEN
	var bob: float = 1.0 if _pulse_on else 0.0
	var pp: Vector2 = Vector2(1.0e9, 1.0e9)
	if Game.player != null:
		var rp: Variant = Game.player.get("render_pos")
		pp = (rp as Vector2) if rp is Vector2 else Game.player.global_position
	# 가까운 순 MARK_CAP 개(삽입 정렬, 할당 없음)
	var m: int = 0
	var skip_r2: float = MARK_SKIP_R * MARK_SKIP_R
	for k in em.active_count:
		var i: int = em.active[k]
		var f: int = em.flags[i]
		if (f & need) == 0 or (f & skip) != 0:
			continue
		var x0: float = floorf(em.px[i] + 0.5)
		var y0: float = floorf(em.py[i] + 0.5)
		if not view.has_point(Vector2(x0, y0)):
			continue
		var d2: float = Vector2(x0, y0).distance_squared_to(pp)
		if d2 < skip_r2:
			continue
		if m == MARK_CAP and d2 >= _mk_d[MARK_CAP - 1]:
			continue
		var j: int = mini(m, MARK_CAP - 1)
		while j > 0 and _mk_d[j - 1] > d2:
			_mk_d[j] = _mk_d[j - 1]
			_mk_i[j] = _mk_i[j - 1]
			j -= 1
		_mk_d[j] = d2
		_mk_i[j] = i
		m = mini(m + 1, MARK_CAP)
	for q in m:
		var i: int = _mk_i[q]
		var x: float = floorf(em.px[i] + 0.5)
		var y: float = floorf(em.py[i] + 0.5)
		var top: float = y - float(em.body_h_of(i)) - 7.0 - bob
		_motes_node.draw_rect(Rect2(x - 2.0, top - 2.0, 5.0, 5.0), C_MEOK)
		_motes_node.draw_rect(Rect2(x - 1.0, top - 1.0, 3.0, 3.0), C_BAEK)


func _frame_of(fx: Dictionary, i: int) -> int:
	var n: int = (fx["regions"] as Array).size()
	return int(floorf((_t + _pph[i]) * float(fx["fps"]))) % maxi(1, n)


func _draw_sheet(fx: Dictionary, i: int, p: Vector2) -> void:
	if fx.is_empty():
		return
	var r: Rect2 = (fx["regions"] as Array)[_frame_of(fx, i)]
	var pv: Vector2 = fx["pivot"]
	_props_node.draw_texture_rect_region(fx["texture"], Rect2(p - pv, r.size), r)


func _draw_props() -> void:
	var view: Rect2 = _view_rect().grow(72.0)
	var big_view: Rect2 = view.grow(100.0)
	# 1차: 큰 랜드마크(당집·선바위·소나무 언덕)를 먼저 — 작은 소품이 그 앞에 서게
	for i in _pn:
		var k0: int = _pk[i]
		if k0 != P.DANGJIP and k0 != P.SEONBAWI and k0 != P.PINE:
			continue
		var p0: Vector2 = Vector2(_px[i], _py[i])
		if not big_view.has_point(p0):
			continue
		match k0:
			P.DANGJIP:
				if _is_lit(i):
					_draw_sheet(_dangjip, i, p0)
				else:
					_draw_unlit(_dangjip, p0)
			P.SEONBAWI:
				if _seonbawi_tex != null:
					_props_node.draw_texture(_seonbawi_tex, p0 - Vector2(64, 142))
			P.PINE:
				if _pine_tex != null:
					_props_node.draw_texture(_pine_tex, p0 - Vector2(80, 112))
	for i in _pn:
		var p: Vector2 = Vector2(_px[i], _py[i])
		var k: int = _pk[i]
		if k == P.DANGJIP or k == P.SEONBAWI or k == P.PINE:
			continue
		if k == P.POLE:
			if not view.intersects(Rect2(p.x - 8.0, p.y - 64.0, _pw[i] + 16.0, 70.0)):
				continue
			_draw_lantern_line(i, p)
			continue
		if not view.has_point(p):
			continue
		match k:
			P.CANDLE:
				if _is_lit(i):
					_draw_sheet(_candle, i, p)
				else:
					_draw_unlit(_candle, p)
			P.SEOKDEUNG:
				if _is_lit(i):
					_draw_sheet(_seok, i, p)
				else:
					_draw_unlit(_seok, p)
			P.ALTAR:
				if _altar_tex != null:
					_props_node.draw_texture(_altar_tex, p - Vector2(32, 28))
			P.JANGSEUNG:
				if _jangseung_tex != null:
					_props_node.draw_texture(_jangseung_tex, p - Vector2(16, 61))
			P.SOTDAE:
				if _sotdae_tex != null:
					_props_node.draw_texture(_sotdae_tex, p - Vector2(8, 63))
			P.DOLTAP:
				_draw_sheet(_doltap, i, p)


## 꺼진 소품: 첫 프레임을 먹빛 실루엣으로(불꽃 없음 — 색 치환은 팔레트 먹 #221c2e 단색).
func _draw_unlit(fx: Dictionary, p: Vector2) -> void:
	if fx.is_empty():
		return
	var r: Rect2 = (fx["regions"] as Array)[0]
	var pv: Vector2 = fx["pivot"]
	_props_node.draw_texture_rect_region(fx["texture"], Rect2(p - pv, r.size), r, Color(0.36, 0.32, 0.42))


## 두 신장대 사이 금줄(1px, 정수 처짐) + 연등. 연등은 바람에 1px 흔들린다(계단).
func _draw_lantern_line(i: int, p: Vector2) -> void:
	var w: float = _pw[i]
	var top: float = p.y - 58.0
	if _pole_tex != null:
		_props_node.draw_texture(_pole_tex, Vector2(p.x - 8.0, p.y - 62.0))
		_props_node.draw_texture(_pole_tex, Vector2(p.x + w - 8.0, p.y - 62.0))
	var iw: int = int(w)
	var sag: float = 7.0
	for x in iw:
		var u: float = float(x) / maxf(w, 1.0)
		var y: float = top + floorf(sag * 4.0 * u * (1.0 - u) + 0.5)
		_props_node.draw_rect(Rect2(p.x + float(x), y, 1.0, 1.0), C_ROPE)
	var ltex: Texture2D = _lantern_tex if _is_lit(i) or _lantern_off_tex == null else _lantern_off_tex
	if ltex == null:
		return
	var nl: int = clampi(int(w / 48.0), 2, 4)
	for l in nl:
		var u2: float = (float(l) + 1.0) / (float(nl) + 1.0)
		var lx: float = p.x + floorf(w * u2)
		var ly: float = top + floorf(sag * 4.0 * u2 * (1.0 - u2) + 0.5)
		var sw: float = 1.0 if _flick(i + l * 7, 1.5) > 0.4 else 0.0
		_props_node.draw_texture(ltex, Vector2(lx - 8.0 + sw, ly))


func _draw_motes() -> void:
	_draw_pullil_marks()
	for j in MOTE_CAP:
		if _mon[j] == 0:
			continue
		var u: float = _mage[j] / _mlife[j]
		var k: int = _mk[j]
		var x: float = floorf(_mx[j] + 0.5)
		var y: float = floorf(_my[j] + 0.5)
		match k:
			M.ASH:
				if u > 0.85 and int(_mage[j] * 15.0) % 2 == 0:
					continue                                # 소멸: 점멸(반투명 없음)
				var col: Color = C_ASH if (j % 3) != 0 else C_HANJI_DK
				var flip: bool = int(_mage[j] * 4.0 + _mph[j]) % 2 == 0   # 한지 조각이 뒤집히며 날린다(2×1 ↔ 1×1)
				_motes_node.draw_rect(Rect2(x, y, 2.0 if flip and (j % 2) == 0 else 1.0, 1.0), col)
				if (j % 11) == 0 and u < 0.6:
					_motes_node.draw_rect(Rect2(x + 1.0, y, 1.0, 1.0), C_EMBER)   # 타다 남은 가장자리
			M.SMOKE:
				var s: float = 1.0 if u < 0.35 else 2.0
				if u > 0.6 and ((int(x) + int(y) + int(_mage[j] * 12.0)) % 3) == 0:
					continue                                # 흩어짐: 픽셀 탈락
				if u > 0.85 and int(_mage[j] * 15.0) % 2 == 0:
					continue
				_motes_node.draw_rect(Rect2(x, y, s, s), C_ASH if u < 0.5 else C_ASH_DK)
			M.EMBER:
				if u > 0.7 and int(_mage[j] * 20.0) % 2 == 0:
					continue
				_motes_node.draw_rect(Rect2(x, y, 1.0, 1.0), C_EMBER_HW if u < 0.4 else C_EMBER)
			M.PAPER:
				if u > 0.8 and int(_mage[j] * 15.0) % 2 == 0:
					continue
				var wide: bool = int(_mage[j] * 6.0 + _mph[j]) % 2 == 0
				_motes_node.draw_rect(Rect2(x, y, 2.0 if wide else 1.0, 1.0 if wide else 2.0), C_HANJI)
