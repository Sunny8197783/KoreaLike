extends Node
## Events — 전역 신호 버스. 소유: core(리드).
## 규칙
##  - 신호 추가는 "자기 모듈 구역" 끝에만 한다(append-only). 기존 신호의 이름·인자 변경은 리드 승인 후.
##  - 인자는 정적 타입. 적 개체는 핸들(int, EnemyManager.handle)로 넘긴다. 노드 참조를 신호로 넘기지 않는다.
##  - 시뮬레이션(고정 틱)에서 emit, 연출(L3: vfx/audio/ui)이 구독한다. 구독자는 시뮬레이션 상태를 바꾸지 않는다.

# ─── core ──────────────────────────────────────────────────────────────
signal run_started(char_id: StringName)
signal run_ended(result: Dictionary)                 # {victory, time_sec, toechi, haewon, ratio, boss_form, ...}
signal pause_changed(paused: bool, reason: StringName)
signal hitstop_started(ms: int)
signal sim_speed_changed(speed: int)
signal debug_toggled(flag: StringName, on: bool)

# ─── beat (core) ───────────────────────────────────────────────────────
signal beat(beat_index: int, is_downbeat: bool)
signal grid_tick(grid_index: int)
signal geori_changed(geori_id: StringName, bpm: float, jangdan: StringName)

# ─── combat ────────────────────────────────────────────────────────────
signal weapon_fired(weapon_id: StringName, slot: int, pos: Vector2)
signal weapon_added(weapon_id: StringName, slot: int)
signal weapon_leveled(weapon_id: StringName, level: int)
signal weapon_evolved(from_id: StringName, to_id: StringName)
signal enemy_hit(handle: int, species: StringName, pos: Vector2, damage: float, color: int, crit: bool, knot_locked: bool)
signal player_damaged(amount: float, source: StringName, hp: float, hp_max: float)
signal player_healed(amount: float, hp: float, hp_max: float)
signal player_died()

# ─── enemies ───────────────────────────────────────────────────────────
signal enemy_spawned(handle: int, species: StringName, tier: StringName)
## kind: &"toechi" | &"haewon". cause: &"han_pa" | &"gyeoldan" | &"elite_last" | &"white" | &"ring" | &"saja" | &"debug"
signal enemy_killed(handle: int, species: StringName, pos: Vector2, kind: StringName, cause: StringName, tier: StringName)
signal pullil_entered(handle: int, species: StringName, pos: Vector2)
signal maetim_returned(handle: int, species: StringName, pos: Vector2)
signal elite_spawned(handle: int, species: StringName)
signal boss_spawned(handle: int, species: StringName, form: StringName)
signal xp_collected(amount: float)
signal level_up(new_level: int)
## 픽업 획득(구슬 제외): kind = pick_gongmul | pick_hosinbu | pick_chohon_bal | pick_myeongjul_sil | box_gilhyung | box_neokham
##   | cur_yeopjeon | cur_neok | pick_gajja_yeopjeon | pick_gajja_gongmul | pick_yeou_guseul. value = 양(엽전·넋) 또는 상자 등급 0..2
signal pickup_collected(kind: StringName, value: float, pos: Vector2)
## 정예 이상 패턴 시작(예고 시작 순간): 오디오 큐·공수 힌트(ui)용. pattern = 07 패턴 ID(예: &"dok_ssireum"), telegraph_s = 예고 길이
signal enemy_pattern(handle: int, species: StringName, pattern: StringName, pos: Vector2, telegraph_s: float)
## 상자 개봉(길흉 상자·넋함): grade 0 소길 / 1 중길 / 2 대길, results = WeaponManager.open_box 반환([{kind, id, from}]),
##   bonus = 확정 부가 재화(엽전 또는 넋). 내용은 이미 적용된 뒤다 — ui 는 알림(토스트·점복 연출)만 그린다.
signal box_opened(box_id: StringName, grade: int, results: Array, bonus: float, pos: Vector2)
## 한형 보스(고풀이) 매듭: 생김(alive true)·풀림/사라짐(false). k = 매듭 번호(1..7), pos = 월드 좌표.
##   ui guide 의 오프스크린 표지·첫 매듭 이름표용. 조회는 EnemyManager.boss_knots(out) / boss_gopuri().
signal boss_knot(pos: Vector2, k: int, alive: bool)

