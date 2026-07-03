extends GutTest
## King of the Hill client view (M8-04): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func _instantiate_view() -> MinigameView:
	var scene: PackedScene = load("res://src/minigames/king_of_the_hill/king_of_the_hill_view.tscn")
	var instance: MinigameView = scene.instantiate()
	add_child_autofree(instance)
	return instance


func before_each() -> void:
	view = _instantiate_view()
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_setup_stores_identity_context() -> void:
	assert_eq(view.my_slot, 0)
	assert_eq(view.player_name(1), "Bob")
	assert_eq(view.player_color(1), PlayerPalette.color_for_slot(1))


func test_setup_builds_iso_arena_with_rigs() -> void:
	assert_not_null(view.arena, "MinigameView3D arena should exist after setup")
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.rig_for_slot(1))
	assert_null(view.rig_for_slot(4), "no rig for slots not in the room")


func test_render_replaces_replicated_state() -> void:
	view.render({"players": {0: [1.0, -2.0, 4], 1: [0.0, 0.0, 0]}, "zone": [2.0, 3.0, 1.5]})
	assert_eq(view.players.size(), 2)
	assert_eq(view.players[0], [1.0, -2.0, 4])
	assert_eq(view.zone, [2.0, 3.0, 1.5])
	view.render({"players": {0: [5.0, 5.0, 9]}, "zone": []})
	assert_eq(view.players.size(), 1, "each snapshot fully replaces the last")
	assert_eq(view.zone.size(), 0)


func test_zone_disc_follows_snapshot() -> void:
	view.render({"players": {}, "zone": [2.0, -3.0, 1.5]})
	var zone_node: MeshInstance3D = view.arena.get_node("Zone")
	assert_true(zone_node.visible)
	assert_almost_eq(zone_node.position.x, 2.0, 0.001)
	assert_almost_eq(zone_node.position.z, -3.0, 0.001)
	assert_almost_eq(zone_node.scale.x, 1.5, 0.001)
	view.render({"players": {}, "zone": []})
	assert_false(zone_node.visible, "no zone in the snapshot hides the disc")


func test_rig_follows_player_snapshot() -> void:
	view.render({"players": {0: [4.0, -1.0, 7]}, "zone": []})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 4.0, 0.001)
	assert_almost_eq(rig.position.z, -1.0, 0.001)
	assert_string_contains(rig.display_name, "Alice")
	assert_string_contains(rig.display_name, "7")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.zone.size(), 0)


## M6-02: the first placement tie group cheers on round results.
func test_celebrate_makes_winners_cheer() -> void:
	view.render({"players": {0: [0.0, 0.0, 5], 1: [1.0, 1.0, 2]}, "zone": []})
	view.celebrate([[0], [1]])
	assert_eq(view.rig_for_slot(0).current_action(), &"cheer")
	assert_ne(view.rig_for_slot(1).current_action(), &"cheer")


## M9-05 view flags: Masquerade hides nameplates, Blackout adds the cycling
## lights-out overlay; a plain round gets neither.
func test_masquerade_flag_hides_nameplates() -> void:
	var flagged := _instantiate_view()
	flagged.view_flags = [&"hide_nameplates"]
	flagged.setup({0: "Alice"}, 0)
	var nameplate: Label3D = flagged.rig_for_slot(0).get_node("Nameplate")
	assert_false(nameplate.visible)
	assert_true(view.rig_for_slot(0).get_node("Nameplate").visible, "unflagged view keeps them")


func test_blackout_flag_builds_the_overlay() -> void:
	var flagged := _instantiate_view()
	flagged.view_flags = ["blackout"]
	flagged.setup({0: "Alice"}, 0)
	var overlay: ColorRect = flagged.get_node("BlackoutOverlay")
	assert_false(overlay.visible, "lights start on")
	assert_false((flagged.get_node("BlackoutTimer") as Timer).is_stopped())
	assert_null(view.get_node_or_null("BlackoutOverlay"), "unflagged view has no overlay")
	assert_true(flagged.has_view_flag(&"blackout"), "String flags from the wire still match")
