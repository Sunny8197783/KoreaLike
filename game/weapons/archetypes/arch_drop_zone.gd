class_name ArchDropZone
extends WeaponBase
## 원형 drop_zone: 지점 장판(쑥물 투척·소금 결계·오방기·길베 천) + 진화·결합. 소유: combat.
## params: place(dense|self|follow|flag|obangjin|line|trail_only), push(소금 밀어내기)
##   sammul(삼물씻김: 맑은물·쑥물·향물 3연 장판) · gilbe_trail(베가르기·작두다리: 길베 트레일 자체가 0.5초마다 백 피해) · bursts(부정가심)
## 레벨 필드: dmg, amt, area(u: 반경 또는 길이), width(u: line), dur(s), tick(s), slow, push, buff, trail_dmg, trail_width
## 같은 무구의 장판은 한 대상에 겹치지 않는다(weapons.json globals.hit_lockout) — 무구 단위 재타격 간격으로 보장.
## 연출: 선딜 = 투척 포물선(쑥물)/예고 원, 타격 = 착지 시트, 장판은 자체 수명(바닥 층 z −2).

const MAX_ZONES: int = 24
const COLORS: Array[StringName] = [&"cheong", &"jeok", &"hwang", &"baek", &"heuk"]
var zx: PackedFloat32Array = PackedFloat32Array()
var zy: PackedFloat32Array = PackedFloat32Array()
var zdx: PackedFloat32Array = PackedFloat32Array()
var zdy: PackedFloat32Array = PackedFloat32Array()
var zlife: PackedFloat32Array = PackedFloat32Array()     # 남은 수명(s), <= 0 비활성
var zdur: PackedFloat32Array = PackedFloat32Array()
var zland: PackedFloat32Array = PackedFloat32Array()     # 착지까지(s) — 삼물 순차 배치
var zr: PackedFloat32Array = PackedFloat32Array()        # 반경 px(동심 결계는 다름)
var zkind: PackedInt32Array = PackedInt32Array()         # flag 색 0..4 / 삼물 0 맑은물 1 쑥물 2 향물
var ztick: PackedInt32Array = PackedInt32Array()         # 생성 game_tick
var _wu_target: Vector2 = Vector2.INF
var _trail_t: float = 0.0
var _trail_flash: int = -100000
var _purge_t: float = 0.0


func _on_setup() -> void:
	for arr: String in ["zx", "zy", "zdx", "zdy", "zlife", "zdur", "zland", "zr"]:
		var a: PackedFloat32Array = PackedFloat32Array()
		a.resize(MAX_ZONES)
		set(arr, a)
	zlife.fill(0.0)
	zkind.resize(MAX_ZONES)
	ztick.resize(MAX_ZONES)
	if _place() == "follow":
		_spawn_zone(player_pos(), Vector2.RIGHT, 1e9, _radius(), 0, 0.0)


func _place() -> String:
	return String(params.get("place", "self"))


func uses_fire() -> bool:
	return _place() != "follow" and _place() != "trail_only"


func _radius() -> float:
	return s("area", 1.5) * K.UNIT_PX * area_mult()


func _is_line() -> bool:
	return _place() == "line"


func _spawn_zone(p: Vector2, d: Vector2, dur: float, r: float, kind_v: int, land: float) -> int:
	var z: int = _free_zone()
	zx[z] = p.x
	zy[z] = p.y
	zdx[z] = d.x
	zdy[z] = d.y
	zlife[z] = dur + land
	zdur[z] = dur
	zland[z] = land
	zr[z] = r
	zkind[z] = kind_v
	ztick[z] = Game.game_tick + int(land * K.TICK_HZ)
	return z


func _free_zone() -> int:
	var best: int = 0
	for z in MAX_ZONES:
		if zlife[z] <= 0.0:
			return z
		if zlife[z] < zlife[best]:
			best = z
	return best


