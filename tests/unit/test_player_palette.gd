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
