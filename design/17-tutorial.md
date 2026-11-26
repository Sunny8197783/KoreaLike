# 17. 튜토리얼 — 컨셉 인트로 · 연습 굿판 · 굿 안내서

- 작성: 2026-11-25 / 대상 빌드: 2026-11-26(목) '거의 완성'
- 요청(사용자): "게임 처음 안내가 조금 부족한거 같아. 어떤 컨셉이고 어떻게 플레이 해야하는지 어떤 걸 알아야하는지도 게임 튜토리얼을 만들어줘."
- 이 문서가 바꾸는 원칙: design/11 §13.1-1 "별도 튜토리얼 스테이지는 만들지 않는다"는 **이번 요청으로 개정**한다.
  실전 런 안의 길잡이(`game/ui/guide.gd`, 첫 런 힌트)는 그대로 두고, 그 **앞에 선택형** 튜토리얼 3종을 더한다.
  1. **컨셉 인트로**(카드 6장, 첫 실행 자동, 건너뛰기·다시 보기)
  2. **연습 굿판**(조작형, 약 5분, 실패 없음, 단계 게이트)
  3. **굿 안내서**(도움말 8쪽, 타이틀·쉼 메뉴에서)
- 정본 우선순위: 현재 코드 > 이 문서 > design/11 §13. 용어는 design/01 캐논 그대로 쓴다.
- 구현: 두 에이전트가 병렬로 한다(§7 계약). **이 문서는 구현된 규칙에만 기댄다**(§1 코드 확인).

---

## 0. 한눈에

```
첫 실행 ─▶ 컨셉 인트로(6장) ─▶ "연습 굿판을 해 볼까요?"
                                  ├─ [연습하기] ─▶ 연습 굿판(10단계, 약 5분) ─▶ 끝 화면
                                  │                                   ├─ [굿판 열기(실전)] ─▶ 첫 굿판(만신 직행)
                                  │                                   ├─ [다시 연습]
                                  │                                   └─ [타이틀로]
                                  └─ [바로 굿판 열기] ─▶ 첫 굿판(만신 직행, 기존 흐름)
이후 실행 ─▶ 타이틀. 메뉴 '길잡이' = 인트로 다시 보기 / 연습 굿판 / 굿 안내서
런 중 Esc ─▶ 쉼 메뉴 '굿 안내서'
```

핵심 감정 세 가지를 순서대로 겪게 한다.
- **시원함** — 붉은 무구로 깨는 파열(퇴치).
- **먹먹함** — 흰 무구로 풀어 사람 얼굴이 돌아오고, 그 넋이 뒤를 따르는 것(해원·영가).
- **신명** — 흰 길로 고리를 닫아 한꺼번에 풀려 나가는 순간(길닦음).

---

## 1. 지금 구현 확인 (코드 근거)

사양은 아래 사실 위에 선다. 구현 중 사실이 다르면 코드가 이긴다 — 이 표를 고치고 계속한다.

| # | 사실 | 근거(파일) | 튜토리얼에 주는 뜻 |
|---|---|---|---|
| F1 | 화면 라우터는 `scenes/main.gd`. 타이틀 → (신당) → 런 → 정산. `--autotest` 면 타이틀 없이 런. 런 씬은 매번 새로 만든다 | `scenes/main.gd` | '튜토리얼 모드로 런 시작' 진입점을 여기에 둔다 |
| F2 | 타이틀 메뉴 = 굿판 열기·신당·넋기록·설정·나가기. 신호 `start_requested(char_id)`, `lobby_requested`. 첫 실행(`Save.first_run_pending()`)이면 '굿판 열기' = 만신 직행 | `ui/title.gd` | 메뉴에 '길잡이'를 넣는다. 직행 흐름은 건드리지 않는다 |
| F3 | **`flags.tutorial_done` 은 '첫 판을 정산했다'는 뜻**이다. 첫 정산 때 Save 가 true 로 만들고, `first_run_pending()` = 끝낸 판 0 **그리고** tutorial_done=false. 이 값이 첫 판 만신 직행·첫 굿판 완화(`spawn_director._init_assist`)·신당 경유를 가른다 | `autoload/save.gd` 960행, `meta/meta_rules.gd` 185행, `waves/spawn_director.gd` 345행 | **연습 굿판은 tutorial_done 을 건드리면 안 된다.** 건드리면 첫 실전이 완화 없이 신당으로 간다. 새 플래그 `practice_done` 을 쓴다(§7.5) |
| F4 | `Game.begin_run()` → `Events.run_started` → Save 가 런 추적을 시작하고, 런 씬이 빠지면 ABANDON 으로 **정산**한다(판 수 +1, tutorial_done=true, 재화) | `autoload/game.gd` 323행, `autoload/save.gd` 750·892행 | 연습 굿판은 Save 런 추적에서 빠져야 한다(Save 최소 훅, §7.3) |
| F5 | `run_started` 는 음악·앰비언스·Juice·vfx 도 초기화한다 | `audio/*`, `vfx/*`, `autoload/juice.gd` | run_started 자체는 그대로 낸다(연출 초기화 필요) |
| F6 | `RunLedger._ready` 가 `ui.runs` 를 올리고, `guide.gd`·`hud.gd` 가 그 값으로 '첫 판' 안내·기운 바 숨김을 정한다. guide 는 `ui.hints_seen` 에 본 힌트를 쓴다 | `ui/run_ledger.gd`, `ui/guide.gd` 118행, `ui/hud.gd` 202행 | 연습 굿판은 판 수·본 힌트를 바꾸지 않는다(첫 실전 길잡이가 그대로 나오게) |
| F7 | `SpawnDirector.enabled=false` 면 스폰·이벤트·정예·중간보스·보스가 모두 멈춘다 | `waves/spawn_director.gd` 506행 | 기본 웨이브 끄기는 코드 수정 없이 된다 |
| F8 | 시련은 `TrialDirector.times`(03:00/06:30/12:30/15:30)·`hapil_time`(18:00)로 자동 시작. `start_now()` = 3초 예고 뒤 즉시 시련(F5 디버그와 같은 길). 첫 시련 후보 하나는 몸주신 보장 | `deities/trial_director.gd` 283·319·513행 | 연습 굿판은 자동 시련을 끄고(`times` 를 먼 값으로, `hapil_done=true`) 원하는 때 `start_now()` |
| F9 | 시련 흐름: 예고(OMEN) → 강림(두 원, ≤8초, 원에 들어가면 선택, 시간 지나면 자동 선택) → 확인 1초 → 시련(첫 시련 30초, 위엄·가호 두 게이지, 먼저 100% 찬 면 / 시간 끝 = 높은 쪽 미완) → 빙의 → **빙의 점지(멈춤)** → 여운 3초. **실패가 없다** | 같은 파일 | 시련 맛보기는 '틀릴 수 없는 단계'다 |
| F10 | 피해 해석: 한 ≤ 35% 면 풀릴 기색(흰 테두리, 이동 ×0.4, 접촉 ×0.3). 풀릴 기색 일반 잡귀에게 **붉은 무구는 한을 1 아래로 못 깎는다(매듭 잠금, '팅')**. 흰 무구 피해는 기색 대상에 ×풀이(기본 3). 한이 한 방에 0 이하로 깨지면 한 파열 퇴치. 기색 12초 뒤 맺힘 복귀(한 45%) | `enemies/enemy_manager.gd` 1943~2050행 | '깎고 푼다'를 그대로 보여 줄 수 있다 |
| F11 | 신칼 Lv1 피해 14(왕복 2타), 방울 Lv1 = 몸 둘레 2.5u 오라, 0.6초마다 3(기색 대상 ×3 = 9). 만신 시작 무구 = 신칼(0초)·방울(30초) | `data/weapons.json`, `data/characters.json` | 한 **18** 짜리 귀신은 신칼 1타에 기색(18−14=4 ≤ 6.3), 이어지는 신칼은 매듭 잠금. 한 10 객귀는 신칼 1타 한 파열 |
| F12 | 길베 4초, 걸음 4u/초 → 흰 길 최대 약 16u → **닫을 수 있는 고리 반지름 ≈ 2.2~2.5u**. 고리 안 넓이 ≥ 9칸. 고리 안: 풀릴 기색 = 해원, 일반 잡귀 한 ≤ 50% = 해원, 그 밖 일반 = 기색에 들여 한 1로 묶음. `ring.auto_knot`(접근성 '자동 매듭') = 스냅 2.5u | `haewon/ring_closure.gd`, `data/combat_core.json` | **방울 오라(2.5u)가 고리 안을 통째로 덮는다** → 방울을 받은 뒤 고리를 가르치면 방울이 먼저 다 풀어 버려 고리를 배울 수 없다. 그래서 연습 굿판은 **고리를 방울보다 먼저** 가르친다(§5.2 순서 근거) |
| F13 | `enemy_manager.debug_force_pullil()` = 살아 있는 적 전부를 풀릴 기색으로(공개 함수, F6 키) | 2798행 | 고리 단계 무리를 확실히 기색으로 만든다 |
| F14 | 영가: 해원한 사람 넋이 뒤를 따름, 수명 30초, 천도(수명·대신 맞기·고리·넘침). 대신 맞기는 행렬 9명 이상에서만 | `haewon/yeongga_train.gd`, `combat_core.yeongga.substitute_min_train=8` | 연습 굿판에서 대신 맞기는 보여 주지 않고 한 줄로만 말한다 |
| F15 | 살기: 일반 퇴치 1 = +0.02, 문턱 25/50/75 최초 도달 → 원귀 회귀(퇴치 상위 종, 1~3기, 한 ×4, 정예급). 퇴치 자리에 살 알갱이 | `haewon/haewon_system.gd` 37·317·586행 | 실제로 25까지 쌓으려면 퇴치 1,250번 → 연습 굿판은 **살기를 문턱까지 올리는 최소 훅**이 필요(§7.3) |
| F16 | 레벨업은 바로 열지 않고 run.gd 가 쌓았다가 연다(`_jeomji_flush`, 최대 90초 보류). `levelup.open_with(cands)` 는 후보를 직접 받는 공개 함수. 카드는 ◆ 붉은 / ○ 흰 띠, 카드 아래 진화 줄('진화 신장칼: Lv8+백지술') | `run/run.gd`, `ui/levelup.gd`, `weapons/weapon_manager.gd` 554행 | 점지 단계 전까지 레벨업을 막는 **게이트 훅**과, 가르치기 좋은 카드 3장을 고르는 `open_with` 를 쓴다 |
| F17 | 진화 = 무구 Lv8 + 짝 패시브(신칼 ↔ 백지술, 방울 ↔ 초혼 적삼) → 정예가 남긴 상자(길흉 상자·넋함)를 열 때. 결합 = 붉은 진화 + 흰 진화 → 양면 무구(예: 신장칼 + 넋꽃비 = 넋신칼) | `data/weapons.json` evolutions·unions | 안내서 '성장' 쪽 |
| F18 | 정산: 보스 해결 → 넋 비율 N_final ≥ 0.5 사자의 읍 / 미만 살 거둠(살 덩어리 3 × 30초) / 23:00 미해결 사자가 판을 거둠. 넋 → 공덕, 엽전 → 복전. 신당 로비(내림굿·단장·의뢰·진열장) | `waves/spawn_director.gd` 머리말, `design/01 §4.8` | 정산·신당은 한 장짜리 멈춤 카드로 설명 |
| F19 | 봇: `PlayerBot`(`--autotest`) 이 플레이어 입력을 대신한다. 시련 원 고르기·화신 둘레 돌기 로직이 있다. Save 는 `--autotest` 면 `save_profile_autotest.json` 을 쓴다 | `player/player_bot.gd`, `autoload/save.gd` 69행 | 연습 자동 테스트 봇은 PlayerBot 을 상속해 단계별로만 바꾼다 |
| F20 | 첫 30초 장단은 진양조 45BPM(박 1.33초, 양자화 1/4박), 03:00 중모리 80BPM | `data/waves_stage1.json` geori | 박자 단계는 느린 장단이라 박이 잘 보인다. 연습 중 03:00 장단 전환이 한 번 온다(그대로 둔다) |
| F21 | HUD 시계 옆 작은 마름모 2개가 박마다 밝아진다(박 머리 황) | `ui/hud.gd` `_draw_tc` | 박자 단계에서 "시계 자리 ◆ 깜빡임 = 박" 으로 가리킨다 |
| F22 | 쓸 수 있는 효과음 파일(일부): `sfx_ui_title_start`(장구 덩+촛불), `sfx_sys_deungbul`(촛불 훅+풍경, 순번별 음), `sfx_ui_card_select`(붓 한 획+인장 톡), `sfx_ui_nav`·`sfx_ui_skip`·`sfx_ui_confirm`·`sfx_ui_unlock`, `sfx_sys_hanpa`·`sfx_sys_haewon`·`sfx_sys_maedeup_lock`·`sfx_sys_pullil_enter`·`sfx_sys_yeongga_join`·`sfx_sys_cheondo`·`sfx_sys_gildakkeum`·`sfx_sys_wongwi_rise`·`sfx_sys_sal_drop`, `sfx_trl_omen`·`sfx_trl_sinjangdae`, `sfx_chaser_saja_eup`. **징 단독 효과음 파일은 없다** | `game/assets/sfx/` | 새 음원을 만들지 않는다. '징' 자리는 장구 덩(`sfx_ui_title_start`)으로 대신한다 |
| F23 | 컨셉아트는 `art/concept/`(게임 밖) — 게임 안에는 키아트(`game/ui/art/key_art_gutpan.png`)만 있다. `possession_variants.png` 의 장군은 일본 갑주라 **폐기**, `capsule_soulpath_beomtal.png` 위쪽 로고는 AI 글자라 **잘라서** 쓴다 | `art/ART-CONCEPT-INDEX.md` | 인트로에 쓸 그림은 **복사만** 한다(§4.3). 새 그림 생성 금지 |

