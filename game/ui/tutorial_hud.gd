extends CanvasLayer
## 연습 굿판 HUD(design/17 §5.1.1). 소유: ui(intro_ui). layer 24, 인자 없는 new().
## 디렉터(game/tutorial/tutorial_director.gd)가 _begin 에서 런의 자식으로 붙인다. Events tutorial_* 를 듣고 그린다
## (표시만 — 시뮬 상태는 바꾸지 않는다. 예외: 멈춤 카드·끝 화면의 push/pop_pause 와 요청 신호 tutorial_ack·tutorial_exit_requested).
## 그리는 것
##  - 등불 줄(진행 10개, 위 '연습' 시계 양옆 5개씩, y=19) · 목표 줄(y=H−80~H−64, 먹 띠 + 황 테) · 보조 줄(H−52, H−40, 도움 오면 황 깜박)
##    (가시성: 무당 발밑~y≈275 는 비워 둔다. 묶음 밑에 무당·귀신이 들어오면 0.4 로 옅어진다)
##  - 단계 완료 이름표(가운데 y≈112: 한자 + 붓글씨 32 + 붉은 인장, 0.15초 드러남 → 1.2초 → 0.3초 먹 번짐)
##  - 월드 이름표(B 채널, 0.9초) · 멈춤 주석(위 한지 띠: 점지·빙의 점지) · 멈춤 카드(정산 단계) · 끝 화면
##  - 시작 연출: 먹색 0.6초 페이드인 + 붓글씨 '연습 굿판' 1.0초
## Events 신호는 tutorial_run 이 더한다 — 이름으로 느슨하게 연결한다(has_signal 가드).

const STEP_IDS: Array[StringName] = [&"move", &"beat", &"cut", &"ring", &"white", &"yeongga", &"jeomji", &"trial", &"sal", &"settle"]
const LANTERN_GAP: float = 12.0
const NAME_IN: float = 0.15
const NAME_HOLD: float = 1.2
const NAME_OUT: float = 0.3
const TAG_LIFE: float = 0.9
# 가시성(친구 플레이 피드백 '공격이 안 보인다'): 목표 묶음은 화면 맨 아래 띠로, 등불 줄은 위 '연습' 시계 양옆으로.
# 무당 발밑(화면 가운데 y≈180~200)부터 y≈275 까지는 비워 둔다. 묶음 밑에 무당·귀신이 들어오면 OCCLUDED_A 로 옅어진다.
const BAND_TOP: float = 80.0      # 목표 띠 윗변 = h − 80 (보조 줄은 그 아래 두 줄, 맨 아래 연속 굿 칩 h−34 위)
const LANTERN_Y: float = 19.0     # 등불 줄: hud 시계 '연습'(y 13~26) 양옆 — 박 마름모(cx±26) 바깥
const LANTERN_IN: float = 40.0    # 시계 가운데에서 가장 안쪽 등불까지
const OCCLUDED_A: float = 0.4
# 이름표 자리: hud 알림 줄(y≈64~80, '몸주 신령이 방울을 내리셨다')과 한자가 겹치지 않게 112 → 124(톤 리뷰 11-25)
const NAME_Y: float = 124.0
const GEORI_CARD_AT: float = 3.0   # waves_stage1 runtime.geori_card_min_time_sec
const GEORI_CARD_SEC: float = 3.8  # 카드 3.2초 + 여유
const SEAL_GLYPH: String = "巫"    # 타이틀 로고·인트로 인장과 같은 글자(印 은 '도장'이란 뜻뿐이라 바꿈)
const END_BTNS: Array[String] = ["굿판 열기(실전)", "다시 연습", "타이틀로"]
const END_NEXT: Array[StringName] = [&"real", &"again", &"title"]
const END_LINES: Array[String] = ["◆ 붉은 무구로 깎고, ○ 흰 무구로 푼다", "흰 길로 고리를 닫으면 한꺼번에 풀린다", "시련은 ◆ 꺾어 위엄, ○ 모셔 가호"]
const ANN_JEOMJI: Array[String] = ["◆ 붉은 = 깎아 퇴치 · ○ 흰 = 풀어 해원 — 하나를 고르세요",
	"카드 맨 아래 '짝'을 함께 키우면 무구가 진화합니다"]   # 첫 점지에 Lv8·정예 상자까지는 많다(리뷰 11-25) — 자세한 건 안내서 7쪽
const ANN_BINGUI: Array[String] = ["빙의! 신령의 권능을 하나 고르세요"]

var _view: Control
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_tiny: Font
var _f_brush: Font
var _paper: Texture2D
var _t: float = 0.0

# 진행
var _total: int = 10
var _lit: PackedByteArray = PackedByteArray()
var _skipped: PackedByteArray = PackedByteArray()
var _cur: int = -1
var _cur_id: StringName = &""
var _started: bool = false
var _banner_t: float = 99.0

