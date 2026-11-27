class_name UiCopy
extends RefCounted
## UI 문구(카드 한 줄 설명·무당 소개·안내 문장·목표 줄·쉬운 말 사전). 소유: ui.
## 수치가 아니라 표시 문구라 여기 둔다. 근거: design/19 §1~4(쉬운 말·목표 줄), design/04 §3·§4, design/03 무당 소개.

## 무구 기능 한 줄(점지 카드 '새 항목' 설명, plain_ko 가 없을 때). 키 = 기본 무구 ID. 쉬운 말(design/19 §2).
const WEAPON_LINE: Dictionary = {
	"wpn_sinkal": "칼을 던졌다 거둬들인다. 가는 길·오는 길 모두 벤다",
	"wpn_woldo": "몸 둘레를 크게 한 바퀴 휘둘러 벤다",
	"wpn_samjichang": "세 갈래로 찔러 꿰뚫는다",
	"wpn_jakdu": "작두를 들어 내리찍어 땅을 울린다",
	"wpn_sainsageom": "곧은 칼바람이 줄지어 꿰뚫는다. 강한 귀신에 세다",
	"wpn_gakgung": "가장 가까운 귀신을 활로 쏜다",
	"wpn_jangchang": "가는 방향으로 빠르게 연달아 찌른다",
	"wpn_pyeongon": "넓게 후려쳐 밀어낸다",
	"wpn_cheoljillyeo": "지나간 길에 마름쇠를 뿌린다",
	"wpn_hojakdo": "등 뒤로 범의 기세를 내질러 겁을 준다",
	"wpn_bangul": "방울 소리가 둘레로 퍼져 흰 테두리 귀신을 풀어 준다",
	"wpn_buchae": "앞으로 돌풍을 부친다. 흰 테두리 귀신은 끌어온다",
	"wpn_neokjeon": "종이 넋 인형이 둘레를 돈다",
	"wpn_jijeon": "종이돈을 흩뿌려 넋을 달랜다",
	"wpn_gilbe": "가는 길에 흰 베를 깐다",
	"wpn_ssukmul": "정화수를 끼얹어 자리를 씻는다",
	"wpn_sogeum": "둥글게 소금을 뿌린다. 원한을 걷는다",
	"wpn_myeongdu": "거울이 돌며 빛줄기를 쏜다. 어둠에 세다",
	"wpn_janggu": "박마다 '덩!' 사방으로 울린다",
	"wpn_obanggi": "오색 깃발 자리가 힘을 북돋는다",
}

## 무당 소개 한 줄(무당 고르기)
const CHAR_LINE: Dictionary = {
	"char_mansin": "기준이 되는 무당. 붉은 칼과 흰 방울을 고루 쓴다",
	"char_baksu": "월도로 맞받아치는 남무. 맞으면 되갚는다",
	"char_dangol": "장단을 타는 무당. 흰 무기와 흰 길 감싸기에 능하다",
	"char_myeongdu": "동자령이 흰 테두리 귀신을 먼저 귀띔한다. 정밀 사격",
	"char_simbang": "제주 심방. 새 힘을 한 번 더 고를 수 있다",
}

