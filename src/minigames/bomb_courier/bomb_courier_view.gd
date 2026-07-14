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


## Ember-warm floor for the lit-fuse sprint (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.86, 0.75)


func _arena_half() -> float:
	return BombCourier.ARENA_HALF


func _setup_3d() -> void:
	_build_zone("Pile", BombCourier.PILE_POS, PILE_COLOR)
	_build_zone("Depot", BombCourier.DEPOT_POS, DEPOT_COLOR)
	_build_zone("Defuse", BombCourier.DEFUSE_POS, DEFUSE_COLOR)
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
