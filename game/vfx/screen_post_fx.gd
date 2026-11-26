class_name ScreenPostFx
extends CanvasLayer
## 화면 후처리 2종 런타임 (L17): vfx_screen_flash(길닦음 순백 2프레임 add) · vfx_silence_desat(정적 0.8s).
## 셰이더 원본: res://assets/vfx/vfx_screen_flash.gdshader, res://assets/vfx/vfx_silence_desat.gdshader
## 사용 예:
##   var post := ScreenPostFx.new(); add_child(post)
##   post.flash()                      # 길닦음 순간. 초당 3회 상한, opt_flash_reduce 면 무시.
##   post.flash(ring_center_screen_px)  # 고리 중심 쪽이 조금 더 밝다.
##   post.silence(true)                # 어둑시니·보스 직전: 0.8s 동안 채도 −60% + 먹 비네트로 내려간다.
##   post.silence(false, 0.4)          # 풀기.
## 히트스톱 중에도 진행(PROCESS_MODE_ALWAYS). Juice.flash 를 대체하지 않고, 해원 연출용 '백' 플래시만 맡는다.

const FLASH_SHADER: Shader = preload("res://assets/vfx/vfx_screen_flash.gdshader")
const SILENCE_SHADER: Shader = preload("res://assets/vfx/vfx_silence_desat.gdshader")
const FLASH_FRAMES: Array[float] = [0.30, 0.15]   # 2프레임 @24fps, 알파 ≤ 30%
const FLASH_FPS: float = 24.0
const FLASH_MAX_PER_SEC: int = 3
const SILENCE_SEC: float = 0.8

var flash_enabled: bool = true        # 설정 opt_flash_reduce = true 면 false 로
var _flash_rect: ColorRect
var _flash_mat: ShaderMaterial
var _silence_rect: ColorRect
var _silence_mat: ShaderMaterial
var _flash_t: float = -1.0
var _flash_stamps: Array[int] = []
var _silence_tween: Tween


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silence_mat = ShaderMaterial.new()
	_silence_mat.shader = SILENCE_SHADER
	_silence_rect = _make_rect(_silence_mat)
	_silence_rect.visible = false
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = FLASH_SHADER
	_flash_rect = _make_rect(_flash_mat)
	_flash_rect.visible = false


func _make_rect(mat: ShaderMaterial) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.material = mat
	add_child(r)
	return r


## 순백 플래시 2프레임. center_px: 화면 픽셀 좌표(음수면 화면 중앙). 상한에 걸리면 false.
func flash(center_px: Vector2 = Vector2(-1, -1)) -> bool:
	if not flash_enabled:
		return false
	var now: int = Time.get_ticks_msec()
	while not _flash_stamps.is_empty() and now - _flash_stamps[0] >= 1000:
		_flash_stamps.pop_front()
	if _flash_stamps.size() >= FLASH_MAX_PER_SEC:
		return false
	_flash_stamps.push_back(now)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var c: Vector2 = Vector2(0.5, 0.5) if center_px.x < 0.0 else center_px / vp
	_flash_mat.set_shader_parameter("center_uv", c)
	_flash_t = 0.0
	_flash_rect.visible = true
	_flash_mat.set_shader_parameter("intensity", FLASH_FRAMES[0])
	return true


## 정적: on 이면 duration(기본 0.8s) 동안 strength 0→1, off 면 1→0.
func silence(on: bool = true, duration: float = SILENCE_SEC) -> void:
	if _silence_tween:
		_silence_tween.kill()
	var from: float = float(_silence_mat.get_shader_parameter("strength"))
	var to: float = 1.0 if on else 0.0
	_silence_rect.visible = true
	_silence_tween = create_tween()
	_silence_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_silence_tween.tween_method(_set_silence, from, to, maxf(duration, 0.01)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT if on else Tween.EASE_OUT)
	if not on:
		_silence_tween.tween_callback(func() -> void: _silence_rect.visible = false)


func _set_silence(v: float) -> void:
	_silence_mat.set_shader_parameter("strength", v)


func _process(delta: float) -> void:
	if _flash_t < 0.0:
		return
	_flash_t += delta
	var idx: int = int(_flash_t * FLASH_FPS)
	if idx >= FLASH_FRAMES.size():
		_flash_t = -1.0
		_flash_mat.set_shader_parameter("intensity", 0.0)
		_flash_rect.visible = false
	else:
		_flash_mat.set_shader_parameter("intensity", FLASH_FRAMES[idx])
