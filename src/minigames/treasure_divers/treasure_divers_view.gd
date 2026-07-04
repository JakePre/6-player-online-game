extends MinigameView3D
## Treasure Divers client view (M10-04): the seabed is the arena floor with
## the sunken coins on it; a translucent water surface floats above, and rigs
## swim on it or dive below it via update_rig's height (interpolated, so the
## plunge reads as motion, not a teleport). Air is a hovering bar over each
## diver that drains cyan to red (#235 — it was ASCII pipes on the
## nameplate); blacking out plays the hit flinch and shakes the screen.

const SURFACE_HEIGHT := 1.2
const WATER_COLOR := Color(0.2, 0.45, 0.8, 0.35)
const COIN_COLOR := Color(0.96, 0.79, 0.2)
const COIN_RADIUS := 0.3
const COIN_HEIGHT := 0.12
const COIN_POOL := 12
## Oxygen bar over each diver (#235).
const AIR_BAR_STEPS := 8
const AIR_BAR_HEIGHT := 1.35
const AIR_FULL_COLOR := Color(0.3, 0.95, 1.0)
const AIR_EMPTY_COLOR := Color(1.0, 0.25, 0.2)
const COIN_HOVER := 0.4
## Diver water FX (M13-10).
const BUBBLE_COLOR := Color(0.75, 0.9, 1.0)
const BUBBLE_EVERY_SEC := 0.5

## Latest replicated state, straight from TreasureDivers.get_snapshot().
var players := {}
var treasure: Array = []

var _coin_pool: Array[MeshInstance3D] = []
## slot -> Label3D; bars follow the interpolated rigs.
var _air_bars := {}
## slot -> latest replicated air fraction, consumed by the follow pass.
var _air_seen := {}
# slot -> stunned seconds from the previous snapshot, to spot fresh blackouts.
var _stun_seen := {}
# slot -> diving flag from the previous snapshot, for surface-crossing splashes.
var _diving_seen := {}
# slot -> seconds until that diver's next bubble.
var _bubble_left := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Bars ride the rigs every frame (rigs interpolate between snapshots) and
## spin the treasure so it catches the eye.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for slot: int in _air_bars:
		var bar := _air_bars[slot] as Label3D
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		bar.position = Vector3(rig.position.x, rig.position.y + AIR_BAR_HEIGHT, rig.position.z)
		var fraction := clampf(float(_air_seen.get(slot, 1.0)), 0.0, 1.0)
		bar.visible = rig.visible and fraction < 0.999
		var filled := int(roundf(fraction * AIR_BAR_STEPS))
		bar.text = "●".repeat(filled) + "○".repeat(AIR_BAR_STEPS - filled)
		bar.modulate = AIR_EMPTY_COLOR.lerp(AIR_FULL_COLOR, fraction)
	for i in _coin_pool.size():
		if _coin_pool[i].visible:
			_coin_pool[i].rotation = Vector3(PI / 2.0, now * TAU * 0.8 + i, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"dive": true})
	elif event.is_action_released(&"action_primary"):
		NetManager.send_match_input({"dive": false})


func _arena_half() -> float:
	return TreasureDivers.ARENA_HALF


func _setup_3d() -> void:
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2.ONE * TreasureDivers.ARENA_HALF * 2.0
	var water_material := StandardMaterial3D.new()
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.albedo_color = WATER_COLOR
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_mesh.material = water_material
	var water := MeshInstance3D.new()
	water.name = "WaterSurface"
	water.mesh = water_mesh
	water.position.y = SURFACE_HEIGHT
	arena.add_child(water)

	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = COIN_RADIUS
	coin_mesh.bottom_radius = COIN_RADIUS
	coin_mesh.height = COIN_HEIGHT
	var coin_material := StandardMaterial3D.new()
	coin_material.albedo_color = COIN_COLOR
	coin_material.metallic = 0.6
	coin_material.roughness = 0.35
	coin_material.emission_enabled = true
	coin_material.emission = COIN_COLOR
	coin_material.emission_energy_multiplier = 0.9
	coin_mesh.material = coin_material
	for i in COIN_POOL:
		var node := MeshInstance3D.new()
		node.name = "Treasure%d" % i
		node.mesh = coin_mesh
		node.visible = false
		arena.add_child(node)
		_coin_pool.append(node)
	for slot: int in names:
		_air_bars[slot] = _build_air_bar()


## Air bar over the diver's head (#235): a fixed-size billboard Label3D of
## bubble glyphs (the same primitive nameplates use, so it always faces the
## camera), tinted cyan when full and red when empty. Kept in the arena, not
## parented to the rig, so rig facing never spins it.
func _build_air_bar() -> Label3D:
	var bar := Label3D.new()
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.no_depth_test = true
	bar.fixed_size = true
	bar.pixel_size = 0.002
	bar.font_size = 30
	bar.outline_size = 8
	bar.visible = false
	arena.add_child(bar)
	return bar


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	treasure = game.get("treasure", [])
	_update_players()
	_update_treasure()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var is_diving := int(state[3]) == 1
		var at := Vector2(state[0], state[1])
		update_rig(slot, at, 0.0 if is_diving else SURFACE_HEIGHT)
		rig.display_name = "%s  %d" % [player_name(slot), int(state[2])]
		_air_seen[slot] = float(state[4])
		# Water FX (M13-10): splash on every surface crossing, bubbles on a
		# snapshot-cadence timer while under. Seeded so a rejoiner's first
		# snapshot stays dry.
		if _diving_seen.has(slot) and bool(_diving_seen[slot]) != is_diving:
			fx_splash(at)
		_diving_seen[slot] = is_diving
		if is_diving:
			_bubble_left[slot] = float(_bubble_left.get(slot, 0.0)) - SNAPSHOT_INTERVAL
			if float(_bubble_left[slot]) <= 0.0:
				_bubble_left[slot] = BUBBLE_EVERY_SEC
				fx_sparkle(at, BUBBLE_COLOR, 0.9)
		var stun := float(state[5])
		if stun > 0.0 and float(_stun_seen.get(slot, 0.0)) <= 0.0:
			# Fresh blackout: gasp, rattle the screen, and burst the surface.
			rig.play(&"hit")
			request_shake(8.0)
			fx_splash(at)
		_stun_seen[slot] = stun


func _update_treasure() -> void:
	for i in _coin_pool.size():
		var node := _coin_pool[i]
		node.visible = i < treasure.size()
		if node.visible:
			var state: Array = treasure[i]
			node.position = to_arena(Vector2(state[0], state[1]), COIN_HOVER)
