class_name SpriteLib
## 스프라이트 로딩 + 누락 에셋 자동 플레이스홀더. 소유: core(리드).
## 규약: res://assets/sprites/<entity_id>/{south,east,north,west}.png, walk_<dir>_<n>.png, <anim>_<dir>_<n>.png
## 색인은 res://assets/sprites/manifest.json (tools/sync_art.py 생성). 런타임 디렉터리 나열에 의존하지 않는다.

const SPRITE_ROOT: String = "res://assets/sprites"
const MANIFEST_PATH: String = "res://assets/sprites/manifest.json"
## 정식 규약(ART_STYLE v1, G1_pilot_promote 2026-11-22): res://assets/sprites/<id>/anims.json 이 있으면 새 규격 엔티티.
##   anims.json {spec:"art_style_v1", canvas:[w,h], pivot:[x,y], body_h, anims:{<anim>:{<dir>:n}}, atlas_cols?:{<anim>:[파일 번호…]}}
##   → 피벗·캔버스를 anims.json 에서 읽고 리사이즈 없이 캔버스 하단 중앙 기준 패딩만 한다.
##   없으면 구 규격(legacy): data/anchors/<id>.json → 실측 발끝(measured_pivot). G2~G5 교체 동안 공존.
## PILOT_ROOT 는 파일럿 원본 보관 위치(tests/pilot_scene 전후 비교·VfxLib 옛 __pilot ID 호환용). 기본 스프라이트 경로는 보지 않는다.
const PILOT_ROOT: String = "res://assets/pilot"
## --pilot-legacy(전후 비교): 교체 전 런타임 사본(art/_legacy_runtime/<id>/, res:// 밖 → 원시 PNG 로드). 익스포트 빌드에는 없다.
const LEGACY_REL: String = "../art/_legacy_runtime"
const ANCHOR_ROOT: String = "res://data/anchors"
const SPEC_FILE: String = "anims.json"
## 2D 아틀라스 셀 여백(스쿼시·기울기 시프트가 잘리지 않게, GAME_FEEL 1.5 콘텐츠 여백 조건).
const CELL_PAD: int = 3
const ATLAS_DIRS: PackedStringArray = ["south", "east", "north"]

# 캐시는 오토로드 AssetCache 에 둔다(static var 누수 회피).


