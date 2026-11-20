// Alien hulls: palette colour, low roughness, a cold verdigris sheen at grazing angles.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/noise.gdshaderinc"

uniform sampler2D palette : source_color, filter_nearest;
uniform vec4 sheen : source_color = vec4(0.5, 0.95, 0.85, 1.0);
uniform float sheen_strength = 0.35;
uniform float dust_amount = 0.12;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = texture(palette, UV).rgb;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float band = 0.5 + 0.5 * sin(wpos.y * 9.0 + wpos.x * 0.7);
	float d = smoothstep(0.6, 1.0, clamp(wnrm.y, 0.0, 1.0) + lw_noise3(wpos * 2.0) * 0.3) * dust_amount;
	ALBEDO = mix(base, vec3(0.8, 0.66, 0.48), d);
	ROUGHNESS = 0.38 + d * 0.5;
	METALLIC = 0.35;
	EMISSION = sheen.rgb * fres * sheen_strength * (0.6 + 0.4 * band);
}
