// A sandstorm front on the western horizon: a wall of billowing dust kilometres high.
// (Design doc: weather. In the wedge it is scenery; storms as world events come later.)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform vec4 dust_dark : source_color = vec4(0.36, 0.21, 0.13, 1.0);
uniform vec4 dust_lit : source_color = vec4(0.93, 0.68, 0.42, 1.0);
uniform vec4 haze : source_color = vec4(0.84, 0.69, 0.53, 1.0);
uniform float speed = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += lw_noise3(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	float h = UV.y;          // 0 at the top edge, 1 at the ground (PlaneMesh UV)
	float up = 1.0 - h;
	float t = TIME * 0.02 * speed;
	vec3 p = vec3(wpos.x * 0.00045, wpos.y * 0.0011 - t, wpos.z * 0.00045 + t * 0.4);
	float n = fbm(p * 2.0);
	float billow = fbm(p * 5.0 + vec3(0.0, -t * 2.0, 0.0));
	// top edge is a rolling, lumpy cauliflower line
	float top = 0.55 + n * 0.45;
	float a = smoothstep(top, top - 0.18, up);
	// thin out at the ends of the arc
	a *= smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	vec3 c = mix(dust_dark.rgb, dust_lit.rgb, clamp(billow * 1.3 - 0.15 + up * 0.35, 0.0, 1.0));
	// blend towards the horizon haze with distance, like aerial perspective
	c = mix(c, haze.rgb, 0.22 + up * 0.25);
	ALBEDO = c;
	ALPHA = clamp(a * (0.75 + 0.25 * billow), 0.0, 0.97);
}
