class_name MeteorShowerBrain
extends BotBrain
## Telegraph-dodger archetype (M19): stay inside the safe zone, flee any
## meteor telegraph we're standing in. Snapshot: {players: {slot: [x, y]},
## zone: [x, y, radius], meteors: [[x, y, seconds_left], ...]} (MeteorShower).
## Indices named via MeteorShower.MT_*/ZN_* (#708).

# Dodge-scoring weights (#926). Fleeing straight away from the single nearest
# meteor used to run bots into a second telegraph or off the shrinking zone —
# bots died MORE than a stationary player. Now candidate steps are scored
# against EVERY live telegraph and the zone edge, and the safest is taken.
## Safety buffer added around a blast's real radius when scoring proximity.
const DODGE_MARGIN := 0.8
## How far ahead a candidate step is evaluated.
const STEP := 1.8
## Compass resolution of the candidate ring.
const DIRECTIONS := 16
## Per-unit penalties: standing in a blast, leaving the zone, and (as a mild
## tiebreak) sitting away from the long-lived centre. Zone-exit dominates.
const BLAST_WEIGHT := 3.0
const ZONE_WEIGHT := 6.0
const CENTER_WEIGHT := 0.15
## Small bias to stay put when moving wouldn't be meaningfully safer (no jitter).
const MOVE_COST := 0.05


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	var me := my_position(game.get("players", {}))
	if me == Vector2.INF:
		return {}
	var meteors: Array = game.get("meteors", [])
	var zone: Array = game.get("zone", [])
	var zone_radius := (
		float(zone[MeteorShower.ZN_RADIUS]) if zone.size() >= MeteorShower.ZN_COUNT else INF
	)
	# Nothing telegraphed: drift toward center where the zone lasts longest.
	if meteors.is_empty():
		return move_toward_point(me, Vector2.ZERO, zone_radius * 0.4)
	# Score staying put against a ring of candidate steps, each judged by EVERY
	# telegraph plus the zone edge, and take the safest heading.
	var best_dir := Vector2.ZERO
	var best_score := _score(me, meteors, zone_radius)
	for i in DIRECTIONS:
		var ang := TAU * float(i) / DIRECTIONS
		var dir := Vector2(cos(ang), sin(ang))
		var score := _score(me + dir * STEP, meteors, zone_radius) - MOVE_COST
		if score > best_score:
			best_score = score
			best_dir = dir
	return {"mx": best_dir.x, "my": best_dir.y}


## Safety of standing at `pos` — higher is safer. Penalizes proximity to every
## telegraph (the closer and sooner-landing, the worse), leaving the zone
## (dominant), and — as a tiebreak — distance from the center.
func _score(pos: Vector2, meteors: Array, zone_radius: float) -> float:
	var score := 0.0
	var reach := MeteorShower.METEOR_RADIUS + MeteorShower.PLAYER_RADIUS + DODGE_MARGIN
	for meteor: Array in meteors:
		if meteor.size() < MeteorShower.MT_COUNT:
			continue
		var mp := Vector2(float(meteor[MeteorShower.MT_X]), float(meteor[MeteorShower.MT_Y]))
		var d := pos.distance_to(mp)
		if d < reach:
			var left := float(meteor[MeteorShower.MT_LEFT])
			var urgency := 1.0 + maxf(0.0, MeteorShower.METEOR_TELEGRAPH_SEC - left)
			score -= (reach - d) * urgency * BLAST_WEIGHT
	if pos.length() > zone_radius - MeteorShower.PLAYER_RADIUS:
		score -= (pos.length() - (zone_radius - MeteorShower.PLAYER_RADIUS)) * ZONE_WEIGHT
	return score - pos.length() * CENTER_WEIGHT
