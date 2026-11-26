class_name DamageCalc
## 피해 계산(상태 무관 부분). 소유: combat.
## 캐논 공식(weapons.json globals.damage_formula):
##   final = round((level_dmg + flat_add) * (1 + sum(sinppal_pct)) * state_mult * crit_mult * special_mults), min 1
## 여기서는 state_mult(풀릴 기색 백 ×풀이)를 뺀 값까지 계산한다. state_mult 는 EnemyManager._resolve_one 이 적용.
## 결단(치명, 02 6.2): 적 무구 전용, 타격마다 stat_gyeoldan(기본 5%, 상한 50%) + 무구 crit 필드.
##   맺힘 대상은 ×crit_mult(2.0), 풀릴 기색 일반 잡귀는 결단타(즉시 퇴치, 매듭 잠금 무시 — EnemyManager 가 crit 플래그로 판정).
## 백 무구는 치명 없음(combat_core.damage.white_crit = false). extra_crit < 0 이면 결단 판정 생략(지속 피해).


## 반환: Vector2(dmg, crit ? 1 : 0)  — 할당 없는 2값 반환.
static func roll(level_dmg: float, white: bool, extra_crit: float = 0.0, special_mult: float = 1.0) -> Vector2:
	var sinppal: float = clampf(Game.stat(&"stat_sinppal", 1.0), 0.0, Data.num("combat_core", "damage.sinppal_cap", 10.0))
	var flat: float = 0.0
	var dmg: float = (level_dmg + flat) * sinppal * special_mult
	var crit: bool = false
	if not white and extra_crit >= 0.0:
		var p: float = Game.stat(&"stat_gyeoldan", Data.num("weapons", "globals.crit.base", 0.05)) + extra_crit
		p = minf(p, Data.num("weapons", "globals.crit.cap", 0.5))
		if Rng.chance(&"combat", p):
			crit = true
			dmg *= Data.num("weapons", "globals.crit.mult_vs_normal", Data.num("combat_core", "damage.crit_mult", 2.0))
	return Vector2(maxf(1.0, roundf(dmg)), 1.0 if crit else 0.0)
