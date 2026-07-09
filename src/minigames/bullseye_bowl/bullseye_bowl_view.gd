extends MinigameView3D
## Bullseye Bowl client view (M10-07): one lane per player with a sliding
## concentric-ring target at the far end and a rolling ball mid-flight. Rigs
## stand at their lane's foul line; score and balls-left ride the nameplate.
## Bullseyes rattle the screen.

## Solid, high-contrast boards (#236): the old translucent rings and lane
## washed out against the orange floor.
const LANE_COLOR := Color(0.16, 0.14, 0.2, 0.88)
const RING_COLORS: Array[Color] = [
	Color(0.95, 0.2, 0.12), Color(0.98, 0.72, 0.15), Color(0.94, 0.94, 0.9)
]
## Alternate scheme on odd lanes (#588): adjacent targets otherwise read as one
## continuous board at iso distance — swapping the palette every other lane
## gives each its own silhouette.
const RING_COLORS_ALT: Array[Color] = [
	Color(0.15, 0.35, 0.95), Color(0.2, 0.82, 0.82), Color(0.86, 0.9, 0.97)
]
const BALL_RADIUS := 0.3
const DISC_HEIGHT := 0.04

## Latest replicated state, straight from BullseyeBowl.get_snapshot().
var players := {}

var _lanes := {}  # slot -> {target: Node3D, ball: MeshInstance3D, center_x: float}
var _scores_seen := {}


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"roll": true})


## Camera framing grows with the lane bank (M15-07): lanes keep their tuned
## pitch (each player's alley must stay readable and distinct), so a crowd
## widens the shot instead of squeezing the lanes. Linear growth, not
## MinigameScaling.arena_half()'s sqrt — a lane bank is one-dimensional.
## names is populated before the camera builds (MinigameView.setup order),
## and lobbies up to the 6-player baseline keep the classic framing exactly.
## Warm bowling-lane floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.92, 0.78)


func _arena_half() -> float:
	return BullseyeBowl.LANE_LENGTH * 0.75 * MinigameScaling.growth(names.size())


## #797: below the baseline headcount the arena keeps its tuned <=6 width
## (MinigameScaling.growth floors at 1.0), but the fixed LANE_SPACING packed
## every lane near center regardless — most of that width sat unused. Spreads
## lanes across the same outer-lane span a full baseline bank already fills,
## then settles back to LANE_SPACING once `count` reaches the baseline (where
## the arena itself starts growing to match, keeping the tuned framing exact).
static func _lane_pitch(count: int) -> float:
	var baseline_span := (MinigameScaling.BASELINE_PLAYERS - 1) * BullseyeBowl.LANE_SPACING
	return maxf(BullseyeBowl.LANE_SPACING, baseline_span / maxf(1.0, float(count - 1)))


func _setup_3d() -> void:
	var slot_list: Array = names.keys()
	slot_list.sort()
	var pitch := _lane_pitch(slot_list.size())
	for i in slot_list.size():
		var slot: int = slot_list[i]
		var center_x := (i - (slot_list.size() - 1) / 2.0) * pitch
		_build_lane(slot, center_x, i % 2 == 1)
		var rig := rig_for_slot(slot)
		if rig != null:
			rig.position = Vector3(center_x, 0.0, BullseyeBowl.LANE_LENGTH / 2.0)
			rig.rotation.y = PI  # face down the lane


