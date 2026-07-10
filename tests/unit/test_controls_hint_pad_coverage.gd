extends GutTest
## Regression guard (M17-05, #651): every registered minigame's `controls`
## hint (the intro-card text) names a gamepad binding alongside the keyboard
## one, so a pad-only player never has to guess. Catches a game shipping a
## keyboard-only description — this test found three real gaps (Tug of War,
## Turbo Lap, Shred Session) that were fixed alongside adding it.
##
## Text-based, not exhaustive device-aware parsing (that's InputGlyphs/#608's
## job for live UI) — this only guards that *some* pad-indicating term is
## present, matching the terse "WASD / left stick" style used everywhere.

## Case-insensitive terms that count as "names a pad binding," covering the
## house style (icon glyphs, "pad", "stick", "d-pad") seen across every game.
const PAD_TERMS := ["pad", "stick", "d-pad", "Ⓐ", "Ⓑ", "Ⓧ", "Ⓨ"]


func _mentions_a_pad(text: String) -> bool:
	var lower := text.to_lower()
	for term in PAD_TERMS:
		if term.to_lower() in lower:
			return true
	return false


func test_every_registered_games_controls_hint_names_a_pad_binding() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	var checked := 0
	for id: StringName in MinigameCatalog.registered_ids():
		var meta := MinigameCatalog.meta_of(id)
		if meta.controls_text.is_empty():
			continue  # a missing hint entirely is a separate, pre-existing concern
		checked += 1
		assert_true(
			_mentions_a_pad(meta.controls_text),
			"%s's controls hint names a pad binding: %s" % [id, meta.controls_text]
		)
	assert_gt(checked, 30, "sanity: the sweep actually ran across the full roster")
	MinigameCatalog.clear()


## The finale isn't in the catalog (it mounts separately, #554) but is just as
## player-facing, so it gets the same guard.
func test_gauntlet_finale_controls_hint_names_a_pad_binding() -> void:
	var meta := Gauntlet.make_meta()
	assert_false(meta.controls_text.is_empty())
	assert_true(_mentions_a_pad(meta.controls_text))


## Structured control specs (#832): every row that names an input must resolve
## to a non-empty binding on BOTH devices — a pad-only player never meets an
## unanswerable chip — and each spec keeps at least one pad-answerable row.
## Games without a spec stay covered by the text guard above until the #844
## fan-out converts them.
func test_every_control_spec_row_resolves_on_both_devices() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	var prior_device := InputGlyphs.active_device
	var specs_checked := 0
	for id: StringName in MinigameCatalog.registered_ids():
		var meta := MinigameCatalog.meta_of(id)
		if meta.control_spec.is_empty():
			continue
		specs_checked += 1
		var pad_answerable := 0
		for row: Dictionary in meta.control_spec:
			var input := StringName(String(row.get("input", "")))
			if String(input).is_empty():
				continue  # note-only rows carry no binding by design
			InputGlyphs.active_device = InputGlyphs.Device.KEYBOARD
			assert_false(
				InputGlyphs.binding_label(input).is_empty(),
				"%s: '%s' resolves on keyboard" % [id, row.get("verb", input)]
			)
			InputGlyphs.active_device = InputGlyphs.Device.GAMEPAD
			var pad_label := InputGlyphs.binding_label(input)
			if not pad_label.is_empty():
				pad_answerable += 1
		assert_gt(pad_answerable, 0, "%s keeps >=1 pad-answerable row" % id)
	InputGlyphs.active_device = prior_device
	assert_gt(specs_checked, 2, "sanity: the template conversions are registered")
	MinigameCatalog.clear()
