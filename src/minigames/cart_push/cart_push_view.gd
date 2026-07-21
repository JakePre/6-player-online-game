extends MinigameView3D
## Payload Race client view (#932, reworked from the shared-cart Cart Push
## #175, on the M8-01 MinigameView3D tier): two team-colored carts ride their
## own parallel rails from a shared start line toward the finish. Each cart's
## position reads its lane's monotonic progress, so the standings are legible at
## a glance. Wheel dust scales with how hard each cart is being pushed; shove
## windups play the interact pose (the telegraph) and staggered players flinch.
## A Control-layer banner tells the local player to mash beside their own cart.
##
## Carts use the MDL-013 mine-cart model (#932 follow-up); the per-lane
## progress bars and finish banners remain for a later gameplay pass.

## Declarative button input (#947): shove. Was a raw Input poll in _process
## with no null-peer guard — the event-based base structurally closes that gap.
const INPUT_ACTIONS := {&"action_primary": "shove"}
const EMBER_FLOOR := preload("res://assets/generated/textures/ember-rock.png")
## Rim scenery (#1129): rocks and boulders ring the mine track, dressing the
## arena edge via the shared scatter_rim_props helper.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/rock_smallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallB.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_tallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_tallB.glb"),
	preload("res://assets/environment/kenney_nature_kit/cliff_rock.glb"),
]
const RIM_PROP_COUNT := 24
const RIM_PROP_SEED := 0xCA0E
## Mine lanterns: pole height, globe radius, glow color.
const LANTERN_POLE_HEIGHT := 1.8
const LANTERN_GLOBE_RADIUS := 0.25
const LANTERN_GLOW := Color(1.0, 0.7, 0.3)
const LANTERN_COUNT := 6
## Track cross-ties: spacing and dimensions.
const TIE_SPACING := 0.5
const TIE_WIDTH := 0.12
const TIE_DEPTH := 1.2
## Scattered gold coins along the track.
const GOLD_COIN_SCENE := preload("res://assets/environment/kenney_platformer_kit/coin-gold.glb")
const GOLD_COIN_COUNT := 8
const GOLD_COIN_SEED := 0x70CA
const TEAM_COLORS: Array[Color] = [Color(0.9, 0.5, 0.2), Color(0.35, 0.6, 0.95)]
const RAIL_COLOR := Color(0.35, 0.3, 0.25)
const START_COLOR := Color(0.85, 0.85, 0.85)
const FINISH_COLOR := Color(0.95, 0.85, 0.2)
## MDL-013 mine cart: base-pivoted, long axis +Z, native ~1.8 long / 1.78 tall.
const CART_SCENE := preload("res://assets/generated/models/mine-cart.glb")
## Wheel dust (M13-23): one puff per this many world units a cart rolls.
const DUST_STEP := 0.6

## Latest replicated state, straight from CartPush.get_snapshot().
var players := {}
var teams: Array = []
var progress: Array = [0.0, 0.0]

