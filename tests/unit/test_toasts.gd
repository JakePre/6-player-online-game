extends GutTest
## Toast layer (M6-03): messages stack, never grab the mouse, and expire.

var toasts: Control


func before_each() -> void:
	toasts = (load("res://src/client/toasts.tscn") as PackedScene).instantiate()
	add_child_autofree(toasts)


func test_show_toast_stacks_messages() -> void:
	toasts.show_toast("first")
	toasts.show_toast("second")
	assert_eq(toasts.toast_count(), 2)


func test_toast_displays_its_text() -> void:
	toasts.show_toast("That room is full.")
	var label: Label = toasts.get_node("%Stack").get_child(0).get_child(0)
	assert_eq(label.text, "That room is full.")


func test_toasts_never_block_input() -> void:
	toasts.show_toast("hello")
	assert_eq(toasts.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(toasts.get_node("%Stack").get_child(0).mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_toast_expires_after_its_duration() -> void:
	toasts.show_toast("gone soon", 0.05)
	assert_eq(toasts.toast_count(), 1)
	await get_tree().create_timer(0.3).timeout
	assert_eq(toasts.toast_count(), 0)


## M16-10: toasts are always refusal/disconnect notices — the DANGER accent.
func test_toast_uses_the_danger_accent() -> void:
	toasts.show_toast("Connection to the server was lost.")
	var card: PanelContainer = toasts.get_node("%Stack").get_child(0)
	assert_eq(card.theme_type_variation, &"CardPanel")
	var label: Label = card.get_child(0)
	assert_eq(label.get_theme_color(&"font_color"), PartyTheme.DANGER)


func test_join_failure_text_covers_every_result() -> void:
	for result: int in NetConfig.JoinResult.values():
		if result == NetConfig.JoinResult.OK:
			continue
		assert_true(
			JoinFailureText.TEXT.has(result),
			"Missing message for %s" % NetConfig.join_result_name(result)
		)
	assert_eq(JoinFailureText.describe(NetConfig.JoinResult.FULL), "That room is full.")
