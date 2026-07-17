class_name FortSiegeBrain
extends BotBrain
## Team-siege archetype (M19-02, #686; #1028 relic rework). Attacker: push
## onto the gate line and batter it down — then run the HEIST: converge on
## the relic (home or loose) to grab it, and if we're the thief, sprint it
## out past the escape line. Defender: hold the gate (shove raiders, repair
## between waves) — then chase the thief to shove the relic loose, and touch
## a loose relic to send it home.
##
## Snapshot: {phase, attacking, gate (0..1), relic: [x, y, RelicState,
## carrier], players: {slot: [x, y, ...]}, teams} (FortSiege). Input:
## {mx, my, act}. Indices named via FortSiege.PS_* (#708).

## Where defenders camp while the gate still stands — just behind it, so they
## naturally collide with attackers battering the wall.
const GUARD_POINT := Vector2(0.0, FortSiege.GATE_Y - 1.0)
## Where the thief runs: just past the escape line, straight out.
const ESCAPE_MARGIN := 1.0


func think(match_state: Dictionary, _private: Dictionary) -> Dictionary:
	var game: Dictionary = match_state.get("game", {})
	if int(game.get("phase", FortSiege.Phase.SIEGE)) == FortSiege.Phase.SWAP:
		return {}  # brief halftime pause — nothing to steer toward yet
	var players: Dictionary = game.get("players", {})
	var me := my_position(players)
	if me == Vector2.INF:
		return {}
	var teams: Array = game.get("teams", [])
	var my_team := _team_of(slot, teams)
	if my_team == -1:
		return {}
	var attacking := int(game.get("attacking", 0))
	var gate := float(game.get("gate", 1.0))
	var relic: Array = game.get("relic", [])
	if my_team == attacking:
		return _attack(me, gate, relic)
	var raiders: Array = teams[attacking] if attacking < teams.size() else []
	return _defend(me, gate, players, raiders, relic)


func _attack(me: Vector2, gate: float, relic: Array) -> Dictionary:
	if gate > 0.0:
		# Straight down onto the wall; the sim's own clamp keeps us in
		# battering range without needing exact aim.
		var intent := move_toward_point(me, Vector2(me.x, FortSiege.GATE_Y), 0.0)
		# Battering is an explicit swing (#808) — hit the gate whenever we're
		# in range; the sim caps it to the swing cooldown.
		if me.y - FortSiege.GATE_Y <= FortSiege.GATE_TOUCH:
			intent["act"] = true
		return intent
	# The heist (#1028): the thief sprints the relic out; everyone else
	# converges on it (a grab if it's home or loose, an escort if carried).
	if relic.size() >= 4 and int(relic[3]) == slot:
		return move_toward_point(me, Vector2(me.x, FortSiege.ESCAPE_Y + ESCAPE_MARGIN), 0.0)
	return move_toward_point(me, _relic_pos(relic), 0.2)


func _defend(
	me: Vector2, gate: float, players: Dictionary, raiders: Array, relic: Array
) -> Dictionary:
	var target := GUARD_POINT
	if gate <= 0.0:
		# Post-breach (#1028): the objective is wherever the relic is — chase
		# the thief to shove it loose, touch it loose to send it home, and
		# guard the plinth while it sits there.
		target = _relic_pos(relic)
		if relic.size() >= 4 and int(relic[2]) == FortSiege.RelicState.CARRIED:
			var carrier_state: Array = players.get(int(relic[3]), [])
			if carrier_state.size() > FortSiege.PS_Y:
				target = Vector2(
					float(carrier_state[FortSiege.PS_X]), float(carrier_state[FortSiege.PS_Y])
				)
	var intent := move_toward_point(me, target, 0.2)
	var nearest := _nearest_of(players, raiders, me)
	if nearest != Vector2.INF and me.distance_to(nearest) <= FortSiege.SHOVE_RADIUS:
		intent["act"] = true  # a raider's in reach — shove them off
	elif gate > 0.0 and absf(me.y - FortSiege.GATE_Y) <= FortSiege.GATE_TOUCH:
		intent["act"] = true  # nobody on us and the gate stands — repair it (#808)
	return intent


func _relic_pos(relic: Array) -> Vector2:
	if relic.size() < 2:
		return FortSiege.CORE_POS
	return Vector2(float(relic[0]), float(relic[1]))


## 0/1 for the team roster containing `target_slot`, or -1 if in neither.
func _team_of(target_slot: int, teams: Array) -> int:
	for i in teams.size():
		if target_slot in teams[i]:
			return i
	return -1


func _nearest_of(players: Dictionary, roster: Array, from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for other: int in roster:
		var state: Array = players.get(other, [])
		if state.size() <= FortSiege.PS_Y:
			continue
		var pos := Vector2(float(state[FortSiege.PS_X]), float(state[FortSiege.PS_Y]))
		var distance := from.distance_squared_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = pos
	return best
