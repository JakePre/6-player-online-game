extends GutTest
## Button motion helper (M16-03): wires hover/press scale motion onto a button,
## and — the accessibility contract — wires nothing at all under reduced motion.

var _saved_reduced := false


func before_each() -> void:
	_saved_reduced = ArenaFX.reduced_motion


func after_each() -> void:
	ArenaFX.reduced_motion = _saved_reduced


func _button() -> Button:
	var button := Button.new()
	button.size = Vector2(200, 44)
	add_child_autofree(button)
	return button


func test_attaches_hover_and_press_motion() -> void:
	ArenaFX.reduced_motion = false
	var button := _button()
	ButtonMotion.attach(button)
	assert_false(button.mouse_entered.get_connections().is_empty(), "hover is wired")
	assert_false(button.button_down.get_connections().is_empty(), "press is wired")
	assert_eq(button.pivot_offset, button.size / 2.0, "pivot is centred so the pop is symmetric")


func test_reduced_motion_wires_nothing() -> void:
	ArenaFX.reduced_motion = true
	var button := _button()
	ButtonMotion.attach(button)
	assert_true(button.mouse_entered.get_connections().is_empty(), "no hover motion")
	assert_true(button.button_down.get_connections().is_empty(), "no press motion")


func test_hover_scales_the_button() -> void:
	ArenaFX.reduced_motion = false
	var button := _button()
	ButtonMotion.attach(button)
	button.mouse_entered.emit()
	# The tween starts immediately; let it run its DUR_FAST, then check the pop.
	await get_tree().create_timer(PartyTheme.DUR_FAST + 0.05).timeout
	assert_almost_eq(button.scale.x, ButtonMotion.HOVER_SCALE, 0.01, "hover grows the button")
