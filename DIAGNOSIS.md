# DIAGNOSIS — 1. 렌더링·애니메이션 원인 진단

- 작성일: 2026-11-22
- 대상: `game/` (Godot 4.7.2, gl_compatibility, 기준 해상도 640×360), 런타임 에셋 `game/assets/sprites`, `game/assets/vfx`
- 작업 범위: 진단만 했다. 게임 코드와 에셋은 고치지 않았다. PixelLab에서 크레딧이 드는 생성 호출은 0회다. 무료 도구만 썼다: `search_help`, `get_character`(읽기), `pixelart_workbench` score/lint.
- 표기 규칙: 측정이나 코드 근거가 없는 주장은 **(추정)**으로 표시했다. 각 항목 ID(A=엔진, B=애니 코드, C=에셋)는 검증 단계 기록의 ID와 같다.

---

## 0. 진단 시점의 빌드 상태 (중단된 병렬 빌드)

**지금 `game/`은 런 씬이 컴파일되지 않는다.** 아래 진단은 모두 이 반쯤 수정된 상태와 관계없는 기존 코드와 에셋 기준이다.

| 구분 | 파일 (수정 시각) | 상태 |
|---|---|---|
| 깨진 짝 | `projectiles/projectile_pool.gd` (11-22 19:02) | 220행이 `wm.on_projectile_hit(wslot,e,dmg,dir,ptag,i)`를 인자 6개로 호출한다. 190·200·231행은 `on_projectile_end`, 277~278행은 `w.proj_visual(tag)`를 호출한다 |
| 바뀌지 않은 짝 | `weapons/weapon_manager.gd` (11-21 18:14):86, `weapons/weapon_base.gd` (11-21) | `on_projectile_hit`의 인자는 4개다. `on_projectile_end`와 `proj_visual`은 정의돼 있지 않다 |
| 결과 | Godot 로그 `scratchpad/capB/log.txt` | `Parse Error: Too many arguments for on_projectile_hit() … Expected at most 4 but received 6` (projectile_pool.gd:220) → `Failed to load script res://run/run.gd`. 그리고 `There is no animation with name idle_south`가 420회 찍힌다 |
| 증거 캡처 | `scratchpad/capB/f00000300.png`, `scratchpad/cap/f00000200.png` | 타이머가 00:00에 멈춰 있다. 플레이어 스프라이트 없이 그림자 타원만 보인다 |
| 같은 시간대에 수정된 파일 (진단 근거로 안 씀) | `autoload/events.gd`(19:03), `deities/deity_defs.gd`(19:02), `data/waves_stage1.json`, `ui/tools/gen_ui_assets.py` | 중단된 작업의 결과물일 수 있다 |
| 18:40 이후 수정된 파일 | `autoload/audio.gd`, `debug_tools.gd`, `game.gd`, `waves/spawn_director.gd`, `haewon/ring_closure.gd`, `player/player_bot.gd`, `run/run.gd` | 렌더링 진단과 관계없다 |
| import 안 된 UI | `ui/icons/*.png` 28개, `ui/theme/skin/*.png` 16개 | `.import`가 없다. 아직 아무 데서도 참조하지 않는다 |

- 픽셀 측정은 중단 전에 찍은 정상 빌드 캡처 `game/_capture/run/`(18:41, 640×360 무비)로 했다. 렌더링 관련 스크립트(`game_camera.gd` 18:19, `player.gd` 18:10, `enemy_manager.gd` 18:25)는 그 뒤로 바뀌지 않았으므로 측정 결과는 유효하다.
- B1~B16에서 근거로 인용한 `player.gd`, `player_hit.gd`, `enemy_manager.gd`, `juice.gd`, `vfx_player.gd`, `vfx_lib.gd`, `hit_feedback.gd`, `weapons/*`, `shaders/*`, `k.gd`, `sprite_lib.gd`는 모두 11-21이 마지막 수정이다.
- 측정한 에셋 PNG의 마지막 수정 시각은 11-22 18:24~18:48(asset_review_fix, vfx_install 일괄 작업)이다. 18:48 이후 수정된 sprites/vfx PNG는 없다. `elite_yeokgwi_ttae`만 18:47 리뷰 스크립트로 다시 칠해져 원본과 298px가 다르다.
- **파일럿 렌더링 전 필요한 일(B0):** 다음 둘 중 하나를 해야 한다. (a) `weapon_manager.on_projectile_hit(…, tag, proj_index)`, `on_projectile_end`, `weapon_base.proj_visual(tag)`를 마저 구현한다. (b) `projectile_pool.gd`를 예전 인터페이스로 되돌린다. 그런 다음 `godot_check` 로그에 SCRIPT ERROR가 0건인지 확인한다. 이 작업은 코드 수정이라 사용자 승인이 필요하다.

