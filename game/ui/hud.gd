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
var _end_s: String = " / 20:00"     # 시계 뒤 끝 시각(design/19 §1.3)
# 목표 줄(design/19 §1.3 — 시계 아래 상시 한 줄, 가운데 슬롯 아님: top:goal)
var _goal_s: String = ""
var _goal_icon: int = 0             # 0 없음 1 사자 2 ! 3 신령 점 4 ◆ 5 ○
var _goal_id: String = ""
var _goal_flash: float = 0.0
var _goal_poll: float = 0.0
var _has_white: bool = false
var _white_name: String = "흰 무기"
var _first_ring: bool = false
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
const EDGE_W: float = 176.0       # 기운 바 왼쪽 라벨('풀어 줌 ○ N', x≈190~) 앞에서 멈춘다(design/19 §4.4)
# 연속 굿
var _streak: PackedInt32Array = PackedInt32Array([0, 0])          # 0 해원 1 퇴치
var _streak_last: PackedFloat32Array = PackedFloat32Array([-10, -10])
var _streak_s: PackedStringArray = PackedStringArray(["", ""])
var _streak_vis: PackedFloat32Array = PackedFloat32Array([0, 0])
var _streak_stage: PackedInt32Array = PackedInt32Array([0, 0])
var _streak_pop: PackedFloat32Array = PackedFloat32Array([-10, -10])   # 처치마다 1f +2px 팝(실시간)
var _streak_hot: PackedFloat32Array = PackedFloat32Array([0, 0])       # 10·25·50·100 테 주색 0.15초
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
	_end_s = " / " + K.fmt_time(_boss_time)
	Events.ring_closed.connect(func(_a: int, _h: int, _c: Vector2) -> void: _first_ring = true)
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
	# 실전: 기운 바(넋 ↔ 살)는 첫 판에도 처음부터 보인다(2026-11-26 사용자 피드백 — 첫 판 2분 숨김이 '빠진 UI'로 보였다).
	#   길잡이는 2분(또는 살기 20)에 그대로 깜빡이며 한 줄 설명한다(guide.gd).
	# 연습 굿판: 기운 바는 '살' 단계에서 디렉터가 reveal_giun() 으로 연다(design/17 §5.1)
	if Game.tutorial_mode:
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
	_streak_pop[k] = Time.get_ticks_msec() / 1000.0
	if n == 10 or n == 25 or n == 50 or n == 100:
		_streak_hot[k] = 0.15
	if n >= 5:
		_streak_s[k] = ("풀어 줌 ×%d" if k == 0 else "처치 ×%d") % n
	# 추임새 슬램(붓 큰 글자)은 haewon(haewon_system.slam, combat_core.chuimsae)이 그린다 — HUD 는 연속 칩만(중복 금지)


func _on_weapon_added(id: StringName, slot: int) -> void:
	if slot >= 0 and slot < 6:
		_slot_new[slot] = 1.0
	_icon_of(id)
	if not _has_white and String(Data.weapon(String(id)).get("color", "")) == "white":
		_has_white = true
		_white_name = "방울" if String(id).begins_with("wpn_bangul") else "흰 무기"


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
	_goal_flash = maxf(0.0, _goal_flash - delta)
	for k0 in 2:
		_streak_hot[k0] = maxf(0.0, _streak_hot[k0] - delta)
	_goal_poll -= delta
	if _goal_poll <= 0.0:
		_goal_poll = 0.25
		_update_goal()
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