func _build_lane(slot: int, center_x: float, alt_palette: bool) -> void:
	var lane_mesh := PlaneMesh.new()
	lane_mesh.size = Vector2(BullseyeBowl.LANE_SPACING * 0.8, BullseyeBowl.LANE_LENGTH)
	var lane_material := StandardMaterial3D.new()
	lane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lane_material.albedo_color = LANE_COLOR
	lane_mesh.material = lane_material
	var lane := MeshInstance3D.new()
	lane.name = "Lane%d" % slot
	lane.mesh = lane_mesh
	lane.position = Vector3(center_x, 0.01, 0.0)
	arena.add_child(lane)

	var target := Node3D.new()
	target.name = "Target%d" % slot
	var radii: Array[float] = [
		BullseyeBowl.RING_OUTER, BullseyeBowl.RING_MID, BullseyeBowl.RING_BULLSEYE
	]
	var palette := RING_COLORS_ALT if alt_palette else RING_COLORS
	for r in radii.size():
		var ring := MeshInstance3D.new()
		ring.name = "Ring%d" % r
		var mesh := CylinderMesh.new()
		mesh.top_radius = radii[r]
		mesh.bottom_radius = radii[r]
		# Tier the caps well apart and keep the materials opaque: near-coplanar
		# tops in transparent mode z-fight into one blank disc at iso distance
		# (the #236 reopen).
		mesh.height = DISC_HEIGHT + r * 0.1
		var material := StandardMaterial3D.new()
		material.albedo_color = palette[radii.size() - 1 - r]
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 0.25
		mesh.material = material
		ring.mesh = mesh
		ring.position.y = (mesh.height - DISC_HEIGHT) / 2.0
		target.add_child(ring)
	target.position = Vector3(center_x, 0.0, -BullseyeBowl.LANE_LENGTH / 2.0)
	arena.add_child(target)

	var ball := MeshInstance3D.new()
	ball.name = "Ball%d" % slot
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = BALL_RADIUS
	ball_mesh.height = BALL_RADIUS * 2.0
	var ball_material := StandardMaterial3D.new()
	ball_material.albedo_color = player_color(slot)
	ball_material.emission_enabled = true
	ball_material.emission = player_color(slot)
	ball_material.emission_energy_multiplier = 0.5
	ball_mesh.material = ball_material
	ball.mesh = ball_mesh
	ball.visible = false
	arena.add_child(ball)
	_lanes[slot] = {"target": target, "ball": ball, "center_x": center_x}


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	for slot: int in players:
		var state: Array = players[slot]
		var lane: Dictionary = _lanes.get(slot, {})
		if lane.is_empty():
			continue
		var center_x: float = lane.center_x
		(lane.target as Node3D).position.x = center_x + float(state[BullseyeBowl.PS_TARGET_OFFSET])
		var flight_t := float(state[BullseyeBowl.PS_FLIGHT_T])
		var ball: MeshInstance3D = lane.ball
		var was_flying := ball.visible
		ball.visible = flight_t >= 0.0
		if ball.visible:
			var z := lerpf(
				BullseyeBowl.LANE_LENGTH / 2.0, -BullseyeBowl.LANE_LENGTH / 2.0, flight_t
			)
			ball.position = Vector3(center_x, BALL_RADIUS, z)
			# Rolling spin (M13-14): rotation rides the replicated flight
			# progress - distance traveled over the ball's circumference.
			ball.rotation.x = -flight_t * BullseyeBowl.LANE_LENGTH / BALL_RADIUS
		var rig := rig_for_slot(slot)
		if rig != null:
			# Stationary rigs are placed in _setup_3d, not via update_rig, so
			# reveal them here for the connected slots the snapshot carries —
			# a disconnected member never appears, leaving no ghost (#601).
			reveal_rig(slot)
			rig.display_name = (
				"%s  %d pts  (%d balls)"
				% [
					player_name(slot),
					int(state[BullseyeBowl.PS_SCORE]),
					int(state[BullseyeBowl.PS_BALLS_LEFT]),
				]
			)
		var score := int(state[BullseyeBowl.PS_SCORE])
		var seen := int(_scores_seen.get(slot, score))
		var gained := score - seen
		if gained > 0:
			# Ring-hit flash (M13-14): a sparkle at the target scaled to the
			# ring value - bullseyes burst, outers twinkle. Signature cues
			# (#728): `bell` for the bullseye (docs/AUDIO_GUIDE.md calls out
			# "basket, bullseye" by name), `hit` for a lesser ring.
			var target_at := Vector2(
				center_x + float(state[BullseyeBowl.PS_TARGET_OFFSET]),
				-BullseyeBowl.LANE_LENGTH / 2.0
			)
			if gained >= BullseyeBowl.SCORE_BULLSEYE:
				fx_burst(target_at, player_color(slot), 0.4)
				request_shake(7.0)  # a bullseye just landed
				if slot == my_slot:
					play_sfx(&"bell")
			else:
				fx_sparkle(target_at, player_color(slot), 0.3)
				if slot == my_slot:
					play_sfx(&"hit")
		elif was_flying and not ball.visible and slot == my_slot:
			# The ball landed beyond every ring (gained == 0): a clean miss,
			# previously silent.
			play_sfx(&"error")
		_scores_seen[slot] = score