---

## 1. 요약 — 원인 상위 5개

> 결론: 화면이 '뭉개져' 보이는 원인은 **엔진의 텍스처 필터링이나 비정수 배율이 아니다(A1에서 측정으로 기각).** 원인은 **에셋 자체의 노이즈와 팔레트 표류**, 그리고 **애니메이션을 연결하지 않은 코드**다. 움직임이 어색한 원인은 **애니를 재생하지 않는 것, 앵커 불일치, 반올림 지터, 0px로 사라지는 손맛 수치**다.

| # | 원인 | 체감 증상 | 핵심 증거 | ID |
|---|---|---|---|---|
| 1 | **애니메이션 미연결**: 적은 방향별 정지 그림 4장만 쓴다. 플레이어 idle은 1장이고, 방향을 바꾸면 걷기 사이클이 리셋된다. 걷기 재생 속도는 이동 속도와 따로 논다 | 잡귀 무리가 정지 그림 그대로 미끄러진다. 주인공이 멈추거나 걷기 시작할 때 그림이 툭 바뀐다 | `sprite_lib.gd:73-98` frames=4는 방향 수다. `player.gd:59-62` idle은 1프레임이다. `:117-118` play()가 프레임을 리셋한다. `:65` 12fps로 고정돼 있다. 에셋에는 move 4f×4방향과 idle 4f×4방향이 이미 있다 | A4·B1, A5·B2·B3 |
| 2 | **앵커·피벗 미적용, 정지↔이동 실루엣 점프**: 캔버스 중심 기준으로 그린다. template 애니가 rotation과 다른 크기와 자세로 그려졌다 | 캐릭터가 떠 보인다. 그림자가 무릎 높이에 있어 가려진다. 멈췄다 움직일 때 3~18px씩 출렁인다 | 발이 노드 원점보다 +28~30px 아래에 있다. Shadow는 (0,14)에 있다. 설계 피벗 (32,58)은 적용되지 않았다. sangmun 발은 46→40~41, bulgasari 몸은 83→63~65(−22%), gumiho move_east 발 변동은 17px다 | A6·B6, C-G5·C-G6 |
| 3 | **에셋 후처리 부재**: 마스터 팔레트 준수율 0%, 외곽선 `#1a1a1a` 0%, 애니 프레임 색 수는 rotation의 약 2배, 고립 픽셀 15~36% | 1배 화면에서 몸통이 회색 잡점처럼 보인다. 방향과 프레임마다 색이 미세하게 다르다 | 57개 엔티티 측정. 게임 PNG 41개 중 34개가 PixelLab 원본과 바이트 단위로 같다(후처리가 한 번도 적용되지 않음). char_mansin은 프레임당 54→115색, 엔티티 전체 806색이다. enm_gaekgwi workbench score 61.6 | C-G1·G2·G3 |
| 4 | **카메라와 플레이어의 반올림 불일치(1px 지터)와 60Hz→240Hz 보간 부재** | 이동 중 주인공이 1px(1080p에서 3px) 떨린다. 고주사율 모니터에서 스터터가 생긴다(추정) | 300프레임 동안 x 역전 42회, y 역전 40회(`scratchpad/track.txt`). `game_camera.gd:41`은 `_pos.round()`, `player.gd:102`는 실수 좌표다. physics_interpolation이 꺼져 있고 디스플레이는 240Hz다 | A2, A3(추정) |
| 5 | **손맛 수치가 사실상 0이고 공격 연출 구조가 없다**: 흔들림은 반올림 후 0px, 넉백은 설계의 약 1/10, 일반 타격 히트스톱 없음, 히트스톱 중에도 렌더가 계속 돈다, 선딜·판정·후딜 구분이 없다, 투사체를 자유 회전·비정수 스케일로 그린다 | 맞아도 반응이 없다. 공격이 '선 하나 그어짐'으로만 보인다. 투사체 계단이 깨진다 | `juice.gd:73-79` T1 최대 0.09px. `enemy_manager.gd:444-448` 넉백 총이동 = kb×3.2px. `arch_melee_arc.gd:16-45`는 같은 틱에 deal()을 호출하고 0.15s 벡터 선만 그린다. `projectile_pool.gd:301-331` atan2 회전과 scale | A8·A9, B8~B14, A7 |

