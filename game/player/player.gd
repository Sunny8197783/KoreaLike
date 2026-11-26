class_name Player
extends Node2D
## 플레이어: 이동(스틱 360°/키보드 8방향) + 4방향 스프라이트 애니. 소유: core(리드).
## 피격 파이프라인은 player_hit.gd(소유: combat)에 위임한다.
## 입력은 이동만(캐논). 공격은 무구가 장단 박에 맞춰 자동으로 한다.
##
## 연출 레이어(GAME_FEEL 2장) — 시뮬레이션 무변경, 렌더 전용:
##   · 시뮬 좌표(global_position) = 발(지면 접점). 스프라이트는 발 피벗 offset 으로 그 위에 선다(2.2).
##   · render(alpha): prev/cur 보간 → K.rndv 정수 좌표(2.6 P_r) → 애니·스쿼시·기울기·반동·점멸.
##   · Sprite2D + actor_pixel 셰이더(S/E/N 3행 아틀라스, west = east 반전, 정수 힌지 스쿼시·밴드 기울기·단색 플래시).
##   · 걷기 재생 = 12fps × clamp(|v|/기본속도, 0.8, 1.6), 위상 하나(방향 전환 시 프레임 유지), idle 4f 6fps.
##   · 연출 시계 = Game.anim_dt / anim_tick_cur(히트스톱·일시정지에서 정지).
##   · 가시성(design/18 §1.3·1.4): 자식 Rim(z7 절대, 같은 셀·셰이더 rim_mode 1) = 몸 밖 금 #f5d66b 1px + 먹 1px 테가
##     앞줄 잡귀·내 VFX 위에 늘 보인다. FootMark(z7) = 발밑 3px 금 마름모(+강하게: 22×9 금 타원 테).
##     무적 점멸 숨김 틱은 몸을 지우지 않고 Rim 이 실루엣(rim_mode 2: 먹 몸 + 금 테)으로 바뀐다. 피격 2틱은 테 jk-hi.
##     Juice.player_mark(0 끔 / 1 켬 / 2 강하게, 없으면 1)를 Juice.get 으로 읽는다. 끔이어도 점멸 실루엣은 남긴다.

var char_id: StringName = &"char_mansin"
var vel: Vector2 = Vector2.ZERO
var move_input: Vector2 = Vector2.ZERO
var last_move_dir: Vector2 = Vector2.DOWN
var facing: int = K.Dir.SOUTH
var crowd_touching: int = 0
var speed_mult_ext: float = 1.0            # 외부 감속/가속(지형·시련 등) 곱

var _base_speed: float = 4.0 * 32.0
var _accel_time: float = 0.06
var _decel_time: float = 0.05
var _crowd_per: float = 0.06
var _crowd_floor: float = 0.55
var _total_floor: float = 0.4
var _hysteresis: float = 10.0
var _outer_dz: float = 0.95

var hit: PlayerHit
var sprite: Sprite2D
var shadow: Sprite2D
var rim: Sprite2D                           # 금 테·점멸 실루엣(z7)
var foot_mark: Node2D                       # 발밑 마름모·타원(z7)
var held: HeldWeapon = null                 # 손에 든 무기(design/19 §6, 렌더 전용)
var cell_anim: String = "idle"              # 이번 프레임 셀(손 기준점 anchors 조회용)
var cell_frame: int = 0
var _aim: Vector2 = Vector2.DOWN            # 마지막 공격 방향(가장 가까운 적 쪽). 쏜 적 없으면 이동 방향
var _bot: PlayerBot = null

# --- 렌더 상태 ---
var prev_pos: Vector2 = Vector2.ZERO        # 마지막 진행 틱 직전 발 좌표(보간 기준)
var render_pos: Vector2 = Vector2.ZERO      # P_r: 이번 프레임 정수 발 좌표(월드)
var interp_pos: Vector2 = Vector2.ZERO      # P_f: 보간 발 좌표(실수)
var cam_lift: int = 23                      # 카메라 대상점 = 발 + (0, −round(body_h/2))
var dead: bool = false

