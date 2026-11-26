extends ColorRect
## 화면 후처리(오컬트 분위기): occult_post.gdshader 구동. 소유: vfx. (run.tscn PostLayer/ScreenFx)
##  1 저채도: 평상시 DESAT_BASE 0.08 고정(파일럿 승인값 — 주인공 홍철릭 식별), 살기 문턱(0.5) 뒤에만 DESAT_MAX 까지.
##  2 촛불 조명: 앰비언트(Events.ambient_changed ← waves_stage1.lighting, 플레이 하한 0.18) + 광원 ≤ 24
##     (무당 개인 광원 4.5u·0.85 + Juice 수명/지속 광원 + 프레임 광원[굿판 소품·영가]). 난색 광원은 10Hz 계단 깜빡임.
##  3 거리 색조: geori 마다 다른 밤 색(3초에 걸쳐 옮겨 간다).
##  4 먹 비네트: 살기·저체력으로 짙어짐 + 시련 신령색(trial_start~trial_end) + 빙의·합일 + 보스 붉은 달(boss_spawned~결과).
##     달 원반·헤일로는 후처리가 아니라 월드 층(vfx/red_moon.gd, z −8)에 그린다 — 적·적탄을 가리지 않게. 여기서는 비네트 적빛만.
##  5 신명 오름: 황빛 데움(가장자리 색동 테는 haewon_system 의 vfx_sinmyeong_oreum_border — 셰이더 saekdong 은 예비, 0).
##  6 한지 그레인(6fps).
## 시계: 실시간(일시정지 메뉴 위에서도 그레인·깜빡임이 돈다). 시뮬 상태를 바꾸지 않는다.

const DESAT_BASE: float = 0.08
const DESAT_MAX: float = 0.30
const SALGI_KNEE: float = 0.5
const MAX_LIGHTS: int = 24
const AMBIENT_FLOOR: float = 0.18          # 플레이 중 하한(design/08 §4.2). 시작 3초·정적만 예외
const PLAYER_LIGHT_R_U: float = 4.5
const PLAYER_LIGHT_I: float = 0.85

## 거리별 밤 색(곱). 모두 1 근처 — 팔레트를 깨지 않는 은은한 색조.
const GEORI_TINT: Dictionary = {
	&"geori_jutang_bujeong": Color(0.95, 0.97, 1.04),            # 부정거리: 차가운 먹청
	&"geori_gamang_sansin": Color(0.94, 1.01, 0.98),             # 산신거리: 솔숲 청록
	&"geori_byeolsang_daegam_jeseok": Color(1.00, 0.95, 1.01),   # 별상·대감: 자줏빛 밤
	&"geori_janggun_gunung_changbu": Color(1.04, 0.98, 0.92),    # 장군거리: 횃불 호박
	&"geori_jakdu": Color(1.07, 0.94, 0.90),                     # 작두거리: 붉은 열기
	&"geori_dwitjeon": Color(1.03, 1.00, 0.94),                  # 뒷전: 공물상 촛불
	&"geori_myeongbu": Color(0.90, 0.94, 1.07),                  # 명부: 저승 청백
}
const OBANG: Array[Color] = [Color(0.165, 0.36, 0.667), Color(0.784, 0.196, 0.176), Color(0.91, 0.725, 0.192),
	Color(0.913, 0.863, 0.753), Color(0.20, 0.18, 0.24)]

var _mat: ShaderMaterial
var _lights: PackedVector4Array = PackedVector4Array()
var _tones: PackedFloat32Array = PackedFloat32Array()
var _cand_d: PackedFloat32Array = PackedFloat32Array()
var _t: float = 0.0

var _ambient: float = 1.0
var _ambient_target: float = 1.0
var _ambient_rate: float = 1.0
var _ambient_from_waves: bool = false
var _tint: Color = Color.WHITE
var _tint_target: Color = Color.WHITE
var _aura: float = 0.0
var _aura_target: float = 0.0
var _aura_col: Color = Color.WHITE
var _hapil: bool = false
var _possessed: StringName = &""
var _saek: float = 0.0
var _moon: float = 0.0
var _moon_target: float = 0.0
var _boss_alive: bool = false
var _beat_pulse: float = 0.0
var _vig_hit: float = 0.0
var _deity_defs: GDScript = null
var stat_light_max: int = 0
var _geori_seen: StringName = &""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/occult_post.gdshader") as Shader
	material = _mat
	_lights.resize(MAX_LIGHTS)
	_tones.resize(MAX_LIGHTS)
	_cand_d.resize(MAX_LIGHTS)
	if ResourceLoader.exists("res://deities/deity_defs.gd"):
		_deity_defs = load("res://deities/deity_defs.gd") as GDScript
	Events.run_started.connect(_on_run_started)
	Events.ambient_changed.connect(_on_ambient)
	Events.trial_start.connect(func(_s: int, d: StringName) -> void: _set_aura(d, 1.0))
	Events.trial_end.connect(func(_s: int, _d: StringName, _w: StringName) -> void: _aura_end())
	Events.hapil_start.connect(func(_ids: Array) -> void: _hapil = true; _aura_target = 1.0)
	Events.possession_changed.connect(_on_possession)
	Events.boss_spawned.connect(func(_h: int, _sp: StringName, _f: StringName) -> void: _boss_alive = true)
	Events.boss_resolved.connect(func(_h: int, _k: StringName, _n: float) -> void: _boss_alive = false)
	Events.beat.connect(func(_i: int, down: bool) -> void: _beat_pulse = maxf(_beat_pulse, 1.0 if down else 0.5))
	Events.player_damaged.connect(func(_a: float, _s: StringName, _hp: float, _m: float) -> void: _vig_hit = 1.0)
	_on_run_started(&"")


