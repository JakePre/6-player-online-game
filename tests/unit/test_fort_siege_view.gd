extends GutTest
## Fort Siege client view (M10-12): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/fort_siege/fort_siege_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob", 2: "Carol", 3: "Dave"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"fort_siege"),
		"res://src/minigames/fort_siege/fort_siege_view.tscn"
	)


func test_setup_builds_arena_gate_and_core() -> void:
	assert_not_null(view.arena)
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.arena.get_node("Gate"))
	# The core is now a raised plinth + glowing crystal, not a flat disc (#808).
	assert_not_null(view.arena.get_node("CorePlinth"))
	assert_not_null(view.arena.get_node("CoreCrystal"))


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"phase": FortSiege.Phase.SIEGE,
				"attacking": 1,
				"phase_left": 25.0,
				"gate": 0.5,
				"capture": 0.25,
				"players": {0: [1.0, 2.0]},
				"teams": [[0, 1], [2, 3]],
				"times": [-1.0, -1.0],
			}
		)
	)
	assert_eq(view.attacking, 1)
	assert_almost_eq(view.gate, 0.5, 0.001)
	assert_eq(view.players.size(), 1)
	view.render({"players": {}, "teams": [], "times": []})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_gate_hides_when_breached_and_bursts_once() -> void:
	view.render({"gate": 0.4, "players": {}, "teams": [], "times": []})
	var gate_node: Node3D = view.arena.get_node("Gate")
	assert_true(gate_node.visible)
	var before: int = view.arena.get_child_count()
	view.render({"gate": 0.0, "players": {}, "teams": [], "times": []})
	assert_false(gate_node.visible, "a breached gate is gone")
	assert_eq(view.arena.get_child_count(), before + 2, "breach bursts + dusts once")
	view.render({"gate": 0.0, "players": {}, "teams": [], "times": []})
	assert_eq(view.arena.get_child_count(), before + 2, "staying breached is silent")


func test_capture_flip_bursts_at_the_core() -> void:
	view.render({"times": [-1.0, -1.0], "players": {}, "teams": []})
	var before: int = view.arena.get_child_count()
	view.render({"times": [17.5, -1.0], "players": {}, "teams": []})
	assert_eq(view.arena.get_child_count(), before + 1, "a capture = one burst")


func test_rig_follows_player_snapshot() -> void:
	view.render({"players": {0: [4.0, -2.0]}, "teams": [], "times": []})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 4.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


# --- Readable rework (#808) --------------------------------------------------


func test_fort_walls_and_banners_enclose_the_core() -> void:
	# Two side walls + a back wall, each carrying a team-colored banner strip.
	assert_eq(view._wall_banners.size(), 3, "the fort has side + back walls with banners")
	assert_not_null(view.arena.get_node("CorePlinth"))
	assert_not_null(view.arena.get_node("CoreCrystal"))


func test_batter_action_shakes_the_gate() -> void:
	var teams := [[0, 1], [2, 3]]
	# Seed the action counter (a mid-join must not replay), then bump it.
	(
		view
		. render(
			{
				"gate": 1.0,
				"players": {0: [0.0, FortSiege.GATE_Y, 0, FortSiege.Act.NONE, 0.0]},
				"teams": teams,
				"times": [-1.0, -1.0],
			}
		)
	)
	(
		view
		. render(
			{
				"gate": 0.9,
				"players": {0: [0.0, FortSiege.GATE_Y, 1, FortSiege.Act.BATTER, 0.0]},
				"teams": teams,
				"times": [-1.0, -1.0],
			}
		)
	)
	assert_gt(view._gate_shake, 0.0, "a batter swing kicks off a gate recoil")


func test_shove_cooldown_ring_shows_then_hides() -> void:
	var teams := [[0, 1], [2, 3]]
	view.render(
		{"players": {0: [0.0, 0.0, 0, FortSiege.Act.NONE, 0.8]}, "teams": teams, "times": []}
	)
	var ring := view.rig_for_slot(0).get_node_or_null(^"CooldownRing") as Node3D
	assert_not_null(ring, "a defender on cooldown shows a ring")
	assert_true(ring.visible)
	view.render(
		{"players": {0: [0.0, 0.0, 0, FortSiege.Act.NONE, 0.0]}, "teams": teams, "times": []}
	)
	assert_false(ring.visible, "the ring clears when the shove is ready")


## #1028: the crystal IS the relic — it rides over the thief when carried and
## drops low, flaring the loose tint, when shoved free.
func test_relic_crystal_follows_the_heist() -> void:
	(
		view
		. render(
			{
				"gate": 0.0,
				"capture": 0.2,
				"relic": [3.0, -4.0, FortSiege.RelicState.CARRIED, 0],
				"players": {},
				"teams": [],
				"times": [],
			}
		)
	)
	assert_almost_eq(view._crystal.position.x, 3.0, 0.001, "the crystal rides the thief")
	assert_almost_eq(view._crystal.position.y, view.RELIC_CARRY_HEIGHT, 0.001, "held overhead")
	(
		view
		. render(
			{
				"gate": 0.0,
				"capture": 0.4,
				"relic": [1.0, -2.5, FortSiege.RelicState.DROPPED, -1],
				"players": {},
				"teams": [],
				"times": [],
			}
		)
	)
	assert_almost_eq(
		view._crystal.position.y, view.RELIC_LOOSE_HEIGHT, 0.001, "loose on the ground"
	)
	assert_eq(view._crystal_material.emission, view.RELIC_LOOSE_COLOR, "and flaring urgent")


## The objective line answers "how do I defend?" and "what do I press?" per state.
func test_objective_prompt_is_state_driven() -> void:
	var teams := [[0, 1], [2, 3]]  # local slot 0 is on team 0
	view.render(
		{"phase": FortSiege.Phase.SIEGE, "attacking": 1, "gate": 1.0, "teams": teams, "times": []}
	)
	assert_string_contains(view._banner.text, "REPAIR", "a defender is told how to defend")
	view.render(
		{"phase": FortSiege.Phase.SIEGE, "attacking": 0, "gate": 1.0, "teams": teams, "times": []}
	)
	assert_string_contains(view._banner.text, "BATTER", "an attacker is told to batter")


## #1028: post-breach prompts follow the relic — the thief is told to run,
## the defenders to stop the thief or return the loose relic.
func test_heist_prompts_follow_the_relic() -> void:
	var teams := [[0, 1], [2, 3]]
	(
		view
		. render(
			{
				"phase": FortSiege.Phase.SIEGE,
				"attacking": 0,
				"gate": 0.0,
				"relic": [0.0, -5.0, FortSiege.RelicState.CARRIED, 0],
				"teams": teams,
				"times": [],
			}
		)
	)
	assert_string_contains(view._banner.text, "RUN THE RELIC OUT", "the thief is told to run")
	(
		view
		. render(
			{
				"phase": FortSiege.Phase.SIEGE,
				"attacking": 1,
				"gate": 0.0,
				"relic": [0.0, -5.0, FortSiege.RelicState.CARRIED, 2],
				"teams": teams,
				"times": [],
			}
		)
	)
	assert_string_contains(view._banner.text, "STOP THE THIEF", "defenders are told to shove")
	(
		view
		. render(
			{
				"phase": FortSiege.Phase.SIEGE,
				"attacking": 1,
				"gate": 0.0,
				"relic": [2.0, -4.0, FortSiege.RelicState.DROPPED, -1],
				"teams": teams,
				"times": [],
			}
		)
	)
	assert_string_contains(view._banner.text, "send it home", "defenders are told to return it")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_almost_eq(view.gate, 1.0, 0.001)
