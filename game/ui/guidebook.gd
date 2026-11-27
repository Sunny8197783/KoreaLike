class_name Guidebook
extends Control
## 굿 안내서(도움말 8쪽, design/17 §6). 소유: ui(intro_ui).
## 열기: 타이틀 '길잡이 → 굿 안내서', 쉼 메뉴 '굿 안내서'(쉼 메뉴의 자식, 닫으면 쉼 메뉴로).
## 조작: ← → · A D · D-패드 좌우 · 마우스(◀ ▶) = 쪽 넘김 / 1~8 = 바로 그 쪽 / Esc · Backspace · B = 닫기.
## 수치는 Data 에서 읽는다(시련 시각·합일·길베 초·영가 수명·살기 문턱·풀릴 기색 문턱·중간보스·작두·뒷전·보스 시각).
## 공개: open(page), close(), signal closed. --guidebook-test=<1..8|all> 은 title 이 연다.

signal closed

## design/19 §2: 화면 말은 쉬운 말. 무속 이름은 8쪽 '낱말 풀이'에 작은 보조로만 둔다(쪽 수 8 유지 — 성장·신당을 한 쪽으로 합침).
const PAGE_IDS: Array[String] = ["gb_controls", "gb_flow", "gb_weapons", "gb_haewon", "gb_trial", "gb_sal", "gb_growth", "gb_words"]
const TITLES: Array[String] = ["조작", "목표와 한 판 흐름", "붉은 무기 · 흰 무기", "풀어 주기 · 넋 동무 · 흰 길",
	"신령의 시험", "원한과 성난 귀신", "성장과 신당", "낱말 풀이"]
## 낱말 풀이: [쉬운 말, 무속 이름(보조), 뜻 한 줄]
const WORDS: Array = [
	["처치", "퇴치", "붉은 무기로 베어 없앰"],
	["풀어 줌", "해원", "흰 무기로 한을 풀어 보냄"],
	["흰 테두리", "풀릴 기색", "이제 풀어 줄 수 있는 귀신"],
	["넋 동무", "영가", "풀린 넋. 뒤따르며 지켜 줌"],
	["넋 동무가 떠남", "천도", "때가 되면 저승길로 감"],
	["흰 길", "길베", "걸은 자리에 잠시 남는 길"],
	["한꺼번에 풀림", "길닦음", "흰 길로 한 바퀴 감쌈"],
	["원한", "살", "처치한 자리에 남는 검은 기운"],
	["성난 귀신", "원귀", "원한이 쌓여 돌아온 귀신"],
	["새 힘 고르기", "점지", "구슬이 차면 카드 한 장"],
	["신령의 시험", "시련", "3:00부터 네 번 온다"],
	["싸움 · 모심", "위엄 · 가호", "시험을 넘는 두 길"],
	["신령의 힘", "빙의", "시험을 넘으면 받는 힘"],
	["신령 모두 내림", "합일", "18:00, 모신 신령이 함께"],
	["역병 귀신 역려", "역려", "20:00에 오는 마지막 귀신"],
	["공덕 · 엽전", "복전", "신당에서 쓰는 것"],
]
const TEXT_W: float = 330.0
const TEST_STEP: float = 1.2

var page: int = 0
var _t: float = 0.0
var _slide: float = 0.0            # 1 → 0 (쪽 넘김 0.2초)
var _slide_dir: float = 1.0
var _test_all: bool = false
var _test_t: float = 0.0
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_tiny: Font
var _f_brush: Font
var _paper: Texture2D
var _bodies: Array = []            # 쪽마다 [ [줄 사전...] (글머리 하나) , ... ]
var _cap: PackedStringArray = PackedStringArray()   # 쪽마다 그림 아래 한 줄
var _timeline: Array[Dictionary] = []                # 2쪽 띠: {t, label, kind}
var _img: Dictionary = {}          # 그림 캐시(열 때 한 번)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	UiKit.setup_fonts()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")
	_build_text()


static func _mmss(sec: float) -> String:
	return K.fmt_time(sec)


