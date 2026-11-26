class_name EnemyManager
extends Node2D
## 적 저장소(SoA) + 공간 해시 + MultiMesh 군중 렌더 + 일반 잡귀 아키타입 AI 12종 + 피해 해석(퇴치/해원·풀릴 기색·매듭 잠금).
## 소유: enemies. 정예·중간보스·보스·저승사자·손님 NPC 는 enemy_bigs.gd(자식 노드 Bigs), 예고·장판은 enemy_hazards.gd(자식 Hazards).
##
## 개체는 노드가 아니다. 슬롯 인덱스 + 세대(gen)로 핸들을 만든다: handle = slot | (gen << 12).
## 외부 모듈은 핸들/슬롯과 아래 공개 API 만 쓴다. 배열을 직접 쓰는 것은 읽기만 허용(px/py/han/flags 등).
##
## 공개 API
##   spawn(species_id, pos, opts={}) -> int(handle | -1)
##       opts: han_ratio, han_mult, no_recycle, wongwi(원귀: 원래 종 그대로 + scaling.wongwi), elite_plus, no_variant,
##             intro_s(등장 솟음 초, 기본 0.4), route(저승사자: &"bow"|&"sal_geodum"|&"forced"), parent(소환 부모 핸들)
##   queue_hit(slot, dmg, color:K.DmgColor, crit, kb_dir, kb_u, source_slot) -> void   (이번 틱 일괄 해석)
##   resolve_hits() -> void                       틱 13~14단계(run.gd 가 호출). 정렬 키: 백 → 적.
##   query_circle(pos, r, out, max_out) -> int     out(PackedInt32Array)에 슬롯 채움. 할당 없음. 통과·숨김 개체 제외.
##   nearest(pos, max_r, exclude_mask) -> int      가장 가까운 슬롯(-1)
##   force_haewon(slot, cause) / force_toechi(slot, cause)   고리·사자 등 외부 확정 처리
##   is_alive(slot), handle_of(slot), slot_of(handle), species_id_of(slot), pos_of(slot), tier_of(slot)
##   is_hostile(slot, ranged := false) -> bool   접촉·원거리 공격 가능 여부(D-20)
##   n_ratio() -> float                          넋 비율 N(가중 해원 / 가중 결말, 07 8.0.1). 보스 형태·저승사자 경로
##   boss_form_of(slot) -> StringName             &"sal" | &"han" | &""
##   top_toechi_species(k) -> StringName           이번 런 퇴치 상위 k번째 일반 잡귀(없으면 달걀귀신)
##   toechi_count_of(species) / haewon_count_of(species)
##
## 풀릴 기색·맺힘 등급 분기(캐논 v1.2 D-20/C-09/D-22, 07 enemies.json global_rules 정본):
##   일반·하위 변형: 이동 ×0.4(배회), 접촉 ×0.3, 원거리·돌진·장판·버프·분열·착 정지(진행 중 예고 취소),
##     복귀 시 한 45% + 3초 비적대(접촉·원거리 없음, 이동 ×0.7). 맺힘 시계 = 실시간.
##   정예 이상: 이동 ×0.7, 접촉 유지, 공격 유지(예고 +0.2초, bigs), 복귀 시 한 60%. 맺힘 시계 = 최근 1초 피해 없을 때만 흐름.
##
## 피해 해석은 design/14 §3.6.2 resolveHit 를 옮겼다. 규칙 변경은 haewon 담당과 합의 후.

const BigsScript: GDScript = preload("res://enemies/enemy_bigs.gd")
const HazScript: GDScript = preload("res://enemies/enemy_hazards.gd")

const CAPACITY: int = 2560
const CELL_PX: float = 64.0          # 2u
const HASH_SIZE: int = 4096
const HASH_MASK: int = 4095
const HIT_CAP: int = 8192
const GEN_SHIFT: int = 12
const SLOT_MASK: int = 4095

# --- 상태 비트 ---
const F_ALIVE: int = 1
const F_PULLIL: int = 2
const F_ELITE_PLUS: int = 4
const F_PULLIL_SECOND: int = 8
const F_WONGWI: int = 16
const F_FEAR: int = 32
const F_DYING: int = 64
const F_PENDING_HAEWON: int = 128
const F_FLYING: int = 256
const F_WHITE_FLASH: int = 512
const F_NO_RECYCLE: int = 1024
const F_INVULN: int = 2048
const F_AUTO_TARGET_EXEMPT: int = 4096
const F_TOECHI_BURST: int = 8192
const F_GRACE: int = 16384            # 맺힘 복귀 직후 비적대(일반·하위 변형만, D-20)
const F_PASS: int = 32768             # 투사체·질의 통과(저승사자·손님 NPC·이동 중 숨김)
const F_NONHOSTILE: int = 65536       # 접촉 피해 없음(저승사자·손님·홀린 영가)
const F_CARRY: int = 131072           # 아귀: 공물을 품음
const F_HIDDEN: int = 262144          # 렌더·접촉·질의 제외(순간이동·비행 통과 중)
const F_CHILD: int = 524288           # 달걀귀신(아이): 퇴치 = 먹빛 흩어짐
const F_SCREEN: int = 1048576         # 호식 원혼 엄폐 중: 적 무구 피해 −30%
const F_NO_PULLIL: int = 2097152      # 한 문턱으로 풀릴 기색에 들지 않음(보스 한형: 고풀이 창이 직접 제어)
const F_VANISH: int = 4194304         # 조용히 사라지는 중(분열·삼킴·이탈): 짧은 디졸브, 상승 없음

# --- 아키타입(07 4.3) ---
enum Arc { CHASE, GREED, ATTACH, RANGED, CHARGER, ZONER, SCREEN, FLOAT, LURCH, PROCESSION, SWARM, ORBIT, BIG }
# --- 이동 모드 ---
enum Mv { SEEK, HOLD, VEL, POINT, ORBIT, FLEE, ATTACH, STRAFE, WANDER, DRIFT }
# --- 아키타입 공통 상태 ---
const S_BASE: int = 0
const S_SEEK2: int = 1
const S_WIND: int = 2
const S_ACT: int = 3
const S_REC: int = 4
const S_HOLD: int = 5

# --- SoA ---
var px: PackedFloat32Array
var py: PackedFloat32Array
var vx: PackedFloat32Array
var vy: PackedFloat32Array
var kbx: PackedFloat32Array
var kby: PackedFloat32Array
var han: PackedFloat32Array
var han_max: PackedFloat32Array
var radius: PackedFloat32Array
var speed: PackedFloat32Array
var mass: PackedFloat32Array
var contact: PackedFloat32Array
var contact_cd: PackedFloat32Array
var pullil_t: PackedFloat32Array
var grace_t: PackedFloat32Array
var flash: PackedFloat32Array
var dying_t: PackedFloat32Array
var species: PackedInt32Array
var flags: PackedInt32Array
var gen: PackedInt32Array
var facing: PackedByteArray
# --- AI(아키타입 상태기계) ---
var ai_s: PackedByteArray            # 상태
var ai_m: PackedByteArray            # 이동 모드(Mv)
var ai_t: PackedFloat32Array         # 상태 타이머(초, 0 이하 = 없음)
var ai_cd: PackedFloat32Array        # 행동 쿨다운(초)
var ai_x: PackedFloat32Array         # 목표점 / 조준점
var ai_y: PackedFloat32Array
var ai_vx: PackedFloat32Array        # 고정 속도(돌진) / 행렬 방향
var ai_vy: PackedFloat32Array
var ai_sp: PackedFloat32Array        # 이번 모드 속도(px/s)
var ai_dir: PackedFloat32Array       # 옆걸음·맴돌기 방향(±1) / 노이즈 위상
var ai_link: PackedInt32Array        # 연결 핸들(숙주·우두머리·엄폐·부모)
var ai_tg: PackedInt32Array          # 진행 중 예고 슬롯(-1)
var smult: PackedFloat32Array        # 속도 배율(착 버프·포만·광폭)
var cmult: PackedFloat32Array        # 접촉 배율(돌진 ×2 등)
var dtaken: PackedFloat32Array       # 받는 피해 배율(경직 틈 ×1.5 등, bigs 가 씀)
var spawn_tick: PackedInt32Array     # 등장 틱(솟음 연출·등장 0.4초 접촉 없음)
var intro_ticks: PackedInt32Array    # 등장 솟음 길이(틱)
var last_dmg_tick: PackedInt32Array  # 마지막 피해 틱(정예 맺힘 시계)
var zoim: PackedByteArray            # 매듭 잠금 누적(조임 단계: 1 / 3 / 6)
var host_n: PackedByteArray          # 붙은 객귀 수
var rscale: PackedByteArray          # 정수 렌더 배율(어둑시니 1~3), 0 = 1
var pose_dy: PackedInt32Array        # bigs 자세 오프셋(절: 엎드림 등) — 스쿼시 dy 에 더함
var big: Array = []                  # 슬롯 → bigs 제어 객체(일반 잡귀 null)
# --- 연출·넉백 상태(GAME_FEEL 4장). 렌더 전용 값과 넉백 거리 모델·국소 정지(시뮬, 결정론) ---
var ppx: PackedFloat32Array            # 보간용 직전 틱 좌표
var ppy: PackedFloat32Array
var aph: PackedFloat32Array            # 애니 위상 0..1(스폰 시 무작위)
var arate: PackedFloat32Array          # 개체별 fps 지터 ×0.9~1.1
var kb_s: PackedFloat32Array           # 넉백 진행 s(t) 0..1 (kbx/kby = 총 변위 px)
var kb_used: PackedFloat32Array        # 0.5초 창 넉백 누적 px
var hit_tick: PackedInt32Array         # 마지막 피격 스쿼시 시작 틱
var flash_tick: PackedInt32Array       # 마지막 플래시 시작 틱(최소 간격 12틱)
var nudge_tick: PackedInt32Array       # 넉백 0 타격 렌더 넛지 시작 틱
var freeze_until: PackedInt32Array     # 국소 정지: game_tick < 이 값이면 이동·애니 정지
var stagger_until: PackedInt32Array    # 넉백 후 스태거(목표 속도 0)
var kb_t: PackedInt32Array             # 넉백 경과 틱(-1 없음)
var kb_last: PackedInt32Array          # 마지막 넉백 틱(dr_window)
var kb_win_t: PackedInt32Array         # 넉백 예산 창 시작 틱
var die_tick: PackedInt32Array         # 퇴치/해원 확정 틱
var nudge_d: PackedByteArray           # 넛지 방향(8방향 인덱스)
var hit_w: PackedByteArray             # 마지막 타격 무게 등급(0 경 / 1 중 / 2 중량) — 스쿼시·넛지 길이
var dir_hold: PackedByteArray          # 방향 최소 유지 남은 틱
var cell_x: PackedInt32Array
var cell_y: PackedInt32Array
var next_in_cell: PackedInt32Array
var hash_head: PackedInt32Array

var active: PackedInt32Array
var active_pos: PackedInt32Array
var active_count: int = 0
var free_list: PackedInt32Array
var free_count: int = 0

# --- 종 테이블 ---
var sp_ids: Array[StringName] = []
var sp_index: Dictionary = {}
var sp_def: Array[Dictionary] = []
var sp_tier: Array[StringName] = []
var sp_arch: PackedInt32Array = PackedInt32Array()
var sp_mm: Array[MultiMeshInstance2D] = []          # 플레이어 발 y 이하(뒤) — z 0(일반)/1(정예+)
var sp_mm_front: Array[MultiMeshInstance2D] = []    # 플레이어 발 y 보다 아래(앞) — z 3 (플레이어 2 위)
var sp_count_front: PackedInt32Array = PackedInt32Array()
# y-sort(R4): 발 y 정수 counting sort 버퍼(할당 없음)
const YSORT_RANGE: int = 4096
var _ys_key: PackedInt32Array = PackedInt32Array()
var _ys_order: PackedInt32Array = PackedInt32Array()
var _ys_cnt: PackedInt32Array = PackedInt32Array()
var sp_count: PackedInt32Array = PackedInt32Array()
var sp_alive: PackedInt32Array = PackedInt32Array()
var sp_toechi: PackedInt32Array = PackedInt32Array()
var sp_haewon: PackedInt32Array = PackedInt32Array()
var sp_mat: Array[ShaderMaterial] = []
var sp_cols: PackedInt32Array = PackedInt32Array()
var sp_fps: PackedFloat32Array = PackedFloat32Array()
var sp_body_h: PackedInt32Array = PackedInt32Array()
var sp_shadow: Array[Vector2i] = []
var sp_cap: Array[Vector2i] = []        # 스쿼시 상한 (dy, dx_s)
var sp_massf: PackedFloat32Array = PackedFloat32Array()
var _shadow_mm: MultiMeshInstance2D
var _shadow_shader: Shader

# --- 히트 큐 ---
var hq_slot: PackedInt32Array
var hq_gen: PackedInt32Array
var hq_dmg: PackedFloat32Array
var hq_color: PackedByteArray
var hq_crit: PackedByteArray
var hq_kbx: PackedFloat32Array        # 타격 방향(단위 벡터)
var hq_kby: PackedFloat32Array
var hq_kb: PackedFloat32Array         # 넉백 거리 px(kb_u × 32)
var hq_src: PackedInt32Array
var hq_count: int = 0

# --- 하위 시스템 ---
var bigs: Node = null
var hazards: Node2D = null
var _overlay: Node2D = null
var _bar_buf: PackedFloat32Array = PackedFloat32Array()

# --- 결말 집계(넋 비율 N, 07 8.0.1) ---
var w_toechi: float = 0.0
var w_haewon: float = 0.0
var _sal_alg: float = 0.0             # 원귀 회귀용 살 알갱이 근사(퇴치 가중, 상한 200)
var _w_tier: Dictionary = {"common": 1.0, "minion": 1.0, "elite": 5.0, "elite_system": 5.0, "mboss": 20.0}

