class_name PlaytestPickPanel
extends PanelContainer
## Playtest mode's between-rounds picker (#1070): the host chooses every
## round's game from the live eligible catalog; everyone else watches. Renders
## purely from the PICK snapshot ({eligible: [ids], played: [ids]}), so
## rejoiners and event-racers land here from state alone — same contract as
## ShopPanel (#554). The grid rebuilds only when the eligible set (or host
## status) actually changes, since snapshots arrive every tick.

signal pick_chosen(id: String)

const COLUMNS := 3
const END_ID := "end"

var _title: Label
var _grid: GridContainer
var _history: Label
var _end_button: Button
var _built_key := ""


func _ready() -> void:
	custom_minimum_size = Vector2(780.0, 460.0)
	var main := VBoxContainer.new()
	main.add_theme_constant_override(&"separation", 12)
	add_child(main)
	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", PartyTheme.SIZE_OVERLAY_BODY)
	main.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 2.0
	row.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "GameGrid"
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	var played_header := Label.new()
	played_header.text = "Played this match"
	side.add_child(played_header)
	var history_scroll := ScrollContainer.new()
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(history_scroll)
	_history = Label.new()
	_history.name = "History"
	_history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_scroll.add_child(_history)
	_end_button = Button.new()
	_end_button.name = "EndMatch"
	_end_button.text = "End match"
	_end_button.tooltip_text = "Finish here — finale (if enabled) then the podium."
	_end_button.pressed.connect(func() -> void: pick_chosen.emit(END_ID))
	main.add_child(_end_button)


func render(pick: Dictionary, is_host: bool) -> void:
	var eligible: Array = pick.get("eligible", [])
	_title.text = "Pick the next game" if is_host else "Host is picking the next game..."
	_end_button.visible = is_host
	_history.text = _history_text(pick.get("played", []))
	# Snapshots tick in constantly; only rebuild the button grid when the
	# choice set (or whether this client gets buttons at all) changed.
	var key := "%s|%s" % [is_host, ",".join(eligible)]
	if key == _built_key:
		return
	_built_key = key
	for child in _grid.get_children():
		child.queue_free()
	if not is_host:
		return
	for id: Variant in eligible:
		var sid := StringName(String(id))
		if not MinigameCatalog.is_registered(sid):
			continue
		var button := Button.new()
		button.text = MinigameCatalog.meta_of(sid).display_name
		button.custom_minimum_size = Vector2(180.0, 40.0)
		button.pressed.connect(func() -> void: pick_chosen.emit(String(sid)))
		_grid.add_child(button)


## Pad focus (M17-04): land on the first game button so a controller host can
## pick immediately; spectators have nothing to focus.
func grab_initial_focus() -> void:
	if _grid.get_child_count() > 0:
		(_grid.get_child(0) as Button).grab_focus()


func _history_text(played: Array) -> String:
	if played.is_empty():
		return "Nothing yet."
	var lines: Array[String] = []
	for i in played.size():
		var sid := StringName(String(played[i]))
		var label := String(played[i])
		if MinigameCatalog.is_registered(sid):
			label = MinigameCatalog.meta_of(sid).display_name
		lines.append("%d. %s" % [i + 1, label])
	return "\n".join(lines)
