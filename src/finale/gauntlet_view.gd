extends MinigameView3D
## Finale Gauntlet client view (M8-12): renders the shrinking platform,
## telegraphed hazard discs, and players in the shared 2.5D iso-arena
## (M8-01). New build — the Gauntlet sim (M5-02) had server logic only.
## Renders Gauntlet.get_snapshot() untouched: {radius, players:
## {slot: [x, y, lives, respawn_left]}, hazards: [[x, y, r, warn_left]]}.

const PLATFORM_COLOR := Color(0.45, 0.43, 0.4)
const PLATFORM_THICKNESS := 0.4
const HAZARD_COLOR := Color(0.9, 0.25, 0.2, 0.45)
## Telegraphs darken toward detonation.
const HAZARD_ARMED_COLOR := Color(0.7, 0.1, 0.05, 0.7)
## FX pass (M13-31): hazards pop a warning spark when a new one arms and a burst
## where one detonates; the shrinking platform crumbles dust off the rim it sheds.
const HAZARD_FX_COLOR := Color(0.95, 0.35, 0.2)
const CRUMBLE_PUFFS := 6
const FX_LIFT := PLATFORM_THICKNESS + 0.1

## Latest replicated state, straight from Gauntlet.get_snapshot().
var radius := Gauntlet.START_RADIUS
var players := {}
var hazards: Array = []

var _platform: MeshInstance3D
var _platform_mesh: CylinderMesh
var _hazard_nodes: Array[MeshInstance3D] = []

var _last_radius := Gauntlet.START_RADIUS
var _last_hazard_keys := {}  # quantized "x,y" -> Vector2 world pos (detonation FX)
var _last_lives := {}  # slot -> lives (fall/KO burst)

## Finale targeting (fixes the deferred "HUD targeting pass", #462). While
## alive, a sabotage token drops on the nearest living rival; once eliminated,
## the one grudge hazard aims via a cycle-selected target. The sim already
## validates both (token count / grudge availability), so this is view-only.
var _grudge_target := -1
var _grudge_spent := false
var _grudge_prompt: Label


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Alive: action_secondary spends a sabotage token on the nearest living rival.
## Eliminated: aim the one grudge with move-left/right and strike with either
## action button. Parity-clean — one stick axis to aim, one button to fire.
func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if _local_lives() > 0:
		if event.is_action_pressed(&"action_secondary"):
			NetManager.send_match_input({"sabotage": _sabotage_target()})
		return
	if _grudge_spent:
		return
	if event.is_action_pressed(&"move_left"):
		_cycle_grudge(-1)
	elif event.is_action_pressed(&"move_right"):
		_cycle_grudge(1)
	elif event.is_action_pressed(&"action_secondary") or event.is_action_pressed(&"action_primary"):
		_fire_grudge()


## Nearest living rival's position for a sabotage drop; arena center as a
## harmless fallback if somehow no rival is alive.
func _sabotage_target() -> Array:
	var slot := _nearest_living_rival()
	if slot == -1:
		return [0.0, 0.0]
	var state: Array = players[slot]
	return [state[0], state[1]]


func _nearest_living_rival() -> int:
	if not players.has(my_slot):
		return _first_living_rival()
	var mine: Array = players[my_slot]
	var origin := Vector2(float(mine[0]), float(mine[1]))
	var best := -1
	var best_dist := INF
	for slot: int in _living_rivals():
		var state: Array = players[slot]
		var dist := origin.distance_to(Vector2(float(state[0]), float(state[1])))
		if dist < best_dist:
			best_dist = dist
			best = slot
	return best


## Living opponents (alive, not me), slot-sorted so grudge cycling is stable.
func _living_rivals() -> Array:
	var rivals: Array = []
	for slot: int in players:
		if slot == my_slot:
			continue
		if int((players[slot] as Array)[2]) > 0:
			rivals.append(slot)
	rivals.sort()
	return rivals


func _first_living_rival() -> int:
	var rivals := _living_rivals()
	return rivals[0] if not rivals.is_empty() else -1


func _local_lives() -> int:
	if not players.has(my_slot):
		return 1  # pre-snapshot: assume alive, show no grudge prompt
	return int((players[my_slot] as Array)[2])


func _cycle_grudge(direction: int) -> void:
	var rivals := _living_rivals()
	if rivals.is_empty():
		_grudge_target = -1
	elif _grudge_target not in rivals:
		_grudge_target = rivals[0]
	else:
		var i: int = rivals.find(_grudge_target)
		_grudge_target = rivals[posmod(i + direction, rivals.size())]
	_update_grudge_prompt()


func _fire_grudge() -> void:
	if _grudge_target not in _living_rivals():
		_grudge_target = _first_living_rival()
	if _grudge_target == -1:
		return
	var state: Array = players[_grudge_target]
	NetManager.send_match_input({"grudge": [state[0], state[1]]})
	_grudge_spent = true
	_update_grudge_prompt()


