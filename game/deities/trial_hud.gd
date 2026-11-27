extends CanvasLayer
## 시련 HUD(L3, 읽기 전용, 640×360 화면 좌표). 소유: deities.
## 역할 분담: 두 게이지 막대·남은 시간 줄·공수 자막 레인은 ui/hud.gd 의 의례 슬롯(y 37~78)이 그린다.
##   여기서는 그 아래(y 82~)에 "지금 할 일" 안내판만 둔다 — 처음 하는 사람도 알 수 있게:
##   OMEN/DESCEND: 단계 제목 + 남은 초 + 할 일 한 줄(+ 산통 다시 묻기), 각 화신 원에 신령 이름·두 면 요약
##     (위엄 = 적 + 마름모 표식 / 가호 = 한지빛 + 원 표식 — 색만으로 구분하지 않음)
##   TRIAL: 신령 이름 + 남은 초, 두 길 안내(◆ 화신을 쳐서 / ○ 의례로), 숨 고르기 알림, 마당 이탈 경고·화살표
##   해결·빙의·합일: 붓글씨 큰 글자(면 이름 / 호명 한 단어 / 합일 형태)
## 문자열은 상태가 바뀔 때만 만든다(매 프레임 포맷 금지).

const Defs := preload("res://deities/deity_defs.gd")

var dir: Node = null

const C_HANJI: Color = Color(0.913, 0.863, 0.753, 1.0)
const C_HANJI_DK: Color = Color(0.698, 0.616, 0.463, 1.0)
const C_JEOK: Color = Color(0.784, 0.196, 0.176, 1.0)
const C_JEOK_HI: Color = Color(0.894, 0.376, 0.31, 1.0)
const C_MEOK: Color = Color(0.055, 0.043, 0.086, 1.0)
const C_HEUK: Color = Color(0.102, 0.102, 0.102, 1.0)
const C_HWANG: Color = Color(0.91, 0.725, 0.192, 1.0)

const PANEL_Y: float = 82.0
const PANEL_W: float = 400.0
const LINE_H: float = 12.0
const LBL_W: float = 280.0
const TRIAL_FULL_S: float = 7.0         # 첫 시련: 두 길을 두 줄로 풀어 보이는 시간(그 뒤 한 줄로 접힘)
const TRIAL_FULL_S_LATER: float = 3.0

var _c: Control
var _font: Font
var _bold: Font
var _small: Font
var _brush: Font
var _sig: int = -1
var _s_title: String = ""
var _s_time: String = ""
var _s_l1: String = ""       # 안내 1(위엄 길 / 일반)
var _s_l2: String = ""       # 안내 2(가호 길 / 산통)
var _l1_mark: int = 0        # 0 없음 1 마름모(위엄) 2 원(가호)
var _l2_mark: int = 0
var _s_c1: String = ""       # 접힌 한 줄(시련 중반부터): ◆ _s_c1 · ○ _s_c2
var _s_c2: String = ""
var _s_vuln_short: String = "지금! 큰 신령이 숨을 고른다 — 붙어서 치기"
var _s_vuln: String = "지금! 큰 신령이 숨을 고른다 — 붙어서 치면 1.5배"
var _s_leave: String = "흰 줄 밖이면 절반만 찬다"
var _s_lowhp: String = "체력이 낮다 — 물러나도 실패 없음"
var _s_big3: String = ""
var _s_big: String = ""
var _s_big2: String = ""
var _big_t: float = -10.0
var _big_col: Color = C_HANJI
var _big_dur: float = 1.6
var _lbl: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
var _lbl_sig: int = -1
var _last_res_sig: int = -1
var _s_santong: String = ""
var _geori_t: float = -10.0   # 거리 전환 배너(ui)가 뜨는 3초 동안 안내판을 옅게(겹침 방지)


func _ready() -> void:
	_c = Control.new()
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_c.draw.connect(_on_draw)
	add_child(_c)
	# 글꼴: 테마 기본값에 기대지 않고 UiKit 단계(T3 본문 12 / T4 보조 10)를 직접 쓴다(design/19 §4.1)
	UiKit.setup_fonts()
	_font = UiKit.body()
	_bold = UiKit.bold()
	_small = UiKit.small()
	var bf: FontFile = load("res://assets/fonts/nanum_brush/NanumBrushScript-Regular.ttf") as FontFile
	if bf != null:
		bf = bf.duplicate() as FontFile
		bf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_brush = bf
	else:
		_brush = _font
	Events.geori_changed.connect(func(_g: StringName, _b: float, _j: StringName) -> void: _geori_t = Game.time_sec())


