extends MinigameView3D
## Sumo Smash client view (M8-07): renders the replicated platform in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — the ring as a stone disc,
## players as CharacterRig instances (dashing runs the "run" action with the
## dash-ready state on the nameplate), rung-out players hidden. Presentation-
## tier swap only: state storage and the render contract are unchanged from
## the 2D pass (M4-04).

const PLATFORM_COLOR := Color(0.5, 0.46, 0.4)
const PLATFORM_THICKNESS := 0.4

## Latest replicated state, straight from SumoSmash.get_snapshot().
var players := {}
var out: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"dash": true})


func _arena_half() -> float:
	return SumoSmash.PLATFORM_RADIUS + 2.0


func _setup_3d() -> void:
	var mesh := CylinderMesh.new()
	mesh.height = PLATFORM_THICKNESS
	mesh.top_radius = SumoSmash.PLATFORM_RADIUS
	mesh.bottom_radius = SumoSmash.PLATFORM_RADIUS
	var material := StandardMaterial3D.new()
	material.albedo_color = PLATFORM_COLOR
	mesh.material = material
	var platform := MeshInstance3D.new()
	platform.name = "Platform"
	platform.mesh = mesh
	platform.position = Vector3(0.0, PLATFORM_THICKNESS / 2.0, 0.0)
	arena.add_child(platform)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	out = game.get("out", [])
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		if not players.has(slot):
			rig.visible = false
			continue
		rig.visible = true
		var state: Array = players[slot]
		update_rig(slot, Vector2(state[0], state[1]))
		rig.position.y = PLATFORM_THICKNESS
		var dashing := int(state[3]) == 1
		if dashing and rig.current_action() != &"run":
			rig.play(&"run")
		var cooldown := float(state[2])
		var caption := player_name(slot)
		if cooldown > 0.0:
			caption += "  %.1f" % cooldown
		rig.display_name = caption
