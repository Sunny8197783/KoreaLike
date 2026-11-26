extends Node
## WavePresenter — 굿판 타임라인 연출(L3). 소유: waves. SpawnDirector 의 자식으로 _ready 에서 만들어진다.
## 구독만 한다: Events.wave_warn / wave_event / geori_changed / settlement_started. 디렉터 상태는 읽기만 한다.
##  · 예고 띠(낙관 인장 + 제목 + 처음 하는 사람용 한 줄 힌트 + 남은 시간 막대)         — UI 층(CanvasLayer 11)
##  · 거리 전환 제목 카드(붓글씨 거리명 + 장단)                                         — UI 층
##  · 화면 가장자리 위협 표지(떼·창귀 진입 방향, 정예·중간보스·살 덩어리 방향)         — UI 층
##  · 월드 예고: 떼 진로 띠·갈매기 표, 에워싸기 원과 금빛 틈, 고리 가이드 점선 원,
##    작두 충격파 범위, 뒷전 공물상·효과 반경·묶음 안내선, 금줄 굿청, 살 덩어리, 저승사자 — 월드 층(지면 z-2 / 위 z6)
## 규칙: 좌표는 정수 픽셀(K.rndv), 회전·비정수 배율 없음, 색은 art_palette 마스터 램프만(백은 해원·길베 안내에만).
## 연출 시각은 Game.time_sec()(시뮬 시계: 일시정지·히트스톱에서 멈춤). _draw 안에서 할당하지 않는다.

const F_BODY: String = "res://assets/fonts/galmuri/Galmuri11.ttf"
const F_BOLD: String = "res://assets/fonts/galmuri/Galmuri11-Bold.ttf"
const F_SMALL: String = "res://assets/fonts/galmuri/Galmuri9.ttf"
const F_BIG: String = "res://assets/fonts/galmuri/Galmuri14.ttf"
const F_BRUSH: String = "res://assets/fonts/nanum_brush/NanumBrushScript-Regular.ttf"

# 마스터 팔레트(art_palette.json)
const MK: Color = Color("0e0b16")
const MK1: Color = Color("17131f")
const MK2: Color = Color("221c2e")
const MK3: Color = Color("2f2840")
const MK4: Color = Color("3f3654")
const HK: Color = Color("1a1a1a")
const HJ: Color = Color("e9dcc0")
const HJ_UI: Color = Color("f6eedc")
const HJ2: Color = Color("d2c19c")
const HJ3: Color = Color("b29d76")
const HJ4: Color = Color("857154")
const HJ5: Color = Color("5a4a37")
const BK: Color = Color("f2ece0")            # 예약: 해원·길베 안내 전용
const JK0: Color = Color("561318")
const JK1: Color = Color("8c1f22")
const JK: Color = Color("c8322d")
const JK_HI: Color = Color("e4604f")
const HW0: Color = Color("6a4a12")
const HW1: Color = Color("a97c1b")
const HW: Color = Color("e8b931")
const HW_HI: Color = Color("f5d66b")
const ET1: Color = Color("2c221a")
const ET2: Color = Color("433426")
const ET3: Color = Color("5e4b36")
const ET4: Color = Color("7c674b")
const GH5: Color = Color("aab1b5")
const DC_GUN: Color = Color("3b4f6e")

const SAJA: String = "chaser_jeoseung_saja"

var director: Node = null                 # SpawnDirector(읽기 전용)

var _ground: Node2D
var _over: Node2D
var _layer: CanvasLayer
var _ui: Control
var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_big: Font
var _f_brush: Font

var _tele: Dictionary = {}
var _pres: Dictionary = {}
var _glyphs: Dictionary = {}

# ── 예고 띠(대기열)
var _banners: Array[Dictionary] = []      # {title, hint, glyph, accent, t0, dur, fire_at, w}
# ── 거리 카드
var _card: Dictionary = {}
var _card_pending: StringName = &""
# ── 월드 예고/표지
var _warns: Array[Dictionary] = []        # {id, kind, t0, fire_at, geo, ang}
var _paths: Array[Dictionary] = []        # 발동 후 떼 진로 {origin, geo, t0, dur}
var _rings: Array[Dictionary] = []        # 발동 후 에워싸기 {center, geo, t0, dur}
var _guide: Dictionary = {}               # 고리 가이드 {t0, dur, handle}
var _flashes: Array[Dictionary] = []      # 대해원 등 원형 섬광 {c, r, t0, dur, col}
var _silence: Dictionary = {}
var _saja_frames: Dictionary = {}         # anim -> Array[Texture2D]
var _saja_pivot: Dictionary = {}         # anim -> Vector2
var _qbuf: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_qbuf.resize(256)
	_tele = Data.get_value("waves_stage1", "telegraph", {})
	_pres = _tele.get("presenter", {})
	_glyphs = _tele.get("glyph_ko", {})
	_f_body = _font(F_BODY)
	_f_bold = _font(F_BOLD)
	_f_small = _font(F_SMALL)
	_f_big = _font(F_BIG)
	_f_brush = _font(F_BRUSH)
	_ground = Node2D.new()
	_ground.name = "WaveGround"
	_ground.z_index = -2
	add_child(_ground)
	_ground.draw.connect(_draw_ground)
	_over = Node2D.new()
	_over.name = "WaveOver"
	_over.z_index = 6
	add_child(_over)
	_over.draw.connect(_draw_over)
	_layer = CanvasLayer.new()
	_layer.layer = 11
	add_child(_layer)
	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_ui)
	_ui.draw.connect(_draw_ui)
	for a: String in ["appear", "bow_eup", "lead_procession", "float"]:
		var fr: Array[Texture2D] = SpriteLib.anim_frames(SAJA, a, "south")
		_saja_frames[a] = fr
		_saja_pivot[a] = _foot_pivot(fr)
	# 새 규격 저승사자(G3)는 float 만 있다 — 없는 동작은 float 로 대체(core 통합)
	for a2: String in ["appear", "bow_eup", "lead_procession"]:
		if (_saja_frames[a2] as Array).is_empty():
			_saja_frames[a2] = _saja_frames["float"]
			_saja_pivot[a2] = _saja_pivot["float"]
	Events.wave_warn.connect(_on_warn)
	Events.wave_event.connect(_on_event)
	Events.geori_changed.connect(_on_geori)
	Events.settlement_started.connect(_on_settlement)


func _font(p: String) -> Font:
	var f: FontFile = load(p) as FontFile
	if f != null and f.antialiasing != TextServer.FONT_ANTIALIASING_NONE:
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	return f


