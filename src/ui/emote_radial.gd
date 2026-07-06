class_name EmoteRadial
extends Control
## Controller emote wheel (#608 part 3, owner-approved 2026-07-06): hold the
## emote button to open, aim with the RIGHT stick, release to send. The six
## emotes sit in a ring. The right stick and the emote button are both unused
## by gameplay (games drive movement off the LEFT stick and act with A/X), so a
## player reacts while still moving, with no input conflict. Aiming below a
## deadzone means "cancel" — releasing then sends nothing.

## Stick magnitude under which no slot is selected (release = cancel).
const AIM_DEADZONE := 0.4
## Ring radius and per-slot box, in pixels.
const RADIUS := 104.0
const SLOT_SIZE := 64.0

var _selected := -1
var _slots: Array[Label] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var count := Emotes.EMOTES.size()
	for i in count:
		var slot := Label.new()
		slot.name = "Slot%d" % i
		slot.text = Emotes.EMOTES[i]
		slot.add_theme_font_size_override(&"font_size", PartyTheme.SIZE_DISPLAY)
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.set_anchors_preset(Control.PRESET_CENTER)
		var angle := _slot_angle(i, count)
		# Anchored to the screen centre, then pushed out along the ring. Pivot
		# from the slot's own centre so the selected pop scales in place.
		slot.position += Vector2(RADIUS * cos(angle), RADIUS * sin(angle))
		slot.pivot_offset = slot.custom_minimum_size / 2.0
		add_child(slot)
		_slots.append(slot)
	_apply_highlight()


## Slot i's angle: slot 0 at the top (12 o'clock), going clockwise. Matches the
## right stick's screen-space angle (up = -Y = -PI/2) so aiming points at it.
static func _slot_angle(i: int, count: int) -> float:
	return -PI / 2.0 + TAU * i / count


func open() -> void:
	_selected = -1
	visible = true
	_apply_highlight()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func selected_index() -> int:
	return _selected


## Point the wheel with a stick vector (screen space: +Y down). Below the
## deadzone selects nothing; otherwise the slot whose ring angle is nearest.
func aim(dir: Vector2) -> void:
	if dir.length() < AIM_DEADZONE:
		_set_selected(-1)
		return
	var count := Emotes.EMOTES.size()
	var theta := dir.angle()
	var best := 0
	var best_delta := TAU
	for i in count:
		var delta := absf(wrapf(theta - _slot_angle(i, count), -PI, PI))
		if delta < best_delta:
			best_delta = delta
			best = i
	_set_selected(best)


func _set_selected(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	_apply_highlight()


## The aimed slot pops bright; the rest dim. Nothing selected (centre) leaves
## them all at the resting dim so "release now = cancel" reads clearly.
func _apply_highlight() -> void:
	for i in _slots.size():
		var chosen := i == _selected
		_slots[i].modulate = Color(1, 1, 1, 1.0 if chosen else 0.55)
		_slots[i].scale = Vector2(1.25, 1.25) if chosen else Vector2.ONE
