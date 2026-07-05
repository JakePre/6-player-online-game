extends GutTest
## The design system (M16-01, grown from M6-04): the builder produces the
## fonts, type variations, palette, and depth every screen inherits from the
## app shell, and every registered minigame ships a control hint for the
## intro card.


func test_build_produces_styled_controls() -> void:
	var theme := PartyTheme.build()
	assert_eq(theme.default_font_size, PartyTheme.FONT_SIZE)
	assert_true(theme.has_stylebox(&"panel", &"PanelContainer"))
	assert_true(theme.has_stylebox(&"normal", &"Button"))
	assert_true(theme.has_stylebox(&"hover", &"Button"))
	assert_true(theme.has_stylebox(&"normal", &"LineEdit"))
	assert_eq(theme.get_color(&"font_color", &"Label"), PartyTheme.TEXT)


func test_typography_is_the_two_face_system() -> void:
	var theme := PartyTheme.build()
	assert_not_null(theme.default_font, "body font is the theme default")
	assert_eq((theme.default_font as FontVariation).base_font, PartyTheme.FONT_BODY)
	assert_eq(theme.get_font(&"font", &"Button"), PartyTheme.FONT_DISPLAY, "buttons speak display")
	for variation: StringName in [
		PartyTheme.DISPLAY_VARIATION, PartyTheme.TITLE_VARIATION, PartyTheme.HEADER_VARIATION
	]:
		assert_eq(theme.get_type_variation_base(variation), &"Label")
		assert_eq(theme.get_font(&"font", variation), PartyTheme.FONT_DISPLAY)
	assert_gt(
		theme.get_font_size(&"font_size", PartyTheme.DISPLAY_VARIATION),
		theme.get_font_size(&"font_size", PartyTheme.TITLE_VARIATION),
		"the type scale descends"
	)


func test_depth_panels_cast_shadows_and_pressed_buttons_sink() -> void:
	var theme := PartyTheme.build()
	var panel: StyleBoxFlat = theme.get_stylebox(&"panel", &"PanelContainer")
	assert_gt(panel.shadow_size, 0, "panels float")
	var card: StyleBoxFlat = theme.get_stylebox(&"panel", PartyTheme.CARD_VARIATION)
	assert_eq(card.bg_color, PartyTheme.BG_RAISED, "cards sit above panels")
	var hover: StyleBoxFlat = theme.get_stylebox(&"hover", &"Button")
	assert_gt(hover.shadow_size, 0, "hover glows")
	var pressed: StyleBoxFlat = theme.get_stylebox(&"pressed", &"Button")
	assert_eq(pressed.shadow_size, 0, "pressed sinks flat")


func test_motion_tempo_and_scales_ascend() -> void:
	assert_lt(PartyTheme.DUR_FAST, PartyTheme.DUR_MED)
	assert_lt(PartyTheme.DUR_MED, PartyTheme.DUR_SLOW)
	assert_lt(PartyTheme.SPACE_XS, PartyTheme.SPACE_SM)
	assert_lt(PartyTheme.SPACE_SM, PartyTheme.SPACE_MD)
	assert_lt(PartyTheme.SPACE_MD, PartyTheme.SPACE_LG)
	assert_lt(PartyTheme.SPACE_LG, PartyTheme.SPACE_XL)
	assert_lt(PartyTheme.RADIUS_SM, PartyTheme.RADIUS_MD)
	assert_lt(PartyTheme.RADIUS_MD, PartyTheme.RADIUS_LG)


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
