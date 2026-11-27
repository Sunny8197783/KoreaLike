extends RefCounted
## SfxBank — SFX 정의 테이블. 소유: audio.
## 정의 = data/audio_sfx.json(sfx[]: bus·voice_cap·pitch_rand_st·vol_rand_db·quantize·loop)
##       + assets/sfx/sfx_index.json(빌드 산출 파일: <id>, <id>__v2.. 기본 테이크 / <id>__agg2..4 집계 티어 / 그 밖 __<이름> 변주).
## 누락 대체(fallback): 파일이 없는 id 는 로드 때 한 번 해석해 다른 정의 슬롯으로 별칭을 건다(런타임은 사전 조회 1회).
##   sfx_wpn_X_hit → sfx_wpn_X 의 __hit 변주 → 무구 색 계열 기본(적 sfx_wpn_sinkal_hit / 백 sfx_wpn_bangul_hit)
##   sfx_wpn_X      → 색 계열 기본 발동음(적 sfx_wpn_sinkal / 백 sfx_wpn_buchae)
##   sfx_evo_X      → audio_sfx 목록에서 바로 앞의 원무구 sfx_wpn_*   ·  sfx_union_* → sfx_wpn_janggu
##   sfx_elite_*    → sfx_elite_wongwi  ·  sfx_mboss_*/sfx_boss_* → stg_mboss_enter  ·  sfx_ui_* → sfx_ui_nav
##   sfx_pick_*     → sfx_pick_yeopjeon ·  그 밖(sfx_enm_* 등) → 무음(-1). 해석 결과는 print_verbose 로 1회 기록.

const SFX_DIR: String = "res://assets/sfx/"
const INDEX_PATH: String = "res://assets/sfx/sfx_index.json"

## 다른 모듈이 부르는 이름 ↔ 실제 정의(같은 뜻의 다른 이름). 파일 없는 id 의 1순위 대체.
const ALIAS: Dictionary = {
	"sfx_ui_jeomji_pick": "sfx_ui_card_select", "sfx_ui_move": "sfx_ui_card_hover", "sfx_ui_pause": "sfx_ui_pause_in",
	"sfx_ui_result": "sfx_ui_settle_total", "sfx_ui_gongsu_show": "sfx_ui_card_hover__white",
	"sfx_ui_slider_tick": "sfx_ui_settle_tick", "sfx_ui_singirok_page": "sfx_ui_card_hover",
	"sfx_ui_bongheon": "sfx_ui_unlock", "sfx_ui_daejanggan": "sfx_ui_unlock", "sfx_ui_neokduri_show": "sfx_ui_jeomji_open",
	"sfx_union_reveal": "sfx_evo_reveal", "sfx_sys_sal_purify": "sfx_sys_cheondo", "sfx_sys_sal_merge": "sfx_sys_pullil_enter",
	"sfx_trl_gongmyeong": "sfx_trl_confirm_ring", "sfx_evt_jakdu_descend": "stg_mboss_enter",
	"sfx_plr_lowhp_loop": "sfx_sys_eoduk_heart", "stg_hapil_buildup": "sfx_trl_omen", "sfx_pick_gongmul": "sfx_pick_neok", "sfx_box_neokham": "sfx_pick_hosinbu",
}

const Q_NOW: int = 0      # N: 즉시
const Q_SNAP: int = 1     # S: 연출 스냅(≤250ms)
const Q_GRID: int = 2     # Q: 무구 그리드(발동 신호가 이미 그리드 위)

var count: int = 0
var index_of: Dictionary = {}                  # StringName id -> int 정의 슬롯(-1 = 무음)
var names: Array[StringName] = []
var takes: Array = []                          # [def] -> Array[AudioStream]  (id, id__v2, id__v3 …)
var named: Array = []                          # [def] -> Dictionary  "__suffix" -> AudioStream
var aggs: Array = []                           # [def] -> Array[AudioStream] 길이 4 (티어 1..4, 없는 티어 null)
var bus: Array[StringName] = []
var cap: PackedInt32Array = PackedInt32Array()
var prio: PackedInt32Array = PackedInt32Array()
var pitch_st: PackedFloat32Array = PackedFloat32Array()
var vol_rand: PackedFloat32Array = PackedFloat32Array()
var quant: PackedInt32Array = PackedInt32Array()
var is_loop: PackedByteArray = PackedByteArray()
var wpn_kind: PackedByteArray = PackedByteArray()   # 0 그 밖 · 1 무구 발동(sfx_wpn_X) · 2 무구 적중(sfx_wpn_X_hit)
var last_take: PackedInt32Array = PackedInt32Array()
var min_gap: PackedFloat32Array = PackedFloat32Array()   # 같은 정의 새 보이스 최소 간격(초). 안쪽 요청은 직전 보이스 볼륨만 올린다.
var fallback_count: int = 0
var missing_count: int = 0
var file_count: int = 0

