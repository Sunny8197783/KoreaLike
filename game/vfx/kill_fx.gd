class_name KillFx
extends Node2D
## 처치 순간 연출(design/19 §5.2 I — 렌더 전용, 난수 없음). 소유: kill_ability_fx. HitFeedback 이 VfxPlayer 자식으로 붙인다(z5 절대).
##   퇴치 파열 틱(toechi_seq 2+4 = 틱 6)에: 한지 십자(가로·세로 11px, 정예·치명 15px) 2틱 + 터지는 고리 2px(바깥 jk-hi·안 한지)
##   → (vfx_toechi_burst 는 HitFeedback 이 VfxPlayer 로, 정예·다중·치명은 첫 1f 가산 겹침) → 주 조각 4개 0.22초
##   → 넋 빠짐 0.35초: vfx_neok_pickup 한지 심 + jk-hi 테 2색(테 = 같은 그림을 jk-hi 로 물들여 상하좌우 1px), 12px 떠올랐다가 무당 쪽으로 빨려 듦.
##   군중이면 넋은 5px 넋불(한지 심 1px + jk-hi 십자 테)로 작게. 무당 몸 상자(±16, −42~+6) 둘레 SOUL_KILL_PX 안에 닿으면 그 자리에서 즉시 소멸
##   — 견본 19:30 에서 넋들이 무당 머리 위 같은 길로 모여 붉은 세로 막대('피 기둥')로 보였다(검토 11-26).
##   경로 흔들기는 적 핸들 해시(게임 난수 금지, design/18 §6). ④여운(조각·넋)의 α 에 Juice.my_fx_alpha(설정 '내 무기 효과')를 곱한다.
## 예산(design/19 §5.1): 파열(십자+조각) 동시 8(군중도 8 — 검토 11-26) · 넋 빠짐 0.25초 창 6(군중 2).

