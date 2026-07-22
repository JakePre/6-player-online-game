extends MinigameView3D
## Shock Tag client view (M10-03): renders the replicated arena in the shared
## 2.5D iso-arena — players as CharacterRigs with coin counts on nameplates,
## the electrified player marked by a crackling emissive ring underfoot. Tags
## (the zap changing hands) shake the screen.
##
## Visual enhancements (#1153): metal-deck floor, buzzing secondary ring,
## visible electric beam on hand-off, storm cloud overhead, floor sparks,
## rim props, and a dark electric mood.

const RING_COLOR := Color(1.0, 0.9, 0.25, 0.6)
const RING_HEIGHT := 0.05
## Secondary buzzing ring (#1153): a cooler, dimmer ring outside the main one
## that pulses at a different frequency for a chaotic electric feel.
const BUZZ_COLOR := Color(0.55, 0.75, 1.0, 0.3)
const BUZZ_RADIUS_MULT := 2.8
const BUZZ_HEIGHT := 0.03
## Metal-deck floor texture (#1153): industrial diamond-plate feel for the
## electric arena, matching blast_grid / bey_brawl's floor-texture idiom.
const FLOOR_TEXTURE := preload("res://assets/generated/textures/metal-deck.png")
const FLOOR_TEXTURE_TILES := 4.0
## Storm cloud (#1153): a cluster of dark spheres above the zapped player.
const CLOUD_HEIGHT := 4.0
const CLOUD_RADIUS := 0.8
const CLOUD_PARTS := 6
const CLOUD_COLOR := Color(0.15, 0.15, 0.18)
## Floor spark patterns (#1153): small emissive dots at the zapped player's
## location, pulsing with the crackle.
const SPARK_COLOR := Color(0.7, 0.9, 1.0)
const SPARK_RADIUS := 0.12
const SPARK_HEIGHT := 0.02
const SPARK_COUNT := 5
## Arena-edge rubble (#1153): rocks + barrels ring the electric arena so the
## stadium sits in a rugged space rather than bare grey.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/rock_smallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallB.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_tallA.glb"),
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
	preload("res://assets/environment/kenney_platformer_kit/crate.glb"),
]
const RIM_PROP_COUNT := 16
const RIM_PROP_SEED := 0xBE57

## Latest replicated state, straight from ShockTag.get_snapshot().
var players := {}
var zapped := -1

