extends Control
## 도감(최소판): 풀어 줌·처치 종별 누계 + 최근 판 + 다음 목표. 화면 말은 design/19 §2(넋기록 → 도감, 해원/퇴치 → 풀어 줌/처치). 소유: ui. design/11 §10.1~10.2 축약.
## 자료: Save.records_view()(singirok 해원록·벽사록), Save.recent_runs(5)(프로필 run_history). 구 ui.records 는 폴백만.
## (11-24) singirok 이전 완료 — ui/run_ledger.gd 의 ui.records·ui.run_history 쓰기는 이제 중복(무해, 정리는 선택).
## 입력: ↑↓ 넘기기, Esc/Enter 닫기.

signal closed

const ROWS: int = 9

var _list: Array[Dictionary] = []
var _hist: Array[PackedStringArray] = []
var _scroll: int = 0
var _tot_h: int = 0
var _tot_t: int = 0
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_tiny: Font
var _f_brush: Font
var _paper: Texture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")


func open() -> void:
	_list.clear()
	_hist.clear()
	_tot_h = 0
	_tot_t = 0
	# 정본: Save.records_view()(singirok 해원록·벽사록) / Save.recent_runs(5)(프로필 run_history). 리드 11-24.
	# 구 세이브(ui.records / ui.run_history)는 Save 가 v2 로 옮겼다. API 가 없으면 예전 자료로 폴백.
	if Save.has_method("records_view"):
		for r: Dictionary in Save.records_view():
			var sid: String = String(r.get("id", ""))
			var hv2: int = int(r.get("haewon", 0))
			var tv2: int = int(r.get("toechi", 0))
			if sid == "" or hv2 + tv2 <= 0:
				continue
			_tot_h += hv2
			_tot_t += tv2
			var tex2: Texture2D = SpriteLib.dir_tex(sid, "south", 32) if SpriteLib.has_entity(sid) else null
			_list.append({"id": sid, "name": UiKit.enemy_name(sid), "h": hv2, "t": tv2, "tex": tex2, "reg": _face_region(tex2)})
		for e2: Variant in Save.recent_runs(5):
			if e2 is Dictionary:
				var d2: Dictionary = e2
				var res: String = String(d2.get("result", ""))
				var lab: String = "쓰러짐"
				if res.begins_with("CLEAR"):
					lab = "굿 마침"
				elif res == "TIMEOUT_SAJA":
					lab = "사자 거둠"
				elif res == "ABANDON":
					lab = "그만둠"
				_hist.append(UiKit.wrap(_f_small, UiKit.SZ_SMALL, "%s  %s  %s  ○ %d  ◆ %d" % [
					lab, UiKit.char_name(String(d2.get("char", ""))), K.fmt_time(float(d2.get("time_s", 0))),
					int(d2.get("haewon", 0)), int(d2.get("toechi", 0))], 126.0, 2))
	else:
		_open_legacy()
	_scroll = 0
	visible = true
	queue_redraw()