부수 원인(낮음~중간): y-sort 없음(A10/B7), 좌우를 flip하지 않고 west를 따로 생성(B4), 4방향 구간 비대칭(B5), UI 폰트 폴백으로 한글 계단(A11), 후처리 그레인 3px 블록과 0.5px 떨림(A12), VFX 시트 절반이 64색 초과·반투명(C-G9), 행위자 PNG 반투명(C-G12).

사용자가 예로 든 의심 원인을 하나씩 판정하면 다음과 같다.

| 의심 원인 | 판정 | 근거 |
|---|---|---|
| 안티에일리어싱·스무딩 | **아님** | Nearest 필터를 쓰고, MSAA/FXAA/TAA는 기본값(꺼짐)이다. 실제 창에서 3×3 블록 비균일 비율이 0.0000이었다 |
| 비정수 스케일링(전역) | **아님** | `scale_mode=integer`, 640×360→1920×1080 정확히 ×3이다 |
| 비정수 스케일·회전(국소) | **맞음** | 투사체 atan2 회전과 spin, `vfx_pullil_enter` scale 0.6, `vfx_toechi_burst` 임의 회전(A7/B14, `diag_texel.png`) |
| FPS 고정 문제 | **부분적으로 맞음** | 물리 60Hz는 정상이다. 다만 240Hz 화면에서 보간이 없고(추정), 후반에 23~35fps로 떨어져 한 프레임에 여러 틱을 몰아 처리한다(A3) |
| 히트박스·앵커 불일치 | **맞음** | 발 +28~30px, 그림자 +14px, 설계 피벗 미적용, 방향별 몸 중심 ±5px(A6/B6) |

---

## 2. 엔진 설정 표 (현재값 → 권장값)

| 설정 | 위치 | 현재값 | 권장값 | 판정·근거 |
|---|---|---|---|---|
| 기준 해상도 | `project.godot:31-34` | 640×360, 창 1920×1080 | 유지 | 실측 ×3 정수 (A1) |
| stretch/mode | `project.godot:35` | viewport | 유지 | 저해상도 타깃에 렌더 |
| stretch/aspect | `project.godot:36` | expand | 유지 | 설계 1.1 "월드를 더 보여 준다" |
| stretch/scale_mode | `project.godot:37` | integer | 유지 | |
| default_texture_filter | `project.godot:54` | 0 (Nearest) | 유지 | 노드별 덮어쓰기 0건, 화면 샘플러 `filter_nearest`(occult_post.gdshader:4, vfx_silence_desat:7) |
| snap_2d_transforms_to_pixel | `project.godot:55` | true | 유지 | |
| snap_2d_vertices_to_pixel | `project.godot:56` | true | 유지 | 텍스셀 회전은 막지 못하므로 회전 금지 규칙이 따로 필요하다 |
| MSAA / FXAA / TAA / HDR | (키 없음) | 기본값 꺼짐 | 유지 | |
| import compress/mode, mipmaps | `.import` 2,876개 | 0(무손실), false | 유지하고 린트 추가 | `fix_alpha_border=true`는 Nearest에서 무해하다 |
| physics_ticks_per_second | `project.godot:46` | 60 | 유지 | |
| max_physics_steps_per_frame | `project.godot:47` | 4 | 유지(후반 성능은 별도 과제) | t=14:00에 23fps, 18:00에 35fps (`captures/godot_check.log`) |
| physics_jitter_fix | `project.godot:48` | 0.0 | 유지 | 보간을 켜면 0이 맞다 |
| **physics/common/physics_interpolation** | (키 없음) | **false** | **true** + MultiMesh 적은 prev/cur 위치를 `Engine.get_physics_interpolation_fraction()`로 lerp한 뒤 round | A3 (추정: 캡처는 `--fixed-fps 60`이라 재현되지 않음) |
| vsync | `project.godot:38` | 1 | 유지. 검증용 `max_fps` 옵션 | 디스플레이 2560×1600 @240Hz |
| 카메라 위치 반올림 | `run/game_camera.gd:37,41` | 따로 lerp한 `_pos.round()` + shake | 플레이어 렌더 위치 `round(sim_pos)`를 기준으로 `round(플레이어 렌더 위치 + round(오프셋))` | A2. 300프레임 동안 x 역전 42회, y 역전 40회 |
| 카메라 process | `game_camera.gd:21` | CAMERA2D_PROCESS_IDLE | 보간한 위치를 추적 | A3 |
| UI 폰트 | `ui/theme/main_theme.tres:3-7` | SystemFont `[Galmuri11, …, Malgun Gothic]`, AA 0 → 미설치라 맑은 고딕으로 폴백 | FontFile `res://assets/fonts/galmuri/Galmuri11.ttf`, AA 0, hinting 없음, 정수배 크기 | A11 (`scratchpad/txt.png`, 육안 판정이라 추정) |
| 후처리 그레인 | `shaders/occult_post.gdshader` | `floor(FRAGCOORD/3.0)`, `floor(TIME*12)`, grain 0.035, 채도 감소 0.1~0.35 | 1게임픽셀 단위, 박자에 동기, 행위자 레이어 제외 검토 | A12 (내부 픽셀 오차 평균 11.6/765) |
| 적 떨림 | `shaders/enemy_instanced.gdshader:23` | `sin(...)*0.5`px | 정수 1px를 일정 주기로 토글 | A12. 스냅 때문에 0/1px로 깜빡인다 |

