class_name WeaponManager
extends Node2D
## 무구 슬롯(최대 6)·패시브(최대 6)·진화·결합 관리 + 틱 10·12 단계 + 무구 연출 그리기. 소유: combat.
##
## 공개 API
##   setup_character(id)                    캐릭터 시작 무구(characters.json start_weapons, at_s 예약)
##   add_or_level(id) -> int                무구(wpn_*) 또는 패시브(psv_*) 획득/레벨 +1. 반환: 결과 레벨(실패 -1)
##   has_weapon(id) / level_of(id) / weapon_at(slot) / slot_count() / passive_level(id) / passive_count()
##   get_offer_pool() -> Array[Dictionary]  점지 후보 전체(가중치 포함, stats.json jeomji 규칙): {kind, id, level, title, desc, weight, color, is_new}
##   roll_offers(n := 3) -> Array[Dictionary]  가중 추첨 + 보장(G2·G6·G3, 사후 G4) — Rng "jeomji"
##   offer_candidates() -> Array[Dictionary]  = roll_offers(3) (ui/levelup.gd 호환: 3장이면 그대로 표시됨)
##   apply_offer(choice) -> bool            카드 적용(무구·패시브·충전 항목). ui 가 무구만 add_or_level 로 처리하는 현행 경로도 지원:
##                                          패시브·충전 카드는 Events.levelup_chosen 을 받아 여기서 적용한다(중복 적용 방지 플래그 "_applied").
##   open_box(box_id, items := 1) -> Array[Dictionary]  길흉 상자·넋함 내용(결합 → 진화 → 무구 +1 → 패시브 +1 → 엽전, 상자당 결합+진화 1회)
##   can_evolve(weapon_id) / evolve(weapon_id) -> bool / unite(union_id) -> bool / evolvable_ids() -> Array
##   target_mult(enemy_slot) -> float       표식(삼지창)·공포(호작도) 피해 증폭 — WeaponBase.deal 이 사용
##   set_mark(enemy_slot, dur_s, amp) / set_fear(enemy_slot, dur_s, amp) / set_buff(key, strength)
##   on_projectile_hit / on_projectile_end / on_projectile_step   ProjectilePool 콜백

const MAX_SLOTS: int = 6
const MAX_PASSIVES: int = 6

var slots: Array[WeaponBase] = []
var passive_lv: Dictionary = {}          # psv_id(StringName) -> level
var passive_order: Array[StringName] = []
var _schedule: Array = []                # [{wpn, at_s}] 캐릭터 시작 무구
var _stat_base: Dictionary = {}          # 패시브 적용 전 Game.stats 사본
var _buff: Dictionary = {}               # 오방기 버프 key -> 배율
var _mark_h: PackedInt32Array = PackedInt32Array()
var _mark_until: PackedInt32Array = PackedInt32Array()
var _mark_amp: PackedFloat32Array = PackedFloat32Array()
var _fear_h: PackedInt32Array = PackedInt32Array()
var _fear_until: PackedInt32Array = PackedInt32Array()
var _fear_amp: PackedFloat32Array = PackedFloat32Array()
var _hit_sfx_tick: PackedInt32Array = PackedInt32Array()
var _hit_sfx_frame_tick: int = -1
var _hit_sfx_frame_n: int = 0
var _jeomji_count: int = 0
var _last_g2: int = -100
var _last_g7: int = -100
var _offer_trace_left: int = 12          # --autotest: 진화·결합 조건 문구가 붙은 카드 앞 12장만 로그
var _ground: Node2D = null
var _debug_spec: String = ""
var _verdict_ready_tick: int = 0


## 가산 층(design/19 §5.1): art_vfx_list 가 add 로 지정한 무구 시트와 첫 프레임 한지 겹침을 BLEND_ADD 로 그린다.
## 본 층 _draw 에서 WeaponBase.draw_sheet/add_overlay 가 명령을 쌓고, 자식 _add_ci 의 draw 가 그대로 재생한다(머티리얼 1개).
var _add_ci: Node2D = null
var add_cmds: Array = []                 # [texture, dst Rect2, src Rect2, Transform2D, modulate]
var big_sheets: int = 0                  # 이번 프레임 그린 64px 넘는 원샷 시트 수(design/19 §5.1: 동시 4, 군중 3)


func _ready() -> void:
	z_index = 4                          # 내 무구 VFX 는 앞줄 잡귀(z3) 위(design/19 §5.1 그리기 순서)
	_mark_h.resize(EnemyManager.CAPACITY)
	_mark_h.fill(-1)
	_mark_until.resize(EnemyManager.CAPACITY)
	_mark_amp.resize(EnemyManager.CAPACITY)
	_fear_h.resize(EnemyManager.CAPACITY)
	_fear_h.fill(-1)
	_fear_until.resize(EnemyManager.CAPACITY)
	_fear_amp.resize(EnemyManager.CAPACITY)
	_hit_sfx_tick.resize(MAX_SLOTS + 1)
	_hit_sfx_tick.fill(-100)
	# 바닥 장판 층(지면 위·적 아래): 자기 노드 하위 자식
	_ground = Node2D.new()
	_ground.name = "WeaponGround"
	_ground.z_as_relative = false
	_ground.z_index = -2
	add_child(_ground)
	_ground.draw.connect(_draw_ground)
	_add_ci = Node2D.new()
	_add_ci.name = "WeaponAdd"
	var am: CanvasItemMaterial = CanvasItemMaterial.new()
	am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add_ci.material = am
	add_child(_add_ci)
	_add_ci.draw.connect(_draw_add)
	Events.levelup_chosen.connect(_on_levelup_chosen)
	Events.enemy_killed.connect(_on_enemy_killed)


func setup_character(char_id: StringName) -> void:
	for w in slots:
		w.dispose()
	slots.clear()
	passive_lv.clear()
	passive_order.clear()
	_buff.clear()
	_schedule.clear()
	_stat_base = Game.stats.duplicate()
	var ch: Dictionary = Data.character(String(char_id))
	var sw: Variant = ch.get("start_weapons", [])
	if sw is Array:
		for e: Variant in sw:
			if e is Dictionary:
				_schedule.append({"wpn": String(e.get("wpn", "")), "at_s": float(e.get("at_s", 0.0))})
			elif e is String:
				_schedule.append({"wpn": e, "at_s": 0.0})
	if _schedule.is_empty():
		_schedule.append({"wpn": "wpn_sinkal", "at_s": 0.0})
	# 디버그·캡처: --wpn=wpn_woldo:8,psv_obangkkeun:1,evo_manwoldo,union_neoksinkal (런 시작 시 지급)
	_debug_spec = DebugTools.arg("wpn")


