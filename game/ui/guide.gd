extends Control
## 길잡이(온보딩) + 월드 공간 UI. 소유: ui. HUD 의 자식(스크린 좌표, 월드 → 화면은 캔버스 변환).
## 그리는 것
##  - 발밑 호 2개(왼쪽 신명·오른쪽 영가 행렬) + 정기 바(design/11 §5.2 hud_sinmyeong_jing / hud_haengnyeol_count / hud_player_jeonggi)
##  - 오프스크린 지시자(정예·보스, 최대 6)
##  - 첫 런 길잡이 순서(사용자 지시 2026-11-22):
##      이동 → 풀릴 기색 화살표 '흰 무구로 풀어주세요' → 첫 해원 '영가가 따라옵니다'
##      → 고리 준비 시 '흰 길을 이어 고리를 닫으세요' + 예상선(점선) + 닫힘 원 → 첫 시련 → 첫 원귀 회귀
##  - 힌트 줄(하단 y=H−84, 동시 1·대기 1) · 이름표(B 채널: 解冤 해원, 길닦음)
## 백(#f2ece0)은 월드 해원 표지(풀릴 기색 화살표·길베 예상선·해원 이름표)에만 쓴다.
## 매 프레임 할당 없음: 버퍼는 _ready 에서 만든다.

const ARC_R: float = 13.0
const MAX_ARROWS: int = 5
const MAX_OFF: int = 6

var _f_body: Font
var _f_small: Font
var _f_tiny: Font
var _f_big: Font
var _f_brush: Font

var _arc_l: PackedVector2Array = PackedVector2Array()
var _arc_r: PackedVector2Array = PackedVector2Array()
var _xf: Transform2D = Transform2D.IDENTITY

# 발밑 호 상태
var _beat_k: float = 0.0
var _yg_count: int = 0
var _yg_cap: int = 24
var _yg_label: String = ""
var _yg_label_t: float = 0.0
var _yg_last_mark: int = 0
var _yg_full_said: bool = false    # 행렬이 처음 가득 찬 순간에만 라벨(가득 찬 채로는 다시 띄우지 않는다)
var _oreum: bool = false
var _oreum_t: float = 0.0

# 힌트 줄
var _hint_id: String = ""
var _hint_text: String = ""
var _hint_t: float = 0.0           # 남은 시간
var _hint_in: float = 0.0          # 등장 경과
var _hint_prio: int = 0
var _hint_lines: PackedStringArray = PackedStringArray()   # 힌트 줄을 폭 260 안에 2줄로 접은 것
var _busy: bool = false            # 화면이 바쁨(가운데 슬롯·숫자 군중·잡귀 60↑·합일) — prio<3 미룸, prio 3 은 1.5초만
const HINT_W: float = 260.0
## 가시성 측정(tests/vis_probe.gd): 이번 프레임에 그린 화면 글 사각형. 키 → [Rect2(640×360 기준), 그린 프레임].
var vis_rects: Dictionary = {}
# 대기열(최대 3, 우선순위 높은 것 먼저 · 같은 순위는 들어온 순). 이벤트 때만 바뀐다.
const Q_MAX: int = 3
var _qa_id: PackedStringArray = PackedStringArray()
var _qa_text: PackedStringArray = PackedStringArray()
var _qa_dur: PackedFloat32Array = PackedFloat32Array()
var _qa_prio: PackedInt32Array = PackedInt32Array()
var _qa_age: PackedFloat32Array = PackedFloat32Array()
var _gap: float = 0.0              # 다음 힌트까지 최소 간격(실시간)
var _hint_fade: float = 1.0        # 예고 띠와 겹칠 때 숨김(0..1)
var _seen: Dictionary = {}

# 이름표(B 채널): 최대 4
var _tag_text: PackedStringArray = PackedStringArray(["", "", "", ""])
var _tag_pos: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _tag_t: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var _tag_brush: PackedByteArray = PackedByteArray([0, 0, 0, 0])
var _tag_rc: Array[Rect2] = [Rect2(), Rect2(), Rect2(), Rect2()]   # 이번 프레임에 그린 이름표 받침(겹침 회피용, 할당 없음)

# 길잡이 단계
var guide_on: bool = true
var _step_move: int = 0            # 0 대기 1 표시 2 완료
var _move_from: Vector2 = Vector2.INF
var _move_t: float = 0.0
var _arrows_on: bool = false
var _arrows_t: float = 0.0
var _arrow_slots: PackedInt32Array = PackedInt32Array()
var _arrow_d: PackedFloat32Array = PackedFloat32Array()
var _arrow_n: int = 0
var _first_haewon: bool = false
var _first_by_ring: bool = false
var _ring_step: int = 0            # 0 잠김 1 대기(조건) 2 안내 중 3 완료
var _ring_wait: float = 0.0
var _ring_center: Vector2 = Vector2.ZERO
var _ring_has_center: bool = false
var _ring_hint_again: float = 0.0
var _rings_closed: int = 0
var _ready_ext: bool = false       # haewon 모듈의 gilbe_ready(true) — 예상선·매듭·zone 은 ring_closure 가 그린다
var _ring_said_ready: bool = false # '점선 끝을 밟으세요' 문장을 이미 보였나
var _quiet: float = 0.0            # waves 예고 띠가 같은 내용을 말하는 동안 힌트 줄 대기(실시간)
var _waves_ring_until: float = -1.0  # waves 고리 가이드 원(01:30)이 보이는 동안(게임 시각) 걷기 원 생략
var _white_owned: bool = false
var _sal_hint: bool = false
var _need_white_checked: bool = false
var _runs: int = 1
var _arrows_keep: float = 0.0      # 몸주 흰 무구 직후: 첫 해원이 나도 화살표를 이만큼 더 켠다
var _yg_hit: float = 0.0           # 영가 대신 맞기 순간 발밑 호 번쩍임
var _giun_said: bool = false
var _eod_h: int = -1               # 첫 어둑시니(쳐다볼수록 커진다) 추적
var _eod_seen_t: float = 0.0
var _mb_h: int = -1                # 중간보스(풀릴 기색 안내용)
var _evo_poll: float = 0.0
var _boss_said: bool = false
var _trial_busy: bool = false     # 시련 예고~시련 중: 안내판(deities)이 할 일을 말한다 — 규칙·메타 힌트(prio<2)는 그동안 대기

