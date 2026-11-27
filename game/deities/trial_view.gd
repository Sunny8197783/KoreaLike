extends Node2D
## 시련·빙의·합일 월드 연출(L3, 읽기 전용). 소유: deities. TrialDirector 가 세 인스턴스를 만든다:
##   layer_kind 0 = 바닥(z −2: 지면 위·길베/그림자 아래) — 화신 원·마당 금줄·텔레그래프·과제 바닥·오라·충격파
##   layer_kind 1 = 위(z 4: 적·무당 위) — 신장대·화신·화신 탄·과제 오브젝트·빛의 실·권능 연출·합일
##   layer_kind 2 = 무당 오버레이(z 2, 무당과 같은 층·트리 순서상 뒤) — 빙의 머리·지물·신장 호위
## 규칙: 좌표는 정수 픽셀(K.rnd), 회전·비정수 배율 없음(스프라이트), 텔레그래프 = 청 테두리 + 흑 반투명, 백(#f2ece0) 미사용.
## 할당: 텍스처·프레임 배열은 처음 쓸 때 1회 캐시(Dictionary). 매 프레임 PackedVector2Array 는 멤버 버퍼 재사용.

const Defs := preload("res://deities/deity_defs.gd")
const Avatar := preload("res://deities/trial_avatar.gd")
const Task := preload("res://deities/trial_task.gd")
const Powers := preload("res://deities/deity_powers.gd")

var layer_kind: int = 0
var dir: Node = null          # TrialDirector

var _tex: Dictionary = {}     # path -> Texture2D(null 포함)
var _frames: Dictionary = {}  # key -> Array[Texture2D]
var _feet: Dictionary = {}    # Texture2D rid -> int(발 y)
var _poly4: PackedVector2Array = PackedVector2Array()
var _line: PackedVector2Array = PackedVector2Array()
var _av_sprite: Sprite2D = null
var _av_mat: ShaderMaterial = null
var _font: Font = null
var _head_off: Array[Vector2] = [Vector2(0, -33), Vector2(1, -33), Vector2(0, -33), Vector2(-1, -33)]
var _anchor_char: StringName = &"~"

const C_EDGE: Color = Color(0.165, 0.36, 0.667, 0.95)
const C_FILL: Color = Color(0.055, 0.043, 0.086, 0.42)
const C_HOT: Color = Color(0.894, 0.376, 0.31, 1.0)
const C_HANJI: Color = Color(0.913, 0.863, 0.753, 1.0)
const C_HANJI_DK: Color = Color(0.698, 0.616, 0.463, 1.0)
const C_JEOK: Color = Color(0.784, 0.196, 0.176, 1.0)
const C_MEOK: Color = Color(0.055, 0.043, 0.086, 1.0)
const C_HEUK: Color = Color(0.102, 0.102, 0.102, 1.0)
const C_CHEONG: Color = Color(0.165, 0.36, 0.667, 1.0)
const C_HWANG: Color = Color(0.91, 0.725, 0.192, 1.0)
const OBANG: Array[Color] = [Color(0.165, 0.36, 0.667), Color(0.784, 0.196, 0.176), Color(0.91, 0.725, 0.192), Color(0.913, 0.863, 0.753), Color(0.20, 0.18, 0.24)]
const FLAG_OBANG: PackedInt32Array = [2, 0, 1, 3, 4]          # 중앙 황 · 동 청 · 남 적 · 서 백(한지) · 북 흑
const FLAG_NAMES: Array[StringName] = [&"vfx_obanggi_flag_hwang", &"vfx_obanggi_flag_cheong", &"vfx_obanggi_flag_jeok", &"vfx_obanggi_flag_baek", &"vfx_obanggi_flag_heuk"]
const YG_BODIES: Array[StringName] = [&"yeongga_body_f", &"yeongga_body_m", &"yeongga_body_child"]
const HOWI_ENT: Array[StringName] = [&"avatar_janggun__cheong", &"avatar_janggun__jeok", &"avatar_janggun__baek", &"avatar_janggun__heuk"]
const GUTSANG_TEX: Array[String] = ["res://assets/props/obj_gongmulsang_empty.png", "res://assets/props/obj_gongmulsang_1_3.png", "res://assets/props/obj_gongmulsang_2_3.png", "res://assets/props/obj_gongmulsang_full.png"]
const ANIM_PREF: Dictionary = {
	&"attack": ["attack", "roar", "charge", "idle"],
	&"charge": ["charge", "attack", "roar", "idle"],
	&"roar": ["roar", "attack", "idle"],
	&"run": ["run", "move", "idle"],
	&"move": ["move", "run", "idle"],
	&"idle": ["idle", "move", "run"],
}

var _fxid: Dictionary = {}     # prefix -> {deity -> StringName}
var _dtex: Dictionary = {}     # entity StringName -> south 텍스처
var _ov_deity: StringName = &""
var _av_name_deity: StringName = &""
var _av_name: String = ""
var _av_name_w: float = 0.0
var _ov_face: StringName = &""
var _ov_head: Array[Texture2D] = [null, null, null, null]
var _ov_jimul: Array[Texture2D] = [null, null, null, null]
# 권능 연출(design/19 §5.2 F): 1px 선 → 기존 시트(VfxPlayer). 첫 1f 신령 오방색 2px, 발밑 신령 표지 1f, 동시 8(군중 6).
const PW_CAP: int = 8
const PW_CAP_CROWD: int = 6
const PW_FIRST: float = 2.0 / 60.0                         # '첫 1f' — 60fps 캡처에서도 잡히게 2틱
const C_CHEONGNOK: Color = Color(0.247, 0.561, 0.525, 1.0) # #3f8f86 용왕 오방 청록(적 탄 청과 다른 값)
const C_HWANGTO: Color = Color(0.663, 0.486, 0.106, 1.0)   # #a97c1b 대감 황토
const WAVE_MOD: Color = Color(0.6, 1.0, 0.85, 1.0)         # 쑥물 장판 → 청록 물결
var _pw_seen: PackedFloat32Array = PackedFloat32Array()    # 권능 연출 슬롯별로 본 fx_t0(새 항목 감지)
var _pw_sheet_t: PackedFloat32Array = PackedFloat32Array([-10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0])
var _pw_sheet_head: int = 0
var stat_pw_sheets: int = 0
var stat_pw_cut: int = 0
# 화신 타격 빛 점(design/19 §5.2 F): 맞을 때마다 화신 몸 → 위엄 막대로 0.3초(상한 4)
const HD_CAP: int = 4
const HD_LIFE: float = 0.3
var _hd_t: PackedFloat32Array = PackedFloat32Array([-10.0, -10.0, -10.0, -10.0])
var _hd_from: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _hd_head: int = 0
var _hd_seen: float = -10.0


## 신령 오방색(design/19 §5.2 F): 장군 적, 산신 황, 용왕 청록, 칠성·바리 한지, 대감 황토. 모르면 한지.
func _obang_of(d: StringName) -> Color:
	match String(d):
		"deity_janggun":
			return C_JEOK
		"deity_sansin":
			return C_HWANG
		"deity_yongwang":
			return C_CHEONGNOK
		"deity_jeseok_daegam":
			return C_HWANGTO
	return C_HANJI


## "vfx_<prefix>_<key>" StringName 캐시(매 프레임 문자열 결합 방지).
func _fx_of(prefix: String, d: StringName) -> StringName:
	var m: Dictionary = _fxid.get(prefix, {})
	if not _fxid.has(prefix):
		_fxid[prefix] = m
	if not m.has(d):
		m[d] = StringName(prefix + Defs.vfx_key(d))
	return m[d]


func _south(ent: StringName, fallback: int) -> Texture2D:
	if _dtex.has(ent):
		return _dtex[ent]
	var t: Texture2D = SpriteLib.dir_tex(String(ent), "south", fallback)
	_dtex[ent] = t
	return t


func _ready() -> void:
	_poly4.resize(4)
	_line.resize(17)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = ThemeDB.fallback_font
	var th: Theme = ThemeDB.get_project_theme()
	if th != null and th.default_font != null:
		_font = th.default_font
	if layer_kind == 1:
		_av_sprite = Sprite2D.new()
		_av_sprite.centered = false
		_av_sprite.visible = false
		_av_sprite.show_behind_parent = true   # 화신 위로 징 울림·위엄 글자·탄이 그려지게(부모 _draw 가 스프라이트 위)
		var sh: Shader = load("res://shaders/hit_flash.gdshader") as Shader
		if sh != null:
			_av_mat = ShaderMaterial.new()
			_av_mat.shader = sh
			_av_sprite.material = _av_mat
		add_child(_av_sprite)
	if layer_kind == 2:
		_load_head_anchor()


## 무당별 앵커(data/anchors/<char_id>.json) 프레임 head 의 방향별 평균 → 발 피벗 기준 오프셋. 없으면 만신 것.
func _load_head_anchor() -> void:
	_anchor_char = Game.char_id
	_head_off = [Vector2(0, -33), Vector2(1, -33), Vector2(0, -33), Vector2(-1, -33)]
	var cid: String = String(Game.char_id)
	var path: String = "res://data/anchors/%s.json" % cid
	if cid == "" or not FileAccess.file_exists(path):
		cid = "char_mansin"
		path = "res://data/anchors/char_mansin.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var j: Variant = JSON.parse_string(f.get_as_text())
	if not (j is Dictionary):
		return
	var jd: Dictionary = j
	var keys: Array = [cid]
	keys.append_array(jd.keys())
	for key: Variant in keys:
		if not (jd.get(key) is Dictionary):
			continue
		var ent: Dictionary = jd[key]
		if not (ent.get("frames") is Dictionary):
			continue
		var frames: Dictionary = ent.get("frames", {})
		var piv: Array = ent.get("pivot", [32, 58])
		var acc: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		var cnt: PackedInt32Array = [0, 0, 0, 0]
		for fk: Variant in frames.keys():
			var name: String = String(fk)
			if not (frames[fk] is Dictionary):
				continue
			var fr: Dictionary = frames[fk]
			if not (fr.get("head") is Array) or not name.begins_with("idle_"):
				continue
			var di: int = 0
			if name.contains("_east_"):
				di = 1
			elif name.contains("_north_"):
				di = 2
			elif name.contains("_west_"):
				di = 3
			acc[di] += Vector2(float(fr["head"][0]) - float(piv[0]), float(fr["head"][1]) - float(piv[1]))
			cnt[di] += 1
		for di in 4:
			if cnt[di] > 0:
				_head_off[di] = (acc[di] / float(cnt[di])).round()
		if cnt[1] > 0 and cnt[3] == 0:
			_head_off[3] = Vector2(-_head_off[1].x, _head_off[1].y)
		break