func _foot_pivot(fr: Array[Texture2D]) -> Vector2:
	if fr.is_empty():
		return Vector2(32, 58)
	var im: Image = fr[0].get_image()
	if im == null:
		return Vector2(fr[0].get_width() / 2, fr[0].get_height() - 6)
	var r: Rect2i = im.get_used_rect()
	return Vector2(im.get_width() / 2, r.end.y - 1)


func _pf(key: String, d: float) -> float:
	return float(_pres.get(key, d))


func _now() -> float:
	return Game.time_sec()


func _player_px() -> Vector2:
	var p: Player = Game.player as Player
	if p == null:
		return Vector2.ZERO
	return p.render_pos


# ─── 신호 → 상태 ───────────────────────────────────────────────────────

func _accent(id: String) -> Color:
	match id:
		"evt_sangcharim", "hapil", "sm_jakdu_last_procession", "daehaewon", "saja_bow", "midboss", "boss_resolved_haewon":
			return HW
		"evt_pullil_demo", "ring_guide", "boss_form_han":
			return HJ
	return JK


func _push_banner(id: String, title: String, hint: String, dur: float, fire_at: float = -1.0, front: bool = false) -> void:
	if title == "":
		return
	var tw: float = _f_big.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if _f_big != null else 120.0
	var hw: float = _f_small.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x if _f_small != null and hint != "" else 0.0
	var w: float = clampf(maxf(tw + 28.0, hw) + 40.0, 160.0, _pf("banner_max_w", 560.0))
	var b: Dictionary = {"title": title, "hint": hint, "glyph": String(_glyphs.get(id, "")), "accent": _accent(id),
		"t0": -1.0, "dur": dur, "fire_at": fire_at, "w": int(w)}
	if front:
		_banners.push_front(b)
	else:
		_banners.append(b)
	while _banners.size() > 4:
		_banners.pop_back()


func _on_warn(id: StringName, in_sec: float, p: Dictionary) -> void:
	var t: float = _now()
	var sid: String = String(id)
	var title: String = String(p.get("title_ko", ""))
	if (sid == "elite" or sid == "midboss") and String(p.get("name_ko", "")) != "":
		title = "%s · %s" % [title, String(p.get("name_ko", ""))]
	var big: bool = sid == "midboss" or sid == "boss"
	_push_banner(sid, title, String(p.get("hint_ko", "")), maxf(in_sec + 1.2, _pf("banner_hold_sec", 3.2)), t + in_sec, big)
	_warns.append({"id": id, "kind": p.get("kind", &"point"), "t0": t, "fire_at": t + in_sec, "geo": p,
		"ang": float(p.get("ang", 0.0))})


func _on_event(id: StringName, p: Dictionary) -> void:
	var t: float = _now()
	var sid: String = String(id)
	# 발동 → 해당 예고 제거
	for k in range(_warns.size() - 1, -1, -1):
		if _warns[k]["id"] == id:
			_warns.remove_at(k)
	match sid:
		"evt_ttemolli", "evt_changgwi_haengnyeol":
			_paths.append({"origin": p.get("origin", Vector2.ZERO), "geo": p, "t0": t, "dur": _pf("after_fire_path_sec", 4.0)})
		"evt_ewossagi":
			var R: float = float(p.get("radius_px", 288.0))
			var v: float = maxf(1.0, float(p.get("shrink_px", 25.6)))
			_rings.append({"center": p.get("origin", Vector2.ZERO), "geo": p, "t0": t,
				"dur": (R - float(p.get("stop_px", 96.0))) / v + 0.5})
		"evt_pullil_demo":
			if t < 30.0:
				_push_banner(sid, String(p.get("title_ko", "")), String(p.get("hint_ko", "")), 3.6)
		"evt_sangcharim":
			_push_banner(sid, String(p.get("title_ko", "")), String(p.get("hint_ko", "")), 5.0, -1.0, true)
		"ring_guide_dotted_circle":
			var tx: Dictionary = (_tele.get("scripted", {}) as Dictionary).get("ring_guide", {})
			_push_banner("ring_guide", String(tx.get("title_ko", "")), String(tx.get("hint_ko", "")), 5.0)
			_guide = {"t0": t, "dur": _pf("ring_guide_sec", 8.0), "r": float(p.get("radius", _pf("ring_guide_radius_u", 3.0))) * K.UNIT_PX}
		"hapil":
			pass  # 합일 호명·형태 큰 글씨는 deities(trial_hud)가 그린다 — 예고 띠를 겹쳐 올리지 않는다
		"sm_jakdu_last_procession", "jakdu_ganglim", "pre_clear":
			# pre_clear 처럼 디렉터가 문구를 싣지 않는 발동은 telegraph.scripted[id] 로 채운다
			var txs: Dictionary = (_tele.get("scripted", {}) as Dictionary).get(sid, {})
			_push_banner(sid, String(p.get("title_ko", txs.get("title_ko", ""))), String(p.get("hint_ko", txs.get("hint_ko", ""))),
				3.6, -1.0, true)
			if sid == "jakdu_ganglim":
				_play_vfx(&"vfx_jakdu_blades", _sim_player(), 2)
		"jakdu_pulse":
			_play_vfx(&"vfx_jakdu_shockwave", p.get("pos", _sim_player()), 3)
			if int(p.get("index", 0)) == 1:
				Juice.feedback(2, p.get("pos", Vector2.ZERO), 0.5)
		"daehaewon":
			var sc: Dictionary = (_tele.get("scripted", {}) as Dictionary).get("dwitjeon_bind", {})
			var bound: int = int(p.get("bound", 3))
			var title: String = String(sc.get("title_ko", "대해원"))
			if bound >= 7:
				title += " — 얼씨구!"
			_push_banner("daehaewon", title, String(sc.get("hint_ko", "")).replace("{n}", str(bound)), 2.6, -1.0, true)
			_flashes.append({"c": p.get("centroid", Vector2.ZERO), "r": float(p.get("radius_px", 120.0)), "t0": t,
				"dur": _pf("daehaewon_ring_sec", 0.6), "col": BK})
			Juice.flash(BK, 0.30, 0.10)
			Juice.feedback(3, p.get("centroid", Vector2.ZERO), 0.6)
		"boss_silence":
			_silence = {"t0": t, "dur": float(p.get("sec", 2.0)) + 0.4}
		"boss_resolved":
			var key: String = "boss_resolved_haewon" if p.get("kind", &"") == K.KIND_HAEWON else "boss_resolved_toechi"
			var tx2: Dictionary = (_tele.get("scripted", {}) as Dictionary).get(key, {})
			_push_banner(key, String(tx2.get("title_ko", "")), String(tx2.get("hint_ko", "")), 3.0, -1.0, true)
		"boss":
			# 기운의 결과: 굿판의 기운(넋 비율·살기)이 이 손님의 얼굴을 정했다 — 선택이 보스를 바꾼다는 것을 보스 등장 때 말한다
			var fk: String = "boss_form_%s" % String(p.get("form", &"han"))
			var txf: Dictionary = (_tele.get("scripted", {}) as Dictionary).get(fk, {})
			_push_banner(fk, String(txf.get("title_ko", "")), String(txf.get("hint_ko", "")), 4.6, -1.0, true)
		"midboss_exit", "sal_lump":
			var tx3: Dictionary = (_tele.get("scripted", {}) as Dictionary).get(sid, {})
			_push_banner(sid, String(tx3.get("title_ko", "")), String(tx3.get("hint_ko", "")), 3.2, -1.0, sid == "sal_lump")
		"elite":
			pass


