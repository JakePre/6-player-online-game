extends GutTest
## Match-input trust boundary (#970). Unit-tests the sanitizer, then fires the
## full hostile payload matrix at EVERY registered catalog game through it and
## asserts no game's snapshot ever ships a non-finite number — the regression
## net for every current and future minigame.

const TICK := 1.0 / 30.0

## Every shape a modified client can put in the input Dictionary (all pass the
## RPC's top-level type check). Before #970 these poisoned positions to NaN.
const HOSTILE := [
	{"mx": "1e999", "my": "1e999"},  # string → INF via the sim's float()
	{"mx": INF, "my": 0.0},  # raw INF float
	{"mx": NAN, "my": NAN},  # raw NaN float
	{"mx": [], "my": {}},  # containers → NaN
	{"ax": "1e999", "ay": "1e999", "power": "1e999"},  # putt aim/charge
	{"mx": -INF, "my": INF, "jump": true, "dive": true, "shoot": true, "use": true, "act": true},
]

# --- sanitizer unit tests -----------------------------------------------------


func test_finite_scalars_pass_through() -> void:
	var clean: Dictionary = SafeInput.sanitize({"mx": 1.5, "my": -0.5, "count": 3, "jump": true})
	assert_eq(clean, {"mx": 1.5, "my": -0.5, "count": 3, "jump": true})


func test_non_finite_floats_become_zero() -> void:
	assert_eq(SafeInput.sanitize({"mx": INF}), {"mx": 0.0})
	assert_eq(SafeInput.sanitize({"mx": -INF}), {"mx": 0.0})
	assert_eq(SafeInput.sanitize({"mx": NAN}), {"mx": 0.0})


func test_strings_are_dropped_including_the_1e999_exploit() -> void:
	# "1e999" is the nasty one — it *looks* like the benign junk the old tests
	# sent, but float("1e999") == INF. Dropping it means the field reads default.
	assert_false(SafeInput.sanitize({"mx": "1e999"}).has("mx"))
	assert_false(SafeInput.sanitize({"mx": "garbage"}).has("mx"))


func test_containers_and_objects_are_dropped() -> void:
	var clean: Dictionary = SafeInput.sanitize({"mx": [], "my": {}, "z": Vector2(1, 1)})
	assert_eq(clean, {}, "arrays, dicts, vectors all dropped")


func test_oversized_dict_is_rejected_whole() -> void:
	var big := {}
	for i in SafeInput.MAX_KEYS + 5:
		big["k%d" % i] = 1.0
	assert_eq(SafeInput.sanitize(big), {}, "a flood of keys is hostile")


func test_non_string_keys_are_dropped() -> void:
	assert_eq(SafeInput.sanitize({0: 1.0, "mx": 2.0}), {"mx": 2.0})


# --- the regression net: no catalog game can be poisoned ----------------------


## Recursively true if any float anywhere in `value` is NaN or INF.
func _has_non_finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return not is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if _has_non_finite(item):
					return true
		TYPE_DICTIONARY:
			for k: Variant in value:
				if _has_non_finite(value[k]):
					return true
	return false


func test_no_catalog_game_ships_a_non_finite_snapshot_under_attack() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	var checked := 0
	for id: StringName in MinigameCatalog.registered_ids():
		var game: MinigameBase = MinigameCatalog.instantiate(id)
		game.meta = game.make_meta()
		var count: int = maxi(int(game.meta.min_players), 4)
		if count % 2 == 1:
			count += 1  # team games need an even draft
		var player_slots: Array[int] = []
		for i in count:
			player_slots.append(i)
		game.setup(player_slots, 42)
		# Every slot floods hostile input — but through the boundary sanitizer.
		for payload: Dictionary in HOSTILE:
			for s: int in player_slots:
				game.handle_input(s, SafeInput.sanitize(payload))
			game.tick(TICK)
		assert_false(
			_has_non_finite(game.get_snapshot()),
			"%s ships a non-finite value under hostile input" % id
		)
		checked += 1
	MinigameCatalog.clear()
	assert_gt(checked, 30, "swept the whole roster")