func _process(_d: float) -> void:
	if dir == null:
		return
	var td: TrialDirector = dir as TrialDirector
	_refresh_strings(td)
	_c.queue_redraw()


func _refresh_strings(td: TrialDirector) -> void:
	var now: float = Game.time_sec()
	var sec: int = 0
	match td.ph:
		TrialDirector.Ph.OMEN:
			sec = int(ceilf(td.omen_at - now))
		TrialDirector.Ph.DESCEND, TrialDirector.Ph.CONFIRM:
			sec = int(ceilf(td.descend_end - now))
		TrialDirector.Ph.TRIAL:
			sec = int(ceilf(td.t_left))
	var sig: int = td.ph * 100000 + sec * 100 + (1 if td.santong_on else 0) + td.reroll_left * 1000000 + (td.slot + 1) * 10000000
	if sig != _sig:
		_sig = sig
		_build_panel(td, sec)
	var lsig: int = hash(td.cand[0]) ^ (hash(td.cand[1]) << 1)
	lsig = lsig ^ (td.reroll_left << 20) ^ ((1 << 24) if td.santong_on else 0)
	if lsig != _lbl_sig:
		_lbl_sig = lsig
		_s_santong = "다시 고르기 · %d번" % td.reroll_left
		for i in 2:
			_lbl[i] = _circle_label(td, td.cand[i])
	# 해결·빙의·합일 큰 글자
	var rsig: int = td.ph * 7 + td.slot * 131 + td.hapil_idx * 3
	if rsig != _last_res_sig:
		_last_res_sig = rsig
		if td.ph == TrialDirector.Ph.RESOLVE or td.ph >= TrialDirector.Ph.HAPIL_OMEN:
			_s_big3 = ""
		if td.ph == TrialDirector.Ph.RESOLVE:
			# 결과(design/19 §4.6): 붓 '바리공주' + '힘을 받았다 — 칼 피해 +30% (절반 성공)' + '신령 4분 중 1분 · 18:00에…'
			_s_big = Defs.short_name(td.active_deity)
			var fx: String = Defs.face_plain(td.active_deity, td.res_face)
			_s_big2 = "힘을 받았다 — %s" % fx if td.res_complete else "힘을 받았다 — %s (절반 성공)" % fx
			var got: int = td.possessed.size() + (0 if td.possessed.has(td.active_deity) else 1)
			_s_big3 = "신령 4분 중 %d분 · 18:00에 모두 모이면 큰 힘" % mini(4, got)
			_big_t = now
			_big_dur = 2.2
			_claim_big()
			_big_col = C_JEOK_HI if td.res_face == &"wieom" else C_HANJI
		elif td.ph == TrialDirector.Ph.HAPIL_CALL and td.hapil_idx >= 0 and td.hapil_idx < td.hapil_ids.size():
			_s_big = td.hapil_word
			_s_big2 = Defs.short_name(td.hapil_ids[td.hapil_idx])
			_big_t = now
			_big_dur = 1.2
			_claim_big()
			_big_col = Defs.color(td.hapil_ids[td.hapil_idx]).lightened(0.25)
		elif td.ph == TrialDirector.Ph.HAPIL_ACTIVE and td.hapil_word != "":
			_s_big = td.hapil_word
			_s_big2 = {&"hapil_wise": "신령 모두 내림 · 치명타 +10%", &"hapil_jabi": "신령 모두 내림 · 흰 테두리 쉽게 · 넋 동무 +12", &"hapil_yangmyeon": "신령 모두 내림 · 공격력 +8%"}.get(td.hapil_form, "신령 모두 내림")
			_big_t = now
			_big_dur = 3.2
			_claim_big()
			_big_col = C_HWANG
		elif td.ph == TrialDirector.Ph.HAPIL_OMEN:
			_s_big = "신령 모두 내림"
			_s_big2 = "모신 신령이 모두 내려온다 — 마지막 공세"
			_big_t = now
			_big_dur = 2.0
			_claim_big()
			_big_col = C_HANJI


