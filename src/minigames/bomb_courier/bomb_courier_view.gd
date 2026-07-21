extends MinigameView3D
## Bomb Courier client view (M10-15, on the M8-01 MinigameView3D tier):
## packages are id-keyed crates whose glow reddens as the fuse burns down;
## the pile, delivery depot, and defuse pad are colored floor rings. A
## carried package floats over its courier with a fuse label. Dash lunges
## play the interact pose, detonations flinch + shake the local courier.

const PILE_COLOR := Color(0.6, 0.55, 0.35)
const DEPOT_COLOR := Color(0.4, 0.85, 0.45)
const DEFUSE_COLOR := Color(0.35, 0.6, 0.95)
const CRATE_SIZE := 0.7
const CARRIED_HEIGHT := 2.6
## Bombs should look like bombs (#810): the in-repo Kenney platformer kit
## already ships one. A separate glow ring (below the model, not repainting
## its own materials) still carries the SAFE -> HOT fuse-urgency tint the
## plain colored cube used to show directly.
const BOMB_SCENE := preload("res://assets/environment/kenney_platformer_kit/bomb.glb")
const BOMB_SCALE := 1.0
## Fuse color lerps SAFE -> HOT as it burns from FUSE_MAX to 0.
const SAFE_COLOR := Color(0.9, 0.85, 0.4)
const HOT_COLOR := Color(0.95, 0.2, 0.15)
## FX pass (M13-24): a lit-fuse spark trail off every carried bomb, a burst when
## the bomb changes hands, and a detonation blast on a stagger.
const SPARK_INTERVAL := 0.12
const HANDOFF_FX_COLOR := Color(1.0, 0.85, 0.4)
const BLAST_COLOR := Color(0.95, 0.35, 0.15)
## Fuse-critical warning (#728): matches BombCourierBrain.DUMP_THRESHOLD, the
## same "worth dumping instead of risking it" point the bots already play to.
const ALARM_FUSE_SEC := 1.5
const STONE_FLOOR := preload("res://assets/generated/textures/stone-pavers.png")
## City backdrop (#1122): Kenney City Kit Commercial low-detail buildings as
## rim props around the arena perimeter for an urban courier feel.
const RIM_BUILDINGS: Array[PackedScene] = [
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-a.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-b.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-c.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-d.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-e.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-f.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-g.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-h.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-i.glb"),
	preload("res://assets/environment/kenney_city_kit_commercial/low-detail-building-j.glb"),
]
const RIM_PROP_COUNT := 20
const RIM_PROP_SEED := 45260
## Zone structure models (#1122): crate stack at Pile, desk at Depot, panel at Defuse.
const CRATE_PROP := preload("res://assets/environment/kenney_platformer_kit/crate.glb")
const CRATE_ITEM := preload("res://assets/environment/kenney_platformer_kit/crate-item.glb")

var players := {}
var pile: Array = []

var _crates := {}  # id (int) -> {root, ring}
var _carried := {}  # slot (int) -> {root, ring, label}
var _staggered := {}  # slot (int) -> bool
var _holding := {}  # slot (int) -> bool (last-seen carry state, for handoff FX)
var _spark_accum := 0.0
var _my_score := 0
## Whether the local player's current package has already sounded the
## critical-fuse alarm, so it fires once per carry (#728).
var _fuse_alarmed := false
var _score_label: Label


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		var dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		NetManager.send_match_input({"mx": dir.x, "my": dir.y, "dash": true})
	_trail_fuse_sparks(delta)