func _build_text() -> void:
	var tt: Variant = Data.get_value("deities", "constants.trial_times_s", [180, 390, 750, 930])
	var trials: Array = tt if tt is Array else [180, 390, 750, 930]
	var hapil: float = Data.num("deities", "constants.hapil_time_s", 1080.0)
	var gilbe: float = Data.num("combat_core", "gilbe.duration_base", 4.0)
	var sumyeong: float = Data.num("characters", "stat_base.stat_neok_sumyeong", 30.0)
	var st: Variant = Data.get_value("combat_core", "salgi.thresholds", [25, 50, 75])
	var sal_th: Array = st if st is Array else [25, 50, 75]
	var giseak: float = Data.num("combat_core", "han.giseak_threshold", 0.35)
	var mboss: float = Data.num("waves_stage1", "midboss.time_sec", 600.0)
	var jakdu: float = Data.num("waves_stage1", "jakdu_ganglim.start_sec", 1115.0)
	var boss: float = Data.num("waves_stage1", "boss_time_sec", 1200.0)
	var dwit: float = float(UiKit.geori_def(&"geori_dwitjeon").get("start_sec", 1155.0))
	var trial_s: PackedStringArray = PackedStringArray()
	for v: Variant in trials:
		trial_s.append(_mmss(float(v)))
	var sal_s: PackedStringArray = PackedStringArray()
	for v: Variant in sal_th:
		sal_s.append(str(int(v)))
	var minutes: int = int(roundf(boss / 60.0))
	var src: Array = [
		# 1 조작
		["걷기: **WASD · 방향키** / 패드 **왼쪽 스틱 · D-패드**",
			"공격은 모두 저절로. 하는 일은 **어디로 걷느냐** 하나",
			"쉼: **Esc · P** / 패드 **Start**",
			"새 힘 고르기: **1 · 2 · 3** 또는 **← →** + **Enter** / 패드 **D-패드 + A**",
			"전체 화면: **Alt+Enter · F11**"],
		# 2 흐름
		["목표: **%s까지 버티고, 마지막에 오는 역병 귀신 역려를 보낸다**" % _mmss(boss),
			"**신령의 시험**이 네 번 온다(%s)" % " · ".join(trial_s),
			"%s **큰 귀신**, %s 모신 신령이 **모두 내려온다**" % [_mmss(mboss), _mmss(hapil)],
			"%s **역려**를 보내면 굿이 끝나고, 얻은 것으로 **신당**을 키운다" % _mmss(boss),
			"시간이 갈수록 귀신이 많아지고 빨라진다"],
		# 3 무기
		["◆ **붉은 무기**는 귀신을 베어 **처치**한다. 구슬이 많이 나온다",
			"약해진 귀신(남은 힘 %d%% 아래)에는 **흰 테두리**가 생긴다" % int(roundf(giseak * 100.0)),
			"흰 테두리 귀신은 붉은 칼로 **못 없앤다** — 칼날이 튕긴다",
			"○ **흰 무기**를 가까이 대면 흰 테두리 귀신이 **풀린다**",
			"드물게 치명타는 흰 테두리도 단칼에 끊는다"],
		# 4 풀어 주기·넋 동무·흰 길
		["풀린 넋은 **넋 동무**가 되어 뒤를 따른다(%d초, 곁의 귀신을 막음)" % int(sumyeong),
			"때가 되면 저승길로 **떠난다**. 넋 동무가 많으면 대신 맞아 주기도 한다",
			"걸은 자리에 **흰 길**이 %d초 남는다" % int(gilbe),
			"흰 길로 한 바퀴 감싸면 **한꺼번에 풀림**: 안쪽 흰 테두리 귀신과 반쯤 약해진 귀신이 함께 풀린다",
			"감쌀 수 있으면 점선과 매듭 표시가 뜬다"],
		# 5 신령의 시험
		["신령 둘이 원으로 내려온다. **들어가는 원이 곧 선택**",
			"◆ **싸움**: 큰 신령 곁에서 무기로 친다 / ○ **모심**: 안내판의 과제를 한다",
			"먼저 찬 쪽으로 넘는다. 흰 줄 밖에 있으면 절반만 찬다",
			"넘으면 **신령의 힘**을 하나 고른다. 받은 힘은 그 판 끝까지 간다",
			"%s 모신 신령이 **모두 내려와** 함께 싸운다" % _mmss(hapil)],
		# 6 원한
		["처치한 자리에 검은 **원한 알갱이**가 남는다",
			"원한이 %s만큼 쌓이면 알갱이가 뭉쳐 **성난 귀신**으로 돌아온다" % " · ".join(sal_s),
			"알갱이를 밟아 거두거나, 흰 길·소금으로 씻을 수 있다",
			"위 **풀어 줌 · 처치** 바: 풀어 준 만큼 한지빛, 벤 만큼 먹빛. %s 역려의 얼굴이 여기서 정해진다" % _mmss(boss),
			"어느 쪽으로 가도 끝까지 갈 수 있다"],
		# 7 성장과 신당
		["구슬이 차면 **새 힘 고르기**: 카드 하나(◆ 붉은 띠 / ○ 흰 띠 / 아이템)",
			"무기 6칸, 아이템 6칸",
			"**진화**: 무기 Lv8 + 진화 짝 아이템 → 강한 귀신이 남긴 상자를 열 때",
			"판이 끝나면(쓰러져도) 풀어 준 넋은 **공덕**, 모은 엽전은 **엽전**으로 남는다",
			"**신당**에서 힘을 키우고 새 무기·새 무당을 열어 다음 굿을 연다"],
		# 8 낱말 풀이(표로 그린다 — 글머리 없음)
		[],
	]
	_bodies.clear()
	for pg: Variant in src:
		var bl: Array = []
		for s: Variant in (pg as Array):
			bl.append(TutDraw.rich_wrap(_f_body, UiKit.SZ_BODY, String(s), TEXT_W - 14.0, 4))
		_bodies.append(bl)
	_cap = PackedStringArray(["걷기만으로 싸운다", "%d분 굿 한 판" % minutes, "베고(◆) 풀어 준다(○)",
		"넋 동무 · 한 바퀴 감싸기", "시험 %s" % " · ".join(trial_s), "원한 알갱이 → 성난 귀신",
		"신칼 → 신장칼(진화)", ""])
	# 2쪽 띠(시각 순)
	_timeline = [{"t": 0.0, "label": "시작", "kind": 0}]
	for v: Variant in trials:
		_timeline.append({"t": float(v), "label": "신령의 시험", "kind": 1})
	_timeline.append({"t": mboss, "label": "큰 귀신", "kind": 2})
	_timeline.append({"t": hapil, "label": "신령 모두 내림", "kind": 1})
	_timeline.append({"t": jakdu, "label": "작두", "kind": 2})
	_timeline.append({"t": dwit, "label": "배웅", "kind": 0})
	_timeline.append({"t": boss, "label": "역병 귀신 역려", "kind": 3})
	_timeline.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))