# --- 파라미터(데이터) ---
var _t_a: float = 0.12
var _t_b: float = 0.006
var _c_c: float = 0.06
var _e_e: float = 0.25
var _e_m0: float = 6.0
var _s_k: float = 0.002
var _v_v: float = 0.0075
var _v_cap: float = 1.15
var _speed_cap_common: float = 3.6 * 32.0
var _speed_cap_wongwi: float = 3.8 * 32.0
var _giseak_dur: float = 12.0
var _giseak_dur_repeat: float = 8.0
var _giseak_move: float = 0.7             # 정예 이상
var _giseak_move_common: float = 0.4      # 일반·하위 변형(배회)
var _giseak_contact_common: float = 0.3   # 일반·하위 변형. 정예 이상은 접촉 유지(×1.0)
var _maetim_ratio: float = 0.6            # 정예 이상
var _maetim_ratio_common: float = 0.45    # 일반·하위 변형
var _maetim_grace: float = 3.0            # 일반·하위 변형 복귀 직후 비적대(초)
var _maetim_grace_move: float = 0.7       # 비적대 동안 이동 배율
var _contact_cd_default: float = 0.5
var _recycle_px: float = 22.0 * 32.0
var _player_hit_r: float = 0.3 * 32.0
var _shader: Shader
var _scratch: PackedInt32Array = PackedInt32Array()
var _scratch2: PackedInt32Array = PackedInt32Array()
var _child_share: float = 0.08
var _wongwi: Dictionary = {}
var _tele_common: float = 0.5
# --- 아키타입 수치(enemies.json archetypes, 07 4.3) ---
var _g_seek_r: float = 320.0
var _g_speed: float = 108.8
var _g_eat: float = 1.0
var _g_sated: float = 6.0
var _g_sated_sp: float = 44.8
var _g_heal: float = 0.3
var _a_wander: float = 51.2
var _a_wobble: float = 0.698
var _a_period: float = 2.0
var _a_host_r: float = 192.0
var _a_seek: float = 96.0
var _a_off: float = 12.8
var _a_buff_spd: float = 0.25
var _a_buff_dmg: float = 0.2
var _a_stun: float = 0.5
var _r_band0: float = 160.0
var _r_band1: float = 224.0
var _r_retreat: float = 51.2
var _r_strafe: float = 38.4
var _r_flip: float = 3.0
var _r_lead: float = 0.5
var _r_fire_cd: float = 3.2
var _r_prj_spd: float = 96.0
var _r_prj_life: float = 3.0
var _r_prj_r: float = 5.76
var _r_prj_dmg: float = 7.0
var _c_trig: float = 192.0
var _c_cd: float = 4.0
var _c_wind: float = 0.6
var _c_dash: float = 288.0
var _c_dtime: float = 0.55
var _c_rec: float = 1.2
var _c_tw: float = 22.4
var _c_tl: float = 160.0
var _z_cd: float = 6.0
var _z_max: int = 4
var _z_r: float = 38.4
var _z_dur: float = 10.0
var _s_search: float = 160.0
var _s_off: float = 38.4
var _s_reeval: float = 2.0
var _s_break: float = 64.0
var _s_red: float = 0.3
var _f_noise: float = 1.047
var _f_hz: float = 0.8
var _f_split_t: float = 10.0
var _f_split_n: int = 3
var _f_tele: float = 0.4
var _f_small_life: float = 20.0
var _l_cd: float = 4.0
var _l_trig: float = 256.0
var _l_freeze: float = 0.4
var _l_dist: float = 64.0
var _l_speed: float = 192.0
var _p_break: float = 192.0
var _p_offset: float = 96.0
var _w_rush: float = 128.0
var _w_center: float = 70.4
var _o_appr: float = 96.0
var _o_r: float = 80.0
var _o_flip: float = 6.0
var _o_aura: float = 96.0
var _gawi_rate: float = 1.0
var _gawi_trigger: float = 3.0
var _gawi_slow: float = 0.4
var _gawi_dur: float = 1.5
var _gawi_immune: float = 3.0
var _gawi_stack: float = 0.0
var _gawi_cd: float = 0.0
var _mul_hand_slow: float = 0.4
# --- 연출 수치(combat_core.feel / knockback / hitstop) ---
var _kb_apply_ticks: float = 7.0
var _kb_recover_ticks: int = 3
var _kb_giseak: float = 0.5
var _kb_dr_window: int = 18
var _kb_dr_mult: float = 0.5
var _kb_cap_px: float = 96.0
var _kb_mass: Dictionary = {}
var _freeze_frames: int = 1          # combat_core hitstop.local_freeze_frames (r3: 2 → 1, 넉백이 빨리 시작)
# 넉백 발밑 먼지(렌더 전용, et 램프 2~3px, 정수 좌표) 링 버퍼
const SEP_CELL: float = 20.0          # 겹침 방지 촘촘한 해시 칸(작은 몸 rs ≈ (11+11)×0.9)
const SEP_HASH: int = 2048
const SEP_MASK: int = 2047
const SEP_SMALL_R: float = 16.0       # 이보다 큰 반경은 큰 몸 목록
const SEP_BIG_CAP: int = 64
const SEP_VISIT_CAP: int = 16         # 한 개체가 살펴보는 이웃 상한(같은 점에 몰린 최악 경우)
var _sep_head: PackedInt32Array = PackedInt32Array()
var _sep_next: PackedInt32Array = PackedInt32Array()
var _sep_cx: PackedInt32Array = PackedInt32Array()
var _sep_cy: PackedInt32Array = PackedInt32Array()
var _sep_big: PackedInt32Array = PackedInt32Array()
const DUST_CAP: int = 96
const DUST_TICKS: int = 10
var _dust_x: PackedFloat32Array = PackedFloat32Array()
var _dust_y: PackedFloat32Array = PackedFloat32Array()
var _dust_dx: PackedFloat32Array = PackedFloat32Array()
var _dust_dy: PackedFloat32Array = PackedFloat32Array()
var _dust_t: PackedInt32Array = PackedInt32Array()
var _dust_head: int = 0
var _dust_node: Node2D
var _freeze_ratio: float = 0.25
var _flash_ticks: int = 2
var _flash_min_iv: int = 12
var _toechi_seq: PackedInt32Array = PackedInt32Array([2, 4, 3])
var _haewon_rise_every: int = 6
var _anim_fps: float = 8.0
var _ratio_min: float = 0.8
var _ratio_max: float = 1.6
var _still_v: float = 4.0
var _dir_hold_ticks: int = 15
var _nudge_ticks: int = 2
# 무구 무게 등급(combat_core feel.weight_tiers): 국소 정지·스쿼시·넛지·찌르기 넉백
var _w_of: Dictionary = {}               # 무구 id(StringName) → 0 경 / 1 중 / 2 중량
var _w_thrust: Dictionary = {}           # 찌르기·관통 계열(kb 없으면 thrust_kb_u)
var _w_default: int = 1
var _w_freeze: PackedInt32Array = PackedInt32Array([1, 2, 3])
var _w_squash: PackedInt32Array = PackedInt32Array([2, 3, 4])
var _w_nudge_px: PackedInt32Array = PackedInt32Array([1, 2, 2])
var _w_nudge_t: PackedInt32Array = PackedInt32Array([2, 3, 3])
var _w_heavy_always: bool = true
var _w_thrust_kb_px: float = 9.6
var _flash_big_iv: int = 30              # 정예·중간보스·보스: 재플래시 최소 간격(5Hz 스트로브 방지)
var _flash_big_ratio: float = 0.01       # 큰 몸 플래시 문턱(한 최대치 비율) — 치명·중량 타격은 무조건
var _crowd_unhide_n: int = 0             # 이 수 이상이면 무당 몸 위 앞줄 잡귀를 뒤로 보낸다(design/18 §1.4: 늘 — 0)
var _crowd_base: float = 0.88            # 무리 층 상시 명도 배율(art_palette crowd_dim.base, design/18 §1.2)
var _crowd_base_sent: float = -1.0
var _crowd_base_n: int = -1              # 공급한 머티리얼 수(새 종이 생기면 다시 보낸다)
var sp_no_n: PackedByteArray = PackedByteArray()   # 종별 북(N) 행 없음 → 북향 이동 때 E/W 행으로(얼굴 보이며 뒷걸음 방지)
const HAEWON_TICKS: int = 33           # dying_t 0.55s
const HAEWON_TICKS_ELITE: int = 54     # 정예 이상 0.9s(몸이 커서 상승을 길게)
const DIR8: Array[Vector2] = [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1)]
# 스프라이트 별칭(종 ID → 에셋 폴더). 데이터 ID 와 아트 폴더 이름이 다른 것.
const SPRITE_ALIAS: Dictionary = {
	"mboss_daegwi__sogwi": "enm_subi__sogwi",
	"npc_byeolsang_sonnim": "elite_byeolsang_sonnim",
	"boss_yeokryeo__form_sal": "boss_yeokryeo",
	"boss_yeokryeo__form_han": "boss_yeokryeo",
	"elite_eodukssini__small": "elite_eodukssini",
	"boss_wongyeol__gohon": "enm_dalgyal_gwisin",
	"mboss_dokkaebi__heosang": "mboss_dokkaebi",
}
const PRELOAD_SPECIES: Array[StringName] = [
	&"enm_dalgyal_gwisin", &"enm_agwi", &"enm_gaekgwi", &"enm_cheonyeo_gwisin", &"enm_mongdal_gwisin", &"enm_mul_gwisin",
	&"enm_hosik_wonhon", &"enm_dokkaebi_bul", &"enm_yeongsan", &"enm_sangmun", &"enm_subi", &"enm_hwehwe_gwisin",
	&"enm_dokkaebi_bul__small", &"enm_dalgyal_gwisin__child", &"mboss_daegwi__sogwi", &"mboss_dokkaebi__heosang",
	&"elite_eodukssini", &"elite_eodukssini__small", &"elite_geogu_gwi", &"elite_bulgasari", &"elite_dueoksini", &"elite_yeokgwi_ttae",
	&"mboss_daegwi", &"mboss_dokkaebi", &"mboss_gumiho", &"mboss_gangcheori", &"boss_yeokryeo", &"chaser_jeoseung_saja", &"npc_byeolsang_sonnim",
]
# --- 계측(--autotest): 2분마다 [enemies] 한 줄 ---
var _perf_think_us: int = 0
var _perf_resolve_us: int = 0
var _perf_contact_us: int = 0
var _perf_hash_us: int = 0
var _perf_n: int = 0
var _perf_next_tick: int = 0


func _ready() -> void:
	_alloc()
	_dust_x.resize(DUST_CAP); _dust_y.resize(DUST_CAP); _dust_dx.resize(DUST_CAP); _dust_dy.resize(DUST_CAP)
	_dust_t.resize(DUST_CAP); _dust_t.fill(-100000)
	_dust_node = Node2D.new()
	_dust_node.name = "KbDust"
	_dust_node.z_index = -1
	_dust_node.draw.connect(_draw_dust)
	add_child(_dust_node)
	_shader = load("res://enemies/enemy_crowd.gdshader") as Shader
	_shadow_shader = load("res://shaders/enemy_shadow.gdshader") as Shader
	_load_params()
	_make_shadow_mm()
	hazards = HazScript.new() as Node2D
	hazards.name = "Hazards"
	hazards.set("em", self)
	add_child(hazards)
	bigs = BigsScript.new() as Node
	bigs.name = "Bigs"
	bigs.set("em", self)
	add_child(bigs)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.z_index = 8                     # 적 체력바·예고 테두리 = 위험 층(design/18 §1.3, 내 VFX z5 위)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_bar_buf.resize(4 * 64)
	Events.wongwi_return.connect(_on_wongwi_return)
	# 첫 등장 끊김 방지: v1 에 나오는 종은 런 시작 때 아틀라스·MultiMesh 를 미리 만든다(정예·보스 시트가 크다)
	for sid: StringName in PRELOAD_SPECIES:
		_species(sid)


func _alloc() -> void:
	for arr_name: String in ["px", "py", "vx", "vy", "kbx", "kby", "han", "han_max", "radius", "speed", "mass", "contact", "contact_cd", "pullil_t", "grace_t", "flash", "dying_t", "ppx", "ppy", "aph", "arate", "kb_s", "kb_used",
			"ai_t", "ai_cd", "ai_x", "ai_y", "ai_vx", "ai_vy", "ai_sp", "ai_dir", "smult", "cmult", "dtaken"]:
		var a: PackedFloat32Array = PackedFloat32Array()
		a.resize(CAPACITY)
		set(arr_name, a)
	for arr_name: String in ["species", "flags", "gen", "cell_x", "cell_y", "next_in_cell", "active", "active_pos", "free_list", "hit_tick", "flash_tick", "nudge_tick", "freeze_until", "stagger_until", "kb_t", "kb_last", "kb_win_t", "die_tick",
			"ai_link", "ai_tg", "spawn_tick", "intro_ticks", "last_dmg_tick", "pose_dy"]:
		var b: PackedInt32Array = PackedInt32Array()
		b.resize(CAPACITY)
		set(arr_name, b)
	for arr_name: String in ["facing", "nudge_d", "hit_w", "dir_hold", "ai_s", "ai_m", "zoim", "host_n", "rscale"]:
		var c: PackedByteArray = PackedByteArray()
		c.resize(CAPACITY)
		set(arr_name, c)
	big.resize(CAPACITY)
	kb_t.fill(-1)
	ai_tg.fill(-1)
	ai_link.fill(-1)
	hash_head.resize(HASH_SIZE)
	hash_head.fill(-1)
	active_pos.fill(-1)
	free_count = CAPACITY
	for i in CAPACITY:
		free_list[i] = CAPACITY - 1 - i
	hq_slot.resize(HIT_CAP)
	hq_gen.resize(HIT_CAP)
	hq_dmg.resize(HIT_CAP)
	hq_color.resize(HIT_CAP)
	hq_crit.resize(HIT_CAP)
	hq_kbx.resize(HIT_CAP)
	hq_kby.resize(HIT_CAP)
	hq_kb.resize(HIT_CAP)
	hq_src.resize(HIT_CAP)
	_scratch.resize(256)
	_scratch2.resize(64)


func _load_params() -> void:
	_t_a = Data.num("enemies", "scaling.T_han.a", 0.12)
	_t_b = Data.num("enemies", "scaling.T_han.b", 0.006)
	_c_c = Data.num("enemies", "scaling.C_damage.c", 0.06)
	_e_e = Data.num("enemies", "scaling.E_elite.e", 0.25)
	_e_m0 = Data.num("enemies", "scaling.E_elite.m0", 6.0)
	_s_k = Data.num("enemies", "scaling.S_salgi.k", 0.002)
	_v_v = Data.num("enemies", "scaling.V_speed.v", 0.0075)
	_v_cap = Data.num("enemies", "scaling.V_speed.cap", 1.15)
	_speed_cap_common = Data.num("enemies", "scaling.V_speed.common_speed_cap_u", 3.6) * K.UNIT_PX
	_speed_cap_wongwi = Data.num("enemies", "scaling.V_speed.wongwi_speed_cap_u", 3.8) * K.UNIT_PX
	var wg: Variant = Data.get_value("enemies", "scaling.wongwi", {})
	_wongwi = wg if wg is Dictionary else {}
	_giseak_dur = Data.num("combat_core", "han.giseak_duration", 12.0)
	_giseak_dur_repeat = Data.num("combat_core", "han.giseak_duration_repeat", 8.0)
	_giseak_move = Data.num("combat_core", "han.giseak_move_mult", 0.7)
	_maetim_ratio = Data.num("combat_core", "han.maetim_return_ratio", 0.6)
	_giseak_move_common = Data.num("combat_core", "han.giseak_general_move_mult", 0.4)
	_giseak_contact_common = Data.num("combat_core", "han.giseak_general_contact_mult", 0.3)
	_maetim_ratio_common = Data.num("combat_core", "han.maetim_return_ratio_common", 0.45)
	_maetim_grace = Data.num("combat_core", "han.maetim_return_grace", 3.0)
	_maetim_grace_move = Data.num("combat_core", "han.maetim_return_grace_rules.move_mult", 0.7)
	_contact_cd_default = Data.num("enemies", "global_rules.contact_cd_s_default", 0.5)
	_recycle_px = Data.num("waves_stage1", "director.recycle_radius", 22.0) * K.UNIT_PX
	_player_hit_r = Data.num("enemies", "global_rules.player_hitbox_u", 0.3) * K.UNIT_PX
	_tele_common = Data.num("enemies", "global_rules.telegraph_min_s.common", 0.5)
	_child_share = Data.num("enemies", "minions.6.spawn_share", 0.08)
	var wt: Variant = Data.get_value("enemies", "boss_common.form_rule.N_assumption.weights", null)
	if wt is Dictionary:
		_w_tier = wt
	_kb_apply_ticks = maxf(1.0, Data.num("combat_core", "knockback.apply_time", 0.12) * K.TICK_HZ)
	_kb_recover_ticks = int(roundf(Data.num("combat_core", "knockback.recover_time", 0.05) * K.TICK_HZ))
	_kb_giseak = Data.num("combat_core", "knockback.giseak_factor", 0.5)
	_kb_dr_window = int(roundf(Data.num("combat_core", "knockback.dr_window", 0.3) * K.TICK_HZ))
	_kb_dr_mult = Data.num("combat_core", "knockback.dr_mult", 0.5)
	_kb_cap_px = Data.num("combat_core", "knockback.max_disp_per_half_sec_u", 3.0) * K.UNIT_PX
	var mf: Variant = Data.get_value("combat_core", "knockback.mass_factor", {})
	_kb_mass = mf if mf is Dictionary else {}
	_freeze_frames = int(Data.num("combat_core", "hitstop.local_freeze_frames", 2))
	_freeze_ratio = Data.num("combat_core", "hitstop.local_freeze_dmg_ratio", 0.25)
	_flash_ticks = int(Data.num("combat_core", "feel.enemy_flash.ticks", 2))
	_crowd_base = clampf(Data.num("art_palette", "crowd_dim.base", 0.88), 0.5, 1.0)
	_flash_min_iv = int(Data.num("combat_core", "feel.enemy_flash.min_interval_ticks", 12))
	var ts: Variant = Data.get_value("combat_core", "feel.toechi_seq_ticks", null)
	if ts is Array and ts.size() >= 3:
		_toechi_seq = PackedInt32Array([int(ts[0]), int(ts[1]), int(ts[2])])
	_haewon_rise_every = maxi(1, int(Data.num("combat_core", "feel.haewon_rise_every_ticks", 6)))
	_anim_fps = Data.num("combat_core", "feel.enemy.fps", 8.0)
	_ratio_min = Data.num("combat_core", "feel.enemy.ratio_min", 0.8)
	_ratio_max = Data.num("combat_core", "feel.enemy.ratio_max", 1.6)
	_still_v = Data.num("combat_core", "feel.enemy.still_v", 4.0)
	_dir_hold_ticks = int(roundf(Data.num("combat_core", "feel.enemy.dir_min_hold_s", 0.25) * K.TICK_HZ))
	_nudge_ticks = int(Data.num("combat_core", "feel.nudge.ticks", 2))
	_flash_big_iv = int(Data.num("combat_core", "feel.enemy_flash.big_min_interval_ticks", 30))
	_flash_big_ratio = Data.num("combat_core", "feel.enemy_flash.big_dmg_ratio", 0.01)
	_w_default = clampi(int(Data.num("combat_core", "feel.weight_tiers.default", 1)), 0, 2)
	_w_heavy_always = bool(Data.get_value("combat_core", "feel.weight_tiers.heavy_always_freeze", true))
	_w_thrust_kb_px = Data.num("combat_core", "feel.weight_tiers.thrust_kb_u", 0.3) * K.UNIT_PX
	for key: String in ["freeze_ticks", "squash_ticks", "nudge_px", "nudge_ticks"]:
		var arr: Variant = Data.get_value("combat_core", "feel.weight_tiers." + key, null)
		if arr is Array and (arr as Array).size() >= 3:
			var pk: PackedInt32Array = PackedInt32Array([int(arr[0]), int(arr[1]), int(arr[2])])
			match key:
				"freeze_ticks":
					_w_freeze = pk
				"squash_ticks":
					_w_squash = pk
				"nudge_px":
					_w_nudge_px = pk
				"nudge_ticks":
					_w_nudge_t = pk
	for pair: Array in [["light", 0], ["heavy", 2], ["thrust", 1]]:
		var ids: Variant = Data.get_value("combat_core", "feel.weight_tiers." + String(pair[0]), null)
		if ids is Array:
			for wid: Variant in ids:
				_w_of[StringName(String(wid))] = int(pair[1])
				if String(pair[0]) == "thrust":
					_w_thrust[StringName(String(wid))] = true
	# 아키타입(07 4.3)
	var U: float = K.UNIT_PX
	_g_seek_r = Data.num("enemies", "archetypes.arc_greed.seek_radius_u", 10.0) * U
	_g_speed = Data.num("enemies", "archetypes.arc_greed.greed_speed_u", 3.4) * U
	_g_eat = Data.num("enemies", "archetypes.arc_greed.eat_s", 1.0)
	_g_sated = Data.num("enemies", "archetypes.arc_greed.sated_s", 6.0)
	_g_sated_sp = Data.num("enemies", "archetypes.arc_greed.sated_speed_u", 1.4) * U
	_g_heal = Data.num("enemies", "archetypes.arc_greed.sated_heal_pct", 30.0) / 100.0
	_a_wander = Data.num("enemies", "archetypes.arc_attach.wander_speed_u", 1.6) * U
	_a_wobble = deg_to_rad(Data.num("enemies", "archetypes.arc_attach.wander_wobble_deg", 40.0))
	_a_period = Data.num("enemies", "archetypes.arc_attach.wobble_period_s", 2.0)
	_a_host_r = Data.num("enemies", "archetypes.arc_attach.host_radius_u", 6.0) * U
	_a_seek = Data.num("enemies", "archetypes.arc_attach.seek_speed_u", 3.0) * U
	_a_off = Data.num("enemies", "archetypes.arc_attach.attach_offset_u", 0.4) * U
	_a_buff_spd = Data.num("enemies", "archetypes.arc_attach.buff_speed_pct", 25.0) / 100.0
	_a_buff_dmg = Data.num("enemies", "archetypes.arc_attach.buff_dmg_pct", 20.0) / 100.0
	_a_stun = Data.num("enemies", "archetypes.arc_attach.detach_stun_s", 0.5)
	var band: Variant = Data.get_value("enemies", "archetypes.arc_ranged.band_u", [5, 7])
	if band is Array and band.size() >= 2:
		_r_band0 = float(band[0]) * U
		_r_band1 = float(band[1]) * U
	_r_retreat = Data.num("enemies", "archetypes.arc_ranged.retreat_speed_u", 1.6) * U
	_r_strafe = Data.num("enemies", "archetypes.arc_ranged.strafe_speed_u", 1.2) * U
	_r_flip = Data.num("enemies", "archetypes.arc_ranged.strafe_flip_s", 3.0)
	_r_lead = Data.num("enemies", "archetypes.arc_ranged.lead_s", 0.5)
	_r_fire_cd = Data.num("enemies", "archetypes.arc_ranged.fire_cd_s", 3.2)
	_r_prj_spd = Data.num("enemies", "projectiles.prj_wonhon_tan.speed_u", 3.0) * U
	_r_prj_life = Data.num("enemies", "projectiles.prj_wonhon_tan.life_s", 3.0)
	_r_prj_r = Data.num("enemies", "projectiles.prj_wonhon_tan.radius_u", 0.18) * U
	_c_trig = Data.num("enemies", "archetypes.arc_charger.trigger_dist_u", 6.0) * U
	_c_cd = Data.num("enemies", "archetypes.arc_charger.cooldown_s", 4.0)
	_c_wind = maxf(_tele_common, Data.num("enemies", "archetypes.arc_charger.windup_s", 0.6))
	_c_dash = Data.num("enemies", "archetypes.arc_charger.dash_speed_u", 9.0) * U
	_c_dtime = Data.num("enemies", "archetypes.arc_charger.dash_time_s", 0.55)
	_c_rec = Data.num("enemies", "archetypes.arc_charger.recover_s", 1.2)
	_c_tw = Data.num("enemies", "archetypes.arc_charger.telegraph_width_u", 0.7) * U
	_c_tl = Data.num("enemies", "archetypes.arc_charger.telegraph_len_u", 5.0) * U
	_z_cd = Data.num("enemies", "archetypes.arc_zoner.zone_cd_s", 6.0)
	_z_max = int(Data.num("enemies", "archetypes.arc_zoner.zone_max_per_entity", 4))
	_z_r = Data.num("enemies", "zones.obj_mul_ungdeongi.radius_u", 1.2) * U
	_z_dur = Data.num("enemies", "zones.obj_mul_ungdeongi.duration_s", 10.0)
	_s_search = Data.num("enemies", "archetypes.arc_screen.cover_search_u", 5.0) * U
	_s_off = Data.num("enemies", "archetypes.arc_screen.cover_offset_u", 1.2) * U
	_s_reeval = Data.num("enemies", "archetypes.arc_screen.reeval_s", 2.0)
	_s_break = Data.num("enemies", "archetypes.arc_screen.break_dist_u", 2.0) * U
	_s_red = Data.num("enemies", "archetypes.arc_screen.cover_projectile_reduction_pct", 30.0) / 100.0
	_f_noise = deg_to_rad(Data.num("enemies", "archetypes.arc_float.noise_deg", 60.0))
	_f_hz = Data.num("enemies", "archetypes.arc_float.noise_hz", 0.8)
	_f_split_t = Data.num("enemies", "archetypes.arc_float.split_time_s", 10.0)
	_f_split_n = int(Data.num("enemies", "archetypes.arc_float.split_count", 3))
	_f_tele = maxf(_tele_common, Data.num("enemies", "archetypes.arc_float.split_telegraph_s", 0.4))
	_l_cd = Data.num("enemies", "archetypes.arc_lurch.lurch_cd_s", 4.0)
	_l_trig = Data.num("enemies", "archetypes.arc_lurch.trigger_dist_u", 8.0) * U
	_l_freeze = maxf(_tele_common, Data.num("enemies", "archetypes.arc_lurch.freeze_s", 0.4))
	_l_dist = Data.num("enemies", "archetypes.arc_lurch.lunge_dist_u", 2.0) * U
	_l_speed = Data.num("enemies", "archetypes.arc_lurch.lunge_speed_u", 6.0) * U
	_p_break = Data.num("enemies", "archetypes.arc_procession.break_dist_u", 6.0) * U
	_p_offset = Data.num("enemies", "archetypes.arc_procession.path_pass_offset_u", 3.0) * U
	_w_rush = Data.num("enemies", "archetypes.arc_swarm.rush_dist_u", 4.0) * U
	_w_center = Data.num("enemies", "archetypes.arc_swarm.center_speed_u", 2.2) * U
	_o_appr = Data.num("enemies", "archetypes.arc_orbit.approach_dist_u", 3.0) * U
	_o_r = Data.num("enemies", "archetypes.arc_orbit.orbit_radius_u", 2.5) * U
	_o_flip = Data.num("enemies", "archetypes.arc_orbit.orbit_flip_s", 6.0)
	_o_aura = 3.0 * U
	_gawi_rate = Data.num("enemies", "statuses_on_player.st_gawi.stack_rate_per_s_per_enemy", 1.0)
	_gawi_trigger = Data.num("enemies", "statuses_on_player.st_gawi.trigger_stacks", 3.0)
	_gawi_slow = Data.num("enemies", "statuses_on_player.st_gawi.slow_pct", 40.0) / 100.0
	_gawi_dur = Data.num("enemies", "statuses_on_player.st_gawi.duration_s", 1.5)
	_gawi_immune = Data.num("enemies", "statuses_on_player.st_gawi.post_immunity_s", 3.0)
	_mul_hand_slow = Data.num("enemies", "statuses_on_player.st_mulgwisin_son.slow_pct", 40.0) / 100.0


