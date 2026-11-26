extends Node
## 신당 로비 데모·캡처(사람이 보는 확인용). 소유: meta.
## $GODOT --path game res://meta/tests/lobby_demo.tscn --write-movie <abs>/frame.png --fixed-fps 60 --quit-after 520 -- --profile=lobbydemo [--fresh]
## --fresh: 첫 굿 직후(지갑 적음, 단장 0) 상태. 기본: 몇 판 치른 신당(단장 일부·무당 인연·의뢰).

var lobby: Control
var _f: int = 0


func _ready() -> void:
	var fresh: bool = OS.get_cmdline_user_args().has("--fresh")
	var p: Dictionary = Save.default_profile()
	p["counters"]["cnt_runs"] = 1 if fresh else 4
	p["counters"]["cnt_haewon_total"] = 380 if fresh else 820
	p["flags"]["tutorial_done"] = true
	p["wallet"]["cur_gongdeok"] = 1880 if fresh else 26400
	p["wallet"]["cur_bokjeon"] = 640 if fresh else 9100
	if not fresh:
		p["danjang"] = {"dj_chotbul": 2, "dj_yeondeung": 1, "dj_neokjeon": 1, "dj_obanggi": 1, "dj_sinjangdae": 1,
			"dj_geumjul": 1, "dj_jangdok": 1, "dj_jeonghwasu": 1, "dj_gilbe": 1, "dj_puri": 1, "dj_jipsin": 1}
		p["unlocks"]["chars"].append("char_baksu")
		p["unlocks"]["char_ready"].append("char_dangol")
		p["uiroe"]["offered"] = ["uiroe_honrye", "uiroe_horangi", "uiroe_dokkaebi"]
		p["uiroe"]["offered_age_runs"] = [0, 1, 0]
		p["uiroe"]["accepted"] = "uiroe_horangi"
	p["singirok"]["haewonrok"] = {"enm_dalgyal_gwisin": {"haewon": 312, "pieces": [1, 2]}, "enm_agwi": {"haewon": 44, "pieces": [1]}, "enm_gaekgwi": {"haewon": 20, "pieces": [1]}}
	p["singirok"]["byeoksarok"] = {"enm_dalgyal_gwisin": {"toechi": 140, "tier": 1}, "enm_agwi": {"toechi": 61, "tier": 0}, "enm_sangmun": {"toechi": 12, "tier": 0}}
	Save.reset_profile(p)
	Save.last_settlement = {"first_run": fresh, "result": "DEATH", "N": 0.62, "saved": true, "G": 482, "B": 404, "piece_G": 800 if fresh else 0,
		"tier_B": 0, "neok_w": 420, "yeop_w": 350, "lines": ["어울림 ×1.15"], "notices": []}
	Save.pending_notices.clear()
	if fresh:
		Save.pending_notices.append("신당 단장이 열렸습니다 — 공덕과 복전으로 신단을 꾸미면 다음 굿이 든든해집니다")
	lobby = (load("res://meta/sindang_lobby.tscn") as PackedScene).instantiate() as Control
	lobby.start_requested.connect(func(c: StringName) -> void: print("[lobby-demo] start_requested ", c))
	add_child(lobby)


func _process(_d: float) -> void:
	_f += 1
	match _f:
		150:
			lobby.call("open_panel", "danjang")
		190:
			_focus("dj_musindo")
		200:
			lobby.set("_hold_on", true)
			lobby.set("_hold_t", 0.0)
			lobby.set("_hold_item", lobby.get("_item_i"))
		260:
			lobby.call("open_panel", "char")
		300:
			_focus("char_dangol")
		305:
			lobby.set("_hold_on", true)
			lobby.set("_hold_t", 0.0)
			lobby.set("_hold_item", lobby.get("_item_i"))
		380:
			lobby.call("open_panel", "uiroe")
		420:
			lobby.call("open_panel", "singirok")
		425:
			lobby.set("_item_i", 1)
		460:
			lobby.call("open_panel", "weapons")
		500:
			lobby.call("open_panel", "depart")
		540:
			print("[lobby-demo] done gongdeok=%d bokjeon=%d musindo=%d dangol=%s" % [Save.wallet(MetaRules.CUR_G), Save.wallet(MetaRules.CUR_B),
				Save.danjang_rank("dj_musindo"), str(Save.char_unlocked(&"char_dangol"))])
			Game.quit_game(0)


func _focus(id: String) -> void:
	var items: Array = lobby.get("_items")
	for i in items.size():
		if String((items[i] as Dictionary).get("id", "")) == id:
			lobby.set("_item_i", i)
			lobby.set("_zone", 1)
			lobby.call("_ensure_visible")
