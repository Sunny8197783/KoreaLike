# ASSET-REVIEW — KoreaLike 에셋 전수 검토 (2026-11-22)

검토자: 아트 디렉터 겸 한국 민속 고증 리뷰 단계. 대상: `game/assets/` 전체(VFX·스프라이트·소품·폰트·오디오 메타).
콘택트 시트와 군집 테스트 이미지는 `game/assets/_review/`에 있다. Godot이 이 폴더를 임포트하지 않도록 `.gdignore`를 넣었다.

## 0. 요약

| 구분 | 수량 | 판정 |
|---|---|---|
| VFX 시트 (png+json) | 159종 (사양 ID 120개 전부 존재, 변주 포함) + 셰이더 8종 | 통과. 6종(시트 8개)은 다시 렌더했고, JSON 메타 30건을 보정했다 |
| 스프라이트 엔티티 | 59개 폴더, PNG 2,601장 | 4방향 정지 이미지는 전부 있다. 애니 이름 30건을 사양에 맞췄고, 사양에 없는 애니 1건은 빼냈다. 누락 애니는 118건 |
| 소품·타일·폰트 | 소품 28 + 상태 4 + 데칼 13, 타일셋 4, 폰트 9 (OFL) | 통과 |
| 오디오 | SFX 142 ogg, 음악 176 ogg | 라이선스 통과 (CC0 53, CC-BY 4.0 1, NC/ND 0). P0은 모두 있다. v1 누락은 P1 81, P2 31 |
| 매니페스트 | `ASSET-MANIFEST.json` 602항목, 경로 누락 0, 라이선스 문제 0 | 생성 완료 (누락 목록 포함) |
| PixelLab 잔여 | 291 gen (2,000 중 1,709 사용, 12-10 리셋) | 이번 검토에서는 0 gen을 썼다 |

## 1. 검토 방법

- `tools/asset_audit.py`는 모든 VFX JSON을 자동으로 검사한다. 항목은 다음과 같다.
  - frames 수와 시트 칸 수, 프레임 정렬, `frameWidth`/`frameHeight`/`columns`/`pivot`/`fps`/`loop`
  - 사양(`data/art_vfx_list.json`)의 캔버스, 프레임 수, fps
  - 투명 배경
  - 예약색: 백 `#f2ece0`과 순백(≥240)이 W 역할이 아닌 이펙트에 쓰였는지
  - 첫 프레임 픽셀량(타격감)
  - 스프라이트 4방향과 파일명 규약
  - 결과는 `_review/audit.json`에 저장된다.
- `tools/review_sheets.py`가 만드는 이미지는 다음과 같다. 전부 직접 눈으로 확인했다.
  - `vfx`: 카테고리별 전 프레임 스트립. 피벗은 초록 십자로 표시된다.
  - `crowd`: 640×360 먹 바탕 위에 수백 개를 겹친 가독성 테스트.
  - `sprites`: 엔티티별 4방향과 애니 대표 프레임.
- `tools/merge_manifest.py`는 manifest_parts를 합치고, 디스크 존재와 라이선스를 검사하고, 사양 대비 누락을 정리한다.
- `tools/asset_review_fix.py`는 아래 2절의 기계적 수정을 수행한다. 다시 돌려도 결과가 같고(멱등), 원본은 `art/_review_backup/`에 백업한다. 수정 로그는 `_review/fixlog_*.txt`에 있다.
- `tools/vfx_install.py`는 pixelfx로 다시 렌더한 시트를 게임 폴더에 넣는다. 기존 JSON의 확장 메타를 보존하고, 프레임을 가로 한 줄로 다시 배치한다.

## 2. 수정 내역

### 2.1 다시 렌더한 VFX (pixelfx 소스 수정, 6종·시트 8개)

가장 자주 보이는 것부터 처리했다.

