extends Node
## 가시성 기준 캡처(디버그 빌드 전용, `--vis-stats`). DebugTools 가 인자를 보면 붙인다. 소유: 가시성 캡처 담당.
## 게임 규칙·연출은 건드리지 않는다. 하는 일은 두 가지뿐:
##   1) 지정 게임 시각 근처(lead 초 전부터)만 배속을 1로 낮췄다가(--speed 빨리감기 → 1배속 화면) 창이 끝나면 되돌린다.
##   2) step 초(게임 시각)마다 화면을 PNG 로 저장하고 그 순간 화면 수치를 [vis] 줄 + vis_stats.jsonl 로 남긴다.
## 인자(`--` 뒤):
##   --vis-stats                켜기
##   --vis-at=180,480,...       캡처 시각(게임 초, 오름차순)
##   --vis-dur=4 --vis-step=0.5 --vis-lead=2   창 길이·간격·앞당김(초)
##   --vis-out=<절대 경로>       출력 폴더(<out>/<mmss>/shot_NN.png)
##   --vis-scale=3              저장 배율(640×360 내부 화면을 최근접 ×3 = 1920×1080 창과 같은 픽셀)
## 화면 글 분류(design/18 §5 표 아래, 11-25 갱신 — 위치 기준):
##   글 주인이 그린 프레임의 사각형(vis_rects, 640×360)을 읽는다. 'pos:' 키(붓 슬램·힌트 줄)는 위치로 가른다:
##   가운데 상자(x 0.25~0.75W, y 0.2~0.75H) 안에 사각형 중심 → center, 그 밖에서 x 가 좌우 25% → edge, 위 → top, 아래 → bottom.
##   top = 위 띠/레인·시련 안내판, center = 가운데 큰 글(거리 카드·시련 큰 글자·거리 슬램·레벨업·가운데 붓), edge = 가장자리 레인·붓·힌트,
##   world = 월드 이름표(화신 원 카드는 world 이지만 예전과 비교하려고 center_n 에 1로 센다).
##   safe_n = 플레이어 안전 상자(플레이어 화면 좌표 x±72, y−72~+16) 와 겹치는 화면 공간 글 수(world 제외).
##   goal(목표 줄, design/19 §1.3)은 위치와 무관하게 top:goal 로 센다(가운데 슬롯 아님). goal_on = 이번 프레임 목표 줄이 그려졌는가.
## design/19 §8.2 지표(그림 수치는 tools/vis_measure.py): held_n = 손에 든 무기 수(HeldWeapon 이 이번 프레임 그린 것),
##   pl_hidden = 무적 점멸 숨김 틱(몸 대신 실루엣 — 최소값 계산에서 뺀다), streak = Juice.kill_streak, fx_crowd = Juice.fx_crowd.

const EM_ALIVE: int = 1
const EM_PULLIL: int = 2
const EM_WONGWI: int = 16
const EM_DYING: int = 64
const EM_NONHOSTILE: int = 65536
const EM_HIDDEN: int = 262144
const PR_ALIVE: int = 1
const PR_ENEMY: int = 2

var _at: PackedFloat32Array = PackedFloat32Array()
var _idx: int = 0
var _dur: float = 4.0
var _step: float = 0.5
var _lead: float = 2.0
var _out: String = ""
var _scale: int = 3
var _fast: int = 1
var _in_win: bool = false
var _next_shot: float = 0.0
var _shot_n: int = 0
var _busy: bool = false
var _nodes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s: String in DebugTools.arg("vis-at", "").split(",", false):
		_at.append(float(s))
	_dur = float(DebugTools.arg("vis-dur", "4"))
	_step = maxf(0.05, float(DebugTools.arg("vis-step", "0.5")))
	_lead = float(DebugTools.arg("vis-lead", "2"))
	_scale = maxi(1, int(DebugTools.arg("vis-scale", "3")))
	_out = DebugTools.arg("vis-out", "")
	if _out == "":
		_out = ProjectSettings.globalize_path("res://captures/vis")
	_fast = maxi(1, int(DebugTools.arg("speed", "1")))
	DirAccess.make_dir_recursive_absolute(_out)
	print("[vis] probe on at=%s dur=%.2f step=%.2f lead=%.2f scale=%d fast=%d out=%s" % [str(_at), _dur, _step, _lead, _scale, _fast, _out])


var _pf_last: int = 0          # 성능: 장 사이 프레임 시간·스크립트 시간 누적(캡처 프레임 제외)
var _pf_n: int = 0
var _pf_us: int = 0
var _pf_max: int = 0
var _pf_proc: float = 0.0


