extends Control
## 신당 로비(한 화면 신당 + 시설 메뉴, meta_economy.sindang_v1). 소유: meta.
## 왼쪽 한지 표찰 메뉴 → 오른쪽 패널(굿판 문·무당·신당 단장·재가집 의뢰·넋기록 서고).
## 봉헌/내림굿은 0.6초 길게 눌러 확정(09 §5.3 CONFIRM). 결과는 Save 트랜잭션(원자 저장, 실패 시 롤백).
## 입력: 방향키/WASD/스틱·D패드, Enter/Space/A(길게 = 봉헌), Esc/Backspace/B(닫기), 마우스(호버·클릭·휠).
## UI 는 _draw 일괄(열 때·변경 때만 문자열을 만든다). 배경은 meta/sindang_backdrop.gd.

signal back_requested
signal start_requested(char_id: StringName)

const Backdrop: GDScript = preload("res://meta/sindang_backdrop.gd")

const HOLD_S: float = 0.6
const PANEL_W: float = 268.0
const PANEL_X: float = 364.0
const PANEL_Y: float = 36.0
const PANEL_H: float = 292.0
const MENU_X: float = 12.0
const MENU_Y: float = 62.0
const MENU_W: float = 122.0
const MENU_H: float = 26.0

const C_MEOK: Color = Color("0e0b16")
const C_MEOK1: Color = Color("17131f")
const C_MEOK2: Color = Color("221c2e")
const C_MEOK3: Color = Color("2f2840")
const C_MEOK4: Color = Color("3f3654")
const C_HANJI: Color = Color("e9dcc0")
const C_HANJI_UI: Color = Color("f6eedc")
const C_HANJI2: Color = Color("d2c19c")
const C_HANJI3: Color = Color("b29d76")
const C_HANJI4: Color = Color("857154")
const C_HANJI5: Color = Color("5a4a37")
const C_JEOK: Color = Color("c8322d")
const C_JEOK_HI: Color = Color("e4604f")
const C_JEOK_DK: Color = Color("8c1f22")
const C_HWANG: Color = Color("e8b931")
const C_HWANG_HI: Color = Color("f5d66b")
const C_HWANG_DK: Color = Color("a97c1b")
const C_NOK: Color = Color("55b8aa")

var backdrop: Node2D
var _ui: Control
var _pc: Control                       # 패널(클립)

var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_tiny: Font
var _f_big: Font
var _f_brush: Font

var _menu: Array[Dictionary] = []
var _menu_i: int = 0
var _zone: int = 0                     # 0 메뉴, 1 패널
var _panel: String = ""
var _panel_k: float = 0.0              # 0 닫힘 .. 1 열림(슬라이드)
var _items: Array[Dictionary] = []
var _item_i: int = 0
var _scroll: float = 0.0
var _scroll_target: float = 0.0
var _content_h: float = 0.0
var _header: String = ""
var _header_sub: PackedStringArray = PackedStringArray()
var _foot: PackedStringArray = PackedStringArray()

var _hold_on: bool = false
var _hold_t: float = 0.0
var _hold_item: int = -1
var _nudge: float = 0.0                # 거절 흔들림
var _nudge_i: int = -1
var _pulse: float = 0.0                # 성공 번쩍임(항목)
var _pulse_i: int = -1

var _toasts: Array[String] = []
var _toast: PackedStringArray = PackedStringArray()
var _toast_t: float = 0.0
var _bark_full: String = ""
var _bark_shown: String = ""
var _bark_n: float = 0.0
var _bark_speaker: String = "신어머니"
var _slam_text: String = ""            # 화면 가운데 붓 글씨(내림굿 등)
var _slam_t: float = 0.0
var _screen_flash: float = 0.0

var _disp_g: float = 0.0
var _disp_b: float = 0.0
var _txt_g: String = "0"
var _txt_b: String = "0"
var _wallet_bump: float = 0.0
var _count_delay: float = 0.0          # 정산 굴림 시작 전 대기(로비 첫 진입)
var _count_rate: float = 8.0           # 지갑 굴림 속도(정산 굴림 중엔 느리게)
var _t: float = 0.0
var _starting: bool = false
var _start_t: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Game.state = Game.State.LOBBY
	UiKit.setup_fonts()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_big = UiKit.big()
	_f_brush = UiKit.brush()
	var bg: ColorRect = ColorRect.new()
	bg.color = C_MEOK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	backdrop = Backdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	_ui = Control.new()
	_ui.name = "UiLayer"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)
	_pc = Control.new()
	_pc.name = "Panel"
	_pc.clip_contents = true
	_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pc.position = Vector2(640.0, PANEL_Y)
	_pc.size = Vector2(PANEL_W, PANEL_H)
	_pc.draw.connect(_draw_panel)
	add_child(_pc)
	Save.profile_changed.connect(_on_profile_changed)
	_disp_g = float(Save.wallet(MetaRules.CUR_G))
	_disp_b = float(Save.wallet(MetaRules.CUR_B))
	# 굿을 치르고 처음 들어왔으면: 이번 굿에서 번 만큼 뺀 값에서 굴려 올린다(정산이 눈에 보이게).
	var sv: Dictionary = Save.settlement_view()
	if not sv.is_empty() and not bool(Save.last_settlement.get("lobby_shown", false)):
		Save.last_settlement["lobby_shown"] = true
		var gg: int = int(sv["gain_G"])
		var gb: int = int(sv["gain_B"])
		if gg > 0 or gb > 0:
			_disp_g = maxf(0.0, _disp_g - float(gg))
			_disp_b = maxf(0.0, _disp_b - float(gb))
			_count_delay = 0.7
			_count_rate = 2.2
			_toasts.append("이번 굿 — 공덕 +%s · 복전 +%s" % [_fmt(gg), _fmt(gb)])
	_txt_g = _fmt(int(_disp_g))
	_txt_b = _fmt(int(_disp_b))
	_refresh_backdrop()
	backdrop.call("set_character", Save.selected_char(), false)
	_build_menu()
	# 정산 화면이 한지 카드로 이미 보여 준 기록성 알림(사연 조각·벽사록)은 다시 띄우지 않는다. 해금·시설 안내는 남긴다.
	var shown: bool = bool(Save.last_settlement.get("result_cards_shown", false))
	for n: String in Save.pending_notices:
		if shown and (n.begins_with("사연 조각") or n.begins_with("벽사록")):
			continue
		_toasts.append(n)
	Save.pending_notices.clear()
	if not Save.last_error.is_empty():
		_toasts.append(Save.last_error)
	_greet()
	Audio.play_music(&"jd_gutgeori_mix")
	if not Save.flag("lobby_seen"):
		Save.set_flag("lobby_seen", true)


# ═══ 메뉴 ═════════════════════════════════════════════════════════════

func _build_menu() -> void:
	var runs: int = Save.runs_done()
	var u_need: int = int(MetaRules.num("sindang_v1.uiroe_open_after_runs", 3.0))
	_menu = [
		{"id": "depart", "label": "굿판 문", "sub": "굿을 열러 나간다", "on": true},
		{"id": "char", "label": "무당", "sub": _char_menu_sub(), "on": true},
		{"id": "danjang", "label": "신당 단장", "sub": "신단을 꾸며 영구 강화" if Save.facility_open("danjang_open_after_runs") else "첫 굿 뒤 열림", "on": Save.facility_open("danjang_open_after_runs")},
		{"id": "weapons", "label": "무구 진열장", "sub": "백 무구 봉헌 · 적 무구 제작" if Save.facility_open("weapon_offering_open_after_runs") else "첫 굿 뒤 열림", "on": Save.facility_open("weapon_offering_open_after_runs")},
		{"id": "uiroe", "label": "재가집 의뢰", "sub": _uiroe_menu_sub(runs, u_need), "on": Save.uiroe_open()},
		{"id": "singirok", "label": "넋기록 서고", "sub": "풀어 준 넋·물리친 귀신" if Save.facility_open("singirok_open_after_runs") else "첫 굿 뒤 열림", "on": Save.facility_open("singirok_open_after_runs")},
		{"id": "title", "label": "물러나기", "sub": "타이틀로", "on": true},
	]
	for m: Dictionary in _menu:
		m["fit"] = _fit(String(m["sub"]), _f_tiny, 8, MENU_W - 14.0)
	_menu_i = clampi(_menu_i, 0, _menu.size() - 1)
	_ui.queue_redraw()


