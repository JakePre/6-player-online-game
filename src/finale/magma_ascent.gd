class_name MagmaAscent
extends MinigameBase
## Magma Ascent (#936, owner-locked concept, build 3 of 3): the vertical
## rising-magma finale. A tall tower of zigzag ledges (some crumbling) on the
## side-scroll bones (SideScrollSim + tumble_run's crumble plumbing); a magma
## floor rises at an accelerating pace and eats anyone it catches. Last
## climber above the magma wins the match; the rest rank by how long they
## lasted, then by height reached. The buy-in shop maps to survival: an
## extra life respawns you on a ledge above the magma, a shield shrugs one
## lick, speed is climb speed, and sabotage crumbles a rival's ledge out from
## under them. Not a roster minigame — entered via FinaleVariants (M5-02).

const STAGE_BOUNDS := Rect2(-9.0, -4.0, 18.0, 40.0)
const FLOOR_Y := -1.0
## The climb needs a jump that clears a full ledge rise while crossing (the
## shared default apex can't); same lift as tumble_run (#778).
const JUMP_VELOCITY := 18.0
const MOVE_SPEED_MULT := 1.0
const SPEED_BOOST_MULT := 1.35

const LEDGE_COUNT := 12
const LEDGE_RISE := 3.0
const LEDGE_WIDTH := 4.0
const LEDGE_THICKNESS := 0.4
const LEDGE_X := 4.2
const FIRST_LEDGE_Y := 2.0

## Crumbling footing cycles solid → gone → back, staggered by index so the
## whole tower never vanishes at once (tumble_run idiom).
const CRUMBLE_SOLID_SEC := 3.2
const CRUMBLE_GONE_SEC := 1.5
## A sabotaged ledge is forced GONE for this long, regardless of its cycle.
const SABOTAGE_GONE_SEC := 2.0

## The magma: starts just under the floor and rises, accelerating, so the
## squeeze tightens the longer the round runs.
const MAGMA_START_Y := -3.0
const MAGMA_BASE_SPEED := 0.55
const MAGMA_ACCEL := 0.035
## A magma lick bumps a survivor (shield/extra life) this far up to a safe
## ledge line so they don't instantly re-touch it.
const RESPAWN_ABOVE_MAGMA := 4.0

## get_snapshot() wire shapes (#708). players[0..3] match SideScrollView's
## render_side_scroll contract (x, y, facing, grounded); PS_FLAGS is this
## game's own tail (bit0 shielded, bit1 eliminated).
const PS_X := 0
const PS_Y := 1
const PS_FACING := 2
const PS_GROUNDED := 3
const PS_FLAGS := 4
const PS_COUNT := 5

var sim: SideScrollSim
var lives := {}
var shields := {}
var speed_boosts := {}
var sabotage_tokens := {}
var eliminated := {}
## Highest world-y each climber reached (survival tiebreak).
var peak_height := {}
var magma_y := MAGMA_START_Y
## Parallel to _crumble_indices(): true while that ledge is solid.
var crumble_state: Array[bool] = []
## Climbers in elimination order; simultaneous drops share a tie group.
var elimination_order: Array = []

var _loadout_items := {}
var _crumble_clock := 0.0
## index -> seconds of forced-gone left from a sabotage (overrides the cycle).
var _sabotaged := {}
var _pending_elims: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"magma_ascent",
				"controls": "Move — A/D / stick · Jump — W / stick up · Sabotage — E / pad X",
				"name": "Magma Ascent",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 90.0,
				"rules":
				(
					"Climb! The magma rises faster and faster — last one above it wins"
					+ " the match. Mind the crumbling ledges."
				),
			}
		)
	)


static func ledges() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for i in LEDGE_COUNT:
		var side := 1.0 if i % 2 == 0 else -1.0
		var y := FIRST_LEDGE_Y + float(i) * LEDGE_RISE
		rects.append(Rect2(side * LEDGE_X - LEDGE_WIDTH / 2.0, y, LEDGE_WIDTH, LEDGE_THICKNESS))
	return rects


## Always-solid base floor plus a capstone platform at the top.
static func solid_platforms() -> Array[Rect2]:
	return (
		[
			Rect2(-8.0, FLOOR_Y - 1.0, 16.0, 1.0),
			Rect2(-3.0, FIRST_LEDGE_Y + float(LEDGE_COUNT) * LEDGE_RISE, 6.0, 0.5),
		]
		as Array[Rect2]
	)


