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

var _dash_label: Label
# M13-06 FX state: last replicated pos per slot (shove detection + ring-out
# splash), and out-count seeding for rejoiners.
var _last_pos := {}
var _out_seen := -1
var _was_ready := true


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
	# Screen-space dash indicator for the local player (#140), on the
	# always-on-top banner layer (#258).
	_dash_label = make_banner(&"DashIndicator")


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	out = game.get("out", [])
	_fx_on_ringouts()
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		if not players.has(slot):
			rig.visible = false
			continue
		rig.visible = true
		var state: Array = players[slot]
		var at := Vector2(state[0], state[1])
		# Height rides update_rig (M12-04's interpolator owns position; setting
		# rig.position.y directly after this call would flicker every frame).
		update_rig(slot, at, PLATFORM_THICKNESS)
		var dashing := int(state[3]) == 1
		if dashing and rig.current_action() != &"run":
			rig.play(&"run")
		# M13-06: dashes trail dust; a sudden non-dash displacement means a
		# shove landed - burst at the contact. Seeded via _last_pos.
		if dashing:
			fx_dust(at)
		elif _last_pos.has(slot) and (_last_pos[slot] as Vector2).distance_to(at) > 0.25:
			fx_burst(at, player_color(slot), 0.6)
		_last_pos[slot] = at
		var cooldown := float(state[2])
		var caption := player_name(slot)
		if cooldown > 0.0:
			caption += "  %.1f" % cooldown
		rig.display_name = caption
		if slot == my_slot:
			_update_dash_indicator(cooldown)


## Big readable local-player dash state: countdown bar while cooling,
## READY flash + tick when it comes back (#140).
func _update_dash_indicator(cooldown: float) -> void:
	if _dash_label == null:
		return
	var ready := cooldown <= 0.0
	if ready:
		_dash_label.text = "DASH READY"
		_dash_label.modulate = Color(0.5, 1.0, 0.55)
		if not _was_ready:
			play_sfx(&"tick")
	else:
		var fraction := 1.0 - cooldown / SumoSmash.DASH_COOLDOWN_SEC
		var bar := "█".repeat(int(fraction * 10.0)) + "░".repeat(10 - int(fraction * 10.0))
		_dash_label.text = "DASH %s" % bar
		_dash_label.modulate = Color(1.0, 0.75, 0.4)
	_was_ready = ready


## Ring-outs splash where the player left the platform and rattle the screen
## (M13-06); the seeding snapshot stays calm for rejoiners.
func _fx_on_ringouts() -> void:
	var out_count := 0
	for group: Array in out:
		out_count += group.size()
	if _out_seen >= 0 and out_count > _out_seen:
		request_shake(10.0)
		for group: Array in out:
			for slot: int in group:
				if _last_pos.has(slot):
					fx_splash(_last_pos[slot])
					_last_pos.erase(slot)
	_out_seen = out_count
