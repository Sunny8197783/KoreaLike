class_name PlayerHit
extends Node
## 플레이어 피격 파이프라인. 소유: combat.
## 순서(combat_core.player.hit_order): iframe → dodge(접촉만) → substitute(영가 대신 맞기) → hosinbu_shield → armor
## 현재 구현: iframe + substitute(영가) + armor(신복) + 사망. dodge·호신부는 TODO(combat).

var iframe_left: float = 0.0
var _iframe_hit: float = 0.4
var _iframe_sub: float = 0.2
var _blink_period: float = 0.067
var _t: float = 0.0


func _ready() -> void:
	_iframe_hit = Data.num("combat_core", "player.iframe_hit", 0.4)
	_blink_period = Data.num("combat_core", "player.blink_period", 0.067)
	_iframe_sub = Data.num("combat_core", "player.iframe_substitute", 0.2)


func sim_step(dt: float) -> void:
	_t += dt
	if iframe_left > 0.0:
		iframe_left -= dt


func take_hit(amount: float, source: StringName) -> void:
	if Game.debug_invuln or iframe_left > 0.0 or not Game.run_active:
		return
	# substitute: 영가 행렬 맨 앞 영가가 대신 맞고 천도(장판·hazard 제외는 YeonggaTrain 이 판정)
	var yg: YeonggaTrain = (Game.run_root.get("yeongga") as YeonggaTrain) if Game.run_root != null else null
	if yg != null and yg.try_substitute(source):
		iframe_left = maxf(iframe_left, _iframe_sub)
		return
	# TODO(combat): dodge(stat_jeopsin_hoepi) / 호신부 보호막
	var armor: float = Game.stat(&"stat_sinbok", 0.0)
	var dmg: float = maxf(amount * 0.2, amount - armor)
	Game.hp = maxf(0.0, Game.hp - dmg)
	iframe_left = _iframe_hit
	Events.player_damaged.emit(dmg, source, Game.hp, Game.hp_max)
	if Game.hp <= 0.0:
		Events.player_died.emit()


func heal(amount: float) -> void:
	Game.hp = minf(Game.hp_max, Game.hp + amount)
	Events.player_healed.emit(amount, Game.hp, Game.hp_max)


func blink_alpha() -> float:
	if iframe_left <= 0.0:
		return 1.0
	return 1.0 if fmod(_t, _blink_period * 2.0) < _blink_period else 0.45
