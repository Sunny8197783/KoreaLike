# GAME_FEEL — 3. 움직임·공격 모션 Juice 설계

- 작성일: 2026-11-22 · 상태: **설계 문서(코드 수정 없음)**. 구현은 B0 빌드 복구 뒤에 9장 순서대로 한다.
- 근거: `DIAGNOSIS.md`(원인 ID A*, B*, C-G*), `ART_STYLE.md`(강제 규칙), `game/ARCHITECTURE.md`(코드 계약·소유표). 참고 스킬: game-feel, camera-systems.
- 사용자 결정 반영(2026-11-22): ① 스케일 권장안(플레이어 64 캔버스·몸 44~48·발 피벗 (32,58), 잡귀 S 32/(16,29), M 40/(20,36), L 48/(24,44)) ② B0 = (a) `proj_visual`/`on_projectile_end` 마저 구현 ③ 마스터 팔레트 100%.
- 이 문서의 모든 수치는 `data/combat_core.json`에 새 구역 `feel`로 넣고(8장), 코드는 `Data.num()`으로 읽는다(ARCHITECTURE 8 '수치 하드코딩 금지').

---

## 0. 원칙 (이 문서 전체에 적용)

| # | 원칙 | 근거 |
|---|---|---|
| P1 | **화면에 나가는 모든 좌표는 정수 픽셀이다.** 반올림은 한 곳(렌더 동기 단계, 2.6)에서 `floor(x+0.5)` 하나로만 한다 | A2 (x 역전 42회) |
| P2 | **회전·비정수 배율 금지.** 스쿼시·기울기·플래시는 셰이더의 *정수 픽셀 시프트*와 *단색 치환*으로만 한다. 리샘플링 없음 | ART_STYLE 1.1, A7/B14 |
| P3 | **시뮬레이션 무변경이 기본.** 바운스·기울기·반동·흔들림·플래시는 렌더 전용이다. 시뮬을 바꾸는 것은 넉백 거리 해석(B9)과 국소 정지(B11) 두 가지뿐이고 둘 다 enemies 소유 코드 안에서 결정론을 지킨다 | ARCHITECTURE 0, 8 |
| P4 | **연출 시계(anim clock)는 시뮬 틱에서 파생**한다. 히트스톱·일시정지에서 자동으로 멈춘다. 흔들림·HUD·음악만 실시간 | B11 |
| P5 | **발 = 원점.** 모든 행위자의 시뮬 좌표는 지면 접점(그림자 중심)이다. 스프라이트는 피벗 offset으로 그 위에 선다 | A6/B6 |
| P6 | **군중의 일상 타격에는 흔들림·전역 히트스톱을 쓰지 않는다.** 일상 타격은 대상 국소 반응(플래시·스쿼시·국소 정지·넛지)으로만 판다 | game-feel '중요도 티어' |
| P7 | **팔레트 100%.** 플래시·틴트 색은 마스터 팔레트 색만 쓴다. 백 `#f2ece0`은 예약(풀릴 기색·해원 전용) | ART_STYLE 3.1 |

픽셀 수치 표기: 아래 표의 "명목 배율(x1.06/y0.94)"은 의도이고, 실제 적용은 항상 **정수 px**(1.4 공식)다.

---

## 1. 공통 기반

### 1.1 연출 시계 (anim clock) — B11 해결

| 항목 | 정의 |
|---|---|
| `Game.anim_tick_prev`, `anim_tick_cur` | 마지막 물리 틱 직전·직후의 `game_tick`. 히트스톱·일시정지 틱이면 두 값이 같다 |
| `Game.render_alpha` | `Engine.get_physics_interpolation_fraction()` (0..1). 엔진 보간 설정과 무관하게 값이 나온다 |
| `Game.anim_time()` | `(anim_tick_prev + render_alpha × (anim_tick_cur − anim_tick_prev)) / 60` 초. 히트스톱 중 정지, 배속(F1)에서 같이 빨라짐 |
| 이 시계를 쓰는 것 | 플레이어·적 애니 위상, 적 셰이더(`TIME` 대신 uniform `anim_time`), `vfx_player._t`, `projectile_pool._anim_t`, 데미지 숫자, 스쿼시·플래시 타이머 |
| 실시간을 쓰는 것 | `Juice` 흔들림(히트스톱 중에도 감쇠·진동 → 정지 화면이 떨려 타격이 팔린다), HUD, 음악, 일시정지 메뉴, 전체 화면 플래시 감쇠 |
| 타이머 단위 | 연출 타이머는 **틱(1/60s)** 정수로 센다. 아래 표의 "f"는 별도 표기가 없으면 60Hz 틱, "VFX f"는 20fps 시트 프레임(= 3틱 = 50ms) |

### 1.2 위치 보간 — physics interpolation 정책 (A3 해결)

**결정: 엔진 `physics/common/physics_interpolation`은 `false` 유지. 대신 수동 보간 하나로 통일한다.** (DIAGNOSIS 2장 권장값 `true`와 다름 — 이유는 아래)

| 이유 | 설명 |
|---|---|
| 반올림 권한 단일화 | 엔진 보간은 Node2D마다 소수 좌표를 만들고, 노드마다 따로 스냅한다. 그러면 A2(카메라·플레이어 반올림 불일치)가 다시 생긴다 |
| SoA 대상 | 적(MultiMesh)·투사체(`_draw`)·구슬은 노드가 아니라서 어차피 수동 보간이 필요하다(DIAGNOSIS도 동일 지적) |
| 순간이동 | 적 재배치(`enemy_manager.gd:452-456`)·스폰·`snap_to_target()`에서 `prev=cur` 한 줄로 끊으면 된다. 엔진 방식은 `reset_physics_interpolation()`을 노드마다 불러야 한다 |

| 규칙 | 값 |
|---|---|
| 저장 | 플레이어 `prev_pos/cur_pos`, 적 `ppx/ppy`(SoA, `px/py`와 같은 용량), 투사체 `ppx/ppy` |
| 복사 시점 | **시뮬이 진행된 틱**의 시작에서 `prev=cur`. 진행 안 된 틱(히트스톱·일시정지)에서는 `prev=cur`로 동결(보간이 움직이지 않게) |
| 한 프레임 다중 틱(후반 23~35fps, 배속) | 틱마다 복사하므로 prev는 항상 "마지막 틱 직전" |
| 렌더 좌표 | `r = round(lerp(prev, cur, render_alpha))` |
| 지연 | 1틱(16.7ms) 표시 지연을 감수한다(보간의 표준 비용) |
| 캡처(`--fixed-fps 60`) | alpha가 거의 0 → prev 표시. 측정에는 영향 없음 |

### 1.3 렌더 동기 단계 (호출 순서 고정)

`run.gd._process(delta)` 하나가 아래 순서로 부른다. 각 모듈의 `_process` 렌더 코드는 `render(alpha)` 함수로 옮기고 자체 `_process`는 끈다(core·리드 승인 사항: ARCHITECTURE 4에 "렌더 순서" 표 추가).

| # | 호출 | 소유 |
|---|---|---|
| R1 | `Game.update_anim_clock()` | core |
| R2 | `player.render(alpha)` — 보간·반올림 → 애니·스쿼시·기울기·반동 | core |
| R3 | `camera.render(alpha)` — 2.6 공식 | core/vfx |
| R4 | `enemies.render(alpha)` | enemies |
| R5 | `projectiles.render(alpha)` → `queue_redraw` | combat |
| R6 | `vfx.render()`, `damage_numbers.render()` | vfx |

### 1.4 정수 스쿼시·스트레치 공식 (P2)

