class_name UiCopy
extends RefCounted
## UI 문구(카드 한 줄 설명·무당 소개·안내 문장). 소유: ui.
## 수치가 아니라 표시 문구라 여기 둔다. 근거: design/04 §3·§4 소제목, design/03 무당 소개, data/onboarding_hints.json.

## 무구 기능 한 줄(점지 카드 '새 항목' 설명). 키 = 기본 무구 ID
const WEAPON_LINE: Dictionary = {
	"wpn_sinkal": "칼을 던졌다 거둬들인다. 가는 길·오는 길 모두 벤다",
	"wpn_woldo": "몸 둘레를 크게 한 바퀴 휘둘러 벤다",
	"wpn_samjichang": "세 갈래로 찔러 꿰뚫고 사슬 표식을 남긴다",
	"wpn_jakdu": "발밑에 작두를 세워 땅을 울린다",
	"wpn_sainsageom": "곧은 검기가 줄지어 꿰뚫는다. 정예·보스에 강하다",
	"wpn_gakgung": "가장 가까운 적을 정밀하게 쏜다",
	"wpn_jangchang": "가는 방향으로 빠르게 연달아 찌른다",
	"wpn_pyeongon": "넓게 후려쳐 밀어낸다",
	"wpn_cheoljillyeo": "지나간 길에 마름쇠를 뿌린다",
	"wpn_hojakdo": "등 뒤로 범의 기세를 내질러 겁을 준다",
	"wpn_bangul": "방울 소리가 둘레로 퍼져 한을 달랜다",
	"wpn_buchae": "앞으로 돌풍을 부친다. 풀릴 기색은 끌어온다",
	"wpn_neokjeon": "종이 넋 인형이 둘레를 돈다",
	"wpn_jijeon": "종이돈을 흩뿌려 넋을 달랜다",
	"wpn_gilbe": "가는 길에 흰 베를 깐다",
	"wpn_ssukmul": "정화수를 끼얹어 자리를 씻는다",
	"wpn_sogeum": "둥글게 소금 결계를 친다. 살을 걷는다",
	"wpn_myeongdu": "거울이 돌며 빛줄기를 쏜다. 어둠에 특효",
	"wpn_janggu": "박 머리마다 '덩!' 사방으로 울린다",
	"wpn_obanggi": "오색 깃발 자리가 기운을 북돋는다",
}

## 무당 소개 한 줄(무당 고르기)
const CHAR_LINE: Dictionary = {
	"char_mansin": "기준이 되는 무당. 붉은 칼과 흰 방울을 고루 쓴다",
	"char_baksu": "월도로 맞받아치는 남무. 맞으면 되갚는다",
	"char_dangol": "장단을 타는 세습무. 흰 무구와 길닦음에 능하다",
	"char_myeongdu": "동자령이 풀릴 기색을 먼저 귀띔한다. 정밀 사격",
	"char_simbang": "제주 심방. 점지를 한 번 더 물을 수 있다",
}

