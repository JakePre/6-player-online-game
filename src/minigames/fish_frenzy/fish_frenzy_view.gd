extends MinigameView3D
## Fish Frenzy client view (#183 + M13-19 FX + #1133 GFX): three lanes with
## fish that actually SWIM toward the catch line — Kenney fish model bodies
## (fish.glb, fish-bones.glb variant) with wag + bob driven by replicated
## swim progress (deterministic, no local clocks) — players snapped to lanes,
## catch/streak counts on nameplates, and a splash + sparkle at the line on
## every catch. W/S or stick up/down snaps your lane; ticks play on each
## cadence beat.

const LANE_SPACING := 2.4
const RUNWAY_LEN := 10.0
const FISH_COLOR := Color(0.4, 0.7, 0.95)
const LINE_COLOR := Color(0.4, 0.85, 0.4)
const LANE_DIVIDER := Color(0.55, 0.8, 1.0, 0.6)
## Landed pool-water texture (#929) for the lanes, replacing the flat
## translucent tint. A margin keeps the strips inside the floor bounds —
## they used to overhang past the arena edge into the void at every headcount.
const WATER_TEXTURE := preload("res://assets/generated/textures/water-pool.png")
## Kenney fish models (#1133): swap from SphereMesh+PrismMesh composite to
## real 3D fish models already imported in the repo.
const FISH_MODEL := preload("res://assets/environment/kenney_food_kit/fish.glb")
const FISH_BONES_MODEL := preload("res://assets/environment/kenney_food_kit/fish-bones.glb")
const FISH_SCALE := 1.8
## Pool backdrop (BoxMesh rim) around the arena (#1133).
const POOL_RIM_WIDTH := 0.3
const POOL_RIM_HEIGHT := 0.15
const POOL_RIM_COLOR := Color(0.3, 0.45, 0.55, 0.7)
## Floating buoys at lane boundaries (#1133): TorusMesh ring around SphereMesh.
const BUOY_RADIUS := 0.2
const BUOY_RING_RADIUS := 0.08
const BUOY_COLOR := Color(1.0, 0.6, 0.1)
const LANE_EDGE_MARGIN := 0.4
const FISH_POOL := 12
## Swim motion (M13-19): tail-wag cycles across one lane run, wag angles.
const WAG_CYCLES := 6.0
const BODY_WAG_RAD := 0.22
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


## Aquatic pool mood (#1133): pushes the dusk base toward a cool deep-blue
## underwater tone to match the pool backdrop and water theme.
func _mood() -> Color:
	return Color(0.12, 0.18, 0.3)


## Aqua pool floor (#589).
func _floor_tint() -> Color:
	return Color(0.82, 0.95, 1.0)


## formula-twin — must mirror FishFrenzy._setup (scaled _play_half). The sim
## derives _play_half = MinigameScaling.arena_half(BASE_ARENA_HALF, slots.size());
## this view re-derives the same value. If the scaling formula changes in the
## sim but not here, the rendered floor/camera will mismatch the sim's arena.
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


