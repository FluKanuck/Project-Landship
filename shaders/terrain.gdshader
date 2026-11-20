// Dunes: vertex colours from the generator, flat facets from screen derivatives,
// wind ripples and a little sparkle. Works in Forward+ and Compatibility.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/noise.gdshaderinc"

uniform float ripple_strength = 0.035;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, -VERTEX) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	vec3 c = COLOR.rgb;
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(25.0, 220.0, dist);
	float rip = sin(wpos.x * 1.1 + wpos.z * 0.35 + lw_noise2(wpos.xz * 0.05) * 6.0);
	c *= 1.0 + rip * ripple_strength * fade;
	float blotch = lw_noise2(wpos.xz * 0.004) * 0.5 + lw_noise2(wpos.xz * 0.02) * 0.5;
	c *= mix(0.93, 1.05, blotch);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
