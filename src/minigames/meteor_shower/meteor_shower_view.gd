extends MinigameView3D
## Meteor Shower client view (M10-01 + M13-07 FX): renders the replicated
## arena in the shared 2.5D iso-arena — players as CharacterRigs (knocked-out
## players collapse and dim where the meteor caught them), the shrinking safe
## zone as a cool translucent disc, telegraphed impact points as red discs
## that grow to full impact size as the meteor closes in — and the meteors
## themselves: rocks with emissive trails streaking down from the sky, their
## height driven by the replicated time-left so the fall is perfectly synced
## with the sim. Landings fire an impact burst + dust; knockdowns burst at
## the rig. Impacts shake the screen.

const ZONE_COLOR := Color(0.45, 0.7, 0.95, 0.22)
const ZONE_DISC_HEIGHT := 0.04
const TELEGRAPH_COLOR := Color(0.9, 0.2, 0.12, 0.5)
const TELEGRAPH_POOL := 12
const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
## Falling rocks (M13-07): spawn height and look.
const METEOR_DROP_HEIGHT := 14.0
const METEOR_ROCK_COLOR := Color(0.45, 0.3, 0.22)
const METEOR_TRAIL_COLOR := Color(1.0, 0.55, 0.15, 0.7)
const IMPACT_BURST_COLOR := Color(1.0, 0.5, 0.1)

## Latest replicated state, straight from MeteorShower.get_snapshot().
var players := {}
var zone: Array = []
var meteors: Array = []
var fallen: Array = []

var _zone_node: MeshInstance3D
var _telegraph_pool: Array[MeshInstance3D] = []
var _meteor_pool: Array[Node3D] = []
# [x, y, left] rows from the previous snapshot, to spot landings.
var _meteors_seen: Array = []
var _downed := {}  # slot (int) -> true, once the ko pose + dim have been applied
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _fallen_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Warm ember/ash floor under the falling meteors (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.84, 0.74)


func _arena_half() -> float:
	# Sim and view derive the same play size from the lobby count via the
	# shared base const, so the rendered floor/camera match the scaled arena.
	return MinigameScaling.arena_half(MeteorShower.ARENA_HALF, names.size())


func _setup_3d() -> void:
	_zone_node = _build_disc("Zone", ZONE_COLOR)
	_zone_node.visible = false
	for i in TELEGRAPH_POOL:
		var marker := _build_disc("Telegraph%d" % i, TELEGRAPH_COLOR)
		marker.visible = false
		_telegraph_pool.append(marker)
		_meteor_pool.append(_build_meteor(i))


## A falling rock: craggy sphere with a stretched emissive trail above it.
func _build_meteor(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Meteor%d" % index
	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.5
	rock_mesh.height = 1.0
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = METEOR_ROCK_COLOR
	rock_material.emission_enabled = true
	rock_material.emission = METEOR_TRAIL_COLOR
	rock_material.emission_energy_multiplier = 0.5
	rock_mesh.material = rock_material
	rock.mesh = rock_mesh
	root.add_child(rock)
	var trail := MeshInstance3D.new()
	trail.name = "Trail"
	var trail_mesh := CylinderMesh.new()
	trail_mesh.top_radius = 0.05
	trail_mesh.bottom_radius = 0.3
	trail_mesh.height = 3.0
	var trail_material := StandardMaterial3D.new()
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.albedo_color = METEOR_TRAIL_COLOR
	trail_material.emission_enabled = true
	trail_material.emission = Color(METEOR_TRAIL_COLOR, 1.0)
	trail_material.emission_energy_multiplier = 1.0
	trail_mesh.material = trail_material
	trail.mesh = trail_mesh
	trail.position.y = 1.8
	root.add_child(trail)
	root.visible = false
	arena.add_child(root)
	return root


func _build_disc(disc_name: String, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = ZONE_DISC_HEIGHT
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color, 1.0)
	material.emission_energy_multiplier = 0.3
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = disc_name
	node.mesh = mesh
	arena.add_child(node)
	return node


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	zone = game.get("zone", [])
	meteors = game.get("meteors", [])
	fallen = game.get("fallen", [])
	_update_players()
	_update_zone()
	_update_telegraphs()
	_update_falling_meteors()
	_burst_on_landings()
	_shake_on_new_downs()


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


## Knocked-out players collapse and dim where the meteor (or the zone edge)
## caught them; the snapshot stops carrying their position. The hit itself
## bursts at the rig (M13-07).
func _down_rig(slot: int) -> void:
	if _downed.has(slot):
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	_downed[slot] = true
	rig.play(&"ko")
	rig.player_color = ELIMINATED_COLOR
	fx_burst(Vector2(rig.position.x, rig.position.z), IMPACT_BURST_COLOR)


## The rocks themselves (M13-07): height rides the replicated time-left, so
## every client sees the same fall the sim is timing.
func _update_falling_meteors() -> void:
	for i in _meteor_pool.size():
		var rock := _meteor_pool[i]
		rock.visible = i < meteors.size()
		if not rock.visible:
			continue
		var state: Array = meteors[i]
		var progress := clampf(float(state[2]) / MeteorShower.METEOR_TELEGRAPH_SEC, 0.0, 1.0)
		rock.position = to_arena(Vector2(state[0], state[1]), METEOR_DROP_HEIGHT * progress + 0.5)


## A meteor that left the snapshot with its timer nearly spent just landed:
## impact burst + dust at its last position (M13-07).
func _burst_on_landings() -> void:
	for old: Array in _meteors_seen:
		if float(old[2]) > 0.2:
			continue
		var still_falling := false
		for current: Array in meteors:
			if (
				absf(float(current[0]) - float(old[0])) < 0.01
				and absf(float(current[1]) - float(old[1])) < 0.01
			):
				still_falling = true
				break
		if not still_falling:
			var at := Vector2(float(old[0]), float(old[1]))
			fx_burst(at, IMPACT_BURST_COLOR)
			fx_dust(at)
	_meteors_seen = meteors.duplicate(true)


func _update_zone() -> void:
	_zone_node.visible = zone.size() == 3
	if not _zone_node.visible:
		return
	_zone_node.position = to_arena(Vector2(zone[0], zone[1]), ZONE_DISC_HEIGHT / 2.0)
	var radius := maxf(float(zone[2]), 0.001)
	_zone_node.scale = Vector3(radius, 1.0, radius)


## Telegraph discs grow from half to full impact size as the timer runs out,
## so "how urgent" is readable at a glance.
func _update_telegraphs() -> void:
	for i in _telegraph_pool.size():
		var marker := _telegraph_pool[i]
		marker.visible = i < meteors.size()
		if not marker.visible:
			continue
		var state: Array = meteors[i]
		var urgency := 1.0 - clampf(float(state[2]) / MeteorShower.METEOR_TELEGRAPH_SEC, 0.0, 1.0)
		var radius := MeteorShower.METEOR_RADIUS * lerpf(0.5, 1.0, urgency)
		marker.position = to_arena(Vector2(state[0], state[1]), ZONE_DISC_HEIGHT)
		marker.scale = Vector3(radius, 1.0, radius)


func _shake_on_new_downs() -> void:
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _fallen_seen >= 0 and fallen_count > _fallen_seen:
		request_shake(11.0)
		play_sfx(&"error")
	_fallen_seen = fallen_count
