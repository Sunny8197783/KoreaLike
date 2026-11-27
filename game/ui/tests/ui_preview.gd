extends Node2D
## UI 미리보기(런 없이 HUD·점지·정산 화면을 띄워 캡처). 소유: ui.
## 실행: godot --path game res://ui/tests/ui_preview.tscn --write-movie … -- --ui-preview=hud|levelup|result
## 가짜 수치를 Game 에 넣고 Events 를 몇 개 쏴서 위젯 상태를 보여 준다(시뮬레이션은 돌지 않는다).

var _mode: String = "hud"
var _t: float = 0.0
var _fired: int = 0
var _layer: CanvasLayer


func _ready() -> void:
	_mode = DebugTools.arg("ui-preview", "hud")
	Game.reset_run(&"char_mansin")
	Game.xp = 14.0
	Game.xp_next = 18.0
	Game.hp = 62.0
	Game.hp_max = 100.0
	Game.kills_haewon = 142
	Game.kills_toechi = 88
	Game.salgi = 23.0
	Game.sinmyeong = 0.64
	Game.level = 7
	Game.game_tick = 155 * K.TICK_HZ
	var bg: ColorRect = ColorRect.new()
	bg.color = Color("2b2a22")
	bg.size = Vector2(1280, 720)
	bg.position = Vector2(-320, -180)
	add_child(bg)
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)
	match _mode:
		"result":
			Save.set_value("ui.last_run", {"victory": false, "time_sec": 412.0, "level": 9, "toechi": 210, "haewon": 388,
				"max_yeongga": 19, "rings": 4, "wongwi": 1, "weapons": ["wpn_sinkal:5", "wpn_bangul:4", "wpn_buchae:2"], "new_best": ["haewon"]})
			var r: Control = (load("res://ui/result.tscn") as PackedScene).instantiate() as Control
			r.call("setup", {"victory": false, "time_sec": 412.0, "toechi": 210, "haewon": 388, "level": 9})
			_layer.add_child(r)
		"records":
			Save.set_value("ui.records", {"enm_dalgyal_gwisin": [120, 40], "mboss_daegwi": [1, 0], "boss_yeokryeo": [1, 0],
				"elite_eodukssini": [2, 1], "enm_gaekgwi": [30, 66]})
			var rp: Control = (load("res://ui/records_panel.gd") as Script).new() as Control
			_layer.add_child(rp)
			rp.call_deferred("open")
		"settings":
			var sp: Control = SettingsPanel.new()
			_layer.add_child(sp)
			sp.call_deferred("open")
		"pause":
			var h2: Control = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Control
			_layer.add_child(h2)
			var pl: CanvasLayer = CanvasLayer.new()
			pl.layer = 20
			add_child(pl)
			var pm: Control = (load("res://ui/pause_menu.tscn") as PackedScene).instantiate() as Control
			pl.add_child(pm)
			pm.call_deferred("toggle")
		"levelup":
			var lv: Control = (load("res://ui/levelup.tscn") as PackedScene).instantiate() as Control
			_layer.add_child(lv)
			var c: Array[Dictionary] = [
				{"kind": "weapon", "id": &"wpn_gakgung", "level": 1, "title": "각궁", "desc": ""},
				{"kind": "weapon", "id": &"wpn_bangul", "level": 3, "title": "방울", "desc": "반경 +0.3"},
				{"kind": "weapon", "id": &"wpn_buchae", "level": 1, "title": "부채", "desc": ""}]
			lv.call("open_with", c)
		"tut", "tut_card", "tut_end", "tut_jeomji", "tut_pause":
			# 연습 굿판 HUD(design/17): tutorial_hud + 가짜 tutorial_* 신호. 시뮬레이션은 돌지 않는다.
			Game.tutorial_mode = true
			var h3: Control = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Control
			_layer.add_child(h3)
			var th: Node = (load("res://ui/tutorial_hud.gd") as Script).new() as Node
			add_child(th)
			if _mode == "tut_jeomji":
				var lv2: Control = (load("res://ui/levelup.tscn") as PackedScene).instantiate() as Control
				var ll: CanvasLayer = CanvasLayer.new()
				ll.layer = 20
				add_child(ll)
				ll.add_child(lv2)
			if _mode == "tut_pause":
				var pl2: CanvasLayer = CanvasLayer.new()
				pl2.layer = 20
				add_child(pl2)
				var pm2: Control = (load("res://ui/pause_menu.tscn") as PackedScene).instantiate() as Control
				pl2.add_child(pm2)
				pm2.call_deferred("toggle")
		_:
			var h: Control = (load("res://ui/hud.tscn") as PackedScene).instantiate() as Control
			_layer.add_child(h)


