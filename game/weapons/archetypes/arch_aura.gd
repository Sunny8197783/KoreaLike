class_name ArchAura
extends WeaponBase
## 원형 aura: 상시 원형 오라(방울: mode "aura") / 주기 확산 파동(장구 덩·호작도·작두: mode "pulse"). 소유: combat.
## params: mode(aura|pulse), downbeat(박 머리 고정 — 장구), ring2(장구 L5 후속 "쿵"), fear(호작도: 경악·경직·공포 증폭·등 뒤 강화)
##   jakdu(작두: 저정기 역보정·무적·T2 히트스톱·후속 충격파) · wave2(대작두 2파) · ring_judge(작두다리: 원 안 풀릴 기색 즉시 해원)
##   resonance(천음방울: 2박마다 공명 파동 + 풀릴 기색 끌어오기) · gideok(합장단: 기덕 2연 + 피격 반격) · sub_trail(작두다리: 길베 트레일 피해)
## 레벨 필드: dmg, area(u), kb(u), expand(s), ring2, fear, fear_amp, stagger, invuln, lowhp_k, pull_slow …

const PULSE_CAP: int = 6
## 호작도 세화(족자): 한지 바탕 · 위아래 축목 · 소나무 · 까치 · 줄무늬 범 얼굴. 마스터 팔레트만(괴황지·붉은 符자 금지 — ART_STYLE 2.2).
## 바닥 층(z −2, 플레이어 아래)에 등 뒤 머리 위로 그려 얼굴을 가리는 프레임이 없다. 펼침 = 위 축목 고정, 아래로 풀림.
const SEHWA_ROWS: PackedStringArray = [
	"......ss......",
	"rRRRRRRRRRRRRr",
	".BhhhhhhhhhhB.",
	".BHGGgHHHHHHB.",
	".BGgGGgHHKKHB.",
	".BHTGHHHKKKCB.",
	".BHTHHHHHKHCB.",
	".BHTHHHHHHHHB.",
	".BHTHHHHHHHHB.",
	".BHHYYHHYYHHB.",
	".BHYYYYYYYYHB.",
	".BHYKYYYYKYHB.",
	".BYKKYYYYKKYB.",
	".BYYYYKKYYYYB.",
	".BHYKYYYYKYHB.",
	".BHYYKKKKYYHB.",
	".BHHyYYYYyHHB.",
	".BHHHyKKyHHHB.",
	".BhhhhhhhhhhB.",
	"rRRRRRRRRRRRRr",
]
const SEHWA_COLS: Dictionary = {
	"s": "857154", "r": "7c674b", "R": "433426", "B": "b29d76", "H": "e9dcc0", "h": "d2c19c",
	"G": "26402b", "g": "3a5a3c", "T": "6b3a2a", "K": "1a1a1a", "C": "2a5caa", "Y": "e8b931", "y": "a97c1b",
}
static var _sehwa_tex: ImageTexture = null
var p_t: PackedFloat32Array = PackedFloat32Array()        # 남은 확산 시간(<= 0 비활성)
var p_len: PackedFloat32Array = PackedFloat32Array()
var p_r: PackedFloat32Array = PackedFloat32Array()        # 최대 반경 px
var p_dmg: PackedFloat32Array = PackedFloat32Array()
var p_kb: PackedFloat32Array = PackedFloat32Array()
var p_tick: PackedInt32Array = PackedInt32Array()         # 시작 game_tick(연출)
var p_hits: PackedInt32Array = PackedInt32Array()
var p_slam: PackedInt32Array = PackedInt32Array()         # 작두 강타 피드백: 0 없음 · 1 내리침 · 2 대작두 2파 · -1 이미 냄
var _hit_pulse: PackedByteArray = PackedByteArray()   # PULSE_CAP × CAPACITY (펄스별 1회 타격)
var _last_beat: int = -1
var _beats: int = 0
var _counter_cd: float = 0.0
var _res_tick: int = -100000
var _aura_hits: int = 0


