class_name FlatBar
extends Control
## 픽셀 게이지(ProgressBar 대신: 테마 폰트 높이에 끌려 최소 크기가 커지는 문제 없음). 소유: ui.

@export var value: float = 0.0:
	set(v):
		if v != value:
			value = v
			queue_redraw()
@export var max_value: float = 1.0
@export var fill: Color = Color.WHITE
@export var back: Color = Color(0.13, 0.11, 0.18, 0.85)
@export var outline: Color = Color(0, 0, 0, 0)


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, back)
	var k: float = clampf(value / maxf(max_value, 0.0001), 0.0, 1.0)
	if k > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(roundf(size.x * k), size.y)), fill)
	if outline.a > 0.0:
		draw_rect(r, outline, false, 1.0)
