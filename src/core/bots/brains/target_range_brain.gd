class_name TargetRangeBrain
extends BotBrain
## Aim archetype (M19-02, #686): pick the best-value target, lead its motion
## so the crosshair lands on it, and fire the instant the cooldown clears. The
## crosshair is an absolute position the bot sets via {ax, ay}; a fire hits
## whatever target the crosshair is within radius+grace of, so precise aim
## matters.
##
## Snapshot: {targets: [[id, x, y, radius, kind], ...], aims: {slot: [x, y]},
## scores, cd: {slot: seconds}} (TargetRange). Kind: 0 STANDARD(v1),
## 1 SMALL(v3), 2 GOLD(v5). Input: {ax, ay} to aim, {fire: true} to shoot.
## Indices named via TargetRange.TL_*/AM_* (#708).

## Value per kind, mirroring KIND_STATS — chase points, not just proximity.
const KIND_VALUE := [1, 3, 5]
## Estimated crosshair-travel time used to lead a moving target (one bot tick
## plus a hair); targets drift horizontally, so leading is mostly on x.
const LEAD_SEC := 0.28
## Approx horizontal drift speed per kind (world units/sec), from KIND_STATS.
const KIND_SPEED := [2.2, 3.4, 4.5]

var _last_target_x := {}


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var targets: Array = game.get("targets", [])
	if targets.is_empty():
		return {}
	var aim := _my_aim(game)
	var best := _best_target(targets, aim)
	if best.is_empty():
		return {}
	# Lead the target: estimate its x-velocity from the last snapshot, fall
	# back to the kind's nominal speed toward wherever it's heading.
	var target_id := int(best[TargetRange.TL_ID])
	var here := Vector2(float(best[TargetRange.TL_X]), float(best[TargetRange.TL_Y]))
	var vx := 0.0
	if _last_target_x.has(target_id):
		vx = (here.x - float(_last_target_x[target_id])) / NetManager.BOT_INPUT_INTERVAL_SEC
	_last_target_x[target_id] = here.x
	var lead := Vector2(here.x + vx * LEAD_SEC, here.y)
	var intent := {"ax": lead.x, "ay": lead.y}
	# Fire when the cooldown is clear and the crosshair is close enough that
	# the shot will land (radius + a margin for our lead error).
	var cd: Dictionary = game.get("cd", {})
	var ready := float(cd.get(slot, 0.0)) <= 0.0
	if ready and aim.distance_to(here) <= float(best[TargetRange.TL_RADIUS]) + 0.3:
		intent["fire"] = true
	return intent


func _my_aim(game: Dictionary) -> Vector2:
	var aims: Dictionary = game.get("aims", {})
	var a: Array = aims.get(slot, [])
	return (
		Vector2(float(a[TargetRange.AM_X]), float(a[TargetRange.AM_Y]))
		if a.size() > TargetRange.AM_Y
		else Vector2.ZERO
	)


## Highest value-per-distance target — chase gold when it's near, settle for a
## standard shot rather than sweeping across the gallery for a far small one.
func _best_target(targets: Array, aim: Vector2) -> Array:
	var best: Array = []
	var best_score := -INF
	for target: Array in targets:
		if target.size() < TargetRange.TL_COUNT:
			continue
		var value: int = KIND_VALUE[clampi(int(target[TargetRange.TL_KIND]), 0, 2)]
		var distance := aim.distance_to(
			Vector2(float(target[TargetRange.TL_X]), float(target[TargetRange.TL_Y]))
		)
		var score := float(value) - distance * 0.25
		if score > best_score:
			best_score = score
			best = target
	return best