func _on_setup() -> void:
	if bool(params.get("fear", false)) and _sehwa_tex == null:
		_sehwa_tex = _build_sehwa()
	p_t.resize(PULSE_CAP)
	p_t.fill(0.0)
	p_len.resize(PULSE_CAP)
	p_r.resize(PULSE_CAP)
	p_dmg.resize(PULSE_CAP)
	p_kb.resize(PULSE_CAP)
	p_tick.resize(PULSE_CAP)
	p_tick.fill(-100000)
	p_hits.resize(PULSE_CAP)
	p_slam.resize(PULSE_CAP)
	p_slam.fill(0)
	_hit_pulse.resize(PULSE_CAP * EnemyManager.CAPACITY)
	if bool(params.get("gideok", false)):
		Events.player_damaged.connect(_on_player_damaged)
	if bool(params.get("sub_trail", false)):
		add_sub(&"drop_zone", {"place": "trail_only", "gilbe_trail": true, "base": "wpn_gilbe"}, {"trail_dmg": s("trail_dmg", 8.0), "trail_width": s("trail_width", 0.8), "cd": 0.5, "tick": 0.5}, "white")


func _on_dispose() -> void:
	if Events.player_damaged.is_connected(_on_player_damaged):
		Events.player_damaged.disconnect(_on_player_damaged)


func _is_aura() -> bool:
	return String(params.get("mode", "aura")) == "aura"


## 반경(px): 도량 × (신장 수 1당 방울 +6% · 호작도 +8%, 상한 ×3).
func _radius() -> float:
	var per: float = 0.0
	if _is_aura():
		per = 0.06
	elif bool(params.get("fear", false)):
		per = 0.08
	var sj: float = minf(float(sinjang()), 3.0) * per
	return s("area", 2.5) * K.UNIT_PX * area_mult() * (1.0 + sj)


func _jakdu_mult() -> float:
	if not bool(params.get("jakdu", false)):
		return 1.0
	var miss: float = 1.0 - clampf(Game.hp / maxf(1.0, Game.hp_max), 0.0, 1.0)
	return 1.0 + (s("lowhp_k", 1.5) - 1.0) * miss


func fire() -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	if _is_aura():
		_aura_hits = 0
		var r: float = _radius()
		var n: int = em.query_circle(player_pos(), r, _q)
		var slow: float = s("pull_slow", 0.0)
		for k in n:
			var i: int = _q[k]
			if (em.flags[i] & EnemyManager.F_DYING) != 0:
				continue
			deal(i, s("dmg", 3.0), (em.pos_of(i) - player_pos()).normalized(), s("kb", 0.0))
			_aura_hits += 1
			if slow > 0.0 and (em.flags[i] & EnemyManager.F_PULLIL) != 0:
				apply_status(i, &"st_dunhwa", s("cd", 0.6) + 0.1, slow)
		return
	var mult: float = _jakdu_mult()
	var main_p: int = _start_pulse(_radius(), s("dmg", 8.0) * mult, s("kb", 0.5))
	if bool(params.get("jakdu", false)):
		p_slam[main_p] = 2 if bool(params.get("wave2", false)) else 1   # 적중 ≥3 이면 jakdu_slam — 헛치면 흔들지 않는다
	# 장구 L5 후속 "쿵"(반박 뒤 50%) · 신장 수 1당 후속 고리(70%, 상한 +3)
	var half_beat: float = Beat.beat_len_sec() * 0.5
	if bool(params.get("ring2", false)):
		var extra: int = (1 if s("ring2", 0.0) > 0.0 else 0)
		var m: float = 0.5
		for k in extra + mini(sinjang(), 3):
			schedule_action(half_beat * float(k + 1), 1, Vector2.ZERO, m)
			m = 0.7
	if bool(params.get("gideok", false)):
		schedule_action(half_beat, 2, Vector2.ZERO, 1.0)
		schedule_action(half_beat * 1.5, 2, Vector2.ZERO, 1.0)
	if bool(params.get("jakdu", false)):
		var p: Player = Game.player as Player
		if p != null:
			p.hit.iframe_left = maxf(p.hit.iframe_left, s("invuln", 0.5))
		if bool(params.get("wave2", false)):
			schedule_action(0.4, 3, Vector2.ZERO, s("wave2_mult", 0.6))
		for k2 in mini(sinjang(), int(limit("amt_cap", 2))):
			schedule_action(0.4 * float(k2 + 1) + (0.4 if bool(params.get("wave2", false)) else 0.0), 4, Vector2.ZERO, 0.5)


