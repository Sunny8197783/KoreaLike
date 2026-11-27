class_name HitFeedback
extends Node
## 이벤트 → 타격감 연결(숫자·흔들림·히트스톱·이펙트·플래시). 소유: vfx.
## 단일 원본: data/feedback_matrix.json + combat_core.feedback_tiers/hitstop/feel. 이벤트별 값은 GAME_FEEL 5.1·5.2 표.
## 규칙: 신호를 받아 연출만 한다. 시뮬레이션 상태를 바꾸지 않는다(히트스톱은 Game 이 예산·결정론을 보장).
## P6: 군중의 일상 타격·일반 퇴치에는 흔들림·전역 히트스톱을 쓰지 않는다(대상 국소 반응은 EnemyManager 가 그린다).

var vfx: VfxPlayer = null

var _spark_fx: StringName = &"vfx_hit_spark_red"
var _spark_ok: bool = false
var _spark_white_fx: StringName = &"vfx_hit_spark_white"   # 백 무구 타격(hj + #fffdf6 심) — '붉은 것은 깎고 흰 것은 푼다'를 타격 순간에
var _spark_white_ok: bool = false
var _crit_kick_cd: int = 24                                  # 치명 킥 쿨다운(틱, combat_core.feel.crit_kick_cd_s 0.4) — P6 군중 상시 떨림 방지
var _crit_kick_last: int = -100000
var _spark_cap: int = 12
var _spark_iv_ticks: int = 6
var _spark_last: PackedInt32Array = PackedInt32Array()
var _spark_tick: int = -1
var _spark_n: int = 0
var _kill_tick: int = -1
var _kill_n: int = 0
# 다수 처치 틱 예산(리뷰 vfx#2): 가산 시트 수십 장이 한 점에 겹쳐 백화되지 않게. 넘치면 분위기 파티클만,
# 광원은 넘친 만큼 무게중심 하나로 묶는다(강도 합, 상한 1.5).
const KILL_SHEET_CAP: int = 8
const KILL_LIGHT_CAP: int = 4
var _kill_sheets: int = 0
# 군집 처치 창 예산: 틱 예산(8)만으로는 연속 틱에 해원 빛기둥 시트가 수십 장 쌓여 무리 쪽이 백으로 뭉친다.
#   SHEET_WIN 틱(0.25s) 창 안 시트 SHEET_WIN_CAP 장까지(정예 이상은 예외). 넘친 처치는 재·광원 묶음만 낸다.
const SHEET_WIN: int = 15
const SHEET_WIN_CAP: int = 6
var _win_t0: int = -1000
var _win_n: int = 0
var stat_sheet_skipped: int = 0
# 해원 빛기둥 층(design/18 §1.5 — '백은 해원 한 뜻만'): 가산 #f2ece0 시트가 어두운 바닥 위에서 #ffffff 로 타 흰 귀신·흰 무구와
#   같은 층에 섞였다. 순백(세기 1.0)은 정예 이상·런 처음 HW_FULL_FIRST 해원에만. 나머지는 가산·풀 길이·광원 1.0 그대로, 세기만
#   HW_SOFT(바닥 위 L≈0.9, 포화 없음 — 처치가 드문 구간은 창마다 첫 장이 거의 전부라 '창 첫 2장 순백'으로는 줄지 않았다).
#   화면 일반 잡귀 ≥ HW_CROWD_N 이면 창 상한 HW_CROWD_CAP: 첫 장만 가산, 나머지는 일반 블렌드 α0.75·1.5배속·광원 0.5
#   (가산 기둥이 여러 장 겹치면 세기를 낮춰도 다시 순백으로 뭉친다).
#   무당 HW_NEAR_PX 안 해원은 시트 없이 재·광원 0.6 — 무당 몸을 흰 기둥이 덮지 않게.
const HW_FULL_FIRST: int = 6
const HW_SOFT: Color = Color(0.86, 0.86, 0.86, 1.0)
const HW_NORMAL: Color = Color(1.0, 1.0, 1.0, 0.75)
const HW_CROWD_N: int = 40
const HW_CROWD_CAP: int = 3
const HW_NEAR_PX: float = 40.0
var _hw_win_n: int = 0
var _hw_total: int = 0
var stat_hw_full: int = 0
var stat_hw_soft: int = 0
var stat_hw_norm: int = 0
var stat_hw_near: int = 0
var stat_hw_cut: int = 0
# 흰 무구 스파크: 한지 P 층(≤0.72) — 에셋 그대로, 색만 낮춘다
const SPARK_WHITE_MOD: Color = Color(0.82, 0.80, 0.76, 1.0)
# 숫자 군중 모드 이력(design/18 §3): 켜기 = 잡귀 ≥40 또는 숫자 ≥24 가 0.5초, 끄기 = 잡귀 <30 이고 숫자 <14 가 1초
const NC_ON_CROWD: int = 40
const NC_ON_NUMS: int = 24
const NC_ON_S: float = 0.5
const NC_OFF_CROWD: int = 30
const NC_OFF_NUMS: int = 14
const NC_OFF_S: float = 1.0
var _nc_on: bool = false
var _nc_hold: float = 0.0
var stat_nc_on_s: float = 0.0
var _kill_lights: int = 0
var _agg_n: int = 0
var _agg_x: float = 0.0
var _agg_y: float = 0.0
var _agg_tick: int = -1
# 군중 모드(숫자 소음 억제)
var _hapil_until: float = -1.0
var _boss_until: float = -1.0
# 퇴치 파열 지연(틱 6에 vfx_toechi_burst): [발동 틱, x, y, flip] 링 버퍼
const PEND_CAP: int = 256
var _pend_t: PackedInt32Array = PackedInt32Array()
var _pend_x: PackedFloat32Array = PackedFloat32Array()
var _pend_y: PackedFloat32Array = PackedFloat32Array()
var _pend_f: PackedByteArray = PackedByteArray()       # bit0-1 반전 · bit2 큰 파열(정예·치명 scale 2) · bit3 시트 없음(예산 초과)
var _pend_h: PackedInt32Array = PackedInt32Array()      # 적 핸들(넋 빠짐 경로 해시)
var _pend_head: int = 0
# 처치 연출(design/19 §5.2 I): 한지 십자·조각·넋 빠짐 층 + 다중 처치 J2(0.25초 창 ≥5, 전역 0.6초 쿨다운) + '모음' 소리
var kfx: KillFx = null
var _mk_t0: int = -1000
var _mk_n: int = 0
var _mk_last: int = -100000
var stat_multi_j2: int = 0
var _burst_delay: int = 6
# 첫 1f 가산 겹침(정예·다중 처치·치명 — design/19 §5.2 I): vfx_toechi_burst 0프레임을 가산 α0.55 로 한 번 더. 0.25초 창 4장.
const BURST_OVL_CAP: int = 4
const BURST_OVL_LIFE: float = 1.5 / 60.0
var _ovl_t0: int = -1000
var _ovl_n: int = 0
var stat_burst_ovl: int = 0
# 치명 베기 1f(vfx_gyeoldanta_cut scale 2): 전역 0.15초 간격
const CRIT_CUT_IV: int = 9
var _crit_cut_last: int = -100000
var stat_crit_cut: int = 0
# 천도 알림(design/19 §5.2 G 고침): 처음 3번만 가장자리 레인 한 줄, 2.5초 간격, 그 사이 천도는 모아 다음 알림에
const CHEONDO_LABEL_IV: float = 2.5
const CHEONDO_LABEL_N: int = 3
var _cd_label_t: float = -10.0
var _cd_shown: int = 0
var _cd_pending: int = 0
# 이펙트 군중 이력(Juice.fx_crowd, 켜기 40 0.5초 / 끄기 30 1초)
var _fxc_hold: float = 0.0
var procs: Node = null                    # vfx/passive_procs.gd(패시브 완성 발동 연출, design/19 §5.2 E)
# 가이드(처음 하는 사람이 두 결말을 읽게): 런 처음 LABEL_FIRST 번의 퇴치·해원에는 글자 표식을 띄운다. 이후는 정예 이상·고리만.
const LABEL_FIRST: int = 6
var _label_toechi: int = 0
var _label_haewon: int = 0
var _label_tick: int = -1
var _rings: int = 0
var _oreum_fx: int = -1
var _next_stats_tick: int = 0
# 군집 타격 가독성: 플레이어 주변(DENSE_R px) 적중 밀도 → 적 단색 플래시 비율(flash_keep)·스파크 상한 감쇠.
#   _dense = 최근 적중 수(실시간 반감기 DENSE_HALF_S 의 지수 감쇠 합). 단색 플래시 목표 동시 개수 FLASH_SOLID_CAP.
#   keep = clamp(DENSE_FREE / _dense, FLASH_KEEP_MIN, 1) — 최근 적중이 DENSE_FREE(≈ 0.15초에 8타)를 넘으면 그 비율만큼만 단색 플래시.
const DENSE_R: float = 96.0
const DENSE_HALF_S: float = 0.1
const DENSE_FREE: float = 8.0
const FLASH_KEEP_MIN: float = 0.25
var _dense: float = 0.0
var _flash_keep: float = 1.0
var _flash_keep_sent: float = 1.0
var _dense_tick: int = 0
var _mat_n: int = 0
var _ab_off: bool = false                   # 디버그 A/B 캡처: --crowd-fx-off 면 군집 감쇠(플래시·숫자 군집 합산·주변 상한)를 끈다
var stat_keep_min: float = 1.0
var stat_dense_max: float = 0.0


