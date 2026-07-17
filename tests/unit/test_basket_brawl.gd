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


func test_dunk_scores_two_and_inbounds_at_the_scored_on_hoop() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2.ZERO
	game.tick(TICK)
	assert_eq(game.holder, slot)
	game.positions[slot] = game.attack_hoop(slot)
	game.tick(TICK)
	assert_eq(int(game.scores[0]), BasketBrawl.POINTS_DUNK, "a dunk pays 2 (#1037)")
	assert_eq(game.holder, -1)
	# Team 0 dunked into team 1's hoop (+x): team 1 inbounds at THEIR hoop.
	assert_gt(float(game.ball_pos.x), BasketBrawl.HOOP_X * 0.5, "inbound at the scored-on hoop")
	for scorer: int in game.teams[0]:
		assert_gt(float(game._no_catch[scorer]), 0.0, "the scorers can't poach the inbound")


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


## #803/#1037: the shot is a hold-and-release now. From center the hoop is 8
## units out — beyond the arc — so a make drops in for 3 and inbounds at the
## scored-on hoop. The ball is uncatchable in flight and carries the shot flag.
func test_made_shot_arcs_in_and_scores_three_from_deep() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2.ZERO
	game.tick(TICK)
	assert_eq(game.holder, slot, "picked up")
	game.handle_input(slot, {"shoot": true})
	assert_false(game._shot_active, "holding is a wind-up, not a launch (#1037)")
	game.handle_input(slot, {"shoot": false})
	assert_true(game._shot_active, "the release fires it")
	game._shot_make = true  # force the outcome; the roll itself is tuning
	assert_eq(int(game.get_snapshot().ball[BasketBrawl.BALL_SHOT]), 1, "the shot flag replicates")
	for _i in 60:
		game.tick(TICK)
		if not game._shot_active:
			break
	assert_eq(int(game.scores[0]), BasketBrawl.POINTS_ARC, "downtown pays 3 (#1037)")
	assert_gt(float(game.ball_pos.x), BasketBrawl.HOOP_X * 0.5, "then the inbound")
	assert_eq(game.holder, -1)


## #1037: inside the arc a make pays 2 — the deep ball is the premium.
func test_inside_shot_pays_two() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = game.attack_hoop(slot) - Vector2(3.5, 0.0)
	game.ball_pos = game.positions[slot]
	game.tick(TICK)
	assert_eq(game.holder, slot)
	game.handle_input(slot, {"shoot": true})
	game.handle_input(slot, {"shoot": false})
	game._shot_make = true
	for _i in 60:
		game.tick(TICK)
		if not game._shot_active:
			break
	assert_eq(int(game.scores[0]), BasketBrawl.POINTS_SHOT, "inside the arc pays 2")


## #803: a missed shot clangs off the rim into a live, catchable rebound —
## no score, ball loose with speed.
func test_missed_shot_rebounds_live() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2.ZERO
	game.tick(TICK)
	game.handle_input(slot, {"shoot": true})
	game.handle_input(slot, {"shoot": false})
	game._shot_make = false  # force a miss
	for _i in 60:
		game.tick(TICK)
		if not game._shot_active:
			break
	assert_eq(int(game.scores[0]), 0, "a miss does not score")
	assert_eq(game.holder, -1, "the rebound is loose")
	assert_gt(game.ball_vel.length(), 0.0, "it scatters live for the scramble")


