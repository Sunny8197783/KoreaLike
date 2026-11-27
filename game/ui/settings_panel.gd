class_name SettingsPanel
extends Control
## 설정 패널(타이틀·일시정지 공용). 소유: ui. design/11 §12.1 · GAME_FEEL 7(접근성 연결).
## 항목은 UiSettings.OPTIONS(음량 3 · 흔들림 · 번쩍임 · 타격 멈춤 · 적 피격 번쩍임 · 피해 숫자 · 움직임 줄이기 ·
## 무당 강조 · 무리 어둡게 · 적 탄 강조 · 내 무기 효과 · 글자 크기 · 길잡이). 15항목 + 2줄 = 17줄 × 15px → 패널 319px, 아래 안내까지 360 안.
## 값이 바뀌면 즉시 적용(UiSettings.apply → Juice/Game/Audio), 닫을 때 디스크에 쓴다.
## 입력: ↑↓ 항목, ←→ 값, Enter(닫기 줄)/Esc/Backspace 닫기, 마우스 클릭(◀ ▶).

signal closed

const ROW_H: float = 15.0
const PANEL_W: float = 300.0

var _focus: int = 0
var _t: float = 0.0
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_brush: Font
var _paper: Texture2D
var _vals: PackedStringArray = PackedStringArray()
var _reset_t: float = 0.0          # '길잡이 처음부터' 확인 문구 표시


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


func open() -> void:
	visible = true
	_focus = 0
	_t = 0.0
	_refresh()
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	UiSettings.persist()
	closed.emit()


func _refresh() -> void:
	_vals.resize(UiSettings.OPTIONS.size())
	for i in UiSettings.OPTIONS.size():
		_vals[i] = UiSettings.display(String(UiSettings.OPTIONS[i]["key"]))


func _row_count() -> int:
	return UiSettings.OPTIONS.size() + 2     # + 길잡이 처음부터 + 닫기


func _is_reset_row(i: int) -> bool:
	return i == UiSettings.OPTIONS.size()


func _do_reset() -> void:
	UiSettings.reset_guide()
	UiSettings.ui_sfx(&"sfx_ui_confirm")
	_reset_t = 2.0
	queue_redraw()


func _panel_rect() -> Rect2:
	var h: float = 50.0 + ROW_H * float(_row_count()) + 14.0
	return Rect2(roundf(size.x * 0.5 - PANEL_W * 0.5), roundf(size.y * 0.5 - h * 0.5), PANEL_W, h)


func _row_rect(i: int) -> Rect2:
	var p: Rect2 = _panel_rect()
	return Rect2(p.position.x + 12, p.position.y + 46.0 + ROW_H * float(i), p.size.x - 24, ROW_H - 1.0)


func _step(dir: int) -> void:
	if _focus >= UiSettings.OPTIONS.size():
		return
	UiSettings.step(String(UiSettings.OPTIONS[_focus]["key"]), dir)
	UiSettings.ui_sfx(&"sfx_ui_move")
	_refresh()
	queue_redraw()


func _process(delta: float) -> void:
	if visible and _t < 0.3:
		_t += delta
		queue_redraw()
	if visible and _reset_t > 0.0:
		_reset_t = maxf(0.0, _reset_t - delta)
		if _reset_t <= 0.0:
			queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var handled: bool = true
	if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		_focus = (_focus - 1 + _row_count()) % _row_count()
	elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		_focus = (_focus + 1) % _row_count()
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_step(-1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_step(1)
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		if _is_reset_row(_focus):
			_do_reset()
		elif _focus >= UiSettings.OPTIONS.size():
			close()
		else:
			_step(1)
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
		close()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = (event as InputEventMouseMotion).position
		for i in _row_count():
			if _row_rect(i).has_point(mp) and _focus != i:
				_focus = i
				queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		for i in _row_count():
			var rr: Rect2 = _row_rect(i)
			if rr.has_point(mb.position):
				_focus = i
				if _is_reset_row(i):
					_do_reset()
				elif i >= UiSettings.OPTIONS.size():
					close()
				else:
					_step(-1 if mb.position.x < rr.end.x - 46.0 else 1)
				accept_event()
				return
		if not _panel_rect().has_point(mb.position):
			close()
			accept_event()


func _draw() -> void:
	var a: float = clampf(_t / 0.12, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.MEOK, 0.55 * a))
	var p: Rect2 = _panel_rect()
	p.position.y += roundf((1.0 - UiKit.ease_out_cubic(clampf(_t / 0.18, 0.0, 1.0))) * 12.0)
	draw_rect(Rect2(p.position + Vector2(3, 4), p.size), Color(UiKit.MEOK, 0.6))
	UiKit.draw_hanji_panel(self, p, _paper)
	UiKit.draw_dancheong(self, Rect2(p.position.x + 2, p.position.y + 2, p.size.x - 4, 4))
	draw_rect(Rect2(p.position.x + 2, p.position.y + 6, p.size.x - 4, 34), UiKit.MEOK_1)
	UiKit.text_outline(self, _f_brush, 38, Vector2(p.get_center().x, p.position.y + 33.0), "설정", UiKit.HANJI_UI, 1, 2)
	var ink: Color = UiKit.INK
	for i in _row_count():
		var rr: Rect2 = _row_rect(i)
		rr.position.y = p.position.y + 46.0 + ROW_H * float(i)
		var foc: bool = i == _focus
		if foc:
			draw_rect(rr, Color(UiKit.HWANG, 0.28))
			draw_rect(Rect2(rr.position, Vector2(2, rr.size.y)), UiKit.JEOK)
		if _is_reset_row(i):
			var rs: String = "다음 판부터 처음 안내합니다" if _reset_t > 0.0 else "길잡이 처음부터"
			var rw: float = _f_body.get_string_size(rs, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
			draw_string(_f_body, Vector2(roundf(rr.get_center().x - rw * 0.5), rr.position.y + 12.0), rs, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, UiKit.JEOK_DK if (foc or _reset_t > 0.0) else ink)
			continue
		if i >= UiSettings.OPTIONS.size():
			var s: String = "닫기"
			var sw: float = _f_bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
			draw_string(_f_bold, Vector2(roundf(rr.get_center().x - sw * 0.5), rr.position.y + 12.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, UiKit.JEOK_DK if foc else ink)
			continue
		var o: Dictionary = UiSettings.OPTIONS[i]
		draw_string(_f_body, Vector2(rr.position.x + 6, rr.position.y + 12.0), String(o["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
		var v: String = _vals[i] if i < _vals.size() else ""
		var vw: float = _f_bold.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		var vx: float = rr.end.x - 30.0
		draw_string(_f_bold, Vector2(roundf(vx - vw * 0.5), rr.position.y + 12.0), v, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, UiKit.JEOK_DK if foc else ink)
		if foc:
			draw_string(_f_small, Vector2(vx - 30.0, rr.position.y + 12.0), "◀", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.JEOK_DK)
			draw_string(_f_small, Vector2(vx + 22.0, rr.position.y + 12.0), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.JEOK_DK)
	var hint: String = "↑↓ 항목   ←→ 바꾸기   Esc 닫기"
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(p.get_center().x, p.end.y + 14.0), hint, UiKit.HANJI_2, 1)