```
dy   = clamp(round(H × (1 − sy)), −cap_y, cap_y)     # +면 눌림(위가 내려옴), −면 늘어남
dx_s = clamp(round(W × (sx − 1) / 2), −cap_x, cap_x) # 한쪽 면 확장 px(좌우 대칭)
H = 등급 몸 높이 목표 중앙값, W = 몸 폭(피벗 데이터에서 읽음)
```

셰이더 구현 = **힌지 시프트**(리샘플링 없음):
- 세로: 출력 행 `r ≤ hinge_y`(허리 행) 는 원본 `r − dy` 행을 읽는다. 눌림이면 허리 바로 위 `dy`행이 사라지고, 늘어남이면 허리 행이 중복된다. **발끝 행은 절대 움직이지 않는다.**
- 가로: 피벗 x 기준 왼쪽 반은 `+dx_s`, 오른쪽 반은 `−dx_s` 만큼 원본을 당겨 읽는다(중심 열 중복/삭제).
- `hinge_y = pivot_y − round(0.45 × H)` (플레이어 58−21 = 37행). 엔티티별 덮어쓰기는 `data/anchors/<id>.json`의 `hinge_y`.
- 상한: 플레이어·잡귀 `cap_y 2 / cap_x 1`, 정예 `3 / 2`, 중간보스·보스 `4 / 2`.

등급별 대표값(H·W): 플레이어 46·28, 잡귀 S 21·16, M 29·20, L 36·24, 정예 64·40.

### 1.5 공통 스프라이트 셰이더 `shaders/actor_pixel.gdshader` (신규, vfx 소유)

플레이어(Sprite2D)와 적(MultiMesh, `enemy_instanced.gdshader`에 같은 함수 포함)에 쓰는 기능:

| 기능 | 입력 | 동작 |
|---|---|---|
| 프레임 선택 | `frame`, `dir_row` | [방향 행 × 프레임 열] 2D 아틀라스 셀 |
| 좌우 반전 | `flip` (0/1) | 셀 안에서 `u = 1 − u`. **west 텍스처 없음** |
| 스쿼시 | `dy`, `dx_s`, `hinge_y` | 1.4 힌지 시프트 |
| 기울기 | `shear_px` (−2..2), `hinge_y` | 2.1.6 상체 밴드 시프트 |
| 단색 플래시 | `flash_col_idx` (0 없음 / 1 hj / 2 jk / 3 jk_hi) | 알파 255 픽셀 중 `#1a1a1a`(ΔE<4)가 아닌 픽셀을 그 색으로 **완전 치환**(혼합 아님). 외곽선 보존 |
| 1px 오프셋 | `nudge` (정수 Vector2) | 피격 넛지·반동 |

좌표 계산은 정점 단계의 로컬 정수 픽셀(`floor(VERTEX)`, 원점=발)로 하고 마지막에 UV로 바꾼다. 그래서 반전 뒤에도 기울기·스쿼시 방향이 화면 기준으로 맞는다.
콘텐츠 여백 조건: 좌우 여백 ≥ `|shear_px| + dx_s`(최대 3), 위 여백 ≥ `|dy|`(최대 2, ART_STYLE 위 ≥3 충족). 부족한 엔티티는 quad를 2px 키운다(텍스처는 그대로).

---

## 2. 플레이어 이동

### 2.1 해결 대상과 설계

| DIAGNOSIS | 파일:라인 | 설계 |
|---|---|---|
| B4 | 전체(`flip_h` 0건), `player.gd:58-70` | 2.1.1 |
| B3 | `player.gd:7,61,65`, `:93-96` | 2.1.2 |
| A5 | `player.gd:117-118` | 2.1.3 |
| A5·B2 | `player.gd:59-62` | 2.1.4 |
| C-G5/L12, A5 | `player.gd:113-118` | 2.1.5 (블렌드·바운스) |
| (요청) 틸트 | — | 2.1.6 |
| A6·B6 | `player.tscn:9-14`, `sprite_lib.gd:92-93` | 2.2 |
| A2 | `game_camera.gd:41`, `player.gd:102` | 2.6 |
| B5 | `k.gd:54-72` | 2.1.7 |

#### 2.1.1 좌우 flip
- 아틀라스 행은 **S, E, N 3행만**. west = E 행 + `flip=1`. 기존 `*_west_*` 파일은 런타임에서 읽지 않는다(ART_STYLE L15).
- 반전축 = 피벗 x(64 캔버스의 열 31|32 경계). 열 c → 63−c. 몸 중심이 피벗 ±1이면 반전 후에도 ±1.
- AnimatedSprite2D를 **Sprite2D + 셰이더**로 바꾼다(프레임·반전을 셰이더가 직접 고르므로 AnimatedSprite2D 재생 로직이 필요 없다).

#### 2.1.2 걷기 재생 속도 = 이동 속도 비례
```
ratio      = clamp(|vel| / base_speed, 0.8, 1.6)      # base_speed = move.base_speed_u × 32 = 128px/s (stat_domu 미적용 값)
walk_phase += anim_dt × walk_fps × ratio / 8          # walk_fps 12, 8프레임
frame      = floor(fract(walk_phase) × 8)
```
| 상황 | |vel| | ratio | 사이클 길이 | 사이클당 이동 |
|---|---|---|---|---|
| 기본 | 128 | 1.0 | 0.667s | 85px |
| 군중 감속 하한 0.55 | 70 | 0.8(클램프) | 0.833s | 59px (발 미끄러짐 소폭, 허용) |
| 총 감속 하한 0.4 | 51 | 0.8 | 0.833s | 43px |
| 도무(속도) ×1.5 | 192 | 1.5 | 0.444s | 85px |
| 상한 ×2.0 | 256 | 1.6 | 0.417s | 107px |

#### 2.1.3 방향 전환 시 위상 유지
- `walk_phase`는 방향과 무관한 **하나의 값**이다. 방향이 바뀌면 행만 바꾸고 프레임 번호는 그대로(S/E/N 모두 8프레임, f0·f4 접지 포즈가 같은 위치라는 ART_STYLE 4.1 조건 전제).
- 반전(E↔W)도 같은 프레임을 유지한다. 반전 순간 1회 "턴 핀치" 스쿼시(2.4 표).

#### 2.1.4 idle 4f
- `idle_{s,e,n}_0..3`, 6fps(167ms), `idle_phase`는 idle 진입 시 0(f0 = 중립 포즈). 정지 단독 PNG(`south.png` 등)는 런타임에서 쓰지 않는다.
- 박 동기 옵션: `frame_len = max(beat_len/4, 70ms)` (ART_STYLE 4.1). 기본은 꺼짐.

#### 2.1.5 정지↔이동 블렌드 (알파 크로스페이드 금지 → 포즈 전이 규칙)
| 전이 | 규칙 |
|---|---|
| 정지 → 이동 | walk f0(=idle_0과 같은 자세, L12)에서 시작, `walk_phase=0`. 출발 스트레치 4틱(2.4) |
| 이동 → 정지 | 현재 프레임이 접지 포즈(f0/f4)에서 **±1프레임 이내**면 그 접지 포즈까지 ×1.5 속도로 마저 재생(최대 2프레임 = 0.11s) 후 idle f0. 아니면 즉시 idle f0 |
| 정지 착지 | idle f0으로 들어가는 순간 "착지 스쿼시" 6틱(2.4) |
| 판정 | 이동 시작 `|vel|² > 16`(현행 `player.gd:113`), 정지 `|vel|² < 9`(히스테리시스로 경계 떨림 제거) |

**미세 바운스:** 파일럿 walk 프레임 자체에 상하 1px 운동이 그려져 있으면 코드 바운스는 0이다(이중 바운스 방지). 그림에 없을 때만 f1·f5(체중이 실리는 프레임)에서 `dy=+1` 1프레임 길이 동안 적용.

