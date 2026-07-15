extends MinigameView3D
## Fort Siege client view (M10-12, readable rework #808): the shared 2.5D
## iso-arena rebuilt so the attack/defend fantasy reads at a glance — a real
## fort (side + back walls enclosing a raised core plinth, with the gate as the
## only way in), an active BATTER swing on the gate, a defender REPAIR/SHOVE with
## a cooldown ring, a CONTESTED core tag, and state-driven objective prompts.
## The sim's scoring/phases are untouched; this renders get_snapshot() only.

## Real gate + wall-segment models (#808/#911, MDL-004/005): both are
## base-pivoted single pieces meant to be placed/tiled, not stretched — the
## gate is a realistic doorway width (~2.5u), so the front wall is now the
## gate flanked by tiled stone, matching the two requests as they were meant
## to pair.
const GATE_SCENE := preload("res://assets/generated/models/castle-gate.glb")
const WALL_SCENE := preload("res://assets/generated/models/castle-wall-segment.glb")
## Measured from the delivered models (#911's probe) — the gate's own width
## and each wall segment's tileable length.
const GATE_WIDTH := 2.5
const WALL_SEGMENT_LENGTH := 4.0
## The wall segment model's actual height (probed), for banner placement —
## its crenellated top is baked in, so the old procedural merlon teeth are gone.
const WALL_MODEL_HEIGHT := 1.6
const GATE_HOT_COLOR := Color(0.85, 0.3, 0.2)
const GATE_REPAIR_COLOR := Color(0.75, 0.7, 0.62)
## The gate model's actual height (probed) — sparkle FX placement only, the
## geometry itself needs no height const since it's base-pivoted.
const GATE_MODEL_HEIGHT := 2.7
const CORE_COLOR := Color(0.96, 0.79, 0.2)
const PLINTH_COLOR := Color(0.28, 0.29, 0.34)
const PLINTH_HEIGHT := 0.5
const CRYSTAL_HEIGHT := 1.1
const CONTESTED_COLOR := Color(0.95, 0.3, 0.3)
## The shove cooldown ring drawn under a defender — full when just used, gone
## when ready to shove again.
const COOLDOWN_RING_COLOR := Color(0.4, 0.75, 0.95)
## How long a swing/repair/shove animation owns the rig before walk/idle resumes.
const ACT_HOLD_SEC := 0.45

## Latest replicated state, straight from FortSiege.get_snapshot().
var phase := FortSiege.Phase.SIEGE
var attacking := 0
var phase_left := 0.0
var gate := 1.0
var capture := 0.0
var contested := false
var players := {}
var teams: Array = []
var times: Array = []

var _gate_node: Node3D
## Duplicated per-instance so the gate's damage glow never touches the shared
## cached material (or, hypothetically, another gate instance).
var _gate_materials: Array[StandardMaterial3D] = []
var _gate_rest := Vector3.ZERO
## Recoil magnitude from the last batter, decayed in _process so the shake plays
## out across frames instead of being reset the same render it's set (#808).
var _gate_shake := 0.0
var _crystal_material: StandardMaterial3D
var _crystal: MeshInstance3D
var _banner: Label
var _scores: Label
## Team-colored banner strips on the fort walls — recolored to the defending
## team so "whose fort this is" reads and flips on the swap.
var _wall_banners: Array[MeshInstance3D] = []
## Per-slot: the play-once action-counter edge (#945), the ticks_msec a
## swing/shove owns the rig, and a lazily-built shove cooldown ring.
var _act_edges := EdgeTracker.new()
var _act_hold := {}
var _rings := {}
# FX seeds: last-seen gate for the breach burst and crack thirds, last-seen
# times for the capture burst.
var _gate_seen := -1.0
var _cracks_seen := 0
var _times_seen: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Plays out the gate recoil from a batter across frames (#808); steady (no
## jitter) under reduced motion, but still eases back to rest.
func _process(delta: float) -> void:
	if _gate_node == null:
		return
	if _gate_shake <= 0.001:
		if _gate_node.position != _gate_rest:
			_gate_node.position = _gate_rest
		return
	_gate_shake = maxf(_gate_shake - delta * 0.6, 0.0)
	if ArenaFX.reduced_motion:
		return
	var jitter := sin(Time.get_ticks_msec() * 0.05) * _gate_shake
	_gate_node.position = _gate_rest + Vector3(jitter, 0.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"act": true})


