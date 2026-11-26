extends RefCounted
## 빙의 면 효과 · 권능(權能) · 강신 등급 · 합일 효과 런타임. 소유: deities.
## 06 §7: 신령당 보이는 권능 4종 = 공통 3 + 빙의한 면 전용 1. Lv1~3, 등급 평·길·대길(점괘).
## 구현 범위(v1 마감): 스탯형은 Game.stats 에 가산, 발동형은 EnemyManager 공개 API(query_circle/queue_hit)로 판정.
##   공포·둔화·상자·재화처럼 다른 모듈 API 가 필요한 효과는 카드에는 보이되 효과는 TODO(deities) — 요청 목록 참고.
## 할당: 발동(이벤트) 시점만. 틱 경로는 고정 버퍼(_q)와 쿨다운 Dictionary 조회만.

const Defs := preload("res://deities/deity_defs.gd")

enum Fx { NONE, STAR_FALL, TIGER_DASH, WAVE, SPIN, PULSE, CLAW, SPLASH, HAPIL_RING, LINE, FLOWER, ORB_GIFT }
const FX_CAP: int = 64
const EMPTY: Dictionary = {}   # 읽기 전용 기본값(틱 경로에서 빈 사전 할당 방지)
const POOL_CAP: int = 8

var possessed: Array[StringName] = []
var faces: Dictionary = {}          # deity -> &"wieom"|&"gaho"
var complete: Dictionary = {}       # deity -> bool
var powers: Dictionary = {}         # power_id -> {deity, level, grade_mult, def, face_color}
var gangsin: int = 0
var hapil_form: StringName = &""
var howi_on: bool = false           # 신장 호위 4(장군 가호)
var howi_white: bool = false        # 신장기(백 접촉)
var orbit_t: float = 0.0
var stat_log: Dictionary = {}       # stat -> 누적 가산(디버그)

var _cd: Dictionary = {}            # power/proc id -> 다음 발동 게임 초
var _hits: int = 0
var _casts: int = 0
var _proc_tick: int = -1
var _proc_n: int = 0
var _heal_acc: float = 0.0
var _heal_sec: int = -1
var _march_dir: Vector2 = Vector2.ZERO
var _march_t: float = 0.0
var _march_on: bool = false
var _revive_used: int = 0
var _q: PackedInt32Array = PackedInt32Array()
var _rng: RandomNumberGenerator
var _haengjin_applied: float = 0.0   # 군웅 행진: 지금 stat_jangdan 에 넣어 둔 값
var _haengjin_sec: int = -1
var _donbaram_kills: int = 0
var _donbaram_applied: float = 0.0
var _orb_gift_t: float = -10.0

# 맑은 물 장판(용왕 가호) SoA — view 바닥층이 그린다
var pool_x: PackedFloat32Array = PackedFloat32Array()
var pool_y: PackedFloat32Array = PackedFloat32Array()
var pool_r: PackedFloat32Array = PackedFloat32Array()
var pool_t0: PackedFloat32Array = PackedFloat32Array()
var pool_next: PackedFloat32Array = PackedFloat32Array()
var pool_dur: float = 4.0
var _pool_cd: float = 0.0
# 금줄 결계(제석·대감 가호) — 발동 중이면 geumjul_t0 ≤ now < geumjul_t0 + 3
var geumjul_t0: float = -100.0
var geumjul_r: float = 96.0
var geumjul_c: Vector2 = Vector2.ZERO
var _geumjul_next_tick: float = 0.0

# 연출 이벤트 링 버퍼(view 가 그린다)
var fx_kind: PackedInt32Array = PackedInt32Array()
var fx_x: PackedFloat32Array = PackedFloat32Array()
var fx_y: PackedFloat32Array = PackedFloat32Array()
var fx_dx: PackedFloat32Array = PackedFloat32Array()
var fx_dy: PackedFloat32Array = PackedFloat32Array()
var fx_r: PackedFloat32Array = PackedFloat32Array()
var fx_t0: PackedFloat32Array = PackedFloat32Array()
var fx_col: PackedInt32Array = PackedInt32Array()   # K.DmgColor
var _fx_head: int = 0


func _init() -> void:
	_q.resize(96)
	fx_kind.resize(FX_CAP)
	fx_x.resize(FX_CAP)
	fx_y.resize(FX_CAP)
	fx_dx.resize(FX_CAP)
	fx_dy.resize(FX_CAP)
	fx_r.resize(FX_CAP)
	fx_t0.resize(FX_CAP)
	fx_col.resize(FX_CAP)
	fx_t0.fill(-100.0)
	pool_x.resize(POOL_CAP)
	pool_y.resize(POOL_CAP)
	pool_r.resize(POOL_CAP)
	pool_t0.resize(POOL_CAP)
	pool_next.resize(POOL_CAP)
	pool_t0.fill(-100.0)
	_rng = Rng.stream(&"trial")


func _fx(kind: int, p: Vector2, d: Vector2, r: float, col: int) -> void:
	var i: int = _fx_head
	_fx_head = (_fx_head + 1) % FX_CAP
	fx_kind[i] = kind
	fx_x[i] = p.x
	fx_y[i] = p.y
	fx_dx[i] = d.x
	fx_dy[i] = d.y
	fx_r[i] = r
	fx_t0[i] = Game.time_sec()
	fx_col[i] = col


# ─── 스탯 ──────────────────────────────────────────────────────────────

const INT_STATS: PackedStringArray = ["stat_haengnyeol", "stat_sinbok", "stat_myeongjul", "stat_sinjang", "stat_jeomgwae"]
const MULT_STATS: PackedStringArray = ["stat_sinppal", "stat_doryang", "stat_domu", "stat_yeongheom", "stat_jangdan", "stat_siju", "stat_haewon_suryeon", "stat_gise"]


