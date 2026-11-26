extends Node
## meta 자가 검사(헤드리스). 소유: meta.
## 실행: $GODOT --headless --path game res://meta/tests/meta_selftest.tscn -- --profile=selftest
## 세이브 원자성·무결성·마이그레이션·멱등 정산·신당 단장·무당 해금·재가집 의뢰 흐름을 확인하고 [meta-test] 줄을 찍는다.

var _fail: int = 0
var _pass: int = 0


func _ready() -> void:
	_run_all.call_deferred()


func _check(name: String, cond: bool, info: String = "") -> void:
	if cond:
		_pass += 1
		print("[meta-test] PASS ", name, ("  " + info) if info != "" else "")
	else:
		_fail += 1
		print("[meta-test] FAIL ", name, ("  " + info) if info != "" else "")


func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _fake_run(char_id: StringName, haewon: int, toechi: int, cheondo: int, victory: bool, elites_toechi: int = 0) -> Dictionary:
	Game.stats.clear()
	Save._on_run_started(char_id)
	for i in haewon:
		Events.enemy_killed.emit(i, &"enm_dalgyal_gwisin", Vector2.ZERO, K.KIND_HAEWON, &"ring", K.TIER_COMMON)
	for i in toechi:
		Events.enemy_killed.emit(i, &"enm_agwi", Vector2.ZERO, K.KIND_TOECHI, &"han_pa", K.TIER_COMMON)
	for i in elites_toechi:
		Events.enemy_killed.emit(i, &"elite_bulgasari", Vector2.ZERO, K.KIND_TOECHI, &"han_pa", K.TIER_ELITE)
	Events.trial_resolved.emit(0, &"deity_sansin", &"wieom", true)
	Events.run_ended.emit({"victory": victory, "time_sec": 480.0, "haewon": haewon, "toechi": toechi + elites_toechi,
		"neok": cheondo, "haewon_ratio": float(haewon) / maxf(1.0, float(haewon + toechi + elites_toechi))})
	return Save.last_settlement


