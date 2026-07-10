class_name FaultyWiring
extends MinigameBase
## Faulty Wiring (M10-16, PHASE2 §4 #33): "repair the circuit together in the
## dark; someone keeps cutting wires." A real-time repair-vs-sabotage race —
## NOT The Mole's (#370) whodunit. Four corner nodes start broken; anyone
## nearby passively repairs the nearest one (co-op, stacking). One seeded
## slot is the hidden saboteur (role via get_private_snapshot, #254): its
## cut action instantly knocks a chunk off a node on a cooldown, sparking it
## globally and unattributed — in the dark you can't see whose hands did it.
## The crew wins the instant all four nodes read full; the saboteur wins on
## timeout. Server-side simulation only — the client renders get_snapshot().

enum Phase { WORK, REVEAL }

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
## Four repair nodes inset from the corners.
const NODE_POSITIONS: Array[Vector2] = [
	Vector2(-5.0, -5.0), Vector2(5.0, -5.0), Vector2(-5.0, 5.0), Vector2(5.0, 5.0)
]
const NODE_RADIUS := 1.7
## Repair rate per crew member in range, per second; stacking is capped so a
## dogpile can't trivially out-race the saboteur.
const REPAIR_RATE := 0.30
const MAX_STACKED_REPAIRERS := 3
## A cut instantly drops the nearest node by this much, on a cooldown.
const CUT_AMOUNT := 0.55
const CUT_COOLDOWN_SEC := 3.5
## Internal phase clock; base duration_sec is a backstop above WORK + REVEAL.
const WORK_SEC := 70.0
const REVEAL_SEC := 3.5
## Scoring: repair contribution and cuts convert to points; the winning side
## gets a large bonus so it tops the FFA ranking.
const REPAIR_POINTS := 20  # per full unit of repair contributed
const CUT_POINTS := 3
const CREW_WIN_BONUS := 8
const SABO_WIN_BONUS := 14

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_COUNT := 2

const ND_X := 0
const ND_Y := 1
const ND_VALUE := 2
const ND_SPARK := 3
const ND_COUNT := 4

var phase: int = Phase.WORK
var positions := {}
var move_dirs := {}
## Node repair values 0..1, indexed like NODE_POSITIONS.
var nodes: Array[float] = []
var saboteur := -1
var outcome := ""  # "crew" | "saboteur", set when the round resolves

var _time_left := WORK_SEC
var _reveal_left := REVEAL_SEC
var _cut_cooldown := 0.0
var _cut_pressed := false
var _repair_contribution := {}
var _cuts_made := 0
## Per-node spark pulse counter, bumped on each cut so the view can flash it
## without a local clock.
var _spark_pulses: Array[int] = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"faulty_wiring",
				"name": "Faulty Wiring",
				"category": MinigameMeta.Category.SABOTAGE,
				"min_players": 4,
				# 12 by design (ADR 003 addendum): MAX_STACKED_REPAIRERS (3) x
				# NODE_POSITIONS (4) is a built-in ceiling of 12 usefully-occupied
				# slots — no arena/economy scaling needed, plain bump.
				"max_players": 12,
				"duration_sec": WORK_SEC + REVEAL_SEC + 6.0,
				"rules":
				(
					"Repair all four wiring nodes in the dark before the power dies."
					+ " One of you is the saboteur, cutting wires on the sly —"
					+ " watch the sparks and out-repair them."
				),
				"controls": "Move — WASD / left stick · Cut (saboteur) — SPACE / pad A",
				# Device-aware (#608): the button reads as what the player holds.
				"control_hints":
				[
					"Move — WASD / left stick · Cut (saboteur) — ",
					{"action": &"action_primary"},
				],
				# Structured spec (#832/#844): move + role-qualified action.
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE},
					{"verb": "Cut (saboteur)", "input": &"action_primary"},
				],
			}
		)
	)


func _setup() -> void:
	for i in slots.size():
		var angle := TAU * i / slots.size()
		positions[slots[i]] = Vector2(cos(angle), sin(angle)) * 2.5
		move_dirs[slots[i]] = Vector2.ZERO
		_repair_contribution[slots[i]] = 0.0
	for _i in NODE_POSITIONS.size():
		nodes.append(0.0)
		_spark_pulses.append(0)
	saboteur = slots[rng.randi_range(0, slots.size() - 1)]


func _handle_input(slot: int, data: Dictionary) -> void:
	if phase != Phase.WORK:
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	# Only the saboteur's cut does anything; guarding here keeps the secret
	# server-side so a crafted packet can't cut on a crew slot.
	if data.get("cut", false) and slot == saboteur:
		_cut_pressed = true


