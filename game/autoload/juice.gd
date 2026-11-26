extends Node
## Juice — 타격감 API(흔들림·히트스톱·플래시·데미지 숫자·피드백 티어). 소유: vfx.
## 값의 원본: data/combat_core.json (shake, hitstop, feedback_tiers, flash, feel), data/feedback_matrix.json.
## 게임 코드는 이 API 만 부른다. 구현 세부(노이즈, 레이어, 숫자 글리프)는 vfx 담당이 바꾼다.
##
##   add_trauma(amount)                  흔들림 트라우마 0..1 누적(제곱 응답). 실시간으로 감쇠(히트스톱 중에도).
##   kick(dir, px)                       방향성 정수 킥(1~3px, 2틱 단계 감쇠). GAME_FEEL 5.1 ①
##   shake_offset() -> Vector2           카메라가 매 프레임 더하는 정수 픽셀 오프셋(킥 + 양자화 노이즈, 상한 3px / 보스 4px).
##   hitstop(ms, tier) / hitstop_event(key)  전역 히트스톱(Game.request_hitstop 로 위임, 티어 예산 적용).
##   flash(color, alpha, dur) -> bool    전체 화면 플래시(초당 3회·간격 0.33s·알파 0.30 상한). 백 #f2ece0 은 해원 연출만.
##   damage_number(pos, amount, kind, key)  kind: &"red" &"white" &"crit" &"locked" &"player" &"heal", key = 묶음 키
##   feedback(tier, pos)                 T0..T4 묶음(트라우마+히트스톱). 파티클은 vfx 가 Events 로 처리.
##   feedback_event(key, dir, trauma)    이벤트 이름으로 킥·트라우마·히트스톱·플래시를 한 번에(EVENTS 표 = GAME_FEEL 5.1·5.2).
##   label(pos, text, kind)              글자 표식("해원" "퇴치" "해원 ×12"). 퇴치/해원 구분은 색·움직임이 다르다(damage_numbers.gd).
##   light_pulse(pos, r_px, i, tone, s) / light_add / light_move / light_remove   오컬트 조명 광원(screen_fx 가 읽는다).
##   light_frame(pos, r_px, i, tone)     이번 프레임만 유효한 광원(매 프레임 다시 넣는 쪽: 소품·영가 등).
##   crowd_dim                           밀도 감광 계수 d(0..1, design/13 §2.10.6) — 적 셰이더 유니폼 crowd_dim 으로 공급.
## 접근성(GAME_FEEL 7, 설정 화면이 직접 씀): shake_scale, flash_scale, reduce_motion, enemy_flash_mode, damage_number_mode,
##   Game.hitstop_scale.

var trauma: float = 0.0
var shake_scale: float = 1.0          # 0..1 (combat_core.shake.option_default_scale). 킥 px 에도 곱한다
var flash_enabled: bool = true        # 호환: false 면 flash_scale 0 과 같다
var flash_scale: float = 1.0          # 0 끔 / 0.5 / 1
var reduce_motion: bool = false       # 틸트·걷기 바운스 0, 반동 1px, 흔들림 상한 1px
var enemy_flash_mode: int = 0         # 0 단색 / 1 외곽선만 / 2 끔 (적 셰이더 flash_mode)
var damage_number_mode: int = 0       # 0 자동(군중 규칙) / 1 치명·정예만 / 2 끔 / 3 전부(군중 규칙 무시)
## 가시성 설정(design/18 §4). 다른 분할은 Juice.get(&"player_mark") 처럼 읽고 null 이면 기본값을 쓴다.
var player_mark: int = 1              # 무당 강조 0 끔 / 1 켬(금 테 + 발밑 마름모) / 2 강하게
var crowd_dim_scale: float = 1.0      # 무리 어둡게 0 끔 / 1.0 보통 / 1.4 강하게
var bullet_emphasis: int = 1          # 적 탄 강조 0 끔 / 1 켬 / 2 강하게
var boss_shake: bool = false          # 보스 결과 연출 중이면 흔들림 상한 boss_cap_px(예외)

