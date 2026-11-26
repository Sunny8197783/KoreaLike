extends Control
## 런 HUD(640×360 기준, 앵커는 크기 따라감). 소유: ui.
## 레이아웃: data/ui_hud_layout.json · design/11 §5 (v0.10 '상단 띠 + 발밑' 2 시선 지점).
##  상단: 원혼 구슬 바(+Lv) / 좌: 신통 인장·무구 6칸·정기 바 / 가운데: 시계·거리·시련 칩·의례 슬롯(굿판의 기운 ↔ 시련 게이지 ↔ 보스 한)
##        / 우: 강신 4칸 / 공수 레인(y64) / 아래: 연속 굿 칩·추임새 슬램.
##  발밑 호(신명·영가)·정기 바·풀릴 기색 화살표·고리 예상선·힌트 줄은 자식 Guide(ui/guide.gd)가 그린다.
## 갱신: 신호로 상태 갱신, 그리기만 매 프레임(문자열은 값이 바뀔 때만 만든다 — 매 프레임 할당 없음).
## 블록(Block)마다 modulate 로 근접 투명화(5.5: 플레이어가 32 lpx 안이면 35%).

const GUIDE_SCRIPT: Script = preload("res://ui/guide.gd")
const LEDGER_SCRIPT: Script = preload("res://ui/run_ledger.gd")

const B_XP: int = 0
const B_TL: int = 1
const B_TC: int = 2
const B_TR: int = 3
const B_MISC: int = 4
const B_GIUN: int = 5

## 그리기 블록: 부모 HUD 의 _draw_block 으로 위임(블록별 투명도)
class Block extends Control:
	var draw_cb: Callable
	var which: int = 0

	func _draw() -> void:
		draw_cb.call(self, which)


var _blocks: Array[Control] = []
var _alpha: PackedFloat32Array = PackedFloat32Array([1, 1, 1, 1, 1])
var guide: Control = null
var ledger: Node = null

# 폰트
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_tiny: Font
var _f_brush: Font
var _paper: Texture2D
var _seal_glyph: String = ""

# 원혼 바·레벨
var _xp_show: float = 0.0
var _lv_s: String = "Lv 1"
var _lv_pop: float = 0.0
# 시계
var _clock_s: String = "00:00"
var _clock_last: int = -1
var _boss_time: float = 1200.0
# 박
var _beat_k: float = 0.0
var _beat_down: bool = false
# 거리
var _geori_name: String = ""
var _geori_jd: String = ""
var _geori_line: String = ""
var _geori_t: float = 99.0          # 전환 뒤 실시간 경과
var _geori_first: bool = true
# 시련
var _trial_times: PackedFloat32Array = PackedFloat32Array()
var _trial_dur: float = 30.0
var _trial_active: bool = false
var _trial_slot: int = 0
var _trial_name: String = ""
var _trial_head: String = ""
var _trial_t0: float = 0.0
var _wieom: float = 0.0
var _gaho: float = 0.0
var _trial_msg: String = ""
var _trial_msg_t: float = 0.0
var _chip_s: String = ""
var _chip_sec: int = -1
# 강신 4칸
var _gs_glyph: PackedStringArray = PackedStringArray(["", "", "", ""])
var _gs_face: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])   # 0 빈칸 1 위엄 2 가호
var _gs_half: PackedByteArray = PackedByteArray([0, 0, 0, 0])
var _gs_pop: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
# 굿판의 기운(넋 비율 N, 살기 트랙)
var _n_show: float = 0.5
var _h_s: String = "0"
var _t_s: String = "0"
var _h_last: int = -1
var _t_last: int = -1
var _knot_crossed: PackedByteArray = PackedByteArray([0, 0, 0])
var _knot_flash: PackedFloat32Array = PackedFloat32Array([0, 0, 0])
var _giun_flash: float = 0.0
var _giun_vis: float = 1.0           # 첫 판은 길잡이가 설명할 때(2분·살기 20) 드러낸다(unlock_table run1 hud_hidden)
var _giun_on: bool = true
var _sal_big: float = 0.0            # 살 안내 중 살기 트랙 4px
# 보스
var _boss_handle: int = -1
var _boss_name: String = ""
# 중간보스(wave_event midboss: handle·limit_sec) — 의례 슬롯에 이름·한 바·남은 시간
var _mb_handle: int = -1
var _mb_name: String = ""
var _mb_t0: float = 0.0
var _mb_limit: float = 90.0
# 무구 칸: 진화 준비(Lv8 + 짝) 맥박 · 진화/결합 표식
var _slot_evo: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0, 0])
var _evo_poll: float = 0.0
# 무구 칸
var _icons: Dictionary = {}          # weapon_id -> Texture2D(16)
var _slot_flash: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _slot_new: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0])
# 정기
var _hp_show: float = 1.0
var _hp_trail: float = 1.0
var _hp_hit: float = 0.0
var _hp_s: String = ""
var _hp_last: int = -1
# 공수·물결 예고 레인
var _lane_text: String = ""
var _lane_t: float = 0.0
var _lane_gold: bool = true
var _lane_queue: PackedStringArray = PackedStringArray()
var _lane_qgold: PackedByteArray = PackedByteArray()
var _lane_qdur: PackedFloat32Array = PackedFloat32Array()
# 가장자리 레인(왼쪽 위, 무구 칸 아래): 맛보기 공수(prio<2)·길흉 상자 결과(design/18 §2.1). 화면 가운데를 비운다.
var _edge_text: PackedStringArray = PackedStringArray()   # 줄(최대 2)
var _edge_t: float = 0.0
var _edge_gold: bool = false
var _edge_next: String = ""
var _edge_next_gold: bool = false
## 가시성 측정(tests/vis_probe.gd): 이번 프레임에 그린 화면 글 사각형. 키 → [Rect2(640×360 기준), 그린 프레임].
var vis_rects: Dictionary = {}
const LANE_SEC: float = 2.0       # 위 레인 수명 2.5→2.0(design/18 §2.3)
const LANE_QUEUE: int = 1         # 대기열 2→1
const EDGE_SEC: float = 2.0
const EDGE_W: float = 236.0       # 가운데 의례 슬롯(cx−60) 앞에서 멈춘다
# 연속 굿
var _streak: PackedInt32Array = PackedInt32Array([0, 0])          # 0 해원 1 퇴치
var _streak_last: PackedFloat32Array = PackedFloat32Array([-10, -10])
var _streak_s: PackedStringArray = PackedStringArray(["", ""])
var _streak_vis: PackedFloat32Array = PackedFloat32Array([0, 0])
var _streak_stage: PackedInt32Array = PackedInt32Array([0, 0])
var _slam_text: String = ""
var _slam_t: float = 0.0
var _slam_col: Color = UiKit.HANJI
var _slam_last: float = -100.0
# 거리 슬램
var _gslam_t: float = 0.0
# 신명 오름
var _oreum: bool = false
var _oreum_t: float = 0.0
# 디버그 줄(F10)
var _debug_on: bool = false
var _debug_s: String = ""
var _debug_tick: int = 0

