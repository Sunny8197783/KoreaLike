extends Node
## 런 장부: 이번 런 통계(최대 행렬·길닦음·원귀 회귀·천도·종별 해원/퇴치)를 모아
## 런 끝(Events.run_ended)에 세이브의 ui.* 구역에 남긴다. 소유: ui.
##  ui.last_run      정산 화면 입력(main.gd 가 넘기는 결과에 없는 항목 보충)
##  ui.records       넋기록 최소판: { species: [해원, 퇴치] }
##  ui.run_history   최근 10판 요약
##  ui.runs          시작한 판 수(온보딩 첫 판 판정)
## 세이브 스키마는 meta 소유 — TODO(meta): ui.* 를 singirok(해원록·벽사록)·run_history·counters 로 이전.

var max_yeongga: int = 0
var rings: int = 0
var ring_haewon: int = 0
var wongwi: int = 0
var cheondo: int = 0
var elites: int = 0
var trials_won: Array[String] = []
var _sp_h: Dictionary = {}       # StringName -> int
var _sp_t: Dictionary = {}
var _written: bool = false


func _ready() -> void:
	Events.yeongga_joined.connect(func(c: int, _s: StringName) -> void: max_yeongga = maxi(max_yeongga, c))
	Events.yeongga_cheondo.connect(func(c: int, _r: StringName) -> void: cheondo += c)
	Events.ring_closed.connect(func(_a: int, n: int, _c: Vector2) -> void:
		rings += 1
		ring_haewon += n)
	Events.wongwi_return.connect(func(_t: int) -> void: wongwi += 1)
	Events.trial_end.connect(func(_s: int, d: StringName, w: StringName) -> void:
		if w != &"none":
			trials_won.append("%s:%s" % [String(d), String(w)]))
	Events.enemy_killed.connect(_on_killed)
	Events.run_ended.connect(_on_run_ended)
	if Game.tutorial_mode:
		return   # 연습 굿판은 판 수를 세지 않는다(첫 실전 길잡이가 그대로 나오게, design/17 §7.3)
	var runs: int = int(Save.get_value("ui.runs", 0))
	Save.set_value("ui.runs", runs + 1)


func _on_killed(_h: int, sp: StringName, _pos: Vector2, kind: StringName, _cause: StringName, tier: StringName) -> void:
	if kind == K.KIND_HAEWON:
		_sp_h[sp] = int(_sp_h.get(sp, 0)) + 1
	else:
		_sp_t[sp] = int(_sp_t.get(sp, 0)) + 1
	if tier != &"" and tier != &"minion" and tier != &"common":
		elites += 1


func weapons_list() -> Array[String]:
	var out: Array[String] = []
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm == null:
		return out
	for i in wm.slot_count():
		var w: WeaponBase = wm.weapon_at(i)
		if w != null:
			out.append("%s:%d" % [String(w.id), w.level])
	return out


func _on_run_ended(result: Dictionary) -> void:
	if _written or Game.tutorial_mode:
		return
	_written = true
	var last: Dictionary = {
		"victory": bool(result.get("victory", false)), "time_sec": float(result.get("time_sec", Game.time_sec())),
		"char_id": String(Game.char_id), "level": Game.level, "toechi": Game.kills_toechi, "haewon": Game.kills_haewon,
		"max_yeongga": max_yeongga, "rings": rings, "ring_haewon": ring_haewon, "wongwi": wongwi, "cheondo": cheondo,
		"salgi": Game.salgi, "neok": Game.cur_neok, "weapons": weapons_list(), "trials": trials_won.duplicate(),
		"ending": String(result.get("ending", "")), "boss_form": String(result.get("boss_form", "")),
	}
	Save.set_value("ui.last_run", last)
	# 넋기록: 종별 누계
	var rec: Variant = Save.get_value("ui.records", {})
	var recd: Dictionary = rec if rec is Dictionary else {}
	for sp: Variant in _sp_h:
		var k: String = String(sp)
		var row: Array = recd.get(k, [0, 0])
		row[0] = int(row[0]) + int(_sp_h[sp])
		recd[k] = row
	for sp: Variant in _sp_t:
		var k: String = String(sp)
		var row: Array = recd.get(k, [0, 0])
		row[1] = int(row[1]) + int(_sp_t[sp])
		recd[k] = row
	Save.set_value("ui.records", recd)
	# 최근 10판
	var hist: Variant = Save.get_value("ui.run_history", [])
	var ha: Array = hist if hist is Array else []
	ha.push_front({"char_id": last["char_id"], "victory": last["victory"], "time_sec": last["time_sec"],
		"haewon": last["haewon"], "toechi": last["toechi"], "level": last["level"], "rings": rings})
	if ha.size() > 10:
		ha.resize(10)
	Save.set_value("ui.run_history", ha)
	# 개인 기록(정산 新 표시용)
	var best: Variant = Save.get_value("ui.best", {})
	var bd: Dictionary = best if best is Dictionary else {}
	var news: Array[String] = []
	for key: String in ["haewon", "toechi", "max_yeongga", "rings", "time_sec"]:
		var v: float = float(last[key])
		if v > float(bd.get(key, 0.0)):
			if bd.has(key):
				news.append(key)
			bd[key] = v
	Save.set_value("ui.best", bd)
	last["new_best"] = news
	Save.set_value("ui.last_run", last)
	UiSettings.persist()
