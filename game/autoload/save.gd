extends Node
## Save — 프로필 세이브 + 메타 진행(정산·해금·신당 단장·재가집 의뢰). 소유: meta.
## 설계: design/09 §19(파일·래퍼·원자 쓰기·멱등 정산·로드/마이그레이션), §3.2(정산), §5(신당), §5.6(의뢰).
## 수치: data/meta_economy.json (규칙은 meta/meta_rules.gd 순수 함수).
##
## 파일: user://save_profile.json = {payload, integrity:{algo:"sha256", digest}} (digest = 키 정렬·공백 없는 payload JSON 의 sha256)
##   쓰기: .tmp 작성 → 기존 본 → .bak 로 이동 → .tmp → 본 파일로 이동. 실패하면 메모리 상태를 트랜잭션 이전으로 되돌린다.
##   읽기: 본 → .bak → auto.{0,1,2} 순. 무결성 불일치면 다음 후보. 모두 불일치면 최신 파싱본 + tamper_flag.
##   version 이 SAVE_VERSION 보다 크면 읽기 전용(덮어쓰지 않음). 작으면 MIGRATIONS 체인.
## 메모리의 `profile` 은 payload 만 담는다(get_value/set_value 경로도 payload 기준).
## --autotest(봇·헤드리스)는 user://save_profile_autotest.json, --profile=<name> 은 user://save_profile_<name>.json 을 쓴다.
##
## 런 추적: Events.run_started 에서 신당 단장·의뢰 보정을 Game.stats 에 더하고, 런 중 이벤트(처치·시련·고리)를 센 뒤
## Events.run_ended(또는 물리기: 런 씬 퇴장)에서 1회 정산한다(run_uid 멱등). 결과는 last_settlement 에 남는다.

signal profile_changed                       # 지갑·해금·단장·의뢰 등 프로필이 바뀜(로비 갱신용)
signal settled(summary: Dictionary)          # 정산 직후(정산 화면용) — last_settlement 와 같은 내용

const SAVE_VERSION: int = 2                 # v2: 넋기록 ui.records → singirok 이전(_migrate_1_to_2)
const PATH: String = "user://save_profile.json"   # 기본 경로(실제 경로는 profile_path)
const EXAMPLE_PROFILE_ID: String = "7f3c2a9e-1b4d-4e7a-9c11-2f6b8d0e5a77"
const WALLET_MAX: int = 99999999
const HISTORY_MAX: int = 50
const SETTLED_MAX: int = 64

var profile: Dictionary = {}
var loaded: bool = false
var profile_path: String = PATH
var read_only: bool = false                  # 새 버전 세이브 — 덮어쓰지 않는다
var load_source: String = ""                 # "main" | "bak" | "auto0".. | "new" | "migrated"
var last_error: String = ""
var last_settlement: Dictionary = {}
var pending_notices: Array[String] = []      # 로비가 들어올 때 한 번 띄울 알림(메모리만)

# ─── 런 추적(이벤트 시점에만 갱신) ───
var _run_live: bool = false
var _run: Dictionary = {}
var _sp_haewon: Dictionary = {}              # StringName species -> int
var _sp_toechi: Dictionary = {}
var _run_root_ref: WeakRef = null
var _boss_h: int = -1                        # 이번 런 보스 핸들(시간 초과 정산의 매듭 진행 측정용)
var _boss_segs: int = 7                      # 보스 한 7구간 = 고풀이 매듭 7개
var _main_bad: bool = false                  # 본 파일이 상해 백업에서 읽음


func _ready() -> void:
	profile_path = _pick_path()
	load_profile()
	Events.run_started.connect(_on_run_started)
	Events.run_ended.connect(_on_run_ended)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.trial_resolved.connect(_on_trial_resolved)
	Events.ring_closed.connect(_on_ring_closed)
	Events.wongwi_return.connect(_on_wongwi_return)
	Events.boss_resolved.connect(_on_boss_resolved)
	Events.settlement_progress.connect(_on_settlement_progress)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.enemy_hit.connect(_on_enemy_hit)
	Events.enemy_pattern.connect(_on_enemy_pattern)


func _pick_path() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--profile="):
			var n: String = a.substr(10).validate_filename()
			if n != "":
				return "user://save_profile_%s.json" % n
	if args.has("--autotest"):
		return "user://save_profile_autotest.json"
	return PATH


## 다른 경로로 바꿔 다시 읽는다(테스트·데모 전용).
func use_profile_path(path: String) -> void:
	profile_path = path
	load_profile()


# ═══ 프로필 기본값·검증 ═════════════════════════════════════════════════

func default_profile() -> Dictionary:
	var now: String = _utc_now()
	var weapons: Array = []
	var wl: Variant = MetaRules.econ("weapons", [])
	if wl is Array:
		for w: Variant in wl:
			if w is Dictionary and bool((w as Dictionary).get("default_unlocked", false)):
				weapons.append(String((w as Dictionary)["id"]))
	var chars: Array = []
	for c: Variant in MetaRules.char_defs():
		var cid: String = String((c as Dictionary).get("id", ""))
		if MetaRules.char_cost(cid) <= 0 and MetaRules.char_condition(cid).is_empty():
			chars.append(cid)
	return {
		"version": SAVE_VERSION,
		"game_build": String(ProjectSettings.get_setting("application/config/version", "0.1.0")),
		"profile_id": _new_id(),
		"created_utc": now, "updated_utc": now, "playtime_s": 0,
		"wallet": {"cur_gongdeok": 0, "cur_bokjeon": 0},
		"ledger": {"cur_gongdeok": {"earned": 0, "spent": 0}, "cur_bokjeon": {"earned": 0, "spent": 0}},
		"unlocks": {"chars": chars, "char_ready": [], "weapons": weapons, "weapons_discovered": [],
			"evos_discovered": [], "unions_discovered": [], "recipes_revealed": [],
			"stages": ["stage_guksadang"], "modes": ["mode_pyojun"]},
		"danjang": {},
		"forge": {}, "shrines": {}, "cheongbae_mark": null,
		"myeongdu": {"collected": [], "nodes_unlocked": [], "loadout": []},
		"singirok": {"haewonrok": {}, "byeoksarok": {}, "milestones_claimed": [], "byeoksa_milestones_claimed": [], "uiryeseo_done": []},
		"companions": {"unlocked": [], "equipped": null},
		"ladder": {"max_dan_cleared": 0},
		"uiroe": {"offered": [], "offered_age_runs": [], "accepted": null, "completed": []},
		"achievements": {}, "ach_progress": {}, "ach_pending_platform": [],
		"lobby": {"last_char": "char_mansin"},
		"daily": {}, "active_run_uid": null, "settled_run_uids": [], "tamper_flag": false,
		"counters": {"cnt_runs": 0, "cnt_clears": 0, "cnt_haewon_total": 0, "cnt_toechi_total": 0,
			"cnt_bingui_wieom_total": 0, "cnt_box_gilhyung_opened": 0, "cnt_companions_unlocked": 0,
			"cnt_gildakkeum": 0, "cnt_wongwi_return": 0, "cnt_uiroe_done": 0},
		"run_history": [],
		"flags": {"tutorial_done": false},
		"settings": {},
	}


## 누락 키 채우기·타입 교정·범위 고정(19.7 validate_and_repair).
func _repair(p: Dictionary) -> Dictionary:
	var d: Dictionary = default_profile()
	for k: String in d:
		if not p.has(k) or (d[k] is Dictionary and not (p[k] is Dictionary)) or (d[k] is Array and not (p[k] is Array)):
			p[k] = d[k]
		elif d[k] is Dictionary:
			var pd: Dictionary = p[k]
			var dd: Dictionary = d[k]
			for k2: String in dd:
				if not pd.has(k2) or (dd[k2] is Array and not (pd[k2] is Array)) or (dd[k2] is Dictionary and not (pd[k2] is Dictionary)):
					pd[k2] = dd[k2]
	p["version"] = int(p.get("version", SAVE_VERSION))
	var w: Dictionary = p["wallet"]
	for c: String in ["cur_gongdeok", "cur_bokjeon"]:
		w[c] = clampi(int(w.get(c, 0)), 0, WALLET_MAX)
	var cn: Dictionary = p["counters"]
	for k: String in cn.keys():
		cn[k] = maxi(0, int(cn[k]))
	var dj: Dictionary = p["danjang"]
	for k: String in dj.keys():
		var it: Dictionary = MetaRules.danjang_item(k)
		if it.is_empty():
			push_warning("[Save] 알 수 없는 단장 항목 보존: %s" % k)
			continue
		dj[k] = clampi(int(dj[k]), 0, int(it.get("max_rank", 0)))
	# 기본 해금 무당은 언제나 포함
	var chars: Array = p["unlocks"]["chars"]
	for c: String in (d["unlocks"]["chars"] as Array):
		if not chars.has(c):
			chars.append(c)
	var u: Dictionary = p["uiroe"]
	var off: Array = u["offered"]
	var age: Array = u["offered_age_runs"]
	while age.size() < off.size():
		age.append(0)
	while age.size() > off.size():
		age.pop_back()
	return p


# ═══ 마이그레이션 ══════════════════════════════════════════════════════
## v0: 초기 스텁 형식(래퍼 없음 {schema_version, currencies, unlocks[], settings, stats}) 또는
##     예시 파일을 통째 저장한 것(profile_id == 예시 ID). 설정만 살리고 v1 새 프로필로.
## v1 → v2: 넋기록 저장 위치 이전. RunLedger(ui)가 따로 쌓던 ui.records {종: [해원, 퇴치]} 를 singirok(해원록·벽사록)에
##     합친다(종별 큰 값 — 정산 이후 판은 양쪽에 다 적혀 있으므로 더하면 두 번 센다). ui.run_history 는 프로필 run_history 가
##     비어 있을 때만 옮긴다. ui.* 원본은 지우지 않고, 이전 직전 파일은 <세이브>.pre_v2.json 으로 한 번 남긴다(데이터 손실 없음).

func _migrate(p: Dictionary, from_v: int) -> Dictionary:
	var v: int = from_v
	while v < SAVE_VERSION:
		match v:
			0:
				p = _migrate_0_to_1(p)
			1:
				p = _migrate_1_to_2(p)
		v += 1
		p["version"] = v
	return p


func _migrate_0_to_1(old: Dictionary) -> Dictionary:
	var p: Dictionary = default_profile()
	if old.get("settings") is Dictionary:
		p["settings"] = (old["settings"] as Dictionary).duplicate(true)
	var cur: Variant = old.get("currencies", {})
	if cur is Dictionary:
		for c: String in ["cur_gongdeok", "cur_bokjeon"]:
			if (cur as Dictionary).has(c):
				p["wallet"][c] = int((cur as Dictionary)[c])
	print("[Save] 마이그레이션 v0 → v1 (설정 보존)")
	return p


