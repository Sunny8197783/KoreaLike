# ART_STYLE — 넋길 아트 바이블 (초안 v0.1)

- 상태: **초안, 사용자 승인 대기.** 승인 전에는 이 문서로 에셋을 대량 생성하지 않는다. 4장 파일럿도 승인을 받은 뒤에 실행한다.
- 적용 범위: 앞으로 **모든 PixelLab MCP 호출**(생성·애니·편집)과 손으로 그리는 보정. 이 문서의 '반드시/금지'는 강제 규칙이다.
- 상위 문서: `design/13-art-direction.md`(기획 아트 디렉션, 이하 '13장'), `data/art_palette.json`, `data/art_anim_specs.json`. 충돌하면 캐논(01)이 먼저이고, 그다음 이 문서와 13장 순이다. 이 문서는 13장의 규격을 **PixelLab 호출 규칙과 자동 검사**로 바꿔 놓은 것이다.
- 근거: `DIAGNOSIS.md` (측정 ID A*, B*, C-G*)

---

## 0. 한 줄 규칙

> **"1게임픽셀 = 1원본픽셀, 발이 피벗이고, 엔티티 하나 = 팔레트 하나, 알파는 0과 255뿐. 생성은 시작일 뿐이며, 후처리와 `art_lint`를 통과해야 게임에 들어간다."**

---

## 1. 기준 해상도·픽셀 밀도

### 1.1 화면 규칙 (변경 없음)
- 월드 640×360, **정수 배율만**(720p ×2, 1080p ×3, 1440p ×4). 1유닛 = 32px = 타일 1칸. 현재 엔진 설정이 이 조건을 만족하는 것을 확인했다(DIAGNOSIS A1).
- 런타임에서 행위자를 **회전하거나 비정수 배율로 그리는 것을 금지**한다. 예외는 8px 이하 파티클과 어둑시니 셰이더 몸체뿐이다(13장 2.3). 길쭉한 투사체는 22.5° 간격 16방향을, 회전체는 spin 프레임을 미리 그려 둔다.
- 혼합 해상도(2배로 그린 프롭 등) 금지. 축소 리샘플로 크기 변형을 만드는 것도 금지한다(C-G8, `tools/scale_variant.py` 사용 중단).

### 1.2 사용자안과 권장안 비교

사용자 예시는 캐릭터 32×32, 보스 64×64, 투사체 16×16이다. 진단 결과를 근거로 **권장안은 사용자안과 다르다.** 이유는 아래 표와 같다.

| 판단 근거 | 사용자안 (캐릭터 32 / 보스 64 / 투사체 16) | 권장안 (13장 1.3 규격 + 몸 높이 엄수) |
|---|---|---|
| 지금 에셋의 실제 점유 | 플레이어 몸 57~62px → 약 28px로 절반 이하. 5인 전원을 재생성해야 한다 | 플레이어 몸 60 → 44~48(−20~27%). 역시 재생성이 필요하지만 캔버스(64)와 오버레이 체계는 그대로 유지 |
| 1,000마리 가독성 (13장 2.10) | 주인공(몸 약 28)이 잡귀 L(32~40)보다 작아진다. "무리 속 삼각형 하나 = 나"(2.2)가 깨진다 | 주인공 44~48 > 잡귀 S 18~24 / M 26~32 / L 32~40. 크기 위계 자체가 정보 위계가 된다 |
| 디테일 예산 | 얼굴 폭 4~5px, 눈 1px. 홍철릭·흑립·부채·방울을 4방향에서 구분하기 어렵다(추정) | 얼굴 8~10px, 눈 1×2(13장 2.3). 고증 식별 요소(겹친 옷 단 색 띠)를 넣을 수 있다 |
| 기존 컨셉과의 연속성 | 빙의 머리 오버레이(32×32, 앵커 (16,24)), `overlay_head` 48파일, `overlay_jimul`, 화신 48/96/128이 모두 64px 무당을 전제로 한다. 전부 다시 설계해야 한다 | 그대로 쓴다 |
| 보스 | 64는 정예(64~96)와 같거나 작다. 중간보스 128과 위계가 뒤집힌다 | 정예 64~96 < 중간보스 128 < 보스 192/256 |
| 투사체 16×16 | 동의한다 | **동의한다**(신칼 현재 16×16). 적 탄은 6/8/10/14px 원형으로 별도 규격(13장 2.10.4) |
| PixelLab 비용 | v3 텍스트 생성은 16~90px가 모두 2 gen이라 차이 없음 | 같음. 64px 이하 애니는 방향당 1 gen이라 차이 없음 |
| 성능 | 차이 미미(추정: MultiMesh 인스턴스 수가 병목이고 텍스처 크기는 아님) | 같음 |

**결론: 권장안을 채택하자고 제안한다.** 사용자안의 장점(작고 깔끔한 SNES 감각)은 "몸 높이를 캔버스의 70% 안팎으로 줄이고 색 수를 24색 이하로 묶는 것"으로 얻는다. 몸 높이는 실제로 줄어든다(60→44~48). 최종 선택은 사용자에게 맡긴다(결정 사항 1).

### 1.3 최종 권장 규격표

