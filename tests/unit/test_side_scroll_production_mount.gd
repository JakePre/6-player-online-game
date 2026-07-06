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
	# The discriminating assert (#575 follow-up): on the pre-fix code the
	# null-layer call aborts INSIDE _make_platform() and a null is appended —
	# so size-only asserts stay green while the stage renders nothing. The
	# panel must be a real object, checked BEFORE _ready() can paper over it.
	assert_eq(view._platform_nodes.size(), 1, "stage built with lazily-ensured layers")
	assert_not_null(view._platform_nodes[0], "the panel is real, not a null from an aborted build")
	add_child_autofree(view)


func test_each_game_view_survives_setup_before_ready() -> void:
	for id: String in GAME_SCENES:
		var entry: Dictionary = GAME_SCENES[id]
		var scene: PackedScene = load(entry.scene)
		var view: SideScrollView = scene.instantiate()
		# Production order: configure the view fully, THEN mount it.
		view.setup({0: "Alice", 1: "Bob"}, 0)
		# Discriminating asserts BEFORE mounting: post-mount, the old broken
		# _ready() built the layers anyway, so only the pre-mount nulls (from
		# aborted _make_platform calls) betray the regression.
		assert_gt(view._platform_nodes.size(), 0, "%s built its stage before _ready" % id)
		assert_not_null(view._platform_nodes[0], "%s panels are real, not aborted nulls" % id)
		if id == "tumble_run":
			# The consumer-side variant: crumble panels parent to Tumble Run's
			# own _ready()-era _fx_layer; a regression leaves null values here.
			assert_gt(view._crumble_nodes.size(), 0, "crumble panels built before _ready")
			assert_not_null(view._crumble_nodes.values()[0], "crumble panels are real")
		add_child_autofree(view)
		view.size = Vector2(800.0, 600.0)
		# A render on the now-mounted view must not crash either.
		view.render({"players": {0: entry.sample}})
		assert_not_null(view.rig_for_slot(0), "%s rendered a rig after production mount" % id)
