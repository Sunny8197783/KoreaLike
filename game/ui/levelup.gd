extends Control
## 점지(레벨업 3택). 소유: ui. design/11 §7.1~7.3.
## 후보: WeaponManager.offer_candidates() → Rng("jeomji") 로 3장(가중치·4번째 카드·보장 규칙은 data/stats.json jeomji — TODO(combat)).
## 연출 값: combat_core.jeomji (enter_time_real 0.25, card_stagger 0.06, card_anim 0.22, input_lock_sec 0.35, resume_iframe 0.75)
## 카드 160×196 한지 바탕·단청 모서리, 종류 띠(◆ 붉은 = 적 / ○ 흰 = 한지), 상태 배지(NEW / Lv a→b), 아이콘, 이름, 변화량 우선 설명.
## 입력: 1/2/3 직접, ←/→ + Enter, 마우스. 열린 뒤 0.35초 잠금 + 눌려 있던 키는 한 번 떼야 인식.
## 게임 시계는 Game.push_pause(&"levelup") 로 멈춘다(SceneTree.paused 는 쓰지 않는다). 연출은 실시간.

const CARD_W: float = 160.0
const CARD_H: float = 196.0
const CARD_GAP: float = 16.0
const FIRST_NOTE: String = "하나를 고르세요 · ◆ 붉은 무기는 베어 처치, ○ 흰 무기는 풀어 줌"

var _choices: Array[Dictionary] = []
var _cards: Array[Dictionary] = []       # 표시용 사전(열 때 한 번 만든다)
var _pending: int = 0
var _t: float = 0.0                      # 열린 뒤 실시간
var _lock_left: float = 0.0
var _need_release: bool = false
var _auto_left: float = -1.0
var _focus: int = 1
var _closing: bool = false
var _close_t: float = 0.0
var _picked: int = -1
var _first_note: bool = false
var _dirty: bool = true
var _lock_was: bool = true
var _box_seen: bool = false           # 이번 판 첫 상자를 열었나(쉬운 카드: 진화 줄을 이때 연다)
# 처치 연출(퇴치 번쩍·파열)이 끝난 뒤 연다: 경험치 획득 후 최소 15틱 + 타격 멈춤 끝(실시간 1.5초 안전망)
const DEFER_TICKS: int = 15
var _defer_tick: int = -1
var _defer_real: float = 0.0

var _stagger: float = 0.06
var _anim: float = 0.22
var _enter: float = 0.25

var _f_body: Font
var _f_bold: Font
var _f_small: Font
var _f_tiny: Font
var _f_big: Font
var _f_brush: Font
var _paper: Texture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	UiKit.setup_fonts()
	_f_body = UiKit.body()
	_f_bold = UiKit.bold()
	_f_small = UiKit.small()
	_f_tiny = UiKit.tiny()
	_f_big = UiKit.big()
	_f_brush = UiKit.brush()
	_paper = UiKit.skin("tile_hanji_paper.png")
	_stagger = Data.num("combat_core", "jeomji.card_stagger", 0.06)
	_anim = Data.num("combat_core", "jeomji.card_anim", 0.22)
	_enter = Data.num("combat_core", "jeomji.enter_time_real", 0.25)
	Events.box_opened.connect(func(_b: StringName, _g: int, _r: Array, _bn: float, _p: Vector2) -> void: _box_seen = true)


## run.gd(level_up) 이 부른다. 바로 열지 않고 처치 연출이 끝날 때까지 미룬다(_process → _open_now).
func open() -> void:
	if visible or _defer_tick >= 0:
		_pending += 1
		return
	_defer_tick = Game.game_tick + DEFER_TICKS
	_defer_real = 0.0


func _open_now() -> void:
	_defer_tick = -1
	if not Game.run_active or (Game.player != null and (Game.player as Player).dead):
		_pending = 0
		return
	var wm: WeaponManager = Game.weapons as WeaponManager
	var cands: Array[Dictionary] = wm.offer_candidates() if wm != null else []
	_open_with(cands, wm)


## 미리보기·테스트용: 후보 목록을 직접 받는다
func open_with(cands: Array[Dictionary]) -> void:
	_open_with(cands, Game.weapons as WeaponManager)


