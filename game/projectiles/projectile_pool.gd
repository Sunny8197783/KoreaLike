class_name ProjectilePool
extends Node2D
## 투사체 풀(SoA, 노드 없음). 플레이어 탄 + 적 탄. 소유: combat (적 탄 패턴 생성은 enemies 가 spawn_enemy 호출).
## 상한: tech/perf_budgets caps.projectile_capacity(4096), weapons.json globals.projectile_pool(soft 600 / hard 768 플레이어 탄).
##
## 공개 API
##   spawn_player(weapon_slot, pos, vel, life_s, radius_px, dmg, pierce(-1 무한), returning, tag := 0, red := false, track := false) -> int
##       tag: 무구 안에서 투사체 종류 구분(0 본탄, 1.. 보조탄). red: 붉은 탄 — 풀릴 기색 일반 잡귀는 관통 소모 없이 지나간다
##       (weapons.json globals.red_vs_pullil_common: 판정은 하되 pierce_consumed=false, 대상당 1회).
##   spawn_enemy(pos, vel, life_s, radius_px, dmg, kind=&"prj_wonhon_tan") -> int
##   sim_step(dt)  틱 11 (이동 + 충돌 → WeaponManager.on_projectile_hit / Player.take_hit)
##   clear_all() / clear_slot(weapon_slot) / remap_slot(old, new)   (결합으로 슬롯이 줄 때 WeaponManager 가 호출)
##   alive_count, player_alive
## 콜백(WeaponManager): on_projectile_hit(wslot, enemy_slot, dmg, dir, tag, proj_index)
##                     on_projectile_end(wslot, tag, pos, vel, reason)   reason: 0 사거리 끝 · 1 손에 귀환 · 2 관통 소진
## 그리기(GAME_FEEL 3.3, 렌더 단계 R5 = render(alpha)): 보간 좌표를 K.rndv 로 정수화하고 lift(아군 16 / 적 10px)만큼 위에 그린다
##   (충돌은 지면 좌표끼리). 회전·비정수 배율 금지: proj_visual(tag) -> {fx, orient: none|spin|dir8|dir16, fps, scale(1|2), lift_px,
##   trail, tint}. spin = 사전 렌더 시트 프레임(age × fps), 단일 그림은 90° 단위 스냅(픽셀 정확 회전)만, 둥근 탄은 방향 없음.
## 적 탄(design/18 §1.1·1.3 위험 층): 자식 EnemyShots(z8 절대, 내 VFX z5·재 z6·무당 테 z7 위)에서 그린다.
##   탄마다 청 링(Juice.bullet_emphasis 1 = #5f93de 1px / 2 = #a9caf5 2px, 0 = 링 없음) + 먹 1px 테(±1px 4번) + 탄 그림.
##   원귀 탄(kind 이름에 'wongwi')은 링이 jk_dk #8c1f22. 링·테는 렌더 전용(시뮬 무관).

const CAPACITY: int = 4096
const HIT_MEM: int = 8
const F_ALIVE: int = 1
const F_ENEMY: int = 2
const F_RETURN: int = 4
const F_RETURNING: int = 8
const F_RED: int = 16
const F_TRACK: int = 32           # 틱마다 WeaponManager.on_projectile_step 호출(별 표식·꽃잎·거울 반사)
const END_RANGE: int = 0
const END_RETURNED: int = 1
const END_PIERCE: int = 2
const ETAG_WONGWI: int = 1        # 적 탄 ptag: 원귀 탄(링 jk_dk)
const ENEMY_Z: int = 8
const COL_INK: Color = Color(0.0549, 0.0431, 0.0863)          # 먹 #0e0b16
const COL_RING1: Color = Color(95.0 / 255.0, 147.0 / 255.0, 222.0 / 255.0)   # 청 #5f93de
const COL_RING2: Color = Color(169.0 / 255.0, 202.0 / 255.0, 245.0 / 255.0)  # 청 밝음 #a9caf5
const COL_JK_DK: Color = Color(140.0 / 255.0, 31.0 / 255.0, 34.0 / 255.0)    # jk_dk #8c1f22

