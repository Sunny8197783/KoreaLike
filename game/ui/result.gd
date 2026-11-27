extends Control
## 정산 화면('이번 판에서 얻은 것'). 소유: meta(이 화면 파일만, ARCHITECTURE §5 예외). design/11 §9.4 → design/19 §7(메타 루프).
## 1막 결말(붓 제목·촛불) → 2막 장부(진행 막대: 시각/20:00·첫 시험·큰 귀신·역려·최고 기록, 풀어 줌/처치 같은 크기, 무기)
## → 환산(풀어 준 넋 → 공덕, 모은 엽전 → 엽전: 숫자 카운트업, 줄마다 '딸깍') → 사연 한 줄 → '신당에서 지금 할 수 있는 것'
## → 다음 목표 → 3막 한지 카드(해금·사연) → 버튼 [신당으로 (강화 N)] [다시 굿판]. 살 수 있는 게 있으면 신당이 기본 포커스.
## 입력: setup(result)(main.gd) + 세이브 ui.last_run(RunLedger 보충 통계) + Save.settlement_view()(메타 정산 묶음).
## Enter/Esc 는 연출 중이면 끝까지 건너뛰기, 끝났으면 버튼(Esc = 신당/타이틀).
## 글: 한글은 10px 이상(design/19 §4.1), 한자 없음. 화면 재화는 넋·공덕·엽전 셋.

signal retry_requested
signal title_requested

const T_PANEL: float = 0.6          # 2막 장부
const T_ROLL: float = 0.8           # 풀어 줌·처치 롤링
const T_BTN: float = 1.3            # 버튼(마우스 입력 허용)
const T_CONV: float = 1.35          # 환산 줄 시작
const ROW_GAP: float = 0.3          # 환산 줄 사이
const ROW_FROM: float = 0.35        # 왼쪽 수(넋·엽전) 굴림
const ROW_TO: float = 0.45          # 오른쪽 수(공덕·엽전) 굴림(왼쪽 0.15초 뒤 시작)
const CARD_GAP: float = 0.32        # 한지 카드 사이
const CARD_W: float = 104.0
const CARD_H: float = 78.0
const PANEL_W: float = 400.0
const PANEL_Y: float = 72.0
const RUN_END_S: float = 1200.0     # 20:00
const SEAL_FALLBACK: Dictionary = {"巫": "무", "壇": "강", "錄": "도", "願": "의", "緣": "넋", "辟": "처"}
## 진행 막대 눈금: 시험(금 점) 3:00·6:30·12:30·15:30, 큰 귀신 10:00(주 점), 신령 모두 내림 18:00(백 점), 역려 20:00(주 마름모)
const TICKS: Array = [[180.0, "trial"], [390.0, "trial"], [600.0, "mboss"], [750.0, "trial"], [930.0, "trial"], [1080.0, "hapil"], [1200.0, "boss"]]

var result: Dictionary = {}
var _last: Dictionary = {}
var _t: float = 0.0
var _focus: int = 0
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_big: Font
var _f_brush: Font
var _paper: Texture2D
var _vignette: Texture2D
var _title: String = ""
var _ending: String = ""
var _tip: PackedStringArray = PackedStringArray()
var _weapons: Array[Dictionary] = []
var _news: Array = []
var _victory: bool = false
var _haewon: int = 0
var _toechi: int = 0
var _ratio_line: String = ""
var _btn_labels: PackedStringArray = PackedStringArray(["신당으로", "다시 굿판"])
var _primary: bool = false            # 신당 버튼을 주색으로(살 수 있는 게 있음)
var _lock_left: float = 0.4           # 진입 직후 입력 잠금(사망 직전 연타가 먹히지 않게)
# 진행 막대
var _time_s: float = 0.0
var _best_s: float = 0.0
var _new_best: bool = false
var _marks: Array[Dictionary] = []    # {label, done}
# 메타 환산(Save.settlement_view)
var _conv: Array[Dictionary] = []     # {from, from_n, to, to_n, gold, t0, col, row}
var _mult_line: String = ""
var _wallet_line: String = ""
var _err_line: String = ""
var _sayeon: String = ""
var _can: Array[String] = []          # '신당에서 지금 할 수 있는 것' 줄(최대 2)
var _can_ok: bool = false             # 살 수 있는 게 있다(아니면 '○○까지 N 남음')
var _goal: String = ""
var _next_tick_s: float = -1.0           # 다음 목표가 막대 눈금 하나면 그 시각(금 테로 깜박 + '다음')
var _cards: Array[Dictionary] = []    # {kind, seal, title, body:PackedStringArray, reward, t0, side, slot}
var _t_cards: float = 0.0             # 카드·할 수 있는 것 시작
var _t_end: float = 2.6               # 연출 끝(건너뛰기 목표)
var _cue_done: int = 0                # 이미 울린 소리 비트(줄 시작·착지·카드)
var _cards_marked: bool = false
# 세로 배치(패널 안 y, _build 에서 정함)
var _y_conv: float = 0.0
var _y_say: float = 0.0
var _y_can: float = 0.0
var _y_goal: float = 0.0
var _y_tip: float = 0.0
var _panel_h: float = 200.0


func setup(p_result: Dictionary) -> void:
	result = p_result


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.setup_fonts()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_big = UiKit.big()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")
	_vignette = UiKit.skin("vignette.png")
	var lr: Variant = Save.get_value("ui.last_run", {})
	_last = lr if lr is Dictionary else {}
	_build()
	Audio.play_sfx(&"sfx_ui_result", &"UI")
	print("[result] focus=%s affordable=%d next_goal=%s sayeon=%s cards=%d" % [
		"sindang" if _focus == 0 else "retry", _can.size() if _can_ok else 0, _goal, "yes" if _sayeon != "" else "no", _cards.size()])


