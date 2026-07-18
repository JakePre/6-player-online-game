class_name MagmaAscentBrain
extends GauntletBrain
## Magma Ascent finale archetype (#936): shop thinking inherited from
## GauntletBrain (survivability-first, then confirm). Showdown: climb — steer
## toward the next ledge up the zigzag and jump to reach it, keeping ahead of
## the rising magma. Snapshot: {players: {slot: [x, y, facing, grounded,
## flags]}, magma_y, crumble} (MagmaAscent, #708 named indices).

## Jump when within this world-y of a ledge lid while grounded and moving.
const JUMP_REACH := 1.2


func _think_play(game: Dictionary) -> Dictionary:
	var players: Dictionary = game.get("players", {})
	var me_state: Array = players.get(slot, [])
	if me_state.size() < MagmaAscent.PS_COUNT:
		return {}
	if int(me_state[MagmaAscent.PS_FLAGS]) & 2 > 0:
		return {}  # eliminated
	var me := Vector2(float(me_state[MagmaAscent.PS_X]), float(me_state[MagmaAscent.PS_Y]))
	var grounded := int(me_state[MagmaAscent.PS_GROUNDED]) == 1
	var target := _next_ledge_above(me)
	if target == Vector2.INF:
		# Above the ladder (near the capstone) — just hold center, stay alive.
		return {"mx": -signf(me.x) * 0.4}
	var intent := {"mx": clampf((target.x - me.x) * 0.8, -1.0, 1.0)}
	# Jump when roughly under/beside the next lid and on solid footing — the
	# diagonal carries us up and across to the alternating ledge.
	if grounded and target.y - me.y > 0.3 and absf(target.x - me.x) < MagmaAscent.LEDGE_WIDTH:
		intent["jump"] = true
	return intent


## The nearest ledge lid strictly above us (the next rung of the climb), or
## INF past the top. Reads the static ledge layout — crumble timing is a
## dodge the sim resolves; the brain just keeps climbing.
func _next_ledge_above(me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_gap := INF
	for rect: Rect2 in MagmaAscent.ledges():
		var lid_y := rect.position.y + rect.size.y
		var gap := lid_y - me.y
		if gap > 0.2 and gap < best_gap:
			best_gap = gap
			best = Vector2(rect.get_center().x, lid_y)
	return best
