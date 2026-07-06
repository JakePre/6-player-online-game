class_name InputHintLabel
extends Label
## A label that renders a control hint for an input action in the *active*
## device's glyph (#608) and re-renders live when the device changes —
## "Emote — T" on keyboard, "Emote — Ⓐ" on an Xbox pad, "Emote — ✕" on a
## DualSense. The reusable building block for device-aware hints (#585 Shred
## Session labels, intro cards, the emote bar, the remap UI, M18-05's audit).

## The input action to show (e.g. &"action_primary"). Set via the inspector or
## set_hint().
@export var action: StringName = &"":
	set(value):
		action = value
		_refresh()

## Text shown before the glyph, e.g. "Emote — " → "Emote — T".
@export var prefix := "":
	set(value):
		prefix = value
		_refresh()


func _ready() -> void:
	InputGlyphs.device_changed.connect(_on_device_changed)
	_refresh()


func set_hint(new_action: StringName, new_prefix := "") -> void:
	action = new_action
	prefix = new_prefix
	_refresh()


func _on_device_changed(_device: InputGlyphs.Device) -> void:
	_refresh()


func _refresh() -> void:
	# Nodes can set exported props before _ready; skip until InputGlyphs is
	# reachable (autoloads exist once the tree is up).
	if not is_inside_tree():
		return
	var glyph := InputGlyphs.glyph_for(action)
	text = prefix + glyph if not glyph.is_empty() else prefix.strip_edges()