func _g(key: String, default: Variant = 0) -> Variant:
	if result.has(key):
		return result[key]
	return _last.get(key, default)


func _build() -> void:
	_victory = bool(_g("victory", false))
	var ending: String = String(_last.get("ending", result.get("ending", "")))
	_time_s = float(_g("time_sec", 0.0))
	if ending == "abandon":
		_title = "굿판을 거두었다"
		_ending = "굿을 멈추고 판을 거두었다"
	elif ending == "timeout" or ending == "hard_cap":
		# 보스를 풀지 못해 저승사자가 거둬 감(23:00 강제 사자) — 사망이 아니다 (core 통합)
		_title = "사자가 판을 거두었다"
		_ending = "역려를 다 풀지 못했다 — 저승사자가 굿판을 거두었다"
	elif _victory:
		_title = "굿이 끝났다"
		_ending = "20:00까지 지켜 냈다 — 넋길이 열렸다"
	else:
		_title = "굿판이 흩어졌다"
		_ending = "굿판에서 쓰러졌다 — 다음 판은 더 강해진다"
	_ending = _fit(_f_body, UiKit.SZ_BODY, _ending, PANEL_W - 28.0 - 96.0)
	_haewon = int(_g("haewon", 0))
	_toechi = int(_g("toechi", 0))
	var tot: int = _haewon + _toechi
	var nr: float = 0.5 if tot == 0 else float(_haewon) / float(tot)
	var face: String = "반반의 얼굴"
	if nr >= 0.55:
		face = "한의 얼굴"
	elif nr <= 0.45:
		face = "살의 얼굴"
	_ratio_line = "풀어 줌 %d%% — 역려: %s" % [int(roundf(nr * 100.0)), face]
	_news = _last.get("new_best", [])
	var ws: Variant = _last.get("weapons", [])
	if ws is Array:
		for e: Variant in ws:
			var parts: PackedStringArray = String(e).split(":")
			var id: String = parts[0]
			_weapons.append({"id": id, "lv": int(parts[1]) if parts.size() > 1 else 1,
				"icon": UiKit.weapon_icon(id, true), "white": UiKit.weapon_color(id) == "white"})
	# '다음 굿판의 길'(첫 세 판, onboarding_hints.death_cards_first3)
	var runs: int = int(Save.get_value("ui.runs", 1))
	var tip: String = ""
	if ending == "timeout" and runs <= 3:
		tip = UiCopy.DEATH_TIP_TIMEOUT
	elif not _victory and runs <= 3 and ending not in ["timeout", "hard_cap", "abandon"]:
		if int(_last.get("rings", 1)) == 0:
			tip = UiCopy.DEATH_TIP_NO_RING
		elif nr < 0.15:
			tip = UiCopy.DEATH_TIP_LOW_HAEWON
		elif nr > 0.85:
			tip = UiCopy.DEATH_TIP_HIGH_HAEWON
		elif _weapons.size() <= 3:
			tip = UiCopy.DEATH_TIP_FEW_WEAPONS
	if tip != "":
		_tip = UiKit.wrap(_f_small, UiKit.SZ_SMALL, "도움말: " + tip, PANEL_W - 28.0, 2)
	_build_settlement()
	_layout()


