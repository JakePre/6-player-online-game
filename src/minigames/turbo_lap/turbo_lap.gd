class_name TurboLap
extends MinigameBase
## Turbo Lap (M14-02, PHASE2.md §8): a kart racer over LAP_COUNT laps. Drift
## to bank a mini-turbo, ride the boost pads, and lob what the item pads
## hand you (homing shell, oil slick, boost). Finish order is placement;
## the timeout ranks stragglers by lap progress. Server-side sim only.
##
## The track is a waypoint loop (a shaped centerline + half-width, #785).
## Handling is arcade-simple by design: heading + scalar speed, steering scaled
## by speed, drift multiplying turn rate while it charges the release boost.

const WAYPOINT_COUNT := 28
## Laps per race (#785): the owner asked for more than one. Finish after
## capturing every waypoint this many times.
const LAP_COUNT := 3
const TRACK_RX := 11.0
const TRACK_RY := 7.0
const TRACK_HALF_WIDTH := 2.2
## Shaped-course modulation (#785): smooth deterministic tweaks to the base
## ellipse radius so the circuit reads as a real track with varied corners — a
## couple of sweepers and a tighter turn — instead of a plain oval. Kept well
## under the base radii so the loop never pinches or self-intersects.
const COURSE_RX_WOBBLE := 0.13
const COURSE_RX_WOBBLE2 := 0.05
const COURSE_RY_WOBBLE := 0.12
const COURSE_RY_TILT := 0.06
## Reaching this close to the next waypoint captures it (generous — the
## checkpoint ring spans the whole track width).
const CAPTURE_RADIUS := 2.6
const OFFTRACK_GRIP := 0.45

const MAX_SPEED := 9.0
const ACCEL := 7.0
const BRAKE_DECEL := 12.0
const REVERSE_MAX := 3.0
const COAST_DECEL := 4.0
const STEER_RATE := 2.6
const DRIFT_STEER_MULT := 1.6
const DRIFT_MIN_SPEED := 5.0
## #1067 pad-friendly drift: with gas on a button, slamming the stick to a
## near-full deflection at speed IS the drift input — no third button needed.
const AUTO_DRIFT_STEER := 0.85
## Mini-turbo tiers: hold a drift this long for a small/big release boost.
const DRIFT_BOOST_AT := 0.5
const DRIFT_BIG_AT := 1.2
const BOOST_SMALL_SEC := 1.2
const BOOST_BIG_SEC := 1.8
const BOOST_MULT := 1.3
const PAD_BOOST_SEC := 1.2

const SPIN_SEC := 1.1
const SPIN_RATE := 10.0
const SHELL_SPEED := 14.0
const SHELL_LIFE_SEC := 6.0
const SHELL_HIT_RADIUS := 0.8
const OIL_LIFE_SEC := 8.0
const OIL_HIT_RADIUS := 0.7
const OIL_OWNER_GRACE_SEC := 1.0
const MAX_OILS := 6
const PAD_RESPAWN_SEC := 4.0
const PAD_RADIUS := 1.0

## Pit row (#930): a finished kart used to just coast dead-ahead on whatever
## heading it crossed the line with, which could carry it straight off the
## track into the infield. Instead it eases toward a parking slot beside the
## start line, one per finish order, so finishers read as a tidy row.
const PIT_ROW_SIDE_OFFSET := TRACK_HALF_WIDTH + 3.0
const PIT_ROW_SPACING := 1.6
const PIT_ARRIVE_RADIUS := 0.4
const PIT_EASE_SPEED := 4.0

const ITEM_NONE := 0
const ITEM_SHELL := 1
const ITEM_OIL := 2
const ITEM_BOOST := 3

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_HEADING := 2
const PS_ITEM := 3
const PS_BITS := 4
const PS_COUNT := 5
## #946 wire-shape tripwire: the declared type of each slot in a `players`
## snapshot row. Validated by test_snapshot_schema against get_snapshot().
const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_INT]

