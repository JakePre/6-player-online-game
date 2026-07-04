extends MinigameView3D
## King of the Hill client view (M8-04): renders the replicated arena in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — players as CharacterRig
## instances (position/facing/walk-idle from the snapshot, points on the
## nameplate), the shrinking scoring zone as a translucent gold disc on the
## floor. Presentation-tier swap only: state storage and the render contract
## are unchanged from the 2D pass (M4-01).

const ZONE_COLOR := Color(0.96, 0.79, 0.2, 0.35)
const ZONE_ANCHORED_COLOR := Color(0.3, 0.75, 0.95, 0.45)
const PILLAR_COLOR := Color(0.4, 0.38, 0.45)
const PILLAR_HEIGHT := 1.6
const ITEM_COLORS: Array[Color] = [Color(0.95, 0.4, 0.25), Color(0.3, 0.75, 0.95)]
const ITEM_NAMES: Array[String] = ["SHOVE", "ANCHOR"]
## Unit-radius disc; the node's X/Z scale is the zone radius from the snapshot.
const ZONE_DISC_HEIGHT := 0.04

## Latest replicated state, straight from KingOfTheHill.get_snapshot().
var players := {}
var zone: Array = []
var items: Array = []
var held := {}
var anchored := false

var _zone_node: MeshInstance3D
var _zone_material: StandardMaterial3D
var _pillars_built := false
var _item_nodes: Array[MeshInstance3D] = []
var _held_label: Label
## Last-seen held map, for pickup-moment detection (#260).
var _last_held := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return KingOfTheHill.ARENA_HALF


func _setup_3d() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = ZONE_DISC_HEIGHT
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = ZONE_COLOR
	material.emission_enabled = true
	material.emission = Color(ZONE_COLOR, 1.0)
	material.emission_energy_multiplier = 0.3
	mesh.material = material
	_zone_material = material
	_zone_node = MeshInstance3D.new()
	_zone_node.name = "Zone"
	_zone_node.mesh = mesh
	_zone_node.visible = false
	arena.add_child(_zone_node)
	# Held-item indicator for the local player (#139), above the 3D viewport.
	_held_label = Label.new()
	_held_label.name = "HeldItem"
	_held_label.add_theme_font_size_override(&"font_size", 24)
	_held_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_held_label.position.y -= 48.0
	_held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_held_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"use": true})


## Pillars are static per round; built once from the first snapshot carrying
## them (#139).
func _build_pillars(pillar_list: Array) -> void:
	_pillars_built = true
	for pillar: Array in pillar_list:
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(pillar[2])
		mesh.bottom_radius = float(pillar[2]) * 1.15
		mesh.height = PILLAR_HEIGHT
		var material := StandardMaterial3D.new()
		material.albedo_color = PILLAR_COLOR
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = to_arena(Vector2(float(pillar[0]), float(pillar[1])), PILLAR_HEIGHT / 2.0)
		arena.add_child(node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	zone = game.get("zone", [])
	items = game.get("items", [])
	held = game.get("held", {})
	anchored = bool(game.get("anchored", false))
	if not _pillars_built and game.has("pillars"):
		_build_pillars(game.pillars)
	_zone_material.albedo_color = ZONE_ANCHORED_COLOR if anchored else ZONE_COLOR
	_update_items()
	_update_held()
	_update_players()
	_update_zone()


func _update_items() -> void:
	for node in _item_nodes:
		node.queue_free()
	_item_nodes.clear()
	for item: Array in items:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.5, 0.5)
		var material := StandardMaterial3D.new()
		var color: Color = ITEM_COLORS[clampi(int(item[2]), 0, 1)]
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.4
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = to_arena(Vector2(float(item[0]), float(item[1])), 0.4)
		arena.add_child(node)
		_item_nodes.append(node)


## Pickup flash + sound so grabbing reads (#260).
func _update_held_feedback() -> void:
	for slot: int in held:
		if not _last_held.has(slot) and slot == my_slot:
			play_sfx(&"coin")
	_last_held = held.duplicate()


func _update_held() -> void:
	_update_held_feedback()
	if _held_label == null:
		return
	if held.has(my_slot):
		var item := clampi(int(held[my_slot]), 0, 1)
		_held_label.text = "%s — press Space / Ⓐ" % ITEM_NAMES[item]
		_held_label.modulate = ITEM_COLORS[item]
	else:
		_held_label.text = ""


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		rig.display_name = "%s  %d" % [player_name(slot), int(state[2])]


func _update_zone() -> void:
	_zone_node.visible = zone.size() == 3
	if not _zone_node.visible:
		return
	_zone_node.position = to_arena(Vector2(zone[0], zone[1]), ZONE_DISC_HEIGHT / 2.0)
	# The sim never shrinks below ZONE_MIN_RADIUS; the floor only guards a
	# malformed snapshot from producing a degenerate (zero-scale) basis.
	var radius := maxf(float(zone[2]), 0.001)
	_zone_node.scale = Vector3(radius, 1.0, radius)