| id | 문제 | 수정 |
|---|---|---|
| `vfx_orb_small` / `_mid` / `_large` (화면 최대 400) | 마름모 보석 실루엣이라 일반 판타지 XP 젬처럼 읽혔다 | 둥근 불덩이 위로 꼬리 불꽃이 흔들리는 **혼불** 실루엣으로 다시 그렸다. 색 역할(청록, 황, 적), 비트 맥동, 크기는 유지했다 |
| `vfx_sal_grain_idle` (+`_s`, `_l`, 최대 200) | 먹 바탕 `#0e0b16` 위에서 거의 보이지 않았다 (군집 테스트에서 소실) | 먹 명도를 한 단계 올렸다(rim ink5, body ink3). 붉은 눈은 한 단계 밝히고 8px 이상에서는 2px로 키웠다. 글로우도 강화했다 |
| `vfx_jakdu_blades` / `vfx_daejakdu_blades` | 세운 식칼 모양이 '붉은 기둥'으로 읽혀 작두로 보이지 않았다 | `_g1.js`에 `jakduLong()` 헬퍼를 추가했다. 작두틀 위에 **날을 위로 세운 긴 작두날**(손잡이 한지 매듭, 사선 날끝, 황 날선)로 다시 그렸다. 대작두는 가운데가 가장 크게 뒤에 선다 |

수정 전 소스와 시트는 `art/_review_backup/vfx_src/`, `art/_review_backup/vfx_sheets/`에 있다.

### 2.2 JSON 메타와 파일명

- `frameWidth`/`frameHeight`를 G1 28종에 추가했다. 대상은 sinkal, sinjangkal, woldo, manwoldo, samjichang, saseulchang, jakdu_shockwave, sainsageom, isippalsu, gakgung, jangchang, pajinchang, pyeongon, cheoljillyeo, jusahwajeon, hojakdo_fear_ring, byeongnyeok, sangun_roar, status_fear 등이다.
- `vfx_candle_flame_s`: pivot을 `{x,y}` 객체에서 `[x,y]`로 바꾸고, `frames`/`frameSize`/`id`를 추가했다.
- `vfx_hojakdo_talisman`을 **`vfx_hojakdo_sehwa`**(사양 ID)로 이름을 바꿨다. 사양 누락 ID가 0이 되었다.
  - pixelfx 소스 파일명은 여전히 `vfx_hojakdo_talisman.js`다.
- `vfx_obanggi_flag`(20f)와 `vfx_obangjin_pillar`(30f)를 색별로 나눴다.
  - 원래는 5색이 한 시트의 행으로 들어 있었고 frameTags로만 구분됐다.
  - 그런데 `VfxLib.parse_aseprite`는 frameTags를 무시하고 frames[] 전체를 재생한다. 그대로 두면 색이 번갈아 바뀌며 재생된다.
  - `<id>_{cheong,jeok,hwang,baek,heuk}` 5개 파일로 나누고, 기본 id에는 청 하나만 남겼다(`meta.pixelfx.variants`).
  - 합친 원본 시트는 백업 폴더에 있다.
- `vfx_go_maedeup_untie`: 끝의 빈 프레임 2장 중 1장을 빼서 9f에서 8f로 맞췄다(사양 8).
- G4가 다른 그룹 시트 48개에 덧붙인 spec 필드(blend, layer, color_role 등)를 확인했다. 추가만 된 상태이고 사양 값과 일치해서 **그대로 유지**했다.

### 2.3 팔레트 예약 (순백 = 해원 전용)

W 역할이 아닌 이펙트 35개에서 순백(RGB ≥240)을 찾아 역할 색 계열로 바꿨다. 알파는 유지했다.

| 역할 | 바꾼 색 |
|---|---|
| 신령·황(D/Y) | 황백 `#fff3c8` |
| 용왕 변주 | 청록백 `#d8f4ec` |
| 적 위험(B) | 청백 `#cee2fc` |
| 적(R) | `#ffe0c4` |

대상은 다음과 같다.
- bingui_pillar ×7
- trial_block_wall ×7
- hwasin_won ×7
- sinjangdae_descend ×7
- dueoksini_slam, geogu_inhale, box_gilhyung_open, lamp_ignite, sinmyeong_oreum_border, union_jakdu_dari_ring, union_sanullim

