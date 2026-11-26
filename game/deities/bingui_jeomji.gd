extends CanvasLayer
## 빙의 점지(06 §7.7): 빙의 직후 그 신령의 권능 카드(완성 4장 = 공통 3 + 면 전용 1 / 미완 2장·몸주 3장) 중 하나를 받는다. 소유: deities.
## 게임 시계는 TrialDirector 가 Game.push_pause(&"bingui_jeomji") 로 멈춘다. 이 층은 실시간(_process delta)으로만 움직인다.
## 입력: 1~4 직접, ←/→ + Enter/Space, 마우스. 열린 뒤 0.35초 잠금 + 눌려 있던 키는 한 번 떼야 인식. --autotest 는 0.6초 뒤 자동 선택.
## 색: 카드 바탕 한지빛, 위엄 = 적 + 칼(◆) 표식, 가호 = 한지 + ○ 표식(색만으로 구분하지 않음). 백(#f2ece0) 미사용.
## 문자열·배치는 open() 에서 한 번만 만든다(매 프레임 할당 없음).

const Defs := preload("res://deities/deity_defs.gd")

const CARD_W: float = 132.0
const CARD_H: float = 176.0
const CARD_GAP: float = 10.0
const CARD_Y: float = 96.0
const LOCK_S: float = 0.35
const STAGGER: float = 0.06
const ANIM: float = 0.22
const CLOSE_S: float = 0.28

const C_HANJI: Color = Color(0.913, 0.863, 0.753, 1.0)
const C_HANJI_DK: Color = Color(0.698, 0.616, 0.463, 1.0)
const C_PAPER: Color = Color(0.87, 0.81, 0.69, 1.0)
const C_JEOK: Color = Color(0.784, 0.196, 0.176, 1.0)
const C_JEOK_HI: Color = Color(0.894, 0.376, 0.31, 1.0)
const C_MEOK: Color = Color(0.055, 0.043, 0.086, 1.0)
const C_MEOK2: Color = Color(0.133, 0.11, 0.18, 1.0)
const C_INK: Color = Color(0.16, 0.12, 0.13, 1.0)
const C_HWANG: Color = Color(0.91, 0.725, 0.192, 1.0)
const C_CHEONG: Color = Color(0.165, 0.36, 0.667, 1.0)

const HELD: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down", &"confirm", &"ui_accept", &"choice_1", &"choice_2", &"choice_3"]
const TYPE_KO: Dictionary = {"ptype_ta": "타(打) · 공격 발동", "ptype_hae": "해(解) · 해원 강화", "ptype_haeng": "행(行) · 영가·고리", "ptype_su": "수(守) · 지킴", "ptype_un": "운(運) · 복"}

var dir: Node = null

var _c: Control
var _font: Font
var _brush: Font
var _open: bool = false
var _t: float = 0.0
var _lock: float = 0.0
var _need_release: bool = false
var _auto: float = -1.0
var _focus: int = 0
var _picked: int = -1
var _close_t: float = 0.0
var _n: int = 0
var _deity: StringName = &""
var _face: StringName = &""
var _dcol: Color = C_HANJI

# 카드 표시 자료(open 시 1회)
var _name: PackedStringArray = PackedStringArray()
var _desc: PackedStringArray = PackedStringArray()
var _type: PackedStringArray = PackedStringArray()
var _grade: PackedStringArray = PackedStringArray()
var _lvl: PackedStringArray = PackedStringArray()
var _tag: PackedStringArray = PackedStringArray()
var _gmult: PackedFloat32Array = PackedFloat32Array()
var _is_face: PackedByteArray = PackedByteArray()
var _s_title: String = ""
var _s_sub: String = ""
var _s_hint: String = ""


func _ready() -> void:
	_c = Control.new()
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_c.draw.connect(_on_draw)
	_c.visible = false
	add_child(_c)
	_font = ThemeDB.fallback_font
	var th: Theme = ThemeDB.get_project_theme()
	if th != null and th.default_font != null:
		_font = th.default_font
	var bf: FontFile = load("res://assets/fonts/nanum_brush/NanumBrushScript-Regular.ttf") as FontFile
	if bf != null:
		bf = bf.duplicate() as FontFile
		bf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_brush = bf
	else:
		_brush = _font
	set_process(false)
	set_process_input(false)


