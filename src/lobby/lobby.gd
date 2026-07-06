extends Control
## Lobby scene (M2-02): live player list, ready-up, host-controlled round
## count (Quick 8 / Standard 12 / Marathon 15) and start gating (SPEC $4).
## The server owns all lobby state; this scene renders `room_updated`
## broadcasts and sends requests through NetManager. M16-04/05: the room
## code, player list, match settings, and character carousel are each a
## themed CardPanel section.

const ROUND_COUNT_LABELS := {8: "Quick", 12: "Standard", 15: "Marathon"}
const SERIES_LABELS := {1: "Single match", 3: "Best of 3", 5: "Best of 5"}
## How long the Copy button shows its "Copied!" confirmation before
## reverting to its normal label.
const COPY_FEEDBACK_SEC := 1.5

## Last broadcast room state, kept around so the character carousel buttons
## know the current pick without waiting for a round trip.
var _last_state: Dictionary = {}
## Host-only practice-bot controls (#577), built in _ready so no .tscn churn.
var _add_bot_button: Button
var _remove_bot_button: Button
## Pickable color swatches (#581), one per palette index, built in code under
## the character card. Index i maps to PlayerPalette.active_colors()[i].
var _color_swatches: Array[ColorRect] = []

@onready var _code_label: Label = %CodeLabel
@onready var _copy_button: Button = %CopyButton
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _round_option: OptionButton = %RoundOption
@onready var _series_option: OptionButton = %SeriesOption
@onready var _series_board: Label = %SeriesBoard
@onready var _mutator_box: VBoxContainer = %MutatorBox
@onready var _mutator_toggles: VBoxContainer = %MutatorToggles
@onready var _game_toggles: VBoxContainer = %GameToggles
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
	_build_bot_controls()
	_ready_button.toggled.connect(func(on: bool) -> void: NetManager.request_set_ready(on))
	_start_button.pressed.connect(func() -> void: NetManager.request_start_match())
	_leave_button.pressed.connect(func() -> void: NetManager.request_leave_room())
	_copy_button.pressed.connect(_on_copy_pressed)
	_prev_character_button.pressed.connect(_on_character_step.bind(-1))
	_next_character_button.pressed.connect(_on_character_step.bind(1))
	for count in NetConfig.ROUND_COUNT_OPTIONS:
		_round_option.add_item("%s (%d rounds)" % [ROUND_COUNT_LABELS[count], count], count)
	_round_option.item_selected.connect(_on_round_option_selected)
	for length in NetConfig.SERIES_LENGTH_OPTIONS:
		_series_option.add_item(SERIES_LABELS[length], length)
	_series_option.item_selected.connect(
		func(index: int) -> void:
			NetManager.request_set_series_length(_series_option.get_item_id(index))
	)
	_build_mutator_toggles()
	_build_game_toggles()
	_build_color_swatches()
	_code_label.text = NetManager.my_room_code
	_color_swatch.color = PlayerPalette.color_for_slot(NetManager.my_slot)
	_ready_button.grab_focus()
	for button: Button in [
		_copy_button,
		_prev_character_button,
		_next_character_button,
		_ready_button,
		_start_button,
		_leave_button,
	]:
		ButtonMotion.attach(button)
	# Returning from a match: the routing broadcast fired before this scene
	# existed, so seed from the mirror instead of waiting for the next one.
	if NetManager.my_room_state.has("members"):
		_on_room_updated(NetManager.my_room_state)


## Add/Remove-bot buttons for solo testing (#577): siblings of the start
## button, host-only, wired to the new request pair.
func _build_bot_controls() -> void:
	_add_bot_button = Button.new()
	_add_bot_button.text = "+ Add Bot"
	_add_bot_button.pressed.connect(func() -> void: NetManager.request_add_bot())
	_remove_bot_button = Button.new()
	_remove_bot_button.text = "− Remove Bot"
	_remove_bot_button.pressed.connect(func() -> void: NetManager.request_remove_bot())
	var parent := _start_button.get_parent()
	parent.add_child(_add_bot_button)
	parent.add_child(_remove_bot_button)
	parent.move_child(_add_bot_button, _start_button.get_index())
	parent.move_child(_remove_bot_button, _start_button.get_index())
	ButtonMotion.attach(_add_bot_button)
	ButtonMotion.attach(_remove_bot_button)