const COMBO_THR: Array[int] = [20, 40, 80, 150]
const BOX_GRADE: Array[String] = ["소길", "중길", "대길"]
const OBANG: Array[Color] = [Color("2a5caa"), Color("c8322d"), Color("e8b931"), Color("e9dcc0"), Color("1a1a1a")]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.setup_fonts()
	UiSettings.apply()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")
	var hj: String = UiKit.char_hanja(String(Game.char_id))
	_seal_glyph = hj.left(1) if hj != "" else UiKit.char_name(String(Game.char_id)).left(1)
	for i in 6:
		var b: Block = Block.new()
		b.draw_cb = _draw_block
		b.which = i
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(b)
		_blocks.append(b)
	guide = GUIDE_SCRIPT.new() as Control
	guide.name = "Guide"
	add_child(guide)
	move_child(guide, 0)          # 월드 오버레이는 HUD 블록 아래
	ledger = LEDGER_SCRIPT.new() as Node
	ledger.name = "RunLedger"
	add_child(ledger)
	_boss_time = Data.num("waves_stage1", "boss_time_sec", 1200.0)
	_trial_dur = Data.num("deities", "constants.trial_duration_s", 30.0)
	var tr: Variant = Data.get_value("waves_stage1", "trials", [])
	if tr is Array:
		for e: Variant in tr:
			if e is Dictionary and String((e as Dictionary).get("type", "trial")) == "trial":
				_trial_times.append(float((e as Dictionary).get("time_sec", 0)))
	Events.level_up.connect(_on_level_up)
	Events.geori_changed.connect(_on_geori)
	Events.beat.connect(_on_beat)
	Events.trial_warn.connect(_on_trial_warn)
	Events.trial_start.connect(_on_trial_start)
	Events.trial_gauge_changed.connect(_on_trial_gauge)
	Events.trial_end.connect(_on_trial_end)
	Events.trial_resolved.connect(_on_trial_resolved)
	Events.wongwi_return.connect(_on_wongwi)
	Events.sinmyeong_oreum.connect(_on_oreum)
	Events.enemy_killed.connect(_on_killed)
	Events.weapon_added.connect(_on_weapon_added)
	Events.weapon_leveled.connect(_on_weapon_leveled)
	Events.weapon_evolved.connect(_on_weapon_evolved)
	Events.player_damaged.connect(_on_player_damaged)
	Events.gongsu_spoken.connect(_on_gongsu)
	Events.box_opened.connect(_on_box_opened)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.boss_resolved.connect(func(_h: int, _k: StringName, _n: float) -> void: _boss_handle = -1)
	Events.wave_event.connect(_on_wave_event)
	_on_geori(Beat.geori_id, Beat.bpm, Beat.jangdan)
	_lv_s = "Lv %d" % maxi(1, Game.level)
	# 첫 판(RunLedger 가 위 add_child 에서 이미 ui.runs 를 1 로 올렸다): 굿판의 기운 바는 길잡이가 설명할 때(guide.reveal_giun) 드러낸다
	# 연습 굿판: 기운 바는 '살' 단계에서 디렉터가 reveal_giun() 으로 연다(design/17 §5.1)
	if Game.tutorial_mode or (int(Save.get_value("ui.runs", 0)) <= 1 and UiSettings.guide_on() and not Game.autotest):
		_giun_on = false
		_giun_vis = 0.0


# ─── 이벤트 ─────────────────────────────────────────────────────────────

func _on_level_up(l: int) -> void:
	_lv_s = "Lv %d" % l
	_lv_pop = 0.4
	# 레벨업 고르기 창이 가운데를 쓴다 — 가운데 슬롯 prio 3(거리 카드·붓은 비킨다)
	if Juice.has_method(&"claim_center"):
		Juice.call(&"claim_center", &"level_up", 3, 0.6)


func _on_geori(id: StringName, _bpm: float, jangdan: StringName) -> void:
	var g: Dictionary = UiKit.geori_def(id)
	_geori_name = String(g.get("name_ko", String(id).trim_prefix("geori_")))
	_geori_jd = String(g.get("jangdan_ko", String(jangdan)))
	_geori_line = "%s · %s" % [_geori_name, _geori_jd]
	_geori_t = 0.0
	# 큰 거리 제목 카드는 waves(wave_presenter)가 그린다 — HUD 는 시계 아래 작은 줄만(중복 금지)
	_gslam_t = 0.0
	_geori_first = false


func _on_beat(_idx: int, down: bool) -> void:
	_beat_k = 1.0
	_beat_down = down


func _on_trial_warn(_slot: int, _d: StringName, _in_sec: float) -> void:
	_giun_flash = 0.6


func _on_trial_start(slot: int, deity: StringName) -> void:
	_trial_active = true
	_trial_slot = slot
	_trial_name = UiKit.deity_name(String(deity))
	_trial_head = "시련 %d · %s" % [slot, _trial_name]
	_trial_t0 = Game.time_sec()
	_wieom = 0.0
	_gaho = 0.0
	_giun_flash = 0.8


func _on_trial_gauge(_slot: int, w: float, g: float) -> void:
	_wieom = w
	_gaho = g


func _on_trial_end(slot: int, deity: StringName, winner: StringName) -> void:
	_trial_active = false
	if winner == &"wieom":
		_trial_msg = "%s · 위엄으로 실렸다" % UiKit.deity_name(String(deity))
		_set_gangsin(slot, deity, 1, true)
	elif winner == &"gaho":
		_trial_msg = "%s · 가호로 실렸다" % UiKit.deity_name(String(deity))
		_set_gangsin(slot, deity, 2, true)
	else:
		_trial_msg = "시련이 지나갔다"
	_trial_msg_t = 2.5


func _on_trial_resolved(slot: int, deity: StringName, face: StringName, complete: bool) -> void:
	_set_gangsin(slot, deity, 1 if face == &"wieom" else 2, complete)


func _set_gangsin(slot: int, deity: StringName, face: int, complete: bool) -> void:
	var k: int = clampi(slot - 1, 0, 3)
	var d: Dictionary = Data.deity(String(deity))
	var hj: String = String(d.get("hanja", ""))
	var glyph: String = hj.left(1) if hj != "" else UiKit.deity_name(String(deity)).left(1)
	_gs_glyph[k] = glyph
	_gs_face[k] = face
	_gs_half[k] = 0 if complete else 1
	_gs_pop[k] = 0.6


func _on_wongwi(threshold: int) -> void:
	var k: int = clampi(threshold / 25 - 1, 0, 2)
	_knot_crossed[k] = 1
	_knot_flash[k] = 1.2
	_giun_flash = 1.0


func _on_oreum(on: bool) -> void:
	_oreum = on
	_oreum_t = 0.0