func _on_settlement(r: StringName, p: Dictionary) -> void:
	# enemies(bigs) 저승사자가 낸 신호에는 문구가 없다 → telegraph.scripted[route] 로 채운다
	var tx: Dictionary = (_tele.get("scripted", {}) as Dictionary).get(String(r), {})
	var title: String = String(p.get("title_ko", tx.get("title_ko", "")))
	var hint: String = String(p.get("hint_ko", tx.get("hint_ko", "")))
	_push_banner(String(r), title, hint, 4.0, -1.0, true)


func _on_geori(geori_id: StringName, bpm: float, _j: StringName) -> void:
	# 시련 안내판(강림·고르기·시련 중)이 화면 위쪽을 쓰는 동안에는 큰 거리 카드를 띄우지 않는다(겹침 방지, core 통합).
	# 거리 이름은 HUD 시계 아래 줄·음악 전환으로 전달된다.
	var rr: Node = Game.run_root
	var td: TrialDirector = (rr.get("trials") as TrialDirector) if rr != null else null
	if td != null and td.ph >= TrialDirector.Ph.OMEN and td.ph <= TrialDirector.Ph.RESOLVE:
		_card = {}
		return
	# 합일(HAPIL_OMEN 이후)에는 거리 카드를 띄우지 않는다 — 시계 아래 거리 줄이 대신 말한다(design/18 §2.3).
	if td != null and td.ph >= TrialDirector.Ph.HAPIL_OMEN:
		_card = {}
		return
	for g: Variant in Data.get_value("waves_stage1", "geori", []):
		if g is Dictionary and String(g.get("id", "")) == String(geori_id):
			var gd: Dictionary = g
			var sub: String = String(gd.get("jangdan_ko", ""))
			if bpm > 0.0:
				sub = "%s · %d" % [sub, int(bpm)]
			_card = {"title": String(gd.get("name_ko", "")), "sub": sub, "line": String(gd.get("subtitle_ko", "")), "t0": -1.0,
				"dur": _pf("card_sec", 3.2)}
			return


func _sim_player() -> Vector2:
	return Game.player.global_position if Game.player != null else Vector2.ZERO


func _play_vfx(id: StringName, pos: Vector2, scl: int) -> void:
	var vp: VfxPlayer = Game.vfx as VfxPlayer
	if vp != null:
		vp.play(id, pos, 0.0, float(scl))


# ─── 매 프레임 ─────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if director == null or Game.player == null:
		return
	var t: float = _now()
	# 만료 정리
	if not _banners.is_empty():
		var b: Dictionary = _banners[0]
		if float(b["t0"]) < 0.0:
			b["t0"] = t
		elif t - float(b["t0"]) > float(b["dur"]):
			_banners.pop_front()
			if not _banners.is_empty():
				_banners[0]["t0"] = t
	if not _card.is_empty():
		if float(_card["t0"]) < 0.0 and t >= float(Data.num("waves_stage1", "runtime.geori_card_min_time_sec", 3.0)):
			# 예고 띠(y 84~118)와 거리 카드(y ~104~161)가 겹치지 않게: 띠가 떠 있으면 카드는 띠가 걷힌 뒤(최대 card_wait_max_sec)
			if not _card.has("q"):
				_card["q"] = t
			if _banners.is_empty() or t - float(_card["q"]) > _pf("card_wait_max_sec", 6.0):
				# 대기 중에 시련 예고~해결이 시작됐으면 카드를 버린다(시련 안내판과 겹침 방지, 리드 11-24).
				var rr2: Node = Game.run_root
				var td2: TrialDirector = (rr2.get("trials") as TrialDirector) if rr2 != null else null
				if td2 != null and ((td2.ph >= TrialDirector.Ph.OMEN and td2.ph <= TrialDirector.Ph.RESOLVE) or td2.ph >= TrialDirector.Ph.HAPIL_OMEN):
					_card = {}
				elif t >= float(_card.get("retry_at", -1.0)):
					# 가운데 슬롯(prio 2). 차지 못하면 0.5초마다 다시, 처음 시도 뒤 2초가 지나면 버린다.
					if _claim_card(float(_card["dur"])):
						_card["t0"] = t
					else:
						if not _card.has("c0"):
							_card["c0"] = t
						if t - float(_card["c0"]) > 2.0:
							_card = {}
						else:
							_card["retry_at"] = t + 0.5
		elif float(_card["t0"]) >= 0.0 and t - float(_card["t0"]) > float(_card["dur"]):
			_card = {}
	for k in range(_warns.size() - 1, -1, -1):
		if t > float(_warns[k]["fire_at"]) + 1.0:
			_warns.remove_at(k)
	for k in range(_paths.size() - 1, -1, -1):
		if t - float(_paths[k]["t0"]) > float(_paths[k]["dur"]):
			_paths.remove_at(k)
	for k in range(_rings.size() - 1, -1, -1):
		if t - float(_rings[k]["t0"]) > float(_rings[k]["dur"]):
			_rings.remove_at(k)
	for k in range(_flashes.size() - 1, -1, -1):
		if t - float(_flashes[k]["t0"]) > float(_flashes[k]["dur"]):
			_flashes.remove_at(k)
	if not _guide.is_empty() and t - float(_guide["t0"]) > float(_guide["dur"]):
		_guide = {}
	if not _silence.is_empty() and t - float(_silence["t0"]) > float(_silence["dur"]):
		_silence = {}
	_ground.queue_redraw()
	_over.queue_redraw()
	_ui.queue_redraw()


## 가시성 측정(tests/vis_probe.gd): 이번 프레임에 그린 화면 글 사각형. 키 → [Rect2(640×360 기준), 그린 프레임].
var vis_rects: Dictionary = {}


## 거리 카드가 지금 그려지는가(HUD 공수 레인이 같은 위 구역에 겹쳐 그리지 않게).
func card_on() -> bool:
	return not _card.is_empty() and float(_card["t0"]) >= 0.0 and _card_owns_center() and (_banners.is_empty() or float(_banners[0]["t0"]) < 0.0)