func _ready() -> void:
	Events.enemy_hit.connect(_on_hit)
	Events.enemy_killed.connect(_on_killed)
	Events.pullil_entered.connect(_on_pullil)
	Events.ring_closed.connect(_on_ring)
	Events.player_damaged.connect(_on_player_damaged)
	Events.sinmyeong_oreum.connect(_on_oreum)
	Events.yeongga_cheondo.connect(_on_cheondo)
	Events.maetim_returned.connect(_on_maetim)
	Events.run_started.connect(_on_run_started)
	Events.hapil_start.connect(_on_hapil)
	Events.boss_spawned.connect(func(_h: int, _sp: StringName, _f: StringName) -> void: _boss_until = Game.time_sec() + 3.0)
	_spark_fx = StringName(String(Data.get_value("combat_core", "feel.spark.fx", "vfx_hit_spark_red")).trim_suffix("__pilot"))
	_spark_ok = not bool(VfxLib.get_fx(_spark_fx).get("placeholder", true))   # 시트가 없으면 스파크 생략(절차적 대체 금지)
	_spark_white_ok = FileAccess.file_exists(VfxLib.VFX_ROOT + "/" + String(_spark_white_fx) + ".json") \
		and not bool(VfxLib.get_fx(_spark_white_fx).get("placeholder", true))
	_crit_kick_cd = int(roundf(Data.num("combat_core", "feel.crit_kick_cd_s", 0.4) * K.TICK_HZ))
	_ab_off = DebugTools.arg("crowd-fx-off") != ""
	_spark_cap = int(Data.num("combat_core", "feel.spark.per_frame_cap", 12))
	_spark_iv_ticks = int(roundf(Data.num("combat_core", "feel.spark.per_enemy_ms", 100) * 0.06))
	_spark_last.resize(EnemyManager.CAPACITY)
	_spark_last.fill(-100000)
	_pend_t.resize(PEND_CAP)
	_pend_t.fill(-1)
	_pend_x.resize(PEND_CAP)
	_pend_y.resize(PEND_CAP)
	_pend_f.resize(PEND_CAP)
	_pend_h.resize(PEND_CAP)
	var ts: Variant = Data.get_value("combat_core", "feel.toechi_seq_ticks", [2, 4, 3])
	if ts is Array and ts.size() >= 2:
		_burst_delay = int(ts[0]) + int(ts[1])


