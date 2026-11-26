class_name ArchSummon
extends WeaponBase
## 원형 summon: 일시 소환체(신장·군졸 등)가 가까운 적을 쫓아 친다. v1 무구 20종에는 없음 — 진화·결합·권능용. 소유: combat.
## 레벨 필드: dmg, amt, dur(s), spd(u/s), hitbox(u), hit_iv(s)

const MAX_S: int = 12
var sx: PackedFloat32Array = PackedFloat32Array()
var sy: PackedFloat32Array = PackedFloat32Array()
var slife: PackedFloat32Array = PackedFloat32Array()


func _on_setup() -> void:
	sx.resize(MAX_S)
	sy.resize(MAX_S)
	slife.resize(MAX_S)
	slife.fill(0.0)


func fire() -> void:
	var n: int = mini(MAX_S, maxi(1, int(s("amt", 1))))
	var made: int = 0
	for z in MAX_S:
		if slife[z] <= 0.0 and made < n:
			var p: Vector2 = player_pos() + Vector2.from_angle(TAU * float(made) / float(n)) * 20.0
			sx[z] = p.x
			sy[z] = p.y
			slife[z] = maxf(s("dur", 5.0), 0.5)
			made += 1


func tick(dt: float) -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	var spd: float = s("spd", 5.0) * K.UNIT_PX
	var hr: float = maxf(s("hitbox", 0.4), 0.2) * K.UNIT_PX
	for z in MAX_S:
		if slife[z] <= 0.0:
			continue
		slife[z] -= dt
		var p: Vector2 = Vector2(sx[z], sy[z])
		var i: int = em.nearest(p, 8.0 * K.UNIT_PX)
		var target: Vector2 = em.pos_of(i) if i >= 0 else player_pos()
		p = p.move_toward(target, spd * dt)
		sx[z] = p.x
		sy[z] = p.y
		var n: int = em.query_circle(p, hr, _q)
		for k in n:
			if can_hit(_q[k], maxf(s("hit_iv", 0.4), 0.1)):
				deal(_q[k], s("dmg", 6.0))


func draw(ci: CanvasItem) -> void:
	for z in MAX_S:
		if slife[z] > 0.0:
			ci.draw_circle(Vector2(sx[z], sy[z]).round(), 4.0, Color(K.COL_HWANG, 0.8))