# 목표·보조 줄
var _goal: String = ""
var _sub: PackedStringArray = PackedStringArray()
var _done: int = 0
var _need: int = 0
var _line_t: float = 0.0          # 줄이 바뀐 뒤(등장 0.25초)
var _help_flash: float = 0.0
var _bottom_a: float = 0.0
var _lantern_a: float = 0.0       # 등불 줄(위)은 아래 묶음의 옅어짐과 따로 간다
var _beat_k: float = 0.0
var _beat_down: bool = false

# 이름표(단계 완료)
var _nl_text: String = ""
var _nl_hanja: String = ""
var _nl_t: float = 99.0

# 월드 이름표(최대 4)
var _tag_text: PackedStringArray = PackedStringArray(["", "", "", ""])
var _tag_hj: PackedStringArray = PackedStringArray(["", "", "", ""])
var _tag_pos: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _tag_t: PackedFloat32Array = PackedFloat32Array([99, 99, 99, 99])

# 멈춤 주석
var _ann: PackedStringArray = PackedStringArray()
var _ann_t: float = 0.0
var _ann_kind: StringName = &""
var _trial_phase: StringName = &"dormant"   # 시련 안내판(위 y 82~)이 떠 있으면 이름표를 아래로 내린다
var _geori_until: float = GEORI_CARD_AT + GEORI_CARD_SEC   # 첫 거리 카드(런 시작 신호를 놓쳐도)

# 멈춤 카드
var _card_on: bool = false
var _card_step: StringName = &""
var _card_pages: Array = []
var _card_confirm: String = ""
var _card_page: int = 0
var _card_t: float = 0.0
var _card_lines: Array[PackedStringArray] = []
var _card_tex: Array = []          # 쪽마다 Array[Texture2D] (sprite: 는 idle 프레임, png 는 1장)
var _card_scale: PackedInt32Array = PackedInt32Array()

# 끝 화면
var _end_on: bool = false
var _end_t: float = 0.0
var _end_focus: int = 0


func _ready() -> void:
	layer = 24
	UiKit.setup_fonts()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")
	_view = Control.new()
	_view.name = "View"
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_view_input)
	_lit.resize(_total)
	_skipped.resize(_total)
	_link(&"tutorial_started", _on_started)
	_link(&"tutorial_step_started", _on_step_started)
	_link(&"tutorial_step_progress", _on_progress)
	_link(&"tutorial_help", _on_help)
	_link(&"tutorial_tag", _on_tag)
	_link(&"tutorial_step_completed", _on_completed)
	_link(&"tutorial_card", _on_card)
	_link(&"tutorial_ack", _on_ack)
	_link(&"tutorial_finished", _on_finished)
	Events.beat.connect(_on_beat)
	Events.levelup_offer.connect(_on_levelup_offer)
	Events.levelup_chosen.connect(func(_c: Dictionary) -> void: _hide_ann(&"jeomji"))
	Events.trial_phase_changed.connect(_on_trial_phase)
	Events.geori_changed.connect(_on_geori)


## 거리 제목 카드(wave_presenter, y≈104~161, 게임 3초부터 3.2초)가 뜨는 동안 이름표는 아래 목표 띠 자리로 비킨다.
func _on_geori(_id: StringName, _bpm: float, _j: StringName) -> void:
	_geori_until = maxf(Game.time_sec(), GEORI_CARD_AT) + GEORI_CARD_SEC


func _link(sig: StringName, cb: Callable) -> void:
	if Events.has_signal(sig) and not Events.is_connected(sig, cb):
		Events.connect(sig, cb)


func _exit_tree() -> void:
	# 런 씬과 함께 사라질 때 우리가 건 멈춤을 남기지 않는다
	if _card_on:
		Game.pop_pause(&"tutorial_card")
	if _end_on:
		Game.pop_pause(&"tutorial_end")


# ─── 신호 ───────────────────────────────────────────────────────────────

func _on_started(from_step: StringName, total: int) -> void:
	_total = maxi(1, total)
	_lit.resize(_total)
	_skipped.resize(_total)
	_lit.fill(0)
	_skipped.fill(0)
	var fi: int = STEP_IDS.find(from_step)
	for i in maxi(fi, 0):
		if i < _total:
			_lit[i] = 1
	_started = true
	_banner_t = 0.0
	UiSettings.ui_sfx(&"sfx_ui_title_start")


func _on_step_started(step_id: StringName, index: int, total: int, goal_text: String, sub_text: String) -> void:
	if total != _total and total > 0:
		_total = total
		_lit.resize(_total)
		_skipped.resize(_total)
	if step_id != _cur_id:
		# 앞 단계가 완료 없이 넘어갔으면(건너뛰기) 그 등불은 꺼진 채 흐리게
		if _cur >= 0 and _cur < _total and _lit[_cur] == 0 and index > _cur:
			_skipped[_cur] = 1
		_cur = index
		_cur_id = step_id
		_done = 0
		_need = 0
		_line_t = 0.0
	_started = true
	_goal = goal_text
	_sub = UiKit.wrap(_f_small, UiKit.SZ_SMALL, sub_text, 360.0, 2)
	_line_t = minf(_line_t, 0.0)