var _ring: MeshInstance3D
var _ring_buzz: MeshInstance3D
var _storm_cloud: Node3D
var _spark_nodes: Array[MeshInstance3D] = []
## Snapshot counter driving the crackle-ring pulse (replicated cadence, no
## local clocks — M13-09).
var _pulse_ticks := 0
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _zapped_seen := -1
## Storm cloud flash timer; decremented each snapshot, triggers a brief emissive
## spike on the cloud when it hits 0.
var _flash_countdown := 0


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Dark electric mood (#1153): a cool, dim backstage atmosphere for the
## storm-cloud backdrop.
func _mood() -> Color:
	return Color(0.12, 0.14, 0.2)


## Cool electric-blue floor for the shock arena (#589).
func _floor_tint() -> Color:
	return Color(0.82, 0.9, 1.0)


## Metal-deck floor (#1153): swap the default grey platform for the IMG-057
## diamond-plate texture so the ring of floor reads as an industrial electric
## deck (blast_grid / bey_brawl's floor-texture idiom).
func _build_floor() -> void:
	var floor_node := _dresser.build_floor(_floor_tile_scene(), _floor_tint(), _arena_half())
	if floor_node != null:
		var mat := floor_node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_texture = FLOOR_TEXTURE
			mat.uv1_scale = Vector3(FLOOR_TEXTURE_TILES, FLOOR_TEXTURE_TILES, 1.0)


func _arena_half() -> float:
	return ShockTag.ARENA_HALF


func _setup_3d() -> void:
	_build_zap_ring()
	_build_buzz_ring()
	_build_storm_cloud()
	_build_floor_sparks()
	# Rugged arena edge (#1153): rocks/barrels ring the metal floor.
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


## Main crackle ring — the electrified player's glowing underfoot marker.
func _build_zap_ring() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = ShockTag.PLAYER_RADIUS * 1.4
	mesh.outer_radius = ShockTag.PLAYER_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = RING_COLOR
	material.emission_enabled = true
	material.emission = Color(RING_COLOR, 1.0)
	material.emission_energy_multiplier = 0.8
	mesh.material = material
	_ring = MeshInstance3D.new()
	_ring.name = "ZapRing"
	_ring.mesh = mesh
	_ring.visible = false
	arena.add_child(_ring)


## Secondary buzzing ring (#1153): a cooler, dimmer ring outside the main one
## that pulses at a different frequency for a chaotic electric feel.
func _build_buzz_ring() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = ShockTag.PLAYER_RADIUS * BUZZ_RADIUS_MULT * 0.85
	mesh.outer_radius = ShockTag.PLAYER_RADIUS * BUZZ_RADIUS_MULT
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = BUZZ_COLOR
	material.emission_enabled = true
	material.emission = Color(BUZZ_COLOR, 1.0)
	material.emission_energy_multiplier = 0.4
	mesh.material = material
	_ring_buzz = MeshInstance3D.new()
	_ring_buzz.name = "BuzzRing"
	_ring_buzz.mesh = mesh
	_ring_buzz.visible = false
	arena.add_child(_ring_buzz)


## Storm cloud (#1153): a cluster of dark spheres above the zapped player,
## reading as a menacing electric overhead. Occasionally flashes white.
func _build_storm_cloud() -> void:
	_storm_cloud = Node3D.new()
	_storm_cloud.name = "StormCloud"
	_storm_cloud.visible = false
	arena.add_child(_storm_cloud)
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = CLOUD_COLOR
	cloud_mat.emission_enabled = true
	cloud_mat.emission = CLOUD_COLOR
	cloud_mat.emission_energy_multiplier = 0.05
	for i in CLOUD_PARTS:
		var angle := TAU * float(i) / float(CLOUD_PARTS)
		var offset := Vector3(
			cos(angle) * CLOUD_RADIUS, sin(angle * 2.0) * 0.3, sin(angle) * CLOUD_RADIUS
		)
		var smesh := SphereMesh.new()
		smesh.radius = 0.3 + 0.15 * (i % 3)
		smesh.height = smesh.radius * 2.0
		var mat := cloud_mat.duplicate() as StandardMaterial3D
		smesh.material = mat
		var node := MeshInstance3D.new()
		node.name = "CloudPart%d" % i
		node.mesh = smesh
		node.position = offset
		node.set_meta(&"_cloud_mat", mat)
		_storm_cloud.add_child(node)


## Floor spark patterns (#1153): small emissive dots at the zapped player's
## position, pulsing with the crackle ring cadence.
func _build_floor_sparks() -> void:
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = SPARK_COLOR
	spark_mat.emission_enabled = true
	spark_mat.emission = SPARK_COLOR
	spark_mat.emission_energy_multiplier = 0.5
	for i in SPARK_COUNT:
		var smesh := SphereMesh.new()
		smesh.radius = SPARK_RADIUS
		smesh.height = SPARK_HEIGHT
		var mat := spark_mat.duplicate() as StandardMaterial3D
		smesh.material = mat
		var node := MeshInstance3D.new()
		node.name = "FloorSpark%d" % i
		node.mesh = smesh
		node.visible = false
		_spark_nodes.append(node)
		arena.add_child(node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	zapped = int(game.get("zapped", -1))
	_update_players()
	_update_rings()
	_update_storm_cloud()
	_update_floor_sparks()
	if _zapped_seen >= 0 and zapped != _zapped_seen:
		request_shake(9.0)
		_zap_arc(_zapped_seen, zapped)
		# Personal read on the hand-off (M12-02): stuck with it stings, passing
		# it off relieves. `zap` (#728, docs/AUDIO_GUIDE.md) is this game's own
		# literal namesake in the vocabulary.
		if zapped == my_slot:
			play_sfx(&"zap")
		elif _zapped_seen == my_slot:
			play_sfx(&"confirm")
	_zapped_seen = zapped


## The tag reads as electricity (M13-09): a yellow-white burst at both ends
## of the hand-off — the old carrier discharging, the new one lighting up —
## plus a visible electric beam (#1153) between the two positions.
func _zap_arc(from_slot: int, to_slot: int) -> void:
	var from_state: Array = players.get(from_slot, [])
	var to_state: Array = players.get(to_slot, [])
	if from_state.size() <= ShockTag.PS_Y or to_state.size() <= ShockTag.PS_Y:
		return
	var from_pos := Vector2(from_state[ShockTag.PS_X], from_state[ShockTag.PS_Y])
	var to_pos := Vector2(to_state[ShockTag.PS_X], to_state[ShockTag.PS_Y])
	# Particle burst at both ends (M13-09).
	for slot in [from_slot, to_slot]:
		fx_burst(from_pos if slot == from_slot else to_pos, RING_COLOR, 1.0)
	# Visible electric beam (#1153): a thin emissive elongated BoxMesh
	# connecting the old carrier to the new one.
	var mid := (from_pos + to_pos) * 0.5
	var length := maxf(from_pos.distance_to(to_pos), 0.1)
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.08, 0.04, length)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(RING_COLOR, 0.85)
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(RING_COLOR, 1.0)
	beam_mat.emission_energy_multiplier = 1.5
	beam_mesh.material = beam_mat
	var beam := MeshInstance3D.new()
	beam.name = "ZapArc%d" % randi()
	beam.mesh = beam_mesh
	beam.position = to_arena(mid, 0.15)
	beam.rotation.y = atan2(to_pos.x - from_pos.x, to_pos.y - from_pos.y)
	arena.add_child(beam)
	# Self-free after a brief visible arc.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(beam.queue_free)
	timer.timeout.connect(timer.queue_free)
	arena.add_child(timer)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[ShockTag.PS_X], state[ShockTag.PS_Y]))
		var caption := "%s  %d" % [player_name(slot), int(state[ShockTag.PS_COINS])]
		if slot == zapped:
			caption += "  ZAP!"
		rig.display_name = caption


