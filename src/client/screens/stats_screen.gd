extends Control
## Local stats & match history screen (M20-03, #712 — v1, local-only).
## Picked up by the app shell router (see AppShell.goto_screen). Read-only:
## a summary line, per-game plays/wins sorted by most-played, and the last
## 10 matches newest-first — the same three sections StatsStore.DEFAULTS
## carries. Mirrors credits_screen.gd's populate-a-list structure.

signal navigate(screen: StringName)

const MONTH_NAMES := [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]
## Top N favorite games shown, most-played first.
const MAX_FAVORITES := 5

@onready var _summary_label: Label = %SummaryLabel
@onready var _favorites_list: VBoxContainer = %FavoritesList
@onready var _recent_list: VBoxContainer = %RecentList
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: navigate.emit(&"main_menu"))
	_back_button.grab_focus()
	ButtonMotion.attach(_back_button)
	populate(StatsStore.load_stats())


func populate(stats: Dictionary) -> void:
	_summary_label.text = (
		"%d matches played  ·  %d wins  ·  %d podiums"
		% [int(stats.matches), int(stats.wins), int(stats.podiums)]
	)
	_populate_favorites(stats.games)
	_populate_recent(stats.recent)


func _populate_favorites(games: Dictionary) -> void:
	_clear_list(_favorites_list)
	if games.is_empty():
		_add_line(_favorites_list, "Play a match to start tracking favorites.")
		return
	var ids := games.keys()
	ids.sort_custom(
		func(a: String, b: String) -> bool: return int(games[a].plays) > int(games[b].plays)
	)
	for id: String in ids.slice(0, MAX_FAVORITES):
		var entry: Dictionary = games[id]
		var plays := int(entry.plays)
		var wins := int(entry.wins)
		_add_line(
			_favorites_list,
			(
				"%s  —  %d %s, %d %s"
				% [
					_game_display_name(id),
					plays,
					"play" if plays == 1 else "plays",
					wins,
					"win" if wins == 1 else "wins",
				]
			)
		)


func _populate_recent(recent: Array) -> void:
	_clear_list(_recent_list)
	if recent.is_empty():
		_add_line(_recent_list, "No matches recorded yet.")
		return
	for entry: Dictionary in recent:
		var line := (
			"%s — %s of %d"
			% [
				_format_date(int(entry.date)),
				_ordinal(int(entry.placement)),
				int(entry.player_count),
			]
		)
		var standout := String(entry.standout_game)
		if not standout.is_empty():
			line += (
				"  ·  Best: %s (%s)"
				% [_game_display_name(standout), _ordinal(int(entry.standout_placement))]
			)
		_add_line(_recent_list, line)


func _add_line(list: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(label)


## Removes every child immediately (not just queue_free, which defers to
## frame end), so a repopulate in the same call never sees a stale line
## alongside the fresh ones (same convention as color_clash_view's rebuild).
func _clear_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


## Falls back to the raw id for a game removed from the catalog since it was
## played, so an old history entry never breaks the screen.
func _game_display_name(id: String) -> String:
	var sid := StringName(id)
	if MinigameCatalog.is_registered(sid):
		return MinigameCatalog.meta_of(sid).display_name
	return id.capitalize()


func _ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dth" % n
	match n % 10:
		1:
			return "%dst" % n
		2:
			return "%dnd" % n
		3:
			return "%drd" % n
		_:
			return "%dth" % n


func _format_date(unix_seconds: int) -> String:
	if unix_seconds <= 0:
		return "Unknown date"
	var d := Time.get_datetime_dict_from_unix_time(unix_seconds)
	return "%s %d" % [MONTH_NAMES[int(d.month) - 1], int(d.day)]


## Pad/keyboard back (M17-04): B / Esc returns to the menu from anywhere on
## this screen, matching the Back button.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		navigate.emit(&"main_menu")