func _on_progress(step_id: StringName, done: int, need: int) -> void:
	if step_id != _cur_id:
		return
	_done = done
	_need = need


func _on_help(step_id: StringName, _level: int, sub_text: String) -> void:
	if step_id != _cur_id:
		return
	if sub_text != "":
		_sub = UiKit.wrap(_f_small, UiKit.SZ_SMALL, sub_text, 360.0, 2)
	_help_flash = 0.3


func _on_tag(text: String, hanja: String, world_pos: Vector2) -> void:
	var k: int = 0
	var best: float = -1.0
	for i in 4:
		if _tag_t[i] > best:
			best = _tag_t[i]
			k = i
	_tag_text[k] = text
	_tag_hj[k] = hanja
	_tag_pos[k] = world_pos
	_tag_t[k] = 0.0


func _on_completed(step_id: StringName, name_label: String, hanja: String) -> void:
	var i: int = STEP_IDS.find(step_id)
	if i < 0:
		i = _cur
	if i >= 0 and i < _total:
		_lit[i] = 1
		_skipped[i] = 0
	_nl_text = name_label
	_nl_hanja = hanja
	# 시작 연출('연습 굿판')과 겹치지 않게 그 뒤에 띄운다
	_nl_t = minf(0.0, _banner_t - 1.9)
	UiSettings.ui_sfx(&"sfx_ui_card_select")
	UiSettings.ui_sfx(&"sfx_sys_deungbul")


func _on_card(step_id: StringName, card: Dictionary) -> void:
	var pages: Variant = card.get("pages", [])
	if not (pages is Array) or (pages as Array).is_empty():
		return
	_card_step = step_id
	_card_pages = pages
	_card_confirm = String(card.get("confirm", "Enter / A 다음"))
	_card_lines.clear()
	_card_tex.clear()
	_card_scale.clear()
	for pg: Variant in _card_pages:
		var d: Dictionary = pg if pg is Dictionary else {}
		var ls: PackedStringArray = PackedStringArray()
		var src: Variant = d.get("lines", [])
		if src is Array:
			for s: Variant in (src as Array):
				ls.append_array(UiKit.wrap(_f_body, UiKit.SZ_BODY, String(s), 392.0, 3))
		if ls.size() > 5:
			ls.resize(5)
		_card_lines.append(ls)
		var img: String = String(d.get("image", ""))
		var texs: Array = []
		var sc: int = 1
		if img.begins_with("sprite:"):
			texs = TutDraw.entity_frames(img.substr(7))
			sc = 2
		elif img != "":
			var t: Texture2D = SpriteLib.tex(img)
			if t != null:
				texs = [t]
		_card_tex.append(texs)
		_card_scale.append(sc)
	_card_page = 0
	_card_t = 0.0
	_card_on = true
	Game.push_pause(&"tutorial_card")
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_page_sfx()


func _page_sfx() -> void:
	var d: Dictionary = _card_pages[_card_page] if _card_pages[_card_page] is Dictionary else {}
	var sfx: String = String(d.get("sfx", ""))
	if sfx == "":
		sfx = "sfx_chaser_saja_eup" if _card_page == 0 else "sfx_ui_nav"
	UiSettings.ui_sfx(StringName(sfx))


func _on_ack(step_id: StringName) -> void:
	# 디렉터가 스스로 확인했거나(자동 테스트) 우리가 보낸 확인 — 카드를 닫는다
	if _card_on and step_id == _card_step:
		_close_card()


func _close_card() -> void:
	_card_on = false
	Game.pop_pause(&"tutorial_card")
	if not _end_on:
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _card_next() -> void:
	if _card_t < 0.7:   # 걷던 손으로 → 를 눌러 바로 넘기지 않게(읽을 틈)
		return
	if _card_page < _card_pages.size() - 1:
		_card_page += 1
		_card_t = 0.0
		_page_sfx()
		return
	var sid: StringName = _card_step
	_close_card()
	UiSettings.ui_sfx(&"sfx_ui_confirm")
	if Events.has_signal(&"tutorial_ack"):
		Events.emit_signal(&"tutorial_ack", sid)


func _on_finished(completed: bool) -> void:
	if not completed:
		return
	_end_on = true
	_end_t = 0.0
	_end_focus = 0
	_nl_t = 99.0
	_hide_ann(&"")
	Game.push_pause(&"tutorial_end")
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	UiSettings.ui_sfx(&"sfx_ui_unlock")


func _end_choose(i: int) -> void:
	if not _end_on or _end_t < 0.4:
		return
	_end_on = false
	Game.pop_pause(&"tutorial_end")
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSettings.ui_sfx(&"sfx_ui_confirm")
	if Events.has_signal(&"tutorial_exit_requested"):
		Events.emit_signal(&"tutorial_exit_requested", END_NEXT[clampi(i, 0, END_NEXT.size() - 1)])


