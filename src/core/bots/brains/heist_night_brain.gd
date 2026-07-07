class_name HeistNightBrain
extends BotBrain
## Blackout archetype (M19-02, #686): grab floor coins while the lights are on
## — during the dark, the snapshot's `players` dict is EMPTY (not even our own
## position is public; that's the anonymity the theft mechanic depends on), so
## there is nothing to steer toward. The fair-information move is to just keep
## walking whatever direction we were already heading when the lights went
## out, exactly the blind coast a human loses their own position to as well.
##
## Snapshot: {dark, players: {slot: [x,y]} (LIGHT only), vaults, coins}.
## Input: {mx, my} only.

## Last movement sent during LIGHT, replayed unchanged through the blackout.
var _last_intent := {"mx": 0.0, "my": 0.0}


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	if bool(game.get("dark", false)):
		return _last_intent.duplicate()
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	var coin := nearest_point(me, game.get("coins", []))
	if coin == Vector2.INF:
		_last_intent = {"mx": 0.0, "my": 0.0}
	else:
		_last_intent = move_toward_point(me, coin, 0.05)
	return _last_intent.duplicate()