# ─── waves ─────────────────────────────────────────────────────────────
signal minute_changed(minute: int)
signal wave_event(event_id: StringName, params: Dictionary)
signal midboss_incoming(species: StringName)
signal boss_incoming(species: StringName)
## 이벤트 예고(텔레그래프): in_sec 뒤 event_id 가 시작된다. params: title_ko, hint_ko, 기하(dir/center/gaps…)
signal wave_warn(event_id: StringName, in_sec: float, params: Dictionary)
signal ambient_changed(ambient: float, fade_sec: float)           # waves_stage1.lighting[] (0..1, 1=밝음)
## 뒷전 대해원: 묶은 공물상 수, 넋 보너스 배율(1.0/1.5/2.0), 고리 중심
signal daehaewon(bound: int, bonus_mult: float, centroid: Vector2, haewon_count: int)
## 보스 해결: kind &"haewon"|&"toechi", n_final = 넋 비율 N ± 0.10
signal boss_resolved(handle: int, kind: StringName, n_final: float)
## 정산 시작: route &"saja_bow"(넋 우세) | &"sal_geodum"(살 우세) | &"timeout"(23:00 보스 미해결)
signal settlement_started(route: StringName, params: Dictionary)
signal settlement_progress(route: StringName, done: int, total: int, progress: float)  # 살 거둠 덩어리 진행
## 정산 완료 → core(run.gd)가 Game.end_run(result.victory, result) 후 결과 화면. result: victory, ending, boss_form, n_ratio, n_final …
signal stage_finished(result: Dictionary)

# ─── haewon ────────────────────────────────────────────────────────────
signal yeongga_joined(count: int, species: StringName)
signal yeongga_cheondo(count: int, reason: StringName)
signal gilbe_ready(closable: bool)                       # 고리 닫힘 후보 생김(가이드 표시용)
signal ring_closed(area_tiles: int, haewon_count: int, centroid: Vector2)
signal salgi_changed(value: float, delta: float)
signal wongwi_return(threshold: int)
signal sinmyeong_changed(value: float)                   # 0..1
signal sinmyeong_oreum(active: bool)

# ─── deities ───────────────────────────────────────────────────────────
signal trial_warn(slot: int, deity_id: StringName, in_sec: float)
signal trial_start(slot: int, deity_id: StringName)
signal trial_gauge_changed(slot: int, wieom: float, gaho: float)   # 0..1
signal trial_end(slot: int, deity_id: StringName, winner: StringName)  # &"wieom" | &"gaho" | &"none"
signal hapil_start(deity_ids: Array)
signal possession_changed(deity_id: StringName, active: bool)
signal debug_trial_now()
## 시련 단계: &"omen" &"descend" &"confirm" &"clear" &"trial" &"resolve" &"possession" &"jeomji" &"afterglow" &"dormant"
##   (합일: &"hapil_omen" &"hapil_descend" &"hapil_call" &"hapil_active"). waves 는 clear~afterglow 동안 스폰 ×0.6 에 쓸 수 있다.
signal trial_phase_changed(slot: int, deity_id: StringName, phase: StringName)
signal trial_candidates(slot: int, left_id: StringName, right_id: StringName)   # OMEN·다시 묻기 때
signal trial_resolved(slot: int, deity_id: StringName, face: StringName, complete: bool)  # face &"wieom"|&"gaho", 미완=false
signal gongsu_spoken(deity_id: StringName, trigger: StringName, text: String)  # 공수 자막 1줄(gs_*)
signal deity_power_gained(deity_id: StringName, power_id: StringName, level: int, grade: StringName)
signal hapil_call(deity_id: StringName, word: String, index: int)             # 18:00 합일 4박 호명
signal hapil_complete(form_id: StringName, deity_ids: Array)                   # hapil_wise|hapil_jabi|hapil_yangmyeon

