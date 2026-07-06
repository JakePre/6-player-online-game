extends Control
## In-game credits screen (M7-04), generated from assets/CREDITS.md at
## runtime so it can never drift from the ledger. Picked up by the app shell
## router (see AppShell.goto_screen). M16-06: each row fades in as it
## populates (the "credits scroll treatment") — a no-op under reduced motion.

signal navigate(screen: StringName)

## Stagger between each row's fade-in (on top of PartyTheme.DUR_MED per row).
const ROW_STAGGER_SEC := 0.03

@onready var _list: VBoxContainer = %CreditsList
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: navigate.emit(&"main_menu"))
	_back_button.grab_focus()
	ButtonMotion.attach(_back_button)
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
		_add_line(title)
		var details: Array = []
		if row.has("author"):
			details.append("by %s" % row.author)
		if row.has("license"):
			details.append(String(row.license))
		if row.has("source"):
			details.append(String(row.source))
		if not details.is_empty():
			_add_line(" — ".join(details), &"SmallLabel")


func _add_line(text: String, variation: StringName = &"") -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not variation.is_empty():
		label.theme_type_variation = variation
	_list.add_child(label)
	_fade_in(label)


func _fade_in(label: Label) -> void:
	if ArenaFX.reduced_motion:
		return
	var index := label.get_index()
	label.modulate.a = 0.0
	var tween := label.create_tween()
	tween.set_trans(PartyTheme.TRANS_DEFAULT).set_ease(PartyTheme.EASE_DEFAULT)
	tween.tween_interval(index * ROW_STAGGER_SEC)
	tween.tween_property(label, "modulate:a", 1.0, PartyTheme.DUR_MED)


## Pad/keyboard back (M17-04): B / Esc returns to the menu from anywhere on
## this screen, matching the Back button.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		navigate.emit(&"main_menu")
