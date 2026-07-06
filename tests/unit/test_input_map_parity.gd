extends GutTest
## Regression guard (M17-05, #651): every gameplay action in project.godot's
## input map keeps at least one keyboard event AND at least one gamepad
## event. A future edit that drops one side (e.g. a rebind default that
## erases the factory gamepad event, or a new action added keyboard-only)
## breaks "playable gamepad-only and keyboard-only" (M12-05/M17-02) silently
## until a human notices on a pad — this catches it in CI instead.
##
## Cross-checked against SettingsStore.REBINDABLE_ACTIONS/REBINDABLE_PAD_ACTIONS
## (the factory defaults the remap UI resets to) so the two sources of truth
## can't drift apart either.

## The gameplay actions every minigame/screen shares — project.godot's actual
## [input] map, not a guess. Kept as a literal list (not InputMap.get_actions(),
## which also returns Godot's built-in ui_* actions) so this test asserts on
## exactly the actions the remap UI and every game care about.
const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"action_primary",
	&"action_secondary",
	&"emote",
]


func test_every_gameplay_action_exists() -> void:
	for action in GAMEPLAY_ACTIONS:
		assert_true(InputMap.has_action(action), "%s is a real action" % action)


func test_every_gameplay_action_has_a_keyboard_event() -> void:
	for action in GAMEPLAY_ACTIONS:
		var events := InputMap.action_get_events(action)
		var has_key := events.any(func(e: InputEvent) -> bool: return e is InputEventKey)
		assert_true(has_key, "%s keeps a keyboard binding" % action)


func test_every_gameplay_action_has_a_gamepad_event() -> void:
	for action in GAMEPLAY_ACTIONS:
		var events := InputMap.action_get_events(action)
		var has_pad := events.any(
			func(e: InputEvent) -> bool:
				return e is InputEventJoypadButton or e is InputEventJoypadMotion
		)
		assert_true(has_pad, "%s keeps a gamepad binding" % action)


## The remap UI's factory keyboard map (SettingsStore.REBINDABLE_ACTIONS) must
## cover exactly the same actions project.godot declares — a new action added
## to one and not the other silently loses either remapping or the base
## binding.
func test_rebindable_keyboard_map_matches_the_gameplay_actions() -> void:
	var rebindable: Array[StringName] = []
	for action: String in SettingsStore.REBINDABLE_ACTIONS:
		rebindable.append(StringName(action))
	for action in GAMEPLAY_ACTIONS:
		assert_true(action in rebindable, "%s is remappable on keyboard" % action)
	for action in rebindable:
		assert_true(action in GAMEPLAY_ACTIONS, "%s is a real gameplay action" % action)


## Same check for the M17-03 gamepad remap map.
func test_rebindable_pad_map_matches_the_gameplay_actions() -> void:
	var rebindable: Array[StringName] = []
	for action: String in SettingsStore.REBINDABLE_PAD_ACTIONS:
		rebindable.append(StringName(action))
	for action in GAMEPLAY_ACTIONS:
		assert_true(action in rebindable, "%s is remappable on gamepad" % action)
	for action in rebindable:
		assert_true(action in GAMEPLAY_ACTIONS, "%s is a real gameplay action" % action)
