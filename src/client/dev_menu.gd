extends Node
## Placeholder connection UI so humans can exercise the M1 netcode by hand.
## Built entirely in code on purpose: M2-01/M2-02 replace this with the real
## main menu and lobby scenes.

var _address_edit: LineEdit
var _port_edit: LineEdit
var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _members: Label
var _ping_timer: Timer


func _ready() -> void:
	_build_ui()
	NetManager.connected_to_server.connect(func() -> void: _set_status("Connected."))
	NetManager.connection_failed.connect(func() -> void: _set_status("Connection failed."))
	NetManager.server_disconnected.connect(_on_server_disconnected)
	NetManager.joined_room.connect(_on_joined_room)
	NetManager.join_failed.connect(
		func(reason: int) -> void:
			_set_status("Join failed: %s" % NetConfig.join_result_name(reason))
	)
	NetManager.left_room.connect(
		func() -> void:
			_members.text = ""
			_set_status("Left room.")
	)
	NetManager.room_updated.connect(_on_room_updated)
	NetManager.pong_received.connect(
		func(rtt_ms: int) -> void: _set_status("In room. Ping %d ms" % rtt_ms)
	)


func _on_joined_room(code: String, slot: int, token: String) -> void:
	_set_status("Joined room %s as slot %d." % [code, slot])
	SessionStore.save_session(_address_edit.text, int(_port_edit.text), code, token)


func _on_server_disconnected() -> void:
	_members.text = ""
	_set_status("Server disconnected.")


func _on_room_updated(state: Dictionary) -> void:
	var lines: Array[String] = ["Room %s" % state.code]
	for member: Dictionary in state.members:
		var mark := "(host) " if member.slot == state.host_slot else ""
		var link := "" if member.connected else " [disconnected]"
		lines.append("  slot %d: %s%s%s" % [member.slot, mark, member.name, link])
	_members.text = "\n".join(lines)


func _set_status(text: String) -> void:
	_status.text = text


func _build_ui() -> void:
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(420, 0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(column)

	var title := Label.new()
	title.text = "Party Rush — dev connection menu (replaced in M2)"
	column.add_child(title)

	_address_edit = _add_field(column, "Server address", "127.0.0.1")
	_port_edit = _add_field(column, "Port", str(NetConfig.DEFAULT_PORT))
	_name_edit = _add_field(column, "Name", "Player")
	_code_edit = _add_field(column, "Room code", "")

	_add_button(column, "Connect", _on_connect_pressed)
	_add_button(
		column, "Create room", func() -> void: NetManager.request_create_room(_name_edit.text)
	)
	_add_button(
		column,
		"Join room",
		func() -> void: NetManager.request_join_room(_code_edit.text, _name_edit.text)
	)
	_add_button(column, "Rejoin last session", _on_rejoin_pressed)
	_add_button(column, "Leave room", func() -> void: NetManager.request_leave_room())

	_status = Label.new()
	_status.text = "Not connected."
	column.add_child(_status)
	_members = Label.new()
	column.add_child(_members)

	_ping_timer = Timer.new()
	_ping_timer.wait_time = 2.0
	_ping_timer.timeout.connect(
		func() -> void:
			if not NetManager.my_room_code.is_empty():
				NetManager.send_ping()
	)
	add_child(_ping_timer)
	_ping_timer.start()


func _on_connect_pressed() -> void:
	_set_status("Connecting to %s:%s ..." % [_address_edit.text, _port_edit.text])
	NetManager.connect_to_server(_address_edit.text, int(_port_edit.text))


func _on_rejoin_pressed() -> void:
	var saved := SessionStore.load_session()
	if saved.is_empty() or String(saved.code).is_empty():
		_set_status("No saved session.")
		return
	_set_status("Rejoining %s ..." % saved.code)
	if multiplayer.multiplayer_peer == null:
		NetManager.connect_to_server(saved.address, saved.port)
		await NetManager.connected_to_server
	NetManager.request_rejoin_room(saved.code, saved.token)


func _add_field(parent: Control, label_text: String, initial: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = initial
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _add_button(parent: Control, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)
	return button
