// Shared hull material: one palette texture + a world-space dust layer (Art Profile: no
// modelled wear; dust and sand come from this shader so every asset gets the same effect).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/noise.gdshaderinc"

uniform sampler2D palette : source_color, filter_nearest;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.4;
uniform vec4 dust_color : source_color = vec4(0.82, 0.68, 0.48, 1.0);
uniform float roughness_base = 0.78;
uniform float metallic_base = 0.12;
uniform float grime = 0.25;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = texture(palette, UV).rgb;
	float n = lw_noise3(wpos * 1.3) * 0.55 + lw_noise3(wpos * 0.21) * 0.45;
	float up = clamp(wnrm.y, 0.0, 1.0);
	float d = smoothstep(0.45, 1.0, up * 0.85 + n * 0.4) * dust_amount;
	// streaks running down vertical faces
	float side = 1.0 - abs(wnrm.y);
	float streak = smoothstep(0.55, 0.9, lw_noise3(vec3(wpos.x * 2.0, wpos.y * 0.15, wpos.z * 2.0))) * side * grime;
	vec3 c = mix(base, dust_color.rgb * mix(0.85, 1.05, n), d);
	c = mix(c, c * 0.72, streak);
	ALBEDO = c;
	ROUGHNESS = mix(roughness_base, 0.95, d);
	METALLIC = metallic_base * (1.0 - d);
}