## op add / add_pct. mult = 면 효과 배율(미완 0.7, 만신 ×1.15 등). 정수 효과 미완 = max(1, floor(v×0.7)).
func add_stat(id: String, op: String, value: float, mult: float = 1.0, incomplete: bool = false) -> void:
	var sid: StringName = StringName(id)
	var cur: float = Game.stat(sid, 0.0)
	var delta: float = 0.0
	if op == "add":
		if INT_STATS.has(id):
			delta = float(maxi(1, int(floor(value * 0.70)))) if incomplete else value
		else:
			delta = value * mult
	elif op == "add_pct":
		if MULT_STATS.has(id):
			delta = value * 0.01 * mult
		elif id == "stat_gyeoldan":
			delta = value * 0.01 * mult
		else:
			delta = cur * value * 0.01 * mult
	if delta == 0.0:
		return
	Game.stats[sid] = cur + delta
	stat_log[sid] = float(stat_log.get(sid, 0.0)) + delta


func _hp_max_add(v: float) -> void:
	Game.hp_max += v
	Game.hp = minf(Game.hp_max, Game.hp + v)


# ─── 빙의 ──────────────────────────────────────────────────────────────

## 면 효과 적용. pct_mult: 무당 보정(만신 1.15) × 완성도(미완 0.7).
func apply_face(deity: StringName, face: StringName, is_complete: bool, pct_mult: float) -> void:
	if not possessed.has(deity):
		possessed.append(deity)
	faces[deity] = face
	complete[deity] = is_complete
	var fd: Dictionary = Data.deity(String(deity)).get("faces", EMPTY).get(String(face), EMPTY)
	var effs: Variant = fd.get("effects", [])
	if effs is Array:
		for e: Variant in effs:
			if not (e is Dictionary):
				continue
			var ed: Dictionary = e
			if ed.has("stat"):
				var v: float = float(ed.get("value", 0))
				if String(ed.get("filter", "")) != "":
					v *= 0.5   # 필터(예: 적 근접 무구만)는 전체 가산으로 근사 — 절반값. TODO(deities): 무구 필터 API
				add_stat(String(ed["stat"]), String(ed.get("op", "add")), v, pct_mult, not is_complete)
			elif String(ed.get("id", "")) == "npc_sinjang_howi":
				howi_on = true
	gangsin += 1
	var gl: Array = Data.get_value("deities", "gangsin_grade", [])
	if gangsin < gl.size() and gl[gangsin] is Dictionary and gl[gangsin - 1] is Dictionary:
		var now_g: Dictionary = gl[gangsin]
		var prev_g: Dictionary = gl[gangsin - 1]
		_hp_max_add(float(now_g.get("max_jeonggi_add", 0)) - float(prev_g.get("max_jeonggi_add", 0)))
		add_stat("stat_sinppal", "add_pct", float(now_g.get("sinppal_add_pct", 0)) - float(prev_g.get("sinppal_add_pct", 0)))