func _make_shadow_mm() -> void:
	_shadow_mm = MultiMeshInstance2D.new()
	_shadow_mm.name = "MM_shadow"
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _shadow_shader
	mat.set_shader_parameter("quad", Vector2(64, 12))
	_shadow_mm.material = mat
	_shadow_mm.modulate = Color(1, 1, 1, Data.num("combat_core", "feel.shadow.alpha", 0.45))
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _quad_rect(Vector2(-32, -6), Vector2(64, 12))
	mm.instance_count = 256
	mm.visible_instance_count = 0
	_shadow_mm.multimesh = mm
	_shadow_mm.z_as_relative = false
	_shadow_mm.z_index = -1                    # 지면(-10) 위, 적(0) 아래
	add_child(_shadow_mm)


# ─── 핸들 ──────────────────────────────────────────────────────────────

func handle_of(slot: int) -> int:
	return slot | (gen[slot] << GEN_SHIFT)


func slot_of(handle: int) -> int:
	if handle < 0:
		return -1
	var s: int = handle & SLOT_MASK
	if s >= CAPACITY or (handle >> GEN_SHIFT) != gen[s] or (flags[s] & F_ALIVE) == 0:
		return -1
	return s


func is_alive(slot: int) -> bool:
	return slot >= 0 and slot < CAPACITY and (flags[slot] & F_ALIVE) != 0 and (flags[slot] & F_DYING) == 0


## 접촉·원거리 공격 가능 여부(D-20). 비적대: 맺힘 복귀 직후 3초(일반·하위 변형), 저승사자·손님 NPC,
## 풀릴 기색 중인 일반·하위 변형의 원거리(07 giseak.common_default_disable 에 ranged 포함 — 접촉은 ×0.3 으로 남는다).
func is_hostile(slot: int, ranged: bool = false) -> bool:
	if not is_alive(slot):
		return false
	var f: int = flags[slot]
	if (f & (F_GRACE | F_NONHOSTILE | F_HIDDEN)) != 0:
		return false
	if ranged and (f & F_PULLIL) != 0 and (f & F_ELITE_PLUS) == 0:
		return false
	return true


func pos_of(slot: int) -> Vector2:
	return Vector2(px[slot], py[slot])


func species_id_of(slot: int) -> StringName:
	return sp_ids[species[slot]]


func tier_of(slot: int) -> StringName:
	if (flags[slot] & F_WONGWI) != 0:
		return K.TIER_ELITE          # 원귀(elite_system): 정예 결말 규칙(07 6.6)
	return sp_tier[species[slot]]


func alive_count_of(species_id: StringName) -> int:
	var s: int = sp_index.get(species_id, -1)
	return sp_alive[s] if s >= 0 else 0


func toechi_count_of(species_id: StringName) -> int:
	var s: int = sp_index.get(species_id, -1)
	return sp_toechi[s] if s >= 0 else 0


func haewon_count_of(species_id: StringName) -> int:
	var s: int = sp_index.get(species_id, -1)
	return sp_haewon[s] if s >= 0 else 0


## 넋 비율 N = 가중 해원 / (가중 해원 + 가중 퇴치). 결말이 없으면 0.5(07 8.0.1).
func n_ratio() -> float:
	var tot: float = w_toechi + w_haewon
	return w_haewon / tot if tot > 0.0 else 0.5


func boss_form_of(slot: int) -> StringName:
	if bigs != null and slot >= 0 and slot < CAPACITY:
		return bigs.call("form_of", slot)
	return &""


## 이번 런 퇴치 상위 k번째(0..) 일반 잡귀 종. 아이 변형·하위 변형 제외. 없으면 달걀귀신(어른).
## 공개(ui guide·HUD): 한형 보스 매듭 위치를 out 에 채운다(out 크기 = 최대 개수, 3이면 충분). 반환 개수. 매 프레임 호출 가능(할당 없음).
func boss_knots(out: PackedVector2Array) -> int:
	return int(bigs.call("knot_positions", out)) if bigs != null else 0


## 공개(ui HUD _draw_boss): x = 1 묶임 / 0 열림 / −1 한형 보스 없음, y = 열림 창 남은 초, z = 남은 구간 수(0..7).
func boss_gopuri() -> Vector3:
	return bigs.call("gopuri_state") as Vector3 if bigs != null else Vector3(-1.0, 0.0, 0.0)


func top_toechi_species(k: int) -> StringName:
	var used: PackedInt32Array = PackedInt32Array()
	var pick: int = -1
	for r in k + 1:
		pick = -1
		var best: int = 0
		for s in sp_ids.size():
			if sp_tier[s] != K.TIER_COMMON or used.has(s) or String(sp_ids[s]).ends_with("__child"):
				continue
			if sp_toechi[s] > best:
				best = sp_toechi[s]
				pick = s
		if pick < 0:
			break
		used.append(pick)
	if pick < 0:
		return sp_ids[used[0]] if used.size() > 0 else &"enm_dalgyal_gwisin"   # 모자라면 상위 1종 반복
	return sp_ids[pick]


# ─── 종 등록 ───────────────────────────────────────────────────────────

func _species(id: StringName) -> int:
	if sp_index.has(id):
		return sp_index[id]
	var def: Dictionary = Data.enemy(String(id))
	var idx: int = sp_ids.size()
	sp_ids.append(id)
	sp_def.append(def)
	sp_index[id] = idx
	var tier: String = String(def.get("tier", ""))
	var sid: String = String(id)
	if tier == "" or tier == "elite_system" or tier == "deity_guest" or tier == "boss_part":
		if sid.begins_with("boss_"):
			tier = "boss" if not sid.contains("__") else "minion"
		elif sid.begins_with("mboss_"):
			tier = "mboss" if not sid.contains("__") else "minion"
		elif sid.begins_with("elite_"):
			tier = "elite"
		elif sid.begins_with("chaser_") or sid.begins_with("npc_"):
			tier = "chaser"
		elif tier == "":
			tier = "common"
	sp_tier.append(StringName(tier))
	sp_count.append(0)
	sp_alive.append(0)
	sp_toechi.append(0)
	sp_haewon.append(0)
	sp_arch.append(_arch_code(def, tier))
	var cpx: Variant = def.get("canvas_px", 32)
	var canvas: int = int(cpx[0]) if cpx is Array else (int(cpx) if (cpx is float or cpx is int) else 32)
	var art_id: String = String(SPRITE_ALIAS.get(sid, sid))
	# [S,E,N × 프레임] 2D 아틀라스(파일럿 우선). 정지 단독 PNG 는 애니가 하나도 없을 때만.
	var atlas: Dictionary = SpriteLib.anim_atlas(art_id, PackedStringArray(["move", "walk", "glide", "float", "idle"]), canvas)
	var cell: Vector2i = atlas["cell"]
	var piv: Vector2i = atlas["pivot"]
	var used_anim: String = String(atlas.get("anim", ""))
	sp_no_n.append(1 if used_anim != "" and SpriteLib.anim_frames_any(art_id, used_anim, "north").is_empty() else 0)
	var mmi: MultiMeshInstance2D = MultiMeshInstance2D.new()
	mmi.name = "MM_" + sid
	mmi.texture = atlas["texture"]
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("cols", float(atlas["cols"]))
	mat.set_shader_parameter("cell_size", Vector2(cell))
	mat.set_shader_parameter("pivot", Vector2(piv))
	mat.set_shader_parameter("hinge_y", float(atlas["hinge_y"]))
	mmi.material = mat
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _quad_rect(Vector2(-piv.x, -piv.y), Vector2(cell))   # 발 피벗 quad(GAME_FEEL 4.1)
	mm.instance_count = 64
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	var elite_tier: bool = tier in ["elite", "mboss", "boss", "chaser"]
	mmi.z_index = 1 if elite_tier else 0
	add_child(mmi)
	sp_mm.append(mmi)
	# 앞쪽 MultiMesh(같은 텍스처·재질·메시, z 3): 플레이어보다 발이 아래인 적은 로브 위에 그린다(리뷰 render#5)
	var mmf: MultiMeshInstance2D = MultiMeshInstance2D.new()
	mmf.name = "MMF_" + sid
	mmf.texture = mmi.texture
	mmf.material = mat
	var mm2: MultiMesh = MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_2D
	mm2.use_custom_data = true
	mm2.mesh = mm.mesh
	mm2.instance_count = 64
	mm2.visible_instance_count = 0
	mmf.multimesh = mm2
	mmf.z_index = 3
	add_child(mmf)
	sp_mm_front.append(mmf)
	sp_count_front.append(0)
	sp_mat.append(mat)
	sp_cols.append(int(atlas["cols"]))
	sp_fps.append(_numf(def.get("anim_fps", null), _anim_fps))
	var bh: int = int(atlas["body_h"])
	sp_body_h.append(bh)
	var ch: int = (atlas["canvas"] as Vector2i).y
	var sh: Vector2i
	if elite_tier or ch > 48:
		sh = Vector2i(clampi(int(K.rnd(float(int(atlas["body_w"])) * 0.6 * 0.5)) * 2, 8, 62), 6)
	elif ch <= 32:
		sh = Vector2i(12, 3)
	elif ch <= 40:
		sh = Vector2i(14, 4)
	else:
		sh = Vector2i(18, 4)
	sp_shadow.append(sh)
	match tier:
		"elite":
			sp_cap.append(Vector2i(3, 2))
		"mboss", "boss", "chaser":
			sp_cap.append(Vector2i(4, 2))
		_:
			sp_cap.append(Vector2i(2, 1))
	var mkey: String = "general"
	if tier == "elite":
		mkey = "elite"
	elif tier == "mboss":
		mkey = "mboss"
	elif tier == "boss" or tier == "chaser":
		mkey = "boss"
	var mdef: float = 1.0
	match mkey:
		"elite":
			mdef = 0.25
		"mboss":
			mdef = 0.1
		"boss":
			mdef = 0.0
	var mfv: float = _numf(_kb_mass.get(mkey, null), mdef)
	var ms: Variant = def.get("mass", 1.0)
	if ms is String and String(ms) == "inf":
		mfv = 0.0
	sp_massf.append(mfv)
	return idx


func _arch_code(def: Dictionary, tier: String) -> int:
	if tier != "common" and tier != "minion":
		return Arc.BIG
	match String(def.get("archetype", "arc_chase")):
		"arc_greed":
			return Arc.GREED
		"arc_attach":
			return Arc.ATTACH
		"arc_ranged":
			return Arc.RANGED
		"arc_charger":
			return Arc.CHARGER
		"arc_zoner":
			return Arc.ZONER
		"arc_screen":
			return Arc.SCREEN
		"arc_float":
			return Arc.FLOAT
		"arc_lurch":
			return Arc.LURCH
		"arc_procession":
			return Arc.PROCESSION
		"arc_swarm":
			return Arc.SWARM
		"arc_orbit":
			return Arc.ORBIT
	if String(def.get("id", "")) == "enm_dokkaebi_bul__small":
		return Arc.FLOAT
	return Arc.CHASE


func _quad_rect(origin: Vector2, size: Vector2) -> ArrayMesh:
	var verts: PackedVector2Array = [origin, origin + Vector2(size.x, 0), origin + size, origin + Vector2(0, size.y)]
	var uvs: PackedVector2Array = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var idx: PackedInt32Array = [0, 1, 2, 0, 2, 3]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])  # 없으면 COLOR 가 검정(모듈레이트 무효)
	arrays[Mesh.ARRAY_INDEX] = idx
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _numf(v: Variant, default: float) -> float:
	if v is float or v is int:
		return float(v)
	if v is Array and v.size() > 0 and (v[0] is float or v[0] is int):
		return float(v[0])
	return default


# ─── 스폰/제거 ─────────────────────────────────────────────────────────