func _open_with(cands: Array[Dictionary], wm: WeaponManager) -> void:
	_choices.clear()
	var rng: RandomNumberGenerator = Rng.stream(&"jeomji")
	# 온보딩 구제(onboarding_hints.hint_need_white): 4분 동안 해원 0 이고 흰 무구가 없으면 흰 카드 1장 보장
	if Game.time_sec() >= 240.0 and Game.kills_haewon == 0 and not _owns_white(wm):
		for k in cands.size():
			if UiKit.weapon_color(String(cands[k].get("id", ""))) == "white":
				_choices.append(cands[k])
				cands.remove_at(k)
				break
	while _choices.size() < 3 and not cands.is_empty():
		var k2: int = rng.randi_range(0, cands.size() - 1)
		_choices.append(cands[k2])
		cands.remove_at(k2)
	if _choices.is_empty():
		return
	_build_cards()
	Game.push_pause(&"levelup")
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_t = 0.0
	_closing = false
	_picked = -1
	_focus = 1 if _choices.size() >= 2 else 0
	_lock_left = Data.num("combat_core", "jeomji.input_lock_sec", 0.35)
	_need_release = _any_held()
	_first_note = UiSettings.guide_on() and not bool(Save.get_value("ui.hints_seen.jeomji", false)) and not Game.tutorial_mode
	if _first_note and (not Game.autotest or DebugTools.arg("ui-save") == "1"):
		Save.set_value("ui.hints_seen.jeomji", true)
	Events.levelup_offer.emit(_choices)
	Audio.play_sfx(&"sfx_ui_jeomji_open", &"UI")
	if Game.autotest:
		_auto_left = 0.6


func _owns_white(wm: WeaponManager) -> bool:
	if wm == null:
		return false
	for i in wm.slot_count():
		var w: WeaponBase = wm.weapon_at(i)
		if w != null and w.is_white():
			return true
	return false


const HELD_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down", &"confirm", &"choice_1", &"choice_2", &"choice_3"]


func _any_held() -> bool:
	for a: StringName in HELD_ACTIONS:
		if Input.is_action_pressed(a):
			return true
	return false


## 카드 표시 자료(열 때 한 번). design/19 §4.3:
##   아이콘 → 이름(Bold 12) → 큰 효과 한 줄(T3 12, 최대 2줄) → 숫자(T4 10, 작게) → (첫 상자 뒤) 진화 짝 줄.
##   띠: '붉은 무기 · 베기' / '흰 무기 · 풀기' / '아이템'. 처음 세 판(Save.runs_done() < 3)은 숫자 줄을 숨기고,
##   진화 줄은 이번 판 첫 상자를 연 뒤에만 보인다(그 뒤 판부터는 늘 보인다).
func _build_cards() -> void:
	_cards.clear()
	var easy: bool = _easy_cards()
	var show_evo: bool = not easy or _box_seen
	for c: Dictionary in _choices:
		var id: String = String(c.get("id", ""))
		var lv: int = int(c.get("level", 1))
		var kind: String = String(c.get("kind", "weapon"))
		var d: Dictionary
		if kind == "passive" or kind == "filler":
			d = _side_card(c, id, lv, kind)   # core 통합: 패시브·충전 카드는 후보 사전(title/desc/color)으로
		elif kind == "deity_power":
			d = _power_card(c, id, lv)
		else:
			d = _weapon_card(c, id, lv)
		var big_s: String = String(d.get("big", ""))
		var num_s: String = String(d.get("num", ""))
		# 아이템: '공격력 +8%' + 쉬운 문장이 두 줄을 넘으면 문장만 크게, 수치는 숫자 줄로 내린다
		if d.has("head") and UiKit.wrap(_f_body, UiKit.SZ_BODY, big_s, CARD_W - 16.0, 4).size() > 2:
			big_s = String(d.get("plain", big_s))
			num_s = String(d["head"])
		d["desc"] = UiKit.wrap(_f_body, UiKit.SZ_BODY, big_s, CARD_W - 16.0, 2)
		# Lv5 완성 효과 줄이 있으면 숫자 줄은 한 줄로(아래 진화 줄과 겹치지 않게)
		var num_lines: int = 1 if String(d.get("lv5", "")) != "" else 2
		d["stat"] = PackedStringArray() if easy else UiKit.wrap(_f_small, UiKit.SZ_SMALL, num_s, CARD_W - 16.0, num_lines)
		var evo: String = String(d.get("evo", "")) if show_evo else ""
		d["pair"] = UiKit.wrap(_f_small, UiKit.SZ_SMALL, evo, CARD_W - 40.0, 2)
		d["done5"] = UiKit.wrap(_f_small, UiKit.SZ_SMALL, String(d.get("lv5", "")), CARD_W - 16.0, 2)
		_cards.append(d)


