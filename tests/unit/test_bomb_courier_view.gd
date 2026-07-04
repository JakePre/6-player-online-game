extends GutTest
## Bomb Courier client view (M10-15): couriers ferry fuse-lit crates from pile to
## depot. The M13-24 FX pass adds a lit-fuse spark trail off carried bombs, a
## handoff burst when a courier takes possession, and a detonation blast on a
## stagger — all verified by counting the self-freeing CPUParticles3D the shared
## ArenaFX wrappers spawn under the arena.

const SPARK_INTERVAL_STEP := 0.25  # comfortably above the view's SPARK_INTERVAL

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/bomb_courier/bomb_courier_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


## players[slot] = [x, y, score, fuse, staggered]; fuse < 0 means empty-handed.
func _snapshot(fuse: float, staggered: int) -> Dictionary:
	return {
		"players":
		{
			0: [0.0, 0.0, 0, fuse, staggered],
			1: [2.0, 0.0, 0, -1.0, 0],
		},
		"pile": [],
	}


func _particle_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"bomb_courier"),
		"res://src/minigames/bomb_courier/bomb_courier_view.tscn"
	)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_not_null(view.arena.get_node("Pile"))


## M13-24: taking possession pops a handoff burst; an unchanged carry state does not.
func test_taking_a_bomb_pops_a_handoff_burst() -> void:
	view.render(_snapshot(-1.0, 0))
	var before := _particle_count()
	view.render(_snapshot(5.0, 0))
	assert_gt(_particle_count(), before, "receiving a bomb flashes a handoff burst")
	# Still holding on the next snapshot — no fresh burst.
	var steady := _particle_count()
	view.render(_snapshot(4.5, 0))
	assert_eq(_particle_count(), steady, "an ongoing carry does not re-burst")


## M13-24: a carried bomb spits fuse sparks on its cadence.
func test_carried_bomb_trails_fuse_sparks() -> void:
	view.render(_snapshot(5.0, 0))
	var before := _particle_count()
	view._process(SPARK_INTERVAL_STEP)
	assert_gt(_particle_count(), before, "the lit fuse trails a spark")


## M13-24: a fresh stagger (detonation) pops a blast; a steady state does not.
func test_detonation_pops_a_blast() -> void:
	view.render(_snapshot(-1.0, 0))
	var before := _particle_count()
	view.render(_snapshot(-1.0, 1))
	assert_gt(_particle_count(), before, "a detonation blasts at the courier")
