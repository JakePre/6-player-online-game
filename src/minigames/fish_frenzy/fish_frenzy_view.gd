extends MinigameView3D
## Fish Frenzy client view (#183 + M13-19 FX): three lanes with fish that
## actually SWIM toward the catch line — fish-shaped bodies whose tail-wag
## and bob are driven by the replicated swim progress (deterministic, no
## local clocks) — players snapped to lanes, catch/streak counts on
## nameplates, and a splash + sparkle at the line on every catch.
## W/S or stick up/down snaps your lane; ticks play on each cadence beat.

const LANE_SPACING := 2.4
const RUNWAY_LEN := 10.0
const FISH_COLOR := Color(0.4, 0.7, 0.95)
const LINE_COLOR := Color(0.4, 0.85, 0.4)
const LANE_COLOR := Color(0.16, 0.32, 0.5, 0.55)
const LANE_DIVIDER := Color(0.55, 0.8, 1.0, 0.6)
const FISH_POOL := 12
## Swim motion (M13-19): tail-wag cycles across one lane run, wag angles.
const WAG_CYCLES := 6.0
const BODY_WAG_RAD := 0.22
const TAIL_WAG_RAD := 0.55
const BOB_HEIGHT := 0.06
const CATCH_SPARKLE_COLOR := Color(0.5, 0.9, 1.0)
## Same-lane players queue behind the line at per-slot offsets instead of
## stacking on one point (#238).
const STAND_X := -1.2
const QUEUE_SPACING := 0.9
## Base half-extent for the runway (M15); scales for larger lobbies so a
## worst-case deep queue (everyone stacked in one lane) still fits the floor
## and camera. Unchanged at <=6 players.
const BASE_ARENA_HALF := RUNWAY_LEN * 0.75

## Latest replicated state, straight from FishFrenzy.get_snapshot().
var players := {}
var fish: Array = []
var swim_sec := FishFrenzy.SWIM_SEC

var _fish_pool: Array[Node3D] = []
var _my_lane := 1
var _catches_seen := {}


## Aqua pool floor (#589).
func _floor_tint() -> Color:
	return Color(0.82, 0.95, 1.0)


func _arena_half() -> float:
	return MinigameScaling.arena_half(BASE_ARENA_HALF, names.size())


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
	var fish_material := StandardMaterial3D.new()
	fish_material.albedo_color = FISH_COLOR
	fish_material.emission_enabled = true
	fish_material.emission = FISH_COLOR
	fish_material.emission_energy_multiplier = 0.3
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.22
	body_mesh.height = 0.44
	body_mesh.material = fish_material
	var tail_mesh := PrismMesh.new()
	tail_mesh.size = Vector3(0.3, 0.28, 0.06)
	tail_mesh.material = fish_material
	for i in FISH_POOL:
		var root := Node3D.new()
		root.name = "Fish%d" % i
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = body_mesh
		body.scale = Vector3(1.9, 0.9, 1.0)  # torpedo along the swim axis
		root.add_child(body)
		var tail := MeshInstance3D.new()
		tail.name = "Tail"
		tail.mesh = tail_mesh
		tail.rotation.z = PI / 2.0
		tail.position.x = 0.48  # trailing the body (fish swim toward -x)
		root.add_child(tail)
		root.visible = false
		arena.add_child(root)
		_fish_pool.append(root)
	# The three lanes are visible water strips with dividers (#238).
	for lane_index in FishFrenzy.LANES:
		var strip := BoxMesh.new()
		strip.size = Vector3(RUNWAY_LEN + 3.0, 0.02, LANE_SPACING * 0.92)
		var strip_material := StandardMaterial3D.new()
		strip_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		strip_material.albedo_color = LANE_COLOR
		strip.material = strip_material
		var strip_node := MeshInstance3D.new()
		strip_node.name = "Lane%d" % lane_index
		strip_node.mesh = strip
		strip_node.position = Vector3(RUNWAY_LEN / 2.0 - 1.0, 0.01, _lane_z(lane_index))
		arena.add_child(strip_node)
	for divider_index in FishFrenzy.LANES + 1:
		var divider := BoxMesh.new()
		divider.size = Vector3(RUNWAY_LEN + 3.0, 0.025, 0.08)
		var divider_material := StandardMaterial3D.new()
		divider_material.albedo_color = LANE_DIVIDER
		divider.material = divider_material
		var divider_node := MeshInstance3D.new()
		divider_node.mesh = divider
		divider_node.position = Vector3(
			RUNWAY_LEN / 2.0 - 1.0,
			0.02,
			_lane_z(0) - LANE_SPACING / 2.0 + divider_index * LANE_SPACING
		)
		arena.add_child(divider_node)
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
			# Swim motion rides the replicated progress (M13-19): every client
			# sees the same wag at the same point of the run.
			var wag := sin(progress * WAG_CYCLES * TAU)
			node.position = Vector3(
				lerpf(RUNWAY_LEN, 0.0, progress),
				0.3 + sin(progress * TAU * 2.0) * BOB_HEIGHT,
				_lane_z(int(entry[0]))
			)
			node.rotation.y = wag * BODY_WAG_RAD
			(node.get_node("Tail") as MeshInstance3D).rotation.y = -wag * TAIL_WAG_RAD
			node.visible = true
		else:
			node.visible = false
	# Queue order within a lane: stable by slot, so players line up behind
	# the catch line instead of stacking (#238).
	var lane_queues := {}
	var slots_sorted := players.keys()
	slots_sorted.sort()
	for slot: int in slots_sorted:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var player_lane := int(state[0])
		var queue_index := int(lane_queues.get(player_lane, 0))
		lane_queues[player_lane] = queue_index + 1
		update_rig(slot, Vector2(STAND_X - queue_index * QUEUE_SPACING, _lane_z(player_lane)))
		var caption := "%s  🐟%d" % [player_name(slot), int(state[1])]
		if int(state[2]) >= FishFrenzy.STREAK_EVERY:
			caption += "  🔥%d" % int(state[2])
		rig.display_name = caption
		# Catch FX (M13-19): a catch is the count ticking up — splash + sparkle
		# at the line in that lane. Seeded so a rejoiner's first snapshot stays
		# calm.
		var catches := int(state[1])
		if _catches_seen.has(slot) and catches > int(_catches_seen[slot]):
			var at := Vector2(0.0, _lane_z(player_lane))
			fx_splash(at)
			fx_sparkle(at, CATCH_SPARKLE_COLOR)
			# Signature cues (#728, docs/AUDIO_GUIDE.md — Water): the water-entry
			# sound matching the splash FX, plus the scoring cue — a catch is
			# this game's currency.
			play_sfx(&"splash")
			if slot == my_slot:
				play_sfx(&"coin")
		_catches_seen[slot] = catches


func _lane_z(lane_index: int) -> float:
	return (lane_index - 1) * LANE_SPACING