| 등급 | 캔버스(px) | 실제 몸 높이 목표(px) | 발 피벗 (캔버스 좌표) | 여백 | PixelLab 생성 size (추정, 파일럿에서 검증) | 비고 |
|---|---|---|---|---|---|---|
| 플레이어 무당 | **64×64** | **44~48** | **(32, 58)** | 사방 ≥2, 위 ≥3 | v3 `size=48`(몸 약 44, C-G4) → 64 캔버스에 패딩 | 지금 60~62는 불합격 |
| 영가·동행령 | 32×32 | 어른 22~26, 아이 14 | (16, 29) | ≥2 | v3 `size=32` | 하단 페이드는 셰이더로만 |
| 일반 잡귀 S | 32×32 | 18~24 | (16, 29) | ≥2 | v3 `size=32` | dalgyal, subi, dokkaebi_bul |
| 일반 잡귀 M | 40×40 | 26~32 | (20, 36) | ≥2 | v3 `size=36~40` | agwi, gaekgwi, mul, yeongsan |
| 일반 잡귀 L | 48×48 | 32~40 | (24, 44) | ≥2 | v3 `size=44` | cheonyeo, mongdal, hosik, sangmun, hwehwe |
| 정예 | 64 / 80 / 96 | 48~84 | (w/2, h−8) | ≥3 | v3 `size`=캔버스−8 | 불가사리 3단계는 **단계별로 따로 생성**(축소 금지) |
| 중간보스 | 128×128 | 96~116 | (64, 118) | ≥4 | v3 `size=120`(3 gen) | 2방향(S, E) + 미러 |
| 보스 | 192×192 / 256×256 | 150~240 | (96, 178) / (128, 240) | ≥4 | v3 `size=184` / `248` | 정면 1방향 + 좌우 미러 |
| 화신 | 48 / 96 / 128 | 등급별 | 위와 같은 규칙 | ≥3 | — | |
| 저승사자(추적자) | 64×64 | 48~56 | (32, 58) | ≥2 | v3 `size=56` | |
| 머리 오버레이 | 32×32 | — | 머리 앵커 (16, 24) | — | — | 플레이어 64 캔버스가 전제 |
| 플레이어 투사체 | **16×16** (긴 것 32×16) | 실체 6~12 | 중심 (8, 8) | ≥1 | 손그림 또는 workbench | 회전 = 사전 렌더 8/16 프레임 |
| 적 탄 | 6 / 8 / 10 / 14 원형 | — | 중심 | 0 | 손그림 고정 규격 | 13장 2.10.4. 생성 금지 |
| VFX | **16 / 32 / 64** 정사각 (특수 128) | — | 발생점 = 앵커 | ≥1 | vfx_workbench / pixelart_workbench | 타격 스파크 16×16 |
| 아이콘 | 16×16 (HUD), 24×24 (카드) | 꽉 채움 −1px | — | ≥1 | create_ui_asset 또는 손그림 | 16px는 sel-out 금지 |
| 타일 | **32×32** | — | — | 0 | create_topdown_tileset `tile_size 32` | 1유닛 = 32px, Wang·고리 격자와 같다. 16px 타일은 쓰지 않는다(장식은 프롭으로) |

- **피벗 규칙:** 가장 아래 불투명 행(발끝·치맛단)이 피벗 y의 ±1px 안에 있어야 한다. 모든 애니·방향·프레임에 적용한다. 떠다니는 귀신은 '가상 발끝'(그림자 중심)을 피벗으로 본다.
- **방향 정렬:** 같은 엔티티에서 방향마다 몸 중심 x 차이 ≤1px(지금 만신은 약 5px, A6).
- **같은 엔티티 = 같은 캔버스:** 애니마다 캔버스가 다르면(지금 64/84/88 혼재) 피벗 기준으로 **패딩만** 한다. 리사이즈는 금지한다(`sprite_lib.gd:92-93` NEAREST 리사이즈 폐기 대상).

---

## 2. 시점·스타일 프롬프트

### 2.1 프롬프트 조립 공식 (반드시 이 순서)

```
[A 고증 접두] + [B 대상 서술: 역할·체형·의상 색(방향과 무관하게 고정)·소품 1개] + [C 스타일 접미(등급별)]
```

**A. 고증 접두 (모든 행위자 공통, 복붙):**
```
Korean traditional shamanism (musok) theme, Joseon-era Korean clothing and props,
```

**B. 대상 서술 규칙**
1. 의상 색은 **부위별로** 적는다(예: "deep red outer robe, muted navy inner skirt"). 방향마다 의상이 달라지는 문제(C-G7)를 막으려고 끝에 `same outfit and colors on every side`를 붙인다.
2. 소품은 **1개**만 강조한다(13장 3.7 '사연 소품 1개', 무당은 지물 2개까지).
3. 흰색이 필요한 곳은 `white`라고 쓰지 않는다. 백(`#f2ece0`)은 예약색이다. 잡귀 소복은 `ash-gray mourning clothes`, 종이 술은 `cream hanji paper`로 쓴다.
4. 귀신 공포는 '일그러짐'으로만 표현한다(빈 눈, 늘어난 입, 기울어진 목). 피·상처 묘사는 쓰지 않는다.

**C. 스타일 접미 (영문 그대로 복붙)**

행위자(플레이어·영가·정예·보스) 공통:
```
low top-down 3/4 view, 16-bit SNES-era pixel art, crisp 1px black outline, high contrast, flat cel shading with 3 tones, lit from top-left, limited palette, clean readable pixel clusters, no anti-aliasing, no dithering, transparent background
```

일반 잡귀(1,000마리 가독성용, 위 접미에 덧붙임):
```
, simple bold silhouette, minimal interior detail, muted wet ash-gray tones
```

VFX·투사체(행위자 접미 대신):
```
pixel art game effect sprite, hard-edged square pixels, no outline, no soft glow, no gradient, no blur, limited palette, transparent background
```

타일:
```
low top-down 3/4 view, 16-bit SNES-era pixel art tile, seamless, low contrast, dark night palette, no outline on tile edges, no dithering except 2x2 ordered
```

> 사용자 예시 접미 `"top-down 3/4 view, 16-bit SNES pixel art, crisp dark outline, high contrast, flat cel-shading, transparent background"`를 그대로 포함하되 두 가지를 바꿨다. ① 시점을 기존 전 에셋과 같은 **low top-down**(PixelLab `view` 값, 약 20°)으로 고정했다. ② `lit from top-left`(C-G11), `clean readable pixel clusters`, `no anti-aliasing`(C-G3)을 더했다.

### 2.2 금지 키워드 (프롬프트에 절대 넣지 않는다)

PixelLab `create_character`와 `animate_character`에는 negative prompt 인자가 없다(`search_help` 확인). 그래서 금지어는 **넣지 않는 것**으로 지키고, 결과물은 G0 검수(13장 2.12, 3.8)에서 걸러 낸다.

