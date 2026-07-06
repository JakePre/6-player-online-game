extends GutTest
## Finale Gauntlet client view (M8-12): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

const VIEW_SCENE: PackedScene = preload("res://src/finale/gauntlet_view.tscn")

var view: MinigameView


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


## A view with `count` players, local slot 0 — for the finale targeting tests.
func _make_view(count: int) -> MinigameView:
	var names := {}
	for slot in count:
		names[slot] = "P%d" % (slot + 1)
	var v: MinigameView = VIEW_SCENE.instantiate()
	add_child_autofree(v)
	v.setup(names, 0)
	return v


func test_setup_builds_iso_arena_with_rigs_and_platform() -> void:
	assert_not_null(view.arena, "MinigameView3D arena should exist after setup")
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.rig_for_slot(1))
	var platform: MeshInstance3D = view.arena.get_node("Platform")
	assert_not_null(platform)
	assert_eq((platform.mesh as CylinderMesh).top_radius, Gauntlet.START_RADIUS)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"radius": 7.0,
				"players": {0: [1.0, -2.0, 2, 0.0], 1: [0.0, 0.0, 1, 0.0]},
				"hazards": [[2.0, 2.0, 1.5, 0.8]],
			}
		)
	)
	assert_eq(view.radius, 7.0)
	assert_eq(view.players.size(), 2)
	assert_eq(view.hazards.size(), 1)
	view.render({"radius": 5.5, "players": {}, "hazards": []})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")
	assert_eq(view.hazards.size(), 0)


func test_platform_disc_tracks_snapshot_radius() -> void:
	view.render({"radius": 4.0, "players": {}, "hazards": []})
	var platform: MeshInstance3D = view.arena.get_node("Platform")
	assert_eq((platform.mesh as CylinderMesh).top_radius, 4.0)


func test_respawning_and_eliminated_players_hide_their_rigs() -> void:
	(
		view
		. render(
			{
				"radius": 10.0,
				"players": {0: [1.0, 1.0, 1, 2.5], 1: [2.0, 2.0, 0, 0.0]},
				"hazards": [],
			}
		)
	)
	assert_false(view.rig_for_slot(0).visible, "respawning players are off the platform")
	assert_false(view.rig_for_slot(1).visible, "eliminated players are gone")
	view.render({"radius": 10.0, "players": {0: [1.0, 1.0, 1, 0.0]}, "hazards": []})
	assert_true(view.rig_for_slot(0).visible, "back after the respawn")


func test_lives_shown_on_nameplate() -> void:
	view.render({"radius": 10.0, "players": {0: [0.0, 0.0, 3, 0.0]}, "hazards": []})
	assert_string_contains(view.rig_for_slot(0).display_name, "♥♥♥")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.hazards.size(), 0)
	assert_eq(view.radius, Gauntlet.START_RADIUS)


func _particle_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


## M13-31: the platform sheds crumble dust each time it shrinks a stage.
func test_shrinking_platform_crumbles_dust() -> void:
	view.render({"radius": Gauntlet.START_RADIUS, "players": {}, "hazards": []})
	var before := _particle_count()
	view.render({"radius": Gauntlet.START_RADIUS - 3.0, "players": {}, "hazards": []})
	assert_gt(_particle_count(), before, "a shrink crumbles the shed rim")


## M13-31: a freshly-armed hazard pops a warning spark; a detonating one bursts.
func test_hazard_telegraph_sparks_then_bursts() -> void:
	var armed := {"radius": Gauntlet.START_RADIUS, "players": {}, "hazards": [[2.0, 0.0, 1.5, 0.8]]}
	view.render(armed)
	var after_spawn := _particle_count()
	assert_gt(after_spawn, 0, "a new hazard telegraphs a spark")
	# Same radius so no crumble; the hazard vanishes (detonates).
	view.render({"radius": Gauntlet.START_RADIUS, "players": {}, "hazards": []})
	assert_gt(_particle_count(), after_spawn, "a detonating hazard bursts")


## M13-31: losing a life bursts where the player stood.
func test_losing_a_life_bursts() -> void:
	var two := {"radius": Gauntlet.START_RADIUS, "players": {0: [0.0, 0.0, 2, 0.0]}, "hazards": []}
	view.render(two)
	var before := _particle_count()
	view.render(
		{"radius": Gauntlet.START_RADIUS, "players": {0: [0.0, 0.0, 1, 0.0]}, "hazards": []}
	)
	assert_gt(_particle_count(), before, "a lost life bursts at the player")


