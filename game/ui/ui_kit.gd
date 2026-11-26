class_name UiKit
extends RefCounted
## UI 공용 도구(폰트·색·패널·라벨·그리기 도우미). 소유: ui.
## 정적 함수만 둔다(static var 캐시 금지 — 리소스는 ResourceLoader 캐시를 그대로 쓴다).
## 폰트 픽셀 정합 크기(측정: PIL 회색 픽셀 0): Galmuri11=12, Galmuri11-Bold=12, Galmuri9=10, Galmuri7=8, Galmuri14=15, 붓=정수.
## 색: 캐논 팔레트만. 백(#f2ece0)은 월드 해원 표지(풀릴 기색 화살표·길베 예상선·해원 이름표)에만 쓴다.

const F_BODY: String = "res://assets/fonts/galmuri/Galmuri11.ttf"
const F_BOLD: String = "res://assets/fonts/galmuri/Galmuri11-Bold.ttf"
const F_SMALL: String = "res://assets/fonts/galmuri/Galmuri9.ttf"
const F_TINY: String = "res://assets/fonts/galmuri/Galmuri7.ttf"
const F_BIG: String = "res://assets/fonts/galmuri/Galmuri14.ttf"
const F_BRUSH: String = "res://assets/fonts/nanum_brush/NanumBrushScript-Regular.ttf"

const SZ_BODY: int = 12
const SZ_SMALL: int = 10
const SZ_TINY: int = 8
const SZ_BIG: int = 15

const SKIN: String = "res://ui/theme/skin/"
const ICON_DIR: String = "res://ui/icons/"

# 팔레트(art_palette.json 램프에서 고른 UI 색)
const MEOK: Color = Color("0e0b16")
const MEOK_1: Color = Color("17131f")
const MEOK_2: Color = Color("221c2e")
const MEOK_3: Color = Color("2f2840")
const MEOK_4: Color = Color("3f3654")
const MEOK_5: Color = Color("544a6b")
const HANJI: Color = Color("e9dcc0")
const HANJI_UI: Color = Color("f6eedc")      # UI 전용 밝은 한지
const HANJI_2: Color = Color("d2c19c")
const HANJI_3: Color = Color("b29d76")
const HANJI_4: Color = Color("857154")
const HANJI_5: Color = Color("5a4a37")
const JEOK: Color = Color("c8322d")
const JEOK_HI: Color = Color("e4604f")
const JEOK_DK: Color = Color("8c1f22")
const JEOK_DDK: Color = Color("561318")
const HWANG: Color = Color("e8b931")
const HWANG_HI: Color = Color("f5d66b")
const HWANG_DK: Color = Color("a97c1b")
const CHEONGNOK: Color = Color("55b8aa")
const CHEONGNOK_DK: Color = Color("2f8c86")
const NOK_DC: Color = Color("3e6a5a")         # 단청 뇌록
const CHEONG_DC: Color = Color("3b4f6e")      # 단청 군청(예약 청 아님)
const DANJU: Color = Color("7a3a2c")          # 석간주
const BAEK: Color = Color("f2ece0")           # 예약: 해원 표지 전용
const OUTLINE: Color = Color("1a1a1a")
const INK: Color = Color("3a2f2a")             # pal_ink_text: 한지 패널 위 본문 글자
const DC_COLS: Array[Color] = [JEOK_DK, HWANG, CHEONG_DC, CHEONGNOK_DK]


## 폰트 래스터 설정을 픽셀용으로 고정(임포트 설정이 바뀌어도 안전). 여러 번 불러도 된다.
static func setup_fonts() -> void:
	for p: String in [F_BODY, F_BOLD, F_SMALL, F_TINY, F_BIG, F_BRUSH]:
		var f: FontFile = load(p) as FontFile
		if f == null:
			continue
		if f.antialiasing != TextServer.FONT_ANTIALIASING_NONE:
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		if f.hinting != TextServer.HINTING_NONE:
			f.hinting = TextServer.HINTING_NONE
		if f.subpixel_positioning != TextServer.SUBPIXEL_POSITIONING_DISABLED:
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		# 굵은 갈무리·붓 폰트에 없는 글리프(한자·기호)는 갈무리11 로 대체
		if (p == F_BOLD or p == F_BRUSH) and f.fallbacks.is_empty():
			var fb: FontFile = load(F_BODY) as FontFile
			if fb != null:
				f.fallbacks = [fb]


