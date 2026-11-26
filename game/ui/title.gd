extends Control
## 타이틀 + 무당 고르기. 소유: ui. design/11 §4.3·§4.6.
## 키아트(ui/art/key_art_gutpan.png, art/concept 사본) 위에 붓 로고, 메뉴(굿판 열기·길잡이·신당·넋기록·설정·나가기).
## 무당 고르기: v1 5명(만신·박수·단골·명두·심방) — 초상, 2배 idle, 계보·소개·시작 무구(◆/○)·성향·난이도.
## 신호(main.gd 계약): start_requested(char_id), lobby_requested, tutorial_requested(연습 굿판, design/17 §7.3).
## 첫 실행(design/17 §3.1): flags.intro_seen 이 없으면 컨셉 인트로 → flags.tutorial_offered 가 없으면 권유 창.
## '길잡이' 하위 메뉴: 인트로 다시 보기 · 연습 굿판 · 굿 안내서 · 뒤로. practice_done 전에는 '길잡이' 옆 황 점.
## 디버그: --intro-test(인트로 자동 넘김 → 권유 1.5초 → 종료; --intro-choice=practice|play 면 그 답으로 이어 감), --guidebook-test=<1..8|all>.

signal start_requested(char_id: StringName)
signal lobby_requested
signal tutorial_requested

const KEY_ART: String = "res://ui/art/key_art_gutpan.png"
const MENU: Array[String] = ["굿판 열기", "길잡이", "신당", "넋기록", "설정", "나가기"]
const GUIDE_MENU: Array[String] = ["인트로 다시 보기", "연습 굿판", "굿 안내서", "뒤로"]
const MODE_MENU: int = 0
const MODE_CHARS: int = 1
const MODE_GUIDE: int = 2

var _mode: int = MODE_MENU
var _focus: int = 0
var _t: float = 0.0
var _mode_t: float = 0.0
var _chars: Array[Dictionary] = []
var _sel: int = 0
var _art: Texture2D
var _paper: Texture2D
var _vignette: Texture2D
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_tiny: Font
var _f_big: Font
var _f_brush: Font
var _settings: SettingsPanel
var _records: Control
var _intro: IntroCards
var _offer: TutorialOffer
var _guidebook: Guidebook
var _intro_test: bool = false
var _intro_replay: bool = false
var _quit_t: float = -1.0          # 디버그 테스트 끝난 뒤 종료 대기(실시간)
# 떠도는 넋(장식 입자, 연출 난수)
var _wisp: PackedVector3Array = PackedVector3Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.setup_fonts()
	UiSettings.apply()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_big = UiKit.big()
	_f_brush = UiKit.brush()
	_art = SpriteLib.tex(KEY_ART) if ResourceLoader.exists(KEY_ART) else null
	_paper = UiKit.skin("tile_hanji_paper.png")
	_vignette = UiKit.skin("vignette.png")
	_rng.seed = 11
	for i in 18:
		_wisp.append(Vector3(_rng.randf_range(0, 640), _rng.randf_range(0, 360), _rng.randf_range(0, TAU)))
	_build_chars()
	var last: String = String(Save.get_value("ui.last_char", "char_mansin"))
	for i in _chars.size():
		if String(_chars[i]["id"]) == last:
			_sel = i
	_settings = SettingsPanel.new()
	_settings.name = "Settings"
	add_child(_settings)
	_records = (load("res://ui/records_panel.gd") as Script).new() as Control
	_records.name = "Records"
	add_child(_records)
	_guidebook = (load("res://ui/guidebook.tscn") as PackedScene).instantiate() as Guidebook
	_guidebook.name = "Guidebook"
	add_child(_guidebook)
	_guidebook.closed.connect(_on_guidebook_closed)
	_intro = IntroCards.new()
	_intro.name = "Intro"
	add_child(_intro)
	_intro.finished.connect(_on_intro_finished)
	_offer = TutorialOffer.new()
	_offer.name = "Offer"
	add_child(_offer)
	_offer.chosen.connect(_on_offer_chosen)
	# 첫 실행: 컨셉 인트로 → 권유 창(design/17 §3.1). 디버그 테스트는 플래그와 상관없이.
	# 인트로 검사는 한 프로세스에 한 번(연습 굿판 → 타이틀로 돌아와도 다시 돌지 않게)
	_intro_test = DebugTools.args.has("intro-test") and not Engine.has_meta(&"intro_test_used")
	if _intro_test:
		Engine.set_meta(&"intro_test_used", true)
	var gb_test: String = DebugTools.arg("guidebook-test")
	if _intro_test:
		_intro.open.call_deferred(true)
	elif gb_test != "":
		if gb_test == "all":
			_guidebook.open_test_all.call_deferred()
		else:
			_guidebook.open.call_deferred(clampi(int(gb_test) - 1, 0, 7))
	elif Game.autotest or DebugTools.arg("ui-shot") != "":
		pass
	elif not Save.flag("intro_seen"):
		_intro.open.call_deferred(false)
	elif not Save.flag("tutorial_offered"):
		_offer.open.call_deferred()
	if OS.is_debug_build():
		print("[title] open intro_seen=%s offered=%s practice_done=%s first_run_pending=%s" % [
			str(Save.flag("intro_seen")), str(Save.flag("tutorial_offered")), str(Save.flag("practice_done")),
			str(Save.first_run_pending())])
	# 캡처용: --ui-shot=chars|settings|records|menu|guide
	match DebugTools.arg("ui-shot"):
		"chars":
			_set_mode(MODE_CHARS)
		"guide":
			_set_mode(MODE_GUIDE)
		"settings":
			_settings.open.call_deferred()
		"records":
			_records.call_deferred("open")