func _load_images() -> void:
	if not _img.is_empty():
		return
	_img["mansin_walk"] = TutDraw.entity_frames("char_mansin", "walk")
	_img["ico_jing"] = SpriteLib.tex("res://ui/icons/ico_jing_16.png")
	_img["wpn_sinkal"] = UiKit.weapon_icon("wpn_sinkal")
	_img["wpn_bangul"] = UiKit.weapon_icon("wpn_bangul")
	_img["evo"] = UiKit.weapon_icon("evo_sinjangkal")
	var dal: Array[Texture2D] = TutDraw.entity_frames("enm_dalgyal_gwisin")
	_img["dalgyal"] = dal[0] if not dal.is_empty() else null
	_img["dalgyal_pullil"] = TutDraw.outlined(dal[0], UiKit.BAEK) if not dal.is_empty() else null
	_img["knot"] = TutDraw.sheet_frame("res://assets/vfx/vfx_maetim_knot.png", 0)
	_img["yg_f"] = TutDraw.entity_frames("yeongga_body_f", "walk")
	_img["yg_m"] = TutDraw.entity_frames("yeongga_body_m", "walk")
	_img["gil_knot"] = TutDraw.sheet_frame("res://assets/vfx/vfx_gildakkeum_knot.png", 0)
	_img["sansin"] = TutDraw.entity_frames("avatar_sansin")
	_img["ring"] = TutDraw.sheet_frame("res://assets/vfx/vfx_confirm_ring_sansin.png", 0)
	_img["sal"] = TutDraw.sheet_frame("res://assets/vfx/vfx_sal_grain_idle.png", 0)
	var wn: int = TutDraw.sheet_count("res://assets/vfx/vfx_wongwi_form.png")
	_img["wongwi"] = TutDraw.sheet_frame("res://assets/vfx/vfx_wongwi_form.png", mini(8, wn - 1))   # 다 뭉친 원귀 칸
	_img["box"] = TutDraw.sheet_frame("res://assets/vfx/vfx_box_gilhyung_open.png", 0)
	_img["saja"] = TutDraw.entity_frames("chaser_jeoseung_saja")
	var sd: Texture2D = SpriteLib.tex("res://ui/art/intro/intro_sindang.png")
	if sd != null:
		var at: AtlasTexture = AtlasTexture.new()
		at.atlas = sd
		at.region = Rect2(86, 40, 172, 120)
		_img["sindang"] = at


