class_name SideScrollSim
extends RefCounted
## Server-side 2D platformer physics (M14-00, owner-approved on #509), the
## shared bones of the side-view games (Loadout Duel, Knock-Off, Tumble Run).
## Pure math at the standard 30 Hz tick — no engine physics, so rooms stay
## deterministic and the headless server light, like every other sim.
##
## World space is y-UP (jumping increases y, gravity pulls negative); views
## flip to screen coordinates. Stage rects are authored y-up too: position
## is the bottom-left corner, so a platform's walkable lid sits at
## position.y + size.y.
##
## A game's MinigameBase sim owns one instance: feed it intents
## (set_move/press_jump), call step(delta) from _tick, read bodies back via
## body_of()/snapshot_players(). Feel tunables are public vars — Knock-Off
## raises max_air_jumps, Tumble Run loosens run_speed.

## Body half-extents (a 0.7 × 1.0 unit box).
const HALF := Vector2(0.35, 0.5)
const TERMINAL_FALL := 20.0
const EPSILON := 0.001

## Feel tunables — defaults tuned for a readable party-game jump arc
## (~2.6 u apex, ~0.74 s airtime) at run speeds that cross a 16 u stage
## in a couple of seconds.
var gravity := 38.0
var run_speed := 7.0
var run_accel := 60.0
var air_accel := 30.0
var friction := 50.0
var jump_velocity := 14.0
var max_air_jumps := 0
var coyote_sec := 0.1
var jump_buffer_sec := 0.12

## Stage geometry, set by the owning game before play: solid platforms
## block from every side; one-way platforms catch bodies falling onto
## their lid and are passable from below. `bounds` marks the playable
## region — bodies outside it show up in out_slots() (the game decides
## what falling out means).
var solids: Array[Rect2] = []
var one_way: Array[Rect2] = []
var bounds := Rect2(-12.0, -6.0, 24.0, 18.0)

# slot -> body state (pos/vel Vector2, facing ±1, grounded, timers).
var _bodies := {}


func add_body(slot: int, at: Vector2) -> void:
	_bodies[slot] = {
		"pos": at,
		"vel": Vector2.ZERO,
		"move_x": 0.0,
		"facing": 1,
		"grounded": false,
		"coyote": 0.0,
		"buffer": 0.0,
		"air_jumps": max_air_jumps,
	}


func remove_body(slot: int) -> void:
	_bodies.erase(slot)


func has_body(slot: int) -> bool:
	return _bodies.has(slot)


func body_of(slot: int) -> Dictionary:
	return _bodies.get(slot, {})


## Horizontal intent from the shared move axis, -1..1.
func set_move(slot: int, move_x: float) -> void:
	var body: Dictionary = _bodies.get(slot, {})
	if body.is_empty():
		return
	body.move_x = clampf(move_x, -1.0, 1.0)
	if absf(float(body.move_x)) > EPSILON:
		body.facing = 1 if float(body.move_x) > 0.0 else -1


## Jump press edge. Buffered, so a press landing between ticks still jumps.
func press_jump(slot: int) -> void:
	var body: Dictionary = _bodies.get(slot, {})
	if not body.is_empty():
		body.buffer = jump_buffer_sec


## Knockback/explosion shove. Any upward kick lifts the body off the ground.
func apply_impulse(slot: int, impulse: Vector2) -> void:
	var body: Dictionary = _bodies.get(slot, {})
	if body.is_empty():
		return
	body.vel = (body.vel as Vector2) + impulse
	if impulse.y > 0.0:
		body.grounded = false


func step(delta: float) -> void:
	for slot: int in _bodies:
		_step_body(_bodies[slot], delta)


## Slots whose body center has left the stage bounds (ring-out/pit fall).
func out_slots() -> Array[int]:
	var out: Array[int] = []
	for slot: int in _bodies:
		if not bounds.has_point(_bodies[slot].pos):
			out.append(slot)
	return out


