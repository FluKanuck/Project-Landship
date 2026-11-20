// Thermal view of the ground, seen only by the drone feed's heat camera (LAYER_HEAT).
// Output is a heat value in grey (0 cold .. 1 white hot), not a colour: slopes facing the
// sun soak up heat, shaded and lee slopes run cooler, and distance evens it all out.
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 to_sun = vec3(0.4, 0.6, 0.3); // world direction towards the sun

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(wpos), dFdy(wpos)));
	n *= sign(n.y + 1e-4); // face up whatever the triangle winding
	float sun = max(dot(n, normalize(to_sun)), 0.0);
	// patchy ground: rock, compacted sand, loose drift hold heat differently
	float pat = lw_noise2(wpos.xz * 0.012) * 0.6 + lw_noise2(wpos.xz * 0.09) * 0.3 + lw_noise2(wpos.xz * 0.6) * 0.1;
	float h = 0.2 + 0.26 * sun + 0.08 * (pat - 0.5);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	h = mix(h, 0.3, smoothstep(1800.0, 9000.0, dist));
	ALBEDO = vec3(h);
}
