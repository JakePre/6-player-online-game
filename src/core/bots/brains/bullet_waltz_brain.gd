class_name BulletWaltzBrain
extends BotBrain
## Bullet-hell survival archetype (M19-02, #686): one hit is out, so read the
## bullet field and move to the emptiest nearby space. Bullets carry no id or
## velocity in the snapshot, so this is a potential field — repel from nearby
## bullets (inverse-distance), avoid the center where they spawn and fly out
## from, and stay off the arena rim.
##
## Snapshot: {players: {slot: [x, y, graze_coins]}, bullets: [[x, y], ...],
## out} (BulletWaltz). Input: {mx, my}.

## Only bullets within this radius steer us — the local threat, not the storm.
const SENSE_RADIUS := 4.0
## Push back inward once we're this fraction out toward the rim.
const EDGE_FRACTION := 0.8
## Bullets spawn at the center and radiate; keep a little off dead-center.
const CENTER_AVOID := 1.5


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var players: Dictionary = game.get("players", {})
	var me := my_position(players)
	if me == Vector2.INF:
		return {}
	var steer := Vector2.ZERO
	# Repel from each nearby bullet, weighted by how close it is.
	for bullet: Array in game.get("bullets", []):
		if bullet.size() < 2:
			continue
		var away := me - Vector2(float(bullet[0]), float(bullet[1]))
		var distance := away.length()
		if distance > SENSE_RADIUS or distance < 0.001:
			continue
		steer += away.normalized() / distance
	# Stay off the rim: the sim scales the arena with the head count, so mirror
	# it. Push inward hard as we approach the edge.
	var play_half := MinigameScaling.arena_half(BulletWaltz.ARENA_HALF, players.size())
	if me.length() > play_half * EDGE_FRACTION:
		steer += -me.normalized() * 2.0
	# Drift off the exact center (the bullet spawn point).
	elif me.length() < CENTER_AVOID:
		var out := me.normalized() if me.length() > 0.001 else Vector2.RIGHT
		steer += out
	if steer.length() < 0.001:
		# No threat nearby: ease to a calm mid-radius ring.
		return move_toward_point(me, me.normalized() * play_half * 0.5, 0.3)
	var dir := steer.normalized()
	return {"mx": dir.x, "my": dir.y}