func _on_killed(_h: int, _sp: StringName, _pos: Vector2, kind: StringName, _cause: StringName, _tier: StringName) -> void:
	var k: int = 0 if kind == K.KIND_HAEWON else 1
	var now: float = Game.time_sec()
	if now - _streak_last[k] <= 2.0:
		_streak[k] += 1
	else:
		_streak[k] = 1
		_streak_stage[k] = 0
	_streak_last[k] = now
	var n: int = _streak[k]
	if n >= 5:
		_streak_s[k] = ("○ %d" if k == 0 else "◆ %d") % n
	# 추임새 슬램(붓 큰 글자)은 haewon(haewon_system.slam, combat_core.chuimsae)이 그린다 — HUD 는 연속 칩만(중복 금지)


func _on_weapon_added(id: StringName, slot: int) -> void:
	if slot >= 0 and slot < 6:
		_slot_new[slot] = 1.0
	_icon_of(id)


func _on_weapon_leveled(id: StringName, _lv: int) -> void:
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm == null:
		return
	for i in wm.slot_count():
		var w: WeaponBase = wm.weapon_at(i)
		if w != null and w.id == id:
			_slot_flash[i] = 0.6


func _on_weapon_evolved(_from: StringName, to_id: StringName) -> void:
	_icon_of(to_id)


func _on_player_damaged(_amount: float, _src: StringName, _hp: float, _hp_max: float) -> void:
	_hp_hit = 0.35


func _on_gongsu(deity: StringName, trigger: StringName, s: String) -> void:
	# 합일 호명 말은 trial_hud 큰 글자가 이미 말한다 — 위 레인에 되풀이하지 않는다(design/18 §2.3)
	if trigger == &"gs_hapil_word":
		return
	# 신령 공수는 trial_director 의 prio 를 읽는다. 신령 없는 공수(손님 행차·씨름 등 '할 일')는 위 레인.
	var prio: int = 2
	if deity != &"":
		var rr: Node = Game.run_root
		var td: TrialDirector = (rr.get("trials") as TrialDirector) if rr != null else null
		if td != null:
			prio = td.gongsu_prio
	if prio < 2:
		_push_edge("「%s」" % s, false)
		return
	# 위 띠(예고 띠)·시련 안내판이 떠 있으면 버린다 — 위 구역은 한 번에 1개(design/18 §2.1)
	if _trial_panel_on() or _banner_on() or _card_on():
		return
	_push_lane("「%s」" % s, true, LANE_SEC)


## 예고 띠(waves 의 위 띠)가 떠 있는가.
func _banner_on() -> bool:
	var rr: Node = Game.run_root
	var sd: Node = rr.get("spawn") as Node if rr != null else null
	var pr: Node = sd.get("presenter") as Node if sd != null else null
	return pr != null and pr.has_method(&"banner_on") and bool(pr.call(&"banner_on"))


## 거리 카드가 지금 그려지는가(waves).
func _card_on() -> bool:
	var rr: Node = Game.run_root
	var sd: Node = rr.get("spawn") as Node if rr != null else null
	var pr: Node = sd.get("presenter") as Node if sd != null else null
	return pr != null and pr.has_method(&"card_on") and bool(pr.call(&"card_on"))


## 가장자리 레인에 한 줄(최대 2줄로 접음). 떠 있으면 다음 1개만 기다린다.
func _push_edge(s: String, gold: bool) -> void:
	if _edge_t > 0.0:
		_edge_next = s
		_edge_next_gold = gold
		return
	_edge_text = UiKit.wrap(_f_small, UiKit.SZ_SMALL, s, EDGE_W - 8.0, 2) if _f_small != null else PackedStringArray([s])
	_edge_gold = gold
	_edge_t = EDGE_SEC


## 길흉 상자 결과 이름: 패시브는 name_ko(원시 ID 'psv_…' 를 찍지 않는다), 무구는 무구 이름.
func _box_item_name(id: String) -> String:
	var pd: Dictionary = Data.passive(id)
	if not pd.is_empty():
		return String(pd.get("name_ko", id))
	var wn: String = UiKit.weapon_name(id)
	if wn != id:
		return wn
	return id.trim_prefix("psv_").trim_prefix("wpn_")


## 길흉 상자·넋함: 내용은 이미 적용됨 — 공수 레인에 한 줄 알림(예고 띠는 waves 가 그리므로 wave_warn 은 받지 않는다)
func _on_box_opened(_box: StringName, grade: int, results: Array, _bonus: float, _pos: Vector2) -> void:
	var gname: String = BOX_GRADE[clampi(grade, 0, 2)]
	# 같은 이름은 '초혼 적삼 ×3' 으로 합친다(나온 순서 유지, 최대 3가지)
	var names: PackedStringArray = PackedStringArray()
	var counts: PackedInt32Array = PackedInt32Array()
	for r: Variant in results:
		if r is Dictionary:
			var id: String = String((r as Dictionary).get("id", ""))
			if id == "":
				continue
			var nm: String = _box_item_name(id)
			var k: int = names.find(nm)
			if k >= 0:
				counts[k] += 1
			elif names.size() < 3:
				names.append(nm)
				counts.append(1)
	var parts: PackedStringArray = PackedStringArray()
	for i in names.size():
		parts.append(names[i] if counts[i] <= 1 else "%s ×%d" % [names[i], counts[i]])
	var s: String = "길흉 상자 · %s" % gname
	if not parts.is_empty():
		s += " — " + " · ".join(parts)
	# 맛보기 글 → 왼쪽 위 가장자리 레인(design/18 §2.1)
	_push_edge(s, grade >= 2)


func _push_lane(s: String, gold: bool, dur: float = LANE_SEC) -> void:
	if _lane_t > 0.0:
		if _lane_queue.size() < LANE_QUEUE:
			_lane_queue.append(s)
			_lane_qgold.append(1 if gold else 0)
			_lane_qdur.append(dur)
		return
	_lane_text = s
	_lane_gold = gold
	_lane_t = dur


# ─── 길잡이(guide)가 부르는 공개 함수 ───────────────────────────────────

## 공수 레인(y64) 한 줄. gold = 금 테·황 글자
func push_lane(s: String, gold: bool = true, dur: float = LANE_SEC) -> void:
	_push_lane(s, gold, dur)


func flash_giun(sec: float) -> void:
	_giun_flash = maxf(_giun_flash, sec)


## 살 안내: 매듭 셋을 번쩍이고 살기 트랙을 잠시 4px 로
func flash_knots(sec: float) -> void:
	for i in 3:
		_knot_flash[i] = maxf(_knot_flash[i], sec)
	_sal_big = sec
	_giun_flash = maxf(_giun_flash, 0.6)
	reveal_giun()


func reveal_giun() -> void:
	_giun_on = true


## 중간보스: 이름·한 바·남은 시간(의례 슬롯). 보스 > 중간보스 > 시련 > 기운
func _on_wave_event(id: StringName, p: Dictionary) -> void:
	if id != &"midboss":
		return
	_mb_handle = int(p.get("handle", -1))
	_mb_limit = maxf(1.0, float(p.get("limit_sec", 90.0)))
	_mb_t0 = Game.time_sec()
	_mb_name = UiKit.enemy_name(String(p.get("species", "")))


func _on_boss_spawned(handle: int, species: StringName, _form: StringName) -> void:
	_boss_handle = handle
	_boss_name = UiKit.enemy_name(String(species))
	_on_boss_bar_shown()


