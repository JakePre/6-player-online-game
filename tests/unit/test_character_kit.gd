extends GutTest

const RIG_SCENE := preload("res://src/characters/character_rig.tscn")
const KNIGHT := "res://assets/characters/kaykit_adventurers/Knight.glb"


func _make_rig() -> CharacterRig:
	var rig: CharacterRig = RIG_SCENE.instantiate()
	add_child_autofree(rig)
	rig.character_scene = load(KNIGHT)
	return rig


## ADR 003: palette size is decoupled from the room cap (24 players can't have
## 24 distinct colors) — it just supplies a dozen distinct colors; the number
## channel (label_for_slot) disambiguates past that. The original six lead.
func test_palette_colors_are_distinct() -> void:
	assert_gte(PlayerPalette.COLORS.size(), 12, "at least a dozen distinct colors")
	var seen := {}
	for color in PlayerPalette.COLORS:
		seen[color.to_html()] = true
	assert_eq(seen.size(), PlayerPalette.COLORS.size(), "no duplicate colors")
	assert_eq(PlayerPalette.COLORS[0], Color(0.902, 0.290, 0.235), "P1 stays red")


func test_palette_wraps_out_of_range_slots() -> void:
	var count := PlayerPalette.COLORS.size()
	assert_eq(PlayerPalette.color_for_slot(0), PlayerPalette.COLORS[0])
	assert_eq(PlayerPalette.color_for_slot(count), PlayerPalette.COLORS[0], "wraps at palette size")
	assert_eq(PlayerPalette.color_for_slot(-1), PlayerPalette.COLORS[count - 1])


## M12-03: the colorblind-safe palette is a same-size, all-distinct alternate
## that the toggle swaps in, and it actually differs where the default set is
## worst (P1 red / P4 green — the deutan/protan confusion).
func test_colorblind_palette_is_distinct_alternate() -> void:
	assert_eq(
		PlayerPalette.COLORS_COLORBLIND.size(),
		PlayerPalette.COLORS.size(),
		"same size so slot mapping is unchanged"
	)
	var seen := {}
	for color in PlayerPalette.COLORS_COLORBLIND:
		seen[color.to_html()] = true
	assert_eq(seen.size(), PlayerPalette.COLORS_COLORBLIND.size(), "no duplicate CB colors")
	assert_ne(PlayerPalette.COLORS_COLORBLIND[0], PlayerPalette.COLORS[0], "P1 differs from red")
	assert_ne(PlayerPalette.COLORS_COLORBLIND[3], PlayerPalette.COLORS[3], "P4 differs from green")


func test_colorblind_toggle_switches_active_palette() -> void:
	PlayerPalette.use_colorblind = false
	assert_eq(PlayerPalette.color_for_slot(0), PlayerPalette.COLORS[0])
	PlayerPalette.use_colorblind = true
	assert_eq(PlayerPalette.color_for_slot(0), PlayerPalette.COLORS_COLORBLIND[0])
	assert_eq(
		PlayerPalette.color_for_slot(PlayerPalette.COLORS.size()),
		PlayerPalette.COLORS_COLORBLIND[0],
		"the CB set wraps the same way"
	)
	PlayerPalette.use_colorblind = false  # Don't leak the toggle into other tests.


## The number channel is always unique per slot, even where colors wrap.
func test_label_for_slot_numbers_players_from_one() -> void:
	assert_eq(PlayerPalette.label_for_slot(0), "P1")
	assert_eq(PlayerPalette.label_for_slot(11), "P12")
	assert_eq(PlayerPalette.label_for_slot(23), "P24", "identity survives past the color wrap")


func test_roster_entries_have_distinct_ids_and_scenes() -> void:
	var ids := CharacterRoster.ids()
	var seen := {}
	for id in ids:
		seen[id] = true
	assert_eq(seen.size(), ids.size(), "no duplicate roster ids")
	for entry: Dictionary in CharacterRoster.ENTRIES:
		assert_true(ResourceLoader.exists(entry.scene_path), "scene exists: %s" % entry.scene_path)


func test_roster_default_id_is_valid() -> void:
	assert_true(CharacterRoster.is_valid(CharacterRoster.DEFAULT_ID))


func test_roster_rejects_unknown_id() -> void:
	assert_false(CharacterRoster.is_valid(&"not_a_character"))
	assert_eq(CharacterRoster.display_name_for(&"not_a_character"), "")
	assert_null(CharacterRoster.scene_for(&"not_a_character"))


func test_roster_scene_for_loads_matching_character() -> void:
	var scene := CharacterRoster.scene_for(&"knight")
	assert_not_null(scene)
	var rig := RIG_SCENE.instantiate() as CharacterRig
	add_child_autofree(rig)
	rig.character_scene = scene
	assert_true(rig.play(&"idle"))


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


## #180: plates share one maximum width — long names/captions shrink their
## font to fit it, short names keep the base size.
func test_nameplate_width_is_capped() -> void:
	var rig := _make_rig()
	var plate: Label3D = rig.get_node("Nameplate")
	rig.display_name = "Bo"
	var short_size := plate.font_size
	rig.display_name = "Somebody With A Really Long Name  99  (false start!)"
	var long_size := plate.font_size
	assert_lt(long_size, short_size, "long captions shrink")
	var font := plate.font if plate.font != null else ThemeDB.fallback_font
	var rendered := (
		font.get_string_size(rig.display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, long_size).x
	)
	# The rendered width lands at (or under) the cap, scaled by the same
	# nameplate_scale factor the base size uses.
	var scale := float(long_size) / maxf(float(short_size), 1.0)
	assert_almost_eq(
		rendered,
		CharacterRig.NAMEPLATE_MAX_WIDTH * float(short_size) / CharacterRig.NAMEPLATE_BASE_FONT,
		CharacterRig.NAMEPLATE_MAX_WIDTH * 0.1,
		"long text fits the shared width cap"
	)
	assert_gt(scale, 0.0)


# --- Held weapons (#584) --------------------------------------------------------


func test_attack_action_maps_to_the_spin_swing() -> void:
	var rig := _make_rig()
	assert_true(rig.play(&"attack"), "all shipped characters carry the spin animation")
	assert_eq(rig.current_action(), &"attack")


func test_held_weapon_attaches_to_the_hand_and_clears() -> void:
	var rig := _make_rig()
	assert_false(rig.has_held_weapon())
	rig.set_held_weapon(BoxMesh.new())
	assert_true(rig.has_held_weapon())
	var attach := rig.find_children("HeldWeapon", "BoneAttachment3D", true, false)
	assert_eq(attach.size(), 1, "one weapon attachment on the skeleton")
	assert_eq((attach[0] as BoneAttachment3D).bone_name, "handslot.r")
	rig.clear_held_weapon()
	assert_false(rig.has_held_weapon())


func test_held_weapon_survives_a_character_swap() -> void:
	var rig := _make_rig()
	rig.set_held_weapon(BoxMesh.new())
	rig.character_scene = load("res://assets/characters/kaykit_skeletons/Skeleton_Minion.glb")
	var attach := rig.find_children("HeldWeapon", "BoneAttachment3D", true, false)
	assert_eq(attach.size(), 1, "the new body is re-armed (skeletons have no props of their own)")