func open(p: int = 0) -> void:
	_load_images()
	visible = true
	page = clampi(p, 0, PAGE_IDS.size() - 1)
	_t = 0.0
	_slide = 0.0
	_log_page()
	UiSettings.ui_sfx(&"sfx_ui_nav")
	queue_redraw()


## --guidebook-test=all: 1.2초마다 넘겨 8쪽 뒤 닫는다
func open_test_all() -> void:
	_test_all = true
	_test_t = 0.0
	open(0)


func close() -> void:
	if not visible:
		return
	visible = false
	_test_all = false
	UiSettings.ui_sfx(&"sfx_ui_back")
	closed.emit()


func _log_page() -> void:
	if Game.autotest or DebugTools.args.has("guidebook-test"):
		print("[guidebook] page=%d/%d id=%s" % [page + 1, PAGE_IDS.size(), PAGE_IDS[page]])


func goto_page(p: int) -> void:
	var np: int = clampi(p, 0, PAGE_IDS.size() - 1)
	if np == page:
		return
	_slide_dir = 1.0 if np > page else -1.0
	_slide = 1.0
	page = np
	_t = 0.0
	_log_page()
	UiSettings.ui_sfx(&"sfx_ui_nav")
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_slide = maxf(0.0, _slide - delta / 0.2)
	if _test_all:
		_test_t += delta
		if _test_t >= TEST_STEP:
			_test_t = 0.0
			if page >= PAGE_IDS.size() - 1:
				close()
				return
			goto_page(page + 1)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventJoypadMotion:
		return
	var handled: bool = true
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		goto_page(page - 1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		goto_page(page + 1)
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
		close()
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		if page >= PAGE_IDS.size() - 1:
			close()
		else:
			goto_page(page + 1)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode >= KEY_1 and (event as InputEventKey).physical_keycode <= KEY_8:
		goto_page(int((event as InputEventKey).physical_keycode - KEY_1))
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _arrow_rect(-1).has_point(mb.position):
				goto_page(page - 1)
			elif _arrow_rect(1).has_point(mb.position):
				goto_page(page + 1)
			elif _close_rect().has_point(mb.position) or not _panel().has_point(mb.position):
				close()
			else:
				for i in PAGE_IDS.size():
					if _tab_rect(i).grow(2.0).has_point(mb.position):
						goto_page(i)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			goto_page(page + 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			goto_page(page - 1)
		accept_event()


# ─── 배치 ───────────────────────────────────────────────────────────────

func _panel() -> Rect2:
	return Rect2(roundf(size.x * 0.5 - 300.0), roundf(size.y * 0.5 - 162.0), 600, 324)


func _img_rect() -> Rect2:
	var p: Rect2 = _panel()
	return Rect2(p.position.x + 14, p.position.y + 50, 220, 200)


func _arrow_rect(dir: int) -> Rect2:
	var p: Rect2 = _panel()
	if dir < 0:
		return Rect2(p.position.x + 12, p.end.y - 40, 60, 16)
	return Rect2(p.end.x - 72, p.end.y - 40, 60, 16)


func _tab_rect(i: int) -> Rect2:
	var p: Rect2 = _panel()
	var x0: float = roundf(p.get_center().x - float(PAGE_IDS.size()) * 7.0)
	return Rect2(x0 + float(i) * 14.0, p.end.y - 37, 10, 10)


func _close_rect() -> Rect2:
	var p: Rect2 = _panel()
	return Rect2(p.end.x - 22, p.position.y + 6, 16, 16)


# ─── 그리기 ─────────────────────────────────────────────────────────────

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(0, 0, w, h), Color(UiKit.MEOK, 0.82))
	var p: Rect2 = _panel()
	UiKit.draw_hanji_panel(self, p, _paper)
	var ink: Color = UiKit.INK
	# 쪽 넘김 슬라이드(내용만)
	var off: float = roundf(_slide * 18.0 * _slide_dir)
	var ca: float = 1.0 - _slide * 0.8
	# 위: 붓 제목 + 쪽 번호
	TutDraw.brush_text(self, _f_brush, 28, Vector2(p.position.x + 18 + off, p.position.y + 32), TITLES[page], Color(ink, ca), 0, 0)
	UiKit.text(self, _f_bold, UiKit.SZ_BODY, Vector2(p.end.x - 30, p.position.y + 20), "%d / %d" % [page + 1, PAGE_IDS.size()], UiKit.HANJI_5, 2, false)
	# 닫기 ×
	var cr: Rect2 = _close_rect()
	draw_rect(cr, UiKit.MEOK_2)
	draw_rect(cr, UiKit.HANJI_4, false, 1.0)
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cr.get_center().x, cr.position.y + 12), "×", UiKit.HANJI, 1, false)
	UiKit.draw_dancheong(self, Rect2(p.position.x + 14, p.position.y + 40, p.size.x - 28, 3))
	if PAGE_IDS[page] == "gb_words":
		_draw_words(p, off, ca)
	else:
		_draw_page_body(p, off, ca)
	_draw_footer(p)