func _build_chars() -> void:
	for id: Variant in Data.character_ids():
		var def: Dictionary = Data.character(String(id))
		if not Data.is_v1(def):
			continue
		var d: Dictionary = {"id": String(id)}
		d["name"] = UiKit.char_name(String(id))
		d["hanja"] = UiKit.char_hanja(String(id))
		d["lineage"] = String(def.get("lineage", ""))
		d["line"] = UiKit.wrap(_f_body, UiKit.SZ_BODY, UiCopy.char_line(String(id)), 236.0, 2)
		var tb: Variant = def.get("tendency_bar", {})
		d["toechi"] = int((tb as Dictionary).get("toechi", 3)) if tb is Dictionary else 3
		d["haewon"] = int((tb as Dictionary).get("haewon", 3)) if tb is Dictionary else 3
		d["diff"] = int(def.get("difficulty", 2))
		var ws: Array[Dictionary] = []
		var sw: Variant = def.get("start_weapons", [])
		if sw is Array:
			for e: Variant in sw:
				if e is Dictionary:
					var wid: String = String((e as Dictionary).get("wpn", ""))
					ws.append({"id": wid, "at": int((e as Dictionary).get("at_s", 0)), "name": UiKit.weapon_name(wid),
						"white": UiKit.weapon_color(wid) == "white", "icon": UiKit.weapon_icon(wid, true)})
		d["weapons"] = ws
		var fr: Array[Texture2D] = SpriteLib.anim_frames_any(String(id), "idle", "south")
		if fr.is_empty():
			fr = [SpriteLib.dir_tex(String(id), "south", 48)]
		d["frames"] = fr
		_chars.append(d)


func _process(delta: float) -> void:
	_t += delta
	_mode_t += delta
	if _quit_t > 0.0:
		_quit_t -= delta
		if _quit_t <= 0.0:
			Game.quit_game(0)
	for i in _wisp.size():
		var w: Vector3 = _wisp[i]
		w.y -= delta * (6.0 + float(i % 4) * 2.0)
		w.x += sin(_t * 0.7 + w.z) * delta * 4.0
		if w.y < -6.0:
			w.y = size.y + 6.0
			w.x = _rng.randf_range(0, size.x)
		_wisp[i] = w
	queue_redraw()


func _set_mode(m: int) -> void:
	# 메뉴 ↔ 길잡이 하위 메뉴는 같은 화면(로고를 다시 페이드하지 않는다)
	if not ((m == MODE_GUIDE and _mode == MODE_MENU) or (m == MODE_MENU and _mode == MODE_GUIDE)):
		_mode_t = 0.0
	_mode = m
	_focus = 0


