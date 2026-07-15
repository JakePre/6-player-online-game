extends GutTest
## Declarative INPUT_ACTIONS machinery on MinigameView (#947): the pure
## event→payload mapping (edge press / held release) and the const reflection.
## The mapping is tested directly by seeding the cache, so it needs no real
## game; the reflection is tested against a converted view's real const.

const DODGEBALL_SCENE := preload("res://src/minigames/dodgeball/dodgeball_view.tscn")
const LASER_LIMBO_SCENE := preload("res://src/minigames/laser_limbo/laser_limbo_view.tscn")


func _view_with_actions(actions: Dictionary) -> MinigameView:
	var view := MinigameView.new()
	add_child_autofree(view)
	# Seed the cache directly so the mapping is tested without reflection.
	view._input_actions_cache = actions
	view._input_actions_resolved = true
	return view


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _release(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = false
	return event


func test_edge_press_fires_a_single_true_flag() -> void:
	var view := _view_with_actions({&"action_primary": "jump"})
	assert_eq(view.input_sends_for_event(_press(&"action_primary")), [{"jump": true}])


func test_unmapped_action_fires_nothing() -> void:
	var view := _view_with_actions({&"action_primary": "jump"})
	assert_eq(
		view.input_sends_for_event(_press(&"move_up")), [], "an action not in the map is ignored"
	)


func test_release_of_a_plain_action_fires_nothing() -> void:
	var view := _view_with_actions({&"action_primary": "jump"})
	assert_eq(
		view.input_sends_for_event(_release(&"action_primary")),
		[],
		"a non-held action only fires on press, never release"
	)


func test_held_action_fires_true_on_press_and_false_on_release() -> void:
	var view := _view_with_actions({&"action_secondary": {"key": "duck", "held": true}})
	assert_eq(view.input_sends_for_event(_press(&"action_secondary")), [{"duck": true}])
	assert_eq(view.input_sends_for_event(_release(&"action_secondary")), [{"duck": false}])


func test_multiple_actions_each_map_independently() -> void:
	var view := _view_with_actions(
		{&"action_primary": "jump", &"action_secondary": {"key": "duck", "held": true}}
	)
	assert_eq(view.input_sends_for_event(_press(&"action_primary")), [{"jump": true}])
	assert_eq(view.input_sends_for_event(_press(&"action_secondary")), [{"duck": true}])


func test_empty_map_fires_nothing() -> void:
	var view := _view_with_actions({})
	assert_eq(view.input_sends_for_event(_press(&"action_primary")), [])


## A view with no INPUT_ACTIONS const resolves to an empty map (the base
## MinigameView declares none).
func test_missing_const_resolves_to_empty() -> void:
	var view := MinigameView.new()
	add_child_autofree(view)
	assert_eq(view.input_actions(), {}, "no const declared -> empty map")


## Reflection reaches a real subclass const: dodgeball declares one action.
func test_reflection_reads_a_subclass_const() -> void:
	var view: MinigameView = DODGEBALL_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice"}, 0)
	assert_eq(view.input_actions(), {&"action_primary": "act"}, "reads dodgeball's INPUT_ACTIONS")


## End-to-end through the real const: laser_limbo's held-duck spec produces the
## press/release pair its hand-rolled _unhandled_input used to.
func test_laser_limbo_held_duck_maps_through_the_real_const() -> void:
	var view: MinigameView = LASER_LIMBO_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice"}, 0)
	assert_eq(view.input_sends_for_event(_press(&"action_primary")), [{"jump": true}])
	assert_eq(view.input_sends_for_event(_press(&"action_secondary")), [{"duck": true}])
	assert_eq(view.input_sends_for_event(_release(&"action_secondary")), [{"duck": false}])
