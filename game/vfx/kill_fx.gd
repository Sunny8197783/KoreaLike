class_name KillFx
extends Node2D
## 처치 순간 연출(design/19 §5.2 I — 렌더 전용, 난수 없음). 소유: kill_ability_fx. HitFeedback 이 VfxPlayer 자식으로 붙인다(z5 절대).
##   퇴치 파열 틱(toechi_seq 2+4 = 틱 6)에: 한지 십자 9px 1f → (vfx_toechi_burst 는 HitFeedback 이 VfxPlayer 로)
##   → 주 조각 4개 0.15초 → 넋 빠짐 0.35초(vfx_neok_pickup 을 jk-hi 로 물들여 12px 떠올랐다가 무당 쪽으로 빨려 듦).
##   경로 흔들기는 적 핸들 해시(게임 난수 금지, design/18 §6).
## 예산(design/19 §5.1): 파열(십자+조각) 동시 8(군중 4) · 넋 빠짐 0.25초 창 6(군중 3).

const BURST_CAP: int = 16
const SOUL_CAP: int = 12
const SOUL_LIFE: float = 0.35
const SHARD_LIFE: float = 0.15
const COL_HANJI: Color = Color(233.0 / 255.0, 220.0 / 255.0, 192.0 / 255.0)
const COL_JKHI: Color = Color(228.0 / 255.0, 96.0 / 255.0, 79.0 / 255.0)
const COL_JK: Color = Color(200.0 / 255.0, 50.0 / 255.0, 45.0 / 255.0)
const COL_INK: Color = Color(0.0549, 0.0431, 0.0863)
const SOUL_TINT: Color = Color(1.0, 0.5, 0.42, 1.0)          # 한지 넋불 × 이 색 ≈ jk-hi

var _b_pos: PackedVector2Array = PackedVector2Array()
var _b_t: PackedFloat32Array = PackedFloat32Array()        # 시작 연출 시각(초), <0 비어 있음
var _b_big: PackedByteArray = PackedByteArray()
var _b_seed: PackedInt32Array = PackedInt32Array()
var _s_pos: PackedVector2Array = PackedVector2Array()
var _s_t: PackedFloat32Array = PackedFloat32Array()
var _s_seed: PackedInt32Array = PackedInt32Array()
var _win_t0: int = -1000
var _win_souls: int = 0
var _soul_fx: Dictionary = {}
var stat_bursts: int = 0
var stat_souls: int = 0
var stat_cut: int = 0


func _ready() -> void:
	z_as_relative = false
	z_index = 5
	_b_pos.resize(BURST_CAP)
	_b_t.resize(BURST_CAP)
	_b_t.fill(-1.0)
	_b_big.resize(BURST_CAP)
	_b_seed.resize(BURST_CAP)
	_s_pos.resize(SOUL_CAP)
	_s_t.resize(SOUL_CAP)
	_s_t.fill(-1.0)
	_s_seed.resize(SOUL_CAP)
	_soul_fx = VfxLib.get_fx(&"vfx_neok_pickup")


## 처치 한 건(퇴치 파열 틱). big = 정예 이상·치명(파열 scale 2 는 호출자가). seed = 적 핸들.
func burst(pos: Vector2, big: bool, seed: int, crowd: bool) -> void:
	var now: float = Game.anim_time()
	var live: int = 0
	var free: int = -1
	for k in BURST_CAP:
		if _b_t[k] >= 0.0 and now - _b_t[k] < SHARD_LIFE:
			live += 1
		elif free < 0:
			free = k
	var cap: int = 4 if crowd else 8
	if (live >= cap and not big) or free < 0:
		stat_cut += 1
	else:
		_b_pos[free] = pos
		_b_t[free] = now
		_b_big[free] = 1 if big else 0
		_b_seed[free] = seed
		stat_bursts += 1
	# 넋 빠짐: 0.25초 창 6(군중 3), 정예 이상은 예외
	if Game.anim_tick() - _win_t0 >= 15:
		_win_t0 = Game.anim_tick()
		_win_souls = 0
	if _win_souls >= (3 if crowd else 6) and not big:
		return
	var sf: int = -1
	var oldest: float = INF
	for k2 in SOUL_CAP:
		if _s_t[k2] < 0.0 or now - _s_t[k2] >= SOUL_LIFE:
			sf = k2
			break
		if _s_t[k2] < oldest:
			oldest = _s_t[k2]
			sf = k2
	_win_souls += 1
	_s_pos[sf] = pos
	_s_t[sf] = now
	_s_seed[sf] = seed
	stat_souls += 1


