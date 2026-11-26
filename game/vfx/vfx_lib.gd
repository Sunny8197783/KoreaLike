class_name VfxLib
## 스프라이트시트 이펙트 로더(pixelfx / Aseprite JSON) + 누락 시 절차적 플레이스홀더. 소유: vfx.
## 규약: res://assets/vfx/<fx_id>.png + <fx_id>.json
## JSON 형식(pixelfx tools/render.mjs --sheet 출력 = Aseprite "Array" 형식):
##   { "frames": [ {"frame": {x,y,w,h}, "duration": ms, ...}, ... ]   (또는 Aseprite "Hash": {"name": {...}})
##     "meta": { "pixelfx": { "fps": 12, "loop": false, "frames": n, "frameSize": [w,h], "pivot": [x,y], "columns": c },
##               "korealike": { "impact_frame": i, "impact_hold": 2.0, "blend": "add" } } }
## 반환 Dictionary(읽기 전용 — 캐시 공유):
##   texture, regions: Array[Rect2], fps, loop, pivot: Vector2, size: Vector2, placeholder: bool   (기존 계약)
##   durations: PackedFloat32Array(초, 프레임별)  t_end: PackedFloat32Array(누적 끝 시각)  total: float  uniform: bool
##   impact_frame: int(-1 없음)
##   blend: &"normal" | &"add" | &"multiply"   beat_snap: bool   max_concurrent: int(0 = 목록 없음)   layer: int(L 번호, 10 기본)
## blend·beat_snap·max_concurrent·layer 의 원본은 data/art_vfx_list.json(13장 §6). 변주 ID(vfx_x_<신령>, vfx_x__pilot)는
## 뒤 토막을 떼어 가며 기본 ID 의 항목을 물려받는다. VfxPlayer 가 이 값을 자동 적용한다.
## 직접 그리는 모듈은 frame_at(fx, t) 로 프레임을 고르면 프레임별 duration(판정 프레임 홀드)을 그대로 따른다.

const VFX_ROOT: String = "res://assets/vfx"
const LIST_KEY: StringName = &"__art_vfx_list_index"


## art_vfx_list.json → {fx_id: [blend, beat_snap, max_concurrent, layer]} (AssetCache 에 1회 색인).
static func _list_index() -> Dictionary:
	if AssetCache.fx.has(LIST_KEY):
		return AssetCache.fx[LIST_KEY]
	var idx: Dictionary = {}
	var d: Variant = Data.table("art_vfx_list")
	if d is Dictionary:
		var keys: Array = d.get("tuple", [])
		var ib: int = keys.find("blend")
		var is_: int = keys.find("beat_snap")
		var im: int = keys.find("max_concurrent")
		var il: int = keys.find("layer")
		for row: Variant in d.get("vfx", []):
			if not (row is Array) or row.size() <= maxi(maxi(ib, is_), maxi(im, il)) or ib < 0 or is_ < 0 or im < 0 or il < 0:
				continue
			idx[StringName(String(row[0]))] = [StringName(String(row[ib])), bool(row[is_]), int(row[im]),
				int(String(row[il]).trim_prefix("L"))]
	AssetCache.fx[LIST_KEY] = idx
	return idx


## 목록 항목(없으면 빈 배열). 변주 ID 는 "__pilot" → 끝 "_토막" 순으로 떼어 가며 찾는다.
static func list_entry(fx_id: StringName) -> Array:
	var idx: Dictionary = _list_index()
	if idx.has(fx_id):
		return idx[fx_id]
	var s: String = String(fx_id)
	var cut: int = s.find("__")
	if cut > 0:
		s = s.substr(0, cut)
		if idx.has(StringName(s)):
			return idx[StringName(s)]
	for n in 3:
		cut = s.rfind("_")
		if cut <= 4:
			break
		s = s.substr(0, cut)
		if idx.has(StringName(s)):
			return idx[StringName(s)]
	return []


## 재생 시각 t(초) → 프레임 번호. 반복 시트는 감아 돌고, 원샷은 끝나면 -1.
static func frame_at(fx: Dictionary, t: float) -> int:
	var n: int = (fx["regions"] as Array).size()
	if n <= 0:
		return -1
	var total: float = fx["total"]
	if t >= total:
		if not bool(fx["loop"]) or total <= 0.0:
			return -1
		t = fmod(t, total)
	if bool(fx["uniform"]):
		return mini(n - 1, int(t * float(fx["fps"])))
	var te: PackedFloat32Array = fx["t_end"]
	for i in n:
		if t < te[i]:
			return i
	return n - 1


