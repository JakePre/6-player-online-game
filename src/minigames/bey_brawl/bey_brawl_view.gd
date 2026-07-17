extends MinigameView3D
## Bey Brawl client view (#1034, replaces Sumo Smash): the concave stadium
## bowl rendered as stepped discs sinking toward center, every rig spinning
## permanently — the `whirlwind` looping 2H spin, added to the whole roster
## for exactly this and unused until now — with the Barbarian's CC0 axe in
## hand (the Gauntlet's #584 attach idiom). Spin meters ride the nameplates
## as pips; clashes burst and rattle via the replicated clash_seq edge;
## topples and lip launches splash out like every elimination game.

## The Gauntlet's axe (#584): mesh lifted from the shipped Barbarian GLB,
## gripped at the shared handslot.r bone with the same rest offset.
const AXE_SOURCE_SCENE := "res://assets/characters/kaykit_adventurers/Barbarian.glb"
const AXE_MESH_NAME := "2H_Axe"
const AXE_BONE := "handslot.r"

## Bowl look: a raised stadium pit (the dohyo lesson, #927 — sit ABOVE the
## grass so it never reads as a hole) whose inner discs step DOWN toward
## center, selling the concave slope the sim actually applies.
const BOWL_TOP_COLOR := Color(0.5, 0.52, 0.6)
const BOWL_STEP_COLORS: Array[Color] = [
	Color(0.42, 0.44, 0.52),
	Color(0.34, 0.36, 0.44),
	Color(0.27, 0.29, 0.36),
]
const RIM_COLOR := Color(0.85, 0.7, 0.3)
const RIM_WIDTH := 0.4
const BOWL_THICKNESS := 1.0
## Each inner step sinks this much below the lip surface.
const STEP_DEPTH := 0.09
## Spin meter pips on the nameplate.
const SPIN_PIPS := 5

## Latest replicated state, straight from BeyBrawl.get_snapshot().
var players := {}
var out: Array = []

## Clash / elimination FX seeding (#941): first sight never fires.
var _edges := EdgeTracker.new()
var _last_pos := {}
var _axe_mesh: Mesh
var _armed := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Cool steel floor around the stadium pit.
func _floor_tint() -> Color:
	return Color(0.85, 0.88, 0.95)


func _arena_half() -> float:
	return BeyBrawl.BOWL_RADIUS + 2.0


func _setup_3d() -> void:
	_build_bowl()
	var axe_source: Node = (load(AXE_SOURCE_SCENE) as PackedScene).instantiate()
	var axe_nodes := axe_source.find_children(AXE_MESH_NAME, "MeshInstance3D", true, false)
	if not axe_nodes.is_empty():
		_axe_mesh = (axe_nodes[0] as MeshInstance3D).mesh
	axe_source.free()


## The stadium: a full-radius lip disc with stepped inner discs sinking toward
## center (concave read), and a gold ring right at the ring-out radius so the
## fatal lip is unmissable.
func _build_bowl() -> void:
	_add_disc("BowlLip", BeyBrawl.BOWL_RADIUS, BOWL_TOP_COLOR, BOWL_THICKNESS)
	for i in BOWL_STEP_COLORS.size():
		var fraction := 1.0 - (float(i) + 1.0) / (BOWL_STEP_COLORS.size() + 1.0)
		_add_disc(
			"BowlStep%d" % i,
			BeyBrawl.BOWL_RADIUS * fraction,
			BOWL_STEP_COLORS[i],
			BOWL_THICKNESS - STEP_DEPTH * (i + 1)
		)
	var mesh := TorusMesh.new()
	mesh.inner_radius = BeyBrawl.BOWL_RADIUS - RIM_WIDTH
	mesh.outer_radius = BeyBrawl.BOWL_RADIUS
	var material := StandardMaterial3D.new()
	material.albedo_color = RIM_COLOR
	material.emission_enabled = true
	material.emission = RIM_COLOR
	material.emission_energy_multiplier = 0.5
	mesh.material = material
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = mesh
	rim.position = Vector3(0.0, BOWL_THICKNESS + 0.02, 0.0)
	arena.add_child(rim)


func _add_disc(disc_name: String, radius: float, color: Color, height: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var disc := MeshInstance3D.new()
	disc.name = disc_name
	disc.mesh = mesh
	disc.position = Vector3(0.0, height / 2.0, 0.0)
	arena.add_child(disc)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	out = game.get("out", [])
	_fx_on_outs()
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		if not players.has(slot):
			rig.visible = false
			continue
		var state: Array = players[slot]
		var at := Vector2(state[BeyBrawl.PS_X], state[BeyBrawl.PS_Y])
		_place_spinner(slot, rig, at)
		# Clash FX on the replicated clash counter's rising edge (#941): a
		# burst at the body plus a rattle when the local player is in it.
		if _edges.rose(slot, int(state[BeyBrawl.PS_CLASH_SEQ])):
			fx_burst(at, player_color(slot), 0.8)
			play_sfx(&"bump")
			if slot == my_slot:
				request_shake(6.0)
		_last_pos[slot] = at
		var spin := clampf(float(state[BeyBrawl.PS_SPIN]), 0.0, 1.0)
		var filled := int(roundf(spin * SPIN_PIPS))
		rig.display_name = (
			"%s  %s%s" % [player_name(slot), "●".repeat(filled), "○".repeat(SPIN_PIPS - filled)]
		)


## A spinner is ALWAYS in the whirlwind loop, so update_rig doesn't fit: its
## walk/idle switch stomps any looping action the moment the body moves
## (#800/#942 give one-shots a hold, but never a permanent loop). Feed the
## M12-04 interpolator's sampler directly instead — smooth 30 Hz motion with
## the animation left alone — and assert the loop + axe once per rig.
func _place_spinner(slot: int, rig: CharacterRig, at: Vector2) -> void:
	reveal_rig(slot)
	rig.visible = true
	_record_rig_sample(slot, rig, to_arena(at, BOWL_THICKNESS))
	if rig.current_action() != &"whirlwind":
		rig.play(&"whirlwind")
	if not _armed.get(slot, false) and _axe_mesh != null:
		# Grip offset = the GLB's own 2H_Axe bone rest relative to handslot.r
		# (the Gauntlet's #584 numbers).
		rig.set_held_weapon(
			_axe_mesh, AXE_BONE, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.033, 0.0))
		)
		_armed[slot] = true


## Topples and lip launches: splash where the body left play, rattle the
## screen, and drop the rig — seeded via the tracker so a mid-match rejoiner's
## first snapshot stays calm (#941).
func _fx_on_outs() -> void:
	var out_count := 0
	for group: Array in out:
		out_count += group.size()
	if _edges.rose(&"out", out_count):
		request_shake(10.0)
		# The shared elimination cue (#728).
		play_sfx(&"ko")
		for group: Array in out:
			for slot: int in group:
				if _last_pos.has(slot):
					fx_splash(_last_pos[slot])
					_last_pos.erase(slot)