## 온보딩 문장(첫 런 길잡이 순서). onboarding_hints.json 문구를 짧게 다듬은 것.
## 용어 표(화면 전체 통일): 붉은 = 퇴치(깨다) ◆ · 흰 = 해원(풀다) ○ · 길 = 흰 길(길베 — 첫 등장만 병기)
const HINT: Dictionary = {
	"move": "걸으세요 — 무구는 장단에 맞춰 저절로 칩니다",
	"pullil": "흰 테두리 = 풀릴 기색 · ○ 흰 무구로 풀어 해원하세요",
	"pullil_wait": "흰 테두리 = 풀릴 기색 · 곧 ○ 흰 무구(%s)가 와서 풀 수 있습니다",
	"white_grant": "몸주 신령이 %s 내리셨다 — ○ 흰 무구는 풀어 보낸다",
	"first_haewon": "해원! 풀린 넋은 영가가 되어 함께 걷다 대신 맞아 줍니다",
	"ring": "흰 길(길베)을 이어 고리를 닫으세요 — 점선 끝 매듭을 밟으세요",
	"ring_walk": "풀릴 기색 둘레를 동그랗게 걸어 보세요 — 흰 길이 이어지면 고리가 닫힙니다",
	"ring_retry": "다시 해 보세요 — 한 바퀴 돌아 처음 밟은 흰 길로 돌아오면 닫힙니다",
	"ring_done": "길닦음! 고리 안의 풀릴 기색이 한꺼번에 풀렸다",
	"ring_done_first": "길닦음! 고리 안이 한꺼번에 풀렸다 — 영가가 되어 함께 걷다 대신 맞아 줍니다",
	"ring_done_empty": "길닦음! 고리 안의 풀릴 기색은 한꺼번에 풀린다",
	"trial_warn": "신령의 시련이 다가옵니다 — 위 안내판을 따라 원으로 걸어가세요",
	"trial_choose": "들어가는 원이 곧 선택입니다",
	"trial_faces": "꺾으면 위엄, 모시면 가호 — 먼저 찬 쪽으로 실립니다",
	"sal": "↑ 위 기운 바의 붉은 매듭 — 퇴치한 자리에 살이 쌓여, 차면 원귀로 돌아옵니다",
	"wongwi": "퇴치한 귀신이 살을 모아 돌아왔다 — 원귀",
	"need_white": "○ 흰 무구가 있어야 풀어 보낼 수 있습니다 — 점지에서 ○ 를 고르세요",
	"jeomji": "하나를 고르세요 · ◆ 붉은 무구는 퇴치(깨다), ○ 흰 무구는 해원(풀다)",
	"sinmyeong": "신명 오름! 고리가 더 쉽게 닫힙니다",
	"giun": "↑ 굿판의 기운 — 풀어 보낸 만큼 한지빛, 퇴치한 만큼 먹빛. 마지막 손님을 정한다",
	"daesin": "영가가 대신 맞고 먼저 떠났다 — 천도. 많이 풀수록 방패가 두텁다",
	"eoduk_1": "쳐다볼수록 커진다… 어둑시니",
	"eoduk_2": "어둑시니는 붉은 무구로는 커지기만 한다 — 등을 돌려 걸으면 사라진다",
	"midboss": "중간보스 — 퇴치하면 상자와 엽전, 풀면 거느린 넋까지 함께. 위 막대의 시간 안에",
	"midboss_pullil": "흰 테 — 이제 ○ 흰 무구로 풀 수 있다",
	"evo_ready": "진화 준비! 정예가 남긴 상자를 열면 무구가 진화한다",
	"box_first": "퇴치한 귀신은 길흉 상자, 풀어 준 귀신은 넋함을 남긴다",
}

## 연속 굿 추임새(hud_combo, 20/40/80/150)
const CHUIMSAE_HAEWON: Array[String] = ["얼씨구", "좋다", "잘한다", "그렇지!"]
const CHUIMSAE_TOECHI: Array[String] = ["물렀거라!", "썩 물렀거라!", "훠이, 물렀거라!", "잡귀잡신은 썩 물렀거라!"]

## 첫 세 판 '다음 굿판의 길' 카드(onboarding_hints.death_cards_first3)
const DEATH_TIP_LOW_HAEWON: String = "흰 무구로 풀어 보내면 영가가 대신 맞아 준다"
const DEATH_TIP_HIGH_HAEWON: String = "붉은 무구로 한을 깨면 원혼 구슬이 온전히 모인다 — 빨리 강해진다"
const DEATH_TIP_NO_RING: String = "걸어온 흰 길을 다시 밟아 고리를 닫아 보라"
const DEATH_TIP_FEW_WEAPONS: String = "점지에서 새 무구를 받아 칸을 채우라"
const DEATH_TIP_TIMEOUT: String = "역려의 매듭을 밟아 풀어야 한다 — 매듭이 뜨면 그 자리로 걸어가라"

## 19:58 보스 예고: 지금 기운(넋 비율 N)이 부를 손님(한형 N≥0.55 · 살형 ≤0.45)
const BOSS_FORM_HAN: String = "한지빛이 짙다 — 한(恨)의 손님이 온다"
const BOSS_FORM_SAL: String = "먹빛이 짙다 — 살(煞)의 손님이 온다"
const BOSS_FORM_MID: String = "기운이 반반이다 — 손님의 얼굴이 아직 정해지지 않았다"


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
