# 넋길: 해원굿 — 실행·조작·디버그·내보내기

> 빌드 기준 2026-11-24 (마감 11-26 '거의 완성' 빌드, 리드 최종 검증 완료 — §7). 엔진 **Godot 4.7.2 stable**(표준판, gl_compatibility).
> 프로젝트 폴더: `game/` · 아키텍처 계약: `game/ARCHITECTURE.md` · 아트 규칙: `ART_STYLE.md` · 모션 수치: `GAME_FEEL.md`

---

## 1. 실행

```bash
# 편집기로 열기
C:/Users/김태양/Desktop/Godot_v4.7.2-stable_win64.exe --path C:/Users/김태양/Desktop/KoreaLike/game --editor

# 바로 플레이(타이틀부터)
C:/Users/김태양/Desktop/Godot_v4.7.2-stable_win64.exe --path C:/Users/김태양/Desktop/KoreaLike/game
```

* 창 1920×1080(기준 640×360 × 3 정수 배율). 설정 화면에서 흔들림·플래시·히트스톱·피해 숫자·적 번쩍임 방식(접근성)을 바꿀 수 있다.
* **가시성 설정**(11-25 추가, 설정 화면 아래쪽. 자세한 규칙: `design/18-visibility.md`):

  | 설정 | 값(굵게 = 기본) | 하는 일 |
  |---|---|---|
  | 무당 강조 | 끔 · **켬** · 강하게 | 켬: 무당 몸에 금 1px + 먹 1px 테, 발밑 금 마름모. 강하게: 테 2px + 발밑 금 타원. 끔이어도 무적 점멸 때는 먹 실루엣 + 금 테가 남는다 |
  | 무리 어둡게 | 끔 · **보통** · 강하게 | 일반 잡귀를 늘 조금(×0.88) 어둡게 하고, 화면 잡귀가 24마리를 넘으면 더 어둡게(120마리에서 최대). 풀릴 기색·원귀·피격 번쩍임은 어둡게 하지 않는다. 강하게 = 감광 ×1.4 |
  | 적 탄 강조 | 끔 · **켬** · 강하게 | 적 탄에 청 링 + 먹 테. 강하게 = 밝은 청 2px 링. 원귀 탄은 붉은 링 |
  | 피해 숫자 | **자동** · 전부 · 치명·정예만 · 끔 | 자동: 무리가 많거나(잡귀 40↑) 숫자가 24개 넘게 0.5초 이어지면 일반 숫자를 끈다(치명·정예·보스는 남김). 전부: 군중 규칙 없이 다 띄운다. 예전 저장값 0('전부')은 '자동'으로 읽는다 |
* 세이브: `%APPDATA%/Godot/app_userdata/넋길: 해원굿/save_profile.json`(원자 쓰기, `.bak` 자동 복구).
  봇 실행(`--autotest`)은 `save_profile_autotest.json`, `--profile=<이름>` 은 `save_profile_<이름>.json` 을 따로 쓴다.

### 화면 흐름
**첫 실행** **컨셉 인트로 6장**(Enter 다음 · ← 이전 · Esc 건너뛰기) → 권유 창 "연습 굿판을 해 볼까요?" → [연습하기] 연습 굿판(10단계, 약 5분, 실패 없음) / [바로 굿판 열기].
타이틀 → '굿판 열기' → **초굿(만신) 바로 시작** → 20분 굿 → 정산 화면 → 신당 로비. (연습 굿판은 판 수·정산·재화·본 힌트를 바꾸지 않아 첫 실전은 그대로 초굿 직행.)
**길잡이**(타이틀 메뉴 둘째 줄): 인트로 다시 보기 · 연습 굿판 · 굿 안내서(8쪽: 조작·흐름·무구·해원·시련·살·성장·정산). 연습을 마치기 전엔 '길잡이' 옆 황 점. 런 중 Esc → 쉼 메뉴 '굿 안내서'.
**연습 굿판 하는 법**(약 5분, 실패 없음): 걷기만 하면 된다. 아래 목표 줄을 따라가면 위 등불(10개)이 하나씩 켜진다 — 걷기 → 장단 공격 → 깎기 → 고리 → 풀기 → 영가 → 점지 → 시련 → 살 → 정산.
막히면 12초쯤 뒤 화살표·쉬운 말이 나오고, 더 지나면 조건이 느슨해진다. Esc 쉼 메뉴 = 이어가기 · 굿 안내서 · 설정 · **이 단계 건너뛰기** · **연습 그만두기**(두 번 눌러 확인). 멈춤 카드는 Enter/→ 다음.
끝 화면: [굿판 열기(실전)](첫 판이면 만신 직행 + 첫 굿판 완화) · [다시 연습] · [타이틀로]. 목표 줄은 화면 맨 아래, 등불은 위 '연습' 양옆에 있고, 그 밑에 무당·귀신이 오면 목표 줄이 옅어진다.
**두 번째부터** 타이틀 → '굿판 열기' 또는 '신당' → 신당 로비(무당 고르기·내림굿 해금·신당 단장·재가집 의뢰·무구 진열장·넋기록) → 굿판 문 → 런.
런 중 Esc → 일시정지(설정·타이틀로). 사망 또는 굿 완료(보스 → 저승사자 정산) → 정산 화면 → (신당 개방 뒤) 신당 / 다시 하기.

