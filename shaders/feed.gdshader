// Drone camera feed: low-fi video link. Grain, scanlines, a little vignette, and static that
// grows as the data link weakens.
// Thermal: the heat picture comes from a second camera that sees only the heat stand-ins
// (LAYER_HEAT: hot units, sun-warmed ground, empty cold sky). The colour picture only adds
// a little surface texture. 1 = white hot, 2 = ironbow.
shader_type canvas_item;

uniform sampler2D feed : filter_linear;
uniform sampler2D heat : filter_linear;
uniform float link = 1.0;       // 1 good .. 0 lost
uniform int thermal = 0;
uniform float hit = 0.0;        // flash when the drone is hit
uniform float time_offset = 0.0;

float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec3 ironbow(float t) {
	// black > indigo > magenta > orange > yellow > white
	vec3 c = mix(vec3(0.0, 0.0, 0.02), vec3(0.18, 0.02, 0.42), smoothstep(0.0, 0.25, t));
	c = mix(c, vec3(0.72, 0.08, 0.45), smoothstep(0.2, 0.45, t));
	c = mix(c, vec3(0.98, 0.45, 0.05), smoothstep(0.42, 0.68, t));
	c = mix(c, vec3(1.0, 0.86, 0.25), smoothstep(0.65, 0.86, t));
	return mix(c, vec3(1.0, 1.0, 0.92), smoothstep(0.84, 1.0, t));
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + time_offset;
	// line tearing when the link is poor
	float tear = (1.0 - link) * step(0.97 - (1.0 - link) * 0.2, rnd(vec2(floor(uv.y * 90.0), floor(t * 12.0))));
	uv.x += tear * (rnd(vec2(t, uv.y)) - 0.5) * 0.08;
	vec3 c = texture(feed, uv).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	if (thermal > 0) {
		vec2 px = 1.0 / vec2(textureSize(heat, 0));
		vec4 h = texture(heat, uv);
		// sky (nothing drawn) is cold; ground and units carry their heat value
		float temp = mix(0.04, h.r, h.a);
		// surface texture from the visible picture, only on solid things
		float lb = dot(texture(feed, uv + px * vec2(1.0, 1.0)).rgb, vec3(0.3, 0.59, 0.11));
		temp += (l * 0.5 + lb * 0.5 - 0.45) * 0.1 * h.a;
		// hot things bloom a little: thermal optics smear the brightest returns
		float glow = 0.0;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			glow = max(glow, texture(heat, uv + vec2(cos(a), sin(a)) * px * 3.0).r);
		}
		temp += smoothstep(0.75, 1.0, glow) * 0.12;
		// fixed-pattern sensor noise: faint column stripes
		temp += (rnd(vec2(floor(uv.x * 640.0), 3.0)) - 0.5) * 0.02;
		temp = clamp(temp, 0.0, 1.0);
		if (thermal == 1) {
			float w = smoothstep(0.12, 0.98, temp);
			c = vec3(w) * vec3(0.94, 1.0, 0.96);
		} else {
			c = ironbow(temp);
		}
	} else {
		vec3 mono = vec3(l) * vec3(1.0, 0.97, 0.9);
		c = mix(c, mono, 0.35);
	}
	float g = rnd(uv * 512.0 + t) - 0.5;
	c += g * ((thermal > 0 ? 0.035 : 0.06) + (1.0 - link) * 0.6);
	c *= 0.88 + 0.12 * sin(uv.y * 700.0);
	vec2 v = uv - 0.5;
	c *= 1.0 - dot(v, v) * 0.9;
	float snow = rnd(floor(uv * vec2(320.0, 180.0)) + floor(t * 30.0));
	c = mix(c, vec3(snow * 0.7), smoothstep(0.35, 0.0, link));
	c += vec3(1.0, 0.3, 0.2) * hit * 0.6;
	COLOR = vec4(c, 1.0);
}
