extends GutTest
## Shared UI theme (M6-04): the builder produces the palette every screen
## inherits from the app shell, and every registered minigame ships a control
## hint for the intro card.


func test_build_produces_styled_controls() -> void:
	var theme := PartyTheme.build()
	assert_eq(theme.default_font_size, PartyTheme.FONT_SIZE)
	assert_true(theme.has_stylebox(&"panel", &"PanelContainer"))
	assert_true(theme.has_stylebox(&"normal", &"Button"))
	assert_true(theme.has_stylebox(&"hover", &"Button"))
	assert_true(theme.has_stylebox(&"normal", &"LineEdit"))
	assert_eq(theme.get_color(&"font_color", &"Label"), PartyTheme.TEXT)


func test_hint_variation_is_an_accented_label() -> void:
	var theme := PartyTheme.build()
	assert_eq(theme.get_type_variation_base(PartyTheme.HINT_VARIATION), &"Label")
	assert_eq(theme.get_color(&"font_color", PartyTheme.HINT_VARIATION), PartyTheme.ACCENT)


func test_panel_style_matches_arena_palette() -> void:
	var theme := PartyTheme.build()
	var panel: StyleBoxFlat = theme.get_stylebox(&"panel", &"PanelContainer")
	assert_eq(panel.bg_color, PartyTheme.BG_DARK)
	assert_eq(panel.border_color, PartyTheme.BORDER)


func test_every_registered_minigame_has_control_hints() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	for id: StringName in MinigameCatalog.registered_ids():
		var meta := MinigameCatalog.meta_of(id)
		assert_false(meta.controls_text.is_empty(), "%s is missing a controls hint" % id)
		assert_eq(meta.to_dict().controls, meta.controls_text)


func test_gauntlet_finale_has_control_hints() -> void:
	assert_false(Gauntlet.make_meta().controls_text.is_empty())


func test_meta_roundtrips_controls() -> void:
	var meta := MinigameMeta.create({"id": &"x", "controls": "Move — WASD"})
	assert_eq(meta.controls_text, "Move — WASD")
	assert_eq(meta.to_dict().controls, "Move — WASD")
	var without := MinigameMeta.create({"id": &"y"})
	assert_eq(without.controls_text, "", "controls stay optional")
