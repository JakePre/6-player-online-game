extends GutTest
## Member appearance replication (#935) — split from test_room.gd to stay under
## the public-method lint cap: the worn hat rides the room state next to
## character/color, additive and defaulting bare-headed.


func _room_with(count: int) -> Room:
	var room := Room.new()
	room.code = "TESTAA"
	for i in count:
		room.add_member(100 + i, "P%d" % i, "token%d" % i)
	return room


func test_hat_defaults_to_none_and_replicates() -> void:
	var room := _room_with(2)
	assert_eq(room.members[0].hat_id, HatCatalog.NONE, "bare-headed by default")
	assert_eq(room.members[0].to_dict().hat_id, HatCatalog.NONE, "rides to_dict")
	room.members[0].hat_id = &"top_hat"
	var state := room.to_state_dict()
	assert_eq(state.members[0].hat_id, &"top_hat", "a chosen hat replicates")
	assert_eq(state.members[1].hat_id, HatCatalog.NONE)