var _evo_base: Dictionary = {}                 # "sfx_evo_x" -> "sfx_wpn_y"
var _data_ids: Dictionary = {}                 # 데이터에 정의된 id -> 데이터 사전


static func bus_name(data_bus: String) -> StringName:
	match data_bus:
		"bus_sfx_player": return &"SfxPlayer"
		"bus_sfx_wpn_red": return &"SfxRed"
		"bus_sfx_wpn_white": return &"SfxWhite"
		"bus_sfx_ritual": return &"SfxRitual"
		"bus_sfx_enemy": return &"SfxEnemy"
		"bus_sfx_pickup": return &"SfxPickup"
		"bus_ui": return &"UI"
		"bus_amb": return &"Ambience"
		"bus_mus_stinger": return &"MusicStinger"
		"bus_voice", "bus_vo_gongsu", "bus_vo_chuimsae", "bus_vo_muga": return &"Voice"
	return &"SFX"


## audio_mix.json voices.priority 와 같은 서열.
static func priority_for(id: String, cat: String, b: StringName) -> int:
	if b == &"UI":
		return 250
	if b == &"MusicStinger" or id.begins_with("stg_"):
		return 240
	if b == &"Voice":
		return 230
	if id == "sfx_sys_gildakkeum":
		return 220
	match b:
		&"SfxPlayer": return 200
		&"SfxRitual": return 180
		&"SfxWhite": return 150
		&"SfxRed": return 140
		&"SfxPickup": return 120
		&"Ambience": return 60
		&"SfxEnemy":
			return 110 if (id.begins_with("sfx_elite_") or id.begins_with("sfx_mboss_") or id.begins_with("sfx_boss_")) else 80
	return 100 if cat != "" else 90


## 같은 정의의 새 보이스 최소 간격(design/12 11.4 보강 — 물량 후반 타격음 끊김 방지).
## 일반 타격·피격·발동·획득 = 35~60ms(그 안의 요청은 새 보이스 대신 직전 보이스 +1dB, 최대 +4dB).
## 의식·플레이어·UI·스팅어 = 같은 프레임 같은 음(12ms)만 합친다(해원 화음·폭포는 음이 달라 합쳐지지 않는다).
static func gap_for(id: String, b: StringName) -> float:
	match id:
		"sfx_sys_hanpa", "sfx_sys_maedeup_lock":
			return 0.035
		"sfx_sys_pullil_enter", "sfx_sys_maetim", "sfx_sys_sal_drop":
			return 0.06
		"sfx_trl_avatar_telegraph":
			return 0.05
		"sfx_sys_cheondo":
			return 0.2   # 정산 진행·영가 천도가 줄줄이 와도 2.2s 상승 방울을 겹겹이 새로 깔지 않는다
	match b:
		&"SfxEnemy":
			return 0.035 if not (id.begins_with("sfx_elite_") or id.begins_with("sfx_boss_") or id.begins_with("sfx_mboss_")) else 0.012
		&"SfxRed", &"SfxWhite":
			return 0.035
		&"SfxPickup":
			return 0.04
	return 0.012


func load_all() -> void:
	var index: Dictionary = {}
	if FileAccess.file_exists(INDEX_PATH):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		if j is Dictionary:
			index = j
	var defs: Variant = Data.get_value("audio_sfx", "sfx", [])
	var last_wpn: String = ""
	if defs is Array:
		for e: Variant in defs:
			if not (e is Dictionary):
				continue
			var id: String = String(e.get("id", ""))
			if id == "":
				continue
			_data_ids[id] = e
			if id.begins_with("sfx_wpn_") and not id.ends_with("_hit"):
				last_wpn = id
			elif id.begins_with("sfx_evo_") and last_wpn != "":
				_evo_base[id] = last_wpn
	# 1) 데이터 정의 + 파일 색인 합집합으로 슬롯을 만든다
	var all_ids: Dictionary = {}
	for id: String in _data_ids:
		all_ids[id] = true
	for id: Variant in index:
		all_ids[String(id)] = true
	for id: String in all_ids:
		_add_def(id, _data_ids.get(id, {}), index.get(id, {}))
	# 2) 파일 없는 정의는 대체 슬롯으로 별칭
	for i in count:
		if takes[i].is_empty():
			var fb: int = _fallback_index(String(names[i]))
			index_of[names[i]] = fb
			if fb >= 0:
				fallback_count += 1
				print_verbose("[Audio] sfx fallback: ", names[i], " -> ", names[fb])
			else:
				missing_count += 1
				print_verbose("[Audio] sfx missing (silent): ", names[i])


