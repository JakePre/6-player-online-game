extends GutTest
## Connection status indicator (M16-10): offline/connecting/online text and
## the SUCCESS/DANGER/default semantic coloring that goes with each state.

var status: PanelContainer


func before_each() -> void:
	status = (load("res://src/client/connection_status.tscn") as PackedScene).instantiate()
	add_child_autofree(status)


func test_offline_by_default_and_colored_as_danger() -> void:
	status._process(0.0)
	var label: Label = status.get_node("Label")
	assert_eq(label.text, "Offline")
	assert_eq(label.get_theme_color(&"font_color"), PartyTheme.DANGER)


func test_status_uses_a_card_panel() -> void:
	assert_eq(status.theme_type_variation, &"CardPanel")
