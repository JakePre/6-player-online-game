extends MinigameView3D
## Fish Frenzy client view (#183): three lanes with fish swimming toward the
## catch line, players snapped to lanes, catch/streak counts on nameplates.
## W/S or stick up/down snaps your lane; ticks play on each cadence beat.

const LANE_SPACING := 2.4
const RUNWAY_LEN := 10.0
const FISH_COLOR := Color(0.4, 0.7, 0.95)
const LINE_COLOR := Color(0.4, 0.85, 0.4)
const FISH_POOL := 12

## Latest replicated state, straight from FishFrenzy.get_snapshot().
var players := {}
var fish: Array = []
var swim_sec := FishFrenzy.SWIM_SEC

var _fish_pool: Array[MeshInstance3D] = []
var _my_lane := 1


func _arena_half() -> float:
	return RUNWAY_LEN * 0.75


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	var delta := 0
	if event.is_action_pressed(&"move_up"):
		delta = -1
	elif event.is_action_pressed(&"move_down"):
		delta = 1
	if delta == 0:
		return
	_my_lane = clampi(_my_lane + delta, 0, FishFrenzy.LANES - 1)
	NetManager.send_match_input({"lane": _my_lane})
	play_sfx(&"click")


func _setup_3d() -> void:
	var fish_mesh := SphereMesh.new()
	fish_mesh.radius = 0.3
	fish_mesh.height = 0.45
	var fish_material := StandardMaterial3D.new()
	fish_material.albedo_color = FISH_COLOR
	fish_material.emission_enabled = true
	fish_material.emission = FISH_COLOR
	fish_material.emission_energy_multiplier = 0.3
	fish_mesh.material = fish_material
	for i in FISH_POOL:
		var node := MeshInstance3D.new()
		node.mesh = fish_mesh
		node.visible = false
		arena.add_child(node)
		_fish_pool.append(node)
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(0.15, 0.02, LANE_SPACING * FishFrenzy.LANES)
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = LINE_COLOR
	line_mesh.material = line_material
	var line := MeshInstance3D.new()
	line.name = "CatchLine"
	line.mesh = line_mesh
	line.position = Vector3(0.0, 0.01, 0.0)
	arena.add_child(line)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	fish = game.get("fish", [])
	swim_sec = float(game.get("swim_sec", FishFrenzy.SWIM_SEC))
	for i in _fish_pool.size():
		var node := _fish_pool[i]
		if i < fish.size():
			var entry: Array = fish[i]
			var progress := 1.0 - clampf(float(entry[1]) / swim_sec, 0.0, 1.0)
			node.position = Vector3(lerpf(RUNWAY_LEN, 0.0, progress), 0.3, _lane_z(int(entry[0])))
			node.visible = true
		else:
			node.visible = false
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(-1.2, _lane_z(int(state[0]))))
		var caption := "%s  🐟%d" % [player_name(slot), int(state[1])]
		if int(state[2]) >= FishFrenzy.STREAK_EVERY:
			caption += "  🔥%d" % int(state[2])
		rig.display_name = caption


func _lane_z(lane_index: int) -> float:
	return (lane_index - 1) * LANE_SPACING