## 연습 굿판(design/17 §7.3): 시작 무구 예약 중 wpn_id(빈 값이면 전부)를 지운다.
func drop_schedule(wpn_id: StringName = &"") -> void:
	for k in range(_schedule.size() - 1, -1, -1):
		if wpn_id == &"" or StringName(String(_schedule[k]["wpn"])) == wpn_id:
			_schedule.remove_at(k)


func slot_count() -> int:
	return slots.size()


func weapon_at(i: int) -> WeaponBase:
	return slots[i] if i >= 0 and i < slots.size() else null


func has_weapon(id: StringName) -> bool:
	return level_of(id) > 0


func level_of(id: StringName) -> int:
	for w in slots:
		if w.id == id:
			return w.level
	return 0


func passive_level(id: StringName) -> int:
	return int(passive_lv.get(id, 0))


func passive_count() -> int:
	return passive_order.size()


func add_or_level(item_id: StringName) -> int:
	var sid: String = Data.resolve_id(String(item_id))
	if sid.begins_with("psv_"):
		return _add_passive(StringName(sid))
	if sid.begins_with("evo_") or sid.begins_with("union_"):
		return 1 if _grant_special(StringName(sid)) else -1
	var vdef: Dictionary = {}
	if Data.weapon(sid).is_empty():
		vdef = _variant_def(sid)          # 캐릭터 고유 변형(심방 멩두 신칼·요령) → 원본 id 로 취급
		if not vdef.is_empty():
			sid = String(vdef.get("id", sid))
	var weapon_id: StringName = StringName(sid)
	for w in slots:
		if w.id == weapon_id:
			if w.level >= w.max_level:
				return -1
			w.set_level(w.level + 1)
			Events.weapon_leveled.emit(w.id, w.level)
			_trace("%s L%d" % [w.id, w.level])
			return w.level
	if slots.size() >= MAX_SLOTS:
		return -1
	var def: Dictionary = vdef if not vdef.is_empty() else Data.weapon(sid)
	if def.is_empty():
		push_warning("[WeaponManager] 알 수 없는 무구: %s" % weapon_id)
		return -1
	var nw: WeaponBase = ArchetypeRegistry.create(def, slots.size(), self)
	slots.append(nw)
	Events.weapon_added.emit(nw.id, nw.slot)
	_trace("%s new" % nw.id)
	return 1


## characters.json weapon_variants: {id, base, overrides{radius_mult, hit_rate_mult, dmg_mult}} → 원본 정의 사본(id = base).
## 레벨 행에 배율을 미리 곱한다(진화 후에는 원본 진화 정의를 쓴다 — persist_on_evolution 은 외형만).
func _variant_def(vid: String) -> Dictionary:
	var vl: Variant = Data.get_value("characters", "weapon_variants", [])
	if not (vl is Array):
		return {}
	for v: Variant in vl:
		if not (v is Dictionary) or String(v.get("id", "")) != vid:
			continue
		var base: Dictionary = Data.weapon(String(v.get("base", "")))
		if base.is_empty():
			return {}
		var d: Dictionary = base.duplicate(true)
		var ov: Dictionary = v.get("overrides", {}) if v.get("overrides", {}) is Dictionary else {}
		var rm: float = float(ov.get("radius_mult", 1.0))
		var hm: float = maxf(0.1, float(ov.get("hit_rate_mult", 1.0)))
		var dm: float = float(ov.get("dmg_mult", 1.0))
		var lvls: Variant = d.get("levels", [])
		if lvls is Array:
			for row: Variant in lvls:
				if not (row is Dictionary):
					continue
				if row.has("area"):
					row["area"] = float(row["area"]) * rm
				if row.has("cd"):
					row["cd"] = float(row["cd"]) / hm
				if row.has("dmg"):
					row["dmg"] = float(row["dmg"]) * dm
		d["variant_of"] = vid
		return d
	return {}


## 틱 10 + 12: 발사(박 양자화)와 지속 효과.
func sim_step(dt: float) -> void:
	var t: float = Game.time_sec()
	for k in range(_schedule.size() - 1, -1, -1):
		if t >= float(_schedule[k]["at_s"]):
			add_or_level(StringName(_schedule[k]["wpn"]))
			_schedule.remove_at(k)
	if _debug_spec != "":
		_debug_grant(_debug_spec)
		_debug_spec = ""
	for w in slots:
		w.sim_step(dt)


func on_projectile_hit(weapon_slot: int, enemy_slot: int, dmg: float, dir: Vector2, tag: int = 0, proj_index: int = -1) -> void:
	var w: WeaponBase = weapon_at(weapon_slot)
	if w != null:
		w.on_projectile_hit(enemy_slot, dmg, dir, tag, proj_index)


func on_projectile_end(weapon_slot: int, tag: int, pos: Vector2, vel: Vector2, reason: int) -> void:
	var w: WeaponBase = weapon_at(weapon_slot)
	if w != null:
		w.on_projectile_end(tag, pos, vel, reason)


func on_projectile_step(weapon_slot: int, tag: int, proj_index: int, pos: Vector2) -> void:
	var w: WeaponBase = weapon_at(weapon_slot)
	if w != null:
		w.on_projectile_step(tag, proj_index, pos)


# ─── 피해 증폭(표식·공포) ─────────────────────────────────────────

func target_mult(enemy_slot: int) -> float:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return 1.0
	var h: int = em.handle_of(enemy_slot)
	var m: float = 1.0
	var t: int = Game.game_tick
	if _mark_h[enemy_slot] == h and t < _mark_until[enemy_slot]:
		m *= 1.0 + _mark_amp[enemy_slot]
	if _fear_h[enemy_slot] == h and t < _fear_until[enemy_slot]:
		m *= 1.0 + _fear_amp[enemy_slot]
	return m


