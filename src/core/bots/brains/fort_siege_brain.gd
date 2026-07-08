class_name FortSiegeBrain
extends BotBrain
## Team-siege archetype (M19-02, #686): battering-ram attackers, wall-guard
## defenders, roles swapping at halftime. Attacker: push toward the gate line —
## the sim walls attackers out at GATE_Y + PLAYER_RADIUS while it stands, so
## approaching it is automatically "touching" and battering — then push onto
## the core once it falls. Defender: patrol the gate line to intercept and
## shove attackers on cooldown; once the gate falls, fall back to hold the core
## (any defender standing on it stalls the capture meter) and keep shoving.
##
## Snapshot: {phase (0 SIEGE, 1 SWAP), attacking (team index), phase_left,
## gate (0..1 hp fraction), capture (0..1), players: {slot: [x, y]}, teams:
## [[slot, ...], [slot, ...]], times} (FortSiege). Input: {mx, my, act}.
## Indices named via FortSiege.PS_* (#708).

## Where defenders camp while the gate still stands — just behind it, so they
## naturally collide with attackers battering the wall.
const GUARD_POINT := Vector2(0.0, FortSiege.GATE_Y - 1.0)


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
	if my_team == attacking:
		return _attack(me, gate)
	var raiders: Array = teams[attacking] if attacking < teams.size() else []
	return _defend(me, gate, players, raiders)


func _attack(me: Vector2, gate: float) -> Dictionary:
	if gate > 0.0:
		# Straight down onto the wall; the sim's own clamp keeps us in
		# battering range without needing exact aim.
		return move_toward_point(me, Vector2(me.x, FortSiege.GATE_Y), 0.0)
	return move_toward_point(me, FortSiege.CORE_POS, 0.3)


func _defend(me: Vector2, gate: float, players: Dictionary, raiders: Array) -> Dictionary:
	var target := FortSiege.CORE_POS if gate <= 0.0 else GUARD_POINT
	var intent := move_toward_point(me, target, 0.5)
	var nearest := _nearest_of(players, raiders, me)
	if nearest != Vector2.INF and me.distance_to(nearest) <= FortSiege.SHOVE_RADIUS:
		intent["act"] = true
	return intent


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