---

## 3. 애니메이션·연출 코드 문제 표

| ID | 파일:라인 | 문제 | 영향 | 수정 방향 (3단계 설계에서 확정) |
|---|---|---|---|---|
| A4·B1 | `core/sprite_lib.gd:71-100`, `enemies/enemy_manager.gd:760`, `shaders/enemy_instanced.gdshader:21-25` | 아틀라스가 방향 정지 그림 4장이다. `INSTANCE_CUSTOM.x`에 facing을 넣어 프레임 번호가 곧 방향이 된다. move/glide/float 프레임은 한 번도 재생되지 않는다 | 높음 | [방향×프레임] 2D 아틀라스. 인스턴스별 위상과 fps ±10% 지터 |
| A5·B2 | `player/player.gd:59-62` | idle은 `dir_tex()` 1프레임이다. `idle_*_0..3`은 쓰지 않는다. 정지 그림과 walk_0의 알파 IoU는 0.78~0.86이고, 색이 다른 픽셀이 1,025~1,088개다 | 높음 | idle 4f를 연결하고 정지 단독 PNG는 런타임에서 뺀다 |
| A5 | `player/player.gd:117-118` | 방향을 바꾸면 `play()`가 프레임을 0으로 리셋한다. walk_west_3이 3프레임 만에 끊기고 walk_north_0으로 넘어간다(track.txt) | 중간 | frame과 frame_progress를 이어받는다 |
| B3 | `player/player.gd:65`, `:93-96` | 12fps 고정. 기본 128px/s일 때 사이클당 85px를 이동한다. 군중·지형 감속이 재생 속도에 반영되지 않는다. walk_south 1~7프레임은 발 덩어리가 거의 고정이다 | 높음 | `speed_scale = clamp(v/base, 0.8, 1.6)` (설계 13 §2.11) |
| B4 | 전체(grep으로 `flip_h` 0건) | west를 따로 생성한 그림을 쓴다. walk_east와 flip(walk_west)의 IoU는 0.62~0.73이다. east는 뒤쪽 3/4, west는 얼굴이 보이는 앞쪽 3/4다 | 높음 | west = flip_h(east). 적은 셰이더 비트로 UV.x를 반전한다 |
| B5 | `core/k.gd:54-72` | 4방향을 90°씩 똑같이 나누고 동점이면 앞 인덱스를 고른다. 우하·좌하는 S, 우상은 E, 좌상은 N이 된다 | 중간 | E/W ±55°, N/S ±35°, 히스테리시스 10° (설계 4.1.1) |
| A6·B6 | `player/player.tscn:9-14`, `enemies/enemy_manager.gd:271-276`, `core/sprite_lib.gd:92-93` | offset 없이 중앙 정렬한다. Shadow는 (0,14)다. 캔버스가 다르면 NEAREST 리사이즈한다. sangmun은 정지 46, move 41이다 | 높음 | 피벗 데이터로 offset을 주고 그림자를 발에 둔다. resize 대신 패딩한다 |
| A7·B14 | `projectiles/projectile_pool.gd:301-331`, `vfx/hit_feedback.gd:42,54`, `vfx/vfx_player.gd:52-53,197-199` | atan2 연속 회전, spin, scale 0.6, 0~TAU 임의 회전 | 중간 | 22.5°×16방향 또는 사전 렌더한 spin 프레임. 정수 스케일만 허용 |
| A10·B7 | `enemy_manager.gd:252-268,729-760`, `player.tscn:6` z_index=2 | y-sort 없이 active 배열 순서대로 그린다. 플레이어는 항상 위에 있다 | 중간 | 버킷 정렬. 피벗 정리가 먼저다 |
| A8·B10 | `autoload/juice.gd:73-80`, `data/combat_core.json` shake | trauma²×0.7×6px를 round()한다. T1 최대 0.09px, 플레이어 피격 0.38px, 정예 퇴치 0.51px로 모두 0이 된다 | 높음 | 방향성 킥 1~2px와 최소 1px 보장 (설계 상한 3px) |
| B8 | `enemy_manager.gd:400-401,614`, `enemy_instanced.gdshader:45-51` | 플래시는 50ms(3틱) 동안 명도 ×1.4+0.06뿐이다. `red_hit_tint_frames`, `local_freeze_frames`는 grep 참조 0건이다 | 높음 | 2~4프레임 단색 틴트(적=`jk`, 백=`hj`)와 1px 스쿼시 |
| B9 | `enemy_manager.gd:569-570,607-609,444-448` | kb(거리)를 속도로 넣고 exp(−10t)로 감쇠한다. 총이동은 woldo 1.9px, buchae 4.8px다. 정예는 0(설계 ×0.3) | 높음 | 거리로 해석한다. 0.12~0.15s ease-out, stagger |
| A9·B11 | `autoload/game.gd:113-123,145`, `player.gd:75-119`, `vfx_player.gd:92-98`, `projectile_pool.gd:264-266` | 히트스톱이 시뮬레이션만 멈춘다. `hitstop_started` 시그널은 연결된 곳이 0건이다. `Juice.feedback()`(juice.gd:136)은 호출 0건이다 | 중간 | 렌더 시계를 멈추고 일반 타격에는 local_freeze 2틱 |
| B12 | `enemy_manager.gd:661-668,391-399`, `player/player_hit.gd:41-45`, `run/run.gd:135-147` | 퇴치는 0.1s 번쩍이고 끝이다. 플레이어 hurt(6f×4)와 death(7f)는 참조 0건이다. 사망하면 바로 결과 화면이다 | 높음 | hurt 2f 덧씌움, death 재생 후 결과 화면 |
| B13 | `weapons/arch_melee_arc.gd:16-45,53-68`, `arch_aura/beam/orbit/summon/trail.gd`, `weapon_base.gd:117` | 발사 틱에 바로 피해를 준다. 2~3px 벡터 선 0.15s가 전부다. VFX 시트 162개 중 4개만 참조한다. 타격 스파크가 없다 | 높음 | 선딜 2~3f / 판정 1f / 후딜 3~5f, 시트 연결, hit spark |
| B15 | `vfx/vfx_lib.gd:56-61`, `vfx_player.gd:95` | 프레임별 duration을 무시하고 `fps=1000/durations[0]`만 쓴다(지금 시트는 모두 균일) | 낮음 | 누적 duration 테이블 |
| B16 | `enemy_manager.gd:428-434,450` | 배회 회전 ±0.9rad가 히스테리시스 10°를 넘나든다(추정) | 낮음 | 최소 유지 0.2~0.3s |

