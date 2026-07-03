extends Control
## Lobby scene (M2-02): live player list, ready-up, host-controlled round
## count (Quick 8 / Standard 12 / Marathon 15) and start gating (SPEC $4).
## The server owns all lobby state; this scene renders `room_updated`
## broadcasts and sends requests through NetManager.

const ROUND_COUNT_LABELS := {8: "Quick", 12: "Standard", 15: "Marathon"}

## Last broadcast room state, kept around so the character carousel buttons
## know the current pick without waiting for a round trip.
var _last_state: Dictionary = {}

@onready var _code_label: Label = %CodeLabel
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _round_option: OptionButton = %RoundOption
@onready var _mutator_box: VBoxContainer = %MutatorBox
@onready var _mutator_toggles: VBoxContainer = %MutatorToggles
@onready var _character_label: Label = %CharacterLabel
@onready var _prev_character_button: Button = %PrevCharacterButton
@onready var _next_character_button: Button = %NextCharacterButton
@onready var _color_swatch: ColorRect = %ColorSwatch
@onready var _character_preview: CharacterPreview = %CharacterPreview
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	NetManager.room_updated.connect(_on_room_updated)
	_ready_button.toggled.connect(func(on: bool) -> void: NetManager.request_set_ready(on))
	_start_button.pressed.connect(func() -> void: NetManager.request_start_match())
	_leave_button.pressed.connect(func() -> void: NetManager.request_leave_room())
	_prev_character_button.pressed.connect(_on_character_step.bind(-1))
	_next_character_button.pressed.connect(_on_character_step.bind(1))
	for count in NetConfig.ROUND_COUNT_OPTIONS:
		_round_option.add_item("%s (%d rounds)" % [ROUND_COUNT_LABELS[count], count], count)
	_round_option.item_selected.connect(_on_round_option_selected)
	_build_mutator_toggles()
	_code_label.text = "Room %s" % NetManager.my_room_code
	_color_swatch.color = PlayerPalette.color_for_slot(NetManager.my_slot)
	_ready_button.grab_focus()
	# Returning from a match: the routing broadcast fired before this scene
	# existed, so seed from the mirror instead of waiting for the next one.
	if NetManager.my_room_state.has("members"):
		_on_room_updated(NetManager.my_room_state)


func _on_round_option_selected(index: int) -> void:
	NetManager.request_set_round_count(_round_option.get_item_id(index))


## One checkbox per registered mutator (M9-02); the whole section stays
## hidden until a mutator pack registers something (M9-04/05).
func _build_mutator_toggles() -> void:
	MutatorCatalog.register_builtins()
	var ids := MutatorCatalog.registered_ids()
	_mutator_box.visible = not ids.is_empty()
	for id: StringName in ids:
		var toggle := CheckBox.new()
		toggle.name = "Mutator_%s" % id
		var mutator := MutatorCatalog.mutator_of(id)
		toggle.text = mutator.display_name
		toggle.tooltip_text = mutator.blurb
		toggle.set_meta(&"mutator_id", id)
		toggle.toggled.connect(func(_on: bool) -> void: _send_mutator_pool())
		_mutator_toggles.add_child(toggle)


func _send_mutator_pool() -> void:
	var pool: Array = []
	for toggle: CheckBox in _mutator_toggles.get_children():
		if toggle.button_pressed:
			pool.append(String(toggle.get_meta(&"mutator_id")))
	NetManager.request_set_mutator_pool(pool)


## Server echo wins: reflect the broadcast pool without re-sending it.
func _sync_mutator_toggles(state: Dictionary, editable: bool) -> void:
	var pool: Array = []
	for id in state.get("mutator_pool", []):
		pool.append(String(id))
	for toggle: CheckBox in _mutator_toggles.get_children():
		toggle.set_pressed_no_signal(String(toggle.get_meta(&"mutator_id")) in pool)
		toggle.disabled = not editable


## Steps the local player's roster pick by `delta` (wraps around); the server
## is the source of truth and echoes the accepted pick back via room_updated.
func _on_character_step(delta: int) -> void:
	var ids := CharacterRoster.ids()
	var index := ids.find(_my_character_id())
	if index < 0:
		index = 0
	NetManager.request_set_character(ids[posmod(index + delta, ids.size())])


func _my_character_id() -> StringName:
	for member: Dictionary in _last_state.get("members", []):
		if member.slot == NetManager.my_slot:
			return member.character_id
	return CharacterRoster.DEFAULT_ID


func _on_room_updated(state: Dictionary) -> void:
	_last_state = state
	var i_am_host: bool = state.host_slot == NetManager.my_slot
	var in_match: bool = state.state == Room.State.IN_MATCH
	_code_label.text = "Room %s" % state.code
	_rebuild_player_list(state)
	_round_option.select(_round_option.get_item_index(state.round_count))
	_round_option.disabled = not i_am_host or in_match
	_sync_mutator_toggles(state, i_am_host and not in_match)
	_character_label.text = CharacterRoster.display_name_for(_my_character_id())
	_character_preview.show_character(
		_my_character_id(), PlayerPalette.color_for_slot(NetManager.my_slot), _my_ready(state)
	)
	_prev_character_button.disabled = in_match
	_next_character_button.disabled = in_match
	_color_swatch.color = PlayerPalette.color_for_slot(NetManager.my_slot)
	_ready_button.set_pressed_no_signal(_my_ready(state))
	_ready_button.disabled = in_match
	_start_button.visible = i_am_host
	_start_button.disabled = in_match or not _can_start(state)
	_status_label.text = _status_text(state, i_am_host, in_match)


func _rebuild_player_list(state: Dictionary) -> void:
	for child in _player_list.get_children():
		child.queue_free()
	var i_am_host: bool = state.host_slot == NetManager.my_slot
	for member: Dictionary in state.members:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = _member_line(member, state.host_slot)
		label.modulate = PlayerPalette.color_for_slot(member.slot)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		# Host-only kick (#141) — never on your own row, lobby only.
		if i_am_host and member.slot != NetManager.my_slot and state.state == Room.State.LOBBY:
			var kick := Button.new()
			kick.text = "Kick"
			kick.pressed.connect(NetManager.request_kick.bind(int(member.slot)))
			row.add_child(kick)
		_player_list.add_child(row)


func _member_line(member: Dictionary, host_slot: int) -> String:
	var host_mark := " (host)" if member.slot == host_slot else ""
	var character_name := CharacterRoster.display_name_for(member.character_id)
	if not member.connected:
		return "%s%s [%s] — disconnected" % [member.name, host_mark, character_name]
	var ready_mark := "ready" if member.ready else "not ready"
	return "%s%s [%s] — %s" % [member.name, host_mark, character_name, ready_mark]


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
