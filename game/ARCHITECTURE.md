# 넋길: 해원굿 — 게임 아키텍처 계약 (game/)

> 엔진 **Godot 4.7.2 / GDScript / gl_compatibility**. 기준 뷰포트 **640×360**, 창 1920×1080(×3 정수 배율).
> 이 문서는 병렬 에이전트 작업의 **계약**이다. 파일 경계(§5 소유표)·신호(§3)·API 시그니처(§2)를 바꾸려면 리드(core) 승인 후 이 문서를 먼저 고친다.
> 기획 정본: `../design/` (01 캐논, 14 기술 §3), 수치 정본: `../data/*.json` (읽기 전용 원본 → `game/data/` 사본).

---

## 0. 한눈에

```
main.tscn (화면 라우터) ─ title.tscn ─(첫 실행: 초굿 직행 / 이후: 신당)→ sindang_lobby.tscn → run.tscn ─stage_finished·사망→ result.tscn → 신당(Save.lobby_route()) 또는 title
run.tscn
 ├ World (Node2D, y-sort 없음, 그리기 순서 = 자식 순서)
 │  Ground · Gilbe · Ring · Pickups · Enemies · Yeongga · Player · Weapons · Projectiles · Vfx · DamageNumbers
 ├ Camera (GameCamera: 플레이어 추적 + Juice.shake_offset)
 ├ Systems: SpawnDirector · TrialDirector · HaewonSystem · HitFeedback
 ├ PostLayer (CanvasLayer 5): ScreenFx(오컬트 후처리 ColorRect)
 ├ HUDLayer (CanvasLayer 10): HUD
 └ OverlayLayer (CanvasLayer 20): LevelUp · PauseMenu
```

* **시뮬레이션(L1/L2)** 은 `run.gd._physics_process` 가 60Hz 고정 틱으로 순서대로 호출한다(§4). 노드 `_process` 에 게임 규칙을 넣지 않는다.
* **연출(L3: vfx/audio/ui)** 은 `Events` 신호를 구독만 한다. 구독자는 시뮬레이션 상태를 바꾸지 않는다.
* 적·투사체·구슬·이펙트는 **노드가 아니라 SoA 배열**(Packed*Array) + 풀. 그리기는 MultiMesh 또는 `_draw` 일괄.

---

## 1. 폴더 구조

```
game/
├ project.godot            오토로드·뷰포트·입력 기본값 (core)
├ ARCHITECTURE.md          이 문서 (core)
├ autoload/                오토로드 싱글턴 (§2)
├ core/                    k.gd(상수·예약색·열거), sprite_lib.gd(스프라이트 로더+플레이스홀더)
├ scenes/                  main.tscn / main.gd (화면 라우터)
├ run/                     run.tscn / run.gd(틱 순서), game_camera.gd, ground.gd
├ player/                  player.tscn/gd(이동·4방향 애니), player_hit.gd(피격·무적), player_bot.gd(--autotest 봇)
├ enemies/                 enemy_manager.gd (SoA + 해시 + MultiMesh + 피해 해석)
├ pickups/                 pickup_manager.gd (원혼 구슬 SoA + 흡인)
├ weapons/                 weapon_manager.gd, weapon_base.gd, archetype_registry.gd, damage_calc.gd
│  └ archetypes/           arch_{projectile,melee_arc,orbit,aura,drop_zone,trail,beam,summon}.gd
├ projectiles/             projectile_pool.gd (아군/적 탄 SoA)
├ haewon/                  haewon_system.gd(살기·신명·원귀 문턱), yeongga_train.gd, gilbe_trail.gd, ring_closure.gd
├ deities/                 trial_director.gd (시련 스케줄·게이지·합일)
├ waves/                   spawn_director.gd (waves_stage1.json 타임라인)
├ ui/                      hud, levelup, pause_menu, result, title (.tscn+.gd), widgets/, theme/main_theme.tres
├ meta/                    sindang_lobby.tscn/gd (신당 로비)
├ audio/                   (audio 담당: 장단 음악 레이어 스크립트 자리)
├ vfx/                     vfx_player.gd, vfx_lib.gd, damage_numbers.gd, hit_feedback.gd, screen_fx.gd, screen_post_fx.gd,
│                          atmosphere.gd(조명 소품·한지 재·향 연기·밀도 감광 — VfxPlayer 자식, 소품 z −6 / 파티클 z 6)
├ shaders/                 white_outline, hit_flash, dissolve, enemy_instanced, occult_post, yeongga, vfx_hanji_ribbon
├ data/                    ../data 사본 (tools/sync_data.sh) — 직접 수정 금지
├ assets/                  ../art 사본 (tools/sync_art.py) + 오디오·폰트 — §6
├ tests/                   (헤드리스 테스트 스크립트 자리)
└ captures/                --write-movie 캡처·로그 (.gdignore, git 제외)
```

---

## 2. 오토로드 API

등록 순서(의존 순서): `Data → AssetCache → Rng → Events → Game → Beat → Juice → Audio → Save → DebugTools`.

### Data (`autoload/data.gd`, core)
```gdscript
signal reloaded
var tables: Dictionary            # "weapons", "tech/perf_budgets", "narrative/cast_canon" … -> Variant
var aliases: Dictionary           # canon_ids.json aliases: old_id -> new_id
func load_all() -> void
func table(key: String) -> Variant
func get_value(key: String, path: String, default: Variant = null) -> Variant   # path "hitstop.budget_ms"
func num(key: String, path: String, default: float = 0.0) -> float
func resolve_id(id: String) -> String                # 별칭 해석(체인 허용)
func weapon(id) / evolution(id) / union(id) / passive(id) / character(id) / enemy(id) / deity(id) -> Dictionary
func weapon_ids() / character_ids() / deity_ids() -> Array
func is_v1(def: Dictionary) -> bool                  # v1 범위 필터
```
`enemy(id)` 는 enemies/minions/elites/midbosses/bosses/chasers 를 한 사전으로 합친다.