static func get_fx(fx_id: StringName) -> Dictionary:
	if AssetCache.fx.has(fx_id):
		return AssetCache.fx[fx_id]
	var fx: Dictionary = _load_sheet(String(fx_id))
	if fx.is_empty():
		fx = _placeholder(String(fx_id))
	_finish(fx_id, fx)
	AssetCache.fx[fx_id] = fx
	return fx


## 목록 메타(blend·beat_snap·max_concurrent·layer)와 누적 시각을 채운다.
static func _finish(fx_id: StringName, fx: Dictionary) -> void:
	var n: int = (fx["regions"] as Array).size()
	var fps: float = maxf(float(fx["fps"]), 0.001)
	var dur: PackedFloat32Array = fx.get("durations", PackedFloat32Array())
	if dur.size() != n:
		dur.resize(n)
		dur.fill(1.0 / fps)
	var te: PackedFloat32Array = PackedFloat32Array()
	te.resize(n)
	var acc: float = 0.0
	var uniform: bool = true
	for i in n:
		if absf(dur[i] - dur[0]) > 0.0005:
			uniform = false
		acc += dur[i]
		te[i] = acc
	if uniform and n > 0:
		acc = float(n) / fps
	fx["durations"] = dur
	fx["t_end"] = te
	fx["total"] = acc
	fx["uniform"] = uniform
	if not fx.has("impact_frame"):
		fx["impact_frame"] = -1
	var e: Array = list_entry(fx_id)
	var blend: StringName = fx.get("blend", &"")
	if blend == &"":
		blend = e[0] if e.size() >= 4 else &"normal"
	fx["blend"] = blend
	fx["beat_snap"] = bool(e[1]) if e.size() >= 4 else false
	fx["max_concurrent"] = int(e[2]) if e.size() >= 4 else 0
	fx["layer"] = int(e[3]) if e.size() >= 4 else 10


static func _load_sheet(fx_id: String) -> Dictionary:
	# 정식 경로 res://assets/vfx/<fx_id>. 옛 "<id>__pilot" ID 는 정식 <id> 시트가 있으면 그것으로(G1 승격, 2026-11-22),
	# 없을 때만 파일럿 보관본 res://assets/pilot/<fx_id>/ 을 읽는다(호환). --pilot-legacy 는 파일럿 보관본을 우선(전후 비교).
	var json_path: String = "%s/%s.json" % [VFX_ROOT, fx_id]
	var png_path: String = "%s/%s.png" % [VFX_ROOT, fx_id]
	var cut: int = fx_id.find("__pilot")
	if cut > 0:
		var base: String = fx_id.substr(0, cut)
		var pj: String = "%s/%s/%s.json" % [SpriteLib.PILOT_ROOT, fx_id, fx_id]
		var fj: String = "%s/%s.json" % [VFX_ROOT, base]
		if FileAccess.file_exists(fj) and not (SpriteLib.pilot_legacy() and FileAccess.file_exists(pj)):
			json_path = fj
			png_path = "%s/%s.png" % [VFX_ROOT, base]
		elif FileAccess.file_exists(pj):
			json_path = pj
			png_path = "%s/%s/%s.png" % [SpriteLib.PILOT_ROOT, fx_id, fx_id]
	if not FileAccess.file_exists(json_path):
		return {}
	var tex: Texture2D = SpriteLib.tex(png_path)
	if tex == null:
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not (parsed is Dictionary):
		push_warning("[VfxLib] JSON 오류: " + json_path)
		return {}
	return parse_aseprite(parsed, tex)


