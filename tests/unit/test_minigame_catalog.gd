extends GutTest
## Playlist selection rules (SPEC $4): player-count eligibility, no repeats
## until the eligible pool is exhausted, and category variety.


func before_each() -> void:
	MinigameCatalog.clear()


func after_all() -> void:
	# Leave the static registry empty so production code re-registers builtins.
	MinigameCatalog.clear()


func _register(id: StringName, category: MinigameMeta.Category, min_players := 2) -> void:
	var meta := MinigameMeta.create({"id": id, "category": category, "min_players": min_players})
	MinigameCatalog.register(meta, MinigameBase)


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng


func test_register_builtins_includes_coin_scramble() -> void:
	MinigameCatalog.register_builtins()
	assert_eq(MinigameCatalog.meta_of(&"coin_scramble").display_name, "Coin Scramble")
	var game := MinigameCatalog.instantiate(&"coin_scramble")
	assert_true(game is CoinScramble, "instantiate must return the registered script")
	assert_eq(game.meta.id, &"coin_scramble")


func test_playlist_respects_min_players() -> void:
	_register(&"duo", MinigameMeta.Category.FFA, 2)
	_register(&"crowd", MinigameMeta.Category.SKILL, 4)
	var playlist := MinigameCatalog.build_playlist(_seeded_rng(), 10, 2)
	for id: StringName in playlist:
		assert_eq(id, &"duo", "2-player playlist must exclude 4-player games")


func test_no_repeats_until_pool_exhausted() -> void:
	_register(&"a", MinigameMeta.Category.FFA)
	_register(&"b", MinigameMeta.Category.SKILL)
	_register(&"c", MinigameMeta.Category.TEAM)
	var playlist := MinigameCatalog.build_playlist(_seeded_rng(), 7, 4)
	assert_eq(playlist.size(), 7)
	# Every window of 3 consecutive rounds drains one full pool: all distinct.
	for start in [0, 3]:
		# StringName sorts by identity, not alphabet — compare as Strings.
		var window: Array = playlist.slice(start, start + 3).map(
			func(id: StringName) -> String: return String(id)
		)
		window.sort()
		assert_eq(window, ["a", "b", "c"], "rounds %d-%d must be distinct" % [start, start + 2])


## #815: a reshuffle at the pool-exhaustion boundary must not let the very
## first pick of the new cycle repeat the very last pick of the old one —
## confirmed as a real, frequent bug before the fix (100+ hits in 200 seeds
## with this exact 3-game/9-round setup).
func test_no_repeat_across_the_reshuffle_seam() -> void:
	_register(&"a", MinigameMeta.Category.FFA)
	_register(&"b", MinigameMeta.Category.SKILL)
	_register(&"c", MinigameMeta.Category.TEAM)
	for seed_value in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var playlist: Array = MinigameCatalog.build_playlist(rng, 9, 4)
		for i in range(3, playlist.size(), 3):
			assert_ne(
				playlist[i],
				playlist[i - 1],
				"seed %d: round %d repeats round %d across a reshuffle" % [seed_value, i, i - 1]
			)


## The seam-avoidance defers the last pick to the *next* cycle rather than
## dropping it — a single-game catalog has nothing to defer to, so it must
## still repeat (the only alternative is no playlist at all).
func test_single_game_catalog_still_repeats_every_round() -> void:
	_register(&"only", MinigameMeta.Category.FFA)
	var playlist := MinigameCatalog.build_playlist(_seeded_rng(), 5, 2)
	assert_eq(playlist, [&"only", &"only", &"only", &"only", &"only"])


func test_category_streak_capped_at_two_when_avoidable() -> void:
	# 3 FFA + 1 SKILL over 3 rounds: an unfiltered picker produces FFA/FFA/FFA
	# for ~1 in 4 seeds; the streak rule must always break it up.
	_register(&"ffa1", MinigameMeta.Category.FFA)
	_register(&"ffa2", MinigameMeta.Category.FFA)
	_register(&"ffa3", MinigameMeta.Category.FFA)
	_register(&"skill1", MinigameMeta.Category.SKILL)
	for seed_value in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var playlist := MinigameCatalog.build_playlist(rng, 3, 6)
		var all_ffa := playlist.all(
			func(id: StringName) -> bool:
				return MinigameCatalog.meta_of(id).category == MinigameMeta.Category.FFA
		)
		assert_false(all_ffa, "seed %d produced 3 FFA games in a row" % seed_value)


func test_single_category_catalog_still_builds() -> void:
	# Variety yields to progress when every option violates the streak rule.
	_register(&"only1", MinigameMeta.Category.FFA)
	_register(&"only2", MinigameMeta.Category.FFA)
	var playlist := MinigameCatalog.build_playlist(_seeded_rng(), 6, 3)
	assert_eq(playlist.size(), 6)


func test_playlist_deterministic_for_seed() -> void:
	_register(&"a", MinigameMeta.Category.FFA)
	_register(&"b", MinigameMeta.Category.SKILL)
	_register(&"c", MinigameMeta.Category.TEAM)
	assert_eq(
		MinigameCatalog.build_playlist(_seeded_rng(), 8, 4),
		MinigameCatalog.build_playlist(_seeded_rng(), 8, 4)
	)