## 낱말 풀이(8쪽): 쉬운 말(굵게) · 무속 이름(작은 보조) · 뜻 — 두 단
func _draw_words(p: Rect2, off: float, ca: float) -> void:
	var ink: Color = UiKit.INK
	var x0: float = p.position.x + 22.0 + off
	var y0: float = p.position.y + 62.0
	var colw: float = (p.size.x - 44.0) * 0.5
	var rows: int = int(ceilf(float(WORDS.size()) * 0.5))
	for i in WORDS.size():
		var w: Array = WORDS[i]
		var cx0: float = x0 + (colw if i >= rows else 0.0)
		var y: float = y0 + float(i % rows) * 26.0
		UiKit.draw_diamond(self, Vector2(cx0 + 3, y - 4), 2.0, Color(UiKit.JEOK_DK, ca))
		UiKit.text(self, _f_bold, UiKit.SZ_BODY, Vector2(cx0 + 10, y), String(w[0]), Color(ink, ca), 0, false)
		var bw: float = _f_bold.get_string_size(String(w[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx0 + 16 + bw, y), String(w[1]), Color(UiKit.HANJI_5, ca), 0, false)
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx0 + 10, y + 12), String(w[2]), Color(UiKit.HANJI_5, ca), 0, false)
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(p.get_center().x, p.end.y - 48), "굵은 글씨 = 게임 화면의 말 · 옅은 글씨 = 무속에서 부르는 이름", Color(UiKit.HANJI_5, ca), 1, false)


func _draw_page_body(p: Rect2, off: float, ca: float) -> void:
	var ink: Color = UiKit.INK
	# 그림 칸
	var ir: Rect2 = _img_rect()
	ir.position.x += off
	draw_rect(ir.grow(1.0), Color(UiKit.HANJI_4, ca))
	# 그림 칸 바탕: 먹(어두운 원귀 쪽은 흙빛으로 밝혀 보이게)
	draw_rect(ir, Color(UiKit.HANJI_4 if PAGE_IDS[page] == "gb_sal" else UiKit.MEOK_1, ca))
	_draw_image(PAGE_IDS[page], ir, ca)
	if page < _cap.size():
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(ir.get_center().x, ir.end.y + 14), _cap[page], Color(UiKit.HANJI_5, ca), 1, false)
	# 글 칸
	var x0: float = p.position.x + 250.0 + off
	var y: float = p.position.y + 64.0
	var bl: Array = _bodies[page]
	for bullet: Variant in bl:
		var first: bool = true
		for ln: Variant in (bullet as Array):
			if first:
				UiKit.draw_diamond(self, Vector2(x0 + 3, y - 4), 2.0, Color(UiKit.JEOK_DK, ca))
				first = false
			TutDraw.rich_line(self, _f_body, _f_bold, UiKit.SZ_BODY, Vector2(x0 + 10, y), ln, Color(ink, ca), Color(UiKit.JEOK_DK, ca))
			y += 15.0
		y += 6.0


func _draw_footer(p: Rect2) -> void:
	# 아래: ◀ 쪽 점 ▶ + 조작 안내(키보드 · 패드)
	var lc: Color = UiKit.INK if page > 0 else UiKit.HANJI_3
	var rc: Color = UiKit.INK if page < PAGE_IDS.size() - 1 else UiKit.HANJI_3
	var ar: Rect2 = _arrow_rect(-1)
	UiKit.text(self, _f_body, UiKit.SZ_BODY, ar.position + Vector2(0, 12), "◀ 이전", lc, 0, false)
	var br: Rect2 = _arrow_rect(1)
	UiKit.text(self, _f_body, UiKit.SZ_BODY, Vector2(br.end.x, br.position.y + 12), "다음 ▶", rc, 2, false)
	for i in PAGE_IDS.size():
		var tr: Rect2 = _tab_rect(i)
		if i == page:
			UiKit.draw_diamond(self, tr.get_center(), 4.0, UiKit.JEOK)
		else:
			UiKit.draw_diamond(self, tr.get_center(), 3.0, UiKit.HANJI_4, false)
	draw_rect(Rect2(p.position.x + 14, p.end.y - 22, p.size.x - 28, 1), UiKit.HANJI_3)
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(p.get_center().x, p.end.y - 9),
		"← → 쪽 넘기기 · 1~8 바로 가기 · Esc 닫기     패드: D-패드 쪽 넘기기 · B 닫기", UiKit.HANJI_5, 1, false)


