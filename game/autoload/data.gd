extends Node
## Data — JSON 테이블 로더 + ID 별칭 해석. 소유: core(리드).
## 원본은 저장소 루트 data/ 이고, game/data/ 는 tools/sync_data.sh 사본이다(직접 수정 금지).
## 테이블 키 = res://data/ 기준 상대 경로에서 .json 제거 ("weapons", "tech/perf_budgets", "narrative/cast_canon").

signal reloaded

const DATA_ROOT: String = "res://data"

var tables: Dictionary = {}          # key -> Variant(Dictionary|Array)
var aliases: Dictionary = {}         # old_id -> new_id
var load_errors: PackedStringArray = []

var _weapons: Dictionary = {}
var _evolutions: Dictionary = {}
var _unions: Dictionary = {}
var _passives: Dictionary = {}
var _characters: Dictionary = {}
var _enemies: Dictionary = {}        # 모든 적 계열(enemies/minions/elites/midbosses/bosses/chasers) id -> def
var _deities: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	tables.clear()
	load_errors.clear()
	_scan_dir(DATA_ROOT, "")
	_build_indices()
	reloaded.emit()


func _scan_dir(path: String, prefix: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("[Data] 데이터 폴더 없음: %s (tools/sync_data.sh 실행)" % path)
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(path.path_join(name), prefix + name + "/")
		elif name.ends_with(".json"):
			_load_file(path.path_join(name), prefix + name.get_basename())
		name = dir.get_next()
	dir.list_dir_end()


func _load_file(path: String, key: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		var msg: String = "[Data] JSON 파싱 실패 %s:%d %s" % [path, json.get_error_line(), json.get_error_message()]
		load_errors.append(msg)
		push_error(msg)
		return
	tables[key] = json.data


func _build_indices() -> void:
	aliases.clear()
	var canon: Dictionary = table("canon_ids")
	var a: Variant = canon.get("aliases", {})
	if a is Dictionary:
		for k: String in a:
			aliases[k] = String(a[k])
	var enemies_tbl: Dictionary = table("enemies")
	var meta_alias: Variant = enemies_tbl.get("meta", {}).get("id_aliases", {}) if enemies_tbl.get("meta", {}) is Dictionary else {}
	if meta_alias is Dictionary:
		for k: String in meta_alias:
			if meta_alias[k] is String and not aliases.has(k):
				aliases[k] = String(meta_alias[k])

	var w: Dictionary = table("weapons")
	_weapons = _index(w.get("weapons", []))
	_evolutions = _index(w.get("evolutions", []))
	_unions = _index(w.get("unions", []))
	_passives = _index(table("passives").get("passives", []))
	_characters = _index(table("characters").get("characters", []))
	_deities = _index(table("deities").get("deities", []))
	_enemies.clear()
	for group: String in ["enemies", "minions", "elites", "midbosses", "bosses", "chasers", "npcs"]:
		var arr: Variant = enemies_tbl.get(group, [])
		if arr is Array:
			for e: Variant in arr:
				if e is Dictionary and e.has("id"):
					_enemies[String(e["id"])] = e


func _index(arr: Variant) -> Dictionary:
	var out: Dictionary = {}
	if arr is Array:
		for e: Variant in arr:
			if e is Dictionary and e.has("id"):
				out[String(e["id"])] = e
	return out


## 테이블 원본. 없으면 빈 Dictionary.
func table(key: String) -> Variant:
	return tables.get(key, {})


## 점 경로 조회: get_value("combat_core", "hitstop.events_ms.gildakkeum", 80)
func get_value(key: String, path: String, default: Variant = null) -> Variant:
	var cur: Variant = tables.get(key, null)
	if cur == null:
		return default
	for part in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		elif cur is Array and part.is_valid_int() and int(part) < cur.size():
			cur = cur[int(part)]
		else:
			return default
	return cur


func num(key: String, path: String, default: float = 0.0) -> float:
	var v: Variant = get_value(key, path, default)
	if v is float or v is int:
		return float(v)
	return default


## 별칭 해석(최대 4단계). 폐기된 ID → 현재 ID.
func resolve_id(id: String) -> String:
	var cur: String = id
	for i in 4:
		if aliases.has(cur):
			cur = aliases[cur]
		else:
			break
	return cur


func weapon(id: String) -> Dictionary:
	return _weapons.get(resolve_id(id), {})


func evolution(id: String) -> Dictionary:
	return _evolutions.get(resolve_id(id), {})


func union(id: String) -> Dictionary:
	return _unions.get(resolve_id(id), {})


func passive(id: String) -> Dictionary:
	return _passives.get(resolve_id(id), {})


func character(id: String) -> Dictionary:
	return _characters.get(resolve_id(id), {})


func enemy(id: String) -> Dictionary:
	return _enemies.get(resolve_id(id), {})


func deity(id: String) -> Dictionary:
	return _deities.get(resolve_id(id), {})


func weapon_ids() -> Array:
	return _weapons.keys()


func character_ids() -> Array:
	return _characters.keys()


func deity_ids() -> Array:
	return _deities.keys()


## v1 범위(scope=="v1")만 반환. scope 키가 없으면 포함.
func is_v1(def: Dictionary) -> bool:
	return String(def.get("scope", "v1")) == "v1"
