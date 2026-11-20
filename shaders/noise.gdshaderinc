// Small value-noise helpers shared by several shaders.
float lw_hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float lw_noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(lw_hash3(i + vec3(0, 0, 0)), lw_hash3(i + vec3(1, 0, 0)), f.x),
				   mix(lw_hash3(i + vec3(0, 1, 0)), lw_hash3(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(lw_hash3(i + vec3(0, 0, 1)), lw_hash3(i + vec3(1, 0, 1)), f.x),
				   mix(lw_hash3(i + vec3(0, 1, 1)), lw_hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float lw_hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float lw_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lw_hash2(i), lw_hash2(i + vec2(1.0, 0.0)), f.x),
			   mix(lw_hash2(i + vec2(0.0, 1.0)), lw_hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}
