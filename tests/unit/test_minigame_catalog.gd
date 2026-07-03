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