var _mat: ShaderMaterial
var _rim_mat: ShaderMaterial
var _mark: int = 1                          # 마지막으로 그린 player_mark(발밑 표지 다시 그리기 판정)
var _rim_hot: bool = false
var _atl: Dictionary = {}                   # &"idle" &"walk" &"hurt" &"death" -> SpriteLib.anim_atlas
var _cur_key: StringName = &""
var _moving: bool = false
var _walk_phase: float = 0.0
var _idle_phase: float = 0.0
var _stop_target: int = -1                  # 이동→정지: 마저 재생할 접지 프레임(-1 없음)
var _flip: bool = false
var _row: int = 0
var _sq: Array[PackedInt32Array] = []       # [시작 틱, dy, dx, 길이, 2단계(1/0)]
var _hurt_tick: int = -100000
var _death_t: float = 0.0
var _tilt: float = 0.0                      # 명목각(도) 연속값
var _tilt_px: int = 0                       # 머리 시프트(정수, 밴드 히스테리시스)
var _recoil_dir: Vector2 = Vector2.ZERO
var _recoil_px: int = 0
var _recoil_tick: int = -100000
var _blink_tick: int = -100000

# --- 수치(combat_core.feel, GAME_FEEL 6) ---
var _walk_fps: float = 12.0
var _ratio_min: float = 0.8
var _ratio_max: float = 1.6
var _idle_fps: float = 6.0
var _move_on_sq: float = 16.0
var _move_off_sq: float = 9.0
var _stop_speed: float = 1.5
var _tilt_deg: float = 5.0
var _tilt_max: int = 2
var _tilt_rate: float = 14.0
var _tilt_hys: float = 0.15
var _recoil_steps: PackedInt32Array = PackedInt32Array([2, 3])
var _sq_land: PackedInt32Array = PackedInt32Array([2, 1, 6])
var _sq_start: PackedInt32Array = PackedInt32Array([-2, 0, 4])
var _sq_turn: PackedInt32Array = PackedInt32Array([0, -1, 3])
var _sq_hurt: PackedInt32Array = PackedInt32Array([2, 1, 6])
var _sq_cap: Vector2i = Vector2i(2, 1)
var _blink_on: int = 6
var _blink_off: int = 3
var _hurt_frames: PackedInt32Array = PackedInt32Array([1, 3])
var _hurt_ticks_per: int = 4
var _death_fps: float = 10.0
var _recoil_map: Dictionary = {&"wpn_sinkal": 2, &"wpn_gakgung": 2, &"wpn_jijeon": 1, &"wpn_sainsageom": 2}

const SHADOW_W: int = 18
const SHADOW_H: int = 5
const RIM_Z: int = 7
const RIM_ALPHA: float = 0.9
const COL_GOLD: Color = Color(0.9608, 0.8392, 0.4196)      # 금 #f5d66b (무당만의 표지)
const COL_INK: Color = Color(0.0549, 0.0431, 0.0863)       # 먹 #0e0b16
const COL_JKHI: Color = Color(0.8941, 0.3765, 0.3098)      # jk-hi #e4604f (피격 순간 테)
const RIM_HIT_TICKS: int = 2
const FOOT_DY: int = 11                     # 발 피벗 아래 마름모 중심(정기 바 y+3~+8 바로 밑 — guide.gd _draw_feet)

## 22×9 타원 테 픽셀(금 = 안쪽 경계, 먹 = 바로 바깥). 처음 쓸 때 한 번 계산.
static var _ell_gold: Array[Vector2i] = []
static var _ell_ink: Array[Vector2i] = []