정상으로 확인된 것: 렌더 기본 설정, 카메라와 적 위치의 정수 반올림 자체, 히트스톱 예산과 이중 시계 로직, 해원 디졸브 0.55s, 플레이어 idle의 east/west 정확한 미러(IoU 1.000, 미사용일 뿐).

---

## 4. 에셋 품질 — 문제 파일 상위 10

### 4.1 원인 분류

| 코드 | 원인 | 해당 그룹 |
|---|---|---|
| **a** | 생성 방식·템플릿 선택: 참조 없이 v3 텍스트 생성 → 방향별 의상 불일치. `sad-walk` 같은 template이 rotation 자세를 보존하지 않음. west를 따로 생성 | C-G5, C-G6, C-G7, B4 |
| **b** | 후처리 누락이나 부작용: reduce_colors·correct_pixelart 미적용, 외곽선 색 미정규화, 반투명 알파 | C-G1, C-G2, C-G12 |
| **c** | 리샘플·변형 스크립트: `tools/scale_variant.py:24` `Image.BOX` 축소 → 알파 이진화 → 재양자화 | C-G8 |
| **d** | 생성 파라미터: `detail`(high)과 `size`(몸 높이 과대)를 사양에 맞게 지정하지 않음 | C-G3, C-G4 |

### 4.2 상위 10 (측정치)