## 메타 정산 → 진행 막대·환산 줄·지갑 줄·사연·할 수 있는 것·다음 목표·한지 카드(시간표 포함).
func _build_settlement() -> void:
	var sv: Dictionary = Save.settlement_view()
	# 진행 막대(정산이 없으면 결과 사전만으로)
	var pg: Dictionary = sv.get("progress", {}) if sv.get("progress") is Dictionary else {}
	var trials: int = int(pg.get("trials", 1 if _time_s >= 225.0 else 0))
	var mboss: bool = bool(pg.get("mboss", false))
	var boss: bool = bool(pg.get("boss", _victory))
	_best_s = float(pg.get("best_s", _time_s))
	_new_best = bool(pg.get("new_best", false))
	_marks = [{"label": "첫 시험", "done": trials >= 1, "t": 180.0}, {"label": "큰 귀신", "done": mboss, "t": 600.0}, {"label": "역려", "done": boss, "t": RUN_END_S}]
	var t: float = T_CONV
	if not sv.is_empty():
		if not bool(sv.get("ok", false)):
			_err_line = String(sv.get("error", "")) if String(sv.get("error", "")) != "" else "기록이 저장되지 않았습니다"
		else:
			var extra: int = 0
			for r: Variant in sv.get("rows", []):
				if not (r is Dictionary):
					continue
				var d: Dictionary = r
				var main_row: bool = _conv.size() < 2 and extra == 0 and int(d.get("from_n", 0)) >= 0
				var col: int = 0 if main_row else 1
				var row: int = _conv.size() if main_row else extra
				if not main_row:
					if extra >= 2:
						continue
					extra += 1
				_conv.append({"from": String(d.get("from", d.get("label", ""))), "from_n": int(d.get("from_n", 0)),
					"to": String(d.get("to", "")), "to_n": int(d.get("to_n", 0)), "gold": bool(d.get("gold", false)),
					"t0": t, "col": col, "row": row})
				t += ROW_GAP
			var ml: PackedStringArray = PackedStringArray()
			for m: Variant in sv.get("mults", []):
				ml.append(String(m))
			while ml.size() > 0 and _f_small.get_string_size("  ·  ".join(ml), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x > 170.0:
				ml.resize(ml.size() - 1)
			_mult_line = "  ·  ".join(ml)
			_wallet_line = "가진 것  공덕 %s  ·  엽전 %s" % [_comma(int(sv.get("wallet_G", 0))), _comma(int(sv.get("wallet_B", 0)))]
			# 사연 한 줄
			var sy: Dictionary = sv.get("sayeon", {}) if sv.get("sayeon") is Dictionary else {}
			if String(sy.get("quote", "")) != "":
				# 인용을 먼저 줄이고 '— 이름'은 남긴다(말한 사람이 '…'로 잘리던 것)
				var who: String = " — " + String(sy.get("who", "")) if String(sy.get("who", "")) != "" else ""
				var ww: float = _f_body.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
				_sayeon = _fit(_f_body, UiKit.SZ_BODY, "「%s」" % String(sy["quote"]), PANEL_W - 28.0 - ww) + who
			# 신당에서 지금 할 수 있는 것
			var aff: Array = sv.get("affordable", []) if sv.get("affordable") is Array else []
			for a: Variant in aff:
				if _can.size() >= 2 or not (a is Dictionary):
					continue
				var ad: Dictionary = a
				_can.append(_fit(_f_body, UiKit.SZ_BODY, "%s — %s  (%s %s)" % [String(ad["name"]), String(ad["effect"]), String(ad["cur_ko"]), _comma(int(ad["cost"]))], PANEL_W - 44.0))
			_can_ok = not _can.is_empty()
			if not _can_ok:
				var np: Dictionary = sv.get("nearest", {}) if sv.get("nearest") is Dictionary else {}
				if not np.is_empty():
					_can.append(_fit(_f_body, UiKit.SZ_BODY, "%s까지 %s %s 남음 — %s" % [String(np["name"]), String(np["cur_ko"]), _comma(int(np["need"])), String(np["effect"])], PANEL_W - 44.0))
			var up_n: int = int(sv.get("upgrades_n", 0))
			var ng: Dictionary = sv.get("next_goal", {}) if sv.get("next_goal") is Dictionary else {}
			_goal = _fit(_f_bold, UiKit.SZ_BODY, "다음 목표: " + String(ng.get("long", ng.get("short", ""))), PANEL_W - 44.0) if not ng.is_empty() else ""
			_next_tick_s = float({"trial1": 180.0, "trial2": 390.0, "mboss": 600.0, "hapil": 1080.0, "boss": RUN_END_S}.get(String(ng.get("id", "")), -1.0))
			_primary = _can_ok
			# 단추 숫자 = 지금 살 수 있는 것 수(위 목록과 같은 셈). 강화 칸 총수(up_n)는 살 수 없는 것까지 세어 어긋나 보였다.
			if _can_ok:
				_btn_labels[0] = "신당으로 (살 것 %d)" % aff.size()
			elif up_n > 0:
				_btn_labels[0] = "신당으로"
	if not Save.lobby_route():
		_btn_labels[0] = "타이틀로"
		_primary = false
	_focus = 0 if _primary else 1
	if not _conv.is_empty():
		t = float(_conv[_conv.size() - 1]["t0"]) + ROW_TO + 0.2 + 0.15
	_t_cards = maxf(t, T_CONV)
	var cards: Variant = sv.get("cards", []) if not sv.is_empty() else []
	var i: int = 0
	if cards is Array:
		for c: Variant in cards:
			if not (c is Dictionary) or i >= 4:
				continue
			var cd: Dictionary = c
			var seal: String = String(cd.get("seal", "넋"))
			if SEAL_FALLBACK.has(seal):
				seal = String(SEAL_FALLBACK[seal])
			_cards.append({"kind": String(cd.get("kind", "")), "seal": seal, "title": String(cd.get("title", "")),
				"body": UiKit.wrap(_f_small, UiKit.SZ_SMALL, String(cd.get("body", "")), CARD_W - 12.0, 4),
				"reward": String(cd.get("reward", "")), "t0": _t_cards + float(i) * CARD_GAP,
				"side": 1 if i % 2 == 0 else -1, "slot": i >> 1})
			i += 1
	_t_end = maxf(2.6, (_t_cards + float(_cards.size() - 1) * CARD_GAP + 0.45) if not _cards.is_empty() else _t_cards + 0.3)


## 패널 안 세로 배치(있는 칸만 쌓는다).
func _layout() -> void:
	var y: float = 112.0                 # 환산 첫 줄 기준선
	_y_conv = y
	if not _conv.is_empty() or _err_line != "":
		y += 14.0 * 2.0 + 16.0           # 두 줄 + 지갑 줄
	_y_say = y + 6.0
	if _sayeon != "":
		y += 18.0
	elif not _tip.is_empty():
		_y_tip = y + 6.0
		y += 13.0 * float(_tip.size()) + 4.0
	_y_can = y + 10.0
	if not _can.is_empty():
		y += 16.0 + 14.0 * float(_can.size())
	_y_goal = y + 12.0
	if _goal != "":
		y += 18.0
	_panel_h = y + 6.0


static func _fit(f: Font, sz: int, s: String, w: float) -> String:
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= w:
		return s
	var t: String = s
	while t.length() > 1 and f.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > w:
		t = t.left(t.length() - 1)
	return t + "…"


func _process(delta: float) -> void:
	_t += delta
	_lock_left = maxf(0.0, _lock_left - delta)
	_cues()
	queue_redraw()


## 소리: 환산 줄 착지마다 '딸깍', 한지 카드마다 종이 넘김(+해금 카드는 인장 소리). 건너뛰면 남은 소리는 울리지 않는다.
func _cues() -> void:
	for i in _conv.size():
		var bit: int = 1 << i
		if _cue_done & bit == 0 and _t >= float(_conv[i]["t0"]) + 0.15 + ROW_TO:
			_cue_done |= bit
			Audio.play_sfx(&"sfx_ui_settle_tick", &"UI")
	for i in _cards.size():
		var bit2: int = 1 << (8 + i)
		if _cue_done & bit2 == 0 and _t >= float(_cards[i]["t0"]):
			_cue_done |= bit2
			Audio.play_sfx(&"sfx_ui_singirok_page", &"UI")
		var bit3: int = 1 << (16 + i)
		if _cue_done & bit3 == 0 and _t >= float(_cards[i]["t0"]) + 0.18:
			_cue_done |= bit3
			if String(_cards[i]["kind"]) in ["inyeon", "open", "uiroe"]:
				Audio.play_sfx(&"sfx_ui_unlock", &"UI")
	if not _cards_marked and not _cards.is_empty() and _t >= _t_cards:
		_cards_marked = true
		Save.last_settlement["result_cards_shown"] = true   # 신당이 같은 사연 알림을 다시 띄우지 않게


func _skip() -> void:
	_t = _t_end
	_cue_done = 0x7fffffff           # 건너뛴 연출의 소리를 한꺼번에 몰아 울리지 않는다
	if not _cards.is_empty():
		_cards_marked = true
		Save.last_settlement["result_cards_shown"] = true


func _unhandled_input(event: InputEvent) -> void:
	if _lock_left > 0.0:
		if event is InputEventKey or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_focus = 0
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_focus = 1
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		if _t < _t_end:
			_skip()          # 연출 건너뛰기
		else:
			_press(_focus)
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"cancel"):
		if _t < _t_end:
			_skip()          # 연출 중 Esc 는 건너뛰기만(결과를 못 보고 넘어가지 않게)
		else:
			_press(0)
	else:
		return
	get_viewport().set_input_as_handled()