func spawn(species_id: StringName, pos: Vector2, opts: Dictionary = {}) -> int:
	if free_count <= 0:
		return -1
	var sid0: StringName = species_id
	# 아이 얼굴 변형(07 5.1): 달걀귀신 스폰의 8%(상한 10%)를 대체
	if sid0 == &"enm_dalgyal_gwisin" and not bool(opts.get("no_variant", false)) and not bool(opts.get("wongwi", false)) \
			and Rng.chance(&"spawn", clampf(_child_share, 0.0, 0.1)):
		sid0 = &"enm_dalgyal_gwisin__child"
	var s: int = _species(sid0)
	var def: Dictionary = sp_def[s]
	free_count -= 1
	var i: int = free_list[free_count]
	active[active_count] = i
	active_pos[i] = active_count
	active_count += 1
	var tier: StringName = sp_tier[s]
	var m: float = Game.time_sec() / 60.0
	var wongwi: bool = bool(opts.get("wongwi", false))
	var s_mult: float = 1.0 + _s_k * Game.salgi
	var t_mult: float = 1.0
	var base_han: float = 12.0
	match tier:
		K.TIER_COMMON, K.TIER_MINION:
			t_mult = 1.0 + _t_a * m + _t_b * m * m
			base_han = _numf(def.get("han_base", null), 12.0)
		K.TIER_ELITE:
			t_mult = (1.0 + _t_a * m + _t_b * m * m) * (1.0 + _e_e * maxf(0.0, m - _e_m0))
			base_han = _numf(def.get("han_base", null), 400.0)
		K.TIER_MBOSS:
			base_han = _numf(def.get("han_fixed", null), 13000.0)
		K.TIER_BOSS:
			base_han = 130000.0     # bigs 가 형태(살/한)로 다시 정한다
		_:
			base_han = _numf(def.get("han_fixed", def.get("han_base", null)), 1.0)
	if def.has("han_fixed") and tier != K.TIER_MBOSS:
		base_han = _numf(def.get("han_fixed", null), base_han)
		t_mult = 1.0
	if String(sid0) == "enm_dokkaebi_bul__small":
		base_han = float(opts.get("parent_han", 14.0)) * 0.3
		t_mult = 1.0
	var wmul: float = _numf(_wongwi.get("han_mult", null), 4.0) if wongwi else 1.0
	var hm: float = maxf(1.0, base_han * t_mult * s_mult * wmul * float(opts.get("han_mult", 1.0)))
	px[i] = pos.x
	py[i] = pos.y
	vx[i] = 0.0
	vy[i] = 0.0
	kbx[i] = 0.0
	kby[i] = 0.0
	han_max[i] = hm
	han[i] = hm * float(opts.get("han_ratio", 1.0))
	radius[i] = _numf(def.get("hit_radius_u", null), 0.3) * K.UNIT_PX
	var spd: float = _numf(def.get("speed_u", null), 1.6) * K.UNIT_PX
	if tier == K.TIER_COMMON or tier == K.TIER_MINION:
		spd *= minf(1.0 + _v_v * m, _v_cap)
	if wongwi:
		spd = minf(spd * _numf(_wongwi.get("speed_mult", null), 1.2), _speed_cap_wongwi)
	speed[i] = spd
	var ms: Variant = def.get("mass", 1.0)
	mass[i] = 9999.0 if (ms is String and ms == "inf") else _numf(ms, 1.0)
	if wongwi:
		mass[i] *= _numf(_wongwi.get("mass_mult", null), 2.0)
	var cdm: float = _numf(def.get("contact_dmg", null), 5.0)
	if tier == K.TIER_COMMON or tier == K.TIER_MINION or tier == K.TIER_ELITE:
		cdm *= 1.0 + _c_c * m
	if wongwi:
		cdm *= _numf(_wongwi.get("contact_mult", null), 1.5)
	contact[i] = cdm
	contact_cd[i] = 0.0
	pullil_t[i] = 0.0
	grace_t[i] = 0.0
	flash[i] = 0.0
	dying_t[i] = 0.0
	species[i] = s
	facing[i] = K.Dir.SOUTH
	ppx[i] = pos.x
	ppy[i] = pos.y
	aph[i] = Rng.randf_s(&"fx")                 # 위상 오프셋(군중 동기화 깨기)
	arate[i] = Rng.range_s(&"fx", 0.9, 1.1)     # fps ±10% 지터
	kb_s[i] = 0.0
	kb_used[i] = 0.0
	hit_tick[i] = -100000
	flash_tick[i] = -100000
	nudge_tick[i] = -100000
	hit_w[i] = 1
	freeze_until[i] = 0
	stagger_until[i] = 0
	kb_t[i] = -1
	kb_last[i] = -100000
	kb_win_t[i] = -100000
	die_tick[i] = 0
	dir_hold[i] = 0
	ai_s[i] = S_BASE
	ai_m[i] = Mv.SEEK
	ai_t[i] = 0.0
	ai_cd[i] = Rng.range_s(&"ai", 0.5, 2.0)     # 첫 행동 엇갈림
	ai_x[i] = pos.x
	ai_y[i] = pos.y
	ai_vx[i] = 0.0
	ai_vy[i] = 0.0
	ai_sp[i] = spd
	ai_dir[i] = 1.0 if Rng.chance(&"ai", 0.5) else -1.0
	ai_link[i] = int(opts.get("parent", -1))
	ai_tg[i] = -1
	smult[i] = 1.0
	cmult[i] = 1.0
	dtaken[i] = 1.0
	spawn_tick[i] = Game.game_tick
	var intro_def: float = 0.4 if (tier == K.TIER_COMMON or tier == K.TIER_MINION) else 0.8
	intro_ticks[i] = maxi(1, int(roundf(float(opts.get("intro_s", intro_def)) * K.TICK_HZ)))
	last_dmg_tick[i] = -100000
	zoim[i] = 0
	host_n[i] = 0
	rscale[i] = 0
	pose_dy[i] = 0
	big[i] = null
	cell_x[i] = 0x7FFFFFFF  # 다음 rebuild_hash 전까지 해시에 없음
	var f: int = F_ALIVE
	if tier in [K.TIER_ELITE, K.TIER_MBOSS, K.TIER_BOSS, K.TIER_CHASER] or bool(opts.get("elite_plus", false)) or wongwi:
		f |= F_ELITE_PLUS | F_NO_RECYCLE
	if bool(def.get("flying", false)):
		f |= F_FLYING
	if bool(def.get("auto_target_exempt", false)):
		f |= F_AUTO_TARGET_EXEMPT
	if bool(opts.get("no_recycle", false)):
		f |= F_NO_RECYCLE
	if wongwi:
		f |= F_WONGWI
	if bool(def.get("immune_all", false)):
		f |= F_INVULN
	if bool(def.get("projectiles_pass", false)) or def.get("targetable", true) == false:
		f |= F_PASS | F_AUTO_TARGET_EXEMPT
	if def.get("hostile", true) == false or def.get("contact", true) == false or def.get("contact_damage", true) == false:
		f |= F_NONHOSTILE
	if String(sid0).ends_with("__child"):
		f |= F_CHILD
	flags[i] = f
	sp_alive[s] += 1
	_arch_init(i, s, opts)
	var h: int = handle_of(i)
	if sp_arch[s] == Arc.BIG and bigs != null:
		bigs.call("attach", i, opts)
	if (flags[i] & F_NO_PULLIL) == 0 and han[i] <= Game.pullil_threshold * hm:
		_enter_pullil(i)
	var tier_out: StringName = tier_of(i)
	Events.enemy_spawned.emit(h, sid0, tier_out)
	if tier_out == K.TIER_ELITE:
		Events.elite_spawned.emit(h, sid0)
	if tier == K.TIER_BOSS and bigs != null:
		Events.boss_spawned.emit(h, sid0, bigs.call("form_of", i))
	return h


func _free_slot(i: int) -> void:
	if (flags[i] & F_ALIVE) == 0:
		return
	if big[i] != null and bigs != null:
		bigs.call("detach", i)
	big[i] = null
	if host_n[i] > 0:
		host_n[i] = 0
	if ai_tg[i] >= 0 and hazards != null:
		hazards.call("cancel", ai_tg[i])
		ai_tg[i] = -1
	sp_alive[species[i]] -= 1
	flags[i] = 0
	gen[i] = (gen[i] + 1) & 0x7FFFF
	var p: int = active_pos[i]
	var last: int = active[active_count - 1]
	active[p] = last
	active_pos[last] = p
	active_pos[i] = -1
	active_count -= 1
	free_list[free_count] = i
	free_count += 1


func clear_all() -> void:
	while active_count > 0:
		_free_slot(active[active_count - 1])
	if hazards != null:
		hazards.call("clear_all")


## 조용히 없앤다(분열·삼킴·이탈): 보상·신호 없음. 0.15초 디졸브로 사라진다(해원 디졸브와 같은 셰이더 경로, 상승 없음).
func vanish(slot: int) -> void:
	if not is_alive(slot):
		return
	flags[slot] |= F_DYING | F_PASS | F_VANISH
	flags[slot] &= ~F_PULLIL
	die_tick[slot] = Game.game_tick
	dying_t[slot] = 0.15


# ─── 아키타입 초기화·결정(07 4.3) ───────────────────────────────────────

func _arch_init(i: int, s: int, opts: Dictionary) -> void:
	match sp_arch[s]:
		Arc.FLOAT:
			ai_cd[i] = _f_split_t if String(sp_ids[s]) != "enm_dokkaebi_bul__small" else _f_small_life
			ai_dir[i] = Rng.range_s(&"ai", 0.0, TAU)
		Arc.PROCESSION:
			# 무당 옆 3u 를 지나가는 직선(상문 행렬). 방향은 스폰 순간 고정.
			if Game.player != null:
				var pp: Vector2 = Game.player.global_position
				var to: Vector2 = pp - Vector2(px[i], py[i])
				var side: Vector2 = Vector2(-to.y, to.x).normalized() * _p_offset * ai_dir[i]
				var dirv: Vector2 = (pp + side - Vector2(px[i], py[i])).normalized()
				ai_vx[i] = dirv.x
				ai_vy[i] = dirv.y
			ai_t[i] = 14.0
			ai_m[i] = Mv.VEL
			ai_sp[i] = speed[i]
		Arc.SWARM:
			var lead: int = int(opts.get("leader", opts.get("parent", -1)))
			if lead < 0:
				# 근처(4u) 같은 종 우두머리를 찾는다. 없으면 자신이 우두머리.
				var n: int = query_circle(Vector2(px[i], py[i]), 4.0 * K.UNIT_PX, _scratch2)
				for k in n:
					var j: int = _scratch2[k]
					if j != i and species[j] == s and slot_of(ai_link[j]) < 0:
						lead = handle_of(j)
						break
			ai_link[i] = lead
		Arc.ORBIT:
			ai_t[i] = _o_flip


## 10Hz 엇갈림 결정(먼 개체는 4Hz). 상태 전이·목표 갱신·예고 시작.
func _decide(i: int, pp: Vector2, dx: float, dy: float, d: float) -> void:
	var f: int = flags[i]
	var pullil: bool = (f & F_PULLIL) != 0
	var arc: int = sp_arch[species[i]]
	var st: int = ai_s[i]
	if pullil:
		# 기색 행동(07 2.7): 모든 특수 행동 정지, 느린 배회. 착 중이면 떨어진다.
		if arc == Arc.ATTACH and st == S_ACT:
			_detach(i)
		if arc == Arc.SWARM:
			ai_link[i] = -1
		if st != S_BASE and st != S_REC:
			_reset_ai(i)
		ai_m[i] = Mv.SEEK
		ai_sp[i] = speed[i]
		flags[i] &= ~F_SCREEN
		return
	match arc:
		Arc.CHASE:
			ai_m[i] = Mv.SEEK
			ai_sp[i] = speed[i]
		Arc.GREED:
			if st == S_BASE:
				var pm: Variant = Game.pickups
				var gi: int = -1
				if pm is Object:
					gi = int((pm as Object).call("find_special", &"pick_gongmul", Vector2(px[i], py[i]), _g_seek_r))
				if gi >= 0:
					var gp: Vector2 = (pm as Object).call("special_pos", gi)
					ai_x[i] = gp.x
					ai_y[i] = gp.y
					ai_m[i] = Mv.POINT
					ai_sp[i] = _g_speed                      # 탐식: 공물로 달림(속도 상한 예외)
					ai_link[i] = gi
					var ddx: float = gp.x - px[i]
					var ddy: float = gp.y - py[i]
					if ddx * ddx + ddy * ddy < 144.0:
						if bool((pm as Object).call("take_special", gi)):
							flags[i] |= F_CARRY
							ai_s[i] = S_ACT
							ai_t[i] = _g_eat
							ai_m[i] = Mv.HOLD
				else:
					ai_m[i] = Mv.SEEK
					ai_sp[i] = speed[i]
		Arc.ATTACH:
			if st == S_BASE:
				ai_m[i] = Mv.WANDER
				ai_sp[i] = _a_wander
				if (Game.game_tick + i) % 30 == 0:
					var host: int = _find_host(i)
					if host >= 0:
						ai_link[i] = handle_of(host)
						ai_s[i] = S_SEEK2
			elif st == S_SEEK2:
				var hs: int = slot_of(ai_link[i])
				if hs < 0 or not is_alive(hs) or (flags[hs] & F_PULLIL) != 0:
					_reset_ai(i)
					return
				ai_x[i] = px[hs]
				ai_y[i] = py[hs]
				ai_m[i] = Mv.POINT
				ai_sp[i] = _a_seek
				var hx: float = px[hs] - px[i]
				var hy: float = py[hs] - py[i]
				if hx * hx + hy * hy < (_a_off + 6.0) * (_a_off + 6.0):
					ai_s[i] = S_ACT
					ai_m[i] = Mv.ATTACH
					host_n[hs] = mini(host_n[hs] + 1, 8)
					smult[hs] = 1.0 + _a_buff_spd
					cmult[hs] = 1.0 + _a_buff_dmg
			elif st == S_ACT:
				var hs2: int = slot_of(ai_link[i])
				if hs2 < 0 or not is_alive(hs2) or (flags[hs2] & F_PULLIL) != 0:
					_detach(i)
		Arc.RANGED:
			if st == S_BASE:
				if d > _r_band1:
					ai_m[i] = Mv.SEEK
					ai_sp[i] = speed[i]
				elif d < _r_band0:
					ai_m[i] = Mv.FLEE
					ai_sp[i] = _r_retreat
				else:
					ai_m[i] = Mv.STRAFE
					ai_sp[i] = _r_strafe
				if ai_cd[i] <= 0.0 and d < _r_band1 + 32.0 and is_hostile(i, true):
					# 조준(예고): 시작 순간 위치 + 선행 0.5초로 고정(07 4.5). 청 점선 조준선.
					var pl: Node2D = Game.player
					var pv: Variant = pl.get("vel") if pl != null else null
					var lead: Vector2 = (pv as Vector2) * _r_lead if pv is Vector2 else Vector2.ZERO
					var aim: Vector2 = pp + lead
					ai_x[i] = aim.x
					ai_y[i] = aim.y
					ai_s[i] = S_WIND
					ai_t[i] = _tele_common
					ai_m[i] = Mv.HOLD
					var from: Vector2 = Vector2(px[i], py[i] - 12.0)
					var dirv: Vector2 = aim - from
					ai_tg[i] = hazards.call("add_tg", 1 + 1, from, dirv, minf(dirv.length(), _r_prj_spd * _r_prj_life), 4.0, _tele_common, 0.0, handle_of(i), 0)
		Arc.CHARGER:
			if st == S_BASE:
				ai_m[i] = Mv.SEEK
				ai_sp[i] = speed[i]
				if ai_cd[i] <= 0.0 and d < _c_trig and is_hostile(i):
					var dirc: Vector2 = Vector2(dx, dy) / maxf(d, 0.001)
					ai_vx[i] = dirc.x
					ai_vy[i] = dirc.y
					ai_s[i] = S_WIND
					ai_t[i] = _c_wind
					ai_m[i] = Mv.HOLD
					ai_tg[i] = hazards.call("add_tg", 2, Vector2(px[i], py[i]), dirc, _c_tl, _c_tw, _c_wind, 0.0, handle_of(i), 0)
		Arc.ZONER:
			ai_m[i] = Mv.SEEK
			ai_sp[i] = speed[i]
			if ai_cd[i] <= 0.0 and int(hazards.call("zones_of", handle_of(i), -1)) < _z_max:
				ai_cd[i] = _z_cd
				var zt: int = hazards.call("add_tg", 0, Vector2(px[i], py[i]), Vector2.RIGHT, _z_r, 0.0, _tele_common, 0.0, handle_of(i), 3)
				hazards.call("set_act_zone", zt, 0, _z_r, _z_dur, 0.0)
		Arc.SCREEN:
			if st == S_BASE or st == S_HOLD:
				if d < _s_break:
					flags[i] &= ~F_SCREEN
					ai_s[i] = S_BASE
					ai_m[i] = Mv.SEEK
					ai_sp[i] = speed[i]
					return
				var cv: int = slot_of(ai_link[i])
				if cv < 0 or not is_alive(cv) or ai_t[i] <= 0.0:
					cv = _find_cover(i)
					ai_link[i] = handle_of(cv) if cv >= 0 else -1
					ai_t[i] = _s_reeval
				if cv >= 0:
					var away: Vector2 = Vector2(px[cv] - pp.x, py[cv] - pp.y).normalized()
					ai_x[i] = px[cv] + away.x * _s_off
					ai_y[i] = py[cv] + away.y * _s_off
					ai_m[i] = Mv.POINT
					ai_sp[i] = speed[i]
					ai_s[i] = S_HOLD
					var ex: float = ai_x[i] - px[i]
					var ey: float = ai_y[i] - py[i]
					if ex * ex + ey * ey < 400.0:
						flags[i] |= F_SCREEN
					else:
						flags[i] &= ~F_SCREEN
				else:
					flags[i] &= ~F_SCREEN
					ai_s[i] = S_BASE
					ai_m[i] = Mv.SEEK
					ai_sp[i] = speed[i]
		Arc.FLOAT:
			if st == S_BASE:
				ai_m[i] = Mv.DRIFT
				ai_sp[i] = speed[i]
				if ai_cd[i] <= 0.0:
					if String(sp_ids[species[i]]) == "enm_dokkaebi_bul__small":
						vanish(i)                            # 작은 도깨비불 수명 20초
						return
					ai_s[i] = S_WIND
					ai_t[i] = _f_tele
					ai_m[i] = Mv.HOLD
					ai_tg[i] = hazards.call("add_tg", 4, Vector2(px[i], py[i] - 10.0), Vector2.RIGHT, 10.0, 0.0, _f_tele, 0.0, handle_of(i), 0, true)
		Arc.LURCH:
			if st == S_BASE:
				ai_m[i] = Mv.SEEK
				ai_sp[i] = speed[i]
				if ai_cd[i] <= 0.0 and d < _l_trig and is_hostile(i):
					var dirl: Vector2 = Vector2(dx, dy) / maxf(d, 0.001)
					ai_vx[i] = dirl.x
					ai_vy[i] = dirl.y
					ai_s[i] = S_WIND
					ai_t[i] = _l_freeze
					ai_m[i] = Mv.HOLD
					ai_tg[i] = hazards.call("add_tg", 2, Vector2(px[i], py[i]), dirl, _l_dist + 16.0, radius[i] * 2.0, _l_freeze, 0.0, handle_of(i), 0)
		Arc.PROCESSION:
			if st == S_BASE and (d < _p_break or ai_t[i] <= 0.0):
				ai_s[i] = S_SEEK2
				ai_m[i] = Mv.SEEK
				ai_sp[i] = speed[i]
		Arc.SWARM:
			var ls: int = slot_of(ai_link[i])
			if st == S_BASE:
				if ls >= 0 and is_alive(ls) and (flags[ls] & F_PULLIL) == 0 and d > _w_rush:
					# 보이드 근사: 우두머리 주변 고리 자리(슬롯별 각)로 따라간다 + 분리는 공통 단계
					var ang: float = float(i % 12) * (TAU / 12.0)
					var rr: float = 18.0 + float(i % 3) * 10.0
					ai_x[i] = px[ls] + cos(ang) * rr
					ai_y[i] = py[ls] + sin(ang) * rr
					ai_m[i] = Mv.POINT
					ai_sp[i] = speed[i] * 1.1
				elif ls >= 0 and d > _w_rush:
					ai_m[i] = Mv.SEEK
					ai_sp[i] = _w_center
				else:
					ai_s[i] = S_ACT                          # 돌격(4u 이내 또는 우두머리 소멸)
					ai_m[i] = Mv.SEEK
					ai_sp[i] = speed[i]
			if ls < 0 and st == S_BASE:
				ai_m[i] = Mv.SEEK
				ai_sp[i] = _w_center if d > _w_rush else speed[i]
		Arc.ORBIT:
			if st == S_BASE:
				ai_m[i] = Mv.SEEK
				ai_sp[i] = speed[i]
				if d < _o_appr:
					ai_s[i] = S_HOLD
			elif st == S_HOLD:
				ai_m[i] = Mv.ORBIT
				ai_sp[i] = speed[i] * 1.15                   # 맴돌기 3.0u/s(기본 2.6 × 1.15)
				if d > _o_appr * 1.7:
					ai_s[i] = S_BASE


