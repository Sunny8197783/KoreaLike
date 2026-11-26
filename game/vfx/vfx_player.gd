class_name VfxPlayer
extends Node2D
## 원샷·반복 스프라이트시트 이펙트 재생기(풀링된 Sprite2D). 소유: vfx.
## play(fx_id, pos, rot=0, scale=1, opts={}) -> int      play_flip(fx_id, pos, flip, additive) -> int (타격 경로용, 할당 없음)
##   opts: "fps_mult" 배속, "modulate" Color, "z" int(레이어 자동값 대신), "additive" bool(목록 blend 대신),
##         "flip" 0..3(bit0 좌우, bit1 상하), "snap" bool(목록 beat_snap 무시하려면 false), "life" 초(반복 시트 수명),
##         "delay" 초(연출 시계 지연)
## 시트 메타 자동 적용(VfxLib ← data/art_vfx_list.json):
##   fps·프레임별 duration(판정 프레임 홀드) · pivot(발생점 = 앵커) · blend(normal/add/multiply)
##   beat_snap: 그리드 틱이 아닌 순간에 불리면 다음 그리드까지 남은 시간이 SNAP_WINDOW 이하일 때만 그 박에 맞춰 시작
##              (무구 발사는 이미 박 틱이라 지연 0. 타격 반응을 늦추지 않도록 창을 짧게 둔다)
##   max_concurrent: 종류별 동시 상한(목록 값, 최대 perf caps.vfx_oneshot_per_type 64). 초과 시 같은 종류의 가장 오래된 것을 재사용.
##   풀(256) 가득: 반복·수명 지정 슬롯(상시 오라 등)은 빼고 원샷 중 진행률이 가장 높은 것을 재사용
##   layer: L02~L05(지면 장판·예고) 는 행위자 아래(z −8), 그 밖은 행위자 위
## 회전·비정수 배율 금지(GAME_FEEL 3.3): rot 는 무시(호환 인자), scale 은 정수(1 이상)로 반올림, 방향 변형은 "flip".
## 재생 시계는 연출 시계(Game.anim_dt) — 히트스톱·일시정지에서 프레임이 멈춘다.
## Events.vfx_request(fx_id, pos, rot) 로도 재생 가능(시뮬레이션 쪽이 연출을 직접 참조하지 않게).

const POOL: int = 256
const SNAP_WINDOW: float = 0.085          # 박 스냅 허용 지연(초). 이보다 멀면 즉시 재생
const Z_GROUND: int = -8                  # 지면 레이어(L02~L05) 상대 z (VfxPlayer z 5 → 절대 −3: 지면 위·행위자 아래)

var _sprites: Array[Sprite2D] = []
var _fx: Array[Dictionary] = []
var _ids: Array[StringName] = []
var _t: PackedFloat32Array = PackedFloat32Array()
var _fps_mult: PackedFloat32Array = PackedFloat32Array()
var _delay: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _frame: PackedInt32Array = PackedInt32Array()
var _active: PackedByteArray = PackedByteArray()
var _total: PackedFloat32Array = PackedFloat32Array()   # 원샷 총 길이(초). 반복·수명 지정 = INF(전역 재사용 제외)
var _type_n: Dictionary = {}                            # fx_id → 활성 수(종류 상한 판정을 O(1)로)
var _next: int = 0
var _per_type_cap: int = 64
var _add_mat: CanvasItemMaterial
var _mul_mat: CanvasItemMaterial
var active_count: int = 0                 # 디버그·계측
var stat_played: int = 0
var stat_recycled: int = 0                # 동시 상한으로 재사용한 횟수
var stat_snapped: int = 0                 # 박 스냅으로 지연 시작한 횟수
var atmosphere: Atmosphere = null         # 분위기 층(조명 소품·한지 재·향 연기·밀도 감광)
var moon: RedMoon = null                  # 보스 붉은 달(월드 층 z −8, screen_fx 가 amount 공급)


func _ready() -> void:
	z_index = 5
	_per_type_cap = int(Data.num("tech/perf_budgets", "caps.vfx_oneshot_per_type", 64))
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mul_mat = CanvasItemMaterial.new()
	_mul_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_t.resize(POOL)
	_fps_mult.resize(POOL)
	_delay.resize(POOL)
	_life.resize(POOL)
	_frame.resize(POOL)
	_active.resize(POOL)
	_total.resize(POOL)
	for i in POOL:
		var s: Sprite2D = Sprite2D.new()
		s.visible = false
		s.region_enabled = true
		s.centered = false
		add_child(s)
		_sprites.append(s)
		_fx.append({})
		_ids.append(&"")
	Events.vfx_request.connect(func(id: StringName, pos: Vector2, rot: float) -> void: play(id, pos, rot))
	# 분위기 층(조명 소품·한지 재·향 연기·밀도 감광): vfx 소유 노드 하위에 둔다(run.tscn 무변경).
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	moon = RedMoon.new()
	moon.name = "RedMoon"
	add_child(moon)


func play(fx_id: StringName, pos: Vector2, _rot: float = 0.0, scl: float = 1.0, opts: Dictionary = {}) -> int:
	var blend_o: int = -1
	if opts.has("additive"):
		blend_o = 1 if bool(opts["additive"]) else 0
	return _play(fx_id, pos, scl, int(opts.get("flip", 0)), opts.get("modulate", Color.WHITE), int(opts.get("z", 99999)),
		blend_o, float(opts.get("delay", 0.0)), bool(opts.get("snap", true)), float(opts.get("life", 0.0)),
		float(opts.get("fps_mult", 1.0)))


## 타격·처치 경로 전용(매 호출 Dictionary 할당 없음). additive: -1 목록 blend / 0 normal / 1 add.
func play_flip(fx_id: StringName, pos: Vector2, flip: int = 0, additive: int = -1) -> int:
	return _play(fx_id, pos, 1.0, flip, Color.WHITE, 99999, additive, 0.0, true, 0.0, 1.0)


