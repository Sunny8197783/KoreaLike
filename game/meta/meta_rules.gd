class_name MetaRules
extends RefCounted
## 메타 규칙(순수 함수): 가격 환산, 해금 조건, 신당 단장, 재가집 의뢰 풀, 정산 공식. 소유: meta.
## 원본 수치: data/meta_economy.json (income · characters · sindang_v1 · sindang_danjang · uiroe · singirok).
## 상태를 갖지 않는다(static var 금지). 프로필(Save.profile payload)은 인자로 받는다.

const CUR_G: StringName = &"cur_gongdeok"
const CUR_B: StringName = &"cur_bokjeon"

const R_CLEAR_BOW: String = "CLEAR_BOW"
const R_CLEAR_SAL: String = "CLEAR_SAL_GEODUM"
const R_DEATH: String = "DEATH"
const R_TIMEOUT_SAJA: String = "TIMEOUT_SAJA"   # 23:00 저승사자가 판을 거둠(보스 미해결) — 사망이 아니다
const R_ABANDON: String = "ABANDON"


# ─── 공통 ───────────────────────────────────────────────────────────────

static func econ(path: String, default: Variant = null) -> Variant:
	return Data.get_value("meta_economy", path, default)


static func num(path: String, default: float = 0.0) -> float:
	var v: Variant = econ(path, default)
	if v is float or v is int:
		return float(v)
	return default


## 기준가 → 표시가(econ_price_scale 곱, 100 단위 반올림). 09 §3.2 / income.econ_price_scale.
static func price(base: float) -> int:
	if base <= 0.0:
		return 0
	var s: float = num("income.econ_price_scale", 2.1)
	var r: float = maxf(1.0, num("income.econ_price_scale_rounding", 100.0))
	return int(roundf(base * s / r) * r)


static func currency_name(cur: StringName) -> String:
	match cur:
		CUR_G: return "공덕"
		CUR_B: return "엽전"   # 화면 표기 통합(design/19 §2.5): 복전 → 엽전. 내부 키 cur_bokjeon 은 그대로
		&"cur_neok": return "넋"
		&"cur_yeopjeon": return "엽전"
	return String(cur)


## 받침 유무로 조사 고르기: josa("단골", "과", "와") → "과"
static func josa(word: String, with_batchim: String, without: String) -> String:
	if word.is_empty():
		return without
	var c: int = word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3:
		return without
	return with_batchim if (c - 0xAC00) % 28 != 0 else without


static func counter(p: Dictionary, id: String) -> int:
	var c: Variant = p.get("counters", {})
	return int((c as Dictionary).get(id, 0)) if c is Dictionary else 0


static func runs_done(p: Dictionary) -> int:
	return counter(p, "cnt_runs")


static func has_in(p: Dictionary, group: String, key: String, id: String) -> bool:
	var g: Variant = p.get(group, {})
	if not (g is Dictionary):
		return false
	var arr: Variant = (g as Dictionary).get(key, [])
	return arr is Array and (arr as Array).has(id)


# ─── 무당 해금 (meta_economy.characters + sindang_v1.char_condition_override) ──

static func char_defs() -> Array:
	var out: Array = []
	var arr: Variant = econ("characters", [])
	if arr is Array:
		for c: Variant in arr:
			if c is Dictionary and String((c as Dictionary).get("scope", "v1")) == "v1":
				out.append(c)
	return out


static func char_def(id: String) -> Dictionary:
	for c: Variant in char_defs():
		if String((c as Dictionary).get("id", "")) == id:
			return c
	return {}


## {counter, gte, text} — v1 임시 대체 조건이 있으면 그것.
static func char_condition(id: String) -> Dictionary:
	var ov: Variant = econ("sindang_v1.char_condition_override." + id, null)
	if ov is Dictionary:
		return ov
	var d: Dictionary = char_def(id)
	var c: Variant = d.get("condition", null)
	if c is Dictionary:
		var out: Dictionary = (c as Dictionary).duplicate()
		out["text"] = String(d.get("condition_text", ""))
		return out
	return {}


static func char_cost(id: String) -> int:
	return price(float(char_def(id).get("cost_gongdeok", 0)))


static func char_unlocked(p: Dictionary, id: String) -> bool:
	if char_cost(id) <= 0 and char_condition(id).is_empty():
		return true
	return has_in(p, "unlocks", "chars", id)


