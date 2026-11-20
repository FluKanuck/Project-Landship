// Tactical / survey map. Terrain detail is only as good as our knowledge of it: where no
// sensor has looked, the map shows the coarse pre-war survey, dimmed and hatched.
shader_type canvas_item;

uniform sampler2D height_tex : filter_linear;
uniform sampler2D coarse_tex : filter_linear;
uniform sampler2D know_tex : filter_linear;
uniform sampler2D feat_tex : filter_nearest;
uniform vec2 centre = vec2(0.0);
uniform float span = 6000.0;
uniform float aspect = 1.5;
uniform vec4 ink : source_color = vec4(1.0, 0.69, 0.0, 1.0);
uniform float alert = 0.0;

float hgt(vec2 m, float k) {
	return mix(texture(coarse_tex, m).r, texture(height_tex, m).r, k);
}

void fragment() {
	vec2 w = centre + (UV - 0.5) * vec2(span * aspect, span);
	vec2 m = (w + 5000.0) / 10000.0;
	vec3 col = vec3(0.025, 0.02, 0.015);
	vec3 amb = mix(ink.rgb, vec3(1.0, 0.3, 0.2), alert * 0.5);
	if (m.x < 0.0 || m.y < 0.0 || m.x > 1.0 || m.y > 1.0) {
		float hatch = step(0.85, fract((w.x + w.y) / 160.0));
		COLOR = vec4(col + amb * hatch * 0.05, 1.0);
	} else {
		float k = smoothstep(0.05, 0.6, texture(know_tex, m).r);
		float h = hgt(m, k);
		float e = 1.0 / 256.0;
		float gx = hgt(m + vec2(e, 0.0), k) - hgt(m - vec2(e, 0.0), k);
		float gz = hgt(m + vec2(0.0, e), k) - hgt(m - vec2(0.0, e), k);
		vec3 n = normalize(vec3(-gx, 2.0 * 10000.0 / 256.0 * 0.5, -gz));
		float shade = clamp(dot(n, normalize(vec3(-0.6, 0.7, -0.4))), 0.0, 1.0);
		// contours every 10 m, bold every 50 m
		float cl = h / 10.0;
		float c1 = 1.0 - smoothstep(0.0, 1.2, abs(fract(cl - 0.5) - 0.5) / max(fwidth(cl), 1e-4));
		float cb = h / 50.0;
		float c2 = 1.0 - smoothstep(0.0, 1.4, abs(fract(cb - 0.5) - 0.5) / max(fwidth(cb), 1e-4));
		vec3 f = texture(feat_tex, m).rgb;
		float lit = mix(0.05, 0.3, shade);
		col = amb * lit * mix(0.45, 1.0, k);
		col += amb * (c1 * 0.12 + c2 * 0.3) * mix(0.25, 1.0, k);
		// hard ground: cross hatch, water: cool fill, minerals: stipple (known areas only)
		float hatch = step(0.82, fract((w.x - w.y) / 70.0)) * step(0.5, f.r);
		col += amb * hatch * 0.18 * k;
		col = mix(col, vec3(0.15, 0.45, 0.5) * 0.6, f.g * k);
		float stip = step(0.8, fract(sin(dot(floor(w / 40.0), vec2(12.9, 78.2))) * 43758.5)) * f.b;
		col += amb * stip * 0.25 * k;
		// unknown ground: hatched and dim
		float uh = step(0.9, fract((w.x + w.y) / 120.0));
		col = mix(col * 0.55 + amb * uh * 0.06, col, k);
		// 1 km grid
		vec2 g = abs(fract(w / 1000.0 - 0.5) - 0.5) / max(fwidth(w / 1000.0), vec2(1e-4));
		float grid = 1.0 - smoothstep(0.0, 1.0, min(g.x, g.y));
		col += amb * grid * 0.1;
		COLOR = vec4(col, 1.0);
	}
}