## 쉬운 말 표기층(design/19 §2). 내부 용어·id → 화면 말. UiKit.word(id) 가 읽는다(키 = 영문 id 또는 내부 한글 용어).
## 규칙·내부 id·데이터 키는 바꾸지 않는다. 화면에 나가는 글만 이 표로 바꾼다.
const WORDS: Dictionary = {
	"toechi": "처치", "퇴치": "처치",
	"toechi_verb": "베기",
	"haewon": "풀어 줌", "해원": "풀어 줌",
	"haewon_verb": "풀기",
	"red": "붉은 무기", "붉은 무구": "붉은 무기",
	"white": "흰 무기", "흰 무구": "흰 무기",
	"mugu": "무기", "무구": "무기",
	"pullil": "흰 테두리 귀신", "풀릴 기색": "흰 테두리 귀신",
	"knot_lock": "매듭", "매듭 잠금": "매듭",
	"japgwi": "귀신", "잡귀": "귀신", "원혼": "귀신",
	"elite": "강한 귀신", "정예": "강한 귀신",
	"midboss": "큰 귀신", "중간보스": "큰 귀신",
	"boss": "역병 귀신 역려", "역려": "역병 귀신 역려",
	"yeongga": "넋 동무", "영가": "넋 동무", "행렬": "넋 동무 수",
	"cheondo": "넋 동무가 떠남", "천도": "넋 동무가 떠남",
	"gilbe": "흰 길", "길베": "흰 길",
	"ring": "흰 길로 감싸기", "고리 닫기": "흰 길로 감싸기",
	"gildakkeum": "한꺼번에 풀림", "길닦음": "한꺼번에 풀림",
	"sal": "원한", "살": "원한", "살기": "원한",
	"wongwi": "성난 귀신", "원귀": "성난 귀신",
	"giun": "기운", "굿판의 기운": "기운",
	"jeomji": "새 힘 고르기", "점지": "새 힘 고르기",
	"evo_pair": "진화 짝",
	"passive": "아이템", "패시브": "아이템",
	"box": "상자", "길흉 상자": "상자", "넋함": "상자",
	"sinmyeong": "신명!", "신명 오름": "신명!",
	"trial": "신령의 시험", "시련": "신령의 시험",
	"kkeokgi": "싸워 이기기", "꺾기": "싸워 이기기",
	"mosigi": "모셔 드리기", "모시기": "모셔 드리기",
	"wieom": "싸움", "위엄": "싸움",
	"gaho": "모심", "가호": "모심",
	"hwasin": "큰 신령", "화신": "큰 신령",
	"bingui": "신령의 힘", "빙의": "신령의 힘",
	"mi_bingui": "절반 성공", "미완 빙의": "절반 성공",
	"hapil": "신령 모두 내림", "합일": "신령 모두 내림",
	"momju": "내 신령", "몸주신": "내 신령",
	"reroll": "다시 고르기", "다시 묻기": "다시 고르기",
	"geumjul": "흰 줄", "금줄": "흰 줄",
	"neok": "넋", "gongdeok": "공덕",
	"yeopjeon": "엽전", "bokjeon": "엽전", "복전": "엽전",
	"sindang": "신당 강화", "신당 단장": "신당 강화",
	"shop": "무기 상점", "무구 진열장": "무기 상점",
	"uiroe": "특별 의뢰", "재가집 의뢰": "특별 의뢰",
	"dogam": "도감", "넋기록 서고": "도감",
	"naerimgut": "새 무당 열기", "내림굿": "새 무당 열기",
	"gutpan_door": "출발", "굿판 문": "출발",
	"gongmul": "차린 상", "공물상": "차린 상",
}

## 스탯 화면 이름(design/19 §2.4). data/stats.json 의 name_ui 가 정본이고, 이 표는 데이터에 없을 때의 사본.
const STATS: Dictionary = {
	"stat_jeonggi": "체력", "stat_saenggi": "회복", "stat_sinbok": "방어", "stat_jeopsin_hoepi": "회피",
	"stat_myeongjul": "부활", "stat_sinppal": "공격력", "stat_jangdan": "공격 속도", "stat_gyeoldan": "치명타",
	"stat_puri": "풀기 힘", "stat_sinjang": "발사 수", "stat_doryang": "범위", "stat_gise": "탄속",
	"stat_yeongheom": "지속 시간", "stat_domu": "이동 속도", "stat_chohon": "줍기 범위", "stat_haewon_suryeon": "경험치",
	"stat_siju": "엽전 획득", "stat_jeomgwae": "행운", "stat_salgi": "위험도", "stat_haengnyeol": "넋 동무 수",
	"stat_neok_sumyeong": "넋 동무 시간", "stat_gilbe": "흰 길 길이", "stat_gongsu_gyojeong": "다시 고르기",
	"stat_mullim": "건너뛰기", "stat_geumgi": "빼기",
}
## 화면에서 방향을 뒤집어 읽는 스탯('장단 −10%'(쿨다운) → '공격 속도 +10%'). UiKit.stat_invert(id).
const STAT_INVERT: Array[String] = ["stat_jangdan"]

