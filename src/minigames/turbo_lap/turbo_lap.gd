class_name TurboLap
extends MinigameBase
## Turbo Lap (M14-02, PHASE2.md §8): a kart racer — exactly one lap. Drift
## to bank a mini-turbo, ride the boost pads, and lob what the item pads
## hand you (homing shell, oil slick, boost). Finish order is placement;
## the timeout ranks stragglers by lap progress. Server-side sim only.
##
## The track is a waypoint loop (ellipse centerline + half-width). Handling
## is arcade-simple by design: heading + scalar speed, steering scaled by
## speed, drift multiplying turn rate while it charges the release boost.

const WAYPOINT_COUNT := 16
const TRACK_RX := 11.0
const TRACK_RY := 7.0
const TRACK_HALF_WIDTH := 2.2
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

const ITEM_NONE := 0
const ITEM_SHELL := 1
const ITEM_OIL := 2
const ITEM_BOOST := 3

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
					"Steer/Gas/Brake — A/D/W/S / left stick · Drift — Space / pad A"
					+ " · Item — E / pad X"
				),
				"name": "Turbo Lap",
				"category": MinigameMeta.Category.SKILL,
				"min_players": 2,
				"max_players": 12,
				"duration_sec": 90.0,
				"rules": "One lap, winner takes it! Drift to charge a boost, grab item pads.",
			}
		)
	)


## Ellipse centerline, counterclockwise from the rightmost point (the
## start/finish line). Static so the view draws the identical ribbon.
static func waypoints() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in WAYPOINT_COUNT:
		var angle := TAU * float(i) / float(WAYPOINT_COUNT)
		points.append(Vector2(cos(angle) * TRACK_RX, sin(angle) * TRACK_RY))
	return points


## Boost pads sit on the two long straights; item pads a quarter-lap apart.
static func boost_pad_positions() -> Array[Vector2]:
	var points := waypoints()
	return [points[3], points[11]]


static func item_pad_positions() -> Array[Vector2]:
	var points := waypoints()
	return [points[1], points[6], points[13]]


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
	if data.has("mx"):
		kart.steer = clampf(float(data.get("mx", 0.0)), -1.0, 1.0)
		# Stick/W-S convention: up is negative y, so throttle = -my.
		kart.throttle = clampf(-float(data.get("my", 0.0)), -1.0, 1.0)
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
		return float(WAYPOINT_COUNT) + 1.0
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
		# Coast across the line, easing to a stop.
		kart.speed = move_toward(float(kart.speed), 0.0, COAST_DECEL * delta)
		_integrate(kart, delta)
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
	return (
		bool(kart.drift_held)
		and absf(float(kart.steer)) > 0.3
		and float(kart.speed) > DRIFT_MIN_SPEED
	)


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


func _on_track(pos: Vector2) -> bool:
	var points := waypoints()
	var best := INF
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var closest := Geometry2D.get_closest_point_to_segment(pos, a, b)
		best = minf(best, pos.distance_to(closest))
	return best <= TRACK_HALF_WIDTH


func _capture_waypoints(slot: int, kart: Dictionary) -> void:
	var points := waypoints()
	var target: Vector2 = points[int(kart.next_wp) % WAYPOINT_COUNT]
	if (kart.pos as Vector2).distance_to(target) > CAPTURE_RADIUS:
		return
	kart.captured = int(kart.captured) + 1
	kart.next_wp = int(kart.next_wp) + 1
	if int(kart.captured) >= WAYPOINT_COUNT + 1:
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