## Recursively apply a material override to every MeshInstance3D child.
static func _set_fish_material(node: Node, material: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_override = material
		_set_fish_material(child, material)


func _setup_3d() -> void:
	var fish_material := StandardMaterial3D.new()
	fish_material.albedo_color = FISH_COLOR
	fish_material.emission_enabled = true
	fish_material.emission = FISH_COLOR
	fish_material.emission_energy_multiplier = 0.3
	for i in FISH_POOL:
		var root := Node3D.new()
		root.name = "Fish%d" % i
		## ~30% fish-bones for visual variety (every 3rd fish).
		var use_bones := i % 3 == 0
		var model: Node3D
		if use_bones:
			model = FISH_BONES_MODEL.instantiate()
		else:
			model = FISH_MODEL.instantiate()
		_set_fish_material(model, fish_material)
		## Rotate so the model's head (+Z) faces the swim direction (-X).
		model.rotation.y = -PI / 2.0
		model.scale = Vector3.ONE * FISH_SCALE
		root.add_child(model)
		root.visible = false
		arena.add_child(root)
		_fish_pool.append(root)
	# The three lanes are visible water strips with dividers (#238), clamped
	# to the actual (headcount-scaled) floor bounds (#929) instead of a fixed
	# length that could run past the arena edge.
	var half := _arena_half()
	var near_x := -half + LANE_EDGE_MARGIN
	var far_x := half - LANE_EDGE_MARGIN
	var lane_len := far_x - near_x
	var lane_center_x := (near_x + far_x) / 2.0
	for lane_index in FishFrenzy.LANES:
		var strip := BoxMesh.new()
		strip.size = Vector3(lane_len, 0.02, LANE_SPACING * 0.92)
		var strip_material := StandardMaterial3D.new()
		strip_material.albedo_texture = WATER_TEXTURE
		strip_material.uv1_scale = Vector3(lane_len / LANE_SPACING, 1.0, 1.0)
		strip.material = strip_material
		var strip_node := MeshInstance3D.new()
		strip_node.name = "Lane%d" % lane_index
		strip_node.mesh = strip
		strip_node.position = Vector3(lane_center_x, 0.01, _lane_z(lane_index))
		arena.add_child(strip_node)
	for divider_index in FishFrenzy.LANES + 1:
		var divider := BoxMesh.new()
		divider.size = Vector3(lane_len, 0.025, 0.08)
		var divider_material := StandardMaterial3D.new()
		divider_material.albedo_color = LANE_DIVIDER
		divider.material = divider_material
		var divider_node := MeshInstance3D.new()
		divider_node.mesh = divider
		divider_node.position = Vector3(
			lane_center_x, 0.02, _lane_z(0) - LANE_SPACING / 2.0 + divider_index * LANE_SPACING
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
	# Pool backdrop (#1133): BoxMesh rim around the arena perimeter so the
	# lanes read as a swimming pool, not floating strips. Four sides.
	var pool_rim_mat := StandardMaterial3D.new()
	pool_rim_mat.albedo_color = POOL_RIM_COLOR
	pool_rim_mat.metallic = 0.3
	pool_rim_mat.roughness = 0.6
	# Near-side rim (between lanes and catch line)
	_add_pool_rim(pool_rim_mat, Vector3(near_x, 0.0, 0.0), lane_len, true)
	# Far-side rim
	_add_pool_rim(pool_rim_mat, Vector3(far_x, 0.0, 0.0), lane_len, true)
	# Left-side rim
	_add_pool_rim(
		pool_rim_mat,
		Vector3(lane_center_x, 0.0, _lane_z(0) - LANE_SPACING * 0.55),
		lane_len * 0.5,
		false
	)
	# Right-side rim
	_add_pool_rim(
		pool_rim_mat,
		Vector3(lane_center_x, 0.0, _lane_z(FishFrenzy.LANES - 1) + LANE_SPACING * 0.55),
		lane_len * 0.5,
		false
	)
	# Floating buoys (#1133): TorusMesh ring around SphereMesh at each lane
	# boundary near the far end, marking the lane edges.
	for lane_index in FishFrenzy.LANES + 1:
		var buoy_z := _lane_z(0) - LANE_SPACING / 2.0 + lane_index * LANE_SPACING
		var buoy_pos := Vector3(far_x - 0.8, BUOY_RADIUS * 0.8, buoy_z)
		var buoy_root := Node3D.new()
		buoy_root.name = "Buoy%d" % lane_index
		# Sphere body
		var sphere := SphereMesh.new()
		sphere.radius = BUOY_RADIUS
		sphere.height = BUOY_RADIUS * 2.0
		sphere.material = _buoy_material()
		var sphere_node := MeshInstance3D.new()
		sphere_node.mesh = sphere
		buoy_root.add_child(sphere_node)
		# Torus ring
		var ring := TorusMesh.new()
		ring.inner_radius = BUOY_RADIUS * 1.1
		ring.outer_radius = BUOY_RADIUS * 1.1 + BUOY_RING_RADIUS
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = BUOY_COLOR
		ring_mat.emission_enabled = true
		ring_mat.emission = BUOY_COLOR
		ring_mat.emission_energy_multiplier = 0.4
		ring.material = ring_mat
		var ring_node := MeshInstance3D.new()
		ring_node.mesh = ring
		ring_node.rotation.x = PI / 2.0
		buoy_root.add_child(ring_node)
		buoy_root.position = buoy_pos
		arena.add_child(buoy_root)


static func _buoy_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.metallic = 0.2
	mat.roughness = 0.5
	return mat


func _add_pool_rim(material: Material, pos: Vector3, length: float, is_horizontal: bool) -> void:
	var rim := BoxMesh.new()
	if is_horizontal:
		rim.size = Vector3(length, POOL_RIM_HEIGHT, POOL_RIM_WIDTH)
	else:
		rim.size = Vector3(POOL_RIM_WIDTH, POOL_RIM_HEIGHT, length)
	rim.material = material
	var node := MeshInstance3D.new()
	node.mesh = rim
	node.position = pos
	arena.add_child(node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	fish = game.get("fish", [])
	swim_sec = float(game.get("swim_sec", FishFrenzy.SWIM_SEC))
	for i in _fish_pool.size():
		var node := _fish_pool[i]
		if i < fish.size():
			var entry: Array = fish[i]
			var progress := 1.0 - clampf(float(entry[FishFrenzy.FL_ARRIVES]) / swim_sec, 0.0, 1.0)
			# Swim motion rides the replicated progress (M13-19): every client
			# sees the same wag at the same point of the run.
			var wag := sin(progress * WAG_CYCLES * TAU)
			node.position = Vector3(
				lerpf(RUNWAY_LEN, 0.0, progress),
				0.3 + sin(progress * TAU * 2.0) * BOB_HEIGHT,
				_lane_z(int(entry[FishFrenzy.FL_LANE]))
			)
			node.rotation.y = wag * BODY_WAG_RAD
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
		var player_lane := int(state[FishFrenzy.PS_LANE])
		var queue_index := int(lane_queues.get(player_lane, 0))
		lane_queues[player_lane] = queue_index + 1
		update_rig(slot, Vector2(STAND_X - queue_index * QUEUE_SPACING, _lane_z(player_lane)))
		var caption := "%s  🐟%d" % [player_name(slot), int(state[FishFrenzy.PS_CAUGHT])]
		if int(state[FishFrenzy.PS_STREAK]) >= FishFrenzy.STREAK_EVERY:
			caption += "  🔥%d" % int(state[FishFrenzy.PS_STREAK])
		rig.display_name = caption
		# Catch FX (M13-19): a catch is the count ticking up — splash + sparkle
		# at the line in that lane. Seeded so a rejoiner's first snapshot stays
		# calm.
		var catches := int(state[FishFrenzy.PS_CAUGHT])
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
