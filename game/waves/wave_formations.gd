extends RefCounted
## 웨이브 이벤트 진형 기하(순수 정적 함수). 소유: waves. 좌표 단위 px, 방향은 단위 벡터.
## 이벤트 시점에만 호출된다(틱마다 호출 금지 — 결과 배열을 새로 만든다).
## 각도 규약: 데이터의 direction_deg 는 수학 좌표(y 위, 0=동, 90=북). 화면 벡터 = (cos, -sin).


## 데이터 각도(y 위 규약) → 화면 단위 벡터.
static func dir_from_deg(deg: float) -> Vector2:
	var r: float = deg_to_rad(deg)
	return Vector2(cos(r), -sin(r))


## "north"/"south"/"east"/"west" → 그쪽을 가리키는 화면 단위 벡터.
static func dir_from_name(n: String) -> Vector2:
	match n:
		"north":
			return Vector2.UP
		"south":
			return Vector2.DOWN
		"east":
			return Vector2.RIGHT
		"west":
			return Vector2.LEFT
	return Vector2.ZERO


## 떼(band): travel 방향으로 진행하는 폭 width 의 지터 격자. center = 떼 중심.
## 가로(진행 직교)로 rows 줄, 진행 반대 방향으로 cols 열(선두가 travel 쪽).
static func band(center: Vector2, travel: Vector2, width_px: float, count: int, spacing_px: float,
		jitter_px: float, stream: StringName) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if count <= 0:
		return out
	var perp: Vector2 = Vector2(-travel.y, travel.x)
	var rows: int = maxi(1, int(floor(width_px / maxf(1.0, spacing_px))) + 1)
	rows = mini(rows, count)
	var cols: int = int(ceil(float(count) / float(rows)))
	out.resize(count)
	for k in count:
		var r: int = k % rows
		var c: int = k / rows
		var across: float = (float(r) - float(rows - 1) * 0.5) * spacing_px
		var along: float = -(float(c) - float(cols - 1) * 0.5) * spacing_px
		# 홀수 열은 반 칸 어긋나게(벽돌 쌓기) — 줄이 아니라 '떼'로 읽히게
		if c % 2 == 1:
			across += spacing_px * 0.5
		var j: Vector2 = Vector2(Rng.range_s(stream, -jitter_px, jitter_px), Rng.range_s(stream, -jitter_px, jitter_px))
		out[k] = center + perp * across + travel * along + j
	return out


## 틈 있는 원(에워싸기). gap_angles(라디안) 마다 반폭 gap_half_rad 의 빈 호를 두고,
## 남은 호 길이에 count 마리를 등간격 배치한다.
static func ring_with_gaps(center: Vector2, radius_px: float, count: int, gap_angles: PackedFloat32Array,
		gap_half_rad: float, jitter_px: float, stream: StringName) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if count <= 0:
		return out
	var g: int = gap_angles.size()
	if g == 0:
		out.resize(count)
		for k in count:
			var a0: float = TAU * (float(k) + 0.5) / float(count)
			out[k] = center + Vector2.from_angle(a0) * (radius_px + Rng.range_s(stream, -jitter_px, jitter_px))
		return out
	var gaps: Array[float] = []
	for a: float in gap_angles:
		gaps.append(fposmod(a, TAU))
	gaps.sort()
	# 세그먼트: gap[i] 끝 → gap[i+1] 시작
	var seg_a: PackedFloat32Array = PackedFloat32Array()
	var seg_len: PackedFloat32Array = PackedFloat32Array()
	var free_total: float = 0.0
	for i in g:
		var s: float = gaps[i] + gap_half_rad
		var e: float = gaps[(i + 1) % g] - gap_half_rad
		if i == g - 1:
			e += TAU
		var ln: float = maxf(0.0, e - s)
		seg_a.append(s)
		seg_len.append(ln)
		free_total += ln
	if free_total <= 0.0:
		return ring_with_gaps(center, radius_px, count, PackedFloat32Array(), 0.0, jitter_px, stream)
	var step: float = free_total / float(count)
	out.resize(count)
	for k in count:
		var s_pos: float = (float(k) + 0.5) * step
		var seg: int = 0
		while seg < g - 1 and s_pos > seg_len[seg]:
			s_pos -= seg_len[seg]
			seg += 1
		var ang: float = seg_a[seg] + minf(s_pos, seg_len[seg])
		out[k] = center + Vector2.from_angle(ang) * (radius_px + Rng.range_s(stream, -jitter_px, jitter_px))
	return out


## 호(arc): 플레이어 앞 fwd 방향 중심, 전체 각 arc_rad, 반경 dist.
static func arc(center: Vector2, fwd_angle: float, arc_rad: float, dist_px: float, count: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(maxi(0, count))
	for k in count:
		var f: float = (float(k) / maxf(1.0, float(count - 1))) - 0.5 if count > 1 else 0.0
		out[k] = center + Vector2.from_angle(fwd_angle + f * arc_rad) * dist_px
	return out


## 육각(중심 1 + 꼭짓점 6). 뒷전 공물상(08 3.4).
static func hex7(center: Vector2, spacing_px: float, rot: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.append(center)
	for k in 6:
		out.append(center + Vector2.from_angle(rot + TAU * float(k) / 6.0) * spacing_px)
	return out
