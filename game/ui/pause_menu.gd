extends Control
## 일시정지(쉼). 소유: ui. design/11 §9.1. Game.push_pause(&"menu") 사용(SceneTree.paused 쓰지 않음).
## 머리줄: 쉼 시각 · 거리 · 굿판 / 숫자줄: 해원·퇴치·영가·신명·길닦음·Lv(HUD 에서 숨긴 숫자를 여기서 항상 보여 준다)
## 왼쪽 메뉴: 이어가기 · 굿 안내서 · 설정 · 굿판 거두기(두 번 눌러 확인) / 오른쪽: 무구 빌드 + '굿의 법도' 요약(길잡이)
## 연습 굿판(Game.tutorial_mode, design/17 §3.3): 이어가기 · 굿 안내서 · 설정 · 이 단계 건너뛰기 · 연습 그만두기(두 번 눌러 확인)
##   건너뛰기 → Events.tutorial_skip_step_requested / 그만두기 → Events.tutorial_exit_requested(&"title")
## run.gd 가 pause 입력에서 toggle() 을 부른다. 설정·안내서가 열려 있으면 toggle() 은 그것만 닫는다.

signal quit_to_title

const ITEMS_RUN: Array[String] = ["이어가기", "굿 안내서", "설정", "굿판 거두기"]
const ITEMS_TUT: Array[String] = ["이어가기", "굿 안내서", "설정", "이 단계 건너뛰기", "연습 그만두기"]
const ROW: float = 19.0

var _focus: int = 0
var _t: float = 0.0
var _quit_armed: float = 0.0
var _settings: SettingsPanel = null
var _guidebook: Guidebook = null
var _items: Array[String] = ITEMS_RUN
var _head: String = ""
var _stats: String = ""
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_tiny: Font
var _f_brush: Font
var _paper: Texture2D
var _rules: Array[PackedStringArray] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	UiKit.setup_fonts()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")
	_settings = SettingsPanel.new()
	_settings.name = "Settings"
	add_child(_settings)
	_settings.closed.connect(func() -> void: queue_redraw())
	_guidebook = (load("res://ui/guidebook.tscn") as PackedScene).instantiate() as Guidebook
	_guidebook.name = "Guidebook"
	add_child(_guidebook)
	_guidebook.closed.connect(func() -> void: queue_redraw())
	if DebugTools.arg("pause-test") != "":
		_pause_test(float(DebugTools.arg("pause-test")))
	var rules: Array[String] = [
		"◆ 붉은 무구는 한을 깨 퇴치한다 — 원혼 구슬이 온전히 모인다",
		"○ 흰 테두리(풀릴 기색)는 흰 무구로 풀어 해원한다 — 영가가 되어 따라온다",
		"걸어온 흰 길을 다시 밟아 고리를 닫으면 안의 넋이 한꺼번에 풀린다(길닦음)",
		"퇴치만 하면 살이 쌓여 원귀로 돌아온다 — 기운 바의 매듭을 보라",
	]
	for s: String in rules:
		_rules.append(UiKit.wrap(_f_small, UiKit.SZ_SMALL, s, 404.0, 2))


## 캡처·검사용(--pause-test=<게임 초>): 그 시각에 쉼 메뉴 → 1.5초 뒤 굿 안내서(3쪽) → 1.5초 뒤 닫고 이어가기.
func _pause_test(at: float) -> void:
	while Game.time_sec() < at or not Game.run_active:
		await get_tree().process_frame
	toggle()
	print("[pause] open tutorial=%s items=%s" % [str(Game.tutorial_mode), ", ".join(_items)])
	await get_tree().create_timer(1.5, true).timeout
	_guidebook.open(2)
	print("[pause] guidebook")
	await get_tree().create_timer(1.5, true).timeout
	_guidebook.close()
	toggle()
	print("[pause] done")


