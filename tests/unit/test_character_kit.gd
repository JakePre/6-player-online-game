extends GutTest

const RIG_SCENE := preload("res://src/characters/character_rig.tscn")
const KNIGHT := "res://assets/characters/kaykit_adventurers/Knight.glb"


func _make_rig() -> CharacterRig:
	var rig: CharacterRig = RIG_SCENE.instantiate()
	add_child_autofree(rig)
	rig.character_scene = load(KNIGHT)
	return rig


func test_palette_has_six_distinct_colors() -> void:
	assert_eq(PlayerPalette.COLORS.size(), NetConfig.MAX_PLAYERS_PER_ROOM)
	var seen := {}
	for color in PlayerPalette.COLORS:
		seen[color.to_html()] = true
	assert_eq(seen.size(), PlayerPalette.COLORS.size(), "no duplicate colors")


func test_palette_wraps_out_of_range_slots() -> void:
	assert_eq(PlayerPalette.color_for_slot(0), PlayerPalette.COLORS[0])
	assert_eq(PlayerPalette.color_for_slot(6), PlayerPalette.COLORS[0])
	assert_eq(PlayerPalette.color_for_slot(-1), PlayerPalette.COLORS[5])


func test_rig_starts_idle() -> void:
	var rig := _make_rig()
	assert_eq(rig.current_action(), &"idle")


func test_action_proxy_maps_and_loops() -> void:
	var rig := _make_rig()
	assert_true(rig.play(&"run"))
	assert_eq(rig._anim_player.current_animation, "Running_A")
	var run := rig._anim_player.get_animation(&"Running_A") as Animation
	assert_eq(run.loop_mode, Animation.LOOP_LINEAR, "run loops")
	assert_true(rig.play(&"ko"))
	var ko := rig._anim_player.get_animation(&"Death_A") as Animation
	assert_eq(ko.loop_mode, Animation.LOOP_NONE, "ko plays once")


func test_unknown_action_is_rejected() -> void:
	var rig := _make_rig()
	assert_false(rig.play(&"moonwalk"))


func test_player_color_reaches_outline_and_silhouette() -> void:
	var rig := _make_rig()
	rig.player_color = PlayerPalette.color_for_slot(1)
	var meshes := rig.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "character meshes present")
	var overlay := (meshes[0] as MeshInstance3D).material_overlay as ShaderMaterial
	assert_not_null(overlay)
	assert_eq(overlay.get_shader_parameter("outline_color"), PlayerPalette.color_for_slot(1))
	var xray := overlay.next_pass as ShaderMaterial
	assert_not_null(xray, "through-wall pass chained")
	var ghost: Color = xray.get_shader_parameter("silhouette_color")
	assert_almost_eq(ghost.a, 0.12, 0.001, "silhouette is translucent")


func test_props_hidden_by_default() -> void:
	var rig := _make_rig()
	var attachments := rig.find_children("*", "BoneAttachment3D", true, false)
	assert_gt(attachments.size(), 0, "knight ships props")
	for attachment: BoneAttachment3D in attachments:
		assert_false(attachment.visible, "%s hidden" % attachment.name)
	rig.show_props = true
	for attachment: BoneAttachment3D in attachments:
		assert_true(attachment.visible, "%s shown when enabled" % attachment.name)


func test_nameplate_reflects_identity() -> void:
	var rig := _make_rig()
	rig.display_name = "P2"
	rig.player_color = PlayerPalette.color_for_slot(1)
	var nameplate: Label3D = rig.get_node("Nameplate")
	assert_eq(nameplate.text, "P2")
	assert_eq(nameplate.modulate, PlayerPalette.color_for_slot(1))
	assert_true(nameplate.no_depth_test, "nameplate reads through occluders")
