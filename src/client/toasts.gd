class_name Toasts
extends Control
## Transient notification toasts (M6-03): short-lived messages stacked in the
## bottom-right corner for errors that need to surface on any screen (join
## refusals outside the menu, match start failures, connection loss). Never
## blocks input; every toast dismisses itself after its duration.

const DEFAULT_DURATION_SEC := 4.0

@onready var _stack: VBoxContainer = %Stack


## Refusal/disconnect notices default to DANGER (M16-10); neutral or good
## news (controller hot-plug, M17-01) passes its own semantic accent.
func show_toast(
	text: String, duration_sec: float = DEFAULT_DURATION_SEC, accent: Color = PartyTheme.DANGER
) -> void:
	var toast := PanelContainer.new()
	toast.theme_type_variation = &"CardPanel"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(280, 0)
	label.add_theme_color_override(&"font_color", accent)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(label)
	_stack.add_child(toast)
	get_tree().create_timer(duration_sec).timeout.connect(
		func() -> void:
			if is_instance_valid(toast):
				toast.queue_free()
	)


func toast_count() -> int:
	return _stack.get_child_count()
