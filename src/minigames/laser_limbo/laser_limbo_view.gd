extends MinigameView3D
## Laser Limbo client view (M10-06): sweeping laser walls as glowing red
## boxes — low bars to jump, high bars to duck, full walls with a visible
## gap. Jumps arc via update_rig height, ducks squash the rig, lives ride the
## nameplate as pips, and losing one flinches + shakes.

const LASER_COLOR := Color(0.95, 0.15, 0.1, 0.7)
const WALL_POOL := 8
const LOW_BAR_HEIGHT := 0.45
const HIGH_BAR_HEIGHT := 1.5
const WALL_TALL := 2.2
const JUMP_HEIGHT := 1.0
const DUCK_SCALE := 0.6

## Latest replicated state, straight from LaserLimbo.get_snapshot().
var players := {}
var walls: Array = []
var fallen: Array = []

var _wall_pool: Array[Node3D] = []
var _lives_seen := {}
var _downed := {}
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _fallen_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"jump": true})
	elif event.is_action_pressed(&"action_secondary"):
		NetManager.send_match_input({"duck": true})
	elif event.is_action_released(&"action_secondary"):
		NetManager.send_match_input({"duck": false})


func _arena_half() -> float:
	return LaserLimbo.ARENA_HALF


## Each pooled wall is a root with three beam segments; kind decides which
## show: LOW = the low bar, HIGH = the high bar, GAP = two tall halves whose
## sizes are set per snapshot around the gap.
func _setup_3d() -> void:
	for i in WALL_POOL:
		var root := Node3D.new()
		root.name = "Wall%d" % i
		root.visible = false
		for segment_name: String in ["Low", "High", "GapNear", "GapFar"]:
			var node := MeshInstance3D.new()
			node.name = segment_name
			node.mesh = BoxMesh.new()
			(node.mesh as BoxMesh).material = _laser_material()
			root.add_child(node)
		arena.add_child(root)
		_wall_pool.append(root)


func _laser_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = LASER_COLOR
	material.emission_enabled = true
	material.emission = Color(LASER_COLOR, 1.0)
	material.emission_energy_multiplier = 1.2
	return material


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	walls = game.get("walls", [])
	fallen = game.get("fallen", [])
	_update_players()
	_update_walls()
	_shake_on_new_downs()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var is_airborne := int(state[3]) == 1
		var is_ducking := int(state[4]) == 1
		update_rig(slot, Vector2(state[0], state[1]), JUMP_HEIGHT if is_airborne else 0.0)
		rig.scale.y = DUCK_SCALE if is_ducking else 1.0
		var current_lives := int(state[2])
		rig.display_name = "%s  %s" % [player_name(slot), "+".repeat(current_lives)]
		if _lives_seen.has(slot) and current_lives < int(_lives_seen[slot]):
			rig.play(&"hit")
			request_shake(7.0)
		_lives_seen[slot] = current_lives
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
	rig.scale.y = 1.0
	rig.play(&"ko")


func _update_walls() -> void:
	var half := LaserLimbo.ARENA_HALF
	for i in _wall_pool.size():
		var root := _wall_pool[i]
		root.visible = i < walls.size()
		if not root.visible:
			continue
		var state: Array = walls[i]
		var kind := int(state[2])
		var gap_y := float(state[3])
		root.position = Vector3(float(state[0]), 0.0, 0.0)
		var low: MeshInstance3D = root.get_node("Low")
		var high: MeshInstance3D = root.get_node("High")
		var near: MeshInstance3D = root.get_node("GapNear")
		var far: MeshInstance3D = root.get_node("GapFar")
		low.visible = kind == LaserLimbo.WallKind.LOW
		high.visible = kind == LaserLimbo.WallKind.HIGH
		near.visible = kind == LaserLimbo.WallKind.GAP
		far.visible = kind == LaserLimbo.WallKind.GAP
		if low.visible:
			(low.mesh as BoxMesh).size = Vector3(0.15, LOW_BAR_HEIGHT, half * 2.0)
			low.position = Vector3(0.0, LOW_BAR_HEIGHT / 2.0, 0.0)
		if high.visible:
			(high.mesh as BoxMesh).size = Vector3(0.15, 0.3, half * 2.0)
			high.position = Vector3(0.0, HIGH_BAR_HEIGHT, 0.0)
		if near.visible:
			var gap := LaserLimbo.GAP_HALF_WIDTH
			var near_len := maxf((gap_y - gap) + half, 0.0)
			var far_len := maxf(half - (gap_y + gap), 0.0)
			(near.mesh as BoxMesh).size = Vector3(0.15, WALL_TALL, near_len)
			near.position = Vector3(0.0, WALL_TALL / 2.0, -half + near_len / 2.0)
			(far.mesh as BoxMesh).size = Vector3(0.15, WALL_TALL, far_len)
			far.position = Vector3(0.0, WALL_TALL / 2.0, half - far_len / 2.0)


func _shake_on_new_downs() -> void:
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _fallen_seen >= 0 and fallen_count > _fallen_seen:
		request_shake(11.0)
	_fallen_seen = fallen_count