var px: PackedFloat32Array
var py: PackedFloat32Array
var vx: PackedFloat32Array
var vy: PackedFloat32Array
var life: PackedFloat32Array
var life0: PackedFloat32Array
var rad: PackedFloat32Array
var dmg: PackedFloat32Array
var born: PackedFloat32Array
var ppx: PackedFloat32Array          # 보간용 직전 틱 좌표
var ppy: PackedFloat32Array
var pdir: PackedByteArray            # 90° 스냅 방향(0 E,1 S,2 W,3 N) — 경계 히스테리시스용
var pierce: PackedInt32Array
var wslot: PackedInt32Array
var flags: PackedInt32Array
var ptag: PackedInt32Array
var hit_mem: PackedInt32Array        # CAPACITY * HIT_MEM, 적 핸들
var hit_head: PackedByteArray
var alive_count: int = 0
var player_alive: int = 0
var _free: PackedInt32Array
var _free_n: int = 0
var _q: PackedInt32Array = PackedInt32Array()
var _cull_px: float = 40.0 * 32.0
var _vis_cache: Dictionary = {}       # wslot*16+tag -> {fx dict + 표시 옵션}
var _enemy_fx: Dictionary = {}
var _anim_t: float = 0.0
var _hard_cap: int = 768
var _alpha: float = 0.0
var _lift_player: float = 16.0
var _lift_enemy: float = 10.0
var _scale_warned: bool = false
var _eshots: Node2D = null            # 적 탄 층(z8)
var _ring_tex: Dictionary = {}        # [mode, wongwi] -> ImageTexture(가운데 맞춤)


func _ready() -> void:
	z_index = 4
	for n: String in ["px", "py", "vx", "vy", "life", "life0", "rad", "dmg", "born", "ppx", "ppy"]:
		var a: PackedFloat32Array = PackedFloat32Array()
		a.resize(CAPACITY)
		set(n, a)
	for n: String in ["pierce", "wslot", "flags", "ptag"]:
		var b: PackedInt32Array = PackedInt32Array()
		b.resize(CAPACITY)
		set(n, b)
	hit_mem.resize(CAPACITY * HIT_MEM)
	pdir.resize(CAPACITY)
	_lift_player = Data.num("combat_core", "feel.proj.lift_player", 16.0)
	_lift_enemy = Data.num("combat_core", "feel.proj.lift_enemy", 10.0)
	hit_head.resize(CAPACITY)
	_free.resize(CAPACITY)
	for i in CAPACITY:
		_free[i] = CAPACITY - 1 - i
	_free_n = CAPACITY
	_q.resize(64)
	_hard_cap = int(Data.num("weapons", "globals.projectile_pool.global_hard_cap", 768))
	_enemy_fx = VfxLib.get_fx(&"vfx_cheonyeo_bullet")
	_eshots = Node2D.new()
	_eshots.name = "EnemyShots"
	_eshots.z_as_relative = false
	_eshots.z_index = ENEMY_Z
	add_child(_eshots)
	_eshots.draw.connect(_draw_enemy_shots)
	Events.weapon_added.connect(func(_id: StringName, _s: int) -> void: _vis_cache.clear())
	Events.weapon_evolved.connect(func(_a: StringName, _b: StringName) -> void: _vis_cache.clear())


func _alloc() -> int:
	if _free_n <= 0:
		return -1
	_free_n -= 1
	var i: int = _free[_free_n]
	alive_count += 1
	hit_head[i] = 0
	for k in HIT_MEM:
		hit_mem[i * HIT_MEM + k] = -1
	return i


func _release(i: int) -> void:
	if (flags[i] & F_ALIVE) == 0:
		return
	if (flags[i] & F_ENEMY) == 0:
		player_alive -= 1
	flags[i] = 0
	_free[_free_n] = i
	_free_n += 1
	alive_count -= 1


