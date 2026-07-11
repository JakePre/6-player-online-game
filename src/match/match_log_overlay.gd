class_name MatchLogOverlay
extends Control
## Hold-Tab match log (#814): a roster ranked by score alongside a scrolling
## feed of match events (round results, leaderboards, the match winner). Held
## open over the live match — like the pause overlay (M18-03) it never pauses
## the server sim, it just overlays a readable summary while the round runs on.
## Pad Select opens it too, for M17 controller parity. Built in code on the M16
## design system; a pure renderer — match_screen owns the data and feeds it in.

var _standings_list: VBoxContainer
var _feed_list: VBoxContainer
var _feed_scroll: ScrollContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Informational and held — it doesn't need to eat gameplay input behind it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(PartyTheme.BG_DARKER, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_build_panel()
	visible = false


func _build_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = PartyTheme.CARD_VARIATION
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", PartyTheme.SPACE_MD)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Match Log"
	title.theme_type_variation = PartyTheme.TITLE_VARIATION
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", PartyTheme.SPACE_LG)
	box.add_child(columns)

	# Left: the roster ranked by score.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240.0
	columns.add_child(left)
	var standings_header := Label.new()
	standings_header.text = "Standings"
	standings_header.theme_type_variation = PartyTheme.HEADER_VARIATION
	left.add_child(standings_header)
	_standings_list = VBoxContainer.new()
	left.add_child(_standings_list)

	# Right: the scrolling event feed, newest at the bottom.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 360.0
	columns.add_child(right)
	var feed_header := Label.new()
	feed_header.text = "Minigame log"
	feed_header.theme_type_variation = PartyTheme.HEADER_VARIATION
	right.add_child(feed_header)
	_feed_scroll = ScrollContainer.new()
	_feed_scroll.custom_minimum_size.y = 260.0
	_feed_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_feed_scroll)
	_feed_list = VBoxContainer.new()
	_feed_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed_scroll.add_child(_feed_list)

	var hint := Label.new()
	hint.text = "The match keeps going — release to return."
	hint.theme_type_variation = PartyTheme.SMALL_VARIATION
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


## Populate and show. `standings` and `feed` are ready-to-print lines
## (match_screen builds them via MatchFormat); the feed scrolls to its newest
## line at the bottom.
func open_with(standings: Array, feed: Array) -> void:
	_fill(_standings_list, standings, "No scores yet")
	_fill(_feed_list, feed, "The match is just getting started…")
	visible = true
	# Land at the newest event once the new lines have laid out.
	_scroll_feed_to_bottom.call_deferred()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _fill(list: VBoxContainer, lines: Array, empty_text: String) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if lines.is_empty():
		var placeholder := Label.new()
		placeholder.text = empty_text
		placeholder.theme_type_variation = PartyTheme.DIM_VARIATION
		list.add_child(placeholder)
		return
	for line: String in lines:
		var label := Label.new()
		label.text = line
		list.add_child(label)


func _scroll_feed_to_bottom() -> void:
	if _feed_scroll == null:
		return
	_feed_scroll.scroll_vertical = int(_feed_list.size.y)