## 쑥물 조준: 반경 6u 안 표본 8점 중 적 밀도 최대(풀릴 기색 가중 ×2).
func _dense_point(o: Vector2) -> Vector2:
	var em: EnemyManager = enemies()
	if em == null:
		return o + move_dir() * 3.0 * K.UNIT_PX
	var n: int = em.query_circle(o, 6.0 * K.UNIT_PX, _q)
	if n == 0:
		return o + move_dir() * 3.0 * K.UNIT_PX
	var best: Vector2 = em.pos_of(_q[0])
	var best_s: float = -1.0
	var step: int = maxi(1, n / 8)
	var r2: float = _radius() * _radius()
	for k in range(0, n, step):
		var c: Vector2 = em.pos_of(_q[k])
		var sc: float = 0.0
		for j in n:
			var i: int = _q[j]
			if em.pos_of(i).distance_squared_to(c) <= r2:
				sc += 2.0 if (em.flags[i] & EnemyManager.F_PULLIL) != 0 else 1.0
		if sc > best_s:
			best_s = sc
			best = c
	return best


func _windup_start() -> void:
	if _place() == "dense":
		_wu_target = _dense_point(player_pos())


func fire() -> void:
	var o: Vector2 = player_pos()
	var dur: float = maxf(s("dur", 3.0), 0.2) * dur_mult()
	match _place():
		"dense":
			var n: int = clampi(int(s("amt", 1)) + sinjang(), 1, int(limit("amt_cap", 6)))
			for k in n:
				var p: Vector2 = _wu_target if (k == 0 and _wu_target != Vector2.INF) else _dense_point(o)
				if k > 0:
					p += Vector2.from_angle(TAU * float(k) / float(n)) * 1.5 * K.UNIT_PX
				if bool(params.get("sammul", false)):
					var d: Vector2 = (p - o).normalized() if p.distance_squared_to(o) > 1.0 else move_dir()
					for j in 3:
						_spawn_zone(p - d * 1.5 * K.UNIT_PX * float(2 - j), d, dur, _radius(), j, 0.3 * float(j))
				else:
					_spawn_zone(p, Vector2.RIGHT, dur, _radius(), 0, 0.0)
				play_fx(&"vfx_sogeum_purify_pop", p)
			_wu_target = Vector2.INF
		"self":
			_spawn_zone(o, Vector2.RIGHT, dur, _radius(), 0, 0.0)
			if s("purge", 0.0) > 0.0:
				_purge(o, _radius(), int(s("purge_cap", 20.0)))
			for k2 in mini(sinjang(), int(limit("amt_cap", 2))):
				_spawn_zone(o, Vector2.RIGHT, dur, _radius() * pow(0.6, float(k2 + 1)), 0, 0.0)
		"flag":
			var nf: int = clampi(int(s("amt", 1)) + sinjang(), 1, 5)
			var used: int = 0
			for k3 in nf:
				var ci: int = Rng.int_s(&"combat", 0, 4)
				while (used & (1 << ci)) != 0:
					ci = (ci + 1) % 5
				used |= 1 << ci
				var p2: Vector2 = o
				if not Rng.chance(&"combat", 0.5):
					p2 += Vector2.from_angle(Rng.range_s(&"combat", 0.0, TAU)) * Rng.range_s(&"combat", 0.5, 3.0) * K.UNIT_PX
				_spawn_zone(p2, Vector2.RIGHT, dur, _radius(), ci, 0.0)
		"obangjin":
			_spawn_zone(o, Vector2.RIGHT, dur, _radius(), 2, 0.0)
			var em: EnemyManager = enemies()
			if em != null:
				var n2: int = em.query_circle(o, _radius(), _q)
				for k4 in n2:
					apply_status(_q[k4], &"st_gyeongjik", Beat.beat_len_sec() * s("stun_beats", 1.0))
			Juice.add_trauma(0.15)
		"line":
			var base: Vector2 = move_dir()
			var nl: int = maxi(1, int(s("amt", 1)))
			_spawn_zone(o, base, dur, _radius(), 0, 0.0)
			if nl >= 2:
				_spawn_zone(o, -base, dur, _radius() * 0.7, 0, 0.0)   # 뒤 천은 ×0.7 — 대칭 十·X 자를 깬다
			for k5 in mini(sinjang(), int(limit("amt_cap", 4))):
				var sgn: float = 1.0 if k5 % 2 == 0 else -1.0
				_spawn_zone(o, base.rotated(deg_to_rad(30.0 * float(k5 / 2 + 1)) * sgn), dur, _radius(), 0, 0.0)