## Updates both the main zap ring and the secondary buzzing ring (#1153).
func _update_rings() -> void:
	var state: Array = players.get(zapped, [])
	var show := state.size() > ShockTag.PS_Y
	_ring.visible = show
	_ring_buzz.visible = show
	if show:
		var pos := Vector2(state[ShockTag.PS_X], state[ShockTag.PS_Y])
		_ring.position = to_arena(pos, RING_HEIGHT)
		_ring_buzz.position = to_arena(pos, BUZZ_HEIGHT)
		# Main crackle pulse (M13-09): throb every few snapshots.
		_pulse_ticks += 1
		var throb := 1.0 + 0.18 * sin(_pulse_ticks * TAU / 12.0)
		_ring.scale = Vector3(throb, 1.0, throb)
		# Buzzing ring (#1153): pulses at a different frequency so the two rings
		# create a chaotic electric feel.
		var buzz := 1.0 + 0.12 * sin(_pulse_ticks * TAU / 7.0 + 1.2)
		_ring_buzz.scale = Vector3(buzz, 1.0, buzz)


## Storm cloud (#1153): follows the zapped player, visible only while someone
## carries the tag. Occasionally flashes white (lightning).
func _update_storm_cloud() -> void:
	var state: Array = players.get(zapped, [])
	var show := state.size() > ShockTag.PS_Y
	_storm_cloud.visible = show
	if show:
		_storm_cloud.position = to_arena(
			Vector2(state[ShockTag.PS_X], state[ShockTag.PS_Y]), CLOUD_HEIGHT
		)
		# Occasional lightning flash: whiten the cloud briefly.
		_flash_countdown -= 1
		if _flash_countdown <= 0:
			# Random interval between 8 and 24 snapshots (~0.3s–0.8s at 30 Hz).
			_flash_countdown = 8 + randi() % 17
			for node: Node in _storm_cloud.get_children():
				if node is MeshInstance3D:
					var mat := node.get_meta(&"_cloud_mat") as StandardMaterial3D
					if mat != null:
						mat.emission = Color.WHITE
						mat.emission_energy_multiplier = 1.0
						# Fade back to dark after one snapshot via a deferred reset.
						var reset := func():
							mat.emission = CLOUD_COLOR
							mat.emission_energy_multiplier = 0.05
						reset.call_deferred()
	# Keep cloud dark when not zapped (no stale flash state).
	else:
		_flash_countdown = 0


## Floor spark patterns (#1153): small emissive dots ring the zapped player's
## position, pulsing with the ring cadence.
func _update_floor_sparks() -> void:
	var state: Array = players.get(zapped, [])
	var show := state.size() > ShockTag.PS_Y
	var pos := Vector2.ZERO
	if show:
		pos = Vector2(state[ShockTag.PS_X], state[ShockTag.PS_Y])
	for i in _spark_nodes.size():
		var node := _spark_nodes[i]
		if show:
			var angle := TAU * float(i) / float(_spark_nodes.size()) + _pulse_ticks * 0.05
			var offset := Vector2(cos(angle), sin(angle)) * (ShockTag.PLAYER_RADIUS * 1.5)
			var spark_pos := to_arena(pos + offset, SPARK_HEIGHT)
			node.position = spark_pos
			# Pulse with the ring cadence.
			var spark_scale := 1.0 + 0.5 * sin(_pulse_ticks * TAU / 12.0 + float(i) * 1.5)
			node.scale = Vector3(spark_scale, 1.0, spark_scale)
		node.visible = show
