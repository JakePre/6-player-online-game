extends MinigameView3D
## Laser Limbo client view (M10-06): sweeping laser walls — low beams to jump,
## high beams to duck, full walls with a visible gap. Jumps arc via update_rig
## height, ducks squash the rig, lives ride the nameplate as pips, and losing
## one flinches + shakes.
##
## Reading height from the iso camera (#928, render audit #921): #779's colors +
## back wall + floor stripe still read as flat stripes on the ground. The height
## dimension now reads three ways at once: each beam is an elevated emissive
## CYLINDER at its true jump/duck height; a pair of full-height EMITTER POSTS at
## the beam's ends give the eye a vertical ruler to see where the beam attaches
## (low vs high); and the floor stripe stays as the ground projection, so the
## gap between the glowing beam and its ground line is the height itself.

## Declarative button input (#947): jump the low beams; hold to duck the high
## ones (press ducks, release stands back up).
const INPUT_ACTIONS := {
	&"action_primary": "jump",
	&"action_secondary": {"key": "duck", "held": true},
}
const LASER_COLOR := Color(0.95, 0.15, 0.1, 0.7)
## Per-kind beam colors (#779): the required action reads by hue as well as by
## height — amber = JUMP the low beam, cyan = DUCK the high beam, violet = slip
## through the GAP wall. Named in the intro rules (#928).
const LOW_COLOR := Color(1.0, 0.72, 0.15, 0.85)
const HIGH_COLOR := Color(0.3, 0.82, 1.0, 0.85)
const GAP_COLOR := Color(0.85, 0.3, 0.95, 0.85)
## A dim vertical backstop the beams read their height against (#779, owner's
## "wall on back?"), and a flat floor stripe under each beam so its danger line
## and kind stay legible on the ground plane whatever the camera angle.
const BACK_WALL_COLOR := Color(0.14, 0.1, 0.22, 0.5)
const BACK_WALL_HEIGHT := 2.6
const FLOOR_STRIPE_THICKNESS := 0.04
const WALL_POOL := 8
## Beam heights (#928): a wide low-vs-high separation so the read is unmistakable
## — the low beam sits at shin height (jump it), the high beam at head height
## (duck it). BEAM_RADIUS gives the cylinders body against the floor stripe.
const LOW_BEAM_Y := 0.35
const HIGH_BEAM_Y := 1.7
const BEAM_RADIUS := 0.13
## Emitter posts (#928): the vertical height ruler at each beam end. Tall enough
## to frame both beam heights with headroom; a neutral emissive so the colored
## beam reads as the danger and the post as the structure it hangs on.
const POST_HEIGHT := 2.1
const POST_RADIUS := 0.09
const POST_COLOR := Color(0.6, 0.55, 0.62, 0.9)
const WALL_TALL := 2.2
const JUMP_HEIGHT := 1.0
const DUCK_SCALE := 0.6

## Latest replicated state, straight from LaserLimbo.get_snapshot().
var players := {}
var walls: Array = []
var fallen: Array = []