var _carts: Array[Node3D] = []
var _push_label: Label
var _my_team := -1
var _prev_prog: Array[float] = [0.0, 0.0]
var _dust_accum: Array[float] = [0.0, 0.0]
var _staggered := {}  # slot (int) -> bool, for one-shot shove-impact puffs


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Ember-rock cavern floor (#1129): override the default tiled floor with a
## single textured plane using the ember-rock texture, giving the mine cart
## track a cavern-floor feel.
func _build_floor() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(_arena_half() * 2.0, _arena_half() * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = EMBER_FLOOR
	material.albedo_color = Color(0.85, 0.75, 0.6)
	mesh.material = material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = mesh
	floor_node.position.y = -0.01
	arena.add_child(floor_node)


## Warm-dark cavern mood (#1129): pushes the party-stadium shell toward a warm
## orange-brown atmosphere, matching the ember-rock floor and mine theme.
func _mood() -> Color:
	return Color(0.15, 0.1, 0.08).lerp(Color(0.4, 0.25, 0.15), 0.3)


func _arena_half() -> float:
	return CartPush.ARENA_HALF


func _setup_3d() -> void:
	_build_rails()
	_build_start_finish()
	_build_carts()
	_build_labels()
	_build_track_ties()
	_build_mine_lights()
	_build_gold_coins()
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	teams = game.get("teams", [])
	progress = game.get("carts", [0.0, 0.0])
	for team_index in _carts.size():
		var prog := float(progress[team_index]) if team_index < progress.size() else 0.0
		# height 0: the mine-cart model is base-pivoted, so it sits on the rail
		_carts[team_index].position = to_arena(
			Vector2(-CartPush.TRACK_HALF + prog, _lane_y(team_index)), 0.0
		)
		_kick_wheel_dust(team_index, prog)
	_update_players()
	_update_labels()


func _lane_y(team_index: int) -> float:
	return -CartPush.LANE_Y if team_index == 0 else CartPush.LANE_Y


## A cart's wheels kick dust as it rolls: accumulate travel and drop one puff
## under the cart per DUST_STEP of movement (M13-23), so dust scales with how
## hard the cart is pushed rather than with the snapshot rate.
func _kick_wheel_dust(team_index: int, prog: float) -> void:
	_dust_accum[team_index] += absf(prog - _prev_prog[team_index])
	_prev_prog[team_index] = prog
	while _dust_accum[team_index] >= DUST_STEP:
		_dust_accum[team_index] -= DUST_STEP
		fx_dust(Vector2(-CartPush.TRACK_HALF + prog, _lane_y(team_index)))


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[CartPush.PS_X], state[CartPush.PS_Y]))
		var flags := int(state[CartPush.PS_FLAGS])
		var desired: StringName = &"idle"
		if flags & CartPush.FLAG_STAGGERED:
			desired = &"hit"
		elif flags & CartPush.FLAG_WINDUP:
			desired = &"interact"  # shove windup telegraph
		if desired != &"idle" and rig.current_action() != desired:
			rig.play(desired)
		# Shove landed (stagger rising edge): a dust puff kicks up (M13-23).
		var staggered := flags & CartPush.FLAG_STAGGERED == CartPush.FLAG_STAGGERED
		if staggered and not _staggered.get(slot, false):
			fx_dust(Vector2(state[CartPush.PS_X], state[CartPush.PS_Y]))
			if slot == my_slot:
				# A non-damaging shove (#728) — the vocabulary's own "shove"
				# example for bump.
				play_sfx(&"bump")
		_staggered[slot] = staggered
		rig.display_name = player_name(slot)


func _update_labels() -> void:
	if _my_team == -1 and not teams.is_empty():
		for team_index in teams.size():
			if my_slot in (teams[team_index] as Array):
				_my_team = team_index
	if _my_team != -1:
		_push_label.text = "MASH ◀▶ AT YOUR CART!"
		_push_label.add_theme_color_override(&"font_color", TEAM_COLORS[_my_team])


func _build_rails() -> void:
	for team_index in 2:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(CartPush.TRACK_LENGTH, 0.06, 0.4)
		var material := StandardMaterial3D.new()
		material.albedo_color = RAIL_COLOR
		mesh.material = material
		var rail := MeshInstance3D.new()
		rail.name = "Rail%d" % team_index
		rail.mesh = mesh
		rail.position = Vector3(0.0, 0.03, _lane_y(team_index))
		arena.add_child(rail)


func _build_start_finish() -> void:
	_build_line("StartLine", -CartPush.TRACK_HALF, START_COLOR)
	_build_line("FinishLine", CartPush.TRACK_HALF, FINISH_COLOR)


func _build_line(node_name: String, x: float, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.06, CartPush.LANE_Y * 2.0 + 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.4
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = Vector3(x, 0.05, 0.0)
	arena.add_child(node)


func _build_carts() -> void:
	_carts.clear()
	for team_index in 2:
		var cart := Node3D.new()
		cart.name = "Cart%d" % team_index
		# The model's long axis is +Z and the track runs along X, so rotate
		# 90° to lay the cart's length along the direction of travel. Its
		# wood/gold/iron texture is kept as-is (unlike the neutral go-kart it
		# must NOT be tinted) — the two carts sit in fixed lanes ±LANE_Y apart,
		# so lane position identifies the team.
		var body := CART_SCENE.instantiate() as Node3D
		body.name = "Body"
		body.rotation.y = PI / 2.0
		cart.add_child(body)
		# A small team-colored flag preserves the team-ID the placeholder gave,
		# without touching the cart's own colors.
		var flag := MeshInstance3D.new()
		flag.name = "Flag"
		var fmesh := BoxMesh.new()
		fmesh.size = Vector3(0.12, 0.7, 0.5)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = TEAM_COLORS[team_index]
		fmat.emission_enabled = true
		fmat.emission = TEAM_COLORS[team_index]
		fmat.emission_energy_multiplier = 0.3
		fmesh.material = fmat
		flag.mesh = fmesh
		flag.position = Vector3(0.0, 2.15, 0.0)
		cart.add_child(flag)
		arena.add_child(cart)
		_carts.append(cart)


func _build_labels() -> void:
	_push_label = make_status_label(&"PushLabel")


## Track cross-ties (#1129): small BoxMesh planks across both rails at regular
## intervals for a railroad look. Placed every TIE_SPACING units along the track.
func _build_track_ties() -> void:
	var half_track := CartPush.TRACK_HALF
	var pos := -half_track
	while pos <= half_track:
		var tie := MeshInstance3D.new()
		tie.name = "Tie%.1f" % pos
		var mesh := BoxMesh.new()
		mesh.size = Vector3(TIE_WIDTH, 0.03, TIE_DEPTH)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.18, 0.1)
		mesh.material = material
		tie.mesh = mesh
		tie.position = Vector3(pos, 0.01, 0.0)
		arena.add_child(tie)
		pos += TIE_SPACING


