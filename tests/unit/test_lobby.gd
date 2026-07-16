extends GutTest
## Lobby scene (M16-04/05 visual pass): the room-code copy button, the
## per-row ready/portrait chip, and the character confirm-flourish. No test
## file existed for lobby.gd before this pass; the required-nodes check
## guards against a future scene rebuild silently dropping a %UniqueName the
## script depends on (the test_main_menu.gd pattern from M16-03).

const SCENE_PATH := "res://src/lobby/lobby.tscn"

## Every node lobby.gd reaches by unique name (%Name) — dropping any of these
## in a scene rebuild would crash the live lobby.
const REQUIRED_NODES: Array[String] = [
	"CodeLabel",
	"CopyButton",
	"PlayerList",
	"RoundOption",
	"SeriesOption",
	"SeriesBoard",
	"MutatorBox",
	"MutatorToggles",
	"GamesBox",
	"CharacterLabel",
	"PrevCharacterButton",
	"NextCharacterButton",
	"ColorSwatch",
	"CharacterPreview",
	"ReadyButton",
	"StartButton",
	"LeaveButton",
	"StatusLabel",
]

var lobby: Control


func before_each() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	lobby = scene.instantiate()
	add_child_autofree(lobby)


func after_each() -> void:
	ArenaFX.reduced_motion = false


func _scene_node_names() -> Array[String]:
	var scene: PackedScene = load(SCENE_PATH)
	var state := scene.get_state()
	var names: Array[String] = []
	for i in state.get_node_count():
		names.append(state.get_node_name(i))
	return names


func test_scene_loads() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	assert_true(scene.can_instantiate(), "the restyled lobby scene is valid")


func test_keeps_every_node_the_script_depends_on() -> void:
	var names := _scene_node_names()
	for required in REQUIRED_NODES:
		assert_true(required in names, "lobby keeps %%%s (script depends on it)" % required)


func test_copy_button_copies_the_room_code_and_confirms() -> void:
	lobby.get_node("%CodeLabel").text = "ABC123"
	var copy_button: Button = lobby.get_node("%CopyButton")
	# A headless test runner has no real OS clipboard to round-trip through
	# (DisplayServer.clipboard_get() reliably reads back "" in CI); the
	# button's own confirmation state is what's actually testable here.
	copy_button.pressed.emit()
	assert_eq(copy_button.text, "Copied!", "the button confirms the copy immediately")


func test_status_badge_reads_ready_not_ready_and_disconnected() -> void:
	assert_eq(lobby._status_badge({"connected": true, "ready": true}).text, "ready")
	assert_eq(lobby._status_badge({"connected": true, "ready": false}).text, "not ready")
	assert_eq(lobby._status_badge({"connected": false, "ready": false}).text, "disconnected")


func test_player_list_rebuild_adds_a_portrait_chip_per_row() -> void:
	(
		lobby
		. _rebuild_player_list(
			{
				"host_slot": 0,
				"state": Room.State.LOBBY,
				"members":
				[
					{
						"slot": 0,
						"name": "Alice",
						"connected": true,
						"ready": true,
						"character_id": &"knight"
					},
					{
						"slot": 1,
						"name": "Bob",
						"connected": true,
						"ready": false,
						"character_id": &"mage"
					},
				],
			}
		)
	)
	var player_list: VBoxContainer = lobby.get_node("%PlayerList")
	assert_eq(player_list.get_child_count(), 2, "one row per member")
	var first_row: HBoxContainer = player_list.get_child(0)
	assert_true(first_row.get_child(0) is ColorRect, "the row leads with a portrait chip")


func test_character_preview_flourishes_on_a_real_pick_change() -> void:
	var preview: CharacterPreview = lobby.get_node("%CharacterPreview")
	var ids := CharacterRoster.ids()
	# The first reveal flourishes too (there's no prior pick to compare
	# against); settle it manually so the assertion below isolates the pop
	# triggered by the *second*, real pick change.
	preview.show_character(ids[0], Color.WHITE)
	preview._rig.scale = Vector3.ONE
	preview.show_character(ids[1 % ids.size()], Color.WHITE)
	assert_ne(preview._rig.scale, Vector3.ONE, "the flourish just kicked off a pop")


func test_character_preview_flourish_is_skipped_under_reduced_motion() -> void:
	var preview: CharacterPreview = lobby.get_node("%CharacterPreview")
	var ids := CharacterRoster.ids()
	preview.show_character(ids[0], Color.WHITE)
	preview._rig.scale = Vector3.ONE
	ArenaFX.reduced_motion = true
	preview.show_character(ids[1 % ids.size()], Color.WHITE)
	assert_eq(preview._rig.scale, Vector3.ONE, "no pop under reduced motion")


