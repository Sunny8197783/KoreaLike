# 넋길: 해원굿 (SOULPATH: Untie the Han) — 프로젝트 폴더 안내

## ▶ 바로 플레이

- **브라우저에서 플레이:** https://sunny8197783.github.io/KoreaLike/ (PC 크롬·엣지 권장, 첫 로딩에 수십 초 걸릴 수 있음)
- **Windows 다운로드:** [최신 릴리스](https://github.com/Sunny8197783/KoreaLike/releases/latest)에서 zip을 받아 압축을 풀고 `neokgil_haewongut.exe` 실행
- **조작:** WASD/방향키 이동, 공격은 자동, Esc 쉼 메뉴(굿 안내서). 처음 켜면 컨셉 소개와 연습 굿판(튜토리얼)을 권한다. 타이틀의 '길잡이'에서 다시 볼 수 있다.

한국 무속 기반 뱀서라이크(탑다운 자동공격 서바이버 로그라이트)의 기획 저장소다. 폴더 이름은 `KoreaLike`, 내부 코드명은 `soulpath`다.

> **한 줄 요약:** 붉은 무구로 귀신의 한(恨)을 **깎아 퇴치**하거나, 흰 무구로 마지막 매듭을 **풀어 해원**한다. 해원한 넋은 무당 뒤를 따르는 영가 행렬이 되고, 그 행렬로 고리를 닫으면 넋들이 한꺼번에 저승길로 떠난다.

**현재 단계 (2026-11-21):** 기획 문서 01~14 작성, 리뷰 1차 반영, **캐논 v1.2 확정 결정 반영**(2026-11-21, `99-open-questions-and-next-steps.md` D-xx·C-xx)을 마쳤다(확정 D 50건·C 37건, 보류 D 7건·C 1건, 외부 결정 대기 D-58~D-65 + 자문단 목록). **2026-11-21 사용자 결정: 재미 검증 프로토타입은 생략하고 2026-11-26(목)까지 Godot 거의 완성 빌드로 직행한다.** **엔진: Godot 4.7.2 + GDScript(1차), 렌더러 `gl_compatibility`(D-43·D-44).** C++ `soulsim` GDExtension은 성능 미달 시 후속 작업이다.

---

## 먼저 읽을 것

1. [`design/00-GDD-master.md`](design/00-GDD-master.md) — 통합 색인: 피치, 핵심 비틀기, 시스템 맵, 문서 목차, 핵심 수치, 범위, 용어집
2. [`design/01-concept-and-canon.md`](design/01-concept-and-canon.md) — **캐논(정본).** 규칙·ID·명칭은 여기가 기준이다
3. [`design/99-open-questions-and-next-steps.md`](design/99-open-questions-and-next-steps.md) — 맨 위 'v1.2 확정 요약', 결정(D-xx)·불일치(C-xx) 표의 상태(✅ 확정 / ⏸ 보류 / 🧑‍⚖️ 사용자·외부 결정 필요), 플레이테스트 가설

역할별 읽는 순서는 `00-GDD-master.md` §6.3에 있다.

---

## 폴더 구조

```
KoreaLike/
├─ README.md                  ← 이 파일
├─ skills-lock.json           ← 프로젝트 스킬 버전 잠금
├─ design/                    ← 기획 문서 (마크다운, 한국어)
├─ data/                      ← 게임 데이터 JSON (기획 수치의 기계 판독본)
│  ├─ narrative/              ← 대사·사연·인물 정본·현지화 용어집
│  └─ tech/                   ← 성능 예산·데이터 레지스트리·세이브 스키마·텔레메트리·일정·리스크
├─ art/                       ← PixelLab 컨셉 아트·스프라이트·아트 보드
├─ tools/                     ← 문서·데이터 생성기와 시뮬레이터 (Python)
└─ .claude/skills/            ← 기획 방법론 스킬 (GDD, 로그라이크, 밸런스, 게임 디자이너, 픽셀아트)
```

---

## `design/` — 기획 문서

| 파일 | 내용 | 상태 |
|---|---|---|
| `00-research.md` | 원본 조사: 무당 계통, 무구, 귀신·요괴, 스탯 치환, 6대 신령, 20분 한양굿 | 원문 보존(수정하지 않음) |
| `00-GDD-master.md` | 통합 색인 | v1.2 통합본 (캐논 v1.2 기준) |
| `01-concept-and-canon.md` | 최종 컨셉 & 캐논 레지스트리(ID 사전, 핵심 규칙, 범위, 팔레트, 문화 존중) | v1.2 (캐논 v1.2) |
| `02-core-loop-combat.md` | 조작·카메라·자동공격·한 상태기계·영가·길닦음·살기·장단·피격·피드백·레벨 곡선 | v0.11 (캐논 v1.2 기준) |
| `03-characters.md` | 플레이어블 무당 6명 | v1.2 (캐논 v1.2 기준) |
| `04-weapons-evolution.md` | 무구 20, 진화 20, 결합 6 (**생성기 산출물, 직접 편집 금지**) | v0.9.2 (캐논 v1.2 기준) |
| `05-stats-passives.md` | 스탯 25, 패시브 16, 양자화·점지 정본 | v0.11 (캐논 v1.2 기준) |
| `06-deities-possession.md` | 6대 신령 시련·빙의·권능·공명·합일 | v1.2 (캐논 v1.2 기준) |
| `07-enemies-bosses.md` | 적·정예·중간보스·보스·저승사자·AI | v1.2 (캐논 v1.2 기준) |
| `08-stages-waves.md` | 스테이지 5, 20분 웨이브, 모드 | v1.2 (캐논 v1.2 기준) |
| `09-meta-economy.md` | 재화·해금·로비·명두 계승·넋기록·업적·세이브 | v1.2 (캐논 v1.2 기준) |
| `10-narrative-world.md` | 세계관·스토리 아크·공수·넋두리·사연·톤·현지화 | v0.9 (캐논 v1.2 기준) |
| `11-ux-ui-hud.md` | UX 필러, 화면 흐름, HUD, 입력, 접근성, 온보딩 | v0.11 (캐논 v1.2 기준) |
| `12-audio.md` | 적응형 국악, 장단 시스템, SFX, 믹스 | v0.9.3 (캐논 v1.2 기준) |
| `13-art-direction.md` | 아트 디렉션, 가독성 규칙, 에셋 목록, PixelLab 제작 계획 | v1.0 (캐논 v1.2 기준) |
| `14-tech-production.md` | 엔진·아키텍처·세이브·빌드·일정·팀·예산·마케팅·리스크 | v0.3 (캐논 v1.2 기준) |
| `16-external-research-decisions.md` | 외부 자문 대체 조사·결정(공개 자료 기반, 자문단 확인 목록·법무 항목) | 2026-11-21 작성 |
| `99-open-questions-and-next-steps.md` | v1.2 확정 요약, 결정·불일치 상태표, 외부 결정 대기 목록, (생략된) 프로토타입 계획 기록 | v1.2 (캐논 v1.2 확정 반영) |
| `15-balance.md` | 밸런스(봇 검증, 튜닝 레버 소유) | **신설 예정(미작성)** |

**문서 규칙**
- 섹션 문서끼리 참조할 때는 `NN-파일명` 전체를 쓴다(캐논 §8.3). 옛 가칭(`02-combat-core`, `04-deities-trials` 등)의 치환표는 `data/canon_ids.json`의 `doc_map`에 있다.
- 새 ID나 규칙 변경은 자기 문서에 `[CANON-REQUEST: ...]`로 적고, 크리에이티브 디렉터가 캐논을 개정한다(캐논 §8.2).
- 각 섹션 문서는 끝에 '리뷰 대응 로그'를 둔다. 다른 섹션에 넘긴 요청도 그 로그에 있다.

---

## `data/` — 게임 데이터

모든 JSON은 UTF-8이고 파싱 검증을 통과했다(2026-11-21, 40개). 파일마다 **소유 섹션**이 있고, 그 섹션만 고친다.

| 파일 | 소유 | 내용 |
|---|---|---|
| `canon_ids.json` | 01 | 별칭 ID, 캐논 상수, 접두사, 한자 표기, species_kind, 문서 치환표, 인계 목록 |
| `combat_core.json` | 02 | 전투 상수 전체(조작, 카메라, 한, 영가, 고리, 살기, 장단, 신명, 피격, 경험치, 상자, 런 종료) |
| `companions.json` | 02 | 동행 13종(동자령·동행령 8·호위 신장 4)과 공통 규칙(캐논 4.11). 미정 수치는 `null` |
| `characters.json` | 03 | 무당 6명 스탯·고유 패시브·신통·바크 |
| `weapons.json` | 04 | 무구·진화·결합 수치, `ritual_ref`, 기준 DPS (`tools/wpn04/gen.py`가 생성) |
| `stats.json`, `passives.json` | 05 | 스탯 정의, 점지 생성 규칙, 패시브 16종 |
| `deities.json` | 06 | 신령 6 × 2면, 권능 30, 공명, 합일, 시련 상수 |
| `enemies.json` | 07 | 적 전체, 스케일링 곡선, AI 원형, 스폰 그룹, 동시 상한 |
| `waves_stage1.json` | 08 | 선바위 굿당 표준 모드 20분 웨이브(남도 갯마을·동해안은 미작성) |
| `stages.json`, `spawn_tables.json` | 08 | v1 스테이지 3(선바위 굿당·남도 갯마을 씻김굿판·동해안)의 공통·스테이지 정의 / 스폰 디렉터·공급표·스테이지 배율·정예 예약·시련 연동 |
| `meta_economy.json`, `achievements.json`, `save_profile.example.json` | 09 | 수입·가격·해금·대장간·신단·명두·넋기록·의뢰·살 맺힘 단, 업적 57, 세이브 예시 |
| `narrative/*.json` | 10 | `cast_canon.json`(인물 이름 정본), `gongsu_lines.json`, `story_beats.json`, `sayeon_examples.json`, `loc_glossary.json` |
| `ui_hud_layout.json`, `input_bindings.json`, `accessibility_options.json`, `feedback_matrix.json`, `onboarding_hints.json` | 11 | HUD 25요소, 입력, 접근성 59종, 피드백 매트릭스, 힌트 |
| `audio_jangdan.json`, `audio_music_layers.json`, `audio_sfx.json`, `audio_mix.json` | 12 | 장단·그리드, 스템 레이어, SFX 194, 믹스 버스 |
| `art_palette.json`, `art_render_layers.json`, `art_anim_specs.json`, `art_vfx_list.json` | 13 | 팔레트 예약, 19층 렌더 순서, 애니 규격, VFX 120 |
| `balance_targets.json` | 15(임시 작성 14) | 밸런스 목표치 7묶음·출처 충돌 2건. `15-balance.md` 신설 전 임시 레버 소유는 02 §22·09 |
| `tech/*.json` | 14 | `perf_budgets`, `data_tables_registry`, `save_profile.schema`, `telemetry_events`, `milestones`, `risk_register` |

**아직 없는 파일(캐논이 소유를 지정함):** 남도 갯마을·동해안 웨이브 `waves_<stage>.json`(08). `companions.json`·`stages.json`·`spawn_tables.json`·`balance_targets.json`은 2026-11-21 신설(C-37).

**알아 둘 것:** 문서와 JSON이 다를 때 어느 쪽이 기준인지는 문서마다 다르다. 02는 JSON이 구현 기준이고, 03은 문서가 우선이다. 04는 생성기가 둘을 함께 만든다. 각 문서 머리말을 확인한다.

---

## `art/` — 컨셉 아트

PixelLab으로 만든 픽셀아트 컨셉과 스프라이트다. 색인은 [`art/ART-CONCEPT-INDEX.md`](art/ART-CONCEPT-INDEX.md), 파일 목록은 `art/manifest.tsv`다.

| 폴더 | 내용 |
|---|---|
| `characters/` | 만신·박수·단골·명두·심방 스프라이트(8방향 원본, zip 포함), 만신 걷기·굿 춤 애니 |
| `deities/` | 6신 컨셉(각 a~d 변형) |
| `enemies/` | 일반·정예·중간보스 라인업, 8방향 스프라이트 |
| `bosses/` | 역신(→ 역려 `boss_yeokryeo`로 재지정, D-03)·원결·이무기·저승사자·산신 화신 컨셉 |
| `stages/` | 선바위 굿당·남도 갯마을·동해안·제주·명부 컨셉(`stage_island_asylum.png`는 **폐기 대상**, 폐분교로 재생성 예정) |
| `concept/` | 키 아트, 캡슐 아트, 핵심 비틀기·길닦음·어둑시니·원귀 회귀 목업, 빙의 변형, 로비 |
| `items/`, `ui/`, `tilesets/` | 무구 아이콘 시트, HUD·점지 목업, 타일셋 |
| `ART-BOARD.png`, `_review_*.png` | 전체 보드와 리뷰용 콘택트 시트 |

아트 규칙(팔레트 예약, 640×360 정수배, 흰색 `#f2ece0`은 해원 계열 전용 등)은 `design/13-art-direction.md`와 캐논 §6을 따른다. 기존 에셋 중 규칙 위반으로 재색칠이 필요한 목록도 13에 있다.

---

## `tools/` — 생성기와 시뮬레이터

| 경로 | 용도 | 실행 (프로젝트 루트에서) |
|---|---|---|
| `tools/wpn04/` | 04 무구 문서 표와 `data/weapons.json`을 `wdata.py` 한 곳에서 생성. `buildsim.py`는 진화 타이밍 몬테카를로 | `python -I tools/wpn04/gen.py .` |
| `tools/meta_econ_sim/` | 09 경제: `econ_sim.py`(런 수입 모델), `pacing_sim.py`(400시드 페이싱), `build_meta.py`(JSON과 문서 표 생성) | 각 스크립트 머리말 참조 |
| `tools/art_board.py`, `contact_sheet.py`, `walk_strip.py` | 아트 보드·콘택트 시트·걷기 스트립 이미지 생성 | 각 스크립트 머리말 참조 |

`04-weapons-evolution.md`의 표는 손으로 고치지 않는다. `tools/wpn04/wdata.py`나 템플릿(`doc_t*.md`)을 고친 뒤 생성기를 다시 돌린다.

---

## 핵심 약속 (모든 작업에 적용)

- **조작은 이동 하나**(+ 일시정지/메뉴)다. 새 입력 버튼을 만들지 않는다.
- **퇴치도 해원도 정당하다.** 도덕 점수·질책 연출·경고 툴팁을 쓰지 않는다.
- **무속은 살아 있는 종교 전통이다.** 신령은 처치 대상이 아니다. 모든 귀신에게 해원 경로가 있다. 요괴를 '원래 사람'으로 그리지 않는다. 중국 무협 '무당파(武當派)'와 혼동하지 않는다. 근현대 창작 괴담(장산범 등)은 x2 확장 전용이다. 고증 신뢰 태그 `[전승]`·`[무속]`·`[각색]`·`[현대]`를 단다(캐논 §7).
- **ID는 바꾸거나 지우지 않는다.** 예외는 캐논 §8.1.1 별칭 표로만 한다.

---

## 다음 일정

| 날짜 | 일 |
|---|---|
| 2026-11-21 ~ 11-26 | **Godot 4.7.2 거의 완성 빌드** 제작(2026-11-26(목) 전달). 재미 검증 1주 프로토타입·12-14 판정은 생략(사용자 결정) |
| 2026-12-21 주 (W3) | G0 엔진 성능 게이트 |
| 2027-01-15 (W6) | G1 재미·실현성 게이트(캐논 v1.2는 2026-11-21 확정 완료) |
| 2027-04-09 | 버티컬 슬라이스 |
| 2027-09-30 / 2028-04-20 | EA / 1.0 |

세부 일정은 `data/tech/milestones.json`과 `design/14-tech-production.md` §8에 있다.

---

## 캐논 v1.2 반영 로그 (2026-11-21)

- **D-43·D-44:** '현재 단계'의 "엔진은 Godot 4.7 예정, 3주차 게이트에서 확정"을 "Godot 4.7.2 + GDScript(1차), 렌더러 `gl_compatibility`"로 바꿨다(C++ `soulsim`은 성능 미달 시 후속). 기준일을 2026-11-21로 올렸다.
- **C-36:** `design/` 문서 버전 표를 각 문서 머리말(캐논 v1.2 기준)에 맞췄다(01 v1.2, 02 v0.11, 03 v1.2, 04 v0.9.2, 05 v0.11, 06~09 v1.2, 10 v0.9, 11 v0.11, 12 v0.9.3, 13 v1.0, 14 v0.3). 00·99는 머리말이 v1.0이라 그대로 두고 00에 'v1.2 미반영'을 적었다. 실제로 있는 `16-external-research-decisions.md` 행을 추가했다.
- **캐논 v1.2 확정 마무리(2026-11-21):** 00·99 문서 상태를 v1.2로 갱신했다. `companions.json`·`stages.json`·`spawn_tables.json`·`balance_targets.json`을 데이터 표에 넣고 '아직 없는 파일'을 진도·동해안 웨이브로 줄였다. JSON 40개 파싱 재확인. 다음 일정을 사용자 결정(프로토타입 생략, 2026-11-26(목) Godot 거의 완성 빌드)으로 바꿨다.
- **16 C절·D절 잔존 정리 (2026-11-22):** 문서·데이터 표의 '신기록' → '넋기록'(내부 ID 유지), 스테이지 표시 '국사당' → '선바위 굿당', '진도' → '남도 갯마을(씻김굿판)'. `game/waves/spawn_director.gd` 보스 기본값 `boss_yeoksin` → `boss_yeokryeo`.
