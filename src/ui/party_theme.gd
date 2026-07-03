class_name PartyTheme
extends RefCounted
## Shared UI theme (M6-04): one dark palette + control shapes applied at the
## app shell root so every screen (menu, lobby, match chrome, finale) reads
## as one product. Colors match the arena presentation tier: dark slate
## panels, soft borders, the coin-gold accent.

const BG_DARK := Color(0.13, 0.15, 0.19)
const BG_DARKER := Color(0.09, 0.1, 0.13)
const BORDER := Color(0.35, 0.38, 0.45)
const ACCENT := Color(0.96, 0.79, 0.2)
const TEXT := Color(0.92, 0.93, 0.95)
const TEXT_DIM := Color(0.62, 0.65, 0.72)
const CORNER_RADIUS := 8
const FONT_SIZE := 16

## `HINT_VARIATION` styles the intro card's control hints (and any future
## key-cap style helper text): accent color on the shared dark panel.
const HINT_VARIATION := &"HintLabel"


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	_style_panels(theme)
	_style_buttons(theme)
	_style_inputs(theme)
	_style_labels(theme)
	return theme


static func _flat(bg: Color, border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(CORNER_RADIUS)
	style.set_content_margin_all(10.0)
	if border_color.a > 0.0:
		style.set_border_width_all(2)
		style.border_color = border_color
	return style


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"PanelContainer", _flat(BG_DARK, BORDER))
	theme.set_stylebox(&"panel", &"Panel", _flat(BG_DARKER))


static func _style_buttons(theme: Theme) -> void:
	theme.set_stylebox(&"normal", &"Button", _flat(BG_DARKER, BORDER))
	theme.set_stylebox(&"hover", &"Button", _flat(BG_DARKER.lightened(0.08), ACCENT))
	theme.set_stylebox(&"pressed", &"Button", _flat(BG_DARKER.darkened(0.2), ACCENT))
	theme.set_stylebox(&"focus", &"Button", _flat(Color.TRANSPARENT, ACCENT))
	theme.set_stylebox(&"disabled", &"Button", _flat(BG_DARKER, BORDER.darkened(0.3)))
	theme.set_color(&"font_color", &"Button", TEXT)
	theme.set_color(&"font_hover_color", &"Button", ACCENT)
	theme.set_color(&"font_pressed_color", &"Button", ACCENT)
	theme.set_color(&"font_disabled_color", &"Button", TEXT_DIM)


static func _style_inputs(theme: Theme) -> void:
	theme.set_stylebox(&"normal", &"LineEdit", _flat(BG_DARKER, BORDER))
	theme.set_stylebox(&"focus", &"LineEdit", _flat(BG_DARKER, ACCENT))
	theme.set_color(&"font_color", &"LineEdit", TEXT)
	theme.set_color(&"font_placeholder_color", &"LineEdit", TEXT_DIM)
	theme.set_color(&"caret_color", &"LineEdit", ACCENT)


static func _style_labels(theme: Theme) -> void:
	theme.set_color(&"font_color", &"Label", TEXT)
	theme.set_type_variation(HINT_VARIATION, &"Label")
	theme.set_color(&"font_color", HINT_VARIATION, ACCENT)
