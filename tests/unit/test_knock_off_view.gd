extends GutTest
## Knock-Off client view (M14-03): renders replicated brawl snapshots on the
## side-scroll base — stage, damage-percent nameplates, swing flashes, KO
## chrome — without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/knock_off/knock_off_view.tscn")

var view: SideScrollView
var _saved_show_names := false


func before_each() -> void:
	_saved_show_names = MinigameView.show_names
	MinigameView.show_names = true  # #580: names off by default; this suite tests the name itself
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(960.0, 540.0)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func after_each() -> void:
	MinigameView.show_names = _saved_show_names


func _fighter(x: float, y: float, facing: int, alive: int, percent: int, attack: int) -> Array:
	return [x, y, facing, alive, percent, attack]


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"knock_off"),
		"res://src/minigames/knock_off/knock_off_view.tscn"
	)


func test_setup_builds_the_shared_stage() -> void:
	var expected := KnockOff.solid_platforms().size() + KnockOff.one_way_platforms().size()
	assert_eq(view._platform_nodes.size(), expected)


func test_nameplate_shows_damage_percent() -> void:
	view.render(
		{
			"players": {0: _fighter(0.0, 0.5, 1, 1, 47, 0)},
			"phase": KnockOff.Phase.FIGHT,
			"phase_left": 40.0
		}
	)
	var plate: Label = view.rig_for_slot(0).get_node("Plate")
	assert_string_contains(plate.text, "Alice")
	assert_string_contains(plate.text, "47%")


func test_downed_fighter_is_greyed() -> void:
	view.render(
		{
			"players": {0: _fighter(-2.0, 0.5, 1, 1, 0, 0), 1: _fighter(2.0, 0.5, -1, 0, 60, 0)},
			"phase": KnockOff.Phase.FIGHT
		}
	)
	assert_eq(view.rig_for_slot(0).modulate, Color.WHITE, "the living render bright")
	assert_ne(view.rig_for_slot(1).modulate, Color.WHITE, "the downed are greyed")


func test_attack_spawns_a_transient_swing() -> void:
	view.render({"players": {0: _fighter(0.0, 0.5, 1, 1, 0, 1)}, "phase": KnockOff.Phase.FIGHT})
	assert_eq(view._swings.size(), 1, "a jab flashes a swing")
	view._process(KnockOff.ATTACK_HALF_HEIGHT)  # long enough to expire
	assert_eq(view._swings.size(), 0, "the swing fades")


func test_ko_edge_shakes_and_stings_once_seeded() -> void:
	watch_signals(view)
	view.render({"players": {0: _fighter(0.0, 0.5, 1, 1, 80, 0)}, "phase": KnockOff.Phase.FIGHT})
	assert_signal_not_emitted(view, "shake_requested", "seeding snapshot is calm")
	view.render({"players": {0: _fighter(0.0, 0.5, 1, 0, 80, 0)}, "phase": KnockOff.Phase.FIGHT})
	assert_signal_emitted(view, "shake_requested")
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"ko"])


func test_hud_counts_the_survivors() -> void:
	view.render(
		{
			"players": {0: _fighter(0.0, 0.5, 1, 1, 0, 0), 1: _fighter(2.0, 0.5, 1, 1, 0, 0)},
			"phase": KnockOff.Phase.FIGHT
		}
	)
	assert_string_contains(view._hud.text, "2 left")


## #789: an attack pops a quick squash-lunge on the attacker's own body, on
## top of the arc flash — the rig itself reads as swinging, not just the FX.
func test_swing_pops_a_lunge_that_settles_back() -> void:
	view.render({"players": {0: _fighter(0.0, 0.5, 1, 1, 0, 1)}, "phase": KnockOff.Phase.FIGHT})
	var body: Panel = view.rig_for_slot(0).get_node("Body")
	view._process(view.SWING_POSE_SEC * 0.5)
	assert_ne(body.scale, Vector2.ONE, "mid-lunge the body is off its rest scale")
	view._process(view.SWING_POSE_SEC)
	assert_eq(body.scale, Vector2.ONE, "the lunge settles back out")


## #789/#1038: a landed hit flashes the victim red through the shared
## SideScrollView.play_hit surface, pose-protected until its window elapses.
func test_landing_a_hit_flashes_the_victim() -> void:
	view.render({"players": {0: _fighter(0.0, 0.5, 1, 1, 0, 0)}, "phase": KnockOff.Phase.FIGHT})
	view.render({"players": {0: _fighter(0.0, 0.5, 1, 1, 20, 0)}, "phase": KnockOff.Phase.FIGHT})
	var rig := view.rig_for_slot(0)
	assert_ne(rig.modulate, Color.WHITE, "the landed hit flashes the victim")
	assert_true(view.is_hit_playing(0), "the flinch window protects the flash from the WHITE reset")
	# Once the flinch window elapses, the next render clears back to normal.
	view._hit_until[0] = 0.0
	view.render({"players": {0: _fighter(0.0, 0.5, 1, 1, 20, 0)}, "phase": KnockOff.Phase.FIGHT})
	assert_eq(rig.modulate, Color.WHITE, "after the flinch window the rig reads normal again")


## #789: the sim frees a KO'd body immediately (test_falling_off_the_stage_is_a_ko
## in test_knock_off.gd), so every post-death snapshot reports (0, 0) — the
## view must not teleport the corpse to stage center. It tumbles from its
## last real pose instead, then disappears once the tumble finishes.
func test_ko_tumbles_from_its_last_pose_instead_of_teleporting_to_origin() -> void:
	view.render({"players": {0: _fighter(4.0, 0.5, 1, 1, 80, 0)}, "phase": KnockOff.Phase.FIGHT})
	view.render({"players": {0: _fighter(0.0, 0.0, 1, 0, 80, 0)}, "phase": KnockOff.Phase.FIGHT})
	var rig := view.rig_for_slot(0)
	view._process(0.1)
	assert_ne(
		rig.position, view.world_to_screen(Vector2.ZERO), "does not snap to the wire's dead (0, 0)"
	)
	view._process(view.KO_TUMBLE_SEC)
	assert_false(rig.visible, "the tumble finishes by hiding the rig for good")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
