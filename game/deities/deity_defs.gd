## 신령 연출·표시용 정적 도우미(데이터 조회 + 에셋 키 + 색). 소유: deities.
## class_name 없이 preload 로 쓴다(정적 캐시 금지 규칙: 캐시는 TrialDirector 인스턴스가 들고 있다).
## 색 규칙: 백 #f2ece0 은 해원 예약 → 신령 가호 쪽은 한지빛(K.COL_HANJI). 텔레그래프는 오방 청 테두리 + 흑 채움.

const ORDER: PackedStringArray = ["deity_sansin", "deity_yongwang", "deity_chilseong", "deity_janggun", "deity_barigongju", "deity_jeseok_daegam"]

const FACE_WIEOM: StringName = &"wieom"
const FACE_GAHO: StringName = &"gaho"

const COL_TG_EDGE: Color = Color(0.165, 0.36, 0.667, 0.95)   # 오방 청 #2a5caa
const COL_TG_FILL: Color = Color(0.06, 0.05, 0.09, 0.42)     # 흑 반투명 40%
const COL_GOLD: Color = Color(1.0, 0.953, 0.784)             # 황백 #fff3c8 (신령 빛, 순백 금지)


## vfx_*_<key> 변주 키(hwasin_won, confirm_ring, bingui_pillar, sinjangdae_descend, trial_block_wall).
static func vfx_key(deity_id: StringName) -> String:
	return String(deity_id).trim_prefix("deity_")


## overlay_head / overlay_jimul 파일 접두(제석·대감은 "daegam").
static func overlay_key(deity_id: StringName) -> String:
	var k: String = vfx_key(deity_id)
	return "daegam" if k == "jeseok_daegam" else k


static func avatar_entity(deity_id: StringName) -> String:
	return "avatar_" + vfx_key(deity_id)


## 신령 고유색(오라·문양·배너 테두리). 예약색 HEX 를 그대로 쓰지 않는다.
static func color(deity_id: StringName) -> Color:
	match String(deity_id):
		"deity_sansin":
			return Color(0.89, 0.55, 0.18)
		"deity_yongwang":
			return Color(0.25, 0.68, 0.66)
		"deity_chilseong":
			return Color(0.62, 0.72, 1.0)
		"deity_janggun":
			return Color(0.91, 0.73, 0.19)
		"deity_barigongju":
			return Color(0.78, 0.49, 0.73)
		"deity_jeseok_daegam":
			return Color(0.86, 0.62, 0.26)
	return K.COL_HANJI


static func face_color(face: StringName) -> Color:
	return K.COL_JEOK_HI if face == FACE_WIEOM else K.COL_HANJI


## 화면 이름(쉬운 말, design/19 §2.3): 위엄 → 싸움 / 가호 → 모심
static func face_name(face: StringName) -> String:
	return "싸움" if face == FACE_WIEOM else "모심"


static func name_ko(deity_id: StringName) -> String:
	var d: Dictionary = Data.deity(String(deity_id))
	return String(d.get("name_ko", String(deity_id).trim_prefix("deity_")))


## 짧은 이름(안내판·이름표용): "장군·오방신장" → "장군", "將軍·五方神將" → "將軍".
static func short_name(deity_id: StringName) -> String:
	return name_ko(deity_id).get_slice("·", 0)


static func short_hanja(deity_id: StringName) -> String:
	return hanja(deity_id).get_slice("·", 0)


static func hanja(deity_id: StringName) -> String:
	return String(Data.deity(String(deity_id)).get("hanja", ""))


static func face_title(deity_id: StringName, face: StringName) -> String:
	var faces: Dictionary = Data.deity(String(deity_id)).get("faces", {})
	var f: Dictionary = faces.get(String(face), {})
	return String(f.get("name_ko", face_name(face)))


static func task_name(deity_id: StringName) -> String:
	var t: Dictionary = Data.deity(String(deity_id)).get("gaho_task", {})
	return String(t.get("name_ko", "의례 과제"))