func _process(_delta: float) -> void:
	var now_us: int = Time.get_ticks_usec()
	if _in_win and not _busy and _pf_last > 0:
		var dt_us: int = now_us - _pf_last
		_pf_n += 1
		_pf_us += dt_us
		_pf_max = maxi(_pf_max, dt_us)
		_pf_proc += Performance.get_monitor(Performance.TIME_PROCESS)
	_pf_last = now_us
	if _busy or _idx >= _at.size() or not Game.run_active:
		return
	var t: float = Game.time_sec()
	var target: float = _at[_idx]
	if not _in_win:
		if t >= target - _lead:
			Game.set_sim_speed(1)
			_in_win = true
			_next_shot = maxf(target, t)
			_shot_n = 0
			_nodes.clear()
		return
	if t >= target + _dur + 0.001:
		_in_win = false
		_idx += 1
		Game.set_sim_speed(_fast)
		return
	if t >= _next_shot:
		_next_shot += _step
		_busy = true
		_capture(target, t)


func _capture(target: float, t_req: float) -> void:
	await RenderingServer.frame_post_draw
	var tag: String = "%02d%02d" % [int(target) / 60, int(target) % 60]
	var dir: String = _out.path_join(tag)
	DirAccess.make_dir_recursive_absolute(dir)
	var img: Image = get_viewport().get_texture().get_image()
	var raw: Vector2i = img.get_size()
	if _scale > 1:
		img.resize(raw.x * _scale, raw.y * _scale, Image.INTERPOLATE_NEAREST)
	var fname: String = "shot_%02d.png" % _shot_n
	img.save_png(dir.path_join(fname))
	var st: Dictionary = _stats()
	st["at"] = tag
	st["n"] = _shot_n
	st["file"] = tag + "/" + fname
	st["t"] = snappedf(Game.time_sec(), 0.01)
	st["t_req"] = snappedf(t_req, 0.01)
	st["raw"] = [raw.x, raw.y]
	st["scale"] = _scale
	var f: FileAccess = FileAccess.open(_out.path_join("vis_stats.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(_out.path_join("vis_stats.jsonl")) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(JSON.stringify(st))
		f.close()
	print("[vis] at=%s n=%02d t=%s en_screen=%d near32=%d near64=%d wongwi=%d pullil=%d dying=%d eproj=%d pproj=%d vfx=%d particles=%d dmgnum=%d dmglabel=%d yeongga=%d texts=%d center=%d safe=%d fps=%d dc=%d owner=%s [%s]" % [
		tag, _shot_n, K.fmt_time(Game.time_sec()), st.en_screen, st.near32, st.near64, st.wongwi, st.pullil, st.dying,
		st.eproj, st.pproj, st.vfx, st.particles, st.dmgnum, st.dmglabel, st.yeongga, st.texts_n, st.center_n,
		st.safe_n, int(st.fps), int(st.draw_calls), st.center_owner,
		" / ".join(PackedStringArray(st.texts))])
	_shot_n += 1
	_busy = false
	_pf_last = 0                 # 다음 프레임 시간에 캡처 정지를 넣지 않는다


func _find(path: String) -> Node:
	if _nodes.has(path) and is_instance_valid(_nodes[path]):
		return _nodes[path]
	var n: Node = _walk(get_tree().root, path)
	_nodes[path] = n
	return n


func _walk(n: Node, path: String) -> Node:
	var sc: Variant = n.get_script()
	if sc is Script and (sc as Script).resource_path == path:
		return n
	for c: Node in n.get_children():
		var r: Node = _walk(c, path)
		if r != null:
			return r
	return null


func _count_particles(n: Node) -> int:
	var k: int = 0
	if (n is GPUParticles2D and (n as GPUParticles2D).emitting) or (n is CPUParticles2D and (n as CPUParticles2D).emitting):
		if (n as CanvasItem).is_visible_in_tree():
			k += 1
	for c: Node in n.get_children():
		k += _count_particles(c)
	return k


func _g(n: Node, prop: String, def: Variant) -> Variant:
	if n == null:
		return def
	var v: Variant = n.get(prop)
	return def if v == null else v


func _stats() -> Dictionary:
	var vp: Viewport = get_viewport()
	var inv: Transform2D = vp.get_canvas_transform().affine_inverse()
	var vs: Vector2 = vp.get_visible_rect().size
	var a: Vector2 = inv * Vector2.ZERO
	var b: Vector2 = inv * vs
	var rect: Rect2 = Rect2(a, b - a).abs().grow(8.0)
	var pp: Vector2 = Game.player.global_position if Game.player != null else Vector2.ZERO
	var ps: Vector2 = vp.get_canvas_transform() * pp
	var d: Dictionary = {"player_world": [roundi(pp.x), roundi(pp.y)], "player_screen": [roundi(ps.x), roundi(ps.y)],
		"fps": Engine.get_frames_per_second()}
	# 적: 화면 안·플레이어 주변
	var en: int = 0
	var n32: int = 0
	var n64: int = 0
	var wg: int = 0
	var pl: int = 0
	var dy: int = 0
	var nh: int = 0
	var em: Node = Game.enemies
	if em != null:
		var fl: PackedInt32Array = em.get("flags")
		var ex: PackedFloat32Array = em.get("px")
		var ey: PackedFloat32Array = em.get("py")
		for i in fl.size():
			var f: int = fl[i]
			if (f & EM_ALIVE) == 0 or (f & EM_HIDDEN) != 0:
				continue
			var p: Vector2 = Vector2(ex[i], ey[i])
			if not rect.has_point(p):
				continue
			en += 1
			var dd: float = p.distance_squared_to(pp)
			if dd < 32.0 * 32.0:
				n32 += 1
			if dd < 64.0 * 64.0:
				n64 += 1
			if (f & EM_WONGWI) != 0:
				wg += 1
			if (f & EM_PULLIL) != 0:
				pl += 1
			if (f & EM_DYING) != 0:
				dy += 1
			if (f & EM_NONHOSTILE) != 0:
				nh += 1
	d["en_screen"] = en
	d["near32"] = n32
	d["near64"] = n64
	d["wongwi"] = wg
	d["pullil"] = pl
	d["dying"] = dy
	d["nonhostile"] = nh
	d["en_active"] = int(_g(em, "active_count", 0))
	# 투사체
	var ep: int = 0
	var mp: int = 0
	var pm: Node = Game.projectiles
	if pm != null:
		var pf: PackedInt32Array = pm.get("flags")
		var qx: PackedFloat32Array = pm.get("px")
		var qy: PackedFloat32Array = pm.get("py")
		for i in pf.size():
			if (pf[i] & PR_ALIVE) == 0 or not rect.has_point(Vector2(qx[i], qy[i])):
				continue
			if (pf[i] & PR_ENEMY) != 0:
				ep += 1
			else:
				mp += 1
	d["eproj"] = ep
	d["pproj"] = mp
	# 이펙트
	var vfx: Node = Game.vfx
	d["vfx"] = int(_g(vfx, "active_count", 0))
	var atmo: Node = _g(vfx, "atmosphere", null)
	d["atmo_crowd"] = int(_g(atmo, "crowd_n", 0))
	d["particles"] = _count_particles(get_tree().root)
	d["crowd_dim"] = snappedf(float(Juice.get("crowd_dim")) if Juice.get("crowd_dim") != null else -1.0, 0.01)
	d["number_crowd"] = bool(Juice.get("number_crowd")) if Juice.get("number_crowd") != null else false
	var dn: Node = Juice.damage_numbers
	d["dmgnum"] = int(_g(dn, "_alive_n", 0))
	d["dmglabel"] = int(_g(dn, "_lalive_n", 0))
	var run: Node = _find("res://run/run.gd")
	d["yeongga"] = int(_g(run, "yeongga_count", 0))
	d["lv"] = int(Game.get("level")) if Game.get("level") != null else -1
	# 화면 글·띠(위치 기준 — 글 주인이 이번 프레임에 그린 사각형)
	var texts: PackedStringArray = PackedStringArray()
	var center: int = 0
	var safe: int = 0
	var safe_box: Rect2 = Rect2(ps.x - 72.0, ps.y - 72.0, 144.0, 88.0)
	var ctr_box: Rect2 = Rect2(vs.x * 0.25, vs.y * 0.2, vs.x * 0.5, vs.y * 0.55)
	var cards: int = 0
	var goal_on: bool = false
	var owners: Array = [["res://ui/hud.gd", "hud"], ["res://haewon/haewon_system.gd", "hs"], ["res://ui/guide.gd", "guide"],
		["res://waves/wave_presenter.gd", "waves"], ["res://deities/trial_hud.gd", "trial"]]
	var fr: int = Engine.get_process_frames()
	for o: Array in owners:
		var nd: Node = _find(String(o[0]))
		var vr: Variant = _g(nd, "vis_rects", {})
		if not (vr is Dictionary):
			continue
		for k: Variant in (vr as Dictionary).keys():
			var e: Variant = (vr as Dictionary)[k]
			if not (e is Array) or (e as Array).size() < 2 or fr - int((e as Array)[1]) > 2:
				continue
			var r: Rect2 = (e as Array)[0]
			var key: String = String(k)
			var cls: String = key.get_slice(":", 0)
			var nm: String = key.get_slice(":", 1)
			if nm == "goal":
				cls = "top"
				goal_on = true
			if cls == "pos":
				var c2: Vector2 = r.get_center()
				if ctr_box.has_point(c2):
					cls = "center"
				elif c2.x < vs.x * 0.25 or c2.x > vs.x * 0.75:
					cls = "edge"
				elif c2.y < vs.y * 0.2:
					cls = "top"
				else:
					cls = "bottom"
			var label: String = "%s:%s" % [cls, nm]
			if nm == "brush":
				label += " '%s'" % String(_g(nd, "_bn_text", "")).left(16)
			elif nm == "hint":
				label += " '%s'" % String(_g(nd, "_hint_text", "")).left(24)
			elif nm == "lane":
				if cls == "top":
					label += " '%s'" % String(_g(nd, "_lane_text", "")).left(24)
				else:
					var et: Variant = _g(nd, "_edge_text", PackedStringArray())
					label += " '%s'" % (" ".join(et as PackedStringArray).left(24) if et is PackedStringArray else "")
			elif nm == "trial_big":
				label += " '%s'" % String(_g(nd, "_s_big", "")).left(12)
			elif nm == "trial":
				label += " '%s'" % String(_g(nd, "_s_title", "")).left(16)
			if nm.begins_with("trial_card"):
				cards += 1
				continue
			texts.append(label)
			if cls == "center":
				center += 1
			if cls != "world" and r.intersects(safe_box):
				safe += 1
				texts.append("SAFE!%s" % nm)
	if cards > 0:
		texts.append("center:trial_cards")
		center += 1
	var hud: Node = _find("res://ui/hud.gd")
	if hud != null:
		var sv: Variant = _g(hud, "_streak_vis", PackedFloat32Array())
		if sv is PackedFloat32Array and ((sv as PackedFloat32Array).size() > 1) and ((sv as PackedFloat32Array)[0] > 0.0 or (sv as PackedFloat32Array)[1] > 0.0):
			texts.append("side:streak")
	var gd: Node = _find("res://ui/guide.gd")
	if gd != null:
		var tt: Variant = _g(gd, "_tag_t", PackedFloat32Array())
		var tx: Variant = _g(gd, "_tag_text", PackedStringArray())
		if tt is PackedFloat32Array and tx is PackedStringArray:
			for i in (tt as PackedFloat32Array).size():
				if (tt as PackedFloat32Array)[i] > 0.0 and i < (tx as PackedStringArray).size() and (tx as PackedStringArray)[i] != "":
					texts.append("world:tag '%s'" % (tx as PackedStringArray)[i].left(12))
	var lu: Node = _find("res://ui/levelup.gd")
	if lu is CanvasItem and (lu as CanvasItem).is_visible_in_tree():
		texts.append("center:levelup")
		center += 1
	d["safe_n"] = safe
	d["goal_on"] = goal_on
	# 손 무기·무적 점멸·연속 처치(design/19 §8.1 ④)
	var plr: Node = Game.player
	var held: Node = _g(plr, "held", null)
	var dw: Variant = _g(held, "_draw_w", [])
	d["held_n"] = (dw as Array).size() if dw is Array else 0
	var spr: Variant = _g(plr, "sprite", null)
	d["pl_hidden"] = spr is CanvasItem and not (spr as CanvasItem).visible
	d["streak"] = int(Juice.get(&"kill_streak")) if Juice.get(&"kill_streak") != null else -1
	d["fx_crowd"] = bool(Juice.get(&"fx_crowd")) if Juice.get(&"fx_crowd") != null else false
	d["center_owner"] = String(Juice.call(&"center_current")) if Juice.has_method(&"center_current") else ""
	d["draw_calls"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	# 앞 장 이후 프레임들(캡처 프레임 제외)의 평균·최대 프레임 시간과 스크립트 _process 평균 — PNG 저장 정지가 섞이지 않은 fps
	if _pf_n > 0:
		d["frame_ms_avg"] = snappedf(float(_pf_us) / float(_pf_n) / 1000.0, 0.01)
		d["frame_ms_max"] = snappedf(float(_pf_max) / 1000.0, 0.01)
		d["fps_clean"] = snappedf(1000000.0 * float(_pf_n) / float(maxi(1, _pf_us)), 0.1)
		d["proc_ms_avg"] = snappedf(_pf_proc / float(_pf_n) * 1000.0, 0.01)
	_pf_n = 0
	_pf_us = 0
	_pf_max = 0
	_pf_proc = 0.0
	d["dmglabel_world"] = int(_g(dn, "_lalive_n", 0))
	d["texts"] = Array(texts)
	d["texts_n"] = texts.size()
	d["center_n"] = center
	return d
