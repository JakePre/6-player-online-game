extends GutTest
## Kingslayer (#936, finale variant build 2): crowning by match coin totals,
## the King's kit edge, hunter respawn cooldowns, role-gated swings and
## sabotage, anti-stunlock protection, and the locked ranking — King survives
## → 1st; slain → slayer, assists, King by survival time.

const TICK := 1.0 / 30.0


func _game(count: int = 4) -> Kingslayer:
	var game := Kingslayer.new()
	game.meta = Kingslayer.make_meta()
	var player_slots: Array[int] = []
	for i in count:
		player_slots.append(i)
	game.setup(player_slots, 42)
	game._invuln_left.clear()  # tests drive hits explicitly
	return game


## Squares `attacker` up point-blank against `victim`, facing them.
func _square_up(game: Kingslayer, attacker: int, victim: int) -> void:
	game.positions[victim] = Vector2(1.5, 0.0)
	game.positions[attacker] = Vector2(0.0, 0.0)
	game.facings[attacker] = Vector2.RIGHT
	game._invuln_left.erase(victim)
	game._swing_cd[attacker] = 0.0


func test_totals_crown_the_coin_leader() -> void:
	var game := _game()
	assert_eq(game.king, 0, "deterministic default before the totals land")
	game.apply_match_totals({0: 50, 1: 120, 2: 80, 3: 120})
	assert_eq(game.king, 1, "highest earner takes the crown (tie -> lowest slot)")
	assert_eq(game.hp[1], Kingslayer.KING_HP_BASE, "the crown brings the royal HP pool")
	assert_eq(game.hp[0], Kingslayer.HUNTER_HP_BASE, "the old default is a hunter again")


func test_loadouts_deepen_the_pools_whoever_is_crowned() -> void:
	var game := _game()
	(
		game
		. apply_loadouts(
			{
				1: {"items": {&"extra_life": 2, &"shield": 1}},
				2: {"items": {&"extra_life": 1}},
			}
		)
	)
	game.apply_match_totals({1: 500})
	assert_eq(
		game.hp[1],
		Kingslayer.KING_HP_BASE + 2 * Kingslayer.KING_HP_PER_LIFE,
		"extra lives scale the royal pool even when the crown lands after loadouts"
	)
	assert_eq(game.hp[2], Kingslayer.HUNTER_HP_BASE + 1, "hunter lives = extra HP")
	assert_true(game.shields[1])


func test_hunter_swing_chips_the_king_and_credits_damage() -> void:
	var game := _game()
	game.apply_match_totals({3: 100})
	_square_up(game, 0, 3)
	game.handle_input(0, {"swing": true})
	assert_eq(game.hp[3], Kingslayer.KING_HP_BASE - 1, "a hunter hit chips the crown")
	assert_eq(game.damage_dealt[0], 1, "and is credited for the assist ledger")
	# Anti-stunlock: an immediate second swing (fresh cooldown) is shrugged.
	game._swing_cd[0] = 0.0
	game.handle_input(0, {"swing": true})
	assert_eq(game.hp[3], Kingslayer.KING_HP_BASE - 1, "hit protection blocks the dogpile")


func test_hunters_cannot_hurt_each_other() -> void:
	var game := _game()
	game.apply_match_totals({3: 100})
	_square_up(game, 0, 1)
	game.handle_input(0, {"swing": true})
	assert_eq(game.hp[1], Kingslayer.HUNTER_HP_BASE, "hunter swings pass through hunters")


func test_royal_swing_downs_a_hunter_who_respawns() -> void:
	var game := _game()
	game.apply_match_totals({0: 100})
	_square_up(game, 0, 1)
	game.handle_input(0, {"swing": true})
	assert_true(game._respawn_left.has(1), "one royal swing downs a base hunter")
	game.handle_input(1, {"swing": true})
	assert_eq(game.swing_seq[1], 0, "downed hunters cannot act")
	for _i in int(Kingslayer.HUNTER_RESPAWN_SEC / TICK) + 2:
		game.tick(TICK)
	assert_false(game._respawn_left.has(1), "the respawn cooldown lands")
	assert_eq(game.hp[1], game.max_hp[1], "back at full HP")


