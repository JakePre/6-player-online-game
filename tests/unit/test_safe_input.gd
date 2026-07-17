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
	# Now that numeric arrays pass (#1030/#1042), prove poison inside one can't
	# survive: string elements reject the whole array, non-finite ones zero out.
	{"trap": ["1e999", "1e999"], "grudge": [INF, NAN], "sabotage": [-INF, "x"]},
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


func test_empty_arrays_bare_dicts_and_objects_are_dropped() -> void:
	# An empty array carries no intent; a dict under a non-shop key and a vector
	# are always hostile/erroneous. (Numeric arrays and the shop dict have their
	# own passing rules, tested below.)
	var clean: Dictionary = SafeInput.sanitize({"mx": [], "my": {}, "z": Vector2(1, 1)})
	assert_eq(clean, {}, "empty array, non-shop dict, and vector all dropped")


# --- numeric arrays: trap [col,row], grudge/sabotage [x,y] (#1030/#1042) -------


func test_numeric_arrays_pass_through() -> void:
	# The real client payloads: trap placement (ints) and finale targeting (floats).
	assert_eq(SafeInput.sanitize({"trap": [3, 5]}), {"trap": [3, 5]})
	assert_eq(SafeInput.sanitize({"grudge": [1.5, -2.0]}), {"grudge": [1.5, -2.0]})


func test_non_finite_array_elements_become_zero() -> void:
	assert_eq(SafeInput.sanitize({"grudge": [INF, NAN]}), {"grudge": [0.0, 0.0]})
	assert_eq(SafeInput.sanitize({"sabotage": [-INF, 2.0]}), {"sabotage": [0.0, 2.0]})


func test_array_with_any_non_number_element_is_rejected_whole() -> void:
	# A string element would still be float()-coerced into INF by a consumer, so
	# the whole array is dropped rather than partially coerced.
	assert_false(SafeInput.sanitize({"trap": ["1e999", 5]}).has("trap"))
	assert_false(SafeInput.sanitize({"grudge": [1.0, {}]}).has("grudge"))


func test_oversized_array_is_rejected() -> void:
	var long := []
	for i in SafeInput.ARRAY_MAX_LEN + 1:
		long.append(1.0)
	assert_false(SafeInput.sanitize({"trap": long}).has("trap"), "an over-long array is hostile")


# --- the finale shop's nested string dict (#1030) -----------------------------


## The playtest picker (#1070): `pick` is the one top-level string that
## survives — its consumer only id-matches it, never float()-coerces.
func test_pick_string_survives_but_stays_bounded() -> void:
	assert_eq(SafeInput.sanitize({"pick": "basket_brawl"}), {"pick": "basket_brawl"})
	assert_eq(SafeInput.sanitize({"pick": "end"}), {"pick": "end"})
	var giant := "x".repeat(SafeInput.PICK_STRING_MAX_LEN + 1)
	assert_eq(SafeInput.sanitize({"pick": giant}), {}, "over-long pick dropped whole")
	assert_eq(SafeInput.sanitize({"pick": 1e999}), {}, "a non-string pick is dropped whole")
	assert_eq(SafeInput.sanitize({"pick": {}}), {}, "non-string non-scalar pick dropped")


func test_shop_intent_survives_with_its_strings() -> void:
	var clean: Dictionary = SafeInput.sanitize({"shop": {"action": "buy", "item": "shield"}})
	assert_eq(clean, {"shop": {"action": "buy", "item": "shield"}})


func test_shop_confirm_intent_survives() -> void:
	assert_eq(SafeInput.sanitize({"shop": {"action": "confirm"}}), {"shop": {"action": "confirm"}})


func test_shop_only_special_cases_the_shop_key() -> void:
	# A dict under any other key stays dropped — only `shop` opens the nested path.
	assert_false(SafeInput.sanitize({"loot": {"action": "buy"}}).has("loot"))


func test_shop_drops_an_over_long_string_but_keeps_the_rest() -> void:
	var huge := "x".repeat(SafeInput.SHOP_STRING_MAX_LEN + 1)
	var clean: Dictionary = SafeInput.sanitize({"shop": {"action": "buy", "item": huge}})
	assert_eq(clean, {"shop": {"action": "buy"}}, "the giant string is dropped, buy still stands")


func test_oversized_shop_dict_is_rejected_and_key_dropped() -> void:
	var big := {}
	for i in SafeInput.SHOP_MAX_KEYS + 2:
		big["k%d" % i] = "v"
	assert_false(SafeInput.sanitize({"shop": big}).has("shop"), "a flood inside shop is hostile")


func test_shop_with_a_non_dict_value_is_dropped() -> void:
	assert_false(SafeInput.sanitize({"shop": "buy"}).has("shop"), "shop must be a dict")
	assert_false(SafeInput.sanitize({"shop": [1, 2]}).has("shop"))


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
