extends GutTest
## King of the Hill client view (M8-04): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView
var _saved_show_names := false


func _instantiate_view() -> MinigameView:
	var scene: PackedScene = load("res://src/minigames/king_of_the_hill/king_of_the_hill_view.tscn")
	var instance: MinigameView = scene.instantiate()
	add_child_autofree(instance)
	return instance


func before_each() -> void:
	_saved_show_names = MinigameView.show_names
	MinigameView.show_names = true  # #580: names off by default; this suite tests the name itself
	view = _instantiate_view()
	view.setup({0: "Alice", 1: "Bob"}, 0)


func after_each() -> void:
	MinigameView.show_names = _saved_show_names


func test_setup_stores_identity_context() -> void:
	assert_eq(view.my_slot, 0)
	assert_eq(view.player_name(1), "P2 Bob", "names carry the always-on number (M15-02)")
	assert_eq(view.player_color(1), PlayerPalette.color_for_slot(1))


func test_setup_builds_iso_arena_with_rigs() -> void:
	assert_not_null(view.arena, "MinigameView3D arena should exist after setup")
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.rig_for_slot(1))
	assert_null(view.rig_for_slot(4), "no rig for slots not in the room")


## M15: the view derives its floor/camera size from the lobby count with the
## same formula the sim uses, so the rendered arena matches the scaled one.
func test_arena_half_scales_with_lobby_size() -> void:
	assert_almost_eq(view._arena_half(), KingOfTheHill.ARENA_HALF, 0.001, "2 players = base arena")
	var big := _instantiate_view()
	var names := {}
	for i in 12:
		names[i] = "P%d" % (i + 1)
	big.setup(names, 0)
	assert_gt(big._arena_half(), KingOfTheHill.ARENA_HALF, "12 players get a bigger floor")


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


## #813 demonstrator: the grassy hilltop is ringed with scenery via the shared
## scatter_rim_props helper, dressing the arena edge.
func test_hilltop_is_ringed_with_scenery() -> void:
	var props: Node = view.arena.get_node("RimProps")
	assert_not_null(props, "the rim-prop container is built")
	assert_eq(props.get_child_count(), view.RIM_PROP_COUNT, "pines and rocks ring the hill")


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


## M13-03: scoring sheds sparkles, the zone throbs and bursts on relocation.
func test_scoring_sheds_sparkles_once_seeded() -> void:
	view.render({"players": {0: [0.0, 0.0, 3]}, "zone": [0.0, 0.0, 3.0]})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: [0.0, 0.0, 3]}, "zone": [0.0, 0.0, 3.0]})
	assert_eq(view.arena.get_child_count(), before, "no score change, no sparkle")
	view.render({"players": {0: [0.0, 0.0, 4]}, "zone": [0.0, 0.0, 3.0]})
	assert_eq(view.arena.get_child_count(), before + 1, "a point = a sparkle")


func test_zone_relocation_bursts_and_dusts() -> void:
	view.render({"players": {}, "zone": [0.0, 0.0, 3.0]})
	var before: int = view.arena.get_child_count()
	view.render({"players": {}, "zone": [5.0, 5.0, 3.0]})
	assert_eq(view.arena.get_child_count(), before + 2, "burst at the old spot, dust at the new")


## #587: firing a held Shove Blast plays the shove animation on the rig — the
## held item clearing (while it was SHOVE) is the use-moment.
func test_shove_use_plays_the_interact_animation() -> void:
	(
		view
		. render(
			{
				"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]},
				"zone": [],
				"held": {0: KingOfTheHill.Item.SHOVE},
			}
		)
	)
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zone": [], "held": {}})
	assert_eq(view.rig_for_slot(0).current_action(), &"interact")


## An Anchor use (not Shove) does not trigger the shove animation.
func test_anchor_use_does_not_play_the_shove_animation() -> void:
	view.render({"players": {0: [0.0, 0.0, 0]}, "zone": [], "held": {0: KingOfTheHill.Item.ANCHOR}})
	view.render({"players": {0: [0.0, 0.0, 0]}, "zone": [], "held": {}})
	assert_ne(view.rig_for_slot(0).current_action(), &"interact")


## #844: the held-item prompt used to hardcode "press Space / Ⓐ" for both
## schemes; it now renders only the active device's binding, live.
func test_held_item_prompt_is_device_aware() -> void:
	var saved_device := InputGlyphs.active_device
	InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
	view.render({"players": {}, "zone": [], "held": {0: KingOfTheHill.Item.SHOVE}})
	var held_label: Label = view.get_node("BannerLayer/HeldItem")
	assert_string_contains(held_label.text, InputGlyphs.glyph_for(&"action_primary"))
	assert_false(held_label.text.contains("Ⓐ"), "no hardcoded pad glyph while on keyboard")
	InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
	view.render({"players": {}, "zone": [], "held": {0: KingOfTheHill.Item.SHOVE}})
	assert_string_contains(held_label.text, InputGlyphs.glyph_for(&"action_primary"))
	InputGlyphs.active_device = saved_device