const SH_X := 0
const SH_Y := 1

const OL_X := 0
const OL_Y := 1

const PD_X := 0
const PD_Y := 1
const PD_AVAILABLE := 2

## The shaped centerline is the same every round, so it's built once and cached
## (every kart's on-track / progress / capture check calls waypoints() per tick).
static var _waypoint_cache: PackedVector2Array

## Kart state per slot: pos/heading/speed plus drift, boost, spin, item,
## and checkpoint progress.
var karts := {}
var shells: Array[Dictionary] = []
var oils: Array[Dictionary] = []
var item_pads: Array[Dictionary] = []
## Slots that crossed the line, in finish order (same-tick ties grouped).
var finish_order: Array = []

var _finished_this_tick: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"turbo_lap",
				"controls":
				(
					"Steer — A/D / stick · Gas — hold Space / pad A · Brake — S / "
					+ "stick down · Drift — steer hard at speed · Item — E / pad X"
				),
				# Device-aware buttons (#608); steering stays literal (axis hint).
				"control_hints":
				[
					"Steer — A/D / stick · Gas — hold ",
					{"action": &"action_primary"},
					" · Item — ",
					{"action": &"action_secondary"},
					" · Steer hard at speed to drift",
				],
				# Structured spec (#832/#844): kart-standard (#1067) — gas is a
				# held button, the stick only steers, a hard turn drifts.
				"control_spec":
				[
					{"verb": "Steer", "input": InputGlyphs.CLUSTER_MOVE_LR},
					{"verb": "Gas", "input": &"action_primary", "modifier": "hold"},
					{"verb": "Drift", "input": InputGlyphs.CLUSTER_MOVE_LR, "alt": "hard turn"},
					{"verb": "Item", "input": &"action_secondary"},
				],
				"name": "Turbo Lap",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 12,
				"duration_sec": 90.0,
				"rules":
				# Stale "One lap" text (#961): the race has been LAP_COUNT laps
				# since the #785 course rebuild — off the constant so it can't drift.
				"%d laps, winner takes it! Drift to charge a boost, grab item pads." % LAP_COUNT,
			}
		)
	)


## Shaped centerline (#785), counterclockwise from the start/finish waypoint
## (index 0). An ellipse base with smooth radius modulations gives it varied
## corners without a plain-oval look; it stays a valid non-self-intersecting loop
## because the wobble is well under the base radii. Static + cached so the view
## draws the identical ribbon and the per-tick checks stay cheap.
static func waypoints() -> PackedVector2Array:
	if _waypoint_cache.size() == WAYPOINT_COUNT:
		return _waypoint_cache
	var points := PackedVector2Array()
	for i in WAYPOINT_COUNT:
		var angle := TAU * float(i) / float(WAYPOINT_COUNT)
		var rx := (
			TRACK_RX
			* (
				1.0
				+ COURSE_RX_WOBBLE * cos(2.0 * angle)
				+ COURSE_RX_WOBBLE2 * cos(3.0 * angle + 0.6)
			)
		)
		var ry := (
			TRACK_RY * (1.0 + COURSE_RY_WOBBLE * sin(2.0 * angle) - COURSE_RY_TILT * cos(angle))
		)
		points.append(Vector2(cos(angle) * rx, sin(angle) * ry))
	_waypoint_cache = points
	return points


## Largest world-space extent of the course, for sizing the arena floor/camera.
static func course_bound() -> float:
	var bound := 0.0
	for point: Vector2 in waypoints():
		bound = maxf(bound, maxf(absf(point.x), absf(point.y)))
	return bound


## Boost pads on two of the straights; item pads spread roughly evenly around
## the lap. Indices chosen for the wider (28-waypoint) shaped course.
static func boost_pad_positions() -> Array[Vector2]:
	var points := waypoints()
	return [points[6], points[20]]


static func item_pad_positions() -> Array[Vector2]:
	var points := waypoints()
	return [points[2], points[12], points[23]]


