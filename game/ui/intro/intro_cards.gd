class_name IntroCards
extends Control
## 컨셉 인트로 카드 6장(design/17 §4). 소유: ui(intro_ui).
## 그림(위) + 붓 제목 + 문장 1~2줄. 카드 전환 = 먹 번짐(shaders/dissolve.gdshader mode 1 → 새 그림 mode 0 역재생).
## 넘기기: Enter·Space·A·→·클릭 = 다음 / ←·Backspace·B = 이전 / Esc·P·Start = 건너뛰기(확인 없음).
## 글자는 0.6초 동안 붓으로 쓰이듯 왼쪽부터 드러난다(그동안 '다음' = 글자 다 보이기).
## 신호: finished(skipped) — 끝까지 봤으면 false, 건너뛰면 true. 플래그 저장은 부르는 쪽(title)이 한다.
## --intro-test: open(true) → 실시간 1.5초마다 자동 넘김, 로그 [intro] card=<n>/6 id=<id>.

signal finished(skipped: bool)

const DISSOLVE: Shader = preload("res://shaders/dissolve.gdshader")
const KEY_ART: String = "res://ui/art/key_art_gutpan.png"
const ART_DIR: String = "res://ui/art/intro/"
const T_OUT: float = 0.35          # 옛 그림 먹 번짐
const T_IN0: float = 0.12          # 새 그림 떠오름 시작
const T_IN: float = 0.35           # 새 그림 떠오름 길이
const T_TEXT0: float = 0.3         # 글자 드러남 시작
const T_TEXT: float = 0.6          # 글자 드러남 길이
const TEST_STEP: float = 1.5

## layout: full(화면 가득·표류) | wide(가로 688 잘라 쓰기·흐름) | framed(344 폭 1배, 한지 테)
## design/19 §7: 장 수(6)·그림은 그대로, 말과 순서만 — 1 목표 / 2 벤다 / 3 흰 테두리를 푼다 / 4 넋 동무 / 5 흰 길 감싸기 / 6 끝(역려·신당).
## 한자·괄호 용어를 쓰지 않는다. 귀신의 표시는 '흰 테두리'로 통일.
const CARDS: Array[Dictionary] = [
	{"id": "intro_gutpan", "img": KEY_ART, "layout": "full", "title": "은실 만신의 진오기굿",
		"text": "동짓날 밤, 길 잃은 넋들이 귀신이 되어 굿판으로 몰려든다. 20분을 버티면 넋길이 열린다."},
	{"id": "intro_sal", "img": ART_DIR + "intro_wongwi.png", "layout": "framed", "title": "붉은 칼로 귀신을 벤다",
		"text": "걷기만 하면 무기는 저절로 친다. 붉은 무기는 귀신을 베어 처치한다."},
	{"id": "intro_twist", "img": ART_DIR + "intro_core_twist.png", "layout": "framed", "title": "흰 테두리가 생기면 풀어 준다",
		"text": "약해진 귀신에게 흰 테두리가 생긴다. 흰 무기 곁에 두면 한이 풀려 사람으로 돌아간다."},
	{"id": "intro_yeongga", "img": ART_DIR + "intro_procession.png", "layout": "wide", "crop": Rect2(0, 128, 688, 232),
		"title": "풀린 넋이 뒤따르며 지켜 준다", "text": "풀린 넋은 넋 동무가 되어 뒤를 따르고, 곁의 귀신을 막아 준다."},
	{"id": "intro_gildakkeum", "img": ART_DIR + "intro_gildakkeum.png", "layout": "framed", "title": "흰 길로 한 바퀴 감싸면",
		"text": "걸어온 자리에 흰 길이 남는다. 한 바퀴 감싸면 안쪽 귀신이 한꺼번에 풀린다."},
	{"id": "intro_road", "img": ART_DIR + "intro_jeoseunggil.png", "layout": "framed", "title": "끝에는 역려가 온다",
		"text": "20:00, 역병 귀신 역려를 보내면 굿이 끝난다. 얻은 것으로 신당을 키워 다음 굿을 연다."},
]
const TAGLINE: String = "깎아 부수거나, 풀어 보내거나."