## 가시성 측정(tests/vis_probe.gd): 이번 프레임에 그린 화면 글 사각형. 키 → [Rect2(640×360 기준), 그린 프레임].
var vis_rects: Dictionary = {}


## 큰 글자는 가운데 슬롯 최우선(prio 4, design/18 §2.2). 다른 가운데 글(거리 카드·붓 슬램)은 이 동안 뜨지 않는다.
func _claim_big() -> void:
	if Juice.has_method(&"claim_center"):
		Juice.call(&"claim_center", &"trial_big", 4, _big_dur)


## 안내판 = '지금 할 일' 한 줄(왼쪽 작은 말머리 + 가운데 할 일 + 오른쪽 남은 초).
## 시련(TRIAL) 첫 몇 초만 두 길(◆ 싸움 / ○ 모심)을 두 줄로 풀어 쓰고, 그 뒤엔 한 줄로 접는다.
## 쉬운 첫 시험(td.easy_trial): 강림 수치를 숨기고 안내판은 한 줄(design/19 §4.6).
func _build_panel(td: TrialDirector, sec: int) -> void:
	var easy: bool = td.easy_trial and td.slot == 0
	_s_l1 = ""
	_s_l2 = ""
	_s_c1 = ""
	_s_c2 = ""
	_s_time = ""
	_l1_mark = 0
	_l2_mark = 0
	match td.ph:
		TrialDirector.Ph.OMEN:
			# 예고 10초: 한 줄. 두 신령의 힘은 좌우 카드가 말한다.
			_s_title = "신령의 시험"
			_s_time = "" if easy else "%d" % maxi(0, sec)
			_s_l1 = "신령이 온다 — 왼쪽·오른쪽 원 중 하나로"
		TrialDirector.Ph.DESCEND, TrialDirector.Ph.CONFIRM:
			_s_title = "신령의 시험"
			_s_time = "" if easy else "%d" % maxi(0, sec)
			_s_l1 = "모실 신령의 원 안으로 걸어가 잠깐 서기"
		TrialDirector.Ph.CLEAR:
			_s_title = Defs.short_name(td.active_deity)
			_s_l1 = "흰 줄 안이 시험 자리 — 먼저 찬 쪽 힘을 받는다"
		TrialDirector.Ph.TRIAL:
			_s_title = "-"      # 패널은 켜되 말머리는 없음(HUD 가 신령 이름을 말한다)
			_s_time = "%d" % maxi(0, sec)
			_s_l1 = "싸움 — 큰 신령 곁에서 무기로 치기"
			_s_l2 = "모심 — " + _task_short(td.active_deity)
			_s_c1 = "큰 신령 곁에서 싸우기"
			_s_c2 = _task_short(td.active_deity)
			_l1_mark = 1
			_l2_mark = 2
		TrialDirector.Ph.AFTERGLOW:
			_s_title = Defs.short_name(td.active_deity)
			_s_l1 = "신령 4분 중 %d분 · 18:00에 모두 모이면 큰 힘" % mini(4, td.possessed.size())
		_:
			_s_title = ""


## 모심(가호) 과제 한 줄(쉬운 말, 14자 안팎) — UI 표시 전용 문구
func _task_short(d: StringName) -> String:
	match String(d):
		"deity_sansin":
			return "쉼터 원 안에서 넋 지키기"
		"deity_yongwang":
			return "물속 넋을 건져 용왕상으로"
		"deity_chilseong":
			return "별을 번호 순서로 밟기"
		"deity_janggun":
			return "깃발 자리 다섯 곳에 서기"
		"deity_barigongju":
			return "작은 넋들을 문으로 몰기"
		"deity_jeseok_daegam":
			return "굿상 곁에서 흰 길로 감싸기"
	return Defs.task_object_name(d) + " 과제 하기"


## 원 카드 머리: 신령 이름(한자 없음) + 내 신령 표시
func _name_hj(d: StringName) -> String:
	return Defs.short_name(d)


