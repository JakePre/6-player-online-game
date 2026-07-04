extends GutTest
## Heist Night client view (M4-16): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/heist_night/heist_night_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"heist_night"),
		"res://src/minigames/heist_night/heist_night_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"dark": false,
				"players": {0: [1.0, 2.0]},
				"vaults": {0: [3.0, 3.0, 4]},
				"coins": [[0.0, 0.0]],
			}
		)
	)
	assert_false(view.dark)
	assert_eq(view.players.size(), 1)
	assert_eq(view.vaults[0], [3.0, 3.0, 4])
	view.render({"dark": true, "players": {}, "vaults": {}, "coins": []})
	assert_true(view.dark, "each snapshot fully replaces the last")
	assert_eq(view.players.size(), 0)


func test_render_shows_reveal_when_present() -> void:
	view.render({"dark": false, "players": {}, "vaults": {}, "coins": [], "reveal": {0: {1: 3}}})
	assert_eq(view.reveal, {0: {1: 3}})


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_false(view.dark)
	assert_eq(view.players.size(), 0)
	assert_eq(view.reveal, {})


## M13-27: a vault total dropping (theft) fires a steal pulse; the first
## snapshot seeds silently and gains never pulse.
func test_vault_drop_fires_steal_pulse() -> void:
	view.render({"vaults": {0: [3.0, 3.0, 5], 1: [-3.0, -3.0, 2]}})
	assert_eq(view._pulses.size(), 0, "first sighting seeds silently")
	view.render({"vaults": {0: [3.0, 3.0, 3], 1: [-3.0, -3.0, 2]}})
	assert_eq(view._pulses.size(), 1, "only the robbed vault pulses")
	assert_eq(int(view._pulses[0].slot), 0)


func test_vault_gain_does_not_pulse() -> void:
	view.render({"vaults": {0: [3.0, 3.0, 5]}})
	view.render({"vaults": {0: [3.0, 3.0, 9]}})
	assert_eq(view._pulses.size(), 0, "banking coins is not a robbery")


func test_steal_pulses_expire() -> void:
	view.render({"vaults": {0: [3.0, 3.0, 5]}})
	view.render({"vaults": {0: [3.0, 3.0, 4]}})
	assert_eq(view._pulses.size(), 1)
	view._process(view.PULSE_DURATION + 0.05)
	assert_eq(view._pulses.size(), 0, "pulses free themselves after their lifetime")


func test_scanline_freezes_while_feed_is_lost() -> void:
	view.render({"dark": false})
	view._process(0.5)
	assert_gt(view._scan_clock, 0.0, "live feed sweeps")
	var clock: float = view._scan_clock
	view.render({"dark": true})
	view._process(0.5)
	assert_eq(view._scan_clock, clock, "FEED LOST freezes the scanline")
