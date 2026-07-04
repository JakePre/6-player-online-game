class_name LaneLayout
extends RefCounted
## Many-player line-up helper (M15-07, ADR 003 F7). The games that line
## players up — duel rows, firing lines, tug files, stacked 2D lanes — were
## laid out for a single row of ~6; at 12-24 that row overflows the arena and
## camera. This wraps a line-up into balanced rows/files and fits stacked 2D
## lanes to the viewport. Pure geometry like SpawnLayout (M15-05): no scene,
## no state, safe from sims and views alike.

## A single row stays readable up to this many; more wraps into extra rows.
const MAX_PER_ROW := 8


## `count` line-up offsets in slot order for a row formation. x = lateral
## offset centered on 0; y = 0 for the front row, +row_gap per row further
## back (the caller maps y onto its own depth axis). Rows fill front-first
## and balanced (never a lone straggler in the back), and odd rows shift
## half a pitch so back rows peek between front-row shoulders.
static func row_positions(
	count: int, pitch: float, row_gap: float, max_per_row: int = MAX_PER_ROW
) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count <= 0:
		return positions
	var rows := row_count(count, max_per_row)
	var per_row := _balanced(count, rows)
	for row in rows:
		var on_row: int = per_row[row]
		var stagger := 0.0 if row % 2 == 0 else pitch * 0.5
		for j in on_row:
			var x := (j - (on_row - 1) / 2.0) * pitch + stagger
			positions.append(Vector2(x, row * row_gap))
	return positions


## How many rows a line-up of `count` needs.
static func row_count(count: int, max_per_row: int = MAX_PER_ROW) -> int:
	return maxi(1, ceili(float(count) / maxi(1, max_per_row)))


## Tug-style file: offsets march away from an anchor along +x (pitch apart)
## and spill into parallel files offset by +y * file_gap once a file holds
## max_per_file. Files fill front-first and balanced; the caller mirrors or
## rotates the axes onto its own geometry.
static func file_positions(
	count: int, pitch: float, file_gap: float, max_per_file: int = 6
) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count <= 0:
		return positions
	var files := maxi(1, ceili(float(count) / maxi(1, max_per_file)))
	var per_file := _balanced(count, files)
	for file in files:
		for j in per_file[file]:
			positions.append(Vector2(j * pitch, file * file_gap))
	return positions


## Stacked-2D-lane fit: the multiplier that fits `count` lanes of
## `base_pitch` px into `max_total` px. 1.0 when they already fit (small
## lobbies render exactly as before); floored at min_scale so lanes never
## collapse into unreadable slivers.
static func fitted_scale(
	count: int, base_pitch: float, max_total: float, min_scale: float = 0.25
) -> float:
	if count <= 0 or base_pitch <= 0.0:
		return 1.0
	return clampf(max_total / (base_pitch * count), min_scale, 1.0)


## Splits `count` across `groups` with front groups at most one larger —
## balanced rows read as a formation, not a full row plus a straggler.
static func _balanced(count: int, groups: int) -> Array[int]:
	@warning_ignore("integer_division")
	var base := count / groups
	var remainder := count % groups
	var per_group: Array[int] = []
	for group in groups:
		per_group.append(base + (1 if group < remainder else 0))
	return per_group