func _add_def(id: String, d: Dictionary, idx: Dictionary) -> void:
	var i: int = count
	count += 1
	var sn: StringName = StringName(id)
	names.append(sn)
	index_of[sn] = i
	var b: StringName = bus_name(String(d.get("bus", "")))
	if d.is_empty():
		if id.begins_with("stg_"):
			b = &"MusicStinger"
		elif id.begins_with("amb_"):
			b = &"Ambience"
		elif id.begins_with("sfx_ui_"):
			b = &"UI"
		elif id.begins_with("sfx_wpn_"):
			b = &"SfxWhite"
		elif id.begins_with("sfx_sys_") or id.begins_with("sfx_trl_"):
			b = &"SfxRitual"
		elif id.begins_with("sfx_plr_"):
			b = &"SfxPlayer"
	bus.append(b)
	var vc: int = maxi(1, int(d.get("voice_cap", 2 if id.begins_with("stg_") else 3)))
	if id == "sfx_sys_haewon":
		vc = maxi(vc, 10)  # 토리 사다리·방울 폭포(10음 45ms 간격)가 서로 꼬리를 끊지 않게 — 음이 달라 합침이 안 걸린다
	cap.append(vc)
	prio.append(priority_for(id, String(d.get("cat", "")), b))
	pitch_st.append(float(d.get("pitch_rand_st", 0.0)))
	vol_rand.append(float(d.get("vol_rand_db", 0.0)))
	var q: String = String(d.get("quantize", "N"))
	quant.append(Q_SNAP if q == "S" else (Q_GRID if q == "Q" else Q_NOW))
	is_loop.append(1 if bool(d.get("loop", false)) else 0)
	wpn_kind.append((2 if id.ends_with("_hit") else 1) if id.begins_with("sfx_wpn_") else 0)
	last_take.append(-1)
	min_gap.append(gap_for(id, b))
	var tk: Array[AudioStream] = []
	var nm: Dictionary = {}
	var ag: Array = [null, null, null, null]
	var files: Variant = idx.get("files", {})
	if files is Dictionary:
		var keys: Array = files.keys()
		keys.sort()
		for fname: Variant in keys:
			var f: String = String(fname)
			var s: AudioStream = _load(f)
			if s == null:
				continue
			file_count += 1
			var suffix: String = f.substr(id.length())
			if suffix == "" or (suffix.begins_with("__v") and suffix.substr(3).is_valid_int()):
				tk.append(s)
			elif suffix.begins_with("__agg") and suffix.substr(5).is_valid_int():
				var t: int = clampi(int(suffix.substr(5)), 2, 4)
				ag[t - 1] = s
				nm[suffix] = s
			else:
				nm[suffix] = s
	if not tk.is_empty():
		ag[0] = tk[0]
	takes.append(tk)
	named.append(nm)
	aggs.append(ag)


func _load(fname: String) -> AudioStream:
	for ext: String in [".ogg", ".wav"]:
		var p: String = SFX_DIR + fname + ext
		if ResourceLoader.exists(p):
			var s: AudioStream = load(p) as AudioStream
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = false
			return s
	return null


func _has_files(i: int) -> bool:
	return i >= 0 and not takes[i].is_empty()


func _direct(id: String) -> int:
	var v: Variant = index_of.get(StringName(id), -1)
	var i: int = int(v)
	return i if _has_files(i) else -1


## 파일 없는 id 의 대체 슬롯. 해석 실패 시 -1(무음).
func _fallback_index(id: String) -> int:
	var cand: PackedStringArray = PackedStringArray()
	if ALIAS.has(id):
		cand.append(String(ALIAS[id]))
	if id.begins_with("sfx_wpn_") and id.ends_with("_hit"):
		var base: String = id.substr(0, id.length() - 4)
		cand.append(base + "__hit")
		cand.append(_family(base.substr(4), true))
	elif id.begins_with("sfx_wpn_"):
		cand.append(_family(id.substr(4), false))
	elif id.begins_with("sfx_evo_") and id.ends_with("_hit"):
		var eb: String = String(_evo_base.get(id.substr(0, id.length() - 4), ""))
		if eb != "":
			cand.append(eb + "_hit")
	elif id.begins_with("sfx_evo_") and id != "sfx_evo_reveal":
		cand.append(String(_evo_base.get(id, "")))
	elif id.begins_with("sfx_union_") and id.ends_with("_hit"):
		cand.append("sfx_wpn_janggu_hit")
	elif id.begins_with("sfx_union_"):
		cand.append("sfx_wpn_janggu")
	elif id.begins_with("sfx_elite_"):
		cand.append("sfx_elite_wongwi")
	elif id.begins_with("sfx_mboss_") or (id.begins_with("sfx_boss_") and id != "sfx_boss_knot_untie"):
		cand.append("stg_mboss_enter")
	elif id.begins_with("sfx_ui_"):
		cand.append("sfx_ui_nav")
	elif id.begins_with("sfx_pick_") or id.begins_with("sfx_box_"):
		cand.append("sfx_pick_yeopjeon")
	elif id == "sfx_sys_maetim":
		cand.append("sfx_sys_pullil_enter")
	elif id == "sfx_trl_confirm_cancel" or id == "sfx_trl_barrier":
		cand.append("sfx_trl_circle_enter")
	for c: String in cand:
		if c == "":
			continue
		if c.contains("__"):
			# 이름 변주 대체: 그 변주만 기본 테이크로 가진 별도 슬롯을 만든다
			var parts: PackedStringArray = c.split("__", true, 1)
			var bi: int = _direct(parts[0])
			if bi >= 0 and named[bi].has("__" + parts[1]):
				return _alias_variant(id, bi, "__" + parts[1])
			continue
		var di: int = _direct(c)
		if di >= 0:
			return di
	return -1