## TrialDirector 가 호출. cards = deity_powers.jeomji_cards() 결과.
func open(cards: Array[Dictionary], deity: StringName, face: StringName, complete: bool) -> void:
	_n = mini(4, cards.size())
	_deity = deity
	_face = face
	_dcol = Defs.color(deity)
	_name.resize(_n)
	_desc.resize(_n)
	_type.resize(_n)
	_grade.resize(_n)
	_lvl.resize(_n)
	_tag.resize(_n)
	_gmult.resize(_n)
	_is_face.resize(_n)
	for i in _n:
		var c: Dictionary = cards[i]
		_name[i] = String(c.get("name", ""))
		_desc[i] = String(c.get("desc", ""))
		_type[i] = String(TYPE_KO.get(String(c.get("type", "")), "권능"))
		_grade[i] = String(c.get("grade_name", "평"))
		_gmult[i] = float(c.get("grade_mult", 1.0))
		var lv: int = int(c.get("level", 1))
		_lvl[i] = "새 권능" if lv <= 1 else "Lv %d → %d" % [lv - 1, lv]
		var f: String = String(c.get("face", "common"))
		_is_face[i] = 0 if f == "common" else 1
		if f == "common":
			_tag[i] = "두 면 공통"
		elif f == "wieom":
			_tag[i] = "◆ 위엄 전용"
		else:
			_tag[i] = "○ 가호 전용"
	_s_title = "%s — %s" % [Defs.name_ko(deity), Defs.face_title(deity, face)]
	if complete:
		_s_sub = "신령이 실렸다. 권능 넷 가운데 하나를 받아라."
	else:
		_s_sub = "미완 빙의 — 권능 %d장만 내린다. 하나를 받아라." % _n
	# 시련 수행이 점지 등급을 정한다(trial_director._set_perf) — 잘 모시면 보상이 달라진다는 것을 말로 알린다.
	var pt: StringName = StringName(String(dir.get("perf_tier"))) if dir != null else &""
	match pt:
		&"clean_bonus":
			_s_sub = "깔끔하게 모셨다 — 모든 점괘 길(吉) 이상, 대길 기운이 짙다. 하나를 받아라."
		&"clean":
			_s_sub = "깔끔하게 모셨다 — 모든 점괘 길(吉) 이상. 하나를 받아라."
		&"bonus":
			_s_sub = "정성이 닿았다 — 대길(大吉) 기운이 짙다. 하나를 받아라."
		&"incomplete":
			_s_sub = "미완 빙의 — 권능 %d장, 대길은 없다. 하나를 받아라." % _n
	_s_hint = "1~%d 바로 받기   ·   ← → 고르고 Enter" % _n
	_open = true
	_t = 0.0
	_lock = LOCK_S
	_need_release = true
	_picked = -1
	_close_t = 0.0
	_focus = 0
	_auto = 0.6 if Game.autotest else -1.0
	_c.visible = true
	set_process(true)
	set_process_input(true)
	Audio.play_sfx(&"sfx_ui_jeomji_open", &"UI")


func _any_held() -> bool:
	for a: StringName in HELD:
		if InputMap.has_action(a) and Input.is_action_pressed(a):
			return true
	return false


func _process(delta: float) -> void:
	if not _open:
		return
	_t += delta
	if _picked >= 0:
		_close_t += delta
		if _close_t >= CLOSE_S:
			_finish()
			return
	else:
		if _lock > 0.0:
			_lock -= delta
		if _need_release and not _any_held():
			_need_release = false
		if _auto >= 0.0:
			_auto -= delta
			if _auto < 0.0:
				_pick(_auto_choice())
	_c.queue_redraw()


## 봇: 면 전용 카드를 먼저(없으면 등급 높은 것).
func _auto_choice() -> int:
	var best: int = 0
	var bs: float = -1.0
	for i in _n:
		var s: float = _gmult[i] + (0.5 if _is_face[i] == 1 else 0.0)
		if s > bs:
			bs = s
			best = i
	return best


func _card_rect(i: int) -> Rect2:
	var vs: Vector2 = _c.size
	var total: float = float(_n) * CARD_W + float(_n - 1) * CARD_GAP
	var x0: float = roundf((vs.x - total) * 0.5)
	return Rect2(x0 + float(i) * (CARD_W + CARD_GAP), CARD_Y, CARD_W, CARD_H)