func _activate_menu(i: int) -> void:
	UiSettings.ui_sfx(&"sfx_ui_confirm")
	match i:
		0:
			# 첫 실행 = 초굿(만신) 직행, 이후 = 신당 경유(무당 해금·의뢰는 신당에서). (core 통합, meta 요청)
			if Save.first_run_pending():
				Save.set_value("ui.last_char", "char_mansin")
				UiSettings.persist()
				start_requested.emit(&"char_mansin")
			else:
				lobby_requested.emit()
		1:
			_set_mode(MODE_GUIDE)
		2:
			lobby_requested.emit()
		3:
			_records.call("open")
		4:
			_settings.open()
		5:
			Game.quit_game(0)


## '길잡이' 하위 메뉴
func _activate_guide(i: int) -> void:
	match i:
		0:
			UiSettings.ui_sfx(&"sfx_ui_confirm")
			_intro_replay = true
			_intro.open(false)
		1:
			UiSettings.ui_sfx(&"sfx_ui_confirm")
			tutorial_requested.emit()
		2:
			_guidebook.open(0)
		3:
			UiSettings.ui_sfx(&"sfx_ui_back")
			_set_mode(MODE_MENU)
			_focus = 1


func _overlay_open() -> bool:
	return _settings.visible or _records.visible or _intro.visible or _offer.visible or _guidebook.visible


## 플래그 쓰기(디버그 테스트 중에는 --ui-save=1 일 때만)
func _set_flag(id: String) -> void:
	if (_intro_test or Game.autotest) and DebugTools.arg("ui-save") != "1":
		return
	Save.set_flag(id)


func _on_intro_finished(_skipped: bool) -> void:
	_set_flag("intro_seen")
	if _intro_test:
		print("[intro] offer")
		_offer.open(1.5)
		return
	if _intro_replay:
		_intro_replay = false
		_set_mode(MODE_GUIDE)
		return
	if not Save.flag("tutorial_offered"):
		_offer.open()
	else:
		_mode_t = 0.0


func _on_offer_chosen(choice: StringName) -> void:
	if _intro_test:
		print("[intro] done skipped=false")
		# 첫 실행 흐름 검사(--intro-choice=practice|play): 권유 창 답을 흉내 내 그대로 이어 간다
		var ic: String = DebugTools.arg("intro-choice")
		if ic != "practice" and ic != "play":
			_quit_t = 0.5
			return
		choice = StringName(ic)
		print("[intro] choice=%s" % ic)
	_set_flag("tutorial_offered")
	match choice:
		&"practice":
			tutorial_requested.emit()
		&"play":
			_activate_menu(0)
		_:
			_set_mode(MODE_MENU)


func _on_guidebook_closed() -> void:
	if DebugTools.args.has("guidebook-test"):
		print("[guidebook] done")
		_quit_t = 0.5
	queue_redraw()


func _start() -> void:
	var id: String = String(_chars[_sel]["id"])
	Save.set_value("ui.last_char", id)
	UiSettings.persist()
	UiSettings.ui_sfx(&"sfx_ui_confirm")
	start_requested.emit(StringName(id))


func _unhandled_input(event: InputEvent) -> void:
	if _overlay_open():
		return
	var handled: bool = true
	if _mode == MODE_GUIDE:
		if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
			_focus = (_focus - 1 + GUIDE_MENU.size()) % GUIDE_MENU.size()
		elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
			_focus = (_focus + 1) % GUIDE_MENU.size()
		elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
			_activate_guide(_focus)
		elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
			_activate_guide(GUIDE_MENU.size() - 1)
		else:
			handled = false
	elif _mode == MODE_MENU:
		if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
			_focus = (_focus - 1 + MENU.size()) % MENU.size()
		elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
			_focus = (_focus + 1) % MENU.size()
		elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
			_activate_menu(_focus)
		else:
			handled = false
	else:
		if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
			_sel = (_sel - 1 + _chars.size()) % _chars.size()
		elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
			_sel = (_sel + 1) % _chars.size()
		elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
			_start()
		elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
			_set_mode(MODE_MENU)
		else:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _menu_rect(i: int) -> Rect2:
	return Rect2(roundf(size.x * 0.5) - 60, 230 + i * 17, 120, 16)


func _portrait_rect(i: int) -> Rect2:
	var n: int = _chars.size()
	var x0: float = roundf(size.x * 0.5 - (n * 60 - 4) * 0.5)
	return Rect2(x0 + i * 60, 52, 56, 60)