func set_mark(enemy_slot: int, dur_s: float, amp: float) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	var h: int = em.handle_of(enemy_slot)
	var same: bool = _mark_h[enemy_slot] == h and Game.game_tick < _mark_until[enemy_slot]
	_mark_amp[enemy_slot] = maxf(_mark_amp[enemy_slot] if same else 0.0, amp)
	_mark_h[enemy_slot] = h
	_mark_until[enemy_slot] = Game.game_tick + int(dur_s * K.TICK_HZ)


## 사슬창 '사슬세우기' 판결(01 캐논): 표식이 붙은 대상을 퇴치하면 verdict_chance 로 길흉 상자(verdict_cd 초 내부 쿨다운).
func _on_enemy_killed(handle: int, _species: StringName, pos: Vector2, kind: StringName, _cause: StringName, _tier: StringName) -> void:
	if kind != K.KIND_TOECHI or Game.game_tick < _verdict_ready_tick:
		return
	var es: int = _slot_from_handle(handle)
	if es < 0 or _mark_h[es] != handle or Game.game_tick >= _mark_until[es]:
		return
	for w in slots:
		var ch: float = w.s("verdict_chance", 0.0)
		if ch <= 0.0:
			continue
		if Rng.chance(&"chest", ch):
			_verdict_ready_tick = Game.game_tick + int(w.s("verdict_cd", 45.0) * K.TICK_HZ)
			var pk: PickupManager = Game.pickups as PickupManager
			if pk != null:
				pk.spawn_box(&"box_gilhyung", pos, 0.0, 0)
			w.play_fx(w.fx_name("fx_verdict"), pos)
			Audio.play_sfx(&"sfx_wpn_samjichang_hit", &"SFX", -3.0)
		return


## 처치 신호 시점에는 대상이 소멸 중(F_ALIVE 유지)이라 표식 배열을 핸들로 대조할 수 있다.
func _slot_from_handle(handle: int) -> int:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null or handle < 0:
		return -1
	var es: int = handle & EnemyManager.SLOT_MASK
	return es if es < EnemyManager.CAPACITY else -1


func is_marked(enemy_slot: int) -> bool:
	var em: EnemyManager = Game.enemies as EnemyManager
	return em != null and _mark_h[enemy_slot] == em.handle_of(enemy_slot) and Game.game_tick < _mark_until[enemy_slot]


func set_fear(enemy_slot: int, dur_s: float, amp: float) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	_fear_h[enemy_slot] = em.handle_of(enemy_slot)
	_fear_until[enemy_slot] = Game.game_tick + int(dur_s * K.TICK_HZ)
	_fear_amp[enemy_slot] = amp


## 적중 효과음(무구별 4틱에 1회, 틱당 전체 3회 상한 — 군중 타격에서 소리가 뭉개지지 않게).
func note_hit(w: WeaponBase, _enemy_slot: int) -> void:
	var t: int = Game.game_tick
	if t != _hit_sfx_frame_tick:
		_hit_sfx_frame_tick = t
		_hit_sfx_frame_n = 0
	var k: int = clampi(w.slot, 0, MAX_SLOTS)
	if t - _hit_sfx_tick[k] < 4 or _hit_sfx_frame_n >= 3:
		return
	_hit_sfx_tick[k] = t
	_hit_sfx_frame_n += 1
	Audio.play_sfx(StringName("sfx_wpn_%s_hit" % w.stem), &"SFX", -9.0, 0.08)


# ─── 패시브(passives.json) — 스탯 반영 ────────────────────────────

func _add_passive(pid: StringName) -> int:
	var def: Dictionary = Data.passive(String(pid))
	if def.is_empty():
		return -1
	var cur: int = passive_level(pid)
	var mx: int = int(Data.get_value("passives", "_meta.rules.max_level", 5))
	if cur >= mx:
		return -1
	if cur == 0:
		if passive_order.size() >= MAX_PASSIVES:
			return -1
		passive_order.append(pid)
	passive_lv[pid] = cur + 1
	_recompute_stats()
	_trace("%s P%d" % [pid, cur + 1])
	return cur + 1


## 오방기 버프(장판 안): key cheong|jeok|hwang|baek, strength 0 = 해제.
func set_buff(key: StringName, strength: float) -> void:
	var cur: float = float(_buff.get(key, 0.0))
	if is_equal_approx(cur, strength):
		return
	if strength <= 0.0:
		_buff.erase(key)
	else:
		_buff[key] = strength
	_recompute_stats()


## Game.stats = 기본(캐릭터) + 패시브(flat 가산 → add_pct 가산 버킷) + 오방 버프. 정기(최대 HP)가 바뀌면 hp_max·hp 를 같은 양 이동.
func _recompute_stats() -> void:
	var flat: Dictionary = {}
	var pct: Dictionary = {}
	for pid in passive_order:
		var def: Dictionary = Data.passive(String(pid))
		var lvl: int = passive_level(pid)
		var mods: Variant = def.get("modifiers", [])
		if not (mods is Array):
			continue
		for m: Variant in mods:
			if not (m is Dictionary):
				continue
			var st: StringName = StringName(String(m.get("stat", "")))
			if st == &"stat_salgi":
				continue   # 살기 기본치는 haewon 소유(TODO(haewon): 제웅 살기 기본치 반영)
			var lvls: Variant = m.get("levels", [])
			if not (lvls is Array) or lvls.is_empty():
				continue
			var v: float = float(lvls[mini(lvl, lvls.size()) - 1])
			if String(m.get("op", "flat")) == "add_pct":
				pct[st] = float(pct.get(st, 0.0)) + v
			else:
				flat[st] = float(flat.get(st, 0.0)) + v
	for key: StringName in _buff:
		var b: float = float(_buff[key])
		match key:
			&"cheong":
				pct[&"stat_jangdan"] = float(pct.get(&"stat_jangdan", 0.0)) - 0.10 * b
			&"jeok":
				pct[&"stat_sinppal"] = float(pct.get(&"stat_sinppal", 0.0)) + 0.15 * b
			&"hwang":
				pct[&"stat_chohon"] = float(pct.get(&"stat_chohon", 0.0)) + 0.5 * b
			&"baek":
				flat[&"stat_puri"] = float(flat.get(&"stat_puri", 0.0)) + 0.5 * b
	var old_hp_max: float = Game.stat(&"stat_jeonggi", 100.0)
	var keys: Dictionary = {}
	for k: StringName in flat:
		keys[k] = true
	for k2: StringName in pct:
		keys[k2] = true
	for k3: Variant in _stat_base:
		if not keys.has(k3):
			Game.stats[k3] = _stat_base[k3]
	for st2: StringName in keys:
		var base: float = float(_stat_base.get(st2, Game.stat(st2, 0.0)))
		var v2: float = (base + float(flat.get(st2, 0.0))) * (1.0 + float(pct.get(st2, 0.0)))
		Game.stats[st2] = v2
	var cap_p: float = Data.num("combat_core", "damage.puri_cap", 6.0)
	Game.stats[&"stat_puri"] = minf(Game.stat(&"stat_puri", 3.0), cap_p)
	var new_hp_max: float = Game.stat(&"stat_jeonggi", 100.0)
	if not is_equal_approx(old_hp_max, new_hp_max) and Game.hp_max > 0.0:
		var d: float = new_hp_max - old_hp_max
		Game.hp_max = maxf(1.0, Game.hp_max + d)
		Game.hp = clampf(Game.hp + maxf(d, 0.0), 1.0, Game.hp_max)


