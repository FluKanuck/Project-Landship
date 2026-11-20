// The command projection: the MFD viewport projected in the air in front of the chair.
// Opaque in the centre, see-through towards the edges so the crew and the room stay in
// peripheral vision (design doc: Command screens > Display).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D screen_tex : source_color, filter_linear_mipmap;
uniform float centre_alpha = 1.0;
uniform float edge_alpha = 0.12;
uniform float boot = 1.0;       // 0..1 power-up sweep
uniform float glow = 1.25;
uniform float alert = 0.0;

void fragment() {
	vec2 uv = UV;
	// slight chromatic split towards the edges, like light hitting dust
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec3 col;
	col.r = texture(screen_tex, uv + c * 0.004).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - c * 0.004).b;
	// elliptical vignette: opaque core, fading rim
	float e = length(c * vec2(2.0, 2.0));
	float edge = smoothstep(0.62, 1.02, max(abs(c.x) * 2.0, abs(c.y) * 2.0) * 0.55 + e * 0.5);
	float a = mix(centre_alpha, edge_alpha, edge);
	// projected light: brighter content reads more opaque than dark background
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	a = clamp(a + lum * 0.25 * edge, 0.0, 1.0);
	float scan = 0.9 + 0.1 * sin(uv.y * 900.0 + TIME * 6.0);
	float band = 0.97 + 0.03 * sin(uv.y * 14.0 - TIME * 1.7);
	float flick = 0.985 + 0.015 * sin(TIME * 61.0);
	// boot sweep: lines appear top to bottom
	float on = 1.0 - smoothstep(boot * 1.06 - 0.04, boot * 1.06, uv.y);
	col *= scan * band * flick * glow;
	col = mix(col, col * vec3(1.25, 0.55, 0.45), alert * 0.6);
	ALBEDO = col;
	ALPHA = a * on;
}