func _on_boss_bar_shown() -> void:
	_giun_flash = 0.8


func _icon_of(id: StringName) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var t: Texture2D = UiKit.weapon_icon(String(id), true)
	_icons[id] = t
	return t


# ─── 프레임 ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# 시계(1Hz 문자열)
	var ts: int = int(Game.time_sec())
	if ts != _clock_last:
		_clock_last = ts
		_clock_s = "연습" if Game.tutorial_mode else K.fmt_time(float(ts))
		_update_chip(ts)
	# 수치 따라가기(실시간)
	var xk: float = Game.xp / maxf(Game.xp_next, 1.0)
	_xp_show = xk if xk < _xp_show else lerpf(_xp_show, xk, minf(1.0, delta * 12.0))
	var hk: float = Game.hp / maxf(Game.hp_max, 1.0)
	_hp_show = hk
	_hp_trail = hk if hk > _hp_trail else move_toward(_hp_trail, hk, delta * 0.6)
	var hpi: int = int(ceilf(Game.hp))
	if hpi != _hp_last:
		_hp_last = hpi
		_hp_s = "%d" % hpi
	var tot: int = Game.kills_toechi + Game.kills_haewon
	var n_target: float = 0.5 if tot == 0 else float(Game.kills_haewon) / float(tot)
	var emn: EnemyManager = Game.enemies as EnemyManager
	if emn != null and tot > 0:
		n_target = emn.n_ratio()      # 보스 형태(한형 ≥0.55 / 살형 ≤0.45)를 정하는 바로 그 값
	_n_show = lerpf(_n_show, n_target, minf(1.0, delta * 3.0))
	if Game.kills_haewon != _h_last:
		_h_last = Game.kills_haewon
		_h_s = "%d" % _h_last
	if Game.kills_toechi != _t_last:
		_t_last = Game.kills_toechi
		_t_s = "%d" % _t_last
	# 타이머들
	_beat_k = maxf(0.0, _beat_k - delta * 6.0)
	_lv_pop = maxf(0.0, _lv_pop - delta)
	_geori_t += delta
	_gslam_t = maxf(0.0, _gslam_t - delta)
	_giun_flash = maxf(0.0, _giun_flash - delta)
	_hp_hit = maxf(0.0, _hp_hit - delta)
	_trial_msg_t = maxf(0.0, _trial_msg_t - delta)
	_slam_t = maxf(0.0, _slam_t - delta)
	if _oreum:
		_oreum_t += delta
	for i in 6:
		_slot_flash[i] = maxf(0.0, _slot_flash[i] - delta)
		_slot_new[i] = maxf(0.0, _slot_new[i] - delta * 0.5)
	for i in 4:
		_gs_pop[i] = maxf(0.0, _gs_pop[i] - delta)
	for i in 3:
		_knot_flash[i] = maxf(0.0, _knot_flash[i] - delta)
	if _edge_t > 0.0:
		_edge_t -= delta
		if _edge_t <= 0.0 and _edge_next != "":
			var en: String = _edge_next
			_edge_next = ""
			_push_edge(en, _edge_next_gold)
	if _lane_t > 0.0:
		_lane_t -= delta
		if _lane_t <= 0.0 and not _lane_queue.is_empty():
			_lane_text = _lane_queue[0]
			_lane_gold = _lane_qgold[0] != 0
			_lane_t = _lane_qdur[0]
			_lane_queue.remove_at(0)
			_lane_qgold.remove_at(0)
			_lane_qdur.remove_at(0)
	# 중간보스 끝(퇴치·해원·시간 초과로 사라짐)
	if _mb_handle >= 0:
		var em2: EnemyManager = Game.enemies as EnemyManager
		if em2 == null or not em2.is_alive(em2.slot_of(_mb_handle)):
			_mb_handle = -1
	# 굿판의 기운 드러내기(첫 판)
	_giun_vis = move_toward(_giun_vis, 1.0 if _giun_on else 0.0, delta / 0.6)
	_sal_big = maxf(0.0, _sal_big - delta)
	# 진화 준비 칸(1초마다): Lv8 + 짝 패시브 = 정예 상자에서 열린다
	_evo_poll -= delta
	if _evo_poll <= 0.0:
		_evo_poll = 1.0
		var wm: WeaponManager = Game.weapons as WeaponManager
		for i in 6:
			var w: WeaponBase = wm.weapon_at(i) if wm != null and i < wm.slot_count() else null
			_slot_evo[i] = 1 if (w != null and wm.can_evolve(w.id)) else 0
	var now: float = Game.time_sec()
	for k in 2:
		var live: bool = _streak[k] >= 5 and now - _streak_last[k] <= 2.0
		_streak_vis[k] = 1.0 if live else maxf(0.0, _streak_vis[k] - delta * 2.0)
	_update_proximity(delta)
	if _debug_on:
		_debug_tick += 1
		if _debug_tick % 15 == 0:
			var em: EnemyManager = Game.enemies as EnemyManager
			var run: Node = Game.run_root
			_debug_s = "fps %d  적 %d  틱 %.2fms  ×%d%s" % [Engine.get_frames_per_second(), em.active_count if em != null else 0,
				float(run.get("tick_ms_avg")) if run != null else 0.0, Game.sim_speed, "  무적" if Game.debug_invuln else ""]
	for b: Control in _blocks:
		b.queue_redraw()


func _update_chip(ts: int) -> void:
	_chip_s = ""
	if _trial_active or Game.tutorial_mode:
		return   # 연습 굿판: 다음 시련 칩 숨김(시련은 디렉터가 부른다)
	for t: float in _trial_times:
		var left: int = int(t) - ts
		if left > 0 and left <= 60:
			if left != _chip_sec:
				_chip_sec = left
			_chip_s = "시련 %s" % K.fmt_time(float(left))
			return


## 근접 투명화: 플레이어 화면 위치가 블록 사각형 32 lpx 안이면 35%(0.15초)
func _update_proximity(delta: float) -> void:
	var p: Player = Game.player as Player
	if p == null:
		return
	var sp: Vector2 = get_viewport().get_canvas_transform() * Vector2(p.render_pos) - Vector2(0, float(p.cam_lift))
	var w: float = size.x
	var cx: float = roundf(w * 0.5)
	for i in 4:
		var rr: Rect2 = Rect2(0, 0, w, 12)
		if i == 1:
			rr = Rect2(0, 10, 150, 36)
		elif i == 2:
			rr = Rect2(cx - 80, 10, 160, 56)
		elif i == 3:
			rr = Rect2(w - 90, 10, 90, 24)
		var inside: bool = rr.grow(32.0).has_point(sp)
		var target: float = 0.35 if inside else 1.0
		_alpha[i] = move_toward(_alpha[i], target, delta / 0.15 * 0.65)
		_blocks[i].modulate.a = _alpha[i]
	_blocks[B_GIUN].modulate.a = _alpha[B_TC] * _giun_vis


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_F10:
		_debug_on = not _debug_on
		_debug_s = ""