## 위 띠(예고 띠)가 지금 떠 있는가 — HUD 공수 레인이 겹쳐 올리지 않게(읽기 전용).
func banner_on() -> bool:
	return not _banners.is_empty() and float(_banners[0]["t0"]) >= 0.0


## 거리 카드 가운데 슬롯(design/18 §2.2, prio 2).
func _claim_card(dur: float) -> bool:
	if not Juice.has_method(&"claim_center"):
		return true
	return bool(Juice.call(&"claim_center", &"geori_card", 2, dur))


## 다른 주인이 가운데를 가져갔으면 카드를 그리지 않는다(시간은 그대로 흐른다).
func _card_owns_center() -> bool:
	var o: Variant = Juice.get(&"center_owner")
	if o == null or not Juice.has_method(&"center_busy"):
		return true
	return StringName(o) == &"geori_card" or not bool(Juice.call(&"center_busy", 0))


# ─── 그리기 도우미(정수 픽셀) ──────────────────────────────────────────

func _px(p: Vector2) -> Vector2:
	return K.rndv(p)


func _dot(ci: CanvasItem, p: Vector2, col: Color, s: int = 1) -> void:
	ci.draw_rect(Rect2(K.rndv(p), Vector2(s, s)), col)


func _seg(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float = 1.0) -> void:
	var off: Vector2 = Vector2(0.5, 0.5) if w <= 1.0 else Vector2.ZERO
	ci.draw_line(K.rndv(a) + off, K.rndv(b) + off, col, w, false)


## 점선 원: 대시 dash_px, 간격 gap_px, 위상 phase_px(회전 애니), 굵기 w. 화면 밖 대시는 건너뛴다.
func _dashed_circle(ci: CanvasItem, c: Vector2, r: float, col: Color, dash_px: float, gap_px: float, phase_px: float, w: int,
		view: Rect2) -> void:
	if r < 2.0:
		return
	var circ: float = TAU * r
	var step: float = dash_px + gap_px
	var n: int = mini(int(circ / step), 720)
	if n <= 0:
		return
	var da: float = TAU / float(n)
	var dl: float = da * dash_px / step
	var a0: float = phase_px / r
	for k in n:
		var a: float = a0 + da * float(k)
		var p0: Vector2 = c + Vector2(cos(a), sin(a)) * r
		if not view.has_point(p0):
			continue
		var p1: Vector2 = c + Vector2(cos(a + dl), sin(a + dl)) * r
		if w <= 1:
			_seg(ci, p0, p1, col, 1.0)
		else:
			_dot(ci, p0, col, w)
			_dot(ci, p1, col, w)


func _arc_thick(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, col: Color, w: int) -> void:
	var n: int = maxi(2, int(absf(a1 - a0) * r / 2.0))
	for k in n + 1:
		var a: float = lerpf(a0, a1, float(k) / float(n))
		_dot(ci, c + Vector2(cos(a), sin(a)) * r - Vector2(w * 0.5, w * 0.5), col, w)


## 갈매기(>) 표: 진행 방향 d, 크기 s.
func _chevron(ci: CanvasItem, p: Vector2, d: Vector2, s: float, col: Color) -> void:
	var n: Vector2 = Vector2(-d.y, d.x)
	var tip: Vector2 = p + d * s * 0.5
	_seg(ci, tip, p - d * s * 0.5 + n * s * 0.6, col, 1.0)
	_seg(ci, tip, p - d * s * 0.5 - n * s * 0.6, col, 1.0)
	_seg(ci, tip - d, p - d * s * 0.5 - d + n * s * 0.6, col, 1.0)
	_seg(ci, tip - d, p - d * s * 0.5 - d - n * s * 0.6, col, 1.0)


func _view_rect() -> Rect2:
	var inv: Transform2D = _ground.get_viewport().get_canvas_transform().affine_inverse()
	var sz: Vector2 = _ground.get_viewport_rect().size
	var a: Vector2 = inv * Vector2.ZERO
	var b: Vector2 = inv * sz
	return Rect2(a, b - a).grow(24.0)


func _beat_pulse() -> float:
	return 1.0 - Beat.beat_phase()


# ─── 지면 층(z -2): 원·띠·공물상·금줄·덩어리 ──────────────────────────

func _draw_ground() -> void:
	if director == null:
		return
	var t: float = _now()
	var view: Rect2 = _view_rect()
	var pr: Vector2 = _player_px()
	var bp: float = _beat_pulse()
	# 예고: 떼 진로 / 에워싸기 원
	for w: Dictionary in _warns:
		var kind: StringName = w["kind"]
		var g: Dictionary = w["geo"]
		var left: float = float(w["fire_at"]) - t
		var urgency: float = clampf(1.0 - left / 3.5, 0.0, 1.0)
		if kind == &"band" or kind == &"column":
			_draw_band(pr, g, t - float(w["t0"]), 0.35 + 0.45 * urgency, view)
		elif kind == &"ring":
			_draw_ring_warn(pr, float(g.get("radius_px", 288.0)), g, 0.4 + 0.5 * urgency, t, view)
			_draw_gap_guide(pr, pr, float(g.get("radius_px", 288.0)), g, 0.55 + 0.45 * urgency, t)
	for p: Dictionary in _paths:
		var e: float = t - float(p["t0"])
		_draw_band(K.rndv(p["origin"]), p["geo"], e + 3.0, 0.5 * (1.0 - e / float(p["dur"])), view)
	for r: Dictionary in _rings:
		var g2: Dictionary = r["geo"]
		var e2: float = t - float(r["t0"])
		var rad: float = maxf(float(g2.get("stop_px", 96.0)), float(g2.get("radius_px", 288.0)) - float(g2.get("shrink_px", 25.6)) * e2)
		_draw_ring_warn(K.rndv(r["center"]), rad, g2, 0.9 * (1.0 - e2 / float(r["dur"])), t, view)
		if e2 < _pf("gap_guide_after_fire_sec", 4.0):
			_draw_gap_guide(pr, K.rndv(r["center"]), rad, g2, 0.9 * (1.0 - e2 / _pf("gap_guide_after_fire_sec", 4.0)), t)
	# 작두 강림 범위
	if bool(director.get("jakdu_active")):
		var jr: float = Data.num("waves_stage1", "jakdu_ganglim.radius_u", 4.5) * K.UNIT_PX
		var jc: Color = JK1
		jc.a = 0.55 + 0.45 * bp
		_dashed_circle(_ground, pr, jr, jc, 6.0, 4.0, -t * 24.0, 1, view)
	# 고리 가이드(01:30) — 백 점선: 길베 예상선
	if not _guide.is_empty():
		_draw_ring_guide(t, view)
	# 뒷전 공물상
	if bool(director.get("dw_active")):
		_draw_dwitjeon(t, pr, view, bp)
	# 금줄 굿청
	var ph: int = int(director.get("phase"))
	if ph == 2 or ph == 3:
		_draw_geumjul(K.rndv(director.get("arena_center")), float(director.get("arena_r")), view, t)
	# 살 덩어리
	if ph == 5 and director.get("route") == &"sal_geodum":
		_draw_lumps(t, bp)
	# 섬광 원(대해원)
	for f: Dictionary in _flashes:
		var k: float = (t - float(f["t0"])) / float(f["dur"])
		var col: Color = f["col"]
		col.a = 1.0 - k
		_dashed_circle(_ground, K.rndv(f["c"]), float(f["r"]) * (0.6 + 0.6 * k), col, 3.0, 2.0, 0.0, 2, view)