func _tick(delta: float) -> void:
	if phase == Phase.REVEAL:
		_reveal_left -= delta
		if _reveal_left <= 0.0:
			finish(_build_placements())
		return

	_move_players(delta)
	_apply_repairs(delta)
	_apply_cut()
	_cut_cooldown = maxf(0.0, _cut_cooldown - delta)

	if _all_repaired():
		_resolve("crew")
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_resolve("saboteur")


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	var node_states: Array = []
	for i in nodes.size():
		var pos := NODE_POSITIONS[i]
		node_states.append([pos.x, pos.y, snappedf(nodes[i], 0.01), _spark_pulses[i]])
	var snapshot := {
		"phase": phase,
		"players": players,
		"nodes": node_states,
		"time_left": snappedf(_time_left, 0.1),
	}
	# The saboteur and outcome stay secret until the round resolves.
	if phase == Phase.REVEAL:
		snapshot["saboteur"] = saboteur
		snapshot["outcome"] = outcome
	return snapshot


## Only the saboteur's own client learns the role, and only mid-round (#254).
## Their private cut cooldown rides along so no one else can time it.
func get_private_snapshot(slot: int) -> Dictionary:
	if phase == Phase.WORK and slot == saboteur:
		return {"role": "saboteur", "cut_cd": snappedf(_cut_cooldown, 0.05)}
	return {}


func _move_players(delta: float) -> void:
	for slot: int in slots:
		var velocity: Vector2 = move_dirs[slot] * MOVE_SPEED
		var pos: Vector2 = positions[slot] + velocity * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)


## Every player in range of a node repairs it; stacking is capped. The
## saboteur repairs too (blending in) and it counts as their contribution —
## the cut is the only role-exclusive action.
func _apply_repairs(delta: float) -> void:
	for i in nodes.size():
		if nodes[i] >= 1.0:
			continue
		var repairers: Array = _players_at_node(i)
		if repairers.is_empty():
			continue
		var effective := mini(repairers.size(), MAX_STACKED_REPAIRERS)
		var gain := REPAIR_RATE * effective * delta
		nodes[i] = minf(1.0, nodes[i] + gain)
		# Credit is split evenly among the repairers actually applying it.
		var per_head := REPAIR_RATE * delta * float(effective) / float(repairers.size())
		for slot: int in repairers:
			_repair_contribution[slot] = float(_repair_contribution[slot]) + per_head


func _apply_cut() -> void:
	if not _cut_pressed:
		return
	_cut_pressed = false
	if _cut_cooldown > 0.0:
		return
	var target := _nearest_node(positions[saboteur])
	if target == -1:
		return
	nodes[target] = maxf(0.0, nodes[target] - CUT_AMOUNT)
	_spark_pulses[target] += 1
	_cuts_made += 1
	_cut_cooldown = CUT_COOLDOWN_SEC


func _resolve(who: String) -> void:
	outcome = who
	phase = Phase.REVEAL
	_reveal_left = REVEAL_SEC
	for slot: int in slots:
		move_dirs[slot] = Vector2.ZERO


## Timeout backstop: if the base clock ever beats the internal one, rank from
## whatever the current outcome is (defaulting to a saboteur win, since an
## unresolved circuit is a broken one).
func _rank_players() -> Array:
	if outcome.is_empty():
		outcome = "saboteur"
	return _build_placements()


func _build_placements() -> Array:
	var score := {}
	for slot: int in slots:
		if slot == saboteur:
			var sabo := _cuts_made * CUT_POINTS
			if outcome == "saboteur":
				sabo += SABO_WIN_BONUS
			score[slot] = sabo
		else:
			var crew := int(round(float(_repair_contribution[slot]) * REPAIR_POINTS))
			if outcome == "crew":
				crew += CREW_WIN_BONUS
			score[slot] = crew
	var by_score := {}
	for slot: int in slots:
		var value: int = score[slot]
		if not by_score.has(value):
			by_score[value] = []
		by_score[value].append(slot)
	var values := by_score.keys()
	values.sort()
	values.reverse()
	var placements: Array = []
	for value: int in values:
		placements.append(by_score[value])
	return placements


func _players_at_node(index: int) -> Array:
	var here: Array = []
	for slot: int in slots:
		if positions[slot].distance_to(NODE_POSITIONS[index]) <= NODE_RADIUS:
			here.append(slot)
	return here


func _nearest_node(from: Vector2) -> int:
	var best := -1
	var best_dist := NODE_RADIUS
	for i in nodes.size():
		var dist := from.distance_to(NODE_POSITIONS[i])
		if dist <= best_dist:
			best_dist = dist
			best = i
	return best


func _all_repaired() -> bool:
	for value in nodes:
		if value < 1.0:
			return false
	return true