## 목표 줄 문구(design/19 §1.3 GOAL — 위에서부터 먼저 맞는 것 하나). 0.25초마다, 바뀔 때만 문자열을 만든다.
## 견본 범위: 판 목표 · 위험 · 시련 임박 · 시간대 기본. 시련·보스·중간보스 중에는 그 제목 줄이 이 자리를 쓴다(그리지 않음).
func _update_goal() -> void:
	if Game.tutorial_mode:
		_goal_s = ""
		return
	var t: float = Game.time_sec()
	var id: String = ""
	var icon: int = 0
	var next_tr: float = -1.0
	for tt: float in _trial_times:
		if tt > t:
			next_tr = tt
			break
	if t < 4.0:
		id = "goal"
		icon = 1
	elif Game.hp_max > 0.0 and Game.hp / Game.hp_max < (0.4 if _goal_id == "danger" else 0.3) and t > 1.0:
		# 이력(30% 아래 켜짐 · 40% 위 꺼짐): 30% 언저리에서 목표 줄이 깜박·틱 소리를 되풀이하지 않게(검토 11-26)
		id = "danger"
		icon = 2
	elif next_tr > 0.0 and next_tr - t <= 20.0:
		id = "trial_soon"
		icon = 3
	elif t < 180.0:
		if not _has_white:
			id = "walk"
		elif Game.kills_haewon <= 0:
			id = "white"
			icon = 5
		elif t < 90.0:
			id = "yeongga"
			icon = 5
		elif not _first_ring:
			id = "ring"
			icon = 5
		else:
			id = "grow"
	elif t >= 1180.0:
		id = "boss_soon"
		icon = 1
	elif t >= 1155.0:
		id = "gongmul"
		icon = 5
	elif t >= 1080.0:
		id = "hapil"
		icon = 3
	elif t >= 720.0:
		id = "to_hapil"
		icon = 3
	elif t >= 360.0 and t < 600.0:
		id = "elite"
		icon = 4
	else:
		id = "next_trial"
	if (id == "hapil" or id == "to_hapil") and _possessed_n() == 0:
		# 모신 신령이 없는 판(시련을 다 놓친 처음 하는 사람)에게 '신령과 함께'라고 말하지 않는다(검토 11-26)
		id += "_solo"
		icon = 0
	if id == _goal_id and id != "next_trial":
		return
	var txt: String = String(GOAL.get(id, ""))
	if id == "white":
		txt = txt % ("방울이" if _white_name == "방울" else "흰 무기가")
	elif id == "goal" or id == "boss_soon":
		txt = txt % K.fmt_time(_boss_time)
	elif id == "next_trial":
		txt = (txt % K.fmt_time(next_tr)) if next_tr > 0.0 else String(GOAL["last_stand"]) % K.fmt_time(_boss_time)
	if txt == _goal_s:
		_goal_id = id
		return
	var first: bool = _goal_s == ""
	_goal_id = id
	_goal_s = txt
	_goal_icon = icon
	if not first:
		_goal_flash = 0.3
		Audio.play_sfx(&"sfx_ui_card_hover", &"UI", -8.0)
	if Game.autotest:
		print("[ui] goal t=%.1f id=%s" % [t, id])


## 지금까지 모신(빙의한) 신령 수 — 합일 목표 줄 분기용(0.25초마다 한 번)
func _possessed_n() -> int:
	var rr: Node = Game.run_root
	var td: TrialDirector = (rr.get("trials") as TrialDirector) if rr != null else null
	return td.possessed.size() if td != null else 1


## 목표 줄 문구(design/19 §1.3 표 — 22자 이내, 행동부터). 분할 A 가 UiCopy.GOAL 로 옮길 자리.
const GOAL: Dictionary = {
	"goal": "목표: %s까지 버티고 역려를 보내라",
	"danger": "위험! 무리에서 빠져나가세요",
	"trial_soon": "곧 신령의 시험 — 빛나는 원으로",
	"walk": "걸어 다니며 버티세요 · 무기는 저절로",
	"white": "흰 테두리 귀신 곁으로 — %s 풀어 준다",
	"yeongga": "풀어 준 넋이 뒤따르며 지켜 준다",
	"ring": "흰 길로 한 바퀴 감싸면 한꺼번에 풀린다",
	"grow": "구슬을 모아 무기를 키우세요",
	"next_trial": "다음 시험 %s · 버티세요",
	"last_stand": "버티세요 · %s 역려가 온다",
	"elite": "강한 귀신을 잡으면 상자 · 10:00 큰 귀신",
	"to_hapil": "18:00 모신 신령이 모두 내려온다",
	"hapil": "신령과 함께 마지막 공세를 버티세요",
	"to_hapil_solo": "18:00 마지막 공세가 온다 · 버티세요",
	"hapil_solo": "마지막 공세 — 홀로 끝까지 버티세요",
	"gongmul": "공물상을 흰 길로 감싸 보내세요",
	"boss_soon": "%s 역병 귀신 역려가 온다",
}


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
	var fill: Color = UiKit.HWANG                        # 경험치 = 황(체력·기운 바 한지와 갈림, design/19 §4.4)
	if full and fposmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5:
		fill = UiKit.HWANG_HI
	UiKit.draw_bar(ci, r, _xp_show, fill, UiKit.MEOK_1, UiKit.HANJI_5)
	var xw: float = roundf(r.size.x * clampf(_xp_show, 0.0, 1.0))
	if xw > 0.0:
		ci.draw_rect(Rect2(r.position.x, r.end.y - 1.0, xw, 1.0), UiKit.HWANG_DK)
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
	# 체력 표지: 촛불(8×7 코드 그림 — ◆ 처치 표지와 겹치지 않게, design/19 §4.4). 30% 아래 깜박
	_draw_candle(ci, Vector2(12, 34), pulse)
	UiKit.text(ci, _f_tiny, UiKit.SZ_TINY, Vector2(hr.end.x + 4.0, 42), _hp_s, UiKit.HANJI if not low else UiKit.JEOK_HI)


