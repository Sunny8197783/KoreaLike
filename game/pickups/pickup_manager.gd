class_name PickupManager
extends Node2D
## 원혼 구슬(경험치) + 필드 픽업(공물·호신부·초혼발·명줄 실타래·엽전·넋·길흉 상자·넋함·가짜 엽전/공물·여우구슬). 소유: enemies.
## 개체는 노드가 아니다(SoA). 구슬은 MultiMesh 3장(소/중/대), 픽업은 자식 노드 1개의 _draw 일괄.
##
## 구슬: 퇴치 100% / 해원 60% 드롭(design/14 §3.6.4). 흡인 반경 = stat_chohon(u). 획득 → Game.add_xp.
##   상한 = combat_core.xp.orb_merge_count(300, 캐논 D-45): 넘으면 2u 안 구슬에 값 합산(크기 단계 상승), 근처에 없으면
##   무당에게서 먼 구슬 하나를 새 자리로 옮겨 합친다(값 보존 — 경험치는 사라지지 않는다).
## 픽업 드롭표: enemies.json drops(07 2.9) × 점괘/100. 상자 등급: combat_core.chest(02 18.1). 재화 양: meta_economy.income(09).
##
## 공개 API
##   spawn_orb(pos, value)                     구슬 1개(상한이면 병합)
##   pull_all(pos := 무당, r_px := -1)         반경 안(음수 = 전부) 구슬을 흡인 상태로(초혼발·방울 오라)
##   spawn_special(kind, pos, life_s := 0) -> int   픽업 1개(0 = 수명 없음). kind = pick_* / box_* / cur_*
##   find_special(kind, pos, r_px) -> int      가장 가까운 픽업 인덱스(-1). 아귀·역귀 떼·손님 NPC 가 공물을 찾는다
##   special_pos(i) -> Vector2 ; take_special(i) -> bool   적이 먹어 없앰(보상·신호 없음)
##   spawn_coins(pos, total, n, radius_px)     엽전 n 개를 흩뿌림(합계 total)
##   spawn_neok(pos, total, n)                 넋 n 개(곧바로 무당에게 날아온다)
##   spawn_box(kind, pos, bonus, sub := 0)     상자. bonus = 확정 부가 재화, sub 0 정예 / 1 원귀 / 2 중간보스 / 3 보스
##   clear_all() ; count(구슬 수) ; special_count ; 읽기 전용 px py alive ; CAPACITY
##   yeopjeon_run / neok_box_run / boxes_opened   이번 런 누계(HUD·정산 표시용. 메타 정산은 처치 수로 따로 셈한다)
## 신호: Events.pickup_collected(kind, value, pos) — 구슬 제외 모든 픽업. Events.box_opened(...) — 상자 개봉 결과.

const CAPACITY: int = 384            # 구슬 저장소(병합 상한 300 + 여유)
const SP_CAP: int = 96               # 필드 픽업 저장소
const GRID_SIZE: int = 1024
const GRID_MASK: int = 1023
const GRID_CELL: float = 64.0        # 병합 반경 2u
const PEND_CAP: int = 8
const FX_CAP: int = 32
const FX_TICKS: int = 9
const POP_TICKS: int = 12            # 드롭 튐(렌더 전용)

enum Pk { GONGMUL, HOSINBU, CHOHON, MYEONGJUL, BOX_GIL, BOX_NEOK, YEOPJEON, NEOK, GAJJA_YEOP, GAJJA_GONG, YEOU }
const KIND_IDS: Array[StringName] = [&"pick_gongmul", &"pick_hosinbu", &"pick_chohon_bal", &"pick_myeongjul_sil", &"box_gilhyung", &"box_neokham",
	&"cur_yeopjeon", &"cur_neok", &"pick_gajja_yeopjeon", &"pick_gajja_gongmul", &"pick_yeou_guseul"]

# --- 구슬 SoA(읽기 전용 공개: px py alive) ---
var px: PackedFloat32Array = PackedFloat32Array()
var py: PackedFloat32Array = PackedFloat32Array()
var val: PackedFloat32Array = PackedFloat32Array()
var spd: PackedFloat32Array = PackedFloat32Array()
var alive: PackedByteArray = PackedByteArray()
var count: int = 0
var _ppx: PackedFloat32Array = PackedFloat32Array()
var _ppy: PackedFloat32Array = PackedFloat32Array()
var _ox: PackedFloat32Array = PackedFloat32Array()       # 드롭 튐 시작점
var _oy: PackedFloat32Array = PackedFloat32Array()
var _mag: PackedByteArray = PackedByteArray()            # 1 = 흡인 중
var _born: PackedInt32Array = PackedInt32Array()
var _flash: PackedInt32Array = PackedInt32Array()        # 병합 번쩍 시작 틱
var _act: PackedInt32Array = PackedInt32Array()          # 밀집 활성 목록
var _act_pos: PackedInt32Array = PackedInt32Array()
var _free: PackedInt32Array = PackedInt32Array()
var _free_n: int = 0
var _gh: PackedInt32Array = PackedInt32Array()           # 병합용 격자 해시(정지 구슬만)
var _gn: PackedInt32Array = PackedInt32Array()
var _gb: PackedInt32Array = PackedInt32Array()           # 구슬이 든 버킷(-1 = 해시에 없음)
var _scan: int = 0

# --- 필드 픽업 SoA ---
var s_alive: PackedByteArray = PackedByteArray()
var s_kind: PackedByteArray = PackedByteArray()
var s_sub: PackedByteArray = PackedByteArray()
var s_st: PackedByteArray = PackedByteArray()            # 0 놓임 / 1 무당에게 날아감
var s_x: PackedFloat32Array = PackedFloat32Array()
var s_y: PackedFloat32Array = PackedFloat32Array()
var s_ppx: PackedFloat32Array = PackedFloat32Array()
var s_ppy: PackedFloat32Array = PackedFloat32Array()
var s_ox: PackedFloat32Array = PackedFloat32Array()
var s_oy: PackedFloat32Array = PackedFloat32Array()
var s_val: PackedFloat32Array = PackedFloat32Array()
var s_spd: PackedFloat32Array = PackedFloat32Array()
var s_life: PackedFloat32Array = PackedFloat32Array()
var s_born: PackedInt32Array = PackedInt32Array()
var s_auto: PackedInt32Array = PackedInt32Array()        # 이 틱부터 저절로 날아옴(-1 없음)
var special_count: int = 0
var _kind_n: PackedInt32Array = PackedInt32Array()