## 조건 진행 [cur, need]. 조건 없음이면 [1, 1].
static func char_progress(p: Dictionary, id: String) -> Vector2i:
	var c: Dictionary = char_condition(id)
	if c.is_empty():
		return Vector2i(1, 1)
	var need: int = int(c.get("gte", 1))
	return Vector2i(mini(counter(p, String(c.get("counter", ""))), need), need)


static func char_ready(p: Dictionary, id: String) -> bool:
	var pr: Vector2i = char_progress(p, id)
	return pr.x >= pr.y


# ─── 신당 단장 (sindang_danjang.items) ───────────────────────────────────

static func danjang_items() -> Array:
	var v: Variant = econ("sindang_danjang.items", [])
	return v if v is Array else []


static func danjang_item(id: String) -> Dictionary:
	for it: Variant in danjang_items():
		if String((it as Dictionary).get("id", "")) == id:
			return it
	return {}


static func danjang_rank(p: Dictionary, id: String) -> int:
	var d: Variant = p.get("danjang", {})
	return int((d as Dictionary).get(id, 0)) if d is Dictionary else 0


## 다음 랭크 표시가(최대면 -1).
static func danjang_next_cost(p: Dictionary, id: String) -> int:
	var it: Dictionary = danjang_item(id)
	var r: int = danjang_rank(p, id)
	var costs: Variant = it.get("costs", [])
	if not (costs is Array) or r >= int(it.get("max_rank", 0)) or r >= (costs as Array).size():
		return -1
	return price(float((costs as Array)[r]))


static func danjang_currency(id: String) -> StringName:
	return StringName(String(danjang_item(id).get("currency", "cur_gongdeok")))