func _process(delta: float) -> void:
	_t += delta
	if _mode.begins_with("tut"):
		_tut_step()
		return
	if _mode != "hud":
		return
	# 시간차로 이벤트를 흘려 위젯을 깨운다
	if _fired == 0 and _t > 0.2:
		_fired = 1
		Events.geori_changed.emit(&"geori_gamang_sansin", 80.0, &"jungmori")
		Events.trial_end.emit(1, &"deity_sansin", &"wieom")
		Events.trial_end.emit(2, &"deity_yongwang", &"gaho")
		Events.wongwi_return.emit(25)
	if _fired == 1 and _t > 0.6:
		_fired = 2
		for i in 24:
			Events.enemy_killed.emit(i, &"enm_gaekgwi", Vector2.ZERO, K.KIND_HAEWON, &"white", K.TIER_COMMON)
		Events.gongsu_spoken.emit(&"deity_sansin", &"test", "산이 운다… 길을 비켜라")


var _tut_beat: int = -1


## 연습 굿판 HUD 미리보기: 시간차로 tutorial_* 신호를 흘린다
func _tut_step() -> void:
	if _fired == 0 and _t > 0.1:
		_fired = 1
		Events.emit_signal(&"tutorial_started", &"move", 10)
		Events.emit_signal(&"tutorial_step_started", &"move", 0, 10, "걸어 보세요", "WASD·방향키 / 왼쪽 스틱 — 조작은 걷기 하나뿐입니다")
	if _fired == 1 and _t > 2.2:
		_fired = 2
		Events.emit_signal(&"tutorial_step_completed", &"move", "걸음", "")
		Events.emit_signal(&"tutorial_tag", "퇴치", "退治", Vector2(60, -30))
		Events.emit_signal(&"tutorial_tag", "한꺼번에 ×5", "", Vector2(-80, 40))
	if _fired == 2 and _t > 2.6:
		_fired = 3
		match _mode:
			"tut_card":
				Events.emit_signal(&"tutorial_step_started", &"settle", 9, 10, "정산과 신당", "")
				var card: Dictionary = {"pages": [
					{"title": "저승사자 — 굿판을 거두는 이", "lines": ["20분이 다하면 마지막 손님을 보내고, 저승사자가 굿판을 거두러 옵니다.",
						"넋이 많으면 사자가 읍하고, 살이 많으면 함께 살을 거둡니다. 어느 쪽도 굿의 끝입니다."], "image": "sprite:chaser_jeoseung_saja"},
					{"title": "신당", "lines": ["풀어 준 넋은 공덕으로, 모은 엽전은 그대로 신당에 남습니다.",
						"신당에서 새 무구와 무당을 모시고 다음 굿판을 엽니다."], "image": "res://ui/art/intro/intro_sindang.png"}],
					"confirm": "Enter / A 다음"}
				Events.emit_signal(&"tutorial_card", &"settle", card)
			"tut_end":
				for sid: StringName in [&"beat", &"cut", &"ring", &"white", &"yeongga", &"jeomji", &"trial", &"sal"]:
					Events.emit_signal(&"tutorial_step_completed", sid, "", "")
				Events.emit_signal(&"tutorial_finished", true)
			"tut_jeomji":
				Events.emit_signal(&"tutorial_step_started", &"jeomji", 6, 10, "원혼 구슬을 주우세요", "구슬이 차면 점지 — 신령이 무구를 골라 줍니다")
				var lv: Node = find_child("LevelUp", true, false)
				for n: Node in get_children():
					if n is CanvasLayer and n.get_child_count() > 0 and n.get_child(0).has_method("open_with"):
						lv = n.get_child(0)
				if lv != null:
					var c: Array[Dictionary] = [
						{"kind": "weapon", "id": &"wpn_woldo", "level": 1, "title": "월도", "desc": ""},
						{"kind": "weapon", "id": &"wpn_buchae", "level": 1, "title": "부채", "desc": ""},
						{"kind": "passive", "id": &"psv_baekjisul", "level": 1, "title": "백지술", "desc": ""}]
					lv.call("open_with", c)
			_:
				Events.emit_signal(&"tutorial_step_started", &"beat", 1, 10, "귀신 쪽으로 걸어가세요 — 무구는 저절로 칩니다",
					"◆ 붉은 신칼이 장단 박마다 날아갑니다. 시계 자리 ◆ 깜박임이 박입니다")
				Events.emit_signal(&"tutorial_step_progress", &"beat", 2, 5)
	if _fired == 3 and _t > 3.2 and _mode == "tut":
		_fired = 4
		Events.emit_signal(&"tutorial_help", &"beat", 1, "가장 가까운 귀신 쪽으로 걸어 보세요")
	if _fired >= 4 and _mode == "tut":
		var bi: int = int(_t / 1.33)
		if bi != _tut_beat:
			_tut_beat = bi
			Events.beat.emit(bi, bi % 4 == 0)
