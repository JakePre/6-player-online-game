extends GutTest
## Quick-emote registry (M3-07): six stable wire indices.


func test_exactly_six_emotes() -> void:
	assert_eq(Emotes.EMOTES.size(), 6)


func test_index_validation() -> void:
	assert_true(Emotes.is_valid(0))
	assert_true(Emotes.is_valid(5))
	assert_false(Emotes.is_valid(-1))
	assert_false(Emotes.is_valid(6))


func test_text_lookup_with_fallback() -> void:
	assert_eq(Emotes.text(0), Emotes.EMOTES[0])
	assert_eq(Emotes.text(99), "?")