## Cool stone floor for the fortress clash (#589).
func _floor_tint() -> Color:
	return Color(0.85, 0.88, 0.95)


func _arena_half() -> float:
	return FortSiege.ARENA_HALF + 1.0


func _setup_3d() -> void:
	_build_gate()
	_build_walls()
	_build_core()
	_banner = make_banner(&"Role", 26)
	_scores = make_status_label(&"Scores")


func _build_gate() -> void:
	_gate_node = GATE_SCENE.instantiate() as Node3D
	_gate_node.name = "Gate"
	_gate_rest = to_arena(Vector2(0.0, FortSiege.GATE_Y), 0.0)
	_gate_node.position = _gate_rest
	arena.add_child(_gate_node)
	_gate_materials = _duplicate_materials(_gate_node)


## The fort proper (#808/#911): the gate flanked by tiled stone-wall-segment
## models filling the rest of the front, plus the two side walls and the back
## wall — enclosing the core so the gate reads as the one way in. A
## team-colored banner rides each wall and flips to the defenders on the swap.
func _build_walls() -> void:
	var half := FortSiege.ARENA_HALF
	var back_y := -half
	var gate_half := GATE_WIDTH / 2.0
	# Front wall: two flanks either side of the gate. The model's outward face
	# is single-sided (#911 probe), so a mirrored run needs its rotation
	# flipped 180° on top of the heading — same absolute rotation at a
	# mirrored position turns its face away from the fixed-azimuth iso camera.
	_tile_wall(Vector2(-half, FortSiege.GATE_Y), Vector2(-gate_half, FortSiege.GATE_Y), true)
	_tile_wall(Vector2(gate_half, FortSiege.GATE_Y), Vector2(half, FortSiege.GATE_Y), false)
	# Left and right walls run from the gate line to the back wall.
	for side in [-1.0, 1.0]:
		_tile_wall(Vector2(side * half, FortSiege.GATE_Y), Vector2(side * half, back_y), side < 0.0)
		_wall_banners.append(
			_add_wall_banner(Vector2(side * half, (FortSiege.GATE_Y + back_y) / 2.0))
		)
	# Back wall spans the full width behind the core.
	_tile_wall(Vector2(-half, back_y), Vector2(half, back_y), false)
	_wall_banners.append(_add_wall_banner(Vector2(0.0, back_y + 0.4)))


## Places WALL_SCENE copies end-to-end along the straight run from `from` to
## `to`, oriented to face along it (same heading convention as Turbo Lap's
## track strips) — real tiled stone instead of one stretched box. `flip`
## adds a 180° turn for the mirrored side of a left/right pair (#911).
func _tile_wall(from: Vector2, to: Vector2, flip: bool) -> void:
	var span := from.distance_to(to)
	if span < 0.01:
		return
	var count := int(ceil(span / WALL_SEGMENT_LENGTH))
	var rot := -(to - from).angle() + (PI if flip else 0.0)
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var segment := WALL_SCENE.instantiate() as Node3D
		segment.position = to_arena(from.lerp(to, t), 0.0)
		segment.rotation.y = rot
		arena.add_child(segment)


## Duplicates every mesh surface material under `node` so runtime tweaks (the
## gate's damage glow) never mutate the shared cached resource other
## instances/reloads would see.
func _duplicate_materials(node: Node) -> Array[StandardMaterial3D]:
	var materials: Array[StandardMaterial3D] = []
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for surface in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(surface)
				if mat is StandardMaterial3D:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(surface, dup)
					materials.append(dup)
	for child in node.get_children():
		materials.append_array(_duplicate_materials(child))
	return materials


func _add_wall_banner(world: Vector2) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, WALL_MODEL_HEIGHT * 0.7, 1.2)
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.name = "WallBanner"
	node.mesh = mesh
	node.position = to_arena(world, WALL_MODEL_HEIGHT * 0.55)
	arena.add_child(node)
	return node