| 분류 | 금지어 | 대신 |
|---|---|---|
| 일본풍 | japanese, samurai, kimono, yukata, oni, yokai, kabuto, ninja, kunai, shinto, torii, anime, chibi | Joseon, hanbok, dokkaebi(머슴형 거인), heungnip / gat |
| 중국풍 | chinese, wuxia, kung fu, taoist, wudang, jiangshi, qipao, hanfu, mandarin hat | mudang, gut ritual dance, cheollik |
| 서양 오컬트 | cross, pentagram, rune, magic circle, witch, wizard, priest, demon horns, skull, bones, zombie | obang five-direction colors, bujeok talisman, dancheong |
| 고어 | blood, gore, wound, bleeding eyes, intestines, severed | torn thread, ink splash |
| 예약색 충돌 | white robe, pure white, glowing white (행위자 몸) | ash-gray, cream hanji |
| 노이즈 유발(예방 규칙) | painterly, brush stroke, watercolor, minhwa painting style, realistic, photorealistic, 3d render, soft shading, gradient, bloom, `high detail` | flat cel shading, clean pixel clusters |

> 마지막 행은 **예방 규칙**이다. 회화풍 프롬프트가 노이즈를 키웠다는 주장(C-G10)은 검증에서 기각됐다. 노이즈의 확인된 원인은 `detail=high detail`(C-G3)과 후처리 부재다.

### 2.3 PixelLab 파라미터 고정값 (`search_help`로 확인한 실제 옵션명)

**`create_character`**

| 파라미터 | 고정값 | 비고 |
|---|---|---|
| `mode` | `"v3"` (기본). 기존 캐릭터 스타일 복제가 꼭 필요할 때만 `"pro"` | v3: `shading`·`proportions`·`text_guidance_scale`을 무시하고, `outline`·`detail`은 soft hint다. pro: `outline`/`shading`/`detail`을 무시하는 대신 `palette`·`max_colors`·`style_character_id`·`style_image_url`을 받는다(10~25 gen) |
| `view` | `"low top-down"` | `high top-down`, `side`, `oblique` 금지 |
| `outline` | `"single color black outline"` | 생성 후 외곽을 `#1a1a1a`로 강제 재색칠(3.3) |
| `detail` | 플레이어·정예·보스 `"medium detail"`, 잡귀·영가 `"low detail"` | **`"high detail"` 금지**(C-G3, char_mansin이 high였음) |
| `shading` | 넘기지 않음 | v3는 무시한다. 셰이딩은 프롬프트 `flat cel shading with 3 tones`로 지정 |
| `size` | 1.3 표의 '생성 size' | v3 텍스트 생성은 4의 배수 |
| `n_directions` | 참조 이미지를 쓸 때 `4` | 참조 없는 v3는 항상 8방향을 만든다. 런타임은 S/E/N만 쓴다 |
| `body_type` / `template` | 사람형 `"humanoid"`. 네발은 `"quadruped"` + `template`(`bear`·`cat`·`dog`·`horse`·`lion`) | 참조 없는 v3는 사람형만 그린다 |
| `reference_image_url` | 2단계 생성의 기본값: **승인된 south 1장**(정면을 바라보는 그림) | 방향별 의상 불일치 방지(C-G7). 64px 참조 = 1 gen |

**`animate_character`**

| 동작 | 모드·ID | 고정값 |
|---|---|---|
| idle | `template_animation_id="breathing-idle"` (4f) | `directions=["south","east","north"]`, `ai_freedom=0` |
| walk (플레이어) | `"walking-8-frames"` (8f) | 위와 같음. 품질이 부족하면 `mode="skeleton-v3"` + `motion_adjustments={"stride":1.25}` |
| walk (잡귀) | `"walking-4-frames"` (4f) 또는 `mode="v3"`, `frame_count=4` + `palette` | 미끄러지는 귀신은 v3 커스텀 `"gliding forward, hair and sleeves swaying"` |
| hurt | `"taking-punch"` (6f) → 2프레임만 골라 씀 | 'hurt'라는 ID는 없다 |
| death (플레이어) | `"falling-back-death"` (7f) | 마지막 프레임 홀드 |
| **금지 템플릿** | `"sad-walk"`, `"scary-walk"` | rotation 자세와 크기를 보존하지 않는다(C-G5: sangmun 발 6px 점프, 지물 소실) |
| 커스텀(v3·pixminimax·skeleton-v3) | `palette` = 엔티티 팔레트(3.2), `max_colors` = 등급 예산 | template 모드는 `palette`를 받지 않으므로 후처리에서 반드시 양자화 |
| 방향 | west는 **생성하지 않는다** | 4.4 flip 정책 |

**후처리 도구**

| 도구 | 고정값 | 비용 |
|---|---|---|
| `reduce_colors` | `palette_image_url` = 엔티티 팔레트 스트립 PNG, `num_colors`는 넘기지 않음, `dithering="none"`. **엔티티의 모든 프레임을 한 번에**(총 512×512px 이하, 넘으면 애니 단위로 나누되 같은 palette_image 사용). 모든 프레임이 같은 크기여야 하므로 패딩을 먼저 한다 | 0.1 gen/호출 |
| `correct_pixelart` | `strength=0.1`, 같은 크기 프레임끼리 묶어서 | 0.1 gen/호출 |
| `pixelart_workbench` | `repair <id>` → `lint <id>` → `score <id>` (목표 ≥85) | 무료(구독) |
| `vfx_workbench` | VFX·투사체 손제작과 export | 무료(구독) |

---

## 3. 색상 규칙

### 3.1 마스터 팔레트 (`data/art_palette.json` — 65색 + UI 전용 2색)

