class_name PartyTheme
extends RefCounted
## The design system (M16-01, evolving M6-04's flat theme): one place for
## every visual token — fonts, type scale, palette, spacing, radii, depth,
## and motion standards. Built once at the app-shell root; every screen
## inherits it. docs/STYLE_GUIDE.md documents each token with do/don'ts.
## Hotspot rule (AGENT_COORDINATION §4): additive-only — new tokens and
## variations may be added, existing ones never change meaning mid-milestone.

## Typography — chunky display face for titles/buttons, rounded body face
## for everything else (both OFL, see assets/fonts/ + CREDITS.md).
const FONT_DISPLAY := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const FONT_BODY := preload("res://assets/fonts/Nunito-Variable.ttf")

## Type scale (px). BODY is the theme default; the rest arrive via the
## Label type variations below (DisplayLabel/TitleLabel/HeaderLabel/...).
const SIZE_DISPLAY := 44
const SIZE_TITLE := 30
const SIZE_HEADER := 22
const SIZE_BUTTON := 18
const FONT_SIZE := 16
const SIZE_SMALL := 13
## In-match overlay scale (#831) — screen text drawn OVER the 3D arena reads
## from further away than chrome, so it runs bigger: phase/status headlines
## (MinigameView3D.make_status_label) and gameplay prompts (make_banner).
const SIZE_OVERLAY_TITLE := 40
const SIZE_OVERLAY_BODY := 24

## Palette — dark blue-slate depth with the coin-gold identity accent.
const BG_DARKER := Color(0.07, 0.08, 0.115)
const BG_DARK := Color(0.115, 0.13, 0.175)
const BG_RAISED := Color(0.16, 0.18, 0.235)
const BORDER := Color(0.3, 0.33, 0.42)
const ACCENT := Color(0.96, 0.79, 0.2)
const ACCENT_BRIGHT := Color(1.0, 0.87, 0.38)
const ACCENT_DIM := Color(0.62, 0.5, 0.14)
const SUCCESS := Color(0.36, 0.83, 0.46)
const DANGER := Color(0.92, 0.34, 0.34)
const INFO := Color(0.38, 0.65, 0.95)
const TEXT := Color(0.93, 0.94, 0.96)
const TEXT_DIM := Color(0.6, 0.64, 0.72)

## Spacing scale (px) — margins, separations, padding all come from here.
const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 16
const SPACE_LG := 24
const SPACE_XL := 40

## Radius scale (px). CORNER_RADIUS stays as the default (= RADIUS_MD).
const RADIUS_SM := 6
const RADIUS_MD := 10
const RADIUS_LG := 16
const CORNER_RADIUS := RADIUS_MD

## Motion standards (seconds + Tween curves) — every animated surface
## (M16-02 transitions, hover feedback, banner slides) uses these so the
## whole product moves at one tempo. Reduced-motion (M12-03) suppresses
## the animation entirely; it does not slow these down.
const DUR_FAST := 0.12
const DUR_MED := 0.22
const DUR_SLOW := 0.4
const TRANS_DEFAULT := Tween.TRANS_QUAD
const TRANS_OVERSHOOT := Tween.TRANS_BACK
const EASE_DEFAULT := Tween.EASE_OUT

## Label type variations. HINT_VARIATION predates the rest (M6-04) and
## keeps its name; it styles intro-card control hints in the accent color.
const HINT_VARIATION := &"HintLabel"
const DISPLAY_VARIATION := &"DisplayLabel"
const TITLE_VARIATION := &"TitleLabel"
const HEADER_VARIATION := &"HeaderLabel"
const DIM_VARIATION := &"DimLabel"
const SMALL_VARIATION := &"SmallLabel"
## Elevated card surface (PanelContainer base) for lobby rows, results
## cards, and any panel that should float above the screen background.
const CARD_VARIATION := &"CardPanel"


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = _body(500)
	theme.default_font_size = FONT_SIZE
	_style_panels(theme)
	_style_buttons(theme)
	_style_inputs(theme)
	_style_labels(theme)
	_style_selection_controls(theme)
	_style_bars(theme)
	_style_popups(theme)
	return theme