var _decay: float = 1.8
var _exponent: float = 2.0
var _max_px: Vector2 = Vector2(3, 3)
var _freq: Vector2 = Vector2(18, 27)
var _min_px_thr: float = 0.35
var _sample_hz: float = 30.0
var _cap_px: int = 3
var _boss_cap_px: int = 4
var _noise: FastNoiseLite
var _t: float = 0.0
var _offset: Vector2 = Vector2.ZERO
var _kick_dir: Vector2 = Vector2.ZERO
var _kick_px: int = 0
var _kick_t: float = 99.0
var _boss_shake_left: float = 0.0
const KICK_STEP_S: float = 2.0 / 60.0  # 킥 단계 감쇠 [k, k−1, …, 1] 각 2틱(실시간)
const NOISE_NORM: float = 1.0 / 0.6    # 심플렉스(프랙탈 없음) 실측 진폭 ≈ ±0.6 → ±1 로 정규화

var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_left: float = 0.0
var _flash_dur: float = 0.0
var _flash_alpha: float = 0.0
var _flash_times: PackedFloat32Array = PackedFloat32Array([-10.0, -10.0, -10.0])
var _flash_head: int = 0
var _flash_max_per_sec: int = 3
var _flash_alpha_cap: float = 0.30
var _flash_min_gap: float = 0.33
var _flash_last: float = -10.0
var _flash_prio: int = 0               # 지금(또는 간격 안) 차지한 플래시의 우선순위. 1 피격 / 2 길닦음·대해원 / 3 빙의·신명·보스

var damage_numbers: Node = null       # vfx/damage_numbers.gd (run 이 등록)
## 군중 모드(리뷰 vfx: 18:00 합일·작두 화면이 숫자 소음에 묻힘). HitFeedback 이 매 프레임 정한다.
##   true 면 일반 적 숫자를 끄고 치명·정예·보스·플레이어 숫자만, 동시 표시 상한은 crowd_max_visible.
var number_crowd: bool = false
var crowd_max_visible: int = 16
var _number_hide_until: float = -1.0  # 이 시각(실시간)까지 숫자 전부 숨김(합일 강림 연출 집중)
var _tiers: Dictionary = {}

# ─── 가운데 슬롯(design/18 §2.2): 화면 가운데를 덮는 큰 글은 동시에 1개. ───
##   prio 4 시련 큰 글자 / 3 레벨업·가운데 경고 / 2 거리 카드·거리 슬램 / 1 길닦음 붓 / 0 붓 추임새.
##   시각은 Juice 시계(_t, 히트스톱에 안 늘어남)를 msec 로 쓴다.
var center_owner: StringName = &""
var center_prio: int = -1
var center_until: int = 0

# ─── 밀도 감광(design/13 §2.10.6): Atmosphere 가 4Hz 로 N 을 세어 목표를 정하고 0.5초 선형 보간한다 ───
var crowd_dim: float = 0.0

# ─── 조명 광원(오컬트 후처리 2단계). 좌표는 월드 px, tone 0 난색(촛불) / 1 백(해원) / 2 황(신명) ───
const LIGHT_CAP: int = 32
const FRAME_LIGHT_CAP: int = 48
var lt_x: PackedFloat32Array = PackedFloat32Array()
var lt_y: PackedFloat32Array = PackedFloat32Array()
var lt_r: PackedFloat32Array = PackedFloat32Array()
var lt_i: PackedFloat32Array = PackedFloat32Array()
var lt_life: PackedFloat32Array = PackedFloat32Array()   # 0 = 지속, >0 = 수명(초)
var lt_age: PackedFloat32Array = PackedFloat32Array()
var lt_tone: PackedByteArray = PackedByteArray()
var lt_on: PackedByteArray = PackedByteArray()
var fl_x: PackedFloat32Array = PackedFloat32Array()      # 프레임 광원(매 프레임 초기화)
var fl_y: PackedFloat32Array = PackedFloat32Array()
var fl_r: PackedFloat32Array = PackedFloat32Array()
var fl_i: PackedFloat32Array = PackedFloat32Array()
var fl_tone: PackedByteArray = PackedByteArray()
var fl_n: int = 0
var _fl_frame: int = -1

