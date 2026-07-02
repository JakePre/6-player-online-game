extends GutTest


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng


func test_generate_has_correct_length_and_alphabet() -> void:
	var rng := _seeded_rng()
	for _i in 100:
		var code := RoomCodes.generate(rng)
		assert_eq(code.length(), NetConfig.ROOM_CODE_LENGTH)
		for character in code:
			assert_true(
				NetConfig.ROOM_CODE_ALPHABET.contains(character),
				"unexpected character %s" % character
			)


func test_alphabet_excludes_ambiguous_characters() -> void:
	for banned in ["0", "O", "1", "I"]:
		assert_false(NetConfig.ROOM_CODE_ALPHABET.contains(banned), "%s is ambiguous" % banned)


func test_normalize_uppercases_and_strips() -> void:
	assert_eq(RoomCodes.normalize("  ab cdef\n"), "ABCDEF")


func test_is_valid() -> void:
	assert_true(RoomCodes.is_valid("ABCDEF"))
	assert_false(RoomCodes.is_valid("ABCDE"), "too short")
	assert_false(RoomCodes.is_valid("ABCDEFG"), "too long")
	assert_false(RoomCodes.is_valid("ABCDE0"), "0 not in alphabet")
	assert_false(RoomCodes.is_valid("abcdef"), "lowercase must be normalized first")