func _open_legacy() -> void:
	var rec: Variant = Save.get_value("ui.records", {})
	if rec is Dictionary:
		for sp: Variant in rec:
			var row: Variant = (rec as Dictionary)[sp]
			if not (row is Array) or (row as Array).size() < 2:
				continue
			var hv: int = int((row as Array)[0])
			var tv: int = int((row as Array)[1])
			_tot_h += hv
			_tot_t += tv
			var tex: Texture2D = SpriteLib.dir_tex(String(sp), "south", 32) if SpriteLib.has_entity(String(sp)) else null
			_list.append({"id": String(sp), "name": UiKit.enemy_name(String(sp)), "h": hv, "t": tv, "tex": tex, "reg": _face_region(tex)})
	_list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["h"]) + int(x["t"]) > int(y["h"]) + int(y["t"]))
	var hist: Variant = Save.get_value("ui.run_history", [])
	if hist is Array:
		for e: Variant in hist:
			if e is Dictionary and _hist.size() < 5:
				var d: Dictionary = e
				_hist.append(UiKit.wrap(_f_small, UiKit.SZ_SMALL, "%s  %s  %s  ○ %d  ◆ %d  Lv %d" % [
					"굿 마침" if bool(d.get("victory", false)) else "쓰러짐", UiKit.char_name(String(d.get("char_id", ""))),
					K.fmt_time(float(d.get("time_sec", 0))), int(d.get("haewon", 0)), int(d.get("toechi", 0)), int(d.get("level", 1))], 126.0, 2))


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		_scroll = maxi(0, _scroll - 1)
	elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		_scroll = clampi(_scroll + 1, 0, maxi(0, _list.size() - ROWS))
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = maxi(0, _scroll - 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = clampi(_scroll + 1, 0, maxi(0, _list.size() - ROWS))
		else:
			close()
		accept_event()
		queue_redraw()


## 열 때 한 번: 불투명 영역(get_used_rect)의 위 18줄, 가운데 20px
func _face_region(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2()
	var ts: Vector2 = tex.get_size()
	var used: Rect2 = Rect2(Vector2.ZERO, ts)
	var img: Image = tex.get_image()
	if img != null and not img.is_empty():
		var ur: Rect2i = img.get_used_rect()
		if ur.size.x > 0 and ur.size.y > 0:
			used = Rect2(ur)
	var w: float = minf(20.0, used.size.x)
	var hgt: float = minf(18.0, used.size.y)
	var x: float = clampf(roundf(used.get_center().x - w * 0.5), 0.0, ts.x - w)
	return Rect2(x, used.position.y, w, hgt)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = roundf(w * 0.5)
	draw_rect(Rect2(0, 0, w, h), Color(UiKit.MEOK, 0.8))
	var p: Rect2 = Rect2(cx - 230, 24, 460, 300)
	UiKit.draw_hanji_panel(self, p, _paper)
	UiKit.draw_dancheong(self, Rect2(p.position.x + 2, p.position.y + 2, p.size.x - 4, 4))
	draw_rect(Rect2(p.position.x + 2, p.position.y + 6, p.size.x - 4, 34), UiKit.MEOK_1)
	UiKit.text_outline(self, _f_brush, 38, Vector2(cx, p.position.y + 33), "도감", UiKit.HANJI_UI, 1, 2)
	var ink: Color = UiKit.INK
	var x0: float = p.position.x + 16
	var y: float = p.position.y + 60
	draw_string(_f_bold, Vector2(x0, y), "○ 풀어 줌  %d" % _tot_h, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
	draw_string(_f_bold, Vector2(x0 + 150, y), "◆ 처치  %d" % _tot_t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, UiKit.JEOK_DK)
	y += 8
	draw_rect(Rect2(x0, y, p.size.x - 32, 1), UiKit.HANJI_4)
	if _list.is_empty():
		draw_string(_f_body, Vector2(x0, y + 24), "아직 기록된 넋이 없다. 굿판에서 만난 넋이 여기 남는다.", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, UiKit.HANJI_5)
	for i in ROWS:
		var k: int = _scroll + i
		if k >= _list.size():
			break
		var d: Dictionary = _list[k]
		var ry: float = y + 6 + i * 20
		var tex: Texture2D = d["tex"]
		if tex != null:
			# 얼굴(불투명 영역 위 18줄 × 가운데 20px)만 20×18 칸에 — 큰 캔버스(정예·보스)도 이름 칸을 덮지 않는다
			var reg: Rect2 = d["reg"]
			draw_texture_rect_region(tex, Rect2(Vector2(x0 + 10.0 - roundf(reg.size.x * 0.5), ry).round(), reg.size), reg)
		draw_string(_f_body, Vector2(x0 + 32, ry + 13), String(d["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
		draw_string(_f_small, Vector2(x0 + 150, ry + 13), "○ 풀어 줌 %d" % int(d["h"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, ink)
		draw_string(_f_small, Vector2(x0 + 230, ry + 13), "◆ 처치 %d" % int(d["t"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.JEOK_DK)
		draw_rect(Rect2(x0, ry + 18, 290, 1), Color(UiKit.HANJI_3, 0.6))
	# 최근 판
	var hx: float = p.position.x + 318
	var hy: float = p.position.y + 60
	draw_string(_f_bold, Vector2(hx, hy), "최근 굿판", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
	# 다음 목표(최고 기록 사다리)
	if Save.has_method("next_goal_line"):
		var gl: PackedStringArray = UiKit.wrap(_f_small, UiKit.SZ_SMALL, "다음 목표: " + String(Save.call("next_goal_line")), 126.0, 3)
		var gy: float = p.end.y - 20.0 - 11.0 * float(gl.size())
		draw_rect(Rect2(hx - 4, gy - 11, 134, 11.0 * float(gl.size()) + 6.0), Color(UiKit.HANJI_2, 0.7))
		for li in gl.size():
			draw_string(_f_small, Vector2(hx, gy + li * 11), gl[li], HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.JEOK_DK)
	for i in _hist.size():
		var parts: PackedStringArray = _hist[i]
		var yy: float = hy + 16 + i * 26
		for ln: String in parts:
			draw_string(_f_small, Vector2(hx, yy), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, UiKit.HANJI_5)
			yy += 11
	if _list.size() > ROWS:
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(x0 + 150, p.end.y - 10), "%d–%d / %d" % [_scroll + 1, mini(_scroll + ROWS, _list.size()), _list.size()], UiKit.HANJI_5, 1, false)
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx, h - 14), "↑↓ 넘기기   Esc 닫기", UiKit.HANJI_3, 1)