func _ready() -> void:
	_base_speed = Data.num("combat_core", "move.base_speed_u", 4.0) * K.UNIT_PX
	_accel_time = Data.num("combat_core", "move.accel_time", 0.06)
	_decel_time = Data.num("combat_core", "move.decel_time", 0.05)
	_crowd_per = Data.num("combat_core", "move.crowd_slow_per_enemy", 0.06)
	_crowd_floor = Data.num("combat_core", "move.crowd_slow_floor", 0.55)
	_total_floor = Data.num("combat_core", "move.total_slow_floor", 0.4)
	_hysteresis = Data.num("combat_core", "move.facing_sprite_hysteresis_deg", 10.0)
	_outer_dz = Data.num("combat_core", "input.stick_deadzone_outer", 0.95)
	_load_feel()
	sprite = $Sprite as Sprite2D
	sprite.centered = false
	sprite.region_enabled = true
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/actor_pixel.gdshader") as Shader
	sprite.material = _mat
	_setup_rim()
	_setup_held()
	shadow = $Shadow as Sprite2D
	shadow.texture = SpriteLib.shadow_tex(SHADOW_W, SHADOW_H)
	shadow.centered = false
	shadow.offset = Vector2(-SHADOW_W / 2, -(SHADOW_H / 2))
	shadow.z_as_relative = false
	shadow.z_index = -1                       # 지면(-10) 위, 적(0) 아래
	shadow.modulate = Color(1, 1, 1, Data.num("combat_core", "feel.shadow.alpha", 0.45))
	hit = PlayerHit.new()
	hit.name = "Hit"
	add_child(hit)
	if Game.autotest:
		_bot = PlayerBot.new()
	Events.player_damaged.connect(_on_damaged)
	Events.weapon_fired.connect(_on_weapon_fired)


## 금 테(Rim)와 발밑 표지(FootMark). 씬에 있으면 쓰고 없으면 만든다. 렌더 전용(시뮬·난수 무관).
func _setup_rim() -> void:
	rim = get_node_or_null(^"Rim") as Sprite2D
	if rim == null:
		rim = Sprite2D.new()
		rim.name = "Rim"
		add_child(rim)
	rim.centered = false
	rim.region_enabled = true
	rim.z_as_relative = false
	rim.z_index = RIM_Z
	rim.self_modulate = Color(1, 1, 1, RIM_ALPHA)
	_rim_mat = ShaderMaterial.new()
	_rim_mat.shader = _mat.shader
	_rim_mat.set_shader_parameter("rim_mode", 1)
	_rim_mat.set_shader_parameter("col_rim", COL_GOLD)
	_rim_mat.set_shader_parameter("col_ink", COL_INK)
	rim.material = _rim_mat
	foot_mark = get_node_or_null(^"FootMark") as Node2D
	if foot_mark == null:
		foot_mark = Node2D.new()
		foot_mark.name = "FootMark"
		add_child(foot_mark)
	foot_mark.z_as_relative = false
	foot_mark.z_index = RIM_Z
	foot_mark.draw.connect(_draw_foot_mark)
	_mark = _player_mark()
	if _mark >= 2:
		_build_ellipse()


## 손 무기 층: 몸 Sprite 바로 다음(트리 순서 = 같은 z 에서 몸 위), 금 테 Rim(z7) 아래.
func _setup_held() -> void:
	held = HeldWeapon.new()
	held.name = "Held"
	held.player = self
	add_child(held)
	move_child(held, sprite.get_index() + 1)


## 손 위치(월드, 렌더 정수 좌표). which: &"main" | &"off" | &"both" (design/19 §6.1)
func hand_world(which: StringName = &"main") -> Vector2:
	if held == null:
		return render_pos + Vector2(0, -16)
	return global_position + held.hand_local(which)


## 마지막 공격 방향(쏜 순간 가장 가까운 적 쪽). 쏜 적이 없으면 이동 방향.
func aim_dir() -> Vector2:
	return _aim if _aim.length_squared() > 0.01 else last_move_dir


static func _player_mark() -> int:
	var v: Variant = Juice.get(&"player_mark")
	return clampi(int(v), 0, 2) if (v is int or v is float) else 1


## 두 재질(몸·테)에 같은 셀·변형 값을 넣는다.
func _set_p(param: StringName, value: Variant) -> void:
	_mat.set_shader_parameter(param, value)
	if _rim_mat != null:
		_rim_mat.set_shader_parameter(param, value)