func _anim(key: String, fps: float = 6.0) -> Texture2D:
	var fr: Variant = _img.get(key, [])
	if fr is Array and not (fr as Array).is_empty():
		var arr: Array = fr
		return arr[int(_t * fps) % arr.size()]
	return null


func _blit(tex: Texture2D, c: Vector2, sc: int, a: float, flip: bool = false) -> Rect2:
	if tex == null:
		return Rect2(c, Vector2.ZERO)
	var s: Vector2 = tex.get_size() * float(sc)
	var r: Rect2 = Rect2((c - s * 0.5).round(), s)
	if flip:
		draw_texture_rect(tex, Rect2(r.position + Vector2(r.size.x, 0), Vector2(-r.size.x, r.size.y)), false, Color(1, 1, 1, a))
	else:
		draw_texture_rect(tex, r, false, Color(1, 1, 1, a))
	return r


## 쪽 그림(기존 스프라이트·이펙트 첫 칸·코드 드로잉)
func _draw_image(id: String, r: Rect2, a: float) -> void:
	var c: Vector2 = r.get_center()
	var lab: Color = Color(UiKit.HANJI_2, a)
	match id:
		"gb_controls":
			_blit(_anim("mansin_walk", 8.0), c + Vector2(0, -38), 2, a)
			# 키 모양(코드): W A S D + 방향키
			var k0: Vector2 = Vector2(r.position.x + 30, r.end.y - 70)
			_key(k0 + Vector2(18, 0), "W", a)
			_key(k0 + Vector2(0, 18), "A", a)
			_key(k0 + Vector2(18, 18), "S", a)
			_key(k0 + Vector2(36, 18), "D", a)
			var k1: Vector2 = Vector2(r.position.x + 128, r.end.y - 70)
			_key(k1 + Vector2(18, 0), "↑", a)
			_key(k1 + Vector2(0, 18), "←", a)
			_key(k1 + Vector2(18, 18), "↓", a)
			_key(k1 + Vector2(36, 18), "→", a)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(c.x, r.end.y - 12), "걷기 = 모든 조작", lab, 1)
		"gb_flow":
			_draw_timeline(r, a)
		"gb_weapons":
			var y0: float = r.position.y + 34.0
			var tl: Texture2D = _img.get("wpn_sinkal")
			var tr: Texture2D = _img.get("wpn_bangul")
			_icon_box(Vector2(r.position.x + 56, y0), tl, false, "베기", a)
			_icon_box(Vector2(r.end.x - 56, y0), tr, true, "풀기", a)
			# 달걀귀신(맺힘) → 흰 테두리(풀릴 기색) + 매듭
			var yy: float = r.position.y + 128.0
			_blit(_img.get("dalgyal"), Vector2(r.position.x + 56, yy), 2, a)
			UiKit.text(self, _f_body, UiKit.SZ_BODY, Vector2(c.x, yy + 4), "→", lab, 1)
			_blit(_img.get("dalgyal_pullil"), Vector2(r.end.x - 60, yy), 2, a)
			var kr: Rect2 = _blit(_img.get("knot"), Vector2(r.end.x - 24, yy - 30), 2, a)
			if kr.size.x > 0.0:
				# 이름 없는 회색 X 는 '닫기·오류'로 읽혔다(리뷰 11-25) — 매듭이라고 단다
				UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(kr.get_center().x, kr.end.y + 9.0), "매듭", lab, 1)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.position.x + 56, r.end.y - 14), "귀신", lab, 1)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.end.x - 60, r.end.y - 14), "흰 테두리", Color(UiKit.BAEK, a), 1)
		"gb_haewon":
			# 영가 행렬 3명(걷기) + 길닦음 매듭
			var yb: float = r.position.y + 70.0
			var fr: Array[Texture2D] = [_anim("yg_f", 6.0), _anim("yg_m", 6.0), _anim("yg_f", 5.0)]
			for i in 3:
				_blit(fr[i], Vector2(r.position.x + 52 + i * 58, yb + float(i % 2) * 4.0), 2, a * (1.0 - float(i) * 0.18))
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(c.x, yb + 46), "넋 동무", Color(UiKit.BAEK, a), 1)
			# 흰 고리(코드) + 매듭
			var rc: Vector2 = Vector2(c.x, r.end.y - 52)
			for i in 28:
				var ang: float = TAU * float(i) / 28.0 + _t * 0.6
				var pt: Vector2 = rc + Vector2(cos(ang) * 46.0, sin(ang) * 22.0)
				draw_rect(Rect2(pt.round(), Vector2(2, 2)), Color(UiKit.BAEK, a * (0.4 + 0.6 * float(i % 2))))
			_blit(_img.get("gil_knot"), rc + Vector2(46, 0), 2, a)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(rc.x, rc.y + 4), "한꺼번에", Color(UiKit.HWANG_HI, a), 1)
		"gb_trial":
			_blit(_img.get("ring"), c + Vector2(0, 36), 3, a * 0.9)
			_blit(_anim("sansin", 6.0), c + Vector2(0, -8), 1, a)
			UiKit.draw_kind_mark(self, Vector2(r.position.x + 24, r.end.y - 18), 3.0, false)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.position.x + 32, r.end.y - 14), "싸움", Color(UiKit.JEOK_HI, a))
			UiKit.draw_kind_mark(self, Vector2(r.end.x - 86, r.end.y - 18), 3.0, true)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.end.x - 78, r.end.y - 14), "모심", Color(UiKit.HANJI_UI, a))
		"gb_sal":
			_blit(_img.get("wongwi"), c + Vector2(20, -34), 2, a)
			_blit(_img.get("sal"), Vector2(r.position.x + 34, r.position.y + 108), 3, a)
			_blit(_img.get("sal"), Vector2(r.position.x + 62, r.position.y + 128), 2, a)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.position.x + 46, r.position.y + 150), "원한 알갱이", Color(UiKit.MEOK, a), 1, false)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.end.x - 40, r.position.y + 70), "성난 귀신", Color(UiKit.JEOK_DDK, a), 1, false)
			# 굿판의 기운 바(한지빛 / 먹빛)
			var gb: Rect2 = Rect2(r.position.x + 20, r.end.y - 30, r.size.x - 40, 7)
			var k: float = 0.55 + 0.1 * sin(_t * 0.8)
			draw_rect(gb.grow(1.0), Color(UiKit.HANJI_4, a))
			draw_rect(Rect2(gb.position, Vector2(roundf(gb.size.x * k), gb.size.y)), Color(UiKit.HANJI, a))
			draw_rect(Rect2(gb.position + Vector2(roundf(gb.size.x * k), 0), Vector2(gb.size.x - roundf(gb.size.x * k), gb.size.y)), Color(UiKit.MEOK_3, a))
			for q: float in [0.25, 0.5, 0.75]:
				draw_rect(Rect2(gb.position.x + roundf(gb.size.x * q), gb.position.y - 2, 1, gb.size.y + 4), Color(UiKit.JEOK_DK, a))
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(c.x, gb.position.y - 6), "풀어 줌 · 처치", Color(UiKit.HANJI_UI, a), 1)
		"gb_growth":
			var yi: float = r.position.y + 54.0
			_icon_box(Vector2(r.position.x + 48, yi), _img.get("wpn_sinkal"), false, "Lv8", a)
			UiKit.text(self, _f_body, UiKit.SZ_BODY, Vector2(c.x, yi + 4), "→", lab, 1)
			_icon_box(Vector2(r.end.x - 48, yi), _img.get("evo"), false, "신장칼", a)
			# 진화 아이콘이 따로 없으면 원무구(신칼)와 같아 보인다 → 황 테 두 겹 + '진화' 글자
			var er: Rect2 = Rect2(Vector2(r.end.x - 48, yi) - Vector2(22, 22), Vector2(44, 44))
			draw_rect(er.grow(2.0), Color(UiKit.HWANG, a), false, 1.0)
			draw_rect(er.grow(4.0), Color(UiKit.HWANG_DK, a * 0.8), false, 1.0)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.end.x - 48, yi - 30), "진화", Color(UiKit.HWANG, a), 1)
			_blit(_img.get("box"), Vector2(c.x, r.end.y - 78), 2, a)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(c.x, r.end.y - 10), "강한 귀신 상자를 열면 진화", lab, 1)
		"gb_meta":
			var sd: Texture2D = _img.get("sindang")
			if sd != null:
				var sr: Rect2 = Rect2(Vector2(roundf(r.end.x - 176), roundf(r.position.y + 4)), Vector2(172, 120))
				draw_texture_rect(sd, sr, false, Color(1, 1, 1, a))
			_blit(_anim("saja", 5.0), Vector2(r.position.x + 52, r.end.y - 46), 1, a)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.position.x + 52, r.end.y - 8), "저승사자", lab, 1)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.end.x - 90, r.position.y + 138), "신당", lab, 1)


