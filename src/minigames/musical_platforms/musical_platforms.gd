class_name MusicalPlatforms
extends MinigameBase
## Musical Platforms (M10-02, PHASE2.md $4 #19): everyone roams while the
## music plays; when it stops, platforms appear — one fewer than there are
## players standing. First to reach a platform claims it exclusively; when
## the scramble timer runs out, everyone without one goes down. Repeat until
## one player remains. Down order = placement.
## Server-side simulation only — the client renders get_snapshot().

enum Phase { MUSIC, STOP }

const ARENA_HALF := 9.0
const MOVE_SPEED := 6.0
const PLAYER_RADIUS := 0.45
const PLATFORM_RADIUS := 1.1
## Platforms spawn at least this far apart, inside this ring.
const PLATFORM_SPACING := 3.0
const PLATFORM_MAX_DIST := 7.0
const MUSIC_MIN_SEC := 4.0
const MUSIC_MAX_SEC := 7.0
const STOP_SEC := 4.0
## Minimum scramble before an all-claimed board can end the phase (#804): with
## fast players/bots every platform can be grabbed within a tick or two, which
## used to eliminate the odd one out instantly. Holding the phase open for a
## grace window lets contested platforms actually be fought over before anyone
## goes down. A full-timeout scramble (a platform left free) is unaffected.
const SCRAMBLE_GRACE_SEC := 1.5
## Rejection-sampling budget for _spawn_platforms(), per platform needed
## (200 attempts / 5 platforms at the 6-player baseline).
const PLACEMENT_ATTEMPTS_PER_PLATFORM := 40

## get_snapshot() wire shapes (#708): named indices for the positional arrays
## the view and brain read. Array SHAPE on the wire is unchanged — additive.
const PS_X := 0
const PS_Y := 1

const PT_X := 0
const PT_Y := 1
const PT_CLAIMED_BY := 2
const PT_COUNT := 3

var positions := {}
var move_dirs := {}
var phase := Phase.MUSIC
## Platforms while STOP: {pos: Vector2, claimed_by: int} (-1 = free).
var platforms: Array = []
## Slots in down order; same-scramble losers share a tie group.
var down_order: Array = []

var _phase_left := 0.0

## Play area and platform ring scale with the lobby (M15, ADR 003 F4): a
## fixed-size ring cannot fit N-1 well-spaced platforms much past 12 players,
## so the ring grows by the same per-player-area formula as the arena.
## PLATFORM_SPACING and PLATFORM_RADIUS stay fixed — that is the "well-spaced"
## quality the ring growth is preserving, not a resource to shrink. At <=6
## players these equal the consts above, so the original game is unchanged.
var _play_half := ARENA_HALF
var _platform_max_dist := PLATFORM_MAX_DIST


static func make_meta() -> MinigameMeta:
	return (
		MinigameMeta
		. create(
			{
				"id": &"musical_platforms",
				"controls": "Move — WASD / left stick",
				"name": "Musical Platforms",
				"category": MinigameMeta.Category.FFA,
				"min_players": 3,
				"max_players": 12,
				"duration_sec": 75.0,
				"rules":
				"When the music stops, grab a platform — there's one fewer than there are players.",
			}
		)
	)


func _setup() -> void:
	_play_half = MinigameScaling.arena_half(ARENA_HALF, slots.size())
	_platform_max_dist = MinigameScaling.arena_half(PLATFORM_MAX_DIST, slots.size())
	var spawns := SpawnLayout.ring_positions(slots.size(), _play_half * 0.55)
	for i in slots.size():
		positions[slots[i]] = spawns[i]
		move_dirs[slots[i]] = Vector2.ZERO
	_phase_left = rng.randf_range(MUSIC_MIN_SEC, MUSIC_MAX_SEC)


func _handle_input(slot: int, data: Dictionary) -> void:
	if not _is_in(slot):
		return
	var dir := Vector2(float(data.get("mx", 0.0)), float(data.get("my", 0.0)))
	move_dirs[slot] = dir.limit_length(1.0)