# ─── 그리기 ─────────────────────────────────────────────────────────────

func _draw_block(ci: Control, which: int) -> void:
	match which:
		B_XP:
			_draw_xp(ci)
		B_TL:
			_draw_tl(ci)
		B_TC:
			_draw_tc(ci)
		B_TR:
			_draw_tr(ci)
		B_MISC:
			_draw_misc(ci)
		B_GIUN:
			_draw_giun(ci, roundf(size.x * 0.5))


func _draw_xp(ci: Control) -> void:
	var w: float = size.x
	var r: Rect2 = Rect2(8, 4, w - 16 - 34, 5)
	var full: bool = _xp_show >= 0.9
	var fill: Color = UiKit.HANJI
	if full and fposmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5:
		fill = UiKit.HWANG_HI
	UiKit.draw_bar(ci, r, _xp_show, fill, UiKit.MEOK_1, UiKit.HANJI_5)
	# 4분할 눈금
	for i in range(1, 4):
		var x: float = roundf(r.position.x + r.size.x * float(i) / 4.0)
		ci.draw_rect(Rect2(x, r.position.y + 1.0, 1.0, r.size.y - 1.0), Color(UiKit.MEOK, 0.5))
	var lv_col: Color = UiKit.HWANG_HI if _lv_pop > 0.0 else UiKit.HANJI
	var ly: float = 11.0 - (2.0 if _lv_pop > 0.25 else 0.0)
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(w - 8, ly), _lv_s, lv_col, 2)


func _draw_tl(ci: Control) -> void:
	# 신통 인장(무당 표지): 붉은 인장 + 무당 한자 첫 글자
	var seal: Rect2 = Rect2(8, 14, 14, 14)
	ci.draw_rect(seal.grow(1.0), UiKit.MEOK)
	ci.draw_rect(seal, UiKit.JEOK)
	ci.draw_rect(seal.grow(-1.0), UiKit.HANJI_UI, false, 1.0)
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(15, 25), _seal_glyph, UiKit.HANJI_UI, 1, false)
	# 무구 6칸
	var wm: WeaponManager = Game.weapons as WeaponManager
	for i in 6:
		var r: Rect2 = Rect2(26 + i * 20, 13, 18, 18)
		var w: WeaponBase = wm.weapon_at(i) if wm != null and i < wm.slot_count() else null
		_draw_weapon_slot(ci, r, w, i)
	# 정기 바(좌상단 코너): 한지 채움, 피격 시 적 밝음, 30% 이하 맥박
	var hr: Rect2 = Rect2(26, 37, 116, 4)
	var low: bool = _hp_show <= 0.3
	var pulse: bool = low and fposmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4
	ci.draw_rect(hr.grow(1.0), UiKit.MEOK)
	ci.draw_rect(hr, UiKit.MEOK_2)
	var tw: float = roundf(hr.size.x * clampf(_hp_trail, 0.0, 1.0))
	if tw > 0.0:
		ci.draw_rect(Rect2(hr.position, Vector2(tw, hr.size.y)), UiKit.JEOK_DK)
	var fw: float = roundf(hr.size.x * clampf(_hp_show, 0.0, 1.0))
	var hcol: Color = UiKit.JEOK_HI if (_hp_hit > 0.0 or pulse) else (UiKit.JEOK if low else UiKit.HANJI)
	if fw > 0.0:
		ci.draw_rect(Rect2(hr.position, Vector2(fw, hr.size.y)), hcol)
		ci.draw_rect(Rect2(hr.position, Vector2(fw, 1.0)), hcol.lightened(0.3))
	ci.draw_rect(hr.grow(1.0), UiKit.HANJI_5, false, 1.0)
	# 정기 표지(작은 붉은 마름모) + 숫자
	UiKit.draw_diamond(ci, Vector2(15, 39), 3.0, UiKit.JEOK_HI if pulse else UiKit.JEOK)
	UiKit.text(ci, _f_tiny, UiKit.SZ_TINY, Vector2(hr.end.x + 4.0, 42), _hp_s, UiKit.HANJI if not low else UiKit.JEOK_HI)


func _draw_weapon_slot(ci: Control, r: Rect2, w: WeaponBase, i: int) -> void:
	if w == null:
		# 빈칸: 점선 테
		ci.draw_rect(r, Color(UiKit.MEOK_1, 0.55))
		for k in range(0, int(r.size.x), 3):
			ci.draw_rect(Rect2(r.position.x + k, r.position.y, 1, 1), UiKit.MEOK_5)
			ci.draw_rect(Rect2(r.position.x + k, r.end.y - 1.0, 1, 1), UiKit.MEOK_5)
			ci.draw_rect(Rect2(r.position.x, r.position.y + k, 1, 1), UiKit.MEOK_5)
			ci.draw_rect(Rect2(r.end.x - 1.0, r.position.y + k, 1, 1), UiKit.MEOK_5)
		return
	var white: bool = w.is_white()
	var flash: float = _slot_flash[i]
	var border: Color = UiKit.HANJI_3 if white else UiKit.JEOK
	if flash > 0.0 and fposmod(flash, 0.2) > 0.1:
		border = UiKit.HWANG_HI
	ci.draw_rect(r.grow(1.0), UiKit.MEOK)
	ci.draw_rect(r, Color(UiKit.MEOK_2, 0.92))
	if white:
		# 둥근 테: 모서리 1px 깎기
		ci.draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, 1), border)
		ci.draw_rect(Rect2(r.position.x + 1, r.end.y - 1, r.size.x - 2, 1), border)
		ci.draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 2), border)
		ci.draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2), border)
	else:
		ci.draw_rect(r, border, false, 1.0)
		UiKit.draw_diamond(ci, r.position + Vector2(0.5, 0.5), 2.0, border)
	var t: Texture2D = _icons.get(w.id, null)
	if t == null:
		t = _icon_of(w.id)
	if t != null:
		ci.draw_texture(t, r.position + Vector2(1, 1))
	else:
		UiKit.draw_glyph_medallion(ci, r.grow(-1.0), String(w.id), white, _f_small)
	# 진화·결합 무구: 오른쪽 위 2px 금 모서리
	var sid: String = String(w.id)
	if sid.begins_with("evo_") or sid.begins_with("union_"):
		ci.draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3, 1), UiKit.HWANG_HI)
		ci.draw_rect(Rect2(r.end.x - 1.0, r.position.y, 1, 3), UiKit.HWANG_HI)
		ci.draw_rect(Rect2(r.end.x - 2.0, r.position.y + 1.0, 1, 1), UiKit.HWANG)
	# 진화 준비(Lv8 + 짝): 황 테 맥박 — 정예 상자를 열면 진화
	if _slot_evo[i] != 0 and _beat_k > 0.3:
		ci.draw_rect(r.grow(1.0), Color(UiKit.HWANG_HI, _beat_k), false, 1.0)
	# 레벨 핍 8(2×1)
	for k in w.max_level:
		var px: float = r.position.x + 1.0 + float(k) * 2.0
		ci.draw_rect(Rect2(px, r.end.y + 2.0, 1, 1), UiKit.HWANG if k < w.level else UiKit.MEOK_4)
	if _slot_new[i] > 0.0:
		var a: float = _slot_new[i]
		ci.draw_rect(r.grow(2.0), Color(UiKit.HWANG, a), false, 1.0)


