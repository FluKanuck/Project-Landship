// Drone camera feed: low-fi video link. Grain, scanlines, a little vignette, and static that
// grows as the data link weakens. Thermal mode maps luminance to a heat palette.
shader_type canvas_item;

uniform sampler2D feed : filter_linear;
uniform float link = 1.0;       // 1 good .. 0 lost
uniform float thermal = 0.0;
uniform float hit = 0.0;        // flash when the drone is hit
uniform float time_offset = 0.0;

float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME + time_offset;
	// line tearing when the link is poor
	float tear = (1.0 - link) * step(0.97 - (1.0 - link) * 0.2, rnd(vec2(floor(uv.y * 90.0), floor(t * 12.0))));
	uv.x += tear * (rnd(vec2(t, uv.y)) - 0.5) * 0.08;
	vec3 c = texture(feed, uv).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 mono = vec3(l) * vec3(1.0, 0.97, 0.9);
	vec3 th = mix(vec3(0.05, 0.02, 0.1), vec3(0.9, 0.2, 0.15), smoothstep(0.1, 0.5, l));
	th = mix(th, vec3(1.0, 0.95, 0.6), smoothstep(0.5, 0.9, l));
	c = mix(mix(c, mono, 0.35), th, thermal);
	float g = rnd(uv * 512.0 + t) - 0.5;
	c += g * (0.06 + (1.0 - link) * 0.6);
	c *= 0.88 + 0.12 * sin(uv.y * 700.0);
	vec2 v = uv - 0.5;
	c *= 1.0 - dot(v, v) * 0.9;
	float snow = rnd(floor(uv * vec2(320.0, 180.0)) + floor(t * 30.0));
	c = mix(c, vec3(snow * 0.7), smoothstep(0.35, 0.0, link));
	c += vec3(1.0, 0.3, 0.2) * hit * 0.6;
	COLOR = vec4(c, 1.0);
}