# --- 상자 개봉 뒤 지연 분출(엽전·넋) ---
var _pd_tick: PackedInt32Array = PackedInt32Array()
var _pd_kind: PackedByteArray = PackedByteArray()
var _pd_x: PackedFloat32Array = PackedFloat32Array()
var _pd_y: PackedFloat32Array = PackedFloat32Array()
var _pd_amt: PackedFloat32Array = PackedFloat32Array()
var _pd_n: PackedInt32Array = PackedInt32Array()
var _pd_count: int = 0

# --- 획득 반짝(렌더 전용 링 버퍼) ---
var _fx_x: PackedFloat32Array = PackedFloat32Array()
var _fx_y: PackedFloat32Array = PackedFloat32Array()
var _fx_t: PackedInt32Array = PackedInt32Array()
var _fx_c: PackedByteArray = PackedByteArray()
var _fx_head: int = 0

# --- 이번 런 누계 ---
var yeopjeon_run: int = 0
var neok_box_run: int = 0
var boxes_opened: int = 0
var _myeongjul_dropped: int = 0

# --- 파라미터(데이터) ---
var _max_spd: float = 12.0 * 32.0
var _accel: float = 0.25
var _merge_n: int = 300
var _merge_r: float = 64.0
var _tier_m: float = 5.0
var _tier_l: float = 20.0
var _haewon_orb_p: float = 0.6
var _pull_t: float = 0.0
var _pull_time: float = 1.5
var _heal_gongmul: float = 0.2
var _p_gong_c: float = 0.0025
var _p_gong_e: float = 0.15
var _n_gong_m: int = 2
var _p_hos_c: float = 0.001
var _p_hos_e: float = 0.04
var _p_hos_m: float = 0.3
var _p_hos_hwe: float = 0.01
var _hos_after: float = 180.0
var _p_cho_c: float = 0.0003
var _p_cho_e: float = 0.05
var _p_cho_m: float = 0.5
var _cho_max: int = 2
var _p_myeong_e: float = 0.005
var _p_myeong_m: float = 0.1
var _myeong_max: int = 1
var _box_coins: int = 7
var _fallback_coin: float = 20.0
var _xp_cache: Dictionary = {}       # species -> xp
var _tier_cache: Dictionary = {}     # species -> 정의 등급(원귀 판별)

# --- 그리기 ---
var _mm: Array[MultiMeshInstance2D] = []
var _mm_frames: PackedInt32Array = PackedInt32Array()
var _items: Node2D = null
var _icons: Array[Texture2D] = []
var _fx_coin: Dictionary = {}
var _fx_neok: Dictionary = {}
var _fx_box_g: Dictionary = {}
var _fx_box_n: Dictionary = {}
const _C_SHADOW: Color = Color(14.0 / 255.0, 11.0 / 255.0, 22.0 / 255.0, 0.45)
const _FX_COL: Array[Color] = [Color("#e9dcc0"), Color("#f5d66b"), Color("#f2ece0"), Color("#9fe0d4"), Color("#e4604f")]

# 픽셀 아이콘 팔레트(ART_STYLE 3.1 마스터 색만)
const _PAL: Dictionary = {
	"k": "#1a1a1a", "a": "#6a4a12", "b": "#a97c1b", "c": "#e8b931", "d": "#f5d66b", "e": "#fff1b8",
	"r": "#8c1f22", "R": "#c8322d", "s": "#e4604f", "h": "#857154", "H": "#b29d76", "j": "#d2c19c", "J": "#e9dcc0",
	"t": "#1d5a58", "T": "#2f8c86", "u": "#55b8aa", "U": "#9fe0d4", "g": "#556046", "G": "#727f5f",
}
const _ICON_GONGMUL: PackedStringArray = [
	"................",
	"......kkkk......",
	".....kRsRRk.....",
	"....kkRRRrkk....",
	"...kJJkkkkJJk...",
	"..kJJJJjjJJJJk..",
	"..kjJJJJJJJJjk..",
	"...kkkkkkkkkk...",
	"..kbcdccccccbk..",
	"...kbbbbbbbbk...",
	"....kkabbakk....",
	".....kabbak.....",
	"....kabbbbak....",
	"....kkkkkkkk....",
	"................",
	"................"]
const _ICON_HOSINBU: PackedStringArray = [
	"................",
	"....kkkkkkkk....",
	"....kdddddck....",
	"....kdRRRRck....",
	"....kddRRdck....",
	"....kdRRRRck....",
	"....kdRddRck....",
	"....kddRRdck....",
	"....kdRRRRck....",
	"....kddRRdck....",
	"....kdRddRck....",
	"....kcddddbk....",
	"....kcccbbbk....",
	"....kkkkkkkk....",
	"................",
	"................"]
const _ICON_CHOHON: PackedStringArray = [
	"................",
	"..k.............",
	".kak.kkkkkkk....",
	".kbkkJJJJJJjk...",
	".kbkJJJuuJJJjk..",
	".kbkJJuUUuJJjk..",
	".kbkJJJuuJJjk...",
	".kbkkJJJJJjk....",
	".kbk.kkjJjk.....",
	".kbk...kjk......",
	".kbk....k.......",
	".kbk............",
	".kak............",
	".kak............",
	"..k.............",
	"................"]
const _ICON_MYEONGJUL: PackedStringArray = [
	"................",
	".....kkkkk......",
	"....kRsRsRk.....",
	"...kRsRRsRRk....",
	"..kRRsRsRRsRk...",
	"..ksRRsRRsRRk...",
	"..kRsRRsRsRRk...",
	"..kRRsRRsRRrk...",
	"..krRRsRsRrrk...",
	"...krRRsRrrk....",
	"....krrrrrk.kk..",
	".....kkkkkkRRk..",
	"..........ksRk..",
	"...........kk...",
	"................",
	"................"]
const _ICON_YEOU: PackedStringArray = [
	"................",
	"................",
	".....kkkkkk.....",
	"....kcdddddk....",
	"...kcUUUUUudk...",
	"..kcUUeeUUuuck..",
	"..kdUeeUUuuTck..",
	"..kdUUUUuuTTck..",
	"..kduUUuuTTtck..",
	"..kduuuuTTttck..",
	"...kcuTTTttck...",
	"....kccttcck....",
	".....kkkkkk.....",
	"................",
	"................",
	"................"]