func _draw_band(pr: Vector2, g: Dictionary, age: float, alpha: float, view: Rect2) -> void:
	var dirs: PackedVector2Array = g.get("dirs", PackedVector2Array())
	var starts: PackedVector2Array = g.get("starts", PackedVector2Array())
	var widths: PackedFloat32Array = g.get("widths", PackedFloat32Array())
	var speeds: PackedFloat32Array = g.get("speeds", PackedFloat32Array())
	var cross: float = float(g.get("cross_px", 1152.0))
	var gap: float = _pf("band_chevron_gap_px", 40.0)
	for i in dirs.size():
		var d: Vector2 = dirs[i]
		var n: Vector2 = Vector2(-d.y, d.x)
		var s0: Vector2 = pr + starts[i]
		var hw: float = (widths[i] if i < widths.size() else 128.0) * 0.5
		var spd: float = speeds[i] if i < speeds.size() else 70.0
		var edge: Color = JK1
		edge.a = alpha
		# 가장자리 점선 2줄
		var steps: int = int(cross / 10.0)
		for k in steps:
			if k % 2 == 1:
				continue
			var a: Vector2 = s0 + d * (float(k) * 10.0)
			if not view.has_point(a):
				continue
			_seg(_ground, a + n * hw, a + d * 6.0 + n * hw, edge)
			_seg(_ground, a - n * hw, a + d * 6.0 - n * hw, edge)
		# 흐르는 갈매기 표(떼의 진행 속도로 흐른다)
		var chev: Color = JK
		chev.a = alpha
		var off: float = fposmod(age * spd, gap)
		var cnt: int = int(cross / gap)
		for k in cnt:
			var c: Vector2 = s0 + d * (off + float(k) * gap)
			if view.has_point(c):
				_chevron(_ground, c, d, 8.0, chev)


func _draw_ring_warn(c: Vector2, rad: float, g: Dictionary, alpha: float, t: float, view: Rect2) -> void:
	var col: Color = JK1
	col.a = alpha
	_dashed_circle(_ground, c, rad, col, 5.0, 5.0, t * 8.0, 1, view)
	var gaps: PackedFloat32Array = g.get("gaps", PackedFloat32Array())
	var gh: float = float(g.get("gap_half", 0.14))
	var gold: Color = HW
	gold.a = minf(1.0, alpha + 0.3)
	for a: float in gaps:
		_arc_thick(_ground, c, rad, a - gh, a - gh + 0.03, gold, 2)
		_arc_thick(_ground, c, rad, a + gh - 0.03, a + gh, gold, 2)
		# 틈 바깥으로 빠져나가는 화살(금빛)
		var u: Vector2 = Vector2(cos(a), sin(a))
		var p0: Vector2 = c + u * (rad - 10.0)
		var p1: Vector2 = c + u * (rad + 14.0)
		_seg(_ground, p0, p1, gold)
		_chevron(_ground, p1, u, 7.0, gold)


## 에워싸기 틈 안내: 플레이어 → 가장 가까운 금빛 틈까지 흐르는 금 점선 + 갈매기(원이 화면보다 커서 틈이 화면 밖일 때가 많다).
func _draw_gap_guide(pr: Vector2, c: Vector2, rad: float, g: Dictionary, alpha: float, t: float) -> void:
	var gaps: PackedFloat32Array = g.get("gaps", PackedFloat32Array())
	if gaps.is_empty() or alpha <= 0.0:
		return
	var best: Vector2 = Vector2.ZERO
	var bd: float = 1e18
	for a: float in gaps:
		var gp: Vector2 = c + Vector2(cos(a), sin(a)) * (rad + 12.0)
		var d: float = gp.distance_squared_to(pr)
		if d < bd:
			bd = d
			best = gp
	var seg: Vector2 = best - pr
	var ln: float = seg.length()
	if ln < 24.0:
		return
	var u: Vector2 = seg / ln
	var gold: Color = HW
	gold.a = clampf(alpha, 0.0, 1.0) * (0.7 + 0.3 * _beat_pulse())
	var step: float = 14.0
	var off: float = fposmod(t * 42.0, step)
	var k: float = 22.0 + off
	while k < ln - 6.0:
		var p: Vector2 = pr + u * k
		_seg(_ground, p, p + u * 5.0, gold)
		k += step
	_chevron(_ground, best - u * 4.0, u, 8.0, gold)


func _draw_ring_guide(t: float, view: Rect2) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	var c: Vector2 = _sim_player()
	if em != null:
		var best: int = -1
		var bd: float = 1e18
		var n: int = em.query_circle(c, 8.0 * K.UNIT_PX, _qbuf, 256)
		for k in n:
			var s: int = _qbuf[k]
			if em.is_alive(s) and (em.flags[s] & EnemyManager.F_PULLIL) != 0:
				var d: float = em.pos_of(s).distance_squared_to(c)
				if d < bd:
					bd = d
					best = s
		if best >= 0:
			c = em.pos_of(best)
	var e: float = t - float(_guide["t0"])
	var col: Color = BK
	col.a = clampf(minf(e * 3.0, (float(_guide["dur"]) - e) * 2.0), 0.0, 1.0) * (0.6 + 0.4 * _beat_pulse())
	_dashed_circle(_ground, K.rndv(c), float(_guide["r"]), col, 4.0, 4.0, e * 30.0, 2, view)