static func font(path: String) -> Font:
	var f: Font = load(path) as Font
	if f == null:
		f = ThemeDB.fallback_font
	return f


static func body() -> Font:
	return font(F_BODY)


static func bold() -> Font:
	return font(F_BOLD)


static func small() -> Font:
	return font(F_SMALL)


static func tiny() -> Font:
	return font(F_TINY)


static func big() -> Font:
	return font(F_BIG)


static func brush() -> Font:
	return font(F_BRUSH)


static func skin(name: String) -> Texture2D:
	return SpriteLib.tex(SKIN + name)


## 무구 아이콘(약 38px 원본 / _16 HUD용). 없으면 null → 호출자가 글리프로 대체.
static func weapon_icon(id: String, small_16: bool = false) -> Texture2D:
	var base: String = id.split("__")[0]
	var p: String = "%s%s%s.png" % [ICON_DIR, base, "_16" if small_16 else ""]
	if not ResourceLoader.exists(p):
		var root: String = _base_weapon_of(base)   # 진화·결합: 원무구 아이콘(core 통합)
		if root == "" or root == base:
			return null
		p = "%s%s%s.png" % [ICON_DIR, root, "_16" if small_16 else ""]
		if not ResourceLoader.exists(p):
			return null
	return SpriteLib.tex(p)


## 무구·진화·결합 정의(무구 표에 없으면 진화·결합 표).
static func weapon_def(id: String) -> Dictionary:
	var d: Dictionary = Data.weapon(id)
	if d.is_empty():
		d = Data.evolution(id)
	if d.is_empty():
		d = Data.union(id)
	return d


## 진화(recipe.weapon)·결합(recipe.evolutions[0] → 그 원무구)의 원무구 ID.
static func _base_weapon_of(id: String) -> String:
	var d: Dictionary = Data.evolution(id)
	if d.is_empty():
		var u: Dictionary = Data.union(id)
		var evs: Variant = (u.get("recipe", {}) as Dictionary).get("evolutions", [])
		if evs is Array and (evs as Array).size() > 0:
			d = Data.evolution(String((evs as Array)[0]))
	return String((d.get("recipe", {}) as Dictionary).get("weapon", ""))


## 9-patch 패널: "hanji" | "hanji_plain" | "meok" | "meok_plain"
static func panel_style(kind: String = "meok", pad: int = 6) -> StyleBoxTexture:
	var sb: StyleBoxTexture = StyleBoxTexture.new()
	sb.texture = skin("panel_%s.png" % kind)
	var m: float = 5.0
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


static func flat_style(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad: int = 4) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = false
	return sb


static func label(text: String, f: Font = null, size: int = SZ_BODY, col: Color = HANJI, shadow: bool = true,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f if f != null else body())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if shadow:
		l.add_theme_color_override("font_shadow_color", MEOK)
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
	else:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