## Replication-ready per-player samples: {slot: [x, y, facing, grounded]}.
## Games merge this into their get_snapshot() and append their own fields.
func snapshot_players() -> Dictionary:
	var snap := {}
	for slot: int in _bodies:
		var body: Dictionary = _bodies[slot]
		var pos: Vector2 = body.pos
		snap[slot] = [
			snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), body.facing, 1 if body.grounded else 0
		]
	return snap


func _step_body(body: Dictionary, delta: float) -> void:
	body.coyote = maxf(0.0, float(body.coyote) - delta)
	body.buffer = maxf(0.0, float(body.buffer) - delta)
	var vel: Vector2 = body.vel
	vel.x = _accelerate(body, vel.x, delta)
	vel.y = maxf(vel.y - gravity * delta, -TERMINAL_FALL)
	vel = _consume_jump(body, vel)
	var pos: Vector2 = body.pos
	var moved_x := _move_x(pos, vel, delta)
	pos = moved_x.pos
	vel = moved_x.vel
	var moved_y := _move_y(body, pos, vel, delta)
	body.pos = moved_y.pos
	body.vel = moved_y.vel
	if body.grounded:
		body.coyote = coyote_sec
		body.air_jumps = max_air_jumps


func _accelerate(body: Dictionary, vel_x: float, delta: float) -> float:
	var move_x: float = body.move_x
	var target := move_x * run_speed
	var rate := air_accel
	if body.grounded:
		rate = run_accel if absf(move_x) > EPSILON else friction
	return move_toward(vel_x, target, rate * delta)


func _consume_jump(body: Dictionary, vel: Vector2) -> Vector2:
	if float(body.buffer) <= 0.0:
		return vel
	var from_ground: bool = body.grounded or float(body.coyote) > 0.0
	if not from_ground:
		if int(body.air_jumps) <= 0:
			return vel
		body.air_jumps = int(body.air_jumps) - 1
	body.buffer = 0.0
	body.coyote = 0.0
	body.grounded = false
	vel.y = jump_velocity
	return vel


func _move_x(pos: Vector2, vel: Vector2, delta: float) -> Dictionary:
	pos.x += vel.x * delta
	for platform in solids:
		if _overlaps(pos, platform):
			var center_x := platform.position.x + platform.size.x / 2.0
			if pos.x < center_x:
				pos.x = platform.position.x - HALF.x
			else:
				pos.x = platform.end.x + HALF.x
			vel.x = 0.0
	return {"pos": pos, "vel": vel}


func _move_y(body: Dictionary, pos: Vector2, vel: Vector2, delta: float) -> Dictionary:
	var prev_bottom := pos.y - HALF.y
	pos.y += vel.y * delta
	body.grounded = false
	for platform in solids:
		if not _overlaps(pos, platform):
			continue
		if vel.y <= 0.0:
			pos.y = _top_of(platform) + HALF.y
			vel.y = 0.0
			body.grounded = true
		else:
			pos.y = _bottom_of(platform) - HALF.y
			vel.y = 0.0
	for platform in one_way:
		# Catch only bodies falling onto the lid; passable from below.
		var falling := vel.y <= 0.0
		if falling and prev_bottom >= _top_of(platform) - EPSILON and _overlaps(pos, platform):
			pos.y = _top_of(platform) + HALF.y
			vel.y = 0.0
			body.grounded = true
	return {"pos": pos, "vel": vel}


func _top_of(platform: Rect2) -> float:
	return platform.position.y + platform.size.y


func _bottom_of(platform: Rect2) -> float:
	return platform.position.y


func _overlaps(pos: Vector2, platform: Rect2) -> bool:
	return (
		pos.x + HALF.x > platform.position.x + EPSILON
		and pos.x - HALF.x < platform.end.x - EPSILON
		and pos.y + HALF.y > _bottom_of(platform) + EPSILON
		and pos.y - HALF.y < _top_of(platform) - EPSILON
	)