## 촛불: 먹 테 + 한지 초 3×4 + 심지 + 불꽃(jk-hi·황). lo = 깜박(불꽃 주색).
func _draw_candle(ci: Control, o: Vector2, lo: bool) -> void:
	ci.draw_rect(Rect2(o + Vector2(1, 3), Vector2(5, 6)), UiKit.MEOK)
	ci.draw_rect(Rect2(o + Vector2(2, 4), Vector2(3, 4)), UiKit.HANJI)
	ci.draw_rect(Rect2(o + Vector2(0, 8), Vector2(7, 1)), UiKit.HANJI_3)
	ci.draw_rect(Rect2(o + Vector2(3, 3), Vector2(1, 1)), UiKit.MEOK_4)
	ci.draw_rect(Rect2(o + Vector2(3, 0), Vector2(1, 3)), UiKit.JEOK_HI if lo else UiKit.HWANG)
	ci.draw_rect(Rect2(o + Vector2(3, 1), Vector2(1, 1)), UiKit.HWANG_HI if not lo else UiKit.JEOK)


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
	# 시계 'mm:ss / 20:00'(design/19 §1.3): 지금 시각 Bold 12 + 끝 시각 Galmuri9 10 HANJI_3 — 언제 끝나는지 늘 보인다
	var half_l: float = 26.0
	var half_r: float = 25.0
	if t >= _boss_time:
		var bw: float = 40.0
		ci.draw_rect(Rect2(cx - bw * 0.5, 13, bw, 13), UiKit.HANJI)
		UiKit.text(ci, _f_bold, UiKit.SZ_BODY, Vector2(cx, 24), _clock_s, UiKit.MEOK, 1, false)
	elif Game.tutorial_mode:
		UiKit.text(ci, _f_bold, UiKit.SZ_BODY, Vector2(cx, 24), _clock_s, col, 1)
	else:
		var w1: float = _f_bold.get_string_size(_clock_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		var w2: float = _f_small.get_string_size(_end_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
		var x0: float = roundf(cx - (w1 + w2) * 0.5)
		UiKit.text(ci, _f_bold, UiKit.SZ_BODY, Vector2(x0, 24), _clock_s, col, 0)
		UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(x0 + w1, 24), _end_s, UiKit.HANJI_3, 0)
		half_l = roundf(cx - x0 + 5.0)
		half_r = roundf(x0 + w1 + w2 - cx + 5.0)
		_draw_progress(ci, cx, t)
	# 박 징 표지(시계 양옆 작은 마름모, 박마다 밝아짐 · 박 머리 황)
	var bc: Color = UiKit.HWANG_HI if _beat_down else UiKit.HANJI
	var ba: float = 0.25 + 0.75 * _beat_k
	UiKit.draw_diamond(ci, Vector2(cx - half_l, 19), 2.0, Color(bc, ba))
	UiKit.draw_diamond(ci, Vector2(cx + half_r, 19), 2.0, Color(bc, ba))
	# 거리 줄(장단·BPM)과 다음 시련 칩은 없앤다(design/19 §4.4) — 그 자리(y31~44)는 '지금 할 일' 목표 줄이 늘 쓴다.
	# 시련·보스·중간보스 중에는 그 제목 줄이 같은 자리를 쓰므로 목표 줄을 그리지 않는다.
	if _goal_s != "" and not _trial_active and _boss_handle < 0 and _mb_handle < 0:
		_draw_goal(ci, cx)
	# 의례 슬롯(y=46): 보스 > 시련 > 굿판의 기운
	if _boss_handle >= 0:
		_draw_boss(ci, cx)
	elif _mb_handle >= 0:
		_draw_midboss(ci, cx)
	elif _trial_active:
		_draw_trial(ci, cx)
	# 굿판의 기운은 B_GIUN 블록이 그린다
	# 시련 결과 큰 글자(면 이름·빙의)는 deities(trial_hud)가 그린다 — HUD 는 강신 칸 팝만(겹침 금지)


## 진행 줄(y28, 폭 160, 2px): 지난 부분 한지 · 남은 부분 먹. 눈금 = 시련(황) · 10:00 큰 귀신(주) · 18:00 신령 모두 내림(한지)
## · 20:00 역려(주 마름모). 금 #f5d66b 는 무당 전용이라 쓰지 않는다.
func _draw_progress(ci: Control, cx: float, t: float) -> void:
	var x0: float = cx - 80.0
	var w: float = 160.0
	var y: float = 28.0
	var k: float = clampf(t / maxf(_boss_time, 1.0), 0.0, 1.0)
	ci.draw_rect(Rect2(x0 - 1.0, y - 1.0, w + 2.0, 4.0), Color(UiKit.MEOK, 0.8))
	ci.draw_rect(Rect2(x0, y, w, 2.0), UiKit.MEOK_4)
	var fw: float = roundf(w * k)
	if fw > 0.0:
		ci.draw_rect(Rect2(x0, y, fw, 2.0), UiKit.HANJI_2)
	for tt: float in _trial_times:
		if tt >= _boss_time:
			continue
		var tx: float = roundf(x0 + w * tt / _boss_time)
		var hapil: bool = absf(tt - 1080.0) < 1.0
		var tc: Color = UiKit.HANJI_UI if hapil else UiKit.HWANG
		ci.draw_rect(Rect2(tx - 1.0, y - 1.0, 3.0, 4.0), UiKit.MEOK)
		ci.draw_rect(Rect2(tx, y - 1.0, 1.0, 4.0), tc if tt > t else UiKit.HANJI_4)
	var mx: float = roundf(x0 + w * 600.0 / _boss_time)
	ci.draw_rect(Rect2(mx - 1.0, y - 1.0, 3.0, 4.0), UiKit.MEOK)
	ci.draw_rect(Rect2(mx, y - 1.0, 1.0, 4.0), UiKit.JEOK_HI if t < 600.0 else UiKit.HANJI_4)
	UiKit.draw_diamond(ci, Vector2(x0 + w + 1.0, y + 1.0), 3.0, UiKit.MEOK)
	UiKit.draw_diamond(ci, Vector2(x0 + w + 1.0, y + 1.0), 2.0, UiKit.JEOK_HI)


## 목표 줄: 먹 띠 α0.55(글 폭 + 12, 높이 14, y31~45) + 아이콘 8px + Bold 12 한지. 바뀐 순간 0.3초 황 테 깜박.
func _draw_goal(ci: Control, cx: float) -> void:
	var tw: float = _f_bold.get_string_size(_goal_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
	var iw: float = 11.0 if _goal_icon != 0 else 0.0
	var bw: float = tw + iw + 12.0
	var r: Rect2 = Rect2(roundf(cx - bw * 0.5), 31, roundf(bw), 14)
	vis_rects["top:goal"] = [r, Engine.get_process_frames()]
	ci.draw_rect(r, Color(UiKit.MEOK, 0.55))
	if _goal_flash > 0.0 and fposmod(_goal_flash, 0.1) > 0.05:
		ci.draw_rect(r, UiKit.HWANG_HI, false, 1.0)
	var ix: float = r.position.x + 6.0
	if _goal_icon != 0:
		_draw_goal_icon(ci, Vector2(ix + 4.0, 38.0), _goal_icon)
	var tc: Color = UiKit.JEOK_HI if _goal_icon == 2 else UiKit.HANJI_UI
	UiKit.text_outline(ci, _f_bold, UiKit.SZ_BODY, Vector2(ix + iw, 42), _goal_s, tc, 0, 1)


func _draw_goal_icon(ci: Control, c: Vector2, icon: int) -> void:
	match icon:
		1:  # 사자(흑립): 갓 테 + 먹 갓
			ci.draw_rect(Rect2(c + Vector2(-4, 1), Vector2(9, 2)), UiKit.HANJI_3)
			ci.draw_rect(Rect2(c + Vector2(-2, -3), Vector2(5, 4)), UiKit.HANJI_3)
			ci.draw_rect(Rect2(c + Vector2(-1, -2), Vector2(3, 3)), UiKit.MEOK)
		2:  # !
			ci.draw_rect(Rect2(c + Vector2(-1, -4), Vector2(3, 9)), UiKit.MEOK)
			ci.draw_rect(Rect2(c + Vector2(0, -3), Vector2(1, 5)), UiKit.JEOK_HI)
			ci.draw_rect(Rect2(c + Vector2(0, 3), Vector2(1, 1)), UiKit.JEOK_HI)
		3:  # 신령 점
			ci.draw_circle(c, 3.0, UiKit.MEOK)
			ci.draw_circle(c, 2.0, UiKit.HWANG)
		4:
			UiKit.draw_kind_mark(ci, c, 2.0, false)
		5:
			UiKit.draw_kind_mark(ci, c, 2.0, true)


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
	var r: Rect2 = Rect2(cx - 60, 48, 120, 6)
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
	var sr: Rect2 = Rect2(cx - 60, 56, 120, 4 if _sal_big > 0.0 else 3)
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
	# 양 끝 라벨(Galmuri9 10 — 한글 8px 금지, design/19 §4.4): 왼쪽 '풀어 줌 ○ N', 오른쪽 '◆ 처치 N'. 숫자는 2:00 전엔 숨긴다.
	var show_n: bool = Game.time_sec() >= 120.0
	var lx: float = cx - 66.0
	# 라벨은 바 바깥 전장 위에 놓이므로 그림자 대신 먹 외곽선 1(바쁜 바닥·붉은 바닥 위 주색 '처치' 대비, 검토 11-26)
	if show_n:
		lx -= UiKit.text_outline(ci, _f_small, UiKit.SZ_SMALL, Vector2(lx, 57), _short_num(_h_last), UiKit.HANJI, 2, 1) + 3.0
	UiKit.draw_kind_mark(ci, Vector2(lx - 2.0, 52), 2.0, true)
	UiKit.text_outline(ci, _f_small, UiKit.SZ_SMALL, Vector2(lx - 7.0, 57), "풀어 줌", UiKit.HANJI_2, 2, 1)
	UiKit.draw_kind_mark(ci, Vector2(cx + 67, 52), 2.0, false)
	var tw2: float = UiKit.text_outline(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx + 72, 57), "처치", UiKit.JEOK_HI, 0, 1)
	if show_n:
		UiKit.text_outline(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx + 75.0 + tw2, 57), _short_num(_t_last), UiKit.HANJI, 0, 1)
	# 신명 오름: 오방색 1px 순환 테
	if _oreum:
		var oc: Color = OBANG[int(_oreum_t * 8.0) % 5]
		ci.draw_rect(Rect2(cx - 62, 46, 124, 15), oc, false, 1.0)


