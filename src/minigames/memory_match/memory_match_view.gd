extends MinigameView3D
## Memory Match client view (M10-05): a thin-ice-style tile grid over a dark
## pit. Safe tiles light up during SHOW; in the dark everything looks the
## same — that's the game. Losers drop with the check, with a shake. The grid
## replaces the default floor (the pattern IS the floor).

const TILE_SAFE_COLOR := Color(0.35, 0.85, 0.5)
const TILE_DARK_COLOR := Color(0.28, 0.3, 0.38)
const PIT_COLOR := Color(0.04, 0.04, 0.07)
const TILE_THICKNESS := 0.3
const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
const SHOW_TEXT := "REMEMBER THE PATTERN!"
const DARK_TEXT := "GET TO A SAFE TILE!"

## Latest replicated state, straight from MemoryMatch.get_snapshot().
var players := {}
var phase: int = MemoryMatch.Phase.SHOW
var safe_tiles: Array = []
var fallen: Array = []

var _tile_nodes: Array[MeshInstance3D] = []
var _safe_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _phase_label: Label
var _downed := {}
# Previous phase for reveal-wave detection (M13-12); -1 = unseeded.
var _phase_seen := -1
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _fallen_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return MemoryMatch.HALF_EXTENT


## The tile grid IS the floor: a dark pit plane below, one box per tile.
func _build_floor() -> void:
	var pit_mesh := PlaneMesh.new()
	pit_mesh.size = Vector2.ONE * MemoryMatch.HALF_EXTENT * 2.5
	var pit_material := StandardMaterial3D.new()
	pit_material.albedo_color = PIT_COLOR
	pit_mesh.material = pit_material
	var pit := MeshInstance3D.new()
	pit.name = "Pit"
	pit.mesh = pit_mesh
	pit.position.y = -0.45
	arena.add_child(pit)

	_safe_material = StandardMaterial3D.new()
	_safe_material.albedo_color = TILE_SAFE_COLOR
	_safe_material.emission_enabled = true
	_safe_material.emission = TILE_SAFE_COLOR
	_safe_material.emission_energy_multiplier = 0.4
	_dark_material = StandardMaterial3D.new()
	_dark_material.albedo_color = TILE_DARK_COLOR
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(MemoryMatch.TILE_SIZE, TILE_THICKNESS, MemoryMatch.TILE_SIZE)

	for y in MemoryMatch.GRID_SIZE:
		for x in MemoryMatch.GRID_SIZE:
			var node := MeshInstance3D.new()
			node.name = "Tile_%d_%d" % [x, y]
			node.mesh = tile_mesh
			node.material_override = _dark_material
			node.position = Vector3(
				-MemoryMatch.HALF_EXTENT + (x + 0.5) * MemoryMatch.TILE_SIZE,
				-TILE_THICKNESS / 2.0,
				-MemoryMatch.HALF_EXTENT + (y + 0.5) * MemoryMatch.TILE_SIZE
			)
			arena.add_child(node)
			_tile_nodes.append(node)


func _setup_3d() -> void:
	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.add_theme_font_size_override(&"font_size", 32)
	_phase_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phase_label.position.y = 16.0
	add_child(_phase_label)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	phase = int(game.get("phase", MemoryMatch.Phase.SHOW))
	safe_tiles = game.get("safe_tiles", [])
	fallen = game.get("fallen", [])
	_phase_label.text = SHOW_TEXT if phase == MemoryMatch.Phase.SHOW else DARK_TEXT
	_update_tiles()
	_update_players()
	_reveal_wave_fx()
	_shake_on_new_downs()


## The pattern landing gets a sparkle wave over the safe tiles (M13-12),
## fired on the DARK->SHOW transition only — never on the seeding snapshot.
func _reveal_wave_fx() -> void:
	if (
		_phase_seen == MemoryMatch.Phase.DARK
		and phase == MemoryMatch.Phase.SHOW
		and not safe_tiles.is_empty()
	):
		for index in safe_tiles:
			fx_sparkle(_tile_world(int(index)), TILE_SAFE_COLOR, 0.4)
	_phase_seen = phase


func _tile_world(index: int) -> Vector2:
	var x := index % MemoryMatch.GRID_SIZE
	var y := int(floorf(float(index) / MemoryMatch.GRID_SIZE))
	return Vector2(
		-MemoryMatch.HALF_EXTENT + (x + 0.5) * MemoryMatch.TILE_SIZE,
		-MemoryMatch.HALF_EXTENT + (y + 0.5) * MemoryMatch.TILE_SIZE
	)


func _update_tiles() -> void:
	var lit := phase == MemoryMatch.Phase.SHOW
	for i in _tile_nodes.size():
		_tile_nodes[i].material_override = (
			_safe_material if lit and i in safe_tiles else _dark_material
		)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
	for group: Array in fallen:
		for slot: int in group:
			_down_rig(slot)


func _down_rig(slot: int) -> void:
	if _downed.has(slot):
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	_downed[slot] = true
	rig.play(&"ko")
	rig.player_color = ELIMINATED_COLOR
	# The drop into the pit splashes (M13-12).
	fx_splash(Vector2(rig.position.x, rig.position.z))


func _shake_on_new_downs() -> void:
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _fallen_seen >= 0 and fallen_count > _fallen_seen:
		request_shake(10.0)
	_fallen_seen = fallen_count