## 쉬운 카드(숫자·진화 줄 숨김): 처음 세 판. 연습 굿판은 '진화 짝'을 가르치므로 늘 보인다.
func _easy_cards() -> bool:
	var force: String = DebugTools.arg("easy-cards", "") if OS.is_debug_build() else ""   # 캡처용: 1 = 쉬운 카드 / 0 = 숫자·진화 줄 모두
	if force != "":
		return force == "1"
	if Game.tutorial_mode:
		return false
	var rd: int = Save.runs_done() if Save.has_method(&"runs_done") else 99
	return rd < 3


func _weapon_card(c: Dictionary, id: String, lv: int) -> Dictionary:
	var def: Dictionary = Data.weapon(id)
	var white: bool = String(def.get("color", c.get("color", "red"))) == "white"
	var d: Dictionary = {"id": id, "white": white, "lv": lv}
	d["band"] = "흰 무기 · 풀기" if white else "붉은 무기 · 베기"
	d["name"] = String(def.get("name_ko", c.get("title", id)))
	d["badge"] = "NEW" if lv <= 1 else "Lv %d→%d" % [lv - 1, lv]
	var lvls: Array = def.get("levels", []) if def.get("levels", []) is Array else []
	var row: Dictionary = lvls[lv - 1] if lv >= 1 and lv - 1 < lvls.size() else {}
	var prev: Dictionary = lvls[lv - 2] if lv >= 2 and lv - 2 < lvls.size() else {}
	var desc0: String = String(c.get("desc", ""))
	if lv <= 1:
		d["big"] = String(def.get("plain_ko", UiCopy.weapon_line(id)))
		if not row.is_empty():
			d["num"] = "피해 %s · %s초마다" % [_num(row.get("dmg", 0)), _num(row.get("cd", 0))]
	else:
		var big: String = String(row.get("plain_ko", ""))
		if big == "":
			big = desc0.get_slice("\n", 0) if desc0 != "" else String(row.get("change", ""))
		d["big"] = big
		d["num"] = _diff_line(prev, row)
	# 진화 짝 줄(+결합): 결합 줄은 후보 사전(weapon_manager)의 문구를 빌리고, 진화는 쉬운 말로.
	var evo: PackedStringArray = PackedStringArray()
	if bool(c.get("union_path", false)):
		for ln: String in desc0.split("\n"):
			if ln.begins_with("결합"):
				evo.append(ln.replace("결합 짝:", "결합:"))
				break
	var pair: String = String(def.get("pair_passive", ""))
	if pair != "":
		var pname: String = String(Data.passive(pair).get("name_ko", pair))
		var wm: WeaponManager = Game.weapons as WeaponManager
		var has_p: bool = wm != null and wm.has_method(&"passive_level") and int(wm.call(&"passive_level", StringName(pair))) > 0
		if lv >= 8 and has_p:
			evo.append("이제 상자를 열면 진화!")
		elif has_p:
			evo.append("진화 짝 %s 있음 · Lv8에 진화" % pname)
		else:
			evo.append("진화 짝: %s\n함께 키우면 진화" % pname)
	d["evo"] = "\n".join(evo)
	d["icon"] = UiKit.weapon_icon(id, false)
	return d


## 숫자 줄: 바뀐 값만 'a→b'(피해·간격·개수·범위). 아무것도 안 바뀌면 원래 change 문구.
func _diff_line(a: Dictionary, b: Dictionary) -> String:
	if a.is_empty() or b.is_empty():
		return String(b.get("change", ""))
	var parts: PackedStringArray = PackedStringArray()
	var keys: Array = [["dmg", "피해 %s→%s"], ["cd", "%s→%s초마다"], ["amt", "개수 %s→%s"], ["spins", "회전 %s→%s"], ["pierce", "꿰뚫기 %s→%s"], ["area", "범위 %s→%s"]]
	for kv: Variant in keys:
		var k: String = String((kv as Array)[0])
		if a.has(k) and b.has(k) and not is_equal_approx(float(a[k]), float(b[k])):
			parts.append(String((kv as Array)[1]) % [_num(a[k]), _num(b[k])])
	if parts.is_empty():
		return String(b.get("change", ""))
	return " · ".join(parts)


