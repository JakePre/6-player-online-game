extends GutTest
## Hot Potato client view (M8-05): renders replicated snapshots in the shared
## iso-arena without simulating anything locally.

var view: MinigameView
var _saved_show_names := false


func before_each() -> void:
	_saved_show_names = MinigameView.show_names
	MinigameView.show_names = true  # #580: names off by default; this suite tests the name itself
	var scene: PackedScene = load("res://src/minigames/hot_potato/hot_potato_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func after_each() -> void:
	MinigameView.show_names = _saved_show_names


func test_setup_builds_iso_arena_with_rigs() -> void:
	assert_not_null(view.arena)
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.rig_for_slot(1))


func test_render_replaces_replicated_state() -> void:
	view.render(
		{"players": {0: [1.0, -2.0], 1: [3.0, 4.0]}, "carrier": 1, "fuse": 5.5, "alive": [0, 1]}
	)
	assert_eq(view.players.size(), 2)
	assert_eq(view.carrier, 1)
	assert_almost_eq(view.fuse, 5.5, 0.001)
	assert_eq(view.alive, [0, 1])
	view.render({"players": {0: [0.0, 0.0]}, "carrier": -1, "fuse": 0.0, "alive": [0]})
	assert_eq(view.players.size(), 1, "each snapshot fully replaces the last")
	assert_eq(view.carrier, -1)


func test_bomb_hovers_over_the_carrier() -> void:
	view.render(
		{"players": {0: [1.0, -2.0], 1: [3.0, 4.0]}, "carrier": 1, "fuse": 5.5, "alive": [0, 1]}
	)
	var bomb: MeshInstance3D = view.arena.get_node("Bomb")
	assert_true(bomb.visible)
	assert_almost_eq(bomb.position.x, 3.0, 0.001)
	assert_almost_eq(bomb.position.z, 4.0, 0.001)
	assert_string_contains(view.rig_for_slot(1).display_name, "5.5")


func test_bomb_hidden_without_a_live_carrier() -> void:
	view.render({"players": {0: [0.0, 0.0]}, "carrier": -1, "fuse": 0.0, "alive": [0]})
	assert_false(view.arena.get_node("Bomb").visible)
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "carrier": 1, "fuse": 2.0, "alive": [0]}
	)
	assert_false(
		view.arena.get_node("Bomb").visible, "an eliminated carrier does not wear the bomb"
	)


func test_eliminated_player_goes_down_dimmed() -> void:
	view.render(
		{"players": {0: [1.0, -2.0], 1: [3.0, 4.0]}, "carrier": 0, "fuse": 9.0, "alive": [0, 1]}
	)
	view.render(
		{"players": {0: [1.0, -2.0], 1: [3.0, 4.0]}, "carrier": 0, "fuse": 3.0, "alive": [0]}
	)
	var rig: CharacterRig = view.rig_for_slot(1)
	assert_eq(rig.current_action(), &"ko")
	assert_eq(rig.player_color, view.ELIMINATED_COLOR)
	assert_eq(rig.display_name, "P2 Bob", "no fuse on an eliminated nameplate")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.carrier, -1)
	assert_eq(view.alive.size(), 0)


## M6-02: the bomb going off shakes the screen; the first snapshot never does
## (so a mid-match rejoiner is not greeted with a shake).
func test_elimination_requests_screen_shake() -> void:
	watch_signals(view)
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "carrier": 1, "fuse": 5.0, "alive": [0, 1]}
	)
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot stays calm")
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "carrier": 0, "fuse": 9.0, "alive": [0]}
	)
	assert_signal_emitted(view, "shake_requested")


## M13-04: the lit fuse sheds sparks over the carrier, and the pop adds
## debris + dust under the shockwave.
func test_carrier_trails_sparks_on_a_cadence() -> void:
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "carrier": 1, "fuse": 9.0, "alive": [0, 1]}
	)
	var start: int = view.arena.get_child_count()
	for _i in 20:
		view.render(
			{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "carrier": 1, "fuse": 8.0, "alive": [0, 1]}
		)
	assert_gt(view.arena.get_child_count(), start, "sparks shed while carried")


func test_pop_adds_debris_and_dust() -> void:
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "carrier": 1, "fuse": 0.2, "alive": [0, 1]}
	)
	var before: int = view.arena.get_child_count()
	view.render(
		{"players": {0: [0.0, 0.0], 1: [1.0, 1.0]}, "carrier": 0, "fuse": 9.0, "alive": [0]}
	)
	assert_gte(view.arena.get_child_count(), before + 3, "shockwave + debris burst + dust")
