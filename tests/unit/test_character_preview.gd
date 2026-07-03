extends GutTest
## Lobby character preview (M8-13): a live CharacterRig showing the local
## player's roster pick, idling normally and cheering once readied.

var preview: CharacterPreview


func before_each() -> void:
	preview = CharacterPreview.new()
	add_child_autofree(preview)


func _rig() -> CharacterRig:
	return preview.get_node("PreviewContainer/PreviewViewport/PreviewRig")


func test_builds_viewport_with_a_rig() -> void:
	assert_not_null(_rig())
	assert_true(
		preview.get_node("PreviewContainer/PreviewViewport") is SubViewport,
		"preview renders in its own world"
	)


func test_show_character_applies_scene_color_and_idle() -> void:
	var ids := CharacterRoster.ids()
	preview.show_character(ids[0], Color.RED)
	assert_eq(preview.current_character(), ids[0])
	assert_eq(_rig().character_scene, CharacterRoster.scene_for(ids[0]))
	assert_eq(_rig().player_color, Color.RED)
	assert_eq(_rig().current_action(), &"idle")


func test_changing_the_pick_swaps_the_character_scene() -> void:
	var ids := CharacterRoster.ids()
	preview.show_character(ids[0], Color.RED)
	preview.show_character(ids[1], Color.RED)
	assert_eq(preview.current_character(), ids[1])
	assert_eq(_rig().character_scene, CharacterRoster.scene_for(ids[1]))


func test_ready_players_cheer() -> void:
	var ids := CharacterRoster.ids()
	preview.show_character(ids[0], Color.RED, true)
	assert_eq(_rig().current_action(), &"cheer")
	preview.show_character(ids[0], Color.RED, false)
	assert_eq(_rig().current_action(), &"idle")