func _input(event: InputEvent) -> void:
	if not _open or _picked >= 0:
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = (event as InputEventMouseMotion).position
		for i in _n:
			if _card_rect(i).has_point(mp):
				_focus = i
		return
	if _lock > 0.0 or _need_release:
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			for i in _n:
				if _card_rect(i).has_point(mb.position):
					_pick(i)
					get_viewport().set_input_as_handled()
					return
		return
	if event is InputEventKey:
		var ke: InputEventKey = event
		if ke.pressed and not ke.echo:
			var k: int = ke.physical_keycode if ke.physical_keycode != 0 else ke.keycode
			var idx: int = -1
			if k >= KEY_1 and k <= KEY_4:
				idx = k - KEY_1
			elif k >= KEY_KP_1 and k <= KEY_KP_4:
				idx = k - KEY_KP_1
			if idx >= 0:
				if idx < _n:
					_pick(idx)
				get_viewport().set_input_as_handled()
				return
	if _act(event, &"move_left") or _act(event, &"ui_left"):
		_focus = (_focus + _n - 1) % _n
		Audio.play_sfx(&"sfx_ui_move", &"UI", -6.0)
		get_viewport().set_input_as_handled()
	elif _act(event, &"move_right") or _act(event, &"ui_right"):
		_focus = (_focus + 1) % _n
		Audio.play_sfx(&"sfx_ui_move", &"UI", -6.0)
		get_viewport().set_input_as_handled()
	elif _act(event, &"confirm") or _act(event, &"ui_accept"):
		_pick(_focus)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventJoypadButton:
		# 점지 중에는 다른 키(일시정지 등)가 뒤로 새지 않게 막는다
		get_viewport().set_input_as_handled()


func _act(event: InputEvent, a: StringName) -> bool:
	return InputMap.has_action(a) and event.is_action_pressed(a)


func _pick(i: int) -> void:
	if _picked >= 0 or i < 0 or i >= _n:
		return
	_picked = i
	_focus = i
	_close_t = 0.0
	Audio.play_sfx(&"sfx_ui_jeomji_pick", &"UI")


func _finish() -> void:
	var i: int = _picked
	_open = false
	_picked = -1
	_c.visible = false
	set_process(false)
	set_process_input(false)
	if dir != null:
		dir.call("on_jeomji_chosen", i)


# ─── 그리기 ────────────────────────────────────────────────────────────

func _text(pos: Vector2, s: String, size: int, col: Color, align: HorizontalAlignment, width: float, f: Font = null, outline: bool = false) -> void:
	if s == "":
		return
	var fo: Font = f if f != null else _font
	var p: Vector2 = Vector2(roundf(pos.x), roundf(pos.y))
	if outline:
		fo.draw_string_outline(_c.get_canvas_item(), p, s, align, width, size, 4, Color(C_MEOK, col.a * 0.9))
	fo.draw_string(_c.get_canvas_item(), p, s, align, width, size, col)


func _on_draw() -> void:
	if not _open:
		return
	var vs: Vector2 = _c.size
	var cx: float = roundf(vs.x * 0.5)
	var k_in: float = clampf(_t / 0.25, 0.0, 1.0)
	var k_out: float = clampf(_close_t / CLOSE_S, 0.0, 1.0) if _picked >= 0 else 0.0
	var dim: float = 0.72 * k_in * (1.0 - k_out)
	_c.draw_rect(Rect2(Vector2.ZERO, vs), Color(C_MEOK, dim))
	# 위아래 금줄 띠(신령색)
	_c.draw_rect(Rect2(0, 30, vs.x, 1), Color(_dcol, 0.7 * k_in * (1.0 - k_out)))
	_c.draw_rect(Rect2(0, vs.y - 31, vs.x, 1), Color(_dcol, 0.7 * k_in * (1.0 - k_out)))
	var ta: float = k_in * (1.0 - k_out)
	var fc: Color = C_JEOK_HI if _face == &"wieom" else C_HANJI
	_text(Vector2(cx - 300, 62), _s_title, 32, Color(fc, ta), HORIZONTAL_ALIGNMENT_CENTER, 600.0, _brush, true)
	_text(Vector2(cx - 300, 82), _s_sub, 12, Color(C_HANJI, ta), HORIZONTAL_ALIGNMENT_CENTER, 600.0, null, true)
	for i in _n:
		_draw_card(i, k_out)
	if _picked < 0:
		var ha: float = 0.0 if _lock > 0.0 else 0.85
		_text(Vector2(cx - 300, CARD_Y + CARD_H + 26), _s_hint, 11, Color(C_HANJI_DK, ha), HORIZONTAL_ALIGNMENT_CENTER, 600.0, null, true)