## '지금 할 일' 목표 줄(design/19 §1.3). 22자 안팎, 행동부터, 어미 '~세요'. HUD(hud.gd _pick_goal)가 우선순위로 하나 고른다.
## 첫 등장 쉬운 풀이: 역려(goal2 '역병 귀신 역려') · 흰 길(ring '걸어온 흰 길') · 공물상(gongmul '차린 상(공물상)').
## 왼쪽 아래 힌트 줄(HINT)은 같은 말을 되풀이하지 않는다 — 목표 줄 = 무엇을 할지, 힌트 = 어떻게·왜.
const GOAL: Dictionary = {
	"goal": "목표: %s까지 굿판을 버티세요",
	"goal2": "끝에 오는 역병 귀신 역려를 보내세요",
	"bonus": "신당의 힘: %s",
	"next_goal": "이번 판 목표: %s",
	"danger": "위험! 무리에서 빠져나가세요",
	"danger_long": "귀신이 적은 쪽으로 걸으세요 — 풀어 준 넋 동무가 대신 맞아 줘요",
	"trial_low": "물러나세요 — 시험은 져도 괜찮아요",
	"trial_fight": "큰 신령 곁에서 무기로 싸우세요",
	"trial_serve": "작은 넋들을 문으로 모셔 오세요",
	"trial_any": "큰 신령과 싸우거나 넋을 모시세요",
	"trial_soon": "곧 신령의 시험 — 빛나는 원으로 가세요",
	"sal_near": "원한이 차요 — 흰 무기로 풀어 늦추세요",
	"midboss": "%s — 쓰러뜨리거나 풀어 주세요",
	"boss_han": "흰 매듭을 밟아 역려를 풀어 주세요",
	"boss_han_n": "흰 매듭을 밟아 역려를 풀어 주세요 (%d/%d)",
	"boss_sal": "역려를 베어 쓰러뜨리세요",
	"settle": "저승사자가 넋을 데려가요 — 버티세요",
	"walk": "걸으며 버티세요 · 무기는 저절로 쳐요",
	"white": "흰 테두리 귀신에게 다가가세요",
	"yeongga": "흰 테두리를 더 풀어 넋 동무를 모으세요",
	"ring": "걸어온 흰 길로 귀신을 한 바퀴 감싸세요",
	"grow": "구슬을 모아 무기를 키우세요",
	"next_trial": "버티세요 · 다음 시험 %s",
	"last_stand": "버티세요 · %s 역려가 와요",
	"elite": "강한 귀신을 잡아 상자를 얻으세요",
	"to_hapil": "버티며 신령을 모으세요 · 18:00 모두 내려와요",
	"hapil": "신령과 함께 마지막 공세를 버티세요",
	"to_hapil_solo": "버티세요 · 18:00 마지막 공세가 와요",
	"hapil_solo": "홀로 마지막 공세를 버티세요",
	"gongmul": "차린 상(공물상)을 흰 길로 감싸세요",
	"boss_soon": "버티세요 · %s 역병 귀신 역려가 와요",
	"box_first": "상자를 주우면 무기가 진화해요",
}

## 이야기 카드(실전 00:01, design/19 §1.1·§3). 거리 카드 자리(prio 2, 2.4초). 셋째 줄(작게)은 Save.current_request_line() 이 있으면 그것.
const STORY_TITLE: String = "어머니를 보내는 굿"
const STORY_LINE: String = "길 잃은 넋들이 몰려와요 — 버티세요"

## 쉼 메뉴 규칙 3줄(design/19 §4.7-4)
const PAUSE_RULES: Array[String] = [
	"◆ 붉은 무기 = 베어 처치 (엽전)",
	"○ 흰 테두리 귀신 = 흰 무기로 풀어 넋 동무로 (넋)",
	"흰 길로 한 바퀴 감싸면 안쪽이 한꺼번에 풀린다",
]

