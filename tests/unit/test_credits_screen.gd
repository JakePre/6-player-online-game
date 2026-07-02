extends GutTest
## Credits screen (M7-04): renders parsed ledger rows and falls back
## gracefully when the ledger is missing.

var screen: Control


func before_each() -> void:
	var scene: PackedScene = load("res://src/client/screens/credits_screen.tscn")
	screen = scene.instantiate()
	add_child_autofree(screen)


func _labels() -> Array:
	return screen.get_node("%CreditsList").get_children().filter(
		func(child: Node) -> bool: return not child.is_queued_for_deletion()
	)


func test_ready_populates_from_bundled_ledger() -> void:
	assert_gt(_labels().size(), 0)


func test_populate_renders_title_and_detail_rows() -> void:
	(
		screen
		. populate(
			[
				{
					"asset": "Pack One",
					"author": "Alice",
					"license": "CC0 1.0",
					"source": "https://example.com",
				},
				{"tool": "GUT", "license": "MIT"},
			]
		)
	)
	var labels := _labels()
	assert_eq(labels.size(), 4, "two entries, each a title + details line")
	assert_eq(labels[0].text, "Pack One")
	assert_string_contains(labels[1].text, "by Alice")
	assert_string_contains(labels[1].text, "CC0 1.0")
	assert_eq(labels[2].text, "GUT")
	assert_string_contains(labels[3].text, "MIT")


func test_empty_rows_show_fallback_line() -> void:
	screen.populate([])
	var labels := _labels()
	assert_eq(labels.size(), 1)
	assert_string_contains(labels[0].text, "assets/CREDITS.md")


func test_back_button_navigates_to_main_menu() -> void:
	watch_signals(screen)
	screen.get_node("%BackButton").pressed.emit()
	assert_signal_emitted_with_parameters(screen, "navigate", [&"main_menu"])
