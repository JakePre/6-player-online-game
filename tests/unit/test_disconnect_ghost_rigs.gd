extends GutTest
## Regression for #601 (M18-02): a disconnected member keeps its seat in
## `names` for rejoin, but must not leave a frozen 'ghost' rig standing in
## every subsequent round. MinigameView3D pools rigs hidden and reveals a
## slot's rig only when a round actually uses it (update_rig / reveal_rig);
## the 2D tier builds rigs lazily per snapshot, so it's ghost-free by design.

const KOTH_SCENE := "res://src/minigames/king_of_the_hill/king_of_the_hill_view.tscn"
const BOWL_SCENE := "res://src/minigames/bullseye_bowl/bullseye_bowl_view.tscn"
const KNOCK_OFF_SCENE := "res://src/minigames/knock_off/knock_off_view.tscn"


func _mount(path: String) -> MinigameView:
	var view: MinigameView = load(path).instantiate()
	add_child_autofree(view)
	# Two members, but slot 1 will "disconnect" (never appears in a snapshot).
	view.setup({0: "Alice", 1: "Ghost"}, 0)
	return view


func test_rigs_pool_hidden_until_a_round_uses_the_slot() -> void:
	var view := _mount(KOTH_SCENE)
	assert_false(view.rig_for_slot(0).visible, "pooled hidden at build")
	assert_false(view.rig_for_slot(1).visible)


func test_only_snapshot_present_slots_reveal_no_ghost() -> void:
	var view := _mount(KOTH_SCENE)
	# Snapshot carries only the connected player; slot 1 disconnected.
	view.render({"players": {0: [1.0, 2.0, 0]}})
	assert_true(view.rig_for_slot(0).visible, "the connected player shows")
	assert_false(view.rig_for_slot(1).visible, "the disconnected slot is no ghost")


func test_slot_reveals_when_it_rejoins_the_snapshot() -> void:
	var view := _mount(KOTH_SCENE)
	view.render({"players": {0: [1.0, 2.0, 0]}})
	assert_false(view.rig_for_slot(1).visible)
	view.render({"players": {0: [1.0, 2.0, 0], 1: [3.0, 4.0, 0]}})
	assert_true(view.rig_for_slot(1).visible, "a rejoiner's rig appears")


func test_reveal_is_one_shot_deliberate_hides_are_not_fought() -> void:
	var view := _mount(KOTH_SCENE)
	view.render({"players": {0: [1.0, 2.0, 0]}})
	# A game hides a rig on its own (KO / elimination), then keeps updating it.
	view.rig_for_slot(0).visible = false
	view.render({"players": {0: [1.5, 2.5, 1]}})
	assert_false(view.rig_for_slot(0).visible, "the framework does not re-reveal")


func test_bullseye_bowl_stationary_rigs_skip_the_ghost() -> void:
	# Bowl places rigs in _setup_3d (not via update_rig) and reveals connected
	# slots in _render_3d via reveal_rig.
	var view := _mount(BOWL_SCENE)
	assert_false(view.rig_for_slot(1).visible, "hidden until a round uses it")
	view.render({"players": {0: [0, 3, -1.0, 0.0]}})
	assert_true(view.rig_for_slot(0).visible, "connected bowler shows")
	assert_false(view.rig_for_slot(1).visible, "disconnected bowler is no ghost")


func test_two_d_tier_never_builds_an_absent_slots_rig() -> void:
	var view := _mount(KNOCK_OFF_SCENE)
	view.size = Vector2(800.0, 600.0)
	view.render({"players": {0: [0.0, 0.5, 1, 1, 0, 0]}})
	assert_not_null(view.rig_for_slot(0), "the connected fighter has a rig")
	assert_null(view.rig_for_slot(1), "the disconnected slot never gets one — ghost-free")
