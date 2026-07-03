extends GutTest
## Mutator framework (M9-01): knob application is pure logic — these tests
## pin the exact semantics the M9-04/05 packs and the M9-02/03 wiring rely on.


func _plain() -> Mutator:
	return Mutator.create({"id": &"plain"})


func test_create_defaults_are_neutral() -> void:
	var mutator := _plain()
	assert_eq(mutator.award_multiplier, 1.0)
	assert_eq(mutator.pickup_cap_scale, 1.0)
	assert_eq(mutator.duration_scale, 1.0)
	assert_eq(mutator.speed_scale, 1.0)
	assert_eq(mutator.input_transform, Mutator.InputTransform.NONE)
	assert_eq(mutator.view_flags, [] as Array[StringName])
	assert_eq(mutator.end_transfer_amount, 0)


func test_to_dict_carries_the_announcement_payload() -> void:
	var mutator := (
		Mutator
		. create(
			{
				"id": &"masquerade",
				"name": "Masquerade",
				"blurb": "Nameplates hidden — who's who is the puzzle.",
				"view_flags": [&"hide_nameplates"],
			}
		)
	)
	var payload := mutator.to_dict()
	assert_eq(payload.id, "masquerade")
	assert_eq(payload.name, "Masquerade")
	assert_eq(payload.blurb, "Nameplates hidden — who's who is the puzzle.")
	assert_eq(payload.view_flags, [&"hide_nameplates"])


func test_award_multiplier_scales_and_rounds() -> void:
	var double := Mutator.create({"id": &"double", "award_multiplier": 2.0})
	assert_eq(double.apply_award_multiplier({0: 30, 1: 5}), {0: 60, 1: 10})
	var half := Mutator.create({"id": &"half", "award_multiplier": 0.5})
	assert_eq(half.apply_award_multiplier({0: 15}), {0: 8}, "rounds to whole coins")
	assert_eq(_plain().apply_award_multiplier({0: 30}), {0: 30}, "neutral is identity")


func test_pickup_cap_and_duration_and_speed_scale() -> void:
	var golden := Mutator.create({"id": &"golden", "pickup_cap_scale": 2.0})
	assert_eq(golden.scaled_pickup_cap(Economy.PICKUP_CAP), 60)
	var short_fuse := Mutator.create({"id": &"short", "duration_scale": 0.6})
	assert_almost_eq(short_fuse.scaled_duration(60.0), 36.0, 0.001)
	var overdrive := Mutator.create({"id": &"overdrive", "speed_scale": 1.25})
	assert_almost_eq(overdrive.scaled_tick_delta(1.0 / 30.0), 1.25 / 30.0, 0.0001)


func test_mirror_transform_flips_only_horizontal_intent() -> void:
	var mirror := Mutator.create(
		{"id": &"mirror", "input_transform": Mutator.InputTransform.MIRROR}
	)
	var moved := mirror.transform_input({"mx": 1.0, "my": -0.5})
	assert_eq(moved.mx, -1.0)
	assert_eq(moved.my, -0.5, "vertical intent untouched")
	assert_eq(mirror.transform_input({"jump": true}), {"jump": true}, "bespoke keys pass through")
	assert_eq(_plain().transform_input({"mx": 1.0}), {"mx": 1.0}, "NONE is identity")


func test_mirror_does_not_mutate_the_original_input() -> void:
	var mirror := Mutator.create(
		{"id": &"mirror", "input_transform": Mutator.InputTransform.MIRROR}
	)
	var original := {"mx": 1.0, "my": 0.0}
	mirror.transform_input(original)
	assert_eq(original.mx, 1.0)


func test_end_transfer_moves_coins_from_first_to_last() -> void:
	var robin := Mutator.create({"id": &"robin", "end_transfer": 10})
	var adjusted := robin.apply_end_transfer({0: 50, 1: 20, 2: 5}, [[0], [1], [2]])
	assert_eq(adjusted, {0: 40, 1: 20, 2: 15})


func test_end_transfer_handles_ties_and_splits_the_pot() -> void:
	var robin := Mutator.create({"id": &"robin", "end_transfer": 10})
	# Two tied winners each pay 10; two tied losers split the 20-coin pot.
	var adjusted := robin.apply_end_transfer({0: 50, 1: 50, 2: 5, 3: 5}, [[0, 1], [2, 3]])
	assert_eq(adjusted, {0: 40, 1: 40, 2: 15, 3: 15})
	# An odd pot leaves the remainder with the lowest slot.
	var odd := Mutator.create({"id": &"odd", "end_transfer": 5})
	var split := odd.apply_end_transfer({0: 50, 3: 0, 1: 0}, [[0], [3, 1]])
	assert_eq(split, {0: 45, 1: 3, 3: 2})


func test_end_transfer_never_takes_below_zero_and_full_tie_is_noop() -> void:
	var robin := Mutator.create({"id": &"robin", "end_transfer": 10})
	var poor := robin.apply_end_transfer({0: 3, 1: 0}, [[0], [1]])
	assert_eq(poor, {0: 0, 1: 3}, "first place only pays what they have")
	var tie := robin.apply_end_transfer({0: 10, 1: 10}, [[0, 1]])
	assert_eq(tie, {0: 10, 1: 10}, "a single placement group transfers nothing")
	assert_eq(_plain().apply_end_transfer({0: 10}, [[0]]), {0: 10}, "amount 0 is identity")


func test_catalog_registers_and_clears() -> void:
	MutatorCatalog.clear()
	assert_eq(MutatorCatalog.registered_ids(), [])
	MutatorCatalog.register(Mutator.create({"id": &"double", "name": "Double Coins"}))
	MutatorCatalog.register(Mutator.create({"id": &"blackout", "name": "Blackout"}))
	assert_true(MutatorCatalog.is_registered(&"double"))
	assert_eq(MutatorCatalog.registered_ids(), [&"blackout", &"double"])
	assert_eq(MutatorCatalog.mutator_of(&"double").display_name, "Double Coins")
	assert_null(MutatorCatalog.mutator_of(&"missing"))
	MutatorCatalog.clear()
	assert_false(MutatorCatalog.is_registered(&"double"))
