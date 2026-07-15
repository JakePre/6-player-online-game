extends MinigameView3D
## Sumo Smash client view (M8-07): renders the replicated platform in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — the ring as a stone disc,
## players as CharacterRig instances. A dash throws a real lunge/shove pose
## (`attack`) and a shoved player flinches (`hit`, #792); the local dash's
## ready/recharging state rides the banner. Rung-out players hidden.
## Presentation-tier swap only: state storage and the render contract are
## unchanged from the 2D pass (M4-04).

const PLATFORM_COLOR := Color(0.5, 0.46, 0.4)
const PLATFORM_THICKNESS := 0.4
## How long a shove's hurt reaction owns the rig before walk/idle resumes
## (#792) — mirrors rumble_ring's hit/ko reaction hold.
const REACT_HOLD_SEC := 0.4

## Latest replicated state, straight from SumoSmash.get_snapshot().
var players := {}
var out: Array = []

var _dash_label: Label
# M13-06 FX state: last replicated pos per slot (shove detection + ring-out
# splash), and out-count seeding for rejoiners.
var _last_pos := {}
var _out_seen := -1
var _was_ready := true
## Rig-animation ownership (#792): dash rising-edge tracking. The hurt-react
## hold now lives on the rig (#942, CharacterRig.play_protected).
var _was_dashing := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"dash": true})


## A grass field around the stone ring (#813): the Kenney grass block replaces
## the grey platform tile and carries its own color, so the old tan tint (#589)
## is gone — the ring itself (Platform, below) stays its own stone disc.
func _floor_tile_scene() -> PackedScene:
	return preload("res://assets/environment/kenney_platformer_kit/block-grass.glb")


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
		var at := Vector2(state[SumoSmash.PS_X], state[SumoSmash.PS_Y])
		var dashing := int(state[SumoSmash.PS_DASHING]) == 1
		var lurched := _last_pos.has(slot) and (_last_pos[slot] as Vector2).distance_to(at) > 0.25
		var shoved := lurched and not dashing
		# Rig-animation ownership (#792): the dash IS the shove — a lunge pose
		# played once on the rising edge; a shove throws a hurt reaction held for
		# a beat (the hold lives on the rig now, #942). Both own the rig via a
		# direct position set (like rumble_ring), so the one-shot animation plays
		# out instead of update_rig overwriting it with walk every frame.
		# Ordinary movement uses update_rig as before.
		if dashing:
			if not bool(_was_dashing.get(slot, false)):
				rig.play(&"attack")
				# Signature cue (#728, docs/AUDIO_GUIDE.md — Brawlers): the lunge.
				play_sfx(&"dash")
			rig.position = to_arena(at, PLATFORM_THICKNESS)
		elif rig.is_pose_protected():
			rig.position = to_arena(at, PLATFORM_THICKNESS)
		elif shoved:
			rig.play_protected(&"hit", REACT_HOLD_SEC)
			rig.position = to_arena(at, PLATFORM_THICKNESS)
		else:
			# Height rides update_rig (M12-04's interpolator owns position;
			# setting rig.position.y directly here would flicker every frame).
			update_rig(slot, at, PLATFORM_THICKNESS)
		_was_dashing[slot] = dashing
		# Dash trail (#587): a player-colored burst reads as a fast streak; a
		# sudden non-dash displacement means a shove landed — burst there too.
		if dashing:
			fx_burst(at, player_color(slot), 0.5)
		elif shoved:
			fx_burst(at, player_color(slot), 0.6)
			# Non-damaging body contact — the shove that just landed.
			play_sfx(&"bump")
		_last_pos[slot] = at
		var cooldown := float(state[SumoSmash.PS_COOLDOWN])
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
		# The shared elimination cue (#728) — a ring-out is a KO, same as
		# every other game's terminal-for-the-round moment.
		play_sfx(&"ko")
		for group: Array in out:
			for slot: int in group:
				if _last_pos.has(slot):
					fx_splash(_last_pos[slot])
					_last_pos.erase(slot)
	_out_seen = out_count