func toggle() -> void:
	if visible and _settings.visible:
		_settings.close()
		return
	if visible and _guidebook.visible:
		_guidebook.close()
		return
	visible = not visible
	if visible:
		Game.push_pause(&"menu")
		mouse_filter = Control.MOUSE_FILTER_STOP
		_items = ITEMS_TUT if Game.tutorial_mode else ITEMS_RUN
		_focus = 0
		_t = 0.0
		_quit_armed = 0.0
		_build_text()
		Audio.play_sfx(&"sfx_ui_pause", &"UI")
	else:
		Game.pop_pause(&"menu")
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _build_text() -> void:
	var g: Dictionary = UiKit.geori_def(Beat.geori_id)
	var gname: String = String(g.get("name_ko", ""))
	var stage: String = "인왕산 선바위 굿당"
	_head = "쉼  %s  ·  %s  ·  %s" % [K.fmt_time(Game.time_sec()), gname, stage]
	if Game.tutorial_mode:
		_head = "쉼  ·  연습 굿판  ·  %s" % gname
	var yg: int = 0
	var cap: int = 24
	var r: Run = Game.run_root as Run
	if r != null and r.yeongga != null:
		yg = r.yeongga.count
		cap = r.yeongga.capacity()
	var rings: int = 0
	var hud: Node = r.hud if r != null else null
	if hud != null and hud.get("ledger") != null:
		rings = int((hud.get("ledger") as Node).get("rings"))
	_stats = "○ 해원 %d   ◆ 퇴치 %d   영가 %d/%d   신명 %d%%   길닦음 %d   Lv %d" % [
		Game.kills_haewon, Game.kills_toechi, yg, cap, int(Game.sinmyeong * 100.0), rings, Game.level]
	if Game.tutorial_mode:
		_stats = "연습 굿판 — 기록은 남지 않습니다"   # 연습은 RunLedger 에 남기지 않아 숫자가 늘 0 으로 보인다


func _activate(i: int) -> void:
	match i:
		0:
			toggle()
		1:
			_guidebook.open(0)
		2:
			_settings.open()
		3:
			if Game.tutorial_mode:
				# 이 단계 건너뛰기(쉼 메뉴는 닫힌다)
				toggle()
				if Events.has_signal(&"tutorial_skip_step_requested"):
					Events.emit_signal(&"tutorial_skip_step_requested")
			elif _quit_armed > 0.0:
				_quit()
			else:
				_quit_armed = 2.5
		4:
			if _quit_armed > 0.0:
				toggle()
				if Events.has_signal(&"tutorial_exit_requested"):
					Events.emit_signal(&"tutorial_exit_requested", &"title")
			else:
				_quit_armed = 2.5
	queue_redraw()


func _quit_index() -> int:
	return _items.size() - 1


func _quit() -> void:
	toggle()
	if Game.run_active:
		Game.end_run(false, {"ending": "abandon"})
	quit_to_title.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	if _t < 0.3:
		_t += delta
		queue_redraw()
	if _quit_armed > 0.0:
		_quit_armed -= delta
		if _quit_armed <= 0.0:
			queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _settings.visible or _guidebook.visible:
		return
	var handled: bool = true
	if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		_focus = (_focus - 1 + _items.size()) % _items.size()
	elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		_focus = (_focus + 1) % _items.size()
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		_activate(_focus)
	elif event.is_action_pressed(&"cancel"):
		toggle()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
		queue_redraw()


func _item_rect(i: int) -> Rect2:
	var cx: float = roundf(size.x * 0.5)
	return Rect2(cx - 214, 82 + i * ROW, 118, 18)