#### 2.1.6 이동 방향 기울기(틸트) — 회전 금지, 스텝 스큐
- 명목각 `θ = 5° × clamp(vx / base_speed, −1, 1)` (좌우 성분만, 남북 이동은 0). 목표각으로 `1 − exp(−14·dt)` 지수 추종.
- 셰이더: 허리 위 행 `r < hinge_y`만 `shift(r) = round((hinge_y − r) × tan θ)` 만큼 가로 시프트. 다리는 수직 유지.
- 플레이어(허리→머리 약 25행): tan5° × 25 = 2.2 → **머리 최대 2px**. `|shift| ≤ 2` 상한(±4°→2px, ±6°→2px).
- 밴드 떨림 방지: 연속값이 반올림 경계를 ±0.15 넘어야 밴드가 바뀐다.
- 대안(셰이더 미도입 시): 상체 1px 통째 오프셋(`|θ| ≥ 2.5°`면 1px). 적에게는 기울기를 쓰지 않는다(군중 노이즈 방지, 그림의 머리 흔들림 1px로 충분).
- "모션 줄이기" 옵션이 켜지면 0(7장).

#### 2.1.7 4방향 구간 (B5)
`K.dir4_from_vec`: E/W 중심 ±55°, N/S 중심 ±35°, 현재 방향 유지 히스테리시스 10°. 동점 시 현재 방향 유지. 적은 추가로 **최소 유지 0.25s**(B16).

### 2.2 발 앵커 기준 그리기 (A6·B6)
| 항목 | 현재 | 설계 |
|---|---|---|
| 스프라이트 정렬 | 캔버스 중앙(`centered`) | `centered=false`, `offset = −pivot = (−32, −58)` |
| 피벗 데이터 | 없음 | `sync_art.py`가 manifest에 `pivot`, `body_h`, `body_w`, `hinge_y` 기록(ART_STYLE 1.3 표 기본값, `data/anchors/<id>.json`이 있으면 덮어씀) |
| 크기가 다른 애니 | `sprite_lib.gd:92-93` NEAREST 리사이즈 | **피벗 기준 패딩**만(리사이즈 삭제) |
| 시뮬 좌표 의미 | 스프라이트 중심(관례) | **발(지면 접점)**. 충돌 원 중심도 여기 — 수치는 그대로라 게임플레이 영향 없음. 화면상 스프라이트가 몸 높이 절반만큼 위로 올라간다 |
| 카메라 대상 | 플레이어 원점 | 원점 + `(0, −round(body_h/2))` = `(0, −23)` 고정 정수 오프셋(화면 구도 유지) |
| 투사체 그리기 높이 | 시뮬 좌표 | 시뮬 좌표 + `(0, −lift)`, 아군 `lift 16`(손 앵커 높이), 적 탄 `lift 10`. 충돌은 지면 좌표끼리 |
| 이펙트 기준점 | 적 좌표 | 타격 스파크 = 적 발 + `(0, −round(body_h/2))`, 데미지 숫자 = 발 + `(0, −body_h − 4)` |

### 2.3 그림자
| 항목 | 값 |
|---|---|
| 위치 | 발 원점 `(0, 0)`, 타원 중심 = 발끝 행. 스쿼시·기울기·반동·넛지·hurt에 **영향받지 않음**(그림자는 몸과 같이 밀리지 않는다. 넉백은 시뮬 이동이라 함께 움직임) |
| 형태 | 폴리곤 → **픽셀 타원 텍스처**(무외곽선). 플레이어 18×5, 잡귀 S 12×3, M 14×4, L 18×4, 정예 `round(w×0.6)`×6 |
| 색·알파 | 텍스처 픽셀 = `#0e0b16`(mk0), 알파 255(L2·L3 통과). 그리기는 `modulate.a = 0.45` — ART_STYLE 3.3 "셰이더·블렌드 지정" 예외로 등록(10장 결정 ①) |
| 떠 있는 귀신 | 가상 발끝 = 그림자 중심. glide 애니의 몸만 출렁, 그림자 고정 |
| 해원 상승 | 그림자는 제자리, 상승분만큼 1px씩 줄어듦(18→16→14, 짝수 폭 유지) |

### 2.4 플레이어 스쿼시·스트레치 표 (H 46, W 28, cap 2/1)
| 이벤트 | 명목 배율 | dy / dx_s (px) | 길이(틱) | 이징(단계) |
|---|---|---|---|---|
| 착지(이동→정지) | x1.06 / y0.94 | +2 / +1 | 6 | 3틱 (2,1) → 3틱 (1,0) → 0 |
| 출발(정지→이동) | x0.97 / y1.04 | −2 / 0 | 4 | 2틱 −2 → 2틱 −1 → 0 |
| 걷기 바운스(그림에 없을 때만) | y0.98 | +1 / 0 | f1·f5 동안 | 프레임 동기 |
| 턴 핀치(E↔W 반전) | x0.94 / y1.0 | 0 / −1 | 3 | 단일 단계 |
| 피격(hurt) | x1.08 / y0.92 | +2 / +1 | 6 | 3틱 (2,1) → 3틱 (1,0) |
| 사망 시작 | — | 0 | — | death 애니에 맡김 |

### 2.5 발사 반동·hurt·무적 점멸
| 항목 | 값 |
|---|---|
| 발사 반동 | 조준 반대 방향 **2px**(8방향으로 양자화한 단위 벡터 × 2 → 정수). 단계 2틱 −2 → 3틱 −1 → 0. 렌더 전용. 여러 무구가 같은 박에 쏘면 **합이 아니라 최대값**. 대상 무구는 3.1 표 `recoil` 열 |
| hurt 덧씌움 | `hurt` 6f 중 2f 선택(ART_STYLE 4.1: f0 1px 밀림·눈 감음 / f1 복귀), 16fps(4틱/프레임) → 8틱. 걷기 위상은 계속 돈다 |
| 무적 점멸 | `modulate.a 0.45`(현행 `player_hit.gd:42-45`) **폐기** — 반투명 행위자 금지. 보임 6틱 / 숨김 3틱 토글. 그림자는 항상 보임 |
| 사망 | `death` 8f @10fps(0.8s) → f7 홀드 0.6s → 결과 화면(`run.gd:135-147` 지연 1.4s). 사망 순간 전역 히트스톱 150ms(T3) |

### 2.6 카메라 반올림 일원화 (A2)
```
P_f  = lerp(prev_pos, cur_pos, alpha) + (0, −23)      # 플레이어 보간 위치(카메라 대상점)
P_r  = round(P_f)                                     # 플레이어 렌더 기준 (스프라이트도 이 값에서 −(0,−23) 해서 그린다)
C    = 기존 데드존·룩어헤드·지수 추종(float, game_camera.gd:28-40 로직 유지, 입력만 P_f)
카메라 정지 상태(데드존 안, 목표 이동 없음)에서는 C = round(C) 로 내부값을 정수에 고정
cam  = P_r + round(C − P_f) + shake_int               # global_position (정수)
```
| 성질 | 이유 |
|---|---|
| 카메라가 따라갈 때 플레이어 화면 좌표 = `−round(C−P_f)` | 정상 추종에서 `C−P_f`가 일정 → 화면상 주인공 고정, **역전 0** |
| 카메라가 멈춰 있을 때 `cam = C` | C가 정수면 `round(x) + round(C − x) = C` → 월드 떨림 없음 |
| 적·투사체·VFX | `round(보간 좌표)` 정수 월드 좌표 − 정수 cam → 플레이어와 같은 격자 |
| 반올림 함수 | 전부 `floor(x + 0.5)` (GDScript `round`는 0.5에서 0 반대 방향이라 음수 좌표에서 어긋남 → `K.rnd()` 헬퍼 추가) |
| Camera2D 설정 | `position_smoothing_enabled=false`, `process_callback=IDLE`, `R3` 단계에서만 위치 설정 |
| 검증 | 직선 이동 300프레임 캡처에서 플레이어 화면 좌표 역전 **0회**(현재 x 42 / y 40), 카메라 정지 중 배경 타일 이동 0px |