## 상태 타이머 만료(틱 정확). 예고 → 행동 전이.
func _on_timer(i: int) -> void:
	var arc: int = sp_arch[species[i]]
	var st: int = ai_s[i]
	match arc:
		Arc.GREED:
			if st == S_ACT:
				ai_s[i] = S_REC                           # 포만 6초: 느림 + 한 30% 회복
				ai_t[i] = _g_sated
				han[i] = minf(han_max[i], han[i] + han_max[i] * _g_heal)
				ai_m[i] = Mv.SEEK
				ai_sp[i] = _g_sated_sp
			elif st == S_REC:
				_reset_ai(i)
		Arc.ATTACH:
			if st == S_REC:
				_reset_ai(i)
		Arc.RANGED:
			if st == S_WIND:
				ai_tg[i] = -1
				if is_hostile(i, true) and Game.projectiles != null:
					var from: Vector2 = Vector2(px[i], py[i] - 12.0)
					var dirv: Vector2 = (Vector2(ai_x[i], ai_y[i]) - from).normalized()
					var m: float = Game.time_sec() / 60.0
					Game.projectiles.call("spawn_enemy", from, dirv * _r_prj_spd, _r_prj_life, _r_prj_r, _r_prj_dmg * (1.0 + _c_c * m), &"prj_wonhon_tan_wongwi" if (flags[i] & F_WONGWI) != 0 else &"prj_wonhon_tan")   # 원귀 탄은 jk_dk 링(렌더 전용, design/18 §1.1)
				ai_s[i] = S_BASE
				ai_cd[i] = _r_fire_cd * Rng.range_s(&"ai", 0.85, 1.15)
				ai_dir[i] = -ai_dir[i]
		Arc.CHARGER:
			if st == S_WIND:
				ai_tg[i] = -1
				ai_s[i] = S_ACT                           # 돌진: 고정 속도, 접촉 ×2, 질량 3
				ai_t[i] = _c_dtime
				ai_m[i] = Mv.VEL
				ai_sp[i] = _c_dash
				cmult[i] = 2.0
				contact_cd[i] = 0.0
			elif st == S_ACT:
				ai_s[i] = S_REC
				ai_t[i] = _c_rec
				ai_m[i] = Mv.HOLD
				cmult[i] = 1.0
			elif st == S_REC:
				_reset_ai(i)
				ai_cd[i] = _c_cd
		Arc.FLOAT:
			if st == S_WIND:
				ai_tg[i] = -1
				_split_bul(i)
		Arc.LURCH:
			if st == S_WIND:
				ai_tg[i] = -1
				ai_s[i] = S_ACT
				ai_t[i] = _l_dist / maxf(_l_speed, 1.0)
				ai_m[i] = Mv.VEL
				ai_sp[i] = _l_speed
				cmult[i] = 1.5
				contact_cd[i] = 0.0
			elif st == S_ACT:
				_reset_ai(i)
				ai_cd[i] = _l_cd
		Arc.ORBIT:
			ai_dir[i] = -ai_dir[i]
			ai_t[i] = _o_flip


func _reset_ai(i: int) -> void:
	if ai_tg[i] >= 0 and hazards != null:
		hazards.call("cancel", ai_tg[i])
	ai_tg[i] = -1
	ai_s[i] = S_BASE
	ai_m[i] = Mv.SEEK
	ai_t[i] = 0.0
	ai_sp[i] = speed[i]
	cmult[i] = 1.0


func _find_host(i: int) -> int:
	var n: int = query_circle(Vector2(px[i], py[i]), _a_host_r, _scratch2)
	var best: int = -1
	var bd: float = 1.0e12
	for k in n:
		var j: int = _scratch2[k]
		if j == i or sp_tier[species[j]] != K.TIER_COMMON or sp_arch[species[j]] == Arc.ATTACH:
			continue
		if (flags[j] & (F_PULLIL | F_WONGWI)) != 0 or host_n[j] > 0:
			continue
		var ddx: float = px[j] - px[i]
		var ddy: float = py[j] - py[i]
		var dd: float = ddx * ddx + ddy * ddy
		if dd < bd:
			bd = dd
			best = j
	return best


func _detach(i: int) -> void:
	var hs: int = slot_of(ai_link[i])
	if hs >= 0 and host_n[hs] > 0:
		host_n[hs] -= 1
		if host_n[hs] == 0:
			smult[hs] = 1.0
			cmult[hs] = 1.0
	ai_link[i] = -1
	ai_s[i] = S_REC
	ai_t[i] = _a_stun
	ai_m[i] = Mv.HOLD


func _find_cover(i: int) -> int:
	var n: int = query_circle(Vector2(px[i], py[i]), _s_search, _scratch2)
	var best: int = -1
	var bd: float = 1.0e12
	for k in n:
		var j: int = _scratch2[k]
		if j == i or sp_arch[species[j]] == Arc.SCREEN or (flags[j] & (F_PULLIL | F_ELITE_PLUS)) != 0:
			continue
		var ddx: float = px[j] - px[i]
		var ddy: float = py[j] - py[i]
		var dd: float = ddx * ddx + ddy * ddy
		if dd < bd:
			bd = dd
			best = j
	return best


## 도깨비불 분열: 작은 도깨비불 3(한 = 부모 최대 한 × 0.3). 부모는 조용히 사라진다(분열은 결말이 아니다).
func _split_bul(i: int) -> void:
	var p: Vector2 = Vector2(px[i], py[i])
	var hm: float = han_max[i]
	var parent: int = handle_of(i)
	vanish(i)
	for k in _f_split_n:
		var a: float = TAU * float(k) / float(_f_split_n) + Rng.range_s(&"ai", -0.3, 0.3)
		spawn(&"enm_dokkaebi_bul__small", p + Vector2(cos(a), sin(a)) * 10.0, {"parent_han": hm, "intro_s": 0.15, "parent": parent})


# ─── 틱 7~8: 사고·이동·분리 ────────────────────────────────────────────

func sim_think_move(dt: float) -> void:
	if Game.player == null:
		return
	var t0: int = Time.get_ticks_usec()
	var ppos: Vector2 = Game.player.global_position
	var gt: int = Game.game_tick
	var tsec: float = Game.time_sec()
	var a1: float = 1.0 - exp(-dt / 0.15)
	var a2: float = 1.0 - exp(-2.0 * dt / 0.15)
	var far2: float = (15.0 * K.UNIT_PX) * (15.0 * K.UNIT_PX)
	var gawi_n: int = 0
	if bigs != null:
		bigs.call("sim_pre", dt)
	var n: int = active_count
	var k: int = 0
	while k < n:
		var i: int = active[k]
		var f: int = flags[i]
		ppx[i] = px[i]
		ppy[i] = py[i]
		if (f & F_DYING) != 0:
			dying_t[i] -= dt
			if dying_t[i] <= 0.0:
				_free_slot(i)
				n -= 1
				continue  # 같은 k 에 다른 슬롯이 들어왔다
			k += 1
			continue
		if contact_cd[i] > 0.0:
			contact_cd[i] -= dt
		var elite_plus: bool = (f & F_ELITE_PLUS) != 0
		if (f & F_PULLIL) != 0:
			# 정예 이상 맺힘 시계: 최근 1초 안에 피해를 받았으면 흐르지 않는다(07 2.7.1, D-22)
			if not elite_plus or gt - last_dmg_tick[i] >= 60:
				pullil_t[i] -= dt
			if pullil_t[i] <= 0.0:
				_maetim_return(i)
				f = flags[i]
		if (f & F_GRACE) != 0:
			grace_t[i] -= dt
			if grace_t[i] <= 0.0:
				flags[i] &= ~F_GRACE
				f = flags[i]
		var dx: float = ppos.x - px[i]
		var dy: float = ppos.y - py[i]
		var d2: float = dx * dx + dy * dy
		var far: bool = d2 > far2 and not elite_plus
		# AI 타이머·쿨다운(국소 정지 중에도 흐른다: 공격 타이머는 넉백 중에도 돈다, 07 2.5)
		if ai_cd[i] > 0.0:
			ai_cd[i] -= dt
		if ai_t[i] > 0.0:
			ai_t[i] -= dt
			if ai_t[i] <= 0.0:
				if big[i] != null:
					bigs.call("on_timer", i)
				else:
					_on_timer(i)
				if (flags[i] & F_DYING) != 0:
					k += 1
					continue
		var d: float = sqrt(d2) + 0.0001
		if big[i] != null:
			bigs.call("think", i, dt, ppos, d)
			if (flags[i] & F_DYING) != 0:
				k += 1
				continue
		elif (gt + i) % (15 if far else 6) == 0:
			_decide(i, ppos, dx, dy, d)
			if (flags[i] & F_DYING) != 0:
				k += 1
				continue
		if gt < freeze_until[i]:
			k += 1
			continue                                # 국소 정지(GAME_FEEL 4.2): 이동·애니 정지, 넉백은 끝난 뒤 시작
		if dir_hold[i] > 0:
			dir_hold[i] -= 1
		if kb_t[i] >= 0:
			# 넉백 = 거리(GAME_FEEL 4.3): apply_time 동안 ease-out quad, 이 동안 AI 속도 0
			kb_t[i] += 1
			var tt: float = minf(float(kb_t[i]) / _kb_apply_ticks, 1.0)
			var sv: float = 1.0 - (1.0 - tt) * (1.0 - tt)
			var ds: float = sv - kb_s[i]
			kb_s[i] = sv
			px[i] += kbx[i] * ds
			py[i] += kby[i] * ds
			vx[i] = 0.0
			vy[i] = 0.0
			if tt >= 1.0:
				kb_t[i] = -1
				stagger_until[i] = gt + _kb_recover_ticks
			k += 1
			continue
		# LOD(07 4.6): 화면 밖 15u 넘는 일반 잡귀는 이동을 격틱(2×dt)으로
		var mdt: float = dt
		var aa: float = a1
		if far:
			if ((gt + i) & 1) == 1:
				k += 1
				continue
			mdt = dt * 2.0
			aa = a2
		var pullil: bool = (f & F_PULLIL) != 0
		var mv: float = smult[i]
		if pullil:
			mv *= _giseak_move if elite_plus else _giseak_move_common
		elif (f & F_GRACE) != 0:
			mv *= _maetim_grace_move
		var spd: float = ai_sp[i] * mv
		var mode: int = ai_m[i]
		if not elite_plus and mode != Mv.VEL and not (mode == Mv.POINT and sp_arch[species[i]] == Arc.GREED):
			spd = minf(spd, _speed_cap_common if (f & F_WONGWI) == 0 else _speed_cap_wongwi)
		var tvx: float = 0.0
		var tvy: float = 0.0
		var stop_r: float = (radius[i] + _player_hit_r) * 0.8
		var ux: float = dx / d
		var uy: float = dy / d
		if gt >= stagger_until[i]:
			match mode:
				Mv.SEEK:
					if d > stop_r:
						if pullil and not elite_plus:
							# 배회(07 giseak.common_overlay: slow_wander_toward_player). 결정적: 시간·슬롯 위상만 쓴다(RNG 소비 없음).
							var wa: float = sin(tsec * 1.3 + float(i) * 1.7) * 0.9
							var cw: float = cos(wa)
							var sw: float = sin(wa)
							var rx: float = ux * cw - uy * sw
							uy = ux * sw + uy * cw
							ux = rx
						tvx = ux * spd
						tvy = uy * spd
				Mv.HOLD:
					pass
				Mv.VEL:
					tvx = ai_vx[i] * spd
					tvy = ai_vy[i] * spd
				Mv.POINT:
					var tx: float = ai_x[i] - px[i]
					var ty: float = ai_y[i] - py[i]
					var td: float = sqrt(tx * tx + ty * ty)
					if td > 3.0:
						var sl: float = minf(spd, td * 6.0)
						tvx = tx / td * sl
						tvy = ty / td * sl
				Mv.ORBIT:
					# 반지름 오차 보정 + 접선
					var orr: float = _o_r if big[i] == null else ai_x[i]
					var radial: float = clampf((d - orr) / 32.0, -1.0, 1.0)
					var tx2: float = -uy * ai_dir[i]
					var ty2: float = ux * ai_dir[i]
					var vxo: float = tx2 + ux * radial
					var vyo: float = ty2 + uy * radial
					var vl: float = sqrt(vxo * vxo + vyo * vyo) + 0.0001
					tvx = vxo / vl * spd
					tvy = vyo / vl * spd
					if d < _o_aura and big[i] == null and is_hostile(i):
						gawi_n += 1
				Mv.FLEE:
					tvx = -ux * spd
					tvy = -uy * spd
				Mv.STRAFE:
					var band_c: float = (_r_band0 + _r_band1) * 0.5
					var rad2: float = clampf((d - band_c) / 48.0, -0.6, 0.6)
					var sx: float = -uy * ai_dir[i] + ux * rad2
					var sy: float = ux * ai_dir[i] + uy * rad2
					var sl2: float = sqrt(sx * sx + sy * sy) + 0.0001
					tvx = sx / sl2 * spd
					tvy = sy / sl2 * spd
				Mv.WANDER:
					var wb: float = sin(tsec * TAU / _a_period + float(i) * 2.3) * _a_wobble
					var c2: float = cos(wb)
					var s2: float = sin(wb)
					tvx = (ux * c2 - uy * s2) * spd
					tvy = (ux * s2 + uy * c2) * spd
				Mv.DRIFT:
					var nz: float = sin(tsec * TAU * _f_hz + ai_dir[i]) * _f_noise
					var c3: float = cos(nz)
					var s3: float = sin(nz)
					tvx = (ux * c3 - uy * s3) * spd
					tvy = (ux * s3 + uy * c3) * spd
				Mv.ATTACH:
					var hs: int = slot_of(ai_link[i])
					if hs >= 0:
						var side: float = ai_dir[i]
						px[i] = px[hs] + side * _a_off
						py[i] = py[hs] - 2.0
						vx[i] = vx[hs]
						vy[i] = vy[hs]
						k += 1
						continue
		if mode == Mv.VEL:
			vx[i] = tvx
			vy[i] = tvy
		else:
			vx[i] += (tvx - vx[i]) * aa
			vy[i] += (tvy - vy[i]) * aa
		px[i] += vx[i] * mdt
		py[i] += vy[i] * mdt
		if dir_hold[i] == 0:
			var fx: float = vx[i]
			var fy: float = vy[i]
			if mode == Mv.HOLD or (fx * fx + fy * fy) < 16.0:
				fx = dx                                 # 멈춰 있으면 무당을 본다(조준·예고 중)
				fy = dy
			var nf: int = K.dir4_from_vec(Vector2(fx, fy), facing[i], 10.0)
			if nf != facing[i]:
				facing[i] = nf
				dir_hold[i] = _dir_hold_ticks       # 방향 최소 유지 0.25s(B16)
		# 재배치: 플레이어에서 너무 멀면 반대편 스폰 링으로(design/08 recycle)
		if d2 > _recycle_px * _recycle_px and (f & (F_NO_RECYCLE | F_PULLIL)) == 0 and mode != Mv.ATTACH:
			var ang: float = atan2(-dy, -dx) + PI + Rng.range_s(&"spawn", -0.6, 0.6)
			var rr: float = 13.0 * K.UNIT_PX
			px[i] = ppos.x + cos(ang) * rr
			py[i] = ppos.y + sin(ang) * rr
			ppx[i] = px[i]                          # 순간이동: 보간 끊기
			ppy[i] = py[i]
			if sp_arch[species[i]] == Arc.PROCESSION:
				_arch_init(i, species[i], {})
		k += 1
	_separate(gt)
	_sim_gawi(dt, gawi_n)
	if hazards != null:
		hazards.call("sim_step", dt)
	_perf_think_us += Time.get_ticks_usec() - t0


## 훼훼귀신 가위눌림(st_gawi): 맴도는 개체 수 × 초당 1스택(상한 3/s), 3스택이면 −40% 1.5초, 뒤 3초 면역.
func _sim_gawi(dt: float, n: int) -> void:
	if _gawi_cd > 0.0:
		_gawi_cd -= dt
		return
	if n <= 0:
		_gawi_stack = maxf(0.0, _gawi_stack - dt)
		return
	_gawi_stack += minf(float(n) * _gawi_rate, 3.0) * dt
	if _gawi_stack >= _gawi_trigger and hazards != null:
		_gawi_stack = 0.0
		_gawi_cd = _gawi_dur + _gawi_immune
		var pl: Node2D = Game.player
		if pl != null:
			hazards.call("add_zone", 0, pl.global_position, 40.0, _gawi_dur, 0.0, -1, _gawi_slow)


