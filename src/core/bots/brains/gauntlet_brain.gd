class_name GauntletBrain
extends BotBrain
## Finale archetype (M19): spend coins sensibly in the buy-in shop, then
## survive and fight — stay off the shrinking edge and out of hazard
## telegraphs, grab axe pickups (#584), and swing at rivals in range.
## Shop snapshot: {shop: {players: {slot: {coins, items, confirmed}}}};
## play snapshot: {game: {radius, players: {slot: [x, y, lives, respawn,
## swings, swing_seq, hit_seq]}, hazards: [[x, y, radius, warn_left], ...],
## weapons: [[x, y], ...]}} (Gauntlet, #554/#584).

## Shop buying order: survivability first, mirroring FinaleShop.ITEMS prices.
const BUY_PRIORITY: Array[Dictionary] = [
	{"item": "extra_life", "price": 100},
	{"item": "shield", "price": 40},
	{"item": "speed_boost", "price": 40},
]
## Keep this far inside the platform edge, as a fraction of its radius.
const EDGE_MARGIN := 0.75


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	if int(match_state.get("state", -1)) == MatchController.State.FINALE_SHOP:
		return _think_shop(match_state.get("shop", {}))
	return _think_play(match_state.get("game", {}))


## One shop action per tick: buy down the priority list while affordable,
## then lock in so the room's all-confirmed early close can fire.
func _think_shop(shop: Dictionary) -> Dictionary:
	var players: Dictionary = shop.get("players", {})
	var mine: Dictionary = players.get(slot, {})
	if mine.is_empty() or bool(mine.get("confirmed", false)):
		return {}
	var coins := int(mine.get("coins", 0))
	var items: Dictionary = mine.get("items", {})
	for entry: Dictionary in BUY_PRIORITY:
		var item: String = entry.item
		if int(entry.price) <= coins and int(items.get(StringName(item), 0)) == 0:
			return {"shop": {"action": "buy", "item": item}}
	return {"shop": {"action": "confirm"}}


func _think_play(game: Dictionary) -> Dictionary:
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	var flee := _flee_hazard(game, me)
	if not flee.is_empty():
		return flee
	# Armed (#584): swing when a living rival is inside the axe's reach.
	var players: Dictionary = game.get("players", {})
	var my_state: Array = players.get(slot, [])
	var swings := int(my_state[4]) if my_state.size() >= 5 else 0
	if swings > 0 and _rival_in_swing_range(me, players):
		return {"swing": true}
	# Unarmed with an axe on the floor: go get it (survival still outranks
	# this — hazard flight above already returned).
	var platform := float(game.get("radius", 10.0))
	if swings == 0:
		var axe := nearest_point(me, game.get("weapons", []))
		if axe != Vector2.INF and axe.length() < platform * EDGE_MARGIN:
			return move_toward_point(me, axe, 0.1)
	# No threat, no errand: hold a ring well inside the edge, wandering a
	# little so swings and shoves can't line us up.
	if me.length() > platform * EDGE_MARGIN:
		return move_toward_point(me, Vector2.ZERO, platform * 0.3)
	var jitter := Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
	return {"mx": jitter.x, "my": jitter.y}


## Hazard telegraphs are lethal circles: flee any we're standing in, without
## ever fleeing off the shrinking platform. {} when no hazard threatens.
func _flee_hazard(game: Dictionary, me: Vector2) -> Dictionary:
	for hazard: Array in game.get("hazards", []):
		if hazard.size() < 4:
			continue
		var pos := Vector2(float(hazard[0]), float(hazard[1]))
		if me.distance_to(pos) >= float(hazard[2]) + 0.4:
			continue
		var flee := move_away_from_point(me, pos)
		var radius := float(game.get("radius", 10.0))
		var next := me + Vector2(float(flee.mx), float(flee.my))
		if next.length() > radius * EDGE_MARGIN:
			return move_toward_point(me, Vector2.ZERO, 0.0)
		return flee
	return {}


## Any living rival (lives > 0, not respawning) within axe reach of `me`.
func _rival_in_swing_range(me: Vector2, players: Dictionary) -> bool:
	for other: int in players:
		if other == slot:
			continue
		var state: Array = players[other]
		if state.size() < 4 or int(state[2]) <= 0 or float(state[3]) > 0.0:
			continue
		if me.distance_to(Vector2(float(state[0]), float(state[1]))) <= Gauntlet.SWING_RANGE:
			return true
	return false
