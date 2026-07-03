extends MinigameView3D
## Tug of War client view (M8-09): renders the replicated tug in the shared
## 2.5D iso-arena (M8-01, MinigameView3D) — the rope as a stretched bar with
## a marker knot tracking the replicated offset, teams lined up on their
## sides as CharacterRigs leaning into the pull. Presentation-tier swap only:
## state storage and the alternating pull input are unchanged from the 2D
## pass (M4-10).

const ROPE_COLOR := Color(0.72, 0.55, 0.3)
const MARKER_COLOR := Color(1.0, 0.9, 0.4)
const LINE_COLOR := Color(0.9, 0.25, 0.25)
const ROPE_HEIGHT := 0.9
const ROPE_THICKNESS := 0.12
## Rope world length is a little longer than the two win offsets.
const ROPE_EXTRA := 4.0
## Where teams stand relative to the rope line.
const TEAM_ROW_Z := 1.6
const TEAMMATE_SPACING := 1.4

## Latest replicated state, straight from TugOfWar.get_snapshot().
var rope := 0.0
var win_offset := TugOfWar.WIN_OFFSET
var team_a: Array = []
var team_b: Array = []

var _marker: MeshInstance3D
var _phase := -1
var _last_rope := 0.0


## Polled (not event-driven): stick axis motion doesn't deliver discrete
## pressed events reliably, which left gamepads unable to pull at all (#136).
## is_action_just_pressed unifies keys, d-pad, and stick threshold crossings.
func _process(_delta: float) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	var phase := -1
	if Input.is_action_just_pressed(&"move_left"):
		phase = 0
	elif Input.is_action_just_pressed(&"move_right"):
		phase = 1
	if phase == -1 or phase == _phase:
		return
	_phase = phase
	NetManager.send_match_input({"pull": phase})


func _arena_half() -> float:
	return TugOfWar.WIN_OFFSET + 4.0


func _setup_3d() -> void:
	var rope_mesh := BoxMesh.new()
	rope_mesh.size = Vector3(TugOfWar.WIN_OFFSET * 2.0 + ROPE_EXTRA, ROPE_THICKNESS, ROPE_THICKNESS)
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color = ROPE_COLOR
	rope_mesh.material = rope_material
	var rope_node := MeshInstance3D.new()
	rope_node.name = "Rope"
	rope_node.mesh = rope_mesh
	rope_node.position = Vector3(0.0, ROPE_HEIGHT, 0.0)
	arena.add_child(rope_node)

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.3
	marker_mesh.height = 0.6
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = MARKER_COLOR
	marker_material.emission_enabled = true
	marker_material.emission = MARKER_COLOR
	marker_material.emission_energy_multiplier = 0.4
	marker_mesh.material = marker_material
	_marker = MeshInstance3D.new()
	_marker.name = "Marker"
	_marker.mesh = marker_mesh
	_marker.position = Vector3(0.0, ROPE_HEIGHT, 0.0)
	arena.add_child(_marker)

	for side: float in [-1.0, 1.0]:
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.15, 0.02, 6.0)
		var line_material := StandardMaterial3D.new()
		line_material.albedo_color = LINE_COLOR
		line_mesh.material = line_material
		var line := MeshInstance3D.new()
		line.name = "WinLineLeft" if side < 0.0 else "WinLineRight"
		line.mesh = line_mesh
		line.position = Vector3(side * TugOfWar.WIN_OFFSET, 0.01, 0.0)
		arena.add_child(line)


func _render_3d(game: Dictionary) -> void:
	rope = float(game.get("rope", 0.0))
	win_offset = float(game.get("win_offset", TugOfWar.WIN_OFFSET))
	team_a = game.get("team_a", [])
	team_b = game.get("team_b", [])
	_marker.position.x = rope
	_update_teams()
	_last_rope = rope


func _update_teams() -> void:
	# Team A pulls toward -x and stands on the -x side; B mirrors.
	_place_team(team_a, -1.0)
	_place_team(team_b, 1.0)


func _place_team(team: Array, side: float) -> void:
	var moving := absf(rope - _last_rope) > 0.001
	for i in team.size():
		var slot: int = team[i]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var x := rope + side * (2.0 + i * TEAMMATE_SPACING)
		update_rig(slot, Vector2(x, TEAM_ROW_Z * side))
		# Everyone faces the rope's center line, leaning into the pull.
		rig.rotation.y = atan2(-side, 0.0)
		var desired: StringName = &"run" if moving else &"idle"
		if rig.current_action() != desired:
			rig.play(desired)
