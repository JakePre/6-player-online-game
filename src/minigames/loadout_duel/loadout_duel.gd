class_name LoadoutDuel
extends MinigameBase
## Loadout Duel (M14-01, PHASE2.md §8, owner-approved on #509): a Duck-Game
## arena shooter on the M14-00 side-view platformer bones. Weapons spawn on
## daises; walk over one empty-handed to grab it; fire (action_primary) or
## throw it as a bonking projectile (action_secondary). One hit KOs — a
## shield eats exactly one — and the last duck standing takes the sub-round.
## Best of three; survival points aggregate into the final placement.
##
## Server-authoritative and deterministic: SideScrollSim owns the platforming,
## this owns weapons, projectiles, daises, and the sub-round lifecycle.

enum Phase { COUNTDOWN, FIGHT, ROUND_OVER }

## Loadout kinds a dais can hand out. NONE means empty hands.
enum Kind { NONE, BLASTER, SCATTER, BOOMER, HAMMER, SHIELD }

## Projectile kinds distinguish flight/impact behavior from the weapon that
## fired them (a thrown empty Blaster and a thrown Hammer are both THROWN).
enum Shot { BOLT, LOB, THROWN }

const WEAPON_KINDS := [Kind.BLASTER, Kind.SCATTER, Kind.BOOMER, Kind.HAMMER]
const DAIS_KINDS := [Kind.BLASTER, Kind.SCATTER, Kind.BOOMER, Kind.HAMMER, Kind.SHIELD]
## Shots per pickup; the weapon empties (back to NONE) when it runs dry.
const AMMO := {Kind.BLASTER: 3, Kind.SCATTER: 2, Kind.BOOMER: 1, Kind.HAMMER: 4}

## The weapon daises sit on platforms 3.0 u / 5.6 u up, but the shared default
## jump only clears ~2.6 u — so the loadouts were literally unreachable (#788).
## Lift the apex to ~3.6 u to put the first tier in reach with margin.
const JUMP_VELOCITY := 16.5

const SUB_ROUNDS := 3
const COUNTDOWN_SEC := 1.5
const ROUND_CAP_SEC := 45.0
const ROUND_OVER_SEC := 2.5
const DAIS_REFILL_SEC := 6.0
const DAIS_GRAB_RADIUS := 0.9
const FIRE_COOLDOWN := 0.28

const HIT_RADIUS := 0.6
const BLAST_RADIUS := 2.2
const HAMMER_RANGE := 1.7
const HAMMER_HALF_HEIGHT := 0.8

const BOLT_SPEED := 13.0
const BOLT_LIFE := 1.0
const SCATTER_SPEED := 10.0
const SCATTER_LIFE := 0.42
const SCATTER_SPREAD := 0.32
const LOB_SPEED := 8.0
const LOB_LIFT := 7.0
const LOB_LIFE := 2.6
const THROW_SPEED := 11.0
const THROW_LIFE := 1.6

const KO_KNOCKBACK := Vector2(9.0, 5.0)
const SHIELD_KNOCKBACK := Vector2(6.0, 3.0)

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1
const PS_FACING := 2
const PS_FLAGS := 3
const PS_HELD := 4
const PS_COUNT := 5

const SH_X := 0
const SH_Y := 1
const SH_KIND := 2

const DS_X := 0
const DS_Y := 1
const DS_KIND := 2

var sim: SideScrollSim
var phase: Phase = Phase.COUNTDOWN
var sub_round := 0
var phase_left := COUNTDOWN_SEC
## slot -> {held, ammo, shield, alive, fire_cd, swing, hurt}
var fighters := {}
## Each {pos, vel, shot, owner, life, gravity}.
var projectiles: Array[Dictionary] = []
## Each {pos, kind, refill_at}; kind is Kind.NONE while cooling down.
var daises: Array[Dictionary] = []
var total_score := {}
## KO order within the current sub-round (first out first).
var _ko_order: Array = []


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"loadout_duel",
				"controls":
				"Move — A/D / stick · Jump — W / stick up · Fire — SPACE / pad A · Throw — E / pad X",
				"control_hints":  # Device-aware (#608); Jump stays literal (move_up is axis-bound).
				[
					"Move — A/D / stick · Jump — W / stick up · Fire — ",
					{"action": &"action_primary"},
					" · Throw — ",
					{"action": &"action_secondary"},
				],
				# Structured spec (#832/#844): the side-scroll template shape
				# (lr-cluster move + move_up jump + this game's fire/throw actions).
				"control_spec":
				[
					{"verb": "Move", "input": InputGlyphs.CLUSTER_MOVE_LR},
					{"verb": "Jump", "input": &"move_up"},
					{"verb": "Fire", "input": &"action_primary"},
					{"verb": "Throw", "input": &"action_secondary"},
				],
				"name": "Loadout Duel",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 8,
				"duration_sec": SUB_ROUNDS * (COUNTDOWN_SEC + ROUND_CAP_SEC + ROUND_OVER_SEC) + 5.0,
				"rules":
				"Grab a gun, one hit KOs! Fire or throw it, last duck standing wins the round.",
			}
		)
	)


