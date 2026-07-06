class_name KnockOff
extends MinigameBase
## Knock-Off (M14-03, PHASE2.md §8): a platform fighter on the M14-00
## side-view bones. One stock each — get knocked off the small stage and
## you're out. Every hit raises your damage percent, and knockback scales
## with the *victim's* percent, so a battered duck flies further (the
## smash-fighter staple). Two jumps, a light jab (action_primary) and a
## heavy smash (action_secondary); no projectiles. Last duck on the stage
## wins the round. Server-authoritative and deterministic.

enum Phase { COUNTDOWN, FIGHT, DONE }

const COUNTDOWN_SEC := 1.5
const ROUND_CAP_SEC := 75.0

## Two jumps total (ground + one air).
const AIR_JUMPS := 1
## Small stage: one floating platform, generous void on all sides.
const STAGE_HALF_WIDTH := 6.0

const ATTACK_RANGE := 1.6
const ATTACK_HALF_HEIGHT := 0.9
const ATTACK_COOLDOWN := 0.3
const SMASH_COOLDOWN := 0.7

## Damage each hit adds, and the knockback model. Base knockback plus a
## per-percent term: at 0% you barely nudge, at 100%+ you launch.
const JAB_DAMAGE := 8.0
const SMASH_DAMAGE := 16.0
const JAB_BASE_KB := 4.0
const SMASH_BASE_KB := 7.0
const KB_PER_PERCENT := 0.09
## Upward share of the launch, so hits pop victims up and off, not just sideways.
const KB_LIFT_RATIO := 0.7

var sim: SideScrollSim
var phase: Phase = Phase.COUNTDOWN
var phase_left := COUNTDOWN_SEC
## slot -> {percent, alive, cd, attack (0 none / 1 jab / 2 smash this tick)}
var fighters := {}
## KO order within the round (first off the stage first).
var _ko_order: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"knock_off",
				"controls":
				"Move — A/D / stick · Jump — W / stick up · Jab — SPACE / pad A · Smash — E / pad X",
				"control_hints":  # Device-aware (#608); Jump stays literal (move_up is axis-bound).
				[
					"Move — A/D / stick · Jump — W / stick up · Jab — ",
					{"action": &"action_primary"},
					" · Smash — ",
					{"action": &"action_secondary"},
				],
				"name": "Knock-Off",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 8,
				"duration_sec": COUNTDOWN_SEC + ROUND_CAP_SEC + 3.0,
				"rules":
				"One stock — knock rivals off the stage! Damage builds, so they fly further.",
			}
		)
	)


## A single central platform players fight on; everything else is the void.
static func solid_platforms() -> Array[Rect2]:
	return [Rect2(-STAGE_HALF_WIDTH, -0.6, STAGE_HALF_WIDTH * 2.0, 0.6)] as Array[Rect2]


static func one_way_platforms() -> Array[Rect2]:
	return [Rect2(-2.5, 3.2, 5.0, 0.35)] as Array[Rect2]


static func stage_bounds() -> Rect2:
	return Rect2(-13.0, -8.0, 26.0, 20.0)


func _setup() -> void:
	sim = SideScrollSim.new()
	sim.solids = solid_platforms()
	sim.one_way = one_way_platforms()
	sim.bounds = stage_bounds()
	sim.max_air_jumps = AIR_JUMPS
	phase = Phase.COUNTDOWN
	phase_left = COUNTDOWN_SEC
	var spawns := _spawn_points()
	for i in slots.size():
		sim.add_body(slots[i], spawns[i])
		fighters[slots[i]] = {"percent": 0.0, "alive": true, "cd": 0.0, "attack": 0}


func _spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var count := slots.size()
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		# Drop in just above the platform lid (y=0); spawning embedded would
		# make the sim's wall-resolution eject the body off the edge.
		points.append(Vector2(lerpf(-STAGE_HALF_WIDTH + 1.0, STAGE_HALF_WIDTH - 1.0, t), 0.7))
	return points


func _handle_input(slot: int, data: Dictionary) -> void:
	if phase != Phase.FIGHT:
		return
	var fighter: Dictionary = fighters.get(slot, {})
	if fighter.is_empty() or not bool(fighter.alive):
		return
	if data.has("mx"):
		sim.set_move(slot, clampf(float(data.mx), -1.0, 1.0))
	if data.get("jump", false):
		sim.press_jump(slot)
	if data.get("jab", false):
		_attack(slot, fighter, false)
	if data.get("smash", false):
		_attack(slot, fighter, true)