## 폭에 맞게 자르고 말줄임(열 때만).
func _fit(s: String, f: Font, size: int, w: float) -> String:
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= w:
		return s
	var t: String = s
	while t.length() > 1 and f.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
		t = t.left(t.length() - 1)
	return t + "…"


func _char_menu_sub() -> String:
	var ready: Array = Save.get_value("unlocks.char_ready", [])
	if ready is Array and not (ready as Array).is_empty():
		return "내림굿을 올릴 수 있다!"
	return "모신 무당: " + UiKit.char_name(String(Save.selected_char()))


func _uiroe_menu_sub(runs: int, need: int) -> String:
	if not Save.uiroe_open():
		return "굿 %d번 뒤 열림 (%d/%d)" % [need, mini(runs, need), need]
	var a: String = Save.uiroe_accepted()
	if a != "":
		return "받음: " + String(MetaRules.uiroe_def(a).get("sayeon_ko", a))
	return "사연 %d장이 와 있다" % Save.uiroe_offers().size()


func _greet() -> void:
	var s: Dictionary = Save.last_settlement
	if not s.is_empty() and bool(s.get("first_run", false)):
		_set_bark("첫 굿을 잘 치렀구나. 네가 올린 넋이 공덕이 되었다. 촛불부터 하나 더 밝혀 보렴.")
	elif not s.is_empty() and bool(s.get("uiroe_done", false)):
		_set_bark("재가집에서 고맙다는 기별이 왔다. \"%s\"" % String(s.get("uiroe_thanks", "")))
	elif not s.is_empty():
		_set_bark(_bark_after_run(s))
	else:
		var lines: PackedStringArray = PackedStringArray([
			"굿은 혼자 여는 게 아니다. 신령과 넋, 재가집이 함께 연다.",
			"한이 풀릴 기색을 보이면 길베로 둘레를 감아라. 고리가 닫히면 넋이 풀려난다.",
			"퇴치도 해원도 다 굿의 길이다. 어느 쪽도 그르지 않다.",
			"신단이 채워질수록 신령이 오래 머문다.",
		])
		_set_bark(lines[int(Time.get_ticks_msec() / 1000) % lines.size()])


func _bark_after_run(s: Dictionary) -> String:
	var n: float = float(s.get("N", 0.0))
	if String(s.get("result", "")).begins_with("CLEAR"):
		return "굿판을 끝까지 지켜 냈구나. 저승 문이 오늘은 조용하다."
	if n >= 0.6:
		return "넋을 많이 풀어 주었구나. 공덕이 두텁게 쌓였다."
	if n <= 0.3:
		return "귀신을 많이 물리쳤구나. 엽전 꾸러미가 무겁다. 다음엔 고리도 닫아 보렴."
	return "넋도 풀고 귀신도 물리쳤구나. 어울린 굿이다."


func _set_bark(s: String, speaker: String = "신어머니") -> void:
	_bark_full = s
	_bark_speaker = speaker
	_bark_n = 0.0
	_bark_shown = ""


# ═══ 패널 ═════════════════════════════════════════════════════════════

func open_panel(id: String) -> void:
	if _panel != id:
		_scroll = 0.0
		_scroll_target = 0.0
		_item_i = 0
	_panel = id
	_zone = 1
	_build_panel()
	if id == "char":
		for i in _items.size():
			if String(_items[i].get("id", "")) == String(Save.selected_char()):
				_item_i = i
	Audio.play_sfx(&"sfx_ui_card_select", &"UI")
	_ensure_visible()


func close_panel() -> void:
	if _panel == "":
		return
	_panel = ""
	_zone = 0
	_hold_on = false
	Audio.play_sfx(&"sfx_ui_back", &"UI")


func _build_panel() -> void:
	_items.clear()
	_foot = PackedStringArray()
	_header_sub = PackedStringArray()
	match _panel:
		"depart": _build_depart()
		"char": _build_char()
		"danjang": _build_danjang()
		"uiroe": _build_uiroe()
		"singirok": _build_singirok()
		"weapons": _build_weapons()
	_content_h = 0.0
	for it: Dictionary in _items:
		var r: Rect2 = it["rect"]
		_content_h = maxf(_content_h, r.end.y + 6.0)
	_item_i = clampi(_item_i, 0, maxi(0, _items.size() - 1))
	_pc.queue_redraw()


## 머리 설명 아래 첫 항목 y
func _y0() -> float:
	return 48.0 + 9.0 * float(_header_sub.size())


func _wrap(s: String, w: float, f: Font = null, size: int = 10, lines: int = 4) -> PackedStringArray:
	return UiKit.wrap(f if f != null else _f_small, size, s, w, lines)


func _build_depart() -> void:
	_header = "굿판 문"
	_header_sub = _wrap("선바위 굿당 · 표준 굿 · 20분", PANEL_W - 24.0, _f_tiny, 8, 1)
	var y: float = _y0()
	var guide: Dictionary = {"kind": "guide", "rect": Rect2(8, y, PANEL_W - 16, 146), "sel": false,
		"l1": _wrap("붉은 무구로 치면 귀신을 물리친다(퇴치). 엽전이 모여 복전이 된다.", PANEL_W - 52.0),
		"l2": _wrap("귀신이 흰 테두리로 떨면 한이 풀릴 기색. 내 뒤에 남는 흰 길베로 그 둘레를 한 바퀴 감아 고리를 닫으면 해원 — 넋이 되어 따라온다.", PANEL_W - 52.0, null, 10, 5),
		"l3": _wrap("넋은 굿이 끝나면 공덕이 된다. 퇴치도 해원도 다 굿의 길이다.", PANEL_W - 52.0)}
	_items.append(guide)
	y += 152.0
	var cid: String = String(Save.selected_char())
	_items.append({"kind": "button", "id": "start", "rect": Rect2(8, y, PANEL_W - 16, 38), "sel": true,
		"title": "굿판 열기", "sub": "%s · %s" % [UiKit.char_name(cid), _start_weapons_text(cid)], "hold": false, "on": true})
	y += 40.0
	_items.append({"kind": "button", "id": "goto_char", "rect": Rect2(8, y, (PANEL_W - 22) * 0.5, 24), "sel": true,
		"title": "무당 바꾸기", "sub": "", "hold": false, "on": true})
	var ua: String = Save.uiroe_accepted()
	var ut: String = "의뢰: " + String(MetaRules.uiroe_def(ua).get("sayeon_ko", "")) if ua != "" else ("의뢰 고르기" if Save.uiroe_open() else "의뢰 (잠김)")
	_items.append({"kind": "button", "id": "goto_uiroe", "rect": Rect2(14 + (PANEL_W - 22) * 0.5, y, (PANEL_W - 22) * 0.5, 24), "sel": true,
		"title": _fit(ut, _f_small, 10, (PANEL_W - 22) * 0.5 - 8.0), "sub": "", "hold": false, "on": Save.uiroe_open()})


func _start_weapons_text(cid: String) -> String:
	var sw: Variant = Data.character(cid).get("start_weapons", [])
	var names: PackedStringArray = PackedStringArray()
	if sw is Array:
		for w: Variant in sw:
			if w is Dictionary:
				var wd: Dictionary = Data.weapon(String((w as Dictionary).get("wpn", "")).split("__")[0])
				names.append(String(wd.get("name_ko", (w as Dictionary).get("wpn", ""))))
	return "·".join(names)


