// Holo table terrain. The relief is only as sharp as our sensor knowledge: unknown ground is
// the coarse survey, drawn as a faint dot grid; known ground gets contours and a lit surface.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D height_tex : filter_linear;
uniform sampler2D coarse_tex : filter_linear;
uniform sampler2D know_tex : filter_linear;
uniform sampler2D feat_tex : filter_nearest;
uniform vec2 centre = vec2(0.0);
uniform float span = 10000.0;     // metres across the table disc
uniform float plate = 3.0;        // mesh size in metres
uniform float hscale = 0.0009;    // metres of table per metre of terrain height
uniform float hbase = -10.0;
uniform vec4 ink : source_color = vec4(1.0, 0.62, 0.12, 1.0);
uniform float alert = 0.0;
uniform float boot = 1.0;

varying vec2 wpos;
varying float know;
varying float hgt;
varying float inside;

void vertex() {
	vec2 local = VERTEX.xz / plate;           // -0.5 .. 0.5
	wpos = centre + local * span;
	vec2 m = (wpos + 5000.0) / 10000.0;
	inside = step(0.0, m.x) * step(0.0, m.y) * step(m.x, 1.0) * step(m.y, 1.0);
	know = smoothstep(0.05, 0.6, texture(know_tex, m).r);
	hgt = mix(texture(coarse_tex, m).r, texture(height_tex, m).r, know);
	VERTEX.y += max(hgt - hbase, 0.0) * hscale * inside;
}

void fragment() {
	vec2 local = (wpos - centre) / span;
	float r = length(local) * 2.0;
	if (r > 1.0 || inside < 0.5) {
		discard;
	}
	float edge = smoothstep(1.0, 0.86, r);
	vec3 a = mix(ink.rgb, vec3(1.0, 0.25, 0.15), alert * 0.6);
	float cl = hgt / 10.0;
	float c1 = 1.0 - smoothstep(0.0, 1.5, abs(fract(cl - 0.5) - 0.5) / max(fwidth(cl), 1e-4));
	float cb = hgt / 50.0;
	float c2 = 1.0 - smoothstep(0.0, 1.5, abs(fract(cb - 0.5) - 0.5) / max(fwidth(cb), 1e-4));
	vec2 g = abs(fract(wpos / 1000.0 - 0.5) - 0.5) / max(fwidth(wpos / 1000.0), vec2(1e-4));
	float grid = 1.0 - smoothstep(0.0, 1.0, min(g.x, g.y));
	vec2 dg = abs(fract(wpos / 200.0 - 0.5) - 0.5) / max(fwidth(wpos / 200.0), vec2(1e-4));
	float dots = (1.0 - smoothstep(0.0, 1.6, max(dg.x, dg.y)));
	vec3 f = texture(feat_tex, (wpos + 5000.0) / 10000.0).rgb;
	float scan = 0.8 + 0.2 * sin(wpos.y * 0.02 - TIME * 3.0);
	float sweep = smoothstep(0.03, 0.0, abs(fract(TIME * 0.08) - fract(r * 0.5 + 0.5)));
	vec3 col = vec3(0.0);
	col += a * (0.05 + c1 * 0.35 + c2 * 0.8) * know;
	col += a * grid * 0.25;
	col += a * dots * 0.35 * (1.0 - know);
	col += a * 0.08 * know * (0.6 + 0.4 * sin(hgt * 0.4));
	col += vec3(0.2, 0.6, 0.7) * f.g * know * 0.5;
	col += a * f.r * know * 0.12 * step(0.75, fract((wpos.x - wpos.y) / 90.0));
	col *= scan;
	col += a * sweep * 0.15;
	col *= edge * boot;
	ALBEDO = col * 1.2;
}