## 뒷전 소반: 다리·상판(흙 램프) + 떡·과일·잔·촛불. 남은 음복 횟수 = 위쪽 황 점.
func _draw_soban(p: Vector2, serv: int, t: float, idx: int) -> void:
	var o: Vector2 = K.rndv(p)
	var ci: CanvasItem = _ground
	var dim: bool = serv <= 0
	ci.draw_rect(Rect2(o + Vector2(-11, 1), Vector2(22, 3)), HK)                 # 그림자 겸 외곽
	ci.draw_rect(Rect2(o + Vector2(-9, -2), Vector2(2, 5)), ET1)                 # 다리
	ci.draw_rect(Rect2(o + Vector2(7, -2), Vector2(2, 5)), ET1)
	ci.draw_rect(Rect2(o + Vector2(-11, -5), Vector2(22, 4)), HK)
	ci.draw_rect(Rect2(o + Vector2(-10, -4), Vector2(20, 2)), ET3)               # 상판
	ci.draw_rect(Rect2(o + Vector2(-10, -4), Vector2(20, 1)), ET4)
	if dim:
		return
	ci.draw_rect(Rect2(o + Vector2(-8, -8), Vector2(6, 4)), HJ2)                 # 떡
	ci.draw_rect(Rect2(o + Vector2(-8, -8), Vector2(6, 1)), HJ)
	ci.draw_rect(Rect2(o + Vector2(-1, -7), Vector2(3, 3)), JK)                  # 과일
	ci.draw_rect(Rect2(o + Vector2(0, -7), Vector2(1, 1)), JK_HI)
	ci.draw_rect(Rect2(o + Vector2(3, -7), Vector2(3, 3)), GH5)                  # 잔
	ci.draw_rect(Rect2(o + Vector2(7, -9), Vector2(1, 5)), HJ)                   # 초
	var fl: int = 1 if fposmod(t * 8.0 + float(idx) * 0.37, 1.0) < 0.5 else 0
	ci.draw_rect(Rect2(o + Vector2(7, -11 - fl), Vector2(1, 2)), HW)             # 불꽃(박 없이 깜박)
	for k in serv:
		ci.draw_rect(Rect2(o + Vector2(-3 + k * 4, -14), Vector2(2, 2)), HW_HI)  # 음복 남은 횟수


func _draw_dwitjeon(t: float, pr: Vector2, view: Rect2, bp: float) -> void:
	var pos: PackedVector2Array = director.get("dw_pos")
	var serv: PackedInt32Array = director.get("dw_serv")
	var r: float = float(director.get("dw_radius"))
	var rc: Color = HW1
	rc.a = 0.45 + 0.35 * bp
	for i in pos.size():
		if serv[i] > 0:
			_dashed_circle(_ground, K.rndv(pos[i]), r, rc, 3.0, 5.0, t * 6.0, 1, view)
	for i in pos.size():
		_draw_soban(pos[i], serv[i], t, i)
	# 묶음 안내(처음 guide_sec 동안): 플레이어에 가장 가까운 공물상 셋을 감싸는 백 점선(길베 예상선)
	var age: float = t - float(director.get("dw_t0"))
	if age < Data.num("waves_stage1", "runtime.dwitjeon.guide_sec", 12.0) and int(director.get("dw_count")) == 0:
		var a: int = -1
		var b: int = -1
		var c: int = -1
		var da: float = 1e18
		var db: float = 1e18
		var dc: float = 1e18
		for i in pos.size():
			if serv[i] <= 0:
				continue
			var d: float = pos[i].distance_squared_to(pr)
			if d < da:
				c = b
				dc = db
				b = a
				db = da
				a = i
				da = d
			elif d < db:
				c = b
				dc = db
				b = i
				db = d
			elif d < dc:
				c = i
				dc = d
		if c >= 0:
			var cen: Vector2 = (pos[a] + pos[b] + pos[c]) / 3.0
			var rad: float = maxf(cen.distance_to(pos[a]), maxf(cen.distance_to(pos[b]), cen.distance_to(pos[c]))) + 0.9 * K.UNIT_PX
			var gc: Color = BK
			gc.a = 0.5 + 0.5 * bp
			_dashed_circle(_ground, K.rndv(cen), rad, gc, 4.0, 4.0, age * 30.0, 2, view)


## 금줄 굿청: 꼰 새끼줄(한지 4·5 램프 교대) + 한지 술(4px) + 고추(적)·숯(먹) — 화면 안 구간만.
func _draw_geumjul(c: Vector2, r: float, view: Rect2, t: float) -> void:
	var n: int = int(TAU * r / 4.0)
	for k in n:
		var a: float = TAU * float(k) / float(n)
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
		if not view.has_point(p):
			continue
		_dot(_ground, p, HJ4 if k % 2 == 0 else HJ5, 2)
		if k % 10 == 0:
			_ground.draw_rect(Rect2(K.rndv(p) + Vector2(0, 2), Vector2(2, 4 + (k / 10) % 2)), HJ)    # 한지 술
		elif k % 10 == 5:
			if (k / 10) % 2 == 0:
				_ground.draw_rect(Rect2(K.rndv(p) + Vector2(0, 2), Vector2(2, 3)), JK)                # 고추
			else:
				_ground.draw_rect(Rect2(K.rndv(p) + Vector2(0, 2), Vector2(2, 2)), MK3)               # 숯


func _draw_lumps(t: float, bp: float) -> void:
	var lumps: PackedVector2Array = director.get("lumps")
	var done: int = int(director.get("lumps_done"))
	var idx: int = int(director.get("lump_idx"))
	var per: float = Data.num("combat_core", "run_end.E3_sal_geodum.collect_sec_per_lump", 30.0)
	for k in lumps.size():
		if k < done:
			continue
		var o: Vector2 = K.rndv(lumps[k])
		var s: int = 7 + (1 if bp > 0.6 else 0)
		_ground.draw_rect(Rect2(o - Vector2(s + 1, s / 2 + 1), Vector2(2 * s + 2, s + 2)), HK)
		_ground.draw_rect(Rect2(o - Vector2(s, s / 2), Vector2(2 * s, s)), MK2)
		_ground.draw_rect(Rect2(o - Vector2(s - 3, s / 2 - 2), Vector2(2 * s - 6, s - 4)), JK0)
		_ground.draw_rect(Rect2(o - Vector2(2, 1), Vector2(2, 1)), JK)                           # 붉은 눈 한 점
		if k == idx:
			var prog: float = clampf(float(director.get("lump_t")) / per, 0.0, 1.0)
			_arc_thick(_ground, o, 20.0, -PI * 0.5, -PI * 0.5 + TAU * prog, HW, 2)


# ─── 위 층(z 6): 저승사자 ─────────────────────────────────────────────