func _circle_label(td: TrialDirector, d: StringName) -> PackedStringArray:
	if d == &"":
		return PackedStringArray()
	var head: String = Defs.short_name(d)
	if d == td.momju:
		head += " · 내 신령"
	# 처음 두 판은 신령마다 다른 힘 대신 공통 한 줄(design/19 §4.6) — 처음 보는 낱말을 줄인다. 셋째 판부터 FACE_SHORT.
	if td.easy_trial or td._easy_runs():
		return PackedStringArray([head, "싸우는 힘이 세져요", "나를 돕는 힘이 생겨요"])
	return PackedStringArray([head, Defs.face_short(d, &"wieom"), Defs.face_short(d, &"gaho")])


# ─── 그리기 ────────────────────────────────────────────────────────────

func _text(pos: Vector2, s: String, size: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, width: float = 400.0, f: Font = null) -> void:
	if s == "":
		return
	var fo: Font = f if f != null else _font
	var x: float = pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	var p: Vector2 = Vector2(roundf(x), roundf(pos.y))
	fo.draw_string_outline(_c.get_canvas_item(), p, s, align, width, size, 4, Color(C_MEOK, col.a * 0.9))
	fo.draw_string(_c.get_canvas_item(), p, s, align, width, size, col)


## 면 표식: 1 = 마름모(위엄, 적) / 2 = 원(가호, 한지). c = 중심.
func _mark(c: Vector2, kind: int, a: float) -> void:
	var p: Vector2 = c.round()
	if kind == 1:
		_c.draw_rect(Rect2(p.x - 3, p.y - 1, 7, 3), Color(C_MEOK, a))
		_c.draw_rect(Rect2(p.x - 1, p.y - 3, 3, 7), Color(C_MEOK, a))
		_c.draw_rect(Rect2(p.x - 2, p.y, 5, 1), Color(C_JEOK_HI, a))
		_c.draw_rect(Rect2(p.x, p.y - 2, 1, 5), Color(C_JEOK_HI, a))
		_c.draw_rect(Rect2(p.x - 1, p.y - 1, 3, 3), Color(C_JEOK_HI, a))
	elif kind == 2:
		# 픽셀 고리(7×7): draw_arc 반지름 3 은 시작·끝 이음매가 끊겨 'c' 처럼 보였다(리뷰 11-24 t0300 03:20)
		_c.draw_rect(Rect2(p.x - 3, p.y - 4, 7, 9), Color(C_MEOK, a))
		_c.draw_rect(Rect2(p.x - 4, p.y - 3, 9, 7), Color(C_MEOK, a))
		var hc: Color = Color(C_HANJI, a)
		_c.draw_rect(Rect2(p.x - 1, p.y - 3, 3, 1), hc)
		_c.draw_rect(Rect2(p.x - 1, p.y + 3, 3, 1), hc)
		_c.draw_rect(Rect2(p.x - 3, p.y - 1, 1, 3), hc)
		_c.draw_rect(Rect2(p.x + 3, p.y - 1, 1, 3), hc)
		_c.draw_rect(Rect2(p.x - 2, p.y - 2, 1, 1), hc)
		_c.draw_rect(Rect2(p.x + 2, p.y - 2, 1, 1), hc)
		_c.draw_rect(Rect2(p.x - 2, p.y + 2, 1, 1), hc)
		_c.draw_rect(Rect2(p.x + 2, p.y + 2, 1, 1), hc)


