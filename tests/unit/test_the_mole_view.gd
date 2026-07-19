extends GutTest
## The Mole client view (M10-13): renders replicated snapshots in the shared
## iso-arena; the local secret role comes only from private_state (#254).

var view: MinigameView
var _saved_show_names := false


func before_each() -> void:
	_saved_show_names = MinigameView.show_names
	MinigameView.show_names = true  # #580: names off by default; this suite tests the name itself
	var scene: PackedScene = load("res://src/minigames/the_mole/the_mole_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob", 2: "Carol", 3: "Dave"}, 0)


func after_each() -> void:
	MinigameView.show_names = _saved_show_names


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


## #958: the lights-out vignette shows for the crew, hides for the mole (full
## vision, private-side), and only while the snapshot says the lights are out.
func test_blackout_overlay_shows_for_crew_hides_for_mole() -> void:
	var dark := {
		"phase": TheMole.Phase.WORK,
		"players": {0: [0.0, 0.0, 0]},
		"cells": [],
		"progress": 0,
		"target": 10,
		"blackout": true,
	}
	view.render(dark)
	assert_true(view._blackout_overlay.visible, "the crew sees the dark")
	view.private_state = {"role": "mole"}
	view.render(dark)
	assert_false(view._blackout_overlay.visible, "the mole keeps full vision")
	view.private_state = {}
	var lit := dark.duplicate()
	lit["blackout"] = false
	view.render(lit)
	assert_false(view._blackout_overlay.visible, "lights on -> no overlay")


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


## #801: during voting, each player who's cast a vote gets a check on their
## nameplate (participation only — never who they accused).
func test_vote_phase_marks_who_has_voted() -> void:
	(
		view
		. render(
			{
				"phase": TheMole.Phase.VOTE,
				"players": {0: [0.0, 0.0, 0], 1: [1.0, 0.0, 0], 2: [2.0, 0.0, 0], 3: [3.0, 0.0, 0]},
				"cells": [],
				"votes_in": 2,
				"voted": [1, 3],
			}
		)
	)
	assert_true(view.rig_for_slot(1).display_name.contains("✓"), "a voter is checked")
	assert_true(view.rig_for_slot(3).display_name.contains("✓"))
	assert_false(view.rig_for_slot(0).display_name.contains("✓"), "a non-voter is not")


## #801: the aim chevron floats over the suspect the local player is accusing.
func test_vote_aim_marker_points_at_the_accused() -> void:
	view._my_vote = 2
	(
		view
		. render(
			{
				"phase": TheMole.Phase.VOTE,
				"players": {0: [0.0, 0.0, 0], 2: [5.0, -3.0, 0]},
				"cells": [],
				"voted": [],
			}
		)
	)
	assert_true(view._aim_marker.visible, "the aim marker shows during voting")
	assert_almost_eq(view._aim_marker.position.x, 5.0, 0.01, "over the accused suspect")
	assert_almost_eq(view._aim_marker.position.z, -3.0, 0.01)


func _vote_arrow_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child.name.begins_with("VoteArrow"):
			count += 1
	return count


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


## #801: the reveal draws the accusation web — an arrow from each voter to whom
## they accused — flags the mole's rig, and counts who called it.
func test_reveal_draws_the_accusation_web() -> void:
	(
		view
		. render(
			{
				"phase": TheMole.Phase.REVEAL,
				"players": {0: [0.0, 0.0, 0], 1: [1.0, 0.0, 0], 2: [2.0, 0.0, 0], 3: [3.0, 0.0, 0]},
				"cells": [],
				# mole is 2; slots 0 and 3 accused the mole, slot 1 accused slot 0.
				"reveal": {"mole": 2, "caught": true, "success": true, "votes": {0: 2, 1: 0, 3: 2}},
			}
		)
	)
	assert_eq(_vote_arrow_count(), 3, "one arrow per cast vote")
	assert_true(view.rig_for_slot(2).display_name.contains("THE MOLE"), "the mole is flagged")
	assert_true(
		view.rig_for_slot(0).display_name.contains("called it"), "a correct accuser is noted"
	)
	assert_true(view._banner.text.contains("CAUGHT by 2"), "the banner counts the accusers")


## The web is built once, not re-spawned every reveal snapshot.
func test_reveal_web_builds_once() -> void:
	var snap := {
		"phase": TheMole.Phase.REVEAL,
		"players": {0: [0.0, 0.0, 0], 2: [2.0, 0.0, 0]},
		"cells": [],
		"reveal": {"mole": 2, "caught": false, "success": false, "votes": {0: 2}},
	}
	view.render(snap)
	var after_first := _vote_arrow_count()
	view.render(snap)
	assert_eq(_vote_arrow_count(), after_first, "the accusation web isn't re-spawned each frame")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.progress, 0)
