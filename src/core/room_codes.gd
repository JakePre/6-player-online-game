class_name RoomCodes
extends RefCounted
## Room join-code generation and validation. Pure logic, unit-tested.


static func generate(rng: RandomNumberGenerator) -> String:
	var code := ""
	for _i in NetConfig.ROOM_CODE_LENGTH:
		var index := rng.randi_range(0, NetConfig.ROOM_CODE_ALPHABET.length() - 1)
		code += NetConfig.ROOM_CODE_ALPHABET[index]
	return code


## Uppercases and strips whitespace so codes survive being typed or pasted.
static func normalize(raw: String) -> String:
	return raw.strip_edges().replace(" ", "").to_upper()


static func is_valid(code: String) -> bool:
	if code.length() != NetConfig.ROOM_CODE_LENGTH:
		return false
	for character in code:
		if not NetConfig.ROOM_CODE_ALPHABET.contains(character):
			return false
	return true