### Game (`autoload/game.gd`, core) — 런 상태 · 이중 시계 · 일시정지 · 히트스톱
```gdscript
enum State { BOOT, TITLE, LOBBY, RUN, RESULT }
var game_tick: int     # 시뮬레이션 시계: 일시정지·점지·히트스톱에서 멈춤
var beat_tick: int     # 박 시계: 히트스톱 중에도 흐름(= game_tick + hitstop_ticks_total)
var sim_speed: int     # 프레임당 틱 수(F1, --speed)
var state: State; var run_active: bool; var char_id: StringName; var hitstop_remaining: int; var hitstop_ticks_total: int
var level, xp, xp_next, hp, hp_max, kills_toechi, kills_haewon, salgi, sinmyeong, sinmyeong_oreum, cur_neok, stats, pullil_threshold
var debug_invuln: bool; var autotest: bool; var autotest_quit_sec: float
var player_dead: bool  # run.gd 사망 연출 중 true → add_xp 무시(사망 애니 위 점지 방지). reset_run 에서 false, sim_speed 도 1 로
# 서비스 참조(run.gd 가 채움, 런 밖에서는 null): run_root, world, player, enemies, projectiles, weapons, pickups, vfx, camera
func time_sec() -> float ; func beat_sec() -> float
func is_sim_paused() -> bool ; func is_hitstop() -> bool
func push_pause(reason: StringName) ; func pop_pause(reason: StringName) ; func has_pause(reason) -> bool
func advance_tick() -> bool                       # run.gd 전용
func request_hitstop(ms: int) -> int              # 예산: 10초 창 400ms(combat_core.hitstop), 실제 적용 ms 반환
func set_sim_speed(s: int)
func reset_run(char_id) ; func begin_run() ; func end_run(victory: bool, extra := {})
func stat(id: StringName, default := 0.0) -> float
func xp_required(lv: int) -> float ; func add_xp(amount: float)   # 곡선 c0+c1·l+c2·l² + (L>c3_from) c3·(L−c3_from)³ (combat_core.xp)
func set_fullscreen(on: bool, save_pref := true) ; func is_fullscreen() -> bool   # Alt+Enter·F11(릴리스 포함). 저장 Save "settings.display_fullscreen"
func quit_game(code := 0)                         # 앱 종료는 반드시 이것으로(오디오 정리 후 종료)
func clear_services()                             # run.gd _exit_tree 전용
```
시작 시 창: 저장된 선호 → 없으면 640×360 의 정수배(작업 영역 안, 보통 ×2=1280×720 — project.godot override 1280×720), ×2 도 안 들어가면 전체 화면. 헤드리스·`--write-movie`·`--resolution` 실행은 창을 건드리지 않는다.
창 닫기(X/Alt+F4)는 `auto_accept_quit = false` + `NOTIFICATION_WM_CLOSE_REQUEST` → `quit_game(0)` 으로 같은 경로를 탄다.
**일시정지는 `SceneTree.paused` 를 쓰지 않는다.** 이유별 스택(`&"menu"`, `&"levelup"`, `&"trial_intro"` …).

### Beat (`autoload/beat.gd`, core) — 장단 박 시계 + 발사 양자화(판정 없음)
```gdscript
var geori_id: StringName; var jangdan: StringName; var bpm: float; var grid_frac: float
var beat_index: int; var grid_index: int; var is_grid_tick: bool; var is_beat_tick: bool; var is_downbeat_tick: bool
var heung_mult: float                                 # 흥 가속(마디 경계에서만 변경)
func reset() ; func advance()                         # Game.advance_tick 내부에서 호출
func beat_len_sec() -> float ; func grid_sec() -> float ; func beat_phase() -> float
func effective_period(cooldown: float) -> float      # 쿨다운 하한(신명 시 0.25) 반영
func next_grid_time(t: float, downbeat := false) -> float
func request_fire(key: StringName, cooldown: float, downbeat := false) -> float   # 다음 발사 그리드 시각(박 시계 초)
func try_fire(key: StringName, cooldown: float, downbeat := false) -> bool        # 매 틱 호출, 그리드 경계에서만 true
func reset_weapon(key: StringName)
```
phase_carry: `on grid tick t: fire if t >= ideal_t and t >= last_fire_t + grid; ideal_t += P_eff; if t - ideal_t > grid: ideal_t = t + P_eff`.
거리(geori) 전환은 `waves_stage1.json geori[]` 시각 기준, 위상은 구간 시작 틱에서 다시 계산.

### Events (`autoload/events.gd`, core) — §3

### Juice (`autoload/juice.gd`, 구현 소유 vfx)
```gdscript
var trauma: float; var shake_scale: float; var flash_enabled: bool; var damage_numbers: Node
func add_trauma(amount: float) ; func screen_shake(amount: float)   # 0..1 누적, 제곱 응답, 실시간 감쇠
func shake_offset() -> Vector2                                     # GameCamera 가 매 프레임 더함
func hitstop(ms: int) -> int ; func hitstop_event(key: String) -> int   # combat_core.hitstop.events[key]
func flash(color: Color, alpha := 0.35, duration := 0.08) -> bool  # 초당 3회 상한. 백(#f2ece0)은 해원 전용
func damage_number(pos: Vector2, amount: float, kind := &"red")    # red white crit locked player heal
func feedback(tier: int, pos: Vector2, strength := 0.5)            # T0..T4 (combat_core.feedback_tiers)
func feedback_event(key: String, dir := Vector2.ZERO, trauma_override := -1.0) -> int   # EVENTS 표(킥·트라우마·히트스톱·플래시) 단일 경로
var crowd_dim: float                                               # 군중 밀도 감광(atmosphere 가 enemy_instanced 유니폼 crowd_dim 에 4Hz 로 씀)
func light_pulse(pos, radius_px, intensity, tone := 0, life_s := 0.6) -> int ; light_add/light_move/light_remove/light_frame  # 오컬트 후처리 광원(최대 24)
# 접근성(ui 설정이 씀): shake_scale, flash_scale, reduce_motion, enemy_flash_mode(0 단색/1 외곽선/2 끔), damage_number_mode(0 전부/1 치명·정예/2 끔), Game.hitstop_scale
```

### Audio (`autoload/audio.gd`, 구현 소유 audio)
버스 `Master > Music, SFX, UI, Ambience, Voice`.
```gdscript
func play_sfx(id: StringName, bus := &"SFX", volume_db := 0.0, pitch_var := 0.0)
func play_sfx_at(id: StringName, pos: Vector2, volume_db := 0.0)
func play_music(cue: StringName) ; func stop_music()
func set_bus_volume_linear(bus: StringName, v: float)
func shutdown()                                      # Game.quit_game 전용
var silent: bool                                     # 헤드리스·--write-movie 에서 true: 로드·풀 순환만, play() 생략
```
누락 에셋은 조용히 무시(verbose 로 1회 기록).
`silent` 이유: 엔진 `--quit-after N` 은 메인 루프 프레임 없이 트리를 해제한다. 정지한 playback 은 메인 루프의 AudioServer 갱신에서만 풀리므로
재생 중이던 Ogg 가 남아 "resources still in use at exit" 가 난다. 들리지 않는 자동화 모드에서는 재생 자체를 생략해 해결.