---

## 2. 조작

| 동작 | 키보드 | 패드 |
|---|---|---|
| 이동(360°) | WASD / 방향키 | 왼쪽 스틱 / D-패드 |
| 일시정지 | Esc / P | Start |
| 확인 | Enter / Space | A |
| 취소·뒤로 | Backspace | B |
| 점지(레벨업 3택) | 1 · 2 · 3 (또는 방향 + 확인) | 방향 + A |
| 전체 화면 ↔ 창 | Alt+Enter / F11 | — |

창 모드는 640×360 의 정수배(보통 1280×720)로 화면 작업 영역에 맞춘다. ×2 도 들어가지 않는 화면(1366×768 등)은 전체 화면으로 시작. 고른 모드는 저장된다. 창이 포커스를 잃으면(Alt+Tab·알림) 런은 자동으로 쉼 메뉴. 시련·합일·작두·보스 등장 중 레벨업은 쌓아 두었다가 끝난 뒤 한꺼번에 점지한다.

공격은 전부 **자동**이다(무구는 장단 박에 맞춰 스스로 친다). 플레이어가 하는 일은 **어디로 걷느냐** 하나다.

### 처음 하는 사람에게 — 해원과 고리
1. **붉은 무구**(신칼·월도 …)는 귀신의 한(恨)을 깎아 **퇴치**한다. 붉은 무구만으로는 한을 끝까지 못 깎을 때가 있다(매듭).
2. 한이 35% 아래로 내려간 귀신은 **흰 외곽선**(풀릴 기색)이 생기고 느려진다. 이때 **흰 무구**(방울 등)로 마지막 매듭을 풀면 **해원** — 넋이 무당 뒤를 따르는 **영가 행렬**이 된다.
3. 무당이 걸은 자리에는 4초짜리 **흰 길(길베)** 이 남는다. 그 길로 **한 바퀴 원을 그려 닫으면(고리)** 안쪽의 풀릴 기색 귀신이 한꺼번에 해원되고, 영가들은 저승길로 천도한다.
4. 화면 하단 길잡이 문구와 점선 예상선(고리를 닫을 수 있을 때 점선 끝 매듭 표시)이 처음 몇 번 안내한다.
   **시연 전 초기화**: 타이틀(또는 Esc 일시정지) → 설정 → **「길잡이 처음부터」** 에서 Enter — 본 안내 기록·판 수를 비워 다음 판이 첫 판처럼 안내된다.
5. 03:00 · 06:30 · 12:30 · 15:30 에 **신령 시련**: 두 원 중 하나에 들어가 신령을 고르고, 30초 동안 화신을 때려 **위엄**을 채우거나(붉은 쪽) 과제를 해 **가호**를 채운다. 18:00 **합일**, 18:35 작두 강림, 19:15 뒷전(공물상 대해원), 20:00 보스 역려 → 저승사자 정산.

---

## 3. 디버그 키 (디버그 빌드·편집기 실행에서만)