static func manifest() -> Dictionary:
	if not AssetCache.manifest_loaded:
		AssetCache.manifest_loaded = true
		if FileAccess.file_exists(MANIFEST_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
			if parsed is Dictionary:
				AssetCache.manifest = parsed
	return AssetCache.manifest


static func has_entity(entity_id: String) -> bool:
	var ents: Dictionary = manifest().get("entities", {})
	return ents.has(entity_id)


## 경로의 텍스처. 임포트된 리소스 → 원시 PNG(개발용 폴백) → null 순.
static func tex(path: String) -> Texture2D:
	if AssetCache.tex.has(path):
		return AssetCache.tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	AssetCache.tex[path] = t
	return t


## 엔티티 정지 방향 텍스처(누락 시 플레이스홀더).
static func dir_tex(entity_id: String, dir: String, fallback_px: int = 32) -> Texture2D:
	var root: String = _frames_root(entity_id)
	var t: Texture2D = tex("%s/%s.png" % [root, dir])
	if t == null and dir != "south":
		t = tex("%s/south.png" % root)
	if t == null:
		t = placeholder(entity_id, fallback_px)
	return t


## 애니메이션 프레임(누락 시 빈 배열).
static func anim_frames(entity_id: String, anim: String, dir: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var ents: Dictionary = manifest().get("entities", {})
	var n: int = 0
	if ents.has(entity_id):
		var anims: Dictionary = ents[entity_id].get("anims", {})
		if anims.has(anim):
			n = int(anims[anim].get(dir, 0))
	if n == 0:
		n = 64  # 색인에 없으면(다른 담당이 방금 넣은 파일) 0번부터 끊길 때까지 탐색
	for i in n:
		var t: Texture2D = tex("%s/%s/%s_%s_%d.png" % [SPRITE_ROOT, entity_id, anim, dir, i])
		if t == null:
			break
		out.append(t)
	return out


## 4방향 가로 아틀라스(south,east,north,west). MultiMesh 인스턴스 셰이더용.
## 반환: {texture: Texture2D, frame_w: int, frame_h: int, frames: int, placeholder: bool}
static func dir_atlas(entity_id: String, fallback_px: int = 32) -> Dictionary:
	if AssetCache.atlas.has(entity_id):
		return AssetCache.atlas[entity_id]
	var imgs: Array[Image] = []
	var is_ph: bool = not has_entity(entity_id)
	for d in K.DIRS:
		var t: Texture2D = dir_tex(entity_id, d, fallback_px)
		var img: Image = t.get_image()
		if img == null:
			img = Image.create(fallback_px, fallback_px, false, Image.FORMAT_RGBA8)
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		imgs.append(img)
	# 리사이즈 금지(ART_STYLE): 크기가 다른 방향 그림은 가장 큰 칸에 하단 중앙 기준 패딩만 한다.
	var fw: int = 0
	var fh: int = 0
	for im: Image in imgs:
		fw = maxi(fw, im.get_width())
		fh = maxi(fh, im.get_height())
	var atlas: Image = Image.create(fw * 4, fh, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for i in 4:
		var src: Image = imgs[i]
		var ox: int = (fw - src.get_width()) / 2
		var oy: int = fh - src.get_height()
		atlas.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(i * fw + ox, oy))
	var res: Dictionary = {
		"texture": ImageTexture.create_from_image(atlas),
		"frame_w": fw, "frame_h": fh, "frames": 4, "placeholder": is_ph,
	}
	AssetCache.atlas[entity_id] = res
	return res


## 결정론적 플레이스홀더: 먹 바탕 귀신 실루엣(소복 몸 + 눈 2점 + 1px 흑 외곽선). 색은 ID 해시.
static func placeholder(key: String, size_px: int = 32) -> Texture2D:
	var ck: String = "ph:%s:%d" % [key, size_px]
	if AssetCache.tex.has(ck):
		return AssetCache.tex[ck]
	var s: int = clampi(size_px, 8, 256)
	var img: Image = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var h: int = absi(hash(key))
	var body: Color = Color.from_hsv(float(h % 360) / 360.0, 0.18, 0.55)
	if key.begins_with("char_"):
		body = K.COL_JEOK_DK
	elif key.begins_with("elite_") or key.begins_with("mboss_") or key.begins_with("boss_"):
		body = Color.from_hsv(float(h % 360) / 360.0, 0.35, 0.45)
	var cx: float = s * 0.5
	var r: float = s * 0.34
	for y in s:
		for x in s:
			var dx: float = (x + 0.5 - cx) / r
			var dy: float = (y + 0.5 - s * 0.42) / r
			var inside_head: bool = dx * dx + dy * dy <= 1.0
			var inside_robe: bool = y >= int(s * 0.42) and y < int(s * 0.92) and absf(x + 0.5 - cx) <= r * (0.8 + 0.5 * float(y - s * 0.42) / float(s * 0.5))
			if inside_head or inside_robe:
				img.set_pixel(x, y, body)
	# 외곽선
	var out: Image = img.duplicate()
	for y in s:
		for x in s:
			if img.get_pixel(x, y).a > 0.5:
				continue
			var near: bool = false
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and ny >= 0 and nx < s and ny < s and img.get_pixel(nx, ny).a > 0.5:
					near = true
					break
			if near:
				out.set_pixel(x, y, K.COL_HEUK)
	# 눈
	var ey: int = int(s * 0.40)
	var ex: int = maxi(1, int(r * 0.4))
	var eye: Color = K.COL_HEUK
	out.set_pixel(int(cx) - ex, ey, eye)
	out.set_pixel(int(cx) + ex - 1, ey, eye)
	var t: Texture2D = ImageTexture.create_from_image(out)
	AssetCache.tex[ck] = t
	return t


## 단색 원(파티클·투사체·픽업 플레이스홀더).
static func dot(size_px: int, color: Color, soft: bool = false) -> Texture2D:
	var ck: String = "dot:%d:%s:%s" % [size_px, color.to_html(), soft]
	if AssetCache.tex.has(ck):
		return AssetCache.tex[ck]
	var s: int = maxi(2, size_px)
	var img: Image = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c: float = (s - 1) * 0.5
	for y in s:
		for x in s:
			var d: float = Vector2(x - c, y - c).length() / maxf(c, 0.5)
			if d <= 1.0:
				var col: Color = color
				if soft:
					col.a *= clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, col)
	var t: Texture2D = ImageTexture.create_from_image(img)
	AssetCache.tex[ck] = t
	return t


# ─── 2D 애니 아틀라스 (GAME_FEEL 1.5 / 4.1, ART_STYLE 1.3·4.4) ─────────────

## 명령행 --pilot-legacy: 교체 전 런타임 사본(art/_legacy_runtime)으로 같은 장면을 그린다(전후 비교 렌더용, tests/pilot_scene). 결과는 캐시.
static func pilot_legacy() -> bool:
	var ck: String = "pilot_legacy"
	if AssetCache.atlas.has(ck):
		return AssetCache.atlas[ck]
	var on: bool = "--pilot-legacy" in OS.get_cmdline_args() or "--pilot-legacy" in OS.get_cmdline_user_args()
	AssetCache.atlas[ck] = on
	return on


## --pilot-legacy 이고 백업 폴더가 있으면 그 절대 경로, 아니면 "".
static func legacy_dir(entity_id: String) -> String:
	var ck: String = "legacy_dir:" + entity_id
	if AssetCache.atlas.has(ck):
		return AssetCache.atlas[ck]
	var found: String = ""
	if pilot_legacy():
		var d: String = ProjectSettings.globalize_path("res://").path_join(LEGACY_REL).path_join(entity_id).simplify_path()
		if DirAccess.dir_exists_absolute(d):
			found = d
	AssetCache.atlas[ck] = found
	return found


## 엔티티 프레임 폴더(기본 res://assets/sprites/<id>, --pilot-legacy 면 백업 폴더 우선).
static func _frames_root(entity_id: String) -> String:
	var ld: String = legacy_dir(entity_id)
	return ld if ld != "" else "%s/%s" % [SPRITE_ROOT, entity_id]


## 새 규격(ART_STYLE v1) 메타 = res://assets/sprites/<id>/anims.json. 없으면(또는 --pilot-legacy 로 백업을 볼 때) {}.
static func spec_meta(entity_id: String) -> Dictionary:
	var ck: String = "spec_meta:" + entity_id
	if AssetCache.atlas.has(ck):
		return AssetCache.atlas[ck]
	var out: Dictionary = {}
	var p: String = "%s/%s/%s" % [SPRITE_ROOT, entity_id, SPEC_FILE]
	if legacy_dir(entity_id) == "" and FileAccess.file_exists(p):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary and _vec2i((parsed as Dictionary).get("canvas", (parsed as Dictionary).get("size", null))) != null:
			out = parsed
	AssetCache.atlas[ck] = out
	return out


static func is_spec(entity_id: String) -> bool:
	return not spec_meta(entity_id).is_empty()


static func _frame_path(dir_path: String, anim: String, d: String, n: int) -> String:
	return "%s/%s_%s_%d.png" % [dir_path, anim, d, n]


static func _frame_exists(dir_path: String, anim: String, d: String, n: int) -> bool:
	var p: String = _frame_path(dir_path, anim, d, n)
	return ResourceLoader.exists(p) or FileAccess.file_exists(p)


## 한 방향 프레임 텍스처. 새 규격은 anims.json 프레임 수, 구 규격은 manifest(anim_frames). 없으면 빈 배열.
## west 는 요청하지 않는다(east 반전 사용).
static func anim_frames_any(entity_id: String, anim: String, d: String) -> Array[Texture2D]:
	var ld: String = legacy_dir(entity_id)
	var sm: Dictionary = spec_meta(entity_id)
	if ld == "" and sm.is_empty():
		return anim_frames(entity_id, anim, d)
	var root: String = ld if ld != "" else "%s/%s" % [SPRITE_ROOT, entity_id]
	var n: int = 64
	if not sm.is_empty():
		var an: Variant = sm.get("anims", {})
		n = 0
		if an is Dictionary and (an as Dictionary).get(anim) is Dictionary:
			n = int(((an as Dictionary)[anim] as Dictionary).get(d, 0))
	var out: Array[Texture2D] = []
	for i in n:
		if not _frame_exists(root, anim, d, i):
			break
		var t: Texture2D = tex(_frame_path(root, anim, d, i))
		if t == null:
			break
		out.append(t)
	return out


## 앵커 메타. 새 규격 = anims.json, 구 규격 = data/anchors/<id>.json(엔티티 키로 감싼 형식도 허용).
## {pivot?:Vector2i, canvas?:Vector2i, body_h?, body_w?, hinge_y?, foot_from_bottom?}
static func anchor_meta(entity_id: String) -> Dictionary:
	var ck: String = "anchor_meta:" + entity_id
	if AssetCache.atlas.has(ck):
		return AssetCache.atlas[ck]
	var out: Dictionary = {}
	var sm: Dictionary = spec_meta(entity_id)
	if not sm.is_empty():
		_merge_anchor(out, sm)
	elif legacy_dir(entity_id) == "":
		var p: String = "%s/%s.json" % [ANCHOR_ROOT, entity_id]
		if FileAccess.file_exists(p):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
			if parsed is Dictionary:
				var d: Dictionary = parsed
				if d.get(entity_id) is Dictionary:
					d = d[entity_id]
				_merge_anchor(out, d)
	AssetCache.atlas[ck] = out
	return out


static func _vec2i(v: Variant) -> Variant:
	if v is Array and v.size() >= 2 and (v[0] is float or v[0] is int):
		return Vector2i(int(v[0]), int(v[1]))
	if v is Dictionary and v.has("x") and v.has("y"):
		return Vector2i(int(v["x"]), int(v["y"]))
	return null


static func _merge_anchor(out: Dictionary, d: Dictionary) -> void:
	for k: String in ["pivot", "foot", "anchor", "feet", "foot_anchor"]:
		var v: Variant = d.get(k)
		if v is Dictionary and (v as Dictionary).has("foot"):
			v = v["foot"]
		var p: Variant = _vec2i(v)
		if p != null:
			out["pivot"] = p
			break
		if (v is float or v is int) and k != "pivot":
			out["foot_from_bottom"] = int(v)
	for k: String in ["foot_from_bottom", "anchor_from_bottom", "pivot_from_bottom", "foot_offset_bottom", "bottom_offset"]:
		var b: Variant = d.get(k)
		if b is float or b is int:
			out["foot_from_bottom"] = int(b)
	for k: String in ["body_h", "body_w", "hinge_y"]:
		var b2: Variant = d.get(k)
		if b2 is float or b2 is int:
			out[k] = int(b2)
	var sz: Variant = _vec2i(d.get("canvas", d.get("size", null)))
	if sz != null:
		out["canvas"] = sz


## ART_STYLE 1.3 등급 기본 피벗(캔버스 크기로 추정).
static func default_pivot(w: int, h: int) -> Vector2i:
	match h:
		64:
			return Vector2i(w / 2, 58)
		32:
			return Vector2i(w / 2, 29)
		40:
			return Vector2i(w / 2, 36)
		48:
			return Vector2i(w / 2, 44)
		128:
			return Vector2i(w / 2, 118)
		192:
			return Vector2i(w / 2, 178)
		256:
			return Vector2i(w / 2, 240)
	return Vector2i(w / 2, h - 8 if h >= 80 else h - maxi(3, h / 10))


static func _img_of(t: Texture2D) -> Image:
	if t == null:
		return null
	var img: Image = t.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## 불투명 영역(알파 ≥ 0.5) 경계. 비면 size 0.
static func _opaque_rect(img: Image) -> Rect2i:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var x0: int = w
	var y0: int = h
	var x1: int = -1
	var y1: int = -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a >= 0.5:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## [S,E,N 행 × 프레임 열] 2D 아틀라스. anims 는 후보 애니 이름(앞에서부터 프레임이 있는 첫 애니 사용).
## 모든 애니가 없으면 정지 방향 그림 1열, 그것도 없으면 플레이스홀더. 크기가 다른 프레임은 하단 중앙 기준 패딩만 한다(리사이즈 금지).
## 반환: {texture, cell: Vector2i, cols, rows(3), counts: PackedInt32Array, pivot: Vector2i(셀 좌표, 여백 포함),
##        canvas: Vector2i, body_h, body_w, hinge_y·top_y(셀 좌표), bob(그림에 상하 운동 있음), anim, pilot, placeholder}
static func anim_atlas(entity_id: String, anims: PackedStringArray, fallback_px: int = 32) -> Dictionary:
	var ck: String = "anim_atlas:%s:%s" % [entity_id, ",".join(anims)]
	if AssetCache.atlas.has(ck):
		return AssetCache.atlas[ck]
	var rows: Array = []
	var used_anim: String = ""
	for a: String in anims:
		var any: bool = false
		var tmp: Array = []
		for d: String in ATLAS_DIRS:
			var imgs: Array = []
			for t: Texture2D in anim_frames_any(entity_id, a, d):
				var im: Image = _img_of(t)
				if im != null:
					imgs.append(im)
			tmp.append(imgs)
			if not imgs.is_empty():
				any = true
		if any:
			rows = tmp
			used_anim = a
			break
	var sm: Dictionary = spec_meta(entity_id)
	var spec: bool = not sm.is_empty()
	# 새 규격 atlas_cols: 아틀라스 열 → 파일 번호 표(구 인덱스 체계 호환, 예: hurt 2f 를 6f 인덱스 [1,3] 으로 고르는 player.gd)
	if spec and used_anim != "":
		var ac: Variant = sm.get("atlas_cols", {})
		if ac is Dictionary and (ac as Dictionary).get(used_anim) is Array:
			var cmap: Array = (ac as Dictionary)[used_anim]
			for r0i in 3:
				var src_row: Array = rows[r0i]
				if src_row.is_empty():
					continue
				var mapped: Array = []
				for ci: Variant in cmap:
					mapped.append(src_row[clampi(int(ci), 0, src_row.size() - 1)])
				rows[r0i] = mapped
	var is_ph: bool = false
	if used_anim == "":
		rows = []
		for d: String in ATLAS_DIRS:
			var imgs2: Array = []
			var im2: Image = _img_of(tex("%s/%s.png" % [_frames_root(entity_id), d]))
			if im2 != null:
				imgs2.append(im2)
			rows.append(imgs2)
		if (rows[0] as Array).is_empty() and (rows[1] as Array).is_empty() and (rows[2] as Array).is_empty():
			is_ph = true
			rows[0] = [_img_of(placeholder(entity_id, fallback_px))]
	var base_row: int = 0
	for r in 3:
		if not (rows[r] as Array).is_empty():
			base_row = r
			break
	for r in 3:
		if (rows[r] as Array).is_empty():
			rows[r] = rows[0] if not (rows[0] as Array).is_empty() else rows[base_row]
	var cw: int = 0
	var chh: int = 0
	var cols: int = 1
	var counts: PackedInt32Array = PackedInt32Array([1, 1, 1])
	for r in 3:
		var arr: Array = rows[r]
		counts[r] = arr.size()
		cols = maxi(cols, arr.size())
		for im3: Image in arr:
			cw = maxi(cw, im3.get_width())
			chh = maxi(chh, im3.get_height())
	var meta: Dictionary = anchor_meta(entity_id)
	var pivot: Vector2i
	if spec:
		# 새 규격: 캔버스·피벗은 anims.json 이 정본(프레임은 리사이즈 없이 이 캔버스에 하단 중앙 패딩)
		var cv: Vector2i = meta.get("canvas", Vector2i(cw, chh))
		if cw > cv.x or chh > cv.y:
			push_warning("[SpriteLib] %s: 프레임 %dx%d 가 anims.json 캔버스 %s 보다 큼(그대로 둠)" % [entity_id, cw, chh, str(cv)])
		cw = maxi(cw, cv.x)
		chh = maxi(chh, cv.y)
		pivot = meta.get("pivot", default_pivot(cw, chh))
	elif meta.has("pivot"):
		pivot = meta["pivot"]
	elif meta.has("foot_from_bottom"):
		pivot = Vector2i(cw / 2, chh - int(meta["foot_from_bottom"]))
	else:
		pivot = measured_pivot(entity_id, cw, chh)
	var pad: int = CELL_PAD
	var cell: Vector2i = Vector2i(cw + pad * 2, chh + pad * 2)
	var atlas: Image = Image.create(cell.x * cols, cell.y * 3, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var tops: PackedInt32Array = PackedInt32Array()
	for r in 3:
		var arr2: Array = rows[r]
		for c in cols:
			var im4: Image = arr2[c % arr2.size()]
			var ox: int = (cw - im4.get_width()) / 2
			var oy: int = chh - im4.get_height()
			atlas.blit_rect(im4, Rect2i(0, 0, im4.get_width(), im4.get_height()), Vector2i(c * cell.x + pad + ox, r * cell.y + pad + oy))
			if r == 0 and c < arr2.size():
				var orc: Rect2i = _opaque_rect(im4)
				if orc.size.y > 0:
					tops.append(orc.position.y + oy)
	var body_h: int = int(meta.get("body_h", 0))
	var body_w: int = int(meta.get("body_w", 0))
	var top_y: int = 0
	var src0: Image = (rows[0] as Array)[0]
	var r0: Rect2i = _opaque_rect(src0)
	if r0.size.y > 0:
		top_y = r0.position.y + (chh - src0.get_height())
		if body_h <= 0:
			body_h = pivot.y - top_y + 1
		if body_w <= 0:
			body_w = r0.size.x
	if body_h <= 0:
		body_h = int(chh * 0.7)
	if body_w <= 0:
		body_w = int(cw * 0.5)
	var hinge: int = int(meta.get("hinge_y", pivot.y - int(K.rnd(0.45 * body_h))))
	var bob: bool = false
	if tops.size() >= 2:
		var mn: int = tops[0]
		var mx: int = tops[0]
		for t2: int in tops:
			mn = mini(mn, t2)
			mx = maxi(mx, t2)
		bob = mx - mn >= 1
	var res: Dictionary = {
		"texture": ImageTexture.create_from_image(atlas), "cell": cell, "cols": cols, "rows": 3, "counts": counts,
		"pivot": pivot + Vector2i(pad, pad), "canvas": Vector2i(cw, chh), "body_h": body_h, "body_w": body_w,
		"hinge_y": hinge + pad, "top_y": top_y + pad, "bob": bob, "anim": used_anim, "spec": spec,
		"pilot": spec, "placeholder": is_ph,   # "pilot" = 구 키(tests/pilot_scene 로그 호환) — spec 과 같다
	}
	AssetCache.atlas[ck] = res
	return res


## 구 규격(assets/sprites) 엔티티의 발 피벗: idle/walk/move 0프레임과 정지 그림 S/E/N 의 최저 불투명 행 중 최댓값, x = 캔버스 중앙.
## (구 에셋은 발끝이 58이 아니라 61~62 등 제각각이라 등급 기본값을 쓰면 발이 그림자 아래로 빠진다.)
static func measured_pivot(entity_id: String, cw: int, chh: int) -> Vector2i:
	var ck: String = "measured_pivot:%s:%d:%d" % [entity_id, cw, chh]
	if AssetCache.atlas.has(ck):
		return AssetCache.atlas[ck]
	var bottom: int = -1
	for a: String in ["idle", "walk", "move"]:
		for d: String in ATLAS_DIRS:
			var fr: Array[Texture2D] = anim_frames_any(entity_id, a, d)
			if fr.is_empty():
				continue
			var im: Image = _img_of(fr[0])
			if im == null:
				continue
			var rc: Rect2i = _opaque_rect(im)
			if rc.size.y > 0:
				bottom = maxi(bottom, rc.end.y - 1 + (chh - im.get_height()))
	if bottom < 0:
		for d: String in ATLAS_DIRS:
			var im2: Image = _img_of(tex("%s/%s.png" % [_frames_root(entity_id), d]))
			if im2 == null:
				continue
			var rc2: Rect2i = _opaque_rect(im2)
			if rc2.size.y > 0:
				bottom = maxi(bottom, rc2.end.y - 1 + (chh - im2.get_height()))
	var p: Vector2i = Vector2i(cw / 2, bottom) if bottom >= 0 else default_pivot(cw, chh)
	AssetCache.atlas[ck] = p
	return p


## 픽셀 타원 그림자(무외곽선, 먹 #0e0b16 불투명). 반투명은 그리는 쪽 modulate(GAME_FEEL 2.3).
static func shadow_tex(w: int, h: int) -> Texture2D:
	var ck: String = "shadow:%d:%d" % [w, h]
	if AssetCache.tex.has(ck):
		return AssetCache.tex[ck]
	var img: Image = Image.create(maxi(2, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rx: float = w * 0.5
	var ry: float = h * 0.5
	for y in h:
		for x in w:
			var dx: float = (x + 0.5 - rx) / rx
			var dy: float = (y + 0.5 - ry) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, K.COL_MEOK)
	var t: Texture2D = ImageTexture.create_from_image(img)
	AssetCache.tex[ck] = t
	return t


static func clear_cache() -> void:
	AssetCache.clear()