---

## 3. 공격 모션

### 3.1 무구별 선딜·타격·후딜 타이밍 표
단위: VFX f(20fps, 1f = 50ms = 3틱). "타격 f"는 판정 프레임이며 duration 2배 홀드(ART_STYLE 4.1). 선딜은 **박 앞당김**(3.2)으로 재생하므로 판정 시각은 지금처럼 박 위에 남는다.

| 무구 | 원형 | 선딜 f (ms) | 타격 f (홀드 ms) | 후딜 f (ms) | 반동 | 선딜 표현 | 타격 표현 | 후딜 표현 |
|---|---|---|---|---|---|---|---|---|
| **신칼** `wpn_sinkal` (기본) | projectile return | **2 (100)** | **1 (100)** | **3 (150)** | 2px | 손 앵커에 신칼 등장 + 1px 황 `#f5d66b` 반짝 | 발사: 투사체 생성, 손 섬광 16px 1f | 반동 복귀, 술 잔상 없음(파일럿 범위) |
| 각궁 `wpn_gakgung` | projectile | 2 (100) | 1 (100) | 3 (150) | 2px | 시위 당김 섬광 | 화살 발사 | 반동 복귀 |
| 지전 `wpn_jijeon` | projectile 부채 | 2 (100) | 1 (100) | 4 (200) | 1px | 종이 펼침 | 5장 동시 발사 | 종이 조각 페이드 |
| 사인사검 `wpn_sainsageom` | projectile 관통 | 3 (150) | 1 (100) | 5 (250) | 2px | 칼날 기 모음 | 검기 발사 | 검기 꼬리 |
| 월도 `wpn_woldo` | melee spin | 3 (150) | 1 (100) + 회전 시트 8f(400, `spin_time`) | 3 (150) | 0 | 칼 뒤로 젖힘 | 360° 판정 1회 | 잔상 3f |
| 삼지창 `wpn_samjichang` | melee line | 2 (100) | 1 (100) | 3 (150) | 0(앞 1px 런지) | 당김 | 찌르기 | 복귀 |
| 장창 `wpn_jangchang` | melee line ×3 | 2 (100) | 1 ×3 (간격 `thrust_iv` 100) | 3 (150) | 0(앞 1px) | 당김 | 연타 | 복귀 |
| 평곤 `wpn_pyeongon` | melee cone | 3 (150, `windup` 0.15) | 1 (100) | 4 (200) | 0 | 크게 젖힘 | 부채꼴 강타 + 넉백 | 먼지 |
| 부채 `wpn_buchae` | melee cone(백) | 2 (100) | 1 (100) | 4 (200) | 0 | 부채 접힘 | 돌풍 | 한지색 바람 |
| 방울 `wpn_bangul` | aura 상시 | 0 | 박마다 1 (50, 홀드 없음) | 2 (100) | 0 | — | 고리 1f 밝음 | 2f 감쇠 |
| 장구 `wpn_janggu` | aura pulse 온박 | 2 (100) | 1 (100) | 4 (200) | 0 | 채 들어올림 | "덩" 파동 | 파동 확장 |
| 호작도 `wpn_hojakdo` | aura pulse | 3 (150) | 1 (100) | 4 (200) | 0 | 그림 펼침 | 포효 파동 | — |
| 작두 `wpn_jakdu` | aura pulse(강) | 4 (200) | 1 (150, 3배 홀드) | 5 (250) | 0 | 작두 올라섬 | 내리침 + T2 히트스톱(적중 ≥3) | 파편 |
| 넋전 `wpn_neokjeon` | orbit | 2 (100, 생성) | 접촉 시 | 2 (100, 소멸) | 0 | 생성 | 접촉 스파크 | — |
| 명두 `wpn_myeongdu` | beam | 3 (150) | 1 (100) | 4 (200) | 0 | 거울 번쩍 | 광선 | 잔광 |
| 쑥물·소금·오방기·길베 | drop_zone | 2 (100, 투척) | 1 (착지) | 3 (150) | 0 | 투척 | 착지 판정 | 장판은 자체 수명 |
| 철질려 `wpn_cheoljillyeo` | trail | 0 | 1 (배치) | 2 (100) | 0 | — | 배치 | — |

규칙: 선딜 + 타격 홀드 ≤ 그리드 간격(`Beat.grid_sec()`)의 80%. 넘으면 선딜을 1f씩 줄인다(최소 1). 방울처럼 0.6s 주기 무구는 선딜 0.

### 3.2 선딜을 박 앞에 재생 (B13: "발사 틱에 바로 피해")
- `weapon_base.sim_step` 매 틱: `t_fire = Beat.request_fire(beat_key, cooldown(), downbeat)`(부작용 없음, 이미 있음). `t_fire − Game.beat_sec() ≤ windup_s`가 되는 첫 틱에 `_windup_start()` → 선딜 VFX 재생. 판정(`fire()`/`deal()`)은 지금처럼 `try_fire`가 true인 박 틱.
- 판정 프레임은 시트 메타 `impact_frame`(ART_STYLE 5)로 맞춘다: 선딜 시트가 `impact_frame`에 도달하는 시각 = 박 틱.
- 히트스톱으로 박을 건너뛰면(박 시계는 흐르고 시뮬은 멈춤, `combat_core.hitstop.clock_model`) 선딜을 취소하고 중립으로 복귀한다(발사 없는 선딜 잔상 금지).
- 근접 원형(`arch_melee_arc.gd:16-45,53-68`)의 벡터 선 그리기(`draw_arc` 0.15s)는 VFX 시트 재생으로 교체. 시트가 없는 무구는 지금 선을 유지하되 1px 정수 선폭·불투명 팔레트색으로(`col.a` 페이드 → 2f 간격 점멸).

### 3.3 투사체 회전 규칙 (A7·B14: `projectile_pool.gd:301-331`)
| 종류 | 규칙 | 신칼 적용 |
|---|---|---|
| 둥근 탄(적 탄 6/8/10/14, 구슬) | 방향 없음 | — |
| 회전체 | **사전 렌더 spin 시트 8f(45°)**, `frame = floor(age × 16) % 8`. `ang = age × spin` 계산 삭제 | **신칼: spin 8f @16fps(2회전/s), 16×16** (P3 파일럿) |
| 길쭉한 탄 ≤16px(화살·지전) | **8방향 스냅**: `idx = round(atan2(vy,vx) / 45°) mod 8`. 그림은 E·NE·N·SE 4장 + flip_h(W·NW·SW·S는 반전/대칭으로) — 광원 위배가 보이면 6장으로 늘림 | — |
| 길쭉한 탄 ≥24px(검기 32×16) | **16방향 스냅**(22.5°), 그림 5장(0·22.5·45·67.5·90°) + flip_h/flip_v | — |
| 방향 히스테리시스 | 귀환 탄(곡선 비행)은 구간 경계 ±5°를 넘어야 방향 프레임 변경 | 신칼은 spin이라 해당 없음 |
| 배율 | `proj_visual().scale`은 **정수 1 또는 2만**. 그 외 값은 1로 고정 + 경고 로그 1회 | 1 |
| `draw_set_transform` | 회전 0, 배율 정수, 위치 정수만 | — |
| VFX 회전·배율 | `vfx_pullil_enter` scale 0.6(`hit_feedback.gd:54`) → 1(32px 시트 사용), `vfx_toechi_burst` 임의 회전(`hit_feedback.gd:42`) → **4변형 반전**(flip_h/flip_v 조합, `Rng fx` 0..3), `vfx_player.gd:52-53` rotation·scale 인자는 정수 배율·반전 인덱스로 의미 변경 | — |