## 발밑 표지(로컬 좌표, 원점 = 정수 발 좌표). 켬: 3px 금 마름모 + 먹 테. 강하게: + 22×9 금 타원 테(먹 받침).
func _draw_foot_mark() -> void:
	if _mark <= 0:
		return
	if _mark >= 2:
		for q: Vector2i in _ell_ink:
			foot_mark.draw_rect(Rect2(Vector2(q), Vector2.ONE), COL_INK)
		for q2: Vector2i in _ell_gold:
			foot_mark.draw_rect(Rect2(Vector2(q2), Vector2.ONE), COL_GOLD)
	var c: Vector2 = Vector2(0, FOOT_DY)
	# 먹 테(마름모 반지름 2)
	foot_mark.draw_rect(Rect2(c + Vector2(0, -2), Vector2.ONE), COL_INK)
	foot_mark.draw_rect(Rect2(c + Vector2(-1, -1), Vector2(3, 1)), COL_INK)
	foot_mark.draw_rect(Rect2(c + Vector2(-2, 0), Vector2(5, 1)), COL_INK)
	foot_mark.draw_rect(Rect2(c + Vector2(-1, 1), Vector2(3, 1)), COL_INK)
	foot_mark.draw_rect(Rect2(c + Vector2(0, 2), Vector2.ONE), COL_INK)
	# 금 마름모(가로·세로 3px)
	foot_mark.draw_rect(Rect2(c + Vector2(0, -1), Vector2(1, 3)), COL_GOLD)
	foot_mark.draw_rect(Rect2(c + Vector2(-1, 0), Vector2(3, 1)), COL_GOLD)


static func _build_ellipse() -> void:
	if not _ell_gold.is_empty():
		return
	var inside: Dictionary = {}
	for y in range(-6, 7):
		for x in range(-13, 13):
			var nx: float = (float(x) + 0.5) / 11.0
			var ny: float = float(y) / 4.5
			if nx * nx + ny * ny <= 1.0:
				inside[Vector2i(x, y)] = true
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for q: Vector2i in inside:
		for d: Vector2i in dirs:
			if not inside.has(q + d):
				_ell_gold.append(q)
				break
	for q2: Vector2i in _ell_gold:
		for d2: Vector2i in dirs:
			var o: Vector2i = q2 + d2
			if not inside.has(o) and not _ell_ink.has(o):
				_ell_ink.append(o)


## 매 프레임: 테 스프라이트를 몸과 같은 셀·위치·반전으로 맞추고 모드·색을 고른다.
## hidden = 무적 점멸 숨김 틱(몸 대신 실루엣).
var _rim_mode_sent: int = -1
var _rim_w_sent: int = -1


func _sync_rim(hidden: bool, tick: int) -> void:
	if rim == null:
		return
	var mark: int = _player_mark()
	if mark != _mark:
		_mark = mark
		if mark >= 2:
			_build_ellipse()
		foot_mark.queue_redraw()
	rim.texture = sprite.texture
	rim.region_rect = sprite.region_rect
	rim.offset = sprite.offset
	rim.flip_h = sprite.flip_h
	rim.position = sprite.position
	foot_mark.position = shadow.position
	foot_mark.visible = mark > 0 and not dead
	if hidden:
		rim.visible = true
		rim.self_modulate.a = 1.0
	else:
		rim.visible = mark > 0
		rim.self_modulate.a = RIM_ALPHA
	# 셰이더 파라미터는 바뀔 때만 보낸다(매 프레임 set_shader_parameter 2회 → 0회, 리뷰 regression 성능)
	var rm: int = 2 if hidden else 1
	if rm != _rim_mode_sent:
		_rim_mode_sent = rm
		_rim_mat.set_shader_parameter("rim_mode", rm)
	var rw: int = 2 if mark >= 2 else 1
	if rw != _rim_w_sent:
		_rim_w_sent = rw
		_rim_mat.set_shader_parameter("rim_w", rw)
	var hot: bool = tick - _hurt_tick >= 0 and tick - _hurt_tick < RIM_HIT_TICKS
	if hot != _rim_hot:
		_rim_hot = hot
		_rim_mat.set_shader_parameter("col_rim", COL_JKHI if hot else COL_GOLD)


