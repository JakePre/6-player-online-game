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


## #576: a long banner (e.g. Faulty Wiring's role line) must stay centered
## on the viewport instead of growing off the right edge — the bug was the
## default grow direction on a bottom-center-anchored zero-size label.
func test_long_banner_text_stays_horizontally_centered() -> void:
	var label := view.make_banner(&"TestBanner")
	label.text = "You are the SABOTEUR — cut the wires before they're repaired!"
	await wait_frames(1)
	var viewport_width: float = view.get_viewport_rect().size.x
	var center := viewport_width / 2.0
	var label_center := label.position.x + label.size.x / 2.0
	assert_almost_eq(
		label_center, center, 2.0, "long text stays centered, not clipped off one side"
	)