func _action(code: int, _dir: Vector2, mult: float) -> void:
	match code:
		1:
			_start_pulse(_radius(), s("dmg", 8.0) * mult, s("kb", 0.5) * 0.5)
		2:
			_start_pulse(s("gideok_r", 3.6) * K.UNIT_PX * area_mult(), s("gideok_dmg", 12.0), 0.3)
			Audio.play_sfx(&"sfx_wpn_janggu", &"SFX", -10.0, 0.15)
		3:
			var w2: int = _start_pulse(_radius() * s("wave2_area", 1.3), s("dmg", 30.0) * _jakdu_mult() * mult, s("kb", 1.0) * 0.6)
			p_slam[w2] = 2                      # 대작두 2파: 킥 2px
		4:
			_start_pulse(_radius() * 1.2, s("dmg", 30.0) * _jakdu_mult() * mult, s("kb", 1.0) * 0.5)


func _start_pulse(r: float, dmg: float, kb: float) -> int:
	var best: int = 0
	for k in PULSE_CAP:
		if p_t[k] <= 0.0:
			best = k
			break
		if p_t[k] < p_t[best]:
			best = k
	p_len[best] = maxf(s("expand", 0.25), 0.1)
	p_t[best] = p_len[best]
	p_r[best] = r
	p_dmg[best] = dmg
	p_kb[best] = kb
	p_tick[best] = Game.game_tick
	p_hits[best] = 0
	p_slam[best] = 0
	var b0: int = best * EnemyManager.CAPACITY
	for k2 in EnemyManager.CAPACITY:
		_hit_pulse[b0 + k2] = 0
	return best


func _on_player_damaged(_amount: float, _src: StringName, _hp: float, _hpm: float) -> void:
	if _counter_cd > 0.0:
		return
	_counter_cd = s("counter_icd", 1.0)
	_start_pulse(s("counter_r", 3.0) * K.UNIT_PX * area_mult(), s("counter_dmg", 30.0), 0.6)


func tick(dt: float) -> void:
	_counter_cd = maxf(0.0, _counter_cd - dt)
	if bool(params.get("resonance", false)) and Beat.is_beat_tick and Beat.beat_index != _last_beat:
		_last_beat = Beat.beat_index
		_beats += 1
		if _beats % maxi(1, int(s("res_beats", 2))) == 0:
			_resonance()
	var em: EnemyManager = enemies()
	if em == null:
		return
	var o: Vector2 = player_pos()
	var fear: bool = bool(params.get("fear", false))
	var judge: bool = bool(params.get("ring_judge", false))
	var back: Vector2 = -move_dir()
	for p in PULSE_CAP:
		if p_t[p] <= 0.0:
			continue
		p_t[p] -= dt
		var prog: float = 1.0 - clampf(p_t[p] / p_len[p], 0.0, 1.0)
		var r: float = p_r[p] * prog
		var n: int = em.query_circle(o, r, _q)
		var base_i: int = p * EnemyManager.CAPACITY
		for k in n:
			var i: int = _q[k]
			if _hit_pulse[base_i + i] != 0 or (em.flags[i] & EnemyManager.F_DYING) != 0:
				continue
			_hit_pulse[base_i + i] = 1
			var d: Vector2 = em.pos_of(i) - o
			var kd: Vector2 = d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT
			var f: int = em.flags[i]
			if judge and (f & EnemyManager.F_PULLIL) != 0 and (f & EnemyManager.F_ELITE_PLUS) == 0:
				em.force_haewon(i, &"ring")
				p_hits[p] += 1
				continue
			var m: float = 1.0
			if fear and kd.dot(back) > 0.3:
				m = 1.3                       # 등 뒤 반원 강화(세화)
			deal(i, p_dmg[p], kd, p_kb[p], m)
			p_hits[p] += 1
			if fear:
				apply_status(i, &"st_gyeongak", s("fear", 1.5) * dur_mult())
				apply_status(i, &"st_gyeongjik", s("stagger", 0.3))
				if s("fear_amp", 0.0) > 0.0:
					(mgr as WeaponManager).set_fear(i, s("fear", 1.5) * dur_mult(), s("fear_amp", 0.0))
		if p_slam[p] > 0 and p_hits[p] >= int(_feel_f("hitstop_min_hits", 3)):
			# GAME_FEEL 3.1·5.1: 작두 내리침 적중 ≥3 → jakdu_slam(T2 50ms · 아래 킥 1px · 트라우마 .25). 적중 순간에 한 번.
			Juice.feedback_event("jakdu_slam", Vector2.DOWN)
			if p_slam[p] == 2:
				Juice.kick(Vector2.DOWN, 2)      # 대작두(진화): 킥 2px(가장 무거운 무구)
			p_slam[p] = -1


