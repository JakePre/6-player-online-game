class_name Kingslayer
extends MinigameBase
## Kingslayer (#936, owner-locked concept, build 2 of 3): the asymmetric-hunt
## finale. The match coin-leader is CROWNED — everyone else hunts them. The
## King survives the round timer → 1st place; slain, the killing blow's
## hunter ranks 1st, every hunter who drew blood groups next, and the King
## places by how long they lasted. Hunters respawn on a cooldown, so the King
## can win fights but never the war of attrition — kiting, swings and the
## shop's tools decide it. The King's coin advantage at the buy-in shop IS
## the balance lever (they can afford the deepest loadout), on top of a
## visible kit edge: longer reach, a launching swing, and a real HP pool.
## Not a roster minigame — entered via FinaleVariants (M5-02 contract).

const COURT_RADIUS := 9.0
const MOVE_SPEED := 6.0
const SPEED_BOOST_MULT := 1.3
const PLAYER_RADIUS := 0.45

## The crown's kit edge (#936 "being 5v1 must feel like a crown"): more reach,
## a swing that LAUNCHES, and an HP pool the shop deepens further.
const KING_HP_BASE := 6
const KING_HP_PER_LIFE := 2
const KING_SWING_RANGE := 2.6
const KING_KNOCKBACK := 4.0
## Hunters die in one royal swing (two with an extra life) and come back.
const HUNTER_HP_BASE := 1
const HUNTER_HP_PER_LIFE := 1
const HUNTER_SWING_RANGE := 1.8
const HUNTER_KNOCKBACK := 1.0
const HUNTER_RESPAWN_SEC := 3.0

const SWING_ARC_DOT := 0.0
const SWING_COOLDOWN_SEC := 0.7
## Anti-stunlock: after any hit the victim is briefly unhittable, so five
## hunters can't melt the crown in one dogpile frame.
const HIT_PROTECT_SEC := 0.8
const SPAWN_PROTECT_SEC := 2.0

## Sabotage (#936): hunters strike the King from the sky, the King strikes a
## hunter — same telegraphed, dodgeable circle as Storm Court.
const SABOTAGE_WARN_SEC := 1.2
const SABOTAGE_RADIUS := 1.6

## A slain King who lasted at least this fraction of the round still ranks
## above the hunters who never drew blood — dying late is a performance.
const SURVIVAL_RANK_FRACTION := 0.5

## get_snapshot() wire shapes (#708).
const PS_X := 0
const PS_Y := 1
const PS_FACING_X := 2
const PS_FACING_Y := 3
const PS_HP := 4
const PS_RESPAWN := 5
const PS_INVULN := 6
const PS_HIT_SEQ := 7
const PS_SWING_SEQ := 8
const PS_COUNT := 9
const PLAYER_SCHEMA := [
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_FLOAT,
	TYPE_INT,
	TYPE_INT,
]

const ST_X := 0
const ST_Y := 1
const ST_WARN := 2

var king := -1
var positions := {}
var move_dirs := {}
var facings := {}
var hp := {}
var max_hp := {}
var shields := {}
var speed_boosts := {}
var sabotage_tokens := {}
## Hunter damage ledger: slot -> hits landed on the King (assist credit).
var damage_dealt := {}
var slayer := -1
## Elapsed second the King fell, or -1.0 while they stand.
var king_down_at := -1.0
## Pending sabotage strikes, each {pos, warn_left, from_king}.
var strikes: Array[Dictionary] = []
## Monotonic per-slot counters for view animation (#708 idiom).
var hit_seq := {}
var swing_seq := {}

var _respawn_left := {}
var _invuln_left := {}
var _swing_cd := {}
var _loadout_items := {}


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"kingslayer",
				"controls":
				"Move — WASD / left stick · Swing — Space / pad A · Sabotage — E / pad X",
				"name": "Kingslayer",
				"category": MinigameMeta.Category.FFA,
				"min_players": 2,
				"max_players": 24,
				"duration_sec": 90.0,
				"rules":
				(
					"The match's coin leader wears the crown — everyone else hunts them!"
					+ " The King survives the timer to win it all; the slayer takes it"
					+ " instead if the crown falls."
				),
			}
		)
	)


static func court_radius_for(count: int) -> float:
	return COURT_RADIUS * sqrt(MinigameScaling.growth(count))


func _setup() -> void:
	for i in slots.size():
		var slot: int = slots[i]
		var angle := TAU * i / slots.size()
		positions[slot] = Vector2(cos(angle), sin(angle)) * court_radius_for(slots.size()) * 0.7
		move_dirs[slot] = Vector2.ZERO
		facings[slot] = Vector2(-cos(angle), -sin(angle))
		hp[slot] = HUNTER_HP_BASE
		max_hp[slot] = HUNTER_HP_BASE
		shields[slot] = false
		speed_boosts[slot] = false
		sabotage_tokens[slot] = 0
		damage_dealt[slot] = 0
		hit_seq[slot] = 0
		swing_seq[slot] = 0
		_invuln_left[slot] = SPAWN_PROTECT_SEC
		_swing_cd[slot] = 0.0
	# Deterministic default before apply_match_totals crowns the real leader
	# (harness/tests without a match behind them): lowest slot.
	_crown(slots[0])