# --- Practice-bot host controls (#577) ---


func test_bot_controls_are_built_beside_the_start_button() -> void:
	assert_not_null(lobby._add_bot_button, "add-bot button exists")
	assert_not_null(lobby._remove_bot_button, "remove-bot button exists")
	assert_string_contains(lobby._add_bot_button.text, "Bot")
	assert_eq(
		lobby._add_bot_button.get_parent(),
		lobby._start_button.get_parent(),
		"lives in the host control cluster"
	)


func test_bot_controls_are_host_only_and_lobby_only() -> void:
	lobby._refresh_bot_controls({"members": []}, false, false)
	assert_false(lobby._add_bot_button.visible, "non-host never sees them")
	lobby._refresh_bot_controls({"members": []}, true, true)
	assert_false(lobby._add_bot_button.visible, "hidden once in a match")
	lobby._refresh_bot_controls({"members": []}, true, false)
	assert_true(lobby._add_bot_button.visible, "host sees them in the lobby")


func test_remove_bot_enables_only_when_a_bot_is_present() -> void:
	lobby._refresh_bot_controls({"members": [{"is_bot": false}]}, true, false)
	assert_true(lobby._remove_bot_button.disabled, "nothing to remove")
	lobby._refresh_bot_controls({"members": [{"is_bot": false}, {"is_bot": true}]}, true, false)
	assert_false(lobby._remove_bot_button.disabled, "a bot can be removed")


func test_add_bot_disables_at_the_cap() -> void:
	var full: Array = []
	for i in NetConfig.MAX_PLAYERS_PER_ROOM:
		full.append({"is_bot": i > 0})
	lobby._refresh_bot_controls({"members": full}, true, false)
	assert_true(lobby._add_bot_button.disabled, "no room for another bot")


## #812: the host-only "play all games in order" toggle, built above the
## per-game exclusion list, reflects the broadcast flag and freezes off-host.
func test_debug_all_games_toggle_built_and_reflects_state() -> void:
	assert_not_null(lobby._debug_all_games_toggle, "the debug toggle exists")
	assert_eq(
		lobby._debug_all_games_toggle.get_parent(),
		lobby._games_box,
		(
			"lives in GamesBox, not inside the GamesScroll ScrollContainer (#1032: a "
			+ "second child there renders stacked under GameToggles at the same "
			+ "scrolled position, making the toggle invisible in practice)"
		),
	)
	assert_true(
		lobby._debug_all_games_toggle.get_index() < lobby._game_toggles.get_parent().get_index(),
		"sits above the scrollable games list, not after it",
	)
	lobby._sync_debug_toggle({"debug_all_games": true}, true)
	assert_true(lobby._debug_all_games_toggle.button_pressed, "reflects the broadcast")
	assert_false(lobby._debug_all_games_toggle.disabled, "host edits it in the lobby")
	lobby._sync_debug_toggle({"debug_all_games": true}, false)
	assert_true(lobby._debug_all_games_toggle.disabled, "frozen off-host / in match")
	lobby._sync_debug_toggle({}, true)
	assert_false(lobby._debug_all_games_toggle.button_pressed, "defaults off when absent")


## #581: the color-swatch picker row.
func test_builds_one_color_swatch_per_palette_color() -> void:
	assert_eq(
		lobby._color_swatches.size(), PlayerPalette.COLORS.size(), "a swatch per palette color"
	)


func test_sync_dims_colors_taken_by_other_members() -> void:
	var saved_slot := NetManager.my_slot
	NetManager.my_slot = 0
	# Slot 1 picked index 5; slot 0 (me) has no pick, so I effectively show 0.
	lobby._sync_color_swatches(
		{"members": [{"slot": 0, "color_index": -1}, {"slot": 1, "color_index": 5}]}, true
	)
	assert_lt(lobby._color_swatches[5].modulate.a, 1.0, "a colour taken by another dims")
	assert_false(bool(lobby._color_swatches[5].get_meta(&"pickable")), "and can't be picked")
	assert_eq(lobby._color_swatches[0].modulate.a, 1.0, "my own colour stays available")
	assert_true(bool(lobby._color_swatches[1].get_meta(&"pickable")), "a free colour is pickable")
	NetManager.my_slot = saved_slot


func test_sync_freezes_the_row_in_match() -> void:
	var saved_slot := NetManager.my_slot
	NetManager.my_slot = 0
	lobby._sync_color_swatches({"members": [{"slot": 0, "color_index": -1}]}, false)
	for swatch: ColorRect in lobby._color_swatches:
		assert_false(bool(swatch.get_meta(&"pickable")), "nothing is pickable in-match")
	NetManager.my_slot = saved_slot