## 붓 제목(먹 외곽 1px). size 는 정수.
static func brush_label(text: String, size: int = 32, col: Color = HANJI, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l: Label = label(text, brush(), size, col, false, align)
	l.add_theme_color_override("font_outline_color", MEOK)
	l.add_theme_constant_override("outline_size", 2)
	return l


static func place(c: Control, anchor: Vector2, off: Vector2, sz: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = off.x
	c.offset_top = off.y
	c.offset_right = off.x + sz.x
	c.offset_bottom = off.y + sz.y


static func button(text: String, min_w: int = 96) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 18)
	b.focus_mode = Control.FOCUS_ALL
	return b


static func char_name(id: String) -> String:
	var def: Dictionary = Data.character(id)
	var nm: Variant = def.get("name", id)
	if nm is Dictionary:
		return String((nm as Dictionary).get("ko", id))
	return String(nm)


static func char_hanja(id: String) -> String:
	var nm: Variant = Data.character(id).get("name", {})
	if nm is Dictionary and (nm as Dictionary).get("hanja") != null:
		return String((nm as Dictionary).get("hanja", ""))
	return ""


static func enemy_name(id: String) -> String:
	var def: Dictionary = Data.enemy(id)
	for k: String in ["name_ko", "display_ko"]:
		if def.has(k):
			return String(def[k])
	var nm: Variant = def.get("name", null)
	if nm is Dictionary:
		return String((nm as Dictionary).get("ko", id))
	if nm is String:
		return String(nm)
	return id.trim_prefix("enm_").trim_prefix("elite_").trim_prefix("mboss_").trim_prefix("boss_")


static func deity_name(id: String) -> String:
	var d: Dictionary = Data.deity(id)
	for k: String in ["name_ko", "display_ko"]:
		if d.has(k):
			return String(d[k])
	var nm: Variant = d.get("name", null)
	if nm is Dictionary:
		return String((nm as Dictionary).get("ko", id))
	if nm is String:
		return String(nm)
	return id.trim_prefix("deity_")


## 거리 정의(waves_stage1.geori[]). 없으면 빈 사전.
static func geori_def(id: StringName) -> Dictionary:
	var arr: Variant = Data.get_value("waves_stage1", "geori", [])
	if arr is Array:
		for g: Variant in arr:
			if g is Dictionary and String((g as Dictionary).get("id", "")) == String(id):
				return g
	return {}


## 무구 색 종류: "red" | "white" | "union"
static func weapon_color(id: String) -> String:
	var d: Dictionary = weapon_def(id)
	return String(d.get("color", "red"))


# ─── _draw 도우미(할당 없음) ────────────────────────────────────────────

## 픽셀 프레임 막대: 먹 바탕 + 1px 외곽 + 채움. k 0..1
static func draw_bar(ci: CanvasItem, r: Rect2, k: float, fill: Color, back: Color = MEOK_1, frame: Color = HANJI_5) -> void:
	ci.draw_rect(r.grow(1.0), MEOK)
	ci.draw_rect(r, back)
	var w: float = roundf(r.size.x * clampf(k, 0.0, 1.0))
	if w > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), fill)
		if r.size.y >= 4.0:
			ci.draw_rect(Rect2(r.position, Vector2(w, 1.0)), fill.lightened(0.25))
	ci.draw_rect(r.grow(1.0), frame, false, 1.0)


## 마름모(◆, 붉은 무구 표지)
static func draw_diamond(ci: CanvasItem, c: Vector2, r: float, col: Color, filled: bool = true) -> void:
	var pts: PackedVector2Array = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, 1.0)


## 단청 띠(가로): 녹·적·황·청 반복 문양
static func draw_dancheong(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, NOK_DC)
	var x: float = r.position.x
	var i: int = 0
	while x < r.end.x - 1.0:
		var w: float = minf(6.0, r.end.x - x)
		var c: Color = DC_COLS[i % 4]
		ci.draw_rect(Rect2(Vector2(x + 1.0, r.position.y + 1.0), Vector2(maxf(w - 2.0, 1.0), maxf(r.size.y - 2.0, 1.0))), c)
		x += 6.0
		i += 1
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1.0)), MEOK)
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - 1.0), Vector2(r.size.x, 1.0)), MEOK)


