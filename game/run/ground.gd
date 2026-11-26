class_name Ground
extends Node2D
## 임시 지면: PixelLab Wang 코너 타일셋(assets/tilesets/<id>.png + .metadata.json, 32px 16타일)을
## 격자 코너 노이즈로 이어 붙인다(이음새 없음). 소유: waves(지도·청크 담당).
## TODO(waves): TileMapLayer + 청크(waves_stage1.map: chunk_size 24, ground_noise, trail_path, 장애물, 성곽, 성황당).

const TILE: int = 32
const TILESET: String = "stage1_earth_grass"

var _tex: Texture2D
var _lookup: Dictionary = {}       # 4비트 코너 키(NW|NE<<1|SW<<2|SE<<3, 1=upper) -> Rect2
var _noise: FastNoiseLite
var _threshold: float = 0.18


func _ready() -> void:
	z_index = -10
	_noise = FastNoiseLite.new()
	_noise.seed = 1171
	_noise.frequency = 0.09
	_noise.fractal_octaves = 3
	_tex = SpriteLib.tex("res://assets/tilesets/%s.png" % TILESET)
	var meta_path: String = "res://assets/tilesets/%s.metadata.json" % TILESET
	if _tex != null and FileAccess.file_exists(meta_path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if d is Dictionary:
			for t: Variant in d.get("tileset_data", {}).get("tiles", []):
				var c: Dictionary = t.get("corners", {})
				var key: int = (1 if c.get("NW") == "upper" else 0) | ((1 if c.get("NE") == "upper" else 0) << 1) \
					| ((1 if c.get("SW") == "upper" else 0) << 2) | ((1 if c.get("SE") == "upper" else 0) << 3)
				var bb: Dictionary = t.get("bounding_box", {})
				_lookup[key] = Rect2(float(bb.get("x", 0)), float(bb.get("y", 0)), float(bb.get("width", TILE)), float(bb.get("height", TILE)))


func _corner(x: int, y: int) -> int:
	# 성역(원점 근처 마당)은 흙, 바깥으로 갈수록 풀
	var v: float = _noise.get_noise_2d(float(x), float(y))
	var d: float = Vector2(x, y).length() / 10.0
	return 1 if v + clampf(d - 1.0, -0.6, 0.3) * 0.5 > _threshold else 0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam: Camera2D = Game.camera
	var c: Vector2 = cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var half: Vector2 = get_viewport_rect().size * 0.5 + Vector2(TILE * 2, TILE * 2)
	var x0: int = int(floor((c.x - half.x) / TILE))
	var y0: int = int(floor((c.y - half.y) / TILE))
	var x1: int = int(floor((c.x + half.x) / TILE))
	var y1: int = int(floor((c.y + half.y) / TILE))
	var tint: Color = Color(0.62, 0.62, 0.7)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var r: Rect2 = Rect2(tx * TILE, ty * TILE, TILE, TILE)
			if _lookup.is_empty():
				var shade: float = 0.06 + 0.02 * float(((tx * 7 + ty * 13) & 3))
				draw_rect(r, Color(shade, shade * 0.85, shade * 1.3))
				continue
			var key: int = _corner(tx, ty) | (_corner(tx + 1, ty) << 1) | (_corner(tx, ty + 1) << 2) | (_corner(tx + 1, ty + 1) << 3)
			var src: Variant = _lookup.get(key)
			if src == null:
				src = _lookup.get(0, Rect2(0, 0, TILE, TILE))
			draw_texture_rect_region(_tex, r, src, tint)
