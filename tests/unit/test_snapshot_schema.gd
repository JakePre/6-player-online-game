extends GutTest
## Snapshot wire-shape tripwire (#946, hardening the #708 PS_* convention).
##
## The positional player arrays in get_snapshot() are held together by PR-body
## discipline — nothing programmatically catches a slot being reinterpreted in
## place (Count Quick once flipped PS_LOCKED bool -> PS_ANSWER int with only a
## note) or a slot being added/removed. That class of drift only ever shows up
## as a cross-version desync, far from its cause.
##
## The tripwire: a game opts in by declaring, next to its PS_* indices,
##     const PLAYER_SCHEMA := [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, ...]
## one entry per slot of a `players` snapshot row. This test instantiates every
## catalog game, builds a snapshot, and checks each row against the declaration:
## right length, and each element's kind matches. A game that hasn't declared
## one yet is skipped — the per-game declarations land as an incremental fan-out,
## not all-or-nothing.
##
## Kind, not exact type: TYPE_INT and TYPE_FLOAT are one "number" kind, because
## the wire (and every view's `float(row[i])` read) does not distinguish them —
## a round number in a float slot is not a bug. Bools, strings, arrays, etc. are
## their own kinds, so the reinterpretations that DO break versions across the
## wire (bool<->number, number<->array) and any length change still fail loudly.
## Explicitly NOT binary packing (out of scope per the issue / #463/#479).

const TICK := 1.0 / 30.0
## The const name a game declares to opt into player-row validation.
const SCHEMA_CONST := "PLAYER_SCHEMA"


## Collapse a Variant.Type to its wire-visible kind. Numbers share one kind;
## everything else is itself.
func _kind(t: int) -> int:
	if t == TYPE_INT or t == TYPE_FLOAT:
		return TYPE_FLOAT
	return t


func _kind_name(t: int) -> String:
	match _kind(t):
		TYPE_FLOAT:
			return "number"
		TYPE_BOOL:
			return "bool"
		TYPE_STRING, TYPE_STRING_NAME:
			return "string"
		TYPE_ARRAY:
			return "array"
		TYPE_DICTIONARY:
			return "dictionary"
		_:
			return "type#%d" % t


func test_every_declared_game_matches_its_player_schema() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	var declared := 0
	var checked_rows := 0
	for id: StringName in MinigameCatalog.registered_ids():
		var game: MinigameBase = MinigameCatalog.instantiate(id)
		game.meta = game.make_meta()
		var schema: Variant = game.get_script().get_script_constant_map().get(SCHEMA_CONST, null)
		if schema == null:
			continue  # not opted in yet — the fan-out declares these incrementally
		declared += 1
		assert_true(
			schema is Array, "%s: %s must be an Array of TYPE_* entries" % [id, SCHEMA_CONST]
		)

		# Even head count so team games get a clean draft (mirrors test_safe_input).
		var count: int = maxi(int(game.meta.min_players), 4)
		if count % 2 == 1:
			count += 1
		var player_slots: Array[int] = []
		for i in count:
			player_slots.append(i)
		game.setup(player_slots, 42)
		# One quiet tick so any get_snapshot() state populated on the first frame is
		# present; no input, so nobody is eliminated out of the roster.
		game.tick(TICK)

		var players: Variant = game.get_snapshot().get("players", {})
		assert_true(
			players is Dictionary,
			"%s declares %s but its snapshot has no `players` dict" % [id, SCHEMA_CONST]
		)
		if not (players is Dictionary):
			continue
		for slot: Variant in players:
			var row: Variant = players[slot]
			checked_rows += 1
			assert_true(row is Array, "%s: players[%s] should be a positional Array" % [id, slot])
			if not (row is Array):
				continue
			assert_eq(
				(row as Array).size(),
				(schema as Array).size(),
				(
					"%s: players[%s] has %d slots, %s declares %d"
					% [id, slot, (row as Array).size(), SCHEMA_CONST, (schema as Array).size()]
				)
			)
			var n: int = mini((row as Array).size(), (schema as Array).size())
			for i in n:
				var want: int = int((schema as Array)[i])
				var got: int = typeof((row as Array)[i])
				assert_eq(
					_kind(got),
					_kind(want),
					(
						"%s: players[%s] slot %d is a %s, schema declares %s"
						% [id, slot, i, _kind_name(got), _kind_name(want)]
					)
				)
	MinigameCatalog.clear()
	assert_gt(declared, 0, "at least the reference games declare a PLAYER_SCHEMA")
	assert_gt(checked_rows, 0, "validated at least one player row")


## Guards the checker itself: the kind buckets catch the drift classes the issue
## cares about (bool<->number reinterpret, length change) while tolerating the
## int/float distinction the wire never sees.
func test_kind_buckets_number_but_separates_bool() -> void:
	assert_eq(_kind(TYPE_INT), _kind(TYPE_FLOAT), "int and float are one wire-number kind")
	assert_ne(_kind(TYPE_BOOL), _kind(TYPE_INT), "bool is a distinct kind from a number")
	assert_ne(_kind(TYPE_ARRAY), _kind(TYPE_FLOAT), "an array is not a number")