func _load_feel() -> void:
	_walk_fps = Data.num("combat_core", "feel.walk.fps", 12.0)
	_ratio_min = Data.num("combat_core", "feel.walk.ratio_min", 0.8)
	_ratio_max = Data.num("combat_core", "feel.walk.ratio_max", 1.6)
	_idle_fps = Data.num("combat_core", "feel.idle.fps", 6.0)
	_move_on_sq = Data.num("combat_core", "feel.move_on_sq", 16.0)
	_move_off_sq = Data.num("combat_core", "feel.move_off_sq", 9.0)
	_stop_speed = Data.num("combat_core", "feel.stop_finish_speed", 1.5)
	_tilt_deg = Data.num("combat_core", "feel.tilt.deg", 5.0)
	_tilt_max = int(Data.num("combat_core", "feel.tilt.max_px", 2))
	_tilt_rate = Data.num("combat_core", "feel.tilt.rate", 14.0)
	_tilt_hys = Data.num("combat_core", "feel.tilt.band_hys", 0.15)
	_recoil_steps = _ints("feel.recoil.steps_ticks", _recoil_steps)
	_sq_land = _ints("feel.squash.land", _sq_land)
	_sq_start = _ints("feel.squash.start", _sq_start)
	_sq_turn = _ints("feel.squash.turn", _sq_turn)
	_sq_hurt = _ints("feel.squash.hurt", _sq_hurt)
	var cap: PackedInt32Array = _ints("feel.squash.cap_player", PackedInt32Array([2, 1]))
	_sq_cap = Vector2i(cap[0], cap[1]) if cap.size() >= 2 else Vector2i(2, 1)
	var bl: PackedInt32Array = _ints("feel.iframe_blink_ticks", PackedInt32Array([6, 3]))
	if bl.size() >= 2:
		_blink_on = maxi(1, bl[0])
		_blink_off = maxi(0, bl[1])
	_hurt_frames = _ints("feel.hurt.frames", _hurt_frames)
	_hurt_ticks_per = int(Data.num("combat_core", "feel.hurt.ticks_per_frame", 4))
	_death_fps = Data.num("combat_core", "feel.death.fps", 10.0)


static func _ints(path: String, default: PackedInt32Array) -> PackedInt32Array:
	var v: Variant = Data.get_value("combat_core", path, null)
	if not (v is Array):
		return default
	var out: PackedInt32Array = PackedInt32Array()
	for e: Variant in v:
		if e is float or e is int:
			out.append(int(e))
	return out if not out.is_empty() else default


func setup(p_char_id: StringName) -> void:
	char_id = p_char_id
	var id: String = String(char_id)
	_atl.clear()
	_atl[&"idle"] = SpriteLib.anim_atlas(id, PackedStringArray(["idle", "walk"]), 48)
	_atl[&"walk"] = SpriteLib.anim_atlas(id, PackedStringArray(["walk", "idle"]), 48)
	var hu: Dictionary = SpriteLib.anim_atlas(id, PackedStringArray(["hurt"]), 48)
	if String(hu.get("anim", "")) == "hurt":
		_atl[&"hurt"] = hu
	var de: Dictionary = SpriteLib.anim_atlas(id, PackedStringArray(["death"]), 48)
	if String(de.get("anim", "")) == "death":
		_atl[&"death"] = de
	cam_lift = int(K.rnd(float(int(_atl[&"idle"]["body_h"])) * 0.5))
	_cur_key = &""
	_walk_phase = 0.0
	_idle_phase = 0.0
	_moving = false
	dead = false
	prev_pos = global_position
	interp_pos = global_position
	render_pos = K.rndv(global_position)
	_apply_cell(&"idle", 0, 0)


## 연습 굿판 자동 테스트(design/17 §7.3): 봇 교체.
func set_bot(b: PlayerBot) -> void:
	_bot = b


## 프레임 입력 샘플링(시뮬레이션 틱과 분리). 히트스톱 중 입력은 버퍼링되어 해제 즉시 반영된다.
func _process(_delta: float) -> void:
	if dead:
		move_input = Vector2.ZERO
		return
	if _bot != null:
		move_input = _bot.input(self)
	else:
		var v: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		var l: float = v.length()
		if l > _outer_dz:
			v = v / l
		elif l > 0.0:
			v = v / _outer_dz  # 아날로그 풀스피드 근접(analog_full_speed)
			if v.length() > 1.0:
				v = v.normalized()
		move_input = v