## A Nunito instance at the given variable-font weight (400–900).
static func _body(weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = FONT_BODY
	font.variation_opentype = {"wght": weight}
	return font


static func _flat(bg: Color, border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(CORNER_RADIUS)
	style.set_content_margin_all(10.0)
	if border_color.a > 0.0:
		style.set_border_width_all(2)
		style.border_color = border_color
	return style


## _flat plus a soft drop shadow — the "this floats" treatment.
static func _elevated(
	bg: Color, border_color: Color = Color.TRANSPARENT, glow: Color = Color(0, 0, 0, 0.45)
) -> StyleBoxFlat:
	var style := _flat(bg, border_color)
	style.shadow_color = glow
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	return style


static func _style_panels(theme: Theme) -> void:
	var panel := _elevated(BG_DARK, BORDER)
	panel.set_corner_radius_all(RADIUS_LG)
	theme.set_stylebox(&"panel", &"PanelContainer", panel)
	theme.set_stylebox(&"panel", &"Panel", _flat(BG_DARKER))
	theme.set_type_variation(CARD_VARIATION, &"PanelContainer")
	var card := _elevated(BG_RAISED, BORDER)
	card.set_content_margin_all(float(SPACE_MD))
	theme.set_stylebox(&"panel", CARD_VARIATION, card)


static func _style_buttons(theme: Theme) -> void:
	theme.set_font(&"font", &"Button", FONT_DISPLAY)
	theme.set_font_size(&"font_size", &"Button", SIZE_BUTTON)
	theme.set_stylebox(&"normal", &"Button", _elevated(BG_RAISED, BORDER))
	# Hover glows gold; pressed sinks flat — the shadow disappearing sells it.
	theme.set_stylebox(
		&"hover", &"Button", _elevated(BG_RAISED.lightened(0.06), ACCENT, Color(ACCENT, 0.22))
	)
	theme.set_stylebox(&"pressed", &"Button", _flat(BG_DARKER, ACCENT_DIM))
	theme.set_stylebox(&"focus", &"Button", _flat(Color.TRANSPARENT, ACCENT))
	theme.set_stylebox(&"disabled", &"Button", _flat(BG_DARKER, BORDER.darkened(0.3)))
	theme.set_color(&"font_color", &"Button", TEXT)
	theme.set_color(&"font_hover_color", &"Button", ACCENT_BRIGHT)
	theme.set_color(&"font_pressed_color", &"Button", ACCENT)
	theme.set_color(&"font_focus_color", &"Button", TEXT)
	theme.set_color(&"font_disabled_color", &"Button", TEXT_DIM)


static func _style_inputs(theme: Theme) -> void:
	theme.set_stylebox(&"normal", &"LineEdit", _flat(BG_DARKER, BORDER))
	theme.set_stylebox(&"focus", &"LineEdit", _elevated(BG_DARKER, ACCENT, Color(ACCENT, 0.18)))
	theme.set_color(&"font_color", &"LineEdit", TEXT)
	theme.set_color(&"font_placeholder_color", &"LineEdit", TEXT_DIM)
	theme.set_color(&"caret_color", &"LineEdit", ACCENT)


static func _style_labels(theme: Theme) -> void:
	theme.set_color(&"font_color", &"Label", TEXT)
	theme.set_type_variation(HINT_VARIATION, &"Label")
	theme.set_color(&"font_color", HINT_VARIATION, ACCENT)
	theme.set_font(&"font", HINT_VARIATION, _body(600))
	_display_label(theme, DISPLAY_VARIATION, SIZE_DISPLAY)
	_display_label(theme, TITLE_VARIATION, SIZE_TITLE)
	_display_label(theme, HEADER_VARIATION, SIZE_HEADER)
	theme.set_type_variation(DIM_VARIATION, &"Label")
	theme.set_color(&"font_color", DIM_VARIATION, TEXT_DIM)
	theme.set_type_variation(SMALL_VARIATION, &"Label")
	theme.set_color(&"font_color", SMALL_VARIATION, TEXT_DIM)
	theme.set_font_size(&"font_size", SMALL_VARIATION, SIZE_SMALL)


static func _display_label(theme: Theme, variation: StringName, size: int) -> void:
	theme.set_type_variation(variation, &"Label")
	theme.set_font(&"font", variation, FONT_DISPLAY)
	theme.set_font_size(&"font_size", variation, size)


static func _style_selection_controls(theme: Theme) -> void:
	for type in [&"CheckBox", &"CheckButton"]:
		theme.set_color(&"font_color", type, TEXT)
		theme.set_color(&"font_hover_color", type, ACCENT_BRIGHT)
		theme.set_color(&"font_pressed_color", type, ACCENT)
		theme.set_color(&"font_disabled_color", type, TEXT_DIM)


static func _style_bars(theme: Theme) -> void:
	var track := _flat(BG_DARKER, BORDER)
	track.set_content_margin_all(2.0)
	theme.set_stylebox(&"background", &"ProgressBar", track)
	theme.set_stylebox(&"fill", &"ProgressBar", _flat(ACCENT))
	theme.set_stylebox(&"slider", &"HSlider", _flat(BG_DARKER, BORDER))
	theme.set_stylebox(&"grabber_area", &"HSlider", _flat(ACCENT_DIM))
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", _flat(ACCENT))
	for bar in [&"VScrollBar", &"HScrollBar"]:
		theme.set_stylebox(&"scroll", bar, _flat(BG_DARKER))
		theme.set_stylebox(&"grabber", bar, _flat(BORDER))
		theme.set_stylebox(&"grabber_highlight", bar, _flat(ACCENT_DIM))
		theme.set_stylebox(&"grabber_pressed", bar, _flat(ACCENT))


## Popup surfaces (M16-13): OptionButton dropdowns (PopupMenu) and native
## dialogs (AcceptDialog/Window) otherwise render engine-default gray — the
## only unthemed chrome the consistency audit found still reachable in-game.
static func _style_popups(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"PopupMenu", _elevated(BG_DARK, BORDER))
	theme.set_stylebox(&"hover", &"PopupMenu", _flat(BG_RAISED, ACCENT))
	theme.set_color(&"font_color", &"PopupMenu", TEXT)
	theme.set_color(&"font_hover_color", &"PopupMenu", ACCENT_BRIGHT)
	theme.set_color(&"font_disabled_color", &"PopupMenu", TEXT_DIM)
	theme.set_color(&"font_separator_color", &"PopupMenu", TEXT_DIM)
	theme.set_stylebox(&"panel", &"AcceptDialog", _flat(BG_DARK))
	# The embedded titlebar is drawn by Window's border style; raise it to the
	# panel language and put the title in the display face.
	var titlebar := _flat(BG_RAISED, BORDER)
	titlebar.expand_margin_top = 36.0
	theme.set_stylebox(&"embedded_border", &"Window", titlebar)
	theme.set_color(&"title_color", &"Window", TEXT)
	theme.set_font(&"title_font", &"Window", FONT_DISPLAY)
	theme.set_font_size(&"title_font_size", &"Window", SIZE_BUTTON)