이로써 `#f2ece0`과 순백은 W 역할(해원, 풀릴, 영가, 길베) 이펙트에만 남는다.

### 2.4 스프라이트

애니 이름을 `data/art_anim_specs.json`의 엔티티별 사양에 맞췄다. 파일명 패턴 `<anim>_<dir>_<n>.png`는 원래 지켜지고 있었고, 문제는 이동 애니 이름이 섞여 있던 것이다.

| 바꾼 이름 | 대상 |
|---|---|
| `move`→`walk` | comp_agwi, comp_dalgyal, comp_gaekgwi, comp_mongdal, comp_mulgwi, comp_yeongsan |
| `glide`→`walk` | comp_cheonyeo |
| `walk`→`move` | enm_sangmun, enm_subi(+__sogwi), elite_dueoksini, elite_geogu_gwi, elite_yeokgwi_ttae, mboss_daegwi, mboss_dokkaebi, mboss_gangcheori, mboss_gumiho, avatar_yongwang, avatar_chilseong, avatar_barigongju, avatar_jeseok_daegam, avatar_janggun(+오방 5변주) |
| `walk`→`float` | enm_hwehwe_gwisin |
| `chase`→`float` | chaser_jeoseung_saja (캐논 D-02: 추격 없음) |

- 각 폴더의 `anims.json`도 함께 갱신했다. 이름을 바꾼 PNG의 오래된 `.import`는 지웠다(Godot이 다시 임포트한다).
- 플레이어(`char_*`)는 `walk` 그대로다. `player.gd`가 `walk`를 읽는다.
- `comp_dongja`의 `clone_strike`(6장)를 `art/_deprecated/comp_dongja/`로 옮겼다. 캐논 v1.2 D-27/C-28에서 분신 공격이 삭제됐기 때문이다(사양 note 참고).
- overlay_head/overlay_jimul: `<변주>_<dir>.png`를 `<변주>_<dir>_0.png`로 바꿔 `<anim>_<dir>_<n>` 규약에 맞췄다. anim은 신령+면(예: `chilseong_gaho`)이다.
- `elite_yeokgwi_ttae`: 녹색 피부가 일반 판타지 오크처럼 읽혔다. 사양은 "먹빛 누더기 잡귀 우두머리"다. 전 프레임(28장)의 녹색 계열(5,334px)을 먹빛 회보라로 바꿨다. 원본은 `art/_review_backup/sprites/`에 있다.
- `sprites/manifest.json`을 다시 스캔했다(59 엔티티, VFX 시트 158). 기존에는 gumiho, gangcheori, overlay 등 4개가 빠져 있었다.
  - `sync_art.py` 전체 실행은 일부러 하지 않았다. art/에서 다시 복사하면서 게임 쪽 수정본을 덮어쓸 수 있기 때문이다.
  - 그래서 `rescan_sprites`만 재사용했다.

## 3. 항목별 판정 (VFX)

판정 기준: 한국풍이 한눈에 읽히는가(K) / 일본·중국·판타지와 혼동이 없는가(X) / 팔레트(P) / 군집 가독성(C) / 첫 프레임(F) / 메타(M). ✔ 통과, △ 주의, ✘ 미달 후 수정.

