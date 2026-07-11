extends GutTest
## Basket Brawl (PHASE2.md $4 #26): pickup, carry slowdown, passing,
## shove-fumbles, dunks, and team ranking.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3]) -> BasketBrawl:
	var game := BasketBrawl.new()
	game.meta = BasketBrawl.make_meta()
	game.setup(player_slots, 42)
	return game


func test_meta_catalog_and_even_rule() -> void:
	var meta := BasketBrawl.make_meta()
	assert_eq(meta.id, &"basket_brawl")
	assert_eq(meta.category, MinigameMeta.Category.TEAM)
	assert_eq(meta.max_players, 8)
	assert_true(meta.even_players, "never drafted at 3 or 5 (#178)")
	assert_false(meta.control_spec.is_empty(), "ships a #832 structured control spec")
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_true(MinigameCatalog.instantiate(&"basket_brawl") is BasketBrawl)
	MinigameCatalog.clear()


## No-crowd fairness (M15 8-cap, ADR 003 addendum): 4v4 splits evenly and
## every spawn stays within the arena.
func test_setup_splits_four_v_four_within_arena_at_eight_players() -> void:
	var player_slots: Array[int] = []
	for i in 8:
		player_slots.append(i)
	var game := _game(player_slots)
	assert_eq((game.teams[0] as Array).size(), 4)
	assert_eq((game.teams[1] as Array).size(), 4)
	for slot in 8:
		var pos: Vector2 = game.positions[slot]
		assert_lt(absf(pos.y), BasketBrawl.ARENA_HALF, "spawn row stays inside the arena")


func test_setup_splits_teams_and_centers_ball() -> void:
	var game := _game()
	assert_eq(game.teams[0].size(), 2)
	assert_eq(game.teams[1].size(), 2)
	assert_true(game.team_mode)
	assert_eq(game.ball_pos, Vector2.ZERO)
	assert_eq(game.holder, -1)


func test_proximity_catch_and_carry_slowdown() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2.ZERO
	game.tick(TICK)
	assert_eq(game.holder, slot, "standing on the ball picks it up")
	# Carriers crawl.
	game.positions[slot] = Vector2(0.0, 0.0)
	game.handle_input(slot, {"mx": 1.0, "my": 0.0})
	game.tick(TICK)
	assert_lt(
		(game.positions[slot] as Vector2).x,
		BasketBrawl.MOVE_SPEED * TICK * 0.8,
		"carrying is slower"
	)


func test_pass_flies_toward_teammate_and_is_catchable() -> void:
	var game := _game()
	var passer: int = game.teams[0][0]
	var mate: int = game.teams[0][1]
	game.positions[passer] = Vector2.ZERO
	game.tick(TICK)
	assert_eq(game.holder, passer)
	game.positions[mate] = Vector2(4.0, 0.0)
	game.handle_input(passer, {"act": true})
	assert_eq(game.holder, -1, "pass releases the ball")
	assert_gt(game.ball_vel.x, 0.0, "flying toward the teammate")
	# Move the passer away so the mate is the only catcher on the path.
	game.positions[passer] = Vector2(-8.0, -8.0)
	for _i in 30:
		game.tick(TICK)
	assert_eq(game.holder, mate, "teammate catches the pass")


func test_shove_pops_the_ball_loose() -> void:
	var game := _game()
	var carrier: int = game.teams[0][0]
	var shover: int = game.teams[1][0]
	game.positions[carrier] = Vector2.ZERO
	game.tick(TICK)
	assert_eq(game.holder, carrier)
	game.positions[shover] = Vector2(0.5, 0.0)
	game.handle_input(shover, {"act": true})
	assert_eq(game.holder, -1, "shove fumbles the carrier")
	assert_gt(float(game.shove_cooldowns[shover]), 0.0, "shove starts its cooldown")


func test_teammate_shove_does_nothing() -> void:
	var game := _game()
	var carrier: int = game.teams[0][0]
	var mate: int = game.teams[0][1]
	game.positions[carrier] = Vector2.ZERO
	game.tick(TICK)
	game.positions[mate] = Vector2(0.5, 0.0)
	game.handle_input(mate, {"act": true})
	assert_eq(game.holder, carrier, "no friendly fumbles")


func test_dunk_scores_and_resets_ball() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2.ZERO
	game.tick(TICK)
	assert_eq(game.holder, slot)
	game.positions[slot] = game.attack_hoop(slot)
	game.tick(TICK)
	assert_eq(int(game.scores[0]), 1, "dunk scores for the carrier's team")
	assert_eq(game.holder, -1)
	assert_eq(game.ball_pos, Vector2.ZERO, "ball resets to center")


func test_own_hoop_never_scores() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2.ZERO
	game.tick(TICK)
	game.positions[slot] = -game.attack_hoop(slot)
	game.tick(TICK)
	assert_eq(int(game.scores[0]), 0, "camping your own hoop does nothing")
	assert_eq(game.holder, slot)


func test_ranking_by_team_score_ties_group() -> void:
	var game := _game()
	game.scores = [2, 1]
	assert_eq(game._rank_players(), [game.teams[0], game.teams[1]])
	game.scores = [1, 3]
	assert_eq(game._rank_players(), [game.teams[1], game.teams[0]])
	game.scores = [2, 2]
	assert_eq(game._rank_players(), [game.slots], "dead heat is a full tie")


func test_snapshot_shape_and_junk_input() -> void:
	var game := _game()
	game.handle_input(0, {"act": "garbage", "mx": "NaN"})
	game.handle_input(99, {"act": true})
	var snapshot := game.get_snapshot()
	assert_eq(snapshot.players.size(), 4)
	assert_eq(snapshot.ball.size(), BasketBrawl.BALL_COUNT)
	assert_eq(snapshot.scores, [0, 0])
	assert_eq(snapshot.hoops.size(), 2)
	assert_eq(snapshot.teams.size(), 2)


## #803: you can only shoot the ball you're carrying.
func test_shoot_requires_carrying_the_ball() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.handle_input(slot, {"shoot": true})
	assert_false(game._shot_active, "no ball, no shot")
	assert_eq(game.holder, -1)


## #803: a made shot flies the full arc to the enemy hoop, then drops in for a
## score and resets. The ball is uncatchable in flight and carries the shot flag.
func test_made_shot_arcs_in_and_scores() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2.ZERO
	game.tick(TICK)
	assert_eq(game.holder, slot, "picked up")
	game.handle_input(slot, {"shoot": true})
	assert_true(game._shot_active, "the shot launches")
	game._shot_make = true  # force the outcome; the roll itself is tuning
	assert_eq(int(game.get_snapshot().ball[BasketBrawl.BALL_SHOT]), 1, "the shot flag replicates")
	for _i in 60:
		game.tick(TICK)
		if not game._shot_active:
			break
	assert_eq(int(game.scores[0]), 1, "the made shot scores")
	assert_eq(game.ball_pos, Vector2.ZERO, "ball resets to center")
	assert_eq(game.holder, -1)


## #803: a missed shot clangs off the rim into a live, catchable rebound —
## no score, ball loose with speed.
func test_missed_shot_rebounds_live() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2.ZERO
	game.tick(TICK)
	game.handle_input(slot, {"shoot": true})
	game._shot_make = false  # force a miss
	for _i in 60:
		game.tick(TICK)
		if not game._shot_active:
			break
	assert_eq(int(game.scores[0]), 0, "a miss does not score")
	assert_eq(game.holder, -1, "the rebound is loose")
	assert_gt(game.ball_vel.length(), 0.0, "it scatters live for the scramble")