func _on_draw() -> void:
	if dir == null:
		return
	var td: TrialDirector = dir as TrialDirector
	var vs: Vector2 = _c.size
	var cx: float = roundf(vs.x * 0.5)
	var now: float = Game.time_sec()
	var ph: int = td.ph
	var panel_on: bool = (ph >= TrialDirector.Ph.OMEN and ph <= TrialDirector.Ph.TRIAL) or ph == TrialDirector.Ph.AFTERGLOW
	if panel_on and _s_title != "":
		var a: float = 1.0
		if ph == TrialDirector.Ph.AFTERGLOW:
			a = clampf(1.0 - (now - td.ph_t0) / td.afterglow_s, 0.0, 1.0)
		var gage: float = now - _geori_t
		if gage >= 0.0 and gage < 3.0 and ph == TrialDirector.Ph.AFTERGLOW:   # OMEN~RESOLVE 중엔 waves 가 거리 카드를 띄우지 않는다
			a *= 0.2 + 0.8 * clampf((gage - 2.6) / 0.4, 0.0, 1.0)
		var dc: Color = Defs.color(td.active_deity if td.active_deity != &"" else &"")
		var is_trial: bool = ph == TrialDirector.Ph.TRIAL
		# 시련 두 길: 첫 시련은 TRIAL_FULL_S, 다음 시련부터는 짧게 두 줄로 풀어 보인 뒤 한 줄로 접는다
		var full_s: float = TRIAL_FULL_S if td.slot <= 0 else TRIAL_FULL_S_LATER
		var compact: bool = is_trial and _s_c1 != "" and (now - td.ph_t0) >= full_s
		var two: bool = is_trial and not compact and _s_l2 != ""
		var vul: bool = false
		if is_trial and td.avatar != null:
			vul = bool(td.avatar.call("is_vulnerable"))
		var ph_h: float = 17.0 + (LINE_H if two else 0.0)
		var pr: Rect2 = Rect2(cx - PANEL_W * 0.5, PANEL_Y, PANEL_W, ph_h)
		_c.draw_rect(pr, Color(C_MEOK, 0.72 * a))
		vis_rects["top:trial"] = [pr, Engine.get_process_frames()]
		_c.draw_rect(Rect2(pr.position.x, pr.position.y, pr.size.x, 1), Color(dc, 0.9 * a))
		_c.draw_rect(Rect2(pr.position.x, pr.end.y - 1.0, pr.size.x, 1), Color(C_HANJI_DK, 0.35 * a))
		var ty: float = PANEL_Y + 12.0
		var lx: float = pr.position.x + 8.0
		var rx: float = pr.end.x - 6.0
		# 왼쪽 말머리(작은 황 글자 + 구분 1px)
		if _s_title != "" and _s_title != "-":
			var tgw: float = _bold.get_string_size(_s_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_text(Vector2(lx, ty), _s_title, 12, Color(C_HWANG, a), HORIZONTAL_ALIGNMENT_LEFT, tgw + 4.0, _bold)
			lx += roundf(tgw) + 6.0
			_c.draw_rect(Rect2(lx, PANEL_Y + 4.0, 1, 10), Color(C_HANJI_DK, 0.5 * a))
			lx += 6.0
		# 오른쪽 남은 초
		if _s_time != "":
			var tcol: Color = C_HWANG
			if is_trial and td.t_left <= 5.0 and int(now * 4.0) % 2 == 0:
				tcol = C_JEOK_HI
			var tmw: float = _font.get_string_size(_s_time, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_text(Vector2(rx, ty), _s_time, 12, Color(tcol, a), HORIZONTAL_ALIGNMENT_RIGHT, tmw + 4.0)
			rx -= roundf(tmw) + 8.0
		var tw: float = maxf(40.0, rx - lx)
		var mid: float = roundf((lx + rx) * 0.5)
		var low_hp: bool = is_trial and Game.hp_max > 0.0 and Game.hp < Game.hp_max * 0.3
		if not is_trial:
			_text(Vector2(mid, ty), _s_l1, 12, Color(C_HANJI, a), HORIZONTAL_ALIGNMENT_CENTER, tw)
		elif low_hp:
			_text(Vector2(mid, ty), _s_lowhp, 12, Color(C_JEOK_HI if int(now * 3.0) % 2 == 0 else C_HANJI, a), HORIZONTAL_ALIGNMENT_CENTER, tw)
		elif vul:
			# 숨 고르기: 다른 글을 밀어내고 한 줄만(가장 급한 할 일)
			_mark(Vector2(lx + 3.0, ty - 4.0), 1, a)
			_text(Vector2(lx + 12.0, ty), _s_vuln_short if compact else _s_vuln, 12, Color(C_HANJI if int(now * 6.0) % 2 == 0 else C_JEOK_HI, a), HORIZONTAL_ALIGNMENT_LEFT, tw - 12.0)
			if two:
				_mark(Vector2(lx + 3.0, ty + LINE_H - 4.0), 2, a)
				_text(Vector2(lx + 12.0, ty + LINE_H), _s_l2, 12, Color(C_HANJI, a), HORIZONTAL_ALIGNMENT_LEFT, tw - 12.0)
		elif compact:
			# ◆ 화신을 쳐라 · ○ 과제 — 가운데 정렬로 한 줄
			var w1: float = _font.get_string_size(_s_c1, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var w2: float = _font.get_string_size(_s_c2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var sep: float = 18.0
			var total: float = 12.0 + w1 + sep + 12.0 + w2
			var x0: float = roundf(mid - total * 0.5)
			_mark(Vector2(x0 + 3.0, ty - 4.0), 1, a)
			_text(Vector2(x0 + 12.0, ty), _s_c1, 12, Color(C_JEOK_HI, a), HORIZONTAL_ALIGNMENT_LEFT, w1 + 4.0)
			var x1: float = x0 + 12.0 + w1 + sep
			_c.draw_rect(Rect2(roundf(x1 - sep * 0.5), PANEL_Y + 5.0, 1, 8), Color(C_HANJI_DK, 0.6 * a))
			_mark(Vector2(x1 + 3.0, ty - 4.0), 2, a)
			_text(Vector2(x1 + 12.0, ty), _s_c2, 12, Color(C_HANJI, a), HORIZONTAL_ALIGNMENT_LEFT, w2 + 4.0)
		else:
			_mark(Vector2(lx + 3.0, ty - 4.0), _l1_mark, a)
			_text(Vector2(lx + 12.0, ty), _s_l1, 12, Color(C_JEOK_HI, a), HORIZONTAL_ALIGNMENT_LEFT, tw - 12.0)
			if two:
				_mark(Vector2(lx + 3.0, ty + LINE_H - 4.0), _l2_mark, a)
				_text(Vector2(lx + 12.0, ty + LINE_H), _s_l2, 12, Color(C_HANJI, a), HORIZONTAL_ALIGNMENT_LEFT, tw - 12.0)
		if is_trial and td.leaving:
			var lw: float = roundf(_font.get_string_size(_s_leave, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 16.0
			var lr: Rect2 = Rect2(cx - roundf(lw * 0.5), pr.end.y + 2.0, lw, 15.0)
			_c.draw_rect(lr, Color(C_MEOK, 0.72))
			_text(Vector2(cx, lr.position.y + 11.0), _s_leave, 12, C_JEOK_HI if int(now * 4.0) % 2 == 0 else C_HANJI, HORIZONTAL_ALIGNMENT_CENTER, lw)
	# 화신 원 이름표(OMEN~CONFIRM) — 원 가운데 위, 화면 안으로 고정
	if ph >= TrialDirector.Ph.OMEN and ph <= TrialDirector.Ph.CONFIRM:
		var ct: Transform2D = _c.get_viewport().get_canvas_transform()
		# 두 카드가 겹치지 않게: 왼쪽 원 카드는 왼쪽, 오른쪽 원 카드는 오른쪽으로 벌린 뒤 화면 안으로
		var sx0: float = (ct * td.circle[0]).x
		var sx1: float = (ct * td.circle[1]).x
		var gap: float = LBL_W + 6.0
		if sx1 - sx0 < gap:
			var mid: float = (sx0 + sx1) * 0.5
			sx0 = mid - gap * 0.5
			sx1 = mid + gap * 0.5
		var lo: float = LBL_W * 0.5 + 6.0
		var hi: float = vs.x - LBL_W * 0.5 - 6.0
		sx0 = clampf(sx0, lo, hi - gap)
		sx1 = clampf(sx1, lo + gap, hi)
		for i in 2:
			var lb: PackedStringArray = _lbl[i]
			if lb.size() < 3:
				continue
			var sc: Vector2 = ct * td.circle[i]
			var sp: Vector2 = sc + Vector2(0, -78.0)
			sp.x = sx0 if i == 0 else sx1
			sp.y = clampf(sp.y, 140.0, vs.y - 128.0)
			var la: float = 0.7 if ph == TrialDirector.Ph.OMEN else 1.0
			var dcol: Color = Defs.color(td.cand[i])
			# 연습 굿판: 효과 수치 두 줄을 빼고 이름 + '◆ 꺾기 · ○ 모시기' 한 줄만(글 줄이기, design/17 리뷰)
			var tut: bool = Game.tutorial_mode
			var r2: Rect2 = Rect2(roundf(sp.x - LBL_W * 0.5), roundf(sp.y), LBL_W, 30.0 if tut else 45.0)
			# 무당이 카드 가까이(+8px) 들어오면 카드를 옅게 — 무당 몸을 가리지 않게(design/18 §2.3)
			var bga: float = 0.92
			if Game.player != null and is_instance_valid(Game.player):
				var pps: Vector2 = ct * Game.player.global_position
				if r2.grow(8.0).intersects(Rect2(pps + Vector2(-14, -40), Vector2(28, 44))):
					la *= 0.45
					bga = 0.4
			# 배경은 거의 불투명(0.92): 아래 월드의 피해 숫자가 카드 글자 사이로 비쳐 겹쳐 읽히지 않게
			_c.draw_rect(r2, Color(C_MEOK, bga))
			vis_rects["world:trial_card%d" % i] = [r2, Engine.get_process_frames()]
			_c.draw_rect(Rect2(r2.position.x, r2.position.y, r2.size.x, 1), Color(dcol, la))
			_c.draw_rect(Rect2(r2.position.x, r2.position.y, 2, r2.size.y), Color(dcol, la))
			if td.pick == i and ph == TrialDirector.Ph.CONFIRM:
				_c.draw_rect(r2.grow(1.0), Color(C_HWANG, 0.9), false, 1.0)
			_text(Vector2(sp.x, r2.position.y + 12.0), lb[0], 12, Color(dcol.lightened(0.4), la), HORIZONTAL_ALIGNMENT_CENTER, LBL_W - 8.0)
			if tut:
				_mark(Vector2(sp.x - 46.0, r2.position.y + 21.0), 1, la)
				_text(Vector2(sp.x - 38.0, r2.position.y + 25.0), "싸우기", 12, Color(C_JEOK_HI, la), HORIZONTAL_ALIGNMENT_LEFT, 44.0)
				_mark(Vector2(sp.x + 10.0, r2.position.y + 21.0), 2, la)
				_text(Vector2(sp.x + 18.0, r2.position.y + 25.0), "모시기", 12, Color(C_HANJI, la), HORIZONTAL_ALIGNMENT_LEFT, 44.0)
				if sc.x < 8.0 or sc.x > vs.x - 8.0 or sc.y < 8.0 or sc.y > vs.y - 8.0:
					_edge_arrow(sc, vs, dcol.lightened(0.3))
				continue
			# 두 길 = '◆ 싸워 이기면: …' / '○ 모셔 드리면: …' (design/19 §4.6 — 기호만으로 두지 않음)
			var kx: float = r2.position.x + 19.0
			var kw: float = roundf(_font.get_string_size("모셔 드리면:", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 5.0
			_mark(Vector2(r2.position.x + 11.0, r2.position.y + 22.0), 1, la)
			_text(Vector2(kx, r2.position.y + 26.0), "싸워 이기면:", 12, Color(C_JEOK_HI.darkened(0.15), la), HORIZONTAL_ALIGNMENT_LEFT, kw)
			_text(Vector2(kx + kw, r2.position.y + 26.0), lb[1], 12, Color(C_JEOK_HI, la), HORIZONTAL_ALIGNMENT_LEFT, LBL_W - 24.0 - kw)
			_mark(Vector2(r2.position.x + 11.0, r2.position.y + 36.0), 2, la)
			_text(Vector2(kx, r2.position.y + 40.0), "모셔 드리면:", 12, Color(C_HANJI_DK.lightened(0.2), la), HORIZONTAL_ALIGNMENT_LEFT, kw)
			_text(Vector2(kx + kw, r2.position.y + 40.0), lb[2], 12, Color(C_HANJI, la), HORIZONTAL_ALIGNMENT_LEFT, LBL_W - 24.0 - kw)
			# 원이 화면 밖이면 가장자리 화살표
			if sc.x < 8.0 or sc.x > vs.x - 8.0 or sc.y < 8.0 or sc.y > vs.y - 8.0:
				_edge_arrow(sc, vs, dcol.lightened(0.3))
		# 산통 이름표(월드 위치): '다시 묻기 · 남은 n'
		if td.santong_on and _s_santong != "" and not Game.tutorial_mode:
			var ss: Vector2 = _c.get_viewport().get_canvas_transform() * td.santong_pos
			var sw: float = roundf(_font.get_string_size(_s_santong, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 10.0
			_c.draw_rect(Rect2(roundf(ss.x - sw * 0.5), roundf(ss.y - 33.0), sw, 15.0), Color(C_MEOK, 0.62))
			_text(Vector2(ss.x, ss.y - 22.0), _s_santong, 12, Color(C_HWANG, 0.75 + 0.25 * td.santong_k), HORIZONTAL_ALIGNMENT_CENTER, 140.0)
	# 마당 앵커가 화면 밖(이탈)일 때 방향 화살표
	if ph == TrialDirector.Ph.TRIAL and td.leaving:
		var ct2: Transform2D = _c.get_viewport().get_canvas_transform()
		_edge_arrow(ct2 * td.anchor, vs, C_JEOK_HI)
	# 큰 글자(해결·합일): 0.12s 동안 위에서 6px 내려앉으며 찍힌다. 받침 α0.8(짧게 뜨므로 층 규칙 유지, design/19 §4.6)
	var ba: float = now - _big_t
	if ba >= 0.0 and ba < _big_dur and _s_big != "" and ph != TrialDirector.Ph.JEOMJI:
		var al2: float = clampf((_big_dur - ba) / 0.4, 0.0, 1.0)
		var three: bool = _s_big3 != ""
		# 띠 아래 끝 ≤ y122 — 무당 머리 위를 덮지 않는다(design/18 §2.3). 셋째 줄(결과)이 있으면 붓 32로 줄여 같은 띠 안에.
		var by2: float = roundf(vs.y * 0.27) - (4.0 if three else 0.0)
		var big_size: int = 48 if ph >= TrialDirector.Ph.HAPIL_OMEN else (32 if three else 36)
		var drop: float = roundf(-6.0 * (1.0 - clampf(ba / 0.12, 0.0, 1.0)))
		var bw: float = 300.0 if ph < TrialDirector.Ph.HAPIL_OMEN else 340.0
		var top: float = by2 - (28.0 if three else 34.0)
		var br2: Rect2 = Rect2(cx - bw * 0.5, top, bw, 122.0 - top if three else 58.0)
		_c.draw_rect(br2, Color(C_MEOK, 0.8 * al2))
		vis_rects["center:trial_big"] = [br2, Engine.get_process_frames()]
		_c.draw_rect(Rect2(br2.position.x, br2.position.y, bw, 1), Color(_big_col, 0.8 * al2))
		_c.draw_rect(Rect2(br2.position.x, br2.end.y - 1.0, bw, 1), Color(_big_col, 0.8 * al2))
		_text(Vector2(cx, by2 + drop), _s_big, big_size, Color(_big_col, al2), HORIZONTAL_ALIGNMENT_CENTER, 600.0, _brush)
		_text(Vector2(cx, by2 + (14.0 if three else 17.0)), _s_big2, 12, Color(C_HANJI, al2), HORIZONTAL_ALIGNMENT_CENTER, 500.0)
		if three:
			_text(Vector2(cx, by2 + 26.0), _s_big3, 10, Color(C_HANJI_DK.lightened(0.25), al2), HORIZONTAL_ALIGNMENT_CENTER, 500.0, _small)


func _edge_arrow(sc: Vector2, vs: Vector2, col: Color) -> void:
	var c: Vector2 = vs * 0.5
	var d: Vector2 = (sc - c)
	if d.length_squared() < 1.0:
		return
	d = d.normalized()
	var m: float = 14.0
	var tx: float = INF
	var ty: float = INF
	if absf(d.x) > 0.001:
		tx = ((vs.x * 0.5 - m) / absf(d.x))
	if absf(d.y) > 0.001:
		ty = ((vs.y * 0.5 - m) / absf(d.y))
	var p: Vector2 = c + d * minf(tx, ty)
	var pr: Vector2 = Vector2(-d.y, d.x)
	var tip: Vector2 = p.round()
	var pulse: float = 0.6 + 0.4 * sin(Game.time_sec() * 8.0)
	_c.draw_line(tip, (tip - d * 9.0 + pr * 6.0).round(), Color(col, pulse), 2.0)
	_c.draw_line(tip, (tip - d * 9.0 - pr * 6.0).round(), Color(col, pulse), 2.0)