# ─── 점지 후보(stats.json jeomji — 05 10장 단일 정본) ────────────────

func _color_label(c: String) -> String:
	if c == "white":
		return "흰 무기 · 흰 테두리 귀신을 풀어 준다"
	if c == "dual":
		return "양쪽 · 귀신은 베고, 흰 테두리는 풀어 준다"
	return "붉은 무기 · 귀신을 벤다"


func get_offer_pool() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var J: String = "stats"
	var cw_w: float = Data.num(J, "jeomji.category_weights.weapon", 40.0)
	var cw_p: float = Data.num(J, "jeomji.category_weights.passive", 30.0)
	var owned_mult: float = Data.num(J, "jeomji.owned_mult", 1.3)
	var focus_per: float = Data.num(J, "jeomji.focus_mult.per_level", 0.15)
	var evo_pp: float = Data.num(J, "jeomji.evo_mult.pair_passive", 1.5)
	var evo_pp8: float = Data.num(J, "jeomji.evo_mult.pair_passive_weapon_lv8", 2.5)
	var evo_pw: float = Data.num(J, "jeomji.evo_mult.pair_weapon", 1.3)
	var un_new: float = Data.num(J, "jeomji.evo_mult.union_partner_new", 2.0)
	var un_up: float = Data.num(J, "jeomji.evo_mult.union_partner_owned", 1.3)
	var owned_b: Dictionary = _owned_bases()
	var lvl: int = Game.level
	var free_w: int = MAX_SLOTS - slots.size()
	var free_p: int = MAX_PASSIVES - passive_order.size()
	var boost_w: float = 1.25 if lvl <= 10 and free_w >= 2 else 1.0
	var boost_p: float = 1.1 if lvl <= 10 and free_p >= 4 else 1.0
	# 보유 무구 레벨업
	for w in slots:
		if w.kind != WeaponBase.KIND_WEAPON or w.level >= w.max_level:
			continue
		var nxt: Dictionary = {}
		var lvls: Variant = w.def.get("levels", [])
		if lvls is Array and w.level < lvls.size():
			nxt = lvls[w.level]
		var pp: StringName = StringName(String(w.def.get("pair_passive", "")))
		var em: float = evo_pp if passive_level(pp) > 0 else 1.0
		var ui0: Dictionary = _union_info(w.id)
		var u_on: bool = not ui0.is_empty() and owned_b.has(ui0["partner"])
		if u_on:
			em *= un_up
		var dsc: String = String(nxt.get("change", ""))
		var hint: String = _evo_hint(w, w.level + 1)
		if hint != "":
			dsc += "\n" + hint
		if u_on:
			dsc += "\n" + _union_hint(ui0)
		out.append({"kind": "weapon", "id": w.id, "level": w.level + 1, "is_new": false,
			"title": String(w.def.get("name_ko", w.id)), "desc": dsc,
			"color": String(w.def.get("color", "red")), "evo_path": passive_level(pp) > 0, "union_path": u_on,
			"weight": cw_w * owned_mult * (1.0 + focus_per * float(w.level - 1)) * em * boost_w})
	# 새 무구
	if free_w > 0:
		var ids: Array = Data.weapon_ids()
		var v1n: int = 0
		for id0: Variant in ids:
			if Data.is_v1(Data.weapon(String(id0))):
				v1n += 1
		var dil: float = minf(1.0, 6.0 / maxf(1.0, float(v1n)))
		for id1: Variant in ids:
			var def: Dictionary = Data.weapon(String(id1))
			if not Data.is_v1(def) or has_weapon(StringName(id1)) or _evolved_from(StringName(id1)):
				continue
			var pp2: StringName = StringName(String(def.get("pair_passive", "")))
			var em2: float = evo_pp if passive_level(pp2) > 0 else 1.0
			var c: String = String(def.get("color", "red"))
			var ui1: Dictionary = _union_info(StringName(id1))
			var u_new: bool = not ui1.is_empty() and owned_b.has(ui1["partner"])
			var dsc1: String = "%s — %s" % [String(def.get("archetype", "")), _color_label(c)]
			if u_new:
				em2 *= un_new
				dsc1 = _union_hint(ui1) + "\n" + dsc1
			out.append({"kind": "weapon", "id": StringName(id1), "level": 1, "is_new": true,
				"title": String(def.get("name_ko", id1)), "desc": dsc1, "union_path": u_new,
				"color": c, "weight": cw_w * dil * em2 * boost_w})
	# 패시브
	var rar: Dictionary = {}
	var rv: Variant = Data.get_value(J, "jeomji.rarity_base_weight", {})
	if rv is Dictionary:
		rar = rv
	var plist: Variant = Data.get_value("passives", "passives", [])
	var pmax: int = int(Data.get_value("passives", "_meta.rules.max_level", 5))
	if plist is Array:
		for p: Variant in plist:
			if not (p is Dictionary) or not Data.is_v1(p):
				continue
			var pid: StringName = StringName(String(p.get("id", "")))
			var cur: int = passive_level(pid)
			if cur >= pmax or (cur == 0 and free_p <= 0):
				continue
			var wgt: float = cw_p * float(rar.get(String(p.get("rarity", "common")), 100.0)) / 100.0 * boost_p
			if cur > 0:
				wgt *= owned_mult
			var pw: Variant = p.get("pair_weapons", [])
			var pe: float = 1.0
			if pw is Array:
				for wid: Variant in pw:
					var l8: int = level_of(StringName(String(wid)))
					if l8 >= 8:
						pe = maxf(pe, evo_pp8)
					elif l8 > 0:
						pe = maxf(pe, evo_pw)
			wgt *= pe
			out.append({"kind": "passive", "id": pid, "level": cur + 1, "is_new": cur == 0,
				"title": String(p.get("name_ko", pid)), "desc": _passive_desc(p, cur + 1),
				"color": String(p.get("tilt", "neutral")), "weight": wgt, "pair_lv8": pe >= evo_pp8})
	return out


