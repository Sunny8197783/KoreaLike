extends PlayerBot
## 파일럿 렌더 봇(tests/pilot_scene). 소유: core(리드).
## 게임 시각 기준 8초 주기 고정 시퀀스: 정지 → 원 → 지그재그 → 정지 → 원 → 정지.
## 적 회피를 섞지 않는다(전후 비교 렌더에서 같은 궤적이어야 한다).

const SEQ: Array = [
	[0.0, 0.5, &"stop"],
	[0.5, 2.7, &"circle"],
	[2.7, 4.5, &"zigzag"],
	[4.5, 5.7, &"stop"],
	[5.7, 7.3, &"circle"],
	[7.3, 8.0, &"stop"],
]
const PERIOD: float = 8.0
const CIRCLE_LAP_S: float = 2.2        # 한 바퀴 시간(128px/s 기준 반지름 약 45px)
const ZIG_HALF_S: float = 0.45         # 지그재그 꺾는 간격

var phase: StringName = &"stop"


func input(_p: Node2D) -> Vector2:
	var t: float = fmod(Game.time_sec(), PERIOD)
	var seg_t0: float = 0.0
	phase = &"stop"
	for e: Array in SEQ:
		if t >= float(e[0]) and t < float(e[1]):
			seg_t0 = float(e[0])
			phase = e[2]
			break
	var lt: float = t - seg_t0
	match phase:
		&"circle":
			var ang: float = lt * TAU / CIRCLE_LAP_S
			return Vector2(-sin(ang), cos(ang))
		&"zigzag":
			var up: bool = int(floor(lt / ZIG_HALF_S)) % 2 == 0
			return Vector2(1.0, -1.0 if up else 1.0).normalized()
	return Vector2.ZERO