func _ready() -> void:
	z_index = 0
	for a: String in ["px", "py", "val", "spd", "_ppx", "_ppy", "_ox", "_oy"]:
		var arr: PackedFloat32Array = PackedFloat32Array()
		arr.resize(CAPACITY)
		set(a, arr)
	for a2: String in ["_born", "_flash", "_act", "_act_pos", "_free", "_gn", "_gb"]:
		var ia: PackedInt32Array = PackedInt32Array()
		ia.resize(CAPACITY)
		set(a2, ia)
	alive.resize(CAPACITY)
	_mag.resize(CAPACITY)
	_gh.resize(GRID_SIZE)
	for a3: String in ["s_x", "s_y", "s_ppx", "s_ppy", "s_ox", "s_oy", "s_val", "s_spd", "s_life"]:
		var sa: PackedFloat32Array = PackedFloat32Array()
		sa.resize(SP_CAP)
		set(a3, sa)
	for a4: String in ["s_alive", "s_kind", "s_sub", "s_st"]:
		var sb: PackedByteArray = PackedByteArray()
		sb.resize(SP_CAP)
		set(a4, sb)
	s_born.resize(SP_CAP)
	s_auto.resize(SP_CAP)
	_kind_n.resize(KIND_IDS.size())
	_pd_tick.resize(PEND_CAP)
	_pd_kind.resize(PEND_CAP)
	_pd_x.resize(PEND_CAP)
	_pd_y.resize(PEND_CAP)
	_pd_amt.resize(PEND_CAP)
	_pd_n.resize(PEND_CAP)
	_fx_x.resize(FX_CAP)
	_fx_y.resize(FX_CAP)
	_fx_t.resize(FX_CAP)
	_fx_c.resize(FX_CAP)
	_reset_state()
	_load_params()
	_build_draw()
	Events.enemy_killed.connect(_on_enemy_killed)


func _reset_state() -> void:
	alive.fill(0)
	_mag.fill(0)
	_gh.fill(-1)
	_gb.fill(-1)
	_act_pos.fill(-1)
	count = 0
	_free_n = CAPACITY
	for i in CAPACITY:
		_free[i] = CAPACITY - 1 - i
	s_alive.fill(0)
	_kind_n.fill(0)
	special_count = 0
	_pd_count = 0
	_fx_t.fill(-100000)
	_pull_t = 0.0
	_scan = 0


func _load_params() -> void:
	_max_spd = Data.num("combat_core", "xp.magnet_max_speed_u", 12.0) * K.UNIT_PX
	_accel = maxf(0.01, Data.num("combat_core", "xp.magnet_accel_time", 0.25))
	_merge_n = clampi(int(Data.num("combat_core", "xp.orb_merge_count", 300)), 8, CAPACITY - 8)
	_merge_r = minf(GRID_CELL, Data.num("combat_core", "xp.orb_merge_radius_u", 2.0) * K.UNIT_PX)
	var tm: Variant = Data.get_value("combat_core", "xp.orb_tiers.medium", null)
	if tm is Array and tm.size() > 0:
		_tier_m = float(tm[0])
	var tl: Variant = Data.get_value("combat_core", "xp.orb_tiers.large", null)
	if tl is Array and tl.size() > 0:
		_tier_l = float(tl[0])
	_pull_time = Data.num("combat_core", "pickups.pick_chohon_bal.pull_time", 1.5)
	_heal_gongmul = Data.num("combat_core", "pickups.pick_gongmul.heal", 0.2)
	_p_gong_c = Data.num("enemies", "drops.pick_gongmul.common", 0.0025)
	_p_gong_e = Data.num("enemies", "drops.pick_gongmul.elite", 0.15)
	_n_gong_m = int(Data.num("enemies", "drops.pick_gongmul.mboss.guaranteed", 2))
	_p_hos_c = Data.num("enemies", "drops.pick_hosinbu.common", 0.001)
	_p_hos_e = Data.num("enemies", "drops.pick_hosinbu.elite", 0.04)
	_p_hos_m = Data.num("enemies", "drops.pick_hosinbu.mboss", 0.3)
	_p_hos_hwe = Data.num("enemies", "drops.pick_hosinbu.override.enm_hwehwe_gwisin", 0.01)
	_p_cho_c = Data.num("enemies", "drops.pick_chohon_bal.common", 0.0003)
	_p_cho_e = Data.num("enemies", "drops.pick_chohon_bal.elite", 0.05)
	_p_cho_m = Data.num("enemies", "drops.pick_chohon_bal.mboss", 0.5)
	_cho_max = int(Data.num("enemies", "drops.pick_chohon_bal.max_on_screen", 2))
	_p_myeong_e = Data.num("enemies", "drops.pick_myeongjul_sil.elite", 0.005)
	_p_myeong_m = Data.num("enemies", "drops.pick_myeongjul_sil.mboss", 0.1)
	_myeong_max = int(Data.num("combat_core", "pickups.pick_myeongjul_sil.max_per_run", 1))
	_box_coins = int(Data.num("combat_core", "chest.box_gilhyung.coins", 7))
	_fallback_coin = Data.num("meta_economy", "income.yeopjeon_sources.box_fallback_per_slot", 20.0)


func _build_draw() -> void:
	var shader: Shader = load("res://pickups/orb_sheet.gdshader") as Shader
	for fx_id: StringName in [&"vfx_orb_small", &"vfx_orb_mid", &"vfx_orb_large"]:
		var fx: Dictionary = VfxLib.get_fx(fx_id)
		var tex: Texture2D = fx["texture"]
		var size: Vector2 = fx["size"]
		var piv: Vector2 = fx["pivot"]
		var n: int = maxi(1, (fx["regions"] as Array).size())
		var cols: int = maxi(1, int(tex.get_width() / maxf(size.x, 1.0))) if tex != null else 1
		var rows: int = maxi(1, int(tex.get_height() / maxf(size.y, 1.0))) if tex != null else 1
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("cols", float(cols))
		mat.set_shader_parameter("rows", float(rows))
		var mmi: MultiMeshInstance2D = MultiMeshInstance2D.new()
		mmi.name = "MM_" + String(fx_id)
		mmi.texture = tex
		mmi.material = mat
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		mm.mesh = _quad(-piv, size)
		mm.instance_count = CAPACITY
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		add_child(mmi)
		_mm.append(mmi)
		_mm_frames.append(mini(n, cols * rows))
	_fx_coin = VfxLib.get_fx(&"vfx_yeopjeon_spin")
	_fx_neok = VfxLib.get_fx(&"vfx_neok_pickup")
	_fx_box_g = VfxLib.get_fx(&"vfx_box_gilhyung_open")
	_fx_box_n = VfxLib.get_fx(&"vfx_box_neokham_open")
	_icons.resize(KIND_IDS.size())
	_icons[Pk.GONGMUL] = _icon("gongmul", _ICON_GONGMUL)
	_icons[Pk.GAJJA_GONG] = _icons[Pk.GONGMUL]
	_icons[Pk.HOSINBU] = _icon("hosinbu", _ICON_HOSINBU)
	_icons[Pk.CHOHON] = _icon("chohon", _ICON_CHOHON)
	_icons[Pk.MYEONGJUL] = _icon("myeongjul", _ICON_MYEONGJUL)
	_icons[Pk.YEOU] = _icon("yeou", _ICON_YEOU)
	_items = Node2D.new()
	_items.name = "Items"
	_items.draw.connect(_draw_items)
	add_child(_items)