### Save (`autoload/save.gd`, 구현 소유 meta)
```gdscript
const PATH := "user://save_profile.json"   # 원자적 쓰기: .tmp → rename, .bak 보존
var profile: Dictionary; var loaded: bool
func default_profile() -> Dictionary ; func load_profile() -> Dictionary ; func save_profile() -> bool
func get_value(path: String, default = null) -> Variant ; func set_value(path: String, value)
```
스키마 `data/tech/save_profile.schema.json`, 기본값 `data/save_profile.example.json`.

### Rng (`autoload/rng.gd`, core) — 스트림별 결정론
스트림: `combat drop jeomji chest fx spawn mboss ai trial` (미등록 이름은 자동 생성).
```gdscript
func reseed(seed: int) ; func stream(name) -> RandomNumberGenerator
func randf_s(name) -> float ; func range_s(name, a, b) -> float ; func int_s(name, a, b) -> int
func chance(name, p) -> bool ; func pick_weighted_index(name, items: Array, weight_key := "weight") -> int
```
시뮬레이션 결과에 영향을 주는 난수는 해당 스트림, 연출 난수는 `&"fx"` 만.

### AssetCache (core) / DebugTools (core)
* `AssetCache`: SpriteLib/VfxLib 정적 캐시 저장소(`tex`, `atlas`, `fx`, `manifest`). `clear()`.
* `DebugTools`: 디버그 키·명령행(§8). `arg(name, default) -> String`.

### 정적 라이브러리
* `SpriteLib` (core/sprite_lib.gd): `tex(path)`, `dir_tex(entity_id, dir, fallback_px := 32)`, `anim_frames(entity_id, anim, dir) -> Array[Texture2D]`, `dir_atlas(entity_id, fallback_px := 32)`, `placeholder(key, size_px := 32)`, `dot(size_px, color, soft := false)`, `has_entity(id)`, `manifest()`, `clear_cache()`.
* `VfxLib` (vfx/vfx_lib.gd): `get_fx(fx_id) -> {texture, regions, fps, loop, pivot, size, placeholder}`, `parse_aseprite(json, tex)`, `clear_cache()`. 옛 `<id>__pilot` ID 는 `assets/vfx/<id>` 를 먼저, 없을 때만 `assets/pilot` 을 읽는다(코드의 `__pilot` 참조는 2026-11-24 모두 정식 ID 로 교체).
* `K` (core/k.gd): `UNIT_PX=32`(1u), `TICK_HZ=60`, `VIEW_W/H`, 예약색 `COL_BAEK #f2ece0`, `COL_JEOK #c8322d`, `COL_CHEONG #2a5caa`, `COL_HEUK`, `COL_MEOK #0e0b16`, `COL_HANJI #e9dcc0`, `COL_HWANG #e8b931` …, `KIND_TOECHI/KIND_HAEWON`, `TIER_*`, `DIRS`, `DmgColor`, `fmt_time()`.

### 런 서비스 API(모듈 간 호출 허용 목록)
| 서비스 | 공개 API |
|---|---|
| EnemyManager | `spawn(species, pos, opts := {}) -> handle`, `queue_hit(slot, dmg, color: int(K.DmgColor), crit := false, kb_dir := ZERO, kb_u := 0, source_slot := -1)`, `query_circle(pos, r, out, max_out := -1) -> n`, `nearest(pos, max_r, exclude_mask := F_DYING｜F_AUTO_TARGET_EXEMPT) -> slot`, `force_haewon(slot, cause := &"ring")`, `force_toechi(slot, cause := &"debug")`, `is_alive(slot)`, `is_hostile(slot, ranged := false)`, `pos_of/species_id_of/tier_of/handle_of/slot_of`, `alive_count_of(species)`, `clear_all()`, 읽기 전용 배열 `px py han flags`(플래그 `F_PULLIL` 등), `active_count`, `CAPACITY` |
| ProjectilePool | `spawn_player(weapon_slot, pos, vel, life_s, radius_px, damage, pierce, returning := false) -> int`, `spawn_enemy(pos, vel, life_s, radius_px, damage, kind := &"prj_wonhon_tan") -> int`, `clear_all()`, `alive_count` |
| PickupManager(+) | `find_special(kind, pos, r_px) -> int` |
| HaewonSystem | `cleanse_circle(pos, r_px, max_n) -> int`(살 알갱이 정화), `static jangdan_bonus() -> float`(신명 오름 −0.15, WeaponBase.cooldown 이 씀) |
| RingClosure | `contains(p) -> bool` — **ring_closed 핸들러 안에서만** 유효(`Game.run_root.ring`) |
| YeonggaTrain(+) | `try_substitute(source) -> bool` — PlayerHit.take_hit 의 substitute 단계가 호출(장판·hazard 제외) |
| Run | `trials`·`gilbe`·`yeongga`·`ring` 등 @onready 필드(봇·통합 읽기 전용). 종료는 `Events.stage_finished` 구독으로만 |
| Game(+) | `last_result: Dictionary` — 마지막 `end_run` 결과(= run_ended 사전, main.gd → 정산 화면 입력) |
| WeaponManager | `setup_character(id)`, `add_or_level(id) -> level`, `has_weapon/level_of/weapon_at/slot_count`, `offer_candidates() -> Array[Dictionary]` |
| PickupManager | `spawn_orb(pos, value)`, `clear_all()`, `count`, 읽기 전용 `px py alive`, `CAPACITY` |
| VfxPlayer | `play(fx_id, pos, rot := 0, scl := 1, opts := {}) -> int`, `stop(i)` (또는 `Events.vfx_request`) |
| GilbeTrail | `duration()`, `point(k)`, `time_at(k)`, `clear()`, `consume_keep_last(n)` |
| YeonggaTrain | `capacity()`, `lifetime()`, `count` |
| TrialDirector | `start_now()` |
| SpawnDirector | `ring_point() -> Vector2` |
| Player | `setup(char_id)`, `take_hit(amount, source)`, `hit.iframe_left`, `hit.heal(amount)`, `crowd_touching`, `vel`, `last_move_dir`, `facing`, `speed_mult_ext` |

---

## 3. 신호 목록 (`Events`)

규칙: **append-only** — 자기 모듈 구역 끝에만 추가. 기존 신호 이름·인자 변경은 리드 승인. 인자는 정적 타입, 적은 **핸들(int)** 로 넘긴다(노드 참조 금지).