## 패시브·충전 카드 — 후보 사전의 title/desc/color(tilt: red|white|neutral). 적용은 levelup_chosen → combat.
func _side_card(c: Dictionary, id: String, lv: int, kind: String) -> Dictionary:
	var pd: Dictionary = Data.passive(id) if kind == "passive" else {}
	var tilt0: String = String(c.get("color", "neutral"))
	var d: Dictionary = {"id": id, "white": tilt0 != "red", "lv": lv}
	d["name"] = String(c.get("title", pd.get("name_ko", id)))
	if kind == "filler":
		d["band"] = "보너스"
		d["badge"] = "+"
		d["big"] = String(FILLER_PLAIN.get(id, String(c.get("desc", ""))))
	else:
		d["band"] = "아이템"
		d["badge"] = "NEW" if lv <= 1 else "Lv %d→%d" % [lv - 1, lv]
		var head: String = _passive_head(pd, lv)
		var plain: String = String(pd.get("plain_ko", ""))
		d["head"] = head
		d["plain"] = plain
		if head != "" and plain != "":
			d["big"] = head + "\n" + plain
		else:
			d["big"] = head + plain
		d["num"] = _passive_total(pd, lv) if lv > 1 else ""
		# 짝 무기(진화)
		var pw: Variant = pd.get("pair_weapons", [])
		if bool(c.get("pair_lv8", false)):
			d["evo"] = "고르면 진화 길이 열린다!"
		elif pw is Array and not (pw as Array).is_empty():
			var names: PackedStringArray = PackedStringArray()
			for wid: Variant in pw:
				names.append(String(Data.weapon(String(wid)).get("name_ko", wid)))
			d["evo"] = "진화 짝: %s\n함께 키우면 진화" % ", ".join(names)
		# Lv5 완성 효과: 도는 것만 이름 그대로, 아직 없는 것은 '완성 효과(준비 중)'
		if lv >= 5:
			if _lv5_works(id):
				var comp: Variant = pd.get("lv5_completion", {})
				var cname: String = String((comp as Dictionary).get("name_ko", "")) if comp is Dictionary else ""
				d["lv5"] = "완성 효과: %s" % String(pd.get("lv5_plain_ko", cname))
			else:
				d["lv5"] = "완성 효과(준비 중)"
	var ic: Texture2D = null
	var ip: String = "res://assets/icons/%s.png" % id
	if ResourceLoader.exists(ip):
		ic = SpriteLib.tex(ip)
	d["icon"] = ic
	return d


const FILLER_PLAIN: Dictionary = {"gongmul": "체력 25% 회복", "sinmyeong": "신명 +20% — 가득 차면 신명!"}
## Lv5 완성 효과 중 문장 그대로 화면에서 보이는 것(design/19 §5.2 E, vfx/passive_procs.gd).
## 위패(둘레를 풀어 줌)·명다리(부활 밀침)는 판정이 아직 없어 연출만 나간다 — 판정이 들어올 때까지 '(준비 중)'.
const LV5_WORKING: Array[String] = ["psv_jusa", "psv_chotdae"]


func _lv5_works(id: String) -> bool:
	return LV5_WORKING.has(id) and ResourceLoader.exists("res://vfx/passive_procs.gd")


