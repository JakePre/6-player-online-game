extends GutTest
## MinigameView base behavior (#486): play_sfx() fires AudioManager and also
## emits sfx_requested, the same pattern shake_requested already established
## for request_shake — so per-game view tests can verify a snapshot
## transition triggered the expected sound without mocking AudioManager.

var view: MinigameView3D


func before_each() -> void:
	# Any MinigameView3D scene will do — King of the Hill's is a plain,
	# already-tested fixture with no extra setup requirements.
	var scene: PackedScene = load("res://src/minigames/king_of_the_hill/king_of_the_hill_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice"}, 0)


func test_play_sfx_emits_sfx_requested_with_the_name() -> void:
	watch_signals(view)
	view.play_sfx(&"coin")
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"coin"])