func _draw_over() -> void:
	if director == null or int(director.get("phase")) != 5:
		return
	var sh: int = int(director.get("saja_h"))
	var em: EnemyManager = Game.enemies as EnemyManager
	if sh >= 0 and em != null and em.slot_of(sh) >= 0:
		return  # enemies 가 저승사자 개체를 그린다
	var r: StringName = director.get("route")
	var st: float = float(director.get("settle_t"))
	var pr: Vector2 = _player_px()
	var anim: String = "float"
	var fps: float = 10.0
	var at: float = st
	var pos: Vector2 = pr + Vector2(0, -64)
	if r == &"saja_bow" or r == &"timeout":
		if st < 0.8:
			anim = "appear"
		elif st < 2.5 or r == &"timeout":
			anim = "float"
			at = st - 0.8
		else:
			anim = "bow_eup"
			at = st - 2.5
	elif r == &"sal_geodum":
		var lumps: PackedVector2Array = director.get("lumps")
		var idx: int = int(director.get("lump_idx"))
		if idx < lumps.size():
			pos = K.rndv(lumps[idx]) + Vector2(0, -22)
			anim = "lead_procession"
		else:
			anim = "bow_eup"
	var fr: Array = _saja_frames.get(anim, [])
	if fr.is_empty():
		return
	var loop: bool = anim == "float" or anim == "lead_procession"
	var fi: int = int(at * fps)
	fi = fi % fr.size() if loop else mini(fi, fr.size() - 1)
	var tex: Texture2D = fr[fi]
	var pv: Vector2 = _saja_pivot.get(anim, Vector2(32, 58))
	_over.draw_texture(tex, K.rndv(pos - pv))


# ─── UI 층(CanvasLayer 11): 예고 띠·거리 카드·가장자리 표지 ────────────

func _draw_ui() -> void:
	if director == null:
		return
	var t: float = _now()
	var vs: Vector2 = _ui.get_viewport_rect().size
	if not _silence.is_empty():
		var e: float = t - float(_silence["t0"])
		var d: float = float(_silence["dur"])
		var a: float = clampf(minf(e / 0.3, (d - e) / 0.4), 0.0, 1.0) * _pf("silence_dim_alpha", 0.45)
		var mc: Color = MK
		mc.a = a
		_ui.draw_rect(Rect2(Vector2.ZERO, vs), mc)
	_draw_edges(t, vs)
	if not _card.is_empty() and float(_card["t0"]) >= 0.0 and (_banners.is_empty() or float(_banners[0]["t0"]) < 0.0) and _card_owns_center():
		_draw_card(t, vs)  # 카드 도중 예고가 오면 예고가 우선(겹쳐 그리지 않는다)
	if not _banners.is_empty() and float(_banners[0]["t0"]) >= 0.0:
		_draw_banner(_banners[0], t, vs)


