class_name TutDraw
extends RefCounted
## 튜토리얼 UI 공용 그리기 도우미(인트로·권유 창·안내서·연습 HUD). 소유: ui(intro_ui).
## 정적 함수만. _draw 안에서 부르며 할당을 만들지 않는다(rich 줄 준비 함수 rich_wrap 만 열 때 한 번).

const SEAL: String = "res://ui/theme/skin/seal_red.png"


## 붉은 인장(seal_red.png 2배 = 28px) + 한지 글자. k 0..1 = 찍힘(크게 → 제자리), a = 알파
static func seal(ci: CanvasItem, center: Vector2, k: float, a: float, glyph: String, f: Font) -> void:
	var tex: Texture2D = UiKit.skin("seal_red.png")
	var s: float = roundf(28.0 + 10.0 * (1.0 - clampf(k, 0.0, 1.0)))
	var r: Rect2 = Rect2((center - Vector2(s, s) * 0.5).round(), Vector2(s, s))
	if tex != null:
		ci.draw_texture_rect(tex, r, false, Color(1, 1, 1, a))
	else:
		ci.draw_rect(r, Color(UiKit.JEOK, a))
	ci.draw_rect(r.grow(-2.0), Color(UiKit.HANJI_UI, 0.8 * a), false, 1.0)
	if glyph != "":
		var gw: float = f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		ci.draw_string(f, Vector2(roundf(center.x - gw * 0.5), roundf(center.y + 5.0)), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, Color(UiKit.HANJI_UI, a))


## 등불(초롱, 9×13 정도): 모서리 깎은 한지 몸통 + 붉은 위·아래 테 + 고리·술. 네모 칸으로 읽히지 않게(톤 리뷰 11-25).
## 꺼짐 = 먹빛 한지 / 켜짐 = 속에서 황 불빛(1px 깜박) / cur = 지금 단계(0.8Hz 은은히)
static func lantern(ci: CanvasItem, c: Vector2, lit: bool, cur: bool, t: float, a: float = 1.0, skipped: bool = false) -> void:
	var p: Vector2 = c.round()
	# 몸통 = 가로 칸 + 세로 칸(모서리 1px 깎은 팔각) · 먹 테
	var bh: Rect2 = Rect2(p + Vector2(-3, -2), Vector2(7, 5))
	var bv: Rect2 = Rect2(p + Vector2(-2, -3), Vector2(5, 7))
	var ink: Color = Color(UiKit.MEOK, 0.9 * a)
	ci.draw_rect(bh.grow(1.0), ink)
	ci.draw_rect(bv.grow(1.0), ink)
	var glow: float = 0.0
	if cur and not lit:
		glow = 0.5 + 0.5 * sin(t * TAU * 0.8)
		ci.draw_rect(bh.grow(2.0), Color(UiKit.HWANG, (0.2 + 0.4 * glow) * a), false, 1.0)
	if lit:
		var fl: float = 0.85 + 0.15 * sin(t * 11.0 + c.x)
		var shell: Color = Color(UiKit.HWANG_DK.lerp(UiKit.HWANG_HI, fl), a)
		ci.draw_rect(bh, shell)
		ci.draw_rect(bv, shell)
		# 속 불빛(한지 너머 심지) — 1px 깜박
		ci.draw_rect(Rect2(p + Vector2(-1, -1), Vector2(3, 3)), Color(UiKit.HANJI_UI, a))
		var fy: float = -2.0 if fposmod(t * 3.0 + c.x * 0.1, 1.0) < 0.5 else -1.0
		ci.draw_rect(Rect2(p + Vector2(0, fy), Vector2(1, 2)), Color(UiKit.HWANG_HI, a))
	else:
		var base: Color = UiKit.HANJI_4 if not skipped else UiKit.MEOK_4
		var sc: Color = Color(base.lerp(UiKit.HWANG_DK, glow * 0.7), a)
		ci.draw_rect(bh, sc)
		ci.draw_rect(bv, sc)
		ci.draw_rect(Rect2(p + Vector2(-2, -1), Vector2(5, 3)), Color(UiKit.MEOK_2.lerp(UiKit.HWANG_DK, glow * 0.4), a))
	# 한지 살(가로 줄 하나) — 초롱의 결
	ci.draw_rect(Rect2(p + Vector2(-3, 1), Vector2(7, 1)), Color(UiKit.MEOK, 0.35 * a))
	# 붉은 위·아래 테 + 고리(위)·술(아래)
	var rim: Color = Color(UiKit.JEOK_DK if not skipped else UiKit.MEOK_3, a)
	ci.draw_rect(Rect2(p + Vector2(-2, -5), Vector2(5, 1)), rim)
	ci.draw_rect(Rect2(p + Vector2(-2, 5), Vector2(5, 1)), rim)
	ci.draw_rect(Rect2(p + Vector2(0, -6), Vector2(1, 1)), Color(UiKit.HANJI_5, a))
	ci.draw_rect(Rect2(p + Vector2(0, 6), Vector2(1, 2)), Color(UiKit.JEOK if not skipped else UiKit.MEOK_4, a))