## 천음방울 공명: 반경 res_r 피해 + 풀릴 기색 끌어오기(초당 pull_spd u, 2박 주기분을 한 번에).
func _resonance() -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	var o: Vector2 = player_pos()
	var r: float = s("res_r", 6.0) * K.UNIT_PX * area_mult()
	var n: int = em.query_circle(o, r, _q)
	var pull_u: float = s("pull_spd", 0.8) * Beat.beat_len_sec() * float(s("res_beats", 2))
	for k in n:
		var i: int = _q[k]
		if (em.flags[i] & EnemyManager.F_DYING) != 0:
			continue
		var d: Vector2 = o - em.pos_of(i)
		if (em.flags[i] & EnemyManager.F_PULLIL) != 0:
			deal(i, s("res_dmg", 5.0), d.normalized(), minf(pull_u, d.length() / K.UNIT_PX * 0.8), 1.0, F_PULL | F_NO_SFX)
		else:
			deal(i, s("res_dmg", 5.0), -d.normalized(), 0.0, 1.0, F_NO_SFX)
	_res_tick = Game.game_tick
	var pk: PickupManager = Game.pickups as PickupManager
	if pk != null and s("orb_pull_r", 0.0) > 0.0:
		pk.pull_all(o, s("orb_pull_r", 6.0) * K.UNIT_PX)      # 공명: 원혼 구슬 흡인


# ─── 연출 ────────────────────────────────────────────────────────────

static func _build_sehwa() -> ImageTexture:
	var h: int = SEHWA_ROWS.size()
	var w: int = SEHWA_ROWS[0].length()
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = SEHWA_ROWS[y]
		for x in w:
			var ch: String = row[x]
			if SEHWA_COLS.has(ch):
				img.set_pixel(x, y, Color.html(String(SEHWA_COLS[ch])))
	return ImageTexture.create_from_image(img)


## 세화 족자(등 뒤·머리 위). 선딜 동안 풀리고, 발사 뒤 홀드+후딜+0.35초 유지, 마지막 0.15초 점멸.
func _draw_sehwa(ci: CanvasItem, o: Vector2) -> void:
	if _sehwa_tex == null:
		return
	var wp: float = windup_prog()
	var sf: float = since_fire()
	var keep: float = hold_s() + recovery_s() + 0.35
	var unroll: float = 0.0
	if wp >= 0.0:
		unroll = clampf(wp * 1.5, 0.0, 1.0)
	elif sf < keep:
		unroll = clampf(sf / 0.1, 0.0, 1.0) if windup_s() <= 0.0 else 1.0
		if sf > keep - 0.15 and (Game.anim_tick() / 3) % 2 == 0:
			return
	else:
		return
	var tw: int = SEHWA_ROWS[0].length()
	var th: int = SEHWA_ROWS.size()
	var body: int = th - 3                                  # 끈·위 축목(2줄)과 아래 축목(1줄) 사이
	var shown: int = 2 + int(roundf(float(body) * unroll))   # 위에서부터 보이는 줄 수(끈+축목 포함)
	var bx: float = -move_dir().x
	var tl: Vector2 = K.rndv(o + Vector2(roundf(bx * 9.0) - float(tw) * 0.5, -58.0))   # 아래 축목이 흑립 뒤로 들어가 등에 멘 듯(얼굴과 겹침 0 — 플레이어가 위 층)
	ci.draw_texture_rect_region(_sehwa_tex, Rect2(tl, Vector2(tw, shown)), Rect2(0, 0, tw, shown))
	ci.draw_texture_rect_region(_sehwa_tex, Rect2(tl + Vector2(0, shown), Vector2(tw, 1)), Rect2(0, th - 1, tw, 1))
	if sf < 0.05 and wp < 0.0:
		# 경악 파동 1f: 족자 테두리 적 섬광
		ci.draw_rect(Rect2(tl + Vector2(-1, 0), Vector2(tw + 2, shown + 2)), K.COL_JEOK_HI, false, 1.0)