func _process(delta: float) -> void:
	if Game.autotest and Game.run_active and Game.game_tick >= _next_stats_tick:
		if _next_stats_tick > 0:
			print("[juice] t=%d %s" % [int(Game.time_sec()), _stats()])
		_next_stats_tick = Game.game_tick - Game.game_tick % (60 * K.TICK_HZ) + 60 * K.TICK_HZ
	if vfx == null:
		return
	if _oreum_fx >= 0:
		if Game.sinmyeong_oreum and vfx.is_playing(_oreum_fx, &"vfx_sinmyeong_oreum_aura") and Game.player != null:
			vfx.move(_oreum_fx, Game.player.global_position)
		else:
			vfx.stop(_oreum_fx)
			_oreum_fx = -1
	if kfx == null:
		kfx = KillFx.new()
		kfx.name = "KillFx"
		vfx.add_child(kfx)
	if procs == null:
		var ps: Script = load("res://vfx/passive_procs.gd") as Script
		if ps != null:
			procs = ps.new() as Node
			procs.name = "PassiveProcs"
			procs.set("vfx", vfx)
			vfx.add_child(procs)
	Juice.streak_tick()
	if _cd_pending > 0 and Game.time_sec() - _cd_label_t >= CHEONDO_LABEL_IV:
		_cheondo_label(0)
	var now: int = Game.anim_tick_cur
	var crowd: bool = Juice.number_crowd or (vfx.atmosphere != null and vfx.atmosphere.crowd_n >= HW_CROWD_N)
	for k in PEND_CAP:
		if _pend_t[k] >= 0 and now >= _pend_t[k]:
			var pf: int = int(_pend_f[k])
			var bp: Vector2 = Vector2(_pend_x[k], _pend_y[k])
			if (pf & 8) == 0:
				if (pf & 4) != 0:
					vfx.play(&"vfx_toechi_burst", bp, 0.0, 2.0, {"flip": pf & 3})   # 정예·치명: scale 2
				else:
					vfx.play_flip(&"vfx_toechi_burst", bp, pf & 3)
			# 정예·치명(bit2)·다중 처치(bit4): 첫 1f 가산 겹침 — '터졌다'를 한 장 더 세게(창 4장)
			if (pf & 20) != 0:
				if now - _ovl_t0 >= SHEET_WIN:
					_ovl_t0 = now
					_ovl_n = 0
				if _ovl_n < BURST_OVL_CAP:
					_ovl_n += 1
					stat_burst_ovl += 1
					vfx.play(&"vfx_toechi_burst", bp, 0.0, 2.0 if (pf & 4) != 0 else 1.0,
						{"flip": pf & 3, "additive": true, "life": BURST_OVL_LIFE, "modulate": Color(1, 1, 1, 0.55), "snap": false})
			kfx.burst(bp, (pf & 4) != 0, _pend_h[k], crowd)
			_pend_t[k] = -1
	_flush_light_agg()
	_update_crowd_mode(delta)
	_update_flash_keep(delta)


## 플레이어 주변 적중 밀도로 적 단색 플래시 비율을 정한다(일반 잡귀 머티리얼 유니폼 flash_keep). 정예 이상은 원래 외곽선 플래시.
func _update_flash_keep(dt: float) -> void:
	# 게임 틱 기준 감쇠(배속·히트스톱과 무관하게 '틱당 적중 밀도'를 본다)
	var gt: int = Game.game_tick
	if gt != _dense_tick:
		_dense *= pow(0.5, float(maxi(0, gt - _dense_tick)) / (DENSE_HALF_S * float(K.TICK_HZ)))
		_dense_tick = gt
	var keep: float = 1.0
	if _dense > DENSE_FREE and not _ab_off:
		keep = clampf(DENSE_FREE / _dense, FLASH_KEEP_MIN, 1.0)
	# 올릴 때는 천천히(초당 2), 내릴 때는 즉시 — 몰리는 순간 바로 덜어낸다
	_flash_keep = keep if keep < _flash_keep else move_toward(_flash_keep, keep, dt * 2.0)
	stat_keep_min = minf(stat_keep_min, _flash_keep)
	stat_dense_max = maxf(stat_dense_max, _dense)
	var em: EnemyManager = _em()
	if em == null:
		return
	if absf(_flash_keep - _flash_keep_sent) < 0.02 and not (_flash_keep == 1.0 and _flash_keep_sent != 1.0) 			and em.sp_mat.size() == _mat_n:
		return
	_flash_keep_sent = _flash_keep
	_mat_n = em.sp_mat.size()
	var nmat: int = mini(em.sp_mat.size(), em.sp_tier.size())
	for s in nmat:
		var tr: StringName = em.sp_tier[s]
		if tr == K.TIER_COMMON or tr == K.TIER_MINION:
			em.sp_mat[s].set_shader_parameter("flash_keep", _flash_keep)