## FinaleShop.loadouts() interface (M5-01/M5-02). Items are staged: the crown
## may land after loadouts (both are called from _enter_finale_play), so HP
## math is re-derived in _crown from the staged items.
func apply_loadouts(shop_loadouts: Dictionary) -> void:
	for slot: int in shop_loadouts:
		if slot not in slots:
			continue
		var items: Dictionary = shop_loadouts[slot].get("items", {})
		_loadout_items[slot] = items
		shields[slot] = int(items.get(&"shield", 0)) > 0
		speed_boosts[slot] = int(items.get(&"speed_boost", 0)) > 0
		sabotage_tokens[slot] = int(items.get(&"sabotage_token", 0))
	_apply_hp_pools()


## The #936 crowning hook: the match controller hands every variant the match
## coin totals after loadouts; Kingslayer is the one that cares. Highest
## earner takes the crown (ties: lowest slot — deterministic on every peer).
func apply_match_totals(totals: Dictionary) -> void:
	var best := slots[0] as int
	var best_coins := -1
	for slot: int in slots:
		var coins := int(totals.get(slot, 0))
		if coins > best_coins:
			best_coins = coins
			best = slot
	_crown(best)


func _crown(slot: int) -> void:
	king = slot
	_apply_hp_pools()


func _apply_hp_pools() -> void:
	for slot: int in slots:
		var lives := int((_loadout_items.get(slot, {}) as Dictionary).get(&"extra_life", 0))
		var pool := (
			KING_HP_BASE + KING_HP_PER_LIFE * lives
			if slot == king
			else HUNTER_HP_BASE + HUNTER_HP_PER_LIFE * lives
		)
		max_hp[slot] = pool
		hp[slot] = pool


func _handle_input(slot: int, data: Dictionary) -> void:
	if _respawn_left.has(slot) or finished:
		return
	if data.has("sabotage"):
		_handle_sabotage(slot, data.sabotage)
		return
	if data.has("swing"):
		_swing(slot)
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)
	if dir.length() > 0.1:
		facings[slot] = dir.normalized()


func _tick(delta: float) -> void:
	var court := court_radius_for(slots.size())
	for slot: int in slots:
		_swing_cd[slot] = maxf(0.0, float(_swing_cd[slot]) - delta)
		_invuln_left[slot] = maxf(0.0, float(_invuln_left.get(slot, 0.0)) - delta)
		if _respawn_left.has(slot):
			_respawn_left[slot] = float(_respawn_left[slot]) - delta
			if float(_respawn_left[slot]) <= 0.0:
				_respawn_hunter(slot)
			continue
		var speed := MOVE_SPEED * (SPEED_BOOST_MULT if speed_boosts[slot] else 1.0)
		positions[slot] = (
			((positions[slot] as Vector2) + move_dirs[slot] * speed * delta)
			. limit_length(court - PLAYER_RADIUS)
		)
	_tick_strikes(delta)


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in slots:
		var pos: Vector2 = positions[slot]
		var facing: Vector2 = facings[slot]
		players[slot] = [
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			snappedf(facing.x, 0.01),
			snappedf(facing.y, 0.01),
			int(hp[slot]),
			snappedf(float(_respawn_left.get(slot, 0.0)), 0.01),
			snappedf(float(_invuln_left.get(slot, 0.0)), 0.01),
			int(hit_seq[slot]),
			int(swing_seq[slot]),
		]
	var strike_list: Array = []
	for strike: Dictionary in strikes:
		var pos: Vector2 = strike.pos
		strike_list.append(
			[snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(strike.warn_left, 0.01)]
		)
	return {
		"king": king,
		"king_max_hp": int(max_hp.get(king, KING_HP_BASE)),
		"court": snappedf(court_radius_for(slots.size()), 0.01),
		"players": players,
		"strikes": strike_list,
	}


## The locked ranking (#936): King survives → 1st, hunters by damage dealt.
## Slain → slayer 1st, assists (blood drawn, not the slayer) grouped next,
## then the King IF they lasted SURVIVAL_RANK_FRACTION of the round, then the
## idle hunters — a King who fell early ranks behind everyone.
func _rank_players() -> Array:
	var placements: Array = []
	if king_down_at < 0.0:
		placements.append([king])
		placements += _hunters_by_damage()
		return placements
	placements.append([slayer])
	var assists: Array = []
	var idle: Array = []
	for slot: int in slots:
		if slot == king or slot == slayer:
			continue
		if int(damage_dealt[slot]) > 0:
			assists.append(slot)
		else:
			idle.append(slot)
	if not assists.is_empty():
		placements.append(assists)
	var lasted := king_down_at / maxf(effective_duration(), 0.001)
	if lasted >= SURVIVAL_RANK_FRACTION:
		placements.append([king])
		if not idle.is_empty():
			placements.append(idle)
	else:
		if not idle.is_empty():
			placements.append(idle)
		placements.append([king])
	return placements