func _on_beat(_i: int, down: bool) -> void:
	_beat_k = 1.0
	_beat_down = down


func _on_levelup_offer(_choices: Array) -> void:
	if _cur_id == &"jeomji":
		_show_ann(&"jeomji", ANN_JEOMJI)


func _on_trial_phase(_slot: int, _deity: StringName, phase: StringName) -> void:
	_trial_phase = phase
	# 빙의 점지는 단계와 상관없이 설명한다(시련 단계를 건너뛰면 'sal' 단계에 뜬다)
	if phase == &"jeomji":
		_show_ann(&"bingui", ANN_BINGUI)
	elif _cur_id == &"trial" or _ann_kind == &"bingui":
		_hide_ann(&"bingui")


func _show_ann(kind: StringName, lines: Array[String]) -> void:
	_ann.clear()
	for s: String in lines:
		_ann.append_array(UiKit.wrap(_f_small, UiKit.SZ_SMALL, s, 352.0, 2))
	_ann_kind = kind
	_ann_t = 0.0


func _hide_ann(kind: StringName) -> void:
	if kind == &"" or kind == _ann_kind:
		_ann.clear()
		_ann_kind = &""


# ─── 입력(멈춤 카드·끝 화면) ─────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (_card_on or _end_on) or Game.has_pause(&"menu"):
		return
	if event is InputEventJoypadMotion:
		return
	var handled: bool = true
	if _card_on:
		if event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept") \
				or event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
			_card_next()
		elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"cancel"):
			if _card_page > 0:
				_card_page -= 1
				_card_t = 0.0
				UiSettings.ui_sfx(&"sfx_ui_nav")
		elif event.is_action_pressed(&"pause"):
			pass     # 카드 위에서는 쉼 메뉴를 열지 않는다(카드가 먼저)
		else:
			handled = false
	else:
		if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left") \
				or event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
			_end_focus = (_end_focus - 1 + END_BTNS.size()) % END_BTNS.size()
			UiSettings.ui_sfx(&"sfx_ui_nav")
		elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right") \
				or event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
			_end_focus = (_end_focus + 1) % END_BTNS.size()
			UiSettings.ui_sfx(&"sfx_ui_nav")
		elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
			_end_choose(_end_focus)
		elif event.is_action_pressed(&"pause"):
			pass
		else:
			handled = false
	if handled:
		_view.get_viewport().set_input_as_handled()


func _on_view_input(event: InputEvent) -> void:
	if not (_card_on or _end_on):
		return
	if event is InputEventMouseMotion and _end_on:
		for i in END_BTNS.size():
			if _end_btn(i).has_point((event as InputEventMouseMotion).position):
				_end_focus = i
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = (event as InputEventMouseButton).position
		if _card_on:
			_card_next()
		else:
			for i in END_BTNS.size():
				if _end_btn(i).has_point(mp):
					_end_choose(i)
		_view.accept_event()


# ─── 프레임 ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_t += delta
	_banner_t += delta
	_line_t += delta
	_help_flash = maxf(0.0, _help_flash - delta)
	_beat_k = maxf(0.0, _beat_k - delta / 0.15)
	_nl_t += delta
	_ann_t += delta
	if _card_on:
		_card_t += delta
	if _end_on:
		_end_t += delta
	for i in 4:
		_tag_t[i] += delta
	# 아래 목표 묶음: 시뮬이 멈춘 동안(점지·쉼·카드)과 시작 연출 중엔 숨긴다
	var want: float = 1.0 if (_started and _goal != "" and not Game.is_sim_paused() and not _end_on and _banner_t > 1.2) else 0.0
	_lantern_a = move_toward(_lantern_a, want, delta / 0.15)
	# 가시성: 시련 중 이름표가 아래 자리를 쓰는 동안은 비켜 주고, 무당·귀신이 묶음 밑에 들어오면 옅어진다
	if _name_low() and _name_visible():
		want = 0.0
	elif want > 0.0 and _something_under():
		want = OCCLUDED_A
	_bottom_a = move_toward(_bottom_a, want, delta / 0.15)
	# 주석 안전망: 멈춤이 풀렸으면 닫는다
	if not _ann.is_empty() and _ann_t > 0.5 and not Game.is_sim_paused():
		_hide_ann(&"")
	_view.queue_redraw()


# ─── 그리기 ─────────────────────────────────────────────────────────────

func _draw_view() -> void:
	var ci: Control = _view
	var w: float = ci.size.x
	var h: float = ci.size.y
	var cx: float = roundf(w * 0.5)
	if Game.has_pause(&"menu") and not (_card_on or _end_on):
		return     # 쉼 메뉴(layer 20)·안내서 위로 연습 HUD(layer 24)를 겹쳐 그리지 않는다
	_draw_tags(ci)
	if _lantern_a > 0.0:
		_draw_lanterns(ci, cx, _lantern_a)
	if _bottom_a > 0.0:
		_draw_bottom(ci, cx, h, _bottom_a)
	_draw_name_label(ci, cx)
	if not _ann.is_empty() and not _card_on:
		_draw_ann(ci, cx)
	if _card_on:
		_draw_card(ci, cx, w, h)
	if _end_on:
		_draw_end(ci, cx, w, h)
	_draw_banner(ci, cx, w, h)