func tick(dt: float) -> void:
	var em: EnemyManager = enemies()
	var w: float = maxf(s("width", 0.8), 0.4) * K.UNIT_PX * sqrt(area_mult())
	var iv: float = maxf(s("tick", 0.5), 0.1)
	var push: float = s("push", 0.0) if bool(params.get("push", false)) else 0.0
	var line: bool = _is_line()
	var pp: Vector2 = player_pos()
	var buf_on: int = 0
	var follow: bool = _place() == "follow"
	for z in MAX_ZONES:
		if zlife[z] <= 0.0:
			continue
		zlife[z] -= dt
		if follow:
			zx[z] = pp.x
			zy[z] = pp.y
			zr[z] = _radius()
		if zland[z] > 0.0:
			zland[z] -= dt
			if zland[z] <= 0.0:
				play_fx(&"vfx_sogeum_purify_pop", Vector2(zx[z], zy[z]))
			continue
		if em == null:
			continue
		var c: Vector2 = Vector2(zx[z], zy[z])
		var d: Vector2 = Vector2(zdx[z], zdy[z])
		var r: float = zr[z]
		var center: Vector2 = (c + d * r * 0.5) if line else c
		var qr: float = (r * 0.5 + w) if line else r
		var kind_v: int = zkind[z]
		var place: String = _place()
		# 플레이어 쪽 효과(오방 버프 · 맑은물 회복)
		if c.distance_squared_to(pp) <= r * r and not line:
			if place == "flag" and kind_v != 4:
				buf_on |= 1 << kind_v
			elif place == "obangjin":
				buf_on |= 15
			elif bool(params.get("sammul", false)) and kind_v == 0 and Game.player != null:
				(Game.player as Player).hit.heal(Game.hp_max * s("malgeun_heal", 0.005) * dt)
		var n: int = em.query_circle(center, qr, _q)
		var slow: float = s("slow", 0.0)
		if place == "flag" and kind_v == 4:
			slow = 0.25 * s("buff", 1.0)
		elif bool(params.get("sammul", false)):
			slow = s("ssuk_slow", 0.3) if kind_v == 1 else 0.0
		var mult: float = 1.0
		if bool(params.get("sammul", false)) and kind_v == 2:
			var puri: float = minf(Game.stat(&"stat_puri", 3.0), 6.0)
			mult = (puri + s("hyang_puri", 1.0)) / puri      # 향물: 풀이 +1.0(백 피해는 풀릴 기색에 ×풀이)
		for k in n:
			var i: int = _q[k]
			if (em.flags[i] & EnemyManager.F_DYING) != 0:
				continue
			if line:
				var rel: Vector2 = em.pos_of(i) - c
				var along: float = rel.dot(d)
				if along < 0.0 or along > r or absf(rel.cross(d)) > w * 0.5 + em.radius[i]:
					continue
			if slow > 0.0:
				apply_status(i, &"st_dunhwa", iv + 0.1, slow)
			if can_hit(i, iv):
				var m2: float = mult if (em.flags[i] & EnemyManager.F_PULLIL) != 0 else 1.0
				deal(i, s("dmg", 2.0), (em.pos_of(i) - c).normalized(), push, m2, F_NO_SFX if follow else 0)
	if _place() == "flag" or _place() == "obangjin":
		var wm: WeaponManager = mgr as WeaponManager
		var b: float = s("buff", 1.0)
		for ci in 4:
			wm.set_buff(COLORS[ci], b if (buf_on & (1 << ci)) != 0 else 0.0)
	if bool(params.get("bursts", false)):
		# 부정가심: 결계 둘레 purge_r 안 살 알갱이를 초당 purge_rate 개 정화, 정화할 때마다 백 폭발
		_purge_t -= dt
		if _purge_t <= 0.0:
			var hs: Object = _haewon_sys()
			var has_api: bool = hs != null and hs.has_method(&"cleanse_circle")
			_purge_t = (1.0 / maxf(0.5, s("purge_rate", 4.0))) if has_api else 1.5
			var pr: float = s("purge_r", 5.0) * K.UNIT_PX
			if (not has_api or _purge(pp, pr, 1) > 0) and em != null:
				var t: int = find_target(pp, pr)
				if t >= 0:
					schedule_strike(em.pos_of(t), 0.1, s("burst_r", 1.2) * K.UNIT_PX * area_mult(), s("burst_dmg", 20.0), 0.0, fx_name("fx_blast"))
	if bool(params.get("gilbe_trail", false)):
		_trail_t -= dt
		if _trail_t <= 0.0:
			_trail_t = 0.5
			_trail_damage()


