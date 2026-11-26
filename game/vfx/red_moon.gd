class_name RedMoon
extends Sprite2D
## 보스 붉은 달 — 월드 층(z −8: 지면 위, 소품·행위자 아래), 화면 오른쪽 위 (548, 40)에 카메라 고정. 소유: vfx.
## VfxPlayer 가 자식으로 만들고 screen_fx 가 amount(0..1)를 넣는다. 그림은 shaders/red_moon.gdshader(디더 떠오름).
## 후처리에서 달을 그리면 그 자리의 적·적탄·예고가 사라졌다(리뷰 vfx#12) — 이제는 지면 위에만 비친다.

const SIZE: int = 96
const SCREEN_POS: Vector2 = Vector2(548.0, 40.0)

var amount: float = 0.0
var beat_pulse: float = 0.0
var _mat: ShaderMaterial
var _shown: float = -1.0


func _ready() -> void:
	z_as_relative = false
	z_index = -8
	centered = true
	var img: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(img)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/red_moon.gdshader") as Shader
	_mat.set_shader_parameter("tex_px", float(SIZE))
	material = _mat
	visible = false


func _process(_delta: float) -> void:
	var on: bool = amount > 0.01 and Game.run_active
	visible = on
	if not on:
		return
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	global_position = (inv * SCREEN_POS).round()
	var a: float = floorf(amount * 16.0) / 16.0
	if a != _shown:
		_shown = a
		_mat.set_shader_parameter("reveal", a)
	_mat.set_shader_parameter("beat_pulse", beat_pulse)
	# 달빛: 원반이 오컬트 어둠에 묻히지 않게 약한 난색 프레임 광원(screen_fx 가 화면 좌표로 바꾼다)
	Juice.light_frame(global_position, 1.4 * K.UNIT_PX, 0.55 * a, 0)
