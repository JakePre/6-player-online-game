extends Control
## Lobby scene (M2-02): live player list, ready-up, host-controlled round
## count (Quick 8 / Standard 12 / Marathon 15) and start gating (SPEC $4).
## The server owns all lobby state; this scene renders `room_updated`
## broadcasts and sends requests through NetManager.

const ROUND_COUNT_LABELS := {8: "Quick", 12: "Standard", 15: "Marathon"}

@onready var _code_label: Label = %CodeLabel
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _round_option: OptionButton = %RoundOption
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	NetManager.room_updated.connect(_on_room_updated)
	_ready_button.toggled.connect(func(on: bool) -> void: NetManager.request_set_ready(on))
	_start_button.pressed.connect(func() -> void: NetManager.request_start_match())
	_leave_button.pressed.connect(func() -> void: NetManager.request_leave_room())
	for count in NetConfig.ROUND_COUNT_OPTIONS:
		_round_option.add_item("%s (%d rounds)" % [ROUND_COUNT_LABELS[count], count], count)
	_round_option.item_selected.connect(_on_round_option_selected)
	_code_label.text = "Room %s" % NetManager.my_room_code
	_ready_button.grab_focus()


func _on_round_option_selected(index: int) -> void:
	NetManager.request_set_round_count(_round_option.get_item_id(index))


func _on_room_updated(state: Dictionary) -> void:
	var i_am_host: bool = state.host_slot == NetManager.my_slot
	var in_match: bool = state.state == Room.State.IN_MATCH
	_code_label.text = "Room %s" % state.code
	_rebuild_player_list(state)
	_round_option.select(_round_option.get_item_index(state.round_count))
	_round_option.disabled = not i_am_host or in_match
	_ready_button.set_pressed_no_signal(_my_ready(state))
	_ready_button.disabled = in_match
	_start_button.visible = i_am_host
	_start_button.disabled = in_match or not _can_start(state)
	_status_label.text = _status_text(state, i_am_host, in_match)


func _rebuild_player_list(state: Dictionary) -> void:
	for child in _player_list.get_children():
		child.queue_free()
	for member: Dictionary in state.members:
		var row := Label.new()
		row.text = _member_line(member, state.host_slot)
		_player_list.add_child(row)


func _member_line(member: Dictionary, host_slot: int) -> String:
	var host_mark := " (host)" if member.slot == host_slot else ""
	if not member.connected:
		return "%s%s — disconnected" % [member.name, host_mark]
	var ready_mark := "ready" if member.ready else "not ready"
	return "%s%s — %s" % [member.name, host_mark, ready_mark]


func _my_ready(state: Dictionary) -> bool:
	for member: Dictionary in state.members:
		if member.slot == NetManager.my_slot:
			return member.ready
	return false


## Client-side mirror of Room.can_start() for button gating; the server
## revalidates on the actual start request.
func _can_start(state: Dictionary) -> bool:
	var connected := 0
	for member: Dictionary in state.members:
		if member.connected:
			connected += 1
			if not member.ready:
				return false
	return connected >= NetConfig.MIN_PLAYERS_TO_START


func _status_text(state: Dictionary, i_am_host: bool, in_match: bool) -> String:
	if in_match:
		return "Match starting..."
	if not _can_start(state):
		return (
			"Waiting for everyone to ready up (%d+ players)..." % (NetConfig.MIN_PLAYERS_TO_START)
		)
	if i_am_host:
		return "All set — you can start the match!"
	return "All set — waiting for the host to start."