---

## 2. 설계 원칙

1. **보여주고 → 해 보게 하고 → 이름 붙인다.** 이름(해원·길닦음·영가…)은 그 일이 처음 일어난 **직후**에 붙인다. 먼저 긴 설명을 하지 않는다.
2. **실패가 없다.** 명줄 무한(정기가 바닥나지 않는다), 시간 제한 없음, 막히면 도움이 단계적으로 커진다. 마지막 도움은 '이 단계 건너뛰기'.
3. **조작은 걷기 하나.** 새 버튼을 만들지 않는다. 확인(Enter/Space/A)은 멈춘 카드·끝 화면에서만 쓴다.
4. **대칭(P3).** 퇴치를 '하면 안 되는 일'로 말하지 않는다. 살·원귀는 '결과'로만 말하고, 퇴치 쪽 이점(빠르다, 원혼 구슬이 온전히 모인다)도 같이 말한다. '선·악·죄·카르마' 금지.
5. **화면 문장은 짧고 쉽게.** 목표 줄 1줄(한글 24자 안팎), 보조 줄 최대 2줄. 한 번에 새 이름 하나.
6. **실전 기록을 오염시키지 않는다.** 연습 굿판은 판 수·정산·재화·본 힌트·넋기록·업적에 아무것도 남기지 않는다(`practice_done` 플래그와 연습 기록만 예외).
7. **오컬트·한국풍 연출은 기존 자산으로.** 먹 번짐(기존 `shaders/dissolve.gdshader`), 붓글씨(`UiKit.brush()`), 붉은 인장(`ui/theme/skin/seal_red.png`), 한지 패널(`UiKit.draw_hanji_panel`), 등불(코드 드로잉 + `sfx_sys_deungbul`).

---

## 3. 첫 실행 흐름 · 메뉴 (D)

### 3.1 첫 실행

1. `main._go_title()` → 타이틀 `_ready`.
2. 타이틀은 `Save.flag("intro_seen") == false` 이고 `Game.autotest == false` 이면 **컨셉 인트로**를 바로 띄운다(메뉴는 뒤에서 어둡게).
3. 인트로를 다 보거나 건너뛰면 `Save.set_flag("intro_seen")`.
4. 이어서 `Save.flag("tutorial_offered") == false` 이면 **권유 창**:
   - 머리: "연습 굿판을 해 볼까요?"
   - 본문: "약 5분. 걷기만으로 귀신을 깎고 푸는 법을 배웁니다. 실패는 없습니다."
   - 버튼: **[연습하기]**(기본 초점) · **[바로 굿판 열기]**
   - 아래 작은 줄: "타이틀 '길잡이'에서 언제든 다시 할 수 있습니다"
   - 어느 쪽을 골라도 `Save.set_flag("tutorial_offered")`. Esc/B = 창 닫고 타이틀 메뉴(이때도 offered=true).
5. [연습하기] → 타이틀 신호 `tutorial_requested` → `main.start_tutorial()`.
6. [바로 굿판 열기] → 기존 '굿판 열기'와 같다(`_activate_menu(0)`: 첫 실행이면 만신 직행).

### 3.2 이후 실행

- 타이틀 메뉴: **굿판 열기 · 길잡이 · 신당 · 넋기록 · 설정 · 나가기**(6줄, 메뉴 칸 y 230 + i×17 → 마지막 줄 y 315, 아래 조작 안내 y 352 와 겹치지 않음).
- '길잡이' → 작은 하위 메뉴(같은 자리 교체): **인트로 다시 보기 · 연습 굿판 · 굿 안내서 · 뒤로**.
- `practice_done == false` 인 동안 '길잡이' 글자 오른쪽에 황 점 1개(새 소식 표지).

### 3.3 런 중 쉼 메뉴

| 모드 | 메뉴 |
|---|---|
| 실전 | 이어가기 · **굿 안내서** · 설정 · 굿판 거두기 |
| 연습 굿판(`Game.tutorial_mode`) | 이어가기 · **굿 안내서** · 설정 · **이 단계 건너뛰기** · **연습 그만두기**(두 번 눌러 확인, 기존 '굿판 거두기'와 같은 방식) |

- 이 단계 건너뛰기 → `Events.tutorial_skip_step_requested`(쉼 메뉴는 닫힌다).
- 연습 그만두기 → `Events.tutorial_exit_requested(&"title")`.
- 오른쪽 '굿의 법도' 요약 4줄(기존)은 그대로.

### 3.4 연습 굿판 끝난 뒤

- [굿판 열기(실전)] → `Save.first_run_pending()` 이면 만신 직행(첫 굿판 완화 그대로), 아니면 신당.
- [다시 연습] → `start_tutorial()` 다시(런 씬 새로).
- [타이틀로] → 타이틀.

---

## 4. 컨셉 인트로 (A)

### 4.1 동작

- 640×360 전체 화면. 카드 6장. 그림(위) + 붓 제목 + 문장 1~2줄.
- **넘기기:** Enter·Space·A·→·클릭 = 다음 / ←·Backspace·B = 이전 / **Esc·Start = 건너뛰기**(바로 끝, 확인 창 없음).
- 오른쪽 위에 항상 "건너뛰기 Esc ▶▶" 작은 글씨. 아래 가운데 진행 점 6개(지금 장 = 황 마름모).
- 자동 넘김 없음(읽는 속도는 사람마다 다르다). 단, 글자는 0.6초 동안 붓으로 쓰이듯 왼쪽부터 드러난다(그동안 '다음'을 누르면 글자를 다 보여 주고, 한 번 더 눌러야 넘어간다).
- 카드 전환: 이전 그림이 먹으로 번져 사라지고(`dissolve.gdshader` mode 1, 0.35초) 새 그림이 한지빛으로 떠오른다(mode 0 역재생, 0.35초). 접근성 `reduce_motion` 이면 0.2초 페이드.
- 배경 음악: 타이틀 음악 그대로(별도 BGM 없음). 카드마다 아래 효과음 한 번.
- 끝(또는 건너뛰기) → 권유 창(§3.1-4, 처음 한 번만) 또는 타이틀 메뉴(다시 보기일 때).

### 4.2 카드 6장

