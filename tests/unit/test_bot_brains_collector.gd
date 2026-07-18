extends GutTest
## Collector / skill bot brains (M19-02, #686): bomb_courier, fish_frenzy,
## nom_arena, treasure_divers, musical_platforms — steering assertions on
## crafted snapshots. Split from test_bot_brains.gd per gdlint's public-method
## cap (same precedent as test_match_controller_finale_only.gd).


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


# --- bomb_courier ---------------------------------------------------------------


func test_bomb_courier_brain_empty_handed_seeks_the_nearest_package() -> void:
	var brain := BotBrains.brain_for(&"bomb_courier", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0, -1.0, 0]}, "pile": [[7, 5.0, 0.0, 6.0], [9, -9.0, 0.0, 5.0]]
	}
	var intent := brain.think(_play_state("bomb_courier", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "the package 5.0 away beats the one at -9.0")


func test_bomb_courier_brain_carrying_a_healthy_fuse_heads_to_the_depot() -> void:
	var brain := BotBrains.brain_for(&"bomb_courier", 0, 1)
	var game := {"players": {0: [0.0, 0.0, 0, 5.0, 0]}}
	var intent := brain.think(_play_state("bomb_courier", game), {})
	var to_depot := BombCourier.DEPOT_POS.normalized()
	var heading := Vector2(float(intent.get("mx", 0.0)), float(intent.get("my", 0.0)))
	assert_gt(heading.dot(to_depot), 0.5, "heads for the depot with plenty of fuse left")
	assert_false(intent.has("dash"))


func test_bomb_courier_brain_dumps_a_dying_package_on_a_close_rival() -> void:
	var brain := BotBrains.brain_for(&"bomb_courier", 0, 1)
	var game := {"players": {0: [0.0, 0.0, 0, 0.5, 0], 1: [1.0, 0.0, 0, -1.0, 0]}}
	var intent := brain.think(_play_state("bomb_courier", game), {})
	assert_true(bool(intent.get("dash", false)), "a rival 1.0 away with a dying fuse: dump it")


func test_bomb_courier_brain_defuses_when_no_rival_and_fuse_is_critical() -> void:
	var brain := BotBrains.brain_for(&"bomb_courier", 0, 1)
	var game := {"players": {0: [0.0, 0.0, 0, 0.5, 0]}}
	var intent := brain.think(_play_state("bomb_courier", game), {})
	var to_defuse := BombCourier.DEFUSE_POS.normalized()
	var heading := Vector2(float(intent.get("mx", 0.0)), float(intent.get("my", 0.0)))
	assert_gt(heading.dot(to_defuse), 0.5, "no rival in reach: cut losses at the defuse zone")


# --- fish_frenzy ----------------------------------------------------------------


func test_fish_frenzy_brain_switches_to_the_soonest_fish_lane() -> void:
	var brain := BotBrains.brain_for(&"fish_frenzy", 0, 1)
	var game := {"players": {0: [1, 0, 0]}, "fish": [[2, 0.9], [0, 0.15]], "swim_sec": 1.8}
	var intent := brain.think(_play_state("fish_frenzy", game), {})
	assert_eq(int(intent.get("lane", -1)), 0, "the fish 0.15s out beats the one 0.9s out")


func test_fish_frenzy_brain_idle_with_no_fish_incoming() -> void:
	var brain := BotBrains.brain_for(&"fish_frenzy", 0, 1)
	var game := {"players": {0: [1, 0, 0]}, "fish": [], "swim_sec": 1.8}
	assert_eq(brain.think(_play_state("fish_frenzy", game), {}), {})


# --- nom_arena ------------------------------------------------------------------


func test_nom_arena_brain_flees_a_bigger_blob() -> void:
	var brain := BotBrains.brain_for(&"nom_arena", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 8.0, 0], 1: [1.0, 0.0, 20.0, 0]},
		"dots": [],
		"boundary": 12.0,
	}
	var intent := brain.think(_play_state("nom_arena", game), {})
	assert_lt(float(intent.get("mx", 0.0)), 0.0, "flees the much bigger blob at +1")


func test_nom_arena_brain_lunges_at_a_smaller_blob() -> void:
	var brain := BotBrains.brain_for(&"nom_arena", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 8.0, 0], 1: [1.0, 0.0, 3.0, 0]}, "dots": [], "boundary": 12.0
	}
	var intent := brain.think(_play_state("nom_arena", game), {})
	assert_true(bool(intent.get("lunge", false)), "a much smaller blob in reach: lunge")
	assert_gt(float(intent.get("mx", 0.0)), 0.0, "lunges toward it")


