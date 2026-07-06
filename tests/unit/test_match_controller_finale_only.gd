extends GutTest
## The finale_only debug/render path (#685): a match that opens straight on
## the buy-in shop with a seeded purse, skipping the playlist entirely — how
## `--debug-minigame=gauntlet` and the render harness reach the finale. Split
## from test_match_controller.gd to stay under gdlint's public-method cap
## (same precedent as test_match_screen_diagnostics.gd).

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