static func avatar_name(deity_id: StringName) -> String:
	var a: Dictionary = Data.deity(String(deity_id)).get("avatar", {})
	return String(a.get("name_ko", "화신"))


## 공수 한 줄(없으면 ""). idx 는 연출 난수(fx)로 고른다.
## 제석·대감처럼 면별로 나뉜 표({wieom:{gs_*}, gaho:{gs_*}})는 face(없으면 위엄 → 가호 순)에서 찾는다.
static func gongsu(deity_id: StringName, trigger: String, face: StringName = &"") -> String:
	var g: Dictionary = Data.deity(String(deity_id)).get("gongsu", {})
	if not g.has(trigger) and (g.get("wieom") is Dictionary or g.get("gaho") is Dictionary):
		var first: String = String(face) if face != &"" else "wieom"
		var second: String = "gaho" if first == "wieom" else "wieom"
		var fd: Variant = g.get(first, {})
		if fd is Dictionary and (fd as Dictionary).has(trigger):
			g = fd
		else:
			var fd2: Variant = g.get(second, {})
			g = fd2 if fd2 is Dictionary else {}
	var arr: Variant = g.get(trigger, [])
	if arr is Array and arr.size() > 0:
		return String(arr[Rng.int_s(&"fx", 0, arr.size() - 1)])
	return ""


## 받은 힘 한 줄(쉬운 말, design/19 §2·§4.6). 결과 화면 '힘을 받았다 — …'에 쓴다. 숫자는 플레이어 쪽 방향으로.
const FACE_PLAIN: Dictionary = {
	"deity_sansin:wieom": "가까이 치는 무기 피해↑ · 8번마다 호랑이 울음(주변 귀신 겁줌)",
	"deity_sansin:gaho": "호랑이가 함께 달려요 · 넋 동무가 오래 따라요",
	"deity_yongwang:wieom": "범위·지속 시간 +25%",
	"deity_yongwang:gaho": "풀어 준 자리에 맑은 물이 고인다",
	"deity_chilseong:wieom": "별이 떨어진다 · 부활 +1",
	"deity_chilseong:gaho": "부활 +1 · 흰 길 감싸기에 별빛",
	"deity_janggun:wieom": "공격 속도 +10% · 치명타↑",
	"deity_janggun:gaho": "호위 장수 넷 · 방어 +3",
	"deity_barigongju:wieom": "벤 귀신이 구슬을 더 남겨요 · 줍기 범위 +30%",
	"deity_barigongju:gaho": "넋 동무 +12 · 넋 동무가 쏜다",
	"deity_jeseok_daegam:wieom": "엽전 +50%",
	"deity_jeseok_daegam:gaho": "회복 +2 · 둘레에 울타리",
}
## 원 카드용 아주 짧은 줄(12자 안팎): '◆ 싸워 이기면: …' / '○ 모셔 드리면: …'
const FACE_SHORT: Dictionary = {
	"deity_sansin:wieom": "가까이 치는 무기↑ · 호랑이 울음",
	"deity_sansin:gaho": "호랑이 동무 · 넋 동무 오래",
	"deity_yongwang:wieom": "범위·지속 +25%",
	"deity_yongwang:gaho": "풀린 자리에 맑은 물",
	"deity_chilseong:wieom": "별이 떨어짐 · 부활 +1",
	"deity_chilseong:gaho": "부활 +1 · 별빛 고리",
	"deity_janggun:wieom": "공격 속도 +10%",
	"deity_janggun:gaho": "호위 장수 넷 · 방어 +3",
	"deity_barigongju:wieom": "벤 귀신이 구슬을 더 남김",
	"deity_barigongju:gaho": "넋 동무 +12",
	"deity_jeseok_daegam:wieom": "엽전 +50%",
	"deity_jeseok_daegam:gaho": "회복 +2 · 울타리",
}