`proj_visual(tag)` 반환 계약(B0에서 구현하는 함수, 이 문서가 필드를 확정):
`{fx: StringName, trail: StringName, orient: &"none"|&"spin"|&"dir8"|&"dir16", fps: int, scale: int(1|2), lift_px: int, spark: StringName, recoil_px: int}`

### 3.4 타격 스파크
| 항목 | 값 |
|---|---|
| 에셋 | `vfx_hit_spark_red__pilot` 16×16, 4f @20fps: f0~f1 판정(홀드), f2~f3 소멸. 색 `#8c1f22 #c8322d #e4604f #f4a183 #e9dcc0` |
| 백 무구 변형 | **새 에셋 없이** 셰이더 램프 치환(jk 램프 → hj 램프 `#5a4a37…#e9dcc0`). 백 `#f2ece0` 사용 금지 |
| 위치 | 적 발 + `(0, −round(body_h/2))` + 공격 방향 반대로 3px(맞은 면) |
| 방향 | 4변형 반전, 회전 없음 |
| 상한 | 프레임당 신규 12개, 같은 적 100ms당 1개, 풀 64(타입별 64 상한, ARCHITECTURE 7) |
| 지속 피해(장판·오라 틱) | 스파크 없음(플래시만) |

---

## 4. 적 군중

### 4.1 애니 연결 (A4·B1: `sprite_lib.gd:71-100`, `enemy_manager.gd:760`, `enemy_instanced.gdshader:21-25`)
| 항목 | 값 |
|---|---|
| 아틀라스 | `SpriteLib.anim_atlas(id, "move", [S,E,N])` → 행 3 × 열 4(프레임). `glide/float` 종은 해당 애니. 정지 단독 PNG 미사용 |
| 인스턴스 데이터 `INSTANCE_CUSTOM.x` | `frame + 8 × dir_row + 32 × flip + 64 × (dy + 4) + 576 × (dx_s + 2)` (정수 float, 최대 2879, 셰이더에서 `mod`/`floor`로 분해. dy −4..4, dx_s −2..2로 정예·보스 상한까지 수용) |
| `.y` 상태 비트 | 기존 1/2/4/8/16 유지 + **32 = 국소 정지 중**(디버그 표시용) |
| `.z` | 플래시 색 인덱스(0 없음 / 1 hj / 2 jk / 3 jk_hi) — 기존 0..1 명도 값 대체 |
| `.w` | 해원 디졸브 0..1(유지) |
| 위상 오프셋 | 스폰 시 `anim_phase[i] = Rng.randf_s(&"fx")` (0..1) |
| fps 지터 | `anim_rate[i] = Rng.range_s(&"fx", 0.9, 1.1)` (±10%) |
| 재생 속도 | `fps = species_fps(8~10) × anim_rate × clamp(|v| / speed[i], 0.8, 1.6)`; `|v| < 4px/s`이면 프레임 0 홀드(ART_STYLE 4.1 "정지 적 = move 0") |
| 위상 진행 | `R4` 렌더 단계에서 `anim_dt`로(히트스톱 정지). 국소 정지 중인 개체는 진행 안 함 |
| 방향 | 2.1.7 구간, 최소 유지 0.25s, west = E + flip |
| 피벗 quad | `_quad()`(`enemy_manager.gd:272-276`)를 `(−pivot.x, −pivot.y) ~ (w−pivot.x, h−pivot.y)`로. S(16,29)·M(20,36)·L(24,44) |
| 풀릴 기색 떨림 | `sin(TIME…)×0.5`(`:23`) → `step(0.5, fract(anim_time × 3.75 + id × 0.37))` = **정수 0/1px 토글**(약 3.75Hz) |
| 검증 | 같은 종 20마리 화면에서 동시에 다른 프레임 ≥3종, 시트 4f 모두 재생 |

### 4.2 피격 반응 (B8: `enemy_manager.gd:400-401,614`, `enemy_instanced.gdshader:45-51`)
| 항목 | 값 |
|---|---|
| 일반 피격 플래시 | **단색 `#e9dcc0`(hj4, "흰 플래시") 2틱**. 혼합이 아니라 치환, 외곽선 `#1a1a1a` 보존. 적·백 무구 공통 |
| 퇴치 일격 틴트 | 아래 4.4 순서(단색 `#c8322d`) |
| 풀릴 기색 대상 백 피해 | 플래시 hj 2틱 + 기존 백 외곽선 유지(비트 1) |
| 같은 적 재플래시 | 최소 간격 12틱(0.2s, 개체당 최대 5Hz) — 오라·장판 연속 틱이 화면을 깜빡이지 않게 |
| 피격 스쿼시 | 명목 x1.10/y0.90 → S `dy +2, dx_s +1` / M `+2, +1` / L `+2, +1`(cap). 3틱 (2,1) → 3틱 (1,0) → 0 |
| 국소 정지 | 이번 타격 피해 ≥ 한 최대치 × 0.25(`hitstop.local_freeze_dmg_ratio`)이거나 치명타면 **2틱**(`local_freeze_frames`) 동안 그 적의 이동·애니 정지. 넉백은 정지가 끝난 다음 틱에 시작. 전역 예산 미사용 |
| 피격 넛지(넉백 0인 타격) | 렌더 전용 1px, 맞은 방향, 2틱. 신칼·화살 등 `kb` 없는 무구 |
| 데이터 정리 | `flash.red_hit_tint_frames`·`local_freeze_frames` 참조 0건 → 이 표가 첫 참조. `white_hit_tint_alpha 0.4`는 폐기(단색 치환) |

### 4.3 넉백 (B9: `enemy_manager.gd:569-570,607-609,444-448`)
현재: `kb_u × 32`를 **속도**로 더하고 `exp(−10t)` 감쇠 → 총이동 `kb_u × 3.2px`(설계의 1/10). **설계: `kb_u`는 거리다.**

```
D      = kb_u × 32 × mass_factor[tier] × (giseak_factor if 풀릴 기색) × (dr_mult if 직전 넉백 후 dr_window 안)
D      = min(D, 남은 예산)        # max_disp_per_half_sec_u 3.0u = 96px / 0.5s 개체별
이동   = 정지 후 apply_time 0.12s(7틱) 동안 ease-out quad: s(t) = D × (1 − (1 − t/T)²), 틱 증분만 px/py에 더함
스태거 = 이어서 recover_time 0.05s(3틱) 동안 AI 목표속도 0, 그 뒤 기존 가속(τ 0.15s)
넉백 중 AI 속도 vx/vy = 0 (넉백을 상쇄하며 걸어오지 않게), 분리(_separate)는 계속
```
| 무구 | kb_u | 일반 잡귀 | 풀릴 기색(×0.5) | 정예(×0.25) | 중간보스(×0.1) | 보스 | 현재 실제 |
|---|---|---|---|---|---|---|---|
| 월도 | 0.6 | **19px** | 10 | 5 | 2 | 0 | 1.9 |
| 장구 | 0.6 | 19 | 10 | 5 | 2 | 0 | 1.9 |
| 작두 | 1.0 | 32 | 16 | 8 | 3 | 0 | 3.2 |
| 평곤 | 1.2 | 38 | 19 | 10 | 4 | 0 | 3.8 |
| 부채 | 1.5 | 48 | 24(당김 방향) | 12 | 5 | 0 | 4.8 |
| 신칼·화살 | 0 | 넛지 1px(렌더) | — | — | — | — | 0 |