func _haewon_sys() -> Object:
	var rr: Run = Game.run_root as Run
	return rr.haewon if rr != null else null


## 소금 정화: 원 안 살 알갱이 제거(개당 살기 −0.02, 01 캐논 3.2.6). 반환: 제거 수.
## TODO(haewon): HaewonSystem.cleanse_circle(pos: Vector2, r_px: float, max_n: int) -> int 공개 API — 생기면 자동으로 쓴다.
func _purge(c: Vector2, r_px: float, max_n: int) -> int:
	var hs: Object = _haewon_sys()
	if hs == null or not hs.has_method(&"cleanse_circle"):
		return 0
	return int(hs.call(&"cleanse_circle", c, r_px, max_n))


## 길베 트레일 자체 피해(베가르기·작두다리): 4초 궤적을 0.5u 간격으로 표본, 폭 trail_width.
func _trail_damage() -> void:
	var rr: Run = Game.run_root as Run
	var em: EnemyManager = enemies()
	if rr == null or rr.gilbe == null or em == null:
		return
	var tr: GilbeTrail = rr.gilbe
	var cnt: int = tr.count
	if cnt < 2:
		return
	var r: float = s("trail_width", 0.8) * 0.5 * K.UNIT_PX
	var last: Vector2 = Vector2.INF
	for k in cnt:
		var p: Vector2 = tr.point(k)
		if last != Vector2.INF and p.distance_squared_to(last) < 256.0:
			continue
		last = p
		var n: int = em.query_circle(p, r, _q)
		for j in n:
			var i: int = _q[j]
			if (em.flags[i] & EnemyManager.F_DYING) == 0 and can_hit(i, 0.45):
				deal(i, s("trail_dmg", 10.0), Vector2.ZERO, 0.0, 1.0, F_NO_SFX)
	_trail_flash = Game.game_tick


# ─── 연출 ────────────────────────────────────────────────────────────

const FLAG_FX: Array[StringName] = [&"vfx_obanggi_flag_cheong", &"vfx_obanggi_flag_jeok", &"vfx_obanggi_flag_hwang", &"vfx_obanggi_flag_baek", &"vfx_obanggi_flag_heuk"]
const OBANG_OFFS: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1), Vector2(0, 0), Vector2(-1, 0), Vector2(0, -1)]   # 청 동 · 적 남 · 황 중앙 · 백 서 · 흑 북
const PILLAR_EAST_TINT: Color = Color(0.62, 1.0, 0.7, 1.0)   # 청 기둥 × 이 값 → 청록(#3f8f86 계열)
const PILLAR_FX: Array[StringName] = [&"vfx_obangjin_pillar_cheong", &"vfx_obangjin_pillar_jeok", &"vfx_obangjin_pillar_hwang", &"vfx_obangjin_pillar_baek", &"vfx_obangjin_pillar_heuk"]