## Street texture (#1122): replace the flat tinted floor with IMG-053 stone
## pavers for an urban street feel, giving the bomb-run arena a grounded
## city look instead of the default grey tile.
func _build_floor() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(_arena_half() * 2.0, _arena_half() * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = STONE_FLOOR
	material.albedo_color = Color(1.0, 0.92, 0.85)
	mesh.material = material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = mesh
	floor_node.position.y = -0.01
	arena.add_child(floor_node)


## Ember-warm floor for the lit-fuse sprint (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.86, 0.75)


func _arena_half() -> float:
	return BombCourier.ARENA_HALF


func _setup_3d() -> void:
	_build_zone("Pile", BombCourier.PILE_POS, PILE_COLOR)
	_build_zone("Depot", BombCourier.DEPOT_POS, DEPOT_COLOR)
	_build_zone("Defuse", BombCourier.DEFUSE_POS, DEFUSE_COLOR)
	_build_zone_structures()
	scatter_rim_props(RIM_BUILDINGS, RIM_PROP_COUNT, RIM_PROP_SEED)
	_score_label = make_status_label(&"HintLabel")
	_score_label.text = "Pile → Depot before it blows!"


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	pile = game.get("pile", [])
	_update_players()
	_update_pile()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[BombCourier.PS_X], state[BombCourier.PS_Y]))
		var fuse := float(state[BombCourier.PS_FUSE])
		var staggered := int(state[BombCourier.PS_STAGGERED]) == 1
		var newly_staggered: bool = staggered and not _staggered.get(slot, false)
		var caption := "%s  %d" % [player_name(slot), int(state[BombCourier.PS_SCORE])]
		# Signature cue (#728, docs/AUDIO_GUIDE.md — Bombs & blasts): the
		# detonation reads for everyone, screen-shake stays local to the
		# courier it happened to.
		if newly_staggered:
			play_sfx(&"explosion")
			if slot == my_slot:
				request_shake(7.0)
		if slot == my_slot:
			if not newly_staggered and int(state[BombCourier.PS_SCORE]) > _my_score:
				play_sfx(&"coin")
			_my_score = int(state[BombCourier.PS_SCORE])
		# Handoff flash: a burst the instant a courier takes possession — pickup,
		# catch, or steal — so the pass beat reads across the arena.
		var holding := fuse >= 0.0
		if holding and not _holding.get(slot, false):
			fx_burst(Vector2(rig.position.x, rig.position.z), HANDOFF_FX_COLOR, 1.2)
			if slot == my_slot:
				_fuse_alarmed = false
		if slot == my_slot and holding and fuse < ALARM_FUSE_SEC and not _fuse_alarmed:
			_fuse_alarmed = true
			play_sfx(&"alarm")
		_holding[slot] = holding
		# Detonation blast where a bomb goes off in someone's hands.
		if newly_staggered:
			fx_burst(Vector2(rig.position.x, rig.position.z), BLAST_COLOR, 0.8)
		if staggered and rig.current_action() != &"hit":
			rig.play(&"hit")
		_staggered[slot] = staggered
		rig.display_name = caption
		_update_carried(slot, fuse)


func _update_carried(slot: int, fuse: float) -> void:
	var entry: Dictionary = _carried.get(slot, {})
	var holding := fuse >= 0.0
	if holding and entry.is_empty():
		entry = _build_carried(slot)
		_carried[slot] = entry
	if entry.is_empty():
		return
	var root: Node3D = entry.root
	var label: Label3D = entry.label
	root.visible = holding
	label.visible = holding
	if not holding:
		return
	var rig := rig_for_slot(slot)
	if rig != null:
		root.position = rig.position + Vector3(0.0, CARRIED_HEIGHT, 0.0)
		label.position = rig.position + Vector3(0.0, CARRIED_HEIGHT + 0.7, 0.0)
	_tint_fuse(entry.ring, fuse)
	label.modulate = _fuse_color(fuse)
	label.text = "%.1f" % maxf(fuse, 0.0)


func _update_pile() -> void:
	var seen := {}
	for entry: Array in pile:
		var id := int(entry[BombCourier.PL_ID])
		seen[id] = true
		var crate: Dictionary = _crates.get(id, {})
		if crate.is_empty():
			crate = _build_crate(id)
		(crate.root as Node3D).position = to_arena(
			Vector2(float(entry[BombCourier.PL_X]), float(entry[BombCourier.PL_Y])),
			CRATE_SIZE * 0.5
		)
		_tint_fuse(crate.ring, float(entry[BombCourier.PL_FUSE]))
	for id: int in _crates.keys():
		if not seen.has(id):
			(_crates[id].root as Node3D).queue_free()
			_crates.erase(id)