func _migrate_1_to_2(p: Dictionary) -> Dictionary:
	var st: Dictionary = merge_legacy_records(p)
	print("[Save] 마이그레이션 v1 → v2 (넋기록 ui.records → singirok: 종 %d, 해원 +%d, 퇴치 +%d, 판 기록 %d)" % [
		int(st["species"]), int(st["haewon_add"]), int(st["toechi_add"]), int(st["history"])])
	return p


## ui.records / ui.run_history → singirok / run_history. 멱등(종별 큰 값으로 맞추므로 몇 번 불러도 같다).
## 반환 {species, haewon_add, toechi_add, history}.
func merge_legacy_records(p: Dictionary) -> Dictionary:
	var out: Dictionary = {"species": 0, "haewon_add": 0, "toechi_add": 0, "history": 0}
	var ui: Variant = p.get("ui", {})
	if not (ui is Dictionary):
		return out
	if not (p.get("singirok") is Dictionary):
		p["singirok"] = {}
	var sg: Dictionary = p["singirok"]
	for k: String in ["haewonrok", "byeoksarok"]:
		if not (sg.get(k) is Dictionary):
			sg[k] = {}
	var hr: Dictionary = sg["haewonrok"]
	var br: Dictionary = sg["byeoksarok"]
	var rec: Variant = (ui as Dictionary).get("records", {})
	if rec is Dictionary:
		for sp: Variant in rec:
			var row: Variant = (rec as Dictionary)[sp]
			if not (row is Array) or (row as Array).size() < 2:
				continue
			var key: String = String(sp)
			var hv: int = maxi(0, int((row as Array)[0]))
			var tv: int = maxi(0, int((row as Array)[1]))
			var touched: bool = false
			if hv > 0:
				if not (hr.get(key) is Dictionary):
					hr[key] = {"pieces": [], "haewon": 0}
				var e: Dictionary = hr[key]
				if not (e.get("pieces") is Array):
					e["pieces"] = []
				var cur: int = int(e.get("haewon", 0))
				if hv > cur:
					out["haewon_add"] = int(out["haewon_add"]) + hv - cur
					e["haewon"] = hv
					touched = true
			if tv > 0:
				if not (br.get(key) is Dictionary):
					br[key] = {"toechi": 0, "tier": 0}
				var e2: Dictionary = br[key]
				var cur2: int = int(e2.get("toechi", 0))
				if tv > cur2:
					out["toechi_add"] = int(out["toechi_add"]) + tv - cur2
					e2["toechi"] = tv
					touched = true
				if not e2.has("tier"):
					e2["tier"] = 0
			if touched:
				out["species"] = int(out["species"]) + 1
	# 판 기록: 프로필 run_history 가 비었을 때만(정산 이후 판은 양쪽에 다 있어 겹친다). ui 는 최신이 앞 → 뒤집어 오래된 것부터.
	var uh: Variant = (ui as Dictionary).get("run_history", [])
	if uh is Array and not (uh as Array).is_empty():
		if not (p.get("run_history") is Array):
			p["run_history"] = []
		var hist: Array = p["run_history"]
		if hist.is_empty():
			var src: Array = (uh as Array).duplicate()
			src.reverse()
			for e3: Variant in src:
				if not (e3 is Dictionary):
					continue
				var d: Dictionary = e3
				hist.append({"run_uid": "legacy-%02d" % hist.size(), "char": String(d.get("char_id", "")),
					"result": MetaRules.R_CLEAR_BOW if bool(d.get("victory", false)) else MetaRules.R_DEATH,
					"time_s": int(float(d.get("time_sec", 0.0))), "haewon": int(d.get("haewon", 0)), "toechi": int(d.get("toechi", 0)),
					"neok": 0, "yeopjeon": 0, "gongdeok_gain": 0, "bokjeon_gain": 0, "uiroe": "", "boss_knots": 0,
					"stage": "stage_guksadang", "mode": "mode_pyojun", "dan": 0, "legacy": true})
			out["history"] = hist.size()
	if not (p.get("flags") is Dictionary):
		p["flags"] = {}
	(p["flags"] as Dictionary)["records_migrated_v2"] = true
	return out


## 이전 직전 원본을 한 번 남긴다(<세이브>.pre_v<n>.json). 이미 있으면 덮지 않는다.
func _keep_pre_migration(src_path: String, to_v: int) -> void:
	var dst: String = profile_path.get_basename() + ".pre_v%d.json" % to_v
	if FileAccess.file_exists(dst) or not FileAccess.file_exists(src_path):
		return
	var d: DirAccess = DirAccess.open("user://")
	if d != null and d.copy(src_path, dst) == OK:
		print("[Save] 이전 전 원본 보존: %s" % dst)


