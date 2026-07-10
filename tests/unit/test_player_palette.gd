extends GutTest
## Player palette (#581): chosen-color overrides funnel through color_for_slot()
## so every call site reflects lobby picks, plus the pure uniqueness rule the
## server uses to keep colours distinct.

var _saved_colorblind := false


func before_each() -> void:
	_saved_colorblind = PlayerPalette.use_colorblind
	PlayerPalette.use_colorblind = false


func after_each() -> void:
	# Static state — restore between tests so nothing leaks.
	PlayerPalette.clear_overrides()
	PlayerPalette.clear_team_assignments()
	PlayerPalette.use_colorblind = _saved_colorblind


func test_default_color_is_the_slot_default() -> void:
	assert_eq(PlayerPalette.color_for_slot(0), PlayerPalette.COLORS[0])
	assert_eq(PlayerPalette.color_for_slot(3), PlayerPalette.COLORS[3])


func test_override_recolors_a_slot_by_index() -> void:
	PlayerPalette.set_overrides({0: 5})
	assert_eq(
		PlayerPalette.color_for_slot(0), PlayerPalette.COLORS[5], "slot 0 now shows P6's color"
	)
	assert_eq(PlayerPalette.color_for_slot(1), PlayerPalette.COLORS[1], "unset slot keeps default")


func test_clear_overrides_restores_defaults() -> void:
	PlayerPalette.set_overrides({2: 7})
	PlayerPalette.clear_overrides()
	assert_eq(PlayerPalette.color_for_slot(2), PlayerPalette.COLORS[2])


func test_override_index_follows_the_colorblind_toggle() -> void:
	# A pick is an index, not a Color — index N means the Nth swatch of whatever
	# set is active, so it survives the colorblind switch.
	PlayerPalette.set_overrides({0: 4})
	PlayerPalette.use_colorblind = true
	assert_eq(PlayerPalette.color_for_slot(0), PlayerPalette.COLORS_COLORBLIND[4])


func test_effective_index_is_pick_or_slot_default() -> void:
	assert_eq(PlayerPalette.effective_index(3, -1), 3, "no pick -> slot default")
	assert_eq(PlayerPalette.effective_index(3, 9), 9, "a pick wins")
	# Wraps at the palette size for the default of a high slot.
	assert_eq(PlayerPalette.effective_index(12, -1), 0, "slot 12 defaults to P1's index")


func test_is_index_free_rejects_taken_and_out_of_range() -> void:
	# Slot 1 has no pick, so it effectively shows index 1; slot 5 picked index 3.
	var others := [[1, -1], [5, 3]]
	assert_true(PlayerPalette.is_index_free(0, others), "0 is nobody's colour")
	assert_false(PlayerPalette.is_index_free(1, others), "1 is slot 1's default colour")
	assert_false(PlayerPalette.is_index_free(3, others), "3 is slot 5's chosen colour")
	assert_false(PlayerPalette.is_index_free(-1, others), "negative is not a real index")
	assert_false(
		PlayerPalette.is_index_free(PlayerPalette.COLORS.size(), others), "past the palette end"
	)


# --- Team colors (#820) ------------------------------------------------------


func test_team_assignment_colors_every_member_by_team() -> void:
	# Two teams: slots 0/2 vs 1/3. Each member reads its team color, not its pick.
	PlayerPalette.set_team_assignments([[0, 2], [1, 3]])
	assert_eq(PlayerPalette.color_for_slot(0), PlayerPalette.TEAM_COLORS[0], "team 0 member")
	assert_eq(PlayerPalette.color_for_slot(2), PlayerPalette.TEAM_COLORS[0], "team 0 member")
	assert_eq(PlayerPalette.color_for_slot(1), PlayerPalette.TEAM_COLORS[1], "team 1 member")
	assert_eq(PlayerPalette.color_for_slot(3), PlayerPalette.TEAM_COLORS[1], "team 1 member")


func test_team_color_overrides_a_personal_pick() -> void:
	# Slot 0 picked P6's color, but during a team round its team wins.
	PlayerPalette.set_overrides({0: 5})
	PlayerPalette.set_team_assignments([[0], [1]])
	assert_eq(
		PlayerPalette.color_for_slot(0),
		PlayerPalette.TEAM_COLORS[0],
		"team color takes precedence over the #581 pick",
	)


func test_slots_outside_any_team_keep_their_personal_color() -> void:
	# A spectator/unassigned slot during a team round is untouched.
	PlayerPalette.set_team_assignments([[0], [1]])
	assert_eq(PlayerPalette.color_for_slot(4), PlayerPalette.COLORS[4], "slot 4 is on no team")


func test_clear_team_assignments_restores_personal_identity() -> void:
	PlayerPalette.set_overrides({0: 5})
	PlayerPalette.set_team_assignments([[0], [1]])
	PlayerPalette.clear_team_assignments()
	assert_false(PlayerPalette.has_team_assignments(), "no team round in force")
	assert_eq(PlayerPalette.color_for_slot(0), PlayerPalette.COLORS[5], "the #581 pick is back")
	assert_eq(PlayerPalette.color_for_slot(1), PlayerPalette.COLORS[1], "slot default is back")


func test_team_colors_follow_the_colorblind_toggle() -> void:
	PlayerPalette.set_team_assignments([[0], [1]])
	PlayerPalette.use_colorblind = true
	assert_eq(
		PlayerPalette.color_for_slot(1),
		PlayerPalette.TEAM_COLORS_COLORBLIND[1],
		"the colorblind team set is served when the toggle is on",
	)


func test_team_index_wraps_past_the_team_palette_size() -> void:
	# More teams than colors (defensive): the 5th team reuses the 1st color.
	var teams := []
	for i in PlayerPalette.TEAM_COLORS.size() + 1:
		teams.append([i])
	PlayerPalette.set_team_assignments(teams)
	var wrapped := PlayerPalette.TEAM_COLORS.size()  # the one-past team
	assert_eq(
		PlayerPalette.color_for_slot(wrapped),
		PlayerPalette.TEAM_COLORS[0],
		"team indices wrap like the personal palette does",
	)
