// Faint light cone from the projector lenses to the projection.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.15, 1.0);
uniform float strength = 0.012;
void fragment() {
	float fres = abs(dot(NORMAL, VIEW));
	float along = UV.y;
	ALBEDO = tint.rgb * strength * fres * (0.4 + along) * (0.85 + 0.15 * sin(TIME * 3.0 + UV.y * 20.0));
}