func test_nom_arena_brain_seeks_a_dot_with_nothing_else_around() -> void:
	var brain := BotBrains.brain_for(&"nom_arena", 0, 1)
	var game := {"players": {0: [0.0, 0.0, 8.0, 0]}, "dots": [[3.0, 0.0]], "boundary": 12.0}
	var intent := brain.think(_play_state("nom_arena", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.0, "heads for the only dot")
	assert_false(intent.has("lunge"))


func test_nom_arena_brain_returns_inside_a_closed_boundary() -> void:
	var brain := BotBrains.brain_for(&"nom_arena", 0, 1)
	var game := {"players": {0: [7.5, 0.0, 8.0, 0]}, "dots": [], "boundary": 8.0}
	var intent := brain.think(_play_state("nom_arena", game), {})
	assert_lt(float(intent.get("mx", 0.0)), 0.0, "outside the shrunk ring: head back to center")


## #954: when we're strictly nearest the power pellet, contest it.
func test_nom_arena_brain_contests_the_power_pellet_when_closest() -> void:
	var brain := BotBrains.brain_for(&"nom_arena", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 8.0, 0, 0.0], 1: [9.0, 0.0, 8.0, 0, 0.0]},
		"dots": [[-4.0, 0.0]],
		"pellet": [3.0, 0.0],
		"boundary": 12.0,
	}
	var intent := brain.think(_play_state("nom_arena", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.0, "closest to the pellet: go for it, not the dot")


## #954: a frenzied bot chases the nearest rival regardless of size and bites.
func test_nom_arena_brain_frenzied_chases_and_bites_any_rival() -> void:
	var brain := BotBrains.brain_for(&"nom_arena", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 8.0, 0, NomArena.FRENZY_SEC], 1: [1.0, 0.0, 30.0, 0, 0.0]},
		"dots": [],
		"boundary": 12.0,
	}
	var intent := brain.think(_play_state("nom_arena", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.0, "frenzied: chase the bigger rival, not flee it")
	assert_true(bool(intent.get("lunge", false)), "bites when in reach")


## #954: a rival flees a frenzied blob even when it is smaller than them.
func test_nom_arena_brain_flees_a_frenzied_rival() -> void:
	var brain := BotBrains.brain_for(&"nom_arena", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 30.0, 0, 0.0], 1: [1.0, 0.0, 8.0, 0, NomArena.FRENZY_SEC]},
		"dots": [],
		"boundary": 12.0,
	}
	var intent := brain.think(_play_state("nom_arena", game), {})
	assert_lt(float(intent.get("mx", 0.0)), 0.0, "flees the frenzied blob even though it's smaller")


# --- treasure_divers ------------------------------------------------------------


func test_treasure_divers_brain_dives_for_the_nearest_treasure() -> void:
	var brain := BotBrains.brain_for(&"treasure_divers", 0, 1)
	var game := {"players": {0: [0.0, 0.0, 0, 0, 1.0, 0.0]}, "treasure": [[3.0, 0.0], [-9.0, 0.0]]}
	var intent := brain.think(_play_state("treasure_divers", game), {})
	assert_true(bool(intent.get("dive", false)))
	assert_gt(float(intent.get("mx", 0.0)), 0.0, "the treasure at +3 beats the one at -9")


func test_treasure_divers_brain_surfaces_on_low_air() -> void:
	var brain := BotBrains.brain_for(&"treasure_divers", 0, 1)
	var game := {"players": {0: [0.0, 0.0, 0, 1, 0.1, 0.0]}, "treasure": [[3.0, 0.0]]}
	var intent := brain.think(_play_state("treasure_divers", game), {})
	assert_false(bool(intent.get("dive", true)), "air critical: surface")


func test_treasure_divers_brain_stays_surfaced_until_air_recovers() -> void:
	var brain := BotBrains.brain_for(&"treasure_divers", 0, 1)
	# Trip the surfacing latch, then poll again with partially recovered air —
	# still below RESUME_AIR, so the hysteresis band must hold it surfaced.
	brain.think(
		_play_state(
			"treasure_divers", {"players": {0: [0.0, 0.0, 0, 1, 0.1, 0.0]}, "treasure": []}
		),
		{}
	)
	var intent := brain.think(
		_play_state(
			"treasure_divers", {"players": {0: [0.0, 0.0, 0, 0, 0.3, 0.0]}, "treasure": []}
		),
		{}
	)
	assert_false(bool(intent.get("dive", true)), "0.3 air is still under RESUME_AIR (0.6)")


# --- musical_platforms ------------------------------------------------------------


func test_musical_platforms_brain_races_the_nearest_free_platform() -> void:
	var brain := BotBrains.brain_for(&"musical_platforms", 0, 1)
	var game := {
		"phase": MusicalPlatforms.Phase.STOP,
		"players": {0: [0.0, 0.0]},
		"platforms": [[5.0, 0.0, 1], [-2.0, 0.0, -1]],
	}
	var intent := brain.think(_play_state("musical_platforms", game), {})
	assert_lt(float(intent.get("mx", 0.0)), 0.0, "the free platform is at -2, the other is claimed")


func test_musical_platforms_brain_holds_once_it_owns_a_platform() -> void:
	var brain := BotBrains.brain_for(&"musical_platforms", 0, 1)
	var game := {
		"phase": MusicalPlatforms.Phase.STOP,
		"players": {0: [5.0, 0.0]},
		"platforms": [[5.0, 0.0, 0]],
	}
	var intent := brain.think(_play_state("musical_platforms", game), {})
	assert_eq(intent, {"mx": 0.0, "my": 0.0})


func test_musical_platforms_brain_wanders_during_music() -> void:
	var brain := BotBrains.brain_for(&"musical_platforms", 0, 1)
	var game := {"phase": MusicalPlatforms.Phase.MUSIC, "players": {0: [0.0, 0.0]}, "platforms": []}
	var intent := brain.think(_play_state("musical_platforms", game), {})
	var heading := Vector2(float(intent.get("mx", 0.0)), float(intent.get("my", 0.0)))
	assert_gt(heading.length(), 0.1, "picks a wander target rather than standing still")