## #462: a sabotage token drops on the nearest *living* rival, not arena center.
func test_sabotage_targets_nearest_living_rival() -> void:
	var v := _make_view(4)
	# Local slot 0 at origin; rival 3 is nearest but dead, rival 2 next, rival 1 far.
	(
		v
		. render(
			{
				"radius": 10.0,
				"players":
				{
					0: [0.0, 0.0, 3, 0.0],
					1: [8.0, 0.0, 3, 0.0],
					2: [3.0, 0.0, 2, 0.0],
					3: [1.0, 0.0, 0, 0.0],
				},
				"hazards": [],
			}
		)
	)
	var target: Array = v._sabotage_target()
	assert_almost_eq(float(target[0]), 3.0, 0.001, "aims at the nearest *living* rival (slot 2)")
	assert_almost_eq(float(target[1]), 0.0, 0.001)


func test_sabotage_falls_back_to_center_with_no_living_rival() -> void:
	var v := _make_view(2)
	v.render(
		{"radius": 10.0, "players": {0: [0.0, 0.0, 3, 0.0], 1: [2.0, 0.0, 0, 0.0]}, "hazards": []}
	)
	assert_eq(v._sabotage_target(), [0.0, 0.0], "no living rival -> harmless center drop")


## #462: the grudge prompt appears only for the eliminated local player who
## still holds their one grudge, and names the current target.
func test_grudge_prompt_only_for_eliminated_local_player() -> void:
	var v := _make_view(3)
	var prompt: Label = v.get_node("GrudgePrompt")
	# Local slot 0 alive -> no prompt.
	v.render(
		{"radius": 10.0, "players": {0: [0.0, 0.0, 2, 0.0], 1: [1.0, 0.0, 2, 0.0]}, "hazards": []}
	)
	assert_false(prompt.visible, "alive players get no grudge prompt")
	# Local slot 0 eliminated with a living rival -> prompt shown, names a rival.
	v.render(
		{"radius": 10.0, "players": {0: [0.0, 0.0, 0, 0.0], 1: [1.0, 0.0, 2, 0.0]}, "hazards": []}
	)
	assert_true(prompt.visible, "an eliminated player can grudge")
	assert_string_contains(prompt.text, "GRUDGE")


## Regression for #576: the grudge prompt's long "GRUDGE → name … aim / strike"
## line must grow upward off its bottom anchor, not downward past the viewport.
## Hand-built (not routed through the shared make_banner()), so it carries its
## own copy of the same fix.
func test_grudge_prompt_stays_within_the_viewport() -> void:
	var v := _make_view(3)
	var prompt: Label = v.get_node("GrudgePrompt")
	v.render(
		{"radius": 10.0, "players": {0: [0.0, 0.0, 0, 0.0], 1: [1.0, 0.0, 2, 0.0]}, "hazards": []}
	)
	await get_tree().process_frame
	assert_true(
		prompt.position.y + prompt.size.y <= v.size.y + 1.0,
		"the grudge prompt grows upward off its anchor, not downward past the screen edge"
	)


func test_grudge_cycles_between_living_rivals() -> void:
	var v := _make_view(4)
	(
		v
		. render(
			{
				"radius": 10.0,
				"players":
				{
					0: [0.0, 0.0, 0, 0.0],  # local, eliminated
					1: [1.0, 0.0, 2, 0.0],
					2: [2.0, 0.0, 2, 0.0],
					3: [3.0, 0.0, 0, 0.0],  # dead, not a valid target
				},
				"hazards": [],
			}
		)
	)
	v._cycle_grudge(1)
	var first: int = v._grudge_target
	assert_true(first in [1, 2], "targets a living rival")
	v._cycle_grudge(1)
	assert_ne(v._grudge_target, first, "cycling moves to the other living rival")
	assert_true(v._grudge_target in [1, 2])
	assert_ne(v._grudge_target, 3, "the dead slot is never a target")


func test_grudge_fires_once_then_prompt_hides() -> void:
	var v := _make_view(2)
	var prompt: Label = v.get_node("GrudgePrompt")
	v.render(
		{"radius": 10.0, "players": {0: [0.0, 0.0, 0, 0.0], 1: [1.0, 0.0, 2, 0.0]}, "hazards": []}
	)
	assert_true(prompt.visible)
	v._fire_grudge()
	assert_true(v._grudge_spent, "the one grudge is spent")
	assert_false(prompt.visible, "prompt clears after striking")
	# A re-render must not revive the spent grudge.
	v.render(
		{"radius": 10.0, "players": {0: [0.0, 0.0, 0, 0.0], 1: [1.0, 0.0, 2, 0.0]}, "hazards": []}
	)
	assert_false(prompt.visible, "grudge stays spent")


# --- Finale chrome (M16-11) ---------------------------------------------------


func _intro_card(v: MinigameView) -> VBoxContainer:
	return v.get_node("FinaleChrome/IntroCard")


func _intro_title(v: MinigameView) -> Label:
	return v.get_node("FinaleChrome/IntroCard/IntroTitle")


func _event_banner(v: MinigameView) -> PanelContainer:
	return v.get_node("FinaleChrome/EventBanner")