func draw_ground(ci: CanvasItem) -> void:
	var o: Vector2 = render_origin()
	if bool(params.get("fear", false)):
		_draw_sehwa(ci, o)
	if _is_aura():
		# 상시 오라 테: 1px 점선(어두운 팔레트), 박마다 시트
		var r: float = _radius()
		var seg: int = clampi(int(r / 3.0), 16, 64)
		for k in seg:
			if k % 2 == 0:
				var a0: float = TAU * float(k) / float(seg)
				ci.draw_arc(K.rndv(o), roundf(r), a0, a0 + TAU / float(seg), 2, K.COL_HANJI_DK, 1.0)


func draw(ci: CanvasItem) -> void:
	var o: Vector2 = render_origin()
	var now: int = Game.anim_tick()
	var wp: float = windup_prog()
	if wp >= 0.0:
		draw_windup_hand(ci, move_dir())
		if (now / 2) % 2 == 0 or wp > 0.6:
			draw_ring(ci, o, _radius(), col_dk())
		if fx_name("fx_prop") != &"" and not bool(params.get("fear", false)):
			# 작두 올라섬: 선딜 동안 소품 시트 첫 프레임들(세화는 바닥 층 _draw_sehwa — 괴황지 부적 시트는 쓰지 않는다)
			draw_sheet(ci, fx_name("fx_prop"), o + Vector2(0, 2), (Game.anim_time() - wu_anim_t0) * 0.5, 0, Color.WHITE, true)
	var sf: float = since_fire()
	if _is_aura():
		if sf < 0.5:
			if not draw_sheet(ci, fx_name("fx_cast"), o + Vector2(0, -2), sf):
				if sf < 0.1:
					draw_ring(ci, o, _radius(), col_hi())
		if sf < 0.05:
			draw_ring(ci, o, _radius(), K.COL_HANJI)        # 박 1f 밝음(GAME_FEEL: 고리 1f)
		var rt: float = float(now - _res_tick) / K.TICK_HZ
		if rt >= 0.0 and rt < 0.35:
			if not draw_sheet(ci, fx_name("fx_ring"), o, rt):
				draw_ring(ci, o, s("res_r", 6.0) * K.UNIT_PX * area_mult() * clampf(rt / 0.25, 0.0, 1.0), K.COL_HANJI_DK)
		return
	if fx_name("fx_prop") != &"" and sf < hold_s() + recovery_s() and bool(params.get("jakdu", false)):
		draw_sheet(ci, fx_name("fx_prop"), o + Vector2(0, 2), sf + 0.25)
	for p in PULSE_CAP:
		var age: float = float(now - p_tick[p]) / K.TICK_HZ
		var ln: float = maxf(p_len[p], 0.1)
		if age < 0.0 or age > ln + recovery_s():
			continue
		if age < 0.6:
			draw_sheet(ci, fx_name("fx_cast"), o + Vector2(0, -4), age)
		var prog: float = clampf(age / ln, 0.0, 1.0)
		var r: float = p_r[p] * prog
		if age <= ln:
			draw_ring(ci, o, r, col_main(), 2.0)
			draw_ring(ci, o, maxf(0.0, r - 3.0), col_hi())
		else:
			# 후딜: 최대 반경 테가 2f 간격으로 점멸하며 사라짐
			if (now / 3) % 2 == 0:
				draw_ring(ci, o, p_r[p], col_dk())