## #1037: the 2K release window — early and hung-late releases decay the odds,
## the sweet window keeps them whole. Pure function, deterministic.
func test_release_quality_curve() -> void:
	var game := _game()
	var mid := (BasketBrawl.PERFECT_LO + BasketBrawl.PERFECT_HI) / 2.0
	assert_almost_eq(
		game._release_quality(mid * BasketBrawl.CHARGE_FULL_SEC), 1.0, 0.001, "green window"
	)
	assert_almost_eq(
		game._release_quality(0.0), BasketBrawl.TIMING_WORST_MULT, 0.001, "instant tap = brick"
	)
	assert_almost_eq(
		game._release_quality(BasketBrawl.CHARGE_FULL_SEC),
		BasketBrawl.TIMING_WORST_MULT,
		0.001,
		"hung to the cap = brick"
	)
	assert_gt(
		game._release_quality(0.5 * BasketBrawl.CHARGE_FULL_SEC),
		BasketBrawl.TIMING_WORST_MULT,
		"a merely-early release grades between, not worst"
	)


## #1037: charging replicates (the view meter / brain read) and roots the
## shooter to a shuffle while wound up.
func test_charging_replicates_and_roots_the_shooter() -> void:
	var game := _game()
	var slot: int = game.teams[0][0]
	game.positions[slot] = Vector2.ZERO
	game.tick(TICK)
	game.handle_input(slot, {"shoot": true})
	game.handle_input(slot, {"mx": 1.0, "my": 0.0})
	var before: Vector2 = game.positions[slot]
	game.tick(TICK)
	var moved: float = (game.positions[slot] - before).length()
	assert_lt(
		moved,
		BasketBrawl.MOVE_SPEED * BasketBrawl.CARRY_SPEED_MULT * TICK * 0.5,
		"wound up = rooted to a shuffle"
	)
	var row: Array = game.get_snapshot().players[slot]
	assert_gt(float(row[BasketBrawl.PS_CHARGE]), 0.0, "the wind-up fraction replicates")


## #1037: a defender in the shooter's face is a contest.
func test_contest_detection() -> void:
	var game := _game()
	var shooter: int = game.teams[0][0]
	var defender: int = game.teams[1][0]
	game.positions[shooter] = Vector2.ZERO
	game.positions[defender] = Vector2(BasketBrawl.CONTEST_RADIUS + 1.0, 0.0)
	assert_false(game._is_contested(shooter), "space = an open look")
	game.positions[defender] = Vector2(BasketBrawl.CONTEST_RADIUS - 0.2, 0.0)
	assert_true(game._is_contested(shooter), "a hand in the face is a contest")


## #1037: passes are aimed — the ball goes to the mate in your steer
## half-plane, and an aim at empty space flies into space (a turnover risk).
func test_pass_is_aimed_by_the_steer() -> void:
	var game := _game([0, 1, 2, 3, 4, 5])  # 3v3: two mates in different spots
	var passer: int = game.teams[0][0]
	var mate_up: int = game.teams[0][1]
	var mate_down: int = game.teams[0][2]
	game.positions[passer] = Vector2.ZERO
	game.ball_pos = Vector2.ZERO
	game.tick(TICK)
	assert_eq(game.holder, passer)
	game.positions[mate_up] = Vector2(1.0, 5.0)
	game.positions[mate_down] = Vector2(0.0, -3.0)  # nearer, but behind the aim
	game.handle_input(passer, {"mx": 0.2, "my": 1.0, "act": true})
	assert_eq(game.holder, -1)
	assert_gt(float(game.ball_vel.y), 0.0, "the pass goes where you aimed, not just nearest")


## #1037: whiffing a steal staggers the poker — spam is punishable.
func test_steal_whiff_staggers() -> void:
	var game := _game()
	var poker: int = game.teams[1][0]
	game.positions[poker] = Vector2(5.0, 5.0)  # nobody near, ball loose elsewhere
	game.handle_input(poker, {"act": true})
	assert_gt(float(game._stagger[poker]), 0.0, "a whiff staggers you")
	game.handle_input(poker, {"mx": 1.0, "my": 0.0})
	var before: Vector2 = game.positions[poker]
	game.tick(TICK)
	var moved: float = (game.positions[poker] - before).length()
	assert_lt(moved, BasketBrawl.MOVE_SPEED * TICK * 0.5, "staggered = crawling")