## Aseprite/pixelfx JSON → fx 사전. 테스트에서 직접 호출 가능.
static func parse_aseprite(d: Dictionary, tex: Texture2D) -> Dictionary:
	var regions: Array[Rect2] = []
	var durations: PackedFloat32Array = PackedFloat32Array()
	var frames: Variant = d.get("frames", [])
	var list: Array = []
	if frames is Array:
		list = frames
	elif frames is Dictionary:
		var keys: Array = frames.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a).naturalnocasecmp_to(String(b)) < 0)
		for k: Variant in keys:
			list.append(frames[k])
	for f: Variant in list:
		if not (f is Dictionary):
			continue
		var r: Dictionary = f.get("frame", {})
		regions.append(Rect2(float(r.get("x", 0)), float(r.get("y", 0)), float(r.get("w", 0)), float(r.get("h", 0))))
		durations.append(float(f.get("duration", 83)))
	var meta: Dictionary = d.get("meta", {})
	var pfx: Dictionary = meta.get("pixelfx", {})
	var fps: float = float(pfx.get("fps", 0.0))
	if fps <= 0.0 and durations.size() > 0:
		fps = 1000.0 / maxf(durations[0], 1.0)
	if fps <= 0.0:
		fps = 12.0
	var size: Vector2 = regions[0].size if regions.size() > 0 else Vector2(32, 32)
	var pivot: Vector2 = size * 0.5
	var pv: Variant = pfx.get("pivot", null)
	if pv is Array and pv.size() >= 2:
		pivot = Vector2(float(pv[0]), float(pv[1]))
	elif pv is Dictionary:
		pivot = Vector2(float(pv.get("x", pivot.x)), float(pv.get("y", pivot.y)))
	var out: Dictionary = {"texture": tex, "regions": regions, "fps": fps, "loop": bool(pfx.get("loop", false)),
		"pivot": pivot, "size": size, "placeholder": false}
	# 프레임별 duration(ms → 초). 시트가 fps 로만 지정됐고 duration 이 전부 같으면 fps 가 정본(B15).
	var kl: Dictionary = meta.get("korealike", {})
	var imp: int = int(kl.get("impact_frame", pfx.get("impact_frame", -1)))
	var hold: float = float(kl.get("impact_hold", 1.0))
	var dur: PackedFloat32Array = PackedFloat32Array()
	dur.resize(regions.size())
	var vary: bool = false
	for i in regions.size():
		if absf(durations[i] - durations[0]) > 1.0:
			vary = true
	for i in regions.size():
		dur[i] = (durations[i] / 1000.0) if vary else (1.0 / fps)
		if i == imp and hold > 1.0:
			dur[i] *= hold                      # 판정 프레임 홀드(ART_STYLE 4.1 — 시트가 명시할 때만)
	out["durations"] = dur
	out["impact_frame"] = imp if imp < regions.size() else -1
	var bl: String = String(kl.get("blend_override", ""))
	if bl != "":
		out["blend"] = StringName(bl)
	return out


## 절차적 플레이스홀더: ID 로 색·모양 추정. 퇴치(toechi/burst/hit) = 적 방사형 파열, 해원(haewon/cheondo) = 백 상승 빛줄기,
## 그 외 = 한지 고리. 6프레임 32×32.
static func _placeholder(fx_id: String) -> Dictionary:
	var n: int = 6
	var s: int = 32
	var img: Image = Image.create(s * n, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mode: int = 2
	var col: Color = K.COL_HANJI
	if fx_id.contains("toechi") or fx_id.contains("burst") or fx_id.contains("hit") or fx_id.contains("hanpa"):
		mode = 0
		col = K.COL_JEOK_HI
	elif fx_id.contains("haewon") or fx_id.contains("cheondo") or fx_id.contains("pullil"):
		mode = 1
		col = K.COL_BAEK
	var c: float = s * 0.5
	for f in n:
		var prog: float = float(f + 1) / float(n)
		var fade: float = 1.0 - float(f) / float(n)
		for y in s:
			for x in s:
				var dx: float = x + 0.5 - c
				var dy: float = y + 0.5 - c
				var d: float = sqrt(dx * dx + dy * dy)
				var a: float = 0.0
				match mode:
					0:
						var ang: float = atan2(dy, dx)
						var spike: float = absf(sin(ang * 4.0 + float(fx_id.hash() % 7)))
						var r: float = prog * c * (0.6 + 0.4 * spike)
						a = 1.0 if (d <= r and d >= r - 2.5) or (f < 2 and d < 4.0 * (2 - f)) else 0.0
					1:
						var colw: float = 3.0 + 3.0 * (1.0 - prog)
						a = 1.0 if absf(dx) < colw and y < s * (1.0 - prog * 0.5) and y > s * (0.6 - prog * 0.6) else 0.0
						if absf(dx) < colw * 0.4:
							a = 1.0
					_:
						var rr: float = prog * c * 0.9
						a = 1.0 if absf(d - rr) < 1.2 else 0.0
				if a > 0.0:
					img.set_pixel(f * s + x, y, Color(col, fade))
	var regions: Array[Rect2] = []
	for f in n:
		regions.append(Rect2(f * s, 0, s, s))
	var pivot: Vector2 = Vector2(c, s * 0.8 if mode == 1 else c)
	return {"texture": ImageTexture.create_from_image(img), "regions": regions, "fps": 18.0, "loop": false,
		"pivot": pivot, "size": Vector2(s, s), "placeholder": true}


static func clear_cache() -> void:
	AssetCache.fx.clear()
