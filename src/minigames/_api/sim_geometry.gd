class_name SimGeometry
extends RefCounted
## Pure 2D collision/proximity math shared by the sims (#945).
##
## Several games re-implemented the same geometry by hand — circle-vs-AABB
## bounce with penetration ejection (putt_panic), the distance-to-a-closed-
## -track test (turbo_lap), and the overlapping-body soft-separation push
## (memory_match). This collects the exact, tested-once versions so the next
## ball/brawler game gets correct math for free.
##
## All functions are static and pure: they take values and return values,
## never touching sim state. Callers keep ownership of their `positions` /
## `velocities` dictionaries and apply the returned results.
##
## NOTE (§10): related-looking loops that are NOT unified here because their
## resolution genuinely differs — king_of_the_hill / cart_push push bodies a
## *fixed* distance (not proportional), sumo_smash applies velocity *impulses*
## rather than moving positions, and coin_scramble is a bump-with-cooldown
## that scatters the loser. Folding those into separation_push() would change
## behavior; they stay as-is.


## Bounces a moving circle out of an axis-aligned box and reflects its
## velocity, matching putt_panic's `_bounce_box`. Returns
## `{"pos": Vector2, "vel": Vector2}`; both are the inputs unchanged when the
## circle isn't penetrating the box (so applying the result is a no-op then).
##
## `center`/`half` describe the box; `radius` is the circle radius;
## `restitution` scales the reflected velocity (1.0 = elastic).
static func bounce_circle_box(
	pos: Vector2, vel: Vector2, center: Vector2, half: Vector2, radius: float, restitution: float
) -> Dictionary:
	var closest := Vector2(
		clampf(pos.x, center.x - half.x, center.x + half.x),
		clampf(pos.y, center.y - half.y, center.y + half.y)
	)
	var to_circle := pos - closest
	var dist := to_circle.length()
	if dist >= radius:
		return {"pos": pos, "vel": vel}
	var normal: Vector2
	if dist > 0.0001:
		normal = to_circle / dist
	else:
		# Center inside the box: eject along the axis of least penetration.
		var px := half.x - absf(pos.x - center.x)
		var py := half.y - absf(pos.y - center.y)
		normal = (
			Vector2(signf(pos.x - center.x), 0.0)
			if px < py
			else Vector2(0.0, signf(pos.y - center.y))
		)
	var out_pos := closest + normal * radius
	var out_vel := vel
	if vel.dot(normal) < 0.0:
		out_vel = (vel - 2.0 * vel.dot(normal) * normal) * restitution
	return {"pos": out_pos, "vel": out_vel}


## Shortest distance from `point` to a polyline through `points`, matching
## turbo_lap's `_on_track` distance test. When `closed` (default), the final
## segment wraps from the last point back to the first (a loop); otherwise the
## chain is open. Returns INF for an empty `points` array.
static func distance_to_polyline(
	point: Vector2, points: PackedVector2Array, closed := true
) -> float:
	var count := points.size()
	if count == 0:
		return INF
	if count == 1:
		return point.distance_to(points[0])
	var segments := count if closed else count - 1
	var best := INF
	for i in segments:
		var a := points[i]
		var b := points[(i + 1) % count]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		best = minf(best, point.distance_to(closest))
	return best


## The point on the polyline nearest to `point` — the projection distance_to_
## polyline() measures but discards. Used to confine a body to a ribbon of a
## given half-width around a centerline (turbo_lap's track walls, #1041): push
## the body to nearest + (point - nearest).normalized() * half_width when it
## strays past the edge. Returns `point` itself for an empty polyline.
static func nearest_point_on_polyline(
	point: Vector2, points: PackedVector2Array, closed := true
) -> Vector2:
	var count := points.size()
	if count == 0:
		return point
	if count == 1:
		return points[0]
	var segments := count if closed else count - 1
	var best := points[0]
	var best_d := INF
	for i in segments:
		var a := points[i]
		var b := points[(i + 1) % count]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var d := point.distance_to(closest)
		if d < best_d:
			best_d = d
			best = closest
	return best


## The corrective push for one body of an overlapping pair, matching
## memory_match's `_resolve_separation`: half the penetration along the axis
## from `from_pos` toward `to_pos`. Add the result to `to_pos` and subtract it
## from `from_pos` to separate them. Returns `Vector2.ZERO` when the bodies are
## at least `min_gap` apart (no overlap). A pair sharing the exact same point
## separates along +x (the degenerate-axis fallback), never NaN.
static func separation_push(from_pos: Vector2, to_pos: Vector2, min_gap: float) -> Vector2:
	var apart := to_pos - from_pos
	var dist := apart.length()
	if dist >= min_gap:
		return Vector2.ZERO
	var axis := apart.normalized() if dist > 0.001 else Vector2.RIGHT
	return axis * (min_gap - dist) * 0.5