측정 방법: `scratchpad/measure.py` → `scratchpad/sprites.json`. 몸 높이와 색 수는 south rotation 기준이다. '발 점프'는 정지 rotation과 애니 프레임의 발끝 y 차이다(애니 캔버스가 더 크면 중심 보정). '면적 변동'은 같은 루프 안의 실루엣 면적 변동 최대값, '고립'은 8이웃 중 비슷한 색(RGB 합 차 <24)이 없는 픽셀 비율이다.

순위 기준: ① 런타임 노출 빈도(주인공은 상시 노출, stage1 등장 횟수) ② 설계 기준(12.2 린트) 위반 개수 ③ 위반 폭을 함께 본 판단이다. 검증에서 기각된 C-T10 순위표와는 다르다(6장).

| # | 파일 그룹 (`game/assets/sprites/…`) | 캔버스 실측/사양 | 몸 높이 (4방향 범위) | 색 수 rot / 엔티티 전체 | 반투명 % | 고립 % | 발 점프 / 중심 드리프트 | 면적 변동 | workbench score | 분류 | 핵심 문제 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `char_mansin/*` (주인공, 상시 노출) | 64/64 | **60** (57~60), 사양 40~48 | 54 / **806** (walk 최대 115) | 0 | 14.6 (walk_s_0 29.8) | 1 / 방향별 몸 중심 x 28.5~34 (≈5px) | 4% | 82.6 | a b d | south는 청색 하의, east·north는 백점 무늬 붉은 치마(C-G7). west는 별도 생성(flip IoU 0.62~0.73). 노드 원점 대비 발 +29px |
| 2 | `enm_gaekgwi/*` (stage1 18회) | 40/40 | 38 (37~38) | 63 / 275 | 0 | **29.9** (평균 클러스터 1.48px) | 1 / 1.5 | 7% | **61.6** | d b | lint 결과 '1~2px 클러스터 296개'와 필로우 셰이딩 의심. 잡귀 예산 12색의 5배 |
| 3 | `enm_sangmun/*` (stage1 14회) | 48/48 | 46 (45~46), L 사양 32~40 | 54 / 88 | 0 | **27.5** | **6** (move_south 발 40~41 vs 46) | 16% | 62.7 | a d b | template `sad-walk`. 이동 프레임에서 지물(요령)이 사라진다. 몸 38~40 vs 46 |
| 4 | `elite_bulgasari__s64/*` (+ `__s80`) | 64/80 (사양 64/80/96 단계) | 55 (51~57) | 34 / 64 | 0 | **20.5** (s80 13.8, 원본 11.3) | 10 / 3.5 | 11% | 69.6 | c a | BOX 축소로 1px 클러스터 30.8%→49.0%, 외곽선이 끊긴다. walk 발 48~50 vs 정지 58 |
| 5 | `elite_bulgasari/*` | 96/96 | 83 (76~85) | 34 / 68 | 0 | 11.3 | **15** / 4.5 | 10% | — | a | walk_south 몸 63~65 vs 정지 83 (**−22%**). 멈추면 몸이 커진다 |
| 6 | `mboss_gumiho/*` | 128/128 | 117 (**103~117**) | 15 / 150 | 0 | 0.7 | **17** (move_east 발 101~119) / 6.5 | **22%** | — | a | 방향 간 몸 높이 14px 차. move_south 몸 100~101 vs 117 |
| 7 | `mboss_gangcheori/*` | 128/128 | 121 (117~122) | 51 / 273 | 0 | 11.6 | **18** (move_east 발 107~121) / 2.5 | 16% | — | a | move_south 106~110 vs 121 |
| 8 | `elite_dueoksini/*` | 96/96 | 92 (91~94) | 18 / 23 | 0 | 8.2 | 5 / **14** (move_east cx 39.5~50, south 39.5~53.5) | **28%** | — | a | 루프 안에서 몸 71~87로 출렁이고 좌우로 흘러간다 |
| 9 | `avatar_sansin/*` | 128/128 | 93 (84~93) | 64 / 152 | 0 | **35.7** (1px 클러스터 61.9%) | **13** (idle_south 발 92 vs 105) / 2.5 | 6% | — | d a | 측정 엔티티 중 노이즈 최대 |
| 10 | `yeongga_body_f/m/child/*` | 32/32 | 30 / 30 / 20 (어른 사양 22~26) | 47 / 128 (m 41/169) | **100** | 19~21 | 0 / 0 | — | — | b | 원본 대비 344~374px가 바뀌었다(색 47→127). 하단 페이드를 PNG 알파로 구웠다(설계는 셰이더). 외곽선 0% |

