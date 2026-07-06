class_name FaultyWiringBrain
extends BotBrain
## Faulty Wiring archetype (M19-02, #686): role-branching from the OWN private
## snapshot. The saboteur cuts the crew's best-repaired node (maximum damage)
## whenever its private cooldown allows; crew members spread across the
## unfinished nodes and hold them to repair.
##
## Snapshot: {phase, players: {slot: [x, y]}, nodes: [[x, y, value, spark], ...]}.
## Private: {"role": "saboteur", "cut_cd": seconds} for the saboteur, WORK only
## (FaultyWiring, #254). Input: {mx, my} + {cut: true} (saboteur, in range).


func think(match_state: Dictionary, private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	if int(game.get("phase", FaultyWiring.Phase.WORK)) != FaultyWiring.Phase.WORK:
		return {}
	var players: Dictionary = game.get("players", {})
	var me := my_position(players)
	if me == Vector2.INF:
		return {}
	var nodes: Array = game.get("nodes", [])
	if String(private.get("role", "")) == "saboteur":
		return _sabotage(me, nodes, float(private.get("cut_cd", 0.0)))
	return _repair(me, nodes)


## Cut the highest-value unfinished node — hitting their best progress hurts
## most. Fire the moment the private cooldown is up and we're in range.
func _sabotage(me: Vector2, nodes: Array, cut_cd: float) -> Dictionary:
	var target := _pick_node(nodes, true)
	if target == Vector2.INF:
		return {}
	var intent := move_toward_point(me, target, FaultyWiring.NODE_RADIUS * 0.5)
	if cut_cd <= 0.0 and me.distance_to(target) <= FaultyWiring.NODE_RADIUS:
		intent["cut"] = true
	return intent


## Head to an unfinished node and park on it (repair is passive proximity).
## Bias toward node[slot % count] so a crew of bots spreads instead of
## dogpiling one — the sim caps useful repairers per node at 3 anyway.
func _repair(me: Vector2, nodes: Array) -> Dictionary:
	if nodes.is_empty():
		return {}
	var preferred := slot % nodes.size()
	var pref_node: Array = nodes[preferred]
	var target := Vector2.INF
	if float(pref_node[2]) < 1.0:
		target = Vector2(float(pref_node[0]), float(pref_node[1]))
	else:
		target = _pick_node(nodes, false)
	if target == Vector2.INF:
		return {"mx": 0.0, "my": 0.0}  # all repaired: we've won, hold
	return move_toward_point(me, target, FaultyWiring.NODE_RADIUS * 0.4)


## An unfinished node's position: the highest-value one when `want_high` (the
## saboteur's target), else the lowest-value (the crew's neediest). INF if all
## nodes read full.
func _pick_node(nodes: Array, want_high: bool) -> Vector2:
	var best := Vector2.INF
	var best_value := -1.0 if want_high else 2.0
	for node: Array in nodes:
		var value := float(node[2])
		if value >= 1.0:
			continue
		if (want_high and value > best_value) or (not want_high and value < best_value):
			best_value = value
			best = Vector2(float(node[0]), float(node[1]))
	return best