func draw_ground(ci: CanvasItem) -> void:
	var now: int = Game.anim_tick()
	var at: float = Game.anim_time()
	var place: String = _place()
	var rp: Vector2 = render_origin() - player_pos()
	# 길베 천: 화면에 온전히 그리는 띠는 가장 최근 2개(나머지는 1px 점선 판정선만)
	var full_a: int = -1
	var full_b: int = -1
	if place == "line":
		for z0 in MAX_ZONES:
			if zlife[z0] <= 0.0 or zland[z0] > 0.0:
				continue
			if full_a < 0 or ztick[z0] > ztick[full_a]:
				full_b = full_a
				full_a = z0
			elif full_b < 0 or ztick[z0] > ztick[full_b]:
				full_b = z0
	for z in MAX_ZONES:
		if zlife[z] <= 0.0 or zland[z] > 0.0:
			continue
		var age: float = float(now - ztick[z]) / K.TICK_HZ
		var c: Vector2 = Vector2(zx[z], zy[z]) + (rp if place == "follow" else Vector2.ZERO)
		# 소멸 예고(design/19 §5.2 C): 사라지기 0.3초 전부터 2f 간격 깜박
		var fading: bool = zlife[z] < 0.3 and (now / 2) % 2 == 0
		if fading and place != "line":
			continue
		# 생성 1f(0.1초): 바깥 테 2px 한지 실선 → 그 뒤 점선
		var born: bool = age < 0.1 and place != "line"
		if born:
			draw_ring(ci, c, zr[z], K.COL_HANJI, 2.0)   # ② 첫 프레임은 군중이어도 2px(design/19 §5.1, 검토 11-26 '무리 감쇠가 새 연출을 지운다')
		match place:
			"line":
				if z == full_a or z == full_b:
					_draw_cloth(ci, c, Vector2(zdx[z], zdy[z]), zr[z], age, zlife[z], zdur[z], z)
				else:
					_draw_dots(ci, c, Vector2(zdx[z], zdy[z]), 0.0, zr[z], K.COL_HANJI_DK)
			"flag", "obangjin":
				draw_sheet(ci, fx_name("fx_zone"), c, at, 0, Color.WHITE, true)
				if not born:
					draw_dotted_ring(ci, c, zr[z], K.COL_HANJI_DK, 2, at * 0.5)
			"dense":
				var fx: StringName = fx_name("fx_zone")
				var tint: Color = Color.WHITE
				if bool(params.get("sammul", false)):
					# 향물(2)은 물귀신 웅덩이(먹+청 검은 물·손 = 적 위험 시트)를 쓰면 내 장판이 위험으로 읽힌다(design/18 ③).
					# 쑥물 점선 시트를 황 점선으로 물들여 그린다(vfx_sammul_triple 의 셋째 원 = 황 점선과 같은 뜻).
					fx = &"vfx_mul_puddle_clear" if zkind[z] == 0 else &"vfx_ssukmul_pool"
					if zkind[z] == 2:
						tint = Color(3.6, 0.89, 0.2)   # #2f8c86 → #a97c1b, #55b8aa → 황 밝음
				draw_sheet(ci, fx, c, at + float(z) * 0.1, 0, tint, true)
				if not born:
					draw_dotted_ring(ci, c, zr[z], K.COL_HANJI_DK, 3, at)
			_:
				if age < 0.5:
					draw_sheet(ci, fx_name("fx_cast"), c, age)
				# 소금 결정 점묘 테
				var seg: int = clampi(int(zr[z] / 4.0), 12, 64)
				for k in seg:
					if (k + now / 6) % 3 != 0:
						var a: float = TAU * float(k) / float(seg)
						ci.draw_rect(Rect2(K.rndv(c + Vector2.from_angle(a) * zr[z]), Vector2(1, 1)), K.COL_HANJI)
	if bool(params.get("gilbe_trail", false)) and now - _trail_flash < 4:
		var rr: Run = Game.run_root as Run
		if rr != null and rr.gilbe != null:
			var tr: GilbeTrail = rr.gilbe
			for k2 in range(0, tr.count, 6):
				draw_sheet(ci, &"vfx_begareugi_shimmer", tr.point(k2) + Vector2(-16, 0), at + float(k2) * 0.05, 0, Color.WHITE, true)


const CLOTH_SEG: float = 16.0                          # 천 조각 길이(px): 접힘 음영·소멸 단위
const CLOTH_MAX_PX: float = 160.0                      # 그리는 천 길이 상한(5u) — 그 너머 판정은 1px 점선
const CLOTH_UNFURL_S: float = 0.25
const CLOTH_TEAR_S: float = 0.2                        # 펼친 뒤 먹 찢김선이 머리→꼬리로 나아가는 시간
const COL_HANJI_MID: Color = Color(210.0 / 255.0, 193.0 / 255.0, 156.0 / 255.0)   # #d2c19c (hj 2단) — 무명 결 교차
const FRAY: PackedInt32Array = [0, 2, 1, 3, 1, 0, 3, 2]  # 끝단 3px 톱니(줄마다 잘림 px)


