extends Control
## In-game credits screen (M7-04), generated from assets/CREDITS.md at
## runtime so it can never drift from the ledger. Picked up by the app shell
## router (see AppShell.goto_screen).

signal navigate(screen: StringName)

@onready var _list: VBoxContainer = %CreditsList
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: navigate.emit(&"main_menu"))
	_back_button.grab_focus()
	populate(CreditsCatalog.load_rows())


func populate(rows: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	if rows.is_empty():
		_add_line("Credits unavailable — see assets/CREDITS.md in the repository.")
		return
	for row: Dictionary in rows:
		var title: String = row.get("asset", row.get("tool", ""))
		if title.is_empty():
			continue
		_add_line(title, 16)
		var details: Array = []
		if row.has("author"):
			details.append("by %s" % row.author)
		if row.has("license"):
			details.append(String(row.license))
		if row.has("source"):
			details.append(String(row.source))
		if not details.is_empty():
			_add_line(" — ".join(details), 12)


func _add_line(text: String, font_size := 14) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	_list.add_child(label)