| # | id | 그림(게임 안 경로) | 제목(붓) | 문장(1~2줄) | 연출 |
|---|---|---|---|---|---|
| 1 | `intro_gutpan` | `res://ui/art/key_art_gutpan.png`(688×384, 타이틀처럼 화면 가득·느린 표류) | 밤의 굿판이 열린다 | 한 맺힌 넋들이 굿판으로 몰려든다. 당신은 무당이다. | 먹색 화면 → 장구 '덩'(`sfx_ui_title_start`, 징 자리 대신) → 0.4초 뒤 등불 켜짐(`sfx_sys_deungbul`) + 그림 밝아짐 |
| 2 | `intro_twist` | `res://ui/art/intro/intro_core_twist.png`(344×128, 원본 `art/concept/core_twist_v2.png`) | 깎고, 푼다 | 붉은 무구로 한(恨)을 깎는다. 흰 테두리가 보이면 흰 무구로 마지막 매듭을 푼다. | 왼쪽 두 칸(일그러진 얼굴→사람 얼굴) 위에 0.5초 흰 테 깜빡 → 3번째 칸 붉은 파열 때 `sfx_sys_hanpa`, 4번째 칸 때 `sfx_sys_haewon`. 그림 아래 작은 글씨 "◆ 붉은 = 퇴치 · ○ 흰 = 해원" |
| 3 | `intro_yeongga` | `res://ui/art/intro/intro_procession.png`(원본 `capsule_soulpath_beomtal.png` 688×384) — **잘라 쓰기** 영역 `Rect2(0, 128, 688, 232)`(로고 글자 제외), 화면 가로 640에 맞게 가운데 정렬 | 풀린 넋은 길동무가 된다 | 풀려난 넋은 흰 영가가 되어 뒤를 따른다. 함께 걷다 저승길로 떠난다. | 그림이 오른쪽에서 왼쪽으로 3px/초 천천히 흐름(행렬이 걷는 느낌) + `sfx_sys_yeongga_join` |
| 4 | `intro_gildakkeum` | `res://ui/art/intro/intro_gildakkeum.png`(344×192, 원본 `gameplay_mockup_gildakkeum.png`) | 흰 길로 고리를 닫으면 | 걸어온 흰 길로 한 바퀴 감싸면, 안의 넋이 한꺼번에 풀린다. 길닦음. | 그림 뜬 뒤 0.5초에 '덩'(`sfx_sys_gildakkeum`) + 그림 0.1초 밝게 번쩍(`reduce_motion` 이면 생략) |
| 5 | `intro_sal` | `res://ui/art/intro/intro_wongwi.png`(344×192, 원본 `wongwi_return.png`) | 한은 사라지지 않는다 | 퇴치는 빠르고 정당하다. 다만 깨진 자리에 살(煞)이 남아, 쌓이면 원귀로 돌아온다. | `sfx_sys_wongwi_rise`, 그림 붉은 눈 자리 0.6초 맥동(코드: 그림 위 반투명 적 점 3개는 넣지 않는다 — 그림 그대로) |
| 6 | `intro_road` | `res://ui/art/intro/intro_jeoseunggil.png`(344×192, 원본 `haewon_consoling_scene.png`) | 저승길까지 | 20분, 굿 한 판. 신령의 시련을 넘고, 끝에는 저승사자가 굿판을 거두러 온다. | `sfx_chaser_saja_eup`. 문장 아래 한 박 쉬고 태그라인 붓글씨 크게: **"깎아 부수거나, 풀어 보내거나."** + 붉은 인장(`seal_red.png`) 찍힘(`sfx_ui_card_select`) |

- 문장 글꼴: 본문 `UiKit.body()` 한지빛(`HANJI_UI`), 제목 `UiKit.brush()` 32~40px 외곽선 2.
- 그림 배율: 정수 배율만(픽셀아트). 344×192 그림은 1배로 한지 테(`draw_hanji_panel`, 4px 여백) 안에. 위치: 가로 가운데, y = 36.
- 제목 y ≈ 256, 문장 y ≈ 280·296(가운데 정렬, 폭 ≤ 520px, `UiKit.wrap` 2줄).

### 4.3 그림 복사 목록(새 생성 없음)

intro_ui 가 아래 파일을 **복사만** 한다(원본은 그대로). Godot 임포트 필터는 기존 UI 아트와 같게(Nearest, 밉맵 없음).

| 원본 | 복사 대상 |
|---|---|
| `art/concept/core_twist_v2.png` | `game/ui/art/intro/intro_core_twist.png` |
| `art/concept/capsule_soulpath_beomtal.png` | `game/ui/art/intro/intro_procession.png` |
| `art/concept/gameplay_mockup_gildakkeum.png` | `game/ui/art/intro/intro_gildakkeum.png` |
| `art/concept/wongwi_return.png` | `game/ui/art/intro/intro_wongwi.png` |
| `art/concept/haewon_consoling_scene.png` | `game/ui/art/intro/intro_jeoseunggil.png` |
| `art/concept/lobby_sindang.png` | `game/ui/art/intro/intro_sindang.png`(연습 굿판 정산 카드·안내서 8쪽) |

쓰지 않는 것: `possession_variants.png`(장군 일본 갑주, 폐기), `core_twist_toechi_vs_haewon.png`(폐기 인물).

---

## 5. 연습 굿판 (B)

### 5.1 모드 공통 규칙

| 항목 | 규칙 | 어떻게(계약 §7) |
|---|---|---|
| 무당 | 만신(`char_mansin`) 고정 | `start_tutorial()` 이 `Run.setup(&"char_mansin")` |
| 모드 표지 | `Game.tutorial_mode = true`(런 씬을 만들기 전에 켜고, 나갈 때 끈다) | main |
| 기본 웨이브 | 끔 | 디렉터 `_ready`: `SpawnDirector.enabled = false` |
| 자동 시련·합일 | 끔 | 디렉터 `_ready`: `TrialDirector.times = [1e9,1e9,1e9,1e9]`, `hapil_done = true` |
| 시작 무구 | 신칼만. 방울(30초 예약)은 지우고 '흰 무구' 단계에서 지급 | `WeaponManager.drop_schedule(&"wpn_bangul")`(최소 훅) → 나중에 `add_or_level(&"wpn_bangul")` |
| 명줄 | 무한. 정기 35% 아래면 70%로 채움(`Events.player_healed` 발신). 그래도 0이 되면 run.gd 가 죽음 대신 가득 채움 | 디렉터 + `run._on_player_died` 최소 훅 |
| 레벨업(점지) | '점지' 단계 전까지 열지 않고 쌓아 둔다 | `Run.jeomji_gate = false`(최소 훅) → 점지 단계에서 true |
| 살기 | 퇴치로는 거의 안 오르므로(F15) '살' 단계에서 문턱까지 올린다 | `HaewonSystem.add_salgi(d)`(최소 훅) |
| 저장 | 정산·판 수·재화·넋기록·본 힌트·업적 없음. 끝까지 마치면 `practice_done=true`, 연습 기록 `ui.practice_log`(§8.2)만 | Save·RunLedger·guide·levelup 최소 훅 |
| 길잡이(guide.gd) | **문장 힌트 줄과 guide 이름표만 끈다.** 풀릴 기색 화살표·고리 예상선(점선)·발밑 호·오프스크린 표지는 그대로 | guide `_hint/_show_now/_tag/_mark_seen` 에서 `Game.tutorial_mode` 면 return(본 힌트도 안 씀) |
| HUD | 시계 글자 자리에 "연습", 다음 시련 칩 숨김. 기운 바는 '살' 단계에서 `hud.reveal_giun()` 으로 연다 | hud 최소 훅 |
| 장단·거리 | 그대로(03:00에 중모리로 바뀜 — 숨기지 않는다) | — |
| 끝 | `Game.end_run(false, {"ending": &"tutorial"})` 를 불러 음악·연출을 정리(정산 화면 없음, Save 는 런 추적을 안 했으니 무시) | main `_on_tutorial_exit` |

#### 5.1.1 화면 배치(640×360, tutorial_hud = CanvasLayer layer 24)

