class_name TutorialOffer
extends Control
## 연습 굿판 권유 창(design/17 §3.1-4). 소유: ui(intro_ui).
## [연습하기](기본 초점) · [바로 굿판 열기]. Esc/B = 닫고 타이틀 메뉴.
## 신호: chosen(choice) — &"practice" | &"play" | &"close". 플래그(tutorial_offered) 저장은 title 이 한다.

signal chosen(choice: StringName)

const BTNS: Array[String] = ["연습하기", "바로 굿판 열기"]
const PANEL: Vector2 = Vector2(340, 132)

var _focus: int = 0
var _t: float = 0.0
var _auto: float = -1.0           # --intro-test: n초 뒤 스스로 닫기
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_brush: Font
var _paper: Texture2D
var _body: PackedStringArray = PackedStringArray()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	UiKit.setup_fonts()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")
	_body = UiKit.wrap(_f_body, UiKit.SZ_BODY, "약 5분. 걷기만으로 귀신을 베고 풀어 주는 법을 배웁니다. 실패는 없습니다.", PANEL.x - 40.0, 2)


func open(auto_close: float = -1.0) -> void:
	visible = true
	_focus = 0
	_t = 0.0
	_auto = auto_close
	UiSettings.ui_sfx(&"sfx_ui_unlock")
	queue_redraw()


func _close(choice: StringName) -> void:
	if not visible:
		return
	visible = false
	UiSettings.ui_sfx(&"sfx_ui_back" if choice == &"close" else &"sfx_ui_confirm")
	chosen.emit(choice)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _auto > 0.0:
		_auto -= delta
		if _auto <= 0.0:
			_close(&"close")
			return
	queue_redraw()


func _panel() -> Rect2:
	return Rect2(roundf(size.x * 0.5 - PANEL.x * 0.5), roundf(size.y * 0.5 - PANEL.y * 0.5), PANEL.x, PANEL.y)


func _btn_rect(i: int) -> Rect2:
	var p: Rect2 = _panel()
	var bw: float = 120.0
	var gap: float = 16.0
	var x0: float = roundf(p.get_center().x - bw - gap * 0.5)
	return Rect2(x0 + float(i) * (bw + gap), p.position.y + 82.0, bw, 20.0)


func _activate(i: int) -> void:
	_close(&"practice" if i == 0 else &"play")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventJoypadMotion:
		return
	var handled: bool = true
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left") \
			or event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		_focus = 0
		UiSettings.ui_sfx(&"sfx_ui_nav")
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right") \
			or event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		_focus = 1
		UiSettings.ui_sfx(&"sfx_ui_nav")
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		_activate(_focus)
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
		_close(&"close")
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		for i in BTNS.size():
			if _btn_rect(i).has_point((event as InputEventMouseMotion).position):
				_focus = i
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for i in BTNS.size():
			if _btn_rect(i).has_point((event as InputEventMouseButton).position):
				_activate(i)
		accept_event()


func _draw() -> void:
	var a: float = clampf(_t / 0.2, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.MEOK, 0.72 * a))
	var p: Rect2 = _panel()
	UiKit.draw_hanji_panel(self, p, _paper)
	var cx: float = roundf(p.get_center().x)
	UiKit.text_outline(self, _f_brush, 28, Vector2(cx, p.position.y + 30.0), "연습 굿판을 해 볼까요?", UiKit.INK, 1, 0)
	UiKit.draw_dancheong(self, Rect2(cx - 70, p.position.y + 36.0, 140, 3))
	var y: float = p.position.y + 56.0
	for ln: String in _body:
		var lw: float = _f_body.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		draw_string(_f_body, Vector2(roundf(cx - lw * 0.5), y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, UiKit.INK)
		y += 14.0
	for i in BTNS.size():
		var r: Rect2 = _btn_rect(i)
		var foc: bool = i == _focus
		var pulse: bool = foc and fposmod(_t, 1.0) < 0.5
		UiKit.draw_meok_panel(self, r, 0.95, foc, UiKit.HWANG if pulse else (UiKit.HWANG_DK if foc else UiKit.HANJI_5))
		UiKit.text(self, _f_bold, UiKit.SZ_BODY, Vector2(r.get_center().x, r.position.y + 14.0), BTNS[i], UiKit.HWANG_HI if foc else UiKit.HANJI, 1)
		if foc:
			UiKit.draw_diamond(self, Vector2(r.position.x + 8, r.position.y + 10), 2.0, UiKit.JEOK)
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx, p.end.y - 10.0), "타이틀 '길잡이'에서 언제든 다시 할 수 있습니다", UiKit.HANJI_5, 1, false)