func _draw_tc(ci: Control) -> void:
	var cx: float = roundf(size.x * 0.5)
	# 시계: 보스 시각 이후 먹 반전, 시련 10초 전 황
	var t: float = Game.time_sec()
	var col: Color = UiKit.HANJI
	var near_trial: bool = false
	for tt: float in _trial_times:
		if tt - t > 0.0 and tt - t <= 10.0:
			near_trial = true
	if Game.tutorial_mode:
		near_trial = false
	if near_trial:
		col = UiKit.HWANG_HI
	# 중간보스 마지막 15초: 시계 황(깜빡)
	if _mb_handle >= 0 and _boss_handle < 0:
		var mleft: float = _mb_limit - (t - _mb_t0)
		if mleft <= 15.0:
			col = UiKit.HWANG_HI if fposmod(t, 0.5) < 0.3 else UiKit.HWANG
	if t >= _boss_time:
		var bw: float = 40.0
		ci.draw_rect(Rect2(cx - bw * 0.5, 13, bw, 13), UiKit.HANJI)
		UiKit.text(ci, _f_bold, UiKit.SZ_BODY, Vector2(cx, 24), _clock_s, UiKit.MEOK, 1, false)
	else:
		UiKit.text(ci, _f_bold, UiKit.SZ_BODY, Vector2(cx, 24), _clock_s, col, 1)
	# 박 징 표지(시계 양옆 작은 마름모, 박마다 밝아짐 · 박 머리 황)
	var bc: Color = UiKit.HWANG_HI if _beat_down else UiKit.HANJI
	var ba: float = 0.25 + 0.75 * _beat_k
	UiKit.draw_diamond(ci, Vector2(cx - 26, 19), 2.0, Color(bc, ba))
	UiKit.draw_diamond(ci, Vector2(cx + 25, 19), 2.0, Color(bc, ba))
	# 거리 라벨(전환 뒤 8초, 마지막 1초 페이드)
	# 시련·보스 중에는 그 제목이 같은 줄(y=37)을 쓰므로 거리 줄을 그리지 않는다(겹침 방지, core 통합)
	# 시련 안내판(deities, 예고~여운)이 떠 있는 동안에도 거리 줄은 쉰다 — 위쪽 글줄은 한 번에 하나(시련 칩·제목이 말한다)
	if _geori_t < 8.0 and _gslam_t <= 0.0 and not _trial_active and not _trial_panel_on() and _boss_handle < 0 and _mb_handle < 0:
		var a: float = clampf(8.0 - _geori_t, 0.0, 1.0)
		UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx, 36), _geori_line, Color(UiKit.HANJI_2, a), 1)
	# 다음 시련 칩(≤60초)
	elif _chip_s != "" and _mb_handle < 0 and not _trial_panel_on():   # 예고 중엔 안내판이 '강림 n' 을 센다
		var cw: float = 62.0
		var cr: Rect2 = Rect2(cx - cw * 0.5, 27, cw, 12)
		UiKit.draw_meok_panel(ci, cr, 0.85, false, UiKit.HWANG_DK)
		UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx, 37), _chip_s, UiKit.HWANG_HI, 1)
	# 의례 슬롯(y=46): 보스 > 시련 > 굿판의 기운
	if _boss_handle >= 0:
		_draw_boss(ci, cx)
	elif _mb_handle >= 0:
		_draw_midboss(ci, cx)
	elif _trial_active:
		_draw_trial(ci, cx)
	# 굿판의 기운은 B_GIUN 블록이 그린다
	# 시련 결과 큰 글자(면 이름·빙의)는 deities(trial_hud)가 그린다 — HUD 는 강신 칸 팝만(겹침 금지)


## deities 시련 안내판이 화면 위쪽을 쓰는 단계(예고·강림·확인·정리·시련·해결·여운)
func _trial_panel_on() -> bool:
	var rr: Node = Game.run_root
	var td: TrialDirector = (rr.get("trials") as TrialDirector) if rr != null else null
	if td == null:
		return false
	return (td.ph >= TrialDirector.Ph.OMEN and td.ph <= TrialDirector.Ph.RESOLVE) or td.ph == TrialDirector.Ph.AFTERGLOW


func _draw_giun(ci: Control, cx: float) -> void:
	# 별도 블록(B_GIUN): 근접 투명도 × 첫 판 페이드인(_giun_vis)은 modulate 로
	if _giun_vis <= 0.0 or _boss_handle >= 0 or _mb_handle >= 0 or _trial_active:
		return
	var r: Rect2 = Rect2(cx - 60, 46, 120, 6)
	# 위: 넋 비율 N (한지 = 왼쪽부터, 나머지 먹)
	ci.draw_rect(r.grow(1.0), UiKit.MEOK)
	ci.draw_rect(r, UiKit.MEOK_3)
	var fw: float = roundf(r.size.x * clampf(_n_show, 0.0, 1.0))
	if fw > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(fw, r.size.y)), UiKit.HANJI)
		ci.draw_rect(Rect2(r.position, Vector2(fw, 1)), UiKit.HANJI_UI)
	# 45%·55% 눈금 + 가운데 빗금
	var x45: float = roundf(r.position.x + r.size.x * 0.45)
	var x55: float = roundf(r.position.x + r.size.x * 0.55)
	for x in range(int(x45), int(x55) + 1, 2):
		ci.draw_rect(Rect2(x, r.end.y - 2.0, 1, 1), Color(UiKit.MEOK_5, 0.8))
	ci.draw_rect(Rect2(x45, r.position.y - 2.0, 1, r.size.y + 2.0), UiKit.HWANG_DK)
	ci.draw_rect(Rect2(x55, r.position.y - 2.0, 1, r.size.y + 2.0), UiKit.HWANG_DK)
	var fc: Color = UiKit.HWANG_HI if _giun_flash > 0.0 and fposmod(_giun_flash, 0.2) > 0.1 else UiKit.HANJI_5
	ci.draw_rect(r.grow(1.0), fc, false, 1.0)
	# 아래: 살기 트랙(3px) — 살기/100, 매듭 25/50/75
	var sr: Rect2 = Rect2(cx - 60, 54, 120, 4 if _sal_big > 0.0 else 3)
	ci.draw_rect(sr.grow(1.0), UiKit.MEOK)
	ci.draw_rect(sr, UiKit.MEOK_2)
	var sk: float = clampf(Game.salgi / 100.0, 0.0, 1.0)
	var sw: float = roundf(sr.size.x * sk)
	if sw > 0.0:
		ci.draw_rect(Rect2(sr.position, Vector2(sw, sr.size.y)), UiKit.JEOK_DK)
	for i in 3:
		var thr: float = 25.0 * float(i + 1)
		var kx: float = roundf(sr.position.x + sr.size.x * thr / 100.0)
		var c: Vector2 = Vector2(kx, sr.position.y + 1.0)
		var near: bool = _knot_crossed[i] == 0 and Game.salgi >= thr * 0.9
		if near and _beat_k > 0.5:
			c.x += 1.0
		var crossed: bool = _knot_crossed[i] != 0 or Game.salgi >= thr
		ci.draw_rect(Rect2(c - Vector2(2, 2), Vector2(5, 5)), UiKit.MEOK)
		ci.draw_rect(Rect2(c - Vector2(1, 1), Vector2(3, 3)), UiKit.JEOK_DK if crossed else UiKit.HANJI_4)
		if near or _knot_flash[i] > 0.0:
			ci.draw_rect(Rect2(c, Vector2.ONE), UiKit.JEOK_HI)
	# 양 끝 수치(같은 글자 크기 — 동등 표기): 왼쪽 '넋' 해원 ○, 오른쪽 퇴치 ◆ '살'
	UiKit.draw_kind_mark(ci, Vector2(cx - 66, 50), 2.0, true)
	var hw: float = UiKit.text(ci, _f_tiny, UiKit.SZ_TINY, Vector2(cx - 71, 54), _h_s, UiKit.HANJI, 2)
	UiKit.text(ci, _f_tiny, UiKit.SZ_TINY, Vector2(cx - 74.0 - hw, 54), "넋", UiKit.HANJI_3, 2)
	UiKit.draw_kind_mark(ci, Vector2(cx + 65, 50), 2.0, false)
	var tw2: float = UiKit.text(ci, _f_tiny, UiKit.SZ_TINY, Vector2(cx + 70, 54), _t_s, UiKit.JEOK_HI, 0)
	UiKit.text(ci, _f_tiny, UiKit.SZ_TINY, Vector2(cx + 73.0 + tw2, 54), "살", UiKit.JEOK, 0)
	# 신명 오름: 오방색 1px 순환 테
	if _oreum:
		var oc: Color = OBANG[int(_oreum_t * 8.0) % 5]
		ci.draw_rect(Rect2(cx - 62, 44, 124, 15), oc, false, 1.0)