func _tick(delta: float) -> void:
	if finished:
		return
	# Alive-set cache (cleanup #467): computed once, shared by the movement
	# loop, _resolve_claims(), and _advance_phase() (incl. its _spawn_platforms()
	# call) — none of these touch down_order before this point in the tick, so
	# they all see the same pre-elimination roster. _check_end() still calls
	# _in_slots() fresh — it must see the roster *after* _advance_phase() adds
	# this tick's own down_order entries.
	var alive := _in_slots()
	for slot: int in alive:
		var pos: Vector2 = positions[slot] + move_dirs[slot] * MOVE_SPEED * delta
		positions[slot] = pos.limit_length(_play_half)
	if phase == Phase.STOP:
		_resolve_claims(alive)
	_phase_left -= delta
	# An all-claimed board only ends the scramble after the grace window (#804),
	# so a fast fill no longer kills the odd one out on the first tick; a timeout
	# (a platform still free) always ends it regardless.
	var scramble_elapsed := STOP_SEC - _phase_left
	var claimed_out := (
		phase == Phase.STOP and _all_platforms_claimed() and scramble_elapsed >= SCRAMBLE_GRACE_SEC
	)
	if _phase_left <= 0.0 or claimed_out:
		_advance_phase(alive)
	_check_end()


func get_snapshot() -> Dictionary:
	var players := {}
	for slot: int in _in_slots():
		var pos: Vector2 = positions[slot]
		players[slot] = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
	var platform_list: Array = []
	for platform: Dictionary in platforms:
		var pos: Vector2 = platform.pos
		platform_list.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), platform.claimed_by])
	return {
		"players": players,
		"phase": phase,
		"platforms": platform_list,
		"fallen": down_order,
	}


## Timeout: everyone still standing ties ahead of the fallen.
func _rank_players() -> Array:
	var survivors := _in_slots()
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	return placements + _out_placements()


## First unclaimed platform a player touches is theirs, exclusively; a player
## who already holds one cannot take a second.
func _resolve_claims(alive: Array) -> void:
	for platform: Dictionary in platforms:
		if platform.claimed_by != -1:
			continue
		for slot: int in alive:
			if _claim_of(slot) != null:
				continue
			if positions[slot].distance_to(platform.pos) <= PLATFORM_RADIUS + PLAYER_RADIUS:
				platform.claimed_by = slot
				break


func _advance_phase(alive: Array) -> void:
	if phase == Phase.MUSIC:
		phase = Phase.STOP
		_phase_left = STOP_SEC
		_spawn_platforms(alive)
		return
	# STOP resolved: everyone without a platform goes down together.
	var losers: Array = []
	for slot: int in alive:
		if _claim_of(slot) == null:
			losers.append(slot)
	if not losers.is_empty():
		down_order.append(losers)
	platforms = []
	phase = Phase.MUSIC
	_phase_left = rng.randf_range(MUSIC_MIN_SEC, MUSIC_MAX_SEC)


func _spawn_platforms(alive: Array) -> void:
	platforms = []
	var wanted := maxi(alive.size() - 1, 1)
	var guard := 0
	var guard_limit := PLACEMENT_ATTEMPTS_PER_PLATFORM * wanted
	while platforms.size() < wanted and guard < guard_limit:
		guard += 1
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(PLATFORM_SPACING, _platform_max_dist)
		var pos := Vector2(cos(angle), sin(angle)) * dist
		var crowded := false
		for platform: Dictionary in platforms:
			if (platform.pos as Vector2).distance_to(pos) < PLATFORM_SPACING:
				crowded = true
				break
		if not crowded:
			platforms.append({"pos": pos, "claimed_by": -1})


func _all_platforms_claimed() -> bool:
	if platforms.is_empty():
		return false
	for platform: Dictionary in platforms:
		if platform.claimed_by == -1:
			return false
	return true


func _claim_of(slot: int) -> Variant:
	for platform: Dictionary in platforms:
		if platform.claimed_by == slot:
			return platform
	return null


func _check_end() -> void:
	if finished:
		return
	var survivors := _in_slots()
	if survivors.size() > 1:
		return
	var placements: Array = []
	if not survivors.is_empty():
		placements.append(survivors)
	finish(placements + _out_placements())


func _is_in(slot: int) -> bool:
	if slot not in slots:
		return false
	for group: Array in down_order:
		if slot in group:
			return false
	return true


func _in_slots() -> Array:
	return slots.filter(_is_in)


func _out_placements() -> Array:
	var placements := down_order.duplicate(true)
	placements.reverse()
	return placements