func _on_run_started(_c: StringName) -> void:
	_label_toechi = 0
	_label_haewon = 0
	_label_tick = -1
	_rings = 0
	_oreum_fx = -1
	_hapil_until = -1.0
	_boss_until = -1.0
	_agg_n = 0
	_crit_kick_last = -100000
	_dense = 0.0
	_flash_keep = 1.0
	stat_keep_min = 1.0
	stat_dense_max = 0.0
	stat_sheet_skipped = 0
	_win_n = 0
	_hw_win_n = 0
	_hw_total = 0
	stat_hw_full = 0
	stat_hw_soft = 0
	stat_hw_norm = 0
	stat_hw_near = 0
	stat_hw_cut = 0
	_nc_on = false
	_nc_hold = 0.0
	stat_nc_on_s = 0.0
	_fxc_hold = 0.0
	_cd_label_t = -10.0
	_cd_pending = 0
	_cd_shown = 0
	_ovl_n = 0
	_crit_cut_last = -100000
	stat_burst_ovl = 0
	stat_crit_cut = 0


## 넘친 해원 광원을 무게중심 하나로(틱이 바뀐 뒤 한 번).
func _flush_light_agg() -> void:
	if _agg_n <= 0 or Game.game_tick == _agg_tick:
		return
	var c: Vector2 = Vector2(_agg_x / float(_agg_n), _agg_y / float(_agg_n))
	Juice.light_pulse(c + Vector2(0, -12), (2.0 + minf(2.0, float(_agg_n) * 0.25)) * K.UNIT_PX, minf(1.5, float(_agg_n)), 1, 0.7)
	_agg_n = 0
	_agg_x = 0.0
	_agg_y = 0.0


## 군중 모드: 합일(진입 후 12초)·작두거리·보스 등장 3초, 또는 (이력) 화면 일반 잡귀 ≥40·살아 있는 숫자 ≥24 가 0.5초
##   → 일반 숫자 끔(치명·정예·보스·플레이어 숫자와 합산만, 상한 16). 끄기는 잡귀 <30 이고 숫자 <14 가 1초(design/18 §3).
##   정상 런 화면 일반 잡귀는 20~46 이라 예전 문턱(120)으로는 켜지지 않았다(before_crowd 19:30 숫자 46/48).
func _update_crowd_mode(dt: float) -> void:
	var dn: DamageNumbers = Juice.damage_numbers as DamageNumbers
	if not Game.run_active:
		Juice.number_crowd = false
		Juice.fx_crowd = false
		_fxc_hold = 0.0
		_nc_on = false
		_nc_hold = 0.0
		if dn != null:
			dn.crowd_soft = false
		return
	var cn: int = 0
	if vfx != null and vfx.atmosphere != null:
		cn = vfx.atmosphere.crowd_n
	var nn: int = dn.alive_count() if dn != null else 0
	# 이펙트 군중(Juice.fx_crowd): 화면 일반 잡귀만 본다 — 켜기 ≥40 이 0.5초, 끄기 <30 이 1초
	var fflip: bool = (cn >= Juice.FX_CROWD_ON) if not Juice.fx_crowd else (cn < Juice.FX_CROWD_OFF)
	if fflip:
		_fxc_hold += dt
		if _fxc_hold >= (NC_OFF_S if Juice.fx_crowd else NC_ON_S):
			Juice.fx_crowd = not Juice.fx_crowd
			_fxc_hold = 0.0
	else:
		_fxc_hold = 0.0
	var flip: bool = (cn >= NC_ON_CROWD or nn >= NC_ON_NUMS) if not _nc_on else (cn < NC_OFF_CROWD and nn < NC_OFF_NUMS)
	if _ab_off:
		flip = _nc_on                                   # A/B: 이력 군중 모드 끔(예전 규칙만)
	if flip:
		_nc_hold += dt
		if _nc_hold >= (NC_OFF_S if _nc_on else NC_ON_S):
			_nc_on = not _nc_on
			_nc_hold = 0.0
	else:
		_nc_hold = 0.0
	var t: float = Game.time_sec()
	var crowd: bool = _nc_on or t < _hapil_until or t < _boss_until or Beat.geori_id == &"geori_jakdu" or cn >= 120
	if crowd:
		stat_nc_on_s += dt
	Juice.number_crowd = crowd
	if dn != null:
		dn.crowd_soft = cn >= NC_ON_CROWD               # 일반 숫자 α0.8(치명·정예 1.0)


func _on_hapil(_ids: Array) -> void:
	_hapil_until = Game.time_sec() + 12.0
	Juice.hide_numbers(1.5)                     # 강림 1.5초: 숫자 전부 숨김(신령 강림 연출 집중)