func _draw_trial(ci: Control, cx: float) -> void:
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx, 37), _trial_head, UiKit.HWANG_HI, 1)
	# 위엄(적 ◇) | 가호(한지 ○) 각 56×4
	var wr: Rect2 = Rect2(cx - 60, 46, 56, 5)
	var gr: Rect2 = Rect2(cx + 4, 46, 56, 5)
	UiKit.draw_bar(ci, wr, _wieom, UiKit.JEOK, UiKit.MEOK_1, UiKit.JEOK_DK)
	UiKit.draw_bar(ci, gr, _gaho, UiKit.HANJI, UiKit.MEOK_1, UiKit.HANJI_4)
	UiKit.draw_diamond(ci, Vector2(cx - 66, 48), 3.0, UiKit.JEOK_HI, false)
	ci.draw_arc(Vector2(cx + 66, 48), 3.0, 0.0, TAU, 10, UiKit.HANJI, 1.0)
	# 남은 시간(1px 줄, 30초)
	var left: float = clampf(1.0 - (Game.time_sec() - _trial_t0) / maxf(_trial_dur, 1.0), 0.0, 1.0)
	var lw: float = roundf(120.0 * left)
	ci.draw_rect(Rect2(cx - 60, 54, 120, 1), UiKit.MEOK_3)
	ci.draw_rect(Rect2(cx - 60, 54, lw, 1), UiKit.HWANG)
	# 라벨은 막대 양 끝 바깥(y=64 공수 레인과 겹치지 않게)
	UiKit.text(ci, _f_tiny, UiKit.SZ_TINY, Vector2(cx - 72, 52), "위엄", UiKit.JEOK_HI, 2)
	UiKit.text(ci, _f_tiny, UiKit.SZ_TINY, Vector2(cx + 72, 52), "가호", UiKit.HANJI, 0)


func _draw_boss(ci: Control, cx: float) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null or not em.is_alive(em.slot_of(_boss_handle)):
		_boss_handle = -1
		return
	var s: int = em.slot_of(_boss_handle)
	var k: float = em.han[s] / maxf(em.han_max[s], 1.0)
	_draw_name_plate(ci, cx, _boss_name, UiKit.JEOK_HI)
	UiKit.draw_bar(ci, Rect2(cx - 100, 46, 200, 6), k, UiKit.JEOK, UiKit.MEOK_1, UiKit.JEOK_DK)


## 보스·중간보스 이름: 먹 받침(0.8) + 먹 외곽 — 흰 보스 스프라이트 위에서도 읽히게
func _draw_name_plate(ci: Control, cx: float, nm: String, col: Color) -> void:
	var w: float = _f_small.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
	var pr: Rect2 = Rect2(roundf(cx - w * 0.5) - 6.0, 27, w + 12.0, 13)
	ci.draw_rect(pr, Color(UiKit.MEOK, 0.8))
	ci.draw_rect(Rect2(pr.position.x, pr.end.y - 1.0, pr.size.x, 1), Color(UiKit.JEOK_DK, 0.9))
	UiKit.text_outline(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx, 37), nm, col, 1, 1)


func _draw_midboss(ci: Control, cx: float) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	var s: int = em.slot_of(_mb_handle)
	if s < 0 or not em.is_alive(s):
		return
	var k: float = em.han[s] / maxf(em.han_max[s], 1.0)
	_draw_name_plate(ci, cx, _mb_name, UiKit.HWANG_HI)
	var br: Rect2 = Rect2(cx - 100, 46, 200, 6)
	UiKit.draw_bar(ci, br, k, UiKit.JEOK, UiKit.MEOK_1, UiKit.JEOK_DK)
	# 풀릴 기색 문턱 아래: 바 끝에 백 테 + ○ — '이제 흰 무구로 풀 수 있다'
	if (em.flags[s] & EnemyManager.F_PULLIL) != 0:
		var pulse: float = 0.6 + 0.4 * _beat_k
		ci.draw_rect(br.grow(2.0), Color(UiKit.BAEK, pulse), false, 1.0)
		UiKit.draw_kind_mark(ci, Vector2(br.end.x + 8.0, br.get_center().y), 3.0, true)
	# 남은 시간(1px 줄): 마지막 15초 황 깜빡
	var t: float = Game.time_sec()
	var left: float = clampf(1.0 - (t - _mb_t0) / _mb_limit, 0.0, 1.0)
	var late: bool = (_mb_limit - (t - _mb_t0)) <= 15.0
	var lc: Color = (UiKit.HWANG_HI if fposmod(t, 0.5) < 0.3 else UiKit.HWANG) if late else UiKit.HANJI_3
	ci.draw_rect(Rect2(cx - 100, 55, 200, 1), UiKit.MEOK_3)
	ci.draw_rect(Rect2(cx - 100, 55, roundf(200.0 * left), 1), lc)