다음 순위(참고): `comp_dongja`(반투명 34.0%, 48→106색), `char_myeongdu`(엔티티 전체 893색, idle_east 발 점프 4), `elite_eodukssini`(반투명 90.3%, 셰이더 몸체용이므로 별도 판정), 잡귀 L 전반(`enm_dalgyal_gwisin` 캔버스 48/사양 32, 몸 44/사양 18~24).

### 4.3 전체 공통 수치 (57개 엔티티)

| 지표 | 측정값 | 설계 기준 (13장 12.2 / art_palette.json) |
|---|---|---|
| 마스터 팔레트 램프 색 비율 | **0.0%** (elite_eodukssini만 4.9%) | 모든 색 ∈ 램프 |
| 외곽선 중 정확히 `#1a1a1a`인 비율 | **0.0%** (어두운 외곽 자체는 75~100%) | ≥95% |
| rotation 프레임 색 수 | 플레이어 43~56, 잡귀 20~63 | `per_sprite_color_budget` 플레이어 24, 잡귀 12, 정예 16 |
| 애니 프레임 색 수 증가 | mansin 54→115, myeongdu 43→110(walk_east 115), simbang 44→81 | 엔티티 하나 = 팔레트 하나 |
| 원본과 바이트 동일 | 41개 중 34개 | 후처리 단계 필수 |
| 캔버스 사양 불일치 | dalgyal 32→48, agwi 40→48, comp_agwi/cheonyeo/dalgyal/mongdal 32→48, comp_gaekgwi/mulgwi/yeongsan 32→40 | 1.3 표 |
| 여백 | 플레이어 1~2px, 잡귀 다수 1px | ≥2px |
| 광원 방향(좌−우 휘도차) | baksu −0.12, daegwi −0.08 / janggun +0.10, bulgasari +0.10 (부호가 섞임) | 좌상단 베이크. **추정**: 의상 색의 비대칭이 측정에 섞일 수 있다 |
| VFX 159시트 | 업스케일 0개(모두 1x). 64색 초과 78개, 반투명 포함 100개, 반투명 >20% 71개. `vfx_trial_block_wall_*` 3,146~3,705색 | `per_sprite_color_budget.vfx` = 6 |
| 손그림 비교 기준 | `enm_dokkaebi_bul`: 고립 0.0%, 평균 클러스터 7.71px, 6색, score **98.2** | 파일럿 목표 수준 |

PixelLab 생성 기록(`get_character`의 style 줄): char_mansin `-, single color black outline, high detail`, enm_sangmun `-, single color black outline, medium detail`, elite_bulgasari와 mboss_gumiho `-, -, -`. 생성 당시 인자 로그는 따로 없다.

---

## 5. 확대 비교·증거 이미지

| 경로 | 내용 |
|---|---|
| `C:/Users/김태양/Desktop/KoreaLike/game/assets/_review/diag_mansin.png` | 만신 4방향 의상 불일치, 팔레트 스트립(정지 1장 54색 vs idle/walk 합집합 319색), 화면 대비 크기 |
| `C:/Users/김태양/Desktop/KoreaLike/game/assets/_review/diag_sangmun.png` | 정지↔move 실루엣 차, 고립 픽셀(자홍 표시) |
| `C:/Users/김태양/Desktop/KoreaLike/game/assets/_review/diag_bulgasari.png` | 96 원본 vs s80/s64 BOX 축소, walk 몸 축소 |
| `C:/Users/김태양/Desktop/KoreaLike/game/assets/_review/diag_texel.png` | 0.6배 스케일과 33° 회전 시 형태 붕괴 |
| `C:/Users/김태양/Desktop/KoreaLike/game/_capture/run/frame00000240.png` | 정상 빌드: 귀신 무리가 같은 정지 포즈, 방울 오라가 가는 회색 원 |
| `C:/Users/김태양/Desktop/KoreaLike/game/_capture/mansin_dirs.png` | 정상 빌드: 만신 방향별 표시 |
| `C:/Users/김태양/AppData/Local/Temp/claude/753e94647db49f01/1fd1a688-e4b3-466e-b94a-06f22ba391be/scratchpad/B_mansin_dirs_anchor.png` | walk_E/W, idle_E/W, static E/W 비교. 초록 점 = 노드 원점, 노란 타원 = Shadow, 파란 선 = 설계 피벗 y58 |
| `…/scratchpad/p200.png`, `e200.png`, `y200.png` | 200프레임의 플레이어·적·영가 4배 nearest 확대 |
| `…/scratchpad/txt.png` | HUD 한글 글리프 확대(맑은 고딕 폴백) |
| `…/scratchpad/window_crop_portraits.png`, `window_crop_title.png` | 실제 1920×1080 창 크롭(3×3 블록 균일 확인용) |
| `…/scratchpad/track.txt` (+ `track.py`, `anim.py`, `sizes.py`, `measure.py`, `sprites.json`, `vfx_measure.py`, `vfx.json`, `diag_sheets.py`) | 측정 원자료와 스크립트 |
| `…/scratchpad/capB/log.txt`, `capB/f00000300.png`, `cap/f00000200.png` | 현재 깨진 빌드의 로그와 캡처 |

