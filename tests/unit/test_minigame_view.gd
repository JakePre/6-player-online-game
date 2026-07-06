extends GutTest
## MinigameView base behavior (#486): play_sfx() fires AudioManager and also
## emits sfx_requested, the same pattern shake_requested already established
## for request_shake — so per-game view tests can verify a snapshot
## transition triggered the expected sound without mocking AudioManager.

var view: MinigameView3D
var _saved_show_names := false


func before_each() -> void:
	_saved_show_names = MinigameView.show_names
	# Any MinigameView3D scene will do — King of the Hill's is a plain,
	# already-tested fixture with no extra setup requirements.
	var scene: PackedScene = load("res://src/minigames/king_of_the_hill/king_of_the_hill_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice"}, 0)


func after_each() -> void:
	MinigameView.show_names = _saved_show_names


func test_play_sfx_emits_sfx_requested_with_the_name() -> void:
	watch_signals(view)
	view.play_sfx(&"coin")
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"coin"])


## #580: nameplates off by default — player_name() falls back to just the
## number badge until show_names is switched on.
func test_player_name_respects_the_show_names_flag() -> void:
	MinigameView.show_names = false
	assert_eq(view.player_name(0), "P1", "off shows just the number badge")
	MinigameView.show_names = true
	assert_eq(view.player_name(0), "P1 Alice", "on joins the chosen name")


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