## 넋기록 표시용(신당 서고·ui 넋기록 패널 공용): 종별 {id, haewon, toechi, pieces:Array, tier} — 해원+퇴치 많은 순.
func records_view() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hr: Dictionary = get_value("singirok.haewonrok", {}) if get_value("singirok.haewonrok", {}) is Dictionary else {}
	var br: Dictionary = get_value("singirok.byeoksarok", {}) if get_value("singirok.byeoksarok", {}) is Dictionary else {}
	var ids: Dictionary = {}
	for k: Variant in hr:
		ids[String(k)] = true
	for k: Variant in br:
		ids[String(k)] = true
	for id: String in ids:
		var he: Dictionary = hr.get(id, {}) if hr.get(id) is Dictionary else {}
		var be: Dictionary = br.get(id, {}) if br.get(id) is Dictionary else {}
		out.append({"id": id, "haewon": int(he.get("haewon", 0)), "toechi": int(be.get("toechi", 0)),
			"pieces": (he.get("pieces", []) as Array).duplicate() if he.get("pieces") is Array else [], "tier": int(be.get("tier", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["haewon"]) + int(a["toechi"]) > int(b["haewon"]) + int(b["toechi"]))
	return out


## 최근 판 n개(최신이 앞). 프로필 run_history 항목 그대로(복사).
func recent_runs(n: int = 5) -> Array:
	var hist: Array = profile.get("run_history", []) if profile.get("run_history") is Array else []
	var out: Array = []
	for i in range(hist.size() - 1, maxi(-1, hist.size() - 1 - n), -1):
		out.append((hist[i] as Dictionary).duplicate() if hist[i] is Dictionary else hist[i])
	return out


# ═══ 읽기 ══════════════════════════════════════════════════════════════

func load_profile() -> Dictionary:
	loaded = true
	read_only = false
	last_error = ""
	var cands: Array[String] = [profile_path, profile_path + ".bak", _auto_path(0), _auto_path(1), _auto_path(2)]
	var srcs: Array[String] = ["main", "bak", "auto0", "auto1", "auto2"]
	var fallback: Dictionary = {}
	var fallback_src: String = ""
	var any_file: bool = false
	_main_bad = false
	for i in cands.size():
		if not FileAccess.file_exists(cands[i]):
			continue
		any_file = true
		var parsed: Variant = _parse(FileAccess.get_file_as_string(cands[i]))
		if not (parsed is Dictionary):
			push_warning("[Save] 파싱 실패: %s" % cands[i])
			continue
		var w: Dictionary = parsed
		var p: Dictionary
		var v: int
		if not w.has("payload"):
			p = w                               # v0 스텁 형식
			v = 0
		else:
			if not (w["payload"] is Dictionary):
				continue
			p = _normalized(w["payload"])
			var integ: Variant = w.get("integrity", {})
			var digest: String = String((integ as Dictionary).get("digest", "")) if integ is Dictionary else ""
			v = int(p.get("version", 1))
			if String(p.get("profile_id", "")) == EXAMPLE_PROFILE_ID:
				v = 0                           # 예시 파일이 기본값으로 저장된 옛 세이브
			elif digest != _digest(p):
				push_warning("[Save] 무결성 불일치: %s" % cands[i])
				if fallback.is_empty():
					fallback = p
					fallback_src = srcs[i]
				continue
		if i > 0 and FileAccess.file_exists(profile_path):
			_main_bad = true                    # 다음 저장에서 상한 본 파일이 좋은 .bak 을 덮지 않게
		if v > SAVE_VERSION:
			read_only = true
			last_error = "새 버전에서 만든 기록입니다(v%d). 이 빌드에서는 저장하지 않습니다." % v
			push_warning("[Save] " + last_error)
			profile = _repair(p)
			load_source = srcs[i]
			return profile
		if v < SAVE_VERSION:
			if v >= 1:
				_keep_pre_migration(cands[i], SAVE_VERSION)
			p = _migrate(p, v)
			load_source = "migrated"
		else:
			load_source = srcs[i]
		profile = _repair(p)
		if load_source == "migrated":
			save_profile()
		return profile
	if not fallback.is_empty():
		profile = _repair(fallback)
		profile["tamper_flag"] = true
		load_source = fallback_src
		push_warning("[Save] 무결성 불일치본을 사용(tamper_flag)")
		return profile
	if any_file:
		_preserve_corrupt()
		last_error = "기록을 읽을 수 없습니다. 원본은 corrupt_ 파일로 보존했습니다."
	profile = default_profile()
	load_source = "new"
	return profile


func _preserve_corrupt() -> void:
	var stamp: String = str(int(Time.get_unix_time_from_system()))
	var d: DirAccess = DirAccess.open("user://")
	if d == null:
		return
	if FileAccess.file_exists(profile_path):
		d.copy(profile_path, profile_path.get_basename() + ".corrupt_%s.json" % stamp)


# ═══ 쓰기(원자) ════════════════════════════════════════════════════════

func save_profile() -> bool:
	if read_only:
		Events.save_written.emit(false)
		return false
	profile["updated_utc"] = _utc_now()
	profile = _normalized(profile)
	var wrapper: Dictionary = {"payload": profile, "integrity": {"algo": "sha256", "digest": _digest(profile)}}
	var tmp: String = profile_path + ".tmp"
	var bak: String = profile_path + ".bak"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "기록이 저장되지 않았습니다(%s)" % error_string(FileAccess.get_open_error())
		Events.save_written.emit(false)
		return false
	f.store_string(JSON.stringify(wrapper, "\t"))
	f.flush()
	var werr: Error = f.get_error()
	f.close()
	if werr != OK:
		last_error = "기록이 저장되지 않았습니다(쓰기 오류)"
		DirAccess.remove_absolute(tmp)
		Events.save_written.emit(false)
		return false
	var ok: bool = true
	if _main_bad and FileAccess.file_exists(profile_path):
		_preserve_corrupt()
		DirAccess.remove_absolute(profile_path)
		_main_bad = false
	if FileAccess.file_exists(profile_path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		ok = DirAccess.rename_absolute(profile_path, bak) == OK
	if ok:
		ok = DirAccess.rename_absolute(tmp, profile_path) == OK
	if not ok:
		last_error = "기록이 저장되지 않았습니다(이름 바꾸기 실패)"
	Events.save_written.emit(ok)
	return ok


func _auto_path(n: int) -> String:
	return profile_path.get_basename() + ".auto.%d.json" % n


## 10런마다 순환 백업(19.1).
func _rotate_auto_backup() -> void:
	var runs: int = MetaRules.counter(profile, "cnt_runs")
	if runs <= 0 or runs % 10 != 0 or not FileAccess.file_exists(profile_path):
		return
	var d: DirAccess = DirAccess.open("user://")
	if d != null:
		d.copy(profile_path, _auto_path((runs / 10) % 3))


## 트랜잭션: fn 을 적용하고 저장. 저장 실패 시 메모리 롤백(5.3 APPLY_TX).
func _transact(fn: Callable) -> bool:
	var snap: Dictionary = profile.duplicate(true)
	fn.call()
	if save_profile():
		profile_changed.emit()
		return true
	profile = snap
	profile_changed.emit()
	return false


func _parse(text: String) -> Variant:
	var j: JSON = JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


func _digest(p: Dictionary) -> String:
	return JSON.stringify(p, "", true).sha256_text()


## JSON 왕복 안정화: 정수값 float → int (Godot JSON 은 숫자를 float 로 읽는다, 19.2).
func _normalized(v: Variant) -> Variant:
	if v is Dictionary:
		var out: Dictionary = {}
		for k: Variant in v:
			out[String(k)] = _normalized(v[k])
		return out
	if v is Array:
		var a: Array = []
		for e: Variant in v:
			a.append(_normalized(e))
		return a
	if v is float:
		var f: float = v
		if is_finite(f) and absf(f) < 9.0e15 and f == floorf(f):
			return int(f)
	if v is StringName:
		return String(v)
	return v


# ═══ 점 경로 조회/설정 ═════════════════════════════════════════════════

## get_value("wallet.cur_gongdeok", 0)
func get_value(path: String, default: Variant = null) -> Variant:
	var cur: Variant = profile
	for part in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default
	return cur


func set_value(path: String, value: Variant) -> void:
	var parts: PackedStringArray = path.split(".")
	var cur: Dictionary = profile
	for i in parts.size() - 1:
		if not (cur.get(parts[i]) is Dictionary):
			cur[parts[i]] = {}
		cur = cur[parts[i]]
	cur[parts[parts.size() - 1]] = value


# ═══ 지갑 ═════════════════════════════════════════════════════════════

func wallet(cur: StringName) -> int:
	return int((profile.get("wallet", {}) as Dictionary).get(String(cur), 0))


func _wallet_add(cur: StringName, n: int) -> void:
	var w: Dictionary = profile["wallet"]
	var key: String = String(cur)
	w[key] = clampi(int(w.get(key, 0)) + n, 0, WALLET_MAX)
	var led: Dictionary = profile["ledger"]
	if not (led.get(key) is Dictionary):
		led[key] = {"earned": 0, "spent": 0}
	if n >= 0:
		led[key]["earned"] = int(led[key].get("earned", 0)) + n
	else:
		led[key]["spent"] = int(led[key].get("spent", 0)) - n


func _emit_wallet() -> void:
	Events.currency_changed.emit(MetaRules.CUR_G, wallet(MetaRules.CUR_G))
	Events.currency_changed.emit(MetaRules.CUR_B, wallet(MetaRules.CUR_B))


# ═══ 흐름·시설 ════════════════════════════════════════════════════════

## 첫 실행: 타이틀에서 바로 초굿(첫 굿판). 끝나면(사망·클리어·물리기) false.
func first_run_pending() -> bool:
	return MetaRules.first_run_pending(profile)


## 타이틀 '굿판 열기'가 신당을 거쳐야 하는가.
func lobby_route() -> bool:
	return not first_run_pending()


func runs_done() -> int:
	return MetaRules.runs_done(profile)


func facility_open(key: String) -> bool:
	return MetaRules.facility_open(profile, key)


func flag(id: String) -> bool:
	return bool((profile.get("flags", {}) as Dictionary).get(id, false))


func set_flag(id: String, on: bool = true, persist: bool = true) -> void:
	(profile["flags"] as Dictionary)[id] = on
	if persist:
		save_profile()


# ═══ 무당 ═════════════════════════════════════════════════════════════

func selected_char() -> StringName:
	var id: String = String(get_value("lobby.last_char", "char_mansin"))
	if not MetaRules.char_unlocked(profile, id):
		id = "char_mansin"
	return StringName(id)


func select_char(id: StringName) -> bool:
	if not MetaRules.char_unlocked(profile, String(id)):
		return false
	set_value("lobby.last_char", String(id))
	save_profile()
	profile_changed.emit()
	return true


func char_unlocked(id: StringName) -> bool:
	return MetaRules.char_unlocked(profile, String(id))


## 내림굿(무당 해금): 조건 충족 + 공덕 봉헌. 반환 {ok, reason}
func unlock_char(id: StringName) -> Dictionary:
	var sid: String = String(id)
	if MetaRules.char_unlocked(profile, sid):
		return {"ok": false, "reason": "이미 모신 무당입니다"}
	if not MetaRules.char_ready(profile, sid):
		return {"ok": false, "reason": "아직 인연이 닿지 않았습니다"}
	var cost: int = MetaRules.char_cost(sid)
	if wallet(MetaRules.CUR_G) < cost:
		return {"ok": false, "reason": "공덕이 모자랍니다"}
	var ok: bool = _transact(func() -> void:
		_wallet_add(MetaRules.CUR_G, -cost)
		(profile["unlocks"]["chars"] as Array).append(sid)
		(profile["unlocks"]["char_ready"] as Array).erase(sid)
		set_value("lobby.last_char", sid))
	if not ok:
		return {"ok": false, "reason": last_error}
	_emit_wallet()
	Events.unlock_gained.emit(StringName(sid))
	print("[meta] 내림굿 %s cost=%d gongdeok=%d" % [sid, cost, wallet(MetaRules.CUR_G)])
	return {"ok": true, "reason": ""}


# ═══ 신당 단장 ════════════════════════════════════════════════════════

func danjang_rank(id: String) -> int:
	return MetaRules.danjang_rank(profile, id)


## 다음 랭크 봉헌/제작. 반환 {ok, reason, rank}
func buy_danjang(id: String) -> Dictionary:
	var it: Dictionary = MetaRules.danjang_item(id)
	if it.is_empty():
		return {"ok": false, "reason": "없는 항목", "rank": 0}
	if not facility_open("danjang_open_after_runs"):
		return {"ok": false, "reason": "첫 굿을 마친 뒤 열립니다", "rank": 0}
	var cost: int = MetaRules.danjang_next_cost(profile, id)
	if cost < 0:
		return {"ok": false, "reason": "이미 다 갖추었습니다", "rank": danjang_rank(id)}
	var cur: StringName = MetaRules.danjang_currency(id)
	if wallet(cur) < cost:
		return {"ok": false, "reason": "%s이 모자랍니다" % MetaRules.currency_name(cur), "rank": danjang_rank(id)}
	var ok: bool = _transact(func() -> void:
		_wallet_add(cur, -cost)
		(profile["danjang"] as Dictionary)[id] = danjang_rank(id) + 1)
	if not ok:
		return {"ok": false, "reason": last_error, "rank": danjang_rank(id)}
	_emit_wallet()
	Events.unlock_gained.emit(StringName("%s__%d" % [id, danjang_rank(id)]))
	print("[meta] 단장 %s rank=%d cost=%d %s=%d" % [id, danjang_rank(id), cost, cur, wallet(cur)])
	return {"ok": true, "reason": "", "rank": danjang_rank(id)}


# ═══ 재가집 의뢰 ══════════════════════════════════════════════════════

func uiroe_open() -> bool:
	return facility_open("uiroe_open_after_runs")


func uiroe_offers() -> Array:
	return (profile["uiroe"]["offered"] as Array).duplicate()


func uiroe_accepted() -> String:
	var a: Variant = profile["uiroe"].get("accepted")
	return String(a) if a != null else ""


## id == "" 이면 받지 않음.
func accept_uiroe(id: String) -> bool:
	if id != "" and not (profile["uiroe"]["offered"] as Array).has(id):
		return false
	profile["uiroe"]["accepted"] = id if id != "" else null
	var ok: bool = save_profile()
	profile_changed.emit()
	return ok


## 런 수정자(waves/deities/haewon 이 런 시작 때 읽는다). 없으면 빈 사전.
## {id, species_weight?, deity_guarantee?, mboss_fixed?, salgi_base_add?, neok_sumyeong_add_s?, elite_extra?}
func active_uiroe_mods() -> Dictionary:
	var id: String = uiroe_accepted()
	if id == "":
		return {}
	var m: Variant = MetaRules.uiroe_def(id).get("mods", {})
	var out: Dictionary = (m as Dictionary).duplicate(true) if m is Dictionary else {}
	out["id"] = id
	return out


func _uiroe_refill(rng: RandomNumberGenerator) -> void:
	if not uiroe_open():
		return
	var u: Dictionary = profile["uiroe"]
	var off: Array = u["offered"]
	var age: Array = u["offered_age_runs"]
	var want: int = int(MetaRules.num("uiroe.offers", 3.0))
	var pool: Array = MetaRules.uiroe_pool(profile)
	var cands: Array = []
	for id: Variant in pool:
		if not off.has(id):
			cands.append(id)
	# 이미 완수한 의뢰는 뒤로(새 사연 먼저)
	var fresh: Array = cands.filter(func(x: Variant) -> bool: return not (u["completed"] as Array).has(x))
	var pick_from: Array = fresh if not fresh.is_empty() else cands
	while off.size() < want and not pick_from.is_empty():
		var k: int = rng.randi_range(0, pick_from.size() - 1)
		off.append(pick_from[k])
		age.append(0)
		cands.erase(pick_from[k])
		pick_from.remove_at(k)
		if pick_from.is_empty():
			pick_from = cands


# ═══ 무구 해금(09 §6: 백 무구 = 공덕 봉헌, 적 무구 = 복전 제작) ══════════════

## 점지 후보 필터용: meta_economy.weapons 에 없는 무구(무당 고유 등)는 항상 true.
func weapon_unlocked(id: StringName) -> bool:
	var sid: String = String(Data.resolve_id(String(id))).split("__")[0]
	if MetaRules.weapon_def(sid).is_empty():
		return true
	return MetaRules.weapon_state(profile, sid) == "owned"


func buy_weapon(id: String) -> Dictionary:
	if not facility_open("weapon_offering_open_after_runs"):
		return {"ok": false, "reason": "첫 굿을 마친 뒤 열립니다"}
	match MetaRules.weapon_state(profile, id):
		"owned": return {"ok": false, "reason": "이미 갖춘 무구입니다"}
		"undiscovered": return {"ok": false, "reason": "아직 발견하지 못한 무구입니다"}
		"gate": return {"ok": false, "reason": "같은 색 무구를 먼저 더 갖추어야 합니다"}
	var cost: int = MetaRules.weapon_cost(id)
	var cur: StringName = MetaRules.weapon_currency(id)
	if wallet(cur) < cost:
		return {"ok": false, "reason": "%s이 모자랍니다" % MetaRules.currency_name(cur)}
	var ok: bool = _transact(func() -> void:
		_wallet_add(cur, -cost)
		(profile["unlocks"]["weapons"] as Array).append(id))
	if not ok:
		return {"ok": false, "reason": last_error}
	_emit_wallet()
	Events.unlock_gained.emit(StringName(id))
	print("[meta] 무구 %s cost=%d %s=%d" % [id, cost, cur, wallet(cur)])
	return {"ok": true, "reason": ""}


# ═══ 런 추적 ══════════════════════════════════════════════════════════

func _on_run_started(char_id: StringName) -> void:
	if Game.tutorial_mode:
		return   # 연습 굿판은 런 추적·정산에서 뺀다(design/17 F4) → _run_live=false
	var uid: String = "r-%06d-%s" % [MetaRules.counter(profile, "cnt_runs") + 1, _new_id().substr(0, 6)]
	_run = {"uid": uid, "char": String(char_id), "start_ms": Time.get_ticks_msec(),
		"cheondo_neok": 0, "elite_haewon": 0, "mboss_haewon": 0, "boss_haewon": 0,
		"elite_toechi": 0, "mboss_toechi": 0, "boss_toechi": 0,
		"trial_gaho": 0, "trial_wieom": 0, "trial_gaho_half": 0, "trial_wieom_half": 0,
		"rings": 0, "wongwi": 0, "n_final": -1.0, "geodum_p": 1.0, "boss_knots": 0,
		"uiroe": uiroe_accepted(), "danjang": {}}
	_sp_haewon.clear()
	_sp_toechi.clear()
	_boss_h = -1
	_boss_segs = maxi(1, int(MetaRules.num("income.settlement.timeout_knots_max", 7.0)))
	_run_live = true
	_apply_run_bonuses()
	profile["active_run_uid"] = uid
	set_value("lobby.last_char", String(char_id))
	save_profile()
	if Game.run_root != null:
		_run_root_ref = weakref(Game.run_root)
		if not Game.run_root.tree_exiting.is_connected(_on_run_root_exiting):
			Game.run_root.tree_exiting.connect(_on_run_root_exiting, CONNECT_ONE_SHOT)
	print("[meta] run_started uid=%s char=%s uiroe=%s danjang=%s" % [uid, char_id, _run["uiroe"], str(_run["danjang"])])


## 신당 단장 영구 강화 + 의뢰 넋 수명 보정을 Game.stats 에 더한다(sindang_danjang.doc: run_started).
func _apply_run_bonuses() -> void:
	var bonus: Dictionary = MetaRules.danjang_stat_bonus(profile)
	var mods: Dictionary = active_uiroe_mods()
	if mods.has("neok_sumyeong_add_s"):
		bonus[&"stat_neok_sumyeong"] = float(bonus.get(&"stat_neok_sumyeong", 0.0)) + float(mods["neok_sumyeong_add_s"])
	# WeaponManager 는 setup_character(run_started 이전)에서 '패시브 적용 전 기본치' 사본(_stat_base)을 뜬다.
	# 그 사본에도 더해 두지 않으면 첫 패시브 재계산 때 단장 보정이 지워진다.
	# TODO(combat): weapon_manager.add_base_stat(stat, add) 공개 API 가 생기면 그쪽으로 교체.
	var wbase: Variant = Game.weapons.get("_stat_base") if Game.weapons != null else null
	for st: StringName in bonus:
		var add: float = float(bonus[st])
		var cur: float = Game.stat(st, float(Data.get_value("characters", "stat_base." + String(st), 0.0)))
		Game.stats[st] = cur + add
		if wbase is Dictionary:
			(wbase as Dictionary)[st] = float((wbase as Dictionary).get(st, cur)) + add
		if st == &"stat_jeonggi":
			Game.hp_max += add
			Game.hp = Game.hp_max
	_run["danjang"] = bonus


func _on_enemy_killed(_h: int, species: StringName, _p: Vector2, kind: StringName, _cause: StringName, tier: StringName) -> void:
	if not _run_live:
		return
	var haewon: bool = kind == K.KIND_HAEWON
	var d: Dictionary = _sp_haewon if haewon else _sp_toechi
	d[species] = int(d.get(species, 0)) + 1
	var pre: String = "_haewon" if haewon else "_toechi"
	match tier:
		K.TIER_ELITE: _run["elite" + pre] = int(_run["elite" + pre]) + 1
		K.TIER_MBOSS: _run["mboss" + pre] = int(_run["mboss" + pre]) + 1
		K.TIER_BOSS: _run["boss" + pre] = int(_run["boss" + pre]) + 1


func _on_trial_resolved(_slot: int, _deity: StringName, face: StringName, complete: bool) -> void:
	if not _run_live:
		return
	var key: String = "trial_wieom" if face == &"wieom" else "trial_gaho"
	if not complete:
		key += "_half"
	_run[key] = int(_run[key]) + 1


func _on_ring_closed(_a: int, _n: int, _c: Vector2) -> void:
	if _run_live:
		_run["rings"] = int(_run["rings"]) + 1


func _on_wongwi_return(_t: int) -> void:
	if _run_live:
		_run["wongwi"] = int(_run["wongwi"]) + 1


func _on_boss_resolved(_h: int, _kind: StringName, n_final: float) -> void:
	if _run_live:
		_run["n_final"] = n_final


func _on_boss_spawned(handle: int, _species: StringName, _form: StringName) -> void:
	if _run_live:
		_boss_h = handle


## 보스가 맞을 때만(핸들 비교 한 번으로 나머지는 즉시 빠짐) 진행 매듭을 갱신한다. 할당 없음.
func _on_enemy_hit(handle: int, _sp: StringName, _pos: Vector2, _dmg: float, _color: int, _crit: bool, _locked: bool) -> void:
	if handle == _boss_h and _run_live:
		_sample_boss_knots()


func _on_enemy_pattern(handle: int, _sp: StringName, _pat: StringName, _pos: Vector2, _tele: float) -> void:
	if handle == _boss_h and _run_live:
		_sample_boss_knots()


## 보스 진행 매듭 = 깎인 한의 7구간 수(한형: 고풀이 매듭 구간과 정확히 같음, 살형: 같은 비율 환산). 줄지 않는다.
func _sample_boss_knots() -> void:
	var em: Node = Game.enemies
	if em == null or not is_instance_valid(em):
		return
	var slot: int = int(em.call("slot_of", _boss_h))
	if slot < 0:
		return
	var hmv: Variant = em.get(&"han_max")
	var hv: Variant = em.get(&"han")
	if not (hmv is PackedFloat32Array and hv is PackedFloat32Array) or slot >= (hv as PackedFloat32Array).size():
		return
	var hm: float = (hmv as PackedFloat32Array)[slot]
	if hm <= 0.0:
		return
	var k: int = clampi(int(floorf((1.0 - (hv as PackedFloat32Array)[slot] / hm) * float(_boss_segs) + 0.001)), 0, _boss_segs)
	if k > int(_run.get("boss_knots", 0)):
		_run["boss_knots"] = k


func _on_settlement_progress(_route: StringName, _done: int, _total: int, progress: float) -> void:
	if _run_live:
		_run["geodum_p"] = clampf(progress, 0.0, 1.0)


func _on_run_ended(result: Dictionary) -> void:
	if not _run_live:
		return
	var kind: String = String(result.get("meta_result", ""))
	var ending: String = String(result.get("ending", ""))
	if kind == "" and (ending == "timeout" or ending == "hard_cap"):
		kind = MetaRules.R_TIMEOUT_SAJA       # 23:00 저승사자가 판을 거둠 — 사망이 아니다(결과 화면 '사자가 판을 거두었다')
	if kind == "":
		if bool(result.get("victory", false)):
			var n: float = float(_run.get("n_final", -1.0))
			if n < 0.0:
				n = float(result.get("haewon_ratio", 0.0))
			kind = MetaRules.R_CLEAR_BOW if n >= 0.5 else MetaRules.R_CLEAR_SAL
		else:
			kind = MetaRules.R_DEATH
	settle_run(kind, result)


## 물리기(일시정지 → 타이틀) 또는 앱 종료: run_ended 없이 런 씬이 빠지면 ABANDON 으로 정산(DEATH 와 같은 환산).
func _on_run_root_exiting() -> void:
	if not _run_live:
		return
	var total: int = Game.kills_toechi + Game.kills_haewon
	settle_run(MetaRules.R_ABANDON, {"victory": false, "time_sec": Game.time_sec(), "char_id": Game.char_id,
		"toechi": Game.kills_toechi, "haewon": Game.kills_haewon, "neok": Game.cur_neok, "level": Game.level,
		"haewon_ratio": float(Game.kills_haewon) / float(total) if total > 0 else 0.0, "salgi": Game.salgi})


## 정산 트랜잭션(멱등, 19.6). result: Events.run_ended 의 사전. 반환: 정산 요약(last_settlement).
func settle_run(kind: String, result: Dictionary) -> Dictionary:
	_run_live = false
	var uid: String = String(_run.get("uid", "r-manual-" + _new_id().substr(0, 6)))
	if (profile["settled_run_uids"] as Array).has(uid):
		return last_settlement
	var run: Dictionary = _run.duplicate()
	run["result"] = kind
	run["haewon"] = int(result.get("haewon", 0))
	run["toechi"] = int(result.get("toechi", 0))
	run["cheondo_neok"] = int(result.get("neok", 0))
	run["siju"] = Game.stat(&"stat_siju", 1.0)
	var calc: Dictionary = MetaRules.compute_settlement(run)
	var g: int = int(calc["G"])
	var b: int = int(calc["B"])
	var before_runs: int = runs_done()
	var notices: Array[String] = []
	var clear: bool = kind == MetaRules.R_CLEAR_BOW or kind == MetaRules.R_CLEAR_SAL
	var was_open: Dictionary = {}
	for key: String in ["danjang_open_after_runs", "singirok_open_after_runs", "uiroe_open_after_runs"]:
		was_open[key] = facility_open(key)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(uid)
	var acc: Dictionary = {"pg": 0, "tb": 0}       # 람다는 값 캡처 — 결과는 사전으로 받는다
	var uiroe_id: String = String(run.get("uiroe", ""))
	var x2: Dictionary = MetaRules.uiroe_record_x2(uiroe_id) if clear and uiroe_id != "" else {}
	var cacc: Dictionary = {"sayeon": [], "sayeon_ids": [], "byeoksa": [], "inyeon": [], "uiroe": false, "jinogi": false}   # 정산 화면 한지 카드 재료
	# 결과 화면 진행 막대(design/19 §7): 넘긴 시험 수·큰 귀신·이전 최고 기록(이번 판 넣기 전)
	var n_trials: int = int(run.get("trial_gaho", 0)) + int(run.get("trial_wieom", 0)) + int(run.get("trial_gaho_half", 0)) + int(run.get("trial_wieom_half", 0))
	var n_mboss: int = int(run.get("mboss_haewon", 0)) + int(run.get("mboss_toechi", 0))
	var best_before: int = best_time_s()
	var sy_pick: Dictionary = _pick_sayeon_line(uid)
	var ok: bool = _transact(func() -> void:
		var cn: Dictionary = profile["counters"]
		cn["cnt_runs"] = int(cn.get("cnt_runs", 0)) + 1
		if clear:
			cn["cnt_clears"] = int(cn.get("cnt_clears", 0)) + 1
		cn["cnt_haewon_total"] = int(cn.get("cnt_haewon_total", 0)) + int(run["haewon"])
		cn["cnt_toechi_total"] = int(cn.get("cnt_toechi_total", 0)) + int(run["toechi"])
		cn["cnt_bingui_wieom_total"] = int(cn.get("cnt_bingui_wieom_total", 0)) + int(run["trial_wieom"])
		cn["cnt_box_gilhyung_opened"] = int(cn.get("cnt_box_gilhyung_opened", 0)) + int(run["elite_toechi"]) + int(run["mboss_toechi"]) + int(run["boss_toechi"])
		cn["cnt_gildakkeum"] = int(cn.get("cnt_gildakkeum", 0)) + int(run["rings"])
		cn["cnt_wongwi_return"] = int(cn.get("cnt_wongwi_return", 0)) + int(run["wongwi"])
		# 넋기록
		var res: Vector2i = _apply_singirok(x2, notices, cacc)
		acc["pg"] = res.x
		acc["tb"] = res.y
		_wallet_add(MetaRules.CUR_G, g + res.x)
		_wallet_add(MetaRules.CUR_B, b + res.y)
		# 무당 인연(조건 충족 → 내림굿 가능)
		for c: Variant in MetaRules.char_defs():
			var cid: String = String((c as Dictionary)["id"])
			if MetaRules.char_unlocked(profile, cid) or (profile["unlocks"]["char_ready"] as Array).has(cid):
				continue
			if MetaRules.char_ready(profile, cid):
				(profile["unlocks"]["char_ready"] as Array).append(cid)
				var cnm: String = String(MetaRules.char_def(cid).get("name_ko", cid))
				(cacc["inyeon"] as Array).append(cnm)
				notices.append("새 무당 %s%s 인연이 닿았습니다 — '무당'에서 열 수 있습니다" % [cnm, MetaRules.josa(cnm, "과", "와")])
		# 의뢰
		_settle_uiroe(uiroe_id, bool(calc["uiroe_done"]), rng, notices)
		cacc["uiroe"] = bool(calc["uiroe_done"]) and uiroe_id != ""
		# 고정 의뢰 '어머니(은실)를 보내는 진오기굿'(design/19 §7): 첫 클리어에 마침 — 보상은 사연 카드
		if clear and not bool((profile["flags"] as Dictionary).get(JINOGI_FLAG, false)):
			(profile["flags"] as Dictionary)[JINOGI_FLAG] = true
			cacc["jinogi"] = true
		# 기록
		(profile["flags"] as Dictionary)["tutorial_done"] = true
		profile["active_run_uid"] = null
		var su: Array = profile["settled_run_uids"]
		su.append(uid)
		while su.size() > SETTLED_MAX:
			su.pop_front()
		profile["playtime_s"] = int(profile.get("playtime_s", 0)) + int(float(result.get("time_sec", 0.0)))
		var hist: Array = profile["run_history"]
		hist.append({"run_uid": uid, "char": String(run.get("char", "")), "result": kind,
			"time_s": int(float(result.get("time_sec", 0.0))), "haewon": int(run["haewon"]), "toechi": int(run["toechi"]),
			"neok": int(calc["neok_w"]), "yeopjeon": int(calc["yeop_w"]), "gongdeok_gain": g + res.x, "bokjeon_gain": b + res.y,
			"uiroe": uiroe_id, "boss_knots": int(run.get("boss_knots", 0)), "stage": "stage_guksadang", "mode": "mode_pyojun", "dan": 0,
			"trials": n_trials, "mboss": n_mboss})
		while hist.size() > HISTORY_MAX:
			hist.pop_front())
	var piece_g: int = int(acc["pg"]) if ok else 0
	var tier_b: int = int(acc["tb"]) if ok else 0
	var opened: Array[String] = []
	for key: String in was_open:
		if not bool(was_open[key]) and facility_open(key):
			opened.append(key)
			match key:
				"danjang_open_after_runs": notices.append("신당 강화가 열렸습니다 — 공덕과 엽전으로 다음 판을 더 강하게")
				"singirok_open_after_runs": notices.append("도감이 열렸습니다 — 풀어 준 넋과 처치한 귀신이 여기 적힙니다")
				"uiroe_open_after_runs": notices.append("특별 의뢰가 들어왔습니다 — '특별 의뢰'에서 하나 골라 받을 수 있습니다")
	last_settlement = {"run_uid": uid, "result": kind, "saved": ok, "error": "" if ok else last_error,
		"G": g, "B": b, "piece_G": piece_g, "tier_B": tier_b, "neok_w": int(calc["neok_w"]), "yeop_w": int(calc["yeop_w"]),
		"N": float(calc["N"]), "lines": calc["lines"], "notices": notices, "uiroe": uiroe_id,
		"uiroe_done": bool(calc["uiroe_done"]), "uiroe_thanks": String(MetaRules.econ("sindang_v1.uiroe_thanks_ko", "")) if bool(calc["uiroe_done"]) else "",
		"first_run": before_runs == 0, "wallet_G": wallet(MetaRules.CUR_G), "wallet_B": wallet(MetaRules.CUR_B),
		"cards": _build_cards(cacc if ok else {}, opened, piece_g, tier_b),
		"time_s": int(float(result.get("time_sec", 0.0))), "trials": n_trials, "mboss": n_mboss, "best_before": best_before,
		"sayeon_line": _sayeon_for_result(cacc if ok else {}, sy_pick), "jinogi_done": bool(cacc.get("jinogi", false))}
	if ok:
		_rotate_auto_backup()
		_emit_wallet()
	pending_notices.clear()
	for n: String in notices:
		pending_notices.append(n)
	print("[meta] settled uid=%s result=%s haewon=%d toechi=%d neok_w=%d yeop_w=%d G=%d(+%d) B=%d(+%d) N=%.2f wallet=%d/%d saved=%s notices=%d boss_knots=%d" % [
		uid, kind, int(run["haewon"]), int(run["toechi"]), int(calc["neok_w"]), int(calc["yeop_w"]), g, piece_g, b, tier_b,
		float(calc["N"]), wallet(MetaRules.CUR_G), wallet(MetaRules.CUR_B), ok, notices.size(), int(run.get("boss_knots", 0))])
	settled.emit(last_settlement)
	_run = {}
	return last_settlement


## 정산 화면 3막 한지 카드: 같은 종류는 한 장으로 묶는다(첫 판엔 사연이 종마다 나와 화면을 덮지 않게).
## [{kind, seal, title, body, reward}] — kind: sayeon | byeoksa | inyeon | open | uiroe. 최대 4장(중요한 순).
## 낙관(seal)은 한글 한 글자(design/19 §4.7: 화면 한자 삭제). 사연 카드는 받은 조각 첫 문장을 인용한다.
func _build_cards(cacc: Dictionary, opened: Array[String], piece_g: int, tier_b: int) -> Array:
	var cards: Array = []
	if bool(cacc.get("jinogi", false)):
		cards.append({"kind": "uiroe", "seal": "넋", "title": "진오기굿을 마쳤다",
			"body": "\"서리야, 풀어라. 다 풀고 나면… 나도.\" — 어머니의 목소리가 한 번 더 들렸다", "reward": ""})
	for nm: Variant in cacc.get("inyeon", []):
		cards.append({"kind": "inyeon", "seal": "무", "title": "새 무당 인연", "body": "%s%s 인연이 닿았다 — 신당 '무당'에서 연다" % [String(nm), MetaRules.josa(String(nm), "과", "와")], "reward": ""})
	for key: String in opened:
		match key:
			"danjang_open_after_runs": cards.append({"kind": "open", "seal": "강", "title": "신당 강화", "body": "열렸다 — 공덕·엽전으로 다음 판을 더 강하게", "reward": ""})
			"singirok_open_after_runs": cards.append({"kind": "open", "seal": "도", "title": "도감", "body": "열렸다 — 풀어 준 넋의 사연이 여기 적힌다", "reward": ""})
			"uiroe_open_after_runs": cards.append({"kind": "open", "seal": "의", "title": "특별 의뢰", "body": "들어왔다 — 신당에서 사연을 골라 받는다", "reward": ""})
	if bool(cacc.get("uiroe", false)):
		cards.append({"kind": "uiroe", "seal": "의", "title": "의뢰를 마쳤다", "body": String(MetaRules.econ("sindang_v1.uiroe_thanks_ko", "재가집이 고개를 숙였다")), "reward": ""})
	var sy: Array = cacc.get("sayeon", [])
	if not sy.is_empty():
		var body: String = _name_list(sy) + ("의 사연을 들었다" if sy.size() == 1 else " — 사연을 들었다")
		for e: Variant in cacc.get("sayeon_ids", []):
			if not (e is Array):
				continue
			var q: String = sayeon_piece_quote(String((e as Array)[0]), int((e as Array)[1]))
			if q != "":
				body = "「%s」 — %s" % [q, sayeon_who(String((e as Array)[0]))]
				break
		cards.append({"kind": "sayeon", "seal": "넋", "title": "사연" + (" ×%d" % sy.size() if sy.size() > 1 else ""),
			"body": body, "reward": "공덕 +" + _comma(piece_g) if piece_g > 0 else ""})
	var bs: Array = cacc.get("byeoksa", [])
	if not bs.is_empty():
		cards.append({"kind": "byeoksa", "seal": "처", "title": "처치 기록" + (" ×%d" % bs.size() if bs.size() > 1 else ""),
			"body": _name_list(bs) + ("에 올랐다" if bs.size() == 1 else " — 단계가 올랐다"), "reward": "엽전 +" + _comma(tier_b) if tier_b > 0 else ""})
	if cards.size() > 4:
		cards.resize(4)
	return cards


static func _name_list(names: Array) -> String:
	var shown: PackedStringArray = PackedStringArray()
	for i in mini(2, names.size()):
		shown.append(String(names[i]))
	var s: String = "·".join(shown)
	if names.size() > 2:
		s += " 외 %d" % (names.size() - 2)
	return s


## 종별 해원·퇴치 누계, 사연 조각(첫 해원·누적 150), 벽사록 단계. 반환 (조각 공덕, 단계 복전).
## cacc(선택): 정산 화면 카드용으로 사연 조각·벽사 단계가 오른 종 이름을 모은다.
func _apply_singirok(x2: Dictionary, notices: Array[String], cacc: Dictionary = {}) -> Vector2i:
	var hr: Dictionary = profile["singirok"]["haewonrok"]
	var br: Dictionary = profile["singirok"]["byeoksarok"]
	var piece_reward: int = MetaRules.price(MetaRules.num("singirok.haewonrok.piece_reward_G", 200.0))
	var tier_reward: int = MetaRules.price(MetaRules.num("singirok.byeoksarok.tier_reward_B", 200.0))
	var gsum: int = 0
	var bsum: int = 0
	for sp: StringName in _sp_haewon:
		var key: String = String(sp)
		var n: int = int(_sp_haewon[sp]) * (2 if x2.has(key) else 1)
		if not (hr.get(key) is Dictionary):
			hr[key] = {"pieces": [], "haewon": 0}
		var e: Dictionary = hr[key]
		e["haewon"] = int(e.get("haewon", 0)) + n
		var pieces: Array = e.get("pieces", [])
		e["pieces"] = pieces
		if not pieces.has(1):
			pieces.append(1)
			gsum += piece_reward
			notices.append("사연: %s의 첫 사연을 들었습니다" % MetaRules.enemy_ko(key))
			if cacc.has("sayeon"):
				(cacc["sayeon"] as Array).append(MetaRules.enemy_ko(key))
				(cacc["sayeon_ids"] as Array).append([key, 0])
		if int(e["haewon"]) >= 150 and not pieces.has(2):
			pieces.append(2)
			gsum += piece_reward
			notices.append("사연: %s의 두 번째 사연" % MetaRules.enemy_ko(key))
			if cacc.has("sayeon") and not (cacc["sayeon"] as Array).has(MetaRules.enemy_ko(key)):
				(cacc["sayeon"] as Array).append(MetaRules.enemy_ko(key))
			if cacc.has("sayeon_ids"):
				(cacc["sayeon_ids"] as Array).append([key, 1])
	for sp: StringName in _sp_toechi:
		var key: String = String(sp)
		var n: int = int(_sp_toechi[sp]) * (2 if x2.has(key) else 1)
		if not (br.get(key) is Dictionary):
			br[key] = {"toechi": 0, "tier": 0}
		var e: Dictionary = br[key]
		e["toechi"] = int(e.get("toechi", 0)) + n
		var grp: String = MetaRules.tier_group(StringName(String(Data.enemy(key).get("tier", "common"))))
		var t: int = MetaRules.byeoksa_tier(grp, int(e["toechi"]))
		if t > int(e.get("tier", 0)):
			bsum += tier_reward * (t - int(e.get("tier", 0)))
			notices.append("처치 기록: %s %d단계" % [MetaRules.enemy_ko(key), t])
			if cacc.has("byeoksa"):
				(cacc["byeoksa"] as Array).append("%s %d단계" % [MetaRules.enemy_ko(key), t])
			e["tier"] = t
	return Vector2i(gsum, bsum)


func _settle_uiroe(accepted: String, done: bool, rng: RandomNumberGenerator, notices: Array[String]) -> void:
	var u: Dictionary = profile["uiroe"]
	var off: Array = u["offered"]
	var age: Array = u["offered_age_runs"]
	if accepted != "":
		var i: int = off.find(accepted)
		if i >= 0:
			off.remove_at(i)
			age.remove_at(i)
		if done:
			(u["completed"] as Array).append(accepted)
			var cn: Dictionary = profile["counters"]
			cn["cnt_uiroe_done"] = int(cn.get("cnt_uiroe_done", 0)) + 1
			notices.append("특별 의뢰를 마쳤습니다 — \"%s\"" % String(MetaRules.econ("sindang_v1.uiroe_thanks_ko", "")))
		u["accepted"] = null
	# 받지 않은 의뢰는 3런 동안 유지
	var keep: int = 3
	for i in range(off.size() - 1, -1, -1):
		age[i] = int(age[i]) + 1
		if int(age[i]) >= keep:
			off.remove_at(i)
			age.remove_at(i)
	_uiroe_refill(rng)


## 정산 화면(ui/result.gd)용 표시 묶음. 정산 전이면 빈 사전.
## {ok, first_run, gain_G, gain_B, wallet_G, wallet_B,
##  rows: [{label, value, gold:bool, from, from_n, to, to_n}] — "풀어 준 넋 420 → 공덕 +482" 식 환산 줄(넋·엽전 두 줄은 늘 있다),
##  mults: Array[String] — 배율 줄("어울림 ×1.15" 등), notices: Array[String] — 해금·사연 등,
##  cards: [{kind, seal, title, body, reward}] — 3막 한지 카드(묶음, 최대 4장),
##  progress: {time_s, trials, mboss, boss, best_s, new_best} — 진행 막대(design/19 §7),
##  affordable: [{kind, id, name, effect, cost, cur, cur_ko}] — 지금 신당에서 살 수 있는 것(싼 순),
##  upgrades_n: int — 살 수 있는 신당 강화 칸 수, nearest: {name, effect, need, cur_ko} — 없으면 가장 가까운 것,
##  next_goal: {id, short, long}, sayeon: {quote, who, species} — 사연 한 줄}
## 화면 재화 이름: 복전 → 엽전(design/19 §2.5). 세이브 키는 그대로.
func settlement_view() -> Dictionary:
	var s: Dictionary = last_settlement
	if s.is_empty():
		return {}
	var g: int = int(s.get("G", 0))
	var b: int = int(s.get("B", 0))
	var pg: int = int(s.get("piece_G", 0))
	var tb: int = int(s.get("tier_B", 0))
	var rows: Array[Dictionary] = []
	# from/to/from_n/to_n: 정산 화면 카운트업용 숫자(label/value 는 옛 표시 호환).
	var nw: int = int(s.get("neok_w", 0))
	var yw: int = int(s.get("yeop_w", 0))
	rows.append({"label": "풀어 준 넋 %s → 공덕" % _comma(nw), "value": "+" + _comma(g), "gold": false,
		"from": "풀어 준 넋", "from_n": nw, "to": "공덕", "to_n": g})
	rows.append({"label": "모은 엽전 %s → 엽전" % _comma(yw), "value": "+" + _comma(b), "gold": true,
		"from": "모은 엽전", "from_n": yw, "to": "엽전", "to_n": b})
	if pg > 0:
		rows.append({"label": "사연", "value": "공덕 +" + _comma(pg), "gold": false,
			"from": "사연", "from_n": -1, "to": "공덕", "to_n": pg})
	if tb > 0:
		rows.append({"label": "처치 기록", "value": "엽전 +" + _comma(tb), "gold": true,
			"from": "처치 기록", "from_n": -1, "to": "엽전", "to_n": tb})
	var mults: Array[String] = []
	for l: Variant in s.get("lines", []):
		mults.append(String(l))
	var notices: Array[String] = []
	for n: Variant in s.get("notices", []):
		notices.append(String(n))
	var ts: int = int(s.get("time_s", 0))
	var kind: String = String(s.get("result", ""))
	var best_before: int = int(s.get("best_before", 0))
	var aff: Array[Dictionary] = affordable()
	var up_n: int = 0
	for a: Dictionary in aff:
		if String(a["kind"]) == "danjang":
			up_n += 1
	return {"ok": bool(s.get("saved", false)), "first_run": bool(s.get("first_run", false)),
		"gain_G": g + pg, "gain_B": b + tb, "wallet_G": int(s.get("wallet_G", 0)), "wallet_B": int(s.get("wallet_B", 0)),
		"rows": rows, "mults": mults, "notices": notices, "error": String(s.get("error", "")),
		"cards": (s.get("cards", []) as Array).duplicate(true) if s.get("cards") is Array else [],
		"progress": {"time_s": ts, "trials": int(s.get("trials", 0)), "mboss": int(s.get("mboss", 0)) > 0,
			"boss": kind == MetaRules.R_CLEAR_BOW or kind == MetaRules.R_CLEAR_SAL, "result": kind,
			"best_s": maxi(best_before, ts), "new_best": ts > best_before and best_before > 0},
		"affordable": aff, "upgrades_n": up_n, "nearest": nearest_purchase(), "next_goal": next_goal(),
		"sayeon": (s.get("sayeon_line", {}) as Dictionary).duplicate() if s.get("sayeon_line") is Dictionary else {}}


# ═══ 메타 루프 표시(design/19 §7) — 결과 화면·신당·HUD(목표 줄) 공용 ═══════════════
const JINOGI_FLAG: String = "jinogi_done"
const JINOGI_TITLE: String = "어머니(은실)를 보내는 진오기굿"
## 다음 목표 사다리 시각(초). 시험 3:00·6:30, 큰 귀신 10:00, 신령 모두 내림 18:00, 역려 20:00.
const LADDER_T: Dictionary = {"trial1": 180, "trial2": 390, "mboss": 600, "hapil": 1080, "boss": 1200}


## 지난 판 중 가장 오래 버틴 시각(초). 기록이 없으면 0.
func best_time_s() -> int:
	var best: int = 0
	var hist: Variant = profile.get("run_history", [])
	if hist is Array:
		for e: Variant in hist:
			if e is Dictionary:
				best = maxi(best, int((e as Dictionary).get("time_s", 0)))
	return best


## 사다리 단계별 달성 여부(지난 판 기록 전부). 옛 기록(trials·mboss 키 없음)은 버틴 시각으로 판정한다.
func _ladder_done() -> Dictionary:
	var d: Dictionary = {"trial1": false, "trial2": false, "mboss": false, "hapil": false, "boss": false, "bow": false, "sal": false}
	var hist: Variant = profile.get("run_history", [])
	if not (hist is Array):
		return d
	for e: Variant in hist:
		if not (e is Dictionary):
			continue
		var h: Dictionary = e
		var t: int = int(h.get("time_s", 0))
		var res: String = String(h.get("result", ""))
		var tr: int = int(h["trials"]) if h.has("trials") else (1 if t >= 225 else 0) + (1 if t >= 435 else 0)
		if tr >= 1:
			d["trial1"] = true
		if tr >= 2:
			d["trial2"] = true
		if int(h.get("mboss", 1 if t >= 720 else 0)) > 0:
			d["mboss"] = true
		if t >= int(LADDER_T["hapil"]):
			d["hapil"] = true
		if res == MetaRules.R_CLEAR_BOW or res == MetaRules.R_CLEAR_SAL:
			d["boss"] = true
			d["hapil"] = true
		if res == MetaRules.R_CLEAR_BOW:
			d["bow"] = true
		if res == MetaRules.R_CLEAR_SAL:
			d["sal"] = true
	return d


## 다음 목표 하나(최고 기록 사다리에서 처음 못 넘은 것). {id, short, long}
## short 는 HUD 목표 줄용(22자 이내), long 은 결과 화면·신당 '출발' 패널용.
func next_goal() -> Dictionary:
	var d: Dictionary = _ladder_done()
	if not bool(d["trial1"]):
		return {"id": "trial1", "short": "03:00 첫 신령의 시험 넘기기", "tiny": "03:00 첫 시험", "long": "03:00 첫 신령의 시험 넘기기 — 빛나는 원으로 들어가 싸우거나 모시기"}
	if not bool(d["trial2"]):
		return {"id": "trial2", "short": "06:30 두 번째 시험 넘기기", "tiny": "06:30 둘째 시험", "long": "06:30 두 번째 신령의 시험을 넘기기"}
	if not bool(d["mboss"]):
		return {"id": "mboss", "short": "10:00 큰 귀신 이기기", "tiny": "10:00 큰 귀신", "long": "10:00 큰 귀신을 쓰러뜨리거나 풀어 주기"}
	if not bool(d["hapil"]):
		return {"id": "hapil", "short": "18:00 신령 모두 내림까지", "tiny": "18:00 신령 내림", "long": "18:00까지 버텨 모신 신령을 모두 내려오게 하기"}
	if not bool(d["boss"]):
		return {"id": "boss", "short": "20:00 역려를 보내기", "tiny": "20:00 역려 보내기", "long": "20:00 마지막에 오는 역병 귀신 역려를 보내기"}
	if not bool(d["bow"]):
		return {"id": "bow", "short": "역려를 풀어 보내기", "tiny": "역려 풀어 보내기", "long": "많이 풀어 주어(절반 넘게) 역려를 한의 얼굴로 불러 풀어 보내기"}
	if not bool(d["sal"]):
		return {"id": "sal", "short": "역려를 베어 쓰러뜨리기", "tiny": "역려 베어 보내기", "long": "많이 처치해(절반 넘게) 역려를 살의 얼굴로 불러 쓰러뜨리기"}
	# 무당 인연(가장 가까운 것)
	var best_cid: String = ""
	var best_k: float = -1.0
	for c: Variant in MetaRules.char_defs():
		var cid: String = String((c as Dictionary).get("id", ""))
		if MetaRules.char_unlocked(profile, cid):
			continue
		var pr: Vector2i = MetaRules.char_progress(profile, cid)
		var k: float = float(pr.x) / float(maxi(1, pr.y))
		if k > best_k:
			best_k = k
			best_cid = cid
	if best_cid != "":
		var pr2: Vector2i = MetaRules.char_progress(profile, best_cid)
		var nm: String = String(MetaRules.char_def(best_cid).get("name_ko", best_cid))
		return {"id": "char", "short": "새 무당: %s (%d/%d)" % [nm, pr2.x, pr2.y],
			"long": "새 무당 %s%s 인연 맺기 — %s (%d/%d)" % [nm, MetaRules.josa(nm, "과", "와"), _cond_text(best_cid), pr2.x, pr2.y]}
	var np: Dictionary = nearest_purchase(true)
	if not np.is_empty():
		return {"id": "shop", "short": "%s 갖추기" % String(np["name"]), "long": "%s 갖추기 — %s %s 남음" % [String(np["name"]), String(np["cur_ko"]), _comma(int(np["need"]))]}
	return {"id": "more", "short": "더 많이 풀어 주기", "long": "더 많은 넋을 풀어 도감을 채우기"}


func _cond_text(cid: String) -> String:
	var t: String = String(MetaRules.char_condition(cid).get("text", ""))
	var paren: int = t.find(" (v1")
	return t.left(paren) if paren >= 0 else t


## HUD 목표 줄·이야기 카드용 짧은 한 줄(22자 이내). 예: "다음 목표: 06:30 두 번째 시험 넘기기" 대신 짧은 형만.
func next_goal_line() -> String:
	return String(next_goal().get("short", ""))


## 아주 짧은 형(신당 메뉴 부제 등 좁은 칸용 — 시각·대상만). 없으면 short.
func next_goal_tiny() -> String:
	var g: Dictionary = next_goal()
	return String(g.get("tiny", g.get("short", "")))


## 다음 판 시작 때 '신당의 힘' 항목(쉬운 말). 예: ["체력 +10", "넋 동무 머묾 +3초"]. 강화가 없으면 빈 배열.
## HUD 는 "신당의 힘: " + " · ".join(앞 2개) 로 띄운다(run_start_bonus_text() 가 그 완성형).
func run_start_bonus_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var bonus: Dictionary = MetaRules.danjang_stat_bonus(profile)
	for it: Variant in MetaRules.danjang_items():
		var st: String = String((it as Dictionary).get("stat", ""))
		if not bonus.has(StringName(st)):
			continue
		var line: String = MetaRules.stat_easy(st, float(bonus[StringName(st)]))
		if line != "" and not out.has(line):
			out.append(line)
	return out


## "신당의 힘: 체력 +10 · 넋 동무 머묾 +3초 외 2" (강화가 없으면 "").
func run_start_bonus_text(max_items: int = 2) -> String:
	var ls: PackedStringArray = run_start_bonus_lines()
	if ls.is_empty():
		return ""
	var shown: PackedStringArray = ls.slice(0, maxi(1, max_items))
	return "신당의 힘: " + " · ".join(shown) + (" 외 %d" % (ls.size() - shown.size()) if ls.size() > shown.size() else "")


## 이번 판 의뢰 한 줄(이야기 카드 둘째 줄). 받은 특별 의뢰가 있으면 그 사연, 없으면 첫 클리어 전까지 고정 의뢰.
## 예: "의뢰: 어머니(은실)를 보내는 진오기굿". 둘 다 없으면 "".
func current_request_line() -> String:
	var a: String = uiroe_accepted()
	if a != "":
		return "의뢰: " + String(MetaRules.uiroe_def(a).get("sayeon_ko", a))
	if not flag(JINOGI_FLAG):
		return "의뢰: " + JINOGI_TITLE
	return ""


## 지금 지갑으로 살 수 있는 것(신당 강화 → 무기 → 새 무당), 칸마다 싼 순. [{kind, id, name, effect, cost, cur, cur_ko}]
func affordable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if facility_open("danjang_open_after_runs"):
		var dj: Array[Dictionary] = []
		for it: Variant in MetaRules.danjang_items():
			var id: String = String((it as Dictionary).get("id", ""))
			var cost: int = MetaRules.danjang_next_cost(profile, id)
			var cur: StringName = MetaRules.danjang_currency(id)
			if cost >= 0 and wallet(cur) >= cost:
				dj.append({"kind": "danjang", "id": id, "name": String((it as Dictionary).get("name_ko", id)),
					"effect": MetaRules.danjang_effect_easy(id), "cost": cost, "cur": cur, "cur_ko": MetaRules.currency_name(cur)})
		dj.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["cost"]) < int(y["cost"]))
		out.append_array(dj)
	if facility_open("weapon_offering_open_after_runs"):
		var ws: Array[Dictionary] = []
		for w: Variant in MetaRules.weapon_defs():
			var wid: String = String((w as Dictionary).get("id", ""))
			if not Data.weapon(wid).is_empty() and not Data.is_v1(Data.weapon(wid)):
				continue
			if MetaRules.weapon_state(profile, wid) != "buyable":
				continue
			var wc: int = MetaRules.weapon_cost(wid)
			var wcur: StringName = MetaRules.weapon_currency(wid)
			if wallet(wcur) >= wc:
				ws.append({"kind": "weapon", "id": wid, "name": String((w as Dictionary).get("name_ko", wid)),
					"effect": "새 무기", "cost": wc, "cur": wcur, "cur_ko": MetaRules.currency_name(wcur)})
		ws.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["cost"]) < int(y["cost"]))
		out.append_array(ws)
	for c: Variant in MetaRules.char_defs():
		var cid: String = String((c as Dictionary).get("id", ""))
		if MetaRules.char_unlocked(profile, cid) or not MetaRules.char_ready(profile, cid):
			continue
		var cc: int = MetaRules.char_cost(cid)
		if wallet(MetaRules.CUR_G) >= cc:
			out.append({"kind": "char", "id": cid, "name": String((c as Dictionary).get("name_ko", cid)),
				"effect": "새 무당", "cost": cc, "cur": MetaRules.CUR_G, "cur_ko": MetaRules.currency_name(MetaRules.CUR_G)})
	return out