# 오프스크린
var _off_h: PackedInt32Array = PackedInt32Array()
var _off_boss: PackedByteArray = PackedByteArray()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_body = UiKit.body()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_big = UiKit.big()
	_f_brush = UiKit.brush()
	_arc_l = _make_arc(105.0, 255.0)
	_arc_r = _make_arc(75.0, -75.0)
	_arrow_slots.resize(MAX_ARROWS)
	_arrow_d.resize(MAX_ARROWS)
	_off_h.resize(MAX_OFF)
	_off_h.fill(-1)
	_off_boss.resize(MAX_OFF)
	guide_on = UiSettings.guide_on()
	var hs: Variant = Save.get_value("ui.hints_seen", {})
	if hs is Dictionary and not (Game.autotest and DebugTools.arg("ui-save") != "1"):
		_seen = (hs as Dictionary).duplicate()
	# RunLedger(HUD 에서 이 노드 다음에 붙는다)가 _ready 에서 ui.runs 를 올리기 전이라 +1 = 이번 판 번호
	_runs = int(Save.get_value("ui.runs", 0)) + 1
	if _seen.has("ring_done"):
		_ring_step = 3      # 이미 고리를 닫아 본 사람: 고리 길잡이 생략
	Events.beat.connect(func(_i: int, _d: bool) -> void: _beat_k = 1.0)
	Events.yeongga_joined.connect(_on_yg_joined)
	Events.yeongga_cheondo.connect(_on_yg_cheondo)
	Events.sinmyeong_oreum.connect(_on_oreum)
	Events.pullil_entered.connect(_on_pullil)
	Events.enemy_killed.connect(_on_killed)
	Events.ring_closed.connect(_on_ring_closed)
	Events.gilbe_ready.connect(func(c: bool) -> void: _ready_ext = c)
	# 시련: 할 일 안내판은 deities(trial_hud, y82~)가 그린다 — 여기서는 첫 시련에 시선만 위로 보낸다
	Events.trial_warn.connect(func(_s: int, _d: StringName, _in: float) -> void: _hint("trial_warn", UiCopy.HINT["trial_warn"], 3.5, 3))
	Events.wongwi_return.connect(func(_t: int) -> void: _hint("wongwi", UiCopy.HINT["wongwi"], 4.5, 3))
	Events.wave_event.connect(_on_wave_event)
	Events.hint_requested.connect(_on_hint_requested)
	Events.weapon_added.connect(_on_weapon_added)
	Events.elite_spawned.connect(_on_elite)
	Events.midboss_incoming.connect(func(_s: StringName) -> void: _hint("midboss", UiCopy.HINT["midboss"], 5.0, 3))
	Events.box_opened.connect(func(_b: StringName, _g: int, _r: Array, _bn: float, _p: Vector2) -> void: _hint("box_first", UiCopy.HINT["box_first"], 4.5, 2))
	Events.weapon_evolved.connect(func(_f: StringName, _t: StringName) -> void: _mark_seen("evo_ready"))
	Events.wave_warn.connect(_on_wave_warn)
	Events.boss_spawned.connect(func(h: int, _s: StringName, _f: StringName) -> void: _track_off(h, true))
	var yt: Node = _yeongga()
	if yt != null and yt.has_method("capacity"):
		_yg_cap = maxi(1, int(yt.call("capacity")))
	_white_owned = _has_white()


