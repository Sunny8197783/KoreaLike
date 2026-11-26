class_name Guidebook
extends Control
## 굿 안내서(도움말 8쪽, design/17 §6). 소유: ui(intro_ui).
## 열기: 타이틀 '길잡이 → 굿 안내서', 쉼 메뉴 '굿 안내서'(쉼 메뉴의 자식, 닫으면 쉼 메뉴로).
## 조작: ← → · A D · D-패드 좌우 · 마우스(◀ ▶) = 쪽 넘김 / 1~8 = 바로 그 쪽 / Esc · Backspace · B = 닫기.
## 수치는 Data 에서 읽는다(시련 시각·합일·길베 초·영가 수명·살기 문턱·풀릴 기색 문턱·중간보스·작두·뒷전·보스 시각).
## 공개: open(page), close(), signal closed. --guidebook-test=<1..8|all> 은 title 이 연다.

signal closed

const PAGE_IDS: Array[String] = ["gb_controls", "gb_flow", "gb_weapons", "gb_haewon", "gb_trial", "gb_sal", "gb_growth", "gb_meta"]
const TITLES: Array[String] = ["조작", "목표와 한 판 흐름", "붉은 무구 · 흰 무구 · 매듭", "해원 · 영가 · 고리",
	"시련과 빙의", "살과 원귀", "성장 — 점지 · 진화 · 결합", "정산과 신당"]
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
			"점지 고르기: **1 · 2 · 3** 또는 **← →** + **Enter** / 패드 **D-패드 + A**",
			"전체 화면: **Alt+Enter · F11**"],
		# 2 흐름
		["**%d분 굿 한 판**을 끝까지 치르면 된다" % minutes,
			"신령의 **시련**이 네 번 온다(%s)" % " · ".join(trial_s),
			"%s 중간보스, %s 모신 신령들이 **합일**한다" % [_mmss(mboss), _mmss(hapil)],
			"%s **마지막 손님**(보스)을 보내면 **저승사자**가 정산한다" % _mmss(boss),
			"장단은 **진양조**에서 **단모리**로 점점 빨라진다"],
		# 3 무구
		["◆ 붉은 무구는 한(恨)을 깎아 **퇴치**한다. 원혼 구슬이 온전히 모인다",
			"한이 %d%% 아래면 흰 테두리 — **풀릴 기색**" % int(roundf(giseak * 100.0)),
			"기색 귀신에게 붉은 무구는 마지막 매듭을 끊지 못한다(**매듭 잠금**)",
			"○ 흰 무구는 기색 귀신을 **해원**한다",
			"드물게 치명타(**결단타**)는 기색도 단칼에 끊는다"],
		# 4 해원·영가·고리
		["해원한 사람의 넋은 **영가**가 되어 뒤를 따른다(%d초, 곁의 귀신을 달램)" % int(sumyeong),
			"때가 되면 저승길로 떠난다 — **천도**. 행렬이 길면 대신 맞고 먼저 떠난다",
			"걸은 자리에 흰 길(**길베**)이 %d초 남는다" % int(gilbe),
			"흰 길로 한 바퀴 감싸 닫으면 **길닦음**: 안의 기색 귀신과 한이 절반 아래인 귀신이 한꺼번에 풀린다",
			"닫을 수 있으면 점선과 매듭 표지가 뜬다"],
		# 5 시련
		["시련 때 신령 둘이 원으로 내려온다. **들어가는 원이 곧 선택**",
			"예고 때 무당 아래 놓이는 작은 원(**산통**)에 잠시 서면 신령을 다시 묻는다",
			"◆ 무구로 화신을 치면 **위엄**(꺾기), ○ 안내판의 의례를 하면 **가호**(모시기) — 먼저 찬 쪽",
			"이기면 **빙의**: 신령의 권능 하나를 고른다",
			"%s 모신 신령들이 **합일**한다" % _mmss(hapil)],
		# 6 살
		["퇴치한 자리에 **살 알갱이**가 남고 **살기**가 오른다",
			"살기 %s에서 알갱이가 뭉쳐 **원귀**로 돌아온다" % " · ".join(sal_s),
			"알갱이를 밟아 거두면 벽사 기세가 차고, 고리·소금으로 씻을 수 있다",
			"위 **굿판의 기운** 바: 풀어 보낸 만큼 한지빛, 퇴치한 만큼 먹빛. %s 손님의 얼굴이 여기서 정해진다" % _mmss(boss),
			"어느 쪽도 끝까지 갈 수 있다"],
		# 7 성장
		["원혼 구슬이 차면 **점지**: 카드 하나를 고른다(◆ 붉은 띠 / ○ 흰 띠)",
			"무구 6칸, 패시브 6칸",
			"**진화**: 무구 Lv8 + 짝 패시브 → 정예가 남긴 상자(길흉 상자 · 넋함)를 열 때",
			"**결합**: 붉은 진화와 흰 진화가 만나면 양면 무구",
			"카드 맨 아래 줄이 진화 · 결합 조건을 알려 준다"],
		# 8 정산
		["마지막 손님을 보내면 **저승사자**가 굿판을 거둔다",
			"넋이 많으면 **사자의 읍**, 살이 많으면 **살 거둠**(원귀를 막으며 버틴다)",
			"쓰러져도 판은 정산된다",
			"넋 → **공덕**, 엽전 → **복전**",
			"신당에서 무구를 봉헌·제작하고, **내림굿**으로 새 무당을 모신다"],
	]
	_bodies.clear()
	for pg: Variant in src:
		var bl: Array = []
		for s: Variant in (pg as Array):
			bl.append(TutDraw.rich_wrap(_f_body, UiKit.SZ_BODY, String(s), TEXT_W - 14.0, 4))
		_bodies.append(bl)
	_cap = PackedStringArray(["걷기만으로 싸운다", "%d분 · 거리마다 장단이 바뀐다" % minutes, "깎고(◆) 푼다(○)",
		"영가 행렬 · 길닦음 매듭", "시련 %s" % " · ".join(trial_s), "살 알갱이 → 원귀",
		"신칼 → 신장칼(진화)", "저승사자 · 신당"])
	# 2쪽 띠(시각 순)
	_timeline = [{"t": 0.0, "label": "개막(진양조)", "kind": 0}]
	for v: Variant in trials:
		_timeline.append({"t": float(v), "label": "시련", "kind": 1})
	_timeline.append({"t": mboss, "label": "중간보스", "kind": 2})
	_timeline.append({"t": hapil, "label": "합일", "kind": 1})
	_timeline.append({"t": jakdu, "label": "작두 강림", "kind": 2})
	_timeline.append({"t": dwit, "label": "뒷전(대해원)", "kind": 0})
	_timeline.append({"t": boss, "label": "마지막 손님", "kind": 3})
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
			_icon_box(Vector2(r.position.x + 56, y0), tl, false, "퇴치", a)
			_icon_box(Vector2(r.end.x - 56, y0), tr, true, "해원", a)
			# 달걀귀신(맺힘) → 흰 테두리(풀릴 기색) + 매듭
			var yy: float = r.position.y + 128.0
			_blit(_img.get("dalgyal"), Vector2(r.position.x + 56, yy), 2, a)
			UiKit.text(self, _f_body, UiKit.SZ_BODY, Vector2(c.x, yy + 4), "→", lab, 1)
			_blit(_img.get("dalgyal_pullil"), Vector2(r.end.x - 60, yy), 2, a)
			var kr: Rect2 = _blit(_img.get("knot"), Vector2(r.end.x - 24, yy - 30), 2, a)
			if kr.size.x > 0.0:
				# 이름 없는 회색 X 는 '닫기·오류'로 읽혔다(리뷰 11-25) — 매듭이라고 단다
				UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(kr.get_center().x, kr.end.y + 9.0), "매듭", lab, 1)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.position.x + 56, r.end.y - 14), "맺힘", lab, 1)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.end.x - 60, r.end.y - 14), "풀릴 기색", Color(UiKit.BAEK, a), 1)
		"gb_haewon":
			# 영가 행렬 3명(걷기) + 길닦음 매듭
			var yb: float = r.position.y + 70.0
			var fr: Array[Texture2D] = [_anim("yg_f", 6.0), _anim("yg_m", 6.0), _anim("yg_f", 5.0)]
			for i in 3:
				_blit(fr[i], Vector2(r.position.x + 52 + i * 58, yb + float(i % 2) * 4.0), 2, a * (1.0 - float(i) * 0.18))
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(c.x, yb + 46), "영가 행렬", Color(UiKit.BAEK, a), 1)
			# 흰 고리(코드) + 매듭
			var rc: Vector2 = Vector2(c.x, r.end.y - 52)
			for i in 28:
				var ang: float = TAU * float(i) / 28.0 + _t * 0.6
				var pt: Vector2 = rc + Vector2(cos(ang) * 46.0, sin(ang) * 22.0)
				draw_rect(Rect2(pt.round(), Vector2(2, 2)), Color(UiKit.BAEK, a * (0.4 + 0.6 * float(i % 2))))
			_blit(_img.get("gil_knot"), rc + Vector2(46, 0), 2, a)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(rc.x, rc.y + 4), "길닦음", Color(UiKit.HWANG_HI, a), 1)
		"gb_trial":
			_blit(_img.get("ring"), c + Vector2(0, 36), 3, a * 0.9)
			_blit(_anim("sansin", 6.0), c + Vector2(0, -8), 1, a)
			UiKit.draw_kind_mark(self, Vector2(r.position.x + 24, r.end.y - 18), 3.0, false)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.position.x + 32, r.end.y - 14), "꺾기 = 위엄", Color(UiKit.JEOK_HI, a))
			UiKit.draw_kind_mark(self, Vector2(r.end.x - 86, r.end.y - 18), 3.0, true)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.end.x - 78, r.end.y - 14), "모시기 = 가호", Color(UiKit.HANJI_UI, a))
		"gb_sal":
			_blit(_img.get("wongwi"), c + Vector2(20, -34), 2, a)
			_blit(_img.get("sal"), Vector2(r.position.x + 34, r.position.y + 108), 3, a)
			_blit(_img.get("sal"), Vector2(r.position.x + 62, r.position.y + 128), 2, a)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.position.x + 46, r.position.y + 150), "살 알갱이", Color(UiKit.MEOK, a), 1, false)
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(r.end.x - 30, r.position.y + 70), "원귀", Color(UiKit.JEOK_DDK, a), 1, false)
			# 굿판의 기운 바(한지빛 / 먹빛)
			var gb: Rect2 = Rect2(r.position.x + 20, r.end.y - 30, r.size.x - 40, 7)
			var k: float = 0.55 + 0.1 * sin(_t * 0.8)
			draw_rect(gb.grow(1.0), Color(UiKit.HANJI_4, a))
			draw_rect(Rect2(gb.position, Vector2(roundf(gb.size.x * k), gb.size.y)), Color(UiKit.HANJI, a))
			draw_rect(Rect2(gb.position + Vector2(roundf(gb.size.x * k), 0), Vector2(gb.size.x - roundf(gb.size.x * k), gb.size.y)), Color(UiKit.MEOK_3, a))
			for q: float in [0.25, 0.5, 0.75]:
				draw_rect(Rect2(gb.position.x + roundf(gb.size.x * q), gb.position.y - 2, 1, gb.size.y + 4), Color(UiKit.JEOK_DK, a))
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(c.x, gb.position.y - 6), "굿판의 기운", Color(UiKit.HANJI_UI, a), 1)
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
			UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(c.x, r.end.y - 10), "정예 상자를 열 때 진화", lab, 1)
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
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(band.end.x + 16, minf(ly2, r.end.y - 4)), "→ 저승사자 정산", Color(UiKit.HANJI_3, a))