## Mine lanterns (#1129): tall thin poles with a glowing orb at the top,
## placed on both sides of the track to light the mine path.
func _build_mine_lights() -> void:
	for i in LANTERN_COUNT:
		var t := float(i) / float(LANTERN_COUNT - 1)
		var x := lerpf(-CartPush.TRACK_HALF, CartPush.TRACK_HALF, t)
		for side in [-1, 1]:
			var y: float = side * (CartPush.LANE_Y + 1.2)
			var pole := MeshInstance3D.new()
			pole.name = "LanternPole%d_%d" % [i, side]
			var pmesh := CylinderMesh.new()
			pmesh.top_radius = 0.04
			pmesh.bottom_radius = 0.06
			pmesh.height = LANTERN_POLE_HEIGHT
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.45, 0.35, 0.25)
			pmesh.material = pmat
			pole.mesh = pmesh
			pole.position = Vector3(x, LANTERN_POLE_HEIGHT * 0.5, y)
			arena.add_child(pole)
			var globe := MeshInstance3D.new()
			globe.name = "LanternGlobe%d_%d" % [i, side]
			var gmesh := SphereMesh.new()
			gmesh.radius = LANTERN_GLOBE_RADIUS
			gmesh.height = LANTERN_GLOBE_RADIUS * 2.0
			var gmat := StandardMaterial3D.new()
			gmat.albedo_color = LANTERN_GLOW
			gmat.emission_enabled = true
			gmat.emission = LANTERN_GLOW
			gmat.emission_energy_multiplier = 0.5
			gmesh.material = gmat
			globe.mesh = gmesh
			globe.position = Vector3(x, LANTERN_POLE_HEIGHT, y)
			arena.add_child(globe)
			# A second, larger translucent glow sphere for a soft halo.
			var halo := MeshInstance3D.new()
			halo.name = "LanternHalo%d_%d" % [i, side]
			var hmesh := SphereMesh.new()
			hmesh.radius = LANTERN_GLOBE_RADIUS * 1.8
			hmesh.height = LANTERN_GLOBE_RADIUS * 3.6
			var hmat := StandardMaterial3D.new()
			hmat.albedo_color = Color(LANTERN_GLOW, 0.15)
			hmat.emission_enabled = true
			hmat.emission = LANTERN_GLOW
			hmat.emission_energy_multiplier = 0.1
			hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hmesh.material = hmat
			halo.mesh = hmesh
			halo.position = Vector3(x, LANTERN_POLE_HEIGHT, y)
			arena.add_child(halo)


## Decorative gold coins (#1129): scatter coin-gold.glb models along the track
## at fixed seeded positions as non-interactive mine-bonus dressing.
func _build_gold_coins() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GOLD_COIN_SEED
	for i in GOLD_COIN_COUNT:
		var coin := GOLD_COIN_SCENE.instantiate() as Node3D
		if coin == null:
			continue
		coin.name = "GoldCoin%d" % i
		var x := rng.randf_range(-CartPush.TRACK_HALF, CartPush.TRACK_HALF)
		var y := rng.randf_range(-CartPush.LANE_Y - 0.5, CartPush.LANE_Y + 0.5)
		coin.position = to_arena(Vector2(x, y), 0.02)
		coin.rotation.y = rng.randf() * TAU
		coin.scale = Vector3(0.4, 0.4, 0.4)
		arena.add_child(coin)