func _key(p: Vector2, s: String, a: float) -> void:
	var r: Rect2 = Rect2(p, Vector2(16, 16))
	draw_rect(r.grow(1.0), Color(UiKit.MEOK, a))
	draw_rect(r, Color(UiKit.HANJI_2, a))
	draw_rect(Rect2(r.position.x, r.end.y - 3, r.size.x, 3), Color(UiKit.HANJI_4, a))
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.get_center().x, r.position.y + 11), s, Color(UiKit.INK, a), 1, false)


func _icon_box(c: Vector2, tex: Texture2D, white: bool, label: String, a: float) -> void:
	var r: Rect2 = Rect2(c - Vector2(22, 22), Vector2(44, 44))
	draw_rect(r.grow(1.0), Color(UiKit.HANJI_3 if white else UiKit.JEOK, a))
	draw_rect(r, Color(UiKit.MEOK_2, a))
	if tex != null:
		var reg: Rect2 = UiKit.icon_region(tex)
		draw_texture_rect_region(tex, Rect2((c - reg.size * 0.5).round(), reg.size), reg, Color(1, 1, 1, a))
	UiKit.draw_kind_mark(self, r.position + Vector2(-2, -2), 3.0, white)
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(c.x, r.end.y + 13), label, Color(UiKit.HANJI_UI if white else UiKit.JEOK_HI, a), 1)