func _build_char() -> void:
	_header = "무당"
	_header_sub = _wrap("굿을 맡을 무당을 고른다. 인연이 닿으면 공덕을 올려 내림굿을 한다.", PANEL_W - 24.0, _f_tiny, 8, 2)
	var y: float = _y0()
	for c: Variant in MetaRules.char_defs():
		var cid: String = String((c as Dictionary).get("id", ""))
		var unlocked: bool = Save.char_unlocked(StringName(cid))
		var ready: bool = not unlocked and MetaRules.char_ready(Save.profile, cid)
		var pr: Vector2i = MetaRules.char_progress(Save.profile, cid)
		var cond: Dictionary = MetaRules.char_condition(cid)
		var status: String
		if unlocked:
			status = "모심" if StringName(cid) == Save.selected_char() else "고르기"
		elif ready:
			status = "내림굿 · 공덕 %s (길게 눌러)" % _fmt(MetaRules.char_cost(cid))
		else:
			var ctext: String = String(cond.get("text", ""))
			var paren: int = ctext.find(" (v1")
			if paren >= 0:
				ctext = ctext.left(paren)
			status = "인연: %s (%d/%d)" % [ctext, pr.x, pr.y]
		var def: Dictionary = Data.character(cid)
		var tb: Variant = def.get("tendency_bar", {})
		var frames: Array[Texture2D] = SpriteLib.anim_frames_any(cid, "idle", "south")
		var tex: Texture2D = frames[0] if not frames.is_empty() else SpriteLib.dir_tex(cid, "south", 64)
		_items.append({"kind": "char", "id": cid, "rect": Rect2(6, y, PANEL_W - 12, 56), "sel": true,
			"title": UiKit.char_name(cid), "hanja": UiKit.char_hanja(cid), "tex": tex,
			"unlocked": unlocked, "ready": ready, "status": _wrap(status, PANEL_W - 90.0, _f_tiny, 8, 2),
			"weapons": _start_weapons_text(cid), "toechi": int((tb as Dictionary).get("toechi", 0)) if tb is Dictionary else 0,
			"haewon": int((tb as Dictionary).get("haewon", 0)) if tb is Dictionary else 0,
			"hold": ready, "on": unlocked or ready, "chosen": unlocked and StringName(cid) == Save.selected_char()})
		y += 60.0


func _build_danjang() -> void:
	_header = "신당 단장"
	_header_sub = _wrap("신단을 꾸미면 그 정성이 굿판에서 힘이 된다. 길게 눌러 봉헌.", PANEL_W - 24.0, _f_tiny, 8, 2)
	var y: float = _y0()
	for it: Variant in MetaRules.danjang_items():
		var d: Dictionary = it
		var id: String = String(d.get("id", ""))
		var r: int = Save.danjang_rank(id)
		var mx: int = int(d.get("max_rank", 1))
		var cost: int = MetaRules.danjang_next_cost(Save.profile, id)
		var cur: StringName = MetaRules.danjang_currency(id)
		var afford: bool = cost >= 0 and Save.wallet(cur) >= cost
		_items.append({"kind": "danjang", "id": id, "rect": Rect2(6, y, PANEL_W - 12, 38), "sel": true,
			"title": String(d.get("name_ko", id)), "hanja": String(d.get("hanja", "")).left(1),
			"effect": String(d.get("effect_ko", "")), "flavor": String(d.get("flavor_ko", "")), "rank": r, "max": mx,
			"cost": cost, "cost_txt": ("다 갖춤" if cost < 0 else _fmt(cost)), "cur": cur, "afford": afford,
			"hold": cost >= 0, "on": cost >= 0})
		y += 41.0
	_foot = PackedStringArray()


func _build_uiroe() -> void:
	_header = "재가집 의뢰"
	_header_sub = _wrap("굿을 청한 집의 사연. 한 장을 받으면 이번 굿판이 그 사연대로 바뀐다. 굿을 끝까지 마치면 보답이 있다.", PANEL_W - 24.0, _f_tiny, 8, 3)
	var y: float = _y0()
	if not Save.uiroe_open():
		var need: int = int(MetaRules.num("sindang_v1.uiroe_open_after_runs", 3.0))
		_items.append({"kind": "note", "rect": Rect2(8, y, PANEL_W - 16, 40), "sel": false,
			"lines": _wrap("굿을 %d번 치르면 재가집에서 의뢰가 들어온다. (%d/%d)" % [need, mini(Save.runs_done(), need), need], PANEL_W - 32.0)})
		return
	var acc: String = Save.uiroe_accepted()
	for id: Variant in Save.uiroe_offers():
		var sid: String = String(id)
		var tx: Dictionary = MetaRules.uiroe_text(sid)
		var mods: PackedStringArray = PackedStringArray()
		for m: String in (tx["mods"] as Array):
			mods.append("· " + m)
		_items.append({"kind": "uiroe", "id": sid, "rect": Rect2(6, y, PANEL_W - 12, 70), "sel": true,
			"title": String(tx["sayeon"]), "mods": mods, "reward": "보답: " + String(tx["reward"]),
			"accepted": sid == acc, "hold": false, "on": true})
		y += 74.0
	_items.append({"kind": "button", "id": "uiroe_none", "rect": Rect2(6, y, PANEL_W - 12, 22), "sel": true,
		"title": "받지 않기" + (" (지금)" if acc == "" else ""), "sub": "", "hold": false, "on": true})


func _build_weapons() -> void:
	_header = "무구 진열장"
	_header_sub = _wrap("갖춘 무구만 굿판의 점지에 나온다. 흰 무구는 공덕을 봉헌하고, 붉은 무구는 복전으로 제작한다. 길게 눌러 확정.", PANEL_W - 24.0, _f_tiny, 8, 3)
	var y: float = _y0()
	for w: Variant in MetaRules.weapon_defs():
		var d: Dictionary = w
		var id: String = String(d.get("id", ""))
		if not Data.is_v1(Data.weapon(id)) and not Data.weapon(id).is_empty():
			continue
		var st: String = MetaRules.weapon_state(Save.profile, id)
		var cost: int = MetaRules.weapon_cost(id)
		var cur: StringName = MetaRules.weapon_currency(id)
		var note: String = ""
		match st:
			"owned": note = "갖춤 · " + String(Data.weapon(id).get("archetype", ""))
			"undiscovered": note = "발견: " + String(d.get("discover_condition", ""))
			"gate": note = "같은 색 무구 %d개를 먼저 갖추면 열린다" % int(d.get("gate_same_color_purchased", 0))
			_: note = String(Data.weapon(id).get("archetype", ""))
		var white: bool = String(d.get("color", "red")) == "white"
		_items.append({"kind": "weapon", "id": id, "rect": Rect2(6, y, PANEL_W - 12, 32), "sel": true,
			"title": String(d.get("name_ko", id)) if st != "undiscovered" else "???", "white": white, "tier": int(d.get("tier", 0)),
			"state": st, "note": _fit(note, _f_tiny, 8, PANEL_W - 110.0), "cost": cost, "cost_txt": _fmt(cost), "cur": cur,
			"afford": Save.wallet(cur) >= cost, "icon": UiKit.weapon_icon(id, true), "hold": st == "buyable", "on": st == "buyable"})
		y += 35.0


func _build_singirok() -> void:
	_header = "넋기록 서고"
	_header_sub = _wrap("해원록(풀어 준 넋)과 벽사록(물리친 귀신). 첫 해원마다 사연 조각을 얻는다.", PANEL_W - 24.0, _f_tiny, 8, 2)
	var species: Array = Data.get_value("enemies", "enemies", [])
	var x0: float = 6.0
	var y0: float = _y0()
	var cw: float = 64.0
	var ch: float = 64.0
	var i: int = 0
	for e: Variant in species:
		if not (e is Dictionary):
			continue
		var sid: String = String((e as Dictionary).get("id", ""))
		var h: int = int(Save.get_value("singirok.haewonrok.%s.haewon" % sid, 0))
		var t: int = int(Save.get_value("singirok.byeoksarok.%s.toechi" % sid, 0))
		var pieces: Variant = Save.get_value("singirok.haewonrok.%s.pieces" % sid, [])
		var tier: int = int(Save.get_value("singirok.byeoksarok.%s.tier" % sid, 0))
		var seen: bool = h > 0 or t > 0
		var cond: Variant = MetaRules.econ("singirok.haewonrok.sayeon_conditions." + sid, {})
		var cond_txt: String = String((cond as Dictionary).get("ko", "")) if cond is Dictionary else ""
		var col: int = i % 4
		var row: int = i / 4
		_items.append({"kind": "species", "id": sid, "rect": Rect2(x0 + float(col) * cw, y0 + float(row) * ch, cw - 2.0, ch - 2.0),
			"sel": true, "title": MetaRules.enemy_ko(sid) if seen else "???", "tex": SpriteLib.dir_tex(sid, "south", 32),
			"seen": seen, "haewon": h, "toechi": t, "pieces": (pieces as Array).size() if pieces is Array else 0, "tier": tier,
			"detail": _wrap(("사연: " + cond_txt) if seen and cond_txt != "" else "아직 만나지 못한 귀신이다.", PANEL_W - 20.0, _f_tiny, 8, 2),
			"hold": false, "on": true})
		i += 1