func _on_run_started(_c: StringName) -> void:
	_ambient = 0.10 if Game.run_active or Game.state == Game.State.RUN else 1.0
	_ambient_target = 0.30
	_ambient_rate = 0.1
	_ambient_from_waves = false
	_tint = GEORI_TINT.get(&"geori_jutang_bujeong", Color.WHITE)
	_tint_target = _tint
	_aura = 0.0
	_aura_target = 0.0
	_hapil = false
	_possessed = &""
	_saek = 0.0
	_moon = 0.0
	_moon_target = 0.0
	_boss_alive = false
	_geori_seen = &""
	stat_light_max = 0


func _on_ambient(a: float, fade: float) -> void:
	_ambient_from_waves = true
	var floor_v: float = AMBIENT_FLOOR if Game.time_sec() >= 3.0 else 0.0
	if Game.time_sec() >= 1199.5 and Game.time_sec() < 1202.0:
		floor_v = 0.0                               # 20:00 정적(연출 1~3초만 진짜 암흑)
	_ambient_target = maxf(a, floor_v)
	_ambient_rate = absf(_ambient_target - _ambient) / maxf(fade, 0.25)


func _set_geori(id: StringName) -> void:
	_tint_target = GEORI_TINT.get(id, Color.WHITE)
	_moon_target = 0.35 if id == &"geori_myeongbu" else 0.0


func _deity_color(d: StringName) -> Color:
	if _deity_defs != null:
		var v: Variant = _deity_defs.call("color", d)
		if v is Color:
			return v
	return K.COL_HANJI


func _set_aura(d: StringName, s: float) -> void:
	_aura_col = _deity_color(d)
	_aura_target = s


func _aura_end() -> void:
	if _possessed != &"":
		_set_aura(_possessed, 0.55)
	elif not _hapil:
		_aura_target = 0.0


func _on_possession(d: StringName, active: bool) -> void:
	if active:
		_possessed = d
		_set_aura(d, 0.55)
	elif d == _possessed:
		_possessed = &""
		_aura_end()


## 실시간 1차 추종(초당 rate 만큼)
func _approach(v: float, target: float, rate: float, dt: float) -> float:
	return move_toward(v, target, rate * dt)


func _process(delta: float) -> void:
	_t += delta
	var in_run: bool = Game.run_active
	# 앰비언트: 웨이브 조명 신호가 없으면 시작 3초 0.10 → 0.30(design/08 §4.3)
	if in_run and not _ambient_from_waves and Game.time_sec() >= 3.0 and _ambient_target < 0.3:
		_ambient_target = 0.30
		_ambient_rate = 0.2 / 1.5
	if not in_run:
		_ambient_target = 1.0
		_ambient_rate = 2.0
	_ambient = _approach(_ambient, _ambient_target, maxf(_ambient_rate, 0.05), delta)
	if in_run and Beat.geori_id != _geori_seen:
		_geori_seen = Beat.geori_id
		_set_geori(_geori_seen)
	var tk: float = minf(1.0, delta / 3.0)
	_tint = _tint.lerp(_tint_target, tk)
	_aura = _approach(_aura, _aura_target, 1.5, delta)
	if _hapil:
		# 합일: 오방색이 박마다 돈다
		_aura_col = OBANG[posmod(Beat.beat_index, OBANG.size())]
	_saek = _approach(_saek, 1.0 if Game.sinmyeong_oreum else 0.0, 3.3, delta)
	var mt: float = 1.0 if _boss_alive else _moon_target
	_moon = _approach(_moon, mt, 0.5, delta)
	_beat_pulse = maxf(0.0, _beat_pulse - delta * 4.0)
	_vig_hit = maxf(0.0, _vig_hit - delta * 3.0)
	# 1 저채도 + 4 비네트
	var s: float = clampf(Game.salgi / 100.0, 0.0, 1.0)
	var ds: float = DESAT_BASE + (DESAT_MAX - DESAT_BASE) * clampf((s - SALGI_KNEE) / (1.0 - SALGI_KNEE), 0.0, 1.0)
	var low_hp: float = 0.0
	if in_run and Game.hp_max > 0.0:
		low_hp = clampf(1.0 - (Game.hp / Game.hp_max) / 0.3, 0.0, 1.0)     # 체력 30% 아래에서 먹빛이 조여 온다
	var vig: float = 0.5 + 0.3 * s + 0.15 * low_hp + 0.08 * _vig_hit
	_mat.set_shader_parameter("vignette", minf(vig, 0.95))
	_mat.set_shader_parameter("desaturate", ds)
	# 신명 오름: 가장자리 색동 테는 haewon 의 vfx_sinmyeong_oreum_border 가 그린다 → 셰이더 색동 줄무늬는 끄고 황빛 데움만
	var warm: Color = _tint * Color(1.0 + 0.06 * _saek, 1.0, 1.0 - 0.10 * _saek)
	_mat.set_shader_parameter("tint", warm)
	_mat.set_shader_parameter("aura", _aura)
	_mat.set_shader_parameter("aura_col", _aura_col)
	_mat.set_shader_parameter("saekdong", 0.0)
	_mat.set_shader_parameter("red_moon", _moon)          # 비네트 적빛만(달 원반은 월드 층 RedMoon)
	var vp: VfxPlayer = Game.vfx as VfxPlayer
	if vp != null and vp.moon != null:
		vp.moon.amount = _moon
		vp.moon.beat_pulse = floorf(_beat_pulse * 4.0) / 4.0
	_mat.set_shader_parameter("beat_pulse", floorf(_beat_pulse * 4.0) / 4.0)   # 계단(부드러운 맥동 금지)
	_mat.set_shader_parameter("fx_time", _t)
	_mat.set_shader_parameter("ambient", _ambient if in_run else 1.0)
	_push_lights(in_run)


