extends GutTest
## Pickpocket Plaza client view (M10-14): renders replicated snapshots without
## simulating anything locally. The disguise is only ever resolved from the
## local player's own private_state (or the end reveal) — a thief's client
## must not be able to point at the guard mid-round.

var view: MinigameView


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/pickpocket_plaza/pickpocket_plaza_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob", 2: "Carol", 3: "Dave"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"pickpocket_plaza"),
		"res://src/minigames/pickpocket_plaza/pickpocket_plaza_view.tscn"
	)


func test_render_replaces_replicated_state() -> void:
	(
		view
		. render(
			{
				"crowd": [[1.0, 2.0], [3.0, 4.0]],
				"thieves": {1: [0.0, 0.0, 0, 0]},
				"guard": 0,
				"scores": {0: 3, 1: 2},
				"alarm": false,
				"time_left": 40.0,
			}
		)
	)
	assert_eq(view.crowd.size(), 2)
	assert_eq(view.thieves.size(), 1)
	assert_eq(view.guard, 0)
	view.render({"crowd": [], "thieves": {}})
	assert_eq(view.crowd.size(), 0, "each snapshot fully replaces the last")
	assert_eq(view.thieves.size(), 0)


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.crowd.size(), 0)
	assert_eq(view.guard, -1)
	assert_eq(view.reveal, {})


## The load-bearing secrecy check on the client: without a private role and
## before the reveal, the view cannot resolve which body is the guard.
func test_thief_client_cannot_point_at_the_guard() -> void:
	view.private_state = {}
	view.render({"crowd": [[0.0, 0.0], [1.0, 1.0]], "guard": 0})
	assert_eq(view._guard_body_index(), -1, "a thief's client never learns the disguise")


func test_guard_client_knows_its_own_body() -> void:
	view.private_state = {"role": "guard", "body": 2}
	view.render({"crowd": [[0.0, 0.0], [1.0, 1.0], [2.0, 2.0]], "guard": 0})
	assert_eq(view._guard_body_index(), 2, "the guard's own client rings its body")


func test_reveal_exposes_the_guard_body_to_everyone() -> void:
	view.private_state = {}
	view.render({"crowd": [[0.0, 0.0], [1.0, 1.0]], "guard": 3, "reveal": {"guard": 3, "body": 1}})
	assert_eq(view._guard_body_index(), 1, "the reveal marks the body for the whole table")
	assert_eq(int(view.reveal.guard), 3)


## An arrest is a public commotion: the alarm's rising edge spawns one pulse
## (positioned where the local client can place it), and a held alarm is quiet.
func test_alarm_rising_edge_pulses_once() -> void:
	view.private_state = {"role": "guard", "body": 0}
	view.render({"crowd": [[0.0, 0.0]], "alarm": false})
	assert_eq(view._pulses.size(), 0)
	view.render({"crowd": [[0.0, 0.0]], "alarm": true})
	assert_eq(view._pulses.size(), 1, "the commotion pulses once")
	view.render({"crowd": [[0.0, 0.0]], "alarm": true})
	assert_eq(view._pulses.size(), 1, "a held alarm stays quiet")


func test_pulses_expire() -> void:
	view.private_state = {"role": "guard", "body": 0}
	view.render({"crowd": [[0.0, 0.0]], "alarm": false})
	view.render({"crowd": [[0.0, 0.0]], "alarm": true})
	assert_eq(view._pulses.size(), 1)
	view._process(1.1)
	assert_eq(view._pulses.size(), 0, "commotion rings free themselves")
