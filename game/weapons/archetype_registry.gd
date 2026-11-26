class_name ArchetypeRegistry
## 무구 ID → 행동 원형(archetype) + 원형 파라미터. 소유: combat.
## weapons.json 의 "archetype" 필드는 한국어 설명이므로 실행 매핑은 여기서 한다.
## 새 무구/진화/결합: MAP 에 한 줄 추가. 없으면 tags 로 추측(TAG_FALLBACK).
## 진화·결합은 "base"(원본 무구: SFX·feel·빠진 수치 기준) 를 준다. 파라미터는 원형 스크립트 머리 주석 참고.

const SCRIPTS: Dictionary = {
	&"projectile": preload("res://weapons/archetypes/arch_projectile.gd"),
	&"melee_arc": preload("res://weapons/archetypes/arch_melee_arc.gd"),
	&"orbit": preload("res://weapons/archetypes/arch_orbit.gd"),
	&"aura": preload("res://weapons/archetypes/arch_aura.gd"),
	&"drop_zone": preload("res://weapons/archetypes/arch_drop_zone.gd"),
	&"trail": preload("res://weapons/archetypes/arch_trail.gd"),
	&"beam": preload("res://weapons/archetypes/arch_beam.gd"),
	&"summon": preload("res://weapons/archetypes/arch_summon.gd"),
}

## id -> [archetype_key, params]
const MAP: Dictionary = {
	# ── 무구 20 ──
	"wpn_sinkal": [&"projectile", {"return": true, "spread_deg": 12.0, "amt_sinjang": true}],
	"wpn_gakgung": [&"projectile", {"aim": "distinct", "amt_sinjang": true}],
	"wpn_jijeon": [&"projectile", {"fan_field": "angle", "amt_sinjang": true, "sinjang_per": 2}],
	"wpn_sainsageom": [&"projectile", {"spread_deg": 20.0, "aim": "elite", "elite_bonus": true, "blade": true, "amt_sinjang": true}],
	"wpn_woldo": [&"melee_arc", {"shape": "spin"}],
	"wpn_samjichang": [&"melee_arc", {"shape": "prong"}],
	"wpn_jangchang": [&"melee_arc", {"shape": "thrust"}],
	"wpn_pyeongon": [&"melee_arc", {"shape": "cone"}],
	"wpn_buchae": [&"melee_arc", {"shape": "cone", "pull_pullil": true}],
	"wpn_bangul": [&"aura", {"mode": "aura"}],
	"wpn_janggu": [&"aura", {"mode": "pulse", "downbeat": true, "ring2": true}],
	"wpn_hojakdo": [&"aura", {"mode": "pulse", "fear": true}],
	"wpn_jakdu": [&"aura", {"mode": "pulse", "jakdu": true}],
	"wpn_neokjeon": [&"orbit", {}],
	"wpn_myeongdu": [&"beam", {}],
	"wpn_ssukmul": [&"drop_zone", {"place": "dense"}],
	"wpn_sogeum": [&"drop_zone", {"place": "self", "push": true}],
	"wpn_obanggi": [&"drop_zone", {"place": "flag"}],
	"wpn_gilbe": [&"drop_zone", {"place": "line"}],
	"wpn_cheoljillyeo": [&"trail", {}],
	# ── 진화 20 ──
	"evo_sinjangkal": [&"projectile", {"base": "wpn_sinkal", "return": true, "spread_deg": 12.0, "catch": true}],
	"evo_jusahwajeon": [&"projectile", {"base": "wpn_gakgung", "aim": "distinct", "blast": true, "burn": true}],
	"evo_nojatdon": [&"projectile", {"base": "wpn_jijeon", "fan_field": "angle", "chain": true}],
	"evo_isippalsugeom": [&"projectile", {"base": "wpn_sainsageom", "spread_deg": 20.0, "aim": "elite", "elite_bonus": true, "blade": true, "stars": true}],
	"evo_manwoldo": [&"melee_arc", {"base": "wpn_woldo", "shape": "spin", "crescents": true}],
	"evo_saseulchang": [&"melee_arc", {"base": "wpn_samjichang", "shape": "prong", "fan_deg": 60.0}],
	"evo_pajinchang": [&"melee_arc", {"base": "wpn_jangchang", "shape": "thrust", "lunge": true}],
	"evo_byeongnyeok_pyeongon": [&"melee_arc", {"base": "wpn_pyeongon", "shape": "cone", "quake": true}],
	"evo_irwolseonpung": [&"melee_arc", {"base": "wpn_buchae", "shape": "cone", "pull_pullil": true, "whirls": true}],
	"evo_cheoneum_bangul": [&"aura", {"base": "wpn_bangul", "mode": "aura", "resonance": true}],
	"evo_hapjangdan": [&"aura", {"base": "wpn_janggu", "mode": "pulse", "downbeat": true, "gideok": true}],
	"evo_sangun_pohyodo": [&"aura", {"base": "wpn_hojakdo", "mode": "pulse", "fear": true}],
	"evo_daejakdu": [&"aura", {"base": "wpn_jakdu", "mode": "pulse", "jakdu": true, "wave2": true}],
	"evo_neokkkotbi": [&"orbit", {"base": "wpn_neokjeon", "permanent": true, "petals": true}],
	"evo_irwol_myeongdu": [&"beam", {"base": "wpn_myeongdu"}],
	"evo_sammul_ssitgim": [&"drop_zone", {"base": "wpn_ssukmul", "place": "dense", "sammul": true}],
	"evo_bujeong_gasim": [&"drop_zone", {"base": "wpn_sogeum", "place": "follow", "push": true, "bursts": true}],
	"evo_obangjin": [&"drop_zone", {"base": "wpn_obanggi", "place": "obangjin"}],
	"evo_begareugi": [&"drop_zone", {"base": "wpn_gilbe", "place": "line", "gilbe_trail": true}],
	"evo_cheoljillyeojin": [&"trail", {"base": "wpn_cheoljillyeo", "formation": true, "salgi": true}],
	# ── 결합 v1 (오방철진·산울림은 x1) ──
	"union_neoksinkal": [&"projectile", {"base": "wpn_sinkal", "return": true, "spread_deg": 12.0, "petals": true, "sub_orbit": true}],
	"union_sogeumsal": [&"projectile", {"base": "wpn_gakgung", "aim": "distinct", "blast": true, "sub_barrier": true}],
	"union_jakdu_dari": [&"aura", {"base": "wpn_jakdu", "mode": "pulse", "jakdu": true, "ring_judge": true, "sub_trail": true}],
	"union_chilseong_myeonggyeonggeom": [&"projectile", {"base": "wpn_sainsageom", "spread_deg": 20.0, "aim": "elite", "elite_bonus": true, "blade": true, "mirrors": true}],
}