func _em() -> EnemyManager:
	return Game.enemies as EnemyManager


func _body_h(handle: int) -> int:
	var em: EnemyManager = _em()
	if em == null:
		return 24
	return em.body_h_of(handle & EnemyManager.SLOT_MASK)


func _on_hit(h: int, _sp: StringName, pos: Vector2, dmg: float, color: int, crit: bool, locked: bool) -> void:
	var kind: StringName = &"red"
	if locked:
		kind = &"locked"
	elif crit:
		kind = &"crit"
	elif color == K.DmgColor.WHITE:
		kind = &"white"
	var bh: int = _body_h(h)
	var np: Vector2 = pos + Vector2(0, -bh - 4)
	# 근접전: 숫자가 플레이어 몸 박스(발 기준 ±14 × −48..0)와 겹치면 위로 8px(부채·손 가림 방지, 리뷰 render#9)
	var pl: Player = Game.player as Player
	if pl != null:
		var pd: Vector2 = pos - pl.render_pos
		if absf(pd.x) <= DENSE_R and absf(pd.y) <= DENSE_R:
			_dense += 1.0
		var rel: Vector2 = np - pl.render_pos
		if absf(rel.x) <= 14.0 + 6.0 and rel.y >= -48.0 - 6.0 and rel.y <= 2.0:
			np.y -= 8.0
			# 8px 로도 몸 박스 안이면 맞은 적 쪽으로 박스 밖까지 옆으로 민다
			if np.y - pl.render_pos.y >= -48.0 - 6.0:
				var side: float = signf(pos.x - pl.render_pos.x)
				if side == 0.0:
					side = 1.0
				np.x = pl.render_pos.x + side * (14.0 + 8.0)
	var em: EnemyManager = _em()
	var slot: int = h & EnemyManager.SLOT_MASK
	var important: bool = em != null and slot < em.flags.size() and (em.flags[slot] & EnemyManager.F_ELITE_PLUS) != 0
	Juice.damage_number(np, dmg, kind, h, important)
	var away: Vector2 = Vector2.ZERO
	if Game.player != null:
		away = pos - Game.player.global_position
	if crit and Game.game_tick - _crit_kick_last >= _crit_kick_cd:
		_crit_kick_last = Game.game_tick
		Juice.kick(away, 1)                       # 치명타: 공격 방향 1px 킥(트라우마 0), 0.4초 쿨다운(P6)
	# 타격 스파크(16px 4f): 발 + (0, −몸/2) + 맞은 면 3px. 프레임당 12개, 같은 적 100ms 1개
	if _spark_ok and vfx != null:
		var now: int = Game.game_tick
		if now != _spark_tick:
			_spark_tick = now
			_spark_n = 0
		# 군집: 스파크 상한도 플래시 비율만큼 덜어낸다(치명은 상한 밖 — 결단타는 늘 튄다)
		var scap: int = maxi(3, int(roundf(float(_spark_cap) * _flash_keep)))
		if (_spark_n < scap or (crit and _spark_n < _spark_cap)) and slot < _spark_last.size() and now - _spark_last[slot] >= _spark_iv_ticks:
			_spark_n += 1
			_spark_last[slot] = now
			var face: Vector2 = -K.dir8(away) * 3.0
			var spos: Vector2 = pos + Vector2(0, -roundf(bh * 0.5)) + face
			if color == K.DmgColor.WHITE and _spark_white_ok:
				# 흰 무구 스파크는 한지 톤(P ≤0.72) — 순백은 해원 빛기둥 몫(design/18 §1.1)
				vfx.play_ex(_spark_white_fx, spos, Rng.int_s(&"fx", 0, 3), -1, SPARK_WHITE_MOD)
			else:
				vfx.play_flip(_spark_fx, spos, Rng.int_s(&"fx", 0, 3))
			# 치명: 타격 지점에 결단 베기 1f scale 2(design/19 §5.2 I) — 전역 0.15초 간격(군중 상시 번쩍임 방지)
			if crit and now - _crit_cut_last >= CRIT_CUT_IV:
				_crit_cut_last = now
				stat_crit_cut += 1
				vfx.play(&"vfx_gyeoldanta_cut", spos, 0.0, 2.0, {"flip": (slot & 3), "life": 2.0 / 60.0, "snap": false})