## 이름 변주(예: sfx_wpn_gakgung__hit)를 기본 테이크로 하는 새 슬롯. 원래 id 의 데이터 정의(버스·상한)를 쓴다.
func _alias_variant(id: String, src: int, suffix: String) -> int:
	var own: int = int(index_of.get(StringName(id), -1))
	if own < 0:
		return -1
	var tk: Array[AudioStream] = [named[src][suffix]]
	takes[own] = tk
	aggs[own][0] = tk[0]
	return own


func _family(wpn_id: String, hit: bool) -> String:
	var w: Dictionary = Data.weapon(wpn_id)
	var white: bool = String(w.get("color", "red")) == "white"
	if hit:
		return "sfx_wpn_bangul_hit" if white else "sfx_wpn_sinkal_hit"
	return "sfx_wpn_buchae" if white else "sfx_wpn_sinkal"


## id → 정의 슬롯(대체 해석 포함). 모르는 id 는 이번에 해석해 캐시한다.
func resolve(id: StringName) -> int:
	var v: Variant = index_of.get(id, null)
	if v != null:
		return int(v)
	var s: String = String(id)
	var r: int = -1
	if s.contains("__"):
		var parts: PackedStringArray = s.split("__", true, 1)
		var bi: int = resolve(StringName(parts[0]))
		r = bi
	else:
		r = _fallback_index(s)
	index_of[id] = r
	if r < 0:
		missing_count += 1
		print_verbose("[Audio] sfx unknown (silent): ", id)
	return r


## 반복 회피 테이크 선택(테이크 ≥3 이면 직전 1개 제외).
func pick_take(i: int, rng: RandomNumberGenerator) -> AudioStream:
	var tk: Array = takes[i]
	var n: int = tk.size()
	if n == 0:
		return null
	if n == 1:
		return tk[0]
	var k: int = rng.randi_range(0, n - 1)
	if n >= 3 and k == last_take[i]:
		k = (k + 1 + rng.randi_range(0, n - 2)) % n
	last_take[i] = k
	return tk[k]


func named_stream(i: int, suffix: String) -> AudioStream:
	if i < 0:
		return null
	var nm: Dictionary = named[i]
	return nm.get(suffix, null)


## 집계 티어 스트림(1..4). 없는 티어는 아래 티어로 내려간다.
func agg_stream(i: int, tier: int, rng: RandomNumberGenerator) -> AudioStream:
	var ag: Array = aggs[i]
	var t: int = clampi(tier, 1, 4)
	while t > 1 and ag[t - 1] == null:
		t -= 1
	if t == 1:
		return pick_take(i, rng)
	return ag[t - 1]


func clear() -> void:
	takes.clear()
	named.clear()
	aggs.clear()
	index_of.clear()
	names.clear()
	count = 0
	_gate.clear()


# ─── 덧소리 문턱(design/19 §5.0 소리 문법): 같은 sfx 0.1초에 3개까지, 넘치면 −6dB 하나만 ───────────
## 무구 연출 덧소리(진화 −3반음 레이어 · 결합 짝 겹침 · 무거운 무기 저음)가 부른다. 반환: 볼륨 보정(dB).
## 0 = 그대로, −6 = 창의 넷째(−6dB 하나), −100 = 버림. 상태는 정의 슬롯별 [창 시작, 개수].
var _gate: Dictionary = {}


func gate(d: int, t: float) -> float:
	if d < 0:
		return -100.0
	var g: Variant = _gate.get(d, null)
	if g == null or t - float(g[0]) >= 0.1 or t < float(g[0]):
		_gate[d] = [t, 1]
		return 0.0
	var n: int = int(g[1]) + 1
	g[1] = n
	if n <= 3:
		return 0.0
	return -6.0 if n == 4 else -100.0
