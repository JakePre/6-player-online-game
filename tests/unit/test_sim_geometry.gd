extends GutTest
## SimGeometry (#945): pure collision/proximity math. Tests the edge cases the
## hand-rolled versions each had to get right — corner ejection, center-inside
## least-penetration, closed vs open polylines, and the degenerate same-point
## separation that would otherwise NaN.

# --- bounce_circle_box -------------------------------------------------------


func test_bounce_is_a_noop_when_the_circle_clears_the_box() -> void:
	var r := SimGeometry.bounce_circle_box(
		Vector2(5.0, 0.0), Vector2(-1.0, 0.0), Vector2.ZERO, Vector2(1.0, 1.0), 0.5, 0.8
	)
	assert_eq(r.pos, Vector2(5.0, 0.0), "far from the box, position is untouched")
	assert_eq(r.vel, Vector2(-1.0, 0.0), "and velocity is untouched")


func test_bounce_ejects_off_a_face_and_reflects_inbound_velocity() -> void:
	# Circle just right of the box's right face, moving left into it.
	var r := SimGeometry.bounce_circle_box(
		Vector2(1.3, 0.0), Vector2(-2.0, 0.0), Vector2.ZERO, Vector2(1.0, 1.0), 0.5, 0.5
	)
	assert_almost_eq(r.pos.x, 1.5, 0.001, "pushed out to face + radius (1.0 + 0.5)")
	assert_almost_eq(r.vel.x, 1.0, 0.001, "vx reflects and scales by restitution (-2*-0.5)")


func test_bounce_leaves_velocity_alone_when_already_moving_away() -> void:
	# Penetrating, but the velocity already points out of the box: reposition
	# only, don't reflect (dot >= 0).
	var r := SimGeometry.bounce_circle_box(
		Vector2(1.3, 0.0), Vector2(2.0, 0.0), Vector2.ZERO, Vector2(1.0, 1.0), 0.5, 0.5
	)
	assert_almost_eq(r.pos.x, 1.5, 0.001, "still pushed clear")
	assert_eq(r.vel, Vector2(2.0, 0.0), "outbound velocity is preserved")


func test_bounce_from_inside_ejects_along_least_penetration_axis() -> void:
	# Center inside a wide-but-short box → least penetration is vertical, so it
	# ejects along +y. `closest` == pos when inside, so the push is
	# `pos + normal*radius` (matching putt_panic): 0.1 + 0.5 = 0.6.
	var r := SimGeometry.bounce_circle_box(
		Vector2(0.0, 0.1), Vector2.ZERO, Vector2.ZERO, Vector2(3.0, 1.0), 0.5, 1.0
	)
	assert_almost_eq(r.pos.x, 0.0, 0.001, "no horizontal shift — the +y axis wins")
	assert_almost_eq(r.pos.y, 0.6, 0.001, "ejected up by one radius from the inside point")


func test_bounce_off_a_corner_uses_the_diagonal_normal() -> void:
	# Circle off the box's top-right corner, moving into it.
	var r := SimGeometry.bounce_circle_box(
		Vector2(1.2, 1.2), Vector2(-1.0, -1.0), Vector2.ZERO, Vector2(1.0, 1.0), 0.5, 1.0
	)
	assert_gt(r.pos.distance_to(Vector2(1.0, 1.0)), 0.49, "sits ~radius off the corner")
	assert_almost_eq(r.pos.distance_to(Vector2(1.0, 1.0)), 0.5, 0.001)
	assert_gt(r.vel.x, 0.0, "reflected outward on both axes")
	assert_gt(r.vel.y, 0.0)


# --- distance_to_polyline ----------------------------------------------------


func test_distance_to_closed_loop_uses_the_wrap_segment() -> void:
	# Unit square loop; a point just outside the left edge midpoint.
	var square := PackedVector2Array(
		[Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	)
	# The closing segment is (−1,1)→(−1,−1) (the left edge). A point at
	# (−1.5, 0) is 0.5 from it — only reachable via the wrap segment.
	assert_almost_eq(
		SimGeometry.distance_to_polyline(Vector2(-1.5, 0.0), square, true),
		0.5,
		0.001,
		"the last→first wrap segment is included when closed"
	)


func test_open_polyline_skips_the_wrap_segment() -> void:
	var square := PackedVector2Array(
		[Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	)
	# Open: no left edge. Nearest is the (−1,1) endpoint → distance sqrt(0.5).
	assert_almost_eq(
		SimGeometry.distance_to_polyline(Vector2(-1.5, 0.5), square, false),
		Vector2(-1.5, 0.5).distance_to(Vector2(-1.0, 1.0)),
		0.001,
		"an open chain has no wrap segment"
	)


# --- nearest_point_on_polyline (#1041) ----------------------------------------


func test_nearest_point_projects_onto_the_closest_edge() -> void:
	var square := PackedVector2Array(
		[Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	)
	# A point left of the left (wrap) edge projects straight onto it at y=0.
	var near := SimGeometry.nearest_point_on_polyline(Vector2(-1.5, 0.0), square, true)
	assert_almost_eq(near.x, -1.0, 0.001)
	assert_almost_eq(near.y, 0.0, 0.001)


func test_nearest_point_falls_back_for_a_degenerate_polyline() -> void:
	assert_eq(
		SimGeometry.nearest_point_on_polyline(Vector2(3, 4), PackedVector2Array(), true),
		Vector2(3, 4),
		"an empty polyline returns the query point unchanged"
	)
	assert_eq(
		SimGeometry.nearest_point_on_polyline(
			Vector2(3, 4), PackedVector2Array([Vector2(1, 1)]), true
		),
		Vector2(1, 1),
		"a single-point polyline is that point"
	)


func test_distance_to_polyline_handles_tiny_inputs() -> void:
	assert_eq(SimGeometry.distance_to_polyline(Vector2.ZERO, PackedVector2Array(), true), INF)
	assert_almost_eq(
		SimGeometry.distance_to_polyline(
			Vector2(3.0, 4.0), PackedVector2Array([Vector2.ZERO]), true
		),
		5.0,
		0.001,
		"a single point is just the distance to it"
	)


# --- separation_push ---------------------------------------------------------


func test_no_push_when_bodies_are_far_enough_apart() -> void:
	assert_eq(
		SimGeometry.separation_push(Vector2.ZERO, Vector2(3.0, 0.0), 2.0),
		Vector2.ZERO,
		"already >= min_gap apart: no correction"
	)


func test_overlapping_bodies_each_move_half_the_penetration() -> void:
	# 1.0 apart, want 2.0 → penetration 1.0 → each moves 0.5.
	var push := SimGeometry.separation_push(Vector2.ZERO, Vector2(1.0, 0.0), 2.0)
	assert_almost_eq(push.x, 0.5, 0.001, "half the overlap along +x")
	assert_almost_eq(push.y, 0.0, 0.001)


func test_coincident_bodies_separate_along_x_without_nan() -> void:
	var push := SimGeometry.separation_push(Vector2(2.0, 2.0), Vector2(2.0, 2.0), 1.0)
	assert_false(is_nan(push.x), "the degenerate same-point case never NaNs")
	assert_almost_eq(push.x, 0.5, 0.001, "falls back to a +x separation of half the gap")
	assert_almost_eq(push.y, 0.0, 0.001)