| 요소 | 자리 | 모양 |
|---|---|---|
| 등불 줄(진행) | 아래 가운데 y = H−112, 등불 10개 간격 12px | 꺼진 등불 = 먹 테 한지 점, 켜진 등불 = 황(`HWANG_HI`) 불꽃 1px 깜박. 지금 단계 등불은 0.8Hz 은은히 |
| 목표 줄 | 아래 가운데 y = H−100 ~ H−84, 폭 ≤ 360 | 먹 띠(알파 0.8) + 황 테 1px, 굵은 본문 한지빛. 진척이 있으면 끝에 " (2/3)" |
| 보조 줄 | y = H−72, H−60(최대 2줄) | 작은 글씨 `HANJI_2`. 도움(`tutorial_help`)이 오면 이 줄을 바꾸고 0.3초 황으로 깜박 |
| 이름표(단계 완료) | 가운데 y ≈ 112 | 한자(작게, 있을 때) 위 + 한글 붓글씨 32px 외곽선 2 + 오른쪽 붉은 인장. 0.15초 붓 획 드러남 → 1.2초 유지 → 0.3초 먹 번짐. 소리 `sfx_ui_card_select`, 동시에 등불 켜짐 `sfx_sys_deungbul`(등불 순번 k → 토리 사다리 k번째 음은 오디오 쪽이 이미 처리) |
| 월드 이름표(B 채널) | 대상 위(월드 → 화면 변환) | 1~2단어 붓글씨 16px, 0.9초. 해원 표지는 백(#f2ece0), 그 밖은 한지빛 |
| 멈춤 주석(점지·빙의 점지·카드 위) | 위 가운데 y = 2~30, 폭 360 | 한지 띠(`draw_hanji_panel`) + 먹 글씨 1~2줄(design/11 §13.3) |
| 멈춤 카드(정산 단계) | 가운데 패널 420×240 | 한지 패널, 그림 + 제목 + 2줄, 아래 "Enter / A 다음" |
| 끝 화면 | 가운데 패널 460×250 | §5.4 |

- **개정(11-25 리드, 친구 플레이 '공격이 안 보인다' 피드백):** 위 표의 등불 줄·목표 줄·보조 줄 자리는 무당 발밑 바로 아래를 덮었다. 지금 코드: 등불 줄 = 위 '연습' 시계 양옆 5개씩(y=19, 거리 이름 줄·기운 바와 안 겹침), 목표 띠 = H−80~H−64, 보조 줄 = H−52·H−40. 묶음 밑에 무당·귀신이 들어오면 알파 0.4. 시련 중 이름표는 y≈112 대신 목표 띠 자리(그동안 목표 묶음은 숨김). 코드가 정본(`ui/tutorial_hud.gd`).
- 실전 guide 의 힌트 줄(y = H−84)은 연습 굿판에서 꺼져 있으므로 겹치지 않는다. 시련 안내판(deities, y 82~)·시련 게이지(y 37~78)는 위쪽이라 겹치지 않는다.
- 월드 표지(화살표·점선 경로·체크포인트·방울 반경 원)는 **tutorial_run** 의 `game/tutorial/tutorial_marks.gd`(World 안 Node2D)가 그린다. 색은 **황(#e8b931) 점선**(백은 해원 표지 예약색이라 쓰지 않는다, `UiKit.BAEK` 주석).

#### 5.1.2 도움 단계(모든 단계 공통 틀)

시간은 **그 단계 시작 뒤 게임 시각**(멈춤 시간 제외).

| 단계 | 기본 시각 | 하는 일 |
|---|---|---|
| L1 | 12~15초 | 월드 화살표(가장 가까운 목표) + 보조 줄을 더 쉬운 말로 |
| L2 | 30초 | 재시연(점선 경로·움직이는 점) 또는 목표를 더 가까이 다시 세움 |
| L3 | 60초 | 완료 조건을 느슨하게(단계별 표) |
| L4 | 120초 | 보조 줄 "막히면 Esc → 이 단계 건너뛰기" |

#### 5.1.3 완료 연출(모든 단계 공통)

1. 완료 조건 충족 → 0.4초 뒤(그 순간의 시스템 연출 — 파열·길닦음 — 을 덮지 않게) `tutorial_step_completed(id, name_label, hanja)`.
2. HUD: 이름표 붓글씨 + 인장 + 등불 켜짐(§5.1.1).
3. 1.6초 쉬고 다음 단계 시작. 다음 단계는 **멈춤 사유가 없을 때**(`not Game.is_sim_paused()`)만 시작한다(점지가 남아 있으면 기다린다).

### 5.2 단계 순서와 근거

| 순서 | id | 이름 | 배우는 것 | 예상 |
|---|---|---|---|---|
| 1 | `move` | 걷기 | 조작은 걷기 하나 | 10초 |
| 2 | `beat` | 장단 공격 | 무구는 박에 맞춰 저절로 / ◆ 붉은 = 퇴치 / 원혼 구슬 | 25초 |
| 3 | `cut` | 깎기 | 풀릴 기색(흰 테두리) · 매듭 잠금 | 25초 |
| 4 | `ring` | 고리 | 길베 · 고리로 한꺼번에 해원(길닦음) | 40초 |
| 5 | `white` | 풀기 | ○ 흰 무구(방울)로 해원 | 30초 |
| 6 | `yeongga` | 영가 행렬 | 풀린 넋이 뒤를 따르고 떠난다(천도) | 10초 |
| 7 | `jeomji` | 구슬과 점지 | 원혼 구슬 → 점지, 카드 읽기(◆/○, 진화 줄) | 30초 |
| 8 | `trial` | 시련 맛보기 | 원으로 고르기 · ◆ 꺾기(위엄) / ○ 모시기(가호) · 빙의 | 50초 |
| 9 | `sal` | 살과 원귀 | 퇴치 자리의 살 → 원귀 회귀(중립) · 기운 바 | 40초 |
| 10 | `settle` | 정산과 신당 | 저승사자 정산, 넋 → 공덕, 신당 | 20초 |
| | | | **합계** | **약 4분 40초 ~ 6분** |

**고리를 방울보다 먼저 가르치는 이유(코드 근거 F11·F12):** 방울 오라 반지름 2.5u 가, 길베 4초로 닫을 수 있는 고리 반지름(약 2.2~2.5u) 안을 통째로 덮는다. 방울을 쥔 채 고리를 그리면 고리가 닫히기 전에 방울이 무리를 다 풀어 버려 '한꺼번에'를 볼 수 없다. 반대로 방울 전에는 붉은 칼만 있으므로 매듭 잠금 때문에 **고리 말고는 풀 길이 없다** — "칼로는 안 끊긴다 → 흰 길로 감싸 푼다 → 몸주 신령이 흰 방울을 내려 준다"로 이야기가 이어진다. 사용자 요청의 최소 단계(이동·박자·붉은/흰·해원과 영가·고리·줍기와 점지·시련·살·정산)는 모두 들어 있고 순서만 이렇게 맞춘다.

### 5.3 단계 상세

표기: u = 32px. "앞" = 마지막 이동 방향(`player.last_move_dir`, 없으면 오른쪽). 스폰은 `EnemyManager.spawn(species, pos, opts)`, 진형은 `waves/wave_formations.gd`(`arc`, `ring_with_gaps`)를 읽기 전용으로 쓴다. 모든 스폰 opts 에 `intro_s: 0.4`(솟음 연출), 달걀귀신은 `no_variant: true`(아이 얼굴 변형 끔).

**목표 한 맞추기:** `han_max = han_base × 시간배율 × 살기배율 × han_mult`(enemy_manager.spawn). 디렉터는 같은 식을 Data(`enemies` scaling)로 계산해 `han_mult = 목표 / (han_base × 시간배율 × 살기배율)` 를 넘긴다. 스폰 직후 `em.han_max[slot]` 을 읽어 로그(`[tutorial] han sp=… max=…`)로 남기고, 목표 범위를 벗어나면 다음 스폰부터 보정한다.
- 기색 목표 한 = **18**(범위 15~21): 신칼 1타(14)에 기색(남은 한 ≤ 35%), 다음 타부터 매듭 잠금.
- 파열 목표 한 = 객귀 기본(약 10): 신칼 1타 한 파열.

스폰은 신호 처리기 안에서 하지 않는다(피해 해석 도중 스폰 금지 — haewon 규칙). 처리기는 표시만 세우고, 스폰은 디렉터 `_physics_process`(Run 의 틱 다음)에서 한다.

---

#### 단계 1 `move` — 걷기

| 항목 | 내용 |
|---|---|
| 시작 연출 | 먹색에서 0.6초 페이드인, 장구 '덩'(`sfx_ui_title_start`). 화면 가운데 붓글씨 "연습 굿판" 1.0초 |
| 목표 줄 | 걸어 보세요 |
| 보조 줄 | WASD·방향키 / 왼쪽 스틱 — 조작은 걷기 하나뿐입니다 |
| 스폰 | 없음 |
| 완료 조건 | 누적 이동 ≥ 4u(`player.global_position` 프레임 차 합) **그리고** 단계 시작 뒤 ≥ 2초 |
| 도움 | L1 8초: 무당 둘레 4방향 황 화살표 글리프 깜박(tutorial_marks) + 보조 "키를 누르고 있으면 무당이 걷습니다" |
| 이름표 | **걸음** (한자 없음) |
| 완료 뒤 보조 | 걷는 자리가 곧 길이 됩니다 |

#### 단계 2 `beat` — 장단 공격

| 항목 | 내용 |
|---|---|
| 목표 줄 | 귀신 쪽으로 걸어가세요 — 무구는 저절로 칩니다 |
| 보조 줄 | ◆ 붉은 신칼이 장단 박마다 날아갑니다. 시계 자리 ◆ 깜박임이 박입니다 |
| 스폰 | ① 즉시: 객귀(`enm_gaekgwi`) 3, 앞 6u 호(60°). ② 첫 퇴치 0.5초 뒤: 객귀 5, 무당 둘레 7u 원(틈 2곳). 합계 8 |
| 진척 | `tutorial_step_progress(&"beat", 퇴치 수, 5)` |
| 완료 조건 | 퇴치(`enemy_killed` kind = toechi) ≥ 5 |
| 월드 이름표 | 첫 퇴치 자리: **퇴치**(退治) |
| 박 강조 | 이 단계 동안만 tutorial_hud 가 `Events.beat` 마다 목표 줄 왼쪽 작은 장구 마름모를 0.15초 밝힌다(박 머리 = 황) |
| 도움 | L1 15초: 가장 가까운 귀신 화살표 / L2 30초: 객귀 3을 3u 둘레에 다시 세움 / L3 60초: 퇴치 3이면 완료 |
| 이름표 | **◆ 퇴치** (退治) |
| 완료 뒤 보조 | 퇴치한 귀신은 원혼 구슬을 남깁니다 — 가까이 가면 빨려 옵니다 |

(이 단계의 원혼 구슬은 그대로 주워진다. 레벨이 차도 점지 게이트가 닫혀 있어 창이 열리지 않는다 — 7단계에서 한꺼번에 연다.)

#### 단계 3 `cut` — 깎기(풀릴 기색·매듭)

| 항목 | 내용 |
|---|---|
| 목표 줄 | 붉은 칼로 깎아 보세요 — 흰 테두리가 생길 때까지 |
| 보조 줄 | 한(恨)이 줄면 얼굴이 돌아오고 흰 테두리가 생깁니다. 이것이 풀릴 기색입니다 |
| 스폰 | 달걀귀신(`enm_dalgyal_gwisin`) 5, 한 18, 앞 6u 호(90°) |
| 진척 | 풀릴 기색 수 / 3 |
| 완료 조건 | `pullil_entered` ≥ 3 **그리고** `enemy_hit` 중 `knot_locked = true` ≥ 2 |
| 월드 이름표 | 첫 `pullil_entered` 자리: **풀릴 기색** / 첫 매듭 잠금 타격 자리: **매듭**('팅' `sfx_sys_maedeup_lock` 은 이미 난다) |
| 도움 | L1 15초: 화살표 / L2 30초: 같은 달걀귀신 3을 3.5u 앞에 / L3 60초: 기색 2 + 잠금 1 |
| 이름표 | **풀릴 기색 · 매듭** (한자 없음) |
| 완료 뒤 보조 | 붉은 무구로는 마지막 매듭을 끊지 못합니다 |

- 남은 기색 귀신은 지우지 않는다 → 4단계 무리에 합류한다.
- 결단타(치명) 5%로 기색 귀신이 퇴치될 수 있다. 막지 않는다(이름표 없음, 실전 길잡이 몫).

#### 단계 4 `ring` — 고리(길베로 한꺼번에)

| 항목 | 내용 |
|---|---|
| 시작 | 무당 뒤 흰 길 위에 월드 이름표 **길베** 0.9초. `ring.auto_knot = true`(스냅 2.5u, 단계 끝나면 원래 값으로) |
| 목표 줄 | 흰 길로 흰 테두리 무리를 한 바퀴 감싸세요 |
| 보조 줄 | 걸어온 자리에 흰 길이 4초 남습니다. 처음 밟은 흰 길로 돌아오면 고리가 닫힙니다 |
| 스폰 | 무리 중심 C = 무당 앞 5u. 달걀귀신 6(한 18): C 1 + 반지름 0.8u 원 5. 0.6초 뒤 `em.debug_force_pullil()`(살아 있는 적 전부 기색) |
| 무리 유지 | 0.5초마다: 무리 반경 5u 안 기색 귀신 < 3 이면 C 둘레 0.8u 에 3 보충(0.6초 뒤 기색 강제). 맺힘 복귀(한 45%)한 귀신도 고리 안에서 '한 ≤ 50% = 해원' 규칙으로 풀리므로 그대로 둔다 |
| 완료 조건 | `ring_closed(area, haewon_count, centroid)` 에서 haewon_count ≥ 3 |
| 도움 | L1 12초: C 둘레 반지름 2.2u **황 점선 원** + 체크포인트 4개(밟을 때마다 하나씩 불 켜짐, 보조 "점을 차례로 밟아 동그랗게 걸어 보세요") / L2 30초: **재시연** — 흰 점 하나가 점선 원을 3.8초에 한 바퀴 그리며 되풀이(뒤에 짧은 흰 꼬리) / L3 60초: haewon_count ≥ 1 이거나 넓이 ≥ 9인 고리면 완료 / L4 120초: 건너뛰기 안내 |
| 고리 예상선 | 닫을 수 있게 되면 haewon 이 `gilbe_ready` + 점선 끝 매듭을 이미 그린다(guide.gd 월드 그림 유지). 소리 `sfx_sys_gilbe_close_ready` |
| 이름표 | **길닦음 · 해원** (解冤) — 고리 연출(만다라·'덩')이 끝난 0.4초 뒤 |
| 월드 이름표 | 고리 중심: **한꺼번에 ×N**(N = haewon_count) |
| 완료 뒤 보조 | 풀린 넋은 영가가 되어 뒤를 따릅니다 |

#### 단계 5 `white` — 풀기(흰 무구)

| 항목 | 내용 |
|---|---|
| 시작 연출 | `weapons.add_or_level(&"wpn_bangul")`(HUD 무구 칸 등장은 기존 연출). `hud.push_lane("몸주 신령이 방울을 내리셨다", true, 2.5)`. 소리 `sfx_ui_unlock` |
| 목표 줄 | 흰 테두리 귀신 곁으로 걸어가세요 — 방울이 풀어 줍니다 |
| 보조 줄 | ○ 흰 무구는 풀릴 기색을 해원합니다. 방울 소리는 몸 둘레에 닿습니다 |
| 스폰 | 달걀귀신 6(한 18), 앞 6u 호(90°). (신칼이 깎아 기색 → 방울이 해원) |
| 진척 | 흰 무구 해원 수 / 4 |
| 완료 조건 | `enemy_killed` kind = haewon, cause = &"white" ≥ 4 |
| 도움 | L1 15초: 방울 반경(2.5u × 도량) 황 점선 원을 무당 둘레에 + 기색 귀신 화살표 / L2 30초: 기색 강제 달걀귀신 3을 2u 앞에(스폰 0.6초 뒤 `debug_force_pullil`) / L3 60초: 해원 2 |
| 이름표 | **○ 해원** (解冤) |
| 완료 뒤 보조 | 빨간 걸로 깎고, 흰 걸로 풉니다 |

#### 단계 6 `yeongga` — 영가 행렬

| 항목 | 내용 |
|---|---|
| 목표 줄 | 뒤를 보세요 — 영가 행렬입니다 |
| 보조 줄 | 영가는 30초 함께 걸으며 곁의 귀신을 달랩니다. 그리고 저승길로 떠납니다(천도) |
| 스폰 | 시작 때 행렬 < 3 이면: 기색 강제 달걀귀신 4를 무당 둘레 1.5u 에(방울이 바로 풀어 영가가 된다) |
| 강조 | tutorial_marks: 행렬 맨 앞~맨 뒤를 잇는 황 점선 괄호 1.5초 |
| 완료 조건 | 단계 시작 뒤 ≥ 6초 **그리고** 행렬 수(`run.yeongga.count`) ≥ 3 |
| 월드 이름표 | 이 단계 중 `yeongga_cheondo(_, &"lifetime")` 가 오면 떠나는 자리: **천도** |
| 도움 | L1 10초: 위 스폰을 한 번 더 / L3 30초: 시간 조건만 |
| 이름표 | **영가 행렬** (靈駕) |
| 완료 뒤 보조 | 행렬이 길면 영가가 대신 맞아 주기도 합니다 |

#### 단계 7 `jeomji` — 원혼 구슬과 점지

| 항목 | 내용 |
|---|---|
| 목표 줄 | 원혼 구슬을 주우세요 |
| 보조 줄 | 구슬이 차면 점지 — 신령이 무구를 골라 줍니다 |
| 스폰 | 원혼 구슬 10개(`pickups.spawn_orb(pos, v)`), 앞 2u~9u 한 줄. 값 합 = (`Game.xp_next − Game.xp`) × 1.1 (나눠서) |
| 점지 열기 | 이 단계 중 첫 `Events.level_up` → 디렉터가 ① 가르치기 카드 3장으로 `levelup.open_with(cands)` ② `Run.jeomji_gate = true`(그동안 쌓인 레벨업은 levelup 의 대기 '점지 ×N' 으로 이어서 열린다). 단계 시작 때 이미 쌓인 레벨업이 있으면(앞 단계 구슬) 구슬은 그대로 뿌리고 2초 뒤 같은 방식으로 연다 |
| 가르치기 카드 3장 | `WeaponManager.get_offer_pool()` 에서: ① ◆ 붉은 **새** 무구 1(월도 우선, 없으면 아무 붉은 새 무구) ② ○ 흰 **새** 무구 1(부채 우선) ③ 패시브 **백지술**(`psv_baekjisul`, 신칼의 짝 — 카드에 '짝·진화' 줄이 나온다). 없는 자리는 `roll_offers(3)` 로 채운다. 이 한 번은 '덤' 점지다(레벨을 쓰지 않는다 — 연습이라 균형 무관) |
| 멈춤 주석(위 한지 띠) | 1줄: ◆ 붉은 = 깎아 퇴치 · ○ 흰 = 풀어 해원 — 하나를 고르세요 / 2줄: 카드 아래 '진화' 줄 = 무구 Lv8 + 짝 패시브 → 정예 상자를 열면 진화 |
| 완료 조건 | 첫 `Events.levelup_chosen` |
| 도움 | L1 15초: 가장 가까운 구슬 화살표 / L2 30초: `pickups.pull_all()`(구슬을 모두 끌어옴) |
| 이름표 | **점지** (點指) |
| 완료 뒤 보조 | 무구 칸은 여섯. 붉은 것과 흰 것을 고루 채우세요 |

- levelup 의 첫 점지 주석(`ui.hints_seen.jeomji`)은 연습 굿판에서 나오지 않는다(위 멈춤 주석이 대신한다, §7.3 ui 훅).

#### 단계 8 `trial` — 시련 맛보기

| 항목 | 내용 |
|---|---|
| 준비 | 남은 적은 `em.vanish(slot)` 으로 조용히 치운다(행렬은 그대로). 멈춤이 없을 때 `trials.start_now()` |
| 예고·강림(OMEN·DESCEND) | 목표: **두 원 중 하나로 걸어 들어가세요** / 보조: 들어가는 원이 곧 선택입니다 — 모실 신령을 고릅니다 |
| 도움(강림) | 강림 시작 즉시 두 원으로 황 화살표 2개. 8초가 지나면 시련이 알아서 고른다(F9) — 실패 없음 |
| 시련(TRIAL) | 목표: **◆ 무구로 화신을 치면 꺾기 · ○ 안내판 의례는 모시기** / 보조: 먼저 찬 쪽으로 실립니다 — 위엄(꺾기) 또는 가호(모시기) |
| 도움(시련) | 시련 12초에 두 게이지 모두 < 0.3 이면 보조를 번갈아(4초씩): "화신 곁에 서면 무구가 화신을 칩니다" ↔ "위 안내판의 의례를 따라 해 보세요". 시간이 끝나도 높은 쪽으로 실린다 |
| 빙의 점지(멈춤) | 멈춤 주석: **빙의! 신령의 권능을 하나 고르세요** |
| 진행 신호 | 디렉터가 `trial_phase_changed` 를 듣고 목표 줄을 바꾼다. 바꾸는 방법은 **`tutorial_step_started` 재발신**(같은 id·index, 새 goal/sub). HUD 는 같은 id 면 등불·이름표를 건드리지 않고 두 줄만 바꾼다 |
| 완료 조건 | `trial_resolved` 를 받은 뒤 `trial_phase_changed` 가 &"afterglow" 또는 &"dormant" |
| 이름표 | 면에 따라 **◆ 위엄** (威嚴) 또는 **○ 가호** (加護) |
| 완료 뒤 보조 | 시련은 ◆ 꺾어 위엄, ○ 모셔 가호. 실전에서는 네 번 옵니다 |

- 시련 HUD(게이지·안내판·공수 자막)는 deities 가 이미 그린다. 연습 HUD 는 아래 목표 줄만 더한다.
- 첫 시련 제한시간은 data 값(30초)을 그대로 쓴다.

#### 단계 9 `sal` — 살과 원귀

| 항목 | 내용 |
|---|---|
| 준비 | `hud.reveal_giun()` + `hud.flash_knots(1.5)`(기운 바와 살 매듭 눈금을 드러냄) |
| 9a 목표 | 객귀 무리를 붉은 칼로 퇴치하세요 |
| 9a 보조 | 퇴치한 자리에 먹빛 살 알갱이가 남습니다. 위 기운 바의 매듭이 살기입니다 |
| 9a 스폰 | 객귀 8, 무당 둘레 6u 원(틈 2곳) |
| 9a 월드 이름표 | 첫 살 알갱이(첫 퇴치 자리): **살**(煞) |
| 9b 전환 | 퇴치 6(또는 9a 20초) → `haewon.add_salgi(25.0 − Game.salgi + 0.01)` → 다음 틱 haewon 이 원귀 회귀(알갱이가 떠올라 1.2초 뒤 원귀 1기, `sfx_sys_wongwi_rise`) |
| 9b 원귀 추적 | `wongwi_return` 뒤 3초 동안 `enemy_spawned` 로 오는 핸들 중 `em.flags[slot] & F_WONGWI` 인 것을 기록. 1.5초 안에 하나도 없으면(퇴치 기록 0 등) 디렉터가 직접 `em.spawn(&"enm_gaekgwi", 무당 앞 6u, {wongwi: true, elite_plus: true, han_mult: 4.0, no_recycle: true})` |
| 9b 목표 | 원귀가 돌아왔습니다 — 퇴치하거나 풀어 보내세요 |
| 9b 보조 | 퇴치는 빠르고 정당합니다. 다만 살이 쌓이면 원귀로 돌아옵니다 / (2줄) 알갱이를 밟아 거두거나, 고리로 씻을 수 있습니다 |
| 월드 이름표 | 원귀 위: **원귀**(冤鬼) |
| 완료 조건 | 기록한 원귀가 모두 결말(`enemy_killed`, 퇴치·해원 어느 쪽이든) |
| 도움 | L1 15초: 원귀 화살표 / L3 45초: 원귀를 `em.vanish` 하고 완료 |
| 이름표 | **살 · 원귀** (煞 · 冤鬼) |
| 완료 뒤 보조 | 풀어 보낸 만큼 한지빛, 퇴치한 만큼 먹빛 — 기운이 마지막 손님을 정합니다 |

#### 단계 10 `settle` — 정산과 신당(멈춤 카드)

| 항목 | 내용 |
|---|---|
| 방식 | 디렉터가 `Events.tutorial_card(&"settle", card)` → tutorial_hud 가 `Game.push_pause(&"tutorial_card")` 하고 카드 2쪽을 보여 준다. 마지막 쪽에서 확인 → `pop_pause` + `Events.tutorial_ack(&"settle")` |
| 1쪽 그림 | `sprite:chaser_jeoseung_saja`(idle, 남향, 2배) |
| 1쪽 제목 | 저승사자 — 굿판을 거두는 이 |
| 1쪽 문장 | 20분이 다하면 마지막 손님을 보내고, 저승사자가 굿판을 거두러 옵니다. / 넋이 많으면 사자가 읍하고, 살이 많으면 함께 살을 거둡니다. 어느 쪽도 굿의 끝입니다. |
| 2쪽 그림 | `res://ui/art/intro/intro_sindang.png`(344×192, 1배) |
| 2쪽 제목 | 신당 |
| 2쪽 문장 | 풀어 보낸 넋은 공덕, 모은 엽전은 복전이 됩니다. / 신당에서 새 무구와 무당을 모시고 다음 굿판을 엽니다. |
| 소리 | 1쪽 `sfx_chaser_saja_eup`, 2쪽 `sfx_ui_nav` |
| 완료 조건 | `tutorial_ack(&"settle")` |
| 이름표 | **정산 · 신당** (한자 없음) |

### 5.4 끝 화면

- `Events.tutorial_finished(true)` → tutorial_hud 가 `push_pause(&"tutorial_end")` 하고 가운데 한지 패널:
  - 붓글씨 제목: **연습 굿판을 마쳤습니다** + 인장
  - 배운 것 세 줄(등불 아이콘과 함께, §8 측정 문장과 같다):
    1. ◆ 빨간 무구로 깎고, ○ 흰 무구로 푼다
    2. 흰 길로 고리를 닫으면 한꺼번에 풀린다
    3. 시련은 ◆ 꺾어 위엄, ○ 모셔 가호
  - 버튼: **[굿판 열기(실전)]**(기본 초점) · [다시 연습] · [타이틀로]
  - 아래 작은 줄: "더 알고 싶으면 쉼 메뉴(Esc) → 굿 안내서"
- 버튼 → `Events.tutorial_exit_requested(&"real" | &"again" | &"title")`(pop_pause 뒤).
- `practice_done` 저장은 디렉터가 `tutorial_finished(true)` 를 보내기 직전에 한다.
- 중간에 '연습 그만두기'로 나가면 `tutorial_finished` 를 보내지 않는다(practice_done 그대로).

### 5.5 `--tutorial-step=<id>` 준비 상태

중간 단계부터 시작할 때 디렉터가 앞 단계 결과를 대신 만들어 둔다.

| 시작 단계 | 준비 |
|---|---|
| `move`~`ring` | 없음 |
| `white` | 없음(이 단계가 방울을 준다) |
| `yeongga` | 방울 지급 + 단계 6 스폰 규칙 |
| `jeomji` | 방울 지급 |
| `trial`·`sal`·`settle` | 방울 지급 + `jeomji_gate = true` |

---

## 6. 굿 안내서 (C)

### 6.1 동작

- `game/ui/guidebook.gd`(+ `.tscn`), Control 전체 화면. 열기: 타이틀 '길잡이 → 굿 안내서', 쉼 메뉴 '굿 안내서'.
- 공개: `open(page: int = 0)`, `close()`, `signal closed`. 쉼 메뉴에서는 쉼 메뉴의 자식(설정 패널과 같은 방식), 닫으면 쉼 메뉴로.
- 조작: ←/→ · A/D · D-패드 좌우 · 마우스 화살표 = 쪽 넘김(`sfx_ui_nav`), 1~8 = 바로 그 쪽, Esc · Backspace · B = 닫기(`sfx_ui_back`). 쪽 넘김은 한지 넘기는 0.2초 슬라이드.
- 배치: 한지 패널 600×320(가운데). 위: 붓 제목 + 쪽 번호 "3 / 8". 왼쪽 그림 칸 220×200, 오른쪽 글 칸 330 폭 3~5줄. 아래: "← → 쪽 넘기기 · Esc 닫기" / 패드 "D-패드 · B 닫기".
- 모든 쪽에 키보드와 패드를 함께 적는다.
- **수치는 Data 에서 읽는다**: 시련 시각(`deities.constants.trial_times_s`, `hapil_time_s`), 길베 초(`combat_core.gilbe.duration_base`), 영가 수명(`characters.stat_base.stat_neok_sumyeong`), 살기 문턱(`combat_core.salgi.thresholds`), 풀릴 기색 문턱(`combat_core.han.giseak_threshold`). 하드코딩 금지.

### 6.2 8쪽

| 쪽 | id | 제목 | 그림(기존) | 본문(3~5줄) |
|---|---|---|---|---|
| 1 | `gb_controls` | 조작 | `char_mansin` walk 남향 2배 애니(`SpriteLib.anim_frames_any`) + 코드로 그린 키 모양 | 걷기: WASD·방향키 / 왼쪽 스틱·D-패드 · 쉼: Esc·P / Start · 점지 고르기: 1·2·3 또는 ←→ + Enter / D-패드 + A · 공격은 모두 저절로. 하는 일은 **어디로 걷느냐** 하나 · 전체 화면: Alt+Enter·F11 |
| 2 | `gb_flow` | 목표와 한 판 흐름 | 코드로 그린 20분 띠(거리 색 띠) + 아이콘: `ui/icons/ico_jing.png`(시련 표지), `sprite:boss_yeokryeo` 작게, `sprite:chaser_jeoseung_saja` 작게 | 20분 굿 한 판을 끝까지 치르면 된다 · 띠: 00:00 개막 → 03:00·06:30·12:30·15:30 시련 → 10:00 중간보스 → 18:00 합일 → 18:35 작두 강림 → 19:15 뒷전(공물상 대해원) → 20:00 마지막 손님(보스) → 저승사자 정산 · 장단은 진양조에서 단모리로 점점 빨라진다 |
| 3 | `gb_weapons` | 붉은 무구 · 흰 무구 · 매듭 | `ui/icons/wpn_sinkal.png`(◆ 표지), `ui/icons/wpn_bangul.png`(○ 표지), `sprite:enm_dalgyal_gwisin` + `shaders/white_outline.gdshader`(풀릴 기색 모습), `assets/vfx/vfx_maetim_knot.png` 첫 칸 | ◆ 붉은 무구는 한(恨)을 깎아 **퇴치**한다. 원혼 구슬이 온전히 모인다 · 한이 35% 아래면 흰 테두리 — **풀릴 기색** · 기색 귀신에게 붉은 무구는 마지막 매듭을 끊지 못한다(**매듭 잠금**) · ○ 흰 무구는 기색 귀신을 **해원**한다 · 드물게 치명타(결단타)는 기색도 단칼에 끊는다 |
| 4 | `gb_haewon` | 해원 · 영가 · 고리 | `sprite:yeongga_body_f`·`yeongga_body_m` walk 3명 줄, `assets/vfx/vfx_gildakkeum_knot.png` 첫 칸 | 해원한 사람의 넋은 **영가**가 되어 뒤를 따른다(30초, 곁의 귀신을 달램) · 행렬이 길면 영가가 대신 맞고 먼저 떠난다 — **천도** · 걸은 자리에 흰 길(**길베**)이 4초 남는다 · 흰 길로 한 바퀴 감싸 닫으면 **길닦음**: 안의 기색 귀신과 한이 절반 아래인 귀신이 한꺼번에 풀린다 · 닫을 수 있으면 점선과 매듭 표지가 뜬다 |
| 5 | `gb_trial` | 시련과 빙의 | `sprite:avatar_sansin` idle 2배, `assets/vfx/vfx_confirm_ring_sansin.png` 첫 칸 | 시련 때 신령 둘이 원으로 내려온다. **들어가는 원이 곧 선택** · 산통에 머물면 한 번 다시 물을 수 있다 · ◆ 무구로 화신을 치면 **위엄**(꺾기), ○ 안내판의 의례를 하면 **가호**(모시기) — 먼저 찬 쪽 · 이기면 **빙의**: 신령의 권능 하나를 고른다 · 18:00 모신 신령들이 **합일**한다 |
| 6 | `gb_sal` | 살과 원귀 | `assets/vfx/vfx_sal_grain_idle.png` 첫 칸, `assets/vfx/vfx_wongwi_form.png` 첫 칸, 코드로 그린 기운 바(한지빛/먹빛) | 퇴치한 자리에 **살 알갱이**가 남고 **살기**가 오른다 · 살기 25·50·75에서 알갱이가 뭉쳐 **원귀**로 돌아온다 · 알갱이를 밟아 거두면 벽사 기세가 차고, 고리·소금으로 씻을 수 있다 · 위 **굿판의 기운** 바: 풀어 보낸 만큼 한지빛, 퇴치한 만큼 먹빛. 20:00 손님의 얼굴(한형/살형)이 여기서 정해진다 · 어느 쪽도 끝까지 갈 수 있다 |
| 7 | `gb_growth` | 성장 — 점지 · 진화 · 결합 | `ui/icons/wpn_sinkal.png` → 화살표 → 진화 아이콘(`UiKit.weapon_icon("evo_sinjangkal")`), `assets/vfx/vfx_box_gilhyung_open.png` 첫 칸 | 원혼 구슬이 차면 **점지**: 카드 하나를 고른다(◆ 붉은 띠 / ○ 흰 띠, NEW·Lv) · 무구 6칸, 패시브 6칸 · **진화**: 무구 Lv8 + 짝 패시브 → 정예가 남긴 상자(길흉 상자·넋함)를 열 때 · **결합**: 붉은 진화와 흰 진화가 만나면 양면 무구 · 카드 맨 아래 줄이 진화·결합 조건을 알려 준다 |
| 8 | `gb_meta` | 정산과 신당 | `sprite:chaser_jeoseung_saja` idle, `res://ui/art/intro/intro_sindang.png` 잘라 쓰기 `Rect2(86, 40, 172, 120)` | 마지막 손님을 보내면 저승사자가 굿판을 거둔다 · 넋이 많으면 **사자의 읍**, 살이 많으면 **살 거둠**(원귀를 막으며 버틴다) · 쓰러져도 판은 정산된다 · 넋 → **공덕**, 엽전 → **복전** · 신당에서 봉헌해 새 무구·무당·신령을 모신다 |

- `sprite:<entity_id>` = `SpriteLib.anim_frames_any(id, "idle", "south")`(없으면 `dir_tex`). vfx png 의 '첫 칸' = 시트의 첫 프레임 영역(같은 이름 json 의 frame 크기).
- 4쪽 '한이 절반 아래' 는 F12 규칙(일반 잡귀 한 ≤ 50%)을 쉬운 말로 옮긴 것.

---

## 7. 모듈 간 계약 (E)

### 7.1 소유

| 에이전트 | 소유(새로 만들거나 고침) | 다른 파일 최소 훅 |
|---|---|---|
| **tutorial_run** | `game/tutorial/**`(디렉터·단계·스폰 제어·월드 표지·봇·문구), `scenes/main.gd` 의 튜토리얼 진입점·나가기 경로, `autoload/events.gd` 의 tutorial 신호 구역 | `autoload/game.gd`(변수 1), `run/run.gd`(게이트 변수 + 죽음 가드), `autoload/save.gd`(run_started 가드 1줄), `weapons/weapon_manager.gd`(`drop_schedule`), `haewon/haewon_system.gd`(`add_salgi`), `player/player.gd`(`set_bot`) |
| **intro_ui** | `game/ui/intro/**`(인트로 카드·권유 창), `game/ui/art/intro/**`(복사 그림), `game/ui/guidebook.gd`(+`.tscn`), `game/ui/tutorial_hud.gd`(목표 줄·등불·이름표·멈춤 주석·카드·끝 화면), `game/ui/title.gd`·`game/ui/pause_menu.gd` 메뉴 항목, 첫 실행 흐름(플래그 `intro_seen`·`tutorial_offered`) | `ui/guide.gd`·`ui/levelup.gd`·`ui/run_ledger.gd`·`ui/hud.gd` 의 `Game.tutorial_mode` 가드(§7.3) |

- **Events 신호 추가는 tutorial_run 만** 한다(intro_ui 는 쓰기만). 두 에이전트가 같은 파일을 고치지 않는다.
- intro_ui 는 tutorial_run 이 신호를 추가하기 전에도 컴파일되게 `Events.has_signal(&"tutorial_step_started")` 로 가드하고 연결한다. tutorial_run 은 `tutorial_hud.gd` 가 없어도 돌게 `ResourceLoader.exists` 로 가드한다.

### 7.2 신호 (Events, `# ─── tutorial ───` 구역, tutorial_run 이 append)

| 신호 | 인자 | 보냄 → 받음 | 뜻 |
|---|---|---|---|
| `tutorial_started` | `(from_step: StringName, total: int)` | tutorial_run → intro_ui(tutorial_hud) | 연습 시작. 등불 total 개 준비(from_step 앞 단계 등불은 켜 둔다) |
| `tutorial_step_started` | `(step_id: StringName, index: int, total: int, goal_text: String, sub_text: String)` | tutorial_run → tutorial_hud | 단계 시작(index 0부터). 같은 id 로 다시 오면 목표·보조 줄만 바꾼다(등불 그대로) |
| `tutorial_step_progress` | `(step_id: StringName, done: int, need: int)` | tutorial_run → tutorial_hud | 목표 줄 끝 "(done/need)" |
| `tutorial_help` | `(step_id: StringName, level: int, sub_text: String)` | tutorial_run → tutorial_hud | 도움 단계(1~4). sub_text 가 "" 이면 보조 줄 유지·깜박만 |
| `tutorial_tag` | `(text: String, hanja: String, world_pos: Vector2)` | tutorial_run → tutorial_hud | 월드 이름표(B 채널, 0.9초) |
| `tutorial_step_completed` | `(step_id: StringName, name_label: String, hanja: String)` | tutorial_run → tutorial_hud | 이름표 붓글씨 + 인장 + 등불 켜짐 |
| `tutorial_card` | `(step_id: StringName, card: Dictionary)` | tutorial_run → tutorial_hud | 멈춤 카드. `card = {pages: [{title: String, lines: Array[String], image: String}], confirm: String}`. image = `res://…png` 또는 `sprite:<entity_id>` |
| `tutorial_ack` | `(step_id: StringName)` | tutorial_hud → tutorial_run | 카드 끝까지 확인 |
| `tutorial_finished` | `(completed: bool)` | tutorial_run → tutorial_hud(끝 화면), main | 모든 단계 끝(true) |
| `tutorial_exit_requested` | `(next: StringName)` | tutorial_hud(끝 화면)·pause_menu → main | `&"real"` 실전 / `&"again"` 다시 연습 / `&"title"` 타이틀 |
| `tutorial_skip_step_requested` | `()` | pause_menu → tutorial_run | 지금 단계 건너뛰기(완료 연출 없이 다음 단계, 로그 `skip`) |

- `tutorial_ack`·`tutorial_exit_requested`·`tutorial_skip_step_requested` 는 ui → 로직 요청 신호다(기존 `pause_menu.quit_to_title` 과 같은 성격). Events 머리말의 'L3 구독자는 시뮬 상태를 바꾸지 않는다' 규칙의 예외로 events.gd 주석에 적는다.

### 7.3 함수 · 변수 · 최소 훅

| 이름 | 꼴 | 파일 | 추가 | 쓰는 곳 |
|---|---|---|---|---|
| `Game.tutorial_mode` | `var tutorial_mode: bool = false` | `autoload/game.gd` | tutorial_run | main 이 켜고 끈다. 읽기: save·run·guide·levelup·run_ledger·hud·pause_menu·tutorial_hud |
| `main.start_tutorial` | `func start_tutorial(from_step: StringName = &"") -> void` | `scenes/main.gd` | tutorial_run | `tutorial_mode=true` → `RUN_SCENE.instantiate()` → `setup(&"char_mansin")` → `TutorialDirector.new()`(from_step) 를 런의 자식으로 → `_swap`. 쉼 메뉴 `quit_to_title` 은 연결하지 않는다 |
| 타이틀 신호 | `signal tutorial_requested` | `ui/title.gd` | intro_ui | main `_go_title` 이 `has_signal` 가드로 `start_tutorial` 에 연결(tutorial_run) |
| 나가기 경로 | `func _on_tutorial_exit(next: StringName) -> void` | `scenes/main.gd` | tutorial_run | `Game.end_run(false, {"ending": &"tutorial"})` → `tutorial_mode=false` → real: `first_run_pending()` 이면 `_go_run(&"char_mansin")` 아니면 `_go_lobby()` / again: `start_tutorial()` / title: `_go_title()` |
| `TutorialDirector` | `class_name TutorialDirector extends Node`, `var from_step: StringName`, `func skip_step() -> void`, `const STEP_IDS` | `game/tutorial/tutorial_director.gd` | tutorial_run | `_ready`: 스폰 끔·자동 시련 끔(동기). `call_deferred("_begin")`: 무구 예약 지우기·게이트·HUD·봇·`tutorial_started` |
| `tutorial_hud` | `extends CanvasLayer`, 인자 없는 `new()`, layer 24 | `game/ui/tutorial_hud.gd` | intro_ui | 디렉터 `_begin` 에서 `ResourceLoader.exists` 가드 후 런의 자식으로 추가. Events tutorial_* 만 듣는다 |
| `Run.jeomji_gate` | `var jeomji_gate: bool = true` — `_jeomji_flush()` 맨 앞 `if not jeomji_gate: return` | `run/run.gd` | tutorial_run | 디렉터 |
| 죽음 가드 | `_on_player_died()` 맨 앞: `if Game.tutorial_mode: Game.hp = Game.hp_max; return` | `run/run.gd` | tutorial_run | — |
| Save 가드 | `_on_run_started()` 맨 앞: `if Game.tutorial_mode: return` | `autoload/save.gd` | tutorial_run | → `_run_live=false` 라 run_ended·런 씬 퇴장 정산도 자동으로 안 함 |
| `WeaponManager.drop_schedule` | `func drop_schedule(wpn_id: StringName = &"") -> void` — 시작 무구 예약 중 그 id(빈 값이면 전부)를 지움 | `weapons/weapon_manager.gd` | tutorial_run | 디렉터 `_begin` |
| `HaewonSystem.add_salgi` | `func add_salgi(d: float) -> void` — `_add_salgi(d)` 공개 래퍼(문턱·원귀 회귀 그대로) | `haewon/haewon_system.gd` | tutorial_run | '살' 단계 |
| `Player.set_bot` | `func set_bot(b: PlayerBot) -> void` — `_bot = b` | `player/player.gd` | tutorial_run | `--tutorial-autotest` 의 `TutorialBot extends PlayerBot` |
| 기존 공개 API(수정 없음) | `SpawnDirector.enabled`, `TrialDirector.times / hapil_done / start_now()`, `RingClosure.auto_knot`, `EnemyManager.spawn / vanish / debug_force_pullil / han_max / flags`, `PickupManager.spawn_orb / pull_all`, `levelup.open_with(cands)`, `WeaponManager.add_or_level / get_offer_pool / roll_offers`, `hud.reveal_giun / flash_knots / push_lane`, `Save.flag / set_flag / get_value / set_value` | 각 모듈 | — | tutorial_run |
| guide 가드 | `_hint()`·`_show_now()`·`_tag()`·`_mark_seen()` 맨 앞 `if Game.tutorial_mode: return`(문장 힌트·이름표·본 힌트 저장만 끔 — 이름표는 tutorial_hud 가 대신 단다. 풀릴 기색 화살표·고리 예상선·발밑 호·오프스크린 표지는 유지) | `ui/guide.gd` | intro_ui | — |
| levelup 가드 | `_first_note` 계산에 `and not Game.tutorial_mode` | `ui/levelup.gd` | intro_ui | — |
| run_ledger 가드 | `_ready` 의 `ui.runs` 증가와 `_on_run_ended` 기록을 `Game.tutorial_mode` 면 건너뜀 | `ui/run_ledger.gd` | intro_ui | — |
| hud 가드 | 시계 글자 → "연습", 다음 시련 칩 숨김(박 마름모는 그대로) | `ui/hud.gd` | intro_ui | — |
| pause_menu | §3.3 메뉴. 연습 중 '연습 그만두기' → `Events.tutorial_exit_requested(&"title")`, '이 단계 건너뛰기' → `Events.tutorial_skip_step_requested.emit()` | `ui/pause_menu.gd` | intro_ui | — |
| `Guidebook` | `open(page: int = 0)`, `close()`, `signal closed` | `game/ui/guidebook.gd` | intro_ui | title·pause_menu |

### 7.4 단계 id (두 에이전트 공용, 순서 고정)

`move` · `beat` · `cut` · `ring` · `white` · `yeongga` · `jeomji` · `trial` · `sal` · `settle` (total = 10)

### 7.5 세이브 플래그 · 값

| 키 | 쓰는 쪽 | 뜻 |
|---|---|---|
| `flags.intro_seen` | intro_ui | 인트로를 끝까지 보거나 건너뜀 |
| `flags.tutorial_offered` | intro_ui | 권유 창에 답함 |
| `flags.practice_done` | tutorial_run | 연습 굿판 10단계를 마침 |
| `ui.practice_log` | tutorial_run | 최근 5회 연습 기록 `[{t_total, steps: {id: {dur, help_max, skipped}}}]`(로컬만, §8.2) |
| `flags.tutorial_done` | **건드리지 않는다** | 기존 뜻(첫 판 정산) 유지 — F3 |

### 7.6 디버그 인자

| 인자 | 소유 | 동작 | 로그 |
|---|---|---|---|
| `--intro-test` | intro_ui | 타이틀이 `intro_seen` 과 상관없이 인트로를 바로 연다. 카드를 실시간 1.5초마다 자동 넘기고, 끝나면 권유 창을 1.5초 띄운 뒤 닫는다. `--ui-save=1` 이 아니면 플래그를 쓰지 않는다 | `[intro] card=<n>/6 id=<id>` · `[intro] offer` · `[intro] done skipped=false` |
| `--guidebook-test=<쪽\|all>` | intro_ui | 타이틀에서 안내서를 그 쪽(1~8)으로 연다. `all` 이면 1.2초마다 넘겨 8쪽 뒤 닫는다 | `[guidebook] page=<n>/8 id=<id>` · `[guidebook] done` |
| `--tutorial-autotest` | tutorial_run | `--autotest` 와 **함께** 쓴다(세이브가 autotest 프로필로 분리됨). main 이 타이틀 없이 `start_tutorial()`. `TutorialBot` 이 단계마다 움직이고, 멈춤 카드는 디렉터가 1.5초 뒤 스스로 ack, 끝 화면은 1.0초 뒤 종료(`Game.quit_game(0)`). 단계가 게임 시각 120초를 넘으면 `push_error` 후 강제 완료(→ godot_check 가 실패로 잡음). `--autotest` 없이 주면 경고하고 `practice_done`·`ui.practice_log` 를 쓰지 않는다 | `[tutorial] begin from=<id>` · `[tutorial] step=<id> start t=<초>` · `[tutorial] step=<id> help=<n> t=<초>` · **`[tutorial] step=<id> done t=<초> dur=<초> help=<최대>`** · `[tutorial] skip step=<id> t=<초>` · `[tutorial] finished t=<초> done=<n>/10` |
| `--tutorial-step=<id>` | tutorial_run | 그 단계부터 시작(§5.5 준비). `--tutorial-autotest` 와 함께 써도 되고, 혼자 쓰면 사람이 그 단계부터 해 본다(타이틀 건너뜀). 모르는 id 는 경고 후 `move` | `[tutorial] begin from=<id>` |

`t=<초>` = `Game.time_sec()` 소수 1자리.

**TutorialBot 단계별 행동**(`extends PlayerBot`, 시각은 게임 시각):

| 단계 | 행동 |
|---|---|
| move | 오른쪽으로 2.5초 |
| beat·cut·sal(9a) | 가장 가까운 적 쪽으로, 2u 안이면 그 둘레를 2u 로 돈다 |
| ring | 무리 중심(디렉터가 넘김) 둘레를 반지름 2.2u 로 돈다(PlayerBot 고리 궤적과 같은 방식) |
| white·yeongga | 가장 가까운 기색 적 쪽으로 1u 까지 |
| jeomji | 가장 가까운 구슬 쪽으로(점지 카드는 기존 autotest 자동 선택 0.6초) |
| trial·sal(9b 원귀) | `super.input(p)`(PlayerBot 의 시련 원 고르기·화신 둘레 돌기·적 회피) |
| settle | 제자리 |

**권장 검사 명령**(리드가 `tools/godot_check.sh` 에 단계로 넣어 주기를 요청):
```bash
GODOT=/c/Users/김태양/Desktop/Godot_v4.7.2-stable_win64_console.exe
# 연습 굿판 자동 완주(약 5분 게임 시각, ×4)
$GODOT --headless --path game --fixed-fps 60 --quit-after 12000 -- --autotest --tutorial-autotest --seed=1 --speed=4
# 인트로·안내서
$GODOT --headless --path game --quit-after 900 -- --intro-test
$GODOT --headless --path game --quit-after 900 -- --guidebook-test=all
# 캡처(무비는 절대 경로, 무음)
MOVIE_AT=60 MOVIE_ARGS="--tutorial-autotest --tutorial-step=ring" LOG_TAG=tutorial bash tools/godot_check.sh --movie
```
판정: 로그에 `[tutorial] step=<id> done` 10줄 + `[tutorial] finished … done=10/10`, 오류 0.

### 7.7 문서 반영

- `PLAY.md` §1 화면 흐름(첫 실행 인트로·권유·길잡이)·§4 인자 표: 각 에이전트가 자기 인자 줄을 append.
- `game/ARCHITECTURE.md` §3 신호 표(tutorial 구역)·§5 소유표(`tutorial/**` = tutorial_run 후속 소유: ui 와 core 합의 전까지 '리드')·§9 인자: 리드 통합 때.
- design/11 §13.1-1 은 이 문서가 대체한다(11 본문은 고치지 않고 이 문서를 가리킨다).

---

## 8. 측정 (F)

### 8.1 성공 기준

처음 하는 사람이 연습 굿판 직후, 열린 질문에 **자기 말로** 아래 셋을 말할 수 있으면 성공이다.

| # | 기대 문장(뜻이 같으면 인정) | 질문(유도 금지) |
|---|---|---|
| S1 | 빨간 걸로 깎고, 흰 걸로 푼다 | "귀신을 어떻게 처리했나요? 무구 색에 따라 뭐가 달랐나요?" |
| S2 | 흰 길(고리)로 감싸면 한꺼번에 풀린다 | "여러 마리를 한 번에 풀려면 어떻게 하나요?" |
| S3 | 시련은 ◆ 꺾기(위엄) / ○ 모시기(가호) | "신령의 시련에서는 무엇을 할 수 있었나요?" |

- 목표: 참가자 **70% 이상이 3개 모두**(design/11 K-3 '2런 안 70%'를 연습 굿판 1회로 앞당김). S1 단독은 85% 이상.
- 실패 처리: S2 가 낮으면 4단계 도움 L1 시각(12초)과 재시연을 앞당긴다. S3 가 낮으면 8단계 목표 줄을 두 줄로 나눈다.

### 8.2 로그 지표(로컬, 외부 전송 없음)

`ui.practice_log`(§7.5) 와 콘솔 로그로 본다. 개인정보를 담지 않는다(시각·단계·도움 수준만).

| 지표 | 목표 |
|---|---|
| 연습 굿판 총 시간 중앙값 | 4~6분 |
| `ring` 단계 도움 L2 도달 비율 | ≤ 40% |
| 단계 건너뛰기 비율(아무 단계) | ≤ 10% |
| 인트로 건너뛰기 비율 | 기록만(목표 없음 — 건너뛰기는 정상 선택) |
| 연습 뒤 첫 실전에서 첫 해원 시각 | ≤ 0:45(design/11 K-1 0:50 보다 빠르게) |
| 연습 뒤 첫 실전에서 길닦음 ≥ 1 | ≥ 90%(K-4 80% 보다 높게) |

---

## 9. 수용 기준 · 검사 목록

1. 새 프로필(`--profile=fresh`) 첫 실행: 인트로 → 권유 창이 뜬다. 두 번째 실행: 타이틀 메뉴가 바로 뜬다.
2. 인트로 Esc 한 번에 끝나고 `intro_seen=true`. '길잡이 → 인트로 다시 보기'로 다시 볼 수 있다.
3. 연습 굿판을 끝낸 뒤 '굿판 열기(실전)': **첫 실전이 만신 직행 + 첫 굿판 완화**로 시작한다(`first_run_pending()` 그대로 true). 신당으로 가면 실패.
4. 연습 굿판 중·후: `Save.runs_done()`, `ui.runs`, `ui.hints_seen`, 재화, 넋기록이 바뀌지 않는다.
5. 연습 굿판 중 자동 시련·웨이브·중간보스가 오지 않는다(5분 넘게 머물러도).
6. 정기가 0이 되지 않는다(맞기는 한다 — 손맛 유지).
7. `--autotest --tutorial-autotest`: 10단계 done 로그 + finished, 오류 0, 게임 시각 6분 안.
8. `--intro-test`, `--guidebook-test=all`: 오류 0, 카드 6·쪽 8 로그.
9. 모든 문구 한국어, 캐논 용어(퇴치·해원·풀릴 기색·매듭 잠금·영가·천도·길베·길닦음·원혼 구슬·점지·시련·위엄·가호·빙의·살·살기·원귀·저승사자·정산·공덕·복전·신당). '선/악·죄·카르마' 없음.
10. 새로 생성한 그림·음원 없음(복사 6개뿐).

---

## 10. 결정 기록 · 남은 위험

| # | 결정 / 위험 | 내용 |
|---|---|---|
| D1 | 고리 → 방울 순서 | F12 근거. 요청 목록의 단계는 모두 있다. |
| D2 | `tutorial_done` 대신 `practice_done` | F3 근거. 계산된 작업 지시의 "flags.tutorial_done=true" 를 그대로 따르면 첫 실전 직행·완화가 꺼진다. |
| D3 | '넋 줍기' → '원혼 구슬 줍기' | 캐논: 레벨업 재화는 원혼 구슬(`cur_wonhon_guseul`), 넋(`cur_neok`)은 정산 재화(공덕 환산). 문구는 캐논을 따른다. |
| D4 | 대신 맞기 시연 생략 | 행렬 9명 이상 조건(F14) — 한 줄 설명만. |
| D5 | 시련 = 실제 시련 그대로 | 실패가 없는 구조(F9)라 따로 만들지 않는다. 신령 과제는 후보에 따라 다르다(산신 쉼터·용왕 넋 건지기 등) — 안내판(deities)이 설명한다. |
| D6 | '덤' 점지 1회 | 가르치기 카드 3장을 위해 레벨을 쓰지 않는 점지를 한 번 준다. 연습 전용이라 균형 영향 없음. |
| R1 | 디렉터 스폰과 틱 순서 | 신호 처리기 안 스폰 금지. 디렉터 `_physics_process` 에서만 스폰(§5.3). |
| R2 | 시련 중 03:00 장단 전환 | 연습 시각 3분 근처에서 중모리로 바뀐다. 끊김 없으면 그대로 둔다. |
| R3 | 결단타·맺힘 복귀로 진척이 늦어짐 | 단계마다 무리 보충 규칙과 L3 완화가 있다. |
| R4 | 디렉터 `_ready` 순서 | 디렉터는 런 씬의 마지막 자식으로 붙어 `Run._ready` 보다 먼저 `_ready` 가 돈다 → 스폰·시련 끄기는 `_ready`(형제 노드는 이미 준비됨), 무구·HUD·봇은 `call_deferred("_begin")`(Game.reset_run·무구 설정 뒤). |