var _idx: int = 0
var _t: float = 0.0                # 이 카드가 시작된 뒤 실시간
var _out_t: float = 99.0           # 옛 그림 번짐 경과
var _test: bool = false
var _test_t: float = 0.0
var _done: bool = false
var _reduce: bool = false
var _fx_done: int = 0              # 카드별 연출 단계(소리·깜박)
var _f_body: Font
var _f_small: Font
var _f_tiny: Font
var _f_brush: Font
var _paper: Texture2D
var _vignette: Texture2D
var _texs: Array[Texture2D] = []
var _lines: Array[PackedStringArray] = []
var _line_len: PackedInt32Array = PackedInt32Array()
var _img_in: TextureRect
var _img_out: TextureRect
var _mat_in: ShaderMaterial
var _mat_out: ShaderMaterial
var _fg: Control
var _out_layout: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	UiKit.setup_fonts()
	_f_body = UiKit.body()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")
	_vignette = UiKit.skin("vignette.png")
	for c: Dictionary in CARDS:
		var tex: Texture2D = SpriteLib.tex(String(c["img"]))
		if tex != null and c.has("crop"):
			tex = _crop(tex, c["crop"])
		_texs.append(tex)
		var ls: PackedStringArray = UiKit.wrap(_f_body, UiKit.SZ_BODY, String(c["text"]), 520.0, 2)
		_lines.append(ls)
		var n: int = 0
		for s: String in ls:
			n += s.length()
		_line_len.append(n)
	_mat_out = _make_mat(1)
	_mat_in = _make_mat(0)
	_img_out = _make_rect(_mat_out)
	_img_in = _make_rect(_mat_in)
	_fg = Control.new()
	_fg.name = "Fg"
	_fg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fg)
	_fg.draw.connect(_draw_fg)


func _make_mat(mode: int) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = DISSOLVE
	m.set_shader_parameter("mode", mode)
	# 먹으로 번져 사라지고(먹 가장자리), 한지빛으로 떠오른다(한지 가장자리)
	m.set_shader_parameter("edge_toechi", UiKit.MEOK_3)
	m.set_shader_parameter("edge_haewon", UiKit.HANJI)
	m.set_shader_parameter("edge_width", 0.1)
	return m


func _make_rect(m: ShaderMaterial) -> TextureRect:
	var r: TextureRect = TextureRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.stretch_mode = TextureRect.STRETCH_KEEP
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.material = m
	add_child(r)
	return r


## 잘라 쓰기(로고 글자 제외 등) — 열 때 한 번만.
func _crop(tex: Texture2D, rc: Rect2) -> Texture2D:
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return tex
	if img.is_compressed():
		img.decompress()
	var r: Rect2i = Rect2i(rc).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	return ImageTexture.create_from_image(img.get_region(r))


func open(test: bool = false) -> void:
	_test = test
	_done = false
	_reduce = Juice.reduce_motion
	visible = true
	_out_t = 99.0
	_img_out.visible = false
	_show(0)


func _show(i: int) -> void:
	var prev: int = _idx
	var had: bool = _img_in.visible and _img_in.texture != null
	_idx = i
	_t = 0.0
	_test_t = 0.0
	_fx_done = 0
	# 옛 그림 → 번짐(먹)
	if had and prev != i:
		_img_out.texture = _img_in.texture
		_img_out.position = _img_in.position
		_img_out.size = _img_in.size
		_img_out.modulate = _img_in.modulate
		_img_out.visible = true
		_out_layout = String(CARDS[prev]["layout"])
		_out_t = 0.0
	_img_in.texture = _texs[i]
	_img_in.visible = _texs[i] != null
	if _texs[i] != null:
		_img_in.size = _texs[i].get_size()
		_img_in.position = _img_pos(i, 0.0)
	_apply_fx()
	if _test or Game.autotest:
		print("[intro] card=%d/%d id=%s" % [i + 1, CARDS.size(), String(CARDS[i]["id"])])
	# 카드 소리
	match String(CARDS[i]["id"]):
		"intro_gutpan":
			UiSettings.ui_sfx(&"sfx_ui_title_start")      # 징 자리 대신 장구 '덩'(F22)
		"intro_road":
			UiSettings.ui_sfx(&"sfx_chaser_saja_eup")
		_:
			if prev != i:
				UiSettings.ui_sfx(&"sfx_ui_nav")
	queue_redraw()