func spawn_player(weapon_slot: int, pos: Vector2, vel: Vector2, life_s: float, radius_px: float, damage: float, p_pierce: int, returning: bool = false, tag: int = 0, red: bool = false, track: bool = false) -> int:
	if player_alive >= _hard_cap:
		return -1
	var i: int = _alloc()
	if i < 0:
		return -1
	player_alive += 1
	px[i] = pos.x
	py[i] = pos.y
	ppx[i] = pos.x
	ppy[i] = pos.y
	vx[i] = vel.x
	vy[i] = vel.y
	pdir[i] = _dir4(vel, 0)
	life[i] = life_s * (2.2 if returning else 1.0)
	life0[i] = life_s
	rad[i] = radius_px
	dmg[i] = damage
	born[i] = Game.time_sec()
	pierce[i] = p_pierce
	wslot[i] = weapon_slot
	ptag[i] = tag
	flags[i] = F_ALIVE | (F_RETURN if returning else 0) | (F_RED if red else 0) | (F_TRACK if track else 0)
	return i


func spawn_enemy(pos: Vector2, vel: Vector2, life_s: float, radius_px: float, damage: float, _kind: StringName = &"prj_wonhon_tan") -> int:
	var i: int = _alloc()
	if i < 0:
		return -1
	px[i] = pos.x
	py[i] = pos.y
	ppx[i] = pos.x
	ppy[i] = pos.y
	vx[i] = vel.x
	vy[i] = vel.y
	life[i] = life_s
	life0[i] = life_s
	rad[i] = radius_px
	dmg[i] = damage
	born[i] = Game.time_sec()
	pierce[i] = 1
	wslot[i] = -1
	ptag[i] = ETAG_WONGWI if String(_kind).contains("wongwi") else 0
	flags[i] = F_ALIVE | F_ENEMY
	return i


func clear_all() -> void:
	for i in CAPACITY:
		_release(i)


## 해당 무구 슬롯의 플레이어 탄 전부 제거(진화·결합 교체 시).
func clear_slot(weapon_slot: int) -> void:
	for i in CAPACITY:
		if (flags[i] & F_ALIVE) != 0 and (flags[i] & F_ENEMY) == 0 and wslot[i] == weapon_slot:
			_release(i)
	_vis_cache.clear()


## 결합으로 슬롯 번호가 당겨질 때.
func remap_slot(old_slot: int, new_slot: int) -> void:
	for i in CAPACITY:
		if (flags[i] & F_ALIVE) != 0 and (flags[i] & F_ENEMY) == 0 and wslot[i] == old_slot:
			wslot[i] = new_slot
	_vis_cache.clear()