## Each carried bomb spits sparks on a short cadence — a lit fuse readable from
## across the arena — tinted to the current fuse color, so the trail reddens
## right along with the countdown. Fire-and-forget; the sparks self-free.
func _trail_fuse_sparks(delta: float) -> void:
	_spark_accum += delta
	if _spark_accum < SPARK_INTERVAL:
		return
	_spark_accum = 0.0
	for slot: int in _carried:
		var entry: Dictionary = _carried[slot]
		var root: Node3D = entry.get("root")
		if root == null or not root.visible:
			continue
		var ring: MeshInstance3D = entry.get("ring")
		var material := ring.mesh.surface_get_material(0) as StandardMaterial3D
		fx_sparkle(
			Vector2(root.position.x, root.position.z), material.albedo_color, root.position.y
		)


func _fuse_color(fuse: float) -> Color:
	var t := clampf(fuse / BombCourier.FUSE_MAX, 0.0, 1.0)
	return HOT_COLOR.lerp(SAFE_COLOR, t)


func _tint_fuse(ring: MeshInstance3D, fuse: float) -> void:
	var color := _fuse_color(fuse)
	var material := ring.mesh.surface_get_material(0) as StandardMaterial3D
	material.albedo_color = color
	material.emission = color


## A colored glow ring under the bomb model signals fuse urgency (SAFE ->
## HOT) without repainting the shared model's own materials (#810).
func _build_fuse_ring() -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = CRATE_SIZE * 0.55
	mesh.outer_radius = CRATE_SIZE * 0.8
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "FuseRing"
	node.mesh = mesh
	node.rotation.x = PI / 2.0
	return node