# ═══ 행동 ═════════════════════════════════════════════════════════════

func _activate_menu(i: int) -> void:
	var m: Dictionary = _menu[i]
	if not bool(m["on"]):
		_reject(-1, String(m["sub"]))
		return
	if String(m["id"]) == "title":
		Audio.play_sfx(&"sfx_ui_back", &"UI")
		back_requested.emit()
		return
	open_panel(String(m["id"]))


func _activate_item(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	var it: Dictionary = _items[i]
	match String(it["kind"]):
		"button":
			match String(it["id"]):
				"start": _start_run()
				"goto_char": open_panel("char")
				"goto_uiroe":
					if Save.uiroe_open():
						open_panel("uiroe")
					else:
						_reject(i, "굿을 세 번 치르면 열린다")
				"uiroe_none":
					Save.accept_uiroe("")
					Audio.play_sfx(&"sfx_ui_confirm", &"UI")
					_set_bark("이번엔 사연 없이 굿판을 연다. 그것도 괜찮다.")
		"char":
			var cid: StringName = StringName(String(it["id"]))
			if bool(it["unlocked"]):
				if cid != Save.selected_char():
					Save.select_char(cid)
					backdrop.call("set_character", cid, true)
					Audio.play_sfx(&"sfx_ui_confirm", &"UI")
					_pulse_item(i)
					_set_bark(_char_bark(String(cid)), UiKit.char_name(String(cid)))
			elif bool(it["ready"]):
				var r: Dictionary = Save.unlock_char(cid)
				if bool(r["ok"]):
					backdrop.call("set_character", cid, true)
					backdrop.call("burst", Vector2(320, 250), 40)
					backdrop.set("shake", 1.0)
					_slam("내림굿")
					_screen_flash = 0.7
					Audio.play_sfx(&"sfx_ui_unlock", &"UI")
					Audio.play_sfx(&"sfx_trl_bingui", &"SFX", -6.0)
					_set_bark("방울을 받아라. 이제 너도 신의 제자다.")
				else:
					_reject(i, String(r["reason"]))
			else:
				_reject(i, "아직 인연이 닿지 않았다")
		"danjang":
			var res: Dictionary = Save.buy_danjang(String(it["id"]))
			if bool(res["ok"]):
				backdrop.call("celebrate", String(it["id"]))
				Audio.play_sfx(&"sfx_ui_unlock", &"UI")
				_pulse_item(i)
				_wallet_bump = 1.0
				_set_bark(String(MetaRules.danjang_item(String(it["id"])).get("flavor_ko", "")) + " — " + String(it["effect"]))
			else:
				_reject(i, String(res["reason"]))
		"weapon":
			if String(it["state"]) != "buyable":
				_reject(i, String(it["note"]) if String(it["state"]) != "owned" else "")
				return
			var wr: Dictionary = Save.buy_weapon(String(it["id"]))
			if bool(wr["ok"]):
				backdrop.call("burst", Vector2(320, 160), 30)
				backdrop.set("shake", 0.7)
				Audio.play_sfx(&"sfx_ui_unlock", &"UI")
				_pulse_item(i)
				_wallet_bump = 1.0
				_set_bark("%s%s 진열장에 걸렸다. 이제 굿판에서 점지될 수 있다." % [String(it["title"]), MetaRules.josa(String(it["title"]), "이", "가")])
			else:
				_reject(i, String(wr["reason"]))
		"uiroe":
			var uid: String = String(it["id"])
			Save.accept_uiroe("" if bool(it["accepted"]) else uid)
			Audio.play_sfx(&"sfx_ui_card_select", &"UI")
			_pulse_item(i)
			if not bool(it["accepted"]):
				_set_bark("\"%s\" — 그 집의 사연을 품고 굿판에 나서자." % String(it["title"]))
		_:
			pass


func _char_bark(cid: String) -> String:
	match cid:
		"char_mansin": return "만신 몸주를 모시고 나선다. 붉은 신칼과 방울로 고르게."
		"char_baksu": return "월도를 쥐었다. 물리치는 굿에 능하다."
		"char_dangol": return "장구 장단으로 넋을 달랜다. 풀어 주는 굿에 능하다."
		"char_myeongdu": return "동자령이 곁에 붙는다. 각궁으로 멀리서 친다."
		"char_simbang": return "제주 굿의 멩두를 든다. 점괘를 다시 묻는 데 능하다."
	return "이 무당으로 굿을 연다."


func _reject(i: int, reason: String) -> void:
	_nudge = 1.0
	_nudge_i = i
	Audio.play_sfx(&"sfx_ui_error", &"UI")
	if reason != "":
		_push_toast(reason)


func _pulse_item(i: int) -> void:
	_pulse = 1.0
	_pulse_i = i


func _slam(s: String) -> void:
	_slam_text = s
	_slam_t = 1.6


func _push_toast(s: String) -> void:
	if _toast_t > 0.0 and _toast.size() > 0 and " ".join(_toast) == s:
		return
	_toasts.append(s)
	if _toast_t > 0.3:
		_toast_t = 0.3      # 떠 있는 알림은 빨리 접고 새 알림을 올린다


func _start_run() -> void:
	if _starting:
		return
	_starting = true
	_start_t = 0.0
	Audio.play_sfx(&"sfx_ui_title_start", &"UI")
	backdrop.set("shake", 0.5)
	_slam("굿판 열기")
	_screen_flash = 0.3


func _emit_start() -> void:
	var cid: StringName = Save.selected_char()
	print("[meta] lobby start char=%s uiroe=%s gongdeok=%d bokjeon=%d" % [cid, Save.uiroe_accepted(), Save.wallet(MetaRules.CUR_G), Save.wallet(MetaRules.CUR_B)])
	if start_requested.get_connections().is_empty():
		# TODO(core): main.gd 가 start_requested → _go_run 을 연결하면 이 분기는 필요 없다.
		var p: Node = get_parent()
		if p != null and p.has_method("_go_run"):
			p.call("_go_run", cid)
			return
	start_requested.emit(cid)


func _on_profile_changed() -> void:
	_build_menu()
	if _panel != "":
		_build_panel()
	_refresh_backdrop()


func _refresh_backdrop() -> void:
	var d: Variant = Save.get_value("danjang", {})
	backdrop.call("refresh", d if d is Dictionary else {})


# ═══ 입력 ═════════════════════════════════════════════════════════════

func _unhandled_input(e: InputEvent) -> void:
	if _starting:
		return
	if e is InputEventKey or e is InputEventJoypadButton or e is InputEventJoypadMotion:
		if _pressed(e, [&"ui_up", &"move_up"]):
			_move(0, -1)
		elif _pressed(e, [&"ui_down", &"move_down"]):
			_move(0, 1)
		elif _pressed(e, [&"ui_left", &"move_left"]):
			_move(-1, 0)
		elif _pressed(e, [&"ui_right", &"move_right"]):
			_move(1, 0)
		elif _pressed(e, [&"ui_accept", &"confirm"]):
			_accept_down()
		elif _released(e, [&"ui_accept", &"confirm"]):
			_accept_up()
		elif _pressed(e, [&"ui_cancel", &"cancel", &"pause"]):
			if _zone == 1:
				close_panel()
		else:
			return
		get_viewport().set_input_as_handled()


func _pressed(e: InputEvent, acts: Array[StringName]) -> bool:
	for a: StringName in acts:
		if InputMap.has_action(a) and e.is_action_pressed(a, false):
			return true
	return false


func _released(e: InputEvent, acts: Array[StringName]) -> bool:
	for a: StringName in acts:
		if InputMap.has_action(a) and e.is_action_released(a):
			return true
	return false


func _gui_input(e: InputEvent) -> void:
	if _starting:
		return
	if e is InputEventMouseMotion:
		_hover((e as InputEventMouseMotion).position)
	elif e is InputEventMouseButton:
		var mb: InputEventMouseButton = e
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_scroll_target = maxf(0.0, _scroll_target - 24.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_scroll_target = clampf(_scroll_target + 24.0, 0.0, maxf(0.0, _content_h - PANEL_H))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _hover(mb.position):
					_accept_down()
				elif _zone == 1 and not Rect2(_pc.position, _pc.size).has_point(mb.position):
					close_panel()
			else:
				_accept_up()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _zone == 1:
			close_panel()


## 마우스 위치의 항목에 초점. 항목 위면 true.
func _hover(p: Vector2) -> bool:
	for i in _menu.size():
		if _menu_rect(i).has_point(p):
			if _zone != 0 or _menu_i != i:
				if _zone == 0:
					Audio.play_sfx(&"sfx_ui_nav", &"UI", -8.0)
				_zone = 0
				_menu_i = i
			return true
	if _panel != "" and Rect2(_pc.position, _pc.size).has_point(p):
		var lp: Vector2 = p - _pc.position + Vector2(0.0, _scroll)
		for i in _items.size():
			if bool(_items[i].get("sel", false)) and (_items[i]["rect"] as Rect2).has_point(lp):
				if _zone != 1 or _item_i != i:
					Audio.play_sfx(&"sfx_ui_nav", &"UI", -8.0)
					_zone = 1
					_item_i = i
					_hold_on = false
				return true
	return false


func _move(dx: int, dy: int) -> void:
	_hold_on = false
	if _zone == 0:
		if dx > 0 and _panel != "":
			_zone = 1
		elif dy != 0:
			_menu_i = wrapi(_menu_i + dy, 0, _menu.size())
		Audio.play_sfx(&"sfx_ui_nav", &"UI", -6.0)
		return
	if dx < 0 and (_panel != "singirok" or _item_i % 4 == 0):
		_zone = 0
		Audio.play_sfx(&"sfx_ui_nav", &"UI", -6.0)
		return
	var n: int = _items.size()
	if n == 0:
		return
	if _panel == "singirok":
		var ni: int = _item_i + dx + dy * 4
		if ni >= 0 and ni < n:
			_item_i = ni
	else:
		# 2열 버튼(굿판 문 아래)은 좌우로, 나머지는 위아래로
		var step: int = dy if dy != 0 else dx
		var j: int = _item_i
		for k in n:
			j = wrapi(j + step, 0, n)
			if bool(_items[j].get("sel", false)):
				break
		_item_i = j
	Audio.play_sfx(&"sfx_ui_nav", &"UI", -6.0)
	_ensure_visible()


func _ensure_visible() -> void:
	if _items.is_empty() or _item_i < 0 or _item_i >= _items.size():
		return
	var r: Rect2 = _items[_item_i]["rect"]
	if r.position.y - 46.0 < _scroll_target:
		_scroll_target = maxf(0.0, r.position.y - 46.0)
	elif r.end.y + 6.0 > _scroll_target + PANEL_H:
		_scroll_target = r.end.y + 6.0 - PANEL_H
	_scroll_target = clampf(_scroll_target, 0.0, maxf(0.0, _content_h - PANEL_H))


func _accept_down() -> void:
	if _zone == 0:
		_activate_menu(_menu_i)
		return
	if _item_i < 0 or _item_i >= _items.size():
		return
	var it: Dictionary = _items[_item_i]
	if not bool(it.get("sel", false)):
		return
	if bool(it.get("hold", false)):
		_hold_on = true
		_hold_t = 0.0
		_hold_item = _item_i
		Audio.play_sfx(&"sfx_ui_card_hover__red", &"UI", -4.0)
	else:
		_activate_item(_item_i)


func _accept_up() -> void:
	if _hold_on:
		_hold_on = false
		if _hold_t < HOLD_S:
			_push_toast("길게 눌러 올린다")


# ═══ 진행 ═════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_t += delta
	var target: float = 1.0 if _panel != "" else 0.0
	_panel_k = move_toward(_panel_k, target, delta / 0.18)
	var e: float = UiKit.ease_out_cubic(_panel_k)
	_pc.position = Vector2(roundf(640.0 - (640.0 - PANEL_X) * e), PANEL_Y)
	backdrop.set("base_pos", Vector2(-roundf(64.0 * e), 0.0))
	backdrop.set("dim", e * 0.6)
	_scroll = lerpf(_scroll, _scroll_target, minf(1.0, delta * 14.0))
	if absf(_scroll - _scroll_target) < 0.5:
		_scroll = _scroll_target
	if _hold_on:
		_hold_t += delta
		if _hold_t >= HOLD_S:
			_hold_on = false
			_activate_item(_hold_item)
	_nudge = maxf(0.0, _nudge - delta * 4.0)
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	_wallet_bump = maxf(0.0, _wallet_bump - delta * 3.0)
	_screen_flash = maxf(0.0, _screen_flash - delta * 2.0)
	_slam_t = maxf(0.0, _slam_t - delta)
	# 지갑 굴림
	var tg: float = float(Save.wallet(MetaRules.CUR_G))
	var tb: float = float(Save.wallet(MetaRules.CUR_B))
	if _count_delay > 0.0:
		_count_delay -= delta
	elif _disp_g != tg or _disp_b != tb:
		_disp_g = tg if absf(tg - _disp_g) < 1.0 else lerpf(_disp_g, tg, minf(1.0, delta * _count_rate))
		_disp_b = tb if absf(tb - _disp_b) < 1.0 else lerpf(_disp_b, tb, minf(1.0, delta * _count_rate))
		if _disp_g == tg and _disp_b == tb and _count_rate < 8.0:
			_count_rate = 8.0
			_wallet_bump = 1.0
			Audio.play_sfx(&"sfx_ui_settle_tick", &"UI")
		var sg: String = _fmt(int(roundf(_disp_g)))
		if sg != _txt_g:
			_txt_g = sg
		var sb: String = _fmt(int(roundf(_disp_b)))
		if sb != _txt_b:
			_txt_b = sb
	# 신어머니 말(타자)
	if _bark_n < float(_bark_full.length()):
		_bark_n += delta * 28.0
		var n: int = mini(_bark_full.length(), int(_bark_n))
		if n != _bark_shown.length():
			_bark_shown = _bark_full.left(n)
	# 알림
	if _toast_t > 0.0:
		_toast_t -= delta
	elif not _toasts.is_empty():
		var s: String = _toasts.pop_front()
		_toast = UiKit.wrap(_f_small, 10, s, 200.0 if _panel != "" else 300.0, 3)
		_toast_t = 3.4
		Audio.play_sfx(&"sfx_ui_settle_tick", &"UI", -6.0)
	if _starting:
		_start_t += delta
		if _start_t >= 0.9:
			_starting = false
			_emit_start()
	_ui.queue_redraw()
	_pc.queue_redraw()


# ═══ 그리기 ═══════════════════════════════════════════════════════════

func _menu_rect(i: int) -> Rect2:
	return Rect2(MENU_X, MENU_Y + float(i) * (MENU_H + 6.0), MENU_W, MENU_H)


func _draw_ui() -> void:
	var c: CanvasItem = _ui
	# 제목
	UiKit.text_outline(c, _f_brush, 32, Vector2(16, 44), "신당", C_HANJI, 0, 2)
	UiKit.text(c, _f_tiny, 8, Vector2(74, 30), "神堂", C_HANJI3, 0)
	UiKit.text(c, _f_tiny, 8, Vector2(74, 41), "선바위 굿당", C_HANJI3, 0)
	# 지갑
	var bump: float = roundf(_wallet_bump * -2.0)
	_draw_chip(c, Rect2(432, 18 + bump, 98, 18), "공덕", _txt_g, C_HANJI, true)
	_draw_chip(c, Rect2(536, 18 + bump, 92, 18), "복전", _txt_b, C_HWANG, false)
	# 메뉴
	for i in _menu.size():
		_draw_menu_item(c, i)
	# 신어머니 말
	if _bark_full != "":
		var br: Rect2 = Rect2(140, 334, 360, 22)
		if _panel != "":
			br = Rect2(12, 334, 344, 22)
		UiKit.draw_meok_panel(c, br, 0.9)
		UiKit.draw_seal(c, br.position + Vector2(3, 3), 16.0, _bark_speaker.left(1), _f_tiny, 8)
		UiKit.text(c, _f_tiny, 8, br.position + Vector2(24, 9), _bark_speaker, C_JEOK_HI, 0)
		var lines: PackedStringArray = _bark_lines()
		for li in lines.size():
			UiKit.text(c, _f_tiny, 8, br.position + Vector2(24 + 40, 9 + li * 9), lines[li], C_HANJI, 0)
	# 알림(한지 두루마리)
	if _toast_t > 0.0 and _toast.size() > 0:
		var k: float = clampf((3.4 - _toast_t) / 0.18, 0.0, 1.0) * clampf(_toast_t / 0.3, 0.0, 1.0)
		var h: float = 10.0 + 11.0 * float(_toast.size())
		# 패널이 열려 있으면 패널에 가리지 않게 왼쪽(신단 위)으로 옮긴다.
		var pe: float = UiKit.ease_out_cubic(_panel_k)
		var tcx: float = roundf(lerpf(320.0, 248.0, pe))
		var tw: float = roundf(lerpf(320.0, 216.0, pe))
		var tr: Rect2 = Rect2(roundf(tcx - tw * 0.5), roundf(-h + (h + 46.0) * UiKit.ease_out_cubic(k)), tw, h)
		UiKit.draw_hanji_panel(c, tr)
		for li in _toast.size():
			UiKit.text(c, _f_small, 10, Vector2(tcx, tr.position.y + 13 + li * 11), _toast[li], C_MEOK, 1, false)
	# 붓 슬램
	if _slam_t > 0.0:
		var a: float = clampf(_slam_t / 0.4, 0.0, 1.0)
		var grow: float = UiKit.ease_out_back(clampf((1.6 - _slam_t) / 0.25, 0.0, 1.0))
		var sz: int = 40 + int(roundf(8.0 * (1.0 - grow)))
		c.draw_rect(Rect2(0, 150, 640, 50), Color(C_MEOK, 0.55 * a))
		UiKit.text_outline(c, _f_brush, sz, Vector2(320 - (64 if _panel != "" else 0), 190), _slam_text, Color(C_HANJI, a), 1, 3)
	if _screen_flash > 0.0:
		c.draw_rect(Rect2(0, 0, 640, 360), Color(C_HANJI_UI, _screen_flash * 0.6))


var _bark_cache_src: String = ""
var _bark_cache: PackedStringArray = PackedStringArray()

func _bark_lines() -> PackedStringArray:
	if _bark_shown != _bark_cache_src:
		_bark_cache_src = _bark_shown
		var w: float = (344.0 if _panel != "" else 360.0) - 70.0
		_bark_cache = UiKit.wrap(_f_tiny, 8, _bark_shown, w, 2)
	return _bark_cache


func _draw_chip(c: CanvasItem, r: Rect2, label: String, val: String, col: Color, hanji_icon: bool) -> void:
	UiKit.draw_meok_panel(c, r, 0.92)
	var ic: Vector2 = r.position + Vector2(9, 9)
	if hanji_icon:
		# 접힌 한지(공덕)
		c.draw_rect(Rect2(ic - Vector2(4, 4), Vector2(8, 8)), C_HANJI)
		c.draw_rect(Rect2(ic - Vector2(4, 4), Vector2(8, 1)), C_HANJI3)
		c.draw_rect(Rect2(ic + Vector2(-1, -3), Vector2(1, 7)), C_JEOK)
	else:
		# 엽전(복전)
		c.draw_circle(ic, 4.5, C_HWANG_DK)
		c.draw_circle(ic, 3.5, C_HWANG)
		c.draw_rect(Rect2(ic - Vector2(1, 1), Vector2(2, 2)), C_MEOK)
	UiKit.text(c, _f_tiny, 8, r.position + Vector2(17, 12), label, C_HANJI3, 0)
	UiKit.text(c, _f_body, 12, Vector2(r.end.x - 5, r.position.y + 13), val, col, 2)


func _draw_menu_item(c: CanvasItem, i: int) -> void:
	var m: Dictionary = _menu[i]
	var r: Rect2 = _menu_rect(i)
	var focus: bool = _zone == 0 and i == _menu_i
	var open: bool = _panel == String(m["id"])
	var on: bool = bool(m["on"])
	if focus:
		r.position.x += 4.0
	if i == _nudge_i and _nudge > 0.0 and _zone == 0:
		r.position.x += roundf(sin(_nudge * 30.0) * 2.0 * _nudge)
	# 한지 표찰(걸린 종이)
	c.draw_rect(r.grow(1.0), C_MEOK)
	c.draw_rect(r, C_HANJI if on else C_HANJI4)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), C_HANJI_UI if on else C_HANJI3)
	c.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), C_HANJI3 if on else C_HANJI5)
	if focus or open:
		c.draw_rect(Rect2(r.position + Vector2(-4, 0), Vector2(3, r.size.y)), C_JEOK)
	if focus:
		UiKit.draw_corners(c, r.grow(2.0), C_JEOK)
	var tc: Color = C_MEOK if on else C_MEOK3
	UiKit.text(c, _f_bold, 12, r.position + Vector2(8, 12), String(m["label"]), tc, 0, false)
	UiKit.text(c, _f_tiny, 8, r.position + Vector2(8, 22), String(m["fit"]), C_HANJI5 if on else C_MEOK4, 0, false)
	if String(m["id"]) == "char" and String(m["sub"]).begins_with("내림굿"):
		var a: float = 0.5 + 0.5 * sin(_t * 6.0)
		c.draw_circle(r.position + Vector2(r.size.x - 8, 7), 3.0, Color(C_JEOK, a))