- 정예에 넉백이 0이던 문제(`:611` `if not elite_plus`)를 `mass_factor`로 교체(정예 0.25 — DIAGNOSIS 표기 ×0.3은 데이터 0.25를 따른다).
- 넉백 중 스쿼시 `dy +1`(y0.95) 유지, 끝날 때 0.
- 저장소: `kb_dx, kb_dy, kb_t, kb_done, kb_budget, kb_budget_t, freeze_t`(SoA, 용량 2560).

### 4.4 사망 연출 (B12: `enemy_manager.gd:661-668,391-399`)
**퇴치(toechi) = 번쩍 + 파열** (`dying_t 0.1` → 0.15s)
| 틱 | 적 스프라이트 | 기타 |
|---|---|---|
| 0~1 | 단색 hj `#e9dcc0` | 국소 정지(이동·애니) |
| 2~5 | 단색 jk `#c8322d` + 부풂 `dy −1, dx_s +1`(x1.15/y0.90 의도를 정수로) | — |
| 6~8 | 단색 jk_hi `#e4604f`, `dy −2, dx_s +1` | 틱 6에 `vfx_toechi_burst`(4변형 반전) + 픽셀 파편 3~6개(≤8px 파티클, jk 램프, 정수 좌표) |
| 9 | 숨김 → 슬롯 해제 | 파열 시트는 VFX 시계로 계속(6f@20fps) |

**해원(haewon) = 상승** (`dying_t 0.55` 유지)
| 구간 | 값 |
|---|---|
| 애니 | move f0(중립) 홀드, 플래시 없음, 붉은색 없음 |
| 상승 | 6틱마다 −1px(총 −5px), 그림자는 2.3 규칙 |
| 디졸브 | 기존 아래→위 디졸브 + 백 가장자리(정상 판정, 유지). `c.a *= 1 − w×0.3`(`:63`) 반투명은 제거 → 디졸브 경계만으로 |
| VFX | `vfx_haewon_rise` additive(블렌드 지정 시트) |

**정예+**: 퇴치·해원 모두 위 순서 + 전역 히트스톱 `elite_result` 60ms + trauma 0.45(5장).

### 4.5 히트스톱 중 애니 정지
적 셰이더 uniform `anim_time`과 `R4`의 `anim_dt`가 0이 되므로 위상·플래시·스쿼시 타이머가 모두 멈춘다. 플래시가 걸린 적은 정지 동안 **단색 상태로 홀드**된다(고전적인 '흰 정지 프레임').

---

## 5. 화면 흔들림·히트스톱·플래시·데미지 숫자

### 5.1 화면 흔들림 (A8·B10: `juice.gd:73-80`)
현재: `trauma² × 0.7 × (6,4)px` 후 `round()` → T1 최대 0.09px, 플레이어 피격 0.38px, 정예 퇴치 0.51px로 모두 0px.

```
① 킥(방향성):  kick_px 정수, 방향 = 사건 방향(8방향 양자화), 단계 감쇠 [k, k−1, …, 0], 각 단계 2틱
② 노이즈:      a = A × trauma² × shake_scale            (A = max_offset_px (3, 3))
               n = simplex(t_q × freq) ∈ [−1, 1],  t_q = floor(t × 30) / 30   # 30Hz 홀드(240Hz 버즈 방지)
               o = sign(n·a) × max(1, round(|n·a|))  if |n·a| ≥ 0.35  else 0  # 최소 1px 보장
③ 합:          offset = clamp(kick + o, −cap, cap),  cap = 3px (보스 결과만 4px)
④ 카메라:      2.6 공식의 shake_int 로 더함(정수 보장)
```
| 항목 | 값 | 비고 |
|---|---|---|
| trauma 감쇠 | 1.8/s (유지) | 실시간, 히트스톱 중에도 |
| 지수 | 2 (유지, trauma 제곱) | |
| max_offset_px | **(3, 3)** (현재 (6,4)) | 상한 3px 설계 |
| 최소 1px 임계 | `|n·a| ≥ 0.35` | trauma 0.35 이상에서 확실히 1px이 나옴 |
| 샘플링 | 30Hz 홀드 | |
| roll | false (유지) | 회전 금지 |
| 기본 shake_scale | **1.0** (현재 0.7) | 진폭 자체를 줄였으므로. 옵션 7장 |

이벤트별 값:
| 이벤트 | 킥 px | trauma | 화면 최대 |
|---|---|---|---|
| 일반 타격·일반 퇴치 | 0 | 0 | 0 (P6) |
| 치명타 | 1 (공격 방향) | 0 | 1px |
| 같은 틱 퇴치 ≥8 | 0 | +0.2 | 0~1px |
| 플레이어 피격 | 2 (피격 반대 방향) | 0.30 | 2~3px |
| 플레이어 큰 피격(≥ hp 10%) | 2 | 0.45 | 3px |
| 작두 강타(적중 ≥3) | 1 (아래) | 0.25 | 1~2px |
| 정예 퇴치·해원 | 1 | 0.45 | 2px |
| 길닦음 닫힘 | 0 | 0.25 + 0.0025×면적, 상한 0.5 (유지) | 1~2px |
| 신명 오름 시작 | 0 | 0.5 | 2px |
| 중간보스 결과 | 2 | 0.8 | 3px |
| 보스 결과 | 3 | 1.0 | 4px (예외 cap) |

### 5.2 히트스톱 (A9·B11: `game.gd:113-123,145`, `juice.gd:136`)
| 티어 | ms | 틱(60Hz) | 대상 이벤트(`combat_core.hitstop.events_ms`) |
|---|---|---|---|
| T0 | 0 | 0 | 이동, 구슬 획득 |
| T1 | 0 (전역) / **국소 2틱** | 2 (그 적만) | 일반 타격, 치명타, 일반 퇴치 |
| T2 | 50~80 | 3~5 | `player_hit_big` 50, `elite_result` 60, `hosin` 70, `gildakkeum` 80, `byeoksa_oreum_start` 80, 작두 강타 50 |
| T3 | 100~150 | 6~9 | `sinmyeong_oreum_start` 100, `gildakkeum_large` 110, `bingui` 120, `mboss_result` 150, `eodukssini_vanish` 150, 플레이어 사망 150 |
| T4 | 150~200 | 9~12 | `boss_result` 200, `revive` 200 |

| 규칙 | 값 |
|---|---|
| 10초 창 예산 | 400ms (유지). **T2는 그중 200ms까지만** 사용. T3·T4는 400ms 전체 |
| T4 보장 | T4는 예산이 남지 않아도 최소 100ms(6틱) 적용(보스 결과가 길닦음 연타에 먹히지 않게) |
| 중첩 | `max_remaining` (유지) |
| 저티어 후 쿨다운 | 히트스톱 종료 후 0.3s 안의 T2 요청은 버림(`post_cooldown_low_tier`) |
| 단일 최대 | 200ms |
| 히트스톱 중 | 시뮬·연출 시계 정지(4.5), 흔들림 진행, 음악·박 진행, HUD 진행, 입력 버퍼링(현행) |
| 시그널 | `Events.hitstop_started(ms)` 구독자: `vfx_player`(정지), `damage_numbers`(정지), audio(선택: 저역 필터 70ms) |
| 호출 경로 | `HitFeedback`가 이벤트→티어 표(이 표)로 `Juice.feedback(tier, pos, strength)`를 부른다. 지금 `feedback()` 호출 0건 → 모든 연출 경로가 이 함수를 거치게 통일 |