## 붓글씨 한 줄. 붓 글꼴의 가운뎃점(·)은 위로 떠서 따옴표(')처럼 보이므로, 그 자리에 글자 높이 가운데 먹 점을 직접 찍는다.
## 폭·정렬은 UiKit.text_outline 과 같다(반환 = 전체 폭). 할당: '·' 가 있을 때 split 1회.
static func brush_text(ci: CanvasItem, f: Font, size: int, pos: Vector2, s: String, col: Color, align: int = 1, outline: int = 2) -> float:
	if not s.contains("·"):
		return UiKit.text_outline(ci, f, size, pos, s, col, align, outline)
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x: float = pos.x
	if align == 1:
		x = roundf(pos.x - w * 0.5)
	elif align == 2:
		x = pos.x - w
	var dw: float = f.get_string_size("·", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var d: float = maxf(2.0, roundf(float(size) / 11.0))
	var parts: PackedStringArray = s.split("·")
	for i in parts.size():
		var seg: String = parts[i]
		if seg != "":
			UiKit.text_outline(ci, f, size, Vector2(x, pos.y), seg, col, 0, outline)
			x += f.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if i < parts.size() - 1:
			var dc: Vector2 = Vector2(roundf(x + dw * 0.5 - d * 0.5), roundf(pos.y - float(size) * 0.36))
			if outline > 0:
				ci.draw_rect(Rect2(dc - Vector2(outline, outline), Vector2(d + outline * 2, d + outline * 2)), Color(UiKit.MEOK, col.a))
			ci.draw_rect(Rect2(dc, Vector2(d, d)), col)
			x += dw
	return w


## '**굵게**' 표시가 있는 문장을 폭에 맞춰 줄로 나눈다(열 때 한 번). 반환: [{s: String, b: PackedByteArray}]
static func rich_wrap(f: Font, size: int, src: String, max_w: float, max_lines: int = 4) -> Array[Dictionary]:
	var plain: String = ""
	var mask: PackedByteArray = PackedByteArray()
	var bold: bool = false
	var i: int = 0
	while i < src.length():
		if src.substr(i, 2) == "**":
			bold = not bold
			i += 2
			continue
		plain += src[i]
		mask.append(1 if bold else 0)
		i += 1
	var lines: PackedStringArray = UiKit.wrap(f, size, plain, max_w, max_lines)
	var out: Array[Dictionary] = []
	var cur: int = 0
	for ln: String in lines:
		var at: int = plain.find(ln.trim_suffix("…"), cur)
		if at < 0:
			at = cur
		var b: PackedByteArray = mask.slice(at, at + ln.length())
		b.resize(ln.length())
		out.append({"s": ln, "b": b})
		cur = at + ln.length()
	return out


## rich_wrap 한 줄 그리기: 굵은 글자는 굵은 글꼴 + hi 색
static func rich_line(ci: CanvasItem, f: Font, fb: Font, size: int, pos: Vector2, line: Dictionary, col: Color, hi: Color) -> void:
	var s: String = String(line["s"])
	var b: PackedByteArray = line["b"]
	var x: float = pos.x
	var i: int = 0
	var n: int = s.length()
	while i < n:
		var j: int = i
		var bb: int = b[i] if i < b.size() else 0
		while j < n and (b[j] if j < b.size() else 0) == bb:
			j += 1
		var seg: String = s.substr(i, j - i)
		var ff: Font = fb if bb == 1 else f
		ci.draw_string(ff, Vector2(x, pos.y), seg, HORIZONTAL_ALIGNMENT_LEFT, -1, size, hi if bb == 1 else col)
		x += ff.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		i = j


## 시트(json 이 같은 이름) 의 n 번째 칸. 없으면 시트 전체.
static func sheet_frame(png_path: String, n: int = 0) -> Texture2D:
	var tex: Texture2D = SpriteLib.tex(png_path)
	if tex == null:
		return null
	var jp: String = png_path.get_basename() + ".json"
	if not FileAccess.file_exists(jp):
		return tex
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if not (d is Dictionary):
		return tex
	var fr: Variant = (d as Dictionary).get("frames", [])
	var arr: Array = []
	if fr is Array:
		arr = fr
	elif fr is Dictionary:
		arr = (fr as Dictionary).values()
	if arr.is_empty():
		return tex
	var e: Dictionary = arr[clampi(n, 0, arr.size() - 1)]
	var fd: Dictionary = e.get("frame", {})
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(float(fd.get("x", 0)), float(fd.get("y", 0)), float(fd.get("w", 16)), float(fd.get("h", 16)))
	return at


## 시트 칸 수(json). 없으면 1.
static func sheet_count(png_path: String) -> int:
	var jp: String = png_path.get_basename() + ".json"
	if not FileAccess.file_exists(jp):
		return 1
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if not (d is Dictionary):
		return 1
	var fr: Variant = (d as Dictionary).get("frames", [])
	if fr is Array:
		return maxi(1, (fr as Array).size())
	if fr is Dictionary:
		return maxi(1, (fr as Dictionary).size())
	return 1


## 엔티티 그림 프레임(idle 남향 → 없으면 정지 텍스처)
static func entity_frames(id: String, anim: String = "idle") -> Array[Texture2D]:
	var fr: Array[Texture2D] = SpriteLib.anim_frames_any(id, anim, "south")
	if fr.is_empty() and anim != "idle":
		fr = SpriteLib.anim_frames_any(id, "idle", "south")
	if fr.is_empty():
		var t: Texture2D = SpriteLib.dir_tex(id, "south", 48)
		if t != null:
			fr = [t]
	return fr


## 백 외곽선(풀릴 기색 모습)을 입힌 사본 — 열 때 한 번.
static func outlined(tex: Texture2D, col: Color) -> Texture2D:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return tex
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var out: Image = Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(1, 1))
	var src: Image = out.duplicate() as Image
	for y in h + 2:
		for x in w + 2:
			if src.get_pixel(x, y).a >= 0.5:
				continue
			var hit: bool = false
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < w + 2 and q.y < h + 2 and src.get_pixel(q.x, q.y).a >= 0.5:
					hit = true
					break
			if hit:
				out.set_pixel(x, y, col)
	return ImageTexture.create_from_image(out)