## 보이는 권능 4종(공통 3 + 면 전용 1).
func visible_powers(deity: StringName, face: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var arr: Variant = Data.deity(String(deity)).get("powers", [])
	if arr is Array:
		for p: Variant in arr:
			if p is Dictionary:
				var f: String = String((p as Dictionary).get("face", "common"))
				if f == "common" or f == String(face):
					out.append(p)
	return out


## 점괘 등급 굴림(grade_formula): L = 점괘/100, 대길 min(30,5L), 길 min(50,25√L).
## 시련 수행(trial_director._set_perf)이 가중을 정한다: min_gil(깔끔한 완수) = 평 없음, daegil_mult·gil_mult = 대길·길 가중 배율.
func roll_grade(min_gil: bool = false, daegil_mult: float = 1.0, gil_mult: float = 1.0) -> Dictionary:
	var L: float = Game.stat(&"stat_jeomgwae", 100.0) / 100.0
	var w_dae: float = minf(30.0, 5.0 * L) * maxf(0.0, daegil_mult)
	var w_gil: float = minf(50.0, 25.0 * sqrt(L)) * maxf(0.0, gil_mult)
	var w_py: float = maxf(0.0, 100.0 - w_dae - w_gil)
	if min_gil:
		w_py = 0.0
	var r: float = _rng.randf() * (w_dae + w_gil + w_py)
	if r < w_dae:
		return {"id": "grade_daegil", "name": "대길", "mult": 1.6}
	if r < w_dae + w_gil:
		return {"id": "grade_gil", "name": "길", "mult": 1.3}
	return {"id": "grade_pyeong", "name": "평", "mult": 1.0}


## 빙의 점지 카드(06 §7.7): 완성 4장 / 미완 2장(몸주신 3장). 몸주 완성은 한 장 길 이상 보장.
func jeomji_cards(deity: StringName, face: StringName, is_complete: bool, is_momju: bool, perf_min_gil: bool = false, daegil_mult: float = 1.0, gil_mult: float = 1.0) -> Array[Dictionary]:
	var pool: Array[Dictionary] = visible_powers(deity, face)
	var want: int = 4 if is_complete else (3 if is_momju else 2)
	var picks: Array[Dictionary] = []
	while picks.size() < want and not pool.is_empty():
		var k: int = _rng.randi_range(0, pool.size() - 1)
		picks.append(pool[k])
		pool.remove_at(k)
	var out: Array[Dictionary] = []
	var guarantee: int = _rng.randi_range(0, maxi(0, picks.size() - 1)) if (is_momju and is_complete) else -1
	for i in picks.size():
		var p: Dictionary = picks[i]
		var g: Dictionary = roll_grade(perf_min_gil or i == guarantee, daegil_mult, gil_mult)
		var col_rule: String = String(p.get("color_rule", "none"))
		var nlv: int = int(powers.get(String(p.get("id", "")), EMPTY).get("level", 0)) + 1
		var dv1: String = desc_v1(p, nlv)
		out.append({
			"power_id": String(p.get("id", "")),
			"deity": deity,
			"name": String(p.get("name_ko", "")),
			"desc": dv1 if dv1 != "" else String(p.get("desc_ko", "")),
			"type": String(p.get("type", "")),
			"face": String(p.get("face", "common")),
			"color_rule": col_rule,
			"grade": g["id"],
			"grade_name": g["name"],
			"grade_mult": g["mult"],
			"level": int(powers.get(String(p.get("id", "")), EMPTY).get("level", 0)) + 1,
		})
	return out


## v1 카드 설명: 데이터 desc_ko 가 아직 없는 다른 모듈 API(공포·둔화·상자·엽전…)를 전제로 한 권능은
## 이 빌드에서 실제로 하는 일을 그대로 적는다(깨진 약속을 카드에 노출하지 않는다). 없으면 "".
func desc_v1(p: Dictionary, lv: int) -> String:
	var levels: Variant = p.get("levels", [])
	var row: Dictionary = {}
	if levels is Array and (levels as Array).size() > 0 and levels[clampi(lv, 1, (levels as Array).size()) - 1] is Dictionary:
		row = levels[clampi(lv, 1, (levels as Array).size()) - 1]
	match String(p.get("id", "")):
		"pwr_sansin_horyeong":
			return "%d초마다 범의 호령: 반경 %.1f유닛 잡귀를 밀쳐 내고 흔든다." % [int(row.get("cooldown_s", 12)), float(row.get("radius", 3.0))]
		"pwr_sansin_sangil":
			return "산길이 발을 받친다: 무당 도무 +%.1f%%." % (float(row.get("domu_on_gilbe_pct", 5)) * 0.5)
		"pwr_sansin_sanjigi":
			return "영가(넋) 수명 +%d초. 영수 범이 더 자주 달린다." % int(row.get("neok_sumyeong_add_s", 3))
		"pwr_yongwang_mulbora":
			return "무구 적중 시 %d%% 확률로 물보라(반경 1.2): 원 타격의 30%% 피해." % int(row.get("proc_chance_pct", 10))
		"pwr_yongwang_yonggung_bomul":
			return "정예 이상을 거두면 %d%% 확률로 용궁 보물 — 넋 구슬 한 움큼이 쏟아진다." % int(row.get("box_upgrade_pct", 10))
		"pwr_yongwang_mulgil":
			return "길베 +%.1f초 · 무당 도무 +%.0f%%." % [float(row.get("gilbe_add_s", 0.5)), float(row.get("domu_on_gilbe_pct", 8)) * 0.5]
		"pwr_yongwang_neokgeonjigi":
			return "맑은 물 장판 반경 +%d%% · 장판 백 피해 ×1.5." % int(row.get("clear_water_radius_pct", 50))
		"pwr_chilseong_myeong_itgi":
			return "피격 시 %d%% 확률로 별빛이 명을 잇는다: 받은 피해를 되돌려 회복." % int(row.get("survive_chance_pct", 10))
		"pwr_chilseong_bukdu_byeolbit":
			return "7초마다 무당 둘레 일곱 자리에 별이 떨어진다(빙의 면 색, 기준×%.1f)." % float(row.get("dmg_x_face_base", 0.8))
		"pwr_chilseong_yeonmyeong":
			return "정기가 10%% 아래로 떨어지면 정기 %d%% 회복 + 무적 2초(런당 %d회)." % [int(row.get("heal_pct", 30)), int(row.get("uses_per_run", 1))]
		"pwr_barigongju_samsaekkot":
			return "풀릴 기색에 든 잡귀에게 %d%% 확률로 꽃 표식 — 그 자리에서 백 피해(기준×2)." % int(row.get("mark_chance_pct", 10))
		"pwr_barigongju_mujangseung":
			return "퇴치한 잡귀가 넋 구슬로 바뀔 확률 +%d%% (바리 위엄과 합산, 상한 50%%)." % int(row.get("neok_convert_add_pct", 10))
		"pwr_barigongju_jeoseunggil":
			return "영가가 천도할 때 무당 둘레 반경 %.1f유닛에 저승길 파동(기준×0.6)." % float(row.get("radius", 2.0))
		"pwr_jeseok_daegam_siru":
			return "정예 이상을 거두면 시루떡 한 덩이 — 정기 %.0f%% 회복." % (float(row.get("offering_heal_pct", 25)) * 0.2)
		"pwr_jeseok_daegam_yeomju":
			return "길닦음이 닫히면 고리 안에 염주 파동: 백 피해(기준×%.1f)." % (1.0 + float(row.get("ring_dmg_pct", 20)) * 0.01)
		"pwr_jeseok_daegam_donbaram":
			return "퇴치 10마다 무구 피해 +%.1f%% (상한 30%%)." % float(row.get("red_dmg_pct_per_coin", 0.5))
		"pwr_jeseok_daegam_geumjul":
			return "금줄 결계 %d초마다 · 반경 +%.1f유닛: 안의 잡귀를 밀쳐 낸다." % [int(row.get("interval_s", 8)), float(row.get("radius_add", 0.5))]
		"pwr_janggun_obang_howi":
			return "신복 +%d · 피격 뒤 무적 +%.1f초." % [int(row.get("sinbok_add", 2)), float(row.get("iframe_add_s", 0.5))]
	return ""


func gain_power(card: Dictionary) -> void:
	var id: String = String(card.get("power_id", ""))
	if id == "":
		return
	var deity: StringName = card.get("deity", &"")
	var def: Dictionary = {}
	for p: Dictionary in visible_powers(deity, faces.get(deity, &"wieom")):
		if String(p.get("id", "")) == id:
			def = p
	var cur: Dictionary = powers.get(id, EMPTY)
	var lv: int = mini(3, int(cur.get("level", 0)) + 1)
	powers[id] = {"deity": deity, "level": lv, "grade_mult": float(card.get("grade_mult", 1.0)), "grade": String(card.get("grade", "grade_pyeong")), "def": def}
	_apply_power_stats(id, lv, int(cur.get("level", 0)))
	Events.deity_power_gained.emit(deity, StringName(id), lv, StringName(String(card.get("grade", "grade_pyeong"))))


## 정규 점지에서 레벨 올리기(ui/combat 이 호출: TrialDirector.apply_power_choice).
func level_power(id: String) -> int:
	if not powers.has(id):
		return 0
	var cur: Dictionary = powers[id]
	var old: int = int(cur.get("level", 1))
	var lv: int = mini(3, old + 1)
	if lv == old:
		# Lv3 초과 = 등급 1단계 상승(합일 규칙과 같게)
		cur["grade_mult"] = minf(1.6, float(cur.get("grade_mult", 1.0)) + 0.3)
		return lv
	cur["level"] = lv
	_apply_power_stats(id, lv, old)
	Events.deity_power_gained.emit(cur.get("deity", &""), StringName(id), lv, StringName(String(cur.get("grade", "grade_pyeong"))))
	return lv


func _lvrow(id: String) -> Dictionary:
	var p: Dictionary = powers.get(id, EMPTY)
	var def: Dictionary = p.get("def", EMPTY)
	var levels: Variant = def.get("levels", [])
	var lv: int = int(p.get("level", 1))
	if levels is Array and (levels as Array).size() > 0:
		return levels[clampi(lv, 1, (levels as Array).size()) - 1]
	return {}


## 등급 축 값(쿨다운 축은 나눔, 그 외 곱).
func _gv(id: String, field: String, default: float) -> float:
	var row: Dictionary = _lvrow(id)
	var v: float = float(row.get(field, default))
	var p: Dictionary = powers.get(id, EMPTY)
	var def: Dictionary = p.get("def", EMPTY)
	if String(def.get("grade_axis", "")) == field:
		var m: float = float(p.get("grade_mult", 1.0))
		v = v / m if field.contains("cooldown") or field.contains("interval") else v * m
	return v


## 스탯형 권능: 이전 레벨 값을 빼고 새 레벨 값을 더한다.
func _apply_power_stats(id: String, lv: int, old_lv: int) -> void:
	var p: Dictionary = powers.get(id, EMPTY)
	var def: Dictionary = p.get("def", EMPTY)
	var levels: Variant = def.get("levels", [])
	if not (levels is Array) or (levels as Array).is_empty():
		return
	var nrow: Dictionary = levels[clampi(lv, 1, levels.size()) - 1]
	var orow: Dictionary = levels[clampi(old_lv, 1, levels.size()) - 1] if old_lv > 0 else {}
	var m: float = float(p.get("grade_mult", 1.0))
	var pairs: Array = [
		["sinbok_add", "stat_sinbok", "add", 1.0],
		["haengnyeol_add", "stat_haengnyeol", "add", 1.0],
		["neok_sumyeong_add_s", "stat_neok_sumyeong", "add", 1.0],
		["gyeoldan_add_pct", "stat_gyeoldan", "add_pct", 1.0],
		["siju_add_pct", "stat_siju", "add_pct", 1.0],
		["domu_on_gilbe_pct", "stat_domu", "add_pct", 0.5],   # 길베 위 조건 → 상시 절반으로 근사
		["gilbe_add_s", "stat_gilbe", "add", 1.0],
	]
	for pr: Array in pairs:
		var key: String = pr[0]
		if nrow.has(key):
			var nv: float = float(nrow[key]) * (m if String(def.get("grade_axis", "")) == key else 1.0)
			var ov: float = float(orow.get(key, 0.0)) * (m if String(def.get("grade_axis", "")) == key else 1.0)
			if old_lv <= 0:
				ov = 0.0
			add_stat(String(pr[1]), String(pr[2]), (nv - ov) * float(pr[3]))
	if id == "pwr_janggun_sinjanggi":
		howi_white = true


# ─── 기준 피해 ─────────────────────────────────────────────────────────

func base_max(white: bool) -> float:
	var best: float = 0.0
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm != null:
		for i in wm.slot_count():
			var w: WeaponBase = wm.weapon_at(i)
			if w == null:
				continue
			if (w.color == K.DmgColor.WHITE) == white or w.color == K.DmgColor.UNION:
				best = maxf(best, w.s("dmg", 0.0))
	if best <= 0.0:
		best = 10.0 * (1.0 + 0.1 * float(Game.level))
	return best * Game.stat(&"stat_sinppal", 1.0)


func _face_color(deity: StringName) -> int:
	return K.DmgColor.WHITE if faces.get(deity, &"wieom") == &"gaho" else K.DmgColor.RED


## 원 안 적 일괄 피해(대상 상한). 반환: 맞힌 수.
func strike_circle(c: Vector2, r_px: float, dmg: float, color: int, kb_u: float = 0.0, max_n: int = 40) -> int:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return 0
	var cnt: int = em.query_circle(c, r_px, _q, mini(max_n, _q.size()))
	var hit: int = 0
	for k in cnt:
		var s: int = _q[k]
		if not em.is_alive(s):
			continue
		var d: Vector2 = em.pos_of(s) - c
		em.queue_hit(s, dmg, color, false, d.normalized() if d.length_squared() > 1.0 else Vector2.DOWN, kb_u)
		hit += 1
	return hit


func strike_rect(o: Vector2, dirv: Vector2, length: float, width: float, dmg: float, color: int, kb_u: float) -> int:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return 0
	var mid: Vector2 = o + dirv * length * 0.5
	var cnt: int = em.query_circle(mid, length * 0.5 + width, _q, _q.size())
	var hit: int = 0
	var perp: Vector2 = Vector2(-dirv.y, dirv.x)
	for k in cnt:
		var s: int = _q[k]
		var rel: Vector2 = em.pos_of(s) - o
		var al: float = rel.dot(dirv)
		if al < 0.0 or al > length or absf(rel.dot(perp)) > width * 0.5:
			continue
		em.queue_hit(s, dmg, color, false, dirv, kb_u)
		hit += 1
	return hit


## 반경 안 밀집 방향(맹호출림·해일 조준).
func _dense_dir(c: Vector2, r_px: float) -> Vector2:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return Vector2.RIGHT
	var cnt: int = em.query_circle(c, r_px, _q, _q.size())
	var acc: Vector2 = Vector2.ZERO
	for k in cnt:
		acc += (em.pos_of(_q[k]) - c).normalized()
	if acc.length_squared() < 0.01:
		var pl: Player = Game.player as Player
		return pl.last_move_dir if pl != null else Vector2.RIGHT
	return acc.normalized()


func _ready_cd(key: String, cd: float, now: float) -> bool:
	if now < float(_cd.get(key, 0.0)):
		return false
	_cd[key] = now + cd
	return true


# ─── 틱(시뮬, 틱 6b) ──────────────────────────────────────────────────

func sim_step(dt: float, now: float) -> void:
	if Game.player == null:
		return
	var pp: Vector2 = Game.player.global_position
	orbit_t += dt
	# 칠성 위엄: 북두 별 낙하(6초, 7점)
	if faces.get(&"deity_chilseong", &"") == &"wieom" and _ready_cd("bukdu_byeol", 6.0, now):
		var dv: Vector2 = _dense_dir(pp, 8.0 * K.UNIT_PX)
		var c: Vector2 = pp + dv * 4.0 * K.UNIT_PX
		var mult: float = 0.7 if not bool(complete.get(&"deity_chilseong", true)) else 1.0
		for k in 7:
			var p: Vector2 = c + Vector2.from_angle(TAU * float(k) / 7.0) * (1.6 if k > 0 else 0.0) * K.UNIT_PX
			strike_circle(p, 1.0 * K.UNIT_PX, base_max(false) * 1.2 * mult, K.DmgColor.RED, 0.3, 12)
			_fx(Fx.STAR_FALL, p, Vector2.ZERO, 1.0 * K.UNIT_PX, K.DmgColor.RED)
	for id: Variant in powers:      # Dictionary 직접 순회(keys() 사본 할당 없음)
		var sid: String = String(id)
		match sid:
			"pwr_sansin_horyeong":
				if _ready_cd(sid, _gv(sid, "cooldown_s", 12.0), now):
					var r: float = _gv(sid, "radius", 3.0) * K.UNIT_PX
					strike_circle(pp, r, 1.0, K.DmgColor.WHITE, 1.5)
					_fx(Fx.PULSE, pp, Vector2.ZERO, r, K.DmgColor.NONE)
			"pwr_sansin_maengho":
				if _ready_cd(sid, _gv(sid, "cooldown_s", 20.0), now):
					var dv2: Vector2 = _dense_dir(pp, 8.0 * K.UNIT_PX)
					var o: Vector2 = pp - dv2 * 2.0 * K.UNIT_PX
					strike_rect(o, dv2, 12.0 * K.UNIT_PX, 1.6 * K.UNIT_PX, base_max(false) * _gv(sid, "dmg_x_base_red", 4.0), K.DmgColor.RED, 1.0)
					_fx(Fx.TIGER_DASH, o, dv2, 12.0 * K.UNIT_PX, K.DmgColor.RED)
					Juice.kick(dv2, 1)
			"pwr_yongwang_haeil":
				if _ready_cd(sid, _gv(sid, "cooldown_s", 18.0), now):
					var dv3: Vector2 = _dense_dir(pp, 8.0 * K.UNIT_PX)
					strike_rect(pp, dv3, 10.0 * K.UNIT_PX, 6.0 * K.UNIT_PX, base_max(false) * _gv(sid, "dmg_x_base_red", 3.0), K.DmgColor.RED, 3.0)
					_fx(Fx.WAVE, pp, dv3, 10.0 * K.UNIT_PX, K.DmgColor.RED)
			"pwr_chilseong_bukdu_byeolbit":
				if _ready_cd(sid, 7.0, now):
					var dm: float = base_max(_face_color(&"deity_chilseong") == K.DmgColor.WHITE) * _gv(sid, "dmg_x_face_base", 0.8)
					for k in 7:
						var p2: Vector2 = pp + Vector2.from_angle(TAU * float(k) / 7.0 + orbit_t) * 3.0 * K.UNIT_PX
						strike_circle(p2, 0.9 * K.UNIT_PX, dm, _face_color(&"deity_chilseong"), 0.3, 6)
						_fx(Fx.STAR_FALL, p2, Vector2.ZERO, 0.9 * K.UNIT_PX, _face_color(&"deity_chilseong"))
			"pwr_chilseong_yeonmyeong":
				# 정기 0 직전 연명: 런당 1(Lv3 2)회. 사망 훅 대신 정기 10% 이하에서 발동(TODO(deities): 사망 직전 훅 요청)
				var uses: int = 2 if int(powers[sid].get("level", 1)) >= 3 else 1
				if _revive_used < uses and Game.hp > 0.0 and Game.hp <= Game.hp_max * 0.10:
					_revive_used += 1
					var pl2: Player = Game.player as Player
					if pl2 != null:
						pl2.hit.heal(Game.hp_max * _gv(sid, "heal_pct", 30.0) * 0.01)
						pl2.hit.iframe_left = maxf(pl2.hit.iframe_left, 2.0)
					_fx(Fx.PULSE, pp, Vector2.ZERO, 2.0 * K.UNIT_PX, K.DmgColor.NONE)
			"pwr_janggun_jingun":
				var pl3: Player = Game.player as Player
				if pl3 != null:
					var md: Vector2 = pl3.vel.normalized() if pl3.vel.length_squared() > 100.0 else Vector2.ZERO
					if md != Vector2.ZERO and (_march_dir == Vector2.ZERO or md.dot(_march_dir) > 0.866):
						if _march_dir == Vector2.ZERO:
							_march_dir = md
						_march_t += dt
					else:
						_march_dir = md
						_march_t = 0.0
					var want_on: bool = _march_t >= 2.0
					if want_on != _march_on:
						_march_on = want_on
						var v: float = _gv(sid, "dmg_pct", 10.0) * 0.01
						Game.stats[&"stat_sinppal"] = Game.stat(&"stat_sinppal", 1.0) + (v if want_on else -v)
	_tick_face_procs(now, pp)
	# 신장 호위(장군 가호): 4신장 공전, 신장기 보유 시 접촉 적에게 백 피해
	# (신장기 없으면 밀침 위주 약한 백 피해 ×0.15, 신장기 ×0.4)
	if howi_on and _ready_cd("howi_touch", 0.5, now):
		var hm: float = 0.4 if howi_white else 0.15
		for k in 4:
			var hp2: Vector2 = pp + Vector2.from_angle(orbit_t * 1.05 + TAU * float(k) / 4.0) * 1.4 * K.UNIT_PX
			strike_circle(hp2, 0.5 * K.UNIT_PX, base_max(true) * hm, K.DmgColor.WHITE, 0.6, 4)


## 면 효과 중 발동형(06 §3.x 면 표) — v1 근사: 공포·둔화 API 대신 밀침(넉백)·피해로 표현한다.
func _tick_face_procs(now: float, pp: Vector2) -> void:
	# 산신 가호: 영수 범이 행렬 곁에서 5초(산지기 −Lv·0.5초)마다 밀집 쪽으로 짧게 달린다(백)
	if faces.get(&"deity_sansin", &"") == &"gaho":
		var iv: float = 5.0 - 0.5 * float(int(powers.get("pwr_sansin_sanjigi", EMPTY).get("level", 0)))
		if _ready_cd("yeongsu_beom", iv, now):
			var dv: Vector2 = _dense_dir(pp, 7.0 * K.UNIT_PX)
			var o: Vector2 = pp - dv * 1.0 * K.UNIT_PX + Vector2(-dv.y, dv.x) * 0.6 * K.UNIT_PX
			strike_rect(o, dv, 6.0 * K.UNIT_PX, 1.4 * K.UNIT_PX, base_max(true) * 1.2, K.DmgColor.WHITE, 1.5)
			_fx(Fx.TIGER_DASH, o, dv, 6.0 * K.UNIT_PX, K.DmgColor.WHITE)
	# 용왕 위엄: 물결 — 1초마다 무당 둘레 1.5유닛 밀침 + 약한 적 피해
	if faces.get(&"deity_yongwang", &"") == &"wieom" and _ready_cd("mulgyeol", 1.0, now):
		strike_circle(pp, 1.5 * K.UNIT_PX, base_max(false) * 0.25, K.DmgColor.RED, 0.6, 16)
		_fx(Fx.SPLASH, pp, Vector2.ZERO, 1.5 * K.UNIT_PX, K.DmgColor.RED)
	# 용왕 가호: 맑은 물 장판(해원 자리) 틱
	for i in POOL_CAP:
		var age: float = now - pool_t0[i]
		if age < 0.0 or age > pool_dur:
			continue
		if now >= pool_next[i]:
			pool_next[i] = now + 0.5
			var m: float = 1.5 if powers.has("pwr_yongwang_neokgeonjigi") else 1.0
			strike_circle(Vector2(pool_x[i], pool_y[i]), pool_r[i], base_max(true) * 0.2 * m, K.DmgColor.WHITE, 0.0, 12)
	# 바리 가호: 영가 사격 — 3초마다 가까운 잡귀 셋에게 백 화살
	if faces.get(&"deity_barigongju", &"") == &"gaho" and _ready_cd("yeongga_sagyeok", 3.0, now):
		var em: EnemyManager = Game.enemies as EnemyManager
		if em != null:
			var cnt: int = em.query_circle(pp, 4.0 * K.UNIT_PX, _q, 24)
			var shot: int = 0
			for k in cnt:
				var sl: int = _q[k]
				if shot >= 3 or not em.is_alive(sl) or not em.is_hostile(sl):
					continue
				var tp: Vector2 = em.pos_of(sl)
				em.queue_hit(sl, base_max(true) * 0.8, K.DmgColor.WHITE, false, (tp - pp).normalized(), 0.3)
				_fx(Fx.LINE, pp + Vector2(0, -14), tp - pp, 0.0, K.DmgColor.WHITE)
				shot += 1
	# 제석·대감 가호: 금줄 결계(10초, 금줄 권능 시 interval_s)마다 3초간 반경 안 잡귀 밀침
	if faces.get(&"deity_jeseok_daegam", &"") == &"gaho":
		var giv: float = 10.0
		var gr: float = 3.0
		if powers.has("pwr_jeseok_daegam_geumjul"):
			giv = _gv("pwr_jeseok_daegam_geumjul", "interval_s", 8.0)
			gr += _gv("pwr_jeseok_daegam_geumjul", "radius_add", 0.5)
		if _ready_cd("geumjul", giv, now):
			geumjul_t0 = now
			geumjul_r = gr * K.UNIT_PX
			_geumjul_next_tick = now
		if now - geumjul_t0 < 3.0:
			geumjul_c = pp
			if now >= _geumjul_next_tick:
				_geumjul_next_tick = now + 0.5
				strike_circle(pp, geumjul_r, base_max(true) * 0.25, K.DmgColor.WHITE, 1.0, 40)
	# 장군 군웅 행진: 영가 8명당 장단 −(Lv) %, 최대 3중첩(1초마다 갱신)
	if powers.has("pwr_janggun_gunung_haengjin"):
		var sec: int = int(now)
		if sec != _haengjin_sec:
			_haengjin_sec = sec
			var yc: int = 0
			if Game.run_root != null:
				var yt: Variant = Game.run_root.get("yeongga")
				if yt is Object:
					yc = int((yt as Object).get("count"))
			var want: float = _gv("pwr_janggun_gunung_haengjin", "jangdan_per_stack_pct", -2.0) * 0.01 * float(mini(3, yc / 8))
			if absf(want - _haengjin_applied) > 0.0001:
				Game.stats[&"stat_jangdan"] = maxf(0.4, Game.stat(&"stat_jangdan", 1.0) + want - _haengjin_applied)
				_haengjin_applied = want


## 넋 구슬 한 움큼(용궁 보물·대감 상자 근사). value = 다음 레벨 경험치의 3% × n 알.
func _orb_gift(pos: Vector2, n_orbs: int) -> void:
	var pm: Object = Game.pickups
	if pm == null or not pm.has_method("spawn_orb"):
		return
	var v: float = maxf(2.0, Game.xp_next * 0.03)
	for k in n_orbs:
		pm.call("spawn_orb", pos + Vector2.from_angle(TAU * float(k) / float(n_orbs)) * 10.0, v)
	_fx(Fx.ORB_GIFT, pos, Vector2.ZERO, 14.0, K.DmgColor.NONE)


## 무구 적중(Events.enemy_hit, 화신 아님). 같은 틱 발동 2회 상한(연쇄 방지).
func on_enemy_hit(pos: Vector2, dmg: float, color: int) -> void:
	if powers.is_empty() and not faces.has(&"deity_sansin"):
		return
	var t: int = Game.game_tick
	if t != _proc_tick:
		_proc_tick = t
		_proc_n = 0
	if _proc_n >= 2 or dmg <= 1.5:
		return
	_hits += 1
	var now: float = Game.time_sec()
	if faces.get(&"deity_sansin", &"") == &"wieom" and _hits % 8 == 0 and _ready_cd("beom_pohyo", 1.0, now):
		_proc_n += 1
		var pp: Vector2 = Game.player.global_position if Game.player != null else pos
		strike_circle(pp, 3.5 * K.UNIT_PX, base_max(false) * 0.5, K.DmgColor.RED, 1.2)
		_fx(Fx.PULSE, pp, Vector2.ZERO, 3.5 * K.UNIT_PX, K.DmgColor.RED)
	if powers.has("pwr_sansin_beom_baltop") and color != K.DmgColor.WHITE:
		if _rng.randf() * 100.0 < _gv("pwr_sansin_beom_baltop", "proc_chance_pct", 12.0):
			_proc_n += 1
			strike_circle(pos, 0.9 * K.UNIT_PX, dmg * 0.5, _face_color(&"deity_sansin"), 0.2, 3)
			_fx(Fx.CLAW, pos, Vector2.ZERO, 12.0, _face_color(&"deity_sansin"))
	if powers.has("pwr_yongwang_mulbora"):
		if _rng.randf() * 100.0 < _gv("pwr_yongwang_mulbora", "proc_chance_pct", 10.0):
			_proc_n += 1
			strike_circle(pos, 1.2 * K.UNIT_PX, dmg * 0.3, color, 0.4, 8)
			_fx(Fx.SPLASH, pos, Vector2.ZERO, 1.2 * K.UNIT_PX, color)


func on_weapon_fired(w: WeaponBase) -> void:
	if w == null or w.color == K.DmgColor.WHITE:
		return
	if not powers.has("pwr_janggun_geommu"):
		return
	_casts += 1
	var every: int = int(_gv("pwr_janggun_geommu", "every_casts", 5.0))
	if _casts % maxi(1, every) == 0 and Game.player != null:
		var pp: Vector2 = Game.player.global_position
		var r: float = _gv("pwr_janggun_geommu", "radius", 2.5) * K.UNIT_PX
		strike_circle(pp, r, base_max(false) * _gv("pwr_janggun_geommu", "dmg_x_base_red", 1.5), K.DmgColor.RED, 0.8)
		_fx(Fx.SPIN, pp, Vector2.ZERO, r, K.DmgColor.RED)


func on_enemy_killed(kind: StringName, pos: Vector2 = Vector2.ZERO, tier: StringName = &"") -> void:
	if Game.player == null:
		return
	var now: float = Game.time_sec()
	var elite: bool = tier != &"" and tier != K.TIER_COMMON and tier != K.TIER_MINION
	if elite:
		var gift: float = 0.0
		if powers.has("pwr_yongwang_yonggung_bomul"):
			gift += _gv("pwr_yongwang_yonggung_bomul", "box_upgrade_pct", 10.0)
		if faces.get(&"deity_jeseok_daegam", &"") == &"wieom":
			gift += 25.0
		if gift > 0.0 and _rng.randf() * 100.0 < gift:
			_orb_gift(pos, 3)
		if powers.has("pwr_jeseok_daegam_siru"):
			(Game.player as Player).hit.heal(Game.hp_max * _gv("pwr_jeseok_daegam_siru", "offering_heal_pct", 25.0) * 0.002)
			_fx(Fx.PULSE, Game.player.global_position, Vector2.ZERO, 1.5 * K.UNIT_PX, K.DmgColor.NONE)
	if kind == K.KIND_TOECHI:
		# 바리 위엄 무장승: 퇴치 → 넋 구슬 전환(면 20% + 권능, 상한 50%)
		var conv: float = 0.0
		if faces.get(&"deity_barigongju", &"") == &"wieom":
			conv += 20.0 * (1.0 if bool(complete.get(&"deity_barigongju", true)) else 0.7)
		if powers.has("pwr_barigongju_mujangseung"):
			conv += _gv("pwr_barigongju_mujangseung", "neok_convert_add_pct", 10.0)
		if conv > 0.0 and _rng.randf() * 100.0 < minf(50.0, conv):
			var pm: Object = Game.pickups
			if pm != null and pm.has_method("spawn_orb"):
				pm.call("spawn_orb", pos, maxf(1.0, Game.xp_next * 0.01))
		if powers.has("pwr_jeseok_daegam_donbaram"):
			_donbaram_kills += 1
			if _donbaram_kills % 10 == 0:
				var want: float = minf(0.30, float(_donbaram_kills / 10) * _gv("pwr_jeseok_daegam_donbaram", "red_dmg_pct_per_coin", 0.5) * 0.01)
				if want > _donbaram_applied:
					Game.stats[&"stat_sinppal"] = Game.stat(&"stat_sinppal", 1.0) + want - _donbaram_applied
					_donbaram_applied = want
		return
	# 용왕 가호: 해원 자리에 맑은 물(0.4초 내부쿨, 최대 8)
	if faces.get(&"deity_yongwang", &"") == &"gaho" and now >= _pool_cd:
		_pool_cd = now + 0.4
		var oldest: int = 0
		for i in POOL_CAP:
			if pool_t0[i] < pool_t0[oldest]:
				oldest = i
		pool_x[oldest] = pos.x
		pool_y[oldest] = pos.y
		var rm: float = 1.0
		if powers.has("pwr_yongwang_neokgeonjigi"):
			rm += _gv("pwr_yongwang_neokgeonjigi", "clear_water_radius_pct", 0.0) * 0.01
		pool_r[oldest] = 1.2 * K.UNIT_PX * rm
		pool_t0[oldest] = now
		pool_next[oldest] = now + 0.3
	if not powers.has("pwr_barigongju_yaksu"):
		return
	var sec: int = int(Game.time_sec())
	if sec != _heal_sec:
		_heal_sec = sec
		_heal_acc = 0.0
	var cap: float = _gv("pwr_barigongju_yaksu", "heal_cap_per_s", 3.0)
	var h: float = minf(_gv("pwr_barigongju_yaksu", "heal_per_haewon", 0.2), cap - _heal_acc)
	if h > 0.0:
		_heal_acc += h
		(Game.player as Player).hit.heal(h)


func on_ring_closed(centroid: Vector2, area: int) -> void:
	if area <= 0:
		return
	if powers.has("pwr_jeseok_daegam_yeomju"):
		var rr0: float = sqrt(float(area)) * K.UNIT_PX * 0.55
		strike_circle(centroid, rr0, base_max(true) * (1.0 + _gv("pwr_jeseok_daegam_yeomju", "ring_dmg_pct", 20.0) * 0.01), K.DmgColor.WHITE, 0.5, 60)
		_fx(Fx.PULSE, centroid, Vector2.ZERO, rr0, K.DmgColor.WHITE)
	var stars: int = 0
	var col: int = K.DmgColor.WHITE
	if faces.get(&"deity_chilseong", &"") == &"gaho":
		stars = 7
	if powers.has("pwr_chilseong_byeolgil"):
		stars = maxi(stars, int(_gv("pwr_chilseong_byeolgil", "stars", 3.0)))
		col = _face_color(&"deity_chilseong")
	if stars <= 0:
		return
	var rr: float = sqrt(float(area)) * K.UNIT_PX * 0.5
	for k in stars:
		var p: Vector2 = centroid + Vector2.from_angle(TAU * float(k) / float(stars)) * rr
		strike_circle(p, 0.9 * K.UNIT_PX, base_max(col == K.DmgColor.WHITE) * 0.5, col, 0.2, 8)
		_fx(Fx.STAR_FALL, p, Vector2.ZERO, 0.9 * K.UNIT_PX, col)


## 무당 피격(Events.player_damaged): 오방 호위 무적 연장 · 명 잇기 회복.
func on_player_damaged(amount: float) -> void:
	var pl: Player = Game.player as Player
	if pl == null or amount <= 0.0 or Game.hp <= 0.0:
		return
	if powers.has("pwr_janggun_obang_howi"):
		pl.hit.iframe_left += _gv("pwr_janggun_obang_howi", "iframe_add_s", 0.5)
	if powers.has("pwr_chilseong_myeong_itgi") and _rng.randf() * 100.0 < _gv("pwr_chilseong_myeong_itgi", "survive_chance_pct", 10.0):
		pl.hit.heal(amount)
		_fx(Fx.STAR_FALL, pl.global_position, Vector2.ZERO, 1.0 * K.UNIT_PX, K.DmgColor.WHITE)


## 풀릴 기색 진입(Events.pullil_entered): 삼색꽃 표식 → 즉시 백 피해(기준×2).
func on_pullil(handle: int, pos: Vector2) -> void:
	if not powers.has("pwr_barigongju_samsaekkot"):
		return
	if _rng.randf() * 100.0 >= _gv("pwr_barigongju_samsaekkot", "mark_chance_pct", 10.0):
		return
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	var sl: int = em.slot_of(handle)
	if sl < 0 or not em.is_alive(sl):
		return
	em.queue_hit(sl, base_max(true) * 2.0, K.DmgColor.WHITE)
	_fx(Fx.FLOWER, pos, Vector2.ZERO, 8.0, K.DmgColor.WHITE)


func on_cheondo() -> void:
	if not powers.has("pwr_barigongju_jeoseunggil") or Game.player == null:
		return
	var pp: Vector2 = Game.player.global_position
	var r: float = _gv("pwr_barigongju_jeoseunggil", "radius", 2.0) * K.UNIT_PX
	strike_circle(pp, r, base_max(true) * 0.6, _face_color(&"deity_barigongju"), 0.5, 16)
	_fx(Fx.PULSE, pp, Vector2.ZERO, r, _face_color(&"deity_barigongju"))


# ─── 합일 ──────────────────────────────────────────────────────────────

## 18:00 합일: 보유 권능 +1Lv, 강신 '합', 면 구성으로 3형 결정. 반환: form id.
func apply_hapil() -> StringName:
	var w: int = 0
	var g: int = 0
	for d: StringName in possessed:
		if faces.get(d, &"") == &"wieom":
			w += 1
		else:
			g += 1
	var form: StringName = &"hapil_yangmyeon"
	if w >= g + 2:
		form = &"hapil_wise"
	elif g >= w + 2:
		form = &"hapil_jabi"
	hapil_form = form
	for id: Variant in powers.keys():
		level_power(String(id))
	# 강신 '합': 현재 등급 → hap 누적 총합
	var gl: Array = Data.get_value("deities", "gangsin_grade", [])
	if gl.size() > 0 and gl[gl.size() - 1] is Dictionary:
		var hap: Dictionary = gl[gl.size() - 1]
		var cur: Dictionary = gl[clampi(gangsin, 0, gl.size() - 2)] if gl[clampi(gangsin, 0, gl.size() - 2)] is Dictionary else {}
		_hp_max_add(float(hap.get("max_jeonggi_add", 30)) - float(cur.get("max_jeonggi_add", 0)))
		add_stat("stat_sinppal", "add_pct", float(hap.get("sinppal_add_pct", 18)) - float(cur.get("sinppal_add_pct", 0)))
	match form:
		&"hapil_wise":
			add_stat("stat_gyeoldan", "add_pct", 10.0)
		&"hapil_jabi":
			Game.pullil_threshold = minf(0.6, Game.pullil_threshold + 0.10)
			add_stat("stat_haengnyeol", "add", 12.0)
		_:
			add_stat("stat_sinppal", "add_pct", 8.0)   # 결합 무구 +25% 근사(결합 필터 API 전까지 전체 +8%). TODO(deities)
	return form