## 틱 3: 이동.
func sim_step(dt: float) -> void:
	var crowd: float = maxf(_crowd_floor, 1.0 - _crowd_per * float(crowd_touching))
	var mult: float = maxf(_total_floor, crowd * speed_mult_ext)
	var domu: float = Game.stat(&"stat_domu", 1.0)
	var target: Vector2 = move_input * _base_speed * domu * mult
	var t: float = _accel_time if target.length_squared() > vel.length_squared() else _decel_time
	var a: float = 1.0 - exp(-dt / maxf(t, 0.001))
	vel = vel.lerp(target, a)
	if vel.length_squared() < 1.0:
		vel = Vector2.ZERO
	global_position += vel * dt
	if move_input.length_squared() > 0.01:
		last_move_dir = move_input.normalized()
	hit.sim_step(dt)


func take_hit(amount: float, source: StringName) -> void:
	if dead:
		return
	hit.take_hit(amount, source)


## run.gd 가 진행 틱 시작(과 히트스톱·일시정지 동결)에서 호출.
func store_prev() -> void:
	prev_pos = global_position


## 사망 연출 시작(run.gd). 입력·피격 차단, death 애니 → 마지막 프레임 홀드.
func begin_death() -> void:
	dead = true
	_death_t = 0.0
	move_input = Vector2.ZERO
	vel = Vector2.ZERO


# ─── 렌더 (R2) ─────────────────────────────────────────────────────────