func _t(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex[path] = t
	return t


## 애니 프레임 캐시: _frames[entity][anim][dir] (문자열 결합 없이 조회).
func _anim(entity: StringName, anim: String, d: String) -> Array:
	var e: Dictionary = _frames.get(entity, {})
	if not _frames.has(entity):
		_frames[entity] = e
	var a: Dictionary = e.get(anim, {})
	if not e.has(anim):
		e[anim] = a
	if a.has(d):
		return a[d]
	var arr: Array[Texture2D] = SpriteLib.anim_frames(String(entity), anim, d)
	a[d] = arr
	return arr


func _feet_y(t: Texture2D) -> int:
	var id: int = t.get_rid().get_id()
	if _feet.has(id):
		return _feet[id]
	var y: int = t.get_height() - 4
	var img: Image = t.get_image()
	if img != null:
		var r: Rect2i = img.get_used_rect()
		if r.size.y > 0:
			y = r.position.y + r.size.y - 2
	_feet[id] = y
	return y


func _process(_delta: float) -> void:
	if dir == null:
		return
	if layer_kind == 1:
		_update_avatar_sprite()
		_spawn_power_sheets()
		_track_avatar_hits()
	queue_redraw()


## 새 권능 연출 항목을 찾아 기존 시트를 VfxPlayer 로 낸다(동시 8, 군중 6 — 넘치면 선 연출만).
func _spawn_power_sheets() -> void:
	var td: TrialDirector = dir as TrialDirector
	var pw: Powers = td.powers as Powers if td != null else null
	var vfx: VfxPlayer = Game.vfx as VfxPlayer
	if pw == null or vfx == null:
		return
	if _pw_seen.size() != Powers.FX_CAP:
		_pw_seen.resize(Powers.FX_CAP)
		for i0 in Powers.FX_CAP:
			_pw_seen[i0] = pw.fx_t0[i0]          # 붙기 전 항목은 낡은 것
		return
	var now: float = _now()
	var cap: int = PW_CAP_CROWD if bool(Juice.get(&"fx_crowd")) else PW_CAP
	for i in Powers.FX_CAP:
		var t0: float = pw.fx_t0[i]
		if t0 == _pw_seen[i]:
			continue
		_pw_seen[i] = t0
		if now - t0 > 0.1 or now < t0:
			continue
		var live: int = 0
		for k in _pw_sheet_t.size():
			if now - _pw_sheet_t[k] < 0.6:
				live += 1
		if live >= cap:
			stat_pw_cut += 1
			continue
		_pw_sheet_t[_pw_sheet_head] = now
		_pw_sheet_head = (_pw_sheet_head + 1) % _pw_sheet_t.size()
		stat_pw_sheets += 1
		var p: Vector2 = Vector2(pw.fx_x[i], pw.fx_y[i])
		var r: float = pw.fx_r[i]
		var dc: Color = _obang_of(pw.fx_deity[i] if i < pw.fx_deity.size() else &"")
		var white: bool = pw.fx_col[i] == K.DmgColor.WHITE
		match pw.fx_kind[i]:
			Powers.Fx.STAR_FALL:
				vfx.play(&"vfx_isippalsu_bolt", p, 0.0, 1.0, {"additive": true, "snap": false, "modulate": Color(1, 1, 1, 0.9)})
				vfx.play(&"vfx_hit_spark_white" if white else &"vfx_hit_spark_red", p + Vector2(0, -4), 0.0, 2.0,
					{"delay": 0.1, "snap": false, "modulate": Color(0.82, 0.80, 0.76, 1.0) if white else Color.WHITE})
			Powers.Fx.PULSE:
				vfx.play(&"vfx_janggu_deong", p + Vector2(0, -6), 0.0, 1.0, {"snap": false, "modulate": Color(dc.lightened(0.25), 0.85)})
			Powers.Fx.CLAW:
				vfx.play(&"vfx_gyeoldanta_cut", p + Vector2(0, -12), 0.0, 1.0, {"snap": false, "modulate": C_HWANG.lightened(0.3)})
			Powers.Fx.WAVE:
				var dw: Vector2 = Vector2(pw.fx_dx[i], pw.fx_dy[i])
				for m in 3:
					var f: float = 0.25 + 0.25 * float(m)
					vfx.play(&"vfx_ssukmul_pool", p + dw * r * f, 0.0, 1.0, {"snap": false, "modulate": WAVE_MOD, "life": 0.45, "delay": f * 0.45})
			Powers.Fx.SPLASH:
				vfx.play(&"vfx_mul_puddle_clear", p, 0.0, 1.0, {"snap": false, "life": 0.5})
			Powers.Fx.ORB_GIFT:
				vfx.play(&"vfx_box_neokham_open", p, 0.0, 1.0, {"snap": false, "life": 4.0 * 0.083})


## 시련 중 화신 타격을 감지해 빛 점을 띄운다(TrialDirector.last_hit_t 가 바뀌면 1개, 상한 4 — 넘치면 가장 오래된 것을 덮음).
func _track_avatar_hits() -> void:
	var td: TrialDirector = dir as TrialDirector
	if td == null or td.ph != TrialDirector.Ph.TRIAL:
		return
	if td.last_hit_t == _hd_seen:
		return
	_hd_seen = td.last_hit_t
	var av: Avatar = td.avatar as Avatar
	if av == null or _now() - td.last_hit_t > 0.1:
		return
	_hd_t[_hd_head] = _now()
	_hd_from[_hd_head] = av.pos + Vector2(0, -roundf(float(av.size_px) * 0.36))
	_hd_head = (_hd_head + 1) % HD_CAP


func _now() -> float:
	return Game.time_sec()


func _draw() -> void:
	if dir == null or not Game.run_active and Game.state != Game.State.RUN:
		return
	match layer_kind:
		0:
			_draw_ground()
			_draw_power_foot()
		1:
			_draw_top()
		2:
			_draw_over()


# ─── 공통 그리기 ───────────────────────────────────────────────────────

func _dash_circle(c: Vector2, r: float, col: Color, dashes: int, width: float = 1.0, phase: float = 0.0) -> void:
	var step: float = TAU / float(dashes)
	for i in dashes:
		var a0: float = phase + step * float(i)
		draw_arc(K.rndv(c), r, a0, a0 + step * 0.55, 3, col, width, false)


func _ring(c: Vector2, r: float, col: Color, width: float = 1.0) -> void:
	draw_arc(K.rndv(c), maxf(1.0, r), 0.0, TAU, clampi(int(r * 0.5), 16, 96), col, width, false)


func _rect_poly(o: Vector2, d: Vector2, length: float, width: float, col: Color) -> void:
	var p: Vector2 = Vector2(-d.y, d.x) * width * 0.5
	_poly4[0] = K.rndv(o + p)
	_poly4[1] = K.rndv(o + d * length + p)
	_poly4[2] = K.rndv(o + d * length - p)
	_poly4[3] = K.rndv(o - p)
	draw_colored_polygon(_poly4, col)


func _rect_edge(o: Vector2, d: Vector2, length: float, width: float, col: Color, w: float = 1.0) -> void:
	var p: Vector2 = Vector2(-d.y, d.x) * width * 0.5
	var a: Vector2 = K.rndv(o + p)
	var b: Vector2 = K.rndv(o + d * length + p)
	var c: Vector2 = K.rndv(o + d * length - p)
	var e: Vector2 = K.rndv(o - p)
	draw_line(a, b, col, w)
	draw_line(b, c, col, w)
	draw_line(c, e, col, w)
	draw_line(e, a, col, w)


func _tex_flip(t: Texture2D, feet: Vector2, pivot: Vector2, col: Color, flip: bool) -> void:
	if t == null:
		return
	var w: float = float(t.get_width())
	var h: float = float(t.get_height())
	var pos: Vector2 = K.rndv(feet - pivot)
	if flip:
		draw_texture_rect(t, Rect2(pos.x + w, pos.y, -w, h), false, col)
	else:
		draw_texture(t, pos, col)


func _fx_frame(fx_id: StringName, center: Vector2, t: float, col: Color, loop: bool = true) -> void:
	var fx: Dictionary = VfxLib.get_fx(fx_id)
	var regions: Array = fx.get("regions", [])
	if regions.is_empty() or bool(fx.get("placeholder", false)):
		return
	var f: int = int(t * float(fx.get("fps", 8)))
	f = f % regions.size() if loop else mini(f, regions.size() - 1)
	var reg: Rect2 = regions[f]
	var piv: Vector2 = fx.get("pivot", reg.size * 0.5)
	draw_texture_rect_region(fx["texture"], Rect2(K.rndv(center - piv), reg.size), reg, col)


func _deity_col(d: StringName, a: float = 1.0) -> Color:
	var c: Color = Defs.color(d)
	c.a = a
	return c


# ─── 바닥 ──────────────────────────────────────────────────────────────

func _draw_ground() -> void:
	var td: TrialDirector = dir as TrialDirector
	var now: float = _now()
	var ph: int = td.ph
	var pl: Player = Game.player as Player
	var pp: Vector2 = pl.render_pos if pl != null else Vector2.ZERO
	# 빙의 오라(최근 1신) / 합일 오방 순환
	if ph == TrialDirector.Ph.HAPIL_ACTIVE and not td.hapil_ids.is_empty():
		var ci: int = int(Beat.beat_index) % 5
		var pulse: float = 1.0 - Beat.beat_phase()
		_ring(pp + Vector2(0, -1), 15.0 + 2.0 * pulse, Color(OBANG[ci], 0.85), 2.0)
		_ring(pp + Vector2(0, -1), 19.0 + 3.0 * pulse, Color(OBANG[(ci + 4) % 5], 0.35), 1.0)
	elif td.overlay_deity != &"" and pl != null:
		var pulse2: float = 1.0 - Beat.beat_phase()
		var oc: Color = _deity_col(td.overlay_deity, 0.55 + 0.3 * pulse2)
		draw_arc(K.rndv(pp), 14.0 + pulse2 * 1.5, 0.0, TAU, 40, oc, 1.0, false)
		if td.overlay_face == &"wieom":
			draw_arc(K.rndv(pp), 11.0, PI * 0.1, PI * 0.9, 12, Color(C_JEOK, 0.5 * pulse2), 1.0, false)
		else:
			draw_arc(K.rndv(pp), 17.0 + pulse2 * 2.0, 0.0, TAU, 40, Color(C_HANJI, 0.25 * pulse2), 1.0, false)
	_draw_power_ground(td, now)
	# 합일 화신 고스트: 지면 층(z−2)에 옅게 — 무당·적·내 공격 위를 덮지 않는다(design/18 §1.3)
	if ph >= TrialDirector.Ph.HAPIL_DESCEND and ph <= TrialDirector.Ph.HAPIL_CALL:
		_draw_hapil_ghosts(td, pp)
	if ph == TrialDirector.Ph.DORMANT or ph >= TrialDirector.Ph.HAPIL_OMEN:
		_draw_shock(td, now)
		return
	# 화신 원 2(예고 30% → 강림 100%)
	if ph >= TrialDirector.Ph.OMEN and ph <= TrialDirector.Ph.CONFIRM:
		var a: float = 0.3 if ph == TrialDirector.Ph.OMEN else 1.0
		for i in 2:
			var d: StringName = td.cand[i]
			var c: Vector2 = td.circle[i]
			var sel: bool = td.pick == i and ph == TrialDirector.Ph.CONFIRM
			draw_circle(K.rndv(c), td.circle_r, Color(C_MEOK, 0.22 * a + (0.1 if sel else 0.0)), true, -1.0, false)
			draw_circle(K.rndv(c), td.circle_r * 0.55, _deity_col(d, 0.05 * a), true, -1.0, false)
			_fx_frame(_fx_of("vfx_hwasin_won_", d), c, now - td.ph_t0, Color(1, 1, 1, a))
			_dash_circle(c, td.circle_r - 6.0, _deity_col(d, 0.45 * a), 36, 1.0, now * 0.25 * (1.0 if i == 0 else -1.0))
			if sel:
				draw_arc(K.rndv(c), td.circle_r + 5.0, -PI * 0.5, -PI * 0.5 + TAU * td.confirm_k, 72, _deity_col(d, 1.0), 3.0, false)
				draw_arc(K.rndv(c), td.circle_r + 9.0, -PI * 0.5, -PI * 0.5 + TAU * td.confirm_k, 72, Color(C_HANJI, 0.6), 1.0, false)
		# 산통(다시 묻기)
		if td.santong_on:
			var sp: Vector2 = td.santong_pos
			draw_circle(K.rndv(sp), 1.2 * K.UNIT_PX, Color(C_MEOK, 0.35), true, -1.0, false)
			_dash_circle(sp, 1.2 * K.UNIT_PX, Color(C_HANJI_DK, 0.8), 16, 1.0, now * 0.6)
			if td.santong_k > 0.0:
				draw_arc(K.rndv(sp), 1.2 * K.UNIT_PX + 3.0, -PI * 0.5, -PI * 0.5 + TAU * td.santong_k, 40, C_HANJI, 2.0, false)
	# 시련 마당(금줄 점선 + 사방 신장대는 위층) + 과제 바닥
	if ph >= TrialDirector.Ph.CLEAR and ph <= TrialDirector.Ph.AFTERGLOW and td.active_deity != &"":
		var fade: float = 1.0
		if ph == TrialDirector.Ph.AFTERGLOW:
			fade = clampf(1.0 - (now - td.ph_t0) / td.afterglow_s, 0.0, 1.0)
		var grow: float = clampf((now - td.ph_t0) / 0.5, 0.0, 1.0) if ph == TrialDirector.Ph.CLEAR else 1.0
		var bc: Color = Color(C_HANJI, 0.55 * fade)
		if td.leaving and ph == TrialDirector.Ph.TRIAL and int(now * 6.0) % 2 == 0:
			bc = Color(C_HOT, 0.8)
		_dash_circle(td.anchor, td.ground_r * grow, bc, 72, 1.0, now * 0.05)
		# 금줄 종이 술(8곳, 적·한지)
		for k in 8:
			var q: Vector2 = td.anchor + Vector2.from_angle(TAU * float(k) / 8.0 + now * 0.05) * td.ground_r * grow
			draw_rect(Rect2(K.rndv(q) + Vector2(-1, 0), Vector2(2, 4)), Color(C_JEOK if k % 2 == 0 else C_HANJI, 0.8 * fade))
		if ph == TrialDirector.Ph.CLEAR:
			_ring(td.anchor, td.circle_r * (0.5 + grow * 0.6), Color(_deity_col(td.active_deity), 1.0 - grow), 3.0)
		_draw_task_ground(td, now, fade)
		# 화신 그림자·사거리
		var av: Avatar = td.avatar as Avatar
		if av != null and (ph == TrialDirector.Ph.TRIAL or ph == TrialDirector.Ph.RESOLVE):
			var ap: Vector2 = av.pos
			var sw: float = float(av.size_px) * 0.22
			draw_set_transform(K.rndv(ap), 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, sw, Color(C_MEOK, 0.45 * av.alpha), true, -1.0, false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if ph == TrialDirector.Ph.TRIAL and av.targetable():
				var dpl: float = pp.distance_to(ap)
				var reach: float = td.reach_u * K.UNIT_PX
				if dpl > reach:
					_dash_circle(ap, reach, Color(C_JEOK, 0.28), 40, 1.0, -now * 0.4)
				if av.is_vulnerable():
					var bp: float = 0.5 + 0.5 * sin(now * 12.0)
					_ring(ap, sw * 1.4 + 3.0 * bp, Color(C_HANJI, 0.5 + 0.4 * bp), 2.0)
			_draw_telegraphs(av, now)
	_draw_shock(td, now)


## 권능 바닥 연출: 맑은 물 장판(용왕 가호) · 금줄 결계(제석·대감 가호).
func _draw_power_ground(td: TrialDirector, now: float) -> void:
	var pw: Powers = td.powers as Powers
	if pw == null:
		return
	for i in Powers.POOL_CAP:
		var age: float = now - pw.pool_t0[i]
		if age < 0.0 or age > pw.pool_dur:
			continue
		var c: Vector2 = Vector2(pw.pool_x[i], pw.pool_y[i])
		var a: float = clampf(minf(age / 0.2, (pw.pool_dur - age) / 0.5), 0.0, 1.0)
		var r: float = pw.pool_r[i]
		draw_set_transform(K.rndv(c), 0.0, Vector2(1.0, 0.6))
		draw_circle(Vector2.ZERO, r, Color(0.35, 0.62, 0.72, 0.22 * a), true, -1.0, false)
		var rk: float = fmod(age * 14.0, r)
		draw_arc(Vector2.ZERO, rk, 0.0, TAU, 24, Color(0.62, 0.82, 0.88, 0.55 * a * (1.0 - rk / r)), 1.0, false)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(0.62, 0.82, 0.88, 0.6 * a), 1.0, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ga: float = now - pw.geumjul_t0
	if ga >= 0.0 and ga < 3.0:
		var gk: float = clampf(ga / 0.15, 0.0, 1.0) * clampf((3.0 - ga) / 0.3, 0.0, 1.0)
		var gc: Vector2 = pw.geumjul_c
		var gr: float = pw.geumjul_r * (0.85 + 0.15 * clampf(ga / 0.15, 0.0, 1.0))
		_dash_circle(gc, gr, Color(C_HANJI_DK, 0.85 * gk), 40, 2.0, now * 0.4)
		# 금줄 종이 술(적·한지 번갈아 12곳)
		for k in 12:
			var q: Vector2 = gc + Vector2.from_angle(TAU * float(k) / 12.0 + now * 0.4) * gr
			draw_rect(Rect2(K.rndv(q) + Vector2(-1, 0), Vector2(2, 5)), Color(C_JEOK if k % 2 == 0 else C_HANJI, 0.9 * gk))


func _draw_shock(td: TrialDirector, now: float) -> void:
	var age: float = now - td.shock_t
	if age >= 0.0 and age < 0.35:
		var k: float = ease(age / 0.35, 0.5)
		var col: Color = C_JEOK if td.res_face == &"wieom" or td.ph >= TrialDirector.Ph.HAPIL_OMEN else C_HANJI
		_ring(td.shock_pos, td.shock_r * k, Color(col, 1.0 - k), 3.0)
		_ring(td.shock_pos, td.shock_r * k * 0.8, Color(col, 0.5 * (1.0 - k)), 1.0)


func _draw_telegraphs(av: Avatar, now: float) -> void:
	for i in Avatar.TG_CAP:
		if av.tg_on[i] == 0:
			continue
		var f: int = av.tg_flags[i]
		var c: Vector2 = Vector2(av.tg_x[i], av.tg_y[i])
		var span: float = maxf(0.01, av.tg_t1[i] - av.tg_t0[i])
		var k: float = clampf((now - av.tg_t0[i]) / span, 0.0, 1.0)
		var fired: bool = (f & Avatar.F_FIRED) != 0
		var age: float = now - av.tg_t1[i]
		var hot: bool = not fired and av.tg_t1[i] - now < 0.15 and int(now * 30.0) % 2 == 0
		var nod: bool = (f & Avatar.F_NO_DMG) != 0 and (f & Avatar.F_SLOW) == 0 and (f & Avatar.F_DASH) == 0
		var edge: Color = C_HOT if hot else C_EDGE
		if nod:
			edge = Color(C_EDGE, 0.5)
		var fill: Color = C_FILL
		match av.tg_shape[i]:
			Avatar.Shape.CIRCLE:
				var r: float = av.tg_a[i]
				if not fired or av.tg_life[i] > 0.0:
					draw_circle(K.rndv(c), r, fill, true, -1.0, false)
					if not fired:
						draw_circle(K.rndv(c), r * k, Color(C_CHEONG, 0.22), true, -1.0, false)
					elif (f & Avatar.F_PULL) != 0:
						_dash_circle(c, r * (1.0 - fmod(age, 0.6) / 0.6), Color(C_CHEONG, 0.7), 10, 1.0, age * 4.0)
					if (f & Avatar.F_SLOW) != 0:
						_dash_circle(c, r * 0.7, Color(C_HANJI_DK, 0.5), 12, 1.0, now)
					_ring(c, r, edge, 1.0)
				else:
					var bk: float = clampf(age / 0.22, 0.0, 1.0)
					_ring(c, r * (0.8 + 0.4 * bk), Color(C_HANJI_DK, 1.0 - bk), 2.0)
					draw_circle(K.rndv(c), r * (1.0 - bk), Color(C_HEUK, 0.5 * (1.0 - bk)), true, -1.0, false)
			Avatar.Shape.RECT:
				var d: Vector2 = Vector2(av.tg_dx[i], av.tg_dy[i])
				var L: float = av.tg_a[i]
				var W: float = av.tg_b[i]
				if not fired:
					_rect_poly(c, d, L, W, fill)
					_rect_poly(c, d, L * k, W, Color(C_CHEONG, 0.22))
					_rect_edge(c, d, L, W, edge)
					if (f & Avatar.F_DASH) != 0:
						# 진행 방향 화살(3개)
						for m in 3:
							var q: Vector2 = c + d * L * (0.3 + 0.25 * float(m))
							var pr: Vector2 = Vector2(-d.y, d.x) * W * 0.3
							draw_line(K.rndv(q - d * 6.0 + pr), K.rndv(q), Color(edge, 0.8), 1.0)
							draw_line(K.rndv(q - d * 6.0 - pr), K.rndv(q), Color(edge, 0.8), 1.0)
				else:
					var bk2: float = clampf(age / 0.22, 0.0, 1.0)
					_rect_poly(c, d, L, W * (1.0 - bk2), Color(C_HEUK, 0.45 * (1.0 - bk2)))
					_rect_edge(c, d, L, W, Color(C_HANJI_DK, 1.0 - bk2))
			Avatar.Shape.RING:
				var rr: float = av.ring_r(i, maxf(0.0, age) if fired else 0.0)
				var th: float = av.tg_b[i]
				var gd: Vector2 = Vector2(av.tg_dx[i], av.tg_dy[i])
				var gap: float = av.tg_c[i]
				var a0: float = gd.angle() + gap * 0.5
				var a1: float = gd.angle() + TAU - gap * 0.5
				if not fired:
					draw_arc(K.rndv(c), rr, a0, a1, 64, Color(C_MEOK, 0.4), maxf(2.0, th), false)
					draw_arc(K.rndv(c), rr, a0, a0 + (a1 - a0) * k, 64, edge, 1.0, false)
				else:
					draw_arc(K.rndv(c), rr, a0, a1, 64, Color(C_HEUK, 0.55), maxf(2.0, th), false)
					draw_arc(K.rndv(c), rr + th * 0.5, a0, a1, 64, Color(C_CHEONG, 0.9), 1.0, false)
					draw_arc(K.rndv(c), rr - th * 0.5, a0, a1, 64, Color(C_CHEONG, 0.6), 1.0, false)
			Avatar.Shape.SWEEP:
				var dsw: Vector2 = Vector2(av.tg_dx[i], av.tg_dy[i])
				var perp: Vector2 = Vector2(-dsw.y, dsw.x)
				var front: float = av.tg_v[i] * maxf(0.0, age) if fired else 0.0
				var half: float = av.tg_a[i]
				var gapc: float = av.tg_c[i]
				var gh: float = av.tg_tick[i] * 0.5
				var base: Vector2 = c + dsw * front
				if not fired:
					# 진행로 미리보기(쓸고 갈 띠)
					_rect_poly(c - perp * half, perp, half * 2.0, 6.0, Color(C_CHEONG, 0.25 + 0.3 * k))
					draw_line(K.rndv(c + perp * (gapc - gh)), K.rndv(c + perp * (gapc + gh)), C_HANJI, 2.0)
				else:
					_rect_poly(base - perp * half, perp, half - gh + gapc, av.tg_b[i] + 2.0, Color(C_CHEONG, 0.85))
					_rect_poly(base + perp * (gapc + gh), perp, half - gh - gapc, av.tg_b[i] + 2.0, Color(C_CHEONG, 0.85))
					_rect_edge(base - perp * half, perp, half * 2.0, av.tg_b[i] + 4.0, Color(C_HEUK, 0.7))


func _draw_task_ground(td: TrialDirector, now: float, fade: float) -> void:
	var tk: Task = td.task as Task
	if tk == null:
		return
	var dc: Color = _deity_col(td.active_deity)
	var pl: Player = Game.player as Player
	var pp: Vector2 = pl.render_pos if pl != null else Vector2.ZERO
	match tk.kind:
		Task.Kind.HOLD:
			var inside: bool = pp.distance_to(tk.zone) <= tk.zone_r
			draw_circle(K.rndv(tk.zone), tk.zone_r, Color(C_HANJI, (0.10 if inside else 0.05) * fade), true, -1.0, false)
			_dash_circle(tk.zone, tk.zone_r, Color(C_HANJI, (0.9 if inside else 0.6) * fade), 28, 1.0, now * 0.2)
			_ring(tk.zone, tk.zone_r - 3.0, Color(dc, 0.35 * fade), 1.0)
		Task.Kind.ESCORT_WATER:
			draw_circle(K.rndv(tk.zone), tk.zone_r, Color(C_CHEONG, 0.22 * fade), true, -1.0, false)
			for k in 3:
				var rk: float = fmod(now * 18.0 + float(k) * tk.zone_r / 3.0, tk.zone_r)
				_ring(tk.zone, rk, Color(0.55, 0.75, 0.85, 0.5 * (1.0 - rk / tk.zone_r) * fade), 1.0)
			_ring(tk.zone, tk.zone_r, Color(C_HANJI, 0.7 * fade), 1.0)
			for i in tk.o_count:
				if tk.ost[i] == 1:
					var sp: Vector2 = Vector2(tk.ox[i], tk.oy[i])
					var rr: float = 6.0 + fmod(now * 6.0 + float(i), 5.0)
					draw_set_transform(K.rndv(sp), 0.0, Vector2(1.0, 0.5))
					draw_arc(Vector2.ZERO, rr, 0.0, TAU, 24, Color(0.55, 0.75, 0.85, 0.6 * fade), 1.0, false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		Task.Kind.CONNECT:
			# 이어진 별 사이 실선, 다음 별까지 점선
			for i in 6:
				if tk.ost[i] == 2 and tk.ost[i + 1] == 2:
					draw_line(K.rndv(Vector2(tk.ox[i], tk.oy[i])), K.rndv(Vector2(tk.ox[i + 1], tk.oy[i + 1])), Color(C_HANJI, 0.9 * fade), 1.0)
			if tk.star_next > 0 and tk.star_next < 7:
				var a: Vector2 = Vector2(tk.ox[tk.star_next - 1], tk.oy[tk.star_next - 1])
				var b: Vector2 = Vector2(tk.ox[tk.star_next], tk.oy[tk.star_next])
				var segs: int = int(a.distance_to(b) / 8.0)
				for s in segs:
					if s % 2 == 0:
						draw_line(K.rndv(a.lerp(b, float(s) / float(segs))), K.rndv(a.lerp(b, float(s + 1) / float(segs))), Color(C_HANJI, 0.45 * fade), 1.0)
				# 사슬 시한
				var left: float = clampf(1.0 - (now - tk.star_last_t) / tk.star_timeout, 0.0, 1.0)
				draw_arc(K.rndv(pp), 20.0, -PI * 0.5, -PI * 0.5 + TAU * left, 32, Color(C_HANJI, 0.6), 1.0, false)
			for i in 7:
				var sp2: Vector2 = Vector2(tk.ox[i], tk.oy[i])
				var nxt: bool = i == tk.star_next
				_ring(sp2, K.UNIT_PX * 1.0, Color(C_HANJI if nxt else C_HANJI_DK, (0.8 if nxt else 0.3) * fade), 1.0)
		Task.Kind.INSTALL:
			for i in 5:
				var fp: Vector2 = Vector2(tk.ox[i], tk.oy[i])
				var oc: Color = OBANG[FLAG_OBANG[i]]
				draw_circle(K.rndv(fp), 1.2 * K.UNIT_PX, Color(oc, 0.18 * fade), true, -1.0, false)
				_ring(fp, 1.2 * K.UNIT_PX, Color(oc, 0.8 * fade), 1.0)
				if tk.ost[i] != 2 and tk.ot[i] > 0.0:
					draw_arc(K.rndv(fp), 1.2 * K.UNIT_PX + 3.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(tk.ot[i] / 0.8, 0.0, 1.0), 32, C_HANJI, 2.0, false)
				elif tk.ost[i] == 2 and tk.ot[i] > 0.0:
					draw_arc(K.rndv(fp), 1.2 * K.UNIT_PX + 3.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(tk.ot[i] / 2.0, 0.0, 1.0), 32, C_HOT, 2.0, false)
		Task.Kind.HERD:
			draw_circle(K.rndv(tk.zone), tk.zone_r, Color(C_MEOK, 0.5 * fade), true, -1.0, false)
			for k in 4:
				_dash_circle(tk.zone, tk.zone_r * (0.3 + 0.2 * float(k)), Color(C_CHEONG, 0.6 * fade), 10 + k * 4, 1.0, now * (1.5 - 0.3 * float(k)))
			_ring(tk.zone, tk.zone_r, Color(C_HANJI_DK, 0.9 * fade), 1.0)
		Task.Kind.GUTSANG:
			_dash_circle(tk.zone, 1.5 * K.UNIT_PX, Color(C_JEOK, 0.5 * fade), 16, 1.0, now * 0.3)
			_dash_circle(tk.zone, 5.0 * K.UNIT_PX, Color(C_HANJI, 0.25 * fade), 40, 1.0, -now * 0.1)


# ─── 위층 ──────────────────────────────────────────────────────────────

func _update_avatar_sprite() -> void:
	if _av_sprite == null:
		return
	var td: TrialDirector = dir as TrialDirector
	var av: Avatar = td.avatar as Avatar
	var show: bool = av != null and td.active_deity != &"" and (td.ph == TrialDirector.Ph.TRIAL or td.ph == TrialDirector.Ph.RESOLVE or td.ph == TrialDirector.Ph.POSSESSION)
	if not show:
		_av_sprite.visible = false
		return
	var now: float = _now()
	var ent: StringName = _fx_of("avatar_", td.active_deity)
	var horiz: bool = av.state == Avatar.St.MOVE or av.state == Avatar.St.DASH
	var dname: String = "east" if av.face_x > 0.0 else "west"
	var want: Array = ANIM_PREF.get(av.anim, ANIM_PREF[&"idle"])
	var frames: Array = []
	var flip: bool = false
	for an_v: Variant in want:
		var an: String = an_v
		if horiz or an == "move" or an == "run":
			frames = _anim(ent, an, dname)
			if frames.is_empty() and dname == "west":
				frames = _anim(ent, an, "east")
				flip = not frames.is_empty()
		if frames.is_empty():
			frames = _anim(ent, an, "south")
			flip = false
		if not frames.is_empty():
			break
	var tex: Texture2D = null
	if frames.is_empty():
		tex = _south(ent, 96)
	else:
		# ART_STYLE 4.1: idle 4f@6, 이동 8. 화신 루프는 2026-11-24 안정화(L23 끓음 PASS)로 모든 프레임을 그대로 돈다.
		var fps: float = 6.0 if av.anim == &"idle" else 8.0
		var fi: int = int((Game.anim_time() - av.anim_t0) * fps)
		if av.anim == &"attack" or av.anim == &"charge" or av.anim == &"roar":
			fi = mini(fi, frames.size() - 1)
		else:
			fi = fi % frames.size()
		tex = frames[fi]
	_av_sprite.texture = tex
	_av_sprite.flip_h = flip
	var fy: int = _feet_y(tex)
	var bob: float = 0.0
	if av.state == Avatar.St.VULN:
		bob = roundf(sin(now * 10.0))      # 숨 고르기: 1px 들썩
	if now < av.nod_until:
		bob += 1.0                         # 끄덕임 1px
	_av_sprite.offset = Vector2(-float(tex.get_width()) * 0.5, -float(fy))
	_av_sprite.position = K.rndv(av.pos + Vector2(0, bob))
	var a: float = av.alpha
	if td.ph == TrialDirector.Ph.POSSESSION:
		a = clampf(1.0 - (now - td.ph_t0 - 0.15) / 0.35, 0.0, 1.0)
	_av_sprite.modulate = Color(1, 1, 1, a)
	if _av_mat != null:
		var fl: int = 0
		if now < av.flash_until:
			fl = 1
		elif td.ph == TrialDirector.Ph.RESOLVE and now - td.ph_t0 < 0.1:
			# 해결 순간 0.1s 만 번쩍(위엄 적 / 가호 흰) — 이후는 본래 모습으로 미소 짓고 빛의 실로 풀린다
			fl = 1 if td.res_face == &"gaho" else 3
		_av_mat.set_shader_parameter("flash_idx", fl)
	_av_sprite.visible = true


func _draw_top() -> void:
	var td: TrialDirector = dir as TrialDirector
	var now: float = _now()
	var ph: int = td.ph
	var pl: Player = Game.player as Player
	var pp: Vector2 = pl.render_pos if pl != null else Vector2.ZERO
	# 신장대(OMEN~CONFIRM): 강림 0.8s → 정지 소품. 재점 = 올라갔다 다시 내려옴
	if ph >= TrialDirector.Ph.OMEN and ph <= TrialDirector.Ph.CONFIRM:
		for i in 2:
			_draw_pole(td.cand[i], td.circle[i], now - maxf(td.omen_t0, td.reroll_t + 0.5), now - td.reroll_t, ph == TrialDirector.Ph.OMEN)
		if td.santong_on:
			_draw_santong(td.santong_pos, now, td.santong_k)
	if ph >= TrialDirector.Ph.CLEAR and ph <= TrialDirector.Ph.AFTERGLOW and td.active_deity != &"":
		var fade: float = 1.0 if ph != TrialDirector.Ph.AFTERGLOW else clampf(1.0 - (now - td.ph_t0) / td.afterglow_s, 0.0, 1.0)
		var pole: Texture2D = _t("res://assets/props/prop_sinjangdae.png")
		for k in 4:
			var q: Vector2 = td.anchor + Vector2.from_angle(TAU * float(k) / 4.0 + PI * 0.25) * td.ground_r
			_tex_flip(pole, q, Vector2(8, 62), Color(1, 1, 1, 0.85 * fade), false)
		_draw_task_top(td, now, fade)
		var av: Avatar = td.avatar as Avatar
		if av != null and (ph == TrialDirector.Ph.TRIAL or ph == TrialDirector.Ph.RESOLVE):
			_draw_bullets(av)
			_draw_avatar_gauge(td, av, now)
			if av.tether_until > now:
				var tc: Color = C_HOT if av.pos.distance_to(pp) > av.tether_max_px else Color(C_HANJI, 0.6)
				draw_line(K.rndv(av.pos + Vector2(0, -20)), K.rndv(pp + Vector2(0, -20)), tc, 1.0)
			# 위엄 시험 타격(무당 → 화신): 적 '퇴치' 문법(붉은 파열·피해 숫자) 대신 황·한지 '징' 울림 — 신령은 처치 대상이 아니다
			var ha: float = now - td.last_hit_t
			if ph == TrialDirector.Ph.TRIAL and ha >= 0.0 and ha < 0.22:
				var chest: Vector2 = av.pos + Vector2(0, -roundf(float(av.size_px) * 0.36))
				if ha < 0.08:
					draw_line(K.rndv(td.last_hit_from + Vector2(0, -20)), K.rndv(chest), Color(C_HWANG, 1.0 - ha / 0.08), 1.0)
				var jk: float = ha / 0.22
				var jr: float = roundf(lerpf(10.0, 30.0 if td.last_hit_crit else 24.0, 1.0 - (1.0 - jk) * (1.0 - jk)))
				draw_arc(K.rndv(chest), jr, 0.0, TAU, 32, Color(C_HWANG, 1.0 - jk), 2.0, false)
				if jr > 14.0:
					draw_arc(K.rndv(chest), jr - 5.0, 0.0, TAU, 28, Color(C_HANJI, 0.7 * (1.0 - jk)), 1.0, false)
			# 위엄 5% 눈금: 화신 위로 '위엄' 글자가 떠오른다(0.6s, 정수 px 상승)
			var pa: float = now - td.wieom_pop_t
			if ph == TrialDirector.Ph.TRIAL and pa >= 0.0 and pa < 0.6 and _font != null:
				var py: float = roundf(-float(av.size_px) * 0.45 - minf(pa / 0.3, 1.0) * 8.0)
				var pc: Color = Color(C_HWANG, 1.0 if pa < 0.45 else (0.6 - pa) / 0.15)
				var pp2: Vector2 = K.rndv(av.pos + Vector2(roundf(float(av.size_px) * 0.22) - 6.0, py))
				draw_string_outline(_font, pp2, "싸움", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 12, 3, Color(C_MEOK, pc.a * 0.9))
				draw_string(_font, pp2, "싸움", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 12, pc)
		# 빛의 실(POSSESSION 0.15~0.5)
		if ph == TrialDirector.Ph.POSSESSION and av != null:
			var t: float = now - td.ph_t0
			if t >= 0.1 and t <= 0.6:
				var k: float = clampf((t - 0.15) / 0.35, 0.0, 1.0)
				var tc2: Color = C_HOT if td.res_face == &"wieom" else C_HANJI
				var lines: int = 4 if td.res_complete else 2
				for j in lines:
					_thread(av.pos + Vector2(0, -float(av.body_r_px)), pp + Vector2(0, -24), k, float(j) - float(lines - 1) * 0.5, tc2)
			if t >= 0.55 and t < 1.2:
				var ck: float = 1.0 - (t - 0.55) / 0.65
				var cw: float = 10.0 * ck + 2.0
				draw_rect(Rect2(K.rndv(pp + Vector2(-cw * 0.5, -150.0)), Vector2(roundf(cw), 150.0)), Color(_deity_col(td.active_deity), 0.35 * ck))
				draw_rect(Rect2(K.rndv(pp + Vector2(-1, -150.0)), Vector2(2, 150.0)), Color(C_HANJI, 0.7 * ck))
		_draw_guide(td, pp, now)
	_draw_power_fx(td, now)
	# 합일: 신장대 + 반투명 화신
	if ph >= TrialDirector.Ph.HAPIL_OMEN and ph <= TrialDirector.Ph.HAPIL_CALL:
		for i in td.hapil_ids.size():
			var d: StringName = td.hapil_ids[i]
			var q2: Vector2 = pp + td.hapil_pos[i]
			_draw_pole(d, q2, now - td.ph_t0 if ph == TrialDirector.Ph.HAPIL_OMEN else 9.0, 9.0, false)
	# (반투명 화신은 _draw_hapil_ghosts — 지면 층으로 옮겼다)


## 합일 반투명 화신(지면 층). α 0.4, 호명이 끝난 신령은 0.18.
## 몸 사각형이 무당 몸 상자(발 기준 x±20, y−44~+20)와 겹치면 α ≤ 0.15 — 무당을 0.3초 안에 찾게(design/18 ①).
## (가시성 리뷰 11-25: 0.25 는 지면 층 아래에서 신령 강림이 거의 안 보였다 — 합일은 런의 큰 박. 적·공격은 이 위에 그려지므로 가리지 않는다.)
func _draw_hapil_ghosts(td: TrialDirector, pp: Vector2) -> void:
	var body: Rect2 = Rect2(pp + Vector2(-20, -44), Vector2(40, 64))
	for i in mini(td.hapil_ids.size(), td.hapil_pos.size()):
		var d: StringName = td.hapil_ids[i]
		var q2: Vector2 = pp + td.hapil_pos[i]
		var gt: Texture2D = _south(_fx_of("avatar_", d), 96)
		if gt == null:
			continue
		var ga: float = 0.4
		if td.ph == TrialDirector.Ph.HAPIL_CALL and td.hapil_idx >= i:
			ga = 0.18
		var piv: Vector2 = Vector2(float(gt.get_width()) * 0.5, float(_feet_y(gt)))
		var feet: Vector2 = q2 + Vector2(0, -4)
		var gr: Rect2 = Rect2(feet - piv, gt.get_size())
		if gr.intersects(body):
			ga = minf(ga, 0.15)
		_tex_flip(gt, feet, piv, Color(1, 1, 1, ga), false)


func _draw_pole(d: StringName, feet: Vector2, age: float, reroll_age: float, ghost: bool) -> void:
	var lift: float = 0.0
	if reroll_age >= 0.0 and reroll_age < 0.5:
		lift = -ease(reroll_age / 0.5, 2.0) * 90.0
	var col: Color = Color(1, 1, 1, 0.75 if ghost else 1.0)
	if age >= 0.0 and age < 0.8 and (reroll_age < 0.0 or reroll_age >= 0.5):
		# 강림: 하늘에서 꽂히는 시트(발 피벗) + 꽂히는 순간 먼지 고리
		_fx_frame(_fx_of("vfx_sinjangdae_descend_", d), feet, age, col, false)
		if age > 0.45:
			_ring(feet, 4.0 + (age - 0.45) * 60.0, Color(C_HANJI, 1.0 - (age - 0.45) / 0.35), 1.0)
		return
	var t: Texture2D = _t("res://assets/props/prop_sinjangdae.png")
	_tex_flip(t, feet + Vector2(0, lift), Vector2(8, 62), col, false)
	# 신령 빛 술(깃 끝 2px 흔들림)
	var sway: float = roundf(sin(_now() * 3.0 + feet.x) * 1.0)
	draw_rect(Rect2(K.rndv(feet + Vector2(-3 + sway, -64 + lift)), Vector2(6, 2)), _deity_col(d, 0.9))


func _draw_santong(p: Vector2, now: float, k: float) -> void:
	# 산통(算筒): 나무 통 + 산가지 3, 흔들림
	var sh: float = roundf(sin(now * (30.0 if k > 0.0 else 3.0)) * (1.0 if k > 0.0 else 0.0))
	var base: Vector2 = K.rndv(p + Vector2(sh, 0))
	draw_rect(Rect2(base + Vector2(-4, -12), Vector2(8, 12)), Color(0.43, 0.26, 0.19))
	draw_rect(Rect2(base + Vector2(-4, -12), Vector2(8, 2)), Color(0.65, 0.44, 0.31))
	draw_rect(Rect2(base + Vector2(-4, -12), Vector2(1, 12)), C_HEUK)
	draw_rect(Rect2(base + Vector2(3, -12), Vector2(1, 12)), C_HEUK)
	for s in 3:
		draw_rect(Rect2(base + Vector2(-3 + s * 2, -17 - (s % 2) * 2), Vector2(1, 6)), C_HANJI)


func _thread(a: Vector2, b: Vector2, k: float, side: float, col: Color) -> void:
	var mid: Vector2 = (a + b) * 0.5 + Vector2(-(b - a).y, (b - a).x).normalized() * side * 26.0 + Vector2(0, -30)
	var nseg: int = 16
	var last: int = int(float(nseg) * k)
	for s in nseg + 1:
		var t: float = float(s) / float(nseg)
		var p: Vector2 = a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		_line[s] = K.rndv(p)
	var start: int = maxi(0, last - 6)
	for s in range(start, mini(last, nseg)):
		draw_line(_line[s], _line[s + 1], col, 2.0 if s >= last - 2 else 1.0)


func _draw_bullets(av: Avatar) -> void:
	if av.b_count <= 0:
		return
	for i in Avatar.B_CAP:
		if av.b_on[i] == 0:
			continue
		var p: Vector2 = K.rndv(Vector2(av.bx[i], av.by[i]))
		var r: float = av.brad[i]
		draw_circle(p, r + 1.0, C_CHEONG, true, -1.0, false)
		draw_circle(p, maxf(1.0, r - 1.0), C_HEUK, true, -1.0, false)


func _draw_avatar_gauge(td: TrialDirector, av: Avatar, now: float) -> void:
	if td.ph != TrialDirector.Ph.TRIAL:
		return
	var top: Vector2 = K.rndv(av.pos + Vector2(-20, -float(av.size_px) * 0.78))
	# 화신 이름(처음 보는 사람용: 이 존재가 '신령의 화신'이지 잡귀가 아님을 알린다)
	if _av_name_deity != td.active_deity:
		_av_name_deity = td.active_deity
		_av_name = "큰 신령 · %s" % Defs.short_name(td.active_deity)
		_av_name_w = 0.0
	# 화면 위 HUD 띠(시계·의례 슬롯·공수 레인)와 시련 안내판(trial_hud, y82~113) 안으로 올라가면 이름표는 생략
	# — HUD '시련 n · 신령' 이 같은 말을 한다. 막대 위 이름표 윗변 = top−17 이 안내판 아래(≈115)보다 아래일 때만.
	var name_on_screen_y: float = (get_viewport().get_canvas_transform() * top).y
	if _font != null and name_on_screen_y >= 132.0:
		# 이름표는 위엄 막대 위에 띄운다(글자 아래 끝 ≤ 막대 위 −3px): 먹 받침 + 글자, 막대와 겹치지 않게
		if _av_name_w <= 0.0:
			_av_name_w = roundf(_font.get_string_size(_av_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
		var nw: float = _av_name_w + 10.0
		var nr: Rect2 = Rect2(top.x + 20.0 - roundf(nw * 0.5), top.y - 17.0, nw, 13.0)
		draw_rect(nr, Color(C_HEUK, 0.62))
		draw_rect(Rect2(nr.position.x, nr.end.y - 1.0, nr.size.x, 1), Color(_deity_col(td.active_deity, 1.0), 0.7))
		draw_string_outline(_font, Vector2(nr.position.x, top.y - 7.0), _av_name, HORIZONTAL_ALIGNMENT_CENTER, nw, 12, 2, Color(C_MEOK, 0.85))
		draw_string(_font, Vector2(nr.position.x, top.y - 7.0), _av_name, HORIZONTAL_ALIGNMENT_CENTER, nw, 12, _deity_col(td.active_deity, 1.0).lightened(0.35))
	draw_rect(Rect2(top + Vector2(-1, -1), Vector2(42, 5)), C_HEUK)
	draw_rect(Rect2(top, Vector2(40, 3)), Color(C_HANJI_DK, 0.7))
	draw_rect(Rect2(top, Vector2(roundf(40.0 * td.wieom), 3)), C_JEOK)
	# 화신 타격 빛 점: 몸 → 막대 채움 끝으로 0.3초(ease-in). 닿는 순간 막대 끝 1f 한지 — '내가 친 만큼 찬다'
	var tip: Vector2 = top + Vector2(roundf(40.0 * td.wieom), 1)
	var hc: Color = _obang_of(td.active_deity)
	for k in HD_CAP:
		var ha2: float = now - _hd_t[k]
		if ha2 < 0.0 or ha2 >= HD_LIFE + 0.05:
			continue
		if ha2 >= HD_LIFE:
			draw_rect(Rect2(tip + Vector2(-2, -2), Vector2(4, 5)), C_HANJI)
			continue
		var u: float = ha2 / HD_LIFE
		var q: Vector2 = K.rndv(_hd_from[k].lerp(tip, u * u) + Vector2(0, -sin(u * PI) * 10.0))
		draw_rect(Rect2(q - Vector2(2, 2), Vector2(5, 5)), Color(C_MEOK, 0.8))
		draw_rect(Rect2(q - Vector2(1, 1), Vector2(3, 3)), hc)
		draw_rect(Rect2(q, Vector2.ONE), C_HANJI)
	if av.is_vulnerable():
		var bp: float = 0.5 + 0.5 * sin(now * 14.0)
		draw_rect(Rect2(top + Vector2(-1, -1), Vector2(42, 5)), Color(C_HANJI, 0.6 * bp), false, 1.0)
		if _font != null:
			draw_string(_font, top + Vector2(44, 5), "숨", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(C_HANJI, 0.7 + 0.3 * bp))


func _draw_task_top(td: TrialDirector, now: float, fade: float) -> void:
	var tk: Task = td.task as Task
	if tk == null:
		return
	match tk.kind:
		Task.Kind.HOLD:
			var pine: Texture2D = _t("res://assets/props/prop_pine_a.png")
			if pine != null:
				_tex_flip(pine, tk.zone + Vector2(tk.zone_r * 0.75, -6), Vector2(float(pine.get_width()) * 0.5, float(pine.get_height()) - 2.0), Color(1, 1, 1, 0.9 * fade), false)
			for i in tk.o_count:
				var p: Vector2 = Vector2(tk.ox[i], tk.oy[i])
				var t: Texture2D = _south(YG_BODIES[i % 3], 32)
				if tk.ost[i] == 1:
					var bob: float = roundf(sin(now * 2.0 + float(i)) * 1.0)
					var shake: float = roundf(sin(now * 40.0)) if tk.ot[i] > 0.2 else 0.0
					_tex_flip(t, p + Vector2(shake, bob), Vector2(16, 29), Color(1, 1, 1, 0.85 * fade), i % 2 == 1)
				elif tk.ost[i] == 3:
					var a: float = clampf(1.0 - (now - tk.ofx[i]) / 0.8, 0.0, 1.0)
					if a > 0.0:
						_tex_flip(t, p + Vector2(0, -(1.0 - a) * 24.0), Vector2(16, 29), Color(0.5, 0.6, 0.8, a), false)
		Task.Kind.ESCORT_WATER:
			var st: Texture2D = _t("res://assets/props/prop_seokdeung.png")
			_tex_flip(st, tk.zone, Vector2(16, 46), Color(1, 1, 1, fade), false)
			for i in tk.o_count:
				if tk.ost[i] == 1 or tk.ost[i] == 2:
					var t2: Texture2D = _south(YG_BODIES[2] if i % 2 == 0 else YG_BODIES[0], 32)
					var sink: float = 4.0 if tk.ost[i] == 1 else 0.0
					var col: Color = Color(0.65, 0.85, 0.95, 0.8 * fade) if tk.ost[i] == 1 else Color(1, 1, 1, 0.9 * fade)
					_tex_flip(t2, Vector2(tk.ox[i], tk.oy[i] + sink), Vector2(16, 29), col, false)
				elif tk.ost[i] == 3:
					var a2: float = clampf(1.0 - (now - tk.ofx[i]) / 0.8, 0.0, 1.0)
					_ring(tk.zone, (1.0 - a2) * tk.zone_r * 1.6, Color(C_HANJI, a2), 1.0)
		Task.Kind.CONNECT:
			for i in 7:
				var sp: Vector2 = K.rndv(Vector2(tk.ox[i], tk.oy[i]) + Vector2(0, -10))
				var lit: bool = tk.ost[i] == 2
				var nxt: bool = i == tk.star_next
				var tw: float = 0.6 + 0.4 * sin(now * 6.0 + float(i))
				var sc: Color = Color(C_HANJI, (1.0 if lit else (0.85 * tw if nxt else 0.45)) * fade)
				var arm: float = 5.0 if lit or nxt else 3.0
				draw_line(sp + Vector2(-arm, 0), sp + Vector2(arm, 0), sc, 1.0)
				draw_line(sp + Vector2(0, -arm), sp + Vector2(0, arm), sc, 1.0)
				draw_rect(Rect2(sp - Vector2(1, 1), Vector2(3, 3)), sc)
				if lit and now - tk.ofx[i] < 0.4:
					_ring(sp, 4.0 + (now - tk.ofx[i]) * 40.0, Color(C_HANJI, 1.0 - (now - tk.ofx[i]) / 0.4), 1.0)
				if nxt and _font != null:
					draw_string(_font, sp + Vector2(6, -4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(C_HANJI, 0.9 * fade))
		Task.Kind.INSTALL:
			for i in 5:
				var fp: Vector2 = Vector2(tk.ox[i], tk.oy[i])
				if tk.ost[i] == 2:
					var t3: Texture2D = _t("res://assets/props/prop_obanggi_bundle.png")
					_tex_flip(t3, fp, Vector2(16, 62), Color(1, 1, 1, fade), false)
					_fx_frame(FLAG_NAMES[i], fp + Vector2(10, -54), now - tk.ofx[i], Color(1, 1, 1, fade))
				else:
					var oc: Color = OBANG[FLAG_OBANG[i]]
					draw_rect(Rect2(K.rndv(fp + Vector2(-1, -14)), Vector2(2, 14)), Color(C_HANJI_DK, 0.6 * fade))
					draw_rect(Rect2(K.rndv(fp + Vector2(1, -14)), Vector2(6, 4)), Color(oc, 0.4 * fade))
		Task.Kind.HERD:
			# 저승 문(기둥 둘 + 갓머리)
			var g: Vector2 = K.rndv(tk.zone)
			draw_rect(Rect2(g + Vector2(-26, -44), Vector2(4, 44)), Color(0.24, 0.16, 0.14, fade))
			draw_rect(Rect2(g + Vector2(22, -44), Vector2(4, 44)), Color(0.24, 0.16, 0.14, fade))
			draw_rect(Rect2(g + Vector2(-32, -50), Vector2(64, 5)), Color(0.2, 0.12, 0.12, fade))
			draw_rect(Rect2(g + Vector2(-28, -45), Vector2(56, 2)), Color(C_JEOK, 0.8 * fade))
			draw_rect(Rect2(g + Vector2(-22, -40), Vector2(44, 40)), Color(C_MEOK, 0.55 * fade))
			# 넋이 문에 들어간 순간 문이 1f 한지로 번쩍(design/19 §5.2 F, 모심 쪽)
			if tk.last_event == &"gate" and now - tk.last_event_t < PW_FIRST:
				draw_rect(Rect2(g + Vector2(-26, -44), Vector2(4, 44)), C_HANJI)
				draw_rect(Rect2(g + Vector2(22, -44), Vector2(4, 44)), C_HANJI)
				draw_rect(Rect2(g + Vector2(-32, -50), Vector2(64, 5)), C_HANJI)
				draw_rect(Rect2(g + Vector2(-22, -40), Vector2(44, 40)), Color(C_HANJI, 0.35))
			for i in tk.o_count:
				var p3: Vector2 = Vector2(tk.ox[i], tk.oy[i])
				var t4: Texture2D = _south(YG_BODIES[1] if i % 2 == 0 else YG_BODIES[0], 32)
				if tk.ost[i] == 1:
					_tex_flip(t4, p3, Vector2(16, 29), Color(0.62, 0.66, 0.8, 0.85 * fade), tk.ovx[i] < 0.0)
				elif tk.ost[i] == 4:
					var a4: float = clampf(1.0 - (now - tk.ofx[i]) / 0.9, 0.0, 1.0)
					if a4 > 0.0:
						_tex_flip(t4, p3 + Vector2(0, -(1.0 - a4) * 30.0), Vector2(16, 29), Color(C_HANJI, a4), false)
		Task.Kind.GUTSANG:
			var stage: int = 0
			if tk.offering >= 85.0:
				stage = 3
			elif tk.offering >= 50.0:
				stage = 2
			elif tk.offering >= 20.0:
				stage = 1
			var gt: Texture2D = _t(GUTSANG_TEX[stage])
			if gt != null:
				_tex_flip(gt, tk.zone, Vector2(float(gt.get_width()) * 0.5, float(gt.get_height()) - 2.0), Color(1, 1, 1, fade), false)
			var bar: Vector2 = K.rndv(tk.zone + Vector2(-20, 6))
			draw_rect(Rect2(bar + Vector2(-1, -1), Vector2(42, 5)), C_HEUK)
			draw_rect(Rect2(bar, Vector2(40, 3)), Color(C_HANJI_DK, 0.6))
			draw_rect(Rect2(bar, Vector2(roundf(40.0 * tk.offering / 100.0), 3)), C_HWANG if tk.offering >= 50.0 else C_HOT)
			draw_rect(Rect2(bar + Vector2(20, -2), Vector2(1, 7)), C_HANJI)
	# 방금 일어난 일 반짝임
	if now - tk.last_event_t < 0.5:
		var k: float = (now - tk.last_event_t) / 0.5
		_ring(tk.last_event_pos + Vector2(0, -8), 6.0 + 18.0 * k, Color(C_HANJI, 1.0 - k), 1.0)


## 과제 길잡이: 무당 발밑에서 다음 목표 쪽으로 작은 꺾쇠(처음 하는 사람용).
func _draw_guide(td: TrialDirector, pp: Vector2, now: float) -> void:
	if td.ph != TrialDirector.Ph.TRIAL:
		return
	var tk: Task = td.task as Task
	var av: Avatar = td.avatar as Avatar
	if tk == null:
		return
	var gp: Vector2 = tk.guide_point(pp)
	var d: Vector2 = gp - pp
	if d.length() > 2.2 * K.UNIT_PX:
		var dn: Vector2 = d.normalized()
		var bob: float = 2.0 * sin(now * 6.0)
		var tip: Vector2 = K.rndv(pp + Vector2(0, -16) + dn * (26.0 + bob))
		var pr: Vector2 = Vector2(-dn.y, dn.x)
		draw_line(tip, K.rndv(tip - dn * 6.0 + pr * 4.0), C_HANJI, 1.0)
		draw_line(tip, K.rndv(tip - dn * 6.0 - pr * 4.0), C_HANJI, 1.0)
	if av != null and av.targetable():
		var da: Vector2 = av.pos - pp
		if da.length() > td.reach_u * K.UNIT_PX:
			var dn2: Vector2 = da.normalized()
			var tip2: Vector2 = K.rndv(pp + Vector2(0, -16) + dn2 * 22.0)
			var pr2: Vector2 = Vector2(-dn2.y, dn2.x)
			draw_line(tip2, K.rndv(tip2 - dn2 * 5.0 + pr2 * 3.0), C_JEOK, 1.0)
			draw_line(tip2, K.rndv(tip2 - dn2 * 5.0 - pr2 * 3.0), C_JEOK, 1.0)


## 무당 발밑 신령 표지 1f(design/19 §5.2 F): 방금(첫 1f) 나간 권능 중 가장 새 것의 신령 confirm_ring 한 프레임(다 찬 고리).
func _draw_power_foot() -> void:
	var td: TrialDirector = dir as TrialDirector
	var pw: Powers = td.powers as Powers
	var pl: Player = Game.player as Player
	if pw == null or pl == null or pw.fx_deity.size() != Powers.FX_CAP:
		return
	var now: float = _now()
	for j in Powers.FX_CAP:
		var i: int = (pw._fx_head - 1 - j + Powers.FX_CAP * 2) % Powers.FX_CAP
		var age: float = now - pw.fx_t0[i]
		if age < 0.0 or age >= PW_FIRST:
			return                                  # 새 것부터 보므로 첫 1f 밖이면 끝
		var d: StringName = pw.fx_deity[i]
		if d == &"":
			continue
		_fx_frame(_fx_of("vfx_confirm_ring_", d), pl.render_pos, 99.0, Color.WHITE, false)   # 마지막 프레임 = 다 찬 고리(첫 프레임은 빈 진행 고리)
		_ring(pl.render_pos + Vector2(0, -1), 13.0, _obang_of(d), 2.0)
		return


func _draw_power_fx(td: TrialDirector, now: float) -> void:
	var pw: Powers = td.powers as Powers
	if pw == null:
		return
	var cap: int = PW_CAP_CROWD if bool(Juice.get(&"fx_crowd")) else PW_CAP
	var drawn: int = 0
	var has_d: bool = pw.fx_deity.size() == Powers.FX_CAP
	for j in Powers.FX_CAP:
		var i: int = (pw._fx_head - 1 - j + Powers.FX_CAP * 2) % Powers.FX_CAP   # 새 것부터(동시 상한에서 새 것을 남긴다)
		var age: float = now - pw.fx_t0[i]
		if age < 0.0 or age > 0.6:
			continue
		if drawn >= cap:
			break
		drawn += 1
		var p: Vector2 = Vector2(pw.fx_x[i], pw.fx_y[i])
		var col: Color = C_JEOK if pw.fx_col[i] == K.DmgColor.RED else (C_HANJI if pw.fx_col[i] == K.DmgColor.WHITE else C_HANJI_DK)
		var r: float = pw.fx_r[i]
		# 첫 1f: 신령 오방색 2px 고리(권능의 주인을 색으로)
		if age < PW_FIRST and has_d and pw.fx_deity[i] != &"":
			var fr: float = maxf(10.0, r) if pw.fx_kind[i] != Powers.Fx.LINE else 6.0
			var fc: Vector2 = p + Vector2(pw.fx_dx[i], pw.fx_dy[i]) if pw.fx_kind[i] == Powers.Fx.LINE else p
			_ring(fc, fr, _obang_of(pw.fx_deity[i]), 2.0)
		match pw.fx_kind[i]:
			Powers.Fx.STAR_FALL:
				if age < 0.12:
					var k: float = age / 0.12
					draw_line(K.rndv(p + Vector2(-10, -70) * (1.0 - k) + Vector2(0, -6)), K.rndv(p + Vector2(-2, -12) * (1.0 - k)), Color(C_HANJI, 0.9), 1.0)
				elif age < 0.4:
					var k2: float = (age - 0.12) / 0.28
					_ring(p, r * (0.6 + 0.6 * k2), Color(col, 1.0 - k2), 2.0)
					var s: Vector2 = K.rndv(p + Vector2(0, -4))
					draw_line(s + Vector2(-4, 0), s + Vector2(4, 0), Color(C_HANJI, 1.0 - k2), 1.0)
					draw_line(s + Vector2(0, -4), s + Vector2(0, 4), Color(C_HANJI, 1.0 - k2), 1.0)
			Powers.Fx.TIGER_DASH:
				var dv: Vector2 = Vector2(pw.fx_dx[i], pw.fx_dy[i])
				var k3: float = clampf(age / 0.35, 0.0, 1.0)
				var hp: Vector2 = p + dv * r * k3
				_rect_poly(p, dv, r * k3, 12.0, Color(C_JEOK, 0.35 * (1.0 - k3 * 0.5)))
				var frames: Array = _anim(&"avatar_sansin", "run", "east" if dv.x >= 0.0 else "west")
				if frames.size() > 0 and k3 < 1.0:
					var tx: Texture2D = frames[int(age * 20.0) % frames.size()]
					var tpiv: Vector2 = Vector2(float(tx.get_width()) * 0.5, float(_feet_y(tx)))
					# 범이 무당 몸 상자(x±20, y−44~+20)와 겹치는 동안은 α0.15 — 범 그림이 무당을 통째로 덮던 것(19:30 캡처, design/18 ①)
					var ta: float = 0.9
					var tpl: Player = Game.player as Player
					if tpl != null and Rect2(hp - tpiv, tx.get_size()).intersects(Rect2(tpl.render_pos + Vector2(-20, -44), Vector2(40, 64))):
						ta = 0.15
					_tex_flip(tx, hp, tpiv, Color(1, 1, 1, ta), false)
			Powers.Fx.WAVE:
				var dw: Vector2 = Vector2(pw.fx_dx[i], pw.fx_dy[i])
				var k4: float = clampf(age / 0.5, 0.0, 1.0)
				var perp: Vector2 = Vector2(-dw.y, dw.x)
				for m in 3:
					var c: Vector2 = p + dw * r * clampf(k4 - 0.08 * float(m), 0.0, 1.0)
					draw_line(K.rndv(c - perp * 96.0), K.rndv(c + perp * 96.0), Color(C_CHEONG if m > 0 else C_HANJI, 0.8 * (1.0 - k4)), 2.0 if m == 0 else 1.0)
			Powers.Fx.SPIN:
				var k5: float = clampf(age / 0.3, 0.0, 1.0)
				draw_arc(K.rndv(p), r, k5 * TAU * 1.2, k5 * TAU * 1.2 + 2.2, 24, Color(col, 1.0 - k5), 3.0, false)
				draw_arc(K.rndv(p), r * 0.7, k5 * TAU * 1.2 + PI, k5 * TAU * 1.2 + PI + 1.6, 18, Color(C_HANJI_DK, 1.0 - k5), 1.0, false)
			Powers.Fx.PULSE:
				var k6: float = clampf(age / 0.35, 0.0, 1.0)
				_ring(p, r * ease(k6, 0.4), Color(col, 1.0 - k6), 2.0)
			Powers.Fx.CLAW:
				var k7: float = clampf(age / 0.18, 0.0, 1.0)
				if k7 < 1.0:
					for m in 3:
						var o: Vector2 = K.rndv(p + Vector2(-6 + m * 6, -14))
						draw_line(o, o + Vector2(4, 10) * k7, Color(col, 1.0 - k7), 1.0)
			Powers.Fx.SPLASH:
				var k8: float = clampf(age / 0.3, 0.0, 1.0)
				_ring(p, r * (0.4 + 0.6 * k8), Color(C_CHEONGNOK.lightened(0.3), 1.0 - k8), 2.0 if k8 < 0.3 else 1.0)
			Powers.Fx.LINE:
				# 영가 사격: 한지빛 화살 줄기(0.12s) — 끝에서 짧게 번진다
				var k9: float = clampf(age / 0.12, 0.0, 1.0)
				var tgt: Vector2 = p + Vector2(pw.fx_dx[i], pw.fx_dy[i])
				if k9 < 1.0:
					draw_line(K.rndv(p.lerp(tgt, maxf(0.0, k9 - 0.4))), K.rndv(p.lerp(tgt, k9)), Color(C_HANJI, 0.95), 2.0)
				elif age < 0.3:
					var lk: float = (age - 0.12) / 0.18
					_ring(tgt, 3.0 + (age - 0.12) * 30.0, Color(C_HANJI, 1.0 - lk), 1.0)
					# 꽂힘 꽃: 오방 3색 꽃잎 3장
					for m2 in 3:
						var fq: Vector2 = K.rndv(tgt + Vector2(0, -10) + Vector2.from_angle(-PI * 0.5 + TAU * float(m2) / 3.0) * (3.0 + 4.0 * lk))
						draw_rect(Rect2(fq - Vector2(1, 1), Vector2(3, 3)), Color(OBANG[m2], 1.0 - lk))
			Powers.Fx.FLOWER:
				# 삼색꽃 표식: 적·황·청 꽃잎 세 장이 피었다 진다
				var k10: float = clampf(age / 0.45, 0.0, 1.0)
				var pr2: float = 3.0 + 5.0 * ease(k10, 0.4)
				for m in 3:
					var q2: Vector2 = K.rndv(p + Vector2(0, -12) + Vector2.from_angle(-PI * 0.5 + TAU * float(m) / 3.0 + k10) * pr2)
					var pc: Color = OBANG[m]
					draw_rect(Rect2(q2 - Vector2(1, 1), Vector2(3, 3)), Color(pc, 1.0 - k10))
			Powers.Fx.ORB_GIFT:
				var k11: float = clampf(age / 0.5, 0.0, 1.0)
				_ring(p, r * (0.5 + k11), Color(C_HWANG, 1.0 - k11), 2.0)
				_ring(p, r * (0.3 + 0.8 * k11), Color(C_HANJI, 0.6 * (1.0 - k11)), 1.0)


# ─── 무당 오버레이(빙의 머리·지물·신장 호위) ─────────────────────────────

func _draw_over() -> void:
	var td: TrialDirector = dir as TrialDirector
	var pl: Player = Game.player as Player
	if pl == null or pl.dead:
		return
	var now: float = _now()
	var pw: Powers = td.powers as Powers
	if pw != null and pw.howi_on:
		for k in 4:
			var a: float = pw.orbit_t * 1.05 + TAU * float(k) / 4.0
			var q: Vector2 = pl.render_pos + Vector2.from_angle(a) * 1.4 * K.UNIT_PX
			var t: Texture2D = _south(HOWI_ENT[k], 48)
			_tex_flip(t, q, Vector2(24, 45), Color(1, 1, 1, 0.8), false)
	if td.overlay_deity == &"":
		return
	if _anchor_char != Game.char_id:
		_load_head_anchor()
	var f: int = pl.facing
	_ensure_overlay(td.overlay_deity, td.overlay_face)
	var head: Texture2D = _ov_head[f] if _ov_head[f] != null else _ov_head[0]
	var hp: Vector2 = pl.render_pos + _head_off[f]
	# 스냅 직후 0.12s: 1px 위로 튀었다 앉음
	var snap: float = -1.0 if now - td.overlay_t < 0.12 else 0.0
	if head != null:
		_tex_flip(head, hp + Vector2(0, snap), Vector2(16, 24), Color.WHITE, false)
	var jm: Texture2D = _ov_jimul[f]
	if jm != null and f != K.Dir.NORTH:
		var hx: float = 9.0 if f != K.Dir.WEST else -9.0
		_tex_flip(jm, pl.render_pos + Vector2(hx, -14), Vector2(16, 24), Color(1, 1, 1, 0.9), false)


## 빙의 오버레이 텍스처(머리 4방향·지물 4방향)를 빙의가 바뀔 때만 다시 찾는다.
func _ensure_overlay(d: StringName, face: StringName) -> void:
	if d == _ov_deity and face == _ov_face:
		return
	_ov_deity = d
	_ov_face = face
	var ok: String = Defs.overlay_key(d)
	for i in 4:
		var dn: String = K.DIRS[i]
		_ov_head[i] = _t("res://assets/sprites/overlay_head/%s_%s_%s_0.png" % [ok, String(face), dn])
		_ov_jimul[i] = _t("res://assets/sprites/overlay_jimul/%s_%s_0.png" % [ok, dn])
