extends GutTest
## The Mole client view (M10-13): renders replicated snapshots in the shared
## iso-arena; the local secret role comes only from private_state (#254).

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/the_mole/the_mole_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob", 2: "Carol", 3: "Dave"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"the_mole"),
		"res://src/minigames/the_mole/the_mole_view.tscn"
	)


func test_setup_builds_arena_and_machine() -> void:
	assert_not_null(view.arena)
	assert_not_null(view.rig_for_slot(0))
	assert_not_null(view.arena.get_node("Machine"))


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"phase": TheMole.Phase.WORK,
				"phase_left": 30.0,
				"progress": 4,
				"target": 10,
				"sparked": false,
				"players": {0: [1.0, 2.0, 0]},
				"cells": [[3.0, 3.0]],
				"votes_in": 0,
			}
		)
	)
	assert_eq(view.progress, 4)
	assert_eq(view.players.size(), 1)
	assert_eq(view.cells.size(), 1)
	view.render({"players": {}, "cells": []})
	assert_eq(view.players.size(), 0, "each snapshot fully replaces the last")


func test_mole_banner_only_with_private_role() -> void:
	view.render({"players": {}, "cells": [], "progress": 0, "target": 10})
	var banner: Label = view._banner
	assert_false(banner.text.contains("MOLE"), "no private role, no mole banner")
	view.private_state = {"role": "mole"}
	view.render({"players": {}, "cells": [], "progress": 0, "target": 10})
	assert_true(banner.text.contains("MOLE"), "the private role flips the banner")


func test_spark_bursts_on_rising_edge_only() -> void:
	view.render({"players": {}, "cells": [], "sparked": false})
	var before: int = view.arena.get_child_count()
	view.render({"players": {}, "cells": [], "sparked": true})
	assert_eq(view.arena.get_child_count(), before + 1, "sabotage tell bursts once")
	view.render({"players": {}, "cells": [], "sparked": true})
	assert_eq(view.arena.get_child_count(), before + 1, "a held spark stays quiet")


func test_rig_follows_player_snapshot() -> void:
	view.render({"players": {0: [4.0, -2.0, 0]}, "cells": []})
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_almost_eq(rig.position.x, 4.0, 0.001)
	assert_almost_eq(rig.position.z, -2.0, 0.001)


func test_reveal_banner_names_the_mole() -> void:
	(
		view
		. render(
			{
				"phase": TheMole.Phase.REVEAL,
				"players": {},
				"cells": [],
				"reveal": {"mole": 2, "caught": true, "success": false, "votes": {}},
			}
		)
	)
	assert_true((view._banner as Label).text.contains("Carol"), "the reveal names the mole")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.progress, 0)
