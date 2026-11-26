extends Control
## 정산 화면(명부 정산). 소유: meta(이 화면 파일만, ARCHITECTURE §5 예외). design/11 §9.4.
## 1막 결말(붓 제목·촛불) → 2막 장부(해원/퇴치 같은 크기·같은 굵기, 넋 비율 바, 최대 행렬·길닦음·원귀 회귀, 무구)
## → 환산(넋 → 공덕, 엽전 → 복전, 사연 조각·벽사록 보상: 숫자 카운트업, 줄마다 짧은 '딸깍') → 3막 한지 카드(해금·사연 조각) → 버튼.
## 입력: setup(result)(main.gd) + 세이브 ui.last_run(RunLedger 보충 통계) + Save.settlement_view()(메타 정산 묶음).
## Enter/Esc 는 연출 중이면 끝까지 건너뛰기, 끝났으면 버튼.

signal retry_requested
signal title_requested

const BTN: Array[String] = ["다시 굿판", "타이틀로"]
const T_PANEL: float = 0.9          # 2막 장부
const T_ROLL: float = 1.1           # 해원·퇴치 롤링
const T_BTN: float = 1.6            # 버튼(마우스 입력 허용)
const T_CONV: float = 1.75          # 환산 줄 시작
const ROW_GAP: float = 0.3          # 환산 줄 사이
const ROW_FROM: float = 0.35        # 왼쪽 수(넋·엽전) 굴림
const ROW_TO: float = 0.45          # 오른쪽 수(공덕·복전) 굴림(왼쪽 0.15초 뒤 시작)
const CARD_GAP: float = 0.32        # 한지 카드 사이
const CARD_W: float = 104.0
const CARD_H: float = 60.0
const SEAL_FALLBACK: Dictionary = {"巫": "무", "壇": "단", "錄": "록", "願": "원", "緣": "연", "辟": "벽"}

var result: Dictionary = {}
var _last: Dictionary = {}
var _t: float = 0.0
var _focus: int = 0
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_tiny: Font
var _f_big: Font
var _f_brush: Font
var _paper: Texture2D
var _vignette: Texture2D
var _title: String = ""
var _sub: String = ""
var _ending: String = ""
var _tip: PackedStringArray = PackedStringArray()
var _rows: Array[Dictionary] = []
var _weapons: Array[Dictionary] = []
var _news: Array = []
var _victory: bool = false
var _line2: String = ""
var _btn2: String = "타이틀로"
var _lock_left: float = 0.4           # 진입 직후 입력 잠금(사망 직전 연타가 먹히지 않게)
# 메타 환산(Save.settlement_view)
var _conv: Array[Dictionary] = []     # {from, from_n, to, to_n, gold, t0}
var _mult_line: String = ""
var _wallet_line: String = ""
var _err_line: String = ""
var _cards: Array[Dictionary] = []    # {kind, seal, title, body:PackedStringArray, reward, t0, side, slot}
var _t_cards: float = 0.0             # 카드 시작
var _t_end: float = 2.6               # 연출 끝(건너뛰기 목표)
var _cue_done: int = 0                # 이미 울린 소리 비트(줄 시작·착지·카드)
var _cards_marked: bool = false


func setup(p_result: Dictionary) -> void:
	result = p_result


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.setup_fonts()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_big = UiKit.big()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")
	_vignette = UiKit.skin("vignette.png")
	var lr: Variant = Save.get_value("ui.last_run", {})
	_last = lr if lr is Dictionary else {}
	_build()
	Audio.play_sfx(&"sfx_ui_result", &"UI")


func _g(key: String, default: Variant = 0) -> Variant:
	if result.has(key):
		return result[key]
	return _last.get(key, default)


