extends MinigameView3D
## Count Quick client view (M10-08): the swarm scatters as small gold props
## during the flash, then vanishes; four numbered answer pads appear for the
## scramble. Each player's current pick shows on their nameplate — it can still
## change (no lock-in, #799). COUNT! / STAND ON THE ANSWER! call-outs flip with
## the phase.

const SWARM_COLOR := Color(0.96, 0.79, 0.2)
const SWARM_RADIUS := 0.22
const SWARM_POOL := 24
const PAD_COLOR := Color(0.4, 0.6, 0.9, 0.6)
const PAD_DISC_HEIGHT := 0.05
const FLASH_TEXT := "COUNT THE SWARM!"
const ANSWER_TEXT := "STAND ON THE ANSWER!"

## Latest replicated state, straight from CountQuick.get_snapshot().
var players := {}
var phase: int = CountQuick.Phase.FLASH
var swarm: Array = []
var pads: Array = []

var _swarm_pool: Array[MeshInstance3D] = []
# Critter wiggle counter + per-slot last-seen pick (M13-15; #799: a pick is
# now the pad value under the player, -1 for none, and can still change).
var _wiggle_ticks := 0
var _answer_seen := {}
var _scores_seen := {}
var _pad_nodes: Array[Node3D] = []
var _pad_labels: Array[Label3D] = []
var _phase_label: Label


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Bright yellow-green floor for the critter scramble (#589).
func _floor_tint() -> Color:
	return Color(0.95, 1.0, 0.82)


func _arena_half() -> float:
	return CountQuick.ARENA_HALF


func _setup_3d() -> void:
	var swarm_mesh := SphereMesh.new()
	swarm_mesh.radius = SWARM_RADIUS
	swarm_mesh.height = SWARM_RADIUS * 2.0
	var swarm_material := StandardMaterial3D.new()
	swarm_material.albedo_color = SWARM_COLOR
	swarm_material.metallic = 0.5
	swarm_mesh.material = swarm_material
	for i in SWARM_POOL:
		var node := MeshInstance3D.new()
		node.name = "Swarm%d" % i
		node.mesh = swarm_mesh
		node.visible = false
		arena.add_child(node)
		_swarm_pool.append(node)

	for i in 4:
		var pad := Node3D.new()
		pad.name = "Pad%d" % i
		var disc := MeshInstance3D.new()
		disc.name = "Disc"
		var mesh := CylinderMesh.new()
		mesh.top_radius = CountQuick.PAD_RADIUS
		mesh.bottom_radius = CountQuick.PAD_RADIUS
		mesh.height = PAD_DISC_HEIGHT
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = PAD_COLOR
		mesh.material = material
		disc.mesh = mesh
		pad.add_child(disc)
		var label := Label3D.new()
		label.name = "Value"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.004
		label.position.y = 1.2
		pad.add_child(label)
		pad.visible = false
		arena.add_child(pad)
		_pad_nodes.append(pad)
		_pad_labels.append(label)

	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.add_theme_font_size_override(&"font_size", 32)
	_phase_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phase_label.position.y = 16.0
	add_child(_phase_label)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	phase = int(game.get("phase", CountQuick.Phase.FLASH))
	swarm = game.get("swarm", [])
	pads = game.get("pads", [])
	_phase_label.text = FLASH_TEXT if phase == CountQuick.Phase.FLASH else ANSWER_TEXT
	_update_swarm()
	_update_pads()
	_update_players()


## The swarm reads as living critters (M13-15): each prop bobs and jitters on
## an index-phased snapshot-cadence wiggle - deterministic, identical on
## every client, and genuinely harder to count than a static grid.
func _update_swarm() -> void:
	_wiggle_ticks += 1
	for i in _swarm_pool.size():
		var node := _swarm_pool[i]
		node.visible = i < swarm.size()
		if node.visible:
			var state: Array = swarm[i]
			var t := _wiggle_ticks * TAU / 20.0 + i * 1.7
			node.position = to_arena(
				Vector2(
					state[CountQuick.SW_X] + sin(t) * 0.12,
					state[CountQuick.SW_Y] + cos(t * 1.3) * 0.12
				),
				SWARM_RADIUS + absf(sin(t * 2.0)) * 0.15
			)


func _update_pads() -> void:
	for i in _pad_nodes.size():
		var pad := _pad_nodes[i]
		pad.visible = i < pads.size()
		if not pad.visible:
			continue
		var state: Array = pads[i]
		pad.position = to_arena(
			Vector2(state[CountQuick.PD_X], state[CountQuick.PD_Y]), PAD_DISC_HEIGHT / 2.0
		)
		_pad_labels[i].text = str(int(state[CountQuick.PD_VALUE]))


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[CountQuick.PS_X], state[CountQuick.PS_Y]))
		var score := int(state[CountQuick.PS_SCORE])
		var caption := "%s  %d" % [player_name(slot), score]
		var answer := int(state[CountQuick.PS_ANSWER])
		if answer >= 0:
			caption += "  ▶ %d" % answer
		rig.display_name = caption
		# Pick flash (M13-15): landing on a pad — or switching to a different one —
		# sparkles in the player's color. Seeded via _answer_seen; -1 = off all
		# pads, so stepping off doesn't flash.
		var last_answer := int(_answer_seen.get(slot, -1))
		if answer >= 0 and answer != last_answer:
			fx_sparkle(Vector2(state[CountQuick.PS_X], state[CountQuick.PS_Y]), player_color(slot))
			if slot == my_slot:
				play_sfx(&"click")
		_answer_seen[slot] = answer
		# A correct guess pays out (M12-02): only the scorer hears it.
		if slot == my_slot and _scores_seen.has(slot) and score > int(_scores_seen[slot]):
			# A correct guess is a small satisfying consume (#728).
			play_sfx(&"pop")
		_scores_seen[slot] = score