func test_slaying_the_king_finishes_with_the_locked_ranking() -> void:
	var game := _game(4)
	game.apply_match_totals({3: 100})
	game.hp[3] = 1
	game.damage_dealt[1] = 2  # slot 1 drew blood earlier
	game.elapsed = 60.0  # past half the 90s round: the King ranked above idles
	_square_up(game, 0, 3)
	game.handle_input(0, {"swing": true})
	assert_true(game.finished, "the killing blow ends it")
	var placements: Array = game.get_results().placements
	assert_eq(placements[0], [0], "slayer first")
	assert_eq(placements[1], [1], "assists next")
	assert_eq(placements[2], [3], "the King lasted long enough to beat the idle pack")
	assert_eq(placements[3], [2], "idle hunters last")


func test_an_early_fallen_king_ranks_last() -> void:
	var game := _game(3)
	game.apply_match_totals({2: 100})
	game.hp[2] = 1
	game.elapsed = 5.0  # far short of SURVIVAL_RANK_FRACTION of 90s
	_square_up(game, 0, 2)
	game.handle_input(0, {"swing": true})
	var placements: Array = game.get_results().placements
	assert_eq(placements[0], [0], "slayer first")
	assert_eq(placements[-1], [2], "a King who fell early ranks behind everyone")


func test_surviving_king_wins_and_hunters_rank_by_damage() -> void:
	var game := _game(3)
	game.apply_match_totals({2: 100})
	game.damage_dealt[1] = 3
	game.damage_dealt[0] = 1
	var placements: Array = game._rank_players()
	assert_eq(placements[0], [2], "the surviving King takes the match")
	assert_eq(placements[1], [1], "then the hunter who hurt them most")
	assert_eq(placements[2], [0])


func test_sabotage_is_role_gated_and_strikes_the_circle() -> void:
	var game := _game(3)
	game.apply_match_totals({2: 100})
	game.sabotage_tokens[0] = 1
	game.sabotage_tokens[2] = 1
	game.handle_input(0, {"sabotage": 1})
	assert_eq(game.strikes.size(), 0, "hunters cannot strike hunters")
	game.handle_input(0, {"sabotage": 2})
	assert_eq(game.strikes.size(), 1, "hunter -> King is the legal strike")
	game.handle_input(2, {"sabotage": 0})
	assert_eq(game.strikes.size(), 2, "King -> hunter is legal too")
	# Freeze everyone on the marks and let both land: only opposite roles hurt.
	game.move_dirs.clear()
	for slot in [0, 1, 2]:
		game.move_dirs[slot] = Vector2.ZERO
	game.positions[2] = game.strikes[0].pos
	game.positions[0] = game.strikes[1].pos
	game.positions[1] = game.strikes[0].pos  # hunter loitering in the anti-King circle
	for _i in int(Kingslayer.SABOTAGE_WARN_SEC / TICK) + 2:
		game.tick(TICK)
	assert_eq(game.hp[2], Kingslayer.KING_HP_BASE - 1, "the King took the hunters' strike")
	assert_true(
		game._respawn_left.has(0) or int(game.hp[0]) < Kingslayer.HUNTER_HP_BASE,
		"the hunter took the King's strike"
	)
	assert_eq(game.hp[1], Kingslayer.HUNTER_HP_BASE, "friendly fire never lands")


func test_snapshot_shape() -> void:
	var game := _game()
	var snap := game.get_snapshot()
	for key in ["king", "king_max_hp", "court", "players", "strikes"]:
		assert_true(snap.has(key), "%s replicates" % key)
	assert_eq((snap.players[0] as Array).size(), Kingslayer.PS_COUNT)
