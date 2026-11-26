class_name GameCamera
extends Camera2D
## 런 카메라: 데드존·룩어헤드·평활(combat_core.camera) + Juice 흔들림. 소유: vfx (카메라 연출), 기본 추종은 core.
## 반올림 일원화(GAME_FEEL 2.6): 렌더 단계 R3 에서 run.gd 가 render() 를 부른다(자체 _process 없음).
##   P_f = 플레이어 보간 발 좌표 + (0, −cam_lift)      (카메라 대상점)
##   P_r = K.rndv(P_f)                                 (플레이어 스프라이트가 그려지는 정수 기준과 같다)
##   C   = 데드존·룩어헤드·지수 추종(float). 추종이 멈춘 프레임에는 C 를 정수에 고정
##   cam = P_r + K.rndv(C − P_f) + shake_int           → 정상 추종에서 주인공 화면 좌표가 고정(역전 0)

var target: Node2D = null
var _deadzone: float = 0.25 * 32.0
var _lookahead: float = 1.0 * 32.0
var _look_rate: float = 4.0
var _follow_rate: float = 10.0
var _max_offset: float = 1.6 * 32.0
var _look: Vector2 = Vector2.ZERO
var _pos: Vector2 = Vector2.ZERO
var _off_i: Vector2 = Vector2.ZERO          # round(C − P_f) 정수(경계 히스테리시스 0.15px — 추종 수렴 중 1px 깜빡임 방지)
const OFF_HYS: float = 0.15


func _ready() -> void:
	_deadzone = Data.num("combat_core", "camera.deadzone_u", 0.25) * K.UNIT_PX
	_lookahead = Data.num("combat_core", "camera.lookahead_u", 1.0) * K.UNIT_PX
	_look_rate = Data.num("combat_core", "camera.lookahead_rate", 4.0)
	_follow_rate = Data.num("combat_core", "camera.follow_rate", 10.0)
	_max_offset = Data.num("combat_core", "camera.max_offset_u", 1.6) * K.UNIT_PX
	process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	position_smoothing_enabled = false
	set_process(false)
	make_current()


## 플레이어 보간 대상점(P_f). 플레이어가 아니면 노드 위치.
func _target_point() -> Vector2:
	var p: Player = target as Player
	if p != null:
		return p.interp_pos + Vector2(0.0, -float(p.cam_lift))
	return target.global_position


## R3. alpha 는 보간 비율(플레이어가 이미 R2 에서 interp_pos 를 계산), delta 는 실시간(추종 평활).
func render(_alpha: float, delta: float) -> void:
	if target == null:
		return
	var pf: Vector2 = _target_point()
	var p: Player = target as Player
	var want_look: Vector2 = Vector2.ZERO
	if p != null and p.vel.length_squared() > 4.0:
		want_look = p.vel.normalized() * _lookahead
	var look_before: Vector2 = _look
	_look = _look.lerp(want_look, 1.0 - exp(-delta * _look_rate))
	var goal: Vector2 = pf + _look
	var diff: Vector2 = goal - _pos
	var moved: bool = false
	if diff.length() > _deadzone:
		_pos = _pos.lerp(goal - diff.normalized() * _deadzone, 1.0 - exp(-delta * _follow_rate))
		moved = true
	var off: Vector2 = _pos - pf
	if off.length() > _max_offset:
		_pos = pf + off.normalized() * _max_offset
		moved = true
	if not moved and look_before.distance_squared_to(_look) < 0.0001:
		_pos = K.rndv(_pos)                    # 카메라 정지: 내부값을 정수에 고정 → 월드 떨림 없음
	var pr: Vector2 = K.rndv(pf)
	var cont: Vector2 = _pos - pf
	if absf(cont.x - _off_i.x) > 0.5 + OFF_HYS:
		_off_i.x = K.rnd(cont.x)
	if absf(cont.y - _off_i.y) > 0.5 + OFF_HYS:
		_off_i.y = K.rnd(cont.y)
	if not moved:
		_off_i = K.rndv(cont)                  # 정지 중엔 C 가 정수 → pr + off = C 정확
	global_position = pr + _off_i + Juice.shake_offset()


func snap_to_target() -> void:
	if target != null:
		_pos = K.rndv(_target_point())
		_off_i = Vector2.ZERO
		global_position = _pos