static func _h(seed: int, salt: int) -> float:
	var x: int = (seed * 2654435761 + salt * 40503) & 0x7fffffff
	x = ((x >> 13) ^ x) * 1274126177 & 0x7fffffff
	return float(x % 1000) / 1000.0


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var now: float = Game.anim_time()
	var pl: Player = Game.player as Player
	var tgt: Vector2 = (pl.render_pos + Vector2(0, -float(pl.cam_lift))) if pl != null else Vector2.ZERO
	# 파열: 0~1f 한지 십자 9px(정예·치명 13px) → 조각 4개(주·먹 테) 0.15초
	for k in BURST_CAP:
		if _b_t[k] < 0.0:
			continue
		var age: float = now - _b_t[k]
		if age >= SHARD_LIFE:
			_b_t[k] = -1.0
			continue
		var c: Vector2 = K.rndv(_b_pos[k] + Vector2(0, -12))
		var big: bool = _b_big[k] != 0
		if age < 1.5 / K.TICK_HZ:
			var h: float = 6.0 if big else 4.0
			draw_rect(Rect2(c + Vector2(-h - 1, -1), Vector2(h * 2 + 3, 3)), COL_INK)
			draw_rect(Rect2(c + Vector2(-1, -h - 1), Vector2(3, h * 2 + 3)), COL_INK)
			draw_rect(Rect2(c + Vector2(-h, 0), Vector2(h * 2 + 1, 1)), COL_HANJI)
			draw_rect(Rect2(c + Vector2(0, -h), Vector2(1, h * 2 + 1)), COL_HANJI)
		var kt: float = age / SHARD_LIFE
		var e: float = 1.0 - (1.0 - kt) * (1.0 - kt)
		for m in 4:
			var ang: float = TAU * (float(m) / 4.0 + _h(_b_seed[k], m) * 0.2) + 0.4
			var q: Vector2 = K.rndv(c + Vector2.from_angle(ang) * (3.0 + (12.0 if big else 9.0) * e) + Vector2(0, 6.0 * kt * kt))
			draw_rect(Rect2(q - Vector2(1, 1), Vector2(3, 3)), Color(COL_INK, 1.0 - kt))
			draw_rect(Rect2(q, Vector2(2, 1) if kt < 0.5 else Vector2.ONE), Color(COL_JKHI if kt < 0.4 else COL_JK, 1.0 - kt))
	# 넋 빠짐: 12px 떠오름(0.1초) → 무당 쪽으로 빨려 듦(ease-in) → 0.35초에 사라짐
	var regions: Array = _soul_fx.get("regions", [])
	var tex: Texture2D = _soul_fx.get("texture") as Texture2D
	for k2 in SOUL_CAP:
		if _s_t[k2] < 0.0:
			continue
		var age2: float = now - _s_t[k2]
		if age2 >= SOUL_LIFE or age2 < 0.0:
			if age2 >= SOUL_LIFE:
				_s_t[k2] = -1.0
			continue
		var start: Vector2 = _s_pos[k2] + Vector2(0, -12)
		var up: Vector2 = start + Vector2(0, -12)
		var p: Vector2
		if age2 < 0.1:
			p = start.lerp(up, age2 / 0.1)
		else:
			var u: float = (age2 - 0.1) / (SOUL_LIFE - 0.1)
			p = up.lerp(tgt, u * u)
			p.x += sin(u * 9.0 + _h(_s_seed[k2], 7) * TAU) * 3.0 * (1.0 - u)
		var a: float = 1.0 if age2 < 0.22 else clampf((SOUL_LIFE - age2) / 0.13, 0.0, 1.0)
		var q2: Vector2 = K.rndv(p)
		# 무당 몸 상자(±16, −42~+6) 안에서는 그리지 않는다 — 넋은 몸 테두리에 닿는 순간 '빨려 들어간' 것으로 끝(design/18 §1.4·§3 몸 상자 비움, 검토 11-26)
		if pl != null and absf(q2.x - pl.render_pos.x) < 16.0 and q2.y > pl.render_pos.y - 42.0 and q2.y < pl.render_pos.y + 6.0:
			continue
		if tex != null and not regions.is_empty():
			var fi: int = int(age2 * 16.0) % regions.size()
			var r: Rect2 = regions[fi]
			draw_texture_rect_region(tex, Rect2(q2 - K.rndv(r.size * 0.5), r.size), r, Color(SOUL_TINT, a))
		else:
			draw_rect(Rect2(q2 - Vector2(1, 2), Vector2(3, 4)), Color(COL_JKHI, a))
		# 꼬리 1점
		if age2 > 0.1:
			var tail: Vector2 = K.rndv(p.lerp(up, 0.25))
			draw_rect(Rect2(tail, Vector2.ONE), Color(COL_JKHI, a * 0.6))