## Every third ledge crumbles; the rest are stable footing (tumble_run rule).
static func _crumble_indices() -> Array[int]:
	var out: Array[int] = []
	for i in LEDGE_COUNT:
		if i % 3 == 1:
			out.append(i)
	return out


func _setup() -> void:
	sim = SideScrollSim.new()
	sim.bounds = STAGE_BOUNDS
	sim.jump_velocity = JUMP_VELOCITY
	crumble_state.resize(LEDGE_COUNT)
	crumble_state.fill(true)
	_rebuild_platforms()
	magma_y = MAGMA_START_Y
	var spawns := _spawn_points()
	for i in slots.size():
		var slot: int = slots[i]
		sim.add_body(slot, spawns[i])
		lives[slot] = 0
		shields[slot] = false
		speed_boosts[slot] = false
		sabotage_tokens[slot] = 0
		eliminated[slot] = false
		peak_height[slot] = spawns[i].y


## FinaleShop.loadouts() interface (M5-01/M5-02): extra lives = respawns above
## the magma, shield = one free lick, speed = climb speed, sabotage = crumble.
func apply_loadouts(shop_loadouts: Dictionary) -> void:
	for slot: int in shop_loadouts:
		if slot not in slots:
			continue
		var items: Dictionary = shop_loadouts[slot].get("items", {})
		_loadout_items[slot] = items
		lives[slot] = int(items.get(&"extra_life", 0))
		shields[slot] = int(items.get(&"shield", 0)) > 0
		speed_boosts[slot] = int(items.get(&"speed_boost", 0)) > 0
		sabotage_tokens[slot] = int(items.get(&"sabotage_token", 0))


func _spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var count := slots.size()
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		points.append(Vector2(lerpf(-6.0, 6.0, t), FLOOR_Y + 0.7))
	return points


## Floor + capstone plus every currently-solid crumble ledge and all stable
## ledges, pushed to the sim as one-way climbing platforms.
func _rebuild_platforms() -> void:
	sim.solids = solid_platforms()
	var one_way: Array[Rect2] = []
	var all := ledges()
	for i in all.size():
		if crumble_state[i]:
			one_way.append(all[i])
	sim.one_way = one_way


func _handle_input(slot: int, data: Dictionary) -> void:
	if bool(eliminated[slot]):
		return
	if data.has("sabotage"):
		_handle_sabotage(slot, data.sabotage)
		return
	if data.has("mx"):
		sim.set_move(slot, clampf(float(data.mx), -1.0, 1.0) * _speed_mult(slot))
	if data.get("jump", false):
		sim.press_jump(slot)


func _speed_mult(slot: int) -> float:
	return SPEED_BOOST_MULT if bool(speed_boosts[slot]) else MOVE_SPEED_MULT


func _tick(delta: float) -> void:
	_tick_crumble(delta)
	_tick_magma(delta)
	sim.step(delta)
	_track_heights()
	_check_magma_catches()
	_flush_eliminations()
	_check_end()


func _tick_magma(delta: float) -> void:
	# Accelerating rise: speed grows with elapsed time.
	var speed := MAGMA_BASE_SPEED + MAGMA_ACCEL * elapsed
	magma_y += speed * delta


func _tick_crumble(delta: float) -> void:
	_crumble_clock += delta
	var cycle := CRUMBLE_SOLID_SEC + CRUMBLE_GONE_SEC
	var crumble := _crumble_indices()
	var changed := false
	for offset in crumble.size():
		var index: int = crumble[offset]
		# A live sabotage forces the ledge gone regardless of its cycle.
		if _sabotaged.has(index):
			_sabotaged[index] = float(_sabotaged[index]) - delta
			if float(_sabotaged[index]) <= 0.0:
				_sabotaged.erase(index)
			if crumble_state[index]:
				crumble_state[index] = false
				changed = true
			continue
		var phase_offset := float(offset) * cycle / maxf(1.0, float(crumble.size()))
		var t := fmod(_crumble_clock + phase_offset, cycle)
		var solid := t < CRUMBLE_SOLID_SEC
		if crumble_state[index] != solid:
			crumble_state[index] = solid
			changed = true
	if changed:
		_rebuild_platforms()


func _track_heights() -> void:
	for slot: int in slots:
		if bool(eliminated[slot]):
			continue
		var body := sim.body_of(slot)
		if not body.is_empty():
			peak_height[slot] = maxf(float(peak_height[slot]), float((body.pos as Vector2).y))