## play_flip + 색·배속(할당 없음). 해원 빛기둥 세기 단계·흰 무구 스파크 한지 톤(design/18 §1.5)에 쓴다.
func play_ex(fx_id: StringName, pos: Vector2, flip: int, additive: int, modc: Color, fps_mult: float = 1.0) -> int:
	return _play(fx_id, pos, 1.0, flip, modc, 99999, additive, 0.0, true, 0.0, fps_mult)


func _play(fx_id: StringName, pos: Vector2, scl: float, fl: int, modc: Color, z: int, blend_o: int, delay: float,
		snap: bool, life: float, fps_mult: float) -> int:
	var fx: Dictionary = VfxLib.get_fx(fx_id)
	var regions: Array = fx["regions"]
	if regions.is_empty():
		return -1
	var i: int = _find_slot(fx_id, int(fx["max_concurrent"]))
	var s: Sprite2D = _sprites[i]
	s.texture = fx["texture"]
	s.region_rect = regions[0]
	s.offset = -fx["pivot"]
	s.position = K.rndv(pos)
	s.rotation = 0.0
	var si: float = maxf(1.0, K.rnd(scl))
	s.scale = Vector2(si, si)
	s.flip_h = (fl & 1) != 0
	s.flip_v = (fl & 2) != 0
	s.modulate = modc
	var layer: int = int(fx["layer"])
	s.z_index = z if z != 99999 else (Z_GROUND if (layer >= 2 and layer <= 5) else 0)
	var blend: StringName = fx["blend"]
	if blend_o >= 0:
		blend = &"add" if blend_o == 1 else &"normal"
	s.material = _add_mat if blend == &"add" else (_mul_mat if blend == &"multiply" else null)
	if bool(fx["beat_snap"]) and snap and Game.run_active and not Beat.is_grid_tick:
		var now: float = Game.beat_sec()
		var wait: float = Beat.next_grid_time(now) - now
		if wait > 0.0 and wait <= SNAP_WINDOW:
			delay = maxf(delay, wait)
			stat_snapped += 1
	s.visible = delay <= 0.0
	if _active[i] == 0:
		active_count += 1
	else:
		_type_dec(_ids[i])
	_type_n[fx_id] = int(_type_n.get(fx_id, 0)) + 1
	_fx[i] = fx
	_ids[i] = fx_id
	_t[i] = 0.0
	_frame[i] = 0
	_delay[i] = delay
	_life[i] = life
	_fps_mult[i] = fps_mult
	_total[i] = INF if (life > 0.0 or bool(fx["loop"])) else maxf(float(fx["total"]), 0.001)
	_active[i] = 1
	stat_played += 1
	return i


func _type_dec(id: StringName) -> void:
	var n: int = int(_type_n.get(id, 0)) - 1
	_type_n[id] = maxi(0, n)


## 진행 중 이펙트를 옮긴다(따라다니는 오라 등). 정수 좌표로 스냅.
func move(i: int, pos: Vector2) -> void:
	if i >= 0 and i < POOL and _active[i] == 1:
		_sprites[i].position = K.rndv(pos)


func is_playing(i: int, fx_id: StringName = &"") -> bool:
	return i >= 0 and i < POOL and _active[i] == 1 and (fx_id == &"" or _ids[i] == fx_id)


func _find_slot(fx_id: StringName, list_cap: int) -> int:
	var cap: int = _per_type_cap if list_cap <= 0 else mini(list_cap, _per_type_cap)
	if int(_type_n.get(fx_id, 0)) >= cap:
		# 종류 상한: 같은 종류 중 가장 오래된 것(드묾 — 이때만 훑는다)
		var oldest_same: int = -1
		var oldest_t: float = -1.0
		for k in POOL:
			if _active[k] == 1 and _ids[k] == fx_id and _t[k] > oldest_t:
				oldest_t = _t[k]
				oldest_same = k
		if oldest_same >= 0:
			stat_recycled += 1
			return oldest_same
	for k in POOL:
		var j: int = (_next + k) % POOL
		if _active[j] == 0:
			_next = (j + 1) % POOL
			return j
	# 풀 가득: 반복·수명 지정(상시 오라·시련 기둥) 슬롯은 빼고, 원샷 중 진행률이 가장 높은 것을 재사용
	var old: int = -1
	var best: float = -1.0
	for k in POOL:
		if _total[k] == INF:
			continue
		var pr: float = _t[k] / _total[k]
		if pr > best:
			best = pr
			old = k
	if old < 0:
		old = _next
		_next = (_next + 1) % POOL
	stat_recycled += 1
	return old


func stop(i: int) -> void:
	if i >= 0 and i < POOL and _active[i] == 1:
		_active[i] = 0
		_type_dec(_ids[i])
		active_count -= 1
		_sprites[i].visible = false


func _process(delta: float) -> void:
	if active_count <= 0:
		return
	if Game.run_active or Game.state == Game.State.RUN:
		delta = Game.anim_dt
	if delta <= 0.0:
		return
	for i in POOL:
		if _active[i] == 0:
			continue
		if _delay[i] > 0.0:
			_delay[i] -= delta
			if _delay[i] > 0.0:
				continue
			_sprites[i].visible = true
		_t[i] += delta * _fps_mult[i]
		if _life[i] > 0.0 and _t[i] >= _life[i]:
			stop(i)
			continue
		var f: int = VfxLib.frame_at(_fx[i], _t[i])
		if f < 0:
			stop(i)
			continue
		if f != _frame[i]:
			_frame[i] = f
			_sprites[i].region_rect = (_fx[i]["regions"] as Array)[f]