## #800: the shove flourish must never stall movement — the walk switch
## fires the instant the player actually moves, even mid-flourish.
func test_movement_during_the_shove_flourish_is_not_stalled() -> void:
	(
		view
		. render(
			{
				"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]},
				"zone": [],
				"held": {0: KingOfTheHill.Item.SHOVE},
			}
		)
	)
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zone": [], "held": {}})
	assert_eq(view.rig_for_slot(0).current_action(), &"interact", "the flourish plays first")
	view.render({"players": {0: [3.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zone": [], "held": {}})
	assert_eq(
		view.rig_for_slot(0).current_action(),
		&"walk",
		"moving mid-flourish switches to walk immediately — never stalls movement"
	)


## Standing still lets the flourish play out undisturbed (unchanged from
## before #800) — only movement interrupts it.
func test_standing_still_keeps_the_flourish_playing() -> void:
	(
		view
		. render(
			{
				"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]},
				"zone": [],
				"held": {0: KingOfTheHill.Item.SHOVE},
			}
		)
	)
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zone": [], "held": {}})
	view.render({"players": {0: [0.0, 0.0, 0], 1: [1.0, 1.0, 0]}, "zone": [], "held": {}})
	assert_eq(
		view.rig_for_slot(0).current_action(),
		&"interact",
		"no movement — the flourish still plays out"
	)


func test_zone_throbs_across_snapshots() -> void:
	view.render({"players": {}, "zone": [0.0, 0.0, 3.0]})
	var glow_a: float = view._zone_material.emission_energy_multiplier
	view.render({"players": {}, "zone": [0.0, 0.0, 3.0]})
	assert_ne(view._zone_material.emission_energy_multiplier, glow_a, "shimmer advances")


## #919: the zone disc caps a real hill-crest model instead of floating at
## ground level — both track the snapshot position and hide together.
func test_hill_crest_tracks_the_zone() -> void:
	var crest: Node3D = view.arena.get_node("HillCrest")
	assert_false(crest.visible, "no zone in the seeding snapshot")
	view.render({"players": {}, "zone": [2.0, -3.0, 1.5]})
	assert_true(crest.visible)
	assert_almost_eq(crest.position.x, 2.0, 0.001)
	assert_almost_eq(crest.position.z, -3.0, 0.001)
	assert_almost_eq(crest.position.y, 0.0, 0.001, "base-pivoted — sits on the ground")
	assert_almost_eq(
		crest.scale.x, 1.5 / view.HILL_CREST_HALF_WIDTH, 0.001, "footprint scales with radius"
	)
	var zone_node: MeshInstance3D = view.arena.get_node("Zone")
	assert_almost_eq(
		zone_node.position.y,
		view.HILL_CREST_HEIGHT + view.ZONE_DISC_HEIGHT / 2.0,
		0.001,
		"the disc rides on top of the crest, not at ground level"
	)
	view.render({"players": {}, "zone": []})
	assert_false(crest.visible, "hides together with the disc when the zone is gone")


## #919: item pickups are real shove-horn/anchor models sharing one pool node,
## swapped by visibility rather than rebuilt when a slot's item type changes.
func test_item_pickups_show_the_matching_model() -> void:
	(
		view
		. render(
			{
				"players": {},
				"zone": [],
				"items":
				[[0.0, 0.0, KingOfTheHill.Item.SHOVE], [1.0, 1.0, KingOfTheHill.Item.ANCHOR]],
			}
		)
	)
	var item0: Node3D = view._item_nodes[0]
	var item1: Node3D = view._item_nodes[1]
	assert_true((item0.get_node("Horn") as Node3D).visible)
	assert_false((item0.get_node("Anchor") as Node3D).visible)
	assert_false((item1.get_node("Horn") as Node3D).visible)
	assert_true((item1.get_node("Anchor") as Node3D).visible)
	assert_almost_eq(item0.position.y, 0.0, 0.001, "base-pivoted — sits on the ground")
	# The same pool node flips shape when a slot's item type changes next spawn.
	view.render({"players": {}, "zone": [], "items": [[0.0, 0.0, KingOfTheHill.Item.ANCHOR]]})
	assert_true((item0.get_node("Anchor") as Node3D).visible)
	assert_false((item0.get_node("Horn") as Node3D).visible)
