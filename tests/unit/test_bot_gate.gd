extends GutTest
## BotGate (#819): the shared "don't wait on bots" filter used by
## MinigameBase (Count Quick lock-ins, The Mole votes) and MatchController
## (the intro skip vote).


func test_filters_bot_slots_out_of_the_candidate_list() -> void:
	var result := BotGate.humans_or_everyone([0, 1, 2, 3] as Array[int], [1, 3] as Array[int])
	assert_eq(result, [0, 2])


func test_no_bots_returns_the_candidate_list_unchanged() -> void:
	var result := BotGate.humans_or_everyone([0, 1, 2] as Array[int], [] as Array[int])
	assert_eq(result, [0, 1, 2])


## An all-bot candidate list has nobody to wait FOR — falls back to
## requiring everyone rather than returning an empty gate that would
## resolve instantly.
func test_all_bots_falls_back_to_the_full_candidate_list() -> void:
	var result := BotGate.humans_or_everyone([0, 1] as Array[int], [0, 1] as Array[int])
	assert_eq(result, [0, 1])


func test_bot_slots_outside_the_candidate_list_are_irrelevant() -> void:
	var result := BotGate.humans_or_everyone([0, 1] as Array[int], [5, 6] as Array[int])
	assert_eq(result, [0, 1])


func test_empty_candidate_list_returns_empty() -> void:
	var result := BotGate.humans_or_everyone([] as Array[int], [] as Array[int])
	assert_eq(result, [])