func _draw_banner(b: Dictionary, t: float, vs: Vector2) -> void:
	var e: float = t - float(b["t0"])
	var dur: float = float(b["dur"])
	var op: float = _pf("banner_open_sec", 0.12)
	var cl: float = _pf("banner_close_sec", 0.25)
	var k_open: float = clampf(e / op, 0.0, 1.0)
	k_open = 1.0 - (1.0 - k_open) * (1.0 - k_open)
	var alpha: float = clampf((dur - e) / cl, 0.0, 1.0)
	var w: int = int(float(b["w"]) * k_open)
	if w < 8:
		return
	var h: int = int(_pf("banner_h", 34.0))
	var y: int = int(_pf("banner_y", 84.0))
	var x: int = int(vs.x * 0.5) - w / 2
	var bg: Color = MK
	bg.a = 0.84 * alpha
	var rule: Color = HJ4
	rule.a = alpha
	var acc: Color = b["accent"]
	acc.a = alpha
	_ui.draw_rect(Rect2(x, y, w, h), bg)
	vis_rects["top:wave_band"] = [Rect2(x, y, w, h), Engine.get_process_frames()]
	_ui.draw_rect(Rect2(x, y, w, 1), rule)
	_ui.draw_rect(Rect2(x, y + h - 1, w, 1), rule)
	_ui.draw_rect(Rect2(x + 2, y + 2, w - 4, 1), Color(acc.r, acc.g, acc.b, 0.45 * alpha))
	# 양 끝 매듭(먹 띠를 묶는 실)
	_ui.draw_rect(Rect2(x - 2, y + h / 2 - 2, 2, 4), acc)
	_ui.draw_rect(Rect2(x + w, y + h / 2 - 2, 2, 4), acc)
	if k_open < 1.0:
		return
	# 낙관 인장
	var sx: int = x + 8
	var sy: int = y + 8
	_ui.draw_rect(Rect2(sx - 1, sy - 1, 18, 18), Color(HK.r, HK.g, HK.b, alpha))
	_ui.draw_rect(Rect2(sx, sy, 16, 16), acc)
	var gl: String = b["glyph"]
	if gl != "" and _f_bold != null:
		var gc: Color = HJ_UI if acc.v < 0.7 else MK
		gc.a = alpha
		_ui.draw_string(_f_bold, Vector2(sx + 2, sy + 13), gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, gc)
	# 제목 + 힌트
	var tx: int = sx + 24
	var title_col: Color = HJ_UI
	title_col.a = alpha
	var sh: Color = MK
	sh.a = alpha
	if _f_big != null:
		_ui.draw_string(_f_big, Vector2(tx + 1, y + 17), b["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, sh)
		_ui.draw_string(_f_big, Vector2(tx, y + 16), b["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, title_col)
	var hint: String = b["hint"]
	if hint != "" and _f_small != null:
		var hc: Color = HJ2
		hc.a = alpha
		_ui.draw_string(_f_small, Vector2(tx, y + 29), hint, HORIZONTAL_ALIGNMENT_LEFT, w - (tx - x) - 6, 10, hc)
	# 남은 시간 막대(예고일 때): 띠 아래 2px, 발동 순간 0
	var fa: float = float(b["fire_at"])
	if fa > 0.0:
		var left: float = fa - t
		if left > 0.0:
			var tot: float = maxf(0.1, fa - float(b["t0"]))
			var bw: int = int(float(w - 4) * clampf(left / tot, 0.0, 1.0))
			_ui.draw_rect(Rect2(x + 2, y + h + 1, bw, 2), acc)


func _draw_card(t: float, vs: Vector2) -> void:
	var e: float = t - float(_card["t0"])
	var d: float = float(_card["dur"])
	var a: float = clampf(minf(e / 0.4, (d - e) / 0.5), 0.0, 1.0)
	if a <= 0.0 or _f_brush == null:
		return
	# 제목 기준선 y. 먹 띠는 y−34 ~ y+30 → 띠 아래 끝 y122(card_y 92, ≤ y122), 무당 머리 위를 덮지 않는다(design/18 §2.3).
	var y: int = int(_pf("card_y", 92.0))
	var cx: int = int(vs.x * 0.5)
	var title: String = _card["title"]
	var tw: int = int(_f_brush.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x)
	var sub: String = _card["sub"]
	var line: String = _card["line"]
	var sw: int = int(_f_body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) if _f_body != null else 0
	var lw: int = int(_f_small.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x) if (line != "" and _f_small != null) else 0
	# 먹 띠(α0.55) + 위아래 단청 1px(적·청·황 6px 마디)
	var bw: int = maxi(maxi(tw, sw + 52), lw) + 40
	var bx: int = cx - bw / 2
	var by0: int = y - 34
	var by1: int = y + 30
	_ui.draw_rect(Rect2(bx, by0, bw, by1 - by0), Color(MK.r, MK.g, MK.b, 0.55 * a))
	vis_rects["center:wave_card"] = [Rect2(bx, by0, bw, by1 - by0), Engine.get_process_frames()]
	var dc: Array[Color] = [JK, DC_GUN, HW, DC_GUN]
	var xx: int = bx
	var di: int = 0
	while xx < bx + bw:
		var sw6: int = mini(6, bx + bw - xx)
		var c6: Color = dc[di % 4]
		c6.a = 0.85 * a
		_ui.draw_rect(Rect2(xx, by0, sw6, 1), c6)
		_ui.draw_rect(Rect2(xx, by1 - 1, sw6, 1), c6)
		xx += 6
		di += 1
	var sh: Color = MK
	sh.a = a
	var col: Color = HJ
	col.a = a
	# 붓 제목은 기준선 아래로 약 8px 내려온다(받침·삐침) — 기준선을 10px 올리고 장단 줄을 2px 내려 둘 사이를 8px 띄운다
	# (톤 리뷰 11-25: '진양조 · 45' 가 붓 제목 아래 끝에 겹쳐 찍혔다, tutorial/final2/practice/01_move_z_name)
	_brush_str(Vector2(cx - tw / 2 + 2, y - 8), title, sh)
	_brush_str(Vector2(cx - tw / 2, y - 10), title, col)
	if _f_body != null:
		var rc: Color = JK
		rc.a = a
		_ui.draw_rect(Rect2(cx - sw / 2 - 26, y + 12, 18, 1), rc)
		_ui.draw_rect(Rect2(cx + sw / 2 + 8, y + 12, 18, 1), rc)
		var sc: Color = HJ2
		sc.a = a
		_ui.draw_string(_f_body, Vector2(cx - sw / 2 + 1, y + 17), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sh)
		_ui.draw_string(_f_body, Vector2(cx - sw / 2, y + 16), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sc)
	if lw > 0:
		var lc: Color = HJ3
		lc.a = a
		_ui.draw_string(_f_small, Vector2(cx - lw / 2, y + 27), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lc)


## 붓 글꼴의 가운뎃점(·)은 따옴표처럼 위로 뜬다 → 글자 높이 가운데에 먹/한지 점을 직접 찍는다(TutDraw.brush_text 와 같은 방식).
func _brush_str(pos: Vector2, s: String, col: Color) -> void:
	if not s.contains("·"):
		_ui.draw_string(_f_brush, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, col)
		return
	var x: float = pos.x
	var dw: float = _f_brush.get_string_size("·", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var parts: PackedStringArray = s.split("·")
	for i in parts.size():
		if parts[i] != "":
			_ui.draw_string(_f_brush, Vector2(x, pos.y), parts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 32, col)
			x += _f_brush.get_string_size(parts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
		if i < parts.size() - 1:
			_ui.draw_rect(Rect2(roundf(x + dw * 0.5 - 1.5), roundf(pos.y - 12.0), 3, 3), col)
			x += dw


## 화면 가장자리 표지: 월드 점이 화면 밖이면 가장자리에 붉은 마름모 + 안쪽 화살. 박에 맞춰 1px 맥동.
func _draw_edges(t: float, vs: Vector2) -> void:
	var xf: Transform2D = _ui.get_viewport().get_canvas_transform()
	var pw: Vector2 = _sim_player()
	var bp: float = _beat_pulse()
	for w: Dictionary in _warns:
		var kind: StringName = w["kind"]
		var g: Dictionary = w["geo"]
		var id: StringName = w["id"]
		var urgent: bool = float(w["fire_at"]) - t < 1.2
		if kind == &"band" or kind == &"column":
			var starts: PackedVector2Array = g.get("starts", PackedVector2Array())
			for s: Vector2 in starts:
				_edge_marker(xf * (pw + s), vs, JK, bp, urgent, false)
		elif kind == &"ring":
			var gaps: PackedFloat32Array = g.get("gaps", PackedFloat32Array())
			var rr: float = float(g.get("radius_px", 288.0))
			for a: float in gaps:
				_edge_marker(xf * (pw + Vector2(cos(a), sin(a)) * rr), vs, HW, bp, urgent, false)
		elif id == &"elite" or id == &"midboss":  # 보스는 금줄 굿청(플레이어 중심)에 들어서므로 방향 표지 없음
			var dist: float = 13.0 * K.UNIT_PX
			_edge_marker(xf * (pw + Vector2.from_angle(float(w["ang"])) * dist), vs, HW if id != &"elite" else JK, bp, urgent, id != &"elite")
	if int(director.get("phase")) == 5 and director.get("route") == &"sal_geodum":
		var lumps: PackedVector2Array = director.get("lumps")
		var idx: int = int(director.get("lump_idx"))
		if idx < lumps.size():
			_edge_marker(xf * lumps[idx], vs, HW, bp, false, true)


func _edge_marker(sp: Vector2, vs: Vector2, col: Color, bp: float, urgent: bool, big: bool) -> void:
	var inset: float = _pf("edge_inset_px", 14.0)
	var inner: Rect2 = Rect2(Vector2(inset, inset), vs - Vector2(inset, inset) * 2.0)
	if inner.has_point(sp):
		return
	var c: Vector2 = vs * 0.5
	var d: Vector2 = sp - c
	if d.length_squared() < 1.0:
		return
	var sx: float = (inner.size.x * 0.5) / maxf(0.001, absf(d.x))
	var sy: float = (inner.size.y * 0.5) / maxf(0.001, absf(d.y))
	var p: Vector2 = K.rndv(c + d * minf(sx, sy))
	var u: Vector2 = d.normalized()
	var r: int = (6 if big else 4) + (1 if bp > 0.7 else 0) + (1 if urgent else 0)
	# 마름모(외곽 흑 + 색)
	for yy in range(-r - 1, r + 2):
		var span: int = r + 1 - absi(yy)
		_ui.draw_rect(Rect2(p.x - span, p.y + yy, span * 2 + 1, 1), HK)
	for yy in range(-r, r + 1):
		var span2: int = r - absi(yy)
		_ui.draw_rect(Rect2(p.x - span2, p.y + yy, span2 * 2 + 1, 1), col)
	_ui.draw_rect(Rect2(p.x - 1, p.y - 1, 2, 2), MK)
	# 안쪽(위협이 오는 쪽의 반대 = 화면 중심 쪽)으로 갈매기
	var tip: Vector2 = p - u * float(r + 4)
	_chevron(_ui, tip, -u, 6.0, col)