## 아직 못 사는 것 중 가장 적게 모자란 신당 강화(any=true 면 무기도). {name, effect, need, cur_ko} 또는 빈 사전.
func nearest_purchase(any: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var best_need: int = 0x7fffffff
	for it: Variant in MetaRules.danjang_items():
		var id: String = String((it as Dictionary).get("id", ""))
		var cost: int = MetaRules.danjang_next_cost(profile, id)
		var cur: StringName = MetaRules.danjang_currency(id)
		var need: int = cost - wallet(cur)
		if cost >= 0 and need > 0 and need < best_need:
			best_need = need
			best = {"name": String((it as Dictionary).get("name_ko", id)), "effect": MetaRules.danjang_effect_easy(id),
				"need": need, "cur_ko": MetaRules.currency_name(cur)}
	if any or best.is_empty():
		for w: Variant in MetaRules.weapon_defs():
			var wid: String = String((w as Dictionary).get("id", ""))
			if MetaRules.weapon_state(profile, wid) != "buyable":
				continue
			var wcur: StringName = MetaRules.weapon_currency(wid)
			var need2: int = MetaRules.weapon_cost(wid) - wallet(wcur)
			if need2 > 0 and need2 < best_need:
				best_need = need2
				best = {"name": String((w as Dictionary).get("name_ko", wid)), "effect": "새 무기", "need": need2, "cur_ko": MetaRules.currency_name(wcur)}
	return best


# ─── 사연(narrative/sayeon_examples.json) ───

func _sayeon_entry(species: String) -> Dictionary:
	var es: Variant = Data.get_value("narrative/sayeon_examples", "entries", [])
	if es is Array:
		for e: Variant in es:
			if e is Dictionary and String((e as Dictionary).get("id", "")) == species:
				return e
	return {}


## 사연 조각 idx(0..2)의 첫 문장(짧으면 다음 문장까지, 32자 안). 없으면 "".
func sayeon_piece_quote(species: String, idx: int) -> String:
	var h: Variant = _sayeon_entry(species).get("haewon", {})
	if not (h is Dictionary):
		return ""
	var ps: Variant = (h as Dictionary).get("pieces", [])
	if not (ps is Array) or idx < 0 or idx >= (ps as Array).size():
		return ""
	return first_sentence(String((ps as Array)[idx]))


static func first_sentence(t: String, max_len: int = 32) -> String:
	var out: String = ""
	var rest: String = t.strip_edges()
	while rest != "":
		var cut: int = -1
		for mark: String in [". ", "? ", "! ", "… "]:
			var k: int = rest.find(mark)
			if k >= 0 and (cut < 0 or k < cut):
				cut = k
		var sent: String = rest if cut < 0 else rest.left(cut + 1)
		if out != "" and (out + " " + sent).length() > max_len:
			if out.length() < 10:
				out = (out + " " + sent).left(max_len).strip_edges() + "…"
			break
		out = sent if out == "" else out + " " + sent
		rest = "" if cut < 0 else rest.substr(cut + 2).strip_edges()
		if out.length() >= 10:
			break
	if out.length() > max_len + 8:
		out = out.left(max_len) + "…"
	return out


## "순덕(달걀귀신)" — 대표 이름이 없으면 종 이름만.
func sayeon_who(species: String) -> String:
	var e: Dictionary = _sayeon_entry(species)
	var nm: String = MetaRules.enemy_ko(species)
	var rep_v: Variant = (e.get("haewon", {}) as Dictionary).get("representative", "") if e.get("haewon") is Dictionary else ""
	var rep_s: String = String(rep_v)
	if rep_s == "" or rep_s.begins_with("무명") or rep_s.length() > 6:
		return nm
	return "%s(%s)" % [rep_s, nm]


## 도감 칸 사연 카드: 받은 조각 문장들(최대 3) + 넋두리 한 줄. {who, pieces: Array[String], neokduri}
func sayeon_card(species: String) -> Dictionary:
	var e: Dictionary = _sayeon_entry(species)
	var got: Variant = get_value("singirok.haewonrok.%s.pieces" % species, [])
	var out: Array[String] = []
	var h: Variant = e.get("haewon", {})
	if h is Dictionary and (h as Dictionary).get("pieces") is Array and got is Array:
		var ps: Array = (h as Dictionary)["pieces"]
		for i in ps.size():
			if (got as Array).has(i + 1) or (got as Array).has(float(i + 1)):
				out.append(String(ps[i]))
	var nd: Variant = e.get("neokduri", [])
	return {"who": sayeon_who(species), "pieces": out,
		"neokduri": String((nd as Array)[0]) if nd is Array and not (nd as Array).is_empty() else "", "has_entry": not e.is_empty()}


## 정산 직전(이번 판 종별 해원 집계가 살아 있을 때): 가장 많이 풀어 준 종의 넋두리 한 줄. 화면용 — 게임 난수 아님(uid 해시).
func _pick_sayeon_line(uid: String) -> Dictionary:
	var best_sp: String = ""
	var best_n: int = 0
	for sp: StringName in _sp_haewon:
		var n: int = int(_sp_haewon[sp])
		if n > best_n and not _sayeon_entry(String(sp)).is_empty():
			best_n = n
			best_sp = String(sp)
	if best_sp == "":
		return {}
	var nd: Variant = _sayeon_entry(best_sp).get("neokduri", [])
	if not (nd is Array) or (nd as Array).is_empty():
		return {}
	var line: String = String((nd as Array)[absi(hash(uid)) % (nd as Array).size()])
	return {"quote": line.trim_prefix("…").strip_edges(), "who": sayeon_who(best_sp), "species": best_sp}


## 결과 화면 사연 한 줄: 이번 판 새 사연 조각이 있으면 그 첫 문장, 없으면 넋두리.
func _sayeon_for_result(cacc: Dictionary, fallback: Dictionary) -> Dictionary:
	for e: Variant in cacc.get("sayeon_ids", []):
		if not (e is Array):
			continue
		var sp: String = String((e as Array)[0])
		var q: String = sayeon_piece_quote(sp, int((e as Array)[1]))
		if q != "":
			return {"quote": q, "who": sayeon_who(sp), "species": sp}
	return fallback


# ─── 이야기 비트(narrative/story_beats.json, requires 최소 해석기) ───
## 문법: requires = AND 목록. 'flag.<id>' | 'beat_done.<id>' | 'unlocked.<id>' | '<key> <op> <number>'
##   key: stats.deaths·stats.runs·stats.clears·record.haewon_pieces_total·counter.<id>. 모르는 키는 거짓.
## 신당(로비 v1)에서는 lobby_v1: true 인 비트만 튼다(B01·B02). ctx 는 호출자가 참으로 주는 플래그(예: first_hub_visit).

func _beat_key(key: String) -> float:
	match key:
		"stats.deaths":
			var n: int = 0
			for e: Variant in profile.get("run_history", []):
				if e is Dictionary and String((e as Dictionary).get("result", "")) == MetaRules.R_DEATH:
					n += 1
			return float(n)
		"stats.runs": return float(runs_done())
		"stats.clears": return float(MetaRules.counter(profile, "cnt_clears"))
		"record.haewon_pieces_total":
			var t: int = 0
			var hr: Variant = get_value("singirok.haewonrok", {})
			if hr is Dictionary:
				for k: Variant in hr:
					var pe: Variant = (hr as Dictionary)[k]
					if pe is Dictionary and (pe as Dictionary).get("pieces") is Array:
						t += ((pe as Dictionary)["pieces"] as Array).size()
			return float(t)
	if key.begins_with("counter."):
		return float(MetaRules.counter(profile, key.substr(8)))
	return NAN


func beat_requires_ok(reqs: Variant, ctx: Dictionary = {}) -> bool:
	if not (reqs is Array):
		return true
	for r: Variant in reqs:
		var s: String = String(r).strip_edges()
		if s.begins_with("flag."):
			var f: String = s.substr(5)
			if not (bool(ctx.get(f, false)) or flag(f)):
				return false
		elif s.begins_with("beat_done."):
			if not beat_done(s.substr(10)):
				return false
		elif s.begins_with("unlocked."):
			var u: String = s.substr(9)
			if not (MetaRules.char_unlocked(profile, u) or MetaRules.has_in(profile, "unlocks", "weapons", u)):
				return false
		else:
			var parts: PackedStringArray = s.split(" ", false)
			if parts.size() != 3 or not parts[2].is_valid_float():
				return false
			var a: float = _beat_key(parts[0])
			if is_nan(a):
				return false
			var b: float = parts[2].to_float()
			var ok: bool = false
			match parts[1]:
				">=": ok = a >= b
				">": ok = a > b
				"<=": ok = a <= b
				"<": ok = a < b
				"==": ok = is_equal_approx(a, b)
				"!=": ok = not is_equal_approx(a, b)
			if not ok:
				return false
	return true


func beat_done(id: String) -> bool:
	return flag("beat." + id)


## 신당에 들어올 때 틀 비트 하나(우선순위 높은 순, 한 번만). 없으면 빈 사전. {id, lines: [{speaker, ko}]}
func next_lobby_beat(ctx: Dictionary = {}) -> Dictionary:
	var beats: Variant = Data.get_value("narrative/story_beats", "beats", [])
	if not (beats is Array):
		return {}
	var best: Dictionary = {}
	for b: Variant in beats:
		if not (b is Dictionary):
			continue
		var bd: Dictionary = b
		if not bool(bd.get("lobby_v1", false)) or not (bd.get("lines") is Array) or (bd["lines"] as Array).is_empty():
			continue
		var bid: String = String(bd.get("id", ""))
		if bool(bd.get("once", true)) and beat_done(bid):
			continue
		if not beat_requires_ok(bd.get("requires", []), ctx):
			continue
		if best.is_empty() or int(bd.get("priority", 0)) > int(best.get("priority", 0)):
			best = bd
	return best


func mark_beat_done(id: String) -> void:
	set_flag("beat." + id, true, true)
	print("[meta] beat_done %s" % id)


## 목표 목록(achievements.json 의 goal_v1 이 있는 것만, 판정은 counters). [{id, name, goal, cur, need, done}]
func goal_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var arr: Variant = Data.get_value("achievements", "achievements", [])
	if not (arr is Array):
		return out
	for a: Variant in arr:
		if not (a is Dictionary):
			continue
		var g: Variant = (a as Dictionary).get("goal_v1", null)
		if not (g is Dictionary):
			continue
		var need: int = maxi(1, int((g as Dictionary).get("gte", 1)))
		var cur: int = mini(MetaRules.counter(profile, String((g as Dictionary).get("counter", ""))), need)
		out.append({"id": String((a as Dictionary).get("id", "")), "name": String((a as Dictionary).get("name_ko", "")),
			"goal": String((g as Dictionary).get("ko", "")), "cur": cur, "need": need, "done": cur >= need})
	return out


static func _comma(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ═══ 유틸 ═════════════════════════════════════════════════════════════

func _utc_now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


func _new_id() -> String:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.randomize()
	return "%08x-%04x-%04x-%08x" % [r.randi(), r.randi() & 0xffff, r.randi() & 0xffff, r.randi()]


## 테스트·데모: 새 프로필로 초기화(저장 포함).
func reset_profile(p: Dictionary = {}) -> void:
	profile = _repair(p.duplicate(true) if not p.is_empty() else default_profile())
	read_only = false
	save_profile()
	profile_changed.emit()