| 키 | 기능 |
|---|---|
| F1 | 시간 ×10 토글 |
| F2 | 즉시 레벨업 |
| F3 | 무적 토글 |
| F4 | 적 200 즉시 스폰(링) |
| F5 | 시련 즉시 시작 |
| F6 | 화면 안 적 전부 풀릴 기색 |
| F9 | 성능 덤프(콘솔: fps·적 수·draw call·객체 수) |
| F10 | HUD 디버그 오버레이 토글 |

## 4. 명령행 인자 (`--` 뒤에 붙인다)

| 인자 | 설명 |
|---|---|
| `--autotest` | 타이틀 건너뜀, 봇 이동, 점지 자동, 사망 무시, 런 끝나면 정산 화면 3초 후 종료 |
| `--char=<id>` | 무당(char_mansin·char_baksu·char_dangol·char_myeongdu·char_simbang) |
| `--seed=<n>` · `--speed=<n>` | 난수 시드 · 시뮬 배속(프레임당 틱) |
| `--start-sec=<s>` · `--quit-at=<s>` | 게임 시각에서 시작 · 게임 시각에 종료(봇) |
| `--autotest-die=<s>\|settle` | 봇: 그 시각(또는 보스 해결 뒤 정산 단계)에 정기 0 → 사망 정산 / '굿판 거둠' 경로 시험 |
| `--bot-pick=greedy\|random\|pair` | 봇 점지 정책(pair = 짝 패시브 > 빈 칸 새 무구 > 진화 짝 패시브 > 강화) |
| `--result-hold=<s>` · `--autotest-lobby` | 봇: 정산 화면 유지 시간 · 정산 뒤 신당 로비도 띄워 보기 |
| `--trial-at=<s>` · `--deity-test=wieom\|gaho\|mix` | 시련을 해당 시각에 강제 · 6신 면 효과·권능 전부 켜기(스모크) |
| `--boss-form=han\|sal` | 보스 역려 형태 강제 |
| `--waves-boss-resolve=haewon\|toechi` · `--waves-boss-resolve-after=<s>` · `--waves-n=<0..1>` | 보스 강제 해결(정산 흐름 시험) · 해원 비율 강제 |
| `--wpn=<id[:Lv],…>` | 런 시작 시 무구·패시브·진화·결합 지급. 예 `--wpn=wpn_woldo:8,psv_obangkkeun:1,evo_manwoldo` |
| `--profile=<name>` | 별도 세이브 프로필 |
| `--vis-stats --vis-at=<초,초..> --vis-dur=4 --vis-step=0.5 --vis-lead=2 --vis-out=<절대 경로> --vis-scale=3` | 가시성 캡처(창 실행). 각 시각 2초 전부터 1배속으로 0.5초 간격 PNG(1920×1080) + `vis_stats.jsonl`(화면 적·적 탄·vfx·숫자·글 위치·fps·draw call). 보통 `tools/vis_capture.sh` 로 부른다 |
| `--crowd-fx-off` | (A/B 캡처용) 군집 감쇠(플래시 솎기·숫자 군중 이력 규칙·빛기둥 무리 규칙)를 끈다 |
| `--pilot` · `--pilot-legacy` | 파일럿 렌더 장면(전후 비교) |
| `--intro-test` | 타이틀이 컨셉 인트로를 바로 열고 1.5초마다 자동 넘김 → 권유 창 1.5초 → 종료. 로그 `[intro] card=<n>/6 id=…`·`[intro] offer`·`[intro] done`. `--ui-save=1` 이 아니면 플래그를 쓰지 않는다. `--fixed-fps 60 --quit-after 900` 과 함께 |
| `--intro-choice=practice\|play` | (`--intro-test` 와 함께) 권유 창에서 그 답을 고른 것처럼 이어 간다 — 첫 실행 흐름 검사(인트로 → 권유 → 연습/실전). `--autotest --profile=<새 이름> --ui-save=1 --tutorial-autotest` 와 같이 쓰면 연습 굿판까지 자동. 타이틀은 열릴 때 `[title] open intro_seen= offered= practice_done= first_run_pending=` 을 찍는다 |
| `--pause-test=<게임 초>` | 그 시각에 쉼 메뉴 → 1.5초 뒤 굿 안내서 3쪽 → 1.5초 뒤 닫기(캡처·검사용). 로그 `[pause] open tutorial=… items=…`·`[pause] guidebook`·`[pause] done` |
| `--guidebook-test=<1..8\|all>` | 타이틀에서 굿 안내서를 그 쪽으로 연다. `all` = 1.2초마다 넘겨 8쪽 뒤 닫고 종료. 로그 `[guidebook] page=<n>/8 id=…`·`[guidebook] done` |
| `--ui-shot=guide` | 타이틀 '길잡이' 하위 메뉴 캡처(인트로 자동 열기 생략) |
| `--tutorial-step=<id>` | 타이틀 없이 연습 굿판을 그 단계부터(`move beat cut ring white yeongga jeomji trial sal settle`). 혼자 쓰면 사람이 직접 해 본다 |
| `--tutorial-autotest` | **`--autotest` 와 함께.** 연습 굿판 자동 완주(TutorialBot) 뒤 종료. 로그 `[tutorial] step=<id> done t= dur=(게임 초) help=(최대 도움) screen=(화면 초)`·`finished … done=10/10`·`save_same=true`(실전 기록 불변). 예 `--fixed-fps 60 --quit-after 12000 -- --autotest --tutorial-autotest --seed=1 --speed=4` |
| `--tutorial-exit=real\|again\|title` · `--tutorial-exit-at=<id>` | (자동 테스트) 끝 화면에서 그 버튼을 고름 · 그 단계에서 그만두고 다시 연습. `real` 이면 첫 실전이 만신 직행+첫 굿판 완화인지 `[tutorial] real_run … assist=` 로 찍고 종료 |
| `--tutorial-skip-all=<s>` · `--tutorial-bot-idle=<s>` | (자동 테스트) 단계마다 s초에 건너뛰기 · 봇이 단계마다 처음 s초 가만히(도움 L1~L3 시험) |
| `--tutorial-shots=<절대 경로>` | (non-headless) 단계마다 대표 프레임만 PNG 로(목표 줄·이름표·도움·카드·끝 화면). 예 `game/captures/tutorial/run/` |
| (미리보기) `res://ui/tests/ui_preview.tscn -- --ui-preview=tut\|tut_card\|tut_end\|tut_jeomji\|tut_pause` | 연습 굿판 HUD(목표 줄·등불·이름표·멈춤 카드·끝 화면·점지 주석·연습 쉼 메뉴)를 가짜 신호로 띄운다 |

