class_name K
## 전역 상수. 소유: core(리드). 캐논 예약색(01 6.1 / data/art_palette.json)은 HEX 변경 금지.

const UNIT_PX: float = 32.0          # 1u = 32px (data/weapons.json units)
const TICK_HZ: int = 60
const TICK_DT: float = 1.0 / 60.0
const VIEW_W: int = 640
const VIEW_H: int = 360

# --- 캐논 예약 팔레트 ---
const COL_BAEK: Color = Color(242.0 / 255.0, 236.0 / 255.0, 224.0 / 255.0)   # #f2ece0 백: 풀릴 기색·길베·영가·해원 전용
const COL_BAEK_FLASH: Color = Color(1.0, 253.0 / 255.0, 246.0 / 255.0)      # #fffdf6 해원 섬광 코어 전용
const COL_JEOK: Color = Color(200.0 / 255.0, 50.0 / 255.0, 45.0 / 255.0)     # #c8322d 적: 붉은 무구·퇴치
const COL_JEOK_HI: Color = Color(228.0 / 255.0, 96.0 / 255.0, 79.0 / 255.0)  # #e4604f
const COL_JEOK_DK: Color = Color(140.0 / 255.0, 31.0 / 255.0, 34.0 / 255.0)  # #8c1f22
const COL_CHEONG: Color = Color(42.0 / 255.0, 92.0 / 255.0, 170.0 / 255.0)   # #2a5caa 적 탄 청
const COL_HEUK: Color = Color(26.0 / 255.0, 26.0 / 255.0, 26.0 / 255.0)      # #1a1a1a 오방 흑(외곽선·적 탄 코어)
const COL_MEOK: Color = Color(14.0 / 255.0, 11.0 / 255.0, 22.0 / 255.0)      # #0e0b16 바탕 먹
const COL_MEOK_2: Color = Color(34.0 / 255.0, 28.0 / 255.0, 46.0 / 255.0)    # #221c2e
const COL_HANJI: Color = Color(233.0 / 255.0, 220.0 / 255.0, 192.0 / 255.0)  # #e9dcc0 한지(백 무구 VFX 주색 P)
const COL_HANJI_DK: Color = Color(178.0 / 255.0, 157.0 / 255.0, 118.0 / 255.0) # #b29d76
const COL_HWANG: Color = Color(232.0 / 255.0, 185.0 / 255.0, 49.0 / 255.0)   # #e8b931 황: 엽전·상자·공덕
const COL_CHEONGNOK: Color = Color(85.0 / 255.0, 184.0 / 255.0, 170.0 / 255.0) # #55b8aa 원혼 구슬 소

# --- 피해 색 (data: HitRecord.color, tech 3.6.1) ---
enum DmgColor { NONE = 0, RED = 1, WHITE = 2, UNION = 3, AURA_YEONGGA = 4, RING = 5 }

# --- 처치 동사 ---
const KIND_TOECHI: StringName = &"toechi"
const KIND_HAEWON: StringName = &"haewon"

# --- 적 등급 ---
const TIER_COMMON: StringName = &"common"
const TIER_MINION: StringName = &"minion"
const TIER_ELITE: StringName = &"elite"
const TIER_MBOSS: StringName = &"mboss"
const TIER_BOSS: StringName = &"boss"
const TIER_CHASER: StringName = &"chaser"

# --- 4방향 (D-11) ---
const DIRS: PackedStringArray = ["south", "east", "north", "west"]
enum Dir { SOUTH = 0, EAST = 1, NORTH = 2, WEST = 3 }


static func u(units: float) -> float:
	return units * UNIT_PX


static func to_u(px: float) -> float:
	return px / UNIT_PX


## 각도(라디안, 화면 좌표 y 아래)를 4방향 인덱스로(GAME_FEEL 2.1.7 / ART_STYLE 4.4).
## 구간: E/W 중심 ±55°, N/S 중심 ±35°(대각선은 좌우 방향이 이긴다). 현재 방향은 hysteresis_deg 만큼 더 넓게 유지.
static func dir4_from_vec(v: Vector2, current: int, hysteresis_deg: float = 10.0) -> int:
	if v.length_squared() < 0.0001:
		return current
	var ang: float = rad_to_deg(atan2(v.y, v.x))  # 0=east, 90=south
	var cur: int = clampi(current, 0, 3)
	if absf(wrapf(ang - DIR_CENTER[cur], -180.0, 180.0)) <= DIR_HALF[cur] + hysteresis_deg:
		return cur
	for i in 4:
		if absf(wrapf(ang - DIR_CENTER[i], -180.0, 180.0)) <= DIR_HALF[i]:
			return i
	return cur


const DIR_CENTER: PackedFloat32Array = [90.0, 0.0, -90.0, 180.0]   # south,east,north,west
const DIR_HALF: PackedFloat32Array = [35.0, 55.0, 35.0, 55.0]
## 아틀라스 행(S,E,N 3행). west = east 행 + 좌우 반전(ART_STYLE 4.4).
const DIR_ROW: PackedInt32Array = [0, 1, 2, 1]


## 화면 좌표 반올림 단일 함수: floor(x + 0.5). GDScript round()는 음수 .5 에서 방향이 달라 쓰지 않는다(GAME_FEEL 2.6).
static func rnd(x: float) -> float:
	return floorf(x + 0.5)


static func rndv(v: Vector2) -> Vector2:
	return Vector2(floorf(v.x + 0.5), floorf(v.y + 0.5))


## 8방향 양자화 단위 벡터(성분 -1/0/1).
static func dir8(v: Vector2) -> Vector2:
	if v.length_squared() < 0.0001:
		return Vector2.ZERO
	var a: float = snappedf(atan2(v.y, v.x), PI / 4.0)
	return Vector2(rnd(cos(a)), rnd(sin(a)))


static func fmt_time(sec: float) -> String:
	var s: int = int(sec)
	return "%02d:%02d" % [s / 60, s % 60]