func render(alpha: float) -> void:
	if _atl.is_empty():
		return
	var adt: float = Game.anim_dt
	var tick: int = Game.anim_tick_cur
	interp_pos = prev_pos.lerp(global_position, alpha)
	render_pos = K.rndv(interp_pos)
	var reduce: bool = Juice.reduce_motion
	# --- 사망 ---
	if dead and _atl.has(&"death"):
		_death_t += adt
		var dat: Dictionary = _atl[&"death"]
		var n: int = int(dat["counts"][0])
		_apply_cell(&"death", 0, mini(int(_death_t * _death_fps), n - 1))
		_flip = false
		sprite.flip_h = false
		_set_shader(0, 0, 0.0, 0)
		_place(Vector2.ZERO)
		sprite.visible = true
		_sync_rim(false, Game.anim_tick_cur)
		if held != null:
			held.sync(false)
		return
	# --- 이동/정지 판정(히스테리시스) ---
	var v2: float = vel.length_squared()
	var want_move: bool = v2 > _move_on_sq if not _moving else v2 >= _move_off_sq
	if dead:
		want_move = false
	if want_move:
		var nf: int = K.dir4_from_vec(vel, facing, _hysteresis)
		if nf != facing:
			var was_flip: bool = facing == K.Dir.WEST
			var now_flip: bool = nf == K.Dir.WEST
			if was_flip != now_flip and (facing == K.Dir.EAST or facing == K.Dir.WEST) and (nf == K.Dir.EAST or nf == K.Dir.WEST):
				_push_sq(tick, _sq_turn, false)    # 턴 핀치(E↔W 반전)
			facing = nf
	var walk: Dictionary = _atl[&"walk"]
	var wn: int = maxi(1, int(walk["cols"]))
	if want_move and not _moving:
		_moving = true
		_stop_target = -1
		_walk_phase = 0.0                        # walk f0 = idle_0 과 같은 자세에서 시작
		_push_sq(tick, _sq_start, true)
	elif not want_move and _moving:
		_moving = false
		var cur_f: int = int(floorf(fposmod(_walk_phase, 1.0) * wn))
		var half: int = maxi(1, wn / 2)
		if wn >= 4 and (cur_f + 1) % half == 0:
			_stop_target = (cur_f + 1) % wn     # 접지 포즈 1프레임 전 → 마저 재생
		else:
			_enter_idle(tick)
	_row = K.DIR_ROW[facing]
	_flip = facing == K.Dir.WEST
	# --- 애니 위상 ---
	var key: StringName = &"idle"
	var frame: int = 0
	if _moving or _stop_target >= 0:
		var ratio: float = 1.0 if _stop_target >= 0 else clampf(sqrt(v2) / _base_speed, _ratio_min, _ratio_max)
		var spd: float = _stop_speed if _stop_target >= 0 else ratio
		var before: int = int(floorf(fposmod(_walk_phase, 1.0) * wn))
		_walk_phase += adt * _walk_fps * spd / float(wn)
		frame = int(floorf(fposmod(_walk_phase, 1.0) * wn))
		key = &"walk"
		if _stop_target >= 0 and before != frame and (frame == _stop_target or before == _stop_target):
			_stop_target = -1
			_enter_idle(tick)
			key = &"idle"
			frame = 0
	if key == &"idle":
		var idl: Dictionary = _atl[&"idle"]
		var inn: int = maxi(1, int(idl["cols"]))
		_idle_phase += adt * _idle_fps / float(inn)
		frame = int(floorf(fposmod(_idle_phase, 1.0) * inn))
	# --- hurt 덧씌움(2프레임, 걷기 위상은 계속 돈다) ---
	var he: int = tick - _hurt_tick
	if _atl.has(&"hurt") and he >= 0 and he < _hurt_ticks_per * _hurt_frames.size():
		var hat: Dictionary = _atl[&"hurt"]
		key = &"hurt"
		frame = clampi(_hurt_frames[he / maxi(1, _hurt_ticks_per)], 0, int(hat["cols"]) - 1)
	_apply_cell(key, _row, frame)
	sprite.flip_h = _flip
	# --- 스쿼시 합(상한) + 걷기 바운스 ---
	var dy: int = 0
	var dx: int = 0
	for k in range(_sq.size() - 1, -1, -1):
		var e: PackedInt32Array = _sq[k]
		var t: int = tick - e[0]
		if t >= e[3]:
			_sq.remove_at(k)
			continue
		if t < 0:
			continue
		var ddy: int = e[1]
		var ddx: int = e[2]
		if e[4] == 1 and t >= e[3] / 2:
			ddy -= signi(ddy)
			ddx -= signi(ddx)
		dy += ddy
		dx += ddx
	if key == &"walk" and not reduce and not bool(walk.get("bob", false)) and wn >= 8 and (frame == 1 or frame == 5):
		dy += 1
	dy = clampi(dy, -_sq_cap.x, _sq_cap.x)
	dx = clampi(dx, -_sq_cap.y, _sq_cap.y)
	# --- 기울기(스텝 스큐, 회전 금지) ---
	var cur_atl: Dictionary = _atl[_cur_key]
	var hinge: int = int(cur_atl["hinge_y"])
	var span: int = maxi(1, hinge - int(cur_atl["top_y"]))
	var target_deg: float = 0.0
	if _moving and not reduce:
		target_deg = _tilt_deg * clampf(vel.x / _base_speed, -1.0, 1.0)
	_tilt = lerpf(_tilt, target_deg, 1.0 - exp(-_tilt_rate * adt))
	var cont: float = clampf(float(span) * tan(deg_to_rad(_tilt)), -float(_tilt_max), float(_tilt_max))
	if absf(cont - float(_tilt_px)) > 0.5 + _tilt_hys:
		_tilt_px = int(K.rnd(cont))
	var shear: float = float(_tilt_px) / float(span)
	if _flip:
		shear = -shear                           # 셰이더는 텍스처 공간
	# --- 반동(렌더 전용, 정수) ---
	var off: Vector2 = Vector2.ZERO
	var re: int = tick - _recoil_tick
	if _recoil_px > 0 and re >= 0:
		var s0: int = _recoil_steps[0] if _recoil_steps.size() > 0 else 2
		var s1: int = _recoil_steps[1] if _recoil_steps.size() > 1 else 3
		var mag: int = 0
		if re < s0:
			mag = _recoil_px
		elif re < s0 + s1:
			mag = _recoil_px - 1
		else:
			_recoil_px = 0
		if reduce:
			mag = mini(mag, 1)
		off = _recoil_dir * float(mag)
	_set_shader(dy, dx, shear, 0)
	_place(off)
	# --- 무적 점멸: 보임 6틱 / 숨김 3틱(반투명 금지). 숨김 틱은 몸 대신 먹 실루엣 + 금 테(design/18 §1.4). 그림자는 항상 보임 ---
	var hidden: bool = false
	if hit.iframe_left > 0.0:
		var bt: int = (tick - _blink_tick) % maxi(1, _blink_on + _blink_off)
		hidden = bt >= _blink_on
	sprite.visible = not hidden
	_sync_rim(hidden, tick)
	if held != null:
		held.sync(hidden)