| 구역 | 신호 |
|---|---|
| core | `run_started(char_id)`, `run_ended(result: Dictionary)`, `pause_changed(paused, reason)`, `hitstop_started(ms)`, `sim_speed_changed(speed)`, `debug_toggled(flag, on)` |
| beat | `beat(beat_index, is_downbeat)`, `grid_tick(grid_index)`, `geori_changed(geori_id, bpm, jangdan)` |
| combat | `weapon_fired(weapon_id, slot, pos)`, `weapon_added(weapon_id, slot)`, `weapon_leveled(weapon_id, level)`, `weapon_evolved(from_id, to_id)`, `enemy_hit(handle, species, pos, damage, color: int(K.DmgColor), crit, knot_locked)`, `player_damaged(amount, source, hp, hp_max)`, `player_healed(amount, hp, hp_max)`, `player_died()` |
| enemies | `pickup_collected(kind, value, pos)`, `enemy_pattern(handle, species, pattern, pos, telegraph_s)`, `box_opened(box_id, grade, results, bonus, pos)`, `enemy_spawned(handle, species, tier)`, `enemy_killed(handle, species, pos, kind, cause, tier)` — kind `&"toechi"｜&"haewon"`, cause `han_pa gyeoldan elite_last white ring saja debug`; `pullil_entered(handle, species, pos)`, `maetim_returned(handle, species, pos)`, `elite_spawned(handle, species)`, `boss_spawned(handle, species, form)`, `xp_collected(amount)`, `level_up(new_level)` |
| waves | `minute_changed(minute)`, `wave_event(event_id, params)`, `midboss_incoming(species)`, `boss_incoming(species)`, `wave_warn(event_id, in_sec, params)`, `ambient_changed(ambient, fade_sec)`, `daehaewon(bound, bonus_mult, centroid, haewon_count)`, `boss_resolved(handle, kind, n_final)`, `settlement_started(route, params)`, `settlement_progress(route, done, total, progress)`, **`stage_finished(result)`**(→ run.gd 종료) |
| haewon | `yeongga_joined(count, species)`, `yeongga_cheondo(count, reason)`, `gilbe_ready(closable)`, `ring_closed(area_tiles, haewon_count, centroid)`, `salgi_changed(value, delta)`, `wongwi_return(threshold)` (25/50/75), `sinmyeong_changed(value)`, `sinmyeong_oreum(active)` |
| deities | `trial_warn(slot, deity_id, in_sec)`, `trial_start(slot, deity_id)`, `trial_gauge_changed(slot, wieom, gaho)`, `trial_end(slot, deity_id, winner)` — winner `wieom｜gaho｜none`; `hapil_start(deity_ids)`, `possession_changed(deity_id, active)`, `debug_trial_now()`, `trial_phase_changed(slot, deity_id, phase)`, `trial_candidates(slot, left_id, right_id)`, `trial_resolved(slot, deity_id, face, complete)`, `gongsu_spoken(deity_id, trigger, text)`, `deity_power_gained(deity_id, power_id, level, grade)`, `hapil_call(deity_id, word, index)`, `hapil_complete(form_id, deity_ids)` |
| ui | `levelup_offer(choices)`, `levelup_chosen(choice)`, `hint_requested(hint_id)` |
| meta | `currency_changed(currency_id, value)`, `unlock_gained(unlock_id)`, `save_written(ok)` |
| audio | `music_cue(cue_id)` |
| vfx | `vfx_request(fx_id, pos, rot)` |
| tutorial | (design/17 §7.2) 로직 → ui: `tutorial_started(from_step, total)`, `tutorial_step_started(step_id, index, total, goal_text, sub_text)`(같은 id 재발신 = 목표·보조 줄만 교체), `tutorial_step_progress(step_id, done, need)`, `tutorial_help(step_id, level 1~4, sub_text)`, `tutorial_tag(text, hanja, world_pos)`, `tutorial_step_completed(step_id, name_label, hanja)`, `tutorial_card(step_id, card)`, `tutorial_finished(completed)`. ui → 로직 **요청**(L3 예외): `tutorial_ack(step_id)`, `tutorial_exit_requested(next)` — `real｜again｜title`, `tutorial_skip_step_requested()` |

---

## 4. 데이터 흐름과 고정 틱 순서

```
../data/*.json ──sync_data.sh──▶ game/data/ ──Data.load_all()──▶ Data.tables (+aliases)
../art/**      ──sync_art.py───▶ game/assets/ (+sprites/manifest.json) ──SpriteLib/VfxLib──▶ Texture
입력 ─▶ Player.sim_step ─▶ … 시뮬레이션(L1/L2) ─emit─▶ Events ─▶ vfx / audio / ui (L3)
```

`run.gd._sim_step(dt)` — **순서 고정**(design/14 §3.2.1). 각 모듈은 자기 `sim_*` 함수 안만 고친다.

| # | 호출 | 모듈 |
|---|---|---|
| 1·2 | `Game.advance_tick()` → `Beat.advance()` (히트스톱이면 시뮬 생략, 박은 진행) | core |
| 3 | `player.sim_step` 이동 | core |
| 4 | `gilbe.sim_record` 길베 샘플(4초 궤적) | haewon |
| 5 | `ring.sim_check` 길닦음 닫힘(1.5u 스냅, ≥9타일², 래스터+플러드필 일괄 해원) | haewon |
| 6 | `spawn.sim_step` 스폰 | waves |
| 6b | `trials.sim_step` 시련(03:00/06:30/12:30/15:30, 30초, 위엄/가호) · 18:00 합일 | deities |
| 7·8 | `enemies.sim_think_move` 사고·이동·분리 | enemies |
| 9 | `enemies.rebuild_hash` 공간 해시(셀 2u) | enemies |
| 10·12 | `weapons.sim_step` 무구 발사(Beat.try_fire)·오라·장판 | combat |
| 11 | `projectiles.sim_step` 투사체 이동·충돌 | combat |
| 13·14 | `enemies.resolve_hits` 피해 일괄 해석 → 퇴치/해원·풀릴 기색(한≤35%)·매듭 잠금 | enemies(규칙은 haewon 합의) |
| 15 | `yeongga.sim_step` 영가 행렬(최대 24, 30초) | haewon |
| 16 | `enemies.sim_contact_player` 접촉 피해 | enemies |
| 17 | `pickups.sim_step` 구슬 흡인·획득 | enemies |
| 18 | `haewon.sim_thresholds` 살기·원귀 회귀(25/50/75)·신명 | haewon |