func _draw_banner(ci: Control, cx: float, w: float, h: float) -> void:
	if _banner_t >= 1.9:
		return
	var fade: float = clampf(1.0 - _banner_t / 0.6, 0.0, 1.0)
	if fade > 0.0:
		ci.draw_rect(Rect2(0, 0, w, h), Color(UiKit.MEOK, fade))
	var a: float = clampf(_banner_t / 0.2, 0.0, 1.0) * clampf((1.9 - _banner_t) / 0.3, 0.0, 1.0)
	if a <= 0.0:
		return
	# 거리 제목 카드(waves wave_presenter, y≈128~165)와 겹치지 않게 무당 발밑 아래(y 204~244)에 둔다
	ci.draw_rect(Rect2(0, 206, w, 40), Color(UiKit.MEOK, 0.55 * a))
	var bw: float = UiKit.text_outline(ci, _f_brush, 40, Vector2(cx, 238), "연습 굿판", Color(UiKit.HANJI_UI, a), 1, 2)
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(roundf(cx + bw * 0.5 + 8.0), 236), "練習", Color(UiKit.HWANG_HI, a))


## 시련 안내판(deities, 위 y 82~)이 떠 있는 동안 이름표는 아래 목표 띠 자리에 단다(무당 발밑을 덮지 않게).
func _name_low() -> bool:
	if Game.time_sec() < _geori_until:
		return true
	return not (_trial_phase == &"dormant" or _trial_phase == &"")


func _name_visible() -> bool:
	return _nl_text != "" and _nl_t >= 0.0 and _nl_t < NAME_IN + NAME_HOLD + NAME_OUT


## 아래 목표 묶음(화면 좌표) 밑에 무당이나 살아 있는 귀신이 있는가.
func _something_under() -> bool:
	var h: float = _view.size.y
	var cx: float = roundf(_view.size.x * 0.5)
	var r: Rect2 = Rect2(cx - 200.0, h - BAND_TOP - 8.0, 400.0, 56.0)
	var xf: Transform2D = _view.get_viewport().get_canvas_transform()
	var p: Node2D = Game.player
	if p != null and is_instance_valid(p) and r.grow(10.0).has_point(xf * p.global_position):
		return true
	var em: Node = Game.enemies
	if em == null or not is_instance_valid(em):
		return false
	var act: PackedInt32Array = em.get("active")
	var n: int = mini(int(em.get("active_count")), act.size())
	var ex: PackedFloat32Array = em.get("px")
	var ey: PackedFloat32Array = em.get("py")
	for k in mini(n, 64):
		var s: int = act[k]
		if s >= 0 and s < ex.size() and r.has_point(xf * Vector2(ex[s], ey[s])):
			return true
	return false


## 등불 줄(진행): hud 시계('연습') 양옆에 반씩 — 전투 자리·거리 이름 줄(y 28~37)·기운 바(y 42~52)를 덮지 않는다.
func _draw_lanterns(ci: Control, cx: float, a: float) -> void:
	var half: int = int(ceilf(float(_total) * 0.5))
	for i in _total:
		var x: float = cx + LANTERN_IN + float(i - half) * LANTERN_GAP
		if i < half:
			x = cx - LANTERN_IN - float(half - 1 - i) * LANTERN_GAP
		TutDraw.lantern(ci, Vector2(roundf(x), LANTERN_Y), _lit[i] == 1, i == _cur, _t, a, _skipped[i] == 1)


