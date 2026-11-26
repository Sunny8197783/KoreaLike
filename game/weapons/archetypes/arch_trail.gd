class_name ArchTrail
extends WeaponBase
## 원형 trail: 이동 경로 뒤에 설치물 살포(철질려 마름쇠). 소유: combat.
## params: formation(철질려진: 3회 발동마다 무당 둘레 formation_r 에 formation 개 진형), salgi(철질려진: 피해 ×(1+살기/100), 상한 ×2)
## 레벨 필드: dmg, amt(발사당 개수), dur(s), charges(타격 횟수), root(s: 봉박), max_act, hitbox(u)
## 연출: 뒤로 흩뿌림(착지까지 3틱 동안 손→지점 직선 이동) → 바닥 마름쇠 시트 2f, 타격 시 1f 번쩍, 소진 시 사라짐.

const MAX_ITEMS: int = 128
var ix: PackedFloat32Array = PackedFloat32Array()
var iy: PackedFloat32Array = PackedFloat32Array()
var ilife: PackedFloat32Array = PackedFloat32Array()
var icharges: PackedInt32Array = PackedInt32Array()
var itick: PackedInt32Array = PackedInt32Array()
var ihit: PackedInt32Array = PackedInt32Array()
var ifrom: PackedVector2Array = PackedVector2Array()
var _head: int = 0
var _q2: PackedInt32Array = PackedInt32Array()
var _form_tick: int = -100000


func _on_setup() -> void:
	ix.resize(MAX_ITEMS)
	iy.resize(MAX_ITEMS)
	ilife.resize(MAX_ITEMS)
	icharges.resize(MAX_ITEMS)
	itick.resize(MAX_ITEMS)
	ihit.resize(MAX_ITEMS)
	ihit.fill(-100000)
	ifrom.resize(MAX_ITEMS)
	ilife.fill(0.0)
	_q2.resize(32)


func _cap() -> int:
	return clampi(int(s("max_act", 40)), 1, MAX_ITEMS)


func _place(p: Vector2, from: Vector2) -> void:
	var z: int = _head % _cap()
	_head += 1
	ix[z] = p.x
	iy[z] = p.y
	ilife[z] = maxf(s("dur", 6.0), 0.5) * dur_mult()
	icharges[z] = maxi(1, int(s("charges", 3)))
	itick[z] = Game.game_tick
	ifrom[z] = from


func fire() -> void:
	var n: int = clampi(int(s("amt", 2)) + sinjang(), 1, int(s("amt", 2)) + int(limit("amt_cap", 12)))
	var o: Vector2 = player_pos()
	var back: Vector2 = -move_dir()
	for k in n:
		var a: float = Rng.range_s(&"combat", 0.0, TAU)
		var r: float = sqrt(Rng.randf_s(&"combat")) * 1.2 * K.UNIT_PX
		_place(o + back * 1.2 * K.UNIT_PX + Vector2.from_angle(a) * r, o)
	if bool(params.get("formation", false)) and fires_total % 3 == 0:
		var nf: int = maxi(1, int(s("formation", 12)))
		for k2 in nf:
			_place(o + Vector2.from_angle(TAU * float(k2) / float(nf)) * s("formation_r", 3.0) * K.UNIT_PX, o)
		_form_tick = Game.game_tick
		play_fx(fx_name("fx_ring"), o)


func _dmg() -> float:
	var d: float = s("dmg", 4.0)
	if bool(params.get("salgi", false)):
		d *= minf(1.0 + Game.salgi / maxf(1.0, s("salgi_cap", 100.0)), 2.0)
	return d


func tick(dt: float) -> void:
	var em: EnemyManager = enemies()
	var hr: float = maxf(s("hitbox", 0.3), 0.2) * K.UNIT_PX * sqrt(area_mult())
	var root: float = s("root", 0.0)
	for z in MAX_ITEMS:
		if ilife[z] <= 0.0:
			continue
		ilife[z] -= dt
		if em == null or Game.game_tick - itick[z] < 3:
			continue
		var n: int = em.query_circle(Vector2(ix[z], iy[z]), hr, _q2)
		for k in n:
			var i: int = _q2[k]
			if (em.flags[i] & EnemyManager.F_DYING) != 0 or (em.flags[i] & EnemyManager.F_FLYING) != 0:
				continue
			if icharges[z] > 0 and can_hit(i, 0.5):
				deal(i, _dmg(), Vector2.ZERO, 0.0)
				if root > 0.0:
					apply_status(i, &"st_bongbak", root * dur_mult())
				icharges[z] -= 1
				ihit[z] = Game.game_tick
				if icharges[z] <= 0:
					ilife[z] = 0.0
					break


func draw_ground(ci: CanvasItem) -> void:
	var now: int = Game.anim_tick()
	var at: float = Game.anim_time()
	var fx: StringName = fx_name("fx_prop")
	for z in MAX_ITEMS:
		if ilife[z] <= 0.0:
			continue
		if ilife[z] < 0.5 and (now / 3) % 2 == 0:
			continue
		var p: Vector2 = Vector2(ix[z], iy[z])
		var age: int = now - itick[z]
		if age < 3:
			p = ifrom[z].lerp(p, float(maxi(age, 0)) / 3.0) + Vector2(0, -6.0 * float(3 - maxi(age, 0)) / 3.0)
		if now - ihit[z] < 2:
			ci.draw_rect(Rect2(K.rndv(p) - Vector2(2, 2), Vector2(5, 5)), K.COL_HANJI)
			continue
		if not draw_sheet(ci, fx, p, at + float(z) * 0.31, 0, Color.WHITE, true):
			var q: Vector2 = K.rndv(p)
			ci.draw_line(q + Vector2(-2, -2), q + Vector2(2, 2), K.COL_JEOK_HI, 1.0)
			ci.draw_line(q + Vector2(-2, 2), q + Vector2(2, -2), K.COL_JEOK_HI, 1.0)


func draw(ci: CanvasItem) -> void:
	var ft: float = float(Game.anim_tick() - _form_tick) / K.TICK_HZ
	if ft >= 0.0 and ft < 0.3:
		draw_ring(ci, render_origin(), s("formation_r", 3.0) * K.UNIT_PX, col_hi())