func _setup() -> void:
	for pad_pos in item_pad_positions():
		item_pads.append({"pos": pad_pos, "taken_until": 0.0})
	var points := waypoints()
	var tangent := (points[1] - points[0]).normalized()
	var side := Vector2(-tangent.y, tangent.x)
	for i in slots.size():
		# 3-wide start grid behind the line, outside pole first.
		var row := floori(float(i) / 3.0)
		var col := i % 3
		var grid_pos := points[0] - tangent * (1.2 + 1.6 * row) + side * (float(col) - 1.0) * 1.4
		karts[slots[i]] = {
			"pos": grid_pos,
			"heading": tangent.angle(),
			"speed": 0.0,
			"steer": 0.0,
			"throttle": 0.0,
			"gas": false,
			"drift_held": false,
			"drift_charge": 0.0,
			"boost_left": 0.0,
			"spin_left": 0.0,
			"oil_grace": 0.0,
			"item": ITEM_NONE,
			"next_wp": 1,
			"captured": 0,
			"finished": false,
		}


func _handle_input(slot: int, data: Dictionary) -> void:
	var kart: Dictionary = karts.get(slot, {})
	if kart.is_empty() or bool(kart.finished):
		return
	# Pad-standard gas button (#1067, owner playtest): hold action_primary for
	# full throttle so the stick only steers — diagonal-stick throttle was
	# "not conducive to success". Stick/W-S throttle still works underneath.
	if data.has("gas"):
		kart.gas = bool(data.gas)
		if bool(kart.gas):
			kart.throttle = 1.0
	if data.has("mx"):
		kart.steer = clampf(float(data.get("mx", 0.0)), -1.0, 1.0)
		# Stick/W-S convention: up is negative y, so throttle = -my; the held
		# gas button overrides with full forward.
		var stick := clampf(-float(data.get("my", 0.0)), -1.0, 1.0)
		kart.throttle = 1.0 if bool(kart.gas) else stick
	if data.has("drift"):
		kart.drift_held = bool(data.drift)
	if data.get("use", false):
		_use_item(slot, kart)


func _tick(delta: float) -> void:
	_finished_this_tick = []
	for slot: int in karts:
		_tick_kart(slot, karts[slot], delta)
	if not _finished_this_tick.is_empty():
		finish_order.append(_finished_this_tick.duplicate())
	_tick_shells(delta)
	_tick_oils(delta)
	if _all_finished():
		finish(_rank_players())


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in karts:
		var kart: Dictionary = karts[slot]
		var pos: Vector2 = kart.pos
		var bits := 0
		if float(kart.spin_left) > 0.0:
			bits |= 1
		if float(kart.boost_left) > 0.0:
			bits |= 2
		if _is_drifting(kart):
			bits |= 4
		if bool(kart.finished):
			bits |= 8
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			snappedf(float(kart.heading), 0.01),
			int(kart.item),
			bits,
		]
	var shell_list: Array = []
	for shell in shells:
		var pos: Vector2 = shell.pos
		shell_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	var oil_list: Array = []
	for oil in oils:
		var pos: Vector2 = oil.pos
		oil_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	var pad_list: Array = []
	for pad in item_pads:
		var pos: Vector2 = pad.pos
		pad_list.append([pos.x, pos.y, 1 if elapsed >= float(pad.taken_until) else 0])
	return {
		"players": players,
		"shells": shell_list,
		"oils": oil_list,
		"pads": pad_list,
		"standings": _standings(),
	}


## Live standings: finishers first (in order), then racers by progress.
func _standings() -> Array:
	var order: Array = []
	for group: Array in finish_order:
		order.append_array(group)
	var racing: Array = []
	for slot: int in karts:
		if not bool(karts[slot].finished):
			racing.append(slot)
	racing.sort_custom(func(a: int, b: int) -> bool: return _progress(a) > _progress(b))
	order.append_array(racing)
	return order