func _quad(origin: Vector2, size: Vector2) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([origin, origin + Vector2(size.x, 0), origin + size, origin + Vector2(0, size.y)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _icon(key: String, rows: PackedStringArray) -> Texture2D:
	var ck: String = "pickicon:" + key
	if AssetCache.tex.has(ck):
		return AssetCache.tex[ck]
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in mini(16, rows.size()):
		var line: String = rows[y]
		for x in mini(16, line.length()):
			var ch: String = line[x]
			if _PAL.has(ch):
				img.set_pixel(x, y, Color(String(_PAL[ch])))
	var t: Texture2D = ImageTexture.create_from_image(img)
	AssetCache.tex[ck] = t
	return t


func clear_all() -> void:
	_reset_state()


# ─── 드롭(Events.enemy_killed) ─────────────────────────────────────────

func _on_enemy_killed(_h: int, sp: StringName, pos: Vector2, k: StringName, _cause: StringName, tier: StringName) -> void:
	var haewon: bool = k == K.KIND_HAEWON
	if not _xp_cache.has(sp):
		var def: Dictionary = Data.enemy(String(sp))
		var xv: Variant = def.get("xp", 1)
		_xp_cache[sp] = float(xv) if (xv is float or xv is int) else 1.0
		_tier_cache[sp] = String(def.get("tier", "common"))
	var xp: float = _xp_cache[sp]
	var def_tier: String = _tier_cache[sp]
	var wongwi: bool = tier == K.TIER_ELITE and (def_tier == "common" or def_tier == "minion")
	if wongwi:
		xp *= 5.0
	if xp > 0.0 and (not haewon or Rng.chance(&"drop", _haewon_orb_p)):
		spawn_orb(pos, xp)
	var luck: float = clampf(Game.stat(&"stat_jeomgwae", 100.0) / 100.0, 0.0, 3.0)
	if tier == K.TIER_COMMON or tier == K.TIER_MINION:
		if xp <= 0.0:
			return                                  # 허상 등: 드롭 없음
		# 일반 잡귀: 굴림 1회(공물 → 호신부 → 초혼발). 퇴치·해원 같은 표(07 2.9)
		var r: float = Rng.randf_s(&"drop")
		var t: float = _p_gong_c * luck
		if r < t:
			spawn_special(&"pick_gongmul", pos)
			return
		if Game.time_sec() >= _hos_after:
			t += (_p_hos_hwe if sp == &"enm_hwehwe_gwisin" else _p_hos_c) * luck
			if r < t:
				spawn_special(&"pick_hosinbu", pos)
				return
		t += _p_cho_c * luck
		if r < t and _kind_n[Pk.CHOHON] < _cho_max:
			spawn_special(&"pick_chohon_bal", pos)
		return
	if tier == K.TIER_ELITE or tier == K.TIER_MBOSS:
		var mb: bool = tier == K.TIER_MBOSS
		var ring: int = 0
		if mb:
			for g in _n_gong_m:
				spawn_special(&"pick_gongmul", _ring_pos(pos, ring))
				ring += 1
		elif Rng.chance(&"drop", _p_gong_e * luck):
			spawn_special(&"pick_gongmul", _ring_pos(pos, ring))
			ring += 1
		if Rng.chance(&"drop", (_p_hos_m if mb else _p_hos_e) * luck):
			spawn_special(&"pick_hosinbu", _ring_pos(pos, ring))
			ring += 1
		if _kind_n[Pk.CHOHON] < _cho_max and Rng.chance(&"drop", (_p_cho_m if mb else _p_cho_e) * luck):
			spawn_special(&"pick_chohon_bal", _ring_pos(pos, ring))
			ring += 1
		if _myeongjul_dropped < _myeong_max and Rng.chance(&"drop", (_p_myeong_m if mb else _p_myeong_e) * luck):
			_myeongjul_dropped += 1
			spawn_special(&"pick_myeongjul_sil", _ring_pos(pos, ring))
		var sub: int = 2 if mb else (1 if wongwi else 0)
		if haewon:
			var key: String = "mboss_haewon_neokham" if mb else ("box_neokham_wongwi" if wongwi else "box_neokham_elite")
			spawn_box(&"box_neokham", pos + Vector2(0, 6), Data.num("meta_economy", "income.neok_sources." + key, 60.0), sub)
		else:
			var key2: String = "box_gilhyung_mboss" if mb else ("box_gilhyung_wongwi" if wongwi else "box_gilhyung_elite")
			spawn_box(&"box_gilhyung", pos + Vector2(0, 6), Data.num("meta_economy", "income.yeopjeon_sources." + key2, 330.0), sub)
		return
	if tier == K.TIER_BOSS:
		# 보스: 상자 2(07 8.0.2). 양은 09 합계를 개수로 나눈다
		for b in 2:
			var bp: Vector2 = pos + Vector2(-22.0 + 44.0 * float(b), 10.0)
			if haewon:
				spawn_box(&"box_neokham", bp, Data.num("meta_economy", "income.neok_sources.boss_han_neokham_total", 1500.0) * 0.5, 3)
			else:
				spawn_box(&"box_gilhyung", bp, Data.num("meta_economy", "income.yeopjeon_sources.box_gilhyung_boss_sal_total", 1800.0) * 0.5, 3)


func _ring_pos(c: Vector2, k: int) -> Vector2:
	var a: float = -PI * 0.5 + TAU * float(k) / 5.0 + 0.6
	return c + Vector2(cos(a), sin(a)) * 20.0


# ─── 구슬 ──────────────────────────────────────────────────────────────

func _bucket(cx: int, cy: int) -> int:
	return ((cx * 73856093) ^ (cy * 19349663)) & GRID_MASK


func _grid_add(i: int) -> void:
	var b: int = _bucket(int(floorf(px[i] / GRID_CELL)), int(floorf(py[i] / GRID_CELL)))
	_gn[i] = _gh[b]
	_gh[b] = i
	_gb[i] = b


func _grid_remove(i: int) -> void:
	var b: int = _gb[i]
	if b < 0:
		return
	_gb[i] = -1
	var j: int = _gh[b]
	if j == i:
		_gh[b] = _gn[i]
		return
	while j != -1:
		var nx: int = _gn[j]
		if nx == i:
			_gn[j] = _gn[i]
			return
		j = nx


## 병합 대상: 반경 안에서 가장 가까운 정지 구슬(-1 없음).
func _grid_nearest(x: float, y: float, r: float) -> int:
	var best: int = -1
	var bd: float = r * r
	var cx0: int = int(floorf((x - r) / GRID_CELL))
	var cx1: int = int(floorf((x + r) / GRID_CELL))
	var cy0: int = int(floorf((y - r) / GRID_CELL))
	var cy1: int = int(floorf((y + r) / GRID_CELL))
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var j: int = _gh[_bucket(cx, cy)]
			while j != -1:
				var dx: float = px[j] - x
				var dy: float = py[j] - y
				var d2: float = dx * dx + dy * dy
				if d2 <= bd:
					bd = d2
					best = j
				j = _gn[j]
	return best


func spawn_orb(pos: Vector2, value: float) -> void:
	if value <= 0.0:
		return
	var x: float = pos.x + Rng.range_s(&"pickup", -5.0, 5.0)
	var y: float = pos.y + Rng.range_s(&"pickup", -4.0, 4.0)
	var gt: int = Game.game_tick
	if count >= _merge_n or _free_n <= 0:
		# 상한: 2u 안 구슬에 합산(크기 단계 상승) → 없으면 먼 구슬 하나를 이 자리로 옮겨 합친다
		var j: int = _grid_nearest(x, y, _merge_r)
		if j >= 0:
			val[j] += value
			_flash[j] = gt
			return
		var v: int = _far_victim()
		if v < 0:
			val[_act[0]] += value
			return
		_grid_remove(v)
		val[v] += value
		_ox[v] = pos.x
		_oy[v] = pos.y
		px[v] = x
		py[v] = y
		_ppx[v] = x
		_ppy[v] = y
		_born[v] = gt
		_flash[v] = gt
		_grid_add(v)
		return
	_free_n -= 1
	var i: int = _free[_free_n]
	_act[count] = i
	_act_pos[i] = count
	count += 1
	px[i] = x
	py[i] = y
	_ppx[i] = x
	_ppy[i] = y
	_ox[i] = pos.x
	_oy[i] = pos.y
	val[i] = value
	spd[i] = 0.0
	_mag[i] = 0
	_born[i] = gt
	_flash[i] = -100000
	alive[i] = 1
	_grid_add(i)
	if _pull_t > 0.0:
		_magnetize(i)


## 무당에게서 가장 먼 정지 구슬(회전 창 24개만 본다 — O(1) 상각).
func _far_victim() -> int:
	if count <= 0:
		return -1
	var pp: Vector2 = Game.player.global_position if Game.player != null else Vector2.ZERO
	var best: int = -1
	var bd: float = -1.0
	for n in mini(24, count):
		_scan = (_scan + 1) % count
		var i: int = _act[_scan]
		if _mag[i] != 0:
			continue
		var dx: float = px[i] - pp.x
		var dy: float = py[i] - pp.y
		var d2: float = dx * dx + dy * dy
		if d2 > bd:
			bd = d2
			best = i
	return best


func _magnetize(i: int) -> void:
	if _mag[i] != 0:
		return
	_mag[i] = 1
	spd[i] = -_max_spd * 0.3          # 살짝 물러났다가 빨려 온다(흡인 읽힘)
	_grid_remove(i)


func _free_orb(i: int) -> void:
	_grid_remove(i)
	alive[i] = 0
	_mag[i] = 0
	var p: int = _act_pos[i]
	var last: int = _act[count - 1]
	_act[p] = last
	_act_pos[last] = p
	_act_pos[i] = -1
	count -= 1
	_free[_free_n] = i
	_free_n += 1


## 반경 안(음수 = 전부) 구슬을 흡인 상태로. 기본 중심 = 무당.
func pull_all(pos: Vector2 = Vector2.INF, r_px: float = -1.0) -> void:
	var c: Vector2 = pos
	if c == Vector2.INF:
		c = Game.player.global_position if Game.player != null else Vector2.ZERO
	var r2: float = r_px * r_px
	for k in count:
		var i: int = _act[k]
		if _mag[i] != 0:
			continue
		if r_px >= 0.0:
			var dx: float = px[i] - c.x
			var dy: float = py[i] - c.y
			if dx * dx + dy * dy > r2:
				continue
		_magnetize(i)


# ─── 필드 픽업 ─────────────────────────────────────────────────────────

func _kind_index(kind: StringName) -> int:
	return KIND_IDS.find(kind)


func spawn_special(kind: StringName, pos: Vector2, life_s: float = 0.0) -> int:
	var k: int = _kind_index(kind)
	if k < 0:
		return -1
	return _sp_add(k, pos, pos, 0.0, life_s, 0, -1)


func _sp_add(k: int, pos: Vector2, origin: Vector2, value: float, life_s: float, sub: int, auto_tick: int) -> int:
	for i in SP_CAP:
		if s_alive[i] == 0:
			s_alive[i] = 1
			s_kind[i] = k
			s_sub[i] = sub
			s_st[i] = 0
			s_x[i] = pos.x
			s_y[i] = pos.y
			s_ppx[i] = pos.x
			s_ppy[i] = pos.y
			s_ox[i] = origin.x
			s_oy[i] = origin.y
			s_val[i] = value
			s_spd[i] = 0.0
			s_life[i] = life_s
			s_born[i] = Game.game_tick
			s_auto[i] = auto_tick
			special_count += 1
			_kind_n[k] += 1
			return i
	return -1


func _sp_free(i: int) -> void:
	if s_alive[i] == 0:
		return
	s_alive[i] = 0
	special_count -= 1
	_kind_n[s_kind[i]] -= 1


## 가장 가까운 놓인 픽업(날아가는 중 제외). 없으면 -1. 그 종류가 하나도 없으면 즉시 반환(아귀가 매 결정마다 부른다).
func find_special(kind: StringName, pos: Vector2, r_px: float) -> int:
	var k: int = _kind_index(kind)
	if k < 0 or _kind_n[k] <= 0:
		return -1
	var best: int = -1
	var bd: float = r_px * r_px
	for i in SP_CAP:
		if s_alive[i] == 0 or s_kind[i] != k or s_st[i] != 0:
			continue
		var dx: float = s_x[i] - pos.x
		var dy: float = s_y[i] - pos.y
		var d2: float = dx * dx + dy * dy
		if d2 <= bd:
			bd = d2
			best = i
	return best


func special_pos(i: int) -> Vector2:
	if i < 0 or i >= SP_CAP:
		return Vector2.ZERO
	return Vector2(s_x[i], s_y[i])


## 적이 먹어 없앤다(보상·신호 없음). 이미 없으면 false.
func take_special(i: int) -> bool:
	if i < 0 or i >= SP_CAP or s_alive[i] == 0:
		return false
	_add_fx(s_x[i], s_y[i] - 6.0, 0)
	_sp_free(i)
	return true


func spawn_coins(pos: Vector2, total: float, n: int, radius_px: float, auto_delay_s: float = -1.0) -> void:
	var cnt: int = maxi(1, n)
	var each: float = floorf(total / float(cnt))
	var auto_tick: int = Game.game_tick + int(auto_delay_s * K.TICK_HZ) if auto_delay_s >= 0.0 else -1
	for k in cnt:
		var a: float = TAU * float(k) / float(cnt) + Rng.range_s(&"pickup", -0.25, 0.25)
		var r: float = radius_px * sqrt(Rng.range_s(&"pickup", 0.15, 1.0))
		var v: float = each if k < cnt - 1 else total - each * float(cnt - 1)
		if _sp_add(Pk.YEOPJEON, pos + Vector2(cos(a), sin(a) * 0.7) * r, pos, v, 0.0, 0, auto_tick) < 0:
			_gain_yeopjeon(v, pos)                 # 저장소가 차면 바로 지급


func spawn_neok(pos: Vector2, total: float, n: int) -> void:
	var cnt: int = maxi(1, n)
	var each: float = floorf(total / float(cnt))
	for k in cnt:
		var a: float = TAU * float(k) / float(cnt) + Rng.range_s(&"pickup", -0.3, 0.3)
		var v: float = each if k < cnt - 1 else total - each * float(cnt - 1)
		if _sp_add(Pk.NEOK, pos + Vector2(cos(a), sin(a) * 0.7) * 18.0, pos, v, 0.0, 0, Game.game_tick + 18 + k * 3) < 0:
			_gain_neok(v, pos)


func spawn_box(kind: StringName, pos: Vector2, bonus: float, sub: int = 0) -> int:
	var k: int = _kind_index(kind)
	if k != Pk.BOX_GIL and k != Pk.BOX_NEOK:
		return -1
	return _sp_add(k, pos, pos, bonus, 0.0, sub, -1)


func _gain_yeopjeon(v: float, pos: Vector2) -> void:
	yeopjeon_run += int(v)
	Events.pickup_collected.emit(&"cur_yeopjeon", v, pos)


func _gain_neok(v: float, pos: Vector2) -> void:
	neok_box_run += int(v)
	Game.cur_neok += int(v)
	Events.pickup_collected.emit(&"cur_neok", v, pos)


# ─── 틱 17 ─────────────────────────────────────────────────────────────

func sim_step(dt: float) -> void:
	if Game.player == null:
		return
	var pp: Vector2 = Game.player.global_position
	var mag: float = Game.stat(&"stat_chohon", 2.0) * K.UNIT_PX
	var mag2: float = mag * mag
	var acc: float = _max_spd * dt / _accel
	var vmax: float = _max_spd
	if _pull_t > 0.0:
		_pull_t -= dt
		mag2 = 1.0e12                              # 초혼발: 1.5초 동안 맵 전체 흡인
		vmax = _max_spd * 2.0
	var k: int = 0
	while k < count:
		var i: int = _act[k]
		var dx: float = pp.x - px[i]
		var dy: float = pp.y - py[i]
		var d2: float = dx * dx + dy * dy
		if _mag[i] == 0:
			if d2 > mag2:
				k += 1
				continue
			_magnetize(i)
		_ppx[i] = px[i]
		_ppy[i] = py[i]
		if d2 < 100.0:
			var v: float = val[i]
			if v >= _tier_m:
				_add_fx(pp.x, pp.y - 14.0, 1 if v < _tier_l else 4)
			_free_orb(i)
			Game.add_xp(v)
			continue                               # 같은 k 에 다른 구슬이 들어왔다
		var s: float = minf(vmax, spd[i] + acc)
		spd[i] = s
		var d: float = sqrt(d2)
		var step: float = minf(s * dt, d)
		px[i] += dx / d * step
		py[i] += dy / d * step
		k += 1
	if special_count > 0:
		_sim_specials(dt, pp, mag2, acc, vmax)
	if _pd_count > 0:
		_sim_pending()


func _sim_specials(dt: float, pp: Vector2, mag2: float, acc: float, vmax: float) -> void:
	var gt: int = Game.game_tick
	for i in SP_CAP:
		if s_alive[i] == 0:
			continue
		s_ppx[i] = s_x[i]
		s_ppy[i] = s_y[i]
		if s_life[i] > 0.0:
			s_life[i] -= dt
			if s_life[i] <= 0.0:
				_sp_free(i)
				continue
		var k: int = s_kind[i]
		var dx: float = pp.x - s_x[i]
		var dy: float = pp.y - s_y[i]
		var d2: float = dx * dx + dy * dy
		if s_st[i] == 1:
			if d2 < 100.0:
				_collect(i, pp)
				continue
			var s: float = minf(vmax, s_spd[i] + acc)
			s_spd[i] = s
			var d: float = sqrt(d2)
			var step: float = minf(s * dt, d)
			s_x[i] += dx / d * step
			s_y[i] += dy / d * step
			continue
		if gt - s_born[i] < POP_TICKS:
			continue                               # 튀어 오르는 중에는 줍지 못한다
		if k == Pk.YEOPJEON or k == Pk.NEOK:
			if d2 <= mag2 or (s_auto[i] >= 0 and gt >= s_auto[i]):
				s_st[i] = 1
				s_spd[i] = -_max_spd * 0.3
			continue
		var pr: float = 22.0 if (k == Pk.BOX_GIL or k == Pk.BOX_NEOK) else 16.0
		if d2 <= pr * pr:
			_collect(i, pp)


func _collect(i: int, pp: Vector2) -> void:
	var k: int = s_kind[i]
	var pos: Vector2 = Vector2(s_x[i], s_y[i])
	var v: float = s_val[i]
	var sub: int = s_sub[i]
	_sp_free(i)
	var pl: Node2D = Game.player
	var hit: Variant = pl.get("hit") if pl != null else null
	match k:
		Pk.YEOPJEON:
			_add_fx(pp.x, pp.y - 14.0, 1)
			_gain_yeopjeon(v, pos)
			return
		Pk.NEOK:
			_add_fx(pp.x, pp.y - 14.0, 2)
			_gain_neok(v, pos)
			return
		Pk.BOX_GIL, Pk.BOX_NEOK:
			_open_box(k, pos, v, sub)
			return
		Pk.GONGMUL:
			if hit is Object and (hit as Object).has_method("heal"):
				(hit as Object).call("heal", Game.hp_max * _heal_gongmul)
			_add_fx(pos.x, pos.y - 6.0, 1)
		Pk.HOSINBU:
			# 호신부: 피격 1회 방어막(최대 2겹). 방어막 단계는 combat(player_hit) 소유 — add_hosinbu 가 있으면 그것을 쓴다.
			if hit is Object and (hit as Object).has_method("add_hosinbu"):
				(hit as Object).call("add_hosinbu", 1)
			elif hit is Object:
				# TODO(combat): PlayerHit.add_hosinbu(n) 구현 전 임시 — 짧은 무적으로 대신한다
				(hit as Object).set("iframe_left", maxf(float((hit as Object).get("iframe_left")), 2.0))
			_add_fx(pos.x, pos.y - 6.0, 4)
		Pk.CHOHON:
			_pull_t = _pull_time
			pull_all()
			_add_fx(pos.x, pos.y - 6.0, 3)
		Pk.MYEONGJUL:
			# TODO(core): 명줄(부활 횟수) 상태가 Game 에 생기면 +1 로 교체. 지금은 정기를 가득 채운다.
			if hit is Object and (hit as Object).has_method("add_myeongjul"):
				(hit as Object).call("add_myeongjul", 1)
			elif hit is Object and (hit as Object).has_method("heal"):
				(hit as Object).call("heal", Game.hp_max)
			_add_fx(pos.x, pos.y - 6.0, 4)
		Pk.YEOU:
			_add_fx(pos.x, pos.y - 6.0, 3)
		_:
			_add_fx(pos.x, pos.y - 6.0, 0)         # 가짜 엽전·가짜 공물: 결과(영가 홀림)는 신호 구독자(haewon)
	Events.pickup_collected.emit(KIND_IDS[k], v, pos)


## 상자 개봉(02 18.1): 등급 판정 → 내용 적용(WeaponManager.open_box) → 개봉 연출 + 0.5초 뒤 확정 부가 재화 분출.
## 결과는 연출 전에 확정한다(chest.result_rolled_before_fx). 정지 화면·점복 연출은 ui 가 Events.box_opened 로 덧붙인다.
func _open_box(k: int, pos: Vector2, bonus: float, sub: int) -> void:
	var gil: bool = k == Pk.BOX_GIL
	var key: String = "chest.box_gilhyung." if gil else "chest.box_neokham."
	var j: float = clampf(Game.stat(&"stat_jeomgwae", 100.0) / 100.0, 0.5, 3.0)
	var p_dae: float = minf(Data.num("combat_core", key + "cap.jg_daegil", 0.25), Data.num("combat_core", key + "base.jg_daegil", 0.03) * j)
	var p_jung: float = minf(Data.num("combat_core", key + "cap.jg_junggil", 0.4), Data.num("combat_core", key + "base.jg_junggil", 0.12) * j)
	var r: float = Rng.randf_s(&"chest")
	var grade: int = 2 if r < p_dae else (1 if r < p_dae + p_jung else 0)
	if sub >= 2:
		grade = maxi(grade, 1)                     # 중간보스·보스 상자: 최소 중길
	if sub == 1 and gil:
		grade = mini(2, grade + 1)                 # 원귀 퇴치 상자: 등급 +1 확정(캐논 3.2.6)
	var items: int = int(Data.num("combat_core", "chest.rewards." + ["jg_sogil", "jg_junggil", "jg_daegil"][grade], float(1 + grade * 2)))
	var results: Array = []
	var wm: Variant = Game.weapons
	if wm is Object and (wm as Object).has_method("open_box"):
		var rv: Variant = (wm as Object).call("open_box", KIND_IDS[k], items)
		if rv is Array:
			results = rv
	var extra: float = 0.0
	for it: Variant in results:
		if it is Dictionary and String((it as Dictionary).get("kind", "")) == "yeopjeon":
			extra += _fallback_coin
	boxes_opened += 1
	var vp: Variant = Game.vfx
	if vp is Object and (vp as Object).has_method("play"):
		(vp as Object).call("play", &"vfx_box_gilhyung_open" if gil else &"vfx_box_neokham_open", pos)
	Juice.screen_shake(0.1 + 0.06 * float(grade))
	if _pd_count < PEND_CAP:
		var q: int = _pd_count
		_pd_tick[q] = Game.game_tick + 30
		_pd_kind[q] = Pk.YEOPJEON if gil else Pk.NEOK
		_pd_x[q] = pos.x
		_pd_y[q] = pos.y - 10.0
		_pd_amt[q] = bonus + (extra if gil else 0.0)
		_pd_n[q] = _box_coins if gil else 5
		_pd_count += 1
		if not gil and extra > 0.0:
			_gain_yeopjeon(extra, pos)
	else:
		if gil:
			_gain_yeopjeon(bonus + extra, pos)
		else:
			_gain_neok(bonus, pos)
	Events.pickup_collected.emit(KIND_IDS[k], float(grade), pos)
	Events.box_opened.emit(KIND_IDS[k], grade, results, bonus, pos)


func _sim_pending() -> void:
	var gt: int = Game.game_tick
	var q: int = 0
	while q < _pd_count:
		if gt < _pd_tick[q]:
			q += 1
			continue
		var p: Vector2 = Vector2(_pd_x[q], _pd_y[q])
		if _pd_kind[q] == Pk.YEOPJEON:
			spawn_coins(p, _pd_amt[q], _pd_n[q], 30.0, 0.45)
		else:
			spawn_neok(p, _pd_amt[q], _pd_n[q])
		_pd_count -= 1
		_pd_tick[q] = _pd_tick[_pd_count]
		_pd_kind[q] = _pd_kind[_pd_count]
		_pd_x[q] = _pd_x[_pd_count]
		_pd_y[q] = _pd_y[_pd_count]
		_pd_amt[q] = _pd_amt[_pd_count]
		_pd_n[q] = _pd_n[_pd_count]


func _add_fx(x: float, y: float, c: int) -> void:
	_fx_x[_fx_head] = x
	_fx_y[_fx_head] = y
	_fx_t[_fx_head] = Game.game_tick
	_fx_c[_fx_head] = c
	_fx_head = (_fx_head + 1) % FX_CAP


# ─── 그리기(렌더 프레임) ───────────────────────────────────────────────

func _process(_delta: float) -> void:
	var at: float = Game.anim_time()
	var tick: int = Game.anim_tick_cur
	# 히트스톱·일시정지 프레임(시뮬이 안 돈 프레임)은 보간하지 않는다
	var alpha: float = Game.render_alpha if Game.anim_tick_cur != Game.anim_tick_prev else 1.0
	var n0: int = 0
	var n1: int = 0
	var n2: int = 0
	var mm0: MultiMesh = _mm[0].multimesh
	var mm1: MultiMesh = _mm[1].multimesh
	var mm2: MultiMesh = _mm[2].multimesh
	var fbase: float = at * 8.0
	for k in count:
		var i: int = _act[k]
		var x: float = px[i]
		var y: float = py[i]
		if _mag[i] != 0:
			x = lerpf(_ppx[i], x, alpha)
			y = lerpf(_ppy[i], y, alpha)
		else:
			var age: int = tick - _born[i]
			if age < POP_TICKS:
				# 드롭 튐: 처치 지점 → 제자리, 포물선 6px(렌더 전용)
				var t: float = clampf(float(age) / float(POP_TICKS), 0.0, 1.0)
				var e: float = 1.0 - (1.0 - t) * (1.0 - t)
				x = lerpf(_ox[i], x, e)
				y = lerpf(_oy[i], y, e) - sin(t * PI) * 6.0
			elif ((tick / 24 + i) & 1) == 0:
				y -= 1.0                               # 숨쉬기 1px
		var v: float = val[i]
		var fl: float = 1.0 if tick - _flash[i] < 3 else 0.0
		var tf: Transform2D = Transform2D(0.0, Vector2(floorf(x + 0.5), floorf(y + 0.5)))
		if v < _tier_m:
			mm0.set_instance_transform_2d(n0, tf)
			mm0.set_instance_custom_data(n0, Color(float(int(fbase + float(i) * 0.37) % _mm_frames[0]), 0.0, fl, 0.0))
			n0 += 1
		elif v < _tier_l:
			mm1.set_instance_transform_2d(n1, tf)
			mm1.set_instance_custom_data(n1, Color(float(int(fbase + float(i) * 0.37) % _mm_frames[1]), 0.0, fl, 0.0))
			n1 += 1
		else:
			mm2.set_instance_transform_2d(n2, tf)
			mm2.set_instance_custom_data(n2, Color(float(int(fbase + float(i) * 0.37) % _mm_frames[2]), 0.0, fl, 0.0))
			n2 += 1
	mm0.visible_instance_count = n0
	mm1.visible_instance_count = n1
	mm2.visible_instance_count = n2
	_items.queue_redraw()


func _draw_items() -> void:
	var tick: int = Game.anim_tick_cur
	var alpha: float = Game.render_alpha if Game.anim_tick_cur != Game.anim_tick_prev else 1.0
	var at: float = Game.anim_time()
	if special_count > 0:
		for i in SP_CAP:
			if s_alive[i] == 0:
				continue
			var k: int = s_kind[i]
			var age: int = tick - s_born[i]
			if s_life[i] > 0.0 and s_life[i] < 2.0 and ((tick / 4) & 1) == 0:
				continue                               # 사라지기 2초 전: 점멸(반투명 없음)
			var x: float = lerpf(s_ppx[i], s_x[i], alpha)
			var y: float = lerpf(s_ppy[i], s_y[i], alpha)
			var lift: float = 0.0
			if s_st[i] == 0:
				if age < POP_TICKS:
					var t: float = clampf(float(age) / float(POP_TICKS), 0.0, 1.0)
					var e: float = 1.0 - (1.0 - t) * (1.0 - t)
					x = lerpf(s_ox[i], x, e)
					y = lerpf(s_oy[i], y, e)
					lift = sin(t * PI) * 10.0
				elif ((tick / 20 + i) & 1) == 0:
					lift = 1.0
			var gx: float = floorf(x + 0.5)
			var gy: float = floorf(y + 0.5)
			match k:
				Pk.BOX_GIL, Pk.BOX_NEOK:
					var fx: Dictionary = _fx_box_g if k == Pk.BOX_GIL else _fx_box_n
					var regs: Array = fx["regions"]
					if regs.size() > 0:
						var piv: Vector2 = fx["pivot"]
						_items.draw_texture_rect_region(fx["texture"], Rect2(Vector2(gx, gy - floorf(lift)) - piv, fx["size"]), regs[0])
					# 손짓: 상자 위 황/백 반짝 1px(주우러 오라는 표시)
					var ph: int = (tick / 6 + i) % 4
					var sc: Color = _FX_COL[1] if k == Pk.BOX_GIL else _FX_COL[2]
					_items.draw_rect(Rect2(gx - 9.0 + float(ph) * 6.0, gy - 24.0 - float(ph & 1) * 2.0, 1.0, 1.0), sc)
					_items.draw_rect(Rect2(gx + 8.0 - float(ph) * 5.0, gy - 20.0 - float((ph + 1) & 1) * 3.0, 1.0, 1.0), sc)
				Pk.YEOPJEON, Pk.GAJJA_YEOP, Pk.NEOK:
					var fx2: Dictionary = _fx_neok if k == Pk.NEOK else _fx_coin
					var regs2: Array = fx2["regions"]
					if regs2.size() > 0:
						# 가짜 엽전: 회전이 진짜의 절반 속도(07 7.2 읽기 단서 ②)
						var rate: float = float(fx2["fps"]) * (0.5 if k == Pk.GAJJA_YEOP else 1.0)
						var f: int = int(at * rate + float(i) * 0.7) % regs2.size()
						if s_st[i] == 0 and k != Pk.NEOK:
							_items.draw_rect(Rect2(gx - 3.0, gy + 3.0, 6.0, 2.0), _C_SHADOW)
						_items.draw_texture_rect_region(fx2["texture"], Rect2(Vector2(gx, gy - floorf(lift)) - (fx2["pivot"] as Vector2), fx2["size"]), regs2[f])
				_:
					var tex: Texture2D = _icons[k]
					if tex != null:
						_items.draw_rect(Rect2(gx - 5.0, gy - 1.0, 10.0, 2.0), _C_SHADOW)
						if k == Pk.GAJJA_GONG:
							# 가짜 공물: 그림자 끝 여우 꼬리(07 7.3 읽기 단서)
							_items.draw_rect(Rect2(gx + 5.0, gy - 2.0, 2.0, 1.0), _C_SHADOW)
							_items.draw_rect(Rect2(gx + 7.0, gy - 3.0, 1.0, 1.0), _C_SHADOW)
						_items.draw_texture(tex, Vector2(gx - 8.0, gy - 14.0 - floorf(lift)))
	# 획득 반짝: 4방향 1px 이 9틱 동안 퍼진다(색 단계만)
	for q in FX_CAP:
		var e2: int = tick - _fx_t[q]
		if e2 < 0 or e2 >= FX_TICKS:
			continue
		var c: Color = _FX_COL[_fx_c[q]]
		var o: Vector2 = Vector2(floorf(_fx_x[q] + 0.5), floorf(_fx_y[q] + 0.5))
		var r2: float = float(2 + e2 / 2)
		var sz: Vector2 = Vector2(2, 2) if e2 < 4 else Vector2(1, 1)
		_items.draw_rect(Rect2(o + Vector2(-r2, -r2), sz), c)
		_items.draw_rect(Rect2(o + Vector2(r2, -r2), sz), c)
		_items.draw_rect(Rect2(o + Vector2(-r2, r2), sz), c)
		_items.draw_rect(Rect2(o + Vector2(r2, r2), sz), c)
		if e2 < 3:
			_items.draw_rect(Rect2(o + Vector2(-1, -1), Vector2(3, 3)), c)
