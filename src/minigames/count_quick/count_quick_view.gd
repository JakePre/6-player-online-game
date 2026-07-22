extends MinigameView3D
## Count Quick client view (M10-08): the swarm scatters as small gold props
## during the flash, then vanishes; four numbered answer pads appear for the
## scramble. Each player's current pick shows on their nameplate — it can still
## change (no lock-in, #799). COUNT! / STAND ON THE ANSWER! call-outs flip with
## the phase.

const SWARM_RADIUS := 0.22
const SWARM_POOL := 24
const PAD_COLOR := Color(0.4, 0.6, 0.9, 0.6)
const PAD_DISC_HEIGHT := 0.05
const FLASH_TEXT := "COUNT THE SWARM!"
const ANSWER_TEXT := "STAND ON THE ANSWER!"
## Critter swarm (#1131 Tier 1): the Kenney platformer-kit character props
## replace the plain gold spheres — cycled round-robin across the pool so
## adjacent critters in the swarm read as distinct little guys, not a repeat.
const CRITTER_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_platformer_kit/character-oobi.glb"),
	preload("res://assets/environment/kenney_platformer_kit/character-oodi.glb"),
	preload("res://assets/environment/kenney_platformer_kit/character-ooli.glb"),
	preload("res://assets/environment/kenney_platformer_kit/character-oopi.glb"),
	preload("res://assets/environment/kenney_platformer_kit/character-oozi.glb"),
]
const CRITTER_SCALE := 0.45
## Raised beveled pads (#1131): a torus rim + a slight lift so the answer
## discs read as small platforms, not flat decals.
const PAD_RIM_COLOR := Color(0.55, 0.75, 1.0)
const PAD_RIM_THICKNESS := 0.06
const PAD_LIFT := 0.1
## Stone-pavers floor (#1131): replaces the flat tint under the swarm/pads.
const FLOOR_TEXTURE := preload("res://assets/generated/textures/stone-pavers.png")
const FLOOR_TEXTURE_TILES := 6.0
## Rim rubble (#1131): the issue's flagged "no scatter_rim_props()" gap.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/rock_smallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallB.glb"),
]
const RIM_PROP_COUNT := 14
const RIM_PROP_SEED := 0xC0117

## Latest replicated state, straight from CountQuick.get_snapshot().
var players := {}
var phase: int = CountQuick.Phase.FLASH
var swarm: Array = []
var pads: Array = []

var _swarm_pool: Array[Node3D] = []
# Critter wiggle counter (M13-15; #799: a pick is now the pad value under the
# player, -1 for none, and can still change).
var _wiggle_ticks := 0
var _answer_edges := EdgeTracker.new()
var _score_edges := EdgeTracker.new()
var _pad_nodes: Array[Node3D] = []
var _pad_labels: Array[Label3D] = []
var _phase_label: Label


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Bright yellow-green floor for the critter scramble (#589).
func _floor_tint() -> Color:
	return Color(0.95, 1.0, 0.82)


## Stone-paver floor (#1131) under the swarm and pads, replacing the flat tint.
func _build_floor() -> void:
	var floor_node := _dresser.build_floor(_floor_tile_scene(), _floor_tint(), _arena_half())
	if floor_node != null:
		var mat := floor_node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_texture = FLOOR_TEXTURE
			mat.uv1_scale = Vector3(FLOOR_TEXTURE_TILES, FLOOR_TEXTURE_TILES, 1.0)


func _arena_half() -> float:
	return CountQuick.ARENA_HALF


func _setup_3d() -> void:
	for i in SWARM_POOL:
		# Round-robin the 5 critter models (#1131 Tier 1) so the swarm reads as
		# distinct little guys rather than a repeated prop.
		var critter := CRITTER_SCENES[i % CRITTER_SCENES.size()].instantiate() as Node3D
		critter.name = "Swarm%d" % i
		critter.scale = Vector3.ONE * CRITTER_SCALE
		critter.visible = false
		arena.add_child(critter)
		_swarm_pool.append(critter)

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
		disc.position.y = PAD_LIFT
		pad.add_child(disc)
		# Beveled rim (#1131 Tier 2): a torus at the disc's edge sells "raised
		# platform" instead of a flat decal.
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		var rim_mesh := TorusMesh.new()
		rim_mesh.inner_radius = CountQuick.PAD_RADIUS - PAD_RIM_THICKNESS
		rim_mesh.outer_radius = CountQuick.PAD_RADIUS
		var rim_material := StandardMaterial3D.new()
		rim_material.albedo_color = PAD_RIM_COLOR
		rim_material.emission_enabled = true
		rim_material.emission = PAD_RIM_COLOR
		rim_material.emission_energy_multiplier = 0.4
		rim_mesh.material = rim_material
		rim.mesh = rim_mesh
		rim.rotation.x = PI / 2.0
		rim.position.y = PAD_LIFT + PAD_DISC_HEIGHT / 2.0
		pad.add_child(rim)
		var label := Label3D.new()
		label.name = "Value"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		# STYLE_GUIDE Label3D rule: pixel_size = 0.002, size via font_size,
		# outline_size >= font_size / 4.
		label.pixel_size = 0.002
		label.font_size = 40
		label.outline_size = 14
		label.position.y = 1.2
		pad.add_child(label)
		pad.visible = false
		arena.add_child(pad)
		_pad_nodes.append(pad)
		_pad_labels.append(label)

	_phase_label = make_status_label(&"PhaseLabel")
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


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
		# sparkles in the player's color. -1 = off all pads, so stepping off
		# doesn't flash; seeded, so a rejoiner already on a pad doesn't either.
		var picked := _answer_edges.changed(slot, answer)
		if answer >= 0 and picked:
			fx_sparkle(Vector2(state[CountQuick.PS_X], state[CountQuick.PS_Y]), player_color(slot))
			if slot == my_slot:
				play_sfx(&"click")
		# A correct guess pays out (M12-02): only the scorer hears it.
		if slot == my_slot and _score_edges.rose(slot, score):
			# A correct guess is a small satisfying consume (#728).
			play_sfx(&"pop")