## 겹침 방지. 질량 비례로 밀어낸다. 이웃 최대 6(07 4.4), 먼 개체는 격틱.
## 군중이 플레이어 주위에 몰리면 2u 해시 칸 하나에 수십 마리가 들어가 O(n²) 이 된다(18분 sep 1.4~4.8ms 실측).
## → 이번 틱 위치로 작은 몸 전용 촘촘한 해시(SEP_CELL 20px)를 다시 짓고, 큰 몸(반경 > 16px, ≤ 64)은 목록으로 따로 본다.
func _separate(gt: int) -> void:
	var pp: Vector2 = Game.player.global_position
	var far2: float = (15.0 * K.UNIT_PX) * (15.0 * K.UNIT_PX)
	if _sep_head.size() != SEP_HASH:
		_sep_head.resize(SEP_HASH)
		_sep_next.resize(CAPACITY)
		_sep_cx.resize(CAPACITY)
		_sep_cy.resize(CAPACITY)
		_sep_big.resize(SEP_BIG_CAP)
	_sep_head.fill(-1)
	var nbig: int = 0
	for k in active_count:
		var i: int = active[k]
		if (flags[i] & (F_DYING | F_FLYING | F_HIDDEN)) != 0 or ai_m[i] == Mv.ATTACH:
			_sep_cx[i] = 0x7FFFFFFF
			continue
		if radius[i] > SEP_SMALL_R:
			_sep_cx[i] = 0x7FFFFFFE
			if nbig < SEP_BIG_CAP:
				_sep_big[nbig] = i
				nbig += 1
			continue
		var cx: int = int(floor(px[i] / SEP_CELL))
		var cy: int = int(floor(py[i] / SEP_CELL))
		_sep_cx[i] = cx
		_sep_cy[i] = cy
		var b: int = ((cx * 73856093) ^ (cy * 19349663)) & SEP_MASK
		_sep_next[i] = _sep_head[b]
		_sep_head[b] = i
	for k in active_count:
		var i: int = active[k]
		var sc: int = _sep_cx[i]
		if sc == 0x7FFFFFFF:
			continue                              # 제외 대상(죽는 중·비행·숨김·착)
		var small: bool = sc != 0x7FFFFFFE
		var ex: float = px[i] - pp.x
		var ey: float = py[i] - pp.y
		# 격틱 갱신(밀어내기 ×2): 가까운 개체 2틱, 먼 개체 4틱마다
		if ex * ex + ey * ey > far2:
			if ((gt + i) & 3) != 0:
				continue
		elif ((gt + i) & 1) != 0:
			continue
		var ri: float = radius[i]
		var mi: float = mass[i]
		var sx: float = 0.0
		var sy: float = 0.0
		var found: int = 0
		if small:
			var cx: int = _sep_cx[i]
			var cy: int = _sep_cy[i]
			var visited: int = 0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var ccx: int = cx + ox
					var ccy: int = cy + oy
					var j: int = _sep_head[((ccx * 73856093) ^ (ccy * 19349663)) & SEP_MASK]
					while j != -1 and found < 6 and visited < SEP_VISIT_CAP:
						if j != i and _sep_cx[j] == ccx and _sep_cy[j] == ccy:
							visited += 1
							var ddx: float = px[i] - px[j]
							var ddy: float = py[i] - py[j]
							var rs: float = (ri + radius[j]) * 0.9
							var dd: float = ddx * ddx + ddy * ddy
							if dd < rs * rs and dd > 0.0001:
								var dl: float = sqrt(dd)
								var push: float = (rs - dl) / dl * (mass[j] / (mi + mass[j]))
								sx += ddx * push
								sy += ddy * push
								found += 1
						j = _sep_next[j]
		# 큰 몸(정예 이상): 작은 몸은 큰 몸에서 밀려나고, 큰 몸끼리도 서로 민다. 큰 몸은 작은 몸에 밀리지 않는다(질량).
		for b2 in nbig:
			var j2: int = _sep_big[b2]
			if j2 == i:
				continue
			var ddx2: float = px[i] - px[j2]
			var ddy2: float = py[i] - py[j2]
			var rs2: float = (ri + radius[j2]) * 0.9
			var dd2: float = ddx2 * ddx2 + ddy2 * ddy2
			if dd2 < rs2 * rs2 and dd2 > 0.0001:
				var dl2: float = sqrt(dd2)
				var push2: float = (rs2 - dl2) / dl2 * (mass[j2] / (mi + mass[j2]))
				sx += ddx2 * push2
				sy += ddy2 * push2
				found += 1
		if found > 0:
			px[i] += clampf(sx, -4.0, 4.0)
			py[i] += clampf(sy, -4.0, 4.0)


# ─── 틱 9: 공간 해시 ───────────────────────────────────────────────────

func _bucket(cx: int, cy: int) -> int:
	return ((cx * 73856093) ^ (cy * 19349663)) & HASH_MASK


func rebuild_hash() -> void:
	var t0: int = Time.get_ticks_usec()
	hash_head.fill(-1)
	for k in active_count:
		var i: int = active[k]
		if (flags[i] & (F_DYING | F_HIDDEN)) != 0:
			cell_x[i] = 0x7FFFFFFF
			continue
		var cx: int = int(floor(px[i] / CELL_PX))
		var cy: int = int(floor(py[i] / CELL_PX))
		cell_x[i] = cx
		cell_y[i] = cy
		var b: int = _bucket(cx, cy)
		next_in_cell[i] = hash_head[b]
		hash_head[b] = i
	_perf_hash_us += Time.get_ticks_usec() - t0


## 원 안의 적 슬롯을 out 에 채운다(적 반경 포함). 반환: 개수. 할당 없음. 통과(F_PASS) 개체 제외.
func query_circle(pos: Vector2, r: float, out: PackedInt32Array, max_out: int = -1) -> int:
	var cap: int = out.size() if max_out < 0 else mini(max_out, out.size())
	var n: int = 0
	var reach: float = r + 1.6 * K.UNIT_PX
	var x0: int = int(floor((pos.x - reach) / CELL_PX))
	var x1: int = int(floor((pos.x + reach) / CELL_PX))
	var y0: int = int(floor((pos.y - reach) / CELL_PX))
	var y1: int = int(floor((pos.y + reach) / CELL_PX))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var j: int = hash_head[_bucket(cx, cy)]
			while j != -1:
				if cell_x[j] == cx and cell_y[j] == cy and (flags[j] & (F_ALIVE | F_DYING | F_PASS)) == F_ALIVE:
					var dx: float = px[j] - pos.x
					var dy: float = py[j] - pos.y
					var rr: float = r + radius[j]
					if dx * dx + dy * dy <= rr * rr:
						out[n] = j
						n += 1
						if n >= cap:
							return n
				j = next_in_cell[j]
	return n


## 가장 가까운 적 슬롯. exclude_mask 비트가 있는 개체 제외(기본: 자동 조준 제외·죽는 중). 통과·숨김 개체는 항상 제외.
func nearest(pos: Vector2, max_r: float, exclude_mask: int = F_DYING | F_AUTO_TARGET_EXEMPT) -> int:
	var best: int = -1
	var best_d: float = max_r * max_r
	var mask: int = exclude_mask | F_PASS | F_HIDDEN
	for k in active_count:
		var i: int = active[k]
		if (flags[i] & mask) != 0:
			continue
		var dx: float = px[i] - pos.x
		var dy: float = py[i] - pos.y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = i
	return best


# ─── 틱 13~14: 피해 해석 ───────────────────────────────────────────────

func queue_hit(slot: int, dmg: float, color: int, crit: bool = false, kb_dir: Vector2 = Vector2.ZERO, kb_u: float = 0.0, source_slot: int = -1) -> void:
	if hq_count >= HIT_CAP or not is_alive(slot) or (flags[slot] & F_PASS) != 0:
		return
	var q: int = hq_count
	hq_slot[q] = slot
	hq_gen[q] = gen[slot]
	hq_dmg[q] = dmg
	hq_color[q] = color
	hq_crit[q] = 1 if crit else 0
	hq_kbx[q] = kb_dir.x
	hq_kby[q] = kb_dir.y
	hq_kb[q] = kb_u * K.UNIT_PX
	hq_src[q] = source_slot
	hq_count += 1


func resolve_hits() -> void:
	if hq_count == 0:
		return
	var t0: int = Time.get_ticks_usec()
	# 정렬 키(02 §6.3): 백(영가 오라·양면의 백 전환 포함) → 적 → (지속 피해는 각 색 규칙)
	for pass_i in 2:
		for q in hq_count:
			var c: int = hq_color[q]
			if c == K.DmgColor.NONE:
				continue
			var i: int = hq_slot[q]
			if gen[i] != hq_gen[q] or not is_alive(i):
				hq_color[q] = K.DmgColor.NONE  # 처치 확정된 대상의 나머지 히트는 버린다
				continue
			var eff: int = c
			if c == K.DmgColor.UNION:
				eff = K.DmgColor.WHITE if (flags[i] & F_PULLIL) != 0 else K.DmgColor.RED
			elif c == K.DmgColor.AURA_YEONGGA or c == K.DmgColor.RING:
				eff = K.DmgColor.WHITE
			var white: bool = eff == K.DmgColor.WHITE
			if (pass_i == 0) != white:
				continue
			_resolve_one(i, hq_dmg[q], eff, hq_crit[q] == 1, hq_kbx[q], hq_kby[q], hq_kb[q], hq_src[q])
			hq_color[q] = K.DmgColor.NONE
	hq_count = 0
	_perf_resolve_us += Time.get_ticks_usec() - t0


func _resolve_one(i: int, dmg_in: float, color: int, crit: bool, dirx: float, diry: float, kb_px: float, src: int) -> void:
	var f: int = flags[i]
	var w: int = _weight_of(src)
	if (f & F_INVULN) != 0:
		if big[i] != null:
			_hit_react(i, 0.0, false, dirx, diry, 0.0, false, w)   # 묶임 중에도 맞는 반응(외곽 플래시, 드물게)은 보인다
		return
	var elite_plus: bool = (f & F_ELITE_PLUS) != 0
	var pullil: bool = (f & F_PULLIL) != 0
	var white: bool = color == K.DmgColor.WHITE
	# 찌르기·관통 계열(삼지창·장창·사인사검): kb 가 없으면 light 등급 넉백 — 창의 손맛(백 무구는 풀릴 기색을 밀지 않는다)
	if kb_px <= 0.0 and src >= 0 and _w_src_thrust and (dirx != 0.0 or diry != 0.0) and not (pullil and white):
		kb_px = _w_thrust_kb_px
	var dmg: float = dmg_in * dtaken[i]
	if pullil and white:
		dmg *= minf(Game.stat(&"stat_puri", 3.0), 6.0)
	if not white and (f & F_SCREEN) != 0:
		dmg *= 1.0 - _s_red
	if big[i] != null:
		dmg = float(bigs.call("filter_damage", i, dmg, white, src))
		if dmg <= 0.0:
			_hit_react(i, 0.0, false, dirx, diry, 0.0, pullil, w)
			return
	last_dmg_tick[i] = Game.game_tick
	_hit_react(i, dmg, crit, dirx, diry, kb_px, pullil, w)
	flash[i] = 1.0
	if white:
		flags[i] |= F_WHITE_FLASH
	else:
		flags[i] &= ~F_WHITE_FLASH
	var h: int = handle_of(i)
	var sid: StringName = sp_ids[species[i]]
	var pos: Vector2 = Vector2(px[i], py[i])
	# 결단타: 풀릴 기색 + 적 무구 + 치명(일반 잡귀만)
	if pullil and not white and not elite_plus and crit and Rng.chance(&"combat", minf(Game.stat(&"stat_gyeoldan", 0.05), 0.5)):
		han[i] = 0.0
		Events.enemy_hit.emit(h, sid, pos, dmg, color, crit, false)
		_kill(i, K.KIND_TOECHI, &"gyeoldan")
		return
	# 매듭 잠금: 풀릴 기색 일반 잡귀에게 적 무구는 한을 1 미만으로 못 깎는다 — 조임 단계 누적(07 2.7)
	if pullil and not white and not elite_plus:
		var before: float = han[i]
		han[i] = maxf(1.0, han[i] - dmg)
		if zoim[i] < 250:
			zoim[i] += 1
		Events.enemy_hit.emit(h, sid, pos, before - han[i], color, crit, true)
		return
	han[i] -= dmg
	Events.enemy_hit.emit(h, sid, pos, dmg, color, crit, false)
	if big[i] != null:
		bigs.call("after_hit", i, dmg, white)
		if not is_alive(i):
			return
	if han[i] <= 0.0:
		if white:
			_kill(i, K.KIND_HAEWON, &"white")
		elif elite_plus:
			_kill(i, K.KIND_TOECHI, &"elite_last")
		else:
			_kill(i, K.KIND_TOECHI, &"han_pa")
		return
	if not pullil and (flags[i] & F_NO_PULLIL) == 0 and han[i] <= Game.pullil_threshold * han_max[i]:
		_enter_pullil(i)


func _enter_pullil(i: int) -> void:
	flags[i] |= F_PULLIL
	var dur: float = _giseak_dur_repeat if (flags[i] & F_PULLIL_SECOND) != 0 else _giseak_dur
	if sp_ids[species[i]] == &"enm_gaekgwi" and (flags[i] & F_PULLIL_SECOND) == 0:
		dur = Data.num("combat_core", "han.giseak_duration_gaekgwi", 16.0)
	pullil_t[i] = dur
	zoim[i] = 0
	if (flags[i] & F_ELITE_PLUS) == 0:
		# 기색 행동: 진행 중 예고 취소(0.2초 페이드), 특수 행동 정지(07 4.2)
		if hazards != null:
			hazards.call("cancel_owner", handle_of(i))
		if sp_arch[species[i]] == Arc.ATTACH and ai_s[i] == S_ACT:
			_detach(i)
		_reset_ai(i)
		flags[i] &= ~F_SCREEN
	elif big[i] != null:
		bigs.call("on_pullil", i)
	Events.pullil_entered.emit(handle_of(i), sp_ids[species[i]], Vector2(px[i], py[i]))


func _maetim_return(i: int) -> void:
	flags[i] &= ~F_PULLIL
	flags[i] |= F_PULLIL_SECOND
	zoim[i] = 0
	if (flags[i] & F_ELITE_PLUS) != 0:
		han[i] = maxf(han[i], _maetim_ratio * han_max[i])
	else:
		# 일반·하위 변형: 한 45%로 복귀 + 3초 비적대(접촉·원거리 없음). 캐논 v1.2 D-20/C-09
		han[i] = maxf(han[i], _maetim_ratio_common * han_max[i])
		if _maetim_grace > 0.0:
			flags[i] |= F_GRACE
			grace_t[i] = _maetim_grace
	Events.maetim_returned.emit(handle_of(i), sp_ids[species[i]], Vector2(px[i], py[i]))


func _kill(i: int, kind: StringName, cause: StringName) -> void:
	var h: int = handle_of(i)
	var s: int = species[i]
	var sid: StringName = sp_ids[s]
	var tier: StringName = tier_of(i)
	var pos: Vector2 = Vector2(px[i], py[i])
	var elite_plus: bool = (flags[i] & F_ELITE_PLUS) != 0
	die_tick[i] = Game.game_tick
	if hazards != null:
		hazards.call("cancel_owner", h)
	var wt: float = float(_w_tier.get(String(tier), 1.0))
	if kind == K.KIND_HAEWON:
		Game.kills_haewon += 1
		sp_haewon[s] += 1
		w_haewon += wt
		flags[i] |= F_DYING
		var ht: int = HAEWON_TICKS_ELITE if elite_plus else HAEWON_TICKS
		dying_t[i] = float(ht) / K.TICK_HZ - 0.0001
	else:
		Game.kills_toechi += 1
		sp_toechi[s] += 1
		w_toechi += wt
		_sal_alg = minf(200.0, _sal_alg + (1.0 if not elite_plus else (5.0 if tier == K.TIER_ELITE else 10.0)))
		flags[i] |= F_DYING | F_TOECHI_BURST
		# 퇴치 = 번쩍 + 파열(GAME_FEEL 4.4): hj 2 → jk 4 → jk_hi 3틱 → 해제
		dying_t[i] = float(_toechi_seq[0] + _toechi_seq[1] + _toechi_seq[2]) / K.TICK_HZ - 0.0001
	flags[i] &= ~(F_PULLIL | F_SCREEN)
	if ai_m[i] == Mv.ATTACH:
		_on_attached_resolved(i, kind)
	if host_n[i] > 0:
		_release_parasites(i)
	_species_result(i, s, kind, pos)
	if big[i] != null:
		bigs.call("on_kill", i, kind)
	Events.enemy_killed.emit(h, sid, pos, kind, cause, tier)


## 종별 결말 추가 결과(07 5장 toechi_result / haewon_result).
func _species_result(i: int, s: int, kind: StringName, pos: Vector2) -> void:
	var haewon: bool = kind == K.KIND_HAEWON
	match String(sp_ids[s]):
		"enm_agwi":
			if haewon and (flags[i] & F_CARRY) != 0 and Game.pickups != null:
				Game.pickups.call("spawn_special", &"pick_gongmul", pos)   # 품었던 공물 반환
		"enm_mul_gwisin":
			if hazards != null:
				if haewon:
					# 맑은 물(아군): 재생 2/초(dps 칸을 아군 재생으로 쓴다)
					hazards.call("convert_owner_zones", handle_of(i), 2, -1.0, 0.0, 0.0, Data.num("enemies", "zones.obj_mul_ungdeongi__clear.player_saenggi_per_s", 2.0))
				else:
					var r: float = Data.num("enemies", "zones.obj_mul_ungdeongi__black.radius_u", 1.8) * K.UNIT_PX
					var sl: float = Data.num("enemies", "zones.obj_mul_ungdeongi__black.player_slow_pct", 35.0) / 100.0
					hazards.call("convert_owner_zones", handle_of(i), 1, r, Data.num("enemies", "zones.obj_mul_ungdeongi__black.duration_add_s", 5.0), sl)
		"enm_yeongsan":
			if haewon:
				var pl: Node2D = Game.player
				if pl != null:
					var ph: Variant = pl.get("hit")
					if ph is Object:
						(ph as Object).call("heal", Game.hp_max * 0.01)
			elif hazards != null:
				var m: float = Game.time_sec() / 60.0
				hazards.call("add_zone", 3, pos, Data.num("enemies", "zones.obj_hyungsal_jangpan.radius_u", 1.5) * K.UNIT_PX,
					Data.num("enemies", "zones.obj_hyungsal_jangpan.duration_s", 3.0), 8.0 * (1.0 + _c_c * m), -1, 0.0)
		"enm_dokkaebi_bul":
			if not haewon:
				var hm: float = han_max[i]
				for k in _f_split_n:
					var a: float = TAU * float(k) / float(_f_split_n)
					spawn(&"enm_dokkaebi_bul__small", pos + Vector2(cos(a), sin(a)) * 10.0, {"parent_han": hm, "intro_s": 0.15})
		"enm_hosik_wonhon":
			if haewon:
				# 엄폐물 공포 1초(st_gyeongak)
				var cv: int = slot_of(ai_link[i])
				if cv >= 0 and is_alive(cv) and (flags[cv] & F_ELITE_PLUS) == 0:
					ai_m[cv] = Mv.FLEE
					ai_s[cv] = S_REC
					ai_t[cv] = 1.0
					ai_sp[cv] = speed[cv]
		"enm_cheonyeo_gwisin":
			pass   # 해원: 자기 탄 → 꽃잎(무해) — TODO(combat): ProjectilePool 에 소유자 태그가 없어 적 탄 구분 불가