# ─── ui ────────────────────────────────────────────────────────────────
signal levelup_offer(choices: Array)                     # Array[Dictionary] {kind, id, level, title, desc}
signal levelup_chosen(choice: Dictionary)
signal hint_requested(hint_id: StringName)

# ─── meta ──────────────────────────────────────────────────────────────
signal currency_changed(currency_id: StringName, value: int)
signal unlock_gained(unlock_id: StringName)
signal save_written(ok: bool)

# ─── audio ─────────────────────────────────────────────────────────────
signal music_cue(cue_id: StringName)

# ─── vfx ───────────────────────────────────────────────────────────────
signal vfx_request(fx_id: StringName, pos: Vector2, rot: float)

# ─── tutorial ──────────────────────────────────────────────────────────
## 연습 굿판(design/17 §7.2). 보냄: tutorial_run(game/tutorial/tutorial_director.gd) → 받음: ui/tutorial_hud.gd.
## 예외: tutorial_ack · tutorial_exit_requested · tutorial_skip_step_requested 는 ui → 로직 '요청' 신호다
##   (pause_menu.quit_to_title 과 같은 성격). 머리말의 'L3 구독자는 시뮬 상태를 바꾸지 않는다' 규칙의 예외.
## 단계 id(순서 고정): move beat cut ring white yeongga jeomji trial sal settle (total 10)
signal tutorial_started(from_step: StringName, total: int)
## 같은 step_id 로 다시 오면 목표·보조 줄만 바꾼다(등불 그대로)
signal tutorial_step_started(step_id: StringName, index: int, total: int, goal_text: String, sub_text: String)
signal tutorial_step_progress(step_id: StringName, done: int, need: int)
## level 1..4. sub_text 가 "" 이면 보조 줄 유지·깜박만
signal tutorial_help(step_id: StringName, level: int, sub_text: String)
## 월드 이름표(B 채널, 0.9초)
signal tutorial_tag(text: String, hanja: String, world_pos: Vector2)
signal tutorial_step_completed(step_id: StringName, name_label: String, hanja: String)
## card = {pages: [{title: String, lines: Array[String], image: String}], confirm: String}. image = res://…png 또는 sprite:<entity_id>
signal tutorial_card(step_id: StringName, card: Dictionary)
signal tutorial_ack(step_id: StringName)                       # ui → 로직(요청)
signal tutorial_finished(completed: bool)
signal tutorial_exit_requested(next: StringName)               # ui → main(요청): &"real" | &"again" | &"title"
signal tutorial_skip_step_requested()                          # ui → 로직(요청)

# ─── 쉽고 화려하게(design/19 §11 계약, kill_ability_fx append) ─────────────
## 모두 연출 신호(보냄: vfx·weapons, 받음: hud·audio 등). 구독자는 시뮬 상태를 바꾸지 않는다. 받는 쪽은 Events.has_signal 확인 뒤 연결.
## psv_id = 패시브 id(&"psv_jusa" 등), pos = 월드 좌표(발동 자리).
signal passive_proc(psv_id: StringName, pos: Vector2)
## 0.25초 창 묶음 처치(창에 처치 5 이상이 된 순간 1번). count = 그 창의 처치 수, pos = 마지막 처치 자리.
signal kill_burst(count: int, pos: Vector2)
## 손 무기 타격 순간(held_weapon_attack_fx 가 보냄). hand_pos = 월드 좌표 손 기준점.
signal held_strike(weapon_id: StringName, hand_pos: Vector2)