피해 경로: 무구 `deal()` → `DamageCalc.roll()` → `EnemyManager.queue_hit()` → (틱 13) `resolve_hits()` → `Events.enemy_hit / enemy_killed / pullil_entered` → `HitFeedback`(vfx) 가 `Juice.feedback/damage_number/VfxPlayer.play` 호출.
무구 추가: `weapons.json` 레벨 테이블 + `archetype_registry.gd MAP` 한 줄. 원형 추가는 `archetypes/arch_<key>.gd`(WeaponBase 상속: `fire()`, `tick(dt)`, `draw(ci)`, 선택 `on_projectile_hit`).

---

## 5. 모듈 소유표 (병렬 작업 경계)

**자기 소유 파일만 수정한다.** 남의 파일에 필요한 변경은 (1) 신호 추가(자기 구역 append) (2) 공개 API 요청(소유자에게) (3) `# TODO(<module>):` 주석으로 남긴다.

| 모듈 키 | 소유 파일 | 책임 |
|---|---|---|
| **core** (리드) | `project.godot`, `ARCHITECTURE.md`, `autoload/{data,game,beat,events,rng,asset_cache,debug_tools}.gd`, `core/`, `scenes/`, `run/`, `player/`, `tests/`, `../tools/{sync_data.sh,sync_art.py,godot_check.sh}` | 틱 순서, 이중 시계, 입력, 데이터 로더, 에셋 규약, 봇 |
| **combat** | `weapons/**`, `projectiles/**` | 무구 20·진화·결합, 원형 8종, 피해 계산, Beat 양자화 사용, 넉백 |
| **enemies** | `enemies/**`, `pickups/**` | 적 AI(archetype), 정예·중간보스·보스·저승사자, 피해 해석, 드롭·구슬 |
| **waves** | `waves/**` | 스폰 디렉터, 타임라인(waves_stage1), 거리(geori) 전환 이벤트, 보스 등장 |
| **haewon** | `haewon/**` | 기색·매듭 규칙(EnemyManager 와 합의), 영가 행렬, 길베, 고리 닫기, 살 알갱이/살기/원귀 회귀, 신명 |
| **deities** | `deities/**` | 신령 시련 4회·게이지·빙의·권능·합일 |
| **ui** | `ui/**` | HUD, 레벨업 점지 3택, 일시정지, 결과(정산), 타이틀, 설정, 온보딩 힌트 |
| **meta** | `meta/**`, `autoload/save.gd` | 신당 로비, 메타 화폐, 해금, 세이브 이전 |
| **audio** | `audio/**`, `autoload/audio.gd`, `assets/sfx`, `assets/music` | 장단 음악 레이어(Beat 추종), SFX 매핑(feedback_matrix/audio_sfx) |
| **vfx** | `vfx/**`, `shaders/**`, `autoload/juice.gd`, `assets/vfx` | Juice 구현, 히트 피드백, 화면 효과, 오컬트 후처리 |

튜토리얼(design/17, 11-25): `tutorial/**`(디렉터·봇·문구·월드 표지)와 `scenes/main.gd` 의 `start_tutorial`/`_on_tutorial_exit`, Events tutorial 구역은 **tutorial_run** 이 만들었고 후속 소유는 ui·core 합의 전까지 **리드**. `ui/intro/**`·`ui/guidebook.gd`·`ui/tutorial_hud.gd` 는 ui. 다른 모듈의 최소 훅(모두 `Game.tutorial_mode` 가드): `Game.tutorial_mode`, `Run.jeomji_gate`·죽음 가드, `Save._on_run_started` 가드, `WeaponManager.drop_schedule`, `HaewonSystem.add_salgi`, `Player.set_bot`, guide·levelup·run_ledger·hud·pause_menu 가드.
연습 굿판은 실전 기록을 남기지 않는다: 판 수·`ui.runs`·`ui.hints_seen`·재화·넋기록·`flags.tutorial_done` 불변, `flags.practice_done`·`ui.practice_log` 만 쓴다.
연습 HUD 배치(가시성, 11-25 리드): 무당 발밑(화면 y≈180~200)부터 y≈275 까지는 비워 둔다 — 등불 줄은 위 '연습' 시계 양옆 5개씩(y=19), 목표 띠 y=H−80~H−64, 보조 줄 H−52·H−40(맨 아래 연속 굿 칩 H−34 위). 목표 묶음 밑에 무당·귀신이 들어오면 알파 0.4, 시련 중 단계 이름표는 목표 띠 자리(그동안 목표 묶음은 숨김).

예외(11-24 리드 승인): `ui/result.gd`(정산 결과 화면)는 meta 소유 — 환산 줄·3막 카드가 `Save.settlement_view()` 와 한 몸이라서. 나머지 `ui/**` 는 ui 소유 그대로.

공유 지점: `run/run.tscn` 노드 추가는 리드에게 요청(각 모듈은 자기 노드 하위만). `core/k.gd` 상수 추가는 append 허용(예약색 HEX 변경 금지).

---

## 6. 에셋 규약