func _build() -> void:
	_victory = bool(_g("victory", false))
	var ending: String = String(_last.get("ending", result.get("ending", "")))
	if ending == "abandon":
		_title = "굿판을 거두었다"
		_ending = "굿을 멈추고 판을 거두었다"
	elif ending == "timeout" or ending == "hard_cap":
		# 보스를 풀지 못해 저승사자가 거둬 감(23:00 강제 사자) — 사망이 아니다 (core 통합)
		_title = "사자가 판을 거두었다"
		_ending = "역려를 다 풀지 못했다 — 저승사자가 내려와 읍하고 굿판을 거두었다"
	elif _victory:
		_title = "굿이 끝났다"
		_ending = "명부까지 길을 닦았다"
	else:
		_title = "굿판이 흩어졌다"
		_ending = "%s, 굿판에서 쓰러졌다" % K.fmt_time(float(_g("time_sec", 0.0)))
	_sub = "冥府精算 · 명부 정산"
	var h: int = int(_g("haewon", 0))
	var t: int = int(_g("toechi", 0))
	_rows = [
		{"label": "해원", "v": h, "mark": "white", "key": "haewon"},
		{"label": "퇴치", "v": t, "mark": "red", "key": "toechi"},
	]
	_line2 = "최대 행렬 %d   ·   길닦음 %d   ·   원귀 회귀 %d   ·   Lv %d   ·   %s" % [
		int(_last.get("max_yeongga", 0)), int(_last.get("rings", 0)), int(_last.get("wongwi", 0)),
		int(_g("level", 1)), K.fmt_time(float(_g("time_sec", 0.0)))]
	_news = _last.get("new_best", [])
	_btn2 = "신당으로" if Save.lobby_route() else "타이틀로"
	var ws: Variant = _last.get("weapons", [])
	if ws is Array:
		for e: Variant in ws:
			var parts: PackedStringArray = String(e).split(":")
			var id: String = parts[0]
			_weapons.append({"id": id, "lv": int(parts[1]) if parts.size() > 1 else 1,
				"icon": UiKit.weapon_icon(id, true), "white": UiKit.weapon_color(id) == "white"})
	# '다음 굿판의 길' 카드(첫 세 판 사망, onboarding_hints.death_cards_first3)
	var runs: int = int(Save.get_value("ui.runs", 1))
	if ending == "timeout" and runs <= 3:
		_tip = UiKit.wrap(_f_body, UiKit.SZ_BODY, UiCopy.DEATH_TIP_TIMEOUT, 380.0, 2)
	elif not _victory and runs <= 3 and ending not in ["timeout", "hard_cap", "abandon"]:
		var tot: int = h + t
		var ratio: float = float(h) / float(maxi(tot, 1))
		var tip: String = ""
		if int(_last.get("rings", 1)) == 0:
			tip = UiCopy.DEATH_TIP_NO_RING
		elif ratio < 0.15:
			tip = UiCopy.DEATH_TIP_LOW_HAEWON
		elif ratio > 0.85:
			tip = UiCopy.DEATH_TIP_HIGH_HAEWON
		elif _weapons.size() <= 3:
			tip = UiCopy.DEATH_TIP_FEW_WEAPONS
		if tip != "":
			_tip = UiKit.wrap(_f_body, UiKit.SZ_BODY, tip, 380.0, 2)
	_build_settlement()