func _draw_panel() -> void:
	if _panel == "" and _panel_k <= 0.0:
		return
	var c: CanvasItem = _pc
	var full: Rect2 = Rect2(Vector2.ZERO, _pc.size)
	UiKit.draw_meok_panel(c, full, 0.94)
	c.draw_rect(Rect2(1, 1, full.size.x - 2, 3), C_JEOK_DK)
	var oy: float = -_scroll
	# 머리
	UiKit.text_outline(c, _f_brush, 22, Vector2(10, 24 + oy), _header, C_HANJI, 0, 2)
	c.draw_rect(Rect2(10, 31 + oy, PANEL_W - 20, 1), Color(C_HANJI5, 0.8))
	for li in _header_sub.size():
		UiKit.text(c, _f_tiny, 8, Vector2(12, 42 + li * 9 + oy), _header_sub[li], C_HANJI3, 0)
	for i in _items.size():
		var it: Dictionary = _items[i]
		var r: Rect2 = (it["rect"] as Rect2)
		r.position.y += oy
		if r.end.y < 0.0 or r.position.y > PANEL_H:
			continue
		var focus: bool = _zone == 1 and i == _item_i
		if i == _nudge_i and _nudge > 0.0 and _zone == 1:
			r.position.x += roundf(sin(_nudge * 30.0) * 2.0 * _nudge)
		match String(it["kind"]):
			"guide": _draw_guide(c, r, it)
			"button": _draw_button(c, r, it, focus)
			"char": _draw_char_row(c, r, it, focus)
			"danjang": _draw_danjang_row(c, r, it, focus)
			"uiroe": _draw_uiroe_card(c, r, it, focus)
			"species": _draw_species(c, r, it, focus)
			"weapon": _draw_weapon_row(c, r, it, focus)
			"note":
				UiKit.draw_hanji_panel(c, r)
				var ls: PackedStringArray = it["lines"]
				for li in ls.size():
					UiKit.text(c, _f_small, 10, r.position + Vector2(8, 14 + li * 11), ls[li], C_MEOK, 0, false)
		if focus and _hold_on and _hold_item == i:
			var k: float = clampf(_hold_t / HOLD_S, 0.0, 1.0)
			c.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(roundf(r.size.x * k), 3)), C_JEOK_HI)
			c.draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * k), r.size.y)), Color(C_JEOK, 0.18))
		if i == _pulse_i and _pulse > 0.0:
			c.draw_rect(r.grow(2.0 * (1.0 - _pulse)), Color(C_HWANG_HI, _pulse), false, 1.0)
	# 넋기록: 초점 종 설명(바닥 고정)
	if _panel == "singirok" and _item_i >= 0 and _item_i < _items.size():
		var it2: Dictionary = _items[_item_i]
		var dr: Rect2 = Rect2(4, PANEL_H - 52, PANEL_W - 8, 48)
		UiKit.draw_hanji_panel(c, dr)
		UiKit.text(c, _f_bold, 12, dr.position + Vector2(8, 13), String(it2["title"]), C_MEOK, 0, false)
		var stat: String = "해원 %d · 퇴치 %d · 사연 조각 %d · 벽사 %d단" % [int(it2["haewon"]), int(it2["toechi"]), int(it2["pieces"]), int(it2["tier"])]
		UiKit.text(c, _f_tiny, 8, dr.position + Vector2(8, 25), stat, C_JEOK_DK, 0, false)
		var dl: PackedStringArray = it2["detail"]
		for li in dl.size():
			UiKit.text(c, _f_tiny, 8, dr.position + Vector2(8, 35 + li * 9), dl[li], C_HANJI5, 0, false)
	# 스크롤 표시
	if _content_h > PANEL_H + 1.0:
		var k2: float = _scroll / maxf(1.0, _content_h - PANEL_H)
		var bh: float = maxf(16.0, PANEL_H * PANEL_H / _content_h)
		c.draw_rect(Rect2(PANEL_W - 4, 6, 2, PANEL_H - 12), C_MEOK3)
		c.draw_rect(Rect2(PANEL_W - 4, roundf(6.0 + (PANEL_H - 12.0 - bh) * k2), 2, bh), C_HANJI4)