func _flick(i: int) -> float:
	var step: int = int(floorf(_t * 10.0)) * 7919 + i * 104729
	step = (step ^ (step >> 13)) * 1274126177
	return float(absi(step ^ (step >> 16)) % 2001) / 1000.0 - 1.0


## 광원 하나를 후보 목록에 넣는다(화면 밖이면 버림). 가득 차면 화면 중심에서 가장 먼 것을 바꾼다.
func _offer(n: int, sp: Vector2, r: float, i: float, tone: int, center: Vector2, vs: Vector2) -> int:
	if sp.x < -r or sp.y < -r or sp.x > vs.x + r or sp.y > vs.y + r or r <= 1.0 or i <= 0.001:
		return n
	var d: float = sp.distance_squared_to(center)
	var slot: int = n
	if n >= MAX_LIGHTS:
		var far: float = -1.0
		slot = -1
		for k in MAX_LIGHTS:
			if _cand_d[k] > far:
				far = _cand_d[k]
				slot = k
		if slot < 0 or far <= d:
			return n
	else:
		n += 1
	_lights[slot] = Vector4(floorf(sp.x + 0.5), floorf(sp.y + 0.5), r, i)
	_tones[slot] = float(tone)
	_cand_d[slot] = d
	return n


func _push_lights(in_run: bool) -> void:
	var n: int = 0
	if in_run:
		var xf: Transform2D = get_viewport().get_canvas_transform()
		var vs: Vector2 = get_viewport().get_visible_rect().size
		var center: Vector2 = vs * 0.5
		var pl: Node2D = Game.player
		if pl != null:
			# 무당 개인 광원(design/08 §4.1): 몸 가운데(발 −23px), 촛불 난색 — 맨 앞 슬롯 고정
			var f0: float = _flick(0)
			n = _offer(n, xf * (pl.global_position + Vector2(0, -23)), PLAYER_LIGHT_R_U * K.UNIT_PX + f0 * 2.0,
				PLAYER_LIGHT_I + f0 * 0.03, 0, center, vs)
			_cand_d[0] = -1.0                       # 교체 대상에서 제외
		for li in Juice.LIGHT_CAP:
			if Juice.lt_on[li] == 0:
				continue
			var k: float = 1.0
			if Juice.lt_life[li] > 0.0:
				k = 1.0 - floorf(Juice.lt_age[li] / Juice.lt_life[li] * 4.0) / 4.0   # 수명 광원: 4단 계단 감쇠
			var tn: int = Juice.lt_tone[li]
			var fl: float = _flick(li + 1) if tn == 0 else 0.0
			n = _offer(n, xf * Vector2(Juice.lt_x[li], Juice.lt_y[li]), Juice.lt_r[li] * (1.0 + 0.03 * fl),
				Juice.lt_i[li] * k * (1.0 + 0.06 * fl), tn, center, vs)
		var fc: int = Juice.frame_light_count()
		for fi in fc:
			n = _offer(n, xf * Vector2(Juice.fl_x[fi], Juice.fl_y[fi]), Juice.fl_r[fi], Juice.fl_i[fi], Juice.fl_tone[fi], center, vs)
	stat_light_max = maxi(stat_light_max, n)
	_mat.set_shader_parameter("light_count", n)
	if n > 0:
		_mat.set_shader_parameter("lights", _lights)
		_mat.set_shader_parameter("light_tone", _tones)