## 길베 천 띠(정수 픽셀, 반투명 없음). 무명 결 = 1px 세로결 50%(줄 걸러 칠함 → 바닥 예고가 비친다) + 가장자리 어두운 단
## + 16px 조각마다 지그재그 접힘 음영 + 끝단 톱니. 0.25초 펼침 → 먹 찢김선이 진행하며 두 띠로 갈라짐(베가르기)
## → 수명 후반 30% 는 조각 단위로 점멸 소멸.
func _draw_cloth(ci: CanvasItem, c: Vector2, d: Vector2, ln: float, age: float, life: float, dur: float, zi: int) -> void:
	var u: float = clampf(age / CLOTH_UNFURL_S, 0.0, 1.0)
	u = 1.0 - (1.0 - u) * (1.0 - u)                       # ease-out
	var full_len: float = minf(ln, CLOTH_MAX_PX * minf(1.0, ln / maxf(1.0, _radius())))   # 뒤 천(×0.7)은 상한도 ×0.7
	var L: float = roundf(full_len * u)
	if L < 2.0:
		return
	# 주축 정렬 오프셋(평행 이동 사본 → 대각선도 결이 고르다)
	var off: Vector2 = Vector2(0, 1) if absf(d.x) >= absf(d.y) else Vector2(1, 0)
	var hw: int = clampi(int(maxf(s("width", 1.0), 0.4) * K.UNIT_PX * 0.25), 3, 11)   # 반폭(px)
	var tear_len: float = clampf((age - CLOTH_UNFURL_S) / CLOTH_TEAR_S, 0.0, 1.0) * L
	var split_k: float = clampf((age - CLOTH_UNFURL_S - CLOTH_TEAR_S) / 0.15, 0.0, 1.0)
	var fade_p: float = 0.0
	var tail: float = maxf(0.3 * dur, 0.15)
	if life < tail:
		fade_p = 1.0 - life / tail
	var nseg: int = int(ceilf(L / CLOTH_SEG))
	var c0: Vector2 = K.rndv(c)
	for sg in nseg:
		if fade_p > 0.0:
			var hsh: float = fposmod(sin(float(sg) * 12.9898 + float(zi) * 78.233) * 43758.5453, 1.0)
			if hsh < fade_p:
				continue
		var a0: float = float(sg) * CLOTH_SEG
		var a1: float = minf(a0 + CLOTH_SEG, L)
		var torn: bool = a0 < tear_len
		var gap: float = (1.0 + roundf(split_k)) if torn else 0.0
		for j in range(-hw, hw):
			var edge: bool = j == -hw or j == hw - 1 or (torn and (j == -1 or j == 0))
			if not edge and (j & 1) != 0:
				continue                                      # 50% 결: 홀수 줄은 비운다
			var s0: float = a0
			var s1: float = a1
			if sg == 0:
				s0 += float(FRAY[(j + 64 + 3) % 8])
			if a1 >= L:
				s1 -= float(FRAY[(j + 64) % 8])
			if s1 <= s0:
				continue
			var sh: float = float(j) + (-gap if j < 0 else gap)
			var col: Color = K.COL_HANJI_DK if edge else (K.COL_HANJI if (j & 3) == 0 else COL_HANJI_MID)
			ci.draw_line(c0 + K.rndv(d * s0) + off * sh, c0 + K.rndv(d * s1) + off * sh, col, -1.0)
		# 접힘 음영: 조각마다 한쪽 반폭 가운데에 8px 어두운 결(지그재그로 엇갈림, 비운 홀수 줄에 놓는다)
		if a1 - a0 >= 10.0:
			var fj: int = (hw / 2) | 1
			var fo: float = float(fj) if sg % 2 == 0 else float(-fj)
			fo += (-gap if fo < 0.0 else gap)
			ci.draw_line(c0 + K.rndv(d * (a0 + 4.0)) + off * fo, c0 + K.rndv(d * (a0 + 12.0)) + off * fo, K.COL_HANJI_DK, -1.0)
	# 먹 찢김선: 가운데를 따라 머리→꼬리
	if tear_len >= 1.0 and split_k < 1.0:
		ci.draw_line(c0 + K.rndv(d * 2.0), c0 + K.rndv(d * tear_len), K.COL_MEOK, -1.0)
	# 그리는 상한(5u) 너머의 실제 판정 길이는 1px 점선
	if ln > full_len + 4.0 and u >= 1.0 and fade_p <= 0.0:
		_draw_dots(ci, c, d, full_len + 4.0, ln, K.COL_HANJI_DK)