func _draw_focus(c: CanvasItem, r: Rect2, focus: bool) -> void:
	if focus:
		c.draw_rect(r.grow(1.0), C_JEOK, false, 1.0)
		UiKit.draw_corners(c, r.grow(3.0), C_HWANG)


func _draw_guide(c: CanvasItem, r: Rect2, it: Dictionary) -> void:
	UiKit.draw_hanji_panel(c, r)
	UiKit.text(c, _f_bold, 12, r.position + Vector2(8, 14), "굿 길잡이", C_JEOK_DK, 0, false)
	var y: float = r.position.y + 22.0
	var keys: Array[String] = ["l1", "l2", "l3"]
	for k in 3:
		var ls: PackedStringArray = it[keys[k]]
		var icon_c: Vector2 = Vector2(r.position.x + 16, y + 7)
		match k:
			0:  # 붉은 무구 ◆ + 귀신
				UiKit.draw_diamond(c, icon_c, 5.0, C_JEOK)
				c.draw_rect(Rect2(icon_c + Vector2(-1, -1), Vector2(2, 2)), C_HANJI_UI)
			1:  # 고리 닫기(길베 점선이 돌아 닫힌다)
				var ph: float = fmod(_t * 0.8, 1.0)
				var n: int = 12
				var shown: int = int(ph * float(n + 4))
				for s in mini(shown, n):
					var a0: float = TAU * float(s) / float(n)
					var a1: float = TAU * float(s + 1) / float(n)
					c.draw_line((icon_c + Vector2(cos(a0), sin(a0)) * 8.0).round(), (icon_c + Vector2(cos(a1), sin(a1)) * 8.0).round(), C_HANJI4, 1.0)
				c.draw_circle(icon_c, 2.5, C_HANJI5 if shown < n else C_HWANG)
				if shown >= n:
					c.draw_circle(icon_c, 9.5 + 2.0 * fmod(_t * 3.0, 1.0), Color(C_HWANG, 0.4), false, 1.0)
			2:  # 넋 → 공덕
				c.draw_rect(Rect2(icon_c - Vector2(4, 4), Vector2(8, 8)), C_HANJI_UI)
				c.draw_rect(Rect2(icon_c + Vector2(-1, -3), Vector2(1, 7)), C_JEOK)
		for li in ls.size():
			UiKit.text(c, _f_small, 10, Vector2(r.position.x + 32, y + 9 + li * 11), ls[li], C_MEOK, 0, false)
		y += 6.0 + 11.0 * float(maxi(2, ls.size()))


