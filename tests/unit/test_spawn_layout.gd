extends GutTest
## Shared spawn-layout helper (M15-05 / ADR-003 F5): distributes N spawn
## positions across concentric rings so dense lobbies keep their spacing while
## small lobbies still get the single even ring games have always used.


func _radii_seen(positions: Array) -> Dictionary:
	# Distinct ring radii (rounded), so we can tell one ring from several.
	var seen := {}
	for pos: Vector2 in positions:
		seen[roundi(pos.length() * 10.0)] = true
	return seen


func _min_pairwise_distance(positions: Array) -> float:
	var closest := INF
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			closest = minf(closest, (positions[i] as Vector2).distance_to(positions[j]))
	return closest


func test_non_positive_count_is_empty() -> void:
	assert_eq(SpawnLayout.ring_positions(0, 5.0), [] as Array[Vector2])
	assert_eq(SpawnLayout.ring_positions(-3, 5.0), [] as Array[Vector2])


func test_solo_spawns_in_the_center() -> void:
	var positions := SpawnLayout.ring_positions(1, 5.0)
	assert_eq(positions.size(), 1)
	assert_eq(positions[0], Vector2.ZERO)


func test_returns_exactly_count_positions() -> void:
	for count in [2, 6, 8, 12, 17, 24]:
		assert_eq(
			SpawnLayout.ring_positions(count, 5.0).size(), count, "exactly %d positions" % count
		)


func test_small_count_is_one_even_ring() -> void:
	assert_eq(SpawnLayout.ring_count(6), 1, "six fit on one ring")
	var positions := SpawnLayout.ring_positions(6, 5.0)
	assert_eq(_radii_seen(positions).size(), 1, "all six share one ring")
	for pos: Vector2 in positions:
		assert_almost_eq(pos.length(), 5.0, 0.001, "each sits on the given radius")


func test_dense_counts_fan_out_over_multiple_rings() -> void:
	assert_eq(SpawnLayout.ring_count(12), 2, "twelve need two rings")
	assert_eq(SpawnLayout.ring_count(24), 3, "twenty-four need three rings")
	assert_eq(_radii_seen(SpawnLayout.ring_positions(24, 5.0)).size(), 3, "spread over three rings")


func test_all_positions_stay_within_radius() -> void:
	for pos: Vector2 in SpawnLayout.ring_positions(24, 5.0):
		assert_lte(pos.length(), 5.0 + 0.001, "no one spawns outside the arena")


func test_dense_counts_keep_their_spacing() -> void:
	# 24 in a radius-5 arena: the tightest gap is the inter-ring step (~1.67).
	assert_gt(
		_min_pairwise_distance(SpawnLayout.ring_positions(24, 5.0)),
		1.0,
		"no two players overlap even at 24"
	)
