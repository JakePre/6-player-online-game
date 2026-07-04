class_name FaultyWiring
extends MinigameBase
## Faulty Wiring (M10-16, PHASE2.md $4 #33): the crew repairs a ring of circuit
## wires together in the dark while one secret saboteur keeps cutting the ones
## they fix. A broken wire fills while crew stand on it (more crew, faster); the
## saboteur — known only to themselves via the private snapshot (#254) — cuts a
## repaired wire back open on a cooldown, and their own presence never repairs,
## which is exactly the tell. The crew win the instant every wire is lit at once;
## if time runs out with any wire still dead, the saboteur wins. Server-side
## simulation only — the client renders get_snapshot().

const ARENA_HALF := 8.0
const MOVE_SPEED := 6.0
const WIRE_COUNT := 5
const WIRE_RING_RADIUS := 4.4
## How close a player must be to work a wire (repair as crew, or cut as saboteur).
const WIRE_REACH := 1.2
## Crew-seconds to fill one wire; two crew on it halve the time.
const REPAIR_SEC := 4.0
## The saboteur can cut at most this often.
const CUT_COOLDOWN_SEC := 4.0
const DURATION_SEC := 60.0

var positions := {}
var move_dirs := {}
## One dict per wire: {pos: Vector2, fixed: bool, progress: float}.
var wires: Array = []
var saboteur := -1
var cut_cooldown := 0.0


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"faulty_wiring",
				"name": "Faulty Wiring",
				"category": MinigameMeta.Category.SABOTAGE,
				"min_players": 4,
				"max_players": 6,
				"duration_sec": DURATION_SEC,
				"rules":
				(
					"Light every wire at once to fix the circuit — but one of you is a"
					+ " saboteur cutting them back open. Crew: flood the wires together."
					+ " Saboteur: keep just one dark until the clock runs out."
				),
				"controls": "Move — WASD / left stick · Cut (saboteur) — SPACE / pad A",
			}
		)
	)


func _setup() -> void:
	saboteur = slots[rng.randi_range(0, slots.size() - 1)]
	for i in slots.size():
		var slot: int = slots[i]
		var angle := TAU * i / slots.size()
		positions[slot] = Vector2(cos(angle), sin(angle)) * (ARENA_HALF * 0.25)
		move_dirs[slot] = Vector2.ZERO
	for w in WIRE_COUNT:
		# Start the ring at the top and go clockwise so the view matches.
		var angle := TAU * w / WIRE_COUNT - PI / 2.0
		(
			wires
			. append(
				{
					"pos": Vector2(cos(angle), sin(angle)) * WIRE_RING_RADIUS,
					"fixed": false,
					"progress": 0.0,
				}
			)
		)


func _handle_input(slot: int, data: Dictionary) -> void:
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if data.get("act", false) and slot == saboteur:
		_cut(slot)


## Saboteur-only: reopen the nearest lit wire within reach, then wait out the
## cooldown before the next cut.
func _cut(slot: int) -> void:
	if cut_cooldown > 0.0:
		return
	var target := _nearest_wire(positions[slot], true)
	if target < 0:
		return
	wires[target].fixed = false
	wires[target].progress = 0.0
	cut_cooldown = CUT_COOLDOWN_SEC


func _tick(delta: float) -> void:
	cut_cooldown = maxf(cut_cooldown - delta, 0.0)
	_move(delta)
	_repair(delta)
	if _all_fixed():
		finish(_crew_first())


func _move(delta: float) -> void:
	for slot: int in slots:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.clamp(
			Vector2(-ARENA_HALF, -ARENA_HALF), Vector2(ARENA_HALF, ARENA_HALF)
		)


## Broken wires fill by the number of CREW on them; the saboteur is skipped, so
## a wire under only the saboteur never moves — standing and not fixing is the
## tell the crew has to read.
func _repair(delta: float) -> void:
	for wire: Dictionary in wires:
		if wire.fixed:
			continue
		var hands := 0
		for slot: int in slots:
			if slot == saboteur:
				continue
			if positions[slot].distance_to(wire.pos) <= WIRE_REACH:
				hands += 1
		if hands == 0:
			continue
		wire.progress = minf(wire.progress + hands * delta / REPAIR_SEC, 1.0)
		if wire.progress >= 1.0:
			wire.fixed = true


func _nearest_wire(pos: Vector2, want_fixed: bool) -> int:
	var best := -1
	var best_dist := WIRE_REACH
	for w in wires.size():
		if bool(wires[w].fixed) != want_fixed:
			continue
		var dist: float = pos.distance_to(wires[w].pos)
		if dist <= best_dist:
			best_dist = dist
			best = w
	return best


func _all_fixed() -> bool:
	for wire: Dictionary in wires:
		if not wire.fixed:
			return false
	return true


func _crew() -> Array:
	var crew: Array = []
	for slot: int in slots:
		if slot != saboteur:
			crew.append(slot)
	return crew


func _crew_first() -> Array:
	return [_crew(), [saboteur]]


func _saboteur_first() -> Array:
	return [[saboteur], _crew()]


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	var wire_list: Array = []
	var fixed_count := 0
	for wire: Dictionary in wires:
		if wire.fixed:
			fixed_count += 1
		(
			wire_list
			. append(
				[
					snappedf(wire.pos.x, 0.01),
					snappedf(wire.pos.y, 0.01),
					1 if wire.fixed else 0,
					snappedf(wire.progress, 0.01),
				]
			)
		)
	return {"players": players, "wires": wire_list, "fixed": fixed_count, "total": WIRE_COUNT}


## Only the saboteur learns they are the saboteur (#254); the shared snapshot
## above stays anonymous, so the crew has to deduce who isn't pulling their weight.
func get_private_snapshot(slot: int) -> Dictionary:
	return {"saboteur": true} if slot == saboteur else {}


## Timeout: a wire is still dead, so the saboteur held the line and wins.
func _rank_players() -> Array:
	return _saboteur_first()