func _draw_bottom(ci: Control, cx: float, h: float, a: float) -> void:
	# 목표 줄(먹 띠 + 황 테)
	var k: float = clampf(_line_t / 0.25, 0.0, 1.0)
	var s: String = _goal
	if _need > 0:
		s = "%s (%d/%d)" % [_goal, mini(_done, _need), _need]
	var tw: float = _f_bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
	var bw: float = clampf(tw + 34.0, 200.0, 440.0)
	var band: Rect2 = Rect2(roundf(cx - bw * 0.5), h - BAND_TOP, bw, 16.0)
	ci.draw_rect(band, Color(UiKit.MEOK, 0.72 * a))
	ci.draw_rect(band, Color(UiKit.HWANG_DK.lerp(UiKit.HWANG, k), a), false, 1.0)
	UiKit.draw_corners(ci, band, Color(UiKit.JEOK_DK, a))
	# 박 장구 마름모(박 단계: 박 머리 = 황)
	var bc: Color = UiKit.HANJI_4
	if _cur_id == &"beat":
		bc = (UiKit.HWANG_HI if _beat_down else UiKit.HANJI_UI).lerp(UiKit.HANJI_4, 1.0 - _beat_k)
	UiKit.draw_diamond(ci, Vector2(band.position.x + 9, band.position.y + 8), 3.0 if _beat_k > 0.5 and _cur_id == &"beat" else 2.0, Color(bc, a))
	var ty: float = band.position.y + 12.0 + roundf((1.0 - k) * 3.0)
	var tx: float = roundf(band.position.x + 18.0 + (bw - 34.0 - tw) * 0.5)
	UiKit.text(ci, _f_bold, UiKit.SZ_BODY, Vector2(tx, ty), s, Color(UiKit.HANJI_UI, a * k))
	# 보조 줄(최대 2줄)
	var sc: Color = UiKit.HANJI_2
	if _help_flash > 0.0:
		sc = UiKit.HWANG_HI if fposmod(_help_flash, 0.1) < 0.06 else UiKit.HWANG
	var y: float = h - BAND_TOP + 28.0
	for ln: String in _sub:
		UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx, y), ln, Color(sc, a * k), 1)
		y += 12.0


func _draw_name_label(ci: Control, cx: float) -> void:
	if _nl_text == "" or _nl_t < 0.0 or _nl_t >= NAME_IN + NAME_HOLD + NAME_OUT:
		return
	if Game.is_sim_paused():
		return     # 점지·빙의 점지·카드 위로 겹치지 않는다
	var tin: float = clampf(_nl_t / NAME_IN, 0.0, 1.0)
	var tout: float = clampf((_nl_t - NAME_IN - NAME_HOLD) / NAME_OUT, 0.0, 1.0)
	var a: float = 1.0 - tout
	# 시련 안내판(deities, 위 y 82~)이 떠 있으면 아래 목표 띠 자리로 내린다(그동안 목표 묶음은 비켜 준다)
	var base_y: float = NAME_Y if not _name_low() else roundf(_view.size.y - BAND_TOP + 12.0)
	if _name_low():
		a *= 1.0 - _bottom_a     # 목표 묶음이 비켜 나가는 0.15초 동안은 같은 자리에 두 글이 겹치지 않게(11-26 캡처 01_move_z_name)
		if a <= 0.0:
			return
	var y: float = base_y - roundf(tout * 4.0)
	# 앞머리 ◆/○ 는 붓 글자 대신 무구 표지(붉은 마름모·흰 고리)로
	var label: String = _nl_text
	var mark: int = 0
	if label.begins_with("◆ "):
		mark = 1
		label = label.substr(2)
	elif label.begins_with("○ "):
		mark = 2
		label = label.substr(2)
	var tw: float = _f_brush.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x + (18.0 if mark > 0 else 0.0)
	# 먹 띠(번짐): 나갈 때 넓어지며 옅어진다
	var bw: float = tw + 80.0 + tout * 40.0
	ci.draw_rect(Rect2(roundf(cx - bw * 0.5), y - 30.0, roundf(bw), 40.0), Color(UiKit.MEOK, 0.5 * a))
	ci.draw_rect(Rect2(roundf(cx - bw * 0.5 + 6.0), y - 31.0, roundf(bw - 12.0), 1.0), Color(UiKit.HWANG_DK, 0.7 * a))
	ci.draw_rect(Rect2(roundf(cx - bw * 0.5 + 6.0), y + 10.0, roundf(bw - 12.0), 1.0), Color(UiKit.HWANG_DK, 0.7 * a))
	if _nl_hanja != "":
		UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx - 10.0, y - 33.0), _nl_hanja, Color(UiKit.HWANG_HI, a), 1)
	var shown: int = int(ceilf(float(label.length()) * tin))
	var x: float = roundf(cx - tw * 0.5 - 10.0)
	var lx: float = x
	if mark > 0 and a > 0.5:
		UiKit.draw_kind_mark(ci, Vector2(x + 6.0, y - 10.0), 5.0, mark == 2)
	if mark > 0:
		lx += 18.0
	TutDraw.brush_text(ci, _f_brush, 32, Vector2(lx, y), label.left(shown), Color(UiKit.HANJI_UI, a), 0, 2 + int(tout * 2.0))
	if tin >= 1.0:
		var sk: float = clampf((_nl_t - NAME_IN) / 0.15, 0.0, 1.0)
		TutDraw.seal(ci, Vector2(x + tw + 26.0, y - 10.0), sk, a, SEAL_GLYPH, _f_body)


