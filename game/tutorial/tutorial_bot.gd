class_name TutorialBot
extends PlayerBot
## --tutorial-autotest 봇(design/17 §7.6). 소유: tutorial_run. 단계별로만 PlayerBot 행동을 바꾼다. 시각은 게임 시각.

const RING_R_U: float = 2.2

var director: Node = null      # TutorialDirector
var _q2: PackedInt32Array = PackedInt32Array()
var _idle_s: float = 0.0       # --tutorial-bot-idle=<초>: 단계마다 처음 N초 가만히(도움 L1~L2 표지 캡처용)


func _init() -> void:
	super()
	_q2.resize(64)
	_idle_s = float(DebugTools.arg("tutorial-bot-idle", "0"))


func input(p: Node2D) -> Vector2:
	if director == null or not is_instance_valid(director):
		return super.input(p)
	var pos: Vector2 = p.global_position
	var step: StringName = director.get("step_id")
	if _idle_s > 0.0 and step != &"trial" and float(director.call("step_elapsed")) < _idle_s:
		return Vector2.ZERO
	match step:
		&"move":
			return Vector2.RIGHT if float(director.call("step_elapsed")) < _idle_s + 2.5 else Vector2.ZERO
		&"beat", &"cut":
			return _engage(pos, false)
		&"ring":
			var c: Vector2 = director.get("ring_center")
			return _orbit(pos, c, RING_R_U)
		&"white", &"yeongga":
			var t: Vector2 = _nearest_flag(pos, 12.0 * K.UNIT_PX, EnemyManager.F_PULLIL)
			if t == Vector2.INF:
				return _engage(pos, false)
			return (t - pos).normalized() if pos.distance_to(t) > 1.0 * K.UNIT_PX else Vector2.ZERO
		&"jeomji":
			var o: Vector2 = _nearest_orb(pos, 20.0 * K.UNIT_PX)
			return (o - pos).normalized() if o != Vector2.INF else Vector2.ZERO
		&"trial":
			return super.input(p)
		&"sal":
			return _engage(pos, true)
		_:
			return Vector2.ZERO


## 가장 가까운 적 쪽으로, 2u 안이면 그 둘레를 2u 로 돈다.
func _engage(pos: Vector2, any: bool) -> Vector2:
	var t: Vector2 = _nearest_flag(pos, 30.0 * K.UNIT_PX, 0 if any else 0)
	if t == Vector2.INF:
		return Vector2.ZERO
	if pos.distance_to(t) > 2.4 * K.UNIT_PX:
		return (t - pos).normalized()
	return _orbit(pos, t, 2.0)


func _nearest_flag(from: Vector2, max_r: float, need: int) -> Vector2:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return Vector2.INF
	var n: int = em.query_circle(from, max_r, _q2)
	var best: float = max_r * max_r
	var out: Vector2 = Vector2.INF
	for k in n:
		var i: int = _q2[k]
		if need != 0 and (em.flags[i] & need) == 0:
			continue
		var d2: float = from.distance_squared_to(em.pos_of(i))
		if d2 < best:
			best = d2
			out = em.pos_of(i)
	return out