var _wall_pool: Array[Node3D] = []
var _lives_seen := {}
## Per-kind beam materials (#779), keyed by LaserLimbo.WallKind; all share the
## M13-13 shimmer throb, driven together each snapshot.
var _beam_materials := {}
## Shared neutral material for the emitter posts (#928).
var _post_material: StandardMaterial3D
var _pulse_ticks := 0
var _downed := {}
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _fallen_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Neon violet floor under the sweeping lasers (#589).
func _floor_tint() -> Color:
	return Color(0.92, 0.82, 1.0)


func _arena_half() -> float:
	# Sim and view derive the same scaled play size from the lobby count (M15).
	return MinigameScaling.arena_half(LaserLimbo.ARENA_HALF, names.size())


## Gap half-width scaled to match the sim's `_gap_half` (same fraction of the
## arena), so the rendered opening lines up with the survivable band.
func _gap_half() -> float:
	return LaserLimbo.GAP_HALF_WIDTH * _arena_half() / LaserLimbo.ARENA_HALF


## Each pooled wall is a root carrying every segment; kind decides which show.
## LOW = the low cylinder beam, HIGH = the high one; both flank a pair of
## full-height emitter posts (the height ruler, #928). GAP = two tall halves
## around the opening. Beam/gap segments wear their kind's color (#779); the
## posts are neutral; a per-kind FloorStripe reads the danger line on the ground.
## Geometry that never changes (beam heights, post size/spacing, stripe length)
## is built once here — the play area is fixed for the match — so _update_walls
## only toggles visibility and slides the root in x.
func _setup_3d() -> void:
	_beam_materials = {
		LaserLimbo.WallKind.LOW: _laser_material(LOW_COLOR),
		LaserLimbo.WallKind.HIGH: _laser_material(HIGH_COLOR),
		LaserLimbo.WallKind.GAP: _laser_material(GAP_COLOR),
	}
	_post_material = _laser_material(POST_COLOR)
	_build_back_wall()
	var half := _arena_half()
	for i in WALL_POOL:
		var root := Node3D.new()
		root.name = "Wall%d" % i
		root.visible = false
		_build_beam(root, "Low", LaserLimbo.WallKind.LOW, LOW_BEAM_Y, half)
		_build_beam(root, "High", LaserLimbo.WallKind.HIGH, HIGH_BEAM_Y, half)
		_build_posts(root, half)
		for gap_name: String in ["GapNear", "GapFar"]:
			var gap := MeshInstance3D.new()
			gap.name = gap_name
			gap.mesh = BoxMesh.new()
			(gap.mesh as BoxMesh).material = _beam_materials[LaserLimbo.WallKind.GAP]
			root.add_child(gap)
		var stripe := MeshInstance3D.new()
		stripe.name = "FloorStripe"
		stripe.mesh = BoxMesh.new()
		# Length is fixed; material is re-pointed per snapshot as the pool recycles.
		(stripe.mesh as BoxMesh).size = Vector3(0.28, FLOOR_STRIPE_THICKNESS, half * 2.0)
		stripe.position = Vector3(0.0, FLOOR_STRIPE_THICKNESS / 2.0, 0.0)
		root.add_child(stripe)
		arena.add_child(root)
		_wall_pool.append(root)


## A horizontal emissive cylinder beam spanning the play depth at `beam_y`,
## rotated to lie along z. Fixed geometry — only its visibility toggles (#928).
func _build_beam(root: Node3D, node_name: String, kind: int, beam_y: float, half: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = BEAM_RADIUS
	mesh.bottom_radius = BEAM_RADIUS
	mesh.height = half * 2.0
	mesh.material = _beam_materials[kind]
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.rotation = Vector3(PI / 2.0, 0.0, 0.0)  # cylinder's y-axis → world z (runs the depth)
	node.position = Vector3(0.0, beam_y, 0.0)
	root.add_child(node)


## Two full-height emitter posts at the beam's depth ends — the vertical ruler
## the eye reads a beam's attach height against (#928). Shown for LOW/HIGH.
func _build_posts(root: Node3D, half: float) -> void:
	for post_name: String in ["PostNear", "PostFar"]:
		var mesh := CylinderMesh.new()
		mesh.top_radius = POST_RADIUS
		mesh.bottom_radius = POST_RADIUS
		mesh.height = POST_HEIGHT
		mesh.material = _post_material
		var node := MeshInstance3D.new()
		node.name = post_name
		node.mesh = mesh
		var z := -half if post_name == "PostNear" else half
		node.position = Vector3(0.0, POST_HEIGHT / 2.0, z)
		root.add_child(node)


## A dim translucent panel across the far edge so a HIGH beam reads near its top
## and a LOW beam near its base — a fixed vertical reference the iso camera can't
## foreshorten away (#779, the owner's "wall on back?").
func _build_back_wall() -> void:
	var half := _arena_half()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(half * 2.0, BACK_WALL_HEIGHT, 0.2)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = BACK_WALL_COLOR
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "BackWall"
	node.mesh = mesh
	node.position = Vector3(0.0, BACK_WALL_HEIGHT / 2.0, -half - 0.3)
	arena.add_child(node)


func _laser_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color, 1.0)
	material.emission_energy_multiplier = 1.2
	return material


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	walls = game.get("walls", [])
	fallen = game.get("fallen", [])
	_update_players()
	_update_walls()
	_shake_on_new_downs()
	# Beam shimmer (M13-13): a snapshot-cadence hum, same on every client — driven
	# across all three per-kind materials at once (#779).
	_pulse_ticks += 1
	var glow := 1.2 + 0.4 * sin(_pulse_ticks * TAU / 10.0)
	for material: StandardMaterial3D in _beam_materials.values():
		material.emission_energy_multiplier = glow


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var is_airborne := int(state[LaserLimbo.PS_AIRBORNE]) == 1
		var is_ducking := int(state[LaserLimbo.PS_DUCKING]) == 1
		# While airborne, drive position by hand (force_animate off) and hold the
		# jump pose (#779) so the leap reads as a leap, not a floating walk cycle.
		update_rig(
			slot,
			Vector2(state[LaserLimbo.PS_X], state[LaserLimbo.PS_Y]),
			JUMP_HEIGHT if is_airborne else 0.0,
			not is_airborne
		)
		if is_airborne and rig.current_action() != &"jump_idle":
			rig.play(&"jump_idle")
		rig.scale.y = DUCK_SCALE if is_ducking else 1.0
		var current_lives := int(state[LaserLimbo.PS_LIVES])
		rig.display_name = "%s  %s" % [player_name(slot), "+".repeat(current_lives)]
		if _lives_seen.has(slot) and current_lives < int(_lives_seen[slot]):
			rig.play(&"hit")
			request_shake(7.0)
			# The laser bites (M13-13): electric burst at the hit.
			fx_burst(Vector2(state[LaserLimbo.PS_X], state[LaserLimbo.PS_Y]), LASER_COLOR, 1.0)
			if slot == my_slot:
				# This game's own namesake in the vocabulary (#728).
				play_sfx(&"laser")
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
	fx_burst(Vector2(rig.position.x, rig.position.z), LASER_COLOR, 0.8)


func _update_walls() -> void:
	for i in _wall_pool.size():
		var root := _wall_pool[i]
		root.visible = i < walls.size()
		if not root.visible:
			continue
		var state: Array = walls[i]
		var kind := int(state[LaserLimbo.WL_KIND])
		root.position = Vector3(float(state[LaserLimbo.WL_X]), 0.0, 0.0)
		var is_low := kind == LaserLimbo.WallKind.LOW
		var is_high := kind == LaserLimbo.WallKind.HIGH
		var is_gap := kind == LaserLimbo.WallKind.GAP
		root.get_node("Low").visible = is_low
		root.get_node("High").visible = is_high
		# Emitter posts frame only the beams whose height must be read (#928); the
		# GAP wall's tall halves carry their own vertical reference.
		root.get_node("PostNear").visible = is_low or is_high
		root.get_node("PostFar").visible = is_low or is_high
		var near: MeshInstance3D = root.get_node("GapNear")
		var far: MeshInstance3D = root.get_node("GapFar")
		near.visible = is_gap
		far.visible = is_gap
		# Floor danger-stripe under the beam (#779), recolored to this kind — the
		# ground line the elevated beam's height reads against (#928).
		(root.get_node("FloorStripe").mesh as BoxMesh).material = _beam_materials[kind]
		if is_gap:
			_size_gap(near, far, float(state[LaserLimbo.WL_GAP_Y]))


## Size the two GAP-wall halves around the opening at `gap_y` (varies per wall).
func _size_gap(near: MeshInstance3D, far: MeshInstance3D, gap_y: float) -> void:
	var half := _arena_half()
	var gap := _gap_half()
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
		play_sfx(&"ko")
	_fallen_seen = fallen_count
