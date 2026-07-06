extends MinigameView3D
## Fort Siege client view (M10-12): the shared 2.5D iso-arena with the gate
## wall (draining from grey toward red as it's battered, gone when breached),
## the core disc glowing with capture progress, and a role banner telling
## this client to STORM or DEFEND. Breach and capture moments burst. Renders
## get_snapshot() only.

const GATE_COLOR := Color(0.5, 0.48, 0.45)
const GATE_HOT_COLOR := Color(0.85, 0.3, 0.2)
const GATE_HEIGHT := 1.4
const GATE_THICKNESS := 0.5
const CORE_COLOR := Color(0.96, 0.79, 0.2)
const CORE_DISC_HEIGHT := 0.05

## Latest replicated state, straight from FortSiege.get_snapshot().
var phase := FortSiege.Phase.SIEGE
var attacking := 0
var phase_left := 0.0
var gate := 1.0
var capture := 0.0
var players := {}
var teams: Array = []
var times: Array = []

var _gate_node: MeshInstance3D
var _gate_material: StandardMaterial3D
var _core_material: StandardMaterial3D
var _banner: Label
# FX seeds: last-seen gate for the breach burst, last-seen times for the
# capture burst.
var _gate_seen := -1.0
var _times_seen: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


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
	var wall := BoxMesh.new()
	wall.size = Vector3(FortSiege.ARENA_HALF * 2.0, GATE_HEIGHT, GATE_THICKNESS)
	_gate_material = StandardMaterial3D.new()
	_gate_material.albedo_color = GATE_COLOR
	wall.material = _gate_material
	_gate_node = MeshInstance3D.new()
	_gate_node.name = "Gate"
	_gate_node.mesh = wall
	_gate_node.position = to_arena(Vector2(0.0, FortSiege.GATE_Y), GATE_HEIGHT / 2.0)
	arena.add_child(_gate_node)
	var disc := CylinderMesh.new()
	disc.top_radius = FortSiege.CORE_RADIUS
	disc.bottom_radius = FortSiege.CORE_RADIUS
	disc.height = CORE_DISC_HEIGHT
	_core_material = StandardMaterial3D.new()
	_core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_material.albedo_color = Color(CORE_COLOR, 0.4)
	_core_material.emission_enabled = true
	_core_material.emission = CORE_COLOR
	_core_material.emission_energy_multiplier = 0.2
	disc.material = _core_material
	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = disc
	core.position = to_arena(FortSiege.CORE_POS, CORE_DISC_HEIGHT / 2.0)
	arena.add_child(core)
	_banner = make_banner(&"Role", 26)


func _render_3d(game: Dictionary) -> void:
	phase = game.get("phase", FortSiege.Phase.SIEGE)
	attacking = int(game.get("attacking", 0))
	phase_left = float(game.get("phase_left", 0.0))
	gate = float(game.get("gate", 1.0))
	capture = float(game.get("capture", 0.0))
	players = game.get("players", {})
	teams = game.get("teams", [])
	times = game.get("times", [])
	_update_players()
	_update_gate()
	_update_core()
	_update_banner()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		if rig_for_slot(slot) == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))


func _update_gate() -> void:
	_gate_node.visible = gate > 0.0
	_gate_material.albedo_color = GATE_HOT_COLOR.lerp(GATE_COLOR, gate)
	# Breach burst: the wall coming down is the round's first big moment.
	if _gate_seen > 0.0 and gate <= 0.0:
		fx_burst(Vector2(0.0, FortSiege.GATE_Y), GATE_HOT_COLOR)
		fx_dust(Vector2(0.0, FortSiege.GATE_Y))
		# Heard from your own side of the wall (M12-02).
		if teams.size() == 2:
			play_sfx(&"confirm" if my_slot in teams[attacking] else &"error")
	_gate_seen = gate


func _update_core() -> void:
	_core_material.emission_energy_multiplier = 0.2 + capture * 1.2
	# Capture burst: a -1 in times flipping to a real time is a capture.
	if _times_seen.size() == times.size():
		for i in times.size():
			if float(times[i]) >= 0.0 and float(_times_seen[i]) < 0.0:
				fx_burst(FortSiege.CORE_POS, CORE_COLOR)
				# Your own siege succeeding is a win; the other team's is a loss.
				if i < teams.size():
					play_sfx(&"confirm" if my_slot in teams[i] else &"error")
	_times_seen = times.duplicate()


func _update_banner() -> void:
	if _banner == null:
		return
	if phase == FortSiege.Phase.SWAP:
		_banner.text = "SWAP! Switching sides..."
		_banner.modulate = Color.WHITE
		return
	var storming: bool = teams.size() == 2 and my_slot in teams[attacking]
	if storming:
		_banner.text = "STORM the fort! (%0.0fs)" % phase_left
	else:
		_banner.text = "DEFEND the fort! (%0.0fs)" % phase_left
	_banner.modulate = GATE_HOT_COLOR if storming else CORE_COLOR