func _event_label(v: MinigameView) -> Label:
	return v.get_node("FinaleChrome/EventBanner/EventLabel")


func test_intro_treatment_flashes_on_first_render() -> void:
	var v := _make_view(3)
	assert_false(_intro_card(v).visible, "intro is hidden before any snapshot")
	(
		v
		. render(
			{
				"radius": 10.0,
				"players": {0: [0.0, 0.0, 2, 0.0], 1: [1.0, 0.0, 2, 0.0], 2: [2.0, 0.0, 2, 0.0]},
				"hazards": [],
			}
		)
	)
	assert_true(_intro_card(v).visible, "intro flashes the instant the finale replicates")
	assert_string_contains(_intro_title(v).text, "GAUNTLET")


func test_losing_last_life_pops_an_elimination_banner() -> void:
	var v := _make_view(3)
	var alive := {
		"radius": 10.0,
		"players": {0: [0.0, 0.0, 2, 0.0], 1: [1.0, 0.0, 2, 0.0], 2: [2.0, 0.0, 2, 0.0]},
		"hazards": [],
	}
	v.render(alive)
	# Slot 2 loses its last life while two players remain (no premature champion).
	(
		v
		. render(
			{
				"radius": 10.0,
				"players": {0: [0.0, 0.0, 2, 0.0], 1: [1.0, 0.0, 2, 0.0], 2: [2.0, 0.0, 0, 0.0]},
				"hazards": [],
			}
		)
	)
	assert_true(_event_banner(v).visible, "elimination raises the event banner")
	assert_string_contains(_event_label(v).text, "ELIMINATED")
	assert_string_contains(_event_label(v).text, "P3", "the eliminated player is named")


func test_respawnable_life_loss_does_not_banner() -> void:
	var v := _make_view(3)
	(
		v
		. render(
			{
				"radius": 10.0,
				"players": {0: [0.0, 0.0, 2, 0.0], 1: [1.0, 0.0, 2, 0.0], 2: [2.0, 0.0, 2, 0.0]},
				"hazards": [],
			}
		)
	)
	# Slot 2 drops from 2 to 1 life — bruised, not eliminated.
	(
		v
		. render(
			{
				"radius": 10.0,
				"players": {0: [0.0, 0.0, 2, 0.0], 1: [1.0, 0.0, 2, 0.0], 2: [2.0, 0.0, 1, 3.0]},
				"hazards": [],
			}
		)
	)
	assert_false(_event_banner(v).visible, "a survivable hit does not fire the banner")


func test_last_blob_standing_triggers_the_champion_sequence() -> void:
	var v := _make_view(3)
	(
		v
		. render(
			{
				"radius": 10.0,
				"players": {0: [0.0, 0.0, 2, 0.0], 1: [1.0, 0.0, 2, 0.0], 2: [2.0, 0.0, 2, 0.0]},
				"hazards": [],
			}
		)
	)
	# Only slot 0 is left with lives.
	(
		v
		. render(
			{
				"radius": 10.0,
				"players": {0: [0.0, 0.0, 2, 0.0], 1: [1.0, 0.0, 0, 0.0], 2: [2.0, 0.0, 0, 0.0]},
				"hazards": [],
			}
		)
	)
	assert_true(v._winner_shown, "the champion sequence fires once")
	assert_true(_event_banner(v).visible)
	assert_string_contains(_event_label(v).text, "CHAMPION")
	assert_string_contains(_event_label(v).text, "P1", "the winner is named")


func test_firing_a_grudge_pops_a_strike_banner() -> void:
	var v := _make_view(3)
	# Local (slot 0) is out; two rivals remain, so no premature champion.
	(
		v
		. render(
			{
				"radius": 10.0,
				"players": {0: [0.0, 0.0, 0, 0.0], 1: [1.0, 0.0, 2, 0.0], 2: [2.0, 0.0, 2, 0.0]},
				"hazards": [],
			}
		)
	)
	v._cycle_grudge(1)
	v._fire_grudge()
	assert_true(_event_banner(v).visible, "the grudge strike raises the banner")
	assert_string_contains(_event_label(v).text, "GRUDGE")


func test_reduced_motion_still_shows_the_intro() -> void:
	var prior: bool = ArenaFX.reduced_motion
	ArenaFX.reduced_motion = true
	var v := _make_view(3)
	(
		v
		. render(
			{
				"radius": 10.0,
				"players": {0: [0.0, 0.0, 2, 0.0], 1: [1.0, 0.0, 2, 0.0], 2: [2.0, 0.0, 2, 0.0]},
				"hazards": [],
			}
		)
	)
	assert_true(_intro_card(v).visible, "reduced motion still reveals the intro (no animation)")
	assert_almost_eq(_intro_card(v).modulate.a, 1.0, 0.001, "shown at full opacity, no fade")
	ArenaFX.reduced_motion = prior
