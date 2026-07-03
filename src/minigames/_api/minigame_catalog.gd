class_name MinigameCatalog
extends RefCounted
## Registry of playable minigames and the playlist builder (SPEC $4 selection
## rules: player-count constraints, category variety, no repeats until the
## eligible pool is exhausted).

## Maximum consecutive rounds of the same category.
const MAX_CATEGORY_STREAK := 2

static var _entries := {}


static func register(meta: MinigameMeta, script: GDScript) -> void:
	_entries[meta.id] = {"meta": meta, "script": script}


static func clear() -> void:
	_entries.clear()


static func register_builtins() -> void:
	if not _entries.is_empty():
		return
	register(CoinScramble.make_meta(), CoinScramble)
	register(KingOfTheHill.make_meta(), KingOfTheHill)
	register(PoisonFeast.make_meta(), PoisonFeast)
	register(QuickDraw.make_meta(), QuickDraw)
	register(SumoSmash.make_meta(), SumoSmash)
	register(HotPotato.make_meta(), HotPotato)
	register(TugOfWar.make_meta(), TugOfWar)
	register(ColorClash.make_meta(), ColorClash)
	register(ThinIce.make_meta(), ThinIce)
	register(RelaySprint.make_meta(), RelaySprint)
	register(HeistNight.make_meta(), HeistNight)
	register(CartPush.make_meta(), CartPush)
	register(TrapCorridor.make_meta(), TrapCorridor)
	register(HurdleDash.make_meta(), HurdleDash)
	register(MeteorShower.make_meta(), MeteorShower)
	register(BulletWaltz.make_meta(), BulletWaltz)
	register(SimonStomp.make_meta(), SimonStomp)
	register(TargetRange.make_meta(), TargetRange)
	register(BeatBounce.make_meta(), BeatBounce)


static func meta_of(id: StringName) -> MinigameMeta:
	return _entries[id].meta


static func is_registered(id: StringName) -> bool:
	return _entries.has(id)


static func registered_ids() -> Array:
	return _entries.keys()


static func instantiate(id: StringName) -> MinigameBase:
	var game: MinigameBase = (_entries[id].script as GDScript).new()
	game.meta = _entries[id].meta
	return game


## Conventional location of a minigame's client view scene (root script
## extends MinigameView). The match screen falls back to a placeholder when
## the scene does not exist yet.
static func view_scene_path(id: StringName) -> String:
	return "res://src/minigames/%s/%s_view.tscn" % [id, id]


## Builds the match playlist. Repeats only happen when the eligible pool is
## smaller than the round count (pool resets when exhausted).
static func build_playlist(rng: RandomNumberGenerator, rounds: int, player_count: int) -> Array:
	var eligible: Array = []
	for id: StringName in _entries:
		var meta: MinigameMeta = _entries[id].meta
		if player_count >= meta.min_players and player_count <= meta.max_players:
			eligible.append(id)
	assert(not eligible.is_empty(), "no minigames eligible for %d players" % player_count)

	var playlist: Array = []
	var pool := eligible.duplicate()
	while playlist.size() < rounds:
		if pool.is_empty():
			pool = eligible.duplicate()
		var candidates := _without_streak_violations(pool, playlist)
		var pick: StringName = candidates[rng.randi_range(0, candidates.size() - 1)]
		pool.erase(pick)
		playlist.append(pick)
	return playlist


static func _without_streak_violations(pool: Array, playlist: Array) -> Array:
	if playlist.size() < MAX_CATEGORY_STREAK:
		return pool
	var last_category: MinigameMeta.Category = meta_of(playlist[-1]).category
	for i in range(2, MAX_CATEGORY_STREAK + 1):
		if meta_of(playlist[-i]).category != last_category:
			return pool
	var filtered := pool.filter(
		func(id: StringName) -> bool: return meta_of(id).category != last_category
	)
	# With a tiny catalog every option may violate the rule; variety yields to
	# progress.
	return filtered if not filtered.is_empty() else pool