## Room-code display's "copy-tap feedback" (M16-04): copies to the system
## clipboard and swaps the button label briefly to confirm it landed.
func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_code_label.text)
	_copy_button.text = "Copied!"
	get_tree().create_timer(COPY_FEEDBACK_SEC).timeout.connect(
		func() -> void:
			if is_instance_valid(_copy_button):
				_copy_button.text = "Copy code"
	)


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


## One checkbox per registered minigame (#572): unchecking a game adds it to
## the host's exclusion set. Default (all checked) means nothing excluded,
## matching how the mutator pool defaults to none-selected = mutators off.
func _build_game_toggles() -> void:
	MinigameCatalog.register_builtins()
	for id: StringName in MinigameCatalog.registered_ids():
		var toggle := CheckBox.new()
		toggle.name = "Game_%s" % id
		toggle.text = MinigameCatalog.meta_of(id).display_name
		toggle.button_pressed = true
		toggle.set_meta(&"game_id", id)
		toggle.toggled.connect(func(_on: bool) -> void: _send_excluded_games())
		_game_toggles.add_child(toggle)


func _send_excluded_games() -> void:
	var excluded: Array = []
	for toggle: CheckBox in _game_toggles.get_children():
		if not toggle.button_pressed:
			excluded.append(String(toggle.get_meta(&"game_id")))
	NetManager.request_set_excluded_games(excluded)


## Server echo wins: reflect the broadcast exclusion set without re-sending it.
func _sync_game_toggles(state: Dictionary, editable: bool) -> void:
	var excluded: Array = []
	for id in state.get("excluded_game_ids", []):
		excluded.append(String(id))
	for toggle: CheckBox in _game_toggles.get_children():
		toggle.set_pressed_no_signal(String(toggle.get_meta(&"game_id")) not in excluded)
		toggle.disabled = not editable


## A row of pickable color swatches under the character card (#581). Built once;
## colors/enabled state are refreshed from room state in _sync_color_swatches.
func _build_color_swatches() -> void:
	var row := HBoxContainer.new()
	row.name = "ColorSwatches"
	row.add_theme_constant_override(&"separation", PartyTheme.SPACE_XS)
	_character_preview.get_parent().add_child(row)
	for i in PlayerPalette.COLORS.size():
		var swatch := ColorRect.new()
		swatch.name = "Swatch%d" % i
		swatch.custom_minimum_size = Vector2(24, 24)
		swatch.color = PlayerPalette.active_colors()[i]
		swatch.tooltip_text = "Color P%d" % (i + 1)
		swatch.gui_input.connect(_on_swatch_input.bind(i))
		row.add_child(swatch)
		_color_swatches.append(swatch)


## Only a left click on an enabled swatch requests it; the server validates
## uniqueness and echoes the accepted pick back via room_updated.
func _on_swatch_input(event: InputEvent, index: int) -> void:
	if not bool(_color_swatches[index].get_meta(&"pickable", false)):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		NetManager.request_set_color(index)


## Reflect the broadcast: swatches taken by *other* members dim and stop
## responding; the local player's current color is scaled up as the selection
## cue. Editable is false in-match, freezing the whole row.
func _sync_color_swatches(state: Dictionary, editable: bool) -> void:
	var taken := {}
	for member: Dictionary in state.get("members", []):
		if int(member.slot) == NetManager.my_slot:
			continue
		var idx := PlayerPalette.effective_index(
			int(member.slot), int(member.get("color_index", -1))
		)
		taken[idx] = true
	var mine := PlayerPalette.effective_index(NetManager.my_slot, _my_color_index(state))
	for i in _color_swatches.size():
		var swatch := _color_swatches[i]
		swatch.color = PlayerPalette.active_colors()[i]
		var is_taken: bool = taken.has(i)
		swatch.set_meta(&"pickable", editable and not is_taken)
		swatch.modulate.a = 0.3 if is_taken else 1.0
		swatch.pivot_offset = swatch.size / 2.0
		swatch.scale = Vector2(1.2, 1.2) if i == mine else Vector2.ONE