const BURST_CAP: int = 16
const SOUL_CAP: int = 12
const SOUL_LIFE: float = 0.35
const SHARD_LIFE: float = 0.22
const CROSS_LIFE: float = 2.5 / 60.0        # 십자 2틱(1.5틱은 60fps 캡처에서 거의 안 잡혔다)
const RING_LIFE: float = 0.12               # 터지는 고리
const SOUL_KILL_PX: float = 6.0             # 몸 상자 둘레 이만큼 안이면 소멸
const HANJI_CORE: Color = Color(0.86, 0.84, 0.80, 1.0)    # 한지 그림 × 이 값 ≈ L 0.74(P 층 근처, 순백 아님)
const JKHI_TINT: Color = Color(0.98, 0.436, 0.41, 1.0)   # 한지 그림 × 이 값 ≈ jk-hi #e4604f
const COL_HANJI: Color = Color(233.0 / 255.0, 220.0 / 255.0, 192.0 / 255.0)
const COL_JKHI: Color = Color(228.0 / 255.0, 96.0 / 255.0, 79.0 / 255.0)
const COL_JK: Color = Color(200.0 / 255.0, 50.0 / 255.0, 45.0 / 255.0)
const COL_INK: Color = Color(0.0549, 0.0431, 0.0863)

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
var stat_soul_absorbed: int = 0
var _crowd: bool = false


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
	_crowd = crowd
	var live: int = 0
	var free: int = -1
	for k in BURST_CAP:
		if _b_t[k] >= 0.0 and now - _b_t[k] < SHARD_LIFE:
			live += 1
		elif free < 0:
			free = k
	var cap: int = 8   # 처치 파열은 군중에서도 같은 예산(검토 11-26 — 무리 감쇠가 처치 연출을 지웠다). 군중 예산은 넋 빠짐에서 맞춘다
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
	if _win_souls >= (2 if crowd else 6) and not big:
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
	var my_a: float = clampf(float(Juice.my_fx_alpha), 0.0, 1.0)
	# 파열: 0~2틱 한지 십자 11px(정예·치명 15px, 먹 받침) + 터지는 고리 → 조각 4개(군중 3) 0.22초
	for k in BURST_CAP:
		if _b_t[k] < 0.0:
			continue
		var age: float = now - _b_t[k]
		if age >= SHARD_LIFE:
			_b_t[k] = -1.0
			continue
		var c: Vector2 = K.rndv(_b_pos[k] + Vector2(0, -12))
		var big: bool = _b_big[k] != 0
		if age < CROSS_LIFE:
			var h: float = 7.0 if big else 5.0
			draw_rect(Rect2(c + Vector2(-h - 1, -1), Vector2(h * 2 + 3, 3)), COL_INK)
			draw_rect(Rect2(c + Vector2(-1, -h - 1), Vector2(3, h * 2 + 3)), COL_INK)
			draw_rect(Rect2(c + Vector2(-h, 0), Vector2(h * 2 + 1, 1)), COL_HANJI)
			draw_rect(Rect2(c + Vector2(0, -h), Vector2(1, h * 2 + 1)), COL_HANJI)
			if big:
				draw_rect(Rect2(c + Vector2(-1, -1), Vector2(3, 3)), COL_HANJI)
		if age < RING_LIFE:
			# 터지는 고리: 반경 4 → 11(정예 15), 2px(바깥 jk-hi + 안 한지 1px), 계단 감쇠 — '터졌다'가 일반 처치에서도 읽히게
			var rk: float = age / RING_LIFE
			var rr: float = roundf(4.0 + ((11.0 if big else 8.0) - 4.0) * (1.0 - (1.0 - rk) * (1.0 - rk)))
			var ra: float = 1.0 if rk < 0.5 else 0.5
			draw_arc(c, rr + 0.5, 0.0, TAU, 16, Color(COL_JKHI, ra), 1.0, false)
			if rk < 0.5:
				draw_arc(c, rr - 0.5, 0.0, TAU, 14, Color(COL_HANJI, ra), 1.0, false)
		var kt: float = age / SHARD_LIFE
		var e: float = 1.0 - (1.0 - kt) * (1.0 - kt)
		var sa: float = (1.0 - kt) * my_a
		if sa <= 0.02:
			continue
		var ns: int = 3 if _crowd and not big else 4
		for m in ns:
			var ang: float = TAU * (float(m) / float(ns) + _h(_b_seed[k], m) * 0.2) + 0.4
			var q: Vector2 = K.rndv(c + Vector2.from_angle(ang) * (4.0 + (14.0 if big else 10.0) * e) + Vector2(0, 7.0 * kt * kt))
			draw_rect(Rect2(q - Vector2(1, 1), Vector2(4, 3) if kt < 0.5 else Vector2(3, 3)), Color(COL_INK, sa))
			draw_rect(Rect2(q, Vector2(2, 1) if kt < 0.5 else Vector2.ONE), Color(COL_HANJI if kt < 0.15 else (COL_JKHI if kt < 0.5 else COL_JK), sa))
	# 넋 빠짐: 12px 떠오름(0.1초) → 무당 쪽으로 빨려 듦(ease-in) → 0.35초 또는 몸 상자 둘레에 닿으면 소멸
	var regions: Array = _soul_fx.get("regions", [])
	var tex: Texture2D = _soul_fx.get("texture") as Texture2D
	var has_tex: bool = tex != null and not regions.is_empty()
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
		var q2: Vector2 = K.rndv(p)
		# 무당 몸 상자(±16, −42~+6) + SOUL_KILL_PX 안: 즉시 소멸(슬롯 비움) — 몸 위 같은 길에 넋이 쌓여 기둥이 되지 않게
		if pl != null and age2 >= 0.1:
			var rel: Vector2 = q2 - pl.render_pos
			if absf(rel.x) < 16.0 + SOUL_KILL_PX and rel.y > -42.0 - SOUL_KILL_PX and rel.y < 6.0 + SOUL_KILL_PX:
				_s_t[k2] = -1.0
				stat_soul_absorbed += 1
				continue
		var a: float = (1.0 if age2 < 0.22 else clampf((SOUL_LIFE - age2) / 0.13, 0.0, 1.0)) * my_a
		if a <= 0.02:
			continue
		if _crowd or not has_tex:
			# 군중: 5px 넋불(한지 심 1px + jk-hi 십자 테) — 크기↓
			draw_rect(Rect2(q2 + Vector2(-1, -2), Vector2(3, 5)), Color(COL_JKHI, a))
			draw_rect(Rect2(q2 + Vector2(-2, -1), Vector2(5, 3)), Color(COL_JKHI, a))
			draw_rect(Rect2(q2 + Vector2(-1, -1), Vector2(3, 3)), Color(COL_HANJI * HANJI_CORE, a))
			continue
		var fi: int = int(age2 * 16.0) % regions.size()
		var r: Rect2 = regions[fi]
		var o: Vector2 = q2 - K.rndv(r.size * 0.5)
		# 2색: jk-hi 테(같은 그림 상하좌우 1px) → 한지 심
		var tc: Color = Color(JKHI_TINT, a)
		draw_texture_rect_region(tex, Rect2(o + Vector2(-1, 0), r.size), r, tc)
		draw_texture_rect_region(tex, Rect2(o + Vector2(1, 0), r.size), r, tc)
		draw_texture_rect_region(tex, Rect2(o + Vector2(0, -1), r.size), r, tc)
		draw_texture_rect_region(tex, Rect2(o + Vector2(0, 1), r.size), r, tc)
		draw_texture_rect_region(tex, Rect2(o, r.size), r, Color(HANJI_CORE, a))