func _on_killed(_h: int, _sp: StringName, pos: Vector2, kind: StringName, cause: StringName, tier: StringName) -> void:
	var elite: bool = tier != K.TIER_COMMON and tier != K.TIER_MINION
	if cause != &"debug":
		Juice.note_kill(kind == K.KIND_HAEWON)
	var away: Vector2 = Vector2.ZERO
	if Game.player != null:
		away = pos - Game.player.global_position
	var atmo: Atmosphere = vfx.atmosphere if vfx != null else null
	var bh: int = 24
	if Game.game_tick != _kill_tick:
		_kill_tick = Game.game_tick
		_kill_n = 0
		_kill_sheets = 0
		_kill_lights = 0
	_kill_n += 1
	if Game.game_tick - _win_t0 >= SHEET_WIN:
		_win_t0 = Game.game_tick
		_win_n = 0
		_hw_win_n = 0
	var sheet_ok: bool = (_kill_sheets < KILL_SHEET_CAP and (_win_n < SHEET_WIN_CAP or _ab_off)) or elite
	if sheet_ok:
		_kill_sheets += 1
		_win_n += 1
	else:
		stat_sheet_skipped += 1
	if kind == K.KIND_HAEWON:
		# 빛기둥 층 결정(design/18 §1.5). 창 예산(sheet_ok)·퇴치 파열 순서는 그대로 — 해원만 세기·블렌드·상한을 고른다.
		_hw_total += 1
		var light: float = 1.0
		var ash: int = 6 if elite else (3 if sheet_ok else 1)   # 창 예산을 넘긴 무리 해원은 재 1점만(백 뭉침 방지)
		var near_pl: bool = false
		var pl: Player = Game.player as Player
		if pl != null:
			# 빛기둥(16×48, 위로 선다)이 무당 몸 상자(±16, −40~+4)에 걸리면 정예라도 시트 없이 — 몸 상자 안 순백 0(design/19 §5.1)
			var fp0: Vector2 = pl.render_pos
			var col_r: Rect2 = Rect2(pos.x - 8.0, pos.y - 48.0, 16.0, 56.0)
			near_pl = col_r.intersects(Rect2(fp0.x - 16.0, fp0.y - 40.0, 32.0, 44.0)) or (not elite and pos.distance_squared_to(fp0) < HW_NEAR_PX * HW_NEAR_PX)
		if vfx != null and sheet_ok:
			var crowd40: bool = atmo != null and atmo.crowd_n >= HW_CROWD_N and not _ab_off
			if near_pl:
				light = 0.6                               # 무당 곁: 시트 없이 재·광원만(무당 몸을 흰 기둥이 덮지 않게)
				ash = 3
				stat_hw_near += 1
			elif (elite and not (cause == &"ring" and crowd40)) or _hw_total <= HW_FULL_FIRST:
				# (군중 속 고리 해원은 정예도 순백 기둥 예외 없이 창 예산을 따른다 — 고리 하나에 흰 기둥이 무더기로 서지 않게, design/19 §5.2 G)
				_hw_win_n += 1
				stat_hw_full += 1
				vfx.play_flip(&"vfx_haewon_rise", pos, 0, 1)                     # 순백 — 해원 순간
			elif not crowd40 or _hw_win_n < 1:
				# 무리(≥40): 창 첫 장만 가산 — 가산 기둥 여러 장이 겹치면 다시 순백으로 뭉친다(after 19:30 확인)
				_hw_win_n += 1
				stat_hw_soft += 1
				vfx.play_ex(&"vfx_haewon_rise", pos, 0, 1, HW_SOFT)               # 가산 그대로, 포화 없이
			elif _hw_win_n < HW_CROWD_CAP:
				_hw_win_n += 1
				stat_hw_norm += 1
				light = 0.5
				vfx.play_ex(&"vfx_haewon_rise", pos, 0, 0, HW_NORMAL, 1.5)        # 무리: 일반 블렌드 α0.75, 짧게
			else:
				light = 0.5                               # 무리 창 상한 초과: 재·광원 묶음만
				ash = 1
				stat_hw_cut += 1
		elif not sheet_ok and atmo != null and atmo.crowd_n >= HW_CROWD_N:
			light = 0.5
		# 해원 빛기둥 광원(design/08 §4.1: 2u, 1.0 → 0, 0.6s, 백) + 한지 재. 틱당 4개, 넘치면 무게중심 하나로 묶는다
		if _kill_lights < KILL_LIGHT_CAP or elite:
			_kill_lights += 1
			Juice.light_pulse(pos + Vector2(0, -12), 2.0 * K.UNIT_PX, light, 1, 0.6)
		else:
			_agg_n += 1
			_agg_x += pos.x
			_agg_y += pos.y
			_agg_tick = Game.game_tick
		if atmo != null:
			atmo.burst(pos, true, ash)
	else:
		# 퇴치 파열은 적 스프라이트의 번쩍(hj 2 → jk 4틱) 뒤 틱 6에(GAME_FEEL 4.4). 4변형 반전, 회전 없음
		# 시트 예산을 넘긴 처치도 십자·넋 빠짐은 KillFx 자기 예산(군중 4/3)으로 낸다(bit3 = 시트 없음)
		var big: bool = elite or cause == &"gyeoldan"
		var multi: bool = _multi_kill(away, pos)
		_pend_t[_pend_head] = Game.game_tick + _burst_delay
		_pend_x[_pend_head] = pos.x
		_pend_y[_pend_head] = pos.y
		_pend_f[_pend_head] = (Rng.int_s(&"fx", 0, 3) if sheet_ok else 0) | (4 if big else 0) | (0 if sheet_ok else 8) | (16 if multi else 0)
		_pend_h[_pend_head] = _h
		_pend_head = (_pend_head + 1) % PEND_CAP
		if atmo != null:
			atmo.burst(pos, false, 4 if elite else (2 if sheet_ok else 1))
		if cause == &"gyeoldan" and vfx != null:
			vfx.play_flip(&"vfx_gyeoldanta_cut", pos + Vector2(0, -12), Rng.int_s(&"fx", 0, 3))
	# 글자 표식: 처음 몇 번 + 정예 이상(같은 틱에는 하나만 — 무리 처치 때 글자가 쌓이지 않게)
	# 글자 표식 간격 0.5초(30틱): 시련·정예 무리 해원 때 흰 글자가 영가 행렬 위에 쌓이지 않게(리드 11-24, ui 요청)
	if _label_tick < 0 or Game.game_tick - _label_tick >= 30:
		var lp: Vector2 = pos + Vector2(0, -float(bh) - 14.0)
		if kind == K.KIND_HAEWON and (_label_haewon <= LABEL_FIRST or elite):
			_label_haewon += 1
			_label_tick = Game.game_tick
			if _label_haewon > 1 or elite:          # 첫 해원은 ui/guide 가 '解冤 해원' 이름표를 단다(겹침 방지)
				Juice.label(lp, UiKit.word("haewon"), &"haewon")
		elif kind != K.KIND_HAEWON and (_label_toechi < LABEL_FIRST or elite):
			_label_toechi += 1
			_label_tick = Game.game_tick
			Juice.label(lp, UiKit.word("toechi"), &"toechi")
	# 같은 틱 퇴치·해원 8 이상 → 킥 1px + 트라우마 0.2 (1회) — 시트 대신 '한 방'으로 판다(묶음 라벨은 haewon 배너)
	if _kill_n == 8:
		Juice.feedback_event("kill_burst", away)
	if tier == K.TIER_BOSS:
		Juice.feedback_event("boss_result", away)
	elif tier == K.TIER_MBOSS:
		Juice.feedback_event("mboss_result", away)
	elif elite:
		Juice.feedback_event("elite_result", away)