func _my_color_index(state: Dictionary) -> int:
	for member: Dictionary in state.get("members", []):
		if int(member.slot) == NetManager.my_slot:
			return int(member.get("color_index", -1))
	return -1


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
	_code_label.text = state.code
	_rebuild_player_list(state)
	_round_option.select(_round_option.get_item_index(state.round_count))
	_round_option.disabled = not i_am_host or in_match
	var series: Dictionary = state.get("series", {})
	var series_length := int(series.get("length", 1))
	_series_option.select(_series_option.get_item_index(series_length))
	_series_option.disabled = not i_am_host or in_match
	_update_series_board(series)
	_sync_mutator_toggles(state, i_am_host and not in_match)
	_sync_game_toggles(state, i_am_host and not in_match)
	_character_label.text = CharacterRoster.display_name_for(_my_character_id())
	_character_preview.show_character(
		_my_character_id(), PlayerPalette.color_for_slot(NetManager.my_slot), _my_ready(state)
	)
	_prev_character_button.disabled = in_match
	_next_character_button.disabled = in_match
	_color_swatch.color = PlayerPalette.color_for_slot(NetManager.my_slot)
	_sync_color_swatches(state, not in_match)
	_ready_button.set_pressed_no_signal(_my_ready(state))
	_ready_button.disabled = in_match
	_start_button.visible = i_am_host
	_start_button.disabled = in_match or not _can_start(state)
	_refresh_bot_controls(state, i_am_host, in_match)
	_status_label.text = _status_text(state, i_am_host, in_match)


## Host sees the bot controls in the lobby; add disables at the cap, remove
## disables with no bots present (#577).
func _refresh_bot_controls(state: Dictionary, i_am_host: bool, in_match: bool) -> void:
	var members: Array = state.get("members", [])
	var bot_count := 0
	for member: Dictionary in members:
		if member.get("is_bot", false):
			bot_count += 1
	var show := i_am_host and not in_match
	_add_bot_button.visible = show
	_remove_bot_button.visible = show
	_add_bot_button.disabled = members.size() >= NetConfig.MAX_PLAYERS_PER_ROOM
	_remove_bot_button.disabled = bot_count == 0


## Running series scoreboard between matches (M11-02).
func _update_series_board(series: Dictionary) -> void:
	var rows: Array = series.get("standings", [])
	if int(series.get("length", 1)) <= 1 or rows.is_empty():
		_series_board.visible = false
		return
	var names := {}
	for member: Dictionary in _last_state.get("members", []):
		names[int(member.slot)] = member.name
	var header := (
		"Series — match %d of %d"
		% [
			(
				int(series.get("matches_played", 0))
				+ (0 if bool(series.get("complete", false)) else 1)
			),
			int(series.get("length", 1)),
		]
	)
	if bool(series.get("complete", false)):
		header = "Series complete!"
	var lines := MatchFormat.series_lines(rows, names)
	_series_board.text = header + "\n" + "\n".join(lines)
	_series_board.visible = true


func _rebuild_player_list(state: Dictionary) -> void:
	for child in _player_list.get_children():
		child.queue_free()
	var i_am_host: bool = state.host_slot == NetManager.my_slot
	for member: Dictionary in state.members:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", PartyTheme.SPACE_SM)
		# A small color-swatch "portrait" chip stands in for a character
		# thumbnail (M16-04/05) until real per-character art lands.
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(20, 20)
		portrait.color = PlayerPalette.color_for_slot(member.slot)
		row.add_child(portrait)
		var label := Label.new()
		label.text = _member_line(member, state.host_slot)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_status_badge(member))
		# Host-only kick (#141) — never on your own row, lobby only.
		if i_am_host and member.slot != NetManager.my_slot and state.state == Room.State.LOBBY:
			var kick := Button.new()
			kick.text = "Kick"
			ButtonMotion.attach(kick)
			kick.pressed.connect(NetManager.request_kick.bind(int(member.slot)))
			row.add_child(kick)
		_player_list.add_child(row)


## A themed ready/not-ready/disconnected badge, separate from the name line
## so its color always reads at a glance (M16-04's "ready states" polish).
func _status_badge(member: Dictionary) -> Label:
	var badge := Label.new()
	if not member.connected:
		badge.text = "disconnected"
		badge.theme_type_variation = &"DimLabel"
	elif member.ready:
		badge.text = "ready"
		badge.add_theme_color_override(&"font_color", PartyTheme.SUCCESS)
	else:
		badge.text = "not ready"
		badge.theme_type_variation = &"DimLabel"
	return badge


## Rows lead with the always-on player number (ADR 003 F2 / M15-02), the same
## "P3" every nameplate and results line shows, so players learn their number
## in the lobby before the first round.
func _member_line(member: Dictionary, host_slot: int) -> String:
	var numbered := "%s %s" % [PlayerPalette.label_for_slot(member.slot), member.name]
	var host_mark := " (host)" if member.slot == host_slot else ""
	var character_name := CharacterRoster.display_name_for(member.character_id)
	return "%s%s [%s]" % [numbered, host_mark, character_name]


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
