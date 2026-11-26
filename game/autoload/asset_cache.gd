extends Node
## AssetCache — SpriteLib/VfxLib 정적 함수가 쓰는 캐시 저장소. 소유: core(리드).
## (class_name 스크립트의 static var 는 Godot 4.7 에서 종료 시 스크립트 누수 경고를 내므로 캐시를 오토로드에 둔다.)

var tex: Dictionary = {}          # path/key -> Texture2D | null
var atlas: Dictionary = {}        # entity_id -> Dictionary
var fx: Dictionary = {}           # fx_id -> Dictionary
var manifest: Dictionary = {}
var manifest_loaded: bool = false


func clear() -> void:
	tex.clear()
	atlas.clear()
	fx.clear()
	manifest = {}
	manifest_loaded = false


func _exit_tree() -> void:
	clear()