| 램프 | 색 (어두움 → 밝음) | 예약·용도 |
|---|---|---|
| `mk` 먹 | `#0e0b16` `#17131f` `#221c2e` `#2f2840` `#3f3654` `#544a6b` | **캐논 먹 `#0e0b16`**. 배경, 그림자 색상 이동(청보라) |
| `hk` 흑 | `#1a1a1a` | **행위자 외곽선 전용**, 적 탄 코어 |
| `hj` 한지 | `#5a4a37` `#857154` `#b29d76` `#d2c19c` `#e9dcc0` (UI 전용 `#f6eedc`) | **캐논 한지 `#e9dcc0` = 플레이어·적 스프라이트의 최고 명도 상한**. 백 무구 VFX 주색(P), 종이 술 |
| `bk` 백 | `#d6cfc1` `#f2ece0` (플래시 코어 전용 `#fffdf6`) | **예약**: 풀릴 기색 외곽선, 길베, 영가, 해원 순간 빛, 고 매듭. **행위자 몸·환경·백 무구 VFX에서 금지**(±ΔE6) |
| `jk` 적 | `#561318` `#8c1f22` `#c8322d` `#e4604f` `#f4a183` | **캐논 적 `#c8322d`**. 적 무구 VFX, 퇴치 파열, 원귀 눈, 플레이어 무복(면적 ≤40%) |
| `hw` 황 | `#6a4a12` `#a97c1b` `#e8b931` `#f5d66b` `#fff1b8` | **캐논 황 `#e8b931`**. 엽전, 부적, 등불, 방울 놋쇠 |
| `ch` 청 | `#0f2142` `#1b3a70` `#2a5caa` `#5f93de` `#a9caf5` | **캐논 청 `#2a5caa` = 적 탄·적 장판 전용**. 플레이어 스프라이트·무구 VFX는 ≤2% |
| `cr` 청록 | `#10302f` `#1d5a58` `#2f8c86` `#55b8aa` `#9fe0d4` | 원혼 구슬 소, 물, 용왕, 도깨비불 |
| `gh` 귀회 | `#26292e` `#3a3f46` `#535a62` `#6f7780` `#8f979e` `#aab1b5` | 잡귀 소복·피부. 가장 밝은 색 `#aab1b5`가 상한(적 몸 상대휘도 ≤0.45) |
| `gr` 귀록 | `#262b20` `#3a4230` `#556046` `#727f5f` `#919c7c` | 아귀, 물귀신, 거구귀 |
| `sk` 피부 | `#3b2219` `#6e4330` `#a5704f` `#d29d7a` `#efcdb0` | 무당·화신 피부, 풀릴 기색 사람 얼굴 |
| `eg` 환경 녹 | `#111a14` `#1a2a1e` `#26402b` `#3a5a3c` `#557652` | 환경 전용 |
| `et` 흙·돌 | `#1b1511` `#2c221a` `#433426` `#5e4b36` `#7c674b` | 환경 전용 |
| `dc` 단청 변이 | `#7a3a2c` `#3e6a5a` `#6b3a2a` `#3b4f6e` `#8a7440` | 환경 단청. **무복 남색은 `#3b4f6e`(군청 변이)** |

- 예약 규칙 매트릭스는 13장 2.6.3을 그대로 따른다. 이 문서가 추가하는 것은 '어떻게 강제하는가'(3.3~3.4)다.
- 팔레트 밖의 색은 **한 픽셀도 허용하지 않는다**(행위자·타일·프롭). 마스터에 색을 추가하려면 `art_palette.json`을 고치고 사용자 승인을 받아야 한다(상한 `max_master_colors` 72).

### 3.2 엔티티별 최대 색 수와 팔레트 스트립

`art_palette.json`의 `per_sprite_color_budget`를 그대로 쓴다. **엔티티의 모든 프레임과 방향을 합친 수**에 적용한다(지금은 프레임당 기준으로도 2~5배 초과, 엔티티 전체는 최대 893색).

| 등급 | 최대 색 수 (외곽 `#1a1a1a` 포함) | 지금 (rot south / 엔티티 전체) |
|---|---|---|
| 플레이어 | **24** | 43~56 / 483~893 |
| 영가·동행령 | 10 | 20~57 / 26~197 |
| 일반 잡귀 | **12** | 6~63 / 6~275 |
| 정예 | 16 | 5~58 / 8~154 |
| 중간보스 | 24 | 15~60 / 100~273 |
| 보스 | 32 | 59 / 137 |
| 화신 | 24 | 41~64 / 152~335 |
| 아이콘 | 16 | — |
| 타일셋 | 20 | — |
| 프롭 | 16 | — |
| VFX | **6** (64px 이상 대형은 12까지, `art_palette.json` 개정 제안) | 78/159 시트가 64색 초과 |

- **엔티티 팔레트 스트립:** 엔티티마다 마스터의 부분집합을 `art/palettes/<id>.png`(N×1 px)로 정해 두고, `reduce_colors`의 `palette_image_url`과 커스텀 애니의 `palette`에 넘긴다. 스트립 생성은 `tools/art_lint.py --emit-palette <id>`(사양 3.5)가 `data/art_palette_assign.json`(신규 예정)을 읽어 만든다.
- 파일럿 팔레트 초안은 5장에 있다.

### 3.3 알파 규칙
- 행위자·타일·프롭·아이콘·투사체: **알파 ∈ {0, 255}**. 반투명 0픽셀.
- 반투명이 허용되는 것: VFX 시트 중 `art_vfx_list.json`에 블렌드가 지정된 것, 그리고 셰이더 처리(영가 하단 페이드, 백 무구 P 50%). **영가 PNG의 하단 페이드는 셰이더로 옮긴다**(C-G12: yeongga_body 반투명 100%).
- 이진화 규칙: a ≥ 128 → 255, a < 128 → 0. 외곽 AA 잔여는 이진화한 뒤 `correct_pixelart`로 정리한다.

### 3.4 필수 후처리 파이프라인 (순서 고정, 하나라도 생략하면 런타임 반입 금지)

```
[0] 원본 보관      PixelLab 결과 → art/raw/<id>/  (덮어쓰기 금지, 재현용)
[1] 정규화(로컬)   알파 이진화 → 같은 엔티티 캔버스 통일(피벗 기준 패딩, 리사이즈 금지)
[2] reduce_colors  palette_image_url = art/palettes/<id>.png, dithering="none", 엔티티 전 프레임 1회(≤512²px)
[3] correct_pixelart  strength=0.1 (팔레트 단계가 없으므로 새 색이 생길 수 있다 — 추정)
[4] workbench      pixelart_workbench repair → lint (경고 기록)
[5] 최종 스냅(로컬) 모든 픽셀을 엔티티 팔레트 최근접색으로 스냅 → 외곽 픽셀을 #1a1a1a로 재색칠
                   → 고립 픽셀 제거(8이웃에 같은 색이 없는 내부 픽셀을 다수결 이웃색으로)
[6] 피벗 정렬(로컬) 프레임별 발끝 행 = 피벗 y, 몸 중심 x = 피벗 x ±1 (정수 이동만)
[7] art_lint       tools/art_lint.py 전 항목 PASS + workbench score ≥ 85
[8] 반입           sync_art.py로 game/assets/sprites/<id>/ 복사. 리뷰 시트는 game/assets/_review/
```
- [2]→[3] 순서는 사용자 지시대로 고정한다. [5]의 최종 스냅이 [3]과 [4]에서 생긴 색 표류를 되돌린다.
- 기존 일괄 스크립트(`tools/asset_review_fix.py`, `scale_variant.py`, `palette_variant.py`)의 결과물도 [5]~[7]을 통과해야 한다. comp_dongja(반투명 34%)와 영가(100%)가 이 단계를 건너뛰어 생긴 문제다.

