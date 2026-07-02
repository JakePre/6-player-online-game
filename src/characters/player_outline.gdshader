// Player-color outline (M2-04, SPEC $8/$11): inverted-hull pass applied via
// material_overlay on every character mesh. cull_front + normal extrusion
// renders a colored shell just behind the character's own triangles.
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(1.0);
uniform float outline_width = 0.03;


void vertex() {
	VERTEX += NORMAL * outline_width;
}


void fragment() {
	ALBEDO = outline_color.rgb;
}