func _draw_tags(ci: Control) -> void:
	var xf: Transform2D = ci.get_viewport().get_canvas_transform()
	for i in 4:
		if _tag_t[i] >= TAG_LIFE or _tag_text[i] == "":
			continue
		var tt: float = _tag_t[i]
		var a: float = clampf(tt / 0.1, 0.0, 1.0) * clampf((TAG_LIFE - tt) / 0.3, 0.0, 1.0)
		var p: Vector2 = (xf * _tag_pos[i]).round() - Vector2(0, 22.0 + roundf(tt * 8.0))
		var txt: String = _tag_text[i]
		var col: Color = UiKit.BAEK if (txt.contains("해원") or txt.contains("한꺼번에")) else UiKit.HANJI_UI
		# 가시성: '퇴치'·'해원' 은 타격 연출(hit_feedback → Juice.label)이 같은 자리에 이미 한글로 쓴다.
		# 글자가 두 겹으로 쌓이지 않게 한자 뜻풀이만 그 위에 단다(글자 표식을 끈 설정이면 한글도 그린다).
		if (txt == "퇴치" or txt == "해원") and _tag_hj[i] != "" and Juice.damage_number_mode != 2:
			UiKit.text_outline(ci, _f_small, UiKit.SZ_SMALL, Vector2(p.x, p.y - 34.0), _tag_hj[i], Color(UiKit.HWANG_HI, a), 1, 1)
			continue
		if _tag_hj[i] != "":
			UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(p.x, p.y - 16.0), _tag_hj[i], Color(UiKit.HWANG_HI, a), 1)
		UiKit.text_outline(ci, _f_brush, 16, p, txt, Color(col, a), 1, 2)


func _draw_ann(ci: Control, cx: float) -> void:
	var a: float = clampf(_ann_t / 0.2, 0.0, 1.0)
	# 점지 제목(點 指, y≈31~)과 겹치지 않게 위 2~28 안에 둔다
	var hh: float = 6.0 + float(_ann.size()) * 11.0
	var r: Rect2 = Rect2(cx - 180.0, 1.0, 360.0, hh)
	UiKit.draw_hanji_panel(ci, r, _paper)
	if a < 1.0:
		ci.draw_rect(r, Color(UiKit.MEOK, 1.0 - a))
	var y: float = r.position.y + 12.0
	for ln: String in _ann:
		var lw: float = _f_small.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
		ci.draw_string(_f_small, Vector2(roundf(cx - lw * 0.5), y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.INK, a))
		y += 11.0


func _card_rect(w: float, h: float) -> Rect2:
	return Rect2(roundf(w * 0.5 - 210.0), roundf(h * 0.5 - 124.0), 420, 248)


func _draw_card(ci: Control, cx: float, w: float, h: float) -> void:
	var a: float = clampf(_card_t / 0.2, 0.0, 1.0)
	ci.draw_rect(Rect2(0, 0, w, h), Color(UiKit.MEOK, 0.7))
	var p: Rect2 = _card_rect(w, h)
	UiKit.draw_hanji_panel(ci, p, _paper)
	var pg: Dictionary = _card_pages[_card_page] if _card_pages[_card_page] is Dictionary else {}
	# 그림 칸(가운데 잘라 1배 / 스프라이트 2배 idle)
	var ib: Rect2 = Rect2(p.position.x + 10, p.position.y + 10, p.size.x - 20, 120)
	ci.draw_rect(ib.grow(1.0), UiKit.HANJI_4)
	ci.draw_rect(ib, UiKit.MEOK_1)
	var texs: Array = _card_tex[_card_page] if _card_page < _card_tex.size() else []
	if not texs.is_empty():
		var tex: Texture2D = texs[int(_t * 6.0) % texs.size()]
		var sc: int = _card_scale[_card_page]
		var ts: Vector2 = tex.get_size() * float(sc)
		if ts.x <= ib.size.x and ts.y <= ib.size.y:
			ci.draw_texture_rect(tex, Rect2((ib.get_center() - ts * 0.5).round(), ts), false, Color(1, 1, 1, a))
		else:
			var src_sz: Vector2 = Vector2(minf(tex.get_size().x, ib.size.x / float(sc)), minf(tex.get_size().y, ib.size.y / float(sc)))
			var src: Rect2 = Rect2(((tex.get_size() - src_sz) * 0.5).round(), src_sz)
			var dst_sz: Vector2 = src_sz * float(sc)
			ci.draw_texture_rect_region(tex, Rect2((ib.get_center() - dst_sz * 0.5).round(), dst_sz), src, Color(1, 1, 1, a))
	# 제목(붓) + 문장
	UiKit.text_outline(ci, _f_brush, 26, Vector2(cx, p.position.y + 156.0), String(pg.get("title", "")), Color(UiKit.INK, a), 1, 0)
	var y: float = p.position.y + 176.0
	var ls: PackedStringArray = _card_lines[_card_page] if _card_page < _card_lines.size() else PackedStringArray()
	for ln: String in ls:
		var lw: float = _f_body.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		ci.draw_string(_f_body, Vector2(roundf(cx - lw * 0.5), y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, Color(UiKit.INK, a))
		y += 14.0
	# 아래: 쪽 · 확인
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(p.position.x + 12, p.end.y - 8), "%d / %d" % [_card_page + 1, _card_pages.size()], UiKit.HANJI_5, 0, false)
	var blink: float = 0.6 + 0.4 * sin(_t * 5.0)
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(p.end.x - 12, p.end.y - 8), _card_confirm, Color(UiKit.JEOK_DK, blink), 2, false)