func _draw_card(i: int, k_out: float) -> void:
	var r: Rect2 = _card_rect(i)
	var k: float = clampf((_t - float(i) * STAGGER) / ANIM, 0.0, 1.0)
	if k <= 0.0:
		return
	var e: float = 1.0 - pow(1.0 - k, 3.0)
	var a: float = e
	var oy: float = roundf((1.0 - e) * 22.0)
	var sel: bool = i == _focus and _lock <= 0.0
	if _picked >= 0:
		if i == _picked:
			oy = -roundf(6.0 * sin(k_out * PI))
			a = 1.0 - maxf(0.0, k_out - 0.6) / 0.4
		else:
			a = 1.0 - clampf(k_out / 0.4, 0.0, 1.0)
			oy = roundf(k_out * 14.0)
	elif sel:
		oy -= 4.0
	if a <= 0.0:
		return
	r.position.y += oy
	var ci: RID = _c.get_canvas_item()
	var is_face: bool = _is_face[i] == 1
	var band: Color = _dcol
	# 그림자 · 바탕
	_c.draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(C_MEOK, 0.6 * a))
	_c.draw_rect(r, Color(C_PAPER, a))
	_c.draw_rect(Rect2(r.position, Vector2(r.size.x, 22)), Color(band.darkened(0.45), a))
	_c.draw_rect(Rect2(r.position + Vector2(0, 22), Vector2(r.size.x, 1)), Color(band, a))
	# 테두리(먹 1px + 선택 시 신령색 2px)
	_c.draw_rect(r, Color(C_INK, a), false, 1.0)
	if sel or i == _picked:
		var pulse: float = 0.75 + 0.25 * sin(_t * 9.0)
		_c.draw_rect(r.grow(2.0), Color(C_HWANG if i == _picked else band.lightened(0.3), a * pulse), false, 2.0)
	# 단청 모서리(네 귀 3px)
	for q in 4:
		var cxp: float = r.position.x + (1.0 if q % 2 == 0 else r.size.x - 4.0)
		var cyp: float = r.position.y + (r.size.y - 4.0 if q >= 2 else 23.0)
		_c.draw_rect(Rect2(cxp, cyp, 3, 3), Color(C_JEOK if is_face and _face == &"wieom" else C_CHEONG, 0.8 * a))
	# 번호 · 등급
	_text(r.position + Vector2(5, 15), str(i + 1), 12, Color(C_HANJI, a), HORIZONTAL_ALIGNMENT_LEFT, 20.0)
	var gcol: Color = C_HANJI_DK
	if _gmult[i] >= 1.55:
		gcol = C_HWANG
	elif _gmult[i] >= 1.25:
		gcol = C_HANJI
	_text(r.position + Vector2(r.size.x - 45, 15), _grade[i], 12, Color(gcol, a), HORIZONTAL_ALIGNMENT_RIGHT, 40.0)
	if _gmult[i] >= 1.55:
		_c.draw_rect(Rect2(r.position.x + r.size.x - 48, r.position.y + 4, 44, 15), Color(C_HWANG, 0.7 * a), false, 1.0)
	_text(r.position + Vector2(18, 15), _lvl[i], 11, Color(C_HANJI_DK, a), HORIZONTAL_ALIGNMENT_LEFT, 70.0)
	# 이름(붓글씨)
	_text(r.position + Vector2(4, 50), _name[i], 24, Color(C_INK, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8.0, _brush)
	# 면 표식
	var tcol: Color = C_INK
	if is_face:
		tcol = C_JEOK if _face == &"wieom" else Color(0.36, 0.28, 0.2)
	_text(r.position + Vector2(4, 66), _tag[i], 11, Color(tcol, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8.0)
	_c.draw_rect(Rect2(r.position.x + 10, r.position.y + 72, r.size.x - 20, 1), Color(C_INK, 0.35 * a))
	# 설명(줄바꿈, 최대 6줄)
	_font.draw_multiline_string(ci, Vector2(roundf(r.position.x + 7), roundf(r.position.y + 87)), _desc[i], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 14.0, 11, 6, Color(C_INK, a), TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	# 종류
	_text(r.position + Vector2(4, r.size.y - 7), _type[i], 11, Color(0.36, 0.28, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8.0)