## The objective made a place, not a decal (#808): a raised plinth with a glowing
## crystal the raiders must reach and hold. The crystal brightens with capture.
func _build_core() -> void:
	var plinth_mesh := CylinderMesh.new()
	plinth_mesh.top_radius = FortSiege.CORE_RADIUS
	plinth_mesh.bottom_radius = FortSiege.CORE_RADIUS * 1.15
	plinth_mesh.height = PLINTH_HEIGHT
	var plinth_mat := StandardMaterial3D.new()
	plinth_mat.albedo_color = PLINTH_COLOR
	plinth_mesh.material = plinth_mat
	var plinth := MeshInstance3D.new()
	plinth.name = "CorePlinth"
	plinth.mesh = plinth_mesh
	plinth.position = to_arena(FortSiege.CORE_POS, PLINTH_HEIGHT / 2.0)
	arena.add_child(plinth)

	var crystal_mesh := PrismMesh.new()
	crystal_mesh.size = Vector3(1.1, CRYSTAL_HEIGHT, 1.1)
	_crystal_material = StandardMaterial3D.new()
	_crystal_material.albedo_color = CORE_COLOR
	_crystal_material.emission_enabled = true
	_crystal_material.emission = CORE_COLOR
	_crystal_material.emission_energy_multiplier = 0.4
	crystal_mesh.material = _crystal_material
	_crystal = MeshInstance3D.new()
	_crystal.name = "CoreCrystal"
	_crystal.mesh = crystal_mesh
	_crystal.position = to_arena(FortSiege.CORE_POS, PLINTH_HEIGHT + CRYSTAL_HEIGHT / 2.0)
	arena.add_child(_crystal)


func _render_3d(game: Dictionary) -> void:
	phase = game.get("phase", FortSiege.Phase.SIEGE)
	attacking = int(game.get("attacking", 0))
	phase_left = float(game.get("phase_left", 0.0))
	gate = float(game.get("gate", 1.0))
	capture = float(game.get("capture", 0.0))
	contested = bool(game.get("contested", false))
	players = game.get("players", {})
	teams = game.get("teams", [])
	times = game.get("times", [])
	_update_players()
	_update_gate()
	_update_core()
	_update_banners()
	_update_scores()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		_play_action(slot, state, rig)
		var pos := Vector2(float(state[FortSiege.PS_X]), float(state[FortSiege.PS_Y]))
		if Time.get_ticks_msec() < int(_act_hold.get(slot, 0)):
			# A swing/shove owns the pose (#587 idiom): move it, don't re-animate.
			rig.position = to_arena(pos)
		else:
			update_rig(slot, pos)
		_update_cooldown_ring(slot, state, rig)


## Fires the batter / repair / shove reaction the instant the sim's monotonic
## counter ticks (#808), so each plays exactly once — a swing pose plus a cue
## and, for a batter, a gate shake read as the wall taking the hit.
func _play_action(slot: int, state: Array, rig: CharacterRig) -> void:
	if state.size() <= FortSiege.PS_ACT_KIND:
		return
	var seq := int(state[FortSiege.PS_ACT_SEQ])
	if not _act_edges.rose(slot, seq):
		return
	var kind := int(state[FortSiege.PS_ACT_KIND])
	var at := Vector2(float(state[FortSiege.PS_X]), float(state[FortSiege.PS_Y]))
	match kind:
		FortSiege.Act.BATTER:
			rig.play(&"attack")
			_act_hold[slot] = Time.get_ticks_msec() + int(ACT_HOLD_SEC * 1000.0)
			fx_sparkle(Vector2(0.0, FortSiege.GATE_Y), GATE_HOT_COLOR, GATE_MODEL_HEIGHT * 0.6)
			_gate_shake = 0.18  # recoil, played out in _process
			play_sfx(&"thud")
		FortSiege.Act.REPAIR:
			rig.play(&"interact")
			_act_hold[slot] = Time.get_ticks_msec() + int(ACT_HOLD_SEC * 1000.0)
			fx_sparkle(at, GATE_REPAIR_COLOR, 0.8)
			play_sfx(&"click")
		FortSiege.Act.SHOVE:
			rig.play(&"attack")
			_act_hold[slot] = Time.get_ticks_msec() + int(ACT_HOLD_SEC * 1000.0)
			fx_burst(at, COOLDOWN_RING_COLOR, 0.6)
			play_sfx(&"bump")


## A flat ring under a defender showing their shove cooldown (#808): visible and
## shrinking while on cooldown, hidden the moment it's ready again. Lazily built
## per rig and reused (rigs are pooled).
func _update_cooldown_ring(slot: int, state: Array, rig: CharacterRig) -> void:
	if state.size() <= FortSiege.PS_SHOVE_CD:
		return
	# PS_SHOVE_CD is already a 0..1 fraction (normalized sim-side). Shared
	# cooldown-ring chrome (#945).
	update_cooldown_ring(
		_rings, slot, rig, float(state[FortSiege.PS_SHOVE_CD]), COOLDOWN_RING_COLOR
	)