## 온보딩 문장(첫 런 길잡이 순서). 쉬운 말(design/19 §2), 어미 '~요'. 목표 줄(GOAL)과 같은 말을 하지 않는다.
## 용어(화면 전체 통일): ◆ 붉은 무기 = 베어 처치 · ○ 흰 무기 = 풀어 줌 · 흰 길 · 흰 테두리 귀신 · 넋 동무 · 한꺼번에 풀림
const HINT: Dictionary = {
	"move": "WASD·방향키로 걸으며 귀신을 피해요",
	"pullil": "○ 흰 테두리 귀신은 방울 곁에 두면 저절로 풀려요",
	"white_grant": "내 신령이 %s 내렸어요 — ○ 흰 무기는 풀어 줘요",
	"first_haewon": "풀어 줌! 풀린 넋은 넋 동무가 되어 대신 맞아 줘요",
	"ring": "점선 끝 매듭을 밟으면 감싸기가 닫혀요 — 안쪽이 한꺼번에 풀려요",
	"ring_walk": "흰 테두리 귀신 둘레를 동그랗게 걸어 보세요 — 안쪽이 한꺼번에 풀려요",
	"ring_retry": "다시 해 보세요 — 한 바퀴 돌아 처음 밟은 흰 길로 돌아오면 닫혀요",
	"ring_done": "한꺼번에 풀림! 감싼 안쪽 흰 테두리가 모두 풀렸어요",
	"ring_done_first": "한꺼번에 풀림! 풀린 넋은 넋 동무가 되어 대신 맞아 줘요",
	"ring_done_empty": "한꺼번에 풀림! 감싼 안쪽 흰 테두리는 한꺼번에 풀려요",
	"trial_warn": "왼쪽·오른쪽 원 중 모실 신령 쪽으로 걸어가세요",
	"trial_choose": "들어가는 원이 곧 선택이에요",
	"trial_faces": "◆ 싸움이나 ○ 모심 — 먼저 가득 찬 쪽 힘을 받아요",
	"sal": "원한이 차면 성난 귀신이 와요 — 흰 무기로 풀면 늦춰요",
	"wongwi": "벤 귀신이 원한을 모아 성난 귀신으로 돌아왔어요",
	"need_white": "○ 흰 무기가 있어야 풀 수 있어요 — 새 힘 고르기에서 ○ 를 고르세요",
	"jeomji": "하나를 고르세요 · ◆ 붉은 무기는 베기, ○ 흰 무기는 풀기",
	"sinmyeong": "신명! 흰 길 감싸기가 더 쉽게 닫혀요",
	"giun": "↑ 풀어 준 만큼 흰 칸, 벤 만큼 검은 칸 — 20:00 보스 모습이 바뀌어요",
	"daesin": "넋 동무가 대신 맞고 떠났어요 — 많이 풀수록 방패가 두꺼워요",
	"eoduk_1": "쳐다볼수록 커진다… 어둑시니",
	"eoduk_2": "어둑시니는 붉은 무기로 칠수록 커져요 — 등을 돌려 걸으면 사라져요",
	"midboss": "쓰러뜨리면 상자와 엽전, 풀면 따르던 넋까지 함께 — 위 막대 시간 안에",
	"midboss_pullil": "흰 테 — 이제 ○ 흰 무기로 풀 수 있어요",
	"evo_ready": "진화 준비! 강한 귀신이 남긴 상자를 열면 무기가 진화해요",
	"box_first": "벤 귀신은 상자, 풀어 준 귀신은 넋함을 남겨요",
}

## 연속 굿 추임새(hud_combo, 20/40/80/150)
const CHUIMSAE_HAEWON: Array[String] = ["얼씨구", "좋다", "잘한다", "그렇지!"]
const CHUIMSAE_TOECHI: Array[String] = ["물렀거라!", "썩 물렀거라!", "훠이, 물렀거라!", "잡귀잡신은 썩 물렀거라!"]

## 첫 세 판 '다음 굿판의 길' 카드(onboarding_hints.death_cards_first3)
const DEATH_TIP_LOW_HAEWON: String = "흰 무기로 풀어 주면 넋 동무가 대신 맞아 줘요"
const DEATH_TIP_HIGH_HAEWON: String = "붉은 무기로 베면 원혼 구슬이 온전히 모여요 — 빨리 강해져요"
const DEATH_TIP_NO_RING: String = "걸어온 흰 길을 다시 밟아 귀신을 한 바퀴 감싸 보세요"
const DEATH_TIP_FEW_WEAPONS: String = "새 힘 고르기에서 새 무기를 받아 칸을 채우세요"
const DEATH_TIP_TIMEOUT: String = "역려의 흰 매듭을 밟아 풀어야 해요 — 매듭이 뜨면 그 자리로 가세요"

## 19:58 보스 예고: 지금 기운(넋 비율 N)이 부를 역려의 얼굴(한형 N≥0.55 · 살형 ≤0.45). design/19 §4.5
const BOSS_FORM_HAN: String = "흰 칸이 많아요 — 역려가 한의 얼굴로 와요"
const BOSS_FORM_SAL: String = "검은 칸이 많아요 — 역려가 살의 얼굴로 와요"
const BOSS_FORM_MID: String = "흰 칸·검은 칸이 반반 — 역려의 얼굴이 아직 안 정해졌어요"


static func weapon_line(id: String) -> String:
	var base: String = id.split("__")[0]
	if WEAPON_LINE.has(base):
		return String(WEAPON_LINE[base])
	return String(Data.weapon(id).get("archetype", ""))


## 받침에 따라 을/를(마지막 글자가 한글이 아니면 '를')
static func eul(word: String) -> String:
	if word == "":
		return word
	var c: int = word.unicode_at(word.length() - 1)
	if c >= 0xAC00 and c <= 0xD7A3 and (c - 0xAC00) % 28 != 0:
		return word + "을"
	return word + "를"


static func char_line(id: String) -> String:
	return String(CHAR_LINE.get(id, ""))