## Anyone whose feet are under the magma line takes a lick: a shield shrugs it
## (and bumps them up), an extra life respawns them above it, otherwise they
## are eliminated.
func _check_magma_catches() -> void:
	for slot: int in slots:
		if bool(eliminated[slot]):
			continue
		var body := sim.body_of(slot)
		if body.is_empty():
			continue
		if float((body.pos as Vector2).y) - SideScrollSim.HALF.y > magma_y:
			continue
		if bool(shields[slot]):
			shields[slot] = false
			_lift_above_magma(slot)
		elif int(lives[slot]) > 0:
			lives[slot] = int(lives[slot]) - 1
			_lift_above_magma(slot)
		else:
			eliminated[slot] = true
			sim.remove_body(slot)
			_pending_elims.append(slot)


func _lift_above_magma(slot: int) -> void:
	var x: float = (sim.body_of(slot).pos as Vector2).x
	sim.remove_body(slot)
	sim.add_body(slot, Vector2(clampf(x, -6.0, 6.0), magma_y + RESPAWN_ABOVE_MAGMA))


func _flush_eliminations() -> void:
	if _pending_elims.is_empty():
		return
	elimination_order.append(_pending_elims.duplicate())
	_pending_elims.clear()


func _check_end() -> void:
	if finished:
		return
	var alive := _alive_slots()
	if alive.size() <= 1:
		finish(_rank_players())


func _handle_sabotage(slot: int, target: Variant) -> void:
	if int(sabotage_tokens[slot]) <= 0 or typeof(target) not in [TYPE_INT, TYPE_FLOAT]:
		return
	var victim := int(target)
	if victim == slot or victim not in slots or bool(eliminated[victim]):
		return
	var index := _ledge_under(victim)
	if index == -1:
		return  # not standing on a crumble ledge — nothing to crumble
	sabotage_tokens[slot] = int(sabotage_tokens[slot]) - 1
	_sabotaged[index] = SABOTAGE_GONE_SEC


## The crumble-ledge index the victim is standing on, or -1. Only crumble
## ledges can be sabotaged — stable footing and the base floor can't.
func _ledge_under(victim: int) -> int:
	var body := sim.body_of(victim)
	if body.is_empty() or int(body.get("grounded", 0)) != 1:
		return -1
	var feet := float((body.pos as Vector2).y) - SideScrollSim.HALF.y
	var foot_x := float((body.pos as Vector2).x)
	var all := ledges()
	for index: int in _crumble_indices():
		if not crumble_state[index]:
			continue
		var rect := all[index]
		var lid := rect.position.y + rect.size.y
		if (
			absf(feet - lid) <= 0.3
			and foot_x >= rect.position.x - 0.4
			and foot_x <= rect.position.x + rect.size.x + 0.4
		):
			return index
	return -1


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var body := sim.body_of(slot)
		var pos: Vector2 = body.get("pos", Vector2(0.0, magma_y - 5.0))
		var flags := 0
		if bool(shields[slot]):
			flags |= 1
		if bool(eliminated[slot]):
			flags |= 2
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(body.get("facing", 1)),
			int(body.get("grounded", 0)),
			flags,
		]
	return {
		"players": players,
		"magma_y": snappedf(magma_y, 0.01),
		"crumble": crumble_state.duplicate(),
	}


## Survivors first, grouped by height reached (higher first); then the
## eliminated in reverse drop order — Gauntlet-shaped for FinaleRanking.
func _rank_players() -> Array:
	var placements: Array = []
	var survivors := _alive_slots()
	survivors.sort_custom(
		func(a: int, b: int) -> bool: return float(peak_height[a]) > float(peak_height[b])
	)
	var group: Array = []
	for slot: int in survivors:
		if (
			group.is_empty()
			or is_equal_approx(float(peak_height[int(group[-1])]), float(peak_height[slot]))
		):
			group.append(slot)
		else:
			placements.append(group)
			group = [slot]
	if not group.is_empty():
		placements.append(group)
	var fallen := elimination_order.duplicate()
	fallen.reverse()
	for tie_group: Array in fallen:
		placements.append(tie_group.duplicate())
	return placements


func _alive_slots() -> Array:
	var out: Array = []
	for slot: int in slots:
		if not bool(eliminated[slot]):
			out.append(slot)
	return out
