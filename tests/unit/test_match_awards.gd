extends GutTest
## End-of-match superlatives (#934): the pure MatchAwards.derive() pass over
## existing match data — per-round placements + pickup coins, final standings,
## finale KOs. Deterministic (lowest-slot ties), each award given only when it
## has a real winner.


func _record(placements: Array, pickup := {}, totals_before := {}) -> Dictionary:
	return {"placements": placements, "pickup_coins": pickup, "totals_before": totals_before}


func _standings(order: Array) -> Array:
	var out: Array = []
	for slot: int in order:
		out.append({"slot": slot, "name": "P%d" % slot, "score": 0})
	return out


func _award(awards: Array, id: StringName) -> Dictionary:
	for a: Dictionary in awards:
		if a.id == id:
			return a
	return {}


func test_frontrunner_takes_the_most_round_wins() -> void:
	var records := [
		_record([[0], [1]]),
		_record([[0], [1]]),
		_record([[1], [0]]),
	]
	var awards := MatchAwards.derive(records, _standings([0, 1]), {})
	assert_eq(_award(awards, &"frontrunner").slot, 0, "slot 0 won two rounds")


func test_coin_baron_takes_the_most_pickup_coins() -> void:
	var records := [
		_record([[0]], {0: 3, 1: 5}),
		_record([[1]], {0: 2, 1: 1}),
	]
	# slot 0: 5, slot 1: 6 -> baron is 1.
	var awards := MatchAwards.derive(records, _standings([0, 1]), {})
	assert_eq(_award(awards, &"coin_baron").slot, 1)


func test_clutch_is_a_round_win_from_dead_last() -> void:
	# slot 2 sits last in totals, then wins the round -> clutch.
	var records := [
		_record([[2], [0], [1]], {}, {0: 10, 1: 8, 2: 2}),
		_record([[0], [1], [2]], {}, {0: 14, 1: 11, 2: 9}),
	]
	var awards := MatchAwards.derive(records, _standings([0, 1, 2]), {})
	assert_eq(_award(awards, &"clutch").slot, 2, "won a round while trailing")
	# slot 0 also won a round but was never last -> no clutch credit to 0.
	assert_ne(_award(awards, &"clutch").slot, 0)


func test_assassin_takes_the_most_finale_kos() -> void:
	var awards := MatchAwards.derive([], _standings([0, 1, 2]), {0: 1, 1: 3, 2: 2})
	assert_eq(_award(awards, &"assassin").slot, 1)


func test_no_finale_kos_gives_no_assassin() -> void:
	var awards := MatchAwards.derive([_record([[0]])], _standings([0, 1]), {})
	assert_true(_award(awards, &"assassin").is_empty(), "no KOs -> no Assassin award")


func test_wooden_spoon_goes_to_dead_last_in_standings() -> void:
	var awards := MatchAwards.derive([_record([[0]])], _standings([2, 0, 1]), {})
	assert_eq(_award(awards, &"wooden_spoon").slot, 1, "last in the standings order")


func test_solo_standings_give_no_wooden_spoon() -> void:
	var awards := MatchAwards.derive([_record([[0]])], _standings([0]), {})
	assert_true(_award(awards, &"wooden_spoon").is_empty(), "no roast with one player")


func test_ties_break_to_the_lowest_slot() -> void:
	# slots 1 and 2 both win one round; the lower slot takes Frontrunner.
	var records := [_record([[1], [2]]), _record([[2], [1]])]
	var awards := MatchAwards.derive(records, _standings([1, 2]), {})
	assert_eq(_award(awards, &"frontrunner").slot, 1, "deterministic lowest-slot tiebreak")


func test_awards_carry_title_and_icon() -> void:
	var awards := MatchAwards.derive([_record([[0]], {0: 5})], _standings([0, 1]), {})
	var baron := _award(awards, &"coin_baron")
	assert_eq(baron.title, "Coin Baron")
	assert_false(String(baron.icon).is_empty(), "an icon rides each award")
