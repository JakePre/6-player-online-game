class_name BulletWaltzBrain
extends BotBrain
## Bullet-hell survival archetype (M19-02, #686; #959 graze realignment): one hit
## is out, so survival still comes first — repel hard from bullets crowding our
## dance space. But placement is broken by graze score now, so instead of fleeing
## to the emptiest corner (the #926 camping degeneracy), when nothing is close we
## drift toward the nearest stream to bank grazes. The panic Waltz Bomb clears the
## field when it collapses on us. Bullets carry no id or velocity, so this stays a
## potential field: strong short-range repulsion + a gentle graze pull.
##
## Snapshot: {players: {slot: [x, y, graze_coins, bomb_ready]}, bullets: [[x, y],
## ...], out} (BulletWaltz). Input: {mx, my, bomb}. Indices named via
## BulletWaltz.BU_*/PS_* (#708).

## Bullets beyond this are the storm, not our local problem — ignored.
const SENSE_RADIUS := 4.0
## Survival repulsion band: bullets this close shove us hard (inverse-distance).
## Sits just outside the graze ring so the equilibrium hovers in the graze band.
const DANGER_RADIUS := 1.3
## Don't let the graze pull draw us nearer a stream than this — survival first.
const GRAZE_STANDOFF := 1.0
## The graze pull is gentler than the survival shove, so a close bullet always
## wins the vector sum.
const GRAZE_ATTRACT := 0.6
## Waltz Bomb: spend it when at least BOMB_TRIGGER bullets have converged inside
## the panic radius and we still hold the charge.
const PANIC_RADIUS := 2.2
const BOMB_TRIGGER := 3
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
	var my_row: Array = players.get(slot, [])
	var bomb_ready := my_row.size() > BulletWaltz.PS_BOMB and int(my_row[BulletWaltz.PS_BOMB]) == 1
	var play_half := MinigameScaling.arena_half(BulletWaltz.ARENA_HALF, players.size())

	# One pass over the field: survival repulsion from close bullets, a census
	# of what's crowding the panic radius, and the nearest stream to graze.
	var repel := Vector2.ZERO
	var panic_count := 0
	var nearest := Vector2.INF
	var nearest_distance := INF
	for bullet: Array in game.get("bullets", []):
		if bullet.size() <= BulletWaltz.BU_Y:
			continue
		var bullet_pos := Vector2(float(bullet[BulletWaltz.BU_X]), float(bullet[BulletWaltz.BU_Y]))
		var away := me - bullet_pos
		var distance := away.length()
		if distance < 0.001:
			continue
		if distance <= PANIC_RADIUS:
			panic_count += 1
		if distance <= DANGER_RADIUS:
			repel += away.normalized() / distance
		if distance <= SENSE_RADIUS and distance < nearest_distance:
			nearest_distance = distance
			nearest = bullet_pos

	# Waltz Bomb: the field is caving in and we still hold it — spend it, and keep
	# dodging on the same tick in case the bloom doesn't catch everything.
	if bomb_ready and panic_count >= BOMB_TRIGGER:
		var escape := repel.normalized() if repel.length() > 0.001 else Vector2.ZERO
		return {"mx": escape.x, "my": escape.y, "bomb": true}

	var steer := repel
	# No imminent threat but a stream is nearby: hunt the graze instead of fleeing
	# to a corner (#959 vs #926). The pull never draws us inside the standoff, and
	# a close bullet's repulsion always overrides it.
	if repel.length() < 0.001 and nearest != Vector2.INF and nearest_distance > GRAZE_STANDOFF:
		steer += (nearest - me).normalized() * GRAZE_ATTRACT
	# Stay off the rim: the sim scales the arena with the head count, so mirror it.
	if me.length() > play_half * EDGE_FRACTION:
		steer += -me.normalized() * 2.0
	# Drift off the exact center (the bullet spawn point).
	elif me.length() < CENTER_AVOID:
		var out := me.normalized() if me.length() > 0.001 else Vector2.RIGHT
		steer += out
	if steer.length() < 0.001:
		# Nothing to chase or flee: ease to a calm mid-radius ring where streams
		# pass, not a dead corner.
		return move_toward_point(me, me.normalized() * play_half * 0.5, 0.3)
	var dir := steer.normalized()
	return {"mx": dir.x, "my": dir.y}