## 1px 점선(4px 간격) 판정선: 화면 상한을 넘은 천·오래된 천.
func _draw_dots(ci: CanvasItem, c: Vector2, d: Vector2, t_from: float, t_to: float, col: Color) -> void:
	var c0: Vector2 = K.rndv(c)
	var t: float = t_from
	while t <= t_to:
		ci.draw_rect(Rect2(c0 + K.rndv(d * t), Vector2(1, 1)), col)
		t += 4.0


func draw(ci: CanvasItem) -> void:
	var now: int = Game.anim_tick()
	var place: String = _place()
	var wp: float = windup_prog()
	if wp >= 0.0:
		draw_windup_hand(ci, move_dir())
		if place == "dense" and _wu_target != Vector2.INF:
			# 투척 포물선: 손 → 목표, 정점 높이 24px
			var h: Vector2 = hand_point((_wu_target - player_pos()).normalized())
			var t: float = wp
			var q: Vector2 = h.lerp(_wu_target + Vector2(0, -4), t) + Vector2(0, -24.0 * 4.0 * t * (1.0 - t))
			ci.draw_rect(Rect2(K.rndv(q) - Vector2(2, 2), Vector2(5, 4)), K.COL_HANJI_DK)
			ci.draw_rect(Rect2(K.rndv(q) - Vector2(1, 1), Vector2(3, 2)), K.COL_CHEONGNOK)
			if (now / 2) % 2 == 0:
				draw_dotted_ring(ci, _wu_target, _radius(), col_dk(), 2)
		elif place == "self" or place == "obangjin":
			if (now / 2) % 2 == 0:
				draw_ring(ci, render_origin(), _radius(), col_dk())
	# 서 있는 소품: 오방기 깃발 · 오방진 기둥
	var at: float = Game.anim_time()
	for z in MAX_ZONES:
		if zlife[z] <= 0.0 or zland[z] > 0.0:
			continue
		var c: Vector2 = Vector2(zx[z], zy[z])
		if zlife[z] < 0.3 and (now / 2) % 2 == 0:
			continue
		if place == "flag":
			if not draw_sheet(ci, FLAG_FX[zkind[z]], c, at + float(z) * 0.15, 0, Color.WHITE, true):
				draw_sheet(ci, fx_name("fx_prop"), c, at, 0, Color.WHITE, true)
		elif place == "obangjin":
			var age: float = float(now - ztick[z]) / K.TICK_HZ
			# 진이 무당 발밑에 서면(검토 11-26): 가운데 황 기둥은 무당 몸 한가운데를 세로로 가려 그리지 않고,
			# 남쪽 적 기둥은 무당 바로 아래 붉은 세로 막대('피 기둥')로 읽혀 첫 0.1초 뒤 α0.5 로 낮춘다.
			var on_pl: bool = c.distance_squared_to(render_origin()) < 24.0 * 24.0
			for k in 5:
				if k == 2 and on_pl:
					continue
				var pp: Vector2 = c + OBANG_OFFS[k] * zr[z]
				var t2: float = minf(age, sheet_len(PILLAR_FX[k]) - 0.01) if age < 1.0 else sheet_len(PILLAR_FX[k]) - 0.01
				var tn: Color = Color.WHITE
				if k == 0:
					tn = PILLAR_EAST_TINT          # 청은 적 탄 전용 — 용왕 청록 쪽으로(design/19 §5.2 F 와 같은 규칙)
				elif k == 1 and on_pl and age > 0.1:
					tn = Color(1, 1, 1, 0.5)
				draw_sheet(ci, PILLAR_FX[k], pp, maxf(t2, 0.0), 0, tn)