func test_view_scene_path_follows_convention_and_exists_for_coin_scramble() -> void:
	var path := MinigameCatalog.view_scene_path(&"coin_scramble")
	assert_eq(path, "res://src/minigames/coin_scramble/coin_scramble_view.tscn")
	assert_true(ResourceLoader.exists(path), "reference minigame must ship its view")


func test_is_registered() -> void:
	_register(&"duo", MinigameMeta.Category.FFA, 2)
	assert_true(MinigameCatalog.is_registered(&"duo"))
	assert_false(MinigameCatalog.is_registered(&"nonexistent"))


func test_registered_ids_lists_every_registration() -> void:
	_register(&"a", MinigameMeta.Category.FFA)
	_register(&"b", MinigameMeta.Category.SKILL)
	var ids: Array = MinigameCatalog.registered_ids().map(
		func(id: StringName) -> String: return String(id)
	)
	ids.sort()
	assert_eq(ids, ["a", "b"])


## M15-01: the start gate asks this before any playlist is built — a head
## count no game supports must return empty instead of crashing the picker.
func test_eligible_ids_respects_player_count_bounds() -> void:
	_register(&"duo", MinigameMeta.Category.FFA, 2)  # max_players defaults to 6
	_register(&"crowd", MinigameMeta.Category.SKILL, 4)
	var at_two: Array = MinigameCatalog.eligible_ids(2).map(
		func(id: StringName) -> String: return String(id)
	)
	assert_eq(at_two, ["duo"], "below crowd's min_players only duo qualifies")
	var at_six: Array = MinigameCatalog.eligible_ids(6).map(
		func(id: StringName) -> String: return String(id)
	)
	at_six.sort()
	assert_eq(at_six, ["crowd", "duo"], "both fit at 6")
	assert_eq(
		MinigameCatalog.eligible_ids(7),
		[],
		"above every game's max_players nothing is eligible — the start gate's case"
	)


func test_eligible_ids_skips_even_players_games_at_odd_counts() -> void:
	MinigameCatalog.register(
		MinigameMeta.create({"id": &"pairs_only", "even_players": true, "min_players": 4}),
		MinigameBase
	)
	assert_false(&"pairs_only" in MinigameCatalog.eligible_ids(5), "no 3v2 drafts (#178)")
	assert_true(&"pairs_only" in MinigameCatalog.eligible_ids(6))


func test_even_players_games_skipped_at_odd_counts() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register(
		MinigameMeta.create({"id": &"pairs_only", "even_players": true, "min_players": 4}),
		MinigameBase
	)
	MinigameCatalog.register(MinigameMeta.create({"id": &"any_count"}), MinigameBase)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_false(&"pairs_only" in MinigameCatalog.build_playlist(rng, 8, 5), "no 3v2 drafts (#178)")
	assert_true(&"pairs_only" in MinigameCatalog.build_playlist(rng, 8, 6))
	MinigameCatalog.clear()


## #572: the host exclusion set subtracts from eligibility; every existing
## call site (both here and net_manager's pre-start gate) keeps working
## unchanged since `excluded` defaults to empty.
func test_eligible_ids_subtracts_excluded_set() -> void:
	_register(&"duo", MinigameMeta.Category.FFA, 2)
	_register(&"crowd", MinigameMeta.Category.SKILL, 2)
	var ids: Array = MinigameCatalog.eligible_ids(2, ["duo"]).map(
		func(id: StringName) -> String: return String(id)
	)
	assert_eq(ids, ["crowd"], "excluded id must be subtracted")


func test_eligible_ids_unaffected_when_excluded_empty() -> void:
	_register(&"duo", MinigameMeta.Category.FFA, 2)
	_register(&"crowd", MinigameMeta.Category.SKILL, 2)
	var without_param: Array = MinigameCatalog.eligible_ids(2).map(
		func(id: StringName) -> String: return String(id)
	)
	var with_empty: Array = MinigameCatalog.eligible_ids(2, []).map(
		func(id: StringName) -> String: return String(id)
	)
	without_param.sort()
	with_empty.sort()
	assert_eq(without_param, with_empty)


func test_build_playlist_never_drafts_excluded_games() -> void:
	_register(&"a", MinigameMeta.Category.FFA)
	_register(&"b", MinigameMeta.Category.SKILL)
	_register(&"c", MinigameMeta.Category.TEAM)
	var playlist := MinigameCatalog.build_playlist(_seeded_rng(), 12, 4, [&"a", &"b"])
	for id: StringName in playlist:
		assert_eq(id, &"c", "excluded games must never be drafted")


func test_build_playlist_unaffected_when_excluded_empty() -> void:
	_register(&"a", MinigameMeta.Category.FFA)
	_register(&"b", MinigameMeta.Category.SKILL)
	_register(&"c", MinigameMeta.Category.TEAM)
	assert_eq(
		MinigameCatalog.build_playlist(_seeded_rng(), 8, 4),
		MinigameCatalog.build_playlist(_seeded_rng(), 8, 4, [])
	)