func sim_step(dt: float) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	var wm: WeaponManager = Game.weapons as WeaponManager
	var pp: Vector2 = Game.player.global_position if Game.player != null else Vector2.ZERO
	var player_r: float = Data.num("enemies", "global_rules.player_hitbox_u", 0.3) * K.UNIT_PX
	for i in CAPACITY:
		var f: int = flags[i]
		if (f & F_ALIVE) == 0:
			continue
		ppx[i] = px[i]
		ppy[i] = py[i]
		# 부메랑: 사거리 끝에서 감속 후 플레이어로 귀환(귀환 궤적도 타격, 귀환 시 적중 기록 초기화)
		if (f & F_RETURN) != 0:
			var elapsed: float = life0[i] * 2.2 - life[i]
			if (f & F_RETURNING) == 0 and elapsed >= life0[i]:
				_begin_return(i)
				f = flags[i]
			if (f & F_RETURNING) != 0:
				var to: Vector2 = pp - Vector2(px[i], py[i])
				var sp: float = Vector2(vx[i], vy[i]).length()
				var nv: Vector2 = Vector2(vx[i], vy[i]).lerp(to.normalized() * maxf(sp, 200.0), 1.0 - exp(-dt * 8.0))
				vx[i] = nv.x
				vy[i] = nv.y
				if to.length() < 12.0:
					if wm != null:
						wm.on_projectile_end(wslot[i], ptag[i], Vector2(px[i], py[i]), nv, END_RETURNED)
					_release(i)
					continue
		px[i] += vx[i] * dt
		py[i] += vy[i] * dt
		life[i] -= dt
		var dx: float = px[i] - pp.x
		var dy: float = py[i] - pp.y
		if life[i] <= 0.0 or dx * dx + dy * dy > _cull_px * _cull_px:
			if (f & F_ENEMY) == 0 and wm != null:
				wm.on_projectile_end(wslot[i], ptag[i], Vector2(px[i], py[i]), Vector2(vx[i], vy[i]), END_RANGE)
			_release(i)
			continue
		if (f & F_TRACK) != 0 and wm != null:
			wm.on_projectile_step(wslot[i], ptag[i], i, Vector2(px[i], py[i]))
			if (flags[i] & F_ALIVE) == 0:
				continue
		if (f & F_ENEMY) != 0:
			var rr: float = rad[i] + player_r
			if dx * dx + dy * dy <= rr * rr and Game.player != null:
				Game.player.call("take_hit", dmg[i], &"enemy_projectile")
				_release(i)
			continue
		if em == null or wm == null:
			continue
		var n: int = em.query_circle(Vector2(px[i], py[i]), rad[i], _q)
		for k in n:
			var e: int = _q[k]
			if not em.is_alive(e):
				continue
			var h: int = em.handle_of(e)
			if _in_mem(i, h):
				continue
			_remember(i, h)
			var dir: Vector2 = Vector2(vx[i], vy[i]).normalized()
			wm.on_projectile_hit(wslot[i], e, dmg[i], dir, ptag[i], i)
			if (flags[i] & F_ALIVE) == 0:
				break  # 콜백이 탄을 소모시킴
			# 붉은 탄 vs 풀릴 기색 일반 잡귀: 판정만 하고 관통을 쓰지 않고 지나간다(02 5.2, R11)
			var ef: int = em.flags[e]
			if (f & F_RED) != 0 and (ef & EnemyManager.F_PULLIL) != 0 and (ef & EnemyManager.F_ELITE_PLUS) == 0:
				continue
			if pierce[i] > 0:
				pierce[i] -= 1
				if pierce[i] == 0:
					if (f & F_RETURN) != 0 and (f & F_RETURNING) == 0:
						_begin_return(i)  # 신칼: 관통 소진 시 즉시 귀환
						pierce[i] = 1
					else:
						wm.on_projectile_end(wslot[i], ptag[i], Vector2(px[i], py[i]), Vector2(vx[i], vy[i]), END_PIERCE)
						_release(i)
					break


func _begin_return(i: int) -> void:
	flags[i] |= F_RETURNING
	for k in HIT_MEM:
		hit_mem[i * HIT_MEM + k] = -1


## 외부(무구)에서 탄 소모.
func kill(i: int) -> void:
	if i >= 0 and i < CAPACITY:
		_release(i)


func _in_mem(i: int, h: int) -> bool:
	var b: int = i * HIT_MEM
	for k in HIT_MEM:
		if hit_mem[b + k] == h:
			return true
	return false


func _remember(i: int, h: int) -> void:
	hit_mem[i * HIT_MEM + hit_head[i]] = h
	hit_head[i] = (hit_head[i] + 1) % HIT_MEM


## 히트스톱·일시정지 프레임: prev = cur 동결(run.gd).
func freeze_prev() -> void:
	for i in CAPACITY:
		if (flags[i] & F_ALIVE) != 0:
			ppx[i] = px[i]
			ppy[i] = py[i]


## 렌더 단계 R5(run.gd). 연출 시계(Game.anim_time) 기준이라 히트스톱에서 시트 프레임도 멈춘다.
func render(alpha: float) -> void:
	_alpha = alpha
	_anim_t = Game.anim_time()
	queue_redraw()
	if _eshots != null:
		_eshots.queue_redraw()


## 90° 단위 방향(0 E, 1 S, 2 W, 3 N). 경계 ±5° 히스테리시스(곡선 귀환 탄 떨림 방지).
static func _dir4(v: Vector2, cur: int) -> int:
	if v.length_squared() < 0.0001:
		return cur
	var a: float = rad_to_deg(atan2(v.y, v.x))
	var c: float = float(cur) * 90.0
	if absf(wrapf(a - c, -180.0, 180.0)) <= 45.0 + 5.0:
		return cur
	return int(roundf(a / 90.0)) & 3


