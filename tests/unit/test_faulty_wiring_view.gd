extends GutTest
## Faulty Wiring client view (M10-16): a darkened arena with a ring of wire nodes
## that glow toward green as they fill, a per-client role banner fed by the
## private snapshot (#254), and a lit-wire tally. Renders the shared snapshot.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/faulty_wiring/faulty_wiring_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob", 2: "Cass", 3: "Dev"}, 0)


func _snapshot(lit: Array) -> Dictionary:
	var wires: Array = []
	var fixed := 0
	for w in lit.size():
		var angle := TAU * w / lit.size()
		var on: bool = lit[w]
		wires.append([cos(angle) * 4.4, sin(angle) * 4.4, 1 if on else 0, 1.0 if on else 0.0])
		if on:
			fixed += 1
	return {
		"players": {0: [0.0, 0.0], 1: [1.0, 0.0]},
		"wires": wires,
		"fixed": fixed,
		"total": lit.size(),
	}


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"faulty_wiring"),
		"res://src/minigames/faulty_wiring/faulty_wiring_view.tscn"
	)
	MinigameCatalog.clear()


func test_builds_darkness_and_a_wire_ring() -> void:
	view.render(_snapshot([false, false, false, false, false]))
	assert_not_null(view.arena.get_node("Darkness"), "the arena is dimmed")
	assert_not_null(view.arena.get_node("Wire0"))
	assert_eq(view._wire_nodes.size(), 5, "one node per wire")


func test_role_banner_names_only_this_clients_role() -> void:
	view.private_state = {"saboteur": true}
	view.render(_snapshot([false, false, false, false, false]))
	assert_string_contains(view.get_node("RoleLabel").text, "SABOTEUR")
	view.private_state = {}
	view.render(_snapshot([false, false, false, false, false]))
	assert_string_contains(view.get_node("RoleLabel").text, "CREW")


func test_a_lit_wire_glows_brighter_than_a_dead_one() -> void:
	view.render(_snapshot([true, false, false, false, false]))
	assert_gt(
		view._wire_materials[0].emission_energy_multiplier,
		view._wire_materials[1].emission_energy_multiplier,
		"the lit wire glows brightest"
	)


func test_tally_counts_lit_wires() -> void:
	view.render(_snapshot([true, true, false, false, false]))
	assert_string_contains(view.get_node("TallyLabel").text, "2 / 5")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_not_null(view.arena.get_node("Darkness"))