## Stage geometry in the sim's y-up world units, shared verbatim with the
## view. Ground slab plus symmetric one-way ledges.
static func solid_platforms() -> Array[Rect2]:
	return [Rect2(-10.0, -1.0, 20.0, 1.0)] as Array[Rect2]


static func one_way_platforms() -> Array[Rect2]:
	return (
		[
			Rect2(-8.5, 2.6, 4.0, 0.4),
			Rect2(4.5, 2.6, 4.0, 0.4),
			Rect2(-2.6, 5.2, 5.2, 0.4),
		]
		as Array[Rect2]
	)


static func stage_bounds() -> Rect2:
	return Rect2(-12.0, -7.0, 24.0, 19.0)


## Fixed dais anchor points, resting on the surfaces above.
static func dais_positions() -> Array[Vector2]:
	return [
		Vector2(-6.0, 0.5),
		Vector2(0.0, 0.5),
		Vector2(6.0, 0.5),
		Vector2(-6.5, 3.5),
		Vector2(6.5, 3.5),
		Vector2(0.0, 6.1),
	]


func _setup() -> void:
	sim = SideScrollSim.new()
	sim.jump_velocity = JUMP_VELOCITY
	sim.solids = solid_platforms()
	sim.one_way = one_way_platforms()
	sim.bounds = stage_bounds()
	for slot: int in slots:
		total_score[slot] = 0
	for pos in dais_positions():
		daises.append({"pos": pos, "kind": Kind.NONE, "refill_at": 0.0})
	_start_sub_round()


## Spawn points spread across the ground for the current headcount.
func _spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var count := slots.size()
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		points.append(Vector2(lerpf(-8.0, 8.0, t), 1.0))
	return points


func _start_sub_round() -> void:
	phase = Phase.COUNTDOWN
	phase_left = COUNTDOWN_SEC
	projectiles.clear()
	_ko_order.clear()
	var spawns := _spawn_points()
	for slot: int in sim._bodies.keys():
		sim.remove_body(slot)
	for i in slots.size():
		sim.add_body(slots[i], spawns[i])
		fighters[slots[i]] = {
			"held": Kind.NONE,
			"ammo": 0,
			"shield": false,
			"alive": true,
			"fire_cd": 0.0,
			"swing": false,
			"hurt": false,
		}
	for dais in daises:
		dais.kind = DAIS_KINDS[rng.randi_range(0, DAIS_KINDS.size() - 1)]
		dais.refill_at = 0.0


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
	if data.get("fire", false):
		_fire(slot, fighter)
	if data.get("throw", false):
		_throw(slot, fighter)


func _tick(delta: float) -> void:
	for slot: int in fighters:
		fighters[slot].swing = false
		fighters[slot].hurt = false
		fighters[slot].fire_cd = maxf(0.0, float(fighters[slot].fire_cd) - delta)
	phase_left -= delta
	match phase:
		Phase.COUNTDOWN:
			sim.step(delta)
			if phase_left <= 0.0:
				phase = Phase.FIGHT
				phase_left = ROUND_CAP_SEC
		Phase.FIGHT:
			_tick_fight(delta)
		Phase.ROUND_OVER:
			if phase_left <= 0.0:
				_advance_sub_round()


func _tick_fight(delta: float) -> void:
	# Dead bodies keep ragdolling; the sim just steps everyone.
	sim.step(delta)
	for slot: int in sim.out_slots():
		var fighter: Dictionary = fighters.get(slot, {})
		if not fighter.is_empty() and bool(fighter.alive):
			_ko(slot)
	_tick_daises()
	_tick_projectiles(delta)
	if _alive_count() <= 1 or phase_left <= 0.0:
		_end_sub_round()