func _visual(ws: int, tag: int, wm: WeaponManager) -> Dictionary:
	var key: int = ws * 16 + tag
	var v: Variant = _vis_cache.get(key)
	if v != null:
		return v
	var out: Dictionary = {}
	var w: WeaponBase = wm.weapon_at(ws) if wm != null else null
	if w != null:
		out = w.proj_visual(tag).duplicate()
	if not out.has("fx") or StringName(out.get("fx", &"")) == &"":
		out["tex"] = w.projectile_texture() if w != null else SpriteLib.dot(6, K.COL_JEOK_HI)
	else:
		var fxd: Dictionary = VfxLib.get_fx(StringName(out["fx"]))
		if bool(fxd.get("placeholder", false)):
			out["tex"] = w.projectile_texture() if w != null else SpriteLib.dot(6, K.COL_JEOK_HI)  # 시트 없음 → 기본 그림
		else:
			out["fxd"] = fxd
	if out.has("trail"):
		var trd: Dictionary = VfxLib.get_fx(StringName(out["trail"]))
		if not bool(trd.get("placeholder", false)):
			out["trd"] = trd
	# 배율은 정수 1 또는 2만(그 외는 1 + 경고 1회)
	var sc: Variant = out.get("scale", 1)
	var si: int = int(sc) if (sc is int or sc is float) else 1
	if (sc is float and float(sc) != float(si)) or (si != 1 and si != 2):
		if not _scale_warned:
			_scale_warned = true
			push_warning("[ProjectilePool] proj_visual scale %s → 1 (정수 1|2만 허용)" % str(sc))
		si = 1
	out["scale_i"] = si
	var orient0: StringName = StringName(out.get("orient", &"none"))
	var snap: bool = orient0 == &"dir8" or orient0 == &"dir16" or orient0 == &"dir4"
	var t0: Texture2D = out.get("tex")
	if orient0 == &"none" and not out.has("orient") and t0 != null and t0.get_width() != t0.get_height():
		snap = true                               # 길쭉한 단일 그림(화살 등): 90° 스냅
	out["snap"] = snap
	_vis_cache[key] = out
	return out


