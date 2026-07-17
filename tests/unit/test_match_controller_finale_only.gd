extends GutTest
## The finale_only debug/render path (#685): a match that opens straight on
## the buy-in shop with a seeded purse, skipping the playlist entirely — how
## `--debug-minigame=gauntlet` and the render harness reach the finale. Split
## from test_match_controller.gd to stay under gdlint's public-method cap
## (same precedent as test_match_screen_diagnostics.gd). Also covers the
## finale_results event (#706), since it only ever fires on this same
## SHOP -> PLAY -> PODIUM path.

const TICK := 1.0 / 30.0

var events: Array = []


func before_each() -> void:
	events = []


func _make_room(player_count: int) -> Room:
	var room := Room.new()
	room.code = "TEST42"
	for i in player_count:
		room.add_member(100 + i, "P%d" % i, "token%d" % i)
	return room


func _event_types() -> Array:
	var types: Array = []
	for event: Dictionary in events:
		types.append(String(event.get("type", "")))
	return types


func test_finale_only_starts_at_the_shop_with_a_seeded_purse() -> void:
	var room := _make_room(3)
	var controller := MatchController.new(
		room, {"seed": 7, "finale": true, "finale_only": true, "finale_coins": 90}
	)
	controller.event_emitted.connect(events.append)
	controller.start()
	assert_eq(controller.state, MatchController.State.FINALE_SHOP, "no rounds, straight to shop")
	assert_has(_event_types(), "finale_shop")
	var players: Dictionary = controller.get_snapshot().shop.players
	assert_eq(int(players[0].coins), 90, "the debug purse replaces round earnings")
	controller.handle_input(0, {"shop": {"action": "buy", "item": "shield"}})
	assert_eq(int(controller.get_snapshot().shop.players[0].coins), 50, "and it spends")


func test_finale_only_defaults_off() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	var room := _make_room(2)
	var controller := MatchController.new(room, {"seed": 7, "playlist": [&"coin_scramble"]})
	controller.start()
	assert_eq(controller.state, MatchController.State.INTRO, "normal matches are untouched")


## #706: the finale skips round_results entirely (straight to podium), so its
## KO-cause breakdown rides its own event — this is the only place that event
## can be observed end to end.
func test_finale_results_event_carries_the_ko_cause_breakdown() -> void:
	var room := _make_room(2)
	var controller := MatchController.new(
		room, {"seed": 7, "finale": true, "finale_only": true, "finale_coins": 0}
	)
	controller.event_emitted.connect(events.append)
	controller.start()
	controller.handle_input(0, {"shop": {"action": "confirm"}})
	controller.handle_input(1, {"shop": {"action": "confirm"}})
	controller.tick(TICK)
	assert_eq(
		controller.state, MatchController.State.FINALE_PLAY, "both confirmed: shop closes early"
	)
	var gauntlet := controller.game as Gauntlet
	assert_not_null(gauntlet, "the finale runs The Gauntlet directly")
	gauntlet._invuln_left.clear()  # past the opening spawn-protection window (#787)
	# Walk slot 0 off the rim — a plain KO, no swing involved.
	gauntlet.positions[0] = Vector2(gauntlet.radius + 1.0, 0.0)
	controller.tick(TICK)
	# #1045: a decisive KO holds a finisher beat so the loser's death renders
	# before the podium, instead of cutting the instant the win resolves.
	assert_eq(controller.state, MatchController.State.FINALE_PLAY, "the finisher beat holds first")
	controller.tick(MatchController.FINISHER_SEC + TICK)
	assert_eq(controller.state, MatchController.State.PODIUM, "then the podium, one KO ends it")
	var results_event: Dictionary = {}
	for event: Dictionary in events:
		if String(event.get("type", "")) == "finale_results":
			results_event = event
	assert_eq(String(results_event.get("type", "")), "finale_results", "the event fired")
	assert_eq(int((results_event.ko_causes as Dictionary).get("rim", 0)), 1)
	assert_true(
		results_event.has("placements"), "carries placements too, same shape as round_results"
	)