func _gui_input(event: InputEvent) -> void:
	if not visible or _settings.visible or _guidebook.visible:
		return
	if event is InputEventMouseMotion:
		for i in _items.size():
			if _item_rect(i).has_point((event as InputEventMouseMotion).position) and _focus != i:
				_focus = i
				queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for i in _items.size():
			if _item_rect(i).has_point((event as InputEventMouseButton).position):
				_focus = i
				_activate(i)
				accept_event()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = roundf(w * 0.5)
	var a: float = clampf(_t / 0.12, 0.0, 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(UiKit.MEOK, 0.8 * a))
	# 머리줄
	UiKit.text(self, _f_bold, UiKit.SZ_BODY, Vector2(cx, 30), _head, Color(UiKit.HANJI_UI, a), 1)
	UiKit.draw_dancheong(self, Rect2(cx - 214, 36, 428, 4))
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx, 54), _stats, Color(UiKit.HANJI_2, a), 1)
	# 왼쪽 메뉴(먹 패널)
	var mp: Rect2 = Rect2(cx - 220, 78, 130, float(_items.size()) * ROW + 6.0)
	UiKit.draw_meok_panel(self, mp, 0.9 * a, true, UiKit.HANJI_5)
	var qi: int = _quit_index()
	for i in _items.size():
		var r: Rect2 = _item_rect(i)
		var foc: bool = i == _focus
		var s: String = _items[i]
		if i == qi and _quit_armed > 0.0:
			s = "한 번 더 → 그만두기" if Game.tutorial_mode else "한 번 더 → 거두기"
		if foc:
			draw_rect(r, Color(UiKit.HWANG, 0.18 * a))
			UiKit.draw_diamond(self, r.position + Vector2(6, 9), 2.0, Color(UiKit.HWANG, a))
			draw_rect(Rect2(r.position.x + 12, r.end.y - 2, r.size.x - 18, 1), Color(UiKit.HWANG, a))
		var col: Color = UiKit.HWANG_HI if foc else UiKit.HANJI
		if i == qi and _quit_armed > 0.0:
			col = UiKit.JEOK_HI
		UiKit.text(self, _f_body, UiKit.SZ_BODY, r.position + Vector2(14, 13), s, Color(col, a))
	# 오른쪽: 빌드(한지 패널)
	var bp: Rect2 = Rect2(cx - 86, 66, 300, 112)
	UiKit.draw_hanji_panel(self, bp, _paper)
	draw_string(_f_bold, bp.position + Vector2(10, 16), "무구", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, UiKit.INK)
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm != null:
		for i in 6:
			var col_x: float = bp.position.x + 10.0 + float(i % 2) * 146.0
			var row_y: float = bp.position.y + 24.0 + float(i / 2) * 28.0
			var wpn: WeaponBase = wm.weapon_at(i) if i < wm.slot_count() else null
			var sr: Rect2 = Rect2(col_x, row_y, 18, 18)
			draw_rect(sr, UiKit.MEOK_2)
			if wpn == null:
				draw_rect(sr, UiKit.HANJI_3, false, 1.0)
				continue
			draw_rect(sr, UiKit.HANJI_3 if wpn.is_white() else UiKit.JEOK, false, 1.0)
			var t: Texture2D = UiKit.weapon_icon(String(wpn.id), true)
			if t != null:
				draw_texture(t, sr.position + Vector2(1, 1))
			UiKit.draw_kind_mark(self, Vector2(col_x + 25, row_y + 6), 2.0, wpn.is_white())
			draw_string(_f_body, Vector2(col_x + 30, row_y + 10), UiKit.weapon_name(String(wpn.id)), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, UiKit.INK)
			for k in wpn.max_level:
				draw_rect(Rect2(col_x + 30 + k * 4, row_y + 14, 3, 2), UiKit.HWANG_DK if k < wpn.level else UiKit.HANJI_3)
	# 굿의 법도(규칙 요약) — 처음 하는 사람을 위한 상시 안내
	var gp: Rect2 = Rect2(cx - 220, 186, 434, 112)
	UiKit.draw_meok_panel(self, gp, 0.9 * a, true, UiKit.HWANG_DK)
	UiKit.text(self, _f_bold, UiKit.SZ_BODY, gp.position + Vector2(10, 16), "굿의 법도", Color(UiKit.HWANG_HI, a))
	var y: float = gp.position.y + 32.0
	for lines: PackedStringArray in _rules:
		for ln: String in lines:
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(gp.position.x + 14, y), ln, Color(UiKit.HANJI, a))
			y += 12.0
		y += 2.0
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx, h - 12), "↑↓ 고르기   Enter 확인   Esc 이어가기", Color(UiKit.HANJI_3, a), 1)