## 객귀가 붙은 채로 결말: 퇴치 = 숙주 영구 버프(속도 +30%·최대 한 +50%), 해원 = 숙주 풀릴 기색(r 0.35).
func _on_attached_resolved(i: int, kind: StringName) -> void:
	var hs: int = slot_of(ai_link[i])
	if hs < 0 or not is_alive(hs):
		return
	if host_n[hs] > 0:
		host_n[hs] -= 1
	if kind == K.KIND_TOECHI:
		speed[hs] *= 1.3
		ai_sp[hs] = speed[hs]
		han_max[hs] *= 1.5
		han[hs] *= 1.5
		smult[hs] = 1.0
		cmult[hs] = 1.0
	else:
		smult[hs] = 1.0
		cmult[hs] = 1.0
		if (flags[hs] & F_PULLIL) == 0:
			han[hs] = minf(han[hs], han_max[hs] * Game.pullil_threshold)
			_enter_pullil(hs)


func _release_parasites(host: int) -> void:
	var hh: int = handle_of(host)
	for k in active_count:
		var j: int = active[k]
		if ai_m[j] == Mv.ATTACH and ai_link[j] == hh:
			ai_link[j] = -1
			ai_s[j] = S_REC
			ai_t[j] = _a_stun
			ai_m[j] = Mv.HOLD
	host_n[host] = 0


## 외부 확정(고리 닫힘·저승사자·디버그). 풀릴 기색 여부와 무관하게 결과를 강제한다.
func force_haewon(slot: int, cause: StringName = &"ring") -> void:
	if is_alive(slot) and (flags[slot] & (F_PASS | F_NONHOSTILE)) == 0:
		if big[slot] != null and not bool(bigs.call("allow_force", slot, cause)):
			return
		han[slot] = 0.0
		_kill(slot, K.KIND_HAEWON, cause)


func force_toechi(slot: int, cause: StringName = &"debug") -> void:
	if is_alive(slot) and (flags[slot] & (F_PASS | F_NONHOSTILE)) == 0:
		han[slot] = 0.0
		_kill(slot, K.KIND_TOECHI, cause)


## 예고 효과 실행 알림(hazards → em). 연출 신호 지점(현재 비어 있음 — audio 가 쓸 수 있게 자리만).
func on_telegraph_fired(_owner: int, _shape: int, _c: Vector2) -> void:
	pass


# ─── 원귀 회귀(07 6.6, haewon 의 wongwi_return 신호) ───────────────────

func _on_wongwi_return(_threshold: int) -> void:
	if Game.player == null or _sal_alg <= 0.0:
		return                                      # skip_if_no_toechi
	var cap: int = int(Data.num("enemies", "caps.wongwi", 20))
	# 캐논 3.2.6: 원귀 1~3(combat_core.salgi.wongwi_count). 이전 2~20 은 상자 과다(판당 27~49)의 원인(리드 11-24).
	var cnt: int = clampi(int(roundf(_sal_alg / 10.0)), int(Data.num("combat_core", "salgi.wongwi_count.min", 1)),
		int(Data.num("combat_core", "salgi.wongwi_count.max", 3)))
	var alive_w: int = 0
	for k in active_count:
		if (flags[active[k]] & F_WONGWI) != 0:
			alive_w += 1
	cnt = mini(cnt, cap - alive_w)
	_sal_alg = 0.0                                   # clears_map_algaengi
	var pp: Vector2 = Game.player.global_position
	var ring: float = Data.num("enemies", "elites.6.event.silhouette_ring_u", 9.0) * K.UNIT_PX
	var lift: float = Data.num("enemies", "elites.6.event.activate_after_s", 2.5)
	for n in cnt:
		var sp: StringName = top_toechi_species(n % 3)
		var a: float = TAU * float(n) / float(maxi(cnt, 1)) + Rng.range_s(&"spawn", -0.2, 0.2)
		spawn(sp, pp + Vector2(cos(a), sin(a)) * ring, {"wongwi": true, "no_variant": true, "intro_s": lift})


# ─── 틱 16: 접촉 피해 ──────────────────────────────────────────────────

## 플레이어 접촉. 반환: 몸에 닿아 있는 적 수(군중 감속용).
func sim_contact_player(_dt: float) -> int:
	if Game.player == null:
		return 0
	var t0: int = Time.get_ticks_usec()
	var pp: Vector2 = Game.player.global_position
	var n: int = query_circle(pp, _player_hit_r, _scratch)
	var touching: int = 0
	var gt: int = Game.game_tick
	for k in n:
		var i: int = _scratch[k]
		var f: int = flags[i]
		if (f & (F_DYING | F_HIDDEN | F_NONHOSTILE)) != 0:
			continue
		touching += 1
		if (f & F_GRACE) != 0 or gt - spawn_tick[i] < intro_ticks[i]:
			continue  # 맺힘 복귀 직후 비적대·등장 솟음 중: 몸은 막지만 접촉 피해 없음(D-20, 07 4.2 Spawning)
		if contact_cd[i] <= 0.0:
			# 풀릴 기색 접촉: 일반·하위 변형 ×giseak_general_contact_mult, 정예 이상은 접촉 유지(×1.0)
			var mult: float = cmult[i]
			if (f & F_PULLIL) != 0 and (f & F_ELITE_PLUS) == 0:
				mult *= _giseak_contact_common
			contact_cd[i] = _contact_cd_default
			if mult > 0.0 and Game.player.has_method("take_hit"):
				Game.player.call("take_hit", contact[i] * mult, sp_ids[species[i]])
	_perf_contact_us += Time.get_ticks_usec() - t0
	_perf_n += 1
	if Game.autotest and gt >= _perf_next_tick:
		if _perf_next_tick > 0:
			_print_perf()
		_perf_next_tick = gt - gt % (120 * K.TICK_HZ) + 120 * K.TICK_HZ
	return touching


func _print_perf() -> void:
	var nn: float = maxf(1.0, float(_perf_n))
	var pk: Variant = Game.pickups.get("count") if Game.pickups != null else 0
	print("[enemies] t=%s n=%d think_ms=%.3f hash_ms=%.3f resolve_ms=%.3f contact_ms=%.3f pickups=%s tg=%d zones=%d bigs=%d N=%.2f" % [
		K.fmt_time(Game.time_sec()), active_count, float(_perf_think_us) / nn / 1000.0, float(_perf_hash_us) / nn / 1000.0,
		float(_perf_resolve_us) / nn / 1000.0, float(_perf_contact_us) / nn / 1000.0, str(pk),
		int(hazards.get("tg_count")) if hazards != null else 0, int(hazards.get("z_count")) if hazards != null else 0,
		int(bigs.call("count")) if bigs != null else 0, n_ratio()])
	_perf_think_us = 0
	_perf_hash_us = 0
	_perf_resolve_us = 0
	_perf_contact_us = 0
	_perf_n = 0


# ─── 피격 반응(GAME_FEEL 4.2·4.3) ─────────────────────────────────────

var _wslot_obj: Array = []                 # 무구 슬롯 → 마지막으로 본 무구 객체(무게 등급 캐시)
var _wslot_w: PackedInt32Array = PackedInt32Array()
var _wslot_thrust: PackedByteArray = PackedByteArray()
var _w_src_thrust: bool = false            # 직전 _weight_of 의 찌르기 여부(같은 틱 안에서만 유효)


## 피해 출처(무구 슬롯) → 무게 등급 0 경 / 1 중 / 2 중량. 무구 외 출처(-1)는 default. 슬롯별 객체 캐시(진화로 바뀌면 다시 찾는다).
func _weight_of(src: int) -> int:
	_w_src_thrust = false
	if src < 0 or src >= 16 or Game.weapons == null:
		return _w_default
	if _wslot_obj.size() < 16:
		_wslot_obj.resize(16)
		_wslot_w.resize(16)
		_wslot_thrust.resize(16)
	var wo: Variant = Game.weapons.call("weapon_at", src)
	if not (wo is Object):
		return _w_default
	if _wslot_obj[src] != wo:
		_wslot_obj[src] = wo
		var wid: StringName = StringName(String((wo as Object).get("id")))
		_wslot_w[src] = int(_w_of.get(wid, _w_default))
		_wslot_thrust[src] = 1 if _w_thrust.has(wid) else 0
	_w_src_thrust = _wslot_thrust[src] == 1
	return _wslot_w[src]


## 플래시·스쿼시(렌더) + 국소 정지·넉백 거리 모델(시뮬, 결정론). resolve_hits 안에서만 호출.
## w = 무게 등급(0 경 / 1 중 / 2 중량): 정지 틱 freeze_ticks[w](중량은 피해 조건 없이 항상), 스쿼시·넛지 길이.
func _hit_react(i: int, dmg: float, crit: bool, dirx: float, diry: float, kb_px: float, pullil: bool, w: int = 1) -> void:
	var gt: int = Game.game_tick
	if big[i] != null:
		# 큰 몸(정예·중간보스·보스): 온몸 5Hz 스트로브 금지 — 30틱 간격 + 치명·중량·큰 피해(한 최대치 1%)만, 외곽선 모드(render)
		var iv: int = _flash_big_iv * (2 if dmg <= 0.0 else 1)
		if gt - flash_tick[i] >= iv and (crit or w == 2 or dmg >= _flash_big_ratio * han_max[i] or dmg <= 0.0):
			flash_tick[i] = gt
			hit_tick[i] = gt
			hit_w[i] = w
	elif gt - flash_tick[i] >= _flash_min_iv:
		flash_tick[i] = gt                       # 같은 적 재플래시 최소 12틱(오라·장판 연속 틱 깜빡임 방지)
		hit_tick[i] = gt
		hit_w[i] = w
	if dmg > 0.0 and ((w == 2 and _w_heavy_always and big[i] == null) or dmg >= _freeze_ratio * han_max[i] or crit):   # 큰 몸은 중량도 조건부(경직 잠금 방지)
		freeze_until[i] = maxi(freeze_until[i], gt + 1 + _w_freeze[w])
	var massf: float = sp_massf[species[i]]
	if kb_px > 0.0 and massf > 0.0 and (dirx != 0.0 or diry != 0.0) and ai_m[i] != Mv.ATTACH:
		var dist: float = kb_px * massf
		if pullil:
			dist *= _kb_giseak
		if gt - kb_last[i] < _kb_dr_window:
			dist *= _kb_dr_mult
		if gt - kb_win_t[i] >= 30:
			kb_win_t[i] = gt
			kb_used[i] = 0.0
		dist = minf(dist, _kb_cap_px - kb_used[i])
		if dist >= 0.5:
			kb_used[i] += dist
			var l: float = sqrt(dirx * dirx + diry * diry)
			kbx[i] = dirx / l * dist
			kby[i] = diry / l * dist
			kb_s[i] = 0.0
			kb_t[i] = 0
			kb_last[i] = gt
			_add_dust(px[i], py[i], kbx[i] / dist, kby[i] / dist)
			return
	if dirx != 0.0 or diry != 0.0:
		nudge_tick[i] = gt                       # 넉백 없는 타격: 렌더 넛지(경 1px 2틱 / 중·중량 2px 3틱)
		var a: int = int(roundf(atan2(diry, dirx) / (PI / 4.0))) & 7
		nudge_d[i] = a
		hit_w[i] = w


## 시각 몸 높이(px): 이펙트 기준점(스파크 = 발 − 몸 높이/2, 숫자 = 발 − 몸 높이 − 4).
func body_h_of(slot: int) -> int:
	if slot < 0 or slot >= CAPACITY or (flags[slot] & F_ALIVE) == 0:
		return 24
	return sp_body_h[species[slot]] * maxi(1, rscale[slot])


## 히트스톱·일시정지 프레임: prev = cur 로 동결(run.gd).
func freeze_prev() -> void:
	for k in active_count:
		var i: int = active[k]
		ppx[i] = px[i]
		ppy[i] = py[i]


# ─── 렌더(R4, run.gd 가 호출) ──────────────────────────────────────────