func _update_gate() -> void:
	_gate_node.visible = gate > 0.0
	# Damage now glows through the gate's own wood/iron texture (an emission
	# overlay) rather than recoloring it flat, so the real model reads instead
	# of flattening into a solid tint.
	var heat := clampf(1.0 - gate, 0.0, 1.0)
	for mat in _gate_materials:
		mat.emission_enabled = heat > 0.0
		mat.emission = GATE_HOT_COLOR
		mat.emission_energy_multiplier = heat * 1.5
	# Crack the gate harder at each damage third (#808), so progress reads even
	# before it falls.
	var cracks := int((1.0 - gate) * 3.0)
	if cracks > _cracks_seen and gate > 0.0:
		fx_dust(Vector2(0.0, FortSiege.GATE_Y))
	_cracks_seen = cracks
	# Breach burst: the wall coming down is the round's first big moment.
	if _gate_seen > 0.0 and gate <= 0.0:
		fx_burst(Vector2(0.0, FortSiege.GATE_Y), GATE_HOT_COLOR)
		fx_dust(Vector2(0.0, FortSiege.GATE_Y))
		# The gate itself falling (#728) — heard by both sides alike.
		play_sfx(&"clang")
	_gate_seen = gate


func _update_core() -> void:
	# The crystal brightens with capture and flares red when a defender contests
	# it (#808) — the KotH stall now reads.
	var base := 0.4 + capture * 1.6
	if contested:
		_crystal_material.emission = CONTESTED_COLOR
		_crystal_material.emission_energy_multiplier = 1.6
	else:
		_crystal_material.emission = CORE_COLOR
		_crystal_material.emission_energy_multiplier = base
	# Capture burst: a -1 in times flipping to a real time is a capture.
	if _times_seen.size() == times.size():
		for i in times.size():
			if float(times[i]) >= 0.0 and float(_times_seen[i]) < 0.0:
				fx_burst(FortSiege.CORE_POS, CORE_COLOR, PLINTH_HEIGHT + 0.5)
				if i < teams.size():
					play_sfx(&"bell" if my_slot in teams[i] else &"error")
	_times_seen = times.duplicate()


## Role banner + the state-driven objective line under it (#808): storming vs
## defending, and exactly what to do at each phase, so "how do I defend?" is
## answered on screen. The wall banners flip to the defending team's color.
func _update_banners() -> void:
	_recolor_wall_banners()
	if _banner == null:
		return
	if phase == FortSiege.Phase.SWAP:
		_banner.text = "SWAP! Switching sides..."
		_banner.modulate = Color.WHITE
		return
	var storming: bool = teams.size() == 2 and my_slot in teams[attacking]
	var breached := gate <= 0.0
	var role := "STORM the fort!" if storming else "DEFEND the fort!"
	var task: String
	if storming:
		task = "Rush the core — HOLD it!" if breached else "BATTER the gate! (press to swing)"
	elif contested:
		task = "STAND ON THE CORE — you're blocking the capture!"
	elif breached:
		task = "Get them off the core!"
	else:
		task = "SHOVE raiders off — or hold to REPAIR the gate"
	_banner.text = "%s  (%0.0fs)\n%s" % [role, phase_left, task]
	_banner.modulate = GATE_HOT_COLOR if storming else CORE_COLOR


func _recolor_wall_banners() -> void:
	if teams.size() != 2 or _wall_banners.is_empty():
		return
	var defending: Array = teams[1 - attacking]
	if defending.is_empty():
		return
	var color := player_color(int(defending[0]))
	for banner in _wall_banners:
		var mat := (banner.mesh as BoxMesh).material as StandardMaterial3D
		mat.albedo_color = color
		mat.emission = color
		mat.emission_energy_multiplier = 0.5


## The target to beat, visible during the second siege (#808): both runs' times,
## a dash for a run that failed to capture.
func _update_scores() -> void:
	if _scores == null:
		return
	var any_run := false
	for t in times:
		if float(t) >= 0.0:
			any_run = true
	if not any_run and attacking == 0 and phase == FortSiege.Phase.SIEGE:
		_scores.text = ""
		return
	_scores.text = "Run 1: %s    Run 2: %s" % [_run_label(0), _run_label(1)]


func _run_label(team: int) -> String:
	if team >= times.size():
		return "—"
	var t := float(times[team])
	return "%.1fs" % t if t >= 0.0 else "—"