func _draw() -> void:
	var wm: WeaponManager = Game.weapons as WeaponManager
	var al: float = _alpha
	# 잔상(design/19 §5.1): 내 탄 60개 이하·군중 아님일 때만 2장. 몸통 한지 심은 늘.
	var ghosts_ok: bool = player_alive <= 60 and not WeaponBase.fx_crowd()
	for i in CAPACITY:
		var f: int = flags[i]
		if (f & F_ALIVE) == 0:
			continue
		if (f & F_ENEMY) != 0:
			continue                              # 적 탄은 EnemyShots(z8)에서
		var p: Vector2 = K.rndv(Vector2(lerpf(ppx[i], px[i], al), lerpf(ppy[i], py[i], al)))
		var vis: Dictionary = _visual(wslot[i], ptag[i], wm)
		var lift: float = float(vis.get("lift_px", _lift_player))
		var pp: Vector2 = p - Vector2(0, lift)
		var age: float = maxf(0.0, _anim_t - born[i])
		var scl: float = float(int(vis["scale_i"]))
		var tint: Color = vis.get("tint", Color.WHITE)
		var ang: float = 0.0
		if bool(vis["snap"]):
			var d4: int = _dir4(Vector2(vx[i], vy[i]), pdir[i])
			pdir[i] = d4
			ang = float(d4) * (PI * 0.5)           # 90° 단위만(픽셀 정확). dir8/dir16 시트가 생기면 프레임 선택으로 교체
		var trd: Variant = vis.get("trd")
		if trd != null:
			_draw_sheet(trd, pp, ang, scl, age, tint, true)
		var fxd: Variant = vis.get("fxd")
		var gn: int = int(vis.get("ghosts", 0)) if ghosts_ok else 0
		var vdir: Vector2 = Vector2(vx[i], vy[i])
		if gn > 0 and vdir.length_squared() > 1.0:
			# 잔상: 직전 프레임 자리(속도 1틱분, 최소 3px)에 같은 그림을 jk-hi/한지 α0.5·0.25 로
			var stp: Vector2 = vdir.normalized() * maxf(3.0, vdir.length() / float(K.TICK_HZ))
			var gc: Color = vis.get("ghost_col", K.COL_JEOK_HI)
			for g in range(gn, 0, -1):
				var gpos: Vector2 = K.rndv(pp - stp * float(g))
				var gcol: Color = Color(gc, 0.5 / float(g))
				if fxd != null:
					_draw_sheet(fxd, gpos, ang, scl, age, gcol, false, _phase_frame(i, f, vis, fxd))
				else:
					var tex0: Texture2D = vis.get("tex")
					if tex0 != null:
						draw_set_transform(gpos, ang, Vector2(scl, scl))
						draw_texture(tex0, -K.rndv(tex0.get_size() * 0.5), gcol)
		if fxd != null:
			_draw_sheet(fxd, pp, ang, scl, age, tint, false, _phase_frame(i, f, vis, fxd))
		else:
			var tex: Texture2D = vis.get("tex")
			if tex != null:
				draw_set_transform(pp, ang, Vector2(scl, scl))
				draw_texture(tex, -K.rndv(tex.get_size() * 0.5), tint)
		var cl: int = int(vis.get("core_len", 0))
		if cl > 0 and vdir.length_squared() > 1.0:
			# 몸통 한지 심(진행 방향 1px 선): 어두운 붉은 탄도 L ≥0.5 로 읽힌다
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var hd: Vector2 = vdir.normalized() * (float(cl) * 0.5)
			draw_line(K.rndv(pp - hd), K.rndv(pp + hd), K.COL_HANJI, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 적 탄 층(EnemyShots z8)의 draw 신호. 링 → 먹 테(±1px 4번) → 탄 그림 순.
func _draw_enemy_shots() -> void:
	var left: int = alive_count - player_alive
	if left <= 0:
		return
	var e_regions: Array = _enemy_fx.get("regions", [])
	var tex: Texture2D = _enemy_fx.get("texture") as Texture2D
	var v: Variant = Juice.get(&"bullet_emphasis")
	var mode: int = clampi(int(v), 0, 2) if (v is int or v is float) else 1
	var al: float = _alpha
	var er: Rect2 = Rect2()
	var piv: Vector2 = Vector2.ZERO
	if not e_regions.is_empty():
		er = e_regions[int(_anim_t * 8.0) % e_regions.size()]
		piv = K.rndv(er.size * 0.5)
	# 위치를 먼저 모은 뒤 층별로 그린다(링 전부 → 먹 테 전부 → 탄 전부): 같은 텍스처끼리 이어 그려 묶음(draw call)이 늘지 않게.
	var cs: PackedVector2Array = PackedVector2Array()
	var wons: PackedByteArray = PackedByteArray()
	for i in CAPACITY:
		var f: int = flags[i]
		if (f & F_ALIVE) == 0 or (f & F_ENEMY) == 0:
			continue
		left -= 1
		if left < 0:
			break
		cs.append(K.rndv(Vector2(lerpf(ppx[i], px[i], al), lerpf(ppy[i], py[i], al))) - Vector2(0, _lift_enemy))
		wons.append(1 if ptag[i] == ETAG_WONGWI else 0)
	var n: int = cs.size()
	for k in n:
		if mode > 0 or wons[k] == 1:
			var rt: ImageTexture = _ring(maxi(mode, 1), wons[k] == 1)
			_eshots.draw_texture(rt, cs[k] - Vector2(rt.get_width() / 2, rt.get_height() / 2))
	if tex == null or e_regions.is_empty():
		for k2 in n:
			_eshots.draw_rect(Rect2(cs[k2] - Vector2(2, 2), Vector2(4, 4)), COL_INK)
			_eshots.draw_rect(Rect2(cs[k2] - Vector2(1, 1), Vector2(2, 2)), COL_RING2)
		return
	for k3 in n:
		var r0: Rect2 = Rect2(cs[k3] - piv, er.size)
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_eshots.draw_texture_rect_region(tex, Rect2(r0.position + d, r0.size), er, COL_INK)
	for k4 in n:
		_eshots.draw_texture_rect_region(tex, Rect2(cs[k4] - piv, er.size), er)


## 링 그림(픽셀 정확, 한 번 만들어 둠). mode 1: 반지름 5 청 1px + 바깥 먹 1px / mode 2: 반지름 5~6 밝은 청 2px + 먹 1px.
func _ring(mode: int, won: bool) -> ImageTexture:
	var key: int = mode * 2 + (1 if won else 0)
	var t: Variant = _ring_tex.get(key)
	if t != null:
		return t
	var r_in: float = 4.5
	var r_mid: float = 5.5 if mode == 1 else 6.5
	var r_out: float = r_mid + 1.0
	var col: Color = COL_JK_DK if won else (COL_RING1 if mode == 1 else COL_RING2)
	var sz: int = int(ceilf(r_out)) * 2 + 1
	var h: float = float(sz / 2)
	var img: Image = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in sz:
		for x in sz:
			var d: float = Vector2(float(x) - h, float(y) - h).length()
			if d >= r_in and d < r_mid:
				img.set_pixel(x, y, col)
			elif d >= r_mid and d < r_out:
				img.set_pixel(x, y, COL_INK)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_ring_tex[key] = tex
	return tex


## 구간별 orient(proj_visual: orient_out / orient_apex / orient_ret, apex_frac). 8프레임 사전 렌더 시트에서
## dir8 = 진행 방향 프레임(frame k = k×45° 시계, 동쪽 0 — 칼끝이 진행 방향, 술이 뒤로 끌림), spin = -1(시간 프레임).
## 귀환 탄(F_RETURN): 나감(경과 < life0×apex_frac) → orient_out, 정점 구간 → orient_apex, 귀환 중 → orient_ret.
func _phase_frame(i: int, f: int, vis: Dictionary, fxd: Dictionary) -> int:
	if not vis.has("orient_out"):
		return -1
	var o: StringName = StringName(vis.get("orient_out", &"spin"))
	if (f & F_RETURN) != 0:
		if (f & F_RETURNING) != 0:
			o = StringName(vis.get("orient_ret", vis.get("orient", &"spin")))
		else:
			var elapsed: float = life0[i] * 2.2 - life[i]
			if elapsed >= life0[i] * float(vis.get("apex_frac", 0.7)):
				o = StringName(vis.get("orient_apex", vis.get("orient", &"spin")))
	if o != &"dir8":
		return -1
	var n: int = (fxd["regions"] as Array).size()
	if n != 8:
		return -1
	var a: float = atan2(vy[i], vx[i])
	return int(roundf(a / (PI / 4.0))) & 7


## 꼬리(trail)는 피벗을 탄 뒤쪽에 맞춰 반대 방향(180° = 픽셀 정확)으로 그린다. spin 시트는 회전 없이 프레임만 넘긴다.
func _draw_sheet(fx: Dictionary, p: Vector2, ang: float, scl: float, age: float, tint: Color, trail: bool, force_frame: int = -1) -> void:
	var regions: Array = fx["regions"]
	if regions.is_empty():
		return
	var n: int = regions.size()
	var fi: int = int(age * float(fx["fps"]))
	fi = fi % n if bool(fx["loop"]) else mini(fi, n - 1)
	if force_frame >= 0 and force_frame < n:
		fi = force_frame
	var r: Rect2 = regions[fi]
	var piv: Vector2 = K.rndv(fx["pivot"])
	draw_set_transform(p, ang + (PI if trail else 0.0), Vector2(scl, scl))
	draw_texture_rect_region(fx["texture"], Rect2(-piv, r.size), r, tint)
