extends GutTest
## Coin Scramble client view (M3-06): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/coin_scramble/coin_scramble_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_setup_stores_identity_context() -> void:
	assert_eq(view.my_slot, 0)
	assert_eq(view.player_name(1), "Bob")
	assert_eq(view.player_name(4), "Player 5", "unknown slots fall back")
	assert_eq(view.player_color(1), PlayerPalette.color_for_slot(1))


func test_render_replaces_replicated_state() -> void:
	view.render({"players": {0: [1.0, -2.0, 4], 1: [0.0, 0.0, 0]}, "coins": [[3.0, 3.0]]})
	assert_eq(view.players.size(), 2)
	assert_eq(view.players[0], [1.0, -2.0, 4])
	assert_eq(view.coins, [[3.0, 3.0]])
	view.render({"players": {0: [5.0, 5.0, 9]}, "coins": []})
	assert_eq(view.players.size(), 1, "each snapshot fully replaces the last")
	assert_eq(view.coins.size(), 0)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.coins.size(), 0)