func _tick_daises() -> void:
	for dais in daises:
		if int(dais.kind) == Kind.NONE and elapsed >= float(dais.refill_at):
			dais.kind = DAIS_KINDS[rng.randi_range(0, DAIS_KINDS.size() - 1)]
	for slot: int in fighters:
		var fighter: Dictionary = fighters[slot]
		if not bool(fighter.alive):
			continue
		var body := sim.body_of(slot)
		if body.is_empty():
			continue
		for dais in daises:
			if int(dais.kind) == Kind.NONE:
				continue
			if (body.pos as Vector2).distance_to(dais.pos) > DAIS_GRAB_RADIUS:
				continue
			_try_grab(fighter, dais)


func _try_grab(fighter: Dictionary, dais: Dictionary) -> void:
	var kind := int(dais.kind)
	if kind == Kind.SHIELD:
		if bool(fighter.shield):
			return
		fighter.shield = true
	else:
		if int(fighter.held) != Kind.NONE:
			return
		fighter.held = kind
		fighter.ammo = int(AMMO[kind])
	dais.kind = Kind.NONE
	dais.refill_at = elapsed + DAIS_REFILL_SEC


func _fire(slot: int, fighter: Dictionary) -> void:
	if int(fighter.held) == Kind.NONE or float(fighter.fire_cd) > 0.0:
		return
	fighter.fire_cd = FIRE_COOLDOWN
	var body := sim.body_of(slot)
	var origin: Vector2 = (body.pos as Vector2) + Vector2(float(body.facing) * 0.5, 0.2)
	var dir := float(body.facing)
	match int(fighter.held):
		Kind.BLASTER:
			_spawn_shot(slot, origin, Vector2(dir * BOLT_SPEED, 0.0), Shot.BOLT, BOLT_LIFE, 0.0)
		Kind.SCATTER:
			for spread in [-SCATTER_SPREAD, 0.0, SCATTER_SPREAD]:
				var vel := Vector2(dir * SCATTER_SPEED, 0.0).rotated(spread * dir)
				_spawn_shot(slot, origin, vel, Shot.BOLT, SCATTER_LIFE, 0.0)
		Kind.BOOMER:
			_spawn_shot(
				slot, origin, Vector2(dir * LOB_SPEED, LOB_LIFT), Shot.LOB, LOB_LIFE, sim.gravity
			)
		Kind.HAMMER:
			_swing_hammer(slot, fighter)
	fighter.ammo = int(fighter.ammo) - 1
	if int(fighter.ammo) <= 0:
		fighter.held = Kind.NONE


func _throw(slot: int, fighter: Dictionary) -> void:
	if int(fighter.held) == Kind.NONE or float(fighter.fire_cd) > 0.0:
		return
	fighter.fire_cd = FIRE_COOLDOWN
	var body := sim.body_of(slot)
	var origin: Vector2 = (body.pos as Vector2) + Vector2(float(body.facing) * 0.5, 0.2)
	# Even an empty gun bonks — that's the comedy beat.
	_spawn_shot(
		slot,
		origin,
		Vector2(float(body.facing) * THROW_SPEED, 1.5),
		Shot.THROWN,
		THROW_LIFE,
		sim.gravity * 0.4
	)
	fighter.held = Kind.NONE
	fighter.ammo = 0


func _swing_hammer(slot: int, fighter: Dictionary) -> void:
	fighter.swing = true
	var body := sim.body_of(slot)
	var origin: Vector2 = body.pos
	var dir := float(body.facing)
	for other: int in fighters:
		if other == slot or not bool(fighters[other].alive):
			continue
		var target := sim.body_of(other)
		if target.is_empty():
			continue
		var offset: Vector2 = (target.pos as Vector2) - origin
		if offset.x * dir < 0.0 or absf(offset.x) > HAMMER_RANGE:
			continue
		if absf(offset.y) > HAMMER_HALF_HEIGHT:
			continue
		_resolve_hit(other, origin)


func _spawn_shot(
	owner: int, pos: Vector2, vel: Vector2, shot: int, life: float, gravity: float
) -> void:
	projectiles.append(
		{"pos": pos, "vel": vel, "shot": shot, "owner": owner, "life": life, "gravity": gravity}
	)