## 0 = 신당으로(신당이 안 열렸으면 타이틀), 1 = 다시 굿판
func _press(i: int) -> void:
	Audio.play_sfx(&"sfx_ui_confirm", &"UI")
	if i == 1:
		retry_requested.emit()
	else:
		title_requested.emit()


func _btn_rect(i: int) -> Rect2:
	var cx: float = roundf(size.x * 0.5)
	if i == 0:
		return Rect2(cx - 164, size.y - 30, 184, 22)
	return Rect2(cx + 32, size.y - 30, 132, 22)


func _gui_input(event: InputEvent) -> void:
	if _lock_left > 0.0 or _t < T_BTN:
		return
	if event is InputEventMouseMotion:
		for i in 2:
			if _btn_rect(i).has_point((event as InputEventMouseMotion).position):
				_focus = i
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for i in 2:
			if _btn_rect(i).has_point((event as InputEventMouseButton).position):
				_press(i)
				accept_event()
				return
		if _t < _t_end:
			_skip()
			accept_event()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = roundf(w * 0.5)
	draw_rect(Rect2(0, 0, w, h), UiKit.MEOK)
	# 촛불(1막): 제목 뒤 작은 불꽃, 0.5Hz 깜박
	var fl: float = 0.85 + 0.15 * sin(_t * TAU * 0.5) + 0.05 * sin(_t * 23.0)
	var cy: float = 18.0
	for k in 4:
		var rr: float = 34.0 * fl * (1.0 - float(k) * 0.22)
		draw_circle(Vector2(cx, cy + 14.0), rr, Color(UiKit.HWANG_DK, 0.04 + 0.025 * float(k)))
	if _vignette != null:
		draw_texture_rect(_vignette, Rect2(0, 0, w, h), false, Color(1, 1, 1, 0.5))
	# 1막 제목 + 부제
	var a1: float = clampf(_t / 0.5, 0.0, 1.0)
	var ty: float = 44.0 - roundf((1.0 - UiKit.ease_out_cubic(a1)) * 8.0)
	UiKit.text_outline(self, _f_brush, 36, Vector2(cx, ty), _title, Color(UiKit.HANJI_UI if _victory else UiKit.HANJI, a1), 1, 2)
	UiKit.text(self, _f_bold, UiKit.SZ_BODY, Vector2(cx, ty + 20.0), "이번 판에서 얻은 것", Color(UiKit.HWANG_HI, a1), 1)
	# 2막 장부
	var a2: float = clampf((_t - T_PANEL) / 0.3, 0.0, 1.0)
	if a2 <= 0.0:
		return
	var pr: Rect2 = Rect2(cx - PANEL_W * 0.5, PANEL_Y, PANEL_W, _panel_h)
	pr.position.y += roundf((1.0 - UiKit.ease_out_cubic(a2)) * 10.0)
	draw_rect(Rect2(pr.position + Vector2(3, 4), pr.size), Color(UiKit.MEOK_1, 0.8 * a2))
	UiKit.draw_hanji_panel(self, pr, _paper)
	UiKit.draw_dancheong(self, Rect2(pr.position.x + 2, pr.position.y + 2, pr.size.x - 4, 4))
	var ink: Color = UiKit.INK
	var x0: float = pr.position.x + 14.0
	var iw: float = pr.size.x - 28.0
	var py: float = pr.position.y
	draw_string(_f_body, Vector2(x0, py + 20), _ending, HORIZONTAL_ALIGNMENT_LEFT, iw, UiKit.SZ_BODY, ink)
	_draw_progress(Rect2(x0, py + 27, iw, 6))
	draw_rect(Rect2(x0, py + 52, iw, 1), UiKit.HANJI_4)
	# 풀어 줌 · 처치(같은 크기·굵기, 숫자 롤링)
	var roll: float = UiKit.ease_out_cubic(clampf((_t - T_ROLL) / 0.9, 0.0, 1.0))
	var ry: float = py + 70.0
	var rows: Array = [["풀어 줌", _haewon, true, "haewon"], ["처치", _toechi, false, "toechi"]]
	for i in 2:
		var rw: Array = rows[i]
		var rx: float = x0 + float(i) * 118.0
		UiKit.draw_kind_mark(self, Vector2(rx + 5, ry - 5), 3.5, bool(rw[2]))
		draw_string(_f_body, Vector2(rx + 13, ry), String(rw[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink if bool(rw[2]) else UiKit.JEOK_DK)
		var lw: float = _f_body.get_string_size(String(rw[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		var n: int = int(roundf(float(rw[1]) * roll))
		draw_string(_f_big, Vector2(rx + 17 + lw, ry + 1), _comma(n), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BIG, ink)
		if _news.has(String(rw[3])) and roll >= 1.0:
			var nw: float = _f_big.get_string_size(_comma(int(rw[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BIG).x
			_new_seal(Vector2(rx + 20 + lw + nw, ry - 12))
	draw_string(_f_small, Vector2(x0, ry + 15), _ratio_line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HANJI_5)
	# 무기(오른쪽)
	var wx: float = x0 + 240.0
	for i in _weapons.size():
		var wd: Dictionary = _weapons[i]
		var r: Rect2 = Rect2(wx + i * 21, py + 58, 18, 18)
		if r.end.x > pr.end.x - 10.0:
			break
		draw_rect(r, UiKit.MEOK_2)
		draw_rect(r, UiKit.HANJI_3 if bool(wd["white"]) else UiKit.JEOK, false, 1.0)
		var tex: Texture2D = wd["icon"]
		if tex != null:
			draw_texture(tex, r.position + Vector2(1, 1))
		else:
			UiKit.draw_glyph_medallion(self, r.grow(-1.0), String(wd["id"]), bool(wd["white"]), _f_small)
		draw_string(_f_small, r.position + Vector2(12, 28), "%d" % int(wd["lv"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HWANG_DK)
	draw_rect(Rect2(x0, py + 92, iw, 1), UiKit.HANJI_4)
	# 환산(풀어 준 넋 → 공덕 · 모은 엽전 → 엽전)
	if not _conv.is_empty() or _err_line != "":
		_draw_conversion(Rect2(x0, py + _y_conv, iw, 44.0))
	# 사연 한 줄 / 도움말, 할 수 있는 것, 다음 목표(환산이 끝난 뒤 차례로)
	var a4: float = clampf((_t - _t_cards + 0.2) / 0.3, 0.0, 1.0)
	if a4 > 0.0:
		if _sayeon != "":
			draw_string(_f_body, Vector2(x0, py + _y_say + 8), _sayeon, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, Color(UiKit.HANJI_5, a4))
		elif not _tip.is_empty():
			var yy: float = py + _y_tip + 8.0
			for ln: String in _tip:
				draw_string(_f_small, Vector2(x0, yy), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.JEOK_DK, a4))
				yy += 13.0
		if not _can.is_empty():
			var yc: float = py + _y_can + 4.0
			draw_rect(Rect2(x0 - 4, yc - 10, iw + 8, 14.0 * float(_can.size()) + 18.0), Color(UiKit.HANJI_2, 0.55 * a4))
			draw_string(_f_bold, Vector2(x0, yc), "신당에서 지금 할 수 있는 것" if _can_ok else "신당에서 다음에 할 것", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, Color(UiKit.JEOK_DK, a4))
			for i in _can.size():
				var ly: float = yc + 15.0 + 14.0 * float(i)
				if _can_ok:
					var pulse: float = 0.75 + 0.25 * sin(_t * 5.0)
					draw_circle(Vector2(x0 + 6, ly - 4), 3.0, Color(UiKit.JEOK, a4 * pulse))
				else:
					draw_circle(Vector2(x0 + 6, ly - 4), 3.0, Color(UiKit.HANJI_4, a4), false, 1.0)
				draw_string(_f_body, Vector2(x0 + 14, ly), _can[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, Color(ink, a4))
		if _goal != "":
			var yg: float = py + _y_goal + 4.0
			UiKit.draw_diamond(self, Vector2(x0 + 5, yg - 4), 4.0, Color(UiKit.JEOK, a4))
			draw_string(_f_bold, Vector2(x0 + 14, yg), _goal, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, Color(ink, a4))
	# 3막: 한지 카드(해금·사연)
	for i in _cards.size():
		_draw_card(_cards[i], pr, i)
	# 버튼
	var a3: float = clampf((_t - T_BTN) / 0.3, 0.0, 1.0)
	for i in 2:
		var r2: Rect2 = _btn_rect(i)
		var foc: bool = i == _focus
		if i == 0 and _primary:
			draw_rect(r2.grow(1.0), Color(UiKit.MEOK, a3))
			draw_rect(r2, Color(UiKit.JEOK if foc else UiKit.JEOK_DK, 0.95 * a3))
			if foc:
				UiKit.draw_corners(self, r2.grow(3.0), Color(UiKit.HWANG, a3))
			# 주색 점 배지(살 수 있는 것이 있다)
			var pulse2: float = 0.6 + 0.4 * sin(_t * 6.0)
			draw_circle(r2.position + Vector2(r2.size.x - 4, 3), 3.5, Color(UiKit.HWANG_HI, a3 * pulse2))
		else:
			UiKit.draw_meok_panel(self, r2, 0.95 * a3, foc, UiKit.HWANG if foc else UiKit.HANJI_5)
		var tc: Color = UiKit.HANJI_UI if (i == 0 and _primary) else (UiKit.HWANG_HI if foc else UiKit.HANJI)
		UiKit.text(self, _f_bold, UiKit.SZ_BODY, Vector2(r2.get_center().x, r2.position.y + 15), _btn_labels[i], Color(tc, a3), 1)
	if _t < _t_end and _t > T_BTN + 0.4:
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(w - 8, h - 6), "Enter 건너뛰기", Color(UiKit.HANJI_3, 0.8), 2, false)


## 진행 막대: 지난 부분 한지 / 남은 부분 먹, 시험 금 점·큰 귀신 주 점·신령 모두 내림 백 점·역려 주 마름모, 최고 기록 금 눈금.
## 아랫줄: 첫 시험 ✓ · 큰 귀신 ✗ · 역려 ✗        최고 06:52 (새 기록)
func _draw_progress(r: Rect2) -> void:
	var roll: float = UiKit.ease_out_cubic(clampf((_t - T_PANEL - 0.1) / 0.8, 0.0, 1.0))
	draw_rect(r.grow(1.0), UiKit.MEOK)
	draw_rect(r, UiKit.MEOK_3)
	var k: float = clampf(_time_s / RUN_END_S, 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * k * roll), r.size.y)), UiKit.HANJI_2)
	for tk: Array in TICKS:
		var tx: float = roundf(r.position.x + r.size.x * float(tk[0]) / RUN_END_S)
		var c: Vector2 = Vector2(minf(tx, r.end.x - 2.0), r.get_center().y)
		match String(tk[1]):
			"trial": draw_circle(c, 2.0, UiKit.HWANG)
			"mboss": draw_circle(c, 2.5, UiKit.JEOK)
			"hapil": draw_circle(c, 2.0, UiKit.HANJI_UI)
			"boss": UiKit.draw_diamond(self, c, 4.0, UiKit.JEOK)
	if _best_s > 0.0:
		var bx: float = roundf(r.position.x + r.size.x * clampf(_best_s / RUN_END_S, 0.0, 1.0))
		draw_rect(Rect2(bx, r.position.y - 4, 1, r.size.y + 8), UiKit.HWANG_DK)
	# 현재 시각 표지
	var nx: float = roundf(r.position.x + r.size.x * k * roll)
	draw_rect(Rect2(nx - 1, r.position.y - 2, 2, r.size.y + 4), UiKit.INK)
	var tt: String = "%s / 20:00" % K.fmt_time(_time_s)
	var ttw: float = _f_bold.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
	draw_string(_f_bold, Vector2(r.end.x - ttw, r.position.y - 9), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, UiKit.INK)
	# 다음 목표 눈금: 금 테로 깜박(검토 11-26 — 다음 목표가 막대 어디인지 보이게)
	if _next_tick_s > 0.0:
		var gx: float = minf(roundf(r.position.x + r.size.x * _next_tick_s / RUN_END_S), r.end.x - 2.0)
		if fposmod(_t, 0.8) < 0.55:
			draw_rect(Rect2(gx - 4, r.position.y - 3, 9, r.size.y + 6), UiKit.HWANG, false, 1.0)
	# 아랫줄: 이름표는 그 눈금 바로 아래(왼쪽부터 붙이면 눈금 이름처럼 잘못 읽혔다)
	var y: float = r.end.y + 13.0
	var used_r: Array[Vector2] = []
	for m: Dictionary in _marks:
		var lab: String = String(m["label"])
		var lw: float = _f_small.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
		var full: float = lw + 13.0
		var tx: float = r.position.x + r.size.x * float(m["t"]) / RUN_END_S
		var lx: float = roundf(clampf(tx - full * 0.5, r.position.x, r.end.x - full))
		draw_string(_f_small, Vector2(lx, y), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.INK)
		_mark(Vector2(lx + lw + 7, y - 4), bool(m["done"]))
		used_r.append(Vector2(lx, lx + full))
	if _next_tick_s > 0.0 and _next_tick_s != 180.0 and _next_tick_s != 600.0 and _next_tick_s != RUN_END_S:
		var nl: String = "다음"
		var nw: float = _f_bold.get_string_size(nl, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
		var nx2: float = roundf(clampf(r.position.x + r.size.x * _next_tick_s / RUN_END_S - nw * 0.5, r.position.x, r.end.x - nw))
		if _free(used_r, nx2, nx2 + nw):
			draw_string(_f_bold, Vector2(nx2, y), nl, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HWANG_DK)
			used_r.append(Vector2(nx2, nx2 + nw))
	# 최고 기록: 역려 이름표 왼쪽 빈자리(겹치면 막대 위 시각 줄 왼쪽으로)
	var bs: String = "최고 %s" % K.fmt_time(_best_s)
	if _new_best:
		bs += "  새 기록!"
	var bw: float = _f_small.get_string_size(bs, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
	var bx2: float = used_r[used_r.size() - 1].x - 8.0 - bw if not used_r.is_empty() else r.end.x - bw
	for ur: Vector2 in used_r:
		if ur.x < r.position.x + r.size.x * 0.75:
			continue
		bx2 = minf(bx2, ur.x - 8.0 - bw)
	if _free(used_r, bx2, bx2 + bw):
		draw_string(_f_small, Vector2(bx2, y), bs, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.JEOK_DK if _new_best else UiKit.HWANG_DK)
	else:
		draw_string(_f_small, Vector2(r.end.x - ttw - bw - 10.0, r.position.y - 9), bs, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HWANG_DK)


func _free(used: Array[Vector2], a: float, b: float) -> bool:
	for u: Vector2 in used:
		if a < u.y + 4.0 and b > u.x - 4.0:
			return false
	return true


## 코드 그림 ✓(주) / ✗(흐린 먹) — 글꼴에 기대지 않는다.
func _mark(c: Vector2, done: bool) -> void:
	if done:
		draw_line(c + Vector2(-4, 0), c + Vector2(-1, 3), UiKit.JEOK_DK, 2.0)
		draw_line(c + Vector2(-1, 3), c + Vector2(4, -4), UiKit.JEOK_DK, 2.0)
	else:
		draw_arc(c, 3.5, 0.0, TAU, 16, UiKit.HANJI_5, 1.0)       # 아직 = 빈 원(✗ 는 한지 위에서 거의 안 보였다)


## 환산 칸: 왼쪽 열 = 넋·엽전 두 줄(늘), 오른쪽 열 = 사연·처치 기록 보너스. 줄마다 왼쪽 수가 먼저 차오르고,
## 화살표가 그어진 뒤 오른쪽 수가 굴러 착지(1px 튀고 금빛 밑줄). 0이면 '—'.
func _draw_conversion(r: Rect2) -> void:
	if _t < T_CONV - 0.1:
		return
	var a: float = clampf((_t - (T_CONV - 0.1)) / 0.2, 0.0, 1.0)
	if _err_line != "":
		draw_string(_f_body, Vector2(r.position.x, r.position.y), _err_line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, UiKit.SZ_BODY, Color(UiKit.JEOK_DK, a))
		return
	for i in _conv.size():
		var c: Dictionary = _conv[i]
		var t0: float = float(c["t0"])
		if _t < t0:
			continue
		var col: int = int(c["col"])
		var p: Vector2 = Vector2(r.position.x + (0.0 if col == 0 else 222.0), r.position.y + float(c["row"]) * 14.0)
		var ar: float = clampf((_t - t0) / 0.15, 0.0, 1.0)
		var gold: bool = bool(c["gold"])
		var ink: Color = Color(UiKit.INK, ar)
		var fn: int = int(c["from_n"])
		var tn: int = int(c["to_n"])
		var zero: bool = fn <= 0 and tn <= 0
		# 표지: 넋 = 흰 ○, 엽전 = 금빛 엽전(네모 구멍)
		var mx: float = p.x + 4.0
		if gold:
			draw_circle(Vector2(mx, p.y - 4.0), 3.5, Color(UiKit.HWANG_DK, ar))
			draw_rect(Rect2(mx - 1.0, p.y - 5.0, 2, 2), Color(UiKit.HANJI_2, ar))
		else:
			UiKit.draw_kind_mark(self, Vector2(mx, p.y - 4.0), 3.0, true)
		var x: float = p.x + 11.0
		var from_s: String = String(c["from"])
		draw_string(_f_body, Vector2(x, p.y), from_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
		x += _f_body.get_string_size(from_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x + 4.0
		if fn >= 0 and not zero:
			var kf: float = UiKit.ease_out_cubic(clampf((_t - t0) / ROW_FROM, 0.0, 1.0))
			draw_string(_f_bold, Vector2(x, p.y), _comma(int(roundf(float(fn) * kf))), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
			x += _f_bold.get_string_size(_comma(fn), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x + 4.0
		# 화살표(먹 붓선이 오른쪽으로 그어짐)
		var t1: float = t0 + 0.15
		var ka: float = clampf((_t - t1) / 0.18, 0.0, 1.0)
		if ka <= 0.0:
			continue
		var aw: float = 12.0
		draw_rect(Rect2(x, p.y - 4.0, roundf(aw * ka), 1), UiKit.HANJI_5)
		if ka >= 1.0:
			draw_rect(Rect2(x + aw - 2.0, p.y - 6.0, 1, 1), UiKit.HANJI_5)
			draw_rect(Rect2(x + aw - 2.0, p.y - 2.0, 1, 1), UiKit.HANJI_5)
			draw_rect(Rect2(x + aw - 1.0, p.y - 5.0, 1, 3), UiKit.HANJI_5)
		x += aw + 4.0
		var to_s: String = String(c["to"])
		var to_col: Color = UiKit.HWANG_DK if gold else UiKit.JEOK_DK
		draw_string(_f_body, Vector2(x, p.y), to_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, Color(to_col, ka))
		x += _f_body.get_string_size(to_s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x + 4.0
		if zero:
			draw_string(_f_bold, Vector2(x, p.y), "—", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, Color(UiKit.HANJI_5, ka))
			continue
		var kt: float = UiKit.ease_out_cubic(clampf((_t - t1) / ROW_TO, 0.0, 1.0))
		var ts: String = "+" + _comma(int(roundf(float(tn) * kt)))
		# 착지: 0.12초 동안 1px 튀고 밝게
		var since: float = _t - (t1 + ROW_TO)
		var bump: float = -1.0 if since >= 0.0 and since < 0.08 else 0.0
		var land: Color = UiKit.HWANG if (since >= 0.0 and since < 0.12) else to_col
		draw_string(_f_big, Vector2(x, p.y + 1.0 + bump), ts, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BIG, land)
		if since >= 0.0:
			var uw: float = _f_big.get_string_size("+" + _comma(tn), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BIG).x
			var sweep: float = clampf(since / 0.15, 0.0, 1.0)
			draw_rect(Rect2(x, p.y + 3.0, roundf(uw * sweep), 1), Color(UiKit.HWANG_DK, 0.8))
	# 배율 · 지갑(마지막 줄 착지 뒤) — 공덕·엽전 두 줄은 늘 보인다
	if _conv.is_empty():
		return
	var tl: float = float(_conv[_conv.size() - 1]["t0"]) + 0.15 + ROW_TO
	var am: float = clampf((_t - tl) / 0.25, 0.0, 1.0)
	if am <= 0.0:
		return
	var yb: float = r.position.y + 30.0
	if _mult_line != "":
		draw_string(_f_small, Vector2(r.position.x, yb), _mult_line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.HWANG_DK, am))
	if _wallet_line != "":
		var ww: float = _f_small.get_string_size(_wallet_line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
		draw_string(_f_small, Vector2(r.end.x - ww, yb), _wallet_line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.INK, am))


## 한지 카드: 장부 양옆 여백에 매단 쪽지. 위에서 내려와(뒤로 살짝 넘침) 자리 잡고, 0.18초 뒤 붉은 낙관이 찍힌다.
func _draw_card(c: Dictionary, pr: Rect2, i: int) -> void:
	var t0: float = float(c["t0"])
	if _t < t0:
		return
	var k: float = clampf((_t - t0) / 0.28, 0.0, 1.0)
	var side: int = int(c["side"])
	var slot: int = int(c["slot"])
	var gx: float = pr.end.x + 8.0 if side > 0 else pr.position.x - 8.0 - CARD_W
	gx = clampf(gx, 2.0, size.x - CARD_W - 2.0)
	var gy: float = pr.position.y + 4.0 + float(slot) * (CARD_H + 18.0)
	var drop: float = roundf((1.0 - UiKit.ease_out_back(k)) * -16.0)
	var sway: float = roundf(sin(_t * 1.3 + float(i) * 1.7) * 0.6)    # 매단 쪽지의 아주 작은 흔들림(1px)
	var cr: Rect2 = Rect2(Vector2(gx + sway, gy + drop), Vector2(CARD_W, CARD_H))
	var a: float = clampf(k * 1.6, 0.0, 1.0)
	# 매단 끈 + 매듭
	var sx: float = roundf(cr.get_center().x)
	draw_rect(Rect2(sx, gy - 10.0, 1, cr.position.y - (gy - 10.0)), Color(UiKit.HANJI_5, 0.8 * a))
	draw_rect(Rect2(sx - 1.0, gy - 11.0, 3, 2), Color(UiKit.JEOK_DK, a))
	# 그림자 + 한지
	draw_rect(Rect2(cr.position + Vector2(2, 3), cr.size), Color(UiKit.MEOK_1, 0.7 * a))
	if a < 1.0:
		draw_rect(cr, Color(UiKit.HANJI, a))
	else:
		UiKit.draw_hanji_panel(self, cr, _paper)
	var ink: Color = Color(UiKit.INK, a)
	var kind: String = String(c["kind"])
	# 종류 띠: 사연 = 흰 넋(한지 밝음), 처치 = 적, 해금(인연·시설·의뢰) = 금
	var band: Color = UiKit.HANJI_UI if kind == "sayeon" else (UiKit.JEOK_DK if kind == "byeoksa" else UiKit.HWANG_DK)
	draw_rect(Rect2(cr.position.x + 2.0, cr.position.y + 2.0, 2.0, cr.size.y - 4.0), Color(band, a))
	draw_string(_f_bold, cr.position + Vector2(24, 15), String(c["title"]), HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 28.0, UiKit.SZ_BODY, ink)
	draw_rect(Rect2(cr.position.x + 6.0, cr.position.y + 21.0, CARD_W - 12.0, 1), Color(UiKit.HANJI_4, a))
	var yy: float = cr.position.y + 32.0
	for ln: String in (c["body"] as PackedStringArray):
		draw_string(_f_small, Vector2(cr.position.x + 7.0, yy), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, ink)
		yy += 11.0
	var rw: String = String(c["reward"])
	if rw != "":
		var rwd: float = _f_small.get_string_size(rw, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
		draw_string(_f_small, Vector2(cr.end.x - 6.0 - rwd, cr.end.y - 4.0), rw, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.HWANG_DK, a))
	# 낙관: 0.18초 뒤 크게 찍혔다가(2px 큼) 제자리 — 먹 번짐 점 몇 개
	var ks: float = _t - t0 - 0.18
	if ks >= 0.0:
		var grow: float = 2.0 if ks < 0.06 else (1.0 if ks < 0.12 else 0.0)
		var sp: Vector2 = cr.position + Vector2(6, 5) - Vector2(grow, grow)
		UiKit.draw_seal(self, sp, 14.0 + grow * 2.0, String(c["seal"]), _f_small, UiKit.SZ_SMALL)
		if ks < 0.3:
			var ka: float = 1.0 - ks / 0.3
			for d: Vector2 in [Vector2(-3, 2), Vector2(17, -1), Vector2(15, 16), Vector2(-1, 15)]:
				draw_rect(Rect2(cr.position + Vector2(6, 5) + d, Vector2.ONE), Color(UiKit.JEOK, ka))


func _new_seal(p: Vector2) -> void:
	draw_rect(Rect2(p, Vector2(13, 13)), UiKit.JEOK)
	draw_rect(Rect2(p + Vector2(1, 1), Vector2(11, 11)), UiKit.HANJI_UI, false, 1.0)
	draw_string(_f_small, p + Vector2(2, 11), "새", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HANJI_UI)


static func _comma(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
