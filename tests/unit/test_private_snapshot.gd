extends GutTest
## Per-player private snapshot hook (#254): the framework delivers a
## minigame's secret per-slot state only to that player's own client, and
## only during an in-progress round.


## Reveals a role to slot 0 alone — the shared snapshot stays anonymous.
class MoleStub:
	extends MinigameBase

	func get_private_snapshot(slot: int) -> Dictionary:
		return {"role": "mole"} if slot == 0 else {}


func _make_room(player_count: int) -> Room:
	var room := Room.new()
	room.code = "TEST42"
	for i in player_count:
		room.add_member(100 + i, "P%d" % i, "token%d" % i)
	return room


func _make_controller() -> MatchController:
	MinigameCatalog.clear()
	MinigameCatalog.register(MinigameMeta.create({"id": &"mole", "duration_sec": 60.0}), MoleStub)
	return MatchController.new(
		_make_room(3), {"seed": 7, "playlist": [&"mole", &"mole"], "rounds": 2}
	)


func after_all() -> void:
	MinigameCatalog.clear()


func test_base_minigame_reveals_nothing_by_default() -> void:
	var game := MinigameBase.new()
	assert_eq(game.get_private_snapshot(0), {})


func test_private_data_reaches_only_the_owning_slot_during_play() -> void:
	var controller := _make_controller()
	controller.game = MoleStub.new()
	controller.state = MatchController.State.PLAY
	assert_eq(controller.private_snapshot_for(0), {"role": "mole"}, "the mole learns their role")
	assert_eq(controller.private_snapshot_for(1), {}, "everyone else learns nothing")


func test_no_private_data_outside_an_active_round() -> void:
	var controller := _make_controller()
	controller.game = MoleStub.new()
	controller.state = MatchController.State.INTRO
	assert_eq(controller.private_snapshot_for(0), {}, "secrets only flow during PLAY")
	controller.state = MatchController.State.RESULTS
	assert_eq(controller.private_snapshot_for(0), {})


func test_shared_snapshot_never_carries_the_secret() -> void:
	var controller := _make_controller()
	var stub := MoleStub.new()
	stub.meta = MinigameMeta.create({"id": &"mole", "duration_sec": 60.0})
	controller.game = stub
	controller.state = MatchController.State.PLAY
	# The broadcast-to-everyone snapshot must stay anonymous; the role only
	# ever travels through private_snapshot_for.
	assert_false(JSON.stringify(controller.get_snapshot()).contains("mole"))