### 3.5 자동 검사 스크립트 사양 — `tools/art_lint.py` (구현 예정, 이번엔 사양만)

경로: `C:/Users/김태양/Desktop/KoreaLike/tools/art_lint.py` (기존 `tools/sync_art.py` 옆). 13장 12.2를 구현하고 진단 항목을 추가한다.

**CLI**
```
python tools/art_lint.py <entity_dir> [--tier player|yeongga|common_s|common_m|common_l|elite|midboss|boss|avatar|projectile|vfx|icon|tile|prop]
                        [--pivot 32,58] [--json out.json] [--strict]
python tools/art_lint.py --all game/assets/sprites      # 전수 검사, 표 출력
python tools/art_lint.py --emit-palette <id>             # art/palettes/<id>.png 생성
python tools/art_lint.py --imports game/                 # .import / .tscn 회귀 검사
```
- 입력: 엔티티 폴더의 `<anim>_<dir>_<f>.png`와 `anims.json`. tier와 pivot을 생략하면 `data/art_anim_specs.json`과 이 문서 1.3 표에서 찾는다.
- 출력: 항목별 PASS/FAIL/WARN과 측정값을 JSON으로 저장한다. 종료 코드는 0(전부 PASS), 1(FAIL 있음), 2(입력 오류). `--strict`이면 WARN도 FAIL로 본다.
- Python 3 + Pillow만 쓴다. 외부 네트워크를 쓰지 않는다.

**검사 항목**

| # | 항목 | 규칙 (FAIL 조건) | 현재 위반 예 |
|---|---|---|---|
| L1 | 캔버스 | 1.3 표 크기와 다름. 같은 엔티티 안에서 캔버스 크기가 섞임 | dalgyal 48(사양 32). mansin 64/84 혼재 |
| L2 | 알파 | 0 < a < 255 픽셀이 1개 이상(VFX 블렌드 지정 시트 제외) | yeongga 100%, comp_dongja 34% |
| L3 | 팔레트 소속 | 엔티티 팔레트 스트립(없으면 마스터) 밖의 색이 1개 이상 | 전 엔티티 0% 준수 |
| L4 | 색 수 | 엔티티 전체 합집합 > 3.2 예산 | mansin 806 > 24 |
| L5 | 예약 백 | 행위자·환경에 `#f2ece0` ±ΔE6 픽셀 >0 | — |
| L6 | 예약 청 | 플레이어·플레이어 VFX에 `ch` 램프 >2% | — |
| L7 | 외곽선 | 실루엣 외곽 픽셀 중 `#1a1a1a` 비율 <95%(행위자). 환경은 `#1a1a1a` 사용 시 FAIL | 전 엔티티 0% |
| L8 | 여백 | 사방 투명 여백 < 등급 최소값 | 플레이어 1~2px |
| L9 | 피벗 | 어떤 프레임이든 최저 불투명 행 ≠ 피벗 y ±1 | mansin 61~62(피벗 58) |
| L10 | 방향 중심 | 같은 애니 0프레임끼리 방향별 몸 중심 x 차 >1px | mansin 28.5~34 |
| L11 | 몸 높이 | 정지 south 몸 높이가 등급 목표 범위를 벗어남 | 플레이어 60~62 |
| L12 | 정지↔이동 | idle_0과 walk_0의 몸 높이 차 >2px 또는 발끝 차 >1px | bulgasari −22%, sangmun 6px |
| L13 | 루프 일관성 | 같은 애니 안 실루엣 면적 변동 >12%(attack·death·spawn 제외), 몸 중심 x 범위 >2px | dueoksini 28%, cx 14px |
| L14 | 고립 픽셀 | 외곽선을 뺀 내부 불투명 픽셀 중 8이웃에 같은 색이 없는 비율 >8%. 평균 같은색 클러스터 <2.5px이면 WARN | gaekgwi 29.9%, sansin 35.7% (측정 정의는 measure.py와 조금 다르므로 파일럿에서 다시 보정) |
| L15 | 미러 정책 | `*_west_*` 파일이 있으면 FAIL(`--allow-west`로 예외 등록 가능) | 전 플레이어·적 |
| L16 | 방향 의상 일관성 | 방향별 상위 8색 집합의 겹침 <75%면 WARN(G0 육안 확인 요청) | mansin S vs E/N |
| L17 | 광원 | 외곽선을 뺀 좌반부−우반부 평균 휘도 <0이면 WARN(추정 지표) | baksu −0.12 |
| L18 | 명도 띠 | 적 몸 상대휘도 최대 >0.45, 플레이어 최대 > `#e9dcc0` | — |
| L19 | VFX | 프레임 크기 ∉ {16,32,64,128}, 색 수 > 예산, 프레임 duration이 데이터와 다름 | 78개 시트 64색 초과 |
| L20 | import 회귀 (`--imports`) | `.import`에 `compress/mode≠0`, `mipmaps/generate=true`가 있음. `.tscn`에 `texture_filter` 덮어쓰기가 있음 | 지금 0건(유지 감시) |
| L21 | 앵커 | 오버레이·지물·투사체 발사 대상 엔티티에 `data/anchors/<id>.json` 프레임 앵커가 빠짐 | 전 엔티티 미작성 |
| L22 | workbench 점수 | 별도 단계: `pixelart_workbench score` <85면 FAIL(lint가 결과를 JSON으로 받아 기록) | gaekgwi 61.6, sangmun 62.7 |

