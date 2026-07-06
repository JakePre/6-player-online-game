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
## How long a fired shove's rig animation is protected from update_rig()'s
## walk/idle overwrite (#587) — the same _reaction_hold idiom rumble_ring
## uses for hit/ko, ported here since KotH detects item-use by diffing
## `held` rather than a dedicated event.
const SHOVE_HOLD_SEC := 0.6

## Latest replicated state, straight from KingOfTheHill.get_snapshot().
var players := {}
var zone: Array = []
var items: Array = []
var held := {}
var anchored := false

var _zone_node: MeshInstance3D
var _zone_material: StandardMaterial3D
# M13-03 FX state: zone center for relocation bursts, per-slot points for
# scoring sparkles, snapshot counter for the shimmer throb.
var _zone_center_seen := Vector2.INF
var _points_seen := {}
var _pulse_ticks := 0
var _pillars_built := false
var _item_nodes: Array[MeshInstance3D] = []
var _held_label: Label
## Last-seen held map, for pickup-moment detection (#260).
var _last_held := {}
## slot -> Time.get_ticks_msec() expiry while the shove animation owns the rig.
var _shove_hold := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Cool mossy-green hilltop floor (#589).
func _floor_tint() -> Color:
	return Color(0.85, 0.96, 0.85)


func _arena_half() -> float:
	# Grow the framed floor with the lobby to match the sim's scaled play area
	# (M15, ADR 003 F4); at <=6 players this is the tuned KingOfTheHill.ARENA_HALF.
	return MinigameScaling.arena_half(KingOfTheHill.ARENA_HALF, names.size())


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
	# Held-item indicator for the local player (#139), on the always-on-top
	# banner layer (#258).
	_held_label = make_banner(&"HeldItem")


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


## Pickup flash + sound so grabbing reads (#260), plus a shove animation on
## the rig the instant a held Shove Blast fires (#587): the item clearing
## from `held` while it was SHOVE is the use-moment (no dedicated "used"
## event in the snapshot).
func _update_held_feedback() -> void:
	for slot: int in held:
		if not _last_held.has(slot) and slot == my_slot:
			play_sfx(&"coin")
	for slot: int in _last_held:
		if held.has(slot):
			continue
		if int(_last_held[slot]) != KingOfTheHill.Item.SHOVE:
			continue
		var rig := rig_for_slot(slot)
		if rig != null:
			rig.play(&"interact")
			_shove_hold[slot] = Time.get_ticks_msec() + int(SHOVE_HOLD_SEC * 1000.0)
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
		if Time.get_ticks_msec() < int(_shove_hold.get(slot, 0)):
			# The shove animation owns the rig for a moment (#587): move it,
			# don't re-animate it — mirrors rumble_ring's hit/ko reaction hold.
			rig.position = to_arena(Vector2(state[0], state[1]))
		else:
			update_rig(slot, Vector2(state[0], state[1]))
		rig.display_name = "%s  %d" % [player_name(slot), int(state[2])]
		# Scoring sparkles (M13-03): points ticking up while holding the hill
		# shed a sparkle in the scorer's color. Seeded via _points_seen.
		var points := int(state[2])
		if _points_seen.has(slot) and points > int(_points_seen[slot]):
			fx_sparkle(Vector2(state[0], state[1]), player_color(slot))
		_points_seen[slot] = points


func _update_zone() -> void:
	_zone_node.visible = zone.size() == 3
	if not _zone_node.visible:
		return
	# Shimmer throb + relocation FX (M13-03): the disc breathes on a snapshot
	# cadence, and the zone jumping fires a burst where it was + dust where it
	# lands (seeded on the first sighting).
	_pulse_ticks += 1
	_zone_material.emission_energy_multiplier = 0.3 + 0.15 * sin(_pulse_ticks * TAU / 16.0)
	var center := Vector2(zone[0], zone[1])
	if _zone_center_seen != Vector2.INF and _zone_center_seen.distance_to(center) > 0.5:
		fx_burst(_zone_center_seen, ZONE_COLOR, 0.3)
		fx_dust(center)
	_zone_center_seen = center
	_zone_node.position = to_arena(Vector2(zone[0], zone[1]), ZONE_DISC_HEIGHT / 2.0)
	# The sim never shrinks below ZONE_MIN_RADIUS; the floor only guards a
	# malformed snapshot from producing a degenerate (zero-scale) basis.
	var radius := maxf(float(zone[2]), 0.001)
	_zone_node.scale = Vector3(radius, 1.0, radius)
