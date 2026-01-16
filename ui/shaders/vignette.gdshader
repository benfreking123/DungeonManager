shader_type canvas_item;

uniform float strength : hint_range(0.0, 0.2, 0.001) = 0.03;
uniform float feather : hint_range(0.01, 0.5, 0.001) = 0.18;
uniform vec4 ink_color : source_color = vec4(0.18, 0.13, 0.08, 1.0);

void fragment() {
	// Distance to nearest edge in UV space (0..0.5).
	float d = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float edge = 1.0 - smoothstep(0.0, feather, d);
	float a = edge * strength;
	COLOR = vec4(ink_color.rgb, a);
}