func _evolved_from(wid: StringName) -> bool:
	for w in slots:
		if w.kind != WeaponBase.KIND_WEAPON and w.base_id == wid:
			return true
		# 결합형은 두 재료 무구를 모두 삼켰다 — 짝 쪽 원무구도 다시 새 무구로 내지 않는다
		if w.kind == WeaponBase.KIND_UNION:
			var ui: Dictionary = _union_info(wid)
			if not ui.is_empty() and ui["union"] == w.id:
				return true
	return false


# ─── 진화·결합 길 표시(점지 카드 desc) ──────────────────────────────

var _union_map: Dictionary = {}          # 원무구 id -> {partner, union, evo, partner_evo}


## 결합 짝 정보(v1 결합만). 없으면 {}.
func _union_info(wid: StringName) -> Dictionary:
	if _union_map.is_empty():
		_union_map[&"_built"] = {}
		var ul: Variant = Data.get_value("weapons", "unions", [])
		if ul is Array:
			for u: Variant in ul:
				if not (u is Dictionary) or not Data.is_v1(u):
					continue
				var evs: Variant = ((u as Dictionary).get("recipe", {}) as Dictionary).get("evolutions", [])
				if not (evs is Array) or (evs as Array).size() != 2:
					continue
				var b: Array[StringName] = []
				for e: Variant in evs:
					b.append(StringName(String((Data.evolution(String(e)).get("recipe", {}) as Dictionary).get("weapon", ""))))
				var uid: StringName = StringName(String((u as Dictionary).get("id", "")))
				_union_map[b[0]] = {"partner": b[1], "union": uid, "evo": StringName(String(evs[0])), "partner_evo": StringName(String(evs[1]))}
				_union_map[b[1]] = {"partner": b[0], "union": uid, "evo": StringName(String(evs[1])), "partner_evo": StringName(String(evs[0]))}
	if wid == &"_built":
		return {}
	return _union_map.get(wid, {})


## 보유 원무구 id 집합(무구 그대로 또는 진화형). 결합형은 이미 소모됐으므로 뺀다.
func _owned_bases() -> Dictionary:
	var out: Dictionary = {}
	for w in slots:
		if w.kind == WeaponBase.KIND_WEAPON:
			out[w.id] = 0
		elif w.kind == WeaponBase.KIND_EVO:
			out[StringName(String((w.def.get("recipe", {}) as Dictionary).get("weapon", w.base_id)))] = 1
	return out


## 보유 무구 강화 카드의 진화 조건 한 줄. nl = 이 카드를 고른 뒤 레벨.
func _evo_hint(w: WeaponBase, nl: int) -> String:
	var ed: Dictionary = _evo_def_for(w.id)
	if ed.is_empty() or not Data.is_v1(ed):
		return ""
	var rc: Dictionary = ed.get("recipe", {})
	var pid: String = String(rc.get("passive", ""))
	var pname: String = String(Data.passive(pid).get("name_ko", pid))
	var ename: String = String(ed.get("name_ko", ed.get("id", "")))
	var has_p: bool = passive_level(StringName(pid)) >= int(rc.get("passive_min_level", 1))
	# 카드 폭 140px·10px 글꼴 → 한 줄 약 13자. 짧게.
	if nl >= 8:
		return ("상자 열면 %s 진화" % ename) if has_p else ("짝 %s 얻으면 진화" % pname)
	return ("진화 %s: Lv8만 남음" % ename) if has_p else ("진화 %s: Lv8+%s" % [ename, pname])


## 결합 조건 한 줄(짝 무구를 이미 가진 경우만 부른다).
func _union_hint(ui: Dictionary) -> String:
	var un: String = String(Data.union(String(ui["union"])).get("name_ko", ui["union"]))
	var pn: String = String(Data.weapon(String(ui["partner"])).get("name_ko", ui["partner"]))
	if un.length() + pn.length() <= 7:
		return "결합 %s: 짝 %s도 진화" % [un, pn]
	return "결합 짝: %s도 진화" % pn


const _STAT_KO: Dictionary = {
	"stat_sinppal": "신빨(피해)", "stat_doryang": "도량(범위)", "stat_jangdan": "장단(쿨다운)", "stat_gise": "기세(투사체 속도)",
	"stat_yeongheom": "영험(지속)", "stat_domu": "도무(이동)", "stat_jeonggi": "정기(최대 체력)", "stat_saenggi": "생기(회복)",
	"stat_sinbok": "신복(방어)", "stat_sinjang": "신장 수(개수)", "stat_gyeoldan": "결단(치명)", "stat_puri": "풀이(해원 배율)",
	"stat_chohon": "초혼(흡인)", "stat_haewon_suryeon": "해원 숙련", "stat_siju": "시주", "stat_jeomgwae": "점괘",
	"stat_salgi": "살기", "stat_haengnyeol": "행렬", "stat_neok_sumyeong": "넋 수명", "stat_gilbe": "길베(초)",
}