func _gui_input(event: InputEvent) -> void:
	if _overlay_open():
		return
	var mp: Vector2 = Vector2.ZERO
	var click: bool = false
	if event is InputEventMouseMotion:
		mp = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		mp = (event as InputEventMouseButton).position
		click = true
	else:
		return
	if _mode == MODE_GUIDE:
		for i in GUIDE_MENU.size():
			if _menu_rect(i).has_point(mp):
				_focus = i
				if click:
					_activate_guide(i)
	elif _mode == MODE_MENU:
		for i in MENU.size():
			if _menu_rect(i).has_point(mp):
				_focus = i
				if click:
					_activate_menu(i)
	else:
		for i in _chars.size():
			if _portrait_rect(i).has_point(mp) and click:
				if _sel == i:
					_start()
				_sel = i
		if click and _start_rect().has_point(mp):
			_start()


func _start_rect() -> Rect2:
	var cx: float = roundf(size.x * 0.5)
	return Rect2(cx + 96, size.y - 40, 110, 22)


# ─── 그리기 ─────────────────────────────────────────────────────────────

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = roundf(w * 0.5)
	draw_rect(Rect2(0, 0, w, h), UiKit.MEOK)
	# 키아트(느린 표류 ±3px, 촛불 깜박 0.5Hz)
	if _art != null:
		var asz: Vector2 = _art.get_size()
		var drift: Vector2 = Vector2(roundf(sin(_t * 0.15) * 3.0), roundf(cos(_t * 0.11) * 2.0))
		var flick: float = 0.88 + 0.06 * sin(_t * TAU * 0.5) + 0.03 * sin(_t * 9.0)
		var dim: float = 1.0 if _mode != MODE_CHARS else 0.45
		var pos: Vector2 = Vector2(roundf((w - asz.x) * 0.5), roundf((h - asz.y) * 0.5)) + drift
		draw_texture(_art, pos, Color(flick * dim, flick * dim * 0.97, flick * dim * 0.95, 1.0))
	# 위쪽 먹 그라데이션(로고 가독)
	if _mode != MODE_CHARS:
		for i in 10:
			draw_rect(Rect2(0, float(i) * 10.0, w, 10), Color(UiKit.MEOK, 0.6 - 0.06 * float(i)))
	# 아래쪽 먹 그라데이션(메뉴 가독)
	for i in 12:
		var y0: float = h * 0.42 + float(i) * (h * 0.58 / 12.0)
		draw_rect(Rect2(0, roundf(y0), w, ceilf(h * 0.58 / 12.0) + 1.0), Color(UiKit.MEOK, 0.06 * float(i)))
	if _vignette != null:
		draw_texture_rect(_vignette, Rect2(0, 0, w, h), false, Color(1, 1, 1, 0.7))
	# 떠도는 넋(한지빛 작은 점)
	for wv: Vector3 in _wisp:
		var a: float = 0.25 + 0.2 * sin(_t * 1.3 + wv.z)
		draw_rect(Rect2(Vector2(wv.x, wv.y).floor(), Vector2(1, 2)), Color(UiKit.HANJI_UI, a))
	if _mode != MODE_CHARS:
		_draw_menu(cx, h)
	else:
		_draw_chars(cx, w, h)


