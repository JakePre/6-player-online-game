extends GutTest
## Shared arena FX (M13-01): every helper returns a configured one-shot,
## self-freeing CPUParticles3D parented where asked.

var root: Node3D


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)


func test_burst_is_a_configured_one_shot() -> void:
	var fx := ArenaFX.burst(root, Vector3(1.0, 0.5, -2.0), Color.RED, 24, 6.0, 0.7)
	assert_eq(fx.get_parent(), root)
	assert_true(fx.one_shot)
	assert_true(fx.emitting)
	assert_eq(fx.amount, 24)
	assert_almost_eq(fx.lifetime, 0.7, 0.001)
	assert_eq(fx.color, Color.RED)
	assert_almost_eq(fx.position.x, 1.0, 0.001)
	assert_almost_eq(fx.explosiveness, 1.0, 0.001)


func test_presets_shape_their_motion() -> void:
	var sparkle := ArenaFX.sparkle(root, Vector3.ZERO)
	assert_gt(sparkle.gravity.y, 0.0, "sparkles drift upward")
	var splash := ArenaFX.splash(root, Vector3.ZERO)
	assert_gt(splash.flatness, 0.0, "splashes flatten into a ring")
	assert_lt(splash.gravity.y, 0.0, "splash droplets fall back")
	var dust := ArenaFX.dust(root, Vector3.ZERO)
	assert_lt(dust.initial_velocity_max, 2.0, "dust billows, never flies")


func test_effects_free_themselves_when_finished() -> void:
	var fx := ArenaFX.burst(root, Vector3.ZERO)
	fx.finished.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(fx), "finished one-shots clean themselves up")


func test_view_wrappers_parent_into_the_arena() -> void:
	var scene: PackedScene = load("res://src/minigames/king_of_the_hill/king_of_the_hill_view.tscn")
	var view: MinigameView = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice"}, 0)
	var before: int = view.arena.get_child_count()
	view.fx_burst(Vector2(2.0, 3.0), Color.WHITE)
	view.fx_sparkle(Vector2(0.0, 0.0), Color.YELLOW)
	view.fx_splash(Vector2(1.0, 1.0))
	view.fx_dust(Vector2(-1.0, -1.0))
	assert_eq(view.arena.get_child_count(), before + 4)
	var burst: CPUParticles3D = view.arena.get_child(before)
	assert_almost_eq(burst.position.x, 2.0, 0.001)
	assert_almost_eq(burst.position.z, 3.0, 0.001)
	assert_almost_eq(burst.position.y, 0.5, 0.001, "default burst height")