## 5. 검사

```bash
bash tools/godot_check.sh                       # 임포트 + 타이틀 600프레임 + 봇 60초 + 사망 경로 → "OK: no errors"
bash tools/godot_check.sh --geodum              # + 정산 중 사망 → '굿판 거둠'(클리어 유지)
bash tools/godot_check.sh --builds              # + 빌드 행렬(시드 3 × 무당 2, 병렬) 한 줄 요약
bash tools/godot_check.sh --full                # + 봇 완주(보스 → 저승사자 정산 → 정산 화면, ×10)
bash tools/godot_check.sh --movie               # + 화면 캡처(captures/frame*.png)
LOG_TAG=<모듈> bash tools/godot_check.sh        # 동시 실행 시: captures/godot_check_<모듈>.log, captures/<모듈>/
MOVIE_AT=650 MOVIE_ARGS="--start-sec=590" bash tools/godot_check.sh --movie   # 특정 시각 장면 캡처
```

* 기본 검사의 3f·3q 단계는 `ftcheck`·`tutcheck` 프로필을 지우고 다시 만든다. 11-25 부터 `LOG_TAG` 가 있으면 프로필 이름에 붙는다(`ftcheck_<tag>`·`tutcheck_<tag>`). 그래서 태그가 다른 검사끼리는 동시에 돌려도 서로 프로필을 지우지 않는다. 태그 없이 둘을 동시에 돌리면 예전처럼 'fresh profile did not start at intro' 거짓 실패가 날 수 있다.

가시성 전/후 캡처(design/18 §5, 한 번에 4~5분, 다른 Godot 없이 혼자 돌려야 fps 가 맞다):