func _end_rect(w: float, h: float) -> Rect2:
	return Rect2(roundf(w * 0.5 - 230.0), roundf(h * 0.5 - 125.0), 460, 250)


func _end_btn(i: int) -> Rect2:
	var p: Rect2 = _end_rect(_view.size.x, _view.size.y)
	var ws: Array[float] = [136.0, 100.0, 100.0]
	var gap: float = 10.0
	var tot: float = ws[0] + ws[1] + ws[2] + gap * 2.0
	var x: float = roundf(p.get_center().x - tot * 0.5)
	for k in i:
		x += ws[k] + gap
	return Rect2(x, p.position.y + 178.0, ws[i], 22.0)


func _draw_end(ci: Control, cx: float, w: float, h: float) -> void:
	var a: float = clampf(_end_t / 0.3, 0.0, 1.0)
	ci.draw_rect(Rect2(0, 0, w, h), Color(UiKit.MEOK, 0.75 * a))
	var p: Rect2 = _end_rect(w, h)
	p.position.y += roundf((1.0 - UiKit.ease_out_cubic(a)) * 10.0)
	UiKit.draw_hanji_panel(ci, p, _paper)
	var title: String = "연습 굿판을 마쳤습니다"
	var tw: float = _f_brush.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var tx: float = roundf(cx - tw * 0.5 - 14.0)
	UiKit.text_outline(ci, _f_brush, 32, Vector2(tx, p.position.y + 38.0), title, UiKit.INK, 0, 0)
	TutDraw.seal(ci, Vector2(tx + tw + 20.0, p.position.y + 26.0), clampf((_end_t - 0.3) / 0.15, 0.0, 1.0), clampf((_end_t - 0.3) / 0.05, 0.0, 1.0), SEAL_GLYPH, _f_body)
	UiKit.draw_dancheong(ci, Rect2(p.position.x + 40, p.position.y + 48, p.size.x - 80, 3))
	# 등불 줄(마친 단계)
	var lx0: float = roundf(cx - float(_total - 1) * LANTERN_GAP * 0.5)
	for i in _total:
		TutDraw.lantern(ci, Vector2(lx0 + float(i) * LANTERN_GAP, p.position.y + 66.0), _lit[i] == 1, false, _t, 1.0, _skipped[i] == 1)
	# 배운 것 세 줄
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(p.position.x + 70, p.position.y + 92.0), "배운 것", UiKit.HANJI_5, 0, false)
	for i in END_LINES.size():
		var ly: float = p.position.y + 112.0 + float(i) * 20.0
		var la: float = clampf((_end_t - 0.4 - float(i) * 0.15) / 0.2, 0.0, 1.0)
		TutDraw.lantern(ci, Vector2(p.position.x + 76, ly - 4.0), true, false, _t, la)
		_draw_marked(ci, Vector2(p.position.x + 90, ly), END_LINES[i], Color(UiKit.INK, la))
	# 버튼
	for i in END_BTNS.size():
		var r: Rect2 = _end_btn(i)
		var foc: bool = i == _end_focus
		var pulse: bool = foc and fposmod(_t, 1.0) < 0.5
		UiKit.draw_meok_panel(ci, r, 0.95, foc, UiKit.HWANG if pulse else (UiKit.HWANG_DK if foc else UiKit.HANJI_5))
		UiKit.text(ci, _f_bold, UiKit.SZ_BODY, Vector2(r.get_center().x + (4.0 if foc else 0.0), r.position.y + 15.0), END_BTNS[i], UiKit.HWANG_HI if foc else UiKit.HANJI, 1)
		if foc:
			UiKit.draw_diamond(ci, Vector2(r.position.x + 8, r.position.y + 11), 2.0, UiKit.JEOK)
	UiKit.text(ci, _f_small, UiKit.SZ_SMALL, Vector2(cx, p.end.y - 12.0), "더 알고 싶으면 쉼 메뉴(Esc) → 굿 안내서", UiKit.HANJI_5, 1, false)


## ◆/○ 기호를 무구 표지(마름모·고리)로 바꿔 그린다
func _draw_marked(ci: Control, pos: Vector2, s: String, col: Color) -> void:
	var x: float = pos.x
	var seg: String = ""
	for ch: String in s:
		if ch == "◆" or ch == "○":
			if seg != "":
				ci.draw_string(_f_body, Vector2(x, pos.y), seg, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, col)
				x += _f_body.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
				seg = ""
			if col.a > 0.6:
				UiKit.draw_kind_mark(ci, Vector2(x + 4.0, pos.y - 4.0), 3.0, ch == "○")
			x += 10.0
		else:
			seg += ch
	if seg != "":
		ci.draw_string(_f_body, Vector2(x, pos.y), seg, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, col)