---

## 4. 애니메이션 규격

### 4.1 프레임·fps 표

| 동작 | 프레임 | fps (프레임 길이) | 루프 | 구성 규칙 |
|---|---|---|---|---|
| idle (플레이어·영가) | **4** | **6** (167ms, 루프 0.67s) | O | f0 기본 / f1 어깨 1px 올림 / f2 기본 / f3 무릎 1px 굽힘. 박에 동기할 때는 프레임 길이 = 박 길이/4, **하한 70ms** |
| idle (적) | 없음 | — | — | 정지해 있는 적은 move 0프레임을 쓴다 |
| walk (플레이어) | **8** | **12** × 속도비(0.8~1.6 클램프) | O | f0·f4 = 발 교차 접지 포즈. **발끝 행 고정**(±1). 보폭 목표: 사이클당 이동 거리 85px 대비 발 이동 폭 ≥ 약 40% (추정, 파일럿에서 보정) |
| walk/move (잡귀) | **4** | 8~10 (속도비 적용, 개체별 위상 무작위, ±10% 지터) | O | 머리 1px 흔들림 |
| glide/float (발 없는 귀신) | 4 | 6~8 | O | 몸은 고정하고 머리카락·소매만 2px 출렁 |
| 적 공격 (예비→타격→회복) | **선딜 ≥4f** (12fps, ≥333ms) / **타격 1~2f** / **후딜 3~4f** | 12 | X | 정예·보스는 선딜 ≥0.6s. 타격 프레임은 duration 2배로 홀드(가변 duration은 vfx_lib 개선 B15 후 적용) |
| 플레이어 무구 VFX (자동 공격) | **선딜 2f** / **판정 1f** / **후딜 3~5f** | 16~20 | X | 선딜 = 무구 쪽 1px 당김과 예고 섬광, 판정 = 가장 강한 프레임(duration 2배), 후딜 = 잔상 페이드. 플레이어 몸에 공격 포즈는 그리지 않는다(13장 4.2 범위) |
| hit / hurt | **2** | 16 (63ms) | X | f0 피격 반대 방향 1px 밀림·눈 감음 / f1 복귀. 걷기 위에 덧씌우고 걷기 카운터는 계속 돈다 |
| death (플레이어) | 8 (`falling-back-death` 7 + 홀드 1) | 10 | X | f7 정지 상태로 결과 화면까지 |
| death (적) | 그리지 않음 | — | — | 공용 VFX(퇴치=방사, 해원=상승)와 셰이더 디졸브 |
| spawn | 4 | 10 | X | 먹 안개에서 아래→위로 형체가 나타남 |
| 투사체 spin | 8 (45° 간격 사전 렌더) | 16 | O | 런타임 회전 금지 |
| 타격 스파크 | 4 | 20 | X | f0~f1 판정(홀드), f2~f3 소멸 |

### 4.2 앵커 고정
- 모든 프레임에 피벗(1.3)을 적용한다. 프레임 사이에 '몸 전체 이동'을 그리지 않는다. 이동은 코드가 하고, 그림은 제자리 동작만 담는다.
- 지물·머리·발사 지점 앵커는 `data/anchors/<id>.json`(13장 4.1.5 형식)에 프레임별로 기록한다. 손으로 계산하지 말고 도구로 찍는다.
- **루프 0프레임 = 중립 포즈**로 둔다. 히트스톱이나 방향 전환 때 이 프레임으로 돌아와도 어색하지 않아야 한다.

### 4.3 정지↔이동 연속성
- idle_0과 walk_0은 같은 자세와 몸 높이(±2px), 같은 발끝(±1px)이어야 한다(L12). 정지 단독 PNG(`south.png` 등)는 런타임에서 쓰지 않는다. rotation은 참조용으로만 쓴다.

### 4.4 방향·미러 정책

| 등급 | 저작 방향 | 런타임 | west |
|---|---|---|---|
| 플레이어·영가·잡귀·정예 | **S, E, N** (3) | 4방향 | **flip_h(E)**. 생성 금지 |
| 중간보스 | S, E (2) | 2방향 + 미러 | flip_h(E), N은 S로 대체 |
| 보스 | S (1) | 정면 + 좌우 미러 | flip_h |
| 방향 없음(도깨비불 등) | 1 | 1 | — |

- 미러하면 지물을 든 손이 바뀌는 것(부채가 왼손으로 감)은 허용한다(13장 4 '서=동 미러'). 예외가 필요하면 엔티티별로 `--allow-west`에 등록한다.
- 방향 선택 구간: E/W ±55°, N/S ±35°, 히스테리시스 10°(13장 4.1.1, 코드 B5).

---

## 5. 코드 연출(Juice)과 연결되는 아트 요구사항

Juice 설계는 다음 단계에서 별도 문서로 쓴다. 여기서는 그 설계가 성립하려면 **아트가 지켜야 할 것**만 정한다.

| Juice 기능 (3단계) | 아트 요구 | 이유 |
|---|---|---|
| 스쿼시·스트레치 (착지·피격 −1px, 이동 바운스) | 발 피벗을 정확히(±1) 지킨다. **위 여백 ≥3px**(스트레치 +1px 여유) | 스케일·오프셋을 발 기준 정수 1px로 적용한다. 피벗이 틀리면 발이 떠오른다 |
| 기울기(Tilt) | 회전으로 처리하지 않는다. 필요하면 walk 프레임 안에 1px 앞쏠림을 그려 넣는다 | 픽셀 아트 회전 금지(1.1) |
| 피격 플래시 (적 `jk`, 백 무구 `hj`, 2~4프레임) | **별도 흰색 실루엣 스프라이트는 만들지 않는다.** 셰이더 단색 틴트로 처리한다. 대신 외곽선이 정확히 `#1a1a1a`여야 한다(셰이더가 외곽을 보존하는 기준색) | 백 예약 유지, 에셋 수 절약 |
| hurt 덧씌움 | hurt 2프레임(1px 밀림 + 복귀) | 4.1 |
| 히트스톱 | 루프 0프레임 = 중립 포즈 | 렌더 시계가 멈춰도 자연스럽게 |
| 넉백 | 넉백 이동을 그림에 넣지 않는다 | 이동은 코드 담당 |
| 화면 흔들림 | 요구 없음 | |
| 공격 선딜·판정·후딜 | VFX 시트에 3구간을 프레임으로 분리하고, 판정 프레임을 시트 메타 `impact_frame`에 기록한다 | 코드가 판정 프레임에 deal()을 맞춘다(B13) |
| 잔상 | 행위자 스프라이트에 모션 블러나 잔상을 굽지 않는다. 잔상은 VFX 시트로 만든다 | 프레임 재사용, 히트스톱 정지 |
| 무구 당김·발사 위치 | `data/anchors`의 `hand_l`/`hand_r` 앵커 | 투사체가 손에서 나온다 |
| 적 걷기 위상 분산 | 4프레임 루프의 어느 프레임에서 시작해도 이어져야 한다 | 군중 동기화 깨기(B1) |