func _tick(delta: float) -> void:
	for slot: int in fighters:
		fighters[slot].attack = 0
		fighters[slot].cd = maxf(0.0, float(fighters[slot].cd) - delta)
	phase_left -= delta
	match phase:
		Phase.COUNTDOWN:
			sim.step(delta)
			if phase_left <= 0.0:
				phase = Phase.FIGHT
				phase_left = ROUND_CAP_SEC
		Phase.FIGHT:
			_tick_fight(delta)


func _tick_fight(delta: float) -> void:
	sim.step(delta)
	for slot: int in sim.out_slots():
		var fighter: Dictionary = fighters.get(slot, {})
		if not fighter.is_empty() and bool(fighter.alive):
			_ko(slot)
	if _alive_count() <= 1 or phase_left <= 0.0:
		phase = Phase.DONE
		finish(_rank_players())


func _attack(slot: int, fighter: Dictionary, is_smash: bool) -> void:
	if float(fighter.cd) > 0.0:
		return
	fighter.cd = SMASH_COOLDOWN if is_smash else ATTACK_COOLDOWN
	fighter.attack = 2 if is_smash else 1
	var body := sim.body_of(slot)
	var origin: Vector2 = body.pos
	var dir := float(body.facing)
	var damage := SMASH_DAMAGE if is_smash else JAB_DAMAGE
	var base_kb := SMASH_BASE_KB if is_smash else JAB_BASE_KB
	for other: int in fighters:
		if other == slot or not bool(fighters[other].alive):
			continue
		var target := sim.body_of(other)
		if target.is_empty():
			continue
		var offset: Vector2 = (target.pos as Vector2) - origin
		if offset.x * dir < 0.0 or absf(offset.x) > ATTACK_RANGE:
			continue
		if absf(offset.y) > ATTACK_HALF_HEIGHT:
			continue
		_land_hit(other, fighters[other], dir, damage, base_kb)


func _land_hit(slot: int, fighter: Dictionary, dir: float, damage: float, base_kb: float) -> void:
	fighter.percent = float(fighter.percent) + damage
	var magnitude := base_kb + float(fighter.percent) * KB_PER_PERCENT * base_kb
	sim.apply_impulse(slot, Vector2(dir * magnitude, magnitude * KB_LIFT_RATIO))


func _ko(slot: int) -> void:
	var fighter: Dictionary = fighters[slot]
	if not bool(fighter.alive):
		return
	fighter.alive = false
	_ko_order.append(slot)
	sim.remove_body(slot)


func _alive_count() -> int:
	var count := 0
	for slot: int in fighters:
		if bool(fighters[slot].alive):
			count += 1
	return count


## Survivors first (least damaged on top at a timeout), then the fallen in
## reverse KO order — last off the stage placed best.
func _rank_players() -> Array:
	var survivors: Array = []
	for slot: int in slots:
		if bool(fighters[slot].alive):
			survivors.append(slot)
	survivors.sort_custom(
		func(a: int, b: int) -> bool: return float(fighters[a].percent) < float(fighters[b].percent)
	)
	var placements: Array = []
	# Group survivors that share a damage total (a clean win is its own group).
	var group: Array = []
	for slot: int in survivors:
		if (
			group.is_empty()
			or is_equal_approx(
				float(fighters[int(group[-1])].percent), float(fighters[slot].percent)
			)
		):
			group.append(slot)
		else:
			placements.append(group)
			group = [slot]
	if not group.is_empty():
		placements.append(group)
	for i in range(_ko_order.size() - 1, -1, -1):
		placements.append([_ko_order[i]])
	return placements


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in fighters:
		var fighter: Dictionary = fighters[slot]
		var body := sim.body_of(slot)
		var pos: Vector2 = body.get("pos", Vector2.ZERO)
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(body.get("facing", 1)),
			1 if bool(fighter.alive) else 0,
			int(round(float(fighter.percent))),
			int(fighter.attack),
		]
	return {"players": players, "phase": int(phase), "phase_left": snappedf(phase_left, 0.1)}