func _draw_menu(cx: float, h: float) -> void:
	var a: float = clampf(_mode_t / 0.4, 0.0, 1.0)
	# 로고(붓): 국문 위, 영문 아래 + 낙관
	var ly: float = 58.0
	var lw: float = UiKit.text_outline(self, _f_brush, 52, Vector2(cx, ly), "넋길 : 해원굿", Color(UiKit.HANJI_UI, a), 1, 3)
	var seal: Rect2 = Rect2(cx + lw * 0.5 + 4.0, ly - 34.0, 16, 16)
	draw_rect(seal, Color(UiKit.JEOK, a))
	draw_rect(seal.grow(-1.0), Color(UiKit.HANJI_UI, a), false, 1.0)
	draw_string(_f_small, seal.position + Vector2(3, 12), "巫", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.HANJI_UI, a))
	UiKit.draw_dancheong(self, Rect2(cx - 120, ly + 8.0, 240, 3))
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx, ly + 23.0), "SOULPATH : Untie the Han", Color(UiKit.HWANG_HI, a), 1)
	# 메뉴(길잡이 하위 메뉴는 같은 자리 교체)
	var items: Array[String] = GUIDE_MENU if _mode == MODE_GUIDE else MENU
	var mp: Rect2 = Rect2(cx - 70, 224, 140, items.size() * 17 + 10)
	draw_rect(mp, Color(UiKit.MEOK, 0.55 * a))
	if _mode == MODE_GUIDE:
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx, 219), "길잡이", Color(UiKit.HWANG_HI, a), 1)
	var news: bool = _mode == MODE_MENU and not Save.flag("practice_done")
	for i in items.size():
		var r: Rect2 = _menu_rect(i)
		var foc: bool = i == _focus
		var col: Color = UiKit.HWANG_HI if foc else UiKit.HANJI
		var tw: float = UiKit.text(self, _f_body, UiKit.SZ_BODY, Vector2(r.get_center().x, r.position.y + 12), items[i], Color(col, a), 1)
		if news and i == 1:
			# 새 소식 표지: 연습 굿판을 아직 마치지 않았다
			var dk: float = 0.8 + 0.2 * sin(_t * 4.0)
			draw_rect(Rect2(roundf(r.get_center().x + tw * 0.5 + 4.0), r.position.y + 4, 3, 3), Color(UiKit.HWANG, a * dk))
		if foc:
			var bob: float = roundf(sin(_t * 6.0))
			UiKit.draw_diamond(self, Vector2(r.get_center().x - tw * 0.5 - 9.0 + bob, r.position.y + 8), 3.0, Color(UiKit.JEOK, a))
			draw_rect(Rect2(r.get_center().x - tw * 0.5, r.position.y + 14, tw, 1), Color(UiKit.HWANG, a))
	UiKit.text(self, _f_tiny, UiKit.SZ_TINY, Vector2(size.x - 6, h - 5), "v0.9 거의-완성 빌드", Color(UiKit.HANJI_4, a), 2)
	if not _overlay_open():
		var foot: String = "↑↓ 고르기   Enter 확인   Esc 뒤로" if _mode == MODE_GUIDE else "↑↓ 고르기   Enter 확인"
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx, h - 8), foot, Color(UiKit.HANJI_3, a), 1)


