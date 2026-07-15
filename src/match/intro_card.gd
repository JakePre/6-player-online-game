class_name IntroCard
extends RefCounted
## Intro-card presentation for MatchScreen (#943): populates the round-intro
## panel — key art, title/category/rules, device-aware control hints (#608) or
## structured control-spec chips (#832), and the mutator banner.
##
## MatchScreen composes one of these (passing the intro-panel child nodes) and
## keeps ownership of panel visibility, the skip-vote flow, the top HUD, and
## event routing. This owns only the card's *content* and its live re-render on
## a device switch / rebind. The nodes stay in the match scene; this drives
## them and builds the chip container as a sibling of the controls label.

## Key art (M16-07): the styled text fallback shows until `<id>.png` lands here.
const KEY_ART_DIR := "res://assets/generated/keyart/"

var _key_art: TextureRect
var _title: Label
var _category: Label
var _rules: Label
var _controls: Label
var _mutator: Label
## The structured-chip container, built next to the legacy controls label.
var _chips: VBoxContainer

## Device-aware hint segments (#608) and the plain-prose fallback for the
## current card, kept so a live device change can re-render without the event.
var _hint_segments: Array = []
var _controls_fallback := ""
## Structured control rows (#832): rows win over hint segments, which win over
## the prose fallback.
var _spec_rows: Array = []


func _init(
	key_art: TextureRect,
	title: Label,
	category: Label,
	rules: Label,
	controls: Label,
	mutator: Label
) -> void:
	_key_art = key_art
	_title = title
	_category = category
	_rules = rules
	_controls = controls
	_mutator = mutator
	_build_chips()


## Fills the card for a round's minigame + rolled mutator (empty = no mutator).
## MatchScreen calls this from a round_intro event, after setting the HUD.
func populate(minigame: Dictionary, mutator: Dictionary) -> void:
	_title.text = minigame.name
	_apply_key_art(String(minigame.id))
	_category.text = MatchFormat.category_name(int(minigame.category))
	_rules.text = minigame.rules
	# Control hints (M6-04); older servers may not send the key yet. When the
	# local catalog has device-aware hints (#608) they win over the prose.
	_controls_fallback = String(minigame.get("controls", ""))
	_hint_segments = _control_hints_for(String(minigame.id))
	_spec_rows = _control_spec_for(String(minigame.id))
	refresh_controls()
	# Mutator announcement (M9-03) — no hidden modifiers.
	_mutator.visible = not mutator.is_empty()
	if not mutator.is_empty():
		_mutator.text = "MUTATOR — %s: %s" % [mutator.name, mutator.blurb]


## Re-renders the controls for the active device — MatchScreen calls this on a
## device change and rebind (#832). Structured rows render as verb + key-pill
## chips; device-aware segments are the legacy one-line form; the plain-prose
## fallback shows when a game declares neither.
func refresh_controls() -> void:
	if not _spec_rows.is_empty():
		_render_control_chips()
		_controls.visible = false
		_chips.visible = true
		return
	if _chips != null:
		_chips.visible = false
	var text := (
		InputGlyphs.hint_for(_hint_segments)
		if not _hint_segments.is_empty()
		else _controls_fallback
	)
	_controls.text = text
	_controls.visible = not text.is_empty()


func _apply_key_art(id: String) -> void:
	var path := KEY_ART_DIR + id + ".png"
	if not id.is_empty() and ResourceLoader.exists(path):
		_key_art.texture = load(path)
		_key_art.visible = true
	else:
		_key_art.texture = null
		_key_art.visible = false


## The local catalog's device-aware hint segments for this game, or [] to fall
## back to the server-sent prose. The client already registers the catalog
## (net_manager), so this needs no protocol change.
func _control_hints_for(id: String) -> Array:
	if not MinigameCatalog.is_registered(StringName(id)):
		return []
	return MinigameCatalog.meta_of(StringName(id)).control_hints


## The local catalog's structured control rows (#832), or [] to fall back to
## hint segments / prose. Client-derived like _control_hints_for.
func _control_spec_for(id: String) -> Array:
	if not MinigameCatalog.is_registered(StringName(id)):
		return []
	return MinigameCatalog.meta_of(StringName(id)).control_spec


## The chip rows live in the intro column right where the legacy label sits, so
## games with a structured spec show chips and everything else keeps the
## one-line hint — batches of the #844 fan-out are zero-risk per game.
func _build_chips() -> void:
	_chips = VBoxContainer.new()
	_chips.name = "IntroControlChips"
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.add_theme_constant_override(&"separation", PartyTheme.SPACE_XS)
	_chips.visible = false
	var column := _controls.get_parent()
	column.add_child(_chips)
	column.move_child(_chips, _controls.get_index())


func _render_control_chips() -> void:
	# Remove synchronously (not just queue_free) so a same-frame re-render —
	# device swap or rebind — never shows stale chips next to fresh ones.
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	for row: Dictionary in _spec_rows:
		_chips.add_child(_control_chip_row(row))


func _control_chip_row(row: Dictionary) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_theme_constant_override(&"separation", PartyTheme.SPACE_SM)
	var verb := String(row.get("verb", ""))
	if not verb.is_empty():
		var verb_label := Label.new()
		verb_label.name = "Verb"
		verb_label.text = verb
		chip.add_child(verb_label)
	var input := StringName(String(row.get("input", "")))
	if not String(input).is_empty():
		var modifier := String(row.get("modifier", "hold" if row.get("hold", false) else ""))
		if not modifier.is_empty():
			var modifier_label := Label.new()
			modifier_label.text = modifier
			modifier_label.theme_type_variation = PartyTheme.DIM_VARIATION
			chip.add_child(modifier_label)
		var pill := Label.new()
		pill.name = "Binding"
		pill.text = InputGlyphs.binding_label(input)
		pill.add_theme_stylebox_override(&"normal", PartyTheme.key_pill())
		chip.add_child(pill)
		var alt := String(row.get("alt", ""))
		if not alt.is_empty() and InputGlyphs.active_device == InputGlyphs.Device.KEYBOARD:
			var alt_label := Label.new()
			alt_label.text = alt
			alt_label.theme_type_variation = PartyTheme.DIM_VARIATION
			chip.add_child(alt_label)
	var note := String(row.get("note", ""))
	if not note.is_empty():
		var note_label := Label.new()
		note_label.name = "Note"
		note_label.text = note
		note_label.theme_type_variation = PartyTheme.DIM_VARIATION
		chip.add_child(note_label)
	return chip