## 다중 처치(design/19 §5.0 J2): 0.25초 창에 처치 5 이상 → 16ms + 킥 1px(전역 0.6초 쿨다운) + '모음' 소리 1번.
## 반환: 이 처치가 다중 처치 창(5번째 이상)에 들었는가(파열 첫 1f 가산 겹침). 5번째에 Events.kill_burst(5, pos).
func _multi_kill(away: Vector2, pos: Vector2) -> bool:
	var t: int = Game.game_tick
	if t - _mk_t0 >= 15:
		_mk_t0 = t
		_mk_n = 0
	_mk_n += 1
	if _mk_n == 5:
		Events.kill_burst.emit(_mk_n, pos)
	if _mk_n == 5 and t - _mk_last >= 36 and WeaponBase.new_hitstop_on():
		_mk_last = t
		stat_multi_j2 += 1
		Juice.hitstop(16, 2)
		Juice.kick(away, 1)
		var d: int = Audio.def_of(&"sfx_sys_hanpa")
		if d >= 0:
			Audio.play_def(d, 2.0, 1.1225)          # +2반음 +2dB
	return _mk_n >= 5


func _on_pullil(h: int, _sp: StringName, pos: Vector2) -> void:
	if vfx != null:
		vfx.play_flip(&"vfx_pullil_enter", pos + Vector2(0, -_body_h(h) - 2), 0, 1)


func _on_ring(area: int, haewon_count: int, c: Vector2) -> void:
	var base: float = Data.num("combat_core", "ring.trauma_base", 0.25)
	var per: float = Data.num("combat_core", "ring.trauma_per_area", 0.0025)
	var tr: float = minf(base + per * area, Data.num("combat_core", "ring.trauma_cap", 0.5))
	# 길닦음: 히트스톱·트라우마·백 플래시(해원이 있었을 때만 — 백은 해원 전용)
	# J3(design/19 §5.0): 큰 고리(넓이 ≥40) 또는 한꺼번에 15 이상 풀림
	var key: String = "gildakkeum_large" if (area >= 40 or haewon_count >= 15) else "gildakkeum"
	if haewon_count > 0:
		Juice.feedback_event(key, Vector2.ZERO, tr)
		# 고리 빛(light_pulse)은 haewon/ring_closure 가 낸다(중복 금지)
		_rings += 1
		# 첫 고리는 ui/guide 가 '길닦음' 이름표, 3명 이상·만다라 고리는 haewon 붓 배너('길닦음 ×N')가 센다 — 작은 고리만 여기서
		if _rings > 1 and haewon_count < 3 and area < int(Data.num("combat_core", "ring.mandala_area", 60)):
			# 붓 슬램(추임새 '잘한다' 등)이 떠 있으면 생략 — 화면 위쪽에서 두 큰 글자가 겹쳐 '해원 ×잘한다' 로 읽혔다(리뷰 11-24 t1000_midboss 10:25)
			var hs: Node = null
			if Game.run_root != null:
				hs = Game.run_root.get("haewon") as Node
			var free: bool = not (hs != null and hs.has_method("banner_active") and bool(hs.call("banner_active")))
			# 가운데 슬롯(design/18 §2.2): 다른 큰 글이 떠 있으면 버린다. 비어 있으면 가장 낮은 우선순위(0)로 잠깐 차지
			if free and Juice.has_method(&"center_busy") and bool(Juice.call(&"center_busy", 0)):
				free = false
			if free and Juice.has_method(&"claim_center"):
				free = bool(Juice.call(&"claim_center", &"hf_ring_label", 0, 1.0))
			if free:
				# 한 명은 '×1' 없이 — '해원 ×1' 은 셈이 아니라 군더더기
				Juice.label(c + Vector2(0, -28), UiKit.word("haewon") if haewon_count == 1 else "한꺼번에 풀림 ×%d" % haewon_count, &"ring")
	else:
		# 빈 고리(해원 0): 히트스톱·트라우마 없이 킥 1px 만 — 성공 고리의 정지가 '해원 성공' 신호로 남고 T2 예산도 아낀다.
		# 실패감은 audio(빈 고리 음)·ui 가 전한다.
		Juice.kick(Vector2(0, 1), 1)