func _rank_players() -> Array:
	var placements: Array = []
	for group: Array in finish_order:
		placements.append(group.duplicate())
	var racing: Array = []
	for slot: int in karts:
		if not bool(karts[slot].finished):
			racing.append(slot)
	racing.sort_custom(func(a: int, b: int) -> bool: return _progress(a) > _progress(b))
	# Group timeout stragglers whose progress ties within a checkpoint hair.
	var group: Array = []
	for slot: int in racing:
		if group.is_empty() or absf(_progress(int(group[-1])) - _progress(slot)) < 0.01:
			group.append(slot)
		else:
			placements.append(group)
			group = [slot]
	if not group.is_empty():
		placements.append(group)
	return placements


## Lap progress in captured checkpoints plus the fraction toward the next.
func _progress(slot: int) -> float:
	var kart: Dictionary = karts[slot]
	if bool(kart.finished):
		return float(WAYPOINT_COUNT * LAP_COUNT) + 1.0
	var points := waypoints()
	var next: Vector2 = points[int(kart.next_wp) % WAYPOINT_COUNT]
	var prev: Vector2 = points[(int(kart.next_wp) - 1 + WAYPOINT_COUNT) % WAYPOINT_COUNT]
	var seg_len := prev.distance_to(next)
	var toward := 1.0 - clampf((kart.pos as Vector2).distance_to(next) / seg_len, 0.0, 1.0)
	return float(kart.captured) + toward


func _tick_kart(slot: int, kart: Dictionary, delta: float) -> void:
	kart.oil_grace = maxf(0.0, float(kart.oil_grace) - delta)
	kart.boost_left = maxf(0.0, float(kart.boost_left) - delta)
	if bool(kart.finished):
		_ease_to_pit(slot, kart, delta)
		return
	if float(kart.spin_left) > 0.0:
		kart.spin_left = float(kart.spin_left) - delta
		kart.heading = float(kart.heading) + SPIN_RATE * delta
		kart.speed = move_toward(float(kart.speed), 0.0, BRAKE_DECEL * delta)
		_integrate(kart, delta)
		return
	_steer(kart, delta)
	_throttle(kart, delta)
	_integrate(kart, delta)
	_capture_waypoints(slot, kart)
	_touch_pads(kart)


func _steer(kart: Dictionary, delta: float) -> void:
	var speed := float(kart.speed)
	if absf(speed) < 0.2:
		kart.drift_charge = 0.0
		return
	var drifting := _is_drifting(kart)
	var rate := STEER_RATE * (DRIFT_STEER_MULT if drifting else 1.0)
	# Steering authority grows with speed, capping at full speed/2.
	var authority := clampf(absf(speed) / (MAX_SPEED / 2.0), 0.0, 1.0)
	kart.heading = float(kart.heading) + float(kart.steer) * rate * authority * delta
	if drifting:
		kart.drift_charge = float(kart.drift_charge) + delta
	else:
		_release_drift(kart)


func _is_drifting(kart: Dictionary) -> bool:
	# Two ways in (#1067): the explicit drift input (bots, legacy), or gas held
	# with the stick slammed near-full — the pad-standard hard-turn drift.
	var wants := (
		bool(kart.drift_held)
		or (bool(kart.get("gas", false)) and absf(float(kart.steer)) >= AUTO_DRIFT_STEER)
	)
	return wants and absf(float(kart.steer)) > 0.3 and float(kart.speed) > DRIFT_MIN_SPEED


func _release_drift(kart: Dictionary) -> void:
	var charge := float(kart.drift_charge)
	kart.drift_charge = 0.0
	if charge >= DRIFT_BIG_AT:
		kart.boost_left = maxf(float(kart.boost_left), BOOST_BIG_SEC)
	elif charge >= DRIFT_BOOST_AT:
		kart.boost_left = maxf(float(kart.boost_left), BOOST_SMALL_SEC)


