extends GutTest
## Regression for #575: side-scroll views must survive the PRODUCTION mount
## order. match_screen._mount_view() calls setup() (→ _setup → setup_stage)
## BEFORE add_child fires _ready(). Every per-game view test mounts in the
## reverse order (add_child_autofree then setup), which hid a null-layer
## crash that took all three side-scroll games to desktop at round start.
## These mount the way production does.

const GAME_SCENES := {
	"loadout_duel":
	{
		"scene": "res://src/minigames/loadout_duel/loadout_duel_view.tscn",
		"sample": [0.0, 0.5, 1, 1, 0],
	},
	"knock_off":
	{
		"scene": "res://src/minigames/knock_off/knock_off_view.tscn",
		"sample": [0.0, 0.5, 1, 1, 0, 0],
	},
	"tumble_run":
	{"scene": "res://src/minigames/tumble_run/tumble_run_view.tscn", "sample": [0.0, 0.5, 1, 0]},
}


func test_base_builds_layers_when_setup_stage_precedes_ready() -> void:
	var view := SideScrollView.new()
	# setup() runs the MinigameView contract; then a subclass would call
	# setup_stage() from _setup — here we call it directly, all BEFORE the
	# node is in the tree (i.e. before _ready).
	view.setup({0: "Alice"}, 0)
	view.setup_stage(
		[Rect2(-5.0, -1.0, 10.0, 1.0)] as Array[Rect2], [] as Array[Rect2], Rect2(-6, -2, 12, 10)
	)
	add_child_autofree(view)
	assert_eq(view._platform_nodes.size(), 1, "stage built with lazily-ensured layers")
	# The discriminating check (credit #597): on the broken code _make_platform()
	# still returns a Panel and it still gets appended — just never parented,
	# because add_child ran on a null layer. Count alone passes on the bug; a
	# real *parented* node under the layer is what proves the fix.
	var panel: Node = view._platform_nodes[0]
	assert_true(is_instance_valid(panel), "the platform is a real node")
	assert_not_null(
		panel.get_parent(), "and it is actually parented (not orphaned by a null layer)"
	)


func test_each_game_view_survives_setup_before_ready() -> void:
	for id: String in GAME_SCENES:
		var entry: Dictionary = GAME_SCENES[id]
		var scene: PackedScene = load(entry.scene)
		var view: SideScrollView = scene.instantiate()
		# Production order: configure the view fully, THEN mount it.
		view.setup({0: "Alice", 1: "Bob"}, 0)
		add_child_autofree(view)
		view.size = Vector2(800.0, 600.0)
		assert_gt(view._platform_nodes.size(), 0, "%s built its stage before _ready" % id)
		# Parented, not just present (credit #597): the null-layer bug leaves
		# these orphaned, so the count passes on the broken build but the parent
		# check does not.
		var panel: Node = view._platform_nodes[0]
		assert_not_null(panel.get_parent(), "%s parented its platforms to a real layer" % id)
		# A render on the now-mounted view must not crash either.
		view.render({"players": {0: entry.sample}})
		var rig: Node = view.rig_for_slot(0)
		assert_not_null(rig, "%s rendered a rig after production mount" % id)
		assert_not_null(rig.get_parent(), "%s parented the rig to the rig layer" % id)