## 2쪽: 20분 띠(거리 색) + 시각 목록
func _draw_timeline(r: Rect2, a: float) -> void:
	var boss: float = Data.num("waves_stage1", "boss_time_sec", 1200.0)
	var band: Rect2 = Rect2(r.position.x + 14, r.position.y + 12, 6, r.size.y - 24)
	var arr: Variant = Data.get_value("waves_stage1", "geori", [])
	var cols: Array[Color] = [UiKit.HANJI_3, UiKit.CHEONGNOK_DK, UiKit.NOK_DC, UiKit.DANJU, UiKit.JEOK_DK, UiKit.HWANG_DK]
	if arr is Array:
		var gi: int = 0
		for g: Variant in arr:
			if not (g is Dictionary):
				continue
			var s0: float = float((g as Dictionary).get("start_sec", 0.0))
			var e: Variant = (g as Dictionary).get("end_sec", null)
			if e == null or s0 >= boss:
				continue
			var e0: float = minf(float(e), boss)
			var y0: float = band.position.y + roundf(band.size.y * s0 / boss)
			var y1: float = band.position.y + roundf(band.size.y * e0 / boss)
			draw_rect(Rect2(band.position.x, y0, band.size.x, maxf(1.0, y1 - y0)), Color(cols[gi % cols.size()], a))
			gi += 1
	draw_rect(band.grow(1.0), Color(UiKit.HANJI_4, a), false, 1.0)
	var n: int = _timeline.size()
	var row: float = floorf((r.size.y - 16.0) / float(maxi(n, 1)))
	var jing: Texture2D = _img.get("ico_jing")
	for i in n:
		var e2: Dictionary = _timeline[i]
		var ty: float = band.position.y + roundf(band.size.y * float(e2["t"]) / boss)
		var ly: float = r.position.y + 14.0 + float(i) * row
		var kind: int = int(e2["kind"])
		var col: Color = UiKit.HANJI_2
		match kind:
			1:
				col = UiKit.HWANG_HI
			2:
				col = UiKit.JEOK_HI
			3:
				col = UiKit.HANJI_UI
		# 띠 위 눈금 → 줄 연결
		draw_rect(Rect2(band.end.x + 1, ty, 4, 1), Color(col, a))
		draw_line(Vector2(band.end.x + 5, ty), Vector2(band.end.x + 14, ly - 3), Color(col, 0.5 * a), 1.0)
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(band.end.x + 16, ly), _mmss(float(e2["t"])), Color(col, a))
		if kind == 1 and jing != null:
			draw_texture_rect(jing, Rect2(Vector2(band.end.x + 52, ly - 10), Vector2(12, 12)), false, Color(1, 1, 1, a))
		UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(band.end.x + 68, ly), String(e2["label"]), Color(col, a))
	var ly2: float = r.position.y + 14.0 + float(n) * row
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(band.end.x + 16, minf(ly2, r.end.y - 4)), "→ 굿 끝 · 얻은 것", Color(UiKit.HANJI_3, a))
