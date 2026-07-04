extends GutTest
## Many-player line-up helper (M15-07, ADR 003 F7): row wrapping, tug files,
## and 2D lane fitting. Small counts must reproduce the classic single-row
## layouts exactly — the 2-6 player experience is untouched (ADR non-goal).


func test_row_positions_returns_one_position_per_player() -> void:
	for count in [0, 1, 6, 8, 9, 24]:
		assert_eq(
			LaneLayout.row_positions(count, 2.0, 1.5).size(),
			maxi(count, 0),
			"%d players -> %d positions" % [count, count]
		)


## Up to MAX_PER_ROW the helper reproduces the legacy centered single row —
## the exact `(i - (n-1)/2) * pitch` every line-up view used before M15-07.
func test_small_counts_keep_the_classic_single_row() -> void:
	var positions := LaneLayout.row_positions(6, 2.0, 1.5)
	for i in 6:
		assert_almost_eq(positions[i].x, (i - 2.5) * 2.0, 0.001, "legacy lateral spot %d" % i)
		assert_almost_eq(positions[i].y, 0.0, 0.001, "single row sits at depth 0")


func test_crowds_wrap_into_balanced_rows() -> void:
	assert_eq(LaneLayout.row_count(8), 1)
	assert_eq(LaneLayout.row_count(9), 2)
	assert_eq(LaneLayout.row_count(24), 3)
	var positions := LaneLayout.row_positions(24, 2.0, 1.5)
	var rows := {}
	for position in positions:
		rows[position.y] = int(rows.get(position.y, 0)) + 1
	assert_eq(rows.size(), 3, "24 players stand in three ranks")
	for count: int in rows.values():
		assert_eq(count, 8, "ranks are balanced, no stragglers")


func test_rows_stay_within_the_single_row_footprint() -> void:
	var pitch := 2.0
	# Widest possible row: MAX_PER_ROW at full pitch plus the half-pitch
	# stagger on odd rows.
	var limit := (LaneLayout.MAX_PER_ROW - 1) / 2.0 * pitch + pitch * 0.5 + 0.001
	for position in LaneLayout.row_positions(24, pitch, 1.5):
		assert_lte(absf(position.x), limit, "no rank overflows the front row's width")


func test_file_positions_march_then_spill_into_parallel_files() -> void:
	# Six or fewer: one file marching along +x, exactly the legacy spacing.
	var single := LaneLayout.file_positions(4, 1.4, 1.2)
	for i in 4:
		assert_almost_eq(single[i].x, i * 1.4, 0.001)
		assert_almost_eq(single[i].y, 0.0, 0.001, "small teams keep the classic single file")
	# Twelve: two balanced files of six, the second offset one file_gap out.
	var crowd := LaneLayout.file_positions(12, 1.4, 1.2)
	assert_eq(crowd.size(), 12)
	var files := {}
	for position in crowd:
		files[position.y] = int(files.get(position.y, 0)) + 1
	assert_eq(files.size(), 2, "a 12-puller team splits into two files")
	for count: int in files.values():
		assert_eq(count, 6, "files are balanced")
	var longest := 0.0
	for position in crowd:
		longest = maxf(longest, position.x)
	assert_almost_eq(longest, 5.0 * 1.4, 0.001, "no file marches past six pullers' length")


func test_fitted_scale_only_shrinks_when_lanes_overflow() -> void:
	assert_almost_eq(LaneLayout.fitted_scale(6, 66.0, 600.0), 1.0, 0.001, "6 lanes already fit")
	var crowded := LaneLayout.fitted_scale(24, 66.0, 600.0)
	assert_almost_eq(crowded, 600.0 / (66.0 * 24.0), 0.001, "24 lanes shrink to fit")
	assert_almost_eq(
		LaneLayout.fitted_scale(100, 66.0, 600.0), 0.25, 0.001, "the floor keeps lanes readable"
	)
	assert_almost_eq(LaneLayout.fitted_scale(0, 66.0, 600.0), 1.0, 0.001, "empty draw is a no-op")