## Shows the grudge aim prompt only for the eliminated local player who still
## has their one grudge; names the current target so aiming reads without a
## separate reticle.
func _update_grudge_prompt() -> void:
	if _grudge_prompt == null:
		return
	var eliminated := _local_lives() == 0
	var rivals := _living_rivals()
	if not eliminated or _grudge_spent or rivals.is_empty():
		_grudge_prompt.visible = false
		return
	if _grudge_target not in rivals:
		_grudge_target = rivals[0]
	_grudge_prompt.visible = true
	_grudge_prompt.text = "GRUDGE → %s    ◀ ▶ aim · press to strike" % player_name(_grudge_target)


func _arena_half() -> float:
	# Frame the scaled platform (ADR 003) — `names` is set before setup runs.
	return Gauntlet.start_radius_for(names.size()) + 2.0


func _setup_3d() -> void:
	# Seed the platform at the scaled start radius so the first frame (before
	# any snapshot) already matches the sim's disc.
	radius = Gauntlet.start_radius_for(names.size())
	_last_radius = radius
	_platform_mesh = CylinderMesh.new()
	_platform_mesh.height = PLATFORM_THICKNESS
	_platform_mesh.top_radius = radius
	_platform_mesh.bottom_radius = radius
	var material := StandardMaterial3D.new()
	material.albedo_color = PLATFORM_COLOR
	_platform_mesh.material = material
	_platform = MeshInstance3D.new()
	_platform.name = "Platform"
	_platform.mesh = _platform_mesh
	_platform.position = Vector3(0.0, PLATFORM_THICKNESS / 2.0, 0.0)
	arena.add_child(_platform)

	_grudge_prompt = Label.new()
	_grudge_prompt.name = "GrudgePrompt"
	_grudge_prompt.add_theme_font_size_override(&"font_size", 30)
	_grudge_prompt.add_theme_color_override(&"font_color", HAZARD_FX_COLOR)
	_grudge_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_grudge_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_grudge_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grudge_prompt.position.y = -70.0
	_grudge_prompt.visible = false
	add_child(_grudge_prompt)


func _render_3d(game: Dictionary) -> void:
	radius = float(game.get("radius", Gauntlet.START_RADIUS))
	players = game.get("players", {})
	hazards = game.get("hazards", [])
	_platform_mesh.top_radius = radius
	_platform_mesh.bottom_radius = radius
	# The platform shrinks in stages; each step sheds a rim, so crumble it away.
	if radius < _last_radius - 0.01:
		_crumble_ring(_last_radius)
	_last_radius = radius
	_update_players()
	_update_hazards()
	_update_grudge_prompt()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var lives := int(state[2])
		# Fall/KO burst where a player was standing the instant they lose a life.
		if lives < int(_last_lives.get(slot, lives)):
			fx_burst(
				Vector2(rig.position.x, rig.position.z), HAZARD_FX_COLOR, PLATFORM_THICKNESS + 0.5
			)
		_last_lives[slot] = lives
		var respawning := float(state[3]) > 0.0
		rig.visible = lives > 0 and not respawning
		if not rig.visible:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		rig.position.y = PLATFORM_THICKNESS
		rig.display_name = "%s %s" % [player_name(slot), "♥".repeat(lives)]


## Dust puffs kicked evenly off the rim the platform just shed as it shrank.
func _crumble_ring(shed_radius: float) -> void:
	for k in CRUMBLE_PUFFS:
		var angle := TAU * k / CRUMBLE_PUFFS
		fx_dust(Vector2(cos(angle), sin(angle)) * shed_radius)


## Stationary hazards keyed by position (snapped to 0.1) so we can tell an armed
## hazard from a fresh spawn and spot the one that vanished on detonation.
func _hazard_key(pos: Vector2) -> String:
	return "%d,%d" % [roundi(pos.x * 10.0), roundi(pos.y * 10.0)]


func _update_hazards() -> void:
	for node in _hazard_nodes:
		node.queue_free()
	_hazard_nodes.clear()
	var current_keys := {}
	for hazard: Array in hazards:
		var pos := Vector2(float(hazard[0]), float(hazard[1]))
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(hazard[2])
		mesh.bottom_radius = float(hazard[2])
		mesh.height = 0.05
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var armed := 1.0 - clampf(float(hazard[3]) / Gauntlet.HAZARD_WARN_SEC, 0.0, 1.0)
		material.albedo_color = HAZARD_COLOR.lerp(HAZARD_ARMED_COLOR, armed)
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = to_arena(pos, PLATFORM_THICKNESS + 0.03)
		arena.add_child(node)
		_hazard_nodes.append(node)
		var key := _hazard_key(pos)
		current_keys[key] = pos
		# Telegraph: a warning spark the moment a fresh hazard is armed.
		if not _last_hazard_keys.has(key):
			fx_sparkle(pos, HAZARD_FX_COLOR, FX_LIFT)
	# Detonation: a burst where a telegraphed hazard just fired and vanished.
	for key: String in _last_hazard_keys:
		if not current_keys.has(key):
			fx_burst(_last_hazard_keys[key], HAZARD_FX_COLOR, FX_LIFT)
	_last_hazard_keys = current_keys