func _make_arc(a0_deg: float, a1_deg: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = 22
	for i in n:
		var a: float = deg_to_rad(lerpf(a0_deg, a1_deg, float(i) / float(n - 1)))
		out.append(Vector2(cos(a), sin(a)) * ARC_R - Vector2(1, 1))
	return out


func _run() -> Run:
	return Game.run_root as Run


func _yeongga() -> Node:
	var r: Run = _run()
	return r.yeongga if r != null else null


## 아직 안 들어온 시작 흰 무구 이름(characters.json start_weapons 의 at_s > 0). 없으면 '흰 무구'.
func _next_white_name() -> String:
	var def: Dictionary = Data.character(String(Game.char_id))
	var sw: Variant = def.get("start_weapons", [])
	if sw is Array:
		for e: Variant in sw:
			if e is Dictionary:
				var wid: String = String((e as Dictionary).get("wpn", ""))
				if UiKit.weapon_color(wid) == "white":
					return UiKit.weapon_name(wid)
	return "점지에서 ○"


func _has_white() -> bool:
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm == null:
		return false
	for i in wm.slot_count():
		var w: WeaponBase = wm.weapon_at(i)
		if w != null and w.is_white():
			return true
	return false


# ─── 힌트 줄 ────────────────────────────────────────────────────────────

## prio: 0 meta 1 rule 2 trial 3 survival. once 키로 한 번만(세이브 ui.hints_seen).
## '본 것' 기록은 실제로 화면에 띄울 때(_show_now) 남긴다 — 대기열에서 밀려 버려진 문장은 다음 판에 다시 나온다.
func _hint(id: String, text: String, dur: float, prio: int = 1) -> void:
	if Game.tutorial_mode:
		return   # 연습 굿판: 문장 힌트·이름표·본 힌트 저장은 tutorial_hud 몫(design/17 §7.3)
	if not guide_on or _seen.has(id) or _hint_id == id or _qa_id.has(id):
		return
	if (_hint_t > 0.0 and prio <= _hint_prio) or (_quiet > 0.0 and prio < 3) or (_trial_busy and prio < 2) or (_busy and prio < 3) or not _qa_id.is_empty():
		_enqueue(id, text, dur, prio)
		return
	# 더 급한 문장이 끼어든다: 보던 문장은 남은 시간만큼 대기열로 되돌린다
	if _hint_t > 2.0 and _hint_id != "":
		_enqueue(_hint_id, _hint_text, maxf(3.0, _hint_t), _hint_prio)
	_show_now(id, text, dur, prio)


func _enqueue(id: String, text: String, dur: float, prio: int) -> void:
	var k: int = _qa_id.size()
	while k > 0 and _qa_prio[k - 1] < prio:
		k -= 1
	if k >= Q_MAX:
		return
	_qa_id.insert(k, id)
	_qa_text.insert(k, text)
	_qa_dur.insert(k, dur)
	_qa_prio.insert(k, prio)
	_qa_age.insert(k, 0.0)
	if _qa_id.size() > Q_MAX:
		_qa_id.resize(Q_MAX)
		_qa_text.resize(Q_MAX)
		_qa_dur.resize(Q_MAX)
		_qa_prio.resize(Q_MAX)
		_qa_age.resize(Q_MAX)
	if Game.autotest:
		print("[ui] hint-queued t=%.1f id=%s" % [Game.time_sec(), id])


## 대기 중에 이미 지나간 단계의 문장(예: 첫 해원 뒤의 '풀어주세요')은 버린다
func _stale(id: String) -> bool:
	match id:
		"pullil", "pullil_wait":
			return _first_haewon
		"move":
			return _step_move == 2
		"ring", "ring_ready":
			return _ring_step == 3
		"sinmyeong":
			return not _oreum
		"trial_faces":
			return not _trial_busy                # 시련이 끝났으면 버린다(늦은 설명 금지)
	return false


func _dequeue() -> void:
	_qa_id.remove_at(0)
	_qa_text.remove_at(0)
	_qa_dur.remove_at(0)
	_qa_prio.remove_at(0)
	_qa_age.remove_at(0)


func _mark_seen(id: String) -> void:
	if Game.tutorial_mode:
		return   # 연습 굿판: 문장 힌트·이름표·본 힌트 저장은 tutorial_hud 몫(design/17 §7.3)
	if _seen.has(id):
		return
	_seen[id] = true
	if not Game.autotest or DebugTools.arg("ui-save") == "1":
		Save.set_value("ui.hints_seen." + id, true)    # 키 하나만(점지 levelup 이 같은 사전에 쓰는 jeomji 를 덮지 않게)


func _show_now(id: String, text: String, dur: float, prio: int) -> void:
	if Game.tutorial_mode:
		return   # 연습 굿판: 문장 힌트·이름표·본 힌트 저장은 tutorial_hud 몫(design/17 §7.3)
	_mark_seen(id)
	if Game.autotest:
		print("[ui] hint t=%.1f id=%s" % [Game.time_sec(), id])
	_hint_id = id
	_hint_text = text
	_hint_lines = UiKit.wrap(_f_body, UiKit.SZ_BODY, text, HINT_W - 24.0, 2) if _f_body != null else PackedStringArray([text])
	_hint_t = dur
	_hint_in = 0.0
	_hint_prio = prio


## 현재 힌트를 닫는다(조건 충족). 다음 대기 힌트는 짧은 간격 뒤
func _dismiss(id: String) -> void:
	if _hint_id == id and _hint_t > 0.35:
		# 읽을 틈은 준다: 뜬 지 2.5초 전이면 2.5초까지 유지
		_hint_t = minf(_hint_t, maxf(0.35, 2.5 - _hint_in))


func _tag(text: String, world_pos: Vector2, brush: bool = false) -> void:
	if Game.tutorial_mode:
		return   # 연습 굿판: 문장 힌트·이름표·본 힌트 저장은 tutorial_hud 몫(design/17 §7.3)
	var k: int = 0
	var best: float = 99.0
	for i in 4:
		if _tag_t[i] < best:
			best = _tag_t[i]
			k = i
	_tag_text[k] = text
	_tag_pos[k] = world_pos
	_tag_t[k] = 1.2
	_tag_brush[k] = 1 if brush else 0


# ─── 이벤트 ─────────────────────────────────────────────────────────────

## waves 예고 띠(y84)가 같은 내용을 말하면 힌트 줄은 그 뒤로 미룬다(두 줄 동시 금지)
func _on_wave_event(id: StringName, p: Dictionary) -> void:
	match String(id):
		"midboss":
			# 중간보스 티어는 elite_spawned 를 내지 않는다 — 오프스크린 표지는 여기서 붙인다
			_mb_h = int(p.get("handle", -1))
			if _mb_h >= 0:
				_track_off(_mb_h, true)
		"evt_pullil_demo":
			if String(p.get("title_ko", "x")) != "" and Game.time_sec() < 30.0:
				_quiet = maxf(_quiet, 3.8)
		"ring_guide_dotted_circle":
			_quiet = maxf(_quiet, 5.2)
			_waves_ring_until = Game.time_sec() + Data.num("waves_stage1", "telegraph.presenter.ring_guide_sec", 8.0)
			# 띠가 '길닦음' 을 이미 말했다 — 고리 단계로 바로 넘어가되 같은 문장은 반복하지 않는다
			if _ring_step < 2 and guide_on:
				_ring_step = 2
				_seen["ring"] = true
				_ring_hint_again = 30.0


## 다른 모듈이 길잡이 문장을 청한다(Events.hint_requested). UiCopy.HINT 키만 받는다.
func _on_hint_requested(hint_id: StringName) -> void:
	var k: String = String(hint_id)
	if UiCopy.HINT.has(k):
		# trial_faces(시련 두 면 설명)는 고르는 순간에 떠야 한다 — 시련 중 prio<2 는 대기열로 밀려 시련이 끝난 뒤에 떴다(design/19 §3 버그)
		_hint(k, String(UiCopy.HINT[k]), 4.5, 2 if k == "trial_faces" else 1)


func _on_yg_joined(c: int, _sp: StringName) -> void:
	_set_yg(c)


func _on_yg_cheondo(_c: int, r: StringName) -> void:
	var yt: Node = _yeongga()
	_set_yg(int(yt.get("count")) if yt != null else maxi(0, _yg_count - 1))
	if r == &"substitute":
		_yg_hit = 0.3              # 발밑 영가 호 번쩍 — '방패가 줄었다'
		if guide_on and not _seen.has("daesin"):
			_hint("daesin", UiCopy.HINT["daesin"], 3.5, 3)
			var p: Player = Game.player as Player
			if p != null:
				_tag("천도", p.global_position)


func _set_yg(c: int) -> void:
	_yg_count = c
	# 정원은 매번 다시 읽는다(합일 자비 +12 등으로 바뀐다 — '40/24' 처럼 어긋나지 않게)
	var yt: Node = _yeongga()
	if yt != null and yt.has_method("capacity"):
		_yg_cap = maxi(1, int(yt.call("capacity")))
	var mark: int = c / 5
	var full_now: bool = c >= _yg_cap
	var show: bool = mark != _yg_last_mark or (full_now and not _yg_full_said)
	_yg_last_mark = mark
	_yg_full_said = full_now
	if show:
		_yg_label = "%d/%d" % [mini(c, _yg_cap), _yg_cap]
		_yg_label_t = 1.5


func _on_oreum(on: bool) -> void:
	_oreum = on
	_oreum_t = 0.0
	if on:
		_hint("sinmyeong", UiCopy.HINT["sinmyeong"], 3.0, 0)


func _on_weapon_added(id: StringName, _slot: int) -> void:
	var had: bool = _white_owned
	_white_owned = _has_white()
	if not guide_on:
		return
	# 몸주 신령이 내린 시작 흰 무구(at_s > 0): 공수 레인 금색 한 줄 + 머리 위 이름표 + 풀릴 기색 화살표 10초 더
	if _white_owned and not had and Game.time_sec() > 1.0 and _is_start_white(String(id)) and not _seen.has("white_grant"):
		_mark_seen("white_grant")
		var nm: String = UiKit.weapon_name(String(id))
		var hud: Node = get_parent()
		if hud != null and hud.has_method("push_lane"):
			hud.call("push_lane", String(UiCopy.HINT["white_grant"]) % UiCopy.eul(nm), true, 3.0)
		var p: Player = Game.player as Player
		if p != null:
			_tag(nm, p.global_position)
		_arrows_on = true
		_arrows_t = 20.0
		_arrows_keep = 10.0
	if _white_owned and not had and _arrows_on and not _first_haewon:
		# 흰 무구가 들어왔다 — 문장을 바꿔 다시 알린다
		_show_now("pullil", UiCopy.HINT["pullil"], 6.0, 1)


func _is_start_white(wid: String) -> bool:
	var def: Dictionary = Data.character(String(Game.char_id))
	var sw: Variant = def.get("start_weapons", [])
	if sw is Array:
		for e: Variant in sw:
			if e is Dictionary and String((e as Dictionary).get("wpn", "")) == wid and float((e as Dictionary).get("at_s", 0)) > 0.0:
				return true
	return false


## 첫 어둑시니: 공수 레인 「쳐다볼수록 커진다…」 + 오프스크린 표지, 커지거나 오래 보이면 '등을 돌려라'
func _on_elite(h: int, sp: StringName) -> void:
	_track_off(h, false)
	var sid: String = String(sp)
	if not sid.begins_with("elite_eodukssini") or sid.ends_with("__small") or not guide_on:
		return
	if _eod_h < 0 and not _seen.has("eoduk_2"):
		_eod_h = h
		_eod_seen_t = 0.0
	if not _seen.has("eoduk_1"):
		_mark_seen("eoduk_1")
		if Game.autotest:
			print("[ui] lane t=%.1f id=eoduk_1" % Game.time_sec())
		var hud: Node = get_parent()
		if hud != null and hud.has_method("push_lane"):
			hud.call("push_lane", "「%s」" % String(UiCopy.HINT["eoduk_1"]), true, 3.5)


## 19:58 보스 예고: 지금 기운이 부를 손님을 공수 레인에 한 줄(원인 → 결과 잇기). 길잡이 설정과 무관하게 매 판.
func _on_wave_warn(id: StringName, _in_sec: float, _p: Dictionary) -> void:
	if id != &"boss" or _boss_said:
		return
	_boss_said = true
	var em: EnemyManager = Game.enemies as EnemyManager
	var n: float = em.n_ratio() if em != null else 0.5
	var hi: float = Data.num("enemies", "boss_common.form_rule.han_if_N_gte", 0.55)
	var lo: float = Data.num("enemies", "boss_common.form_rule.sal_if_N_lte", 0.45)
	var s: String = UiCopy.BOSS_FORM_HAN if n >= hi else (UiCopy.BOSS_FORM_SAL if n <= lo else UiCopy.BOSS_FORM_MID)
	var hud: Node = get_parent()
	if hud != null and hud.has_method("push_lane"):
		hud.call("push_lane", s, true, 3.5)
	if hud != null and hud.has_method("flash_giun"):
		hud.call("flash_giun", 1.2)


func _on_pullil(h: int, _sp: StringName, _pos: Vector2) -> void:
	if h == _mb_h and h >= 0 and guide_on:
		_hint("midboss_pullil", UiCopy.HINT["midboss_pullil"], 4.0, 3)
	if not guide_on or _seen.has("pullil") or _first_haewon:
		return
	_arrows_on = true
	_arrows_t = 0.0
	if _white_owned:
		_hint("pullil", UiCopy.HINT["pullil"], 7.0, 1)
	else:
		_seen.erase("pullil_wait")
		_hint("pullil_wait", String(UiCopy.HINT["pullil_wait"]) % _next_white_name(), 7.0, 1)
		_seen["pullil"] = true


func _on_killed(_h: int, _sp: StringName, pos: Vector2, kind: StringName, cause: StringName, _tier: StringName) -> void:
	if kind != K.KIND_HAEWON or _first_haewon:
		return
	if Game.autotest:
		print("[ui] first_haewon t=%.1f cause=%s" % [Game.time_sec(), cause])
	_first_haewon = true
	if _arrows_keep <= 0.0:
		_arrows_on = false
	_dismiss("pullil")
	_dismiss("pullil_wait")
	if guide_on and not _seen.has("first_haewon"):
		_tag("解冤", pos)
		if cause == &"ring":
			# 고리로 처음 풀었다: 같은 틱의 ring_closed 문장이 영가까지 함께 말한다(두 줄 연달아 금지)
			_seen["first_haewon"] = true
			_first_by_ring = true
		else:
			_hint("first_haewon", UiCopy.HINT["first_haewon"], 4.5, 1)
	if _ring_step == 0:
		_ring_step = 1
		_ring_wait = 0.0


func _on_ring_closed(_area: int, n: int, centroid: Vector2) -> void:
	_rings_closed += 1
	if _ring_step < 3:
		_ring_step = 3
		_dismiss("ring")
		_dismiss("ring_ready")
		if guide_on and not _seen.has("ring_done"):
			_tag("길닦음", centroid, true)
			# 고리가 첫 해원이 되는 경우(ring_closed 가 같은 틱 enemy_killed 보다 먼저 올 수도 있다): 영가 문장을 합친다
			if n > 0 and not _seen.has("first_haewon"):
				_seen["first_haewon"] = true
				_first_by_ring = true
			var qk: int = _qa_id.find("first_haewon")
			if qk >= 0:
				_qa_id.remove_at(qk)
				_qa_text.remove_at(qk)
				_qa_dur.remove_at(qk)
				_qa_prio.remove_at(qk)
				_qa_age.remove_at(qk)
				_first_by_ring = true
			elif _hint_id == "first_haewon" and _hint_in < 0.3:
				_hint_t = 0.0
				_hint_id = ""
				_first_by_ring = true
			var txt: String = UiCopy.HINT["ring_done_first"] if _first_by_ring else (UiCopy.HINT["ring_done"] if n > 0 else UiCopy.HINT["ring_done_empty"])
			_hint("ring_done", txt, 4.5 if _first_by_ring else 3.5, 1)


func _track_off(h: int, boss: bool) -> void:
	for i in MAX_OFF:
		if _off_h[i] == -1:
			_off_h[i] = h
			_off_boss[i] = 1 if boss else 0
			return
	_off_h[0] = h
	_off_boss[0] = 1 if boss else 0


# ─── 프레임 ─────────────────────────────────────────────────────────────

func _process(delta_real: float) -> void:
	_xf = get_viewport().get_canvas_transform()
	# 일시정지·점지 중에는 길잡이 시계를 멈춘다(덮인 채로 문장이 지나가지 않게). 그리기는 계속.
	var delta: float = 0.0 if Game.is_sim_paused() else delta_real
	_quiet = maxf(0.0, _quiet - delta)
	_beat_k = maxf(0.0, _beat_k - delta * 6.0)
	_yg_label_t = maxf(0.0, _yg_label_t - delta)
	_yg_hit = maxf(0.0, _yg_hit - delta)
	if _oreum:
		_oreum_t += delta
	for i in 4:
		_tag_t[i] = maxf(0.0, _tag_t[i] - delta)
	# 힌트 줄 시간
	# waves 예고 띠가 떠 있는 동안(_quiet) 보던 문장은 잠시 숨기고 시간도 멈춘다(프라이오 3 생존 문장은 예외)
	_trial_busy = _trial_phase_busy()
	_busy = _screen_busy()
	var held: bool = (_quiet > 0.0 and _hint_prio < 3) or (_trial_busy and _hint_prio < 2) or (_busy and _hint_prio < 3)
	if _busy and _hint_prio >= 3 and _hint_t > 1.5:
		_hint_t = 1.5                    # 바쁜 화면: 생존 문장도 1.5초만
	_hint_fade = move_toward(_hint_fade, 0.0 if held else 1.0, delta_real * 6.0)
	if _hint_t > 0.0 and not held:
		_hint_t -= delta
		_hint_in += delta
		if _hint_t <= 0.0:
			_hint_id = ""
			_gap = 1.2
	else:
		_gap = maxf(0.0, _gap - delta)
		if not _qa_id.is_empty() and _gap <= 0.0 and (_quiet <= 0.0 or _qa_prio[0] >= 3) and (not _trial_busy or _qa_prio[0] >= 2) and (not _busy or _qa_prio[0] >= 3):
			if _stale(_qa_id[0]):
				_mark_seen(_qa_id[0])        # 지나간 단계: 기록만 남긴다
			elif _qa_age[0] <= 25.0:
				_show_now(_qa_id[0], _qa_text[0], _qa_dur[0], _qa_prio[0])
			# 25초 넘게 밀린 문장은 기록 없이 버린다(다음 판에 다시)
			_dequeue()
	if not _trial_busy and not _busy:   # 시련·바쁜 화면 동안 미뤄 둔 문장은 나이를 먹지 않는다(끝나고 이어서 보인다)
		for i in _qa_age.size():
			_qa_age[i] += delta
	_guide_steps(delta)
	queue_redraw()


## 화면이 바쁜가(design/18 §2.3): 가운데 슬롯 사용 중(prio≥1) · 피해 숫자 군중 모드 · 화면 잡귀 ≥60 · 합일 중.
## (붓 추임새 prio 0 은 가장자리에 뜨므로 힌트를 막지 않는다)
func _screen_busy() -> bool:
	if Juice.has_method(&"center_busy") and bool(Juice.call(&"center_busy", 1)):
		return true
	if Juice.number_crowd:
		return true
	var vfx: Node = Game.vfx as Node
	var atmo: Variant = vfx.get("atmosphere") if vfx != null else null
	if atmo is Object and int((atmo as Object).get("crowd_n")) >= 60:
		return true
	var td: TrialDirector = _trial_director()
	return td != null and td.ph >= TrialDirector.Ph.HAPIL_OMEN


func _guide_steps(delta: float) -> void:
	var p: Player = Game.player as Player
	if p == null or not guide_on:
		return
	var t: float = Game.time_sec()
	# 1) 이동
	if _step_move == 0 and t >= 1.0 and not _seen.has("move"):
		_step_move = 1
		_move_from = p.global_position
		_hint("move", UiCopy.HINT["move"], 6.0, 3)
	elif _step_move == 1:
		_move_t += delta
		if p.global_position.distance_to(_move_from) >= 2.0 * K.UNIT_PX or _move_t > 8.0:
			_step_move = 2
			_dismiss("move")
	# 2) 풀릴 기색 화살표: 첫 해원까지(최대 30초)
	if _arrows_on:
		_arrows_t += delta
		_arrows_keep = maxf(0.0, _arrows_keep - delta)
		if _arrows_t > 30.0 or (_first_haewon and _arrows_keep <= 0.0):
			_arrows_on = false
		_collect_arrows(p)
	# 4) 고리: 첫 해원 뒤(또는 90초) 대기 → gilbe_ready(닫을 후보, haewon 이 예상선을 그림) 시 '흰 길을 이어 고리를 닫으세요'
	#    후보가 10초 안에 안 생기면 '동그랗게 걸어 보세요' + 걸어 볼 원(풀릴 기색 둘레). 첫 고리 닫힘까지.
	if _ring_step == 0 and t >= 90.0 and not _seen.has("ring"):
		_ring_step = 1
	if _ring_step == 1:
		_ring_wait += delta
		if _hint_t <= 0.0 and _quiet <= 0.0 and not _trial_busy:
			if _ready_ext and _ring_wait >= 1.0:
				_ring_step = 2
				_ring_said_ready = true
				_hint("ring", UiCopy.HINT["ring"], 6.0, 1)
				_ring_hint_again = 30.0
			elif _ring_wait >= 10.0:
				_ring_step = 2
				_hint("ring", UiCopy.HINT["ring_walk"], 6.5, 1)
				_ring_hint_again = 30.0
	if _ring_step == 2:
		# 후보가 처음 생긴 순간 문장을 '점선 끝을 밟으세요' 로 바꿔 한 번 더(짧게)
		if _ready_ext and not _ring_said_ready and not _trial_busy:
			_ring_said_ready = true
			_show_now("ring_ready", UiCopy.HINT["ring"], 4.5, 1)
		_update_ring_center(p)
		_ring_hint_again -= delta
		if _ring_hint_again <= 0.0 and _hint_t <= 0.0 and not _trial_busy:
			_ring_hint_again = 9999.0
			_show_now("ring", UiCopy.HINT["ring_retry"], 6.0, 1)
	# 살기 경고(원귀 전)
	if not _sal_hint and Game.salgi >= 15.0:
		_sal_hint = true
		if not _seen.has("sal"):
			_hint("sal", UiCopy.HINT["sal"], 4.5, 1)
			var hud: Node = get_parent()
			if hud != null and hud.has_method("flash_knots"):
				hud.call("flash_knots", 1.5)
	# 굿판의 기운: 2분(또는 살기 20 이 먼저) — 바를 드러내고 깜빡이며 한 줄
	if not _giun_said and (t >= 120.0 or Game.salgi >= 20.0):
		_giun_said = true
		var hud2: Node = get_parent()
		if hud2 != null and hud2.has_method("reveal_giun"):
			hud2.call("reveal_giun")
		if not _seen.has("giun"):
			_hint("giun", UiCopy.HINT["giun"], 5.5, 0)
			if hud2 != null and hud2.has_method("flash_giun"):
				hud2.call("flash_giun", 1.2)
	# 어둑시니: 커졌거나(배율 2 = 크기 ≥ 1.67) 화면에 8초 넘게 있으면 '등을 돌려라'
	if _eod_h >= 0:
		_check_eoduk(delta)
	# 진화 준비(1초마다 확인): Lv8 + 짝 패시브 → 정예 상자에서 열린다
	_evo_poll -= delta
	if _evo_poll <= 0.0:
		_evo_poll = 1.0
		if not _seen.has("evo_ready") and _any_evolvable():
			_hint("evo_ready", UiCopy.HINT["evo_ready"], 5.0, 2)
	# 흰 무구 없이 4분(런 1~2)
	if not _need_white_checked and t >= 240.0 and Game.kills_haewon == 0 and _runs <= 2:
		_need_white_checked = true
		_hint("need_white", UiCopy.HINT["need_white"], 5.0, 1)


func _trial_director() -> TrialDirector:
	var rr: Node = Game.run_root
	return (rr.get("trials") as TrialDirector) if rr != null else null


func _trial_phase_busy() -> bool:
	var td: TrialDirector = _trial_director()
	return td != null and td.ph >= TrialDirector.Ph.OMEN and td.ph <= TrialDirector.Ph.TRIAL


func _check_eoduk(delta: float) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	var s: int = em.slot_of(_eod_h) if em != null else -1
	if s < 0 or not em.is_alive(s):
		_eod_h = -1
		return
	var sp: Vector2 = _xf * Vector2(em.px[s], em.py[s])
	if Rect2(Vector2.ZERO, size).has_point(sp):
		_eod_seen_t += delta
	if em.rscale[s] >= 2 or _eod_seen_t >= 8.0:
		_eod_h = -1
		_hint("eoduk_2", UiCopy.HINT["eoduk_2"], 5.0, 3)


func _any_evolvable() -> bool:
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm == null:
		return false
	for i in wm.slot_count():
		var w: WeaponBase = wm.weapon_at(i)
		if w != null and wm.can_evolve(w.id):
			return true
	return false


## 가장 가까운 풀릴 기색 MAX_ARROWS 마리(화면 안)
func _collect_arrows(p: Player) -> void:
	_arrow_n = 0
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	var pp: Vector2 = p.global_position
	var lim: float = (14.0 * K.UNIT_PX) * (14.0 * K.UNIT_PX)
	for i in em.active_count:
		var s: int = em.active[i]
		var f: int = em.flags[s]
		if (f & EnemyManager.F_PULLIL) == 0 or (f & EnemyManager.F_DYING) != 0:
			continue
		var d: float = Vector2(em.px[s], em.py[s]).distance_squared_to(pp)
		if d > lim:
			continue
		# 삽입 정렬(가까운 순)
		var k: int = _arrow_n
		if k < MAX_ARROWS:
			_arrow_n += 1
		elif d >= _arrow_d[MAX_ARROWS - 1]:
			continue
		else:
			k = MAX_ARROWS - 1
		while k > 0 and _arrow_d[k - 1] > d:
			_arrow_d[k] = _arrow_d[k - 1]
			_arrow_slots[k] = _arrow_slots[k - 1]
			k -= 1
		_arrow_d[k] = d
		_arrow_slots[k] = s


## 걸어 볼 원의 중심: 가까운 풀릴 기색(화살표 1순위)이 있으면 그 둘레, 없으면 플레이어 앞 3u. 멀어지면 다시 잡는다.
func _update_ring_center(p: Player) -> void:
	var pp: Vector2 = p.global_position
	if _ring_has_center and pp.distance_to(_ring_center) <= 9.0 * K.UNIT_PX:
		return
	var em: EnemyManager = Game.enemies as EnemyManager
	var best: float = (8.0 * K.UNIT_PX) * (8.0 * K.UNIT_PX)
	var found: bool = false
	if em != null:
		for i in em.active_count:
			var s: int = em.active[i]
			var f: int = em.flags[s]
			if (f & EnemyManager.F_PULLIL) == 0 or (f & EnemyManager.F_DYING) != 0:
				continue
			var q: Vector2 = Vector2(em.px[s], em.py[s])
			var d: float = q.distance_squared_to(pp)
			if d < best:
				best = d
				_ring_center = q
				found = true
	if not found:
		var dir: Vector2 = p.last_move_dir.normalized() if p.last_move_dir.length_squared() > 0.01 else Vector2.DOWN
		_ring_center = pp + dir * 3.0 * K.UNIT_PX
	_ring_has_center = true


# ─── 그리기 ─────────────────────────────────────────────────────────────

func _w2s(p: Vector2) -> Vector2:
	return (_xf * p).round()


func _draw() -> void:
	var p: Player = Game.player as Player
	if p != null and not p.dead:
		_draw_ring_guide(p)
		_draw_arrows()
		_draw_feet(p)
	_draw_offscreen()
	_draw_tags()
	_draw_hint()


func _draw_feet(p: Player) -> void:
	var foot: Vector2 = _w2s(Vector2(p.render_pos))
	var c: Vector2 = foot + Vector2(0, -7)
	# 왼쪽: 신명(아래 → 위 채움). 오름 중이면 오방 순환 + 줄어듦
	var sk: float = Game.sinmyeong
	var fill: Color = UiKit.HANJI.lightened(0.15 * _beat_k)
	if _oreum:
		fill = HUD_OBANG[int(_oreum_t * 8.0) % 5]
	UiKit.draw_arc_pts(self, c, _arc_l, sk, fill, Color(UiKit.MEOK, 0.5), 2.0)
	# 징 문양(위 끝 4×4)
	var top: Vector2 = (c + _arc_l[_arc_l.size() - 1]).floor() + Vector2(-1, -3)
	draw_rect(Rect2(top, Vector2(4, 4)), UiKit.MEOK)
	draw_rect(Rect2(top + Vector2(1, 1), Vector2(2, 2)), UiKit.HWANG_HI if sk >= 0.999 or _beat_k > 0.6 else UiKit.HWANG_DK)
	# 오른쪽: 영가 행렬(0 이면 숨김, 가득 = 황)
	if _yg_count > 0 or _yg_hit > 0.0:
		var yk: float = maxf(float(_yg_count) / float(_yg_cap), 0.05 if _yg_hit > 0.0 else 0.0)
		var yc: Color = UiKit.HWANG_HI if _yg_hit > 0.0 else (UiKit.HWANG if _yg_count >= _yg_cap else UiKit.HANJI)
		UiKit.draw_arc_pts(self, c, _arc_r, yk, yc, Color(UiKit.MEOK, 0.5), 2.0)
		if _yg_label_t > 0.0:
			var lp: Vector2 = foot + Vector2(16, 10)   # 몸 밖(발 오른쪽 아래) — 무당 몸을 덮지 않는다
			var la: float = clampf(_yg_label_t, 0.0, 1.0)
			# 숫자 뒤 먹 받침: 바로 뒤를 따르는 영가 행렬(흰 몸) 위에서 읽히게
			var lw: float = roundf(_f_tiny.get_string_size(_yg_label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY).x)
			draw_rect(Rect2(lp.x - 2.0, lp.y - float(UiKit.SZ_TINY) + 1.0, lw + 4.0, float(UiKit.SZ_TINY) + 2.0), Color(UiKit.MEOK, 0.6 * la))
			UiKit.text(self, _f_tiny, UiKit.SZ_TINY, lp, _yg_label, Color(yc, la))
	# 정기 바(발 아래 24×3)
	var hk: float = Game.hp / maxf(Game.hp_max, 1.0)
	var br: Rect2 = Rect2(foot.x - 12, foot.y + 4, 24, 3)
	var low: bool = hk <= 0.3
	draw_rect(br.grow(1.0), UiKit.MEOK)
	draw_rect(br, UiKit.MEOK_2)
	var fw: float = roundf(br.size.x * clampf(hk, 0.0, 1.0))
	var pulse: bool = low and fposmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4
	if fw > 0.0:
		draw_rect(Rect2(br.position, Vector2(fw, br.size.y)), UiKit.JEOK_HI if pulse else (UiKit.JEOK if low else UiKit.HANJI))


const HUD_OBANG: Array[Color] = [Color("2a5caa"), Color("c8322d"), Color("e8b931"), Color("e9dcc0"), Color("1a1a1a")]


func _draw_arrows() -> void:
	if not _arrows_on or _arrow_n == 0:
		return
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	var bob: float = roundf(sin(Time.get_ticks_msec() / 1000.0 * TAU * 2.0) * 2.0)
	for i in _arrow_n:
		var s: int = _arrow_slots[i]
		if not em.is_alive(s) or (em.flags[s] & EnemyManager.F_PULLIL) == 0:
			continue
		var bh: int = 28
		var si: int = em.species[s]
		if si >= 0 and si < em.sp_body_h.size():
			bh = em.sp_body_h[si]
		var sp: Vector2 = _w2s(Vector2(em.px[s], em.py[s])) + Vector2(0, -float(bh) - 6.0 + bob)
		# 아래를 가리키는 흰 셰브론(7px) + 먹 외곽
		for row in 4:
			var half: float = 3.0 - float(row)
			draw_rect(Rect2(sp + Vector2(-half - 1.0, float(row) - 1.0), Vector2(half * 2.0 + 3.0, 3.0)), UiKit.MEOK)
		for row in 4:
			var half2: float = 3.0 - float(row)
			draw_rect(Rect2(sp + Vector2(-half2, float(row)), Vector2(half2 * 2.0 + 1.0, 1.0)), UiKit.BAEK)


func _draw_ring_guide(_p: Player) -> void:
	# 예상선·매듭·zone 은 ring_closure(haewon)가, 01:30 안내 원은 waves 가 그린다 — 여기서는 그 둘이 없을 때만 '걸어 볼 원'
	if _ring_step != 2 or not _ring_has_center or _ready_ext or Game.time_sec() < _waves_ring_until:
		return
	var ph: float = Time.get_ticks_msec() / 1000.0
	var c: Vector2 = _w2s(_ring_center)
	var r: float = 2.4 * K.UNIT_PX * _xf.get_scale().x * (1.0 + 0.04 * _beat_k)
	# 점선 원(20 대시, 천천히 시계 방향으로 흐름) + 먹 그림자
	var n: int = 40
	var rot: float = ph * 0.5
	for i in range(0, n, 2):
		var a0: float = rot + TAU * float(i) / float(n)
		var a1: float = rot + TAU * float(i + 1) / float(n)
		var q0: Vector2 = (c + Vector2(cos(a0), sin(a0) * 0.75) * r).round()
		var q1: Vector2 = (c + Vector2(cos(a1), sin(a1) * 0.75) * r).round()
		draw_line(q0 + Vector2(0, 1), q1 + Vector2(0, 1), Color(UiKit.MEOK, 0.55), 2.0)
		draw_line(q0, q1, Color(UiKit.BAEK, 0.6 + 0.3 * _beat_k), 2.0)
	# 도는 방향 표지: 원 위를 달리는 구슬 3개(꼬리 작아짐) — '이 둘레를 한 바퀴'
	for k in 3:
		var ang: float = ph * 1.8 - float(k) * 0.16
		var q: Vector2 = (c + Vector2(cos(ang), sin(ang) * 0.75) * r).round()
		var sz: float = 4.0 - float(k)
		draw_rect(Rect2(q - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(UiKit.BAEK, 1.0 - 0.25 * float(k)))


func _draw_offscreen() -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	var w: float = size.x
	var h: float = size.y
	var inner: Rect2 = Rect2(12, 12, w - 24, h - 24)
	var ctr: Vector2 = Vector2(w * 0.5, h * 0.5)
	for i in MAX_OFF:
		var hd: int = _off_h[i]
		if hd < 0:
			continue
		var s: int = em.slot_of(hd)
		if s < 0 or not em.is_alive(s):
			_off_h[i] = -1
			continue
		var sp: Vector2 = _xf * Vector2(em.px[s], em.py[s])
		if Rect2(0, 0, w, h).has_point(sp):
			continue
		var d: Vector2 = sp - ctr
		var tx: float = (inner.size.x * 0.5) / maxf(absf(d.x), 0.001)
		var ty: float = (inner.size.y * 0.5) / maxf(absf(d.y), 0.001)
		var q: Vector2 = (ctr + d * minf(tx, ty)).round()
		var col: Color = UiKit.JEOK_HI if _off_boss[i] == 1 else UiKit.HWANG
		UiKit.draw_diamond(self, q, 5.0, UiKit.MEOK)
		UiKit.draw_diamond(self, q, 4.0, col)
		var dir: Vector2 = d.normalized()
		var tip: Vector2 = q + dir * 9.0
		var side: Vector2 = Vector2(-dir.y, dir.x) * 3.0
		var base: Vector2 = q + dir * 5.0
		draw_line(tip, base + side, col, 1.0)
		draw_line(tip, base - side, col, 1.0)
		draw_line(base + side, base - side, col, 1.0)


func _draw_tags() -> void:
	var n_rc: int = 0
	for i in 4:
		if _tag_t[i] <= 0.0:
			continue
		var el: float = 1.2 - _tag_t[i]
		var a: float = clampf(_tag_t[i] / 0.3, 0.0, 1.0)
		# 이름표는 vfx 글자 표식("해원" -몸높이-14)보다 위에 — 겹치지 않게
		var pos: Vector2 = _w2s(_tag_pos[i]) + Vector2(0, (-34.0 if _tag_brush[i] == 1 else -54.0) - roundf(el * 10.0))
		# 반투명 먹 받침 + 한지 위아래 줄: 영가 행렬(흰 몸)·해원 빛 위에서도 글자가 묻히지 않게
		var fz: int = 40 if _tag_brush[i] == 1 else 15
		var ff: Font = _f_brush if _tag_brush[i] == 1 else _f_big
		var tw: float = roundf(ff.get_string_size(_tag_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fz).x)
		var bh: float = 30.0 if _tag_brush[i] == 1 else 17.0
		var br: Rect2 = Rect2(pos.x - roundf(tw * 0.5) - 6.0, pos.y - bh + (6.0 if _tag_brush[i] == 1 else 3.0), tw + 12.0, bh)
		# 이름표끼리 겹치면(고리 '길닦음' 과 '천도' 가 같은 자리에 — 리뷰 11-24 t1000_midboss 10:15) 먼저 그린 것 위로 쌓는다
		for _pass in 3:
			var moved: bool = false
			for j in n_rc:
				if br.intersects(_tag_rc[j]):
					var dy: float = br.end.y - _tag_rc[j].position.y + 2.0
					br.position.y -= dy
					pos.y -= dy
					moved = true
			if not moved:
				break
		if n_rc < 4:
			_tag_rc[n_rc] = br
			n_rc += 1
		draw_rect(br, Color(UiKit.MEOK, 0.55 * a))
		draw_rect(Rect2(br.position.x, br.position.y, br.size.x, 1), Color(UiKit.HANJI_4, 0.8 * a))
		draw_rect(Rect2(br.position.x, br.end.y - 1.0, br.size.x, 1), Color(UiKit.HANJI_4, 0.8 * a))
		UiKit.text_outline(self, ff, fz, pos, _tag_text[i], Color(UiKit.BAEK, a), 1, 2 if _tag_brush[i] == 1 else 1)


func _draw_hint() -> void:
	if _hint_t <= 0.0 or _hint_text == "":
		return
	var a: float = clampf(_hint_in / 0.15, 0.0, 1.0) * clampf(_hint_t / 0.35, 0.0, 1.0) * _hint_fade
	if a <= 0.0:
		return
	# 왼쪽 아래 가장자리(x 8, y h−58, 폭 ≤260, 2줄): 화면 가운데·무당 안전 상자·연속 굿 칩을 비운다(design/18 §2.1)
	var rise: float = roundf((1.0 - clampf(_hint_in / 0.15, 0.0, 1.0)) * 4.0)
	var lines: PackedStringArray = _hint_lines if not _hint_lines.is_empty() else PackedStringArray([_hint_text])
	var tw: float = 0.0
	for ln: String in lines:
		tw = maxf(tw, _f_body.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x)
	var y: float = size.y - 58.0 + rise
	var r: Rect2 = Rect2(8.0, y - 2.0, minf(HINT_W, tw + 24.0), 5.0 + 13.0 * float(lines.size()))
	vis_rects["pos:hint"] = [r, Engine.get_process_frames()]
	draw_rect(r, Color(UiKit.MEOK, 0.72 * a))
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), Color(UiKit.HANJI_4, a))
	draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1), Color(UiKit.HANJI_4, a))
	# 왼쪽 표지: 붓 점(황) — 길잡이 문장 표시
	UiKit.draw_diamond(self, Vector2(r.position.x + 7.0, r.position.y + 8.0), 2.0, Color(UiKit.HWANG, a))
	for li in lines.size():
		UiKit.text(self, _f_body, UiKit.SZ_BODY, Vector2(r.position.x + 16.0, y + 11.0 + 13.0 * float(li)), lines[li], Color(UiKit.HANJI_UI, a), 0)