func _throttle(kart: Dictionary, delta: float) -> void:
	var top := MAX_SPEED
	if not _on_track(kart.pos):
		top *= OFFTRACK_GRIP
	if float(kart.boost_left) > 0.0:
		top = MAX_SPEED * BOOST_MULT
	var throttle := float(kart.throttle)
	var speed := float(kart.speed)
	if float(kart.boost_left) > 0.0:
		kart.speed = move_toward(speed, top, ACCEL * 2.0 * delta)
	elif throttle > 0.0:
		kart.speed = move_toward(speed, top * throttle, ACCEL * delta)
	elif throttle < 0.0:
		var target := REVERSE_MAX * throttle
		kart.speed = move_toward(speed, target, BRAKE_DECEL * delta)
	else:
		kart.speed = move_toward(speed, 0.0, COAST_DECEL * delta)
	# Off-track always claws speed down toward the grass cap.
	if not _on_track(kart.pos) and float(kart.speed) > top:
		kart.speed = move_toward(float(kart.speed), top, BRAKE_DECEL * delta)


func _integrate(kart: Dictionary, delta: float) -> void:
	var dir := Vector2.from_angle(float(kart.heading))
	kart.pos = (kart.pos as Vector2) + dir * float(kart.speed) * delta
	# Solid track walls (#1041): the view fences both edges at ±TRACK_HALF_WIDTH,
	# so a racing kart is clamped back onto that ribbon instead of driving through
	# the barriers — it scrapes along the wall (position clamp only; heading/speed
	# are untouched, so it slides rather than dead-stopping). Finished karts are
	# exempt: they ease to a pit slot that deliberately sits outside the ribbon.
	if not bool(kart.finished):
		_confine_to_track(kart)


## Push a kart back onto the track ribbon if it has crossed the ±TRACK_HALF_WIDTH
## wall around the centerline (#1041), projecting it to the nearest boundary point.
func _confine_to_track(kart: Dictionary) -> void:
	var pos: Vector2 = kart.pos
	var nearest := SimGeometry.nearest_point_on_polyline(pos, waypoints(), true)
	var offset := pos - nearest
	var dist := offset.length()
	if dist <= TRACK_HALF_WIDTH:
		return
	var normal := offset / dist if dist > 0.0001 else Vector2.RIGHT
	kart.pos = nearest + normal * TRACK_HALF_WIDTH


## Steers a finished kart toward its pit slot and eases to a stop there,
## instead of coasting dead-ahead off whatever heading it finished on (#930).
func _ease_to_pit(slot: int, kart: Dictionary, delta: float) -> void:
	var target := _pit_slot(_finish_rank_index(slot))
	var to_target: Vector2 = target - (kart.pos as Vector2)
	if to_target.length() <= PIT_ARRIVE_RADIUS:
		kart.pos = target
		kart.speed = 0.0
		return
	kart.heading = to_target.angle()
	kart.speed = move_toward(float(kart.speed), PIT_EASE_SPEED, ACCEL * delta)
	_integrate(kart, delta)


## This slot's place in the parking row, beside the start line. Offsets
## radially outward from the course center (not perpendicular to the start
## tangent) — the shaped course (#785) isn't a circle, so a fixed-length
## tangent-perpendicular offset from a wide point can still land back inside
## TRACK_HALF_WIDTH of a different stretch of the loop.
func _pit_slot(rank_index: int) -> Vector2:
	var points := waypoints()
	var start := points[0]
	var outward := start.normalized()
	var tangent := (points[1] - points[0]).normalized()
	return start + outward * PIT_ROW_SIDE_OFFSET - tangent * float(rank_index) * PIT_ROW_SPACING


## Index into finish_order's flattened arrival sequence (ties keep group
## order, but each still gets a distinct parking slot).
func _finish_rank_index(slot: int) -> int:
	var index := 0
	for group: Array in finish_order:
		if slot in group:
			return index + group.find(slot)
		index += group.size()
	return index


func _on_track(pos: Vector2) -> bool:
	# Distance to the closed waypoint loop — shared math (#945).
	return SimGeometry.distance_to_polyline(pos, waypoints(), true) <= TRACK_HALF_WIDTH