func _img_pos(i: int, t: float) -> Vector2:
	var tex: Texture2D = _texs[i]
	if tex == null:
		return Vector2.ZERO
	var ts: Vector2 = tex.get_size()
	match String(CARDS[i]["layout"]):
		"full":
			var drift: Vector2 = Vector2.ZERO
			if not _reduce:
				drift = Vector2(roundf(sin(t * 0.15) * 3.0), roundf(cos(t * 0.11) * 2.0))
			return Vector2(roundf((size.x - ts.x) * 0.5), roundf((size.y - ts.y) * 0.5) - 12.0) + drift
		"wide":
			# 오른쪽에서 왼쪽으로 3px/초(행렬이 걷는 느낌)
			var slack: float = maxf(0.0, ts.x - size.x)
			var sx: float = 0.0 if _reduce else minf(t * 3.0, slack)
			return Vector2(roundf(-sx), 0.0)
		_:
			return Vector2(roundf((size.x - ts.x) * 0.5), roundf(36.0 + (192.0 - ts.y) * 0.5))


func _finish(skipped: bool) -> void:
	if _done:
		return
	_done = true
	visible = false
	UiSettings.ui_sfx(&"sfx_ui_skip" if skipped else &"sfx_ui_confirm")
	if _test or Game.autotest:
		print("[intro] end skipped=%s" % str(skipped))
	finished.emit(skipped)


func _text_k() -> float:
	return clampf((_t - T_TEXT0) / T_TEXT, 0.0, 1.0)


func next() -> void:
	if _done:
		return
	if _text_k() < 1.0:
		_t = T_TEXT0 + T_TEXT        # 글자를 다 보여 준다(한 번 더 눌러야 넘어감)
		return
	if _idx >= CARDS.size() - 1:
		_finish(false)
	else:
		_show(_idx + 1)


func prev() -> void:
	if _done or _idx <= 0:
		return
	_show(_idx - 1)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_out_t += delta
	if _test:
		_test_t += delta
		# 마지막 장은 태그라인·인장까지 보이게 조금 더 둔다
		if _test_t >= (TEST_STEP if _idx < CARDS.size() - 1 else _tag_at() + 0.9):
			_test_t = 0.0
			_t = maxf(_t, T_TEXT0 + T_TEXT)
			next()
			if not visible:
				return
	_update_fx()
	_apply_fx()
	queue_redraw()
	_fg.queue_redraw()


## 카드별 연출(시각 기준 한 번씩): 소리 + 깜박
func _update_fx() -> void:
	var id: String = String(CARDS[_idx]["id"])
	match id:
		"intro_gutpan":
			if _fx_done == 0 and _t >= 0.4:
				_fx_done = 1
				UiSettings.ui_sfx(&"sfx_sys_deungbul")
		"intro_twist":
			if _fx_done == 0 and _t >= 1.0:
				_fx_done = 1
				UiSettings.ui_sfx(&"sfx_sys_hanpa")
			elif _fx_done == 1 and _t >= 1.6:
				_fx_done = 2
				UiSettings.ui_sfx(&"sfx_sys_haewon")
		"intro_yeongga":
			if _fx_done == 0 and _t >= 0.45:
				_fx_done = 1
				UiSettings.ui_sfx(&"sfx_sys_yeongga_join")
		"intro_gildakkeum":
			if _fx_done == 0 and _t >= T_IN0 + T_IN + 0.5:
				_fx_done = 1
				UiSettings.ui_sfx(&"sfx_sys_gildakkeum")
		"intro_sal":
			if _fx_done == 0 and _t >= 0.45:
				_fx_done = 1
				UiSettings.ui_sfx(&"sfx_sys_hanpa")
		"intro_road":
			if _fx_done == 0 and _t >= _tag_at():
				_fx_done = 1
				UiSettings.ui_sfx(&"sfx_ui_card_select")