---

## 6. 파일럿 세트 명세 (실행은 사용자 승인 후)

### 6.1 대상

| # | 세트 | ID (기존 파일은 덮어쓰지 않음) | 규격 | 생성 단계 |
|---|---|---|---|---|
| P1 | **주인공 만신 idle/walk** | `char_mansin__pilot` | 캔버스 64, 몸 44~48, 피벗 (32,58), 24색 | ① v3 텍스트 `size=48`로 8방향 생성(south 승인용) ② E/N 의상이 south와 다르면 승인된 south를 `reference_image_url`로 넣어 v3 `n_directions=4`로 다시 회전 ③ `breathing-idle` S/E/N ④ `walking-8-frames` S/E/N ⑤ 3.4 파이프라인 |
| P2 | **기본 몬스터: 달걀귀신** | `enm_dalgyal_gwisin__pilot` | 잡귀 S: 캔버스 32, 몸 18~24, 피벗 (16,29), 12색 | ① v3 텍스트 `size=32`, `detail="low detail"` ② `walking-4-frames` S/E/N (발 미끄러짐이 심하면 v3 커스텀 4f + palette) ③ 파이프라인. 선정 이유: stage1 웨이브 등장 29회로 최다. 지금 48 캔버스·몸 44로 사양(32/18~24)과 차이가 가장 큰 대표 잡귀 |
| P3 | **기본 공격 이펙트: 신칼(시작 무구 `wpn_sinkal`)** | `vfx_sinkal_proj__pilot` + `vfx_hit_spark_red__pilot` | 16×16. spin 8f@16fps(사전 렌더, 회전 금지), 타격 스파크 4f@20fps(판정 f0~f1), 6색 | `vfx_workbench` / `pixelart_workbench`로 손제작(무료). 실패하면 `create_image_pro`(16~32px, 10 gen)로 후보를 뽑는다 |

### 6.2 프롬프트 (복붙용)

**P1 만신**
```
Korean traditional shamanism (musok) theme, Joseon-era Korean clothing and props, Korean female mudang shaman of the Seoul gut tradition, deep red cheollik ritual robe layered over a muted navy inner robe, wide sleeves, black heungnip wide-brim hat with a red tassel, holding a folding fan in one hand and a brass bell rattle (bangul) in the other, calm dignified face, same outfit and colors on every side, low top-down 3/4 view, 16-bit SNES-era pixel art, crisp 1px black outline, high contrast, flat cel shading with 3 tones, lit from top-left, limited palette, clean readable pixel clusters, no anti-aliasing, no dithering, transparent background
```
파라미터: `mode="v3"`, `view="low top-down"`, `outline="single color black outline"`, `detail="medium detail"`, `size=48`

**P2 달걀귀신**
```
Korean traditional shamanism (musok) theme, Joseon-era Korean clothing and props, Korean dalgyal gwisin egg ghost, small hunched ghost with a large smooth featureless egg-shaped head and no neck, long disheveled black hair down its back, torn ash-gray mourning hanbok, clutching one small child's rubber shoe, same outfit and colors on every side, low top-down 3/4 view, 16-bit SNES-era pixel art, crisp 1px black outline, high contrast, flat cel shading with 3 tones, lit from top-left, limited palette, clean readable pixel clusters, no anti-aliasing, no dithering, transparent background, simple bold silhouette, minimal interior detail, muted wet ash-gray tones
```
파라미터: `mode="v3"`, `view="low top-down"`, `outline="single color black outline"`, `detail="low detail"`, `size=32`

**P3 신칼** (손제작 기준 형태): 짧은 칼날 + **칼보다 긴 한지색 종이 술**(13장 3.2. 술 없는 단검·쿠나이 금지). 칼날은 적 계열, 술은 한지.

### 6.3 파일럿 팔레트 초안 (마스터 부분집합, 파일럿에서 확정)

| 세트 | 색 (최대 수) |
|---|---|
| P1 만신 (≤24) | `#1a1a1a` · `#0e0b16` `#2f2840` · `#3b2219` `#6e4330` `#a5704f` `#d29d7a` `#efcdb0` · `#561318` `#8c1f22` `#c8322d` `#e4604f` · `#221c2e` `#3b4f6e` · `#5a4a37` `#857154` `#b29d76` `#d2c19c` `#e9dcc0` · `#6a4a12` `#a97c1b` `#e8b931` `#f5d66b` (23색) |
| P2 달걀귀신 (≤12) | `#1a1a1a` · `#0e0b16` `#221c2e` · `#26292e` `#3a3f46` `#535a62` `#6f7780` `#8f979e` `#aab1b5` (9색) |
| P3 신칼·스파크 (≤6 각각) | 신칼: `#561318` `#c8322d` `#e4604f` `#857154` `#d2c19c` `#e9dcc0` / 스파크: `#8c1f22` `#c8322d` `#e4604f` `#f4a183` `#e9dcc0` (순백 `#f2ece0` 금지) |

### 6.4 예상 PixelLab 비용 (search_help 가격표 기준)

