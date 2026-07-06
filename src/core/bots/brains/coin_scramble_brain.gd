class_name CoinScrambleBrain
extends BotBrain
## Collector archetype (M19): run at the nearest coin on the floor. Snapshot:
## {players: {slot: [x, y, count]}, coins: [[x, y], ...]} (CoinScramble).


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	var coin := nearest_point(me, game.get("coins", []))
	if coin == Vector2.INF:
		# No coins on the floor right now: drift toward center to be first
		# to the next spawn wave.
		return move_toward_point(me, Vector2.ZERO, 0.5)
	return move_toward_point(me, coin, 0.05)