## 붉은 낙관(인장): 사각 + 흰 글자(한지)
static func draw_seal(ci: CanvasItem, pos: Vector2, s: float, text: String, f: Font, fsize: int) -> void:
	ci.draw_rect(Rect2(pos, Vector2(s, s)), JEOK)
	ci.draw_rect(Rect2(pos + Vector2(1, 1), Vector2(s - 2.0, s - 2.0)), HANJI_UI, false, 1.0)
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	ci.draw_string(f, pos + Vector2(roundf((s - tw) * 0.5), roundf(s * 0.5 + fsize * 0.35)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, HANJI_UI)


## 점선(대시) 선분
static func draw_dashed(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, dash: float = 4.0, gap: float = 3.0, phase: float = 0.0, width: float = 1.0) -> void:
	var d: Vector2 = b - a
	var len: float = d.length()
	if len < 1.0:
		return
	var dir: Vector2 = d / len
	var t: float = -fposmod(phase, dash + gap)
	while t < len:
		var t0: float = maxf(t, 0.0)
		var t1: float = minf(t + dash, len)
		if t1 > t0:
			ci.draw_line((a + dir * t0).round(), (a + dir * t1).round(), col, width)
		t += dash + gap


# ─── 추가 도우미(패널·모서리·글자·이징) ─────────────────────────────────

## 먹 패널(칩): 먹 바탕(alpha) + 1px 한지 어둠 테 + 단청 모서리 점(선택)
static func draw_meok_panel(ci: CanvasItem, r: Rect2, alpha: float = 0.86, corners: bool = true, frame: Color = HANJI_5) -> void:
	ci.draw_rect(r, Color(MEOK_1, alpha))
	ci.draw_rect(r, frame, false, 1.0)
	if corners:
		draw_corners(ci, r, HWANG_DK)


## 한지 패널: 한지 바탕 + 먹 테 + 안쪽 어둠 테 + 단청 모서리
static func draw_hanji_panel(ci: CanvasItem, r: Rect2, paper: Texture2D = null) -> void:
	ci.draw_rect(r.grow(1.0), MEOK)
	if paper != null:
		ci.draw_texture_rect(paper, r, true)
	else:
		ci.draw_rect(r, HANJI)
	ci.draw_rect(r.grow(-1.0), HANJI_3, false, 1.0)
	draw_corners(ci, r.grow(-1.0), JEOK_DK)


## 단청 모서리 장식(3px ㄱ자 + 점)
static func draw_corners(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var p0: Vector2 = r.position
	var p1: Vector2 = Vector2(r.end.x - 1.0, r.position.y)
	var p2: Vector2 = Vector2(r.position.x, r.end.y - 1.0)
	var p3: Vector2 = r.end - Vector2.ONE
	for p: Vector2 in [p0, p1, p2, p3]:
		var sx: float = 1.0 if p.x < r.get_center().x else -1.0
		var sy: float = 1.0 if p.y < r.get_center().y else -1.0
		ci.draw_rect(Rect2(p, Vector2.ONE), col)
		ci.draw_rect(Rect2(p + Vector2(sx, 0), Vector2.ONE), col)
		ci.draw_rect(Rect2(p + Vector2(2.0 * sx, 0), Vector2.ONE), col)
		ci.draw_rect(Rect2(p + Vector2(0, sy), Vector2.ONE), col)
		ci.draw_rect(Rect2(p + Vector2(0, 2.0 * sy), Vector2.ONE), col)


## 그림자 글자(먹 1px). align: 0 왼쪽, 1 가운데, 2 오른쪽 (x 기준)
static func text(ci: CanvasItem, f: Font, size: int, pos: Vector2, s: String, col: Color, align: int = 0, shadow: bool = true) -> float:
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x: float = pos.x
	if align == 1:
		x = roundf(pos.x - w * 0.5)
	elif align == 2:
		x = pos.x - w
	if shadow:
		ci.draw_string(f, Vector2(x + 1.0, pos.y + 1.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(MEOK, col.a))
	ci.draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return w


## 외곽선 글자(월드 위 자막·붓 슬램): 먹 외곽 outline px
static func text_outline(ci: CanvasItem, f: Font, size: int, pos: Vector2, s: String, col: Color, align: int = 1, outline: int = 2) -> float:
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x: float = pos.x
	if align == 1:
		x = roundf(pos.x - w * 0.5)
	elif align == 2:
		x = pos.x - w
	if outline > 0:
		ci.draw_string_outline(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline * 2, Color(MEOK, col.a))
	ci.draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return w


## 글자 줄바꿈(한글 글자 단위, 공백 우선). 열 때 한 번만 부른다(할당 있음).
static func wrap(f: Font, size: int, s: String, max_w: float, max_lines: int = 4) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for para: String in s.split("\n"):
		var line: String = ""
		var words: PackedStringArray = para.split(" ")
		for wi in words.size():
			var word: String = words[wi]
			var cand: String = word if line == "" else line + " " + word
			if f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
				line = cand
				continue
			if line != "":
				out.append(line)
				line = ""
			# 단어 자체가 길면 글자 단위로 자른다
			var chunk: String = ""
			for ch: String in word:
				if f.get_string_size(chunk + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w and chunk != "":
					out.append(chunk)
					chunk = ""
				chunk += ch
			line = chunk
		if line != "":
			out.append(line)
	if out.size() > max_lines:
		out.resize(max_lines)
		out[max_lines - 1] = out[max_lines - 1].left(maxi(0, out[max_lines - 1].length() - 1)) + "…"
	return out


static func ease_out_back(t: float) -> float:
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	var u: float = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + c3 * u * u * u + c1 * u * u


static func ease_out_cubic(t: float) -> float:
	var u: float = 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u


## 무구 표지: 붉은 = ◆ 마름모, 흰 = ○ 원(한지). 결합 = 반반
static func draw_kind_mark(ci: CanvasItem, c: Vector2, r: float, white: bool) -> void:
	if white:
		# ○ 고리(흰 무구 기호 통일 — 속은 먹)
		ci.draw_circle(c, r + 1.0, MEOK)
		ci.draw_circle(c, r, HANJI)
		ci.draw_circle(c, maxf(0.75, r - 1.5), MEOK_2)
	else:
		draw_diamond(ci, c, r + 1.0, MEOK)
		draw_diamond(ci, c, r, JEOK_HI)


static var _glyph_cache: Dictionary = {}


## 아이콘이 없는 무구의 대체 표지: 한지 메달(흰 = 원, 붉은 = 마름모 테) + 이름 첫 글자 붓 글씨. 글자는 id 별로 캐시.
static func draw_glyph_medallion(ci: CanvasItem, r: Rect2, id: String, white: bool, f: Font, fsize: int = SZ_SMALL) -> void:
	var g: String = _glyph_cache.get(id, "")
	if g == "":
		g = weapon_name(id).left(1)
		_glyph_cache[id] = g
	var c: Vector2 = r.get_center()
	var rad: float = floorf(minf(r.size.x, r.size.y) * 0.5)
	if white:
		ci.draw_circle(c, rad, HANJI_2)
		ci.draw_arc(c, rad - 0.5, 0.0, TAU, 20, HANJI_4, 1.0)
	else:
		draw_diamond(ci, c, rad + 1.0, HANJI_2)
		draw_diamond(ci, c, rad + 1.0, JEOK_DK, false)
	var w: float = f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	ci.draw_string(f, Vector2(roundf(c.x - w * 0.5), roundf(c.y + float(fsize) * 0.4)), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, INK)


## 픽셀 호(점 찍기). offs = 미리 계산한 단위 오프셋(할당 없음). k 0..1 채움(앞에서부터)
static func draw_arc_pts(ci: CanvasItem, center: Vector2, offs: PackedVector2Array, k: float, fill: Color, back: Color, th: float = 2.0) -> void:
	var n: int = offs.size()
	var lit: int = int(roundf(clampf(k, 0.0, 1.0) * float(n)))
	for i in n:
		var p: Vector2 = (center + offs[i]).floor()
		ci.draw_rect(Rect2(p, Vector2(th, th)), fill if i < lit else back)


## 무구 정의에서 한 줄 이름(한자 병기 선택)
static func weapon_name(id: String, with_hanja: bool = false) -> String:
	var d: Dictionary = weapon_def(id)
	var nm: String = String(d.get("name_ko", id))
	if with_hanja:
		var hj: String = String(d.get("hanja", ""))
		if hj != "" and hj != "-" and not hj.begins_with("-") and not hj.ends_with("-"):
			return "%s %s" % [nm, hj]
	return nm


## 아이콘 테두리 잘라내기(시트 슬라이스 가장자리 선 제거): 바깥 2px 를 버린 영역
static func icon_region(t: Texture2D) -> Rect2:
	var s: Vector2 = t.get_size()
	if s.x >= 24.0:
		return Rect2(Vector2(2, 2), s - Vector2(4, 4))
	return Rect2(Vector2.ZERO, s)