| 그룹 | 판정 | 메모 |
|---|---|---|
| G1 붉은 무구 (28) | K✔ X✔ P✔ C✔ F✔ M✘→✔ | 신칼 한지술, 월도, 삼지창 ψ, 칠성, 작두 모두 무구로 읽힌다. 작두 2종은 실루엣 미달이라 다시 렌더했다(2.1). toechi_burst, gakgung_hit, gyeoldanta 모두 첫 프레임이 강하다. 산군 포효(sangun_roar)의 호랑이 머리 외곽선은 약하다(△, 최대 1개라 보류) |
| G2 백 무구·해원 (22) | K✔ X✔ P✔ C△ M✘→✔ | 방울, 부채, 넋전, 지전, 노잣돈, 오방기(동청·서백·남적·북흑·중앙황 방위 정확), 쑥물, 소금 모두 맞다. P 역할(L≤0.72)이라 대비가 낮은 편이다. 이는 의도된 것이다. 오방기·오방진 다색 시트는 분리했다(2.2). 흑기는 먹보라(#2f2840) 톤이다. 먹 바탕에서 읽히게 하려는 선택이라 유지했다 |
| G3 판정·영가·길베 (16) | K✔ X✔ P✔ C✔ F✔ | 풀릴(고 매듭 백), 퇴치(적 8방 섬광), 해원(넋전에서 나비), 천도(연꽃 빛기둥)는 퇴치와 해원이 색과 방향(방사 vs 상승)으로 대비된다. 셰이더 4종은 JSON 없이 셰이더만 있다(사양상 정상) |
| G4 적 탄·살·사망 (31) | K✔ X✔ P✔ C✘→✔ | 청 탄과 먹 살이 일관된다. 살 알갱이 가독성 미달은 다시 렌더했다. `eodukssini_body`는 사양상 셰이더(0f)인데 폴백 시트 8f도 함께 있다(정상). `hazard_generic_fill`은 타일용이라 불투명이 맞다 |
| G5 신령·빙의·시련·합일 (16 + 신령 6변주) | K✔ X✔ P✘→✔ | 신장대 오색천, 금줄(왼새끼+숯+고추), 화신원 모두 고증이 좋다. 순백 플래시는 황백으로 바꿨다(2.3). x1 placeholder 2종(오방철진, 산울림)은 틀만 잡힌 상태다 |
| G6 픽업·UI·환경·화면 (12) | K✘→✔ X✔ C✔ | 혼불 구슬은 다시 렌더했다(2.1). 엽전(네모 구멍), 넋함 산통, 공물상(돼지머리 없음), 연등 점화는 좋다. 화면 셰이더 2종은 Godot에서 실행해 보지 않았다(제작 보고) |

군집 테스트(`_review/crowd_*.png`)에서는 플레이어 적, 적 청, 보상 황·청록, 살 먹+적, 해원 백이 수백 개 겹쳐도 색역으로 분리된다.

## 4. 항목별 판정 (스프라이트·소품)

- **무당 5종** (mansin, baksu, dangol, myeongdu, simbang): ✔
  - 홍철릭·쾌자, 전립, 방울·부채, 명두(청동거울), 제주 심방 차림 모두 고증에 맞다.
  - 무속인을 조롱하는 표현은 없다.
- **적** (agwi, 처녀귀신, 달걀귀신, 몽달귀신, 물귀신, 객귀(삿갓), 호식원혼(지게), 상문, 수비, 영산, 도깨비불): ✔
  - 한국 귀신 원형을 잘 따른다.
  - 강시, 오니, 유령 시트 같은 클리셰는 없다.
- **엘리트**
  - 불가사리 ✔, 별상 손님(가마+말) ✔, 두억시니 ✔.
  - 역귀 떼: 녹색 오크 느낌은 수정했지만 뾰족 귀는 그대로다(△).
- **중간보스**
  - 대귀 ✔, 도깨비(삿갓·방망이, 뿔 없음, 오니 회피) ✔, 강철이(가뭄 이무기형) ✔.
  - **구미호 △**: 파스텔 톤에 귀여운 체형이라 일본 키츠네나 몬스터 게임 쪽으로 읽힐 위험이 있다. 재생성 후보다(아래 6절).
- **화신**
  - 산신 호랑이 ✔, 용왕(파도+관복) ✔, 칠성(북두 성관) ✔, 장군 오방 5변주 ✔, 제석대감(전립·홍철릭) ✔.
  - 바리공주 화신은 캐논상 **무장승**이고, 거구·지팡이·물동이로 맞게 그려졌다. 다만 캐논의 삿갓이 없다(△).
- **저승사자**: 흑갓, 흑도포, 붉은 명부가 정확하다 ✔.
- **소품**: ✔
  - 당집(기와), 장승 쌍, 솟대, 서낭당 돌무더기(오색 헝겊), 금줄, 넋전 줄, 오방기 묶음, 무신도, 공물상 4상태, 연등.
  - 석등은 사각 옥개석이라 일본 석등롱과 구분된다.

## 5. 남은 문제

1. **엔진 로더**
   - `VfxLib.parse_aseprite`는 frameTags를 무시한다. 다색 시트는 이번에 분리했지만, 앞으로 행 단위 변주를 넣을 때도 같은 함정이 생긴다.
   - one-shot 끝 빈 프레임 정책이 그룹마다 다르다. G1·G2는 빼고, G3·G4·G5 일부는 넣는다(+1f). 둘 다 재생은 되지만 프레임 수 = 사양으로 통일할지 코어 쪽에서 결정이 필요하다.
2. **스프라이트 캔버스 혼합**
   - PixelLab 공격·사망 애니가 캔버스를 키워서 엔티티 안에 크기가 섞여 있다(예: char 64/84/88, mboss 128/168~176, boss 192/248).
   - 중심 정렬이라면 문제없다. 발 기준 피벗을 쓰면 애니별 오프셋이 필요하다.
3. **애니 누락 118건** (`ASSET-MANIFEST.json → missing.sprite_anims_missing_vs_art_anim_specs`)
   - face_states는 엔티티 대부분에 없다.
   - comp idle·special이 없다(7종).
   - mboss attack_b, summon, stagger, intro, toechi_collapse가 없다(4종).
   - 보스 역려 attack_3, intro, phase_shift, form 오버레이가 없다.
   - 화신 accept_smile, descend, 동쪽 방향 idle·attack이 없다.
   - 저승사자 sal_geodum이 없다.
   - nohat_head_layer가 없다.
   - 불가사리는 사양이 `move_s64/80/96`인데 실제로는 `__s64`/`__s80` 변주 폴더 방식이다. 둘 중 하나로 통일해야 한다.
4. **프레임 수 불일치** (`missing.sprite_anim_frame_count_vs_spec`)
   - char hurt는 6f(사양 2), death는 7f(사양 8)다.
   - mboss·화신 idle은 4f(사양 6), attack은 9f(사양 8)다.
   - 동작에는 지장이 없다. 사양을 실제에 맞출지 결정이 필요하다.
5. **사양 엔티티 미제작**
   - v1: elite_wongwi(오라만), boss_wongyeol, boss_imugi, overlay_pattern, overlay_aura, overlay_aura_hapil.
   - x1: char_beopsa, boss_yeonggam, boss_daeakgwi.
   - 단, overlay_pattern은 `vfx_bingui_pattern_tiles`가 대체할 수 있다.
6. **SFX v1 누락**: P1 81건, P2 31건(목록은 매니페스트에 있다). 무기 SFX 다수(삼지창, 작두, 사인사검 등), 적 고유음, 보스음, 상자음이 포함된다.
   - 장단 패턴 176개는 `proto` 상태다(국악 자문 전 원형).
7. **가독성 주의**
   - 혼불 소(청록 물방울)와 처녀귀신 탄(청 물방울)이 실루엣이 비슷하고 색상도 가깝다.
   - 현재는 색으로 구분되지만, 색약 옵션에서 다시 확인해야 한다.
8. **미검증**
   - 이번 단계에서 Godot 런타임 재생은 하지 않았다.
   - G6의 화면 셰이더 2종(screen_flash, silence_desat)은 컴파일된 적이 없다.
9. **pixelfx check 실패** (원래부터 있던 문제): `vfx_orb_small`이 6×6이라 check.mjs의 최소 8px 규칙에 걸린다. 사양상 6×6이 맞으니 무시해도 된다.

## 6. 권장 재생성 (PixelLab 잔여 291 gen)

- 구미호: 먹빛 꼬리, 붉은 눈, 한국 설화 톤으로 다시 만든다(idle, move, attack_a, 약 15 gen).
- 역귀 떼: 귀 모양만 인페인트한다(약 2 gen).
- 무장승 삿갓: 인페인트한다(약 2 gen).
- 그다음에 위 누락 애니를 우선순위(P0 전투: comp idle·special, face_states)대로 진행한다.