func _draw_button(c: CanvasItem, r: Rect2, it: Dictionary, focus: bool) -> void:
	var on: bool = bool(it.get("on", true))
	var big: bool = String(it.get("id", "")) == "start"
	var bg: Color = C_JEOK_DK if big else C_MEOK2
	if focus:
		bg = C_JEOK if big else C_MEOK3
	if not on:
		bg = C_MEOK1
	c.draw_rect(r.grow(1.0), C_MEOK)
	c.draw_rect(r, bg)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(C_HANJI, 0.25))
	_draw_focus(c, r, focus)
	var tc: Color = C_HANJI_UI if on else C_HANJI5
	if big:
		var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
		UiKit.text_outline(c, _f_brush, 22, Vector2(r.position.x + r.size.x * 0.5, r.position.y + 19), String(it["title"]), tc, 1, 2)
		UiKit.text(c, _f_tiny, 8, Vector2(r.position.x + r.size.x * 0.5, r.position.y + 33), String(it["sub"]), Color(C_HANJI2, 0.7 + 0.3 * pulse), 1)
	else:
		UiKit.text(c, _f_small, 10, Vector2(r.position.x + r.size.x * 0.5, r.position.y + 15), String(it["title"]), tc, 1)


func _draw_char_row(c: CanvasItem, r: Rect2, it: Dictionary, focus: bool) -> void:
	var unlocked: bool = bool(it["unlocked"])
	var ready: bool = bool(it["ready"])
	c.draw_rect(r.grow(1.0), C_MEOK)
	c.draw_rect(r, C_MEOK2 if not focus else C_MEOK3)
	if bool(it["chosen"]):
		c.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), C_JEOK)
	_draw_focus(c, r, focus)
	var tex: Texture2D = it["tex"]
	if tex != null:
		var mod: Color = Color.WHITE if unlocked else (Color(0.55, 0.45, 0.4) if ready else Color(0.1, 0.08, 0.14))
		var src: Rect2 = Rect2(0, 4, mini(64, tex.get_width()), mini(56, tex.get_height() - 4))
		c.draw_texture_rect_region(tex, Rect2(r.position + Vector2(2, 0), src.size), src, mod)
	var x: float = r.position.x + 66.0
	var name_c: Color = C_HANJI_UI if unlocked else (C_HWANG_HI if ready else C_HANJI4)
	var w: float = UiKit.text(c, _f_bold, 12, Vector2(x, r.position.y + 13), String(it["title"]), name_c, 0)
	UiKit.text(c, _f_tiny, 8, Vector2(x + w + 4, r.position.y + 12), String(it["hanja"]), C_HANJI4, 0)
	# 성향 막대(퇴치 적 / 해원 한지)
	var bx: float = x
	var by: float = r.position.y + 18.0
	UiKit.text(c, _f_tiny, 8, Vector2(bx, by + 7), "퇴치", C_HANJI4, 0)
	for k in 5:
		c.draw_rect(Rect2(bx + 20 + k * 6, by + 1, 4, 5), C_JEOK if k < int(it["toechi"]) else C_MEOK4)
	UiKit.text(c, _f_tiny, 8, Vector2(bx + 56, by + 7), "해원", C_HANJI4, 0)
	for k in 5:
		c.draw_rect(Rect2(bx + 76 + k * 6, by + 1, 4, 5), C_HANJI2 if k < int(it["haewon"]) else C_MEOK4)
	UiKit.text(c, _f_tiny, 8, Vector2(bx + 112, by + 7), String(it["weapons"]), C_HANJI3, 0)
	var st: PackedStringArray = it["status"]
	var sc: Color = C_JEOK_HI if bool(it["chosen"]) else (C_HWANG if ready else (C_NOK if unlocked else C_HANJI4))
	for li in st.size():
		UiKit.text(c, _f_tiny, 8, Vector2(x, r.position.y + 37 + li * 9), st[li], sc, 0)
	if bool(it["chosen"]):
		UiKit.draw_seal(c, Vector2(r.end.x - 20, r.position.y + 4), 16.0, "모", _f_tiny, 8)