func _capture_waypoints(slot: int, kart: Dictionary) -> void:
	var points := waypoints()
	var target: Vector2 = points[int(kart.next_wp) % WAYPOINT_COUNT]
	if (kart.pos as Vector2).distance_to(target) > CAPTURE_RADIUS:
		return
	kart.captured = int(kart.captured) + 1
	kart.next_wp = int(kart.next_wp) + 1
	# Finished after LAP_COUNT full laps around the waypoint loop (#785).
	if int(kart.captured) >= WAYPOINT_COUNT * LAP_COUNT:
		kart.finished = true
		_finished_this_tick.append(slot)


func _touch_pads(kart: Dictionary) -> void:
	var pos: Vector2 = kart.pos
	for pad_pos in boost_pad_positions():
		if pos.distance_to(pad_pos) <= PAD_RADIUS:
			kart.boost_left = maxf(float(kart.boost_left), PAD_BOOST_SEC)
	if int(kart.item) != ITEM_NONE:
		return
	for pad in item_pads:
		if elapsed < float(pad.taken_until):
			continue
		if pos.distance_to(pad.pos) <= PAD_RADIUS:
			pad.taken_until = elapsed + PAD_RESPAWN_SEC
			kart.item = rng.randi_range(ITEM_SHELL, ITEM_BOOST)
			return


func _use_item(slot: int, kart: Dictionary) -> void:
	var item := int(kart.item)
	kart.item = ITEM_NONE
	match item:
		ITEM_BOOST:
			kart.boost_left = maxf(float(kart.boost_left), BOOST_BIG_SEC)
		ITEM_OIL:
			if oils.size() < MAX_OILS:
				var behind := -Vector2.from_angle(float(kart.heading)) * 1.2
				oils.append(
					{"pos": (kart.pos as Vector2) + behind, "until": elapsed + OIL_LIFE_SEC}
				)
				kart.oil_grace = OIL_OWNER_GRACE_SEC
		ITEM_SHELL:
			var target := _slot_ahead_of(slot)
			if target >= 0:
				shells.append(
					{"pos": kart.pos, "target": target, "until": elapsed + SHELL_LIFE_SEC}
				)


## The victim a shell hunts: the racer directly ahead of `slot` in the
## standings (the leader's shell fizzles — being first has perks).
func _slot_ahead_of(slot: int) -> int:
	var order := _standings()
	var index := order.find(slot)
	if index <= 0:
		return -1
	return int(order[index - 1])


func _tick_shells(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for shell in shells:
		var target: Dictionary = karts.get(int(shell.target), {})
		if target.is_empty() or elapsed >= float(shell.until):
			continue
		var to_target := (target.pos as Vector2) - (shell.pos as Vector2)
		if to_target.length() <= SHELL_HIT_RADIUS:
			_spin_out(target)
			continue
		shell.pos = (shell.pos as Vector2) + to_target.normalized() * SHELL_SPEED * delta
		alive.append(shell)
	shells = alive


func _tick_oils(_delta: float) -> void:
	var alive: Array[Dictionary] = []
	for oil in oils:
		if elapsed >= float(oil.until):
			continue
		for slot: int in karts:
			var kart: Dictionary = karts[slot]
			if bool(kart.finished) or float(kart.spin_left) > 0.0:
				continue
			if float(kart.oil_grace) > 0.0:
				continue
			if (kart.pos as Vector2).distance_to(oil.pos) <= OIL_HIT_RADIUS:
				_spin_out(kart)
				oil.until = 0.0
		if elapsed < float(oil.until):
			alive.append(oil)
	oils = alive


func _spin_out(kart: Dictionary) -> void:
	if bool(kart.finished):
		return
	kart.spin_left = SPIN_SEC
	kart.drift_charge = 0.0
	kart.boost_left = 0.0


func _all_finished() -> bool:
	for slot: int in karts:
		if not bool(karts[slot].finished):
			return false
	return true