const TAG_FALLBACK: Array = [
	["orbit", &"orbit"], ["aura", &"aura"], ["beam", &"beam"], ["trail", &"trail"], ["trap", &"trail"],
	["zone", &"drop_zone"], ["barrier", &"drop_zone"], ["cone", &"melee_arc"], ["melee", &"melee_arc"],
	["aoe_self", &"aura"], ["projectile", &"projectile"], ["summon", &"summon"],
]


static func resolve(def: Dictionary) -> Array:
	var id: String = String(def.get("id", ""))
	if MAP.has(id):
		return MAP[id]
	var tags: Variant = def.get("tags", [])
	if tags is Array:
		for pair: Array in TAG_FALLBACK:
			if tags.has(pair[0]):
				return [pair[1], {}]
	return [&"projectile", {}]


static func script_for(key: StringName) -> GDScript:
	return SCRIPTS.get(key, SCRIPTS[&"projectile"])


static func create(def: Dictionary, slot: int, mgr: Node2D, kind: StringName = WeaponBase.KIND_WEAPON) -> WeaponBase:
	var r: Array = resolve(def)
	var w: WeaponBase = script_for(r[0]).new() as WeaponBase
	var params: Dictionary = (r[1] as Dictionary).duplicate()
	var downbeat_list: Variant = Data.get_value("weapons", "globals.quantization.downbeat_weapons", [])
	if downbeat_list is Array and downbeat_list.has(def.get("id", "")):
		params["downbeat"] = true
	w.setup(def, slot, mgr, params, kind)
	return w
