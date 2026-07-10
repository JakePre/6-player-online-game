extends GutTest
## Treasure Divers client view (M10-04): renders replicated snapshots in the
## shared iso-arena without simulating anything locally.

const VIEW_SCENE := preload("res://src/minigames/treasure_divers/treasure_divers_view.tscn")

var view: MinigameView


func _player(x: float, y: float, coin_count: int, dive: int, air: float, stun: float) -> Array:
	return [x, y, coin_count, dive, air, stun]


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	MinigameCatalog.clear()
	MinigameCatalog.register_builtins()
	assert_eq(
		MinigameCatalog.view_scene_path(&"treasure_divers"),
		"res://src/minigames/treasure_divers/treasure_divers_view.tscn"
	)


## M15: the view derives its floor/camera size from the lobby count with the
## same formula the sim uses, so the rendered arena matches the scaled one.
func test_arena_half_scales_with_lobby_size() -> void:
	assert_almost_eq(view._arena_half(), TreasureDivers.ARENA_HALF, 0.001, "2 players = base arena")
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	var names := {}
	for i in 12:
		names[i] = "P%d" % (i + 1)
	big.setup(names, 0)
	assert_gt(big._arena_half(), TreasureDivers.ARENA_HALF, "12 players get a bigger floor")


## #588: the arena reads as a pool — a tinted floor overlay plus a deck border
## framing the swim area — instead of the generic shared floor tile.
func test_pool_floor_and_deck_border_dress_the_arena() -> void:
	var tint: MeshInstance3D = view.arena.get_node("PoolFloorTint")
	assert_not_null(tint)
	var material: StandardMaterial3D = tint.mesh.material
	assert_eq(material.albedo_color, view.POOL_FLOOR_COLOR)
	for i in 4:
		assert_not_null(view.arena.get_node("Deck%d" % i), "plank %d frames the pool" % i)


## #782: the basin has walls on all four edges (the back no longer opens onto
## nothing), and they rise from the seabed up to the water line.
func test_pool_has_enclosing_walls() -> void:
	for i in 4:
		var wall: MeshInstance3D = view.arena.get_node("Wall%d" % i)
		assert_not_null(wall, "wall %d encloses the basin" % i)
		assert_almost_eq(
			(wall.mesh as BoxMesh).size.y, view.SURFACE_HEIGHT, 0.001, "the wall reaches the water"
		)
		assert_almost_eq(
			wall.position.y, view.SURFACE_HEIGHT / 2.0, 0.001, "rising from the seabed"
		)


## #782: the coping/deck sits at the water line, not flat on the seabed — that
## was the "frame is at floor level, not water level" complaint.
func test_deck_coping_sits_at_the_water_line() -> void:
	for i in 4:
		var plank: MeshInstance3D = view.arena.get_node("Deck%d" % i)
		assert_almost_eq(
			plank.position.y, view.SURFACE_HEIGHT, 0.001, "the rim is raised to water level"
		)


func test_surfaced_rigs_swim_high_and_divers_sink() -> void:
	assert_not_null(view.arena.get_node("WaterSurface"))
	view.render(
		{
			"players":
			{0: _player(1.0, 2.0, 0, 0, 1.0, 0.0), 1: _player(-1.0, -2.0, 0, 1, 0.5, 0.0)},
			"treasure": []
		}
	)
	assert_almost_eq(view.rig_for_slot(0).position.y, view.SURFACE_HEIGHT, 0.001, "swimmer on top")
	assert_almost_eq(view.rig_for_slot(1).position.y, 0.0, 0.001, "diver on the seabed")


## #235: air is a hovering bar fed from the replicated fraction; the ASCII
## meter no longer rides the nameplate.
func test_air_bar_tracks_the_replicated_fraction() -> void:
	view.render({"players": {0: _player(0.0, 0.0, 4, 1, 1.0, 0.0)}, "treasure": []})
	assert_string_contains(view.rig_for_slot(0).display_name, "4")
	assert_false("|" in view.rig_for_slot(0).display_name, "no ASCII meter on the plate")
	assert_almost_eq(float(view._air_seen[0]), 1.0, 0.001)
	assert_true(view._air_bars.has(0), "a bar exists for the slot")
	view.render({"players": {0: _player(0.0, 0.0, 4, 1, 0.35, 0.0)}, "treasure": []})
	assert_almost_eq(float(view._air_seen[0]), 0.35, 0.001)


func test_fresh_blackout_flinches_and_shakes() -> void:
	watch_signals(view)
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 0.1, 0.0)}, "treasure": []})
	assert_signal_not_emitted(view, "shake_requested")
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 0.0, 2.5)}, "treasure": []})
	assert_signal_emitted(view, "shake_requested")
	assert_eq(view.rig_for_slot(0).current_action(), &"hit")
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 0.0, 2.4)}, "treasure": []})
	assert_signal_emit_count(view, "shake_requested", 1, "ongoing stun does not re-shake")


func test_treasure_pool_tracks_snapshot() -> void:
	view.render({"players": {}, "treasure": [[3.0, -4.0]]})
	var coin: MeshInstance3D = view.arena.get_node("Treasure0")
	assert_true(coin.visible)
	assert_almost_eq(coin.position.x, 3.0, 0.001)
	assert_false(view.arena.get_node("Treasure1").visible)
	view.render({"players": {}, "treasure": []})
	assert_false(coin.visible, "collected treasure disappears")


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.treasure.size(), 0)


## M13-10: surface crossings splash, divers bubble, blackouts burst — all
## seeded so a rejoiner's first snapshot stays dry.
func test_surface_crossings_splash_once_seeded() -> void:
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 1.0, 0.0)}, "treasure": []})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: _player(0.0, 0.0, 0, 1, 1.0, 0.0)}, "treasure": []})
	assert_gte(view.arena.get_child_count(), before + 1, "dive-in splashes")
	var mid: int = view.arena.get_child_count()
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 0.8, 0.0)}, "treasure": []})
	assert_eq(view.arena.get_child_count(), mid + 1, "surfacing splashes too")


func test_divers_trail_bubbles_on_a_cadence() -> void:
	view.render({"players": {0: _player(0.0, 0.0, 0, 1, 1.0, 0.0)}, "treasure": []})
	var start: int = view.arena.get_child_count()
	var renders_per_bubble := int(ceil(view.BUBBLE_EVERY_SEC / view.SNAPSHOT_INTERVAL))
	for _i in renders_per_bubble + 1:
		view.render({"players": {0: _player(0.0, 0.0, 0, 1, 0.5, 0.0)}, "treasure": []})
	assert_gt(view.arena.get_child_count(), start, "bubbles while under")


func test_blackout_adds_a_surface_burst() -> void:
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 0.1, 0.0)}, "treasure": []})
	var before: int = view.arena.get_child_count()
	view.render({"players": {0: _player(0.0, 0.0, 0, 0, 0.0, 2.5)}, "treasure": []})
	assert_eq(view.arena.get_child_count(), before + 1, "gasp splash at the surface")
