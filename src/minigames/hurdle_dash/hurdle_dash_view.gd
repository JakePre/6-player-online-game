extends MinigameView3D
## Hurdle Dash client view (#212, replacing the M4-07 flat placeholder):
## every runner gets a lane on the iso floor, the shared hurdle layout is
## real bars, and rigs run, jump, stumble, and cheer through the race.

const LANE_SPACING := 2.2
const HURDLE_COLOR := Color(0.85, 0.55, 0.25)
const FINISH_COLOR := Color(0.4, 0.85, 0.4)
const STUN_COLOR := Color(0.9, 0.3, 0.25)
const JUMP_LIFT := 1.0
## World x runs 0..COURSE_LEN, recentered so the course spans the arena.
const COURSE_OFFSET := -HurdleDash.COURSE_LEN / 2.0

## Latest replicated state, straight from HurdleDash.get_snapshot().
var players := {}
var hurdles: Array = []
var course_len := HurdleDash.COURSE_LEN

var _hurdles_built := false


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"jump": true})


func _arena_half() -> float:
	return HurdleDash.COURSE_LEN / 2.0 + 2.0


func _setup_3d() -> void:
	var finish_mesh := BoxMesh.new()
	var lanes := maxi(names.size(), 2)
	finish_mesh.size = Vector3(0.2, 0.05, lanes * LANE_SPACING + 1.0)
	var finish_material := StandardMaterial3D.new()
	finish_material.albedo_color = FINISH_COLOR
	finish_material.emission_enabled = true
	finish_material.emission = FINISH_COLOR
	finish_material.emission_energy_multiplier = 0.4
	finish_mesh.material = finish_material
	var finish := MeshInstance3D.new()
	finish.name = "FinishLine"
	finish.mesh = finish_mesh
	finish.position = Vector3(course_len + COURSE_OFFSET, 0.03, 0.0)
	arena.add_child(finish)


## Hurdle bars are static per round; built from the first snapshot.
func _build_hurdles() -> void:
	_hurdles_built = true
	var lanes := maxi(names.size(), 2)
	for hurdle: Variant in hurdles:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.15, 0.5, lanes * LANE_SPACING + 0.6)
		var material := StandardMaterial3D.new()
		material.albedo_color = HURDLE_COLOR
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = Vector3(float(hurdle) + COURSE_OFFSET, 0.45, 0.0)
		arena.add_child(node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	hurdles = game.get("hurdles", [])
	course_len = float(game.get("course_len", HurdleDash.COURSE_LEN))
	if not _hurdles_built and not hurdles.is_empty():
		_build_hurdles()
	var lane_indices := players.keys()
	lane_indices.sort()
	for row in lane_indices.size():
		var slot: int = lane_indices[row]
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var z := (row - (lane_indices.size() - 1) / 2.0) * LANE_SPACING
		var airborne := int(state[1]) == 1
		var stunned := float(state[2]) > 0.0
		var done: bool = state[3]
		# Direct placement (not update_rig): the race owns its own poses and
		# everyone faces down the course.
		rig.position = to_arena(Vector2(float(state[0]) + COURSE_OFFSET, z))
		rig.position.y = JUMP_LIFT if airborne else 0.0
		rig.rotation.y = atan2(1.0, 0.0)
		var desired := _pose(airborne, stunned, done, float(state[0]))
		if rig.current_action() != desired:
			rig.play(desired)
		var caption := player_name(slot)
		if done:
			caption += "  🏁"
		rig.display_name = caption
		rig.player_color = STUN_COLOR if stunned else PlayerPalette.color_for_slot(slot)


func _pose(airborne: bool, stunned: bool, done: bool, progress: float) -> StringName:
	if done:
		return &"cheer"
	if stunned:
		return &"hit"
	if airborne:
		return &"jump_idle"
	return &"run" if progress > 0.0 else &"idle"