## 런 시작 시 Game.stats 에 더할 값 {stat_id: add}.
static func danjang_stat_bonus(p: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for it: Variant in danjang_items():
		var d: Dictionary = it
		var r: int = danjang_rank(p, String(d.get("id", "")))
		if r <= 0:
			continue
		var st: StringName = StringName(String(d.get("stat", "")))
		out[st] = float(out.get(st, 0.0)) + float(d.get("per_rank", 0.0)) * r
	return out


## 쉬운 말 효과(design/19 §2.4): 스탯 하나·값 하나 → '체력 +10' / '공격력 +4%'. 모르는 스탯은 effect_ko 를 쓴다.
const STAT_EASY: Dictionary = {
	"stat_jeonggi": ["체력", "n"], "stat_sinbok": ["방어", "n"], "stat_neok_sumyeong": ["넋 동무 머묾", "s"],
	"stat_haengnyeol": ["넋 동무 수", "n"], "stat_gilbe": ["흰 길", "s1"], "stat_puri": ["풀기 힘", "p"],
	"stat_sinppal": ["공격력", "p"], "stat_doryang": ["범위", "p"], "stat_gyeoldan": ["치명타", "pp"],
	"stat_chohon": ["줍기 범위", "f1"], "stat_domu": ["이동 속도", "p"], "stat_siju": ["얻는 공덕·엽전", "p"],
}


static func stat_easy(stat: String, v: float) -> String:
	var e: Variant = STAT_EASY.get(stat, null)
	if not (e is Array):
		return ""
	var nm: String = String((e as Array)[0])
	match String((e as Array)[1]):
		"n": return "%s +%d" % [nm, int(roundf(v))]
		"s": return "%s +%d초" % [nm, int(roundf(v))]
		"s1": return "%s +%s초" % [nm, _fmt_mult(v)]
		"p": return "%s +%d%%" % [nm, int(roundf(v * 100.0))]
		"pp": return "%s +%d%%p" % [nm, int(roundf(v * 100.0))]
		"f1": return "%s +%s" % [nm, _fmt_mult(v)]
	return ""


## 신당 강화 한 칸의 다음 단계 효과(쉬운 말). 없으면 데이터 effect_ko.
static func danjang_effect_easy(id: String) -> String:
	var d: Dictionary = danjang_item(id)
	var s: String = stat_easy(String(d.get("stat", "")), float(d.get("per_rank", 0.0)))
	return s if s != "" else String(d.get("effect_ko", ""))


# ─── 시설 개방 (sindang_v1) ─────────────────────────────────────────────

static func facility_open(p: Dictionary, key: String) -> bool:
	var need: int = int(num("sindang_v1." + key, 0.0))
	return runs_done(p) >= need


static func first_run_pending(p: Dictionary) -> bool:
	if not bool(econ("sindang_v1.first_run_direct", true)):
		return false
	return runs_done(p) <= 0 and not bool((p.get("flags", {}) as Dictionary).get("tutorial_done", false))


# ─── 재가집 의뢰 (uiroe + sindang_v1.uiroe_v1_pool) ──────────────────────

static func uiroe_def(id: String) -> Dictionary:
	var arr: Variant = econ("uiroe.samples", [])
	if arr is Array:
		for u: Variant in arr:
			if u is Dictionary and String((u as Dictionary).get("id", "")) == id:
				return u
	return {}


static func uiroe_available(p: Dictionary, id: String) -> bool:
	var d: Dictionary = uiroe_def(id)
	if d.is_empty():
		return false
	var rule: Variant = econ("sindang_v1.uiroe_unlock_rules." + String(d.get("unlock", "기본")), "missing")
	if rule == null:
		return true
	if rule is Dictionary and (rule as Dictionary).has("char"):
		return char_unlocked(p, String((rule as Dictionary)["char"]))
	return false


static func uiroe_pool(p: Dictionary) -> Array:
	var out: Array = []
	var pool: Variant = econ("sindang_v1.uiroe_v1_pool", [])
	if pool is Array:
		for id: Variant in pool:
			if uiroe_available(p, String(id)):
				out.append(String(id))
	return out


static func uiroe_currency_mult(id: String) -> Dictionary:
	var r: Variant = uiroe_def(id).get("reward", {})
	if r is Dictionary and (r as Dictionary).get("currency_mult") is Dictionary:
		return (r as Dictionary)["currency_mult"]
	return {}


static func uiroe_record_x2(id: String) -> Dictionary:
	var r: Variant = uiroe_def(id).get("reward", {})
	if r is Dictionary and (r as Dictionary).get("record_x2") is Dictionary:
		return (r as Dictionary)["record_x2"]
	return {}


## 의뢰 한 장을 사람이 읽을 문장으로: {sayeon, mods: [String], reward: String}
static func uiroe_text(id: String) -> Dictionary:
	var d: Dictionary = uiroe_def(id)
	var mods: Array[String] = []
	var m: Variant = d.get("mods", {})
	if m is Dictionary:
		var md: Dictionary = m
		if md.get("species_weight") is Dictionary:
			for sp: String in md["species_weight"]:
				mods.append("%s 출현 ×%s" % [enemy_ko(sp), _fmt_mult(float(md["species_weight"][sp]))])
		if md.has("deity_guarantee"):
			mods.append("06:30 신령의 시험: %s" % deity_ko(String(md["deity_guarantee"])))
		if md.has("mboss_fixed"):
			mods.append("10:00 큰 귀신: %s" % enemy_ko(String(md["mboss_fixed"])))
		if md.has("neok_sumyeong_add_s"):
			mods.append("넋 동무 머무는 시간 %+d초" % int(md["neok_sumyeong_add_s"]))
		if md.has("salgi_base_add"):
			mods.append("시작 원한 +%d" % int(md["salgi_base_add"]))
	var reward: String = ""
	var cm: Dictionary = uiroe_currency_mult(id)
	for c: String in cm:
		reward = "%s ×%s (굿을 마치면)" % [currency_name(StringName(c)), _fmt_mult(float(cm[c]))]
	var rx: Dictionary = uiroe_record_x2(id)
	if not rx.is_empty():
		var names: Array[String] = []
		for sp: String in rx:
			names.append(enemy_ko(sp))
		reward = "%s 도감 기록 ×2" % "·".join(names)
	return {"sayeon": String(d.get("sayeon_ko", id)), "mods": mods, "reward": reward}


static func _fmt_mult(v: float) -> String:
	return ("%.1f" % v) if absf(v - roundf(v)) > 0.01 else str(int(roundf(v)))


static func enemy_ko(id: String) -> String:
	var e: Dictionary = Data.enemy(id)
	var n: Variant = e.get("name_ko", e.get("name", id))
	if n is Dictionary:
		return String((n as Dictionary).get("ko", id))
	return String(n)


static func deity_ko(id: String) -> String:
	var d: Dictionary = Data.deity(id)
	var n: Variant = d.get("name_ko", d.get("name", id))
	if n is Dictionary:
		return String((n as Dictionary).get("ko", id))
	return String(n)


# ─── 넋기록 (singirok) ─────────────────────────────────────────────────

## 벽사록 단계(0..3) — thresholds.<tier_group>
static func byeoksa_tier(tier_group: String, toechi: int) -> int:
	var th: Variant = econ("singirok.byeoksarok.thresholds." + tier_group, [100, 600, 2500])
	var t: int = 0
	if th is Array:
		for v: Variant in th:
			if toechi >= int(v):
				t += 1
	return t


static func tier_group(tier: StringName) -> String:
	match tier:
		K.TIER_ELITE: return "elite"
		K.TIER_MBOSS: return "mboss"
		K.TIER_BOSS: return "boss"
	return "normal"


# ─── 정산 (09 §3.2, v1 단순화) ───────────────────────────────────────────
## run: {result, haewon, toechi, cheondo_neok, elite_haewon, mboss_haewon, boss_haewon, elite_toechi,
##       mboss_toechi, boss_toechi, trial_gaho, trial_wieom, trial_gaho_half, trial_wieom_half, siju, geodum_p, uiroe}
## 반환: {N, neok_w, yeop_w, G, B, lines: Array[String], uiroe_done: bool}
static func compute_settlement(run: Dictionary) -> Dictionary:
	var ns: String = "income.neok_sources."
	var ys: String = "income.yeopjeon_sources."
	var h: int = int(run.get("haewon", 0))
	var t: int = int(run.get("toechi", 0))
	var n_ratio: float = float(h) / float(h + t) if h + t > 0 else 0.0
	var neok_w: float = float(h) * num(ns + "haewon", 1.0) + float(run.get("cheondo_neok", 0))
	neok_w += float(run.get("elite_haewon", 0)) * num(ns + "box_neokham_elite", 60.0)
	neok_w += float(run.get("mboss_haewon", 0)) * num(ns + "mboss_haewon_neokham", 300.0)
	neok_w += float(run.get("boss_haewon", 0)) * num(ns + "boss_han_neokham_total", 1500.0)
	neok_w += (float(run.get("trial_gaho", 0)) + 0.5 * float(run.get("trial_gaho_half", 0))) * num(ns + "trial_gaho", 40.0)
	var yeop_w: float = float(run.get("elite_toechi", 0)) * num(ys + "box_gilhyung_elite", 330.0)
	yeop_w += float(run.get("mboss_toechi", 0)) * num(ys + "box_gilhyung_mboss", 1000.0)
	yeop_w += float(run.get("boss_toechi", 0)) * num(ys + "box_gilhyung_boss_sal_total", 1800.0)
	yeop_w += (float(run.get("trial_wieom", 0)) + 0.5 * float(run.get("trial_wieom_half", 0))) * num(ys + "trial_wieom", 40.0)

	var lines: Array[String] = []
	var s: float = maxf(0.0, float(run.get("siju", 1.0)))
	var g: float = neok_w * num("income.conversion.cur_neok_to_cur_gongdeok", 1.0) * s
	var b: float = yeop_w * num("income.conversion.cur_yeopjeon_to_cur_bokjeon", 1.0) * s
	if absf(s - 1.0) > 0.001:
		lines.append("얻는 양 ×%.2f" % s)
	var band: Variant = econ("income.settlement.eoullim_band", [0.35, 0.65])
	var lo: float = float((band as Array)[0]) if band is Array else 0.35
	var hi: float = float((band as Array)[1]) if band is Array else 0.65
	if h + t > 0 and n_ratio >= lo and n_ratio <= hi:
		var e: float = num("income.settlement.eoullim_mult", 1.15)
		g *= e
		b *= e
		lines.append("반반 보너스 ×%.2f" % e)
	var result: String = String(run.get("result", R_DEATH))
	var clear: bool = result == R_CLEAR_BOW or result == R_CLEAR_SAL
	var uiroe_id: String = String(run.get("uiroe", ""))
	var uiroe_done: bool = clear and uiroe_id != ""
	if uiroe_done:
		var cm: Dictionary = uiroe_currency_mult(uiroe_id)
		var cap: float = num("uiroe.reward_caps.currency_mult_max", 1.2)
		for c: String in cm:
			var m: float = minf(float(cm[c]), cap)
			if c == "cur_neok":
				g *= m
			else:
				b *= m
			lines.append("특별 의뢰 %s ×%.1f" % [currency_name(StringName(c)), m])
	if result == R_CLEAR_BOW:
		var bow: float = num("income.settlement.saja_bow_gongdeok_mult", 1.5)
		g *= bow
		lines.append("역려를 풀어 보냄 ×%.1f" % bow)
	elif result == R_CLEAR_SAL:
		var p: float = clampf(float(run.get("geodum_p", 1.0)), 0.0, 1.0)
		var m2: float = 1.0 + num("income.settlement.sal_geodum_bokjeon_mult_max", 0.5) * p
		b *= m2
		lines.append("역려를 쓰러뜨림 ×%.2f" % m2)
	elif result == R_TIMEOUT_SAJA:
		# 사자가 판을 거두었다: 읍(×1.5)·의뢰 없음. 보스까지 버틴 몫 — 푼 매듭 하나당 공덕 +5%.
		var kn: int = timeout_knots(run)
		var mt: float = timeout_gongdeok_mult(kn)
		g *= mt
		lines.insert(0, "사자가 판을 거둠 · 푼 매듭 %d/%d ×%.2f" % [kn, int(num("income.settlement.timeout_knots_max", 7.0)), mt])
	var cap_w: float = 99999999.0
	return {"N": n_ratio, "neok_w": int(neok_w), "yeop_w": int(yeop_w),
		"G": int(clampf(floorf(g), 0.0, cap_w)), "B": int(clampf(floorf(b), 0.0, cap_w)),
		"lines": lines, "uiroe_done": uiroe_done}


## 시간 초과 정산의 보스 진행 매듭 수(0..timeout_knots_max). run.boss_knots: Save 가 보스 한 감소분으로 센다.
static func timeout_knots(run: Dictionary) -> int:
	return clampi(int(run.get("boss_knots", 0)), 0, int(num("income.settlement.timeout_knots_max", 7.0)))


## 시간 초과 공덕 배율 = 기본(×1.0) + 매듭당 가산(+0.05).
static func timeout_gongdeok_mult(knots: int) -> float:
	return num("income.settlement.timeout_gongdeok_mult", 1.0) + num("income.settlement.timeout_gongdeok_per_knot", 0.05) * float(maxi(knots, 0))


# ─── 무구 해금 (meta_economy.weapons, 09 §6) ─────────────────────────────

static func weapon_defs() -> Array:
	var v: Variant = econ("weapons", [])
	return v if v is Array else []


static func weapon_def(id: String) -> Dictionary:
	for w: Variant in weapon_defs():
		if String((w as Dictionary).get("id", "")) == id:
			return w
	return {}


static func weapon_cost(id: String) -> int:
	return price(float(weapon_def(id).get("cost", 0)))


static func weapon_currency(id: String) -> StringName:
	var c: Variant = weapon_def(id).get("currency", null)
	return StringName(String(c)) if c != null else CUR_G


## 같은 색 무구를 몇 개 봉헌/제작했는가(기본 해금 제외).
static func weapons_bought_of_color(p: Dictionary, color: String) -> int:
	var n: int = 0
	for w: Variant in weapon_defs():
		var d: Dictionary = w
		if String(d.get("color", "")) == color and not bool(d.get("default_unlocked", false)) and has_in(p, "unlocks", "weapons", String(d.get("id", ""))):
			n += 1
	return n


## 해금 상태: "owned" | "buyable" | "gate"(같은 색 선행 부족) | "undiscovered"
static func weapon_state(p: Dictionary, id: String) -> String:
	var d: Dictionary = weapon_def(id)
	if bool(d.get("default_unlocked", false)) or has_in(p, "unlocks", "weapons", id):
		return "owned"
	if d.get("discover_condition") != null and not has_in(p, "unlocks", "weapons_discovered", id):
		return "undiscovered"
	if weapons_bought_of_color(p, String(d.get("color", ""))) < int(d.get("gate_same_color_purchased", 0)):
		return "gate"
	return "buyable"