func _enter_idle(tick: int) -> void:
	_idle_phase = 0.0
	_push_sq(tick, _sq_land, true)              # 착지 스쿼시


func _push_sq(tick: int, def: PackedInt32Array, two_stage: bool) -> void:
	if def.size() < 3 or Juice.reduce_motion:
		return
	_sq.append(PackedInt32Array([tick, def[0], def[1], def[2], 1 if two_stage else 0]))
	if _sq.size() > 6:
		_sq.remove_at(0)


func _apply_cell(key: StringName, row: int, frame: int) -> void:
	var at: Dictionary = _atl[key]
	if key != _cur_key:
		_cur_key = key
		sprite.texture = at["texture"]
		var piv: Vector2i = at["pivot"]
		var cell: Vector2i = at["cell"]
		sprite.offset = Vector2(-piv.x, -piv.y)
		_set_p(&"cell_size", Vector2(cell))
		_set_p(&"pivot", Vector2(piv))
		_set_p(&"hinge_y", float(at["hinge_y"]))
	var c: Vector2i = at["cell"]
	cell_anim = String(at.get("anim", key))
	cell_frame = clampi(frame, 0, int(at["cols"]) - 1)
	var origin: Vector2 = Vector2(clampi(frame, 0, int(at["cols"]) - 1) * c.x, clampi(row, 0, 2) * c.y)
	sprite.region_rect = Rect2(origin, Vector2(c))
	_set_p(&"cell_origin", origin)


func _set_shader(dy: int, dx: int, shear: float, flash_idx: int) -> void:
	_set_p(&"sq_dy", float(dy))
	_set_p(&"sq_dx", float(dx))
	_set_p(&"shear", shear)
	_set_p(&"shear_max", float(_tilt_max))
	_mat.set_shader_parameter("flash_idx", flash_idx)


## 정수 월드 좌표에 스프라이트·그림자 배치(노드 원점은 시뮬 좌표라 차이만큼 로컬 이동).
func _place(off: Vector2) -> void:
	var local: Vector2 = render_pos - global_position
	sprite.position = local + off
	shadow.position = local


# ─── 이벤트(연출 전용) ─────────────────────────────────────────────────

func _on_damaged(_amount: float, _src: StringName, _hp: float, _hp_max: float) -> void:
	var tick: int = Game.anim_tick_cur
	_hurt_tick = tick
	_blink_tick = tick
	_push_sq(tick, _sq_hurt, true)


func _on_weapon_fired(weapon_id: StringName, _slot: int, _pos: Vector2) -> void:
	if held != null:
		held.note_fired(weapon_id)
	var em0: EnemyManager = Game.enemies as EnemyManager
	if em0 != null:
		var i0: int = em0.nearest(global_position, 16.0 * K.UNIT_PX)
		if i0 >= 0:
			var d0: Vector2 = em0.pos_of(i0) - global_position
			if d0.length_squared() > 1.0:
				_aim = d0.normalized()
	var px_: int = int(_recoil_map.get(weapon_id, 0))
	var wd: Dictionary = Data.weapon(String(weapon_id))
	var fe: Variant = wd.get("feel", null)
	if fe is Dictionary and (fe as Dictionary).has("recoil_px"):
		px_ = int(fe["recoil_px"])
	if px_ <= 0:
		return
	var tick: int = Game.anim_tick_cur
	var remaining: int = _recoil_px if tick - _recoil_tick < _recoil_steps[0] else maxi(0, _recoil_px - 1)
	if px_ < remaining:
		return                                    # 같은 박 다중 발사: 합이 아니라 최대값
	var aim: Vector2 = last_move_dir
	var em: EnemyManager = Game.enemies as EnemyManager
	if em != null:
		var i: int = em.nearest(global_position, 16.0 * K.UNIT_PX)
		if i >= 0:
			aim = em.pos_of(i) - global_position
	_recoil_dir = -K.dir8(aim)
	_recoil_px = px_
	_recoil_tick = tick