func _hunters_by_damage() -> Array:
	var by_damage := {}
	for slot: int in slots:
		if slot == king:
			continue
		var dealt: int = damage_dealt[slot]
		if not by_damage.has(dealt):
			by_damage[dealt] = []
		by_damage[dealt].append(slot)
	var keys := by_damage.keys()
	keys.sort()
	keys.reverse()
	var groups: Array = []
	for key: int in keys:
		groups.append(by_damage[key])
	return groups


# --- Combat ----------------------------------------------------------------------


func _swing(slot: int) -> void:
	if float(_swing_cd[slot]) > 0.0:
		return
	_swing_cd[slot] = SWING_COOLDOWN_SEC
	swing_seq[slot] = int(swing_seq[slot]) + 1
	var reach := KING_SWING_RANGE if slot == king else HUNTER_SWING_RANGE
	var facing: Vector2 = facings[slot]
	for other: int in slots:
		if other == slot or _respawn_left.has(other):
			continue
		# Hunters can only hurt the King; the King can only cull hunters.
		if slot != king and other != king:
			continue
		var to_other: Vector2 = positions[other] - positions[slot]
		if to_other.length() > reach:
			continue
		if to_other.normalized().dot(facing) < SWING_ARC_DOT:
			continue
		_hit(other, slot)


func _hit(victim: int, attacker: int) -> void:
	if float(_invuln_left.get(victim, 0.0)) > 0.0 or finished:
		return
	if shields[victim]:
		shields[victim] = false
		hit_seq[victim] = int(hit_seq[victim]) + 1
		_invuln_left[victim] = HIT_PROTECT_SEC
		return
	hp[victim] = int(hp[victim]) - 1
	hit_seq[victim] = int(hit_seq[victim]) + 1
	_invuln_left[victim] = HIT_PROTECT_SEC
	var knockback := KING_KNOCKBACK if attacker == king else HUNTER_KNOCKBACK
	var away: Vector2 = (positions[victim] as Vector2) - (positions[attacker] as Vector2)
	away = away.normalized() if away.length() > 0.001 else Vector2.RIGHT
	positions[victim] = ((positions[victim] as Vector2) + away * knockback).limit_length(
		court_radius_for(slots.size()) - PLAYER_RADIUS
	)
	if victim == king:
		damage_dealt[attacker] = int(damage_dealt[attacker]) + 1
		if int(hp[king]) <= 0:
			slayer = attacker
			king_down_at = elapsed
			finish(_rank_players())
		return
	if int(hp[victim]) <= 0:
		_down_hunter(victim)


func _down_hunter(slot: int) -> void:
	_respawn_left[slot] = HUNTER_RESPAWN_SEC
	move_dirs[slot] = Vector2.ZERO


func _respawn_hunter(slot: int) -> void:
	_respawn_left.erase(slot)
	hp[slot] = int(max_hp[slot])
	_invuln_left[slot] = SPAWN_PROTECT_SEC
	# Back on the rim, never on top of the King.
	var angle := rng.randf_range(0.0, TAU)
	positions[slot] = Vector2(cos(angle), sin(angle)) * court_radius_for(slots.size()) * 0.85


# --- Sabotage --------------------------------------------------------------------


## Hunters may only strike the King; the King may only strike hunters — the
## same telegraphed dodgeable circle as Storm Court (#936).
func _handle_sabotage(slot: int, target: Variant) -> void:
	if int(sabotage_tokens[slot]) <= 0 or typeof(target) not in [TYPE_INT, TYPE_FLOAT]:
		return
	var victim := int(target)
	if victim == slot or victim not in slots or _respawn_left.has(victim):
		return
	if (slot == king) == (victim == king):
		return  # crown strikes hunters, hunters strike the crown
	sabotage_tokens[slot] = int(sabotage_tokens[slot]) - 1
	strikes.append({"pos": positions[victim], "warn_left": SABOTAGE_WARN_SEC, "by": slot})


func _tick_strikes(delta: float) -> void:
	for i in range(strikes.size() - 1, -1, -1):
		var strike: Dictionary = strikes[i]
		strike.warn_left = float(strike.warn_left) - delta
		if float(strike.warn_left) > 0.0:
			continue
		var from_king := int(strike.get("by", -1)) == king
		for slot: int in slots:
			if _respawn_left.has(slot):
				continue
			# A strike only harms the caster's opposite role — no self-slaying
			# crowns, no hunter friendly fire.
			if (slot == king) == from_king:
				continue
			if (positions[slot] as Vector2).distance_to(strike.pos) <= SABOTAGE_RADIUS:
				_hit(slot, int(strike.get("by", slot)))
		strikes.remove_at(i)
