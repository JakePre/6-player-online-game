extends GutTest
## Simon Stomp client view (#261 polish): pad labels, phase chrome, and
## snapshot rendering without local simulation.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/simon_stomp/simon_stomp_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_pads_carry_readable_labels() -> void:
	# #261: every pad names its direction, key, and color.
	for pad in 4:
		var tag: Label3D = view.arena.get_node("PadLabel%d" % pad)
		assert_true(tag.no_depth_test, "labels read through geometry")
		assert_false(tag.text.is_empty())


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_not_null(view.arena.get_node("Pad0"))