func _draw_danjang_row(c: CanvasItem, r: Rect2, it: Dictionary, focus: bool) -> void:
	var maxed: bool = int(it["cost"]) < 0
	c.draw_rect(r.grow(1.0), C_MEOK)
	c.draw_rect(r, C_MEOK2 if not focus else C_MEOK3)
	_draw_focus(c, r, focus)
	# 한자 낙관(랭크가 있으면 붉게)
	var seal_r: Rect2 = Rect2(r.position + Vector2(4, 5), Vector2(26, 26))
	c.draw_rect(seal_r, C_JEOK if int(it["rank"]) > 0 else C_MEOK4)
	c.draw_rect(seal_r.grow(-2.0), C_HANJI_UI if int(it["rank"]) > 0 else C_HANJI5, false, 1.0)
	UiKit.text(c, _f_big, 15, seal_r.get_center() + Vector2(0, 6), String(it["hanja"]), C_HANJI_UI if int(it["rank"]) > 0 else C_HANJI3, 1, false)
	var x: float = r.position.x + 36.0
	UiKit.text(c, _f_bold, 12, Vector2(x, r.position.y + 13), String(it["title"]), C_HANJI_UI, 0)
	UiKit.text(c, _f_tiny, 8, Vector2(x, r.position.y + 24), String(it["effect"]), C_HANJI3, 0)
	# 랭크 구슬
	for k in int(it["max"]):
		var pc: Vector2 = Vector2(x + 4 + k * 9, r.position.y + 32)
		c.draw_circle(pc, 3.0, C_MEOK)
		c.draw_circle(pc, 2.0, C_HWANG if k < int(it["rank"]) else C_MEOK4)
	# 값
	var cur: StringName = it["cur"]
	var cc: Color = C_HANJI if cur == MetaRules.CUR_G else C_HWANG
	if maxed:
		UiKit.text(c, _f_small, 10, Vector2(r.end.x - 6, r.position.y + 14), "다 갖춤", C_NOK, 2)
	else:
		var afford: bool = bool(it["afford"])
		UiKit.text(c, _f_body, 12, Vector2(r.end.x - 6, r.position.y + 14), String(it["cost_txt"]), cc if afford else C_HANJI5, 2)
		UiKit.text(c, _f_tiny, 8, Vector2(r.end.x - 6, r.position.y + 25), MetaRules.currency_name(cur) + (" 봉헌" if cur == MetaRules.CUR_G else " 마련"), C_HANJI4 if afford else C_JEOK_DK, 2)
	if focus and not maxed:
		UiKit.text(c, _f_tiny, 8, Vector2(r.end.x - 6, r.position.y + 34), "길게 눌러", Color(C_HANJI3, 0.6 + 0.4 * sin(_t * 5.0)), 2)


func _draw_weapon_row(c: CanvasItem, r: Rect2, it: Dictionary, focus: bool) -> void:
	var st: String = String(it["state"])
	c.draw_rect(r.grow(1.0), C_MEOK)
	c.draw_rect(r, C_MEOK2 if not focus else C_MEOK3)
	_draw_focus(c, r, focus)
	var ic: Texture2D = it["icon"]
	var mod: Color = Color.WHITE if st == "owned" or st == "buyable" else Color(0.18, 0.15, 0.25)
	if ic != null:
		c.draw_texture(ic, r.position + Vector2(6, 8), mod)
	UiKit.draw_kind_mark(c, r.position + Vector2(28, 10), 2.5, bool(it["white"]))
	UiKit.text(c, _f_bold, 12, r.position + Vector2(34, 14), String(it["title"]), C_HANJI_UI if st != "undiscovered" else C_HANJI4, 0)
	for k in int(it["tier"]):
		c.draw_rect(Rect2(r.position.x + 34 + k * 5, r.position.y + 18, 3, 3), C_HWANG_DK)
	UiKit.text(c, _f_tiny, 8, r.position + Vector2(34, 29), String(it["note"]), C_NOK if st == "owned" else C_HANJI3, 0)
	if st == "buyable":
		var cur: StringName = it["cur"]
		var afford: bool = bool(it["afford"])
		UiKit.text(c, _f_body, 12, Vector2(r.end.x - 6, r.position.y + 14), String(it["cost_txt"]), (C_HANJI if cur == MetaRules.CUR_G else C_HWANG) if afford else C_HANJI5, 2)
		UiKit.text(c, _f_tiny, 8, Vector2(r.end.x - 6, r.position.y + 25), MetaRules.currency_name(cur) + (" 봉헌" if cur == MetaRules.CUR_G else " 제작"), C_HANJI4 if afford else C_JEOK_DK, 2)
	elif st == "owned":
		UiKit.draw_seal(c, Vector2(r.end.x - 20, r.position.y + 8), 14.0, "갖", _f_tiny, 8)


func _draw_uiroe_card(c: CanvasItem, r: Rect2, it: Dictionary, focus: bool) -> void:
	var acc: bool = bool(it["accepted"])
	UiKit.draw_hanji_panel(c, r)
	if acc:
		c.draw_rect(r.grow(-2.0), Color(C_JEOK, 0.12))
	_draw_focus(c, r, focus)
	UiKit.text(c, _f_bold, 12, r.position + Vector2(8, 14), String(it["title"]), C_MEOK, 0, false)
	var mods: PackedStringArray = it["mods"]
	for li in mini(3, mods.size()):
		UiKit.text(c, _f_tiny, 8, r.position + Vector2(10, 26 + li * 10), mods[li], C_HANJI5, 0, false)
	UiKit.text(c, _f_tiny, 8, r.position + Vector2(10, r.size.y - 7), String(it["reward"]), C_JEOK_DK, 0, false)
	if acc:
		UiKit.draw_seal(c, Vector2(r.end.x - 26, r.position.y + 6), 20.0, "받", _f_small, 10)
		UiKit.text(c, _f_tiny, 8, Vector2(r.end.x - 30, r.position.y + 30), "받은 사연", C_JEOK, 2, false)
	elif focus:
		UiKit.text(c, _f_tiny, 8, Vector2(r.end.x - 8, r.position.y + 14), "받기", C_JEOK, 2, false)


func _draw_species(c: CanvasItem, r: Rect2, it: Dictionary, focus: bool) -> void:
	var seen: bool = bool(it["seen"])
	c.draw_rect(r.grow(1.0), C_MEOK)
	c.draw_rect(r, C_MEOK2 if not focus else C_MEOK3)
	_draw_focus(c, r, focus)
	var tex: Texture2D = it["tex"]
	if tex != null:
		var tw: float = float(mini(tex.get_width(), int(r.size.x) - 4))
		var th: float = float(mini(tex.get_height(), 44))
		var src: Rect2 = Rect2((float(tex.get_width()) - tw) * 0.5, float(tex.get_height()) - th, tw, th)
		var dst: Rect2 = Rect2(Vector2(roundf(r.position.x + (r.size.x - tw) * 0.5), r.position.y + 46.0 - th), Vector2(tw, th))
		c.draw_texture_rect_region(tex, dst, src, Color.WHITE if seen else Color(0.16, 0.13, 0.22))
	UiKit.text(c, _f_tiny, 8, Vector2(r.position.x + r.size.x * 0.5, r.position.y + 54), String(it["title"]).left(6), C_HANJI if seen else C_HANJI5, 1)
	# 사연 조각 점
	for k in 3:
		c.draw_rect(Rect2(r.position.x + r.size.x * 0.5 - 8 + k * 6, r.position.y + 57, 4, 3), C_HANJI2 if k < int(it["pieces"]) else C_MEOK4)
	if int(it["tier"]) > 0:
		UiKit.draw_diamond(c, r.position + Vector2(7, 7), 3.0 + float(int(it["tier"])), C_JEOK)


func _fmt(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var cnt: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