### 5.3 플래시 상한
| 항목 | 값 |
|---|---|
| 전체 화면 플래시 횟수 | 초당 3회 이하(유지, `fullscreen_max_per_sec`), 연속 간격 ≥0.33s |
| 알파 상한 | 0.30 × `flash_scale` (현재 호출 0.18~0.35 → 0.30에서 자름) |
| 길이 | 0.06~0.20s, 감쇠는 2단계 계단(알파 a → a/2 → 0, 각 1/3 길이) |
| 색 | 팔레트만: 피격 jk `#c8322d`, 신명 hw `#e8b931`, 해원(고리·영가) **백 `#f2ece0` — 해원 전용** |
| 적 피격 플래시(국소) | 4.2: 개체당 5Hz 상한. 같은 틱에 화면 안 적의 40% 이상이 동시에 플래시되면 그 틱은 짝수 슬롯만 플래시(대면적 동시 점멸 방지, 광과민 대책) |

### 5.4 데미지 숫자 (`vfx/damage_numbers.gd`)
| 항목 | 값 |
|---|---|
| 폰트 | Galmuri11 FontFile, AA 0, 힌팅 없음, **기본 크기 고정(정수배만)**. 현재 크기 10/13/8 → 모두 기본 크기(추정 12px, 폰트 사양 확인)로 통일, 치명타만 첫 2틱 ×2 |
| 위치 | 발 + `(0, −body_h − 4)`, x ±4px 무작위(`Rng fx`) → 정수 |
| 움직임 | 0~2틱 팝(치명 ×2), 2~14틱 위로 8px(ease-out, 정수 계단), 14~32틱 정지, 32~36틱 2틱 점멸 후 소멸. 알파 페이드 없음 |
| 시계 | 연출 시계(히트스톱 중 정지, 팝 상태로 홀드) |
| 묶음 | 같은 적 0.15s 안의 타격은 합산해 한 숫자로 갱신(군중 노이즈 감소) |
| 동시 표시 상한 | 48 (풀 256 유지, 오래된 것부터 교체) |
| 색(팔레트) | red: 글자 `#e9dcc0` + 그림자 `#8c1f22` / white(풀릴 기색 대상 백 피해): 글자 `#f2ece0` + 그림자 `#0e0b16`(예약 용도 일치) / crit: `#e8b931` + `#561318` / locked: `#6f7780`(현재 비팔레트 `Color(0.55,0.52,0.6)` 교체) / player: `#e4604f` + `#0e0b16` / heal: `#55b8aa` + `#10302f` |
| 옵션 | 전부 / 치명·정예만 / 끔 (7장) |

---

## 6. 전체 수치 요약표 (구현 체크리스트)

| 구역 | 키(`feel.*`) | 값 |
|---|---|---|
| 걷기 | `walk.fps` / `ratio_min` / `ratio_max` / `frames` | 12 / 0.8 / 1.6 / 8 |
| idle | `idle.fps` / `frames` / `beat_sync_min_ms` | 6 / 4 / 70 |
| 정지 판정 | `move_on_sq` / `move_off_sq` | 16 / 9 |
| 정지 블렌드 | `stop_finish_window_f` / `stop_finish_speed` | 1 / 1.5 |
| 틸트 | `tilt.deg` / `max_px` / `rate` / `band_hys` | 5 / 2 / 14 / 0.15 |
| 반동 | `recoil.px` / `steps_ticks` | 2 / [2, 3] |
| 플레이어 스쿼시 | `squash.land` / `start` / `turn` / `hurt` | (+2,+1,6틱) / (−2,0,4틱) / (0,−1,3틱) / (+2,+1,6틱) |
| 스쿼시 상한 | `squash.cap` | 플레이어·잡귀 (2,1), 정예 (3,2), 보스 (4,2) |
| 무적 점멸 | `iframe_blink_ticks` | [6 보임, 3 숨김] |
| 사망(플레이어) | `death.fps` / `hold_s` / `hitstop_ms` | 10 / 0.6 / 150 |
| 적 애니 | `enemy.fps` / `jitter` / `ratio` / `still_v` | 8~10 / ±0.1 / 0.8~1.6 / 4px/s |
| 적 방향 | `dir.ew_half` / `ns_half` / `hys` / `enemy_min_hold_s` | 55° / 35° / 10° / 0.25 |
| 적 플래시 | `hit_flash_ticks` / `min_interval_ticks` / `color` | 2 / 12 / `#e9dcc0` |
| 적 피격 스쿼시 | `enemy_hit_squash` | (+2,+1) 3틱 → (+1,0) 3틱 |
| 국소 정지 | `local_freeze_frames` / `dmg_ratio` | 2 / 0.25 (기존 키) |
| 넛지 | `nudge_px` / `ticks` | 1 / 2 |
| 넉백 | `apply_time` / `recover_time` / `mass_factor` / `giseak` / `dr` / `cap` | 0.12 / 0.05 / 1·0.25·0.1·0 / 0.5 / 0.3s ×0.5 / 3u per 0.5s (기존 키, 해석만 거리로) |
| 퇴치 연출 | `toechi_seq_ticks` | hj 2 → jk 4 → jk_hi 3 → 해제 |
| 해원 연출 | `haewon_rise` | 6틱당 −1px, 총 0.55s |
| 공격 | `attack.<wpn>` | 3.1 표(선딜/타격/후딜 VFX f) |
| 투사체 | `proj.spin_frames` / `spin_fps` / `dir_snap` / `scale_allowed` / `lift` | 8 / 16 / 8 또는 16 / {1,2} / 아군 16·적 10 |
| 스파크 | `spark.frames` / `fps` / `per_frame_cap` / `per_enemy_ms` | 4 / 20 / 12 / 100 |
| 흔들림 | `shake.max_offset_px` / `min_px_threshold` / `sample_hz` / `cap_px` / `boss_cap_px` / `option_default_scale` | (3,3) / 0.35 / 30 / 3 / 4 / 1.0 |
| 히트스톱 | `hitstop.t2_budget_ms` / `t4_min_ms` / `max_single_ms` | 200 / 100 / 200 |
| 플래시 | `flash.alpha_cap` / `min_gap_s` / `crowd_ratio` | 0.30 / 0.33 / 0.4 |
| 숫자 | `dmg_num.rise_px` / `life_ticks` / `merge_s` / `max_visible` | 8 / 36 / 0.15 / 48 |
| 그림자 | `shadow.alpha` / 크기 | 0.45 / 2.3 표 |

---

## 7. 접근성 옵션 연결

| 옵션(설정 화면, ui 소유) | 단계 | 연결 | 기본 |
|---|---|---|---|
| 화면 흔들림 | 0 / 25 / 50 / 75 / 100% | `Juice.shake_scale`. 킥 px에도 곱함(`round`, 50% 이하에서 킥 최대 1px). 0%면 킥·노이즈 모두 0, 최소 1px 규칙 해제 | 100% |
| 화면 플래시 | 끔 / 50% / 100% | `Juice.flash_scale`(신규, `flash_enabled` 대체). 끔이면 전체 화면 플래시 0 | 100% |
| 적 피격 플래시 | 단색 / 외곽선만(외곽 1px만 hj) / 끔 | 셰이더 `flash_mode` uniform | 단색 |
| 히트스톱 | 기본 / 짧게(×0.5) / 끔(국소 정지만 유지) | `Game.request_hitstop` 앞단 배율 | 기본 |
| 모션 줄이기 | 켬/끔 | 켜면 틸트 0, 걷기 바운스 0, 반동 1px, 흔들림 상한 1px | 끔 |
| 데미지 숫자 | 전부 / 치명·정예만 / 끔 | `damage_numbers` 필터 | 전부 |

저장: `Save.set_value("settings.a11y.<key>", v)`(meta 소유 스키마 `save_profile.schema.json`에 `settings.a11y` 추가). 적용: 설정 화면이 `Juice`/`Game` 공개 필드를 직접 쓰고, 런 시작 시 `Juice._load_params()`가 저장값으로 덮는다. ARCHITECTURE 10장 ui TODO "설정(흔들림·플래시 옵션 → Juice)"이 이 표다.