func _passive_desc(p: Dictionary, lvl: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var mods: Variant = p.get("modifiers", [])
	if mods is Array:
		for m: Variant in mods:
			if not (m is Dictionary):
				continue
			var lvls: Variant = m.get("levels", [])
			if not (lvls is Array) or lvls.is_empty():
				continue
			var v: float = float(lvls[mini(lvl, lvls.size()) - 1])
			var sid: String = String(m.get("stat", ""))
			var nm: String = UiKit.stat_name(sid)
			if nm == "" or nm == sid:
				nm = String(_STAT_KO.get(sid, sid))
			if UiKit.stat_invert(sid):
				v = -v                                   # 장단(쿨다운) −6% → 화면 '공격 속도 +6%'
			if String(m.get("op", "flat")) == "add_pct":
				parts.append("%s %+d%%" % [nm, int(roundf(v * 100.0))])
			else:
				parts.append("%s %s" % [nm, ("%+d" % int(v)) if is_equal_approx(v, roundf(v)) else ("%+.2f" % v)])
	var stat_s: String = " · ".join(parts)
	var pw: Variant = p.get("pair_weapons", [])
	if pw is Array and not pw.is_empty():
		var names: PackedStringArray = PackedStringArray()
		var held: bool = false
		for wid: Variant in pw:
			var nm2: String = String(Data.weapon(String(wid)).get("name_ko", wid))
			var l2: int = level_of(StringName(String(wid)))
			if l2 > 0:
				held = true
			names.append(("%s Lv%d/8" % [nm2, l2]) if l2 > 0 else nm2)
		var pair_s: String = "진화 짝: " + ", ".join(names)
		# 짝 무구를 가졌으면 진화 조건을 맨 위에(카드 3줄에서 잘리지 않게)
		return (pair_s + "\n" + stat_s) if held else (stat_s + "\n" + pair_s)
	return stat_s


## 가중 추첨 + 보장(stats.json jeomji.guarantees 요약: G2 짝 패시브, G7 결합 짝 무구, G6 보유 무구 강화, G3 초반 새 무구, G4 같은 범주 3장 재추첨).
func roll_offers(n: int = 3) -> Array[Dictionary]:
	var pool: Array[Dictionary] = get_offer_pool()
	var out: Array[Dictionary] = []
	_jeomji_count += 1
	var rng: RandomNumberGenerator = Rng.stream(&"jeomji")
	# G2: 무구 Lv8 인데 짝 패시브가 없으면 3번에 1번 이상
	if _jeomji_count - _last_g2 >= 3:
		for k in pool.size():
			if bool(pool[k].get("pair_lv8", false)) and int(pool[k]["level"]) == 1:
				out.append(pool[k])
				pool.remove_at(k)
				_last_g2 = _jeomji_count
				break
	# G7(결합 자비): 결합 짝 무구를 가졌으면 그 짝 무구(새 무구 우선, 없으면 강화) 카드를 3번에 1번 이상. G2 와 같은 화면에는 안 넣는다.
	var g6_done: bool = false
	if out.is_empty() and _jeomji_count - _last_g7 >= int(Data.num("stats", "jeomji.union_mercy_every", 3.0)):
		var best_k: int = -1
		for k7 in pool.size():
			if not bool(pool[k7].get("union_path", false)):
				continue
			if best_k < 0 or (bool(pool[k7].get("is_new", false)) and not bool(pool[best_k].get("is_new", false))):
				best_k = k7
		if best_k >= 0:
			g6_done = not bool(pool[best_k].get("is_new", false))
			out.append(pool[best_k])
			pool.remove_at(best_k)
			_last_g7 = _jeomji_count
	# G6: 보유 무구 강화 1장
	if out.size() < n and not g6_done:
		_take_where(pool, out, rng, "weapon", false)
	# G3: Lv ≤ 6 이고 빈 무구 칸이 있으면 새 무구 1장
	if out.size() < n and Game.level <= 6 and slots.size() < MAX_SLOTS:
		_take_where(pool, out, rng, "weapon", true)
	while out.size() < n and not pool.is_empty():
		var tot: float = 0.0
		for c in pool:
			tot += float(c["weight"])
		var r: float = rng.randf() * tot
		var pick: int = pool.size() - 1
		for k2 in pool.size():
			r -= float(pool[k2]["weight"])
			if r <= 0.0:
				pick = k2
				break
		out.append(pool[pick])
		pool.remove_at(pick)
	# G4: 3장이 모두 같은 범주면 마지막 장을 다른 범주에서 한 번 다시
	if out.size() == 3 and out[0]["kind"] == out[1]["kind"] and out[1]["kind"] == out[2]["kind"]:
		for k3 in pool.size():
			if pool[k3]["kind"] != out[2]["kind"]:
				out[2] = pool[k3]
				break
	if Game.autotest and _offer_trace_left > 0:
		for c9 in out:
			var d9: String = String(c9.get("desc", ""))
			if d9.contains("진화") or d9.contains("결합"):
				_offer_trace_left -= 1
				_trace("offer %s L%d | %s" % [c9.get("id", ""), int(c9.get("level", 0)), d9.replace("
", " / ")])
	if out.is_empty():
		out.append({"kind": "filler", "id": &"gongmul", "level": 0, "title": "공물상", "desc": "정기 25% 회복", "weight": 1.0, "color": "neutral"})
		# 엽전 충전 카드는 meta 지급 API 전까지 내보내지 않는다(빈 카드 금지) → 신명 충전으로 대체.
		out.append({"kind": "filler", "id": &"sinmyeong", "level": 0, "title": "신명 돋움", "desc": "신명 +20% — 가득 차면 신명 오름", "weight": 1.0, "color": "neutral"})
	return out


func _take_where(pool: Array[Dictionary], out: Array[Dictionary], rng: RandomNumberGenerator, kind_v: String, is_new: bool) -> void:
	var tot: float = 0.0
	for c in pool:
		if c["kind"] == kind_v and bool(c.get("is_new", false)) == is_new:
			tot += float(c["weight"])
	if tot <= 0.0:
		return
	var r: float = rng.randf() * tot
	for k in pool.size():
		var c2: Dictionary = pool[k]
		if c2["kind"] != kind_v or bool(c2.get("is_new", false)) != is_new:
			continue
		r -= float(c2["weight"])
		if r <= 0.0:
			out.append(c2)
			pool.remove_at(k)
			return


## ui/levelup.gd 호환(현행 UI 는 후보에서 3장을 고른다 → 이미 가중 추첨된 3장).
func offer_candidates() -> Array[Dictionary]:
	return roll_offers(3)


func apply_offer(c: Dictionary) -> bool:
	if bool(c.get("_applied", false)):
		return true
	c["_applied"] = true
	var k: String = String(c.get("kind", ""))
	if k == "weapon" or k == "passive":
		return add_or_level(StringName(c.get("id", ""))) > 0
	if k == "filler":
		var fid: StringName = StringName(c.get("id", ""))
		if fid == &"gongmul" and Game.player != null:
			var p: Player = Game.player as Player
			p.hit.heal(Game.hp_max * 0.25)
		elif fid == &"sinmyeong":
			var rr: Run = Game.run_root as Run
			if rr != null and rr.haewon != null and not Game.sinmyeong_oreum:
				rr.haewon.add_sinmyeong(0.2)
			elif Game.player != null:
				(Game.player as Player).hit.heal(Game.hp_max * 0.1)   # 오름 중이면 신명이 안 쌓이므로 정기로 보상
		return true
	return false


func _on_levelup_chosen(c: Dictionary) -> void:
	var k: String = String(c.get("kind", ""))
	if k == "weapon":
		c["_applied"] = true       # ui 가 add_or_level 로 이미 적용
		return
	apply_offer(c)


# ─── 진화·결합·상자 ───────────────────────────────────────────────

## v1 진화 정의(가장 먼저 Lv8 이 된 무구부터).
func evolvable_ids() -> Array:
	var out: Array = []
	for w in slots:
		if can_evolve(w.id):
			out.append(w.id)
	return out


func _evo_def_for(weapon_id: StringName) -> Dictionary:
	var wd: Dictionary = Data.weapon(String(weapon_id))
	return Data.evolution(String(wd.get("evolution", "")))


func can_evolve(weapon_id: StringName) -> bool:
	var w: WeaponBase = _find(weapon_id)
	if w == null or w.kind != WeaponBase.KIND_WEAPON or w.level < 8:
		return false
	var ed: Dictionary = _evo_def_for(weapon_id)
	if ed.is_empty() or not Data.is_v1(ed):
		return false
	var rc: Dictionary = ed.get("recipe", {})
	return passive_level(StringName(String(rc.get("passive", "")))) >= int(rc.get("passive_min_level", 1))


func evolve(weapon_id: StringName) -> bool:
	var w: WeaponBase = _find(weapon_id)
	if w == null:
		return false
	var ed: Dictionary = _evo_def_for(weapon_id)
	if ed.is_empty():
		return false
	return _replace_slot(w.slot, ed, WeaponBase.KIND_EVO, weapon_id)


func _union_ready() -> Dictionary:
	var ul: Variant = Data.get_value("weapons", "unions", [])
	if not (ul is Array):
		return {}
	for u: Variant in ul:
		if not (u is Dictionary) or not Data.is_v1(u):
			continue
		var evs: Variant = (u.get("recipe", {}) as Dictionary).get("evolutions", [])
		if evs is Array and evs.size() == 2 and _find(StringName(String(evs[0]))) != null and _find(StringName(String(evs[1]))) != null:
			return u
	return {}


func unite(union_id: StringName) -> bool:
	var ud: Dictionary = Data.union(String(union_id))
	if ud.is_empty():
		return false
	var evs: Array = (ud.get("recipe", {}) as Dictionary).get("evolutions", [])
	var a: WeaponBase = _find(StringName(String(evs[0])))
	var b: WeaponBase = _find(StringName(String(evs[1])))
	if a == null or b == null:
		return false
	var keep: int = mini(a.slot, b.slot)
	var gone: int = maxi(a.slot, b.slot)
	var pp: ProjectilePool = Game.projectiles as ProjectilePool
	if pp != null:
		pp.clear_slot(gone)
	slots[gone].dispose()
	slots.remove_at(gone)
	for k in range(gone, slots.size()):
		slots[k].slot = k
		for sw in slots[k].subs:
			sw.slot = k
		if pp != null:
			pp.remap_slot(k + 1, k)
	return _replace_slot(keep, ud, WeaponBase.KIND_UNION, a.id)


func _replace_slot(slot_i: int, new_def: Dictionary, kind: StringName, from_id: StringName) -> bool:
	var pp: ProjectilePool = Game.projectiles as ProjectilePool
	if pp != null:
		pp.clear_slot(slot_i)
	var old: WeaponBase = slots[slot_i]
	old.dispose()
	var nw: WeaponBase = ArchetypeRegistry.create(new_def, slot_i, self, kind)
	slots[slot_i] = nw
	Events.weapon_evolved.emit(from_id, nw.id)
	_trace("%s -> %s" % [from_id, nw.id])
	Audio.play_sfx(&"sfx_sys_sinmyeong_full", &"SFX", -2.0)
	Juice.flash(K.COL_HWANG, 0.25, 0.12)
	var v: VfxPlayer = Game.vfx as VfxPlayer
	if v != null:
		# 진화·결합 공개 기둥: 무당 몸(z2)을 덮지 않게 한 층 아래(상대 z −4 → 절대 1)·32px 위로 —
		# 몸 위로 솟은 윗부분만 보인다(design/18 리뷰 after/1200 shot_07).
		var vp: Vector2 = (Game.player.global_position if Game.player != null else Vector2.ZERO) + Vector2(0, -32)
		v.play(&"vfx_sinjangdae_descend", vp, 0.0, 1.0, {"z": -4})
	return true


## 길흉 상자·넋함(02 18 / weapons.json evolution_rule.box_contents). items = 상자 등급 1/3/5.
## 반환: [{kind: union|evolution|weapon_up|passive_up|yeopjeon, id, from}] — 연출·정산은 호출자(pickups/ui).
func open_box(_box_id: StringName, items: int = 1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_trace("box %s items=%d" % [_box_id, items])
	var special_used: bool = false
	for _k in maxi(1, items):
		if not special_used:
			var u: Dictionary = _union_ready()
			if not u.is_empty():
				var evs: Array = (u.get("recipe", {}) as Dictionary).get("evolutions", [])
				if unite(StringName(String(u["id"]))):
					out.append({"kind": "union", "id": StringName(String(u["id"])), "from": StringName(String(evs[0]))})
					special_used = true
					continue
			var ev: Array = evolvable_ids()
			if not ev.is_empty():
				var wid: StringName = _pick_evolution(ev)
				var to: StringName = StringName(String(_evo_def_for(wid).get("id", "")))
				if evolve(wid):
					out.append({"kind": "evolution", "id": to, "from": wid})
					special_used = true
					continue
		# 최고 레벨 무구 +1(04 6.2). 같은 레벨이면 진화 길(짝 패시브 보유)이 열린 무구 먼저.
		var best: WeaponBase = null
		var best_s: int = -1
		for w in slots:
			if w.kind != WeaponBase.KIND_WEAPON or w.level >= 8:
				continue
			var s: int = w.level * 2 + (1 if passive_level(StringName(String(w.def.get("pair_passive", "")))) > 0 else 0)
			if s > best_s:
				best_s = s
				best = w
		if best != null:
			add_or_level(best.id)
			out.append({"kind": "weapon_up", "id": best.id, "from": best.id})
			continue
		var bp: StringName = &""
		for pid in passive_order:
			if passive_level(pid) < 5 and (bp == &"" or passive_level(pid) > passive_level(bp)):
				bp = pid
		if bp != &"":
			_add_passive(bp)
			out.append({"kind": "passive_up", "id": bp, "from": bp})
			continue
		out.append({"kind": "yeopjeon", "id": &"yeopjeon", "from": &""})
	return out


## --autotest 성장 추적 한 줄(tools/godot_check.sh --builds 로그 분석용).
func _trace(msg: String) -> void:
	if Game.autotest:
		print("[growth] %s Lv%d %s" % [K.fmt_time(Game.time_sec()), Game.level, msg])


## 진화 후보가 여럿이면 결합을 여는 쪽(짝이 이미 진화) → 짝 무구를 가진 쪽 → 슬롯 순.
func _pick_evolution(ev: Array) -> StringName:
	var owned_b: Dictionary = _owned_bases()
	var best: StringName = ev[0]
	var best_s: int = -1
	for wid: StringName in ev:
		var ui: Dictionary = _union_info(wid)
		var s: int = 0
		if not ui.is_empty() and owned_b.has(ui["partner"]):
			s = 2 if int(owned_b[ui["partner"]]) == 1 else 1
		if s > best_s:
			best_s = s
			best = wid
	return best


func _find(wid: StringName) -> WeaponBase:
	for w in slots:
		if w.id == wid:
			return w
	return null


## 진화·결합 직접 지급(디버그·캡처). 재료 무구가 있으면 그 칸을 교체, 없으면 새 칸.
func _grant_special(sid: StringName) -> bool:
	var s: String = String(sid)
	if s.begins_with("evo_"):
		var ed: Dictionary = Data.evolution(s)
		if ed.is_empty():
			return false
		var base: StringName = StringName(String((ed.get("recipe", {}) as Dictionary).get("weapon", "")))
		var w: WeaponBase = _find(base)
		if w != null:
			return _replace_slot(w.slot, ed, WeaponBase.KIND_EVO, base)
		if slots.size() >= MAX_SLOTS:
			return false
		var nw: WeaponBase = ArchetypeRegistry.create(ed, slots.size(), self, WeaponBase.KIND_EVO)
		slots.append(nw)
		Events.weapon_added.emit(nw.id, nw.slot)
		return true
	var ud: Dictionary = Data.union(s)
	if ud.is_empty():
		return false
	var evs: Array = (ud.get("recipe", {}) as Dictionary).get("evolutions", [])
	if _find(StringName(String(evs[0]))) != null and _find(StringName(String(evs[1]))) != null:
		return unite(sid)
	if slots.size() >= MAX_SLOTS:
		return false
	var uw: WeaponBase = ArchetypeRegistry.create(ud, slots.size(), self, WeaponBase.KIND_UNION)
	slots.append(uw)
	Events.weapon_added.emit(uw.id, uw.slot)
	return true


## --wpn=wpn_woldo:8,psv_obangkkeun:1,evo_manwoldo,union_neoksinkal,clear
func _debug_grant(spec: String) -> void:
	for part: String in spec.split(",", false):
		var kv: PackedStringArray = part.split(":")
		var item: String = kv[0].strip_edges()
		if item == "clear":
			for w in slots:
				w.dispose()
			slots.clear()
			_schedule.clear()
			continue
		var n: int = int(kv[1]) if kv.size() > 1 else 1
		var cur: int = level_of(StringName(item)) if item.begins_with("wpn_") else passive_level(StringName(item))
		for _i in maxi(1, n - cur):
			if add_or_level(StringName(item)) < 0:
				break
	print("[combat] debug grant: ", spec, " -> ", debug_summary())


func debug_summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for w in slots:
		parts.append("%s:%d" % [w.id, w.level])
	for pid in passive_order:
		parts.append("%s:%d" % [pid, passive_level(pid)])
	return ",".join(parts)


## 무구별 발사·적중·피해 합(부속 포함). 봇 종료 시 한 줄로 찍는다.
func debug_hits_summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for w in slots:
		var h: int = w.hits_total
		var d: float = w.dmg_total
		for sw in w.subs:
			h += sw.hits_total
			d += sw.dmg_total
		parts.append("%s:L%d f%d h%d d%d" % [w.id, w.level, w.fires_total, h, int(d)])
	return " | ".join(parts)


func _exit_tree() -> void:
	if Game.autotest:
		print("[combat] weapons ", debug_hits_summary())


func _process(_delta: float) -> void:
	queue_redraw()
	_ground.queue_redraw()
	_add_ci.queue_redraw()


func _draw() -> void:
	add_cmds.clear()
	big_sheets = 0
	for w in slots:
		w.draw_all(self)


## 가산 층 명령 한 개(본 층 _draw 안에서만 부른다).
func push_add(tex: Texture2D, dst: Rect2, src: Rect2, xf: Transform2D, modc: Color) -> void:
	if add_cmds.size() < 64:
		add_cmds.append([tex, dst, src, xf, modc])


func _draw_add() -> void:
	for c: Array in add_cmds:
		_add_ci.draw_set_transform_matrix(c[3])
		_add_ci.draw_texture_rect_region(c[0], c[1], c[2], c[4])
	_add_ci.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_ground() -> void:
	for w in slots:
		w.draw_ground_all(_ground)