## 패시브 큰 줄: 이번에 오르는 몫(예: '공격력 +8%').
func _passive_head(pd: Dictionary, lv: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var mods: Variant = pd.get("modifiers", [])
	if not (mods is Array):
		return ""
	for m: Variant in mods:
		if not (m is Dictionary):
			continue
		var lvls: Variant = (m as Dictionary).get("levels", [])
		if not (lvls is Array) or (lvls as Array).is_empty():
			continue
		var arr: Array = lvls
		var v1: float = float(arr[clampi(lv, 1, arr.size()) - 1])
		var v0: float = float(arr[clampi(lv - 1, 1, arr.size()) - 1]) if lv >= 2 else 0.0
		var dv: float = v1 - v0
		if is_zero_approx(dv):
			continue
		parts.append(_stat_text(String((m as Dictionary).get("stat", "")), String((m as Dictionary).get("op", "flat")), dv))
	return " · ".join(parts)


## 숫자 줄(Lv2 이상): 합계
func _passive_total(pd: Dictionary, lv: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var mods: Variant = pd.get("modifiers", [])
	if not (mods is Array):
		return ""
	for m: Variant in mods:
		if not (m is Dictionary):
			continue
		var lvls: Variant = (m as Dictionary).get("levels", [])
		if not (lvls is Array) or (lvls as Array).is_empty():
			continue
		var arr: Array = lvls
		parts.append(_stat_text(String((m as Dictionary).get("stat", "")), String((m as Dictionary).get("op", "flat")), float(arr[clampi(lv, 1, arr.size()) - 1])))
	return ("합계 " + " · ".join(parts)) if not parts.is_empty() else ""


## 스탯 쉬운 이름(design/19 §2.4). UiKit.stat_name(stats.json name_ui) 우선, 없으면 아래 표.
const STAT_PLAIN: Dictionary = {
	"stat_sinppal": "공격력", "stat_doryang": "범위", "stat_jangdan": "공격 속도", "stat_gise": "날리는 속도",
	"stat_yeongheom": "지속 시간", "stat_domu": "이동 속도", "stat_jeonggi": "최대 체력", "stat_saenggi": "회복",
	"stat_sinbok": "방어", "stat_sinjang": "발사 수", "stat_gyeoldan": "치명타", "stat_chohon": "줍기 범위",
	"stat_haewon_suryeon": "경험치", "stat_siju": "엽전 획득", "stat_jeomgwae": "행운", "stat_salgi": "위험도",
	"stat_haengnyeol": "넋 동무 수", "stat_neok_sumyeong": "넋 동무 시간",
}


static func stat_plain(stat: String) -> String:
	var v: String = UiKit.stat_name(stat)
	if v != "" and v != stat:
		return v
	return String(STAT_PLAIN.get(stat, stat))


func _stat_text(stat: String, op: String, v: float) -> String:
	var nm: String = stat_plain(stat)
	if stat == "stat_jangdan":
		return "%s %+d%%" % [nm, int(roundf(-v * 100.0))]   # 쿨다운 −6% → 공격 속도 +6%(플레이어 쪽 방향)
	if op == "add_pct" or stat == "stat_gyeoldan":
		return "%s %+d%%" % [nm, int(roundf(v * 100.0))]
	if stat == "stat_saenggi":
		return "%s +%s/초" % [nm, _num(v)]
	if stat == "stat_neok_sumyeong":
		return "%s +%s초" % [nm, _num(v)]
	return "%s %s" % [nm, ("%+d" % int(v)) if is_equal_approx(v, roundf(v)) else ("%+.1f" % v)]


## 신령의 힘(정규 점지에 섞일 때): deities.json powers[].plain_ko
func _power_card(c: Dictionary, id: String, lv: int) -> Dictionary:
	var d: Dictionary = {"id": id, "white": false, "lv": lv}
	d["band"] = "신령의 힘"
	d["name"] = String(c.get("title", id))
	d["badge"] = ("Lv %d→%d" % [lv - 1, lv]) if lv > 1 else "NEW"
	var plain: String = ""
	var deity: String = String(c.get("deity", ""))
	var dd: Dictionary = Data.deity(deity) if deity != "" else {}
	var pl: Variant = dd.get("powers", [])
	if pl is Array:
		for p: Variant in pl:
			if p is Dictionary and String((p as Dictionary).get("id", "")) == id:
				plain = String((p as Dictionary).get("plain_ko", ""))
	d["big"] = plain if plain != "" else String(c.get("desc", ""))
	d["num"] = String(c.get("desc", "")) if plain != "" else ""
	d["icon"] = null
	return d


func _num(v: Variant) -> String:
	var f: float = float(v)
	if is_equal_approx(f, roundf(f)):
		return "%d" % int(f)
	return "%.1f" % f


func _choose(i: int) -> void:
	if not visible or _closing or _lock_left > 0.0 or _need_release or i < 0 or i >= _choices.size():
		return
	_picked = i
	_closing = true
	_close_t = 0.0
	Audio.play_sfx(&"sfx_ui_jeomji_pick", &"UI")


func _finish_close() -> void:
	var c: Dictionary = _choices[_picked]
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm != null and String(c.get("kind", "")) == "weapon":
		wm.add_or_level(StringName(c.get("id", "")))
	Events.levelup_chosen.emit(c)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_closing = false
	Game.pop_pause(&"levelup")
	if Game.player != null:
		var p: Player = Game.player as Player
		p.hit.iframe_left = maxf(p.hit.iframe_left, Data.num("combat_core", "jeomji.resume_iframe", 0.75))
	if _pending > 0:
		_pending -= 1
		_open_now.call_deferred()


func _process(delta: float) -> void:
	if _defer_tick >= 0 and not visible:
		if not Game.is_sim_paused():
			_defer_real += delta
		if (Game.game_tick >= _defer_tick and not Game.is_hitstop() and not Game.is_sim_paused()) or _defer_real >= 1.5:
			_open_now()
		return
	if not visible:
		return
	_t += delta
	if _lock_left > 0.0:
		_lock_left -= delta
	if _need_release and not _any_held():
		_need_release = false
	if _closing:
		_close_t += delta
		if _close_t >= 0.27:
			_finish_close()
			return
	if _auto_left > 0.0:
		_auto_left -= delta
		if _auto_left <= 0.0:
			_lock_left = 0.0
			_need_release = false
			_choose(0)
	var lock: bool = _lock_left > 0.0 or _need_release
	if lock != _lock_was:
		_lock_was = lock
		_dirty = true
	# 등장 연출(≈0.6초)·닫힘 중에만 매 프레임, 그 뒤엔 포커스가 바뀔 때만 다시 그린다
	if _t < 0.7 or _closing or _dirty:
		_dirty = false
		queue_redraw()


func _card_rect(i: int) -> Rect2:
	var n: int = _choices.size()
	var total: float = n * CARD_W + (n - 1) * CARD_GAP
	var x0: float = roundf(size.x * 0.5 - total * 0.5)
	var y: float = roundf(size.y * 0.5 - CARD_H * 0.5 + 6.0)
	return Rect2(x0 + i * (CARD_W + CARD_GAP), y, CARD_W, CARD_H)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in 3:
		if event.is_action_pressed(StringName("choice_%d" % (i + 1))):
			_focus = mini(i, _choices.size() - 1)
			_choose(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_focus = maxi(0, _focus - 1)
		_dirty = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_focus = mini(_choices.size() - 1, _focus + 1)
		_dirty = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"confirm") or event.is_action_pressed(&"ui_accept"):
		_choose(_focus)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = (event as InputEventMouseMotion).position
		for i in _choices.size():
			if _card_rect(i).has_point(mp) and _focus != i:
				_focus = i
				_dirty = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mp2: Vector2 = (event as InputEventMouseButton).position
		for i in _choices.size():
			if _card_rect(i).has_point(mp2):
				_focus = i
				_choose(i)
				accept_event()


# ─── 그리기 ─────────────────────────────────────────────────────────────

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = roundf(w * 0.5)
	var fade_out: float = clampf((_close_t - 0.12) / 0.15, 0.0, 1.0) if _closing else 0.0
	var dim: float = clampf(_t / 0.15, 0.0, 1.0) * 0.8 * (1.0 - fade_out)
	draw_rect(Rect2(0, 0, w, h), Color(UiKit.MEOK, dim))
	var ha: float = clampf(_t / _enter, 0.0, 1.0) * (1.0 - fade_out)
	# 제목: 붓 '점지' + 오른쪽 작은 '새 힘 고르기'(한자 點指 자리를 대신함, design/19 §4.3)
	var ty: float = _card_rect(0).position.y - 22.0
	var tw: float = UiKit.text_outline(self, _f_brush, 40, Vector2(cx, ty), "점지", Color(UiKit.HANJI_UI, ha), 1, 2)
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(roundf(cx + tw * 0.5 + 8.0), ty - 4.0), "새 힘 고르기", Color(UiKit.HWANG_HI, ha), 0)
	UiKit.draw_dancheong(self, Rect2(cx - 90, ty + 6.0, 60, 3))
	UiKit.draw_dancheong(self, Rect2(cx + 30, ty + 6.0, 60, 3))
	if _pending > 0:
		UiKit.text(self, _f_bold, UiKit.SZ_BODY, Vector2(w - 10, 20), "새 힘 ×%d" % (_pending + 1), Color(UiKit.HWANG_HI, ha), 2)
	_draw_build(ha)
	for i in _cards.size():
		_draw_card(i, fade_out)
	# 아래 조작 안내
	var lock: bool = _lock_left > 0.0 or _need_release
	var hint: String = "1 · 2 · 3  고르기     ← →  옮기기     Enter  받기"
	var by: float = _card_rect(0).end.y
	# 첫 점지 안내(카드 아래, 카드와 겹치지 않게): 붉은 = 베어 처치 / 흰 = 풀어 줌
	if _first_note:
		UiKit.text(self, _f_body, UiKit.SZ_BODY, Vector2(cx, by + 20.0), FIRST_NOTE, Color(UiKit.HWANG_HI, ha), 1)
		by += 16.0
	UiKit.text(self, _f_small, UiKit.SZ_SMALL, Vector2(cx, by + 22.0), hint,
		Color(UiKit.HANJI_3 if lock else UiKit.HANJI_2, ha * (0.5 if lock else 1.0)), 1)


## 현재 무구(딤 위로 끌어올린 슬롯): 좌상단
func _draw_build(a: float) -> void:
	var wm: WeaponManager = Game.weapons as WeaponManager
	if wm == null:
		return
	for i in 6:
		var r: Rect2 = Rect2(26 + i * 20, 13, 18, 18)
		var wpn: WeaponBase = wm.weapon_at(i) if i < wm.slot_count() else null
		draw_rect(r.grow(1.0), Color(UiKit.MEOK, a))
		draw_rect(r, Color(UiKit.MEOK_2, a))
		if wpn == null:
			continue
		draw_rect(r, Color(UiKit.HANJI_3 if wpn.is_white() else UiKit.JEOK, a), false, 1.0)
		var t: Texture2D = UiKit.weapon_icon(String(wpn.id), true)
		if t != null:
			draw_texture(t, r.position + Vector2(1, 1), Color(1, 1, 1, a))
		elif a >= 0.99:
			UiKit.draw_glyph_medallion(self, r.grow(-1.0), String(wpn.id), wpn.is_white(), _f_small)
		UiKit.text(self, _f_tiny, UiKit.SZ_TINY, r.position + Vector2(18, 27), "%d" % wpn.level, Color(UiKit.HWANG_HI, a), 2)


func _draw_card(i: int, fade_out: float) -> void:
	var d: Dictionary = _cards[i]
	var base: Rect2 = _card_rect(i)
	var p: float = clampf((_t - _stagger * i) / _anim, 0.0, 1.0)
	if p <= 0.0:
		return
	var off: float = roundf((1.0 - UiKit.ease_out_back(p)) * 90.0)
	var focus: bool = i == _focus and not _closing
	var lift: float = 3.0 if focus else 0.0
	var a: float = clampf(p * 3.0, 0.0, 1.0)
	if _closing:
		if i == _picked:
			lift = 5.0 if _close_t < 0.12 else 5.0 + (_close_t - 0.12) * 120.0
			a = 1.0 - fade_out
		else:
			off = roundf(_close_t * 160.0)
			a = clampf(1.0 - _close_t * 6.0, 0.0, 1.0)
	if a <= 0.0:
		return
	var r: Rect2 = Rect2(base.position + Vector2(0, off - lift), base.size)
	var white: bool = bool(d["white"])
	var mod: Color = Color(1, 1, 1, a)
	# 그림자 + 한지 바탕
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(UiKit.MEOK, 0.6 * a))
	draw_rect(r.grow(1.0), Color(UiKit.MEOK, a))
	if _paper != null:
		draw_texture_rect(_paper, r, true, mod)
	else:
		draw_rect(r, Color(UiKit.HANJI, a))
	draw_rect(r.grow(-2.0), Color(UiKit.HANJI_3, a), false, 1.0)
	# 종류 띠: '붉은 무기 · 베기' / '흰 무기 · 풀기' / '아이템'
	var band: Rect2 = Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 15))
	var ink: Color = Color(UiKit.INK, a)
	if white:
		draw_rect(band, Color(UiKit.HANJI_2, a))
		draw_rect(Rect2(band.position.x, band.end.y, band.size.x, 1), Color(UiKit.HANJI_4, a))
		UiKit.draw_kind_mark(self, band.position + Vector2(8, 7), 3.0, true)
		draw_string(_f_small, band.position + Vector2(15, 11), String(d.get("band", "흰 무기 · 풀기")), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, ink)
	else:
		draw_rect(band, Color(UiKit.JEOK, a))
		draw_rect(Rect2(band.position.x, band.end.y, band.size.x, 1), Color(UiKit.JEOK_DDK, a))
		UiKit.draw_diamond(self, band.position + Vector2(8, 7), 4.0, Color(UiKit.MEOK, a))
		UiKit.draw_diamond(self, band.position + Vector2(8, 7), 3.0, Color(UiKit.HANJI_UI, a))
		draw_string(_f_small, band.position + Vector2(15, 11), String(d.get("band", "붉은 무기 · 베기")), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.HANJI_UI, a))
	var badge: String = String(d["badge"])
	var bw: float = _f_tiny.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY).x + 6.0
	var br: Rect2 = Rect2(band.end.x - bw - 2.0, band.position.y + 3.0, bw, 10)
	draw_rect(br, Color(UiKit.MEOK_1, a))
	draw_string(_f_tiny, br.position + Vector2(3, 8), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY, Color(UiKit.HWANG_HI, a))
	# 아이콘(원 = 흰 / 마름모 = 붉은 바탕 이중 표기)
	var ic: Vector2 = Vector2(r.get_center().x, r.position.y + 44.0)
	if white:
		draw_circle(ic, 22.0, Color(UiKit.HANJI_2, a))
		draw_arc(ic, 22.0, 0.0, TAU, 32, Color(UiKit.HANJI_4, a), 1.0)
	else:
		UiKit.draw_diamond(self, ic, 25.0, Color(UiKit.HANJI_2, a))
		UiKit.draw_diamond(self, ic, 25.0, Color(UiKit.JEOK_DK, a), false)
	var t: Texture2D = d["icon"]
	if t != null:
		var reg: Rect2 = UiKit.icon_region(t)
		var dst: Rect2 = Rect2((ic - reg.size * 0.5).round(), reg.size)
		draw_texture_rect_region(t, dst, reg, mod)
	else:
		UiKit.text_outline(self, _f_brush, 32, ic + Vector2(0, 10), String(d["name"]).left(1), Color(UiKit.HANJI_UI, a), 1, 2)
	# 이름(Bold 12) — 한자는 화면에서 뺐다(도감·안내서에만)
	var ny: float = r.position.y + 86.0
	var nm: String = String(d["name"])
	var nw: float = _f_bold.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
	draw_string(_f_bold, Vector2(roundf(r.get_center().x - nw * 0.5), ny), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
	var ly: float = ny + 5.0
	draw_rect(Rect2(r.position.x + 20, ly, r.size.x - 40, 1), Color(UiKit.HANJI_4, a))
	# 큰 효과 한 줄(T3 12, 최대 2줄)
	var y: float = ly + 15.0
	for line: String in (d["desc"] as PackedStringArray):
		var lw: float = _f_body.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY).x
		draw_string(_f_body, Vector2(roundf(r.get_center().x - lw * 0.5), y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_BODY, ink)
		y += 14.0
	# 숫자(T4 10, 한지 바탕 보조색) — 처음 세 판은 비어 있다
	y += 1.0
	for line2: String in (d["stat"] as PackedStringArray):
		var lw2: float = _f_small.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
		draw_string(_f_small, Vector2(roundf(r.get_center().x - lw2 * 0.5), y), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.HANJI_5, a))
		y += 12.0
	# Lv5 완성 효과(아이템): 동작 = 적 진한 색 / 준비 중 = 보조색
	for line3: String in (d["done5"] as PackedStringArray):
		var lw3: float = _f_small.get_string_size(line3, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
		var ready: bool = not line3.contains("준비 중")
		draw_string(_f_small, Vector2(roundf(r.get_center().x - lw3 * 0.5), y), line3, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.JEOK_DK if ready else UiKit.HANJI_5, a))
		y += 12.0
	# 진화 짝 줄(아래, 번호 인장 옆) — 첫 상자 뒤부터
	var pl: PackedStringArray = d["pair"]
	var py: float = r.end.y - 8.0 - 12.0 * float(maxi(0, pl.size() - 1))
	for line4: String in pl:
		var pw: float = _f_small.get_string_size(line4, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL).x
		draw_string(_f_small, Vector2(roundf(r.get_center().x + 6.0 - pw * 0.5), py), line4, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_SMALL, Color(UiKit.HANJI_5, a))
		py += 12.0
	# 번호 인장(왼쪽 아래)
	var sr: Rect2 = Rect2(r.position.x + 5, r.end.y - 17, 12, 12)
	draw_rect(sr, Color(UiKit.JEOK, a))
	draw_rect(sr.grow(-1.0), Color(UiKit.HANJI_UI, a), false, 1.0)
	draw_string(_f_tiny, sr.position + Vector2(4, 9), "%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SZ_TINY, Color(UiKit.HANJI_UI, a))
	UiKit.draw_corners(self, r.grow(-1.0), Color(UiKit.JEOK_DK, a))
	# 포커스: 황 2px + 먹 1px 바깥 + 단청 모서리
	if focus or (_closing and i == _picked):
		var fr: Rect2 = r.grow(3.0)
		draw_rect(fr.grow(1.0), Color(UiKit.MEOK, a), false, 1.0)
		draw_rect(fr, Color(UiKit.HWANG, a), false, 2.0)
		UiKit.draw_corners(self, fr.grow(2.0), Color(UiKit.HWANG_HI, a))
		if _closing and i == _picked and _close_t < 0.12:
			draw_rect(r, Color(UiKit.HANJI_UI, 0.35 * (1.0 - _close_t / 0.12)))