## 태그라인이 찍히는 시각: 글자가 다 쓰이고 한 박 쉰 뒤
func _tag_at() -> float:
	return T_TEXT0 + T_TEXT + 0.7


func _apply_fx() -> void:
	# 들어오는 그림
	var kin: float = clampf((_t - T_IN0) / (0.2 if _reduce else T_IN), 0.0, 1.0)
	var first: bool = _idx == 0
	if first:
		kin = 1.0     # 첫 장은 먹색에서 밝아짐으로 연다
	if _texs[_idx] != null:
		_img_in.position = _img_pos(_idx, _t)
	var col: Color = Color.WHITE
	if first:
		# 먹색 → 0.4초 뒤 등불 켜짐과 함께 밝아짐(촛불 깜박)
		var b: float = clampf((_t - 0.4) / 0.8, 0.0, 1.0)
		var flick: float = 0.9 + 0.05 * sin(_t * TAU * 0.5) + 0.03 * sin(_t * 9.0)
		col = Color(b * flick, b * flick * 0.97, b * flick * 0.95, 1.0)
	elif String(CARDS[_idx]["id"]) == "intro_sal":
		# 원귀 맥동(0.6초): 그림 그대로, 붉게 한 번 숨쉼
		var pk: float = clampf((_t - 0.45) / 0.6, 0.0, 1.0)
		var p: float = sin(pk * PI)
		# 원본이 아주 어두워 원귀 셋이 잘 안 보였다(리뷰 11-25) → 1.6배 밝힘(modulate 과노출, 그림은 그대로)
		var lift: float = 1.6
		col = Color(lift, lift * (1.0 - 0.25 * p), lift * (1.0 - 0.25 * p), 1.0)
	elif String(CARDS[_idx]["id"]) == "intro_road":
		var dk: float = clampf((_t - _tag_at() + 0.2) / 0.3, 0.0, 1.0)
		col = Color(1.0 - 0.45 * dk, 1.0 - 0.45 * dk, 1.0 - 0.45 * dk, 1.0)
	if _reduce:
		_img_in.material = null
		col.a = kin
	else:
		_img_in.material = _mat_in
		_mat_in.set_shader_parameter("progress", 1.0 - kin)
	_img_in.modulate = col
	# 나가는 그림
	if _img_out.visible:
		var kout: float = clampf(_out_t / (0.2 if _reduce else T_OUT), 0.0, 1.0)
		if kout >= 1.0:
			_img_out.visible = false
		elif _reduce:
			_img_out.material = null
			_img_out.modulate.a = 1.0 - kout
		else:
			_img_out.material = _mat_out
			_mat_out.set_shader_parameter("progress", kout)


# ─── 입력 ───────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _done:
		return
	if event is InputEventJoypadMotion:
		return     # 스틱 흔들림으로 여러 장 넘어가지 않게(D-패드는 됨)
	var handled: bool = true
	if event.is_action_pressed(&"pause"):
		_finish(true)
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept") \
			or event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		next()
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"cancel"):
		prev()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible or _done:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _skip_rect().has_point(mb.position):
				_finish(true)
			else:
				next()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			prev()
			accept_event()


func _skip_rect() -> Rect2:
	return Rect2(size.x - 100, 2, 98, 18)


# ─── 그리기 ─────────────────────────────────────────────────────────────

## 바탕(그림 아래): 먹 + 한지 결 + 한지 테(framed)
func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(0, 0, w, h), UiKit.MEOK)
	if _paper != null:
		draw_texture_rect(_paper, Rect2(0, 0, w, h), true, Color(UiKit.MEOK_2, 0.35))
	if String(CARDS[_idx]["layout"]) == "framed" and _texs[_idx] != null:
		var k: float = clampf((_t - T_IN0) / T_IN, 0.0, 1.0)
		var r: Rect2 = Rect2(_img_pos(_idx, _t), _texs[_idx].get_size()).grow(4.0)
		if String(CARDS[_idx]["id"]) == "intro_twist":
			r = Rect2(Vector2(r.position.x, 32), Vector2(r.size.x, 200))
		draw_rect(r.grow(1.0), Color(UiKit.MEOK, k))
		draw_rect(r, Color(UiKit.HANJI_3, k))
		draw_rect(r.grow(-1.0), Color(UiKit.HANJI_2, k))
		draw_rect(r.grow(-3.0), Color(UiKit.MEOK_1, k))
		UiKit.draw_corners(self, r.grow(-1.0), Color(UiKit.JEOK_DK, k))


