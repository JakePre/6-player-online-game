extends GutTest
## Controller emote wheel (#608 part 3): the ring builds a slot per emote, opens
## with nothing aimed, and maps a stick direction to the nearest slot (below a
## deadzone = cancel).

var radial: EmoteRadial


func before_each() -> void:
	radial = EmoteRadial.new()
	add_child_autofree(radial)


func test_builds_a_slot_per_emote() -> void:
	assert_eq(radial._slots.size(), Emotes.EMOTES.size(), "one ring slot per emote")


func test_starts_closed() -> void:
	assert_false(radial.is_open())


func test_open_arms_with_nothing_selected_then_close() -> void:
	radial.open()
	assert_true(radial.is_open())
	assert_eq(radial.selected_index(), -1, "opens un-aimed so an instant release cancels")
	radial.close()
	assert_false(radial.is_open())


func test_aim_up_selects_the_top_slot() -> void:
	radial.aim(Vector2(0, -1))  # up in screen space (-Y)
	assert_eq(radial.selected_index(), 0, "slot 0 sits at 12 o'clock")


func test_aim_clockwise_selects_the_next_slot() -> void:
	# One slot clockwise of the top for 6 slots is at angle -PI/2 + TAU/6.
	var angle := -PI / 2.0 + TAU / Emotes.EMOTES.size()
	radial.aim(Vector2(cos(angle), sin(angle)))
	assert_eq(radial.selected_index(), 1)


func test_aim_below_deadzone_selects_nothing() -> void:
	radial.aim(Vector2(0, -1))
	assert_eq(radial.selected_index(), 0)
	radial.aim(Vector2(0.1, 0.05))  # inside the deadzone
	assert_eq(radial.selected_index(), -1, "a resting stick aims at nothing")
