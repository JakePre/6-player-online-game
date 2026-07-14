class_name MinigameCatalog
extends RefCounted
## Registry of playable minigames and the playlist builder (SPEC $4 selection
## rules: player-count constraints, category variety, no repeats until the
## eligible pool is exhausted, weak-tier games down-weighted per #937).

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
	register(TiltDeck.make_meta(), TiltDeck)  # #794: Tilt Deck retired Beat Bounce
	register(MusicalPlatforms.make_meta(), MusicalPlatforms)
	register(ShockTag.make_meta(), ShockTag)
	register(TreasureDivers.make_meta(), TreasureDivers)
	register(RumbleRing.make_meta(), RumbleRing)
	register(MemoryMatch.make_meta(), MemoryMatch)
	register(FishFrenzy.make_meta(), FishFrenzy)
	register(LaserLimbo.make_meta(), LaserLimbo)
	register(BullseyeBowl.make_meta(), BullseyeBowl)
	register(CountQuick.make_meta(), CountQuick)
	register(BombCourier.make_meta(), BombCourier)
	register(SnakeChain.make_meta(), SnakeChain)
	register(WallBuilders.make_meta(), WallBuilders)
	register(BasketBrawl.make_meta(), BasketBrawl)
	register(FortSiege.make_meta(), FortSiege)
	register(TheMole.make_meta(), TheMole)
	register(FaultyWiring.make_meta(), FaultyWiring)
	register(PickpocketPlaza.make_meta(), PickpocketPlaza)
	register(BlastGrid.make_meta(), BlastGrid)
	register(Dodgeball.make_meta(), Dodgeball)
	register(TurboLap.make_meta(), TurboLap)
	register(LoadoutDuel.make_meta(), LoadoutDuel)
	register(PuttPanic.make_meta(), PuttPanic)
	register(NomArena.make_meta(), NomArena)
	register(KnockOff.make_meta(), KnockOff)
	register(TumbleRun.make_meta(), TumbleRun)
	register(ShredSession.make_meta(), ShredSession)


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


## Every registered game playable at `player_count` (SPEC $4 constraints),
## minus any id in `excluded` (host-curated exclusion set, #572).
## The match-start gate checks this before a playlist is ever built (M15-01):
## with the room cap above the largest per-game cap, a head count no game
## supports must refuse to start rather than crash the picker.
static func eligible_ids(player_count: int, excluded: Array = []) -> Array:
	var excluded_names: Array[StringName] = []
	for id in excluded:
		excluded_names.append(StringName(String(id)))
	var eligible: Array = []
	for id: StringName in _entries:
		var meta: MinigameMeta = _entries[id].meta
		if player_count < meta.min_players or player_count > meta.max_players:
			continue
		if meta.even_players and player_count % 2 != 0:
			continue  # Uneven teams are never fun (#178).
		if id in excluded_names:
			continue
		eligible.append(id)
	return eligible


## Builds the match playlist. Repeats only happen when the eligible pool is
## smaller than the round count (pool resets when exhausted).
static func build_playlist(
	rng: RandomNumberGenerator, rounds: int, player_count: int, excluded: Array = []
) -> Array:
	var eligible := eligible_ids(player_count, excluded)
	assert(not eligible.is_empty(), "no minigames eligible for %d players" % player_count)

	var playlist: Array = []
	var pool := eligible.duplicate()
	while playlist.size() < rounds:
		var just_refilled := false
		if pool.is_empty():
			pool = eligible.duplicate()
			just_refilled = true
		var candidates := _without_streak_violations(pool, playlist)
		# #815: the very first pick right after a reshuffle must not repeat the
		# game that just closed the previous cycle — that reads as "playing the
		# same game twice in a row" even though the pools are technically
		# distinct. Excluded from *this draw's* candidates only (not from
		# `pool`), so the deferred game still gets drawn later in this same
		# cycle — the cycle stays the full eligible set, just reordered.
		if just_refilled and not playlist.is_empty() and candidates.size() > 1:
			candidates = candidates.duplicate()
			candidates.erase(playlist[-1])
		var pick := _weighted_pick(rng, candidates)
		pool.erase(pick)
		playlist.append(pick)
	return playlist


## Draws one id from `candidates` with probability proportional to
## QualityWeights.weight_of (#937) -- an unweighted (all-1.0) catalog
## degrades to the old uniform draw exactly.
static func _weighted_pick(rng: RandomNumberGenerator, candidates: Array) -> StringName:
	var weights: Array[float] = []
	var total := 0.0
	for id: StringName in candidates:
		var weight := QualityWeights.weight_of(id)
		weights.append(weight)
		total += weight
	var draw := rng.randf() * total
	var cumulative := 0.0
	for i in candidates.size():
		cumulative += weights[i]
		if draw < cumulative:
			return candidates[i]
	return candidates[-1]  # floating-point rounding fallback


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
