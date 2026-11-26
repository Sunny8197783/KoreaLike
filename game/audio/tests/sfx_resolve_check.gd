extends Node
## SFX 매핑 점검(헤드리스): 모든 무구·진화·결합의 발동/적중음, 신령 빙의 변주, 다른 모듈이 부르는 고정 id 가
## 실제 파일(또는 대체)로 풀리는지 + 적중음 길이(짧고 단단하게 ≤ 0.25s). 소유: audio.
##   godot --headless --path game res://audio/tests/sfx_resolve_check.tscn
## 출력: [sfx-check] 줄. 무음(-1)으로 풀리는 것은 MISS 로 표시.

const FIXED: PackedStringArray = [
	"sfx_sys_haewon", "sfx_sys_pungyeong", "sfx_sys_hanpa", "sfx_sys_gyeoldanta", "sfx_sys_gildakkeum", "sfx_sys_maedeup_lock",
	"sfx_sys_pullil_enter", "sfx_sys_maetim", "sfx_pick_wonhon", "sfx_plr_hit", "sfx_plr_death", "sfx_plr_levelup_ready",
	"sfx_trl_omen", "sfx_trl_sinjangdae", "sfx_trl_circle_enter", "sfx_trl_confirm_ring", "sfx_trl_hapil", "sfx_trl_avatar_smile",
	"sfx_trl_avatar_telegraph", "sfx_trl_timeout_warn", "sfx_trl_wieom_step", "sfx_trl_gaho_step", "sfx_ui_jeomji_open",
	"sfx_ui_move", "sfx_ui_jeomji_pick", "sfx_ui_reroll", "sfx_ui_gongsu_show", "sfx_sys_sinmyeong_full", "sfx_sys_oreum_start",
	"stg_boss_silence", "stg_bridge_gullim", "stg_geori_land", "stg_mboss_enter", "stg_death", "stg_hapil_buildup",
	"amb_guksadang", "amb_lobby_sindang", "amb_trial_field", "sfx_amb_pungyeong",
]


func _ready() -> void:
	var miss: int = 0
	var long_hits: int = 0
	var ids: Array[String] = []
	for w: Variant in Data.get_value("weapons", "weapons", []):
		if w is Dictionary:
			ids.append(String(w.get("id", "")))
	for w: Variant in Data.get_value("weapons", "evolutions", []):
		if w is Dictionary:
			ids.append(String(w.get("id", "")))
	for w: Variant in Data.get_value("weapons", "unions", []):
		if w is Dictionary:
			ids.append(String(w.get("id", "")))
	for wid: String in ids:
		var sw: StringName = StringName(wid)
		Audio.router._weapon_info(sw)
		var fd: int = int(Audio.router._wpn_fire[sw])
		var hd: int = int(Audio.router._wpn_hit[sw])
		var hs: AudioStream = Audio.bank.pick_take(hd, Audio.rng()) if hd >= 0 else null
		var hl: float = hs.get_length() if hs != null else 0.0
		if fd < 0 or hd < 0:
			miss += 1
		if hl > 0.25:
			long_hits += 1
		print("[sfx-check] %-30s fire=%-28s hit=%-28s hit_len=%.3fs white=%s%s" % [wid, _nm(fd), _nm(hd), hl,
			Audio.router._wpn_white[sw], "  MISS" if (fd < 0 or hd < 0) else ""])
	for dk: String in ["sansin", "yongwang", "chilseong", "janggun", "barigongju", "jeseok_daegam"]:
		var s: AudioStream = Audio.bank.named_stream(Audio.def_of(&"sfx_trl_bingui"), "__" + dk)
		if s == null:
			miss += 1
		print("[sfx-check] sfx_trl_bingui__%s %s" % [dk, "ok" if s != null else "MISS"])
	for id: String in FIXED:
		var d: int = Audio.def_of(StringName(id))
		if d < 0:
			miss += 1
		print("[sfx-check] %-28s -> %s%s" % [id, _nm(d), "" if d >= 0 else "  MISS"])
	print("[sfx-check] done weapons=%d miss=%d long_hits(>0.25s)=%d" % [ids.size(), miss, long_hits])
	Game.quit_game(0)


func _nm(d: int) -> String:
	return String(Audio.bank.names[d]) if d >= 0 else "-"