func _build_crate(id: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Crate%d" % id
	var model: Node3D = BOMB_SCENE.instantiate()
	model.scale = Vector3.ONE * BOMB_SCALE
	root.add_child(model)
	var ring := _build_fuse_ring()
	root.add_child(ring)
	arena.add_child(root)
	var entry := {"root": root, "ring": ring}
	_crates[id] = entry
	return entry


func _build_carried(slot: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Carried%d" % slot
	var model: Node3D = BOMB_SCENE.instantiate()
	model.scale = Vector3.ONE * BOMB_SCALE
	root.add_child(model)
	var ring := _build_fuse_ring()
	root.add_child(ring)
	arena.add_child(root)
	# Big, always-readable countdown (#810) — the same fixed_size/pixel_size
	# convention CharacterRig's nameplate uses (SPEC $11), scaled up further
	# since an urgent fuse timer needs to read at a glance more than a name.
	var label := Label3D.new()
	label.name = "Fuse%d" % slot
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.002
	label.outline_size = 24
	label.font_size = 72
	arena.add_child(label)
	return {"root": root, "ring": ring, "label": label}


func _build_zone(node_name: String, pos: Vector2, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = BombCourier.ZONE_RADIUS
	mesh.bottom_radius = BombCourier.ZONE_RADIUS
	mesh.height = 0.08
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.4
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = to_arena(pos, 0.04)
	arena.add_child(node)
	_build_zone_label(node_name, pos, color)


## A floating name tag over each zone (#929) — the three colored rings alone
## didn't say which was which.
func _build_zone_label(node_name: String, pos: Vector2, color: Color) -> void:
	var label := Label3D.new()
	label.name = "%sLabel" % node_name
	label.text = node_name.to_upper()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.002
	label.font_size = 40
	label.outline_size = 12
	label.modulate = color.lightened(0.4)
	label.position = to_arena(pos, 1.4)
	arena.add_child(label)


## Decorative structures on top of each zone ring (#1122) so the three
## functional areas read as real places, not just colored floor rings.
func _build_zone_structures() -> void:
	_build_pile_structure(BombCourier.PILE_POS)
	_build_depot_structure(BombCourier.DEPOT_POS)
	_build_defuse_structure(BombCourier.DEFUSE_POS)


## Pile zone: a small stack of wooden crates at the spawn point — two crates
## side-by-side with a third on top, read as the package staging area.
func _build_pile_structure(pos: Vector2) -> void:
	var stack := Node3D.new()
	stack.name = "PileStructure"
	# Bottom layer: two crates side by side.
	for side in [-1, 1]:
		var crate: Node3D = CRATE_PROP.instantiate()
		crate.position = Vector3(side * 0.5, 0.0, 0.0)
		stack.add_child(crate)
	# Top crate, rotated 45° and raised.
	var top: Node3D = CRATE_ITEM.instantiate()
	top.position = Vector3(0.0, 0.7, 0.0)
	top.rotation.y = PI / 4.0
	stack.add_child(top)
	stack.position = to_arena(pos, 0.0)
	arena.add_child(stack)


## Depot zone: a delivery desk — a wooden plank surface on two legs, with
## a small label reading "DELIVER HERE".
func _build_depot_structure(pos: Vector2) -> void:
	var desk := Node3D.new()
	desk.name = "DepotStructure"
	# Table top.
	var top := MeshInstance3D.new()
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(1.8, 0.06, 0.9)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.55, 0.4, 0.25)
	tmesh.material = tmat
	top.mesh = tmesh
	top.position = Vector3(0.0, 1.0, 0.0)
	desk.add_child(top)
	# Two legs.
	for side in [-0.75, 0.75]:
		var leg := MeshInstance3D.new()
		var lmesh := CylinderMesh.new()
		lmesh.top_radius = 0.06
		lmesh.bottom_radius = 0.06
		lmesh.height = 0.95
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.35, 0.25, 0.15)
		lmesh.material = lmat
		leg.mesh = lmesh
		leg.position = Vector3(side, 0.475, 0.0)
		desk.add_child(leg)
	desk.position = to_arena(pos, 0.0)
	arena.add_child(desk)


## Defuse zone: a control panel — a dark box with a glowing green button
## on top, reading as the defuse terminal.
func _build_defuse_structure(pos: Vector2) -> void:
	var panel := Node3D.new()
	panel.name = "DefuseStructure"
	# Panel base.
	var base := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.0, 0.6, 0.6)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.2, 0.22, 0.25)
	bmesh.material = bmat
	base.mesh = bmesh
	base.position = Vector3(0.0, 0.3, 0.0)
	panel.add_child(base)
	# Glowing button on top.
	var button := MeshInstance3D.new()
	var smesh := SphereMesh.new()
	smesh.radius = 0.12
	smesh.height = 0.24
	var smat := StandardMaterial3D.new()
	smat.albedo_color = DEFUSE_COLOR
	smat.emission_enabled = true
	smat.emission = DEFUSE_COLOR
	smat.emission_energy_multiplier = 0.8
	smesh.material = smat
	button.mesh = smesh
	button.position = Vector3(0.0, 0.65, 0.0)
	panel.add_child(button)
	# Small screen panel on the front.
	var screen := MeshInstance3D.new()
	var scmesh := BoxMesh.new()
	scmesh.size = Vector3(0.5, 0.25, 0.03)
	var scmat := StandardMaterial3D.new()
	scmat.albedo_color = Color(0.05, 0.08, 0.1)
	scmat.emission_enabled = true
	scmat.emission = Color(0.0, 0.4, 0.15)
	scmat.emission_energy_multiplier = 0.3
	scmesh.material = scmat
	screen.mesh = scmesh
	screen.position = Vector3(0.0, 0.35, -0.32)
	panel.add_child(screen)
	panel.position = to_arena(pos, 0.0)
	arena.add_child(panel)