---

## 8. 데이터 변경 (`../data/combat_core.json` → `sync_data.sh`)

- 새 구역 `feel`(6장 키 전부). 기존 키 수정: `shake.max_offset_px [3,3]`, `shake.option_default_scale 1.0`, `flash.white_hit_tint_alpha` 삭제(단색), `hitstop.t2_budget_ms 200`, `hitstop.t4_min_ms 100`.
- 무구별 타이밍은 `data/weapons.json` 각 무구에 `feel: {windup_f, impact_f, impact_hold, recovery_f, recoil_px, orient, spark}` (3.1 표).
- 피벗: `data/anchors/<id>.json` = `{pivot:[x,y], body_h, body_w, hinge_y, hand_r:[[x,y]…프레임별]}`. 없으면 ART_STYLE 1.3 등급 기본값. `sync_art.py`가 manifest에 병합.
- `game/data/`는 직접 고치지 않는다(ARCHITECTURE 6).

---

## 9. 구현 대상 파일과 순서

각 단계 끝에 `bash C:/Users/김태양/Desktop/KoreaLike/tools/godot_check.sh` → SCRIPT ERROR 0, 그리고 `--write-movie <절대경로>` 캡처를 Read로 직접 확인한다.

| 단계 | 파일 (소유) | 내용 | 해결 ID | 선행 |
|---|---|---|---|---|
| **0** | `weapons/weapon_manager.gd`, `weapons/weapon_base.gd` (combat) | B0 빌드 복구: `on_projectile_hit(slot,e,dmg,dir,tag,proj_index)`, `on_projectile_end(...)`, `proj_visual(tag)`(3.3 계약 필드) | B0 | — |
| 1 | `../data/combat_core.json`, `../data/weapons.json`, `../tools/sync_art.py`, `data/anchors/` (core·데이터) | `feel` 구역, 피벗 manifest | — | 0 |
| 2 | `core/k.gd`, `core/sprite_lib.gd` (core) | `K.rnd()`, 4방향 구간, `anim_atlas()`(3행×N열, 패딩, 리사이즈 삭제) | B5, A6, A4 | 1 |
| 3 | `autoload/game.gd`, `run/run.gd` (core) | 연출 시계, prev/cur 복사 규칙, 렌더 동기 단계 R1~R6, 히트스톱 티어 규칙, 사망 지연 | A3, B11, B12 | 2 |
| 4 | `shaders/actor_pixel.gdshader` (vfx, 신규) | 프레임·반전·힌지 스쿼시·밴드 기울기·단색 플래시·넛지 | B4, B8 | 2 |
| 5 | `player/player.gd`, `player/player.tscn`, `player/player_hit.gd` (core / combat) | Sprite2D+셰이더, 위상·속도비·idle·블렌드·바운스·틸트·반동, 발 피벗, 픽셀 그림자, 점멸 | B1~B4, A5, A6 | 3, 4 |
| 6 | `run/game_camera.gd` (core/vfx) | 2.6 반올림 공식, 대상점 (0,−23) | A2 | 5 |
| 7 | `autoload/juice.gd` (vfx) | 킥+양자화 노이즈+상한, `flash_scale`, 접근성 필드, `feedback()` 표 | A8, B10 | 3 |
| 8 | `enemies/enemy_manager.gd`, `shaders/enemy_instanced.gdshader` (enemies / vfx) | 2D 아틀라스, 위상·지터·속도비, 피벗 quad, prev 보간, 단색 플래시·스쿼시, 국소 정지, 넉백 거리 모델, 사망 연출, 정수 떨림, `anim_time` | A4, B1, B8, B9, B12, B16, A12 | 3, 4 |
| 9 | `projectiles/projectile_pool.gd`, `weapons/archetypes/arch_*.gd`, `weapons/weapon_base.gd` (combat), `autoload/beat.gd` (core, API 추가 불필요 — `request_fire` 사용) | 선딜 앞당김, VFX 시트 연결, 회전 규칙(spin/dir8/dir16), 정수 배율, lift, 반동 이벤트 | B13, B14, A7 | 0, 3 |
| 10 | `vfx/hit_feedback.gd`, `vfx/vfx_player.gd`, `vfx/vfx_lib.gd`, `vfx/damage_numbers.gd` (vfx) | 이벤트→티어 표, 스파크, 반전 4변형, 회전·0.6배 제거, 프레임별 duration(B15), 숫자 규칙 | B13, B14, B15 | 7, 8 |
| 11 | `ui/` 설정 화면, `autoload/save.gd`·스키마 (ui / meta) | 7장 옵션 | — | 7 |
| 12 | (별도 과제) `enemy_manager.gd` y-sort 버킷 | 발 y 기준 정렬 | A10, B7 | 8 |

ARCHITECTURE 계약 변경(리드 승인 필요): §4에 렌더 순서 R1~R6 추가, §2 Game에 `anim_time()/render_alpha`, Juice에 `flash_scale`, enemy_instanced 인스턴스 데이터 레이아웃(4.1) 갱신, `proj_visual` 반환 계약(3.3).

### 9.1 검증 기준
| 항목 | 방법 | 합격 |
|---|---|---|
| 플레이어 지터 | 직선 이동 300프레임 캡처, 화면 좌표 추적(`track.py`) | 역전 0회 |
| 카메라 정지 중 월드 | 데드존 안 이동 캡처 | 배경 이동 0px |
| 정수 좌표 | 셰이더·`_draw` 입력 로그 | 소수 좌표 0건 |
| 애니 연결 | 같은 종 20마리 | 동시 프레임 ≥3종, 4f 모두 등장 |
| 속도비 | 군중 감속 중 walk fps 로그 | 9.6~19.2fps 범위 |
| 흔들림 | 플레이어 피격 시 `shake_offset()` | 2~3px 정수, 0.5s 안에 0 |
| 넉백 | 월도 1회 적중 일반 잡귀 이동량 | 19±1px, 0.12s |
| 히트스톱 | 10초 창 로그 | T2 합 ≤200ms, 전체 ≤400ms, 정지 중 적 프레임 불변 |
| 플래시 | 1초 창 전체 화면 플래시 수 | ≤3 |
| 회전 | `draw_set_transform` 회전 인자 | 0 고정 |

---

## 10. 사용자 확인이 필요한 항목

1. **그림자 반투명**: 그림자 텍스처는 팔레트 `#0e0b16` 불투명이지만 `modulate.a 0.45`로 블렌드해 그린다(ART_STYLE 3.3 블렌드 예외로 등록). 완전 불투명(알파 255 그대로)을 원하면 `#17131f` 불투명 타원으로 바꾼다.
2. **피격 플래시 색 범위**: ART_STYLE 5장은 붉은 무구 피격 = `jk`였다. 이 문서는 1,000마리 군중이 붉게 맥동하지 않도록 **일반 피격 = hj 단색, jk = 퇴치 일격 전용**으로 좁혔다. 승인되면 ART_STYLE 5장 표를 고친다.
3. **physics_interpolation**: DIAGNOSIS 권장(`true`)과 달리 `false` 유지 + 수동 보간 단일화(1.2 이유).
4. **국소 정지를 시뮬에 넣음**: 타격받은 적이 2틱 실제로 멈춘다(결정론 유지, enemies 소유). 렌더 전용으로만 하길 원하면 넉백 시작 지연도 함께 빠진다.
5. **흔들림 기본값 1.0**: 진폭을 (3,3)px로 줄였으므로 기본 옵션을 0.7→1.0으로 올렸다.