func _draw_chars(cx: float, w: float, h: float) -> void:
	var a: float = clampf(_mode_t / 0.25, 0.0, 1.0)
	UiKit.text_outline(self, _f_brush, 40, Vector2(cx, 38), "무당 고르기", Color(UiKit.HANJI_UI, a), 1, 2)
	# 초상 줄
	for i in _chars.size():
		var r: Rect2 = _portrait_rect(i)
		var sel: bool = i == _sel
		UiKit.draw_meok_panel(self, r, 0.85 * a, sel, UiKit.HWANG if sel else UiKit.HANJI_5)
		var fr: Array = _chars[i]["frames"]
		var tex: Texture2D = fr[0] if not fr.is_empty() else null
		if tex != null:
			var ts: Vector2 = tex.get_size()
			draw_texture(tex, (r.position + Vector2((r.size.x - ts.x) * 0.5, r.size.y - ts.y - 1.0)).round(), Color(1, 1, 1, a if sel else 0.6 * a))
		if sel:
			draw_rect(r.grow(2.0), Color(UiKit.HWANG, a), false, 1.0)
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.get_center().x, r.end.y + 11), String(_chars[i]["name"]), Color(UiKit.HWANG_HI if sel else UiKit.HANJI_2, a), 1)
	var c: Dictionary = _chars[_sel]
	# 큰 미리보기(2배 idle)
	var pv: Rect2 = Rect2(cx - 210, 136, 140, 150)
	UiKit.draw_hanji_panel(self, pv, _paper)
	var frames: Array = c["frames"]
	if not frames.is_empty():
		var fi: int = int(_t * 6.0) % frames.size()
		var tx: Texture2D = frames[fi]
		var s2: Vector2 = tx.get_size() * 2.0
		# 발밑 그림자
		draw_rect(Rect2(pv.get_center().x - 18, pv.end.y - 16, 36, 4), Color(UiKit.HANJI_4, 0.6))
		draw_texture_rect(tx, Rect2((Vector2(pv.get_center().x - s2.x * 0.5, pv.end.y - 12 - s2.y)).round(), s2), false)
	# 정보 패널
	var ip: Rect2 = Rect2(cx - 60, 136, 270, 150)
	UiKit.draw_hanji_panel(self, ip, _paper)
	var x0: float = ip.position.x + 12
	var y: float = ip.position.y + 22
	var ink: Color = UiKit.INK
	draw_string(_f_bold, Vector2(x0, y), String(c["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
	var nw: float = _f_bold.get_string_size(String(c["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
	var sub: String = String(c["lineage"])
	if String(c["hanja"]) != "":
		sub = "%s · %s" % [String(c["hanja"]), sub]
	draw_string(_f_small, Vector2(x0 + nw + 8, y), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HANJI_5)
	y += 6
	draw_rect(Rect2(x0, y, ip.size.x - 24, 1), UiKit.HANJI_4)
	y += 15
	for ln: String in (c["line"] as PackedStringArray):
		draw_string(_f_body, Vector2(x0, y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
		y += 14
	y += 6
	draw_string(_f_small, Vector2(x0, y), "시작 무구", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HANJI_5)
	var wx: float = x0 + 52
	for wd: Dictionary in (c["weapons"] as Array):
		UiKit.draw_kind_mark(self, Vector2(wx + 3, y - 4), 2.0, bool(wd["white"]))
		var label: String = String(wd["name"])
		if int(wd["at"]) > 0:
			label += " (%s)" % K.fmt_time(float(wd["at"]))
		draw_string(_f_small, Vector2(wx + 9, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.JEOK_DK if not bool(wd["white"]) else ink)
		wx += _f_small.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x + 18.0
	y += 18
	# 성향(퇴치 · 해원 5칸) — 도덕 표현 없이 경향만
	draw_string(_f_small, Vector2(x0, y), "퇴치", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.JEOK_DK)
	for k in 5:
		draw_rect(Rect2(x0 + 26 + k * 9, y - 7, 7, 6), UiKit.JEOK if k < int(c["toechi"]) else UiKit.HANJI_3)
	draw_string(_f_small, Vector2(x0 + 84, y), "해원", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, ink)
	for k in 5:
		draw_rect(Rect2(x0 + 110 + k * 9, y - 7, 7, 6), UiKit.MEOK_3 if k < int(c["haewon"]) else UiKit.HANJI_3)
	y += 16
	draw_string(_f_small, Vector2(x0, y), "어려움", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HANJI_5)
	for k in 5:
		UiKit.draw_diamond(self, Vector2(x0 + 40 + k * 10, y - 4), 3.0, UiKit.HWANG_DK if k < int(c["diff"]) else UiKit.HANJI_3)
	# 굿의 법도 두 줄(처음 하는 사람용, 모든 무당 공통)
	y = ip.end.y - 19.0
	draw_rect(Rect2(x0, y - 11.0, ip.size.x - 24, 1), UiKit.HANJI_3)
	UiKit.draw_kind_mark(self, Vector2(x0 + 3, y - 4), 2.0, false)
	draw_string(_f_small, Vector2(x0 + 9, y), "붉은 무구 = 깨서 퇴치", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.JEOK_DK)
	UiKit.draw_kind_mark(self, Vector2(x0 + 124, y - 4), 2.0, true)
	draw_string(_f_small, Vector2(x0 + 130, y), "흰 무구 = 풀어서 해원", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, ink)
	draw_string(_f_small, Vector2(x0, y + 11.0), "흰 길로 고리를 닫으면 안이 한꺼번에 풀린다", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HANJI_5)
	# 출정 버튼
	var sr: Rect2 = _start_rect()
	var pulse: bool = fposmod(_t, 1.0) < 0.5
	UiKit.draw_meok_panel(self, sr, 0.95, true, UiKit.HWANG if pulse else UiKit.HWANG_DK)
	UiKit.text(self, _f_bold, UiKit.SZ_BODY, Vector2(sr.get_center().x, sr.position.y + 15), "출정 ▶", UiKit.HWANG_HI, 1)
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx - 60, h - 24), "← → 무당   Enter 출정   Esc 뒤로", UiKit.HANJI_3, 1)
