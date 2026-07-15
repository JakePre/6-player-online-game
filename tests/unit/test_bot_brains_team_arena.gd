extends GutTest
## Team / arena bot brains (M19-02, #686): rumble_ring, heist_night,
## cart_push, relay_sprint, basket_brawl — steering assertions on crafted
## snapshots. Split from test_bot_brains.gd per gdlint's public-method cap
## (same precedent as test_match_controller_finale_only.gd).


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


# --- rumble_ring ------------------------------------------------------------------


func test_rumble_ring_brain_swings_a_rival_in_range() -> void:
	var brain := BotBrains.brain_for(&"rumble_ring", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0], 1: [1.0, 0.0, 3, 0, 0, 0.0, -1.0, 0.0]}
	}
	var intent := brain.think(_play_state("rumble_ring", game), {})
	assert_true(bool(intent.get("attack", false)), "a rival 1.0 away is inside SWING_RANGE")


func test_rumble_ring_brain_approaches_a_distant_rival() -> void:
	var brain := BotBrains.brain_for(&"rumble_ring", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0], 1: [6.0, 0.0, 3, 0, 0, 0.0, -1.0, 0.0]}
	}
	var intent := brain.think(_play_state("rumble_ring", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "closes the distance instead of attacking")
	assert_false(intent.has("attack"))


# --- heist_night ------------------------------------------------------------------


func test_heist_night_brain_seeks_a_coin_during_light() -> void:
	var brain := BotBrains.brain_for(&"heist_night", 0, 1)
	var game := {"dark": false, "players": {0: [0.0, 0.0]}, "coins": [[4.0, 0.0]]}
	var intent := brain.think(_play_state("heist_night", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "heads for the visible coin")


func test_heist_night_brain_coasts_the_last_light_heading_through_the_dark() -> void:
	var brain := BotBrains.brain_for(&"heist_night", 0, 1)
	brain.think(
		_play_state(
			"heist_night", {"dark": false, "players": {0: [0.0, 0.0]}, "coins": [[4.0, 0.0]]}
		),
		{}
	)
	# No player positions at all during dark — not even our own.
	var intent := brain.think(_play_state("heist_night", {"dark": true, "players": {}}), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "keeps heading the direction it was already going")


# --- cart_push --------------------------------------------------------------------


func test_cart_push_brain_pusher_heads_to_its_own_cart() -> void:
	var brain := BotBrains.brain_for(&"cart_push", 0, 1)
	# Team 0's cart sits at (-TRACK_HALF, -LANE_Y); a small team means no
	# saboteur, so slot 0 walks over to push.
	var game := {"players": {0: [0.0, 0.0, 0]}, "teams": [[0], [1]], "carts": [0.0, 0.0]}
	var intent := brain.think(_play_state("cart_push", game), {})
	assert_lt(float(intent.get("mx", 0.0)), 0.0, "heads left toward its own cart")


func test_cart_push_brain_at_its_cart_alternates_the_push() -> void:
	var brain := BotBrains.brain_for(&"cart_push", 0, 1)
	var cart := Vector2(-CartPush.TRACK_HALF, -CartPush.LANE_Y)
	var game := {"players": {0: [cart.x, cart.y, 0]}, "teams": [[0], [1]], "carts": [0.0, 0.0]}
	var first := brain.think(_play_state("cart_push", game), {})
	assert_true(first.has("push"), "mashes once parked at the cart")
	var second := brain.think(_play_state("cart_push", game), {})
	assert_ne(int(second.push), int(first.push), "flips the phase so the sim sees an alternation")


func test_cart_push_brain_saboteur_shoves_an_enemy_at_the_rival_cart() -> void:
	# Big enough teams that the top slot peels off to sabotage the enemy lane.
	var brain := BotBrains.brain_for(&"cart_push", 2, 1)
	var enemy_cart := Vector2(-CartPush.TRACK_HALF, CartPush.LANE_Y)
	var game := {
		"players": {2: [enemy_cart.x, enemy_cart.y - 0.4, 0], 3: [enemy_cart.x, enemy_cart.y, 0]},
		"teams": [[0, 1, 2], [3, 4, 5]],
		"carts": [0.0, 0.0],
	}
	var intent := brain.think(_play_state("cart_push", game), {})
	assert_true(bool(intent.get("shove", false)), "an enemy 0.4 away is inside SHOVE_RANGE")


func test_cart_push_brain_staggered_sends_nothing() -> void:
	var brain := BotBrains.brain_for(&"cart_push", 0, 1)
	var flags := CartPush.FLAG_STAGGERED
	var game := {"players": {0: [0.0, 0.0, flags]}, "teams": [[0], [1]], "carts": [0.0, 0.0]}
	assert_eq(brain.think(_play_state("cart_push", game), {}), {})


# --- relay_sprint -----------------------------------------------------------------


func test_relay_sprint_brain_benched_runner_sends_nothing() -> void:
	var brain := BotBrains.brain_for(&"relay_sprint", 1, 1)
	var game := {"lanes": {0: [[0, 1], 0, 5.0, 0.0, false]}, "track_len": 24.0, "hazards": []}
	assert_eq(brain.think(_play_state("relay_sprint", game), {}), {})


func test_relay_sprint_brain_active_runner_runs_forward() -> void:
	var brain := BotBrains.brain_for(&"relay_sprint", 0, 1)
	var game := {"lanes": {0: [[0, 1], 0, 5.0, 0.0, false]}, "track_len": 24.0, "hazards": []}
	var intent := brain.think(_play_state("relay_sprint", game), {})
	assert_almost_eq(float(intent.get("mx", 0.0)), 1.0, 0.001, "flat out with nothing ahead")


func test_relay_sprint_brain_dodges_an_imminent_sweeper() -> void:
	var brain := BotBrains.brain_for(&"relay_sprint", 0, 1)
	# A sweeper 1.5 units ahead swinging right at our current lateral (0.0).
	var game := {
		"lanes": {0: [[0], 0, 5.5, 0.0, false]}, "track_len": 24.0, "hazards": [[7.0, 0.0]]
	}
	var intent := brain.think(_play_state("relay_sprint", game), {})
	assert_ne(float(intent.get("my", 0.0)), 0.0, "swerves off the sweeper's lateral line")


func test_relay_sprint_brain_dodges_the_sweeper_s_predicted_position_not_its_stale_one() -> void:
	# #715/#768 follow-up: reacting to the sweeper's snapshot position (not
	# where it'll be on arrival) is what let bots loop into it forever — live
	# testing confirmed a lead estimate fixes it. Crafted so the sweeper is
	# crossing zero: it's slightly negative on both polls, but closing fast
	# enough that the LEAD estimate is positive — a naive "dodge away from
	# current" brain would swerve the opposite way from a predictive one.
	var brain := BotBrains.brain_for(&"relay_sprint", 0, 1)
	var lane := [[0], 0, 5.0, 0.0, false]
	# First poll seeds the velocity estimate (progress unchanged is fine — the
	# brain only tracks the hazard's own lateral history, not our motion).
	brain.think(
		_play_state(
			"relay_sprint", {"lanes": {0: lane}, "track_len": 24.0, "hazards": [[7.0, -0.3]]}
		),
		{}
	)
	# Second poll: the sweeper moved -0.3 -> -0.1 in one ~0.25s interval — a
	# closing velocity that projects past zero by our estimated arrival.
	var intent := brain.think(
		_play_state(
			"relay_sprint", {"lanes": {0: lane}, "track_len": 24.0, "hazards": [[7.0, -0.1]]}
		),
		{}
	)
	assert_lt(
		float(intent.get("my", 0.0)),
		0.0,
		"dodges away from the predicted (positive) position, not the stale negative snapshot"
	)


func test_relay_sprint_brain_finished_team_sends_nothing() -> void:
	var brain := BotBrains.brain_for(&"relay_sprint", 0, 1)
	var game := {"lanes": {0: [[0], 0, 24.0, 0.0, true]}, "track_len": 24.0, "hazards": []}
	assert_eq(brain.think(_play_state("relay_sprint", game), {}), {})


# --- basket_brawl -------------------------------------------------------------


func test_basket_brawl_brain_carrier_drives_to_the_enemy_hoop() -> void:
	var brain := BotBrains.brain_for(&"basket_brawl", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 1]},
		"ball": [0.0, 0.0, 0],
		"teams": [[0], [1]],
		"hoops": [[-8.0, 0.0], [8.0, 0.0]],
	}
	var intent := brain.think(_play_state("basket_brawl", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "team 0 attacks the +x hoop")


func test_basket_brawl_brain_chases_a_loose_ball() -> void:
	var brain := BotBrains.brain_for(&"basket_brawl", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0]},
		"ball": [3.0, 0.0, -1],
		"teams": [[0], [1]],
		"hoops": [[-8.0, 0.0], [8.0, 0.0]],
	}
	var intent := brain.think(_play_state("basket_brawl", game), {})
	assert_gt(float(intent.get("mx", 0.0)), 0.5, "chases the loose ball at +3")


func test_basket_brawl_brain_hounds_an_enemy_carrier_and_shoves_in_range() -> void:
	var brain := BotBrains.brain_for(&"basket_brawl", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0], 1: [1.0, 0.0, 1]},
		"ball": [1.0, 0.0, 1],
		"teams": [[0], [1]],
		"hoops": [[-8.0, 0.0], [8.0, 0.0]],
	}
	var intent := brain.think(_play_state("basket_brawl", game), {})
	assert_true(bool(intent.get("act", false)), "the enemy carrier 1.0 away is inside SHOVE_RADIUS")


func test_basket_brawl_brain_supports_a_teammate_carrier() -> void:
	var brain := BotBrains.brain_for(&"basket_brawl", 0, 1)
	var game := {
		"players": {0: [0.0, 0.0, 0], 1: [-1.0, 0.0, 1]},
		"ball": [-1.0, 0.0, 1],
		"teams": [[0, 1], [2]],
		"hoops": [[-8.0, 0.0], [8.0, 0.0]],
	}
	var intent := brain.think(_play_state("basket_brawl", game), {})
	assert_gt(
		float(intent.get("mx", 0.0)), 0.0, "runs support toward the attack hoop, not the ball"
	)