## 앞(그림 위): 그라데이션·깜박·제목·문장·진행 점·건너뛰기
func _draw_fg() -> void:
	var w: float = _fg.size.x
	var h: float = _fg.size.y
	var cx: float = roundf(w * 0.5)
	var c: Dictionary = CARDS[_idx]
	var id: String = String(c["id"])
	var layout: String = String(c["layout"])
	# 가득 그림(full/wide): 아래 먹 그라데이션(글자 가독)
	if layout != "framed":
		var y0: float = 196.0 if layout == "full" else 176.0
		for i in 14:
			var yy: float = y0 + float(i) * 5.0
			_fg.draw_rect(Rect2(0, yy, w, 5.0), Color(UiKit.MEOK, minf(0.95, 0.07 * float(i + 1))))
		_fg.draw_rect(Rect2(0, y0 + 70.0, w, h - y0 - 70.0), Color(UiKit.MEOK, 0.95))
		if _vignette != null:
			_fg.draw_texture_rect(_vignette, Rect2(0, 0, w, h), false, Color(1, 1, 1, 0.5))
	_draw_card_fx(id, cx)
	# 제목(붓) + 문장(붓으로 쓰이듯)
	var ta: float = clampf((_t - 0.2) / 0.3, 0.0, 1.0)
	if _idx == 0:
		ta = clampf((_t - 0.5) / 0.4, 0.0, 1.0)
	UiKit.text_outline(_fg, _f_brush, 36, Vector2(cx, 264), String(c["title"]), Color(UiKit.HANJI_UI, ta), 1, 2)
	var shown: int = int(floorf(float(_line_len[_idx]) * _text_k()))
	var y: float = 288.0
	for ln: String in _lines[_idx]:
		if shown <= 0:
			break
		var lw: float = _f_body.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		var part: String = ln.left(shown)
		UiKit.text(_fg, _f_body, UiKit.SZ_BODY, Vector2(roundf(cx - lw * 0.5), y), part, UiKit.HANJI_UI)
		shown -= ln.length()
		y += 16.0
	# 진행 점 6개(지금 장 = 황 마름모)
	var n: int = CARDS.size()
	var dx0: float = cx - float(n - 1) * 6.0
	for i in n:
		var p: Vector2 = Vector2(dx0 + float(i) * 12.0, 340.0)
		if i == _idx:
			UiKit.draw_diamond(_fg, p, 3.0, UiKit.HWANG)
		else:
			_fg.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), UiKit.HANJI_3 if i < _idx else UiKit.HANJI_5)
	UiKit.text(_fg, _f_small, UiKit.SZ_SMALL, Vector2(w - 8, 344), "Enter 다음   ← 이전", UiKit.HANJI_3, 2)
	UiKit.text(_fg, _f_small, UiKit.SZ_SMALL, Vector2(8, 344), "%d / %d" % [_idx + 1, n], UiKit.HANJI_4)
	# 건너뛰기(항상)
	UiKit.text(_fg, _f_small, UiKit.SZ_SMALL, Vector2(w - 8, 14), "건너뛰기 Esc ▶▶", UiKit.HANJI_2, 2)