# ─── 계측(검증 로그용, 런 시작에 0) ───
var stat_hitstop_req: int = 0         # 요청 횟수
var stat_hitstop_ms: int = 0          # 실제 적용 ms 합
var stat_hitstop_t2_ms: int = 0
var stat_hitstop_denied: int = 0      # 예산·쿨다운으로 버려진 요청
var stat_flash_ok: int = 0
var stat_flash_denied: int = 0
var stat_flash_alpha_max: float = 0.0
var stat_shake_max_px: float = 0.0
var stat_shake_frac: int = 0          # 정수가 아닌 오프셋이 나온 프레임 수(0 이어야 한다)
var stat_kicks: int = 0
var stat_events: Dictionary = {}

## 이벤트 → 타격감 묶음(GAME_FEEL 5.1 이벤트 표 + 5.2 티어 표). 값이 없는 항목은 0.
##   tier: 피드백 티어(히트스톱 예산 구분)  kick: 정수 px  trauma: 누적량  hs: combat_core.hitstop.events_ms 키 또는 ms
##   flash: [색 이름, 알파, 길이]  boss_cap: 흔들림 상한 4px 예외(초)
const EVENTS: Dictionary = {
	"crit": {"tier": 1, "kick": 1},
	"kill_burst": {"tier": 1, "kick": 1, "trauma": 0.2},
	"player_hit": {"tier": 1, "kick": 2, "trauma": 0.30, "flash": ["jeok", 0.18, 0.08], "prio": 1},
	"player_hit_big": {"tier": 2, "kick": 2, "trauma": 0.45, "hs": "player_hit_big", "flash": ["jeok", 0.24, 0.10], "prio": 1},
	"jakdu_slam": {"tier": 2, "kick": 1, "trauma": 0.25, "hs": 50},
	"elite_result": {"tier": 2, "kick": 1, "trauma": 0.45, "hs": "elite_result"},
	"gildakkeum": {"tier": 2, "kick": 1, "trauma": 0.25, "hs": "gildakkeum", "flash": ["baek", 0.25, 0.12], "prio": 2},
	"gildakkeum_large": {"tier": 3, "kick": 2, "trauma": 0.5, "hs": "gildakkeum_large", "flash": ["baek", 0.30, 0.15], "prio": 2},
	"sinmyeong_oreum_start": {"tier": 3, "kick": 1, "trauma": 0.5, "hs": "sinmyeong_oreum_start", "flash": ["hwang", 0.30, 0.20], "prio": 3},
	"bingui": {"tier": 3, "kick": 2, "trauma": 0.5, "hs": "bingui", "flash": ["hanji", 0.30, 0.10], "prio": 3},
	"mboss_result": {"tier": 3, "kick": 2, "trauma": 0.8, "hs": "mboss_result"},
	"player_death": {"tier": 3, "kick": 2, "trauma": 0.6, "hs": 150, "flash": ["jeok", 0.30, 0.20], "prio": 3},
	"boss_result": {"tier": 4, "kick": 3, "trauma": 1.0, "hs": "boss_result", "boss_cap": 1.2},
	"revive": {"tier": 4, "kick": 2, "trauma": 0.8, "hs": "revive", "flash": ["hanji", 0.30, 0.20], "prio": 3},
}
## 트라우마 항은 노이즈 정규화 뒤에도 0.3 아래면 1px 미만이다. 그래서 트라우마만으로는 '한 방'이 안 팔리는 이벤트에
## 정수 킥을 같이 준다(GAME_FEEL 5.1 표 1~2px: 길닦음 1 / 큰 길닦음 2 / 신명 오름 1 / 무리 처치 1 / 회생 2). 킥 방향 기본 = 아래.