func render(alpha: float) -> void:
	var gt: int = Game.anim_tick_cur
	var adt: float = Game.anim_dt
	var at: float = Game.anim_time()
	var fmode: int = Juice.enemy_flash_mode
	for s in sp_count.size():
		sp_count[s] = 0
		sp_count_front[s] = 0
		sp_mat[s].set_shader_parameter("anim_time", at)
		var tr: StringName = sp_tier[s]
		var fm: int = fmode
		if tr == K.TIER_ELITE or tr == K.TIER_MBOSS or tr == K.TIER_BOSS:
			fm = 1 if fmode == 0 else fmode        # 큰 몸은 외곽선 플래시(온몸 한지 치환 = 그림이 선화로 보이는 문제)
		elif tr == &"chaser":
			fm = 2                                 # 저승사자·손님(비적대): 피격 틴트 없음
		sp_mat[s].set_shader_parameter("flash_mode", fm)
	_send_crowd_base()
	var smm: MultiMesh = _shadow_mm.multimesh
	if smm.instance_count < active_count:
		var cap: int = smm.instance_count
		while cap < active_count:
			cap *= 2
		smm.visible_instance_count = -1
		smm.instance_count = cap
	var sn: int = 0
	var seq0: int = _toechi_seq[0]
	var seq1: int = _toechi_seq[0] + _toechi_seq[1]
	# y-sort: 보간·정수화한 발 y 로 counting sort(O(n)) → 그 순서로 인스턴스를 채운다(인스턴스 순서 = 그리기 순서).
	var ply: float = 1.0e9
	var plx: float = 0.0
	if Game.player != null:
		# Player 타입을 참조하지 않는다(EnemyManager↔Player 순환 참조 → 종료 시 스크립트 누수)
		var rp: Variant = Game.player.get("render_pos")
		ply = (rp as Vector2).y if rp is Vector2 else Game.player.global_position.y
		plx = (rp as Vector2).x if rp is Vector2 else Game.player.global_position.x
	_ysort(alpha, ply)
	var crowd_unhide: bool = active_count >= _crowd_unhide_n
	var bar_n: int = 0
	var bar_cap: int = _bar_buf.size() / 4
	for kk in active_count:
		var i: int = _ys_order[kk]
		var f: int = flags[i]
		if (f & F_HIDDEN) != 0:
			continue
		var s: int = species[i]
		var kyf: float = float(_ys_key_y(i, alpha))
		var front: bool = kyf > ply
		# 가림 창(design/18 §1.4): 무당 몸(발 아래 몸 높이+2px·좌우 22px) 위에 겹치는 앞줄 잡귀는 뒤 MultiMesh 로 — 적 수와 무관하게 늘
		if front and crowd_unhide and big[i] == null and kyf - ply < float(sp_body_h[s]) + 2.0 and absf(lerpf(ppx[i], px[i], alpha) - plx) < 22.0:
			front = false
		# 큰 적(중간보스·보스) 몸 안에 무당이 들어가면 큰 적을 뒤로 — 거대한 몸이 무당을 통째로 가리던 문제(리뷰 11-24 t2000_boss 20:35)
		if front and big[i] != null:
			var bbh: float = float(sp_body_h[s] * maxi(1, rscale[i]))
			if kyf - ply < bbh and absf(lerpf(ppx[i], px[i], alpha) - plx) < bbh * 0.5:
				front = false
		var mm: MultiMesh = (sp_mm_front[s] if front else sp_mm[s]).multimesh
		var idx: int = sp_count_front[s] if front else sp_count[s]
		if idx >= mm.instance_count:
			_grow(s, idx + 1, front)
			mm = (sp_mm_front[s] if front else sp_mm[s]).multimesh
		if front:
			sp_count_front[s] = idx + 1
		else:
			sp_count[s] = idx + 1
		var bits: float = 0.0
		if (f & F_PULLIL) != 0:
			bits += 1.0
			# 조임 단계(매듭 잠금 누적 1 / 3 / 6, combat_core han.knot_glyph_stages)
			var z: int = zoim[i]
			var stage: int = 0 if z < 1 else (1 if z < 3 else (2 if z < 6 else 3))
			bits += 128.0 * float(stage)
			if stage == 3 and bar_n < bar_cap:
				_bar_buf[bar_n * 4] = K.rnd(lerpf(ppx[i], px[i], alpha))
				_bar_buf[bar_n * 4 + 1] = K.rnd(lerpf(ppy[i], py[i], alpha)) - float(sp_body_h[s]) - 7.0
				_bar_buf[bar_n * 4 + 2] = -1.0
				_bar_buf[bar_n * 4 + 3] = 0.0
				bar_n += 1
		if (f & F_WONGWI) != 0:
			bits += 4.0
		if (f & F_TOECHI_BURST) != 0:
			bits += 8.0
			if (f & F_CHILD) != 0:
				bits += 2.0                          # 아이 변형: 붉은 파열 대신 먹빛(07 2.8 예외)
		if (f & F_GRACE) != 0:
			bits += 16.0
		var rx: float = K.rnd(lerpf(ppx[i], px[i], alpha))
		var ry: float = K.rnd(lerpf(ppy[i], py[i], alpha))
		var cols: int = sp_cols[s]
		var frame: int = 0
		var dy: int = pose_dy[i]
		var dx: int = 0
		var fl: int = 0
		var fl_tick0: bool = false        # 피격 첫 틱: 흰 무구도 온몸 한지 임팩트 1장(그 뒤 틱만 외곽선)
		var dis: float = 0.0
		var oy: float = 0.0
		var ox: float = 0.0
		var shw: int = sp_shadow[s].x
		var frozen: bool = Game.game_tick < freeze_until[i]
		var age: int = Game.game_tick - spawn_tick[i]
		if (f & F_DYING) != 0:
			var e: int = gt - die_tick[i]
			if (f & F_TOECHI_BURST) != 0:
				frame = int(floorf(fposmod(aph[i], 1.0) * cols))
				if e < seq0:
					fl = 1
				elif e < seq1:
					fl = 2
					dy = -1
					dx = 1
				else:
					fl = 3
					dy = -2
					dx = 1
			else:
				# 해원 = 상승: move f0 홀드, 6틱마다 −1px, 디졸브(반투명 없음). 그림자는 제자리에서 줄어든다
				var tot: int = HAEWON_TICKS_ELITE if (f & F_ELITE_PLUS) != 0 else HAEWON_TICKS
				if (f & F_VANISH) != 0:
					tot = 9                              # vanish(): 짧은 디졸브만
				var rise: int = e / _haewon_rise_every
				oy = -float(rise) if tot > 9 else 0.0
				shw = maxi(2, shw - rise * 2)
				dis = clampf(float(e) / float(tot), 0.0, 1.0)
		else:
			if frozen:
				bits += 32.0
			else:
				var sp2: float = vx[i] * vx[i] + vy[i] * vy[i]
				if sp2 >= _still_v * _still_v:
					var ratio: float = clampf(sqrt(sp2) / maxf(speed[i], 1.0), _ratio_min, _ratio_max)
					aph[i] += adt * sp_fps[s] * arate[i] * ratio / float(cols)
			var vmov: bool = vx[i] * vx[i] + vy[i] * vy[i] >= _still_v * _still_v or kb_t[i] >= 0
			frame = int(floorf(fposmod(aph[i], 1.0) * cols)) if vmov else 0
			var fe: int = gt - flash_tick[i]
			if fe >= 0 and fe < _flash_ticks:
				fl = 1                                   # 단색 한지 #e9dcc0(일반 피격)
				fl_tick0 = fe == 0
				if fe >= 1 and (f & F_WHITE_FLASH) == 0:
					fl = 3                               # 붉은 무구 2틱째: jk-hi #e4604f 단색 잔광 — '베였다'(design/18 §1.6)
			var he: int = gt - hit_tick[i]
			var sq: int = _w_squash[hit_w[i]]
			if he >= 0 and he < sq:
				dy += 2 if hit_w[i] > 0 else 1
				dx = 1
			elif he >= sq and he < sq + 3:
				dy += 1
			elif kb_t[i] >= 0:
				dy += 1
			if kb_t[i] >= 0 and fl == 0:
				bits += 64.0                             # 넉백 7틱 동안 외곽선 #c8322d 틴트(플래시 2틱 뒤, 밀려난 개체 추적)
			var ne: int = gt - nudge_tick[i]
			if ne >= 0 and ne < _w_nudge_t[hit_w[i]]:
				var nd: Vector2 = DIR8[nudge_d[i] & 7] * float(_w_nudge_px[hit_w[i]] if ne == 0 else 1)
				ox = nd.x
				oy = nd.y
			# 예고 중 웅크림(돌진·비틀·조준 windup): 1px 눌림 — 몸으로도 '곧 온다'를 읽게
			if ai_s[i] == S_WIND and big[i] == null:
				dy -= 1
				if ((gt / 4) & 1) == 0:
					ox += 1.0 if ai_vx[i] < 0.0 else -1.0
			# 등장 솟음(07 4.2 Spawning 0.4초): 발부터 위로 드러남
			if age < intro_ticks[i]:
				dis = -1.0 + float(age) / float(intro_ticks[i])
				shw = maxi(2, int(float(shw) * float(age) / float(intro_ticks[i])))
			# 정예 체력바(화면 안, 32px, 35% 눈금)
			if (f & F_ELITE_PLUS) != 0 and (f & F_PASS) == 0 and bar_n < bar_cap and sp_tier[s] != K.TIER_BOSS and sp_tier[s] != K.TIER_MBOSS \
					and han[i] < han_max[i] and absf(rx - plx) < 360.0 and absf(ry - ply) < 220.0:
				_bar_buf[bar_n * 4] = rx
				_bar_buf[bar_n * 4 + 1] = ry - float(sp_body_h[s] * maxi(1, rscale[i])) - 8.0
				_bar_buf[bar_n * 4 + 2] = han[i] / maxf(han_max[i], 1.0)
				_bar_buf[bar_n * 4 + 3] = 1.0 if (f & F_PULLIL) != 0 else 0.0
				bar_n += 1
		var cap2: Vector2i = sp_cap[s]
		dy = clampi(dy, -4, 4) if big[i] != null else clampi(dy, -cap2.x, cap2.x)
		dx = clampi(dx, -cap2.y, cap2.y)
		var fc: int = facing[i]
		if fc == K.Dir.NORTH and sp_no_n[s] == 1:
			fc = K.Dir.WEST if vx[i] < 0.0 else K.Dir.EAST     # N 행 없는 종(대귀·도깨비): 등 돌림 대신 옆모습
		var xcode: float = float(mini(frame, 7) + 8 * K.DIR_ROW[fc] + (32 if fc == K.Dir.WEST else 0))
		if fl > 0 and (f & F_WHITE_FLASH) != 0 and (f & F_DYING) == 0 and not fl_tick0:
			bits += 512.0                                # 백 무구 피격 2틱째부터: 셰이더가 외곽선만 한지로(몸 전체 흰 덩어리 방지). 틱0 은 온몸 임팩트. 최대 1023
		var zcode: float = float(fl + 4 * (dy + 4) + 36 * (dx + 2))
		var sc: float = float(maxi(1, rscale[i]))
		mm.set_instance_transform_2d(idx, Transform2D(0.0, Vector2(sc, sc), 0.0, Vector2(rx + ox, ry + oy)))
		mm.set_instance_custom_data(idx, Color(xcode, bits, zcode, dis))
		if (f & F_TOECHI_BURST) == 0 or gt - die_tick[i] < seq1:
			smm.set_instance_transform_2d(sn, Transform2D(0.0, Vector2(rx, ry)))
			smm.set_instance_custom_data(sn, Color(float(shw) * sc, float(sp_shadow[s].y), 0.0, 0.0))
			sn += 1
	for s in sp_count.size():
		sp_mm[s].multimesh.visible_instance_count = sp_count[s]
		sp_mm_front[s].multimesh.visible_instance_count = sp_count_front[s]
	smm.visible_instance_count = sn
	_dust_node.queue_redraw()
	if hazards != null:
		hazards.call("set_bars", _bar_buf, bar_n)
	_overlay.queue_redraw()


## 무리 층 상시 배율(일반·미니언 머티리얼만). 설정 '무리 어둡게' 끔(Juice.crowd_dim_scale 0)이면 1.0.
func _send_crowd_base() -> void:
	var scale_v: Variant = Juice.get(&"crowd_dim_scale")
	var base: float = _crowd_base
	if scale_v != null and float(scale_v) <= 0.0:
		base = 1.0
	if base == _crowd_base_sent and sp_mat.size() == _crowd_base_n:
		return
	_crowd_base_sent = base
	_crowd_base_n = sp_mat.size()
	var n: int = mini(sp_mat.size(), sp_tier.size())
	for s in n:
		var tr: StringName = sp_tier[s]
		if tr == K.TIER_COMMON or tr == K.TIER_MINION:
			sp_mat[s].set_shader_parameter("crowd_base", base)


func _draw_overlay() -> void:
	if hazards != null:
		hazards.call("draw_overlay", _overlay)


func _add_dust(x: float, y: float, dx: float, dy: float) -> void:
	_dust_x[_dust_head] = x
	_dust_y[_dust_head] = y
	_dust_dx[_dust_head] = dx
	_dust_dy[_dust_head] = dy
	_dust_t[_dust_head] = Game.anim_tick_cur
	_dust_head = (_dust_head + 1) % DUST_CAP


## 외부(bigs): 발밑 먼지(돌진 착지·내려찍기).
func add_dust(p: Vector2, dir: Vector2) -> void:
	var d: Vector2 = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	_add_dust(p.x, p.y, d.x, d.y)


const _DUST_COL: Array[Color] = [Color("#7c674b"), Color("#5e4b36"), Color("#433426")]


## 먼지: 넉백 시작 지점 발밑에서 밀린 반대쪽으로 2~3개, 2틱마다 1px 퍼지고 10틱 뒤 소멸(알파 없음, 색 단계만).
func _draw_dust() -> void:
	var now: int = Game.anim_tick_cur
	for k in DUST_CAP:
		var e: int = now - _dust_t[k]
		if e < 0 or e >= DUST_TICKS:
			continue
		var bx: Vector2 = K.rndv(Vector2(_dust_x[k], _dust_y[k]) - Vector2(_dust_dx[k], _dust_dy[k]) * 4.0)
		var sp: float = float(1 + e / 3)
		var side: Vector2 = Vector2(-_dust_dy[k], _dust_dx[k])
		var col: Color = _DUST_COL[mini(e / 4, 2)]
		var sz: Vector2 = Vector2(2, 2) if e < 5 else Vector2(1, 1)
		_dust_node.draw_rect(Rect2(K.rndv(bx + side * sp), sz), col)
		_dust_node.draw_rect(Rect2(K.rndv(bx - side * sp), sz), col)
		if e < 6:
			_dust_node.draw_rect(Rect2(K.rndv(bx - Vector2(_dust_dx[k], _dust_dy[k]) * sp + Vector2(0, -1)), Vector2(1, 1)), col)


func _ys_key_y(i: int, alpha: float) -> int:
	return int(K.rnd(lerpf(ppy[i], py[i], alpha)))


## 활성 적을 발 y(정수) 오름차순으로 _ys_order 에 채운다. 범위가 YSORT_RANGE 를 넘으면 플레이어 기준 창으로 자른다.
func _ysort(alpha: float, ply: float) -> void:
	if _ys_order.size() < CAPACITY:
		_ys_order.resize(CAPACITY)
		_ys_key.resize(CAPACITY)
		_ys_cnt.resize(YSORT_RANGE + 1)
	if active_count == 0:
		return
	var ymin: int = 1 << 30
	var ymax: int = -(1 << 30)
	for k in active_count:
		var y: int = _ys_key_y(active[k], alpha)
		_ys_key[k] = y
		ymin = mini(ymin, y)
		ymax = maxi(ymax, y)
	if ymax - ymin >= YSORT_RANGE:
		var c: int = int(ply) if ply < 1.0e8 else (ymin + ymax) / 2
		ymin = c - YSORT_RANGE / 2
	_ys_cnt.fill(0)
	for k in active_count:
		var b: int = clampi(_ys_key[k] - ymin, 0, YSORT_RANGE - 1)
		_ys_key[k] = b
		_ys_cnt[b + 1] += 1
	for b in YSORT_RANGE:
		_ys_cnt[b + 1] += _ys_cnt[b]
	for k in active_count:
		var b2: int = _ys_key[k]
		_ys_order[_ys_cnt[b2]] = active[k]
		_ys_cnt[b2] += 1


func _grow(s: int, need: int, front: bool = false) -> void:
	var mm: MultiMesh = (sp_mm_front[s] if front else sp_mm[s]).multimesh
	var cap: int = mm.instance_count
	while cap < need:
		cap *= 2
	mm.visible_instance_count = -1
	mm.instance_count = cap   # 버퍼 재생성(드묾). 이번 프레임에 다시 채운다.
	mm.visible_instance_count = 0


# ─── bigs 가 쓰는 쓰기 창구(다른 스크립트에서 Packed 배열 원소를 직접 쓰면 배열 전체 복사가 일어난다) ───

func set_move(i: int, mode: int, sp_px: float, tx: float = 0.0, ty: float = 0.0) -> void:
	ai_m[i] = mode
	ai_sp[i] = sp_px
	ai_x[i] = tx
	ai_y[i] = ty


func set_vel_dir(i: int, dir: Vector2) -> void:
	var d: Vector2 = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	ai_vx[i] = d.x
	ai_vy[i] = d.y


func set_timer(i: int, t: float) -> void:
	ai_t[i] = t


func set_flag(i: int, bit: int, on: bool) -> void:
	if on:
		flags[i] |= bit
	else:
		flags[i] &= ~bit


func set_pos(i: int, p: Vector2, snap: bool = true) -> void:
	px[i] = p.x
	py[i] = p.y
	if snap:
		ppx[i] = p.x
		ppy[i] = p.y


func set_han(i: int, h: float, hmax: float = -1.0) -> void:
	if hmax > 0.0:
		han_max[i] = hmax
	han[i] = h


func set_stat(i: int, key: StringName, v: float) -> void:
	match key:
		&"speed":
			speed[i] = v
		&"contact":
			contact[i] = v
		&"cmult":
			cmult[i] = v
		&"smult":
			smult[i] = v
		&"dtaken":
			dtaken[i] = v
		&"radius":
			radius[i] = v
		&"pullil_t":
			pullil_t[i] = v
		&"contact_cd":
			contact_cd[i] = v
		&"ai_dir":
			ai_dir[i] = v


func set_visual(i: int, scale_i: int, p_dy: int) -> void:
	rscale[i] = clampi(scale_i, 0, 4)
	pose_dy[i] = p_dy


func set_big(i: int, ctl: Object) -> void:
	big[i] = ctl


func freeze(i: int, ticks: int) -> void:
	freeze_until[i] = maxi(freeze_until[i], Game.game_tick + ticks)


func enter_pullil_now(i: int) -> void:
	if is_alive(i) and (flags[i] & F_PULLIL) == 0:
		_enter_pullil(i)


## 외부(bigs) 퇴치/해원 확정: cause 를 지정(엄폐·대접 등).
func kill_now(i: int, kind: StringName, cause: StringName) -> void:
	if is_alive(i):
		han[i] = 0.0
		_kill(i, kind, cause)


## 일반 잡귀 밀어내기 파동(페이즈 전환 포효 등, 피해 없음).
func push_commons(c: Vector2, r: float, dist: float) -> void:
	var n: int = query_circle(c, r, _scratch)
	for k in n:
		var j: int = _scratch[k]
		if (flags[j] & F_ELITE_PLUS) != 0:
			continue
		var d: Vector2 = Vector2(px[j], py[j]) - c
		if d.length_squared() < 0.01:
			d = Vector2.RIGHT
		var dn: Vector2 = d.normalized()
		kbx[j] = dn.x * dist
		kby[j] = dn.y * dist
		kb_s[j] = 0.0
		kb_t[j] = 0
		kb_last[j] = Game.game_tick


## 원 안 일반 잡귀에 피해(두억시니 내려찍기: 한 하한 floor_han). 신호 없이 한만 깎는다(적끼리 피해는 결말을 내지 않음).
func damage_commons(c: Vector2, r: float, dmg: float, floor_han: float, stun_ticks: int = 0) -> void:
	var n: int = query_circle(c, r, _scratch)
	for k in n:
		var j: int = _scratch[k]
		if (flags[j] & F_ELITE_PLUS) != 0:
			continue
		han[j] = maxf(floor_han, han[j] - dmg)
		hit_tick[j] = Game.game_tick
		flash_tick[j] = Game.game_tick
		hit_w[j] = 1
		if stun_ticks > 0:
			freeze_until[j] = maxi(freeze_until[j], Game.game_tick + stun_ticks)
		if (flags[j] & F_PULLIL) == 0 and han[j] <= Game.pullil_threshold * han_max[j]:
			_enter_pullil(j)


## 원 안 일반 잡귀를 정해진 점으로 끌어당김(거구귀 흡입). 반환: 입(mouth) 반지름 안에 든 수(삼킴 후보는 out 에).
func pull_commons(c: Vector2, dir: Vector2, half_ang: float, rng: float, pull_px: float, mouth_r: float, out: PackedInt32Array) -> int:
	var n: int = query_circle(c, rng, _scratch)
	var m: int = 0
	var ca: float = cos(half_ang)
	for k in n:
		var j: int = _scratch[k]
		if (flags[j] & F_ELITE_PLUS) != 0:
			continue
		var d: Vector2 = Vector2(px[j], py[j]) - c
		var dl: float = d.length()
		if dl < 0.01:
			continue
		if d.dot(dir) / dl < ca:
			continue
		var step: float = minf(pull_px, dl)
		px[j] -= d.x / dl * step
		py[j] -= d.y / dl * step
		if dl <= mouth_r and m < out.size():
			out[m] = j
			m += 1
	return m


## 특정 일반 잡귀의 속도 배율(대귀 돌격 명령·광폭).
func set_minion_smult(parent: int, mult: float) -> void:
	for k in active_count:
		var j: int = active[k]
		if ai_link[j] == parent and (flags[j] & F_ELITE_PLUS) == 0:
			smult[j] = mult


func minions_of(parent: int) -> int:
	var c: int = 0
	for k in active_count:
		var j: int = active[k]
		if ai_link[j] == parent and (flags[j] & (F_ELITE_PLUS | F_DYING)) == 0:
			c += 1
	return c


# ─── 디버그 ────────────────────────────────────────────────────────────

func debug_spawn_ring(count: int, species_id: StringName = &"enm_dalgyal_gwisin") -> void:
	if Game.player == null:
		return
	var pp: Vector2 = Game.player.global_position
	for n in count:
		var ang: float = TAU * float(n) / float(count)
		var r: float = Rng.range_s(&"spawn", 8.0, 14.0) * K.UNIT_PX
		spawn(species_id, pp + Vector2(cos(ang), sin(ang)) * r)


func debug_force_pullil() -> void:
	for k in active_count:
		var i: int = active[k]
		if (flags[i] & (F_PULLIL | F_DYING | F_NO_PULLIL | F_PASS)) == 0:
			han[i] = minf(han[i], han_max[i] * Game.pullil_threshold)
			_enter_pullil(i)