func _tick_projectiles(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for shot in projectiles:
		shot.life = float(shot.life) - delta
		if float(shot.life) <= 0.0:
			if int(shot.shot) == Shot.LOB:
				_explode(shot.pos)
			continue
		shot.vel = (shot.vel as Vector2) - Vector2(0.0, float(shot.gravity) * delta)
		shot.pos = (shot.pos as Vector2) + (shot.vel as Vector2) * delta
		var pos: Vector2 = shot.pos
		# A lob detonates when it reaches the ground slab's surface.
		if int(shot.shot) == Shot.LOB and pos.y <= 0.5:
			_explode(pos)
			continue
		if not sim.bounds.has_point(pos):
			continue
		var struck := _hit_scan(int(shot.owner), pos)
		if struck >= 0:
			if int(shot.shot) == Shot.LOB:
				_explode(pos)
			else:
				_resolve_hit(struck, pos)
			continue
		alive.append(shot)
	projectiles = alive


## First alive non-owner within HIT_RADIUS of a point, else -1.
func _hit_scan(owner: int, pos: Vector2) -> int:
	for slot: int in fighters:
		if slot == owner or not bool(fighters[slot].alive):
			continue
		var body := sim.body_of(slot)
		if body.is_empty():
			continue
		if (body.pos as Vector2).distance_to(pos) <= HIT_RADIUS:
			return slot
	return -1


func _explode(center: Vector2) -> void:
	for slot: int in fighters:
		if not bool(fighters[slot].alive):
			continue
		var body := sim.body_of(slot)
		if body.is_empty():
			continue
		if (body.pos as Vector2).distance_to(center) <= BLAST_RADIUS:
			_resolve_hit(slot, center)


## One hit: a shield eats it (and shatters), otherwise it's a KO. Either way
## the victim gets shoved away from the source — the physics comedy.
func _resolve_hit(slot: int, from_pos: Vector2) -> void:
	var fighter: Dictionary = fighters[slot]
	if not bool(fighter.alive):
		return
	var body := sim.body_of(slot)
	var away := 1.0 if (body.pos as Vector2).x >= from_pos.x else -1.0
	if bool(fighter.shield):
		fighter.shield = false
		fighter.hurt = true
		sim.apply_impulse(slot, Vector2(away * SHIELD_KNOCKBACK.x, SHIELD_KNOCKBACK.y))
		return
	sim.apply_impulse(slot, Vector2(away * KO_KNOCKBACK.x, KO_KNOCKBACK.y))
	_ko(slot)


func _ko(slot: int) -> void:
	var fighter: Dictionary = fighters[slot]
	if not bool(fighter.alive):
		return
	fighter.alive = false
	fighter.held = Kind.NONE
	_ko_order.append(slot)


func _alive_count() -> int:
	var count := 0
	for slot: int in fighters:
		if bool(fighters[slot].alive):
			count += 1
	return count


## Award survival points for the sub-round (last standing gets the most),
## then advance or finish.
func _end_sub_round() -> void:
	if phase != Phase.FIGHT:
		return
	phase = Phase.ROUND_OVER
	phase_left = ROUND_OVER_SEC
	var survivors: Array = []
	for slot: int in slots:
		if bool(fighters[slot].alive):
			survivors.append(slot)
	# Best to worst: survivors (tie), then reverse KO order (last out is better).
	var ordered: Array = survivors.duplicate()
	for i in range(_ko_order.size() - 1, -1, -1):
		ordered.append(_ko_order[i])
	var n := slots.size()
	for rank in ordered.size():
		var slot: int = ordered[rank]
		total_score[slot] = int(total_score[slot]) + (n - 1 - rank)


func _advance_sub_round() -> void:
	sub_round += 1
	if sub_round >= SUB_ROUNDS:
		finish(_rank_players())
	else:
		_start_sub_round()


func _rank_players() -> Array:
	var by_score := {}
	for slot: int in slots:
		var score: int = total_score.get(slot, 0)
		if not by_score.has(score):
			by_score[score] = []
		by_score[score].append(slot)
	var scores := by_score.keys()
	scores.sort()
	scores.reverse()
	var placements: Array = []
	for score: int in scores:
		placements.append(by_score[score])
	return placements


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in fighters:
		var fighter: Dictionary = fighters[slot]
		var body := sim.body_of(slot)
		var pos: Vector2 = body.get("pos", Vector2.ZERO)
		var flags := 0
		if bool(fighter.alive):
			flags |= 1
		if bool(fighter.shield):
			flags |= 2
		if bool(fighter.swing):
			flags |= 4
		if bool(fighter.hurt):
			flags |= 8
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			int(body.get("facing", 1)),
			flags,
			int(fighter.held),
		]
	var shot_list: Array = []
	for shot in projectiles:
		var pos: Vector2 = shot.pos
		shot_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), int(shot.shot)])
	var dais_list: Array = []
	for dais in daises:
		var pos: Vector2 = dais.pos
		dais_list.append([pos.x, pos.y, int(dais.kind)])
	return {
		"players": players,
		"shots": shot_list,
		"daises": dais_list,
		"phase": int(phase),
		"sub_round": sub_round,
		"scores": total_score.duplicate(),
	}