## 메타 정산 → 환산 줄·배율 줄·지갑 줄·한지 카드(시간표 포함).
func _build_settlement() -> void:
	var sv: Dictionary = Save.settlement_view()
	var t: float = T_CONV
	if not sv.is_empty():
		if not bool(sv.get("ok", false)):
			_err_line = String(sv.get("error", "")) if String(sv.get("error", "")) != "" else "기록이 저장되지 않았습니다"
		else:
			for r: Variant in sv.get("rows", []):
				if not (r is Dictionary):
					continue
				var d: Dictionary = r
				var fn: int = int(d.get("from_n", 0))
				var tn: int = int(d.get("to_n", 0))
				# 엽전·복전이 둘 다 0 이면 줄을 숨긴다(넋 줄은 0 이어도 남긴다 — 첫 판에 환산 규칙을 보여 주려고)
				if _conv.size() > 0 and fn <= 0 and tn <= 0:
					continue
				_conv.append({"from": String(d.get("from", d.get("label", ""))), "from_n": fn,
					"to": String(d.get("to", "")), "to_n": tn, "gold": bool(d.get("gold", false)), "t0": t})
				t += ROW_GAP
				if _conv.size() >= 4:
					break
			var ml: PackedStringArray = PackedStringArray()
			for m: Variant in sv.get("mults", []):
				ml.append(String(m))
			while ml.size() > 0 and _f_tiny.get_string_size("배율  " + "  ·  ".join(ml), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY).x > 210.0:
				ml.resize(ml.size() - 1)
			_mult_line = ("배율  " + "  ·  ".join(ml)) if ml.size() > 0 else ""
			_wallet_line = "신당  공덕 %s  ·  복전 %s" % [_comma(int(sv.get("wallet_G", 0))), _comma(int(sv.get("wallet_B", 0)))]
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
			var seal: String = String(cd.get("seal", "緣"))
			if seal.length() > 0 and not _f_small.has_char(seal.unicode_at(0)):
				seal = String(SEAL_FALLBACK.get(seal, "넋"))
			_cards.append({"kind": String(cd.get("kind", "")), "seal": seal, "title": String(cd.get("title", "")),
				"body": UiKit.wrap(_f_tiny, UiKit.SZ_TINY, String(cd.get("body", "")), CARD_W - 12.0, 3),
				"reward": String(cd.get("reward", "")), "t0": _t_cards + float(i) * CARD_GAP,
				"side": 1 if i % 2 == 0 else -1, "slot": i >> 1})
			i += 1
	_t_end = maxf(2.6, (_t_cards + float(_cards.size() - 1) * CARD_GAP + 0.45) if not _cards.is_empty() else _t_cards)


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
		Save.last_settlement["result_cards_shown"] = true   # 신당이 같은 사연 조각 알림을 다시 띄우지 않게


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
			_press(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _press(i: int) -> void:
	Audio.play_sfx(&"sfx_ui_confirm", &"UI")
	if i == 0:
		retry_requested.emit()
	else:
		title_requested.emit()


func _btn_rect(i: int) -> Rect2:
	var cx: float = roundf(size.x * 0.5)
	return Rect2(cx - 112 + i * 120, size.y - 34, 104, 22)


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


func _panel_h() -> float:
	var hh: float = 112.0
	if not _conv.is_empty() or _err_line != "":
		hh += 60.0
	if not _tip.is_empty():
		hh += 38.0
	return hh


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = roundf(w * 0.5)
	draw_rect(Rect2(0, 0, w, h), UiKit.MEOK)
	# 촛불(1막): 가운데 위에 작은 불꽃, 0.5Hz 깜박
	var fl: float = 0.85 + 0.15 * sin(_t * TAU * 0.5) + 0.05 * sin(_t * 23.0)
	var glow: float = 40.0 * fl
	var cy: float = 34.0
	for k in 4:
		var rr: float = glow * (1.0 - float(k) * 0.22)
		draw_circle(Vector2(cx, cy), rr, Color(UiKit.HWANG_DK, 0.05 + 0.03 * float(k)))
	draw_rect(Rect2(cx - 2, cy + 2, 5, 12), UiKit.HANJI_2)
	draw_rect(Rect2(cx - 1, cy - 4 - roundf(fl * 2.0), 3, 6), UiKit.HWANG_HI)
	draw_rect(Rect2(cx, cy - 6 - roundf(fl * 3.0), 1, 3), UiKit.HANJI_UI)
	if _vignette != null:
		draw_texture_rect(_vignette, Rect2(0, 0, w, h), false, Color(1, 1, 1, 0.5))
	# 1막 제목
	var a1: float = clampf(_t / 0.5, 0.0, 1.0)
	var ty: float = 84.0 - roundf((1.0 - UiKit.ease_out_cubic(a1)) * 8.0)
	UiKit.text_outline(self, _f_brush, 40, Vector2(cx, ty), _title, Color(UiKit.HANJI_UI if _victory else UiKit.HANJI, a1), 1, 2)
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx, ty + 22.0), _sub, Color(UiKit.HWANG_HI, a1), 1)
	# 2막 장부
	var a2: float = clampf((_t - T_PANEL) / 0.3, 0.0, 1.0)
	if a2 <= 0.0:
		return
	var pr: Rect2 = Rect2(cx - 200, 112, 400, _panel_h())
	pr.position.y += roundf((1.0 - UiKit.ease_out_cubic(a2)) * 10.0)
	draw_rect(Rect2(pr.position + Vector2(3, 4), pr.size), Color(UiKit.MEOK_1, 0.8 * a2))
	UiKit.draw_hanji_panel(self, pr, _paper)
	UiKit.draw_dancheong(self, Rect2(pr.position.x + 2, pr.position.y + 2, pr.size.x - 4, 4))
	var ink: Color = UiKit.INK
	var x0: float = pr.position.x + 16.0
	var y: float = pr.position.y + 22.0
	draw_string(_f_body, Vector2(x0, y), "결말   %s" % _ending, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
	y += 8.0
	draw_rect(Rect2(x0, y, pr.size.x - 32, 1), UiKit.HANJI_4)
	# 해원 · 퇴치(같은 크기·굵기, 숫자 롤링)
	var roll: float = UiKit.ease_out_cubic(clampf((_t - T_ROLL) / 0.9, 0.0, 1.0))
	y += 22.0
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var rx: float = x0 + float(i) * 128.0
		UiKit.draw_kind_mark(self, Vector2(rx + 5, y - 5), 3.0, String(row["mark"]) == "white")
		draw_string(_f_body, Vector2(rx + 13, y), String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
		var n: int = int(roundf(float(row["v"]) * roll))
		draw_string(_f_big, Vector2(rx + 46, y + 1), "%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
		if _news.has(String(row["key"])) and roll >= 1.0:
			_new_seal(Vector2(rx + 100, y - 12))
	# 넋 비율 바
	var hv: int = int(_rows[0]["v"])
	var tv: int = int(_rows[1]["v"])
	var nr: float = 0.5 if hv + tv == 0 else float(hv) / float(hv + tv)
	var br: Rect2 = Rect2(x0 + 258, y - 9, 110, 7)
	draw_rect(br.grow(1.0), UiKit.MEOK)
	draw_rect(br, UiKit.MEOK_3)
	draw_rect(Rect2(br.position, Vector2(roundf(br.size.x * nr * roll), br.size.y)), UiKit.HANJI_UI)
	draw_string(_f_tiny, Vector2(br.position.x, br.end.y + 9), "넋 비율 %d%%" % int(roundf(nr * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY, UiKit.HANJI_5)
	# 둘째 줄: 최대 행렬 · 길닦음 · 원귀 회귀 · Lv · 시간
	y += 22.0
	draw_string(_f_small, Vector2(x0, y), _line2, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, ink)
	# 무구
	y += 10.0
	for i in _weapons.size():
		var wd: Dictionary = _weapons[i]
		var r: Rect2 = Rect2(x0 + i * 24, y, 18, 18)
		if r.end.x > pr.end.x - 12.0:
			break
		draw_rect(r, UiKit.MEOK_2)
		draw_rect(r, UiKit.HANJI_3 if bool(wd["white"]) else UiKit.JEOK, false, 1.0)
		var tex: Texture2D = wd["icon"]
		if tex != null:
			draw_texture(tex, r.position + Vector2(1, 1))
		else:
			UiKit.draw_glyph_medallion(self, r.grow(-1.0), String(wd["id"]), bool(wd["white"]), _f_small)
		draw_string(_f_tiny, r.position + Vector2(13, 26), "%d" % int(wd["lv"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY, UiKit.HWANG_DK)
	# 환산(넋 → 공덕 · 엽전 → 복전 …)
	var ys: float = pr.position.y + 118.0
	if not _conv.is_empty() or _err_line != "":
		_draw_conversion(Rect2(x0, ys, pr.size.x - 32.0, 52.0))
	# 다음 굿판의 길(팁)
	if not _tip.is_empty():
		var ty2: float = pr.end.y - 30.0
		draw_rect(Rect2(x0 - 4, ty2 - 10, pr.size.x - 24, 36), Color(UiKit.HANJI_2, 0.8))
		draw_string(_f_small, Vector2(x0, ty2), "다음 굿판의 길", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.JEOK_DK)
		var yy: float = ty2 + 13.0
		for ln: String in _tip:
			draw_string(_f_body, Vector2(x0, yy), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
			yy += 12.0
	# 3막: 한지 카드(해금·사연 조각)
	for i in _cards.size():
		_draw_card(_cards[i], pr, i)
	# 버튼
	var a3: float = clampf((_t - T_BTN) / 0.3, 0.0, 1.0)
	for i in 2:
		var r2: Rect2 = _btn_rect(i)
		var foc: bool = i == _focus
		UiKit.draw_meok_panel(self, r2, 0.95 * a3, foc, UiKit.HWANG if foc else UiKit.HANJI_5)
		UiKit.text(self, _f_bold, UiKit.SZ_BODY, Vector2(r2.get_center().x, r2.position.y + 15), BTN[i] if i == 0 else _btn2, Color(UiKit.HWANG_HI if foc else UiKit.HANJI, a3), 1)
	if _t < _t_end and _t > T_BTN + 0.4:
		UiKit.text(self, _f_tiny, UiKit.SZ_TINY, Vector2(cx, h - 4), "Enter 건너뛰기", Color(UiKit.HANJI_5, 0.7), 1, false)


## 환산 칸: 2열 격자(왼쪽 위부터). 줄마다 왼쪽 수가 먼저 차오르고, 화살표가 그어진 뒤 오른쪽 수가 굴러 착지(1px 튀고 금빛 밑줄).
func _draw_conversion(r: Rect2) -> void:
	if _t < T_CONV - 0.1:
		return
	var a: float = clampf((_t - (T_CONV - 0.1)) / 0.2, 0.0, 1.0)
	draw_rect(Rect2(r.position.x, r.position.y - 4.0, r.size.x, 1), Color(UiKit.HANJI_4, a))
	if _err_line != "":
		draw_string(_f_small, Vector2(r.position.x, r.position.y + 14.0), _err_line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, UiKit.SZ_SMALL, Color(UiKit.JEOK_DK, a))
		return
	var col_w: float = roundf((r.size.x - 20.0) * 0.5)
	for i in _conv.size():
		var c: Dictionary = _conv[i]
		var t0: float = float(c["t0"])
		if _t < t0:
			continue
		var p: Vector2 = Vector2(r.position.x + float(i % 2) * (col_w + 20.0), r.position.y + 12.0 + float(i >> 1) * 15.0)
		var ar: float = clampf((_t - t0) / 0.15, 0.0, 1.0)
		var gold: bool = bool(c["gold"])
		var ink: Color = Color(UiKit.INK, ar)
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
		var fn: int = int(c["from_n"])
		if fn >= 0:
			var kf: float = UiKit.ease_out_cubic(clampf((_t - t0) / ROW_FROM, 0.0, 1.0))
			var fs: String = _comma(int(roundf(float(fn) * kf)))
			draw_string(_f_bold, Vector2(x, p.y), fs, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
			x += _f_bold.get_string_size(_comma(fn), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x + 4.0
		# 화살표(먹 붓선이 오른쪽으로 그어짐)
		var t1: float = t0 + 0.15
		var ka: float = clampf((_t - t1) / 0.18, 0.0, 1.0)
		if ka > 0.0:
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
			var kt_raw: float = clampf((_t - t1) / ROW_TO, 0.0, 1.0)
			var kt: float = UiKit.ease_out_cubic(kt_raw)
			var tn: int = int(c["to_n"])
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
	# 배율 · 지갑(마지막 줄 착지 뒤)
	if _conv.is_empty():
		return
	var tl: float = float(_conv[_conv.size() - 1]["t0"]) + 0.15 + ROW_TO
	var am: float = clampf((_t - tl) / 0.25, 0.0, 1.0)
	if am <= 0.0:
		return
	var yb: float = r.position.y + 12.0 + float((_conv.size() + 1) >> 1) * 15.0 + 2.0
	if _mult_line != "":
		draw_string(_f_tiny, Vector2(r.position.x, yb), _mult_line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY, Color(UiKit.HWANG_DK, am))
	if _wallet_line != "":
		var ww: float = _f_tiny.get_string_size(_wallet_line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY).x
		draw_string(_f_tiny, Vector2(r.end.x - ww, yb), _wallet_line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY, Color(UiKit.INK, 0.75 * am))


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
	# 종류 띠: 사연 = 흰 넋(한지 밝음), 벽사 = 적, 해금(인연·시설·의뢰) = 금
	var band: Color = UiKit.HANJI_UI if kind == "sayeon" else (UiKit.JEOK_DK if kind == "byeoksa" else UiKit.HWANG_DK)
	draw_rect(Rect2(cr.position.x + 2.0, cr.position.y + 2.0, 2.0, cr.size.y - 4.0), Color(band, a))
	draw_string(_f_bold, cr.position + Vector2(24, 15), String(c["title"]), HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 28.0, UiKit.SZ_BODY, ink)
	draw_rect(Rect2(cr.position.x + 6.0, cr.position.y + 21.0, CARD_W - 12.0, 1), Color(UiKit.HANJI_4, a))
	var yy: float = cr.position.y + 31.0
	for ln: String in (c["body"] as PackedStringArray):
		draw_string(_f_tiny, Vector2(cr.position.x + 7.0, yy), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY, ink)
		yy += 9.0
	var rw: String = String(c["reward"])
	if rw != "":
		var rwd: float = _f_tiny.get_string_size(rw, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY).x
		draw_string(_f_tiny, Vector2(cr.end.x - 6.0 - rwd, cr.end.y - 4.0), rw, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY, Color(UiKit.HWANG_DK, a))
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
	draw_string(_f_small, p + Vector2(2, 11), "新", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HANJI_UI)


static func _comma(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