func _on_player_damaged(amount: float, _src: StringName, _hp: float, hp_max: float) -> void:
	Juice.reset_streak()                        # 연속 처치는 피격에 끊긴다(칩이 수천으로 쌓여 뜻을 잃지 않게)
	var p: Player = Game.player as Player
	if p != null:
		Juice.damage_number(p.global_position + Vector2(0, -p.cam_lift * 2 - 4), amount, &"player", -1, true)
	var big: bool = amount >= hp_max * Data.num("combat_core", "player.hit_hitstop_threshold", 0.1)
	var tr: Variant = Data.get_value("combat_core", "player.hit_trauma", [0.3, 0.45])
	var trv: float = -1.0
	if tr is Array and tr.size() >= 2:
		trv = float(tr[1]) if big else float(tr[0])
	# 킥 2px: 피격 반대 방향(가장 가까운 적 → 플레이어)
	var d: Vector2 = Vector2(0, 1)
	var em: EnemyManager = _em()
	if p != null and em != null:
		var i: int = em.nearest(p.global_position, 2.0 * K.UNIT_PX)
		if i >= 0:
			d = p.global_position - em.pos_of(i)
	Juice.feedback_event("player_hit_big" if big else "player_hit", d, trv)


func _on_oreum(active: bool) -> void:
	if active:
		Juice.feedback_event("sinmyeong_oreum_start")
		if vfx != null and Game.player != null and _oreum_fx < 0:
			_oreum_fx = vfx.play(&"vfx_sinmyeong_oreum_aura", Game.player.global_position, 0.0, 1.0, {"life": 60.0})


## 매듭 복귀(맺힘): 매듭이 다시 묶이는 시트.
func _on_maetim(_h: int, _sp: StringName, pos: Vector2) -> void:
	if vfx != null:
		vfx.play_flip(&"vfx_maetim_knot", pos + Vector2(0, -_body_h(_h) - 2), 0)


## 천도(영가가 떠나감): 행렬 자리에 백 빛 + 한지 재.
func _on_cheondo(count: int, _reason: StringName) -> void:
	var p: Node2D = Game.player
	if p == null or count <= 0:
		return
	Juice.light_pulse(p.global_position + Vector2(0, -20), 3.0 * K.UNIT_PX, 0.8, 1, 0.8)
	if vfx != null and vfx.atmosphere != null:
		vfx.atmosphere.burst(p.global_position, true, mini(12, 3 + count))
	_cheondo_label(count)


## 천도 알림: 처음 CHEONDO_LABEL_N 번만 가장자리 레인(화면 좌표, 왼쪽 위)에 주어를 붙여 한 줄 — 그 뒤로는 글 없이 빛·재만.
## (예전 '+N 떠남' 월드 글은 주어가 없고 '+' 가 이득처럼 읽혔으며, 월드 자리에 남아 무당 갓을 덮었다 — 검토 11-26)
func _cheondo_label(count: int) -> void:
	_cd_pending += count
	if _cd_shown >= CHEONDO_LABEL_N:
		_cd_pending = 0
		return
	var t: float = Game.time_sec()
	if _cd_pending <= 0 or t - _cd_label_t < CHEONDO_LABEL_IV:
		return
	var hud: Object = Game.run_root.get("hud") if Game.run_root != null else null
	if hud != null and hud.has_method(&"push_edge"):
		hud.call(&"push_edge", "넋 동무 %d명이 저승길로 떠났어요" % _cd_pending, false)
	_cd_shown += 1
	_cd_label_t = t
	_cd_pending = 0


func _stats() -> String:
	var s: String = Juice.stats_line()
	s += " | crowd_hit dense_max=%.1f flash_keep_min=%.2f sheet_skipped=%d" % [stat_dense_max, stat_keep_min, stat_sheet_skipped]
	s += " | haewon n=%d full=%d soft=%d norm=%d near=%d cut=%d num_crowd_s=%.1f" % [
		_hw_total, stat_hw_full, stat_hw_soft, stat_hw_norm, stat_hw_near, stat_hw_cut, stat_nc_on_s]
	s += " | kill multi_j2=%d ovl=%d crit_cut=%d" % [stat_multi_j2, stat_burst_ovl, stat_crit_cut]
	if kfx != null:
		s += " bursts=%d souls=%d cut=%d absorbed=%d" % [kfx.stat_bursts, kfx.stat_souls, kfx.stat_cut, kfx.stat_soul_absorbed]
	if procs != null and procs.has_method("stats_line"):
		s += " | " + String(procs.call("stats_line"))
	var dn: Node = Juice.damage_numbers
	if dn != null and dn.has_method("stats_line"):
		s += " | " + String(dn.call("stats_line"))
	if vfx != null:
		s += " | vfx played=%d recycled=%d snapped=%d active=%d" % [vfx.stat_played, vfx.stat_recycled, vfx.stat_snapped, vfx.active_count]
		if vfx.atmosphere != null:
			s += " | atmo motes_max=%d prop_lights_max=%d crowd_n=%d" % [vfx.atmosphere.stat_max_motes, vfx.atmosphere.stat_lights_max, vfx.atmosphere.crowd_n]
	return s


func _exit_tree() -> void:
	if Game.autotest:
		print("[juice] end %s" % _stats())
