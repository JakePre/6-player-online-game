extends GutTest
## Playtest mode's pick panel (#1070): renders purely from the PICK snapshot —
## the host gets one button per eligible game plus End match; everyone else
## gets a waiting title and the same history.

var panel: PlaytestPickPanel


func before_each() -> void:
	MinigameCatalog.register_builtins()
	panel = PlaytestPickPanel.new()
	add_child_autofree(panel)


func test_host_gets_a_button_per_eligible_game_and_the_end_button() -> void:
	panel.render({"eligible": ["basket_brawl", "thin_ice"], "played": []}, true)
	assert_eq(panel._grid.get_child_count(), 2, "one button per eligible game")
	var first := panel._grid.get_child(0) as Button
	assert_eq(
		first.text,
		MinigameCatalog.meta_of(&"basket_brawl").display_name,
		"buttons wear display names, not ids",
	)
	assert_true(panel._end_button.visible, "the host can end the match")
	assert_eq(panel._title.text, "Pick the next game")


func test_spectators_get_no_buttons() -> void:
	panel.render({"eligible": ["basket_brawl"], "played": []}, false)
	assert_eq(panel._grid.get_child_count(), 0, "only the host picks")
	assert_false(panel._end_button.visible, "only the host ends")
	assert_eq(panel._title.text, "Host is picking the next game...")


func test_history_lists_played_games_in_order() -> void:
	panel.render({"eligible": [], "played": ["thin_ice", "basket_brawl"]}, false)
	var text: String = panel._history.text
	assert_string_contains(text, "1. %s" % MinigameCatalog.meta_of(&"thin_ice").display_name)
	assert_string_contains(text, "2. %s" % MinigameCatalog.meta_of(&"basket_brawl").display_name)
	panel.render({"eligible": [], "played": []}, false)
	assert_eq(panel._history.text, "Nothing yet.")


func test_button_press_emits_the_pick() -> void:
	panel.render({"eligible": ["basket_brawl"], "played": []}, true)
	watch_signals(panel)
	(panel._grid.get_child(0) as Button).pressed.emit()
	assert_signal_emitted_with_parameters(panel, "pick_chosen", ["basket_brawl"])
	panel._end_button.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "pick_chosen", ["end"])
