class_name PoisonFeastBrain
extends BotBrain
## Push-your-luck archetype (M19-02, #686): only a dish's tier (its odds) is
## replicated, never whether it is actually poisoned, so this is an
## expected-value diner. Priorities, richest-first: take the GOLDEN final course
## (huge, never poisoned); when a pot is on the table, bank it with a
## guaranteed-safe CLEAN bite; otherwise eat the best positive-EV dish that
## won't likely stagger us (SPICED at 25% still nets +1.5, CLEAN a safe +1),
## and only gamble on a DELICACY (even-money) when nothing safer is left.
##
## Snapshot: {players: {slot: [x, y, score, staggered]}, dishes: [[id, x, y,
## tier], ...], pot} (PoisonFeast). Tier: 0 CLEAN, 1 SPICED, 2 DELICACY,
## 3 GOLDEN. Input: {mx, my} (eat by touch). Indices named via
## PoisonFeast.PS_*/DL_* (#708).


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	var dishes: Array = game.get("dishes", [])
	# 1. The golden final course dwarfs everything and can't be poisoned.
	var golden := _nearest_dish(dishes, me, [PoisonFeast.Tier.GOLDEN])
	if golden != Vector2.INF:
		return move_toward_point(me, golden, 0.1)
	# 2. A pot is waiting — claim it with a bite that can't backfire.
	if int(game.get("pot", 0)) > 0:
		var claim := _nearest_dish(dishes, me, [PoisonFeast.Tier.CLEAN])
		if claim != Vector2.INF:
			return move_toward_point(me, claim, 0.1)
	# 3. Best value without courting a stagger: spiced (EV +1.5) or clean.
	var safeish := _nearest_dish(dishes, me, [PoisonFeast.Tier.SPICED, PoisonFeast.Tier.CLEAN])
	if safeish != Vector2.INF:
		return move_toward_point(me, safeish, 0.1)
	# 4. Only even-money delicacies remain — take the nearest gamble.
	var gamble := _nearest_dish(dishes, me, [PoisonFeast.Tier.DELICACY])
	return move_toward_point(me, gamble, 0.1) if gamble != Vector2.INF else {}


## Nearest dish whose tier is in `tiers`, or Vector2.INF when none is on offer.
func _nearest_dish(dishes: Array, from: Vector2, tiers: Array) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for dish: Array in dishes:
		if dish.size() < 4 or int(dish[PoisonFeast.DL_TIER]) not in tiers:
			continue
		var pos := Vector2(float(dish[PoisonFeast.DL_X]), float(dish[PoisonFeast.DL_Y]))
		var distance := from.distance_squared_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = pos
	return best