`…/scratchpad/`의 전체 경로는 `C:/Users/김태양/AppData/Local/Temp/claude/753e94647db49f01/1fd1a688-e4b3-466e-b94a-06f22ba391be/scratchpad/`다. 임시 폴더라 재부팅이나 정리 때 지워질 수 있다. 보존이 필요하면 `game/assets/_review/`(`.gdignore` 있음)로 옮겨야 한다. 이번 작업은 새 파일 쓰기가 이 두 문서로 제한돼 있어 옮기지 않았다.

---

## 6. 기각된 주장 (검증에서 채택하지 않음)

| ID | 기각된 주장 | 처리 |
|---|---|---|
| C-G10 | "엔티티 37개의 PixelLab 프롬프트 어디에도 공통 스타일 접미사가 없고, 일부가 회화 양식(민화·붓 터치)을 요구해 노이즈를 키웠다" | 근거로 쓰지 않는다. 노이즈의 확인된 원인은 detail 설정(C-G3)과 후처리 부재(C-G1·G2)까지다. ART_STYLE.md의 '회화풍 키워드 금지'는 예방 규칙일 뿐 이 주장에 근거하지 않는다 |
| C-T10 | "수치상 문제가 가장 큰 순서: ① bulgasari__s64 ② bulgasari ③ gumiho ④ sangmun ⑤ gaekgwi ⑥ sansin ⑦ gangcheori ⑧ myeongdu ⑨ dongja ⑩ dueoksini" | 이 순위는 쓰지 않는다. 4.2는 노출 빈도와 위반 개수로 다시 매겼다(주인공 1위, 영가 포함) |
| C-ENG | "일반 적은 4방향 정지 이미지만 표시해서 미끄러진다 — 에셋보다 직접적인 원인" | 내용은 A4·B1(엔진/코드)에서 확인됐다. 에셋 항목으로 따로 세우는 것은 기각했다(중복). 에셋은 이미 있으므로 코드로 해결한다 |
| (사용자 가설) 안티에일리어싱·스무딩 | 텍스처 스무딩 때문에 뭉개진다 | 측정으로 반증했다(A1: 3×3 블록 비균일 0.0000, 외곽 오차 6.3 < 내부 11.6) |
| (사용자 가설) 전역 비정수 스케일 | 화면 배율이 비정수다 | 반증했다(`scale_mode=integer`, ×3 실측). 국소 VFX·투사체 변환만 해당한다 |

---

## 7. 수정 우선순위 (참고, 실행은 승인 후)

1. **B0 빌드 복구** — 파일럿을 인게임에서 렌더링하려면 먼저 해야 한다.
2. **B6/A6 피벗** → **B1·B2·B3 애니 연결·idle·속도 동기** → **B4 flip** → **A2 반올림 통일** (모두 에셋 재생성 없이 코드로 해결)
3. **B9·B10 넉백 단위와 흔들림 0px** → **B13 공격 3단계와 VFX 연결** → **B8·B11·B12**
4. 에셋: ART_STYLE.md 후처리 파이프라인 + `tools/art_lint.py` → 파일럿 → 승인 후 재생성/후처리 일괄 진행

에셋을 새로 뽑지 않고 코드로만 고칠 수 있는 것: B1, B2, B3(남쪽 walk는 재생성 권장), B4, B5, B7~B11, B14, B15, A2, A3, A11, A12.