static func face_plain(deity_id: StringName, face: StringName) -> String:
	return String(FACE_PLAIN.get(String(deity_id) + ":" + String(face), face_title(deity_id, face)))


static func face_short(deity_id: StringName, face: StringName) -> String:
	return String(FACE_SHORT.get(String(deity_id) + ":" + String(face), face_plain(deity_id, face)))


## 한 줄 요약(옛 이름 — 지금은 쉬운 말 face_plain 과 같다).
static func face_summary(deity_id: StringName, face: StringName) -> String:
	return face_plain(deity_id, face)


## 모심(가호) 과제 한 줄 안내(처음 하는 사람용, 쉬운 말).
static func task_hint(deity_id: StringName) -> String:
	match String(deity_id):
		"deity_sansin":
			return "쉼터 원 안에 서서 길 잃은 넋을 지키세요"
		"deity_yongwang":
			return "물에 든 넋을 건져 가운데 용왕상으로 데려가세요"
		"deity_chilseong":
			return "빛나는 별을 번호 순서대로 밟으세요"
		"deity_janggun":
			return "깃발 자리 다섯 곳에 잠깐씩 서세요"
		"deity_barigongju":
			return "작은 넋들을 뒤에서 몰아 저승 문으로 들여보내세요"
		"deity_jeseok_daegam":
			return "굿상 곁을 지키며 흰 길로 감싸세요"
	return "과제를 하세요"


static func wieom_hint() -> String:
	return "큰 신령 곁에 붙어 무기로 치세요 (숨 고를 때 1.5배)"


## 의례물(가호 과제) 이름 — HUD 가호 게이지 옆 표식.
static func task_object_name(deity_id: StringName) -> String:
	match String(deity_id):
		"deity_sansin":
			return "쉼터"
		"deity_yongwang":
			return "용왕상"
		"deity_chilseong":
			return "칠성"
		"deity_janggun":
			return "오방기"
		"deity_barigongju":
			return "저승 문"
		"deity_jeseok_daegam":
			return "굿상"
	return "의례"


## 18:00 합일 호명 한 단어(data hapil.call_words 와 같은 순서).
static func call_word(deity_id: StringName) -> String:
	var h: Dictionary = Data.get_value("deities", "hapil", {})
	var order: Array = h.get("call_order", [])
	var words: Array = h.get("call_words", [])
	var i: int = order.find(String(deity_id))
	if i >= 0 and i < words.size():
		return String(words[i])
	return name_ko(deity_id) + "—"


## 시련 순번(첫째·둘째 …).
static func ordinal(n: int) -> String:
	var t: PackedStringArray = ["", "첫째", "둘째", "셋째", "넷째", "다섯째"]
	return t[clampi(n, 0, t.size() - 1)]


## 무당별 몸주신. char_mansin 은 로비 선택(세이브) → 없으면 산신(무료 청신).
static func momju_of(char_id: StringName) -> StringName:
	var mods: Dictionary = Data.get_value("deities", "character_mods", {})
	var m: Dictionary = mods.get(String(char_id), {})
	var v: String = String(m.get("momju", ""))
	if v.begins_with("deity_"):
		return StringName(v)
	var saved: Variant = Save.get_value("momju." + String(char_id), null) if Save != null else null
	if saved is String and String(saved).begins_with("deity_"):
		return StringName(String(saved))
	return &"deity_sansin"


## 바닥 텔레그래프 채움/테두리(화신 공격). 백·황 금지.
const COL_TG_HOT: Color = Color(0.894, 0.376, 0.31, 1.0)    # 적 밝음 #e4604f — 발동 직전 테두리 번쩍(위험)
const COL_BULLET_CORE: Color = Color(0.102, 0.102, 0.102)   # 흑 #1a1a1a
const COL_BULLET_RIM: Color = Color(0.165, 0.36, 0.667)     # 청 #2a5caa