## 히트스톱 이벤트 → 티어(GAME_FEEL 5.2 표). 없는 키는 ms 로 추정.
const HITSTOP_TIER: Dictionary = {
	"player_hit_big": 2, "elite_result": 2, "hosin": 2, "gildakkeum": 2, "byeoksa_oreum_start": 2, "jakdu_slam": 2,
	"sinmyeong_oreum_start": 3, "gildakkeum_large": 3, "bingui": 3, "mboss_result": 3, "eodukssini_vanish": 3, "player_death": 3,
	"boss_result": 4, "revive": 4,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = 7
	_noise.fractal_type = FastNoiseLite.FRACTAL_NONE   # 기본 FBM 은 출력이 ±0.6 에 머물러 trauma 항이 문턱을 못 넘는다(리뷰 vfx#1)
	_load_params()
	Data.reloaded.connect(_load_params)
	lt_x.resize(LIGHT_CAP)
	lt_y.resize(LIGHT_CAP)
	lt_r.resize(LIGHT_CAP)
	lt_i.resize(LIGHT_CAP)
	lt_life.resize(LIGHT_CAP)
	lt_age.resize(LIGHT_CAP)
	lt_tone.resize(LIGHT_CAP)
	lt_on.resize(LIGHT_CAP)
	fl_x.resize(FRAME_LIGHT_CAP)
	fl_y.resize(FRAME_LIGHT_CAP)
	fl_r.resize(FRAME_LIGHT_CAP)
	fl_i.resize(FRAME_LIGHT_CAP)
	fl_tone.resize(FRAME_LIGHT_CAP)
	Events.run_started.connect(_on_run_started)
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 90
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_layer.add_child(_flash_rect)


func _load_params() -> void:
	_decay = Data.num("combat_core", "shake.decay_per_sec", 1.8)
	_exponent = Data.num("combat_core", "shake.exponent", 2.0)
	var mx: Variant = Data.get_value("combat_core", "shake.max_offset_px", [3, 3])
	if mx is Array and mx.size() >= 2:
		_max_px = Vector2(float(mx[0]), float(mx[1]))
	var fq: Variant = Data.get_value("combat_core", "shake.noise_freq", [18.0, 27.0])
	if fq is Array and fq.size() >= 2:
		_freq = Vector2(float(fq[0]), float(fq[1]))
	shake_scale = Data.num("combat_core", "shake.option_default_scale", 1.0)
	_min_px_thr = Data.num("combat_core", "feel.shake.min_px_threshold", 0.35)
	_sample_hz = maxf(1.0, Data.num("combat_core", "feel.shake.sample_hz", 30.0))
	_cap_px = int(Data.num("combat_core", "feel.shake.cap_px", 3))
	_boss_cap_px = int(Data.num("combat_core", "feel.shake.boss_cap_px", 4))
	_flash_max_per_sec = int(Data.num("combat_core", "flash.fullscreen_max_per_sec", 3))
	_flash_alpha_cap = Data.num("combat_core", "feel.flash.alpha_cap", 0.30)
	_flash_min_gap = Data.num("combat_core", "feel.flash.min_gap_s", 0.33)
	var t: Variant = Data.get_value("combat_core", "feedback_tiers", {})
	_tiers = t if t is Dictionary else {}


## 실시간(히트스톱 중에도 진행 → 정지 화면이 떨려 타격이 팔린다, GAME_FEEL 5.1).
func _process(delta: float) -> void:
	_t += delta
	trauma = maxf(0.0, trauma - _decay * delta)
	if _boss_shake_left > 0.0:
		_boss_shake_left -= delta
		if _boss_shake_left <= 0.0:
			boss_shake = false
	var o: Vector2 = Vector2.ZERO
	if shake_scale > 0.0:
		# ① 킥(방향성 정수, 단계 감쇠)
		_kick_t += delta
		if _kick_px > 0:
			var mag: int = _kick_px - int(_kick_t / KICK_STEP_S)
			if mag > 0:
				o += Vector2(K.rnd(_kick_dir.x * mag), K.rnd(_kick_dir.y * mag))
			else:
				_kick_px = 0
		# ② 노이즈(trauma² 진폭, 30Hz 홀드, |n·a| ≥ 0.35 이면 최소 1px)
		var amt: float = pow(trauma, _exponent) * shake_scale
		if amt > 0.0001:
			var tq: float = floorf(_t * _sample_hz) / _sample_hz
			var nx: float = clampf(_noise.get_noise_2d(tq * _freq.x * 10.0, 0.0) * NOISE_NORM, -1.0, 1.0) * _max_px.x * amt
			var ny: float = clampf(_noise.get_noise_2d(0.0, tq * _freq.y * 10.0) * NOISE_NORM, -1.0, 1.0) * _max_px.y * amt
			o += Vector2(_quant(nx), _quant(ny))
		# ③ 상한
		var cap: float = 1.0 if reduce_motion else float(_boss_cap_px if boss_shake else _cap_px)
		o = Vector2(clampf(o.x, -cap, cap), clampf(o.y, -cap, cap))
	_offset = o
	var om: float = maxf(absf(o.x), absf(o.y))
	if om > stat_shake_max_px:
		stat_shake_max_px = om
	if o.x != floorf(o.x) or o.y != floorf(o.y):
		stat_shake_frac += 1
	# 수명 광원: 실시간으로 나이를 먹는다(히트스톱 중에도 해원 빛이 사그라든다)
	for li in LIGHT_CAP:
		if lt_on[li] == 1 and lt_life[li] > 0.0:
			lt_age[li] += delta
			if lt_age[li] >= lt_life[li]:
				lt_on[li] = 0
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		# 2단계 계단 감쇠(a → a/2 → 0, 각 1/3 길이)
		var k: float = _flash_left / maxf(_flash_dur, 0.001)
		_flash_rect.color.a = _flash_alpha if k > 0.6667 else (_flash_alpha * 0.5 if k > 0.3333 else 0.0)
	elif _flash_rect.color.a != 0.0:
		_flash_rect.color.a = 0.0


func _quant(v: float) -> float:
	var a: float = absf(v)
	if a < _min_px_thr:
		return 0.0
	return signf(v) * maxf(1.0, K.rnd(a))


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## 호환 별칭.
func screen_shake(amount: float) -> void:
	add_trauma(amount)


## 방향성 킥(정수 px). dir 은 8방향 양자화. 진행 중인 킥보다 작으면 무시. shake_scale ≤ 50% 면 최대 1px.
func kick(dir: Vector2, px: int) -> void:
	if shake_scale <= 0.0 or px <= 0:
		return
	var p: int = maxi(1, int(K.rnd(float(px) * shake_scale)))
	if shake_scale <= 0.5:
		p = mini(p, 1)
	var remaining: int = maxi(0, _kick_px - int(_kick_t / KICK_STEP_S))
	if p < remaining:
		return
	var d: Vector2 = K.dir8(dir)
	if d == Vector2.ZERO:
		d = Vector2(0, 1)
	_kick_dir = d
	_kick_px = p
	_kick_t = 0.0
	stat_kicks += 1


## 보스 결과 연출: 흔들림 상한을 잠시 boss_cap_px 로.
func allow_boss_shake(sec: float = 1.0) -> void:
	boss_shake = true
	_boss_shake_left = sec


func shake_offset() -> Vector2:
	return _offset


func hitstop(ms: int, tier: int = 0) -> int:
	if ms <= 0:
		return 0
	var got: int = Game.request_hitstop(ms, tier)
	stat_hitstop_req += 1
	if got > 0:
		stat_hitstop_ms += got
		if tier == 2 or (tier <= 0 and ms <= 80):
			stat_hitstop_t2_ms += got
	else:
		stat_hitstop_denied += 1
	return got


## combat_core.hitstop.events_ms 의 키("gildakkeum", "elite_result", "boss_result" ...). 티어는 HITSTOP_TIER.
func hitstop_event(key: String) -> int:
	return hitstop(int(Data.num("combat_core", "hitstop.events_ms." + key, 0)), int(HITSTOP_TIER.get(key, 0)))


## 전체 화면 플래시. 상한: 초당 fullscreen_max_per_sec, 연속 간격 ≥ feel.flash.min_gap_s, 알파 ≤ feel.flash.alpha_cap × flash_scale.
## 색은 팔레트만(피격 적 #c8322d, 신명 황 #e8b931, 해원 백 #f2ece0 — 백은 해원 전용).
## prio: 1 피격·일반 / 2 길닦음·대해원 / 3 빙의·신명·보스·회생. 간격 안이라도 지금 것보다 prio 가 높으면 덮어쓴다
##       (해원 = 백 빛 신호가 피격 플래시에 밀려 사라지지 않게). 초당 상한은 prio 3 에 예외.
func flash(color: Color, alpha: float = 0.30, duration: float = 0.08, prio: int = 1) -> bool:
	var sc: float = flash_scale if flash_enabled else 0.0
	if sc <= 0.0:
		return false
	var now: float = _t
	var in_gap: bool = now - _flash_last < _flash_min_gap
	if in_gap and prio <= _flash_prio:
		stat_flash_denied += 1
		return false
	if _flash_times.size() != _flash_max_per_sec:
		_flash_times.resize(maxi(1, _flash_max_per_sec))
		_flash_times.fill(-10.0)
		_flash_head = 0
	if prio < 3 and not in_gap and now - _flash_times[_flash_head] < 1.0:
		stat_flash_denied += 1
		return false  # 초당 상한(가장 오래된 기록이 1초 안)
	if not in_gap:
		_flash_times[_flash_head] = now
		_flash_head = (_flash_head + 1) % _flash_times.size()
	_flash_last = now
	_flash_prio = prio
	var a: float = minf(alpha, _flash_alpha_cap) * sc
	_flash_rect.color = Color(color.r, color.g, color.b, a)
	_flash_alpha = a
	_flash_dur = clampf(duration, 0.06, 0.20)
	_flash_left = _flash_dur
	stat_flash_ok += 1
	stat_flash_alpha_max = maxf(stat_flash_alpha_max, a)
	return true


## key: 묶음 키(같은 적 핸들 등, -1 이면 묶지 않음). 0.15s 안의 같은 키 타격은 한 숫자로 합산(GAME_FEEL 5.4).
## important: 정예 이상 등(damage_number_mode 1 에서도 표시).
func damage_number(pos: Vector2, amount: float, kind: StringName = &"red", key: int = -1, important: bool = false) -> void:
	if damage_number_mode == 2:   # 2 끔만. 3 '전부'는 군중 규칙만 무시(>= 2 로 쓰면 '전부'가 꺼진다)
		return
	if _t < _number_hide_until and kind != &"player":
		return
	if (damage_number_mode == 1 or (number_crowd and damage_number_mode != 3)) and not important and kind != &"crit" and kind != &"player":
		return
	if damage_numbers != null and damage_numbers.has_method("spawn"):
		damage_numbers.call("spawn", pos, amount, kind, key)


## 피드백 티어 묶음. tier: 0..4 (combat_core.feedback_tiers T0..T4). 범위 값은 strength(0..1)로 보간.
func feedback(tier: int, _pos: Vector2, strength: float = 0.5) -> void:
	var key: String = "T%d" % clampi(tier, 0, 4)
	var t: Dictionary = _tiers.get(key, {})
	var tr: Variant = t.get("trauma", [0.0, 0.0])
	if tr is Array and tr.size() >= 2:
		add_trauma(lerpf(float(tr[0]), float(tr[1]), strength))
	var hs: Variant = t.get("hitstop_ms", 0)
	if hs is Array and hs.size() >= 2:
		hitstop(int(lerpf(float(hs[0]), float(hs[1]), strength)), tier)
	elif hs is float or hs is int:
		hitstop(int(hs), tier)


## 이벤트 이름으로 타격감 묶음을 낸다(EVENTS 표). dir: 킥 방향(공격 방향·피격 반대 방향). trauma_override ≥ 0 이면 표 값 대신.
## 반환: 실제 적용된 히트스톱 ms.
func feedback_event(key: String, dir: Vector2 = Vector2.ZERO, trauma_override: float = -1.0) -> int:
	var e: Dictionary = EVENTS.get(key, {})
	if e.is_empty():
		return 0
	stat_events[key] = int(stat_events.get(key, 0)) + 1
	if e.has("boss_cap"):
		allow_boss_shake(float(e["boss_cap"]))
	var k: int = int(e.get("kick", 0))
	if k > 0:
		kick(dir if dir != Vector2.ZERO else Vector2(0, 1), k)
	var tr: float = trauma_override if trauma_override >= 0.0 else float(e.get("trauma", 0.0))
	if tr > 0.0:
		add_trauma(tr)
	var applied: int = 0
	var hs: Variant = e.get("hs", 0)
	var tier: int = int(e.get("tier", 0))
	if hs is String:
		applied = hitstop(int(Data.num("combat_core", "hitstop.events_ms." + String(hs), 0)), tier)
	elif int(hs) > 0:
		applied = hitstop(int(hs), tier)
	var fl: Variant = e.get("flash", null)
	if fl is Array and fl.size() >= 3:
		flash(_named_col(String(fl[0])), float(fl[1]), float(fl[2]), int(e.get("prio", clampi(tier, 1, 3))))
	return applied


func _named_col(n: String) -> Color:
	match n:
		"jeok":
			return K.COL_JEOK
		"baek":
			return K.COL_BAEK            # 해원 전용
		"hwang":
			return K.COL_HWANG
	return K.COL_HANJI


# ─── 가운데 슬롯 ───────────────────────────────────────────────────────

func _center_now() -> int:
	return int(_t * 1000.0)


## 가운데 슬롯을 sec 초 동안 차지한다. 지금 주인보다 prio 가 낮으면 false(그리지 말 것). 같거나 높으면 덮어쓴다.
## 같은 주인이 다시 부르면 시간만 늘린다.
func claim_center(owner: StringName, prio: int, sec: float) -> bool:
	var now: int = _center_now()
	if center_owner != &"" and now >= center_until:
		center_owner = &""
		center_prio = -1
	if center_owner != &"" and center_owner != owner and prio < center_prio:
		return false
	center_owner = owner
	center_prio = prio
	center_until = now + int(maxf(sec, 0.0) * 1000.0)
	return true


## 가운데 슬롯이 min_prio 이상의 주인에게 차지돼 있는가.
func center_busy(min_prio: int = 0) -> bool:
	if center_owner == &"" or _center_now() >= center_until:
		return false
	return center_prio >= min_prio


## 주인이 일찍 끝냈을 때 비운다(다른 주인 것이면 무시).
func release_center(owner: StringName) -> void:
	if center_owner == owner:
		center_owner = &""
		center_prio = -1
		center_until = 0


## 지금 가운데 주인(비었으면 &"").
func center_current() -> StringName:
	return center_owner if center_busy(0) else &""


## sec 초 동안 피해 숫자를 전부 숨긴다(플레이어 피격 숫자 제외). 합일 강림 1.5초 등.
func hide_numbers(sec: float) -> void:
	_number_hide_until = maxf(_number_hide_until, _t + sec)


func numbers_hidden() -> bool:
	return _t < _number_hide_until


## 글자 표식(퇴치/해원 구분, damage_numbers.gd). kind: &"haewon" 백·천천히 상승 / &"toechi" 적·짧게 튐 / &"ring" 백 큰 글자.
func label(pos: Vector2, text: String, kind: StringName = &"haewon") -> void:
	if damage_number_mode == 2:   # 2 끔만. 3 '전부'는 군중 규칙만 무시(>= 2 로 쓰면 '전부'가 꺼진다)
		return
	if damage_numbers != null and damage_numbers.has_method("spawn_label"):
		damage_numbers.call("spawn_label", pos, text, kind)


# ─── 조명 광원 ────────────────────────────────────────────────────────

## 수명 광원(해원 빛기둥 1.0 → 0 등). 강도는 수명 동안 계단으로 줄어든다. 가득 차면 가장 오래된 수명 광원을 덮는다.
func light_pulse(pos: Vector2, radius_px: float, intensity: float, tone: int = 0, life_s: float = 0.6) -> int:
	var slot: int = -1
	var oldest: float = -1.0
	for i in LIGHT_CAP:
		if lt_on[i] == 0:
			slot = i
			break
		if lt_life[i] > 0.0 and lt_age[i] / lt_life[i] > oldest:
			oldest = lt_age[i] / lt_life[i]
			slot = i
	if slot < 0:
		return -1
	lt_on[slot] = 1
	lt_x[slot] = pos.x
	lt_y[slot] = pos.y
	lt_r[slot] = radius_px
	lt_i[slot] = intensity
	lt_tone[slot] = tone
	lt_life[slot] = maxf(life_s, 0.0)
	lt_age[slot] = 0.0
	return slot


## 지속 광원(등불 등). light_remove 로 끈다.
func light_add(pos: Vector2, radius_px: float, intensity: float, tone: int = 0) -> int:
	return light_pulse(pos, radius_px, intensity, tone, 0.0)


func light_move(id: int, pos: Vector2) -> void:
	if id >= 0 and id < LIGHT_CAP and lt_on[id] == 1:
		lt_x[id] = pos.x
		lt_y[id] = pos.y


func light_remove(id: int) -> void:
	if id >= 0 and id < LIGHT_CAP:
		lt_on[id] = 0


## 이번 프레임만 유효한 광원. 매 프레임 _process 에서 다시 넣는다(소품·따라다니는 빛).
func light_frame(pos: Vector2, radius_px: float, intensity: float, tone: int = 0) -> void:
	var f: int = Engine.get_process_frames()
	if f != _fl_frame:
		_fl_frame = f
		fl_n = 0
	if fl_n >= FRAME_LIGHT_CAP:
		return
	fl_x[fl_n] = pos.x
	fl_y[fl_n] = pos.y
	fl_r[fl_n] = radius_px
	fl_i[fl_n] = intensity
	fl_tone[fl_n] = tone
	fl_n += 1


## 이번 프레임에 들어온 프레임 광원 수(지난 프레임 것이면 0).
func frame_light_count() -> int:
	return fl_n if _fl_frame == Engine.get_process_frames() else 0


func _on_run_started(_char_id: StringName) -> void:
	trauma = 0.0
	_kick_px = 0
	crowd_dim = 0.0
	number_crowd = false
	_number_hide_until = -1.0
	_flash_prio = 0
	center_owner = &""
	center_prio = -1
	center_until = 0
	lt_on.fill(0)
	fl_n = 0
	stat_hitstop_req = 0
	stat_hitstop_ms = 0
	stat_hitstop_t2_ms = 0
	stat_hitstop_denied = 0
	stat_flash_ok = 0
	stat_flash_denied = 0
	stat_flash_alpha_max = 0.0
	stat_shake_max_px = 0.0
	stat_shake_frac = 0
	stat_kicks = 0
	stat_events.clear()


## 검증 로그 한 줄(봇 리포트 시각·종료 시 HitFeedback 이 찍는다).
func stats_line() -> String:
	return "hitstop req=%d applied_ms=%d (T2 %d) denied=%d | flash ok=%d denied=%d alpha_max=%.2f | shake max_px=%d frac_frames=%d kicks=%d | crowd_dim=%.2f" % [
		stat_hitstop_req, stat_hitstop_ms, stat_hitstop_t2_ms, stat_hitstop_denied, stat_flash_ok, stat_flash_denied,
		stat_flash_alpha_max, int(stat_shake_max_px), stat_shake_frac, stat_kicks, crowd_dim]