```bash
bash tools/vis_capture.sh after                                        # 시드 2·짝 점지, 3:00~20:20 7시점 × 9장
PICK=random bash tools/vis_capture.sh after_crowd                      # 무작위 점지(보통 빌드)
AT=1080,1170 EXTRA="--start-sec=1060" bash tools/vis_capture.sh after_weak   # 약한 빌드로 적 200마리에 파묻히는 경우
PYTHONIOENCODING=utf-8 python tools/vis_measure.py game/captures/vis/before game/captures/vis/after
```

---

## 6. 내보내기(Windows)

* 프리셋: `game/export_presets.cfg` → **"Windows Desktop"**, 출력 `build/windows/neokgil_haewongut.exe`(+ `.pck`, 콘솔 래퍼 포함).
  포함(FileAccess 로 직접 읽는 JSON): `data/**/*.json, assets/**/*.json`(음악·효과음 색인, 타일셋 메타, 스프라이트 색인, vfx).
  제외: `captures/ _capture/ tests/ assets/candidates/ assets/_review/ assets/manifest_parts/ *.md`.
* 내보내기 템플릿 4.7.2.stable 이 `%APPDATA%/Godot/export_templates/4.7.2.stable/` 에 설치되어 있다(2026-11-25 확인).
  다른 PC 에서는 편집기 → 편집기 → 내보내기 템플릿 관리 → 4.7.2.stable 다운로드, 또는 공식 `.tpz` 를 '파일에서 설치'.
  (`Godot_v4.7.2-stable_mono_win64.zip` 은 C# 판 편집기라 이 프로젝트 템플릿으로 쓰지 않는다.)
* 내보내기:

```bash
mkdir -p build/windows
C:/Users/김태양/Desktop/Godot_v4.7.2-stable_win64_console.exe --headless --path game --export-release "Windows Desktop" ../build/windows/neokgil_haewongut.exe
```

* 릴리스 빌드에서는 F1~F10 디버그 키와 `--deity-test`·`--trial-at` 이 꺼진다.
* 웹(GitHub Pages): 프리셋 **"Web"**(단일 스레드, `variant/thread_support=false`), 출력 `build/web/index.html`.

```bash
C:/Users/김태양/Desktop/Godot_v4.7.2-stable_win64_console.exe --headless --path game --export-release "Web" C:/Users/김태양/Desktop/KoreaLike/build/web/index.html
```

  - 렌더러는 데스크톱과 같은 `gl_compatibility`(WebGL 2)다. 웹에서 무거울 수 있는 것: 화면 전체 후처리 `shaders/occult_post.gdshader`(비네트·색동·붉은 달 적빛), 적 무리 `enemies/enemy_crowd.gdshader`(풀릴 기색 테가 적 픽셀마다 이웃 8~16번 샘플), 단일 스레드라 오디오·시뮬이 한 스레드에서 돈다. `index.pck` 가 약 87MB 라 첫 로딩이 길다.
  - 웹은 소리를 첫 클릭·키 입력 뒤에야 낸다(브라우저 자동 재생 정책).

---

## 7. 빌드 상태 (2026-11-26 마감 빌드 / 아래는 11-25·11-24 기록)

* **11-26 마감 빌드**(자세히: `design/99` 맨 아래 5.8, 가시성 `design/18` §8.5):
  - 릴리스 exe `build/windows/neokgil_haewongut.exe` + `.pck`(12:36), 묶음 `build/neokgil_haewongut_windows.zip`(12:39), 웹 `build/web/`(12:38). 스모크 `--headless --quit-after 900` 오류 0.
  - 검사: 기본 **OK: no errors**(LOG_TAG=final1126), `--full` **OK: no errors**(20:47 saja_bow 클리어), 연습 굿판 10/10·`save_same=true`. 사용자 세이브 md5 는 검사 전후 같다.
  - 튜토리얼: 인트로 6장 → 권유 창, 연습 굿판 10단계, 굿 안내서 8쪽. 캡처 `game/captures/tutorial/final2/`.
  - 가시성: 무당 금 테·발밑 표지, 무리 감광, 적 탄 z8 청 링, 영가 따뜻한 반투명, 가운데 글 1개, 피해 숫자 합치기. 설정 4종(무당 강조·무리 어둡게·적 탄 강조·피해 숫자 '자동'). 캡처 `game/captures/vis/final/`.
  - 성능: 가시성 설정을 켜고 꺼도 fps 차이 ±3 안. 11-26 측정은 배터리 전원이라 낮게 나왔다(45~50fps, 같은 장면 11-25 전원 연결 113~119fps) — 전원 연결 상태에서 다시 잴 것.


* **릴리스 exe**: `build/windows/neokgil_haewongut.exe` + `neokgil_haewongut.pck`(2026-11-25 00:04, 리뷰 수정 4건 반영 뒤 재내보내기, exit 0).
  - 스모크: 릴리스 exe `--headless --quit-after 900` 오류 0. 디버그 내보내기(임시 폴더)로 봇 사망 경로(`--autotest --seed=3 --autotest-die=20 --quit-at=60 --result-hold=1.0 --autotest-lobby`) 오류 0, `run_finished victory=false ending=death` 까지 도달.
  - 11-25 검사(`LOG_TAG=release1125 bash tools/godot_check.sh`): **OK: no errors**.
  - 11-24 밤 리뷰 수정 반영분: 큰 적(보스·중간보스) 몸 안의 무당이 가려지지 않게 뒤로 그림, 가호 ○ 표식 닫힌 고리, 길잡이 이름표 겹침 회피, '해원 ×N' 글자와 추임새 슬램 겹침 생략·'해원 ×1' → '해원'.
* PixelLab 잔여: 142.40 / 2000 generation(11-25 00시 확인, 12-10 갱신).
* 기본 · `--full` · `--movie` 검사(11-24): **오류 0**. full 봇은 시련 4회 → 합일 → 작두 → 뒷전 → 보스 역려 → 23:00 저승사자 정산 → 정산 화면까지 끝까지 간다.
* 성능: 1920×1080 1배속, 적 193마리에서 약 209fps(RTX 5060 Laptop). 헤드리스 틱당 최대 2.5ms.
* 장면 캡처: `game/captures/final/<장면>/` (title · video · t0300_trial · t0500_crowd · t1000_midboss · t1800_hapil · t1915_dwitjeon_boss · t2000_boss · death_result_lobby · lobby), 30초 영상 `game/captures/final/gameplay.mp4`(1920×1080 60fps, 640×360 → ×3 nearest, 봇 seed 1 의 00:14~00:44 — 11-25 00:10 최신 코드로 다시 만듦).
* **알려진 문제**(자세한 목록과 다음 작업: `design/99-open-questions-and-next-steps.md` 맨 아래 「5. 빌드 상태」):
  - 최종 보스 한형(역려) 해결이 봇 캡처 기준 30~40초로 설계 목표(120~180초)보다 짧다. 사람 1판으로 배율을 잰 뒤 매듭 열림 창·재결박 시간을 조정할 것.
  - 사람 손 플레이 1판이 아직 없다: 새 효과음 27종(발소리 34px마다 -10dB, 길베 스침 루프 -24~-14dB, 신명 틱 등) 체감 음량과 첫 판 길잡이 이해도(H1) 미확인. 헤드리스·무비 캡처는 무음이라 귀로 들은 근거가 없다.
  - 보스 등장(20:06) 때 공수·손님 카드·바닥 힌트가 겹칠 수 있고, 보스전 중 점지가 연달아 나와 흐름이 끊길 수 있다.
  - (11-25 가시성 작업으로 대부분 해결: 가운데 큰 글 동시 1개, 피해 숫자 군중 모드, 무당 금 테 — `design/18-visibility.md` §8) 고리로 수십 마리를 한꺼번에 풀 때 흰 해원 디졸브·빛기둥이 크게 뭉치는 것과 고리 닫힘 섬광의 칸 모양은 남아 있다.
  - 성능: 11-25 저녁 같은 장면(1920×1080, 적 219)에서 90~100fps. 11-25 00:04 릴리스(111~130fps)보다 15~23% 느리다(draw call 은 같음, 스크립트 쪽). 60fps 는 넘는다.
