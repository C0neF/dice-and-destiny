## Global visual effects manager - CRT shader, screen shake, transitions
extends CanvasLayer

var color_rect: ColorRect
var transition_rect: ColorRect

var shake_amount: float = 0.0
var shake_decay: float = 5.0
var original_offset: Vector2 = Vector2.ZERO

func _ready():
	layer = 100
	_setup_crt()
	_setup_transition()

func _process(delta):
	if shake_amount > 0:
		shake_amount = max(0, shake_amount - shake_decay * delta)
		var ofs = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amount
		get_viewport().canvas_transform.origin = original_offset + ofs
	else:
		get_viewport().canvas_transform.origin = original_offset

func screen_shake(intensity: float = 4.0, decay: float = 5.0):
	shake_amount = intensity
	shake_decay = decay

## CRT scanline + vignette effect
func _setup_crt():
	color_rect = ColorRect.new()
	color_rect.name = "CRTFilter"
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.06;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.25;
uniform float curvature : hint_range(0.0, 0.1) = 0.015;
uniform float brightness : hint_range(0.8, 1.2) = 1.05;
uniform float contrast : hint_range(0.8, 1.5) = 1.08;
uniform float saturation : hint_range(0.5, 1.5) = 1.12;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;
	float dist = dot(centered, centered);
	uv = uv + centered * dist * curvature;
	
	vec4 color = texture(screen_tex, uv);
	
	// Scanlines
	float scanline = sin(uv.y * 540.0 * 3.14159) * 0.5 + 0.5;
	color.rgb -= scanline_strength * scanline;
	
	// Brightness & Contrast
	color.rgb = (color.rgb - 0.5) * contrast + 0.5;
	color.rgb *= brightness;
	
	// Saturation boost
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(vec3(gray), color.rgb, saturation);
	
	// Vignette
	float vig = 1.0 - dot(centered * 1.5, centered * 1.5);
	vig = clamp(pow(vig, 1.2), 0.0, 1.0);
	color.rgb *= mix(1.0, vig, vignette_strength);
	
	// Subtle color fringing
	float fringe = dist * 0.002;
	color.r = texture(screen_tex, uv + vec2(fringe, 0.0)).r;
	color.b = texture(screen_tex, uv - vec2(fringe, 0.0)).b;
	
	COLOR = color;
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	color_rect.material = mat
	add_child(color_rect)

## Screen transition (fade in/out)
func _setup_transition():
	transition_rect = ColorRect.new()
	transition_rect.name = "TransitionRect"
	transition_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	transition_rect.color = Color(0, 0, 0, 0)
	transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(transition_rect)

func fade_out(duration: float = 0.5) -> void:
	transition_rect.color = Color(0, 0, 0, transition_rect.color.a)  # Reset to black
	var tween = create_tween()
	tween.tween_property(transition_rect, "color:a", 1.0, duration)
	await tween.finished

func fade_in(duration: float = 0.5) -> void:
	transition_rect.color = Color(0, 0, 0, 1.0)  # Ensure black, not red
	var tween = create_tween()
	tween.tween_property(transition_rect, "color:a", 0.0, duration)
	await tween.finished

## Flash effect for hits
func flash_screen(color: Color = Color(1, 0.2, 0.2, 0.3), duration: float = 0.1):
	transition_rect.color = color
	var tween = create_tween()
	tween.tween_property(transition_rect, "color:a", 0.0, duration)
