extends GutTest
## Cart Push (recreated per #175): one shared cart, net-force pushing,
## dash-shoves with windup/cooldown, rumble-strip staggers, ore delivery
## bonuses, depot wins, and timeout ranking by cart side.

const TICK := 1.0 / 30.0


func _game(player_slots: Array[int] = [0, 1, 2, 3]) -> CartPush:
	var game := CartPush.new()
	game.meta = CartPush.make_meta()
	game.setup(player_slots, 42)
	return game


## Parks `slot` on its team's pushing side of the cart, in reach.
func _on_cart(game: CartPush, slot: int) -> void:
	var side := -1.0 if game._team_of(slot) == 0 else 1.0
	game.positions[slot] = Vector2(game.cart_x + side * 1.0, 0.0)
	game.move_dirs[slot] = Vector2.ZERO


## Parks `slot` far from everything so it contributes nothing.
func _park(game: CartPush, slot: int) -> void:
	game.positions[slot] = Vector2(0.0, CartPush.ARENA_HALF)
	game.move_dirs[slot] = Vector2.ZERO


func test_setup_splits_even_teams_at_center_cart() -> void:
	var game := _game()
	assert_eq((game.teams[0] as Array).size(), 2)
	assert_eq((game.teams[1] as Array).size(), 2)
	assert_eq(game.cart_x, 0.0)
	for slot: int in game.slots:
		assert_eq(float(game.staggers[slot]), 0.0)
		assert_false(game.carrying[slot])


func test_max_players_raised_to_eight() -> void:
	assert_eq(CartPush.make_meta().max_players, 8)


func test_control_spec_present() -> void:
	assert_false(
		CartPush.make_meta().control_spec.is_empty(), "ships a #832 structured control spec"
	)


## No-crowd fairness (M15 8-cap): 4v4 splits evenly and everyone spawns
## within the arena, well clear of the effective-pusher cap concern (a 4th
## player per side has room as a rotating shover/ore-runner, per ADR 003).
func test_setup_splits_four_v_four_within_arena_at_eight_players() -> void:
	var player_slots: Array[int] = []
	for i in 8:
		player_slots.append(i)
	var game := _game(player_slots)
	assert_eq((game.teams[0] as Array).size(), 4)
	assert_eq((game.teams[1] as Array).size(), 4)
	for slot in 8:
		var pos: Vector2 = game.positions[slot]
		assert_lt(absf(pos.y), CartPush.ARENA_HALF, "spawn row stays inside the arena")
		assert_false(game.carrying[slot])


func test_net_pusher_advantage_moves_the_cart() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	var pusher: int = game.teams[0][0]
	_on_cart(game, pusher)
	# effective_pushers is a pure function — assert it directly so the check
	# doesn't ride on tick timing or body-separation nudges (the old
	# two-tick cart-delta version was flaky in CI).
	assert_eq(game.effective_pushers(0), 1)
	assert_eq(game.effective_pushers(1), 0)
	game.tick(TICK)
	assert_gt(game.cart_x, 0.0, "unopposed team 0 pusher moves the cart +x")

	# Balanced 1v1 from a clean centered cart: net force is zero, so it holds.
	# Reset explicitly so the earlier +x drift cannot leak into the check.
	game.cart_x = 0.0
	for slot: int in game.slots:
		_park(game, slot)
	var blocker: int = game.teams[1][0]
	_on_cart(game, pusher)
	_on_cart(game, blocker)
	assert_eq(game.effective_pushers(0), 1)
	assert_eq(game.effective_pushers(1), 1)
	game.tick(TICK)
	assert_almost_eq(game.cart_x, 0.0, 0.001, "balanced pushers stall the cart")


func test_staggered_pushers_do_not_count() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	var pusher: int = game.teams[0][0]
	_on_cart(game, pusher)
	game.staggers[pusher] = 1.0
	var before := game.cart_x
	game.tick(TICK)
	assert_almost_eq(game.cart_x, before, 0.001)


func test_shove_winds_up_then_knocks_back_and_staggers() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	var shover: int = game.teams[0][0]
	var victim: int = game.teams[1][0]
	game.positions[shover] = Vector2.ZERO
	game.positions[victim] = Vector2(1.0, 0.0)
	game.move_dirs[victim] = Vector2.ZERO
	game.handle_input(shover, {"shove": true})
	game.tick(TICK)
	assert_eq(float(game.staggers[victim]), 0.0, "windup has not landed yet")
	game.tick(CartPush.SHOVE_WINDUP_SEC)
	assert_gt(float(game.staggers[victim]), 0.0, "shove landed after the windup")
	assert_gt((game.positions[victim] as Vector2).x, 1.0, "knocked away")
	assert_gt(float(game.shove_cooldowns[shover]), 0.0)
	# On cooldown: another shove input is refused.
	game.handle_input(shover, {"shove": true})
	assert_eq(float(game.shove_windups[shover]), 0.0)


func test_rumble_strip_staggers_everyone_touching_the_cart() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	game.cart_x = CartPush.RUMBLE_XS[1] - 0.05
	var pusher: int = game.teams[0][0]
	_on_cart(game, pusher)
	# Push the cart across the strip in one tick.
	game.tick(0.1)
	assert_gt(game.cart_x, CartPush.RUMBLE_XS[1])
	assert_gt(float(game.staggers[pusher]), 0.0, "crossing rumbles the pushers off")


func test_ore_delivery_grants_capped_bonus_pushers() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	var carrier: int = game.teams[0][0]
	game.ores.append({"id": 99, "pos": Vector2(-5.0, 5.0)})
	game.positions[carrier] = Vector2(-5.0, 5.0)
	game.tick(TICK)
	assert_true(game.carrying[carrier])
	assert_true(game.ores.is_empty())

	game.positions[carrier] = game._depot_of(0)
	game.tick(TICK)
	assert_false(game.carrying[carrier])
	assert_eq(game.bonus_pushers[0], 1)

	game.bonus_pushers[0] = CartPush.ORE_BONUS_MAX
	game.carrying[carrier] = true
	game.tick(TICK)
	assert_eq(game.bonus_pushers[0], CartPush.ORE_BONUS_MAX, "bonus is capped")


func test_bonus_needs_a_live_pusher_no_ghost_pushing() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	game.bonus_pushers[0] = 2
	var before := game.cart_x
	game.tick(TICK)
	assert_almost_eq(game.cart_x, before, 0.001, "bonus alone moves nothing")


func test_cart_reaching_a_depot_ends_with_that_attackers_win() -> void:
	var game := _game()
	for slot: int in game.slots:
		_park(game, slot)
	game.cart_x = CartPush.TRACK_END - 0.01
	var pusher: int = game.teams[0][0]
	_on_cart(game, pusher)
	game.tick(0.1)
	assert_true(game.finished)
	assert_eq(game.get_results().placements[0], game.teams[0])


func test_timeout_ranks_by_cart_side_and_center_ties() -> void:
	var game := _game()
	game.cart_x = -2.0
	assert_eq(game._rank_players()[0], game.teams[1])
	game.cart_x = 0.0
	assert_eq(game._rank_players(), [game.slots])