## 큰 수 줄임(1,234 → 1.2천, 12,345 → 1.2만).
static func _short_num(n: int) -> String:
	if n < 1000:
		return str(maxi(n, 0))
	if n < 10000:
		return "%.1f천" % (float(n) / 1000.0)
	return "%.1f만" % (float(n) / 10000.0)


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
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx - 72, 53), "싸움", UiKit.JEOK_HI, 2)
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx + 72, 53), "모심", UiKit.HANJI, 0)


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
		var nowr: float = Time.get_ticks_msec() / 1000.0
		for k in 2:
			if _streak_vis[k] <= 0.0:
				continue
			var a3: float = _streak_vis[k]
			# '처치 ×N' / '풀어 줌 ×N'(design/19 §4.4): 처치마다 1f +2px 팝, 10·25·50·100 에 테 주색 0.15초
			var r: Rect2 = Rect2(cx - 84 + k * 88, h - 34, 80, 14)
			if nowr - _streak_pop[k] < 0.034:
				r = r.grow(2.0)
			ci.draw_rect(r, Color(UiKit.MEOK_1, 0.8 * a3))
			var bc2: Color = UiKit.JEOK_HI if _streak_hot[k] > 0.0 else (UiKit.HANJI_4 if k == 0 else UiKit.JEOK_DK)
			ci.draw_rect(r, Color(bc2, a3), false, 1.0)
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