| 단계 | 호출 | gen |
|---|---|---|
| P1 생성 | `create_character` v3 텍스트 48px | 2 |
| P1 재회전(의상이 불일치할 때만) | v3 + 참조 south(48~64px) | (1) |
| P1 idle | `breathing-idle` × S/E/N (≤92px 캔버스, 방향당 1) | 3 |
| P1 walk | `walking-8-frames` × S/E/N | 3 |
| P2 생성 | `create_character` v3 텍스트 32px | 2 |
| P2 move | `walking-4-frames` × S/E/N | 3 |
| 후처리 | `reduce_colors` 약 4회 + `correct_pixelart` 약 4회 (각 0.1) | 0.8 |
| P3 | vfx_workbench / pixelart_workbench (무료). 대안 `create_image_pro` 10 | 0 (대안 10) |
| **합계** | | **약 13.8 gen** (재회전 포함 14.8) |
| 재시도 여유 (13장 13.1 계수 ×1.5) | | **상한 약 22 gen** (P3를 PixelLab으로 뽑으면 +10) |

- 실패 처리: 프레임이 L9·L12·L13을 위반하면 그 애니만 `delete_animation` 후 다시 생성한다(엔티티당 최대 2회). 그래도 실패하면 `skeleton-v3`(방향당 3 gen)으로 올린다.
- 남은 크레딧은 실행 직전에 `get_balance`(무료)로 확인한다.

### 6.5 산출물과 합격 기준

**산출물**
- 원본: `art/raw/<pilot_id>/`
- 정규화본: `art/pilot/<pilot_id>/`
- 리뷰 시트: `game/assets/_review/pilot_*.png` (×1·×3, 4방향, 팔레트 스트립, 그레이스케일, 배경 3종)
- 움직임 확인: idle/walk 루프 GIF(×3)와 인게임 캡처. 인게임 렌더링은 **B0 빌드 복구가 먼저**다(DIAGNOSIS 0장). 복구 전에는 오프라인 GIF로만 보여 준다.
- 런타임 에셋 교체: **사용자 OK 전까지 하지 않는다.**

**합격 기준 (전부 만족)**
1. `art_lint` 전 항목 PASS, workbench score ≥85 (비교 기준: 손그림 dokkaebi_bul 98.2)
2. 색 수: P1 ≤24 / P2 ≤12 / P3 ≤6 (엔티티 전체)
3. 피벗 ±1, 정지↔이동 몸 높이 ±2, 루프 면적 변동 ≤12%, 방향 중심 ±1
4. south·east·north의 의상 색 배치가 같다(G0 육안 + L16)
5. 640×360 ×3 화면에서 잡귀 100마리 속 주인공 식별(그레이스케일 포함)
6. 사용자 OK

---

## 7. 기존 에셋 처리 방침 (재생성 vs 후처리로 살리기)

### 7.1 판단 순서

```
① 코드로 해결되는가? (미연결 애니, idle 미사용, west→flip, 피벗 offset)  → 에셋 유지, 코드 과제로
② 아래 '재생성 조건' 중 하나라도 해당하는가?                            → 재생성
③ 3.4 [1]~[6] 후처리 후 art_lint와 score ≥85를 통과하는가?              → 살리기
   통과 못 하면                                                         → 재생성
```

### 7.2 재생성 조건 (하나라도 해당하면 재생성)
1. 몸 높이가 등급 목표를 **+15% 넘게** 벗어난다. 축소 리샘플이 금지돼 있어 후처리로 고칠 수 없다. 해당: 플레이어 5인(60~62 → 44~48), 잡귀 L 다수(42~46 → 32~40), dalgyal(44 → 18~24).
2. 방향마다 의상이나 디자인이 다르다(char_mansin, C-G7).
3. 정지↔이동에서 몸 높이가 ±10% 넘게 달라지거나 지물이 사라진다(template `sad-walk` 사용분, bulgasari −22%, sangmun).
4. 피벗 정렬을 해도 루프 면적 변동이 >20%다(dueoksini 28%, mongdal 28%, yeongsan 24%, gumiho 22%).
5. 축소 변형(`__s64`, `__s80`, `__child`, `__small`)이다. 단계별로 따로 생성한다.
6. 고증 금지 목록(13장 2.12)에 걸린다.

### 7.3 살리기 대상 (후처리만)
- 형태가 맞고 위 조건에 해당하지 않는 것: 예) `enm_subi`·`__sogwi`(28px, 20색, 고립 5~6%), `enm_hwehwe_gwisin`(34색), `comp_dokkaebi_bul`·`enm_dokkaebi_bul`(이미 6색, score 98.2 — 기준 에셋).
- 반투명만 문제인 것: `comp_dongja`, `yeongga_body_*`는 알파 이진화 + 셰이더 페이드로 옮긴다. 단 yeongga 어른은 몸 30이라 사양(22~26)을 넘으므로 조건 1에 따라 재생성 후보다.
- VFX: 업스케일된 시트는 0개다. 색 수 초과·반투명 시트는 `reduce_colors`(예산 6~12)를 거치고, 회전·스케일 사용처는 코드에서 사전 렌더 방식으로 바꾼다.

### 7.4 일괄 작업 순서 (파일럿 OK 이후)
주인공 5인 → stage1 잡귀(등장 빈도순: dalgyal 29, mongdal 19, gaekgwi 18, yeongsan 17, cheonyeo 17, hosik 16, sangmun 14, mul 14, dokkaebi_bul 14, subi 12) → 영가 → 정예 → 중간보스 → 보스·화신. 묶음마다 예산과 결과를 보고하고 승인받는다.

---

## 8. 사용자 결정이 필요한 항목

1. **스케일 기준**: 권장안(플레이어 64 캔버스·몸 44~48, 잡귀 18~40) vs 사용자안(캐릭터 32 / 보스 64). 어느 쪽이든 플레이어 5인은 재생성해야 한다.
2. **파일럿 인게임 렌더링을 위한 B0 빌드 복구 방식**: (a) 중단된 `proj_visual`/`on_projectile_end`를 마저 구현 vs (b) `projectile_pool.gd`를 예전 인터페이스로 되돌림. 둘 다 코드 수정이다.
3. **팔레트 엄격도**: 행위자 100% 마스터 팔레트(권장, 지금 0% 준수라 색감이 꽤 달라진다) vs 엔티티별 보조색을 허용하는 완화안(마스터 ≥95%).
