class_name UiSettings
extends RefCounted
## 설정 값(저장·적용). 소유: ui. GAME_FEEL 7장 접근성 표 + 음량.
## 저장 경로: Save.profile["settings"]["a11y"|"audio"|"ui"] (스키마 소유 meta — settings.a11y 추가 요청함).
## 적용: Juice/Game/Audio 의 공개 필드를 직접 쓴다(GAME_FEEL 7 "설정 화면이 Juice/Game 공개 필드를 직접 쓴다").

## 옵션 정의: key, 표시명, 값 목록, 표시 문자열, 기본값 인덱스
const OPTIONS: Array[Dictionary] = [
	{"key": "audio.master", "label": "전체 음량", "values": [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100], "suffix": "%", "def": 8},
	{"key": "audio.music", "label": "장단(음악)", "values": [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100], "suffix": "%", "def": 8},
	{"key": "audio.sfx", "label": "효과음", "values": [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100], "suffix": "%", "def": 9},
	{"key": "a11y.shake", "label": "화면 흔들림", "values": [0, 25, 50, 75, 100], "suffix": "%", "def": 4},
	{"key": "a11y.flash", "label": "화면 번쩍임", "values": [0, 50, 100], "names": ["끔", "50%", "100%"], "def": 2},
	{"key": "a11y.hitstop", "label": "타격 멈춤", "values": [0, 1, 2], "names": ["기본", "짧게", "끔"], "def": 0},
	{"key": "a11y.enemy_flash", "label": "적 피격 번쩍임", "values": [0, 1, 2], "names": ["단색", "외곽선만", "끔"], "def": 0},
	{"key": "a11y.damage_numbers", "label": "피해 숫자", "values": [0, 3, 1, 2], "names": ["자동", "전부", "치명·정예만", "끔"], "def": 0},
	{"key": "a11y.reduce_motion", "label": "움직임 줄이기", "values": [0, 1], "names": ["끔", "켬"], "def": 0},
	{"key": "a11y.player_mark", "label": "무당 강조", "values": [0, 1, 2], "names": ["끔", "켬", "강하게"], "def": 1},
	{"key": "a11y.crowd_dim", "label": "무리 어둡게", "values": [0, 1, 2], "names": ["끔", "보통", "강하게"], "def": 1},
	{"key": "a11y.bullet", "label": "적 탄 강조", "values": [0, 1, 2], "names": ["끔", "켬", "강하게"], "def": 1},
	{"key": "ui.guide", "label": "길잡이 안내", "values": [1, 0], "names": ["켬", "끔"], "def": 0},
]


static func option_index(key: String) -> int:
	for i in OPTIONS.size():
		if String(OPTIONS[i]["key"]) == key:
			return i
	return -1


static func get_int(key: String) -> int:
	var i: int = option_index(key)
	var def_v: int = 0
	if i >= 0:
		var o: Dictionary = OPTIONS[i]
		def_v = int((o["values"] as Array)[int(o["def"])])
	return int(Save.get_value("settings." + key, def_v))


static func set_int(key: String, v: int) -> void:
	Save.set_value("settings." + key, v)
	apply()


static func display(key: String) -> String:
	var i: int = option_index(key)
	if i < 0:
		return ""
	var o: Dictionary = OPTIONS[i]
	var v: int = get_int(key)
	var vals: Array = o["values"]
	var k: int = vals.find(v)
	if o.has("names") and k >= 0:
		return String((o["names"] as Array)[k])
	return "%d%s" % [v, String(o.get("suffix", ""))]


## 값 목록에서 한 칸 이동(좌우 순환 없음).
static func step(key: String, dir: int) -> void:
	var i: int = option_index(key)
	if i < 0:
		return
	var vals: Array = OPTIONS[i]["values"]
	var k: int = vals.find(get_int(key))
	if k < 0:
		k = int(OPTIONS[i]["def"])
	k = clampi(k + dir, 0, vals.size() - 1)
	set_int(key, int(vals[k]))


static func guide_on() -> bool:
	return get_int("ui.guide") != 0


## 저장값을 엔진 쪽에 반영(타이틀·HUD 진입 때, 값 변경 때).
static func apply() -> void:
	Juice.shake_scale = float(get_int("a11y.shake")) / 100.0
	var fl: int = get_int("a11y.flash")
	Juice.flash_scale = float(fl) / 100.0
	Juice.flash_enabled = fl > 0
	var hs: int = get_int("a11y.hitstop")
	Game.hitstop_scale = 1.0 if hs == 0 else (0.5 if hs == 1 else 0.0)
	Juice.enemy_flash_mode = get_int("a11y.enemy_flash")
	Juice.damage_number_mode = get_int("a11y.damage_numbers")   # 0 자동 / 3 전부(군중 규칙 무시) / 1 치명·정예만 / 2 끔
	Juice.reduce_motion = get_int("a11y.reduce_motion") != 0
	# 가시성(design/18 §4)
	Juice.player_mark = clampi(get_int("a11y.player_mark"), 0, 2)
	var cd: int = get_int("a11y.crowd_dim")
	Juice.crowd_dim_scale = 0.0 if cd <= 0 else (1.4 if cd >= 2 else 1.0)
	Juice.bullet_emphasis = clampi(get_int("a11y.bullet"), 0, 2)
	Audio.set_bus_volume_linear(&"Master", float(get_int("audio.master")) / 100.0)
	Audio.set_bus_volume_linear(&"Music", float(get_int("audio.music")) / 100.0)
	Audio.set_bus_volume_linear(&"SFX", float(get_int("audio.sfx")) / 100.0)
	Audio.set_bus_volume_linear(&"UI", float(get_int("audio.sfx")) / 100.0)


## '길잡이 처음부터'(설정): 본 문장 기록·고리 완료·판 수를 비운다 — 시연 전 초기화. 다음 판부터 첫 판처럼 안내.
static func reset_guide() -> void:
	Save.set_value("ui.hints_seen", {})
	Save.set_value("ui.runs", 0)
	persist()


## 디스크 쓰기(자동 테스트 중에는 --ui-save=1 일 때만).
static func persist() -> void:
	if Game.autotest and DebugTools.arg("ui-save") != "1":
		return
	Save.save_profile()


static func ui_sfx(id: StringName) -> void:
	Audio.play_sfx(id, &"UI")