func _run_all() -> void:
	var path: String = Save.profile_path
	print("[meta-test] profile path ", path, " -> ", ProjectSettings.globalize_path(path))
	for suf: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suf):
			DirAccess.remove_absolute(path + suf)
	Save.load_profile()
	_check("new profile", Save.load_source == "new" and Save.wallet(MetaRules.CUR_G) == 0)
	_check("first run pending", Save.first_run_pending())
	_check("lobby closed before first run", not Save.facility_open("danjang_open_after_runs"))
	_check("default char", Save.selected_char() == &"char_mansin" and Save.char_unlocked(&"char_mansin"))
	_check("price scale", MetaRules.price(600) == 1300 and MetaRules.price(5000) == 10500, "600->%d 5000->%d" % [MetaRules.price(600), MetaRules.price(5000)])

	# 1) 초굿(사망) 정산
	var s1: Dictionary = _fake_run(&"char_mansin", 300, 200, 120, false, 2)
	_check("settle death", s1.get("result") == "DEATH" and int(s1.get("G", 0)) > 0 and bool(s1.get("saved", false)),
		"G=%d B=%d piece=%d tier=%d N=%.2f" % [int(s1.get("G", 0)), int(s1.get("B", 0)), int(s1.get("piece_G", 0)), int(s1.get("tier_B", 0)), float(s1.get("N", 0))])
	var sv: Dictionary = Save.settlement_view()
	_check("settlement view", int(sv.get("gain_G", 0)) == int(s1["G"]) + int(s1["piece_G"]) and (sv.get("rows", []) as Array).size() >= 2
		and bool(sv.get("first_run", false)), str(sv.get("rows", [])))
	_check("after first run: lobby", not Save.first_run_pending() and Save.facility_open("danjang_open_after_runs"))
	_check("notices", (s1.get("notices", []) as Array).size() >= 2, str(s1.get("notices", [])))
	var cards: Array = sv.get("cards", [])
	_check("result cards", cards.size() >= 2 and cards.size() <= 4 and cards.any(func(c: Variant) -> bool: return String((c as Dictionary).get("kind", "")) == "sayeon"),
		str(cards))
	var r0v: Dictionary = (sv.get("rows", []) as Array)[0]
	_check("conv row numbers", int(r0v.get("from_n", -9)) == int(s1["neok_w"]) and int(r0v.get("to_n", -9)) == int(s1["G"]), str(r0v))
	_check("singirok", int(Save.get_value("singirok.haewonrok.enm_dalgyal_gwisin.haewon", 0)) == 300
		and int(Save.get_value("singirok.byeoksarok.enm_agwi.toechi", 0)) == 200)
	_check("counters", MetaRules.counter(Save.profile, "cnt_runs") == 1 and MetaRules.counter(Save.profile, "cnt_box_gilhyung_opened") == 2
		and MetaRules.counter(Save.profile, "cnt_bingui_wieom_total") == 1)

	# 2) 멱등: 같은 uid 재정산 금지
	var g_before: int = Save.wallet(MetaRules.CUR_G)
	Save._run = {"uid": String(s1["run_uid"])}
	Save._run_live = true
	Save.settle_run("DEATH", {"haewon": 999, "toechi": 999})
	_check("idempotent settle", Save.wallet(MetaRules.CUR_G) == g_before)

	# 3) 신당 단장: 부족 → 실패, 충분 → 성공·원자 저장
	Save.profile["wallet"]["cur_gongdeok"] = 100
	var r0: Dictionary = Save.buy_danjang("dj_chotbul")
	_check("danjang insufficient", not bool(r0["ok"]), String(r0["reason"]))
	Save.profile["wallet"]["cur_gongdeok"] = 5000
	var r1: Dictionary = Save.buy_danjang("dj_chotbul")
	_check("danjang buy", bool(r1["ok"]) and Save.danjang_rank("dj_chotbul") == 1 and Save.wallet(MetaRules.CUR_G) == 3700,
		"gongdeok=%d" % Save.wallet(MetaRules.CUR_G))
	var bonus: Dictionary = MetaRules.danjang_stat_bonus(Save.profile)
	_check("danjang stat bonus", is_equal_approx(float(bonus.get(&"stat_jeonggi", 0.0)), 10.0), str(bonus))

	# 4) 다시 읽기(무결성 OK)
	Save.load_profile()
	_check("reload main", Save.load_source == "main" and Save.danjang_rank("dj_chotbul") == 1 and not bool(Save.profile.get("tamper_flag", false)))

	# 5) 본 파일 잘림 → .bak 복구(직전 저장본)
	var good: String = FileAccess.get_file_as_string(path)
	_write(path, good.substr(0, good.length() / 2))
	Save.load_profile()
	_check("corrupt main -> bak", Save.load_source == "bak", "source=%s" % Save.load_source)

	# 6) 변조(digest 불일치) → .bak
	Save.save_profile()
	var txt: String = FileAccess.get_file_as_string(path)
	_write(path, txt.replace("\"cur_bokjeon\": %d" % Save.wallet(MetaRules.CUR_B), "\"cur_bokjeon\": 77777"))
	Save.load_profile()
	_check("tampered main -> bak", Save.load_source == "bak" and Save.wallet(MetaRules.CUR_B) != 77777, "source=%s" % Save.load_source)

	# 7) 무당 인연·내림굿
	Save.profile["counters"]["cnt_haewon_total"] = 600
	var s2: Dictionary = _fake_run(&"char_mansin", 50, 50, 10, false)
	_check("char ready (dangol)", (Save.profile["unlocks"]["char_ready"] as Array).has("char_dangol"), str(s2.get("notices", [])))
	Save.profile["wallet"]["cur_gongdeok"] = 20000
	var u1: Dictionary = Save.unlock_char(&"char_dangol")
	_check("naerimgut", bool(u1["ok"]) and Save.char_unlocked(&"char_dangol") and Save.selected_char() == &"char_dangol")
	var u2: Dictionary = Save.unlock_char(&"char_simbang")
	_check("locked char refused", not bool(u2["ok"]), String(u2["reason"]))

	# 8) 재가집 의뢰: 3런 뒤 개방, 받고 클리어 → 완수·배율
	var s3: Dictionary = _fake_run(&"char_mansin", 50, 50, 10, false)
	_check("uiroe open after 3 runs", Save.uiroe_open() and Save.uiroe_offers().size() == 3, str(Save.uiroe_offers()) + " " + str(s3.get("notices", [])))
	var pick: String = String(Save.uiroe_offers()[0])
	Save.accept_uiroe(pick)
	_check("uiroe mods", String(Save.active_uiroe_mods().get("id", "")) == pick, str(Save.active_uiroe_mods()))
	var s4: Dictionary = _fake_run(&"char_mansin", 500, 400, 200, true, 3)
	_check("uiroe complete on clear", bool(s4.get("uiroe_done", false)) and (Save.profile["uiroe"]["completed"] as Array).has(pick)
		and not Save.uiroe_offers().has(pick) and Save.uiroe_offers().size() == 3, "lines=%s" % str(s4.get("lines", [])))
	_check("clear result", String(s4.get("result", "")) == "CLEAR_BOW" or String(s4.get("result", "")) == "CLEAR_SAL_GEODUM", String(s4.get("result", "")))

	# 8b) 23:00 사자가 판을 거둠(TIMEOUT_SAJA): 사망과 구분, 매듭당 공덕 +5%, 읍·의뢰 없음
	var base_run: Dictionary = {"haewon": 300, "toechi": 200, "cheondo_neok": 120, "siju": 1.0, "boss_knots": 4}
	var rd: Dictionary = base_run.duplicate()
	rd["result"] = MetaRules.R_DEATH
	var rt: Dictionary = base_run.duplicate()
	rt["result"] = MetaRules.R_TIMEOUT_SAJA
	var rt0: Dictionary = rt.duplicate()
	rt0["boss_knots"] = 0
	var cd: Dictionary = MetaRules.compute_settlement(rd)
	var ct: Dictionary = MetaRules.compute_settlement(rt)
	var ct0: Dictionary = MetaRules.compute_settlement(rt0)
	_check("timeout mult", int(ct0["G"]) == int(cd["G"]) and int(cd["G"]) > 0 and absi(int(ct["G"]) - int(roundf(float(int(cd["G"])) * 1.2))) <= 2,
		"death G=%d timeout0 G=%d timeout4 G=%d lines=%s" % [int(cd["G"]), int(ct0["G"]), int(ct["G"]), str(ct.get("lines", []))])
	_check("timeout no uiroe", not bool(ct.get("uiroe_done", true)) and int(ct["B"]) == int(cd["B"]))
	var clears_before: int = MetaRules.counter(Save.profile, "cnt_clears")
	Game.stats.clear()
	Save._on_run_started(&"char_mansin")
	Save._run["boss_knots"] = 3
	Events.run_ended.emit({"victory": false, "ending": &"timeout", "time_sec": 1390.0, "haewon": 100, "toechi": 100, "neok": 50, "haewon_ratio": 0.5})
	var s5: Dictionary = Save.last_settlement
	_check("timeout settle", String(s5.get("result", "")) == MetaRules.R_TIMEOUT_SAJA and MetaRules.counter(Save.profile, "cnt_clears") == clears_before
		and String((s5.get("lines", []) as Array)[0]).begins_with("사자가 판을 거둠"), "%s %s" % [String(s5.get("result", "")), str(s5.get("lines", []))])

	# 9) 옛 스텁 형식 마이그레이션(설정 보존)
	_write(path, JSON.stringify({"schema_version": 1, "currencies": {}, "unlocks": [], "settings": {"audio": {"music": 0.5}}, "stats": {}}))
	DirAccess.remove_absolute(path + ".bak")
	Save.load_profile()
	_check("migrate v0", Save.load_source == "migrated" and int(Save.profile["version"]) == Save.SAVE_VERSION
		and is_equal_approx(float(Save.get_value("settings.audio.music", 0.0)), 0.5) and Save.first_run_pending())
	Save.load_profile()
	_check("migrated saved", Save.load_source == "main")

	# 9b) v1 세이브: ui.records(넋기록 옛 위치) → singirok 이전. 정산 이후 판은 양쪽에 다 있으므로 종별 큰 값, 원본 유지, pre_v2 보존
	var p1: Dictionary = Save.default_profile()
	p1["version"] = 1
	p1["singirok"]["haewonrok"] = {"enm_agwi": {"haewon": 50, "pieces": [1]}}
	p1["singirok"]["byeoksarok"] = {"enm_agwi": {"toechi": 80, "tier": 0}}
	p1["ui"] = {"records": {"enm_agwi": [40, 120], "enm_gaekgwi": [33, 7]}, "runs": 4,
		"run_history": [{"char_id": "char_mansin", "victory": false, "time_sec": 300.0, "haewon": 33, "toechi": 7, "level": 5, "rings": 2}]}
	var pn: Dictionary = Save._normalized(p1)
	_write(path, JSON.stringify({"payload": pn, "integrity": {"algo": "sha256", "digest": Save._digest(pn)}}))
	DirAccess.remove_absolute(path + ".bak")
	var pre: String = path.get_basename() + ".pre_v2.json"
	if FileAccess.file_exists(pre):
		DirAccess.remove_absolute(pre)
	Save.load_profile()
	_check("migrate v1->v2", Save.load_source == "migrated" and int(Save.profile["version"]) == 2
		and int(Save.get_value("singirok.haewonrok.enm_agwi.haewon", 0)) == 50
		and int(Save.get_value("singirok.byeoksarok.enm_agwi.toechi", 0)) == 120
		and int(Save.get_value("singirok.haewonrok.enm_gaekgwi.haewon", 0)) == 33
		and int(Save.get_value("singirok.byeoksarok.enm_gaekgwi.toechi", 0)) == 7
		and (Save.get_value("singirok.haewonrok.enm_agwi.pieces", []) as Array).has(1), str(Save.get_value("singirok", {})))
	_check("migrate keeps ui", Save.get_value("ui.records", {}) is Dictionary and (Save.get_value("ui.records", {}) as Dictionary).size() == 2
		and int(Save.get_value("ui.runs", 0)) == 4 and FileAccess.file_exists(pre))
	_check("migrate history", (Save.profile["run_history"] as Array).size() == 1 and Save.recent_runs(5).size() == 1
		and Save.records_view().size() == 2, str(Save.records_view()))
	var again: Dictionary = Save.merge_legacy_records(Save.profile)
	_check("migrate idempotent", int(again["haewon_add"]) == 0 and int(again["toechi_add"]) == 0
		and int(Save.get_value("singirok.byeoksarok.enm_agwi.toechi", 0)) == 120)
	Save.load_profile()
	_check("v2 saved", Save.load_source == "main" and int(Save.profile["version"]) == 2)
	if FileAccess.file_exists(pre):
		DirAccess.remove_absolute(pre)

	# 10) 새 버전 세이브 → 읽기 전용
	var p99: Dictionary = Save.profile.duplicate(true)
	p99["version"] = 99
	var w99: Dictionary = {"payload": p99, "integrity": {"algo": "sha256", "digest": JSON.stringify(Save._normalized(p99), "", true).sha256_text()}}
	_write(path, JSON.stringify(w99))
	Save.load_profile()
	_check("future version read-only", Save.read_only and not Save.save_profile())
	var still: String = FileAccess.get_file_as_string(path)
	_check("future file untouched", still.find("\"version\":99") >= 0 or still.find("\"version\": 99") >= 0)

	# 정리
	for suf: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suf):
			DirAccess.remove_absolute(path + suf)
	print("[meta-test] done pass=%d fail=%d" % [_pass, _fail])
	Game.quit_game(1 if _fail > 0 else 0)