func _draw_tr(ci: Control) -> void:
	var w: float = size.x
	# 강신 4칸(우상단): 빈칸 점선 원, 위엄 = 마름모, 가호 = 원. 미완은 테 절반
	for i in 4:
		var c: Vector2 = Vector2(w - 8 - 70 + 8 + i * 18, 22)
		var face: int = _gs_face[i]
		var pop: float = 1.0 + (0.3 if _gs_pop[i] > 0.3 else 0.0)
		if face == 0:
			for k in 8:
				var a: float = TAU * float(k) / 8.0
				ci.draw_rect(Rect2((c + Vector2(cos(a), sin(a)) * 6.0).floor(), Vector2.ONE), UiKit.MEOK_5)
			continue
		var col: Color = UiKit.JEOK_HI if face == 1 else UiKit.HANJI
		if face == 1:
			UiKit.draw_diamond(ci, c, 8.0 * pop, UiKit.MEOK)
			UiKit.draw_diamond(ci, c, 7.0 * pop, UiKit.JEOK_DDK)
			UiKit.draw_diamond(ci, c, 7.0 * pop, col, false)
		else:
			ci.draw_circle(c, 7.0 * pop, UiKit.MEOK)
			ci.draw_circle(c, 6.0 * pop, UiKit.MEOK_3)
			ci.draw_arc(c, 6.0 * pop, 0.0, TAU if _gs_half[i] == 0 else PI, 16, col, 1.0)
		UiKit.text(ci, _f_small, UiKit.SZ_SMALL, c + Vector2(0, 4), _gs_glyph[i], UiKit.HANJI_UI, 1)


func _draw_misc(ci: Control) -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = roundf(w * 0.5)
	# 거리 전환 붓 슬램(상단 중앙, ≤1.2초): 단청 띠 + 붓글씨 거리명 + 장단 — 가운데 슬롯 prio 2 를 얻을 때만
	if _gslam_t > 0.0 and (not Juice.has_method(&"claim_center") or bool(Juice.call(&"claim_center", &"hud_geori", 2, _gslam_t))):
		var a: float = clampf(_gslam_t / 0.25, 0.0, 1.0) if _gslam_t < 0.25 else 1.0
		var rise: float = 0.0 if _gslam_t > 0.3 else (0.3 - _gslam_t) * 40.0
		var y: float = 92.0 - rise
		var nw: float = _f_brush.get_string_size(_geori_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		var bw: float = maxf(160.0, nw + 40.0)
		var band: Rect2 = Rect2(cx - bw * 0.5, y - 30.0, bw, 42)
		vis_rects["center:geori_slam"] = [band, Engine.get_process_frames()]
		ci.draw_rect(band, Color(UiKit.MEOK, 0.55 * a))
		UiKit.draw_dancheong(ci, Rect2(band.position.x, band.position.y - 3.0, band.size.x, 3))
		UiKit.draw_dancheong(ci, Rect2(band.position.x, band.end.y, band.size.x, 3))
		UiKit.text_outline(ci, _f_brush, 40, Vector2(cx, y), _geori_name, Color(UiKit.HANJI_UI, a), 1, 2)
		UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx, y + 10.0), _geori_jd, Color(UiKit.HWANG_HI, a), 1)
	# 공수·예고 레인(y=64). 거리 카드(위 구역)가 떠 있으면 그리지 않는다 — 위 구역은 한 번에 1개(design/18 §2.1)
	if _lane_t > 0.0 and _lane_text != "" and not _card_on():
		var a2: float = clampf(_lane_t / 0.3, 0.0, 1.0)
		var tw: float = _f_body.get_string_size(_lane_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		var lr: Rect2 = Rect2(cx - tw * 0.5 - 6.0, 64, tw + 12.0, 15)
		vis_rects["top:lane"] = [lr, Engine.get_process_frames()]
		ci.draw_rect(lr, Color(UiKit.MEOK, 0.6 * a2))
		if _lane_gold:
			ci.draw_rect(lr, Color(UiKit.HWANG_DK, a2), false, 1.0)
		UiKit.text(ci, _f_body, UiKit.SZ_BODY, Vector2(cx, 76), _lane_text, Color(UiKit.HWANG_HI if _lane_gold else UiKit.HANJI, a2), 1)
	# 가장자리 레인(왼쪽 위, 무구 칸·정기 바 아래): 작은 글씨, 왼쪽 정렬, 먹 0.5 받침
	if _edge_t > 0.0 and not _edge_text.is_empty():
		var a5: float = clampf(_edge_t / 0.3, 0.0, 1.0) * clampf((EDGE_SEC - _edge_t) / 0.12, 0.0, 1.0)
		var ew: float = 0.0
		for ln: String in _edge_text:
			ew = maxf(ew, _f_small.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x)
		var er: Rect2 = Rect2(6, 48, minf(EDGE_W, ew + 8.0), 4.0 + 11.0 * float(_edge_text.size()))
		vis_rects["edge:lane"] = [er, Engine.get_process_frames()]
		ci.draw_rect(er, Color(UiKit.MEOK, 0.5 * a5))
		ci.draw_rect(Rect2(er.position, Vector2(1, er.size.y)), Color(UiKit.HWANG_DK if _edge_gold else UiKit.HANJI_4, a5))
		for li in _edge_text.size():
			UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(10, 57.0 + 11.0 * float(li)), _edge_text[li],
				Color(UiKit.HWANG_HI if _edge_gold else UiKit.HANJI_2, a5), 0)
	# 연속 굿 칩(하단 가운데): ○ 해원 | ◆ 퇴치 — 같은 글자 크기·굵기
	var any: bool = _streak_vis[0] > 0.0 or _streak_vis[1] > 0.0
	if any:
		for k in 2:
			if _streak_vis[k] <= 0.0:
				continue
			var a3: float = _streak_vis[k]
			var r: Rect2 = Rect2(cx - 44 + k * 48, h - 34, 40, 14)
			ci.draw_rect(r, Color(UiKit.MEOK_1, 0.8 * a3))
			ci.draw_rect(r, Color(UiKit.HANJI_4 if k == 0 else UiKit.JEOK_DK, a3), false, 1.0)
			UiKit.text(ci, _f_bold, UiKit.SZ_BODY, Vector2(r.get_center().x, r.end.y - 3.0), _streak_s[k],
				Color(UiKit.HANJI if k == 0 else UiKit.JEOK_HI, a3), 1)
	# 추임새 슬램(붓, 0.9초): 크기 단계 팝(정수 크기만)
	if _slam_t > 0.0:
		var el: float = 1.0 - _slam_t
		var fs: int = 36 if el < 0.06 else (46 if el < 0.14 else 40)
		var a4: float = clampf(_slam_t / 0.3, 0.0, 1.0)
		UiKit.text_outline(ci, _f_brush, fs, Vector2(cx, h - 44.0 - el * 10.0), _slam_text, Color(_slam_col, a4), 1, 2)
	if _debug_on and _debug_s != "":
		UiKit.text(ci, _f_tiny, UiKit.SZ_TINY, Vector2(4, h - 4), _debug_s, Color(UiKit.HANJI_2, 0.7))