func _draw_card_fx(id: String, cx: float) -> void:
	match id:
		"intro_twist":
			var ip: Vector2 = _img_pos(_idx, _t)
			var cw: float = 86.0
			# 왼쪽 두 칸(일그러진 얼굴 → 사람 얼굴) 위 흰 테 깜박 0.5초
			if _t >= 0.4 and _t < 0.9 and fposmod(_t, 0.2) < 0.12:
				_fg.draw_rect(Rect2(ip, Vector2(cw * 2.0, 128)).grow(-1.0), UiKit.BAEK, false, 1.0)
			# 3번째 칸 붉은 파열
			if _t >= 1.0:
				var a3: float = clampf(1.0 - (_t - 1.0) / 0.5, 0.25, 1.0)
				_fg.draw_rect(Rect2(ip + Vector2(cw * 2.0, 0), Vector2(cw, 128)).grow(-1.0), Color(UiKit.JEOK_HI, a3), false, 1.0)
			# 4번째 칸 해원(흰)
			if _t >= 1.6:
				var a4: float = clampf(1.0 - (_t - 1.6) / 0.5, 0.25, 1.0)
				_fg.draw_rect(Rect2(ip + Vector2(cw * 3.0, 0), Vector2(cw, 128)).grow(-1.0), Color(UiKit.BAEK, a4), false, 1.0)
			# 아래 작은 글씨: ◆ 붉은 = 베어 처치 · ○ 흰 = 풀어 줌
			var ca: float = clampf((_t - 0.5) / 0.3, 0.0, 1.0)
			var y: float = 220.0
			var s1: String = "붉은 = 베어 처치"
			var s2: String = "흰 = 풀어 줌"
			var w1: float = _f_small.get_string_size(s1, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
			var w2: float = _f_small.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
			var tot: float = 9.0 + w1 + 22.0 + 9.0 + w2
			var x: float = roundf(cx - tot * 0.5)
			if ca > 0.0:
				UiKit.draw_kind_mark(_fg, Vector2(x + 3, y - 4), 2.0, false)
				UiKit.text(_fg, _f_small, UiKit.SZ_SMALL, Vector2(x + 9, y), s1, Color(UiKit.JEOK_HI, ca))
				UiKit.text(_fg, _f_small, UiKit.SZ_SMALL, Vector2(x + 9 + w1 + 8, y), "·", Color(UiKit.HANJI_3, ca))
				var x2: float = x + 9.0 + w1 + 22.0
				UiKit.draw_kind_mark(_fg, Vector2(x2 + 3, y - 4), 2.0, true)
				UiKit.text(_fg, _f_small, UiKit.SZ_SMALL, Vector2(x2 + 9, y), s2, Color(UiKit.HANJI_UI, ca))
		"intro_gildakkeum":
			# 그림 뜬 뒤 0.5초 '덩' + 0.1초 번쩍
			var t0: float = T_IN0 + T_IN + 0.5
			if not _reduce and _t >= t0 and _t < t0 + 0.1 and Juice.flash_enabled:
				var ip2: Vector2 = _img_pos(_idx, _t)
				_fg.draw_rect(Rect2(ip2, _texs[_idx].get_size()), Color(UiKit.HANJI_UI, 0.35 * Juice.flash_scale))
		"intro_road":
			var tk: float = clampf((_t - _tag_at()) / 0.35, 0.0, 1.0)
			if tk <= 0.0:
				return
			# 그림 위 먹 띠 + 태그라인 붓글씨 크게 + 붉은 인장 찍힘
			var band: Rect2 = Rect2(cx - 214, 104, 428, 56)
			_fg.draw_rect(band, Color(UiKit.MEOK, 0.72 * tk))
			_fg.draw_rect(Rect2(band.position.x, band.position.y, band.size.x, 1), Color(UiKit.HWANG_DK, tk))
			_fg.draw_rect(Rect2(band.position.x, band.end.y - 1, band.size.x, 1), Color(UiKit.HWANG_DK, tk))
			var shown: int = int(ceilf(float(TAGLINE.length()) * clampf(tk * 1.4, 0.0, 1.0)))
			var tw: float = _f_brush.get_string_size(TAGLINE, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
			var tx: float = roundf(cx - tw * 0.5 - 12.0)
			UiKit.text_outline(_fg, _f_brush, 40, Vector2(tx, 144), TAGLINE.left(shown), Color(UiKit.HANJI_UI, tk), 0, 2)
			var sk: float = clampf((_t - _tag_at() - 0.3) / 0.15, 0.0, 1.0)
			if sk > 0.0:
				TutDraw.seal(_fg, Vector2(tx + tw + 24.0, 130.0), sk, sk, "巫", _f_body)
