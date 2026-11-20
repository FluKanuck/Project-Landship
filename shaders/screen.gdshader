// Generic console display: procedural readouts in phosphor amber. Each screen gets a seed.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float seed = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.69, 0.0, 1.0);
uniform float brightness = 1.4;
uniform float alert = 0.0;

float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed * 17.13) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.6 + seed * 3.1;
	vec3 col = vec3(0.0);
	// header bar
	if (uv.y > 0.86) {
		col = tint.rgb * (0.35 + 0.1 * step(0.5, fract(uv.x * 3.0 + seed)));
	} else {
		// rows of text-like blocks that scroll slowly
		float rows = 14.0;
		float ry = floor((uv.y + t * 0.02) * rows);
		float cx = floor(uv.x * 34.0);
		float on = step(0.42, h(vec2(cx, ry))) * step(fract(uv.y * rows + t * 0.02 * rows), 0.6);
		float rowlen = h(vec2(ry, 7.0));
		on *= step(uv.x, 0.15 + rowlen * 0.75);
		col = tint.rgb * on * 0.75;
		// a trace graph on the right third
		if (uv.x > 0.68) {
			float g = 0.35 + 0.18 * sin(uv.x * 40.0 + t * 2.0 + seed) + 0.08 * sin(uv.x * 113.0 - t * 5.0);
			col = tint.rgb * 0.12 + tint.rgb * smoothstep(0.012, 0.0, abs(uv.y - g));
		}
	}
	float scan = 0.85 + 0.15 * sin(uv.y * 240.0);
	float flick = 0.96 + 0.04 * sin(TIME * 53.0 + seed);
	vec3 bg = tint.rgb * 0.05;
	col = mix(col, vec3(1.0, 0.2, 0.12) * length(col), alert);
	ALBEDO = (bg + col) * scan * flick * brightness;
}
