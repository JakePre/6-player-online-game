extends Control
## Placeholder in-room screen so the app shell has somewhere to land after a
## join (SPEC $4). Shows the room code and live member list; M2-02 replaces
## this with the real lobby (character select, ready-up, round-count setting).

@onready var _code_label: Label = %CodeLabel
@onready var _members_label: Label = %MembersLabel
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	NetManager.room_updated.connect(_on_room_updated)
	_leave_button.pressed.connect(func() -> void: NetManager.request_leave_room())
	_code_label.text = "Room %s" % NetManager.my_room_code
	_leave_button.grab_focus()


func _on_room_updated(state: Dictionary) -> void:
	_code_label.text = "Room %s" % state.code
	var lines: Array[String] = []
	for member: Dictionary in state.members:
		var host_mark := "(host) " if member.slot == state.host_slot else ""
		var link := "" if member.connected else " [disconnected]"
		lines.append("Slot %d: %s%s%s" % [member.slot, host_mark, member.name, link])
	_members_label.text = "\n".join(lines)