| 종류 | 경로 | 비고 |
|---|---|---|
| 스프라이트 정지 4방향 | `assets/sprites/<entity_id>/{south,east,north,west}.png` | 런타임 4방향(D-11). 원본 8방향 대각선은 복사 안 함 |
| 걷기 | `assets/sprites/<entity_id>/walk_<dir>_<n>.png` | n = 0.. |
| 기타 애니 | `assets/sprites/<entity_id>/<anim>_<dir>_<n>.png` | |
| 새 규격 메타 | `assets/sprites/<entity_id>/anims.json` | **있으면 ART_STYLE v1 엔티티**(`spec: "art_style_v1"`). `canvas`·`pivot`(발)·`body_h`·`anims{<anim>:{<dir>:n}}`·선택 `atlas_cols{<anim>:[파일 번호…]}`(구 인덱스 호환). SpriteLib 은 피벗·캔버스를 여기서 읽고 **리사이즈 없이 하단 중앙 패딩만** 한다. 없으면 구 규격(실측 발끝). 정본 = `art/rework/<그룹>/stage/<id>/`, sync_art.py 는 이 폴더를 건너뛴다(색인만 갱신). west = flip_h(east) 파생 파일 |
| 앵커 | `data/anchors/<entity_id>.json` → `game/data/anchors/` | `{<entity_id>: {canvas, pivot, frames{<anim>_<dir>_<n>: {foot, head, face, hand_l, hand_r, aura}}}}`. tools/art_anchors.py 생성, art_lint L21 검사. 오버레이·손 앵커 소비자는 프레임 키로 찾는다 |
| 교체 전 백업 | `../art/_legacy_runtime/<entity_id>/` | 새 규격으로 바꾸기 직전 런타임 사본(.import 제외). `--pilot-legacy` 전후 비교 렌더만 읽는다(res:// 밖, 익스포트 제외) |
| 파일럿 원본 | `assets/pilot/<id>__pilot/` | 승인 기준선(2026-11-22) 보관. 기본 스프라이트 경로는 보지 않는다. VfxLib 은 옛 `__pilot` fx ID 호환으로만 읽는다 |
| 스프라이트 색인 | `assets/sprites/manifest.json` | sync_art.py 생성. **런타임은 디렉터리 나열 대신 이것을 쓴다**(익스포트 호환) |
| 이펙트 | `assets/vfx/<fx_id>.png` + `<fx_id>.json` | pixelfx/Aseprite 형식: `frames[]` + `meta.pixelfx.{fps,loop,frames,frameSize,pivot,columns}` |
| 효과음 | `assets/sfx/<sfx_id>.ogg｜.wav` | |
| 음악 | `assets/music/<cue_id>.ogg` | 장단 스템 `jd_<jangdan>_<inst>[_h1｜_h2].ogg` |
| 타일셋 | `assets/tilesets/<name>.png` (+ `.metadata.json`), `assets/tiles/` | |
| 아이콘 | `assets/icons/*.png` | 시트 슬라이스는 ui |
| 폰트 | `assets/fonts/<family>/` | galmuri, fusion_pixel, nanum_brush |
| 후보 | `assets/candidates/**` | 런타임 미참조 |

* **누락 에셋은 자동 플레이스홀더**: `SpriteLib.placeholder()`(ID 해시 색 + 외곽선), `VfxLib._placeholder()`(절차적 링), Audio 는 무음. 에셋이 없어서 크래시가 나면 버그다.
* ID 는 `data/canon_ids.json` 기준. 옛 ID 는 `Data.resolve_id()` 로 해석.
* 텍스처 필터 nearest(프로젝트 기본). 픽셀 스냅 켜짐.
* 동기화: `bash tools/sync_data.sh [--art]`, `python tools/sync_art.py [--clean]`. `game/data/`·`game/assets/sprites/` 를 직접 고치지 말 것(다음 동기화에서 덮어씀).

---

## 7. 성능 예산 (data/tech/perf_budgets.json 정본)

* 목표 Steam Deck LCD 60fps, 프레임 16.67ms. 시뮬 합계 ≤ **4.0ms** (이동·분리 1.2, 투사체 1.2, 피해 0.6, 픽업 0.3, 의식 0.3(+고리 닫힘 프레임 1.0), 스폰·AI 0.4), 연출 스크립트 2.0, 렌더 제출 3.0, UI 1.0.
* 상한: 적 저장소 2560(설계 상한 v1 400, 하드 2500), 적 탄 하드 1500, 이펙트 종류당 64(풀 256), 오디오 원샷 48+16.
* 측정: 봇 리포트의 `tick_ms`(프레임당 시뮬 ms, 배속 시 배속분 합), F9 성능 덤프, F4 적 200 즉시 스폰.

## 8. 코딩 규칙

* **정적 타입 필수**(`var x: int`, 반환 타입). `class_name` 은 씬/서비스 스크립트에만.
* 통신은 신호(Events) 또는 §2 서비스 API. 다른 모듈 노드를 `get_node` 경로로 찾지 않는다(`Game.<service>` 사용).
* **매 프레임/매 틱 할당 금지**: Packed*Array 사전 할당, 쿼리 결과는 호출자가 준 버퍼(`query_circle(out)`), 문자열 포맷·Dictionary 생성은 이벤트 시에만.
* 노드 생성은 `_ready` 풀링. 적·탄·구슬·이펙트를 노드로 만들지 않는다.
* 수치 하드코딩 금지 → `Data.num(table, path, default)`. 기본값은 데이터와 같게.
* 결정론: 시뮬 난수는 Rng 스트림, 시뮬 시각은 `Game.time_sec()/game_tick`(실시간·`_process` delta 금지).
* 팔레트 예약: 백 #f2ece0 = 풀릴 기색·길베·영가·해원 **전용**, 적 #c8322d = 붉은 무구·퇴치, 적 탄 = 청 #2a5caa / 흑. 다른 용도로 쓰지 않는다.
* 종료는 `Game.quit_game()`(직접 `get_tree().quit()` 금지 — 오디오 누수).
* class_name 스크립트에 `static var` 캐시 금지(종료 누수) → `AssetCache`.
* 주석·식별자: 식별자는 영문 로마자(캐논 ID), 주석은 한국어 가능. TODO 는 `# TODO(<module>): …`.

## 9. 테스트 방법

```bash
bash tools/godot_check.sh            # 임포트 + 타이틀 600프레임 + 봇 60초 + 사망 경로(20초 사망 → 정산 R_DEATH → 신당)
                                     #  + 튜토리얼: 인트로 카드 6 · 굿 안내서 8쪽 · 연습 굿판 10단계(×4) · 새 프로필(연습 중간 그만두기 → 다시 → 완주 → 실전 = 만신 직행 + 첫 굿판 완화)
                                     #    · 첫 실행 흐름 3f(새 프로필 ftcheck[_<LOG_TAG>] — 태그가 있으면 3q tutcheck 와 함께 프로필 이름에 붙어 동시 실행끼리 서로 지우지 않는다: 인트로 6장 → 권유 '연습하기' → 연습 완주 → 타이틀, 두 번째 실행 = 바로 메뉴·first_run_pending 유지) → 오류 0 이면 exit 0
bash tools/godot_check.sh --full     # + 봇 완주(×10, 점지 pair): 20:00 보스 → 저승사자 정산 → stage_finished → 정산 화면 → 종료
bash tools/godot_check.sh --geodum   # + 보스 강제 해원 → 정산 중 정기 0 → '굿판 거둠'(victory=true, ending=gutpan_geodum)
bash tools/godot_check.sh --builds   # + 빌드 행렬(시드 2/7/11 × 만신·BUILD_CHAR2, pair, 병렬) → [autotest] build 한 줄 요약
bash tools/godot_check.sh --movie    # + non-headless 캡처 → game/captures/frame*.png (50프레임 간격)
LOG_TAG=<모듈> bash tools/godot_check.sh [--full|--movie]   # 동시 실행 규칙: 로그 captures/godot_check_<모듈>.log, 캡처 captures/<모듈>/
OUT_DIR=/abs/dir bash tools/godot_check.sh                  # 출력 폴더 직접 지정
MOVIE_AT=650 MOVIE_ARGS="--start-sec=590" bash tools/godot_check.sh --movie   # 특정 시각 캡처

GODOT=/c/Users/김태양/Desktop/Godot_v4.7.2-stable_win64_console.exe
$GODOT --headless --path game --quit-after 900
$GODOT --headless --path game --fixed-fps 60 --quit-after 4000 -- --autotest --seed=1 --quit-at=60
# --write-movie 경로는 절대 경로로(상대 경로는 --path 기준으로 풀려 game/game/... 가 됨). --quit-after 로 끊어도 이제 누수 없음.
$GODOT --path game --write-movie C:/Users/김태양/Desktop/KoreaLike/game/_capture/run/frame.png --fixed-fps 60 --quit-after 300 -- --autotest --seed=1 [--speed=10]
```
**공용 파일명 금지**: 여러 에이전트가 동시에 돈다. 검증 로그·캡처·scratchpad 파일명에는 모듈 접두사를 붙인다(`LOG_TAG=<모듈>`, `<모듈>_full.log`). 공용 `captures/godot_check.log` 는 리드 최종 검사 전용.
캡처 폴더 `game/captures/`, `game/_capture/` 는 `.gdignore`(임포트 제외)·`.gitignore` 처리. `assets/_review/`, `assets/candidates/` 도 런타임 미참조라 `.gdignore`.
오류 판정: 로그에 `SCRIPT ERROR | Parse Error | ERROR: | Failed to load | Invalid call …` 가 있으면 실패(`captures/godot_check.log`).

**명령행 인자**(`--` 뒤): `--autotest`(타이틀 건너뜀·봇 이동·점지 자동 선택·사망 무시·런 끝나면 정산 화면 `--result-hold=<s>`(3) 뒤 종료, `--autotest-lobby` 면 신당도 3초), `--char=<id>`, `--seed=<n>`, `--start-sec=<s>`, `--speed=<n>`, `--quit-at=<s>`(게임 시각), `--autotest-die=<s>|settle`(사망 경로), `--bot-pick=greedy|random|pair`(봇 점지 정책), `--wpn=<id[:Lv],…>`(combat 지급), `--trial-at=<s>`·`--deity-test=wieom|gaho|mix`(deities, 디버그 빌드), `--boss-form=han|sal`(enemies), `--waves-n=<0..1>`·`--waves-boss-resolve=haewon|toechi`·`--waves-boss-resolve-after=<s>`(waves), `--profile=<name>`(meta 세이브 분리), `--pilot[-legacy]`.
튜토리얼(design/17 §7.6): `--intro-test`(인트로 1.5초 자동 넘김 → 권유 창 → `[intro] card=<n>/6`·`done`), `--guidebook-test=<1..8|all>`(`[guidebook] page=<n>/8`·`done`), `--tutorial-autotest`(**`--autotest` 와 함께**, 타이틀 없이 연습 굿판 + TutorialBot, 끝나면 종료. 로그 `[tutorial] step=<id> done t= dur=(게임 초) help=(최대 도움) screen=(화면 초)`·`finished … done=<n>/10`·`save_same=true|false`), `--tutorial-step=<id>`(그 단계부터, 혼자 쓰면 사람이 해 봄), 자동 테스트 보조: `--tutorial-exit=real|again|title`(끝 화면에서 그 버튼, 한 번), `--tutorial-exit-at=<id>`(그 단계에서 그만두고 다시 연습, 한 번), `--tutorial-skip-all=<s>`(단계마다 s초에 건너뛰기), `--tutorial-bot-idle=<s>`(단계마다 처음 s초 가만히 — 도움 L1~L3 시험·캡처), `--tutorial-shots=<절대 경로>`(단계 대표 프레임 PNG). 첫 실행 흐름 검사: `--intro-test --intro-choice=practice|play`(권유 창 답 흉내, 인트로 검사는 한 프로세스에 한 번; `--tutorial-autotest` 와 같이 오면 main 이 타이틀을 거친다), 타이틀 로그 `[title] open intro_seen= offered= practice_done= first_run_pending=`(디버그 빌드), `--tutorial-exit=title` 이면 `[tutorial] title_back` 뒤 종료. 쉼 메뉴 캡처: `--pause-test=<게임 초>`(쉼 메뉴 → 굿 안내서 3쪽 → 닫기, `[pause] …`). 최종 캡처: `game/captures/tutorial/final/<intro|practice|guidebook|title_guide|pause_guidebook>/`(11-26 마감 캡처는 `tutorial/final2/`, 가시성은 `captures/vis/final/<main|crowd|weak|weak_1930|perf>/`)(인트로·안내서·쉼 메뉴는 `--write-movie <절대경로>.avi` 뒤 ffmpeg 로 필요한 프레임만 뽑음). 전체 목록·조작은 `../PLAY.md`.
봇 리포트(2분마다 + 종료 시, 두 줄):
`[autotest] t= tick_ms=(프레임당, 배속분 합) per_tick_ms=(틱당) fps= enemies= proj= orbs= lv= xp= toechi= haewon= yeongga= salgi= sinmyeong= geori= draw_calls=`
`[autotest]   spawned= fired={무구별 발사 수} hits= killed= rings=(고리 닫힘) bot_dist_u= player=(x,y) hp= weapons=`
종료 시 한 줄 더: `[autotest] build char= seed= pick= lv= levelups= jeomji_opens=(점지 창 열린 횟수) late_gap_min=(14분 뒤 최소 간격) first_lv8= first_evo= evos= first_union= unions= slots=[…]`
**점지 몰아받기**(run.gd): 레벨업은 바로 열지 않고 쌓았다가 연다 — 시련 강림~빙의 점지·합일·작두·보스 직전 정리/침묵/등장 6초·해결 직후에는 보류, 10:00 뒤 15초·14:00 뒤 30초 간격, 최대 90초 보류. 쌓인 것은 levelup 의 '점지 ×N' 으로 연달아. **사망**: 사망 연출(1.4초) 중 레벨업·쉼 입력·stage_finished 무시(사망으로 정산), 보스 해결 뒤 정산 단계 사망은 '굿판 거둠'(클리어 유지). 창 포커스를 잃으면 쉼 메뉴 자동.
봇(`player/player_bot.gd`): 우선순위 ① 시련(강림 원에 들어가 고르기 → 화신 둘레 4u 돌기, 사거리 6.5u 안) ② 보스 고풀이 매듭·살 덩어리 밟기 ②b 중간보스·보스 붙기(`enemy_bigs.bot_engage`, 한형 열림 창 2.2u·살형 4u·중간보스 3~3.5u) ②c 14u 안 상자(길흉함·넋함) 줍기 ③ 16초 주기로 10초 고리 그리기(근처 풀릴 기색 잡귀 둘레 r=2.4u, 없으면 제자리 원; 3주기마다 길베가 허락하는 최대 원 ≤4.5u) → 6초 구슬 줍기, 적 회피 혼합. 게임 시각 기준이라 배속에서도 궤적 동일.

**디버그 키**(디버그 빌드): F1 시간 ×10 토글, F2 즉시 레벨업, F3 무적, F4 적 200 스폰, F5 시련 즉시, F6 화면 내 적 풀릴 기색 강제, F9 성능 덤프. 입력: WASD/화살표/스틱(360°)/D-패드, Esc·P 일시정지, 1·2·3 점지 선택, Enter/Space 확인.

## 10. 현재 상태와 남은 TODO (2026-11-24, 리드 통합 반영)

검증: `bash tools/godot_check.sh --full` → **OK: no errors**(임포트 + 타이틀 + 봇 60초 + 봇 완주).
봇 완주(×10, seed 2): 시련 4회 모두 위엄 완료(16~19초) → 18:00 합일(hapil_wise) → 18:35 작두 강림(충격파 54) → 19:15 뒷전 → 20:02 보스 역려(한형)
→ **22:35 보스 해원 → 저승사자 읍(saja_bow) → `stage_finished` → `Game.end_run` → 정산 화면 → 종료**. Lv41, 퇴치 1088 / 해원 4322.
시뮬 비용(헤드리스 디버그, **틱당**): 1분 0.83 · 6분 0.91 · 10분 1.34 · 12분 1.33 · 16분 0.48 · **18분 3.60**(합일+작두+에워싸기 동시, 예산 4.0ms 근접) · 20분 2.06 · 22분 0.94ms.
장면 캡처: `game/captures/v2/` (01 초반 ~ 09 신당 로비, 장면별 원본 폴더 `s0*_*/`).

**리드 통합(11-24)**
* 종료 흐름: run.gd 21:00 임시 종료 제거 → `Events.stage_finished` 구독(안전망 30:00). 사망·종료 결과는 `Game.last_result` → main.gd → 정산 화면 → `Save.lobby_route()` 면 신당, 아니면 타이틀. 로비 `start_requested` 연결. 타이틀 '굿판 열기' = 첫 실행 초굿(만신) 직행 / 이후 신당 경유(해금 우회 제거).
  waves 의 `_hold_run_open / _restore_run_duration / _bridge_run_end` 다리는 이제 무해한 no-op(run_active 가 이미 false) — waves 가 정리해도 된다.
* 피격: PlayerHit 에 영가 대신 맞기(`YeonggaTrain.try_substitute`, iframe 0.2) 연결. 신명 오름 장단 −15%p(`HaewonSystem.jangdan_bonus`) WeaponBase.cooldown 반영.
* 점지: 패시브·충전 카드가 빈 카드로 나오던 것 수정(후보 사전 title/desc/color, 띠 '패시브 · 붉은/흰 쪽'·'충전'). 진화·결합 무구 아이콘·이름 폴백(UiKit.weapon_def).
* 겹침: 시련 강림~해결 중 waves 거리 카드 생략, HUD 거리 줄은 시련·보스 제목과 배타, 시련 게이지 라벨을 공수 레인(y64) 밖으로, 시련 예고 힌트를 후보 카드 아래로. 첫 고리 글자는 ui 이름표만(haewon 붓 배너·vfx '해원 ×N' 생략), 3명 이상 고리는 haewon 배너만.
* 정산 화면: 결말 '사자가 판을 거두었다'(23:00 timeout), 메타 정산 한 줄(공덕·복전·배율), 버튼 '신당으로'.
* 재가집 의뢰: waves 종 출현 배율(`species_weight`)·중간보스 고정(`mboss_fixed`), deities 06:30 신령 보장(`deity_guarantee`) 적용 — 로비 카드 문구가 실제로 일어난다.
* 데이터: 보스 역려 한 고정 han 85000→**30000**, sal 130000→**40000**(봇 실측: 강한 빌드로도 3분 안 해결 불가 → ttk_target 120~160초에 맞춤, 플레이테스트로 재조정). char_myeongdu body_px [44,44].
* 에셋: `sync_art.py --index-only`(복사 없이 색인만) 추가·실행 — G3 반입 12종의 manifest 애니 항목(구 attack_a·idle 등)이 낡아 있던 것 갱신, avatar 캔버스 160/128 반영. enm_subi__sogwi 재생성(do_sogwi --install, lint PASS). waves 저승사자 대체 연출은 새 규격(float 만)에 맞춰 float 로 대체.
* 도구: godot_check.sh `LOG_TAG`/`OUT_DIR`/`MOVIE_AT`/`MOVIE_ARGS`, --full 은 stage_finished 까지. 봇: 시련 참여, 보스 매듭·살 덩어리 밟기, 큰 원. `export_presets.cfg`(Windows), `../PLAY.md`.

| 담당 | 남은 TODO (마감 전 우선순위 순) |
|---|---|
| enemies | 18분대 틱 3.6ms(합일·작두·에워싸기 겹침) — 예산 4.0 근접. `apply_status`/`push_radial`/`supports_march` 공개 API 미구현(waves 진형·deities 공포/둔화가 근사로 동작) — 이번 빌드는 근사 유지. 구미호 홀린 영가 에셋 없음(미표시) |
| combat | `ProjectilePool.spawn_enemy` 소유 핸들 인자(처녀귀신 꽃잎), 작두 강타 `Juice.feedback_event("jakdu_slam")`, dodge·호신부 단계, 장군 '붉은 무구 관통 +1' 보정 API, `Events.enemy_hit` 원인 무구 |
| waves | 다리 함수 정리(선택), 손님 행차 트리거 단일화(enemies 자동 트리거 유지 중), 뒷전 offering_gated(enemies API 필요) |
| haewon / deities | 봇 기준 원귀 회귀(살기 25)는 자연 도달 안 함 — 수동 테스트. 화신 애니 품질(L8·L13·L23)은 다음 PixelLab 예산 |
| ui | 리바인딩 UI, 정산 화면 상세 rows(지금은 한 줄) |
| meta | 타임아웃 결말도 DEATH 로 환산(의도 확인) |
| core | 내보내기 템플릿 미설치(PLAY.md §6, 다운로드는 사용자 승인 필요) → 릴리스 익스포트·18:00 tick_ms 측정. (11-24 완료: XP 후반 가속 c3=0.5·L30, 점지 몰아받기 — 봇 4런 점지 40~45회·14분 뒤 최소 간격 30초, 사망/굿판 거둠 경로·--autotest-die, 포커스 잃으면 쉼, Alt+Enter/F11, hard_cap=사망 정산, include_filter 확대) |
