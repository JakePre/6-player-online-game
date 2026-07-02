// Through-wall silhouette (M2-04, SPEC $11): drawn with depth testing off so
// a player occluded by scenery still reads as a translucent color ghost.
// Chained as next_pass after the outline overlay. Godot 4.4 cannot restrict
// the pass to occluded fragments (render_mode depth_test_inverted lands in
// 4.5 — switch to it then), so the alpha is kept low enough that the pass is
// a faint tint when the character is visible but still obvious behind walls.
shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_never;

uniform vec4 silhouette_color : source_color = vec4(1.0, 1.0, 1.0, 0.12);


void fragment() {
	ALBEDO = silhouette_color.rgb;
	ALPHA = silhouette_color.a;
}
