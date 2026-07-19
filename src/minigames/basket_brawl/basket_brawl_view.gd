extends MinigameView3D
## Basket Brawl client view (M10-09, #1037 NBA2K-feel pass): the shared 2.5D
## iso-arena with players as CharacterRig instances, the ball dribbled beside
## its carrier (raised overhead while charging, skidding on the floor while
## loose), each team's hoop as a raised model + tinted disc, and a bottom
## charge meter that greens inside the perfect-release window. Dunks burst at
## the hoop, fumbles puff dust. Renders get_snapshot() only.

const BALL_COLOR := Color(0.95, 0.6, 0.15)
const HOOP_ALPHA := 0.4
const BALL_RADIUS := 0.35
const CARRY_HEIGHT := 2.0
const HOOP_DISC_HEIGHT := 0.05
## Real hoop + basketball models (#803, MDL-001/002): the hoop rides its post so
## a shot arcs up INTO a raised rim, and the ball is an actual basketball.
const BALL_SCENE := preload("res://assets/generated/models/basketball.glb")
const HOOP_SCENE := preload("res://assets/generated/models/basketball-hoop.glb")
## Reads a little small at iso distance next to a full-size CharacterRig (#929).
const BALL_SCALE := 1.5
## Court dressing (#929): the landed IMG-054 wood texture over the tile floor,
## plus painted lines (center line/circle, key, free-throw circle) as flat
## quad/disc meshes so the court reads as a real basketball court, not a tint.
const COURT_TEXTURE := preload("res://assets/generated/textures/wood-court.png")
const COURT_HALF_WIDTH := 6.0
const COURT_TEXTURE_TILES := 4.0
const COURT_LINE_COLOR := Color(0.95, 0.95, 0.92)
const COURT_LINE_WIDTH := 0.12
const COURT_LINE_HEIGHT := 0.02
const CENTER_CIRCLE_RADIUS := 2.0
const KEY_WIDTH := 4.6
const KEY_DEPTH := 3.2
const FREE_THROW_CIRCLE_RADIUS := 1.8
## The .glb rim sits about here (MDL-001 spec) — the top of a shot's arc lands on it.
const RIM_HEIGHT := 2.6
## A shot lofts this far above the straight launch→rim line at the peak.
const SHOT_ARC_PEAK := 2.2
## NBA2K-feel pass (#1037): the carrier DRIBBLES — the ball bounces beside
## them at this height/rate — and raises it overhead only while charging a
## shot. The meter below mirrors the replicated charge, green inside the
## perfect-release window.
const DRIBBLE_HEIGHT := 1.1
const DRIBBLE_HZ := 3.2
const DRIBBLE_SIDE := 0.55
const METER_CHARGE_COLOR := Color(0.95, 0.65, 0.2)
const METER_SWEET_COLOR := Color(0.3, 0.9, 0.35)
const PERFECT_FLASH_SEC := 0.8

## Latest replicated state, straight from BasketBrawl.get_snapshot().
var players := {}
var ball: Array = []
var scores: Array = [0, 0]
var teams: Array = []
var hoops: Array = []

var _ball_node: Node3D
var _hoop_tint_nodes: Array[MeshInstance3D] = []
var _hoop_materials: Array[StandardMaterial3D] = []
var _hoops_tinted := false
var _score_label: Label
# M10-09 FX seeds: last-seen scores for dunk bursts, last-seen holder for
# fumble dust.
var _scores_seen: Array = []
var _holder_seen := -1
## Shot-arc state (#803): the launch point recorded on the shot's rising edge,
## the enemy hoop it targets, and whether a shot is currently in flight.
var _shot_flying := false
var _shot_launch := Vector2.ZERO
var _shot_target := Vector2.ZERO
## Charge-meter state (#1037): the local charge fraction last seen (a drop
## from inside the sweet window means a greened release) and the flash timer.
var _charge_bar: ProgressBar
var _perfect_label: Label
var _my_charge_seen := 0.0
var _perfect_left := 0.0


func _physics_process(delta: float) -> void:
	send_move_intent()
	if _perfect_left > 0.0:
		_perfect_left -= delta
		if _perfect_left <= 0.0 and _perfect_label != null:
			_perfect_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"act": true})
	elif event.is_action_pressed(&"action_secondary"):
		NetManager.send_match_input({"shoot": true})
	elif event.is_action_released(&"action_secondary"):
		# Release fires the shot — timing against the meter decides quality.
		NetManager.send_match_input({"shoot": false})


## Warm hardwood-court floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.93, 0.8)


func _arena_half() -> float:
	return BasketBrawl.ARENA_HALF + 1.0


func _setup_3d() -> void:
	_build_court()
	# The ball is now an actual basketball model (#803), scaled up (#929) so
	# it doesn't read small next to a full-size rig at iso distance.
	_ball_node = BALL_SCENE.instantiate()
	_ball_node.name = "Ball"
	_ball_node.scale = Vector3.ONE * BALL_SCALE
	arena.add_child(_ball_node)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# A translucent team-tinted disc on the floor still reads "this hoop is
		# ours to defend" at a glance (tinted in _tint_hoops).
		var disc := CylinderMesh.new()
		disc.top_radius = BasketBrawl.HOOP_RADIUS
		disc.bottom_radius = BasketBrawl.HOOP_RADIUS
		disc.height = HOOP_DISC_HEIGHT
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.6, 0.6, 0.6, HOOP_ALPHA)
		disc.material = material
		_hoop_materials.append(material)
		var tint := MeshInstance3D.new()
		tint.name = "Hoop%d" % i
		tint.mesh = disc
		tint.position = to_arena(Vector2(side * BasketBrawl.HOOP_X, 0.0), HOOP_DISC_HEIGHT / 2.0)
		arena.add_child(tint)
		_hoop_tint_nodes.append(tint)
		# The real hoop assembly (#803), raised on its post, rim facing the court
		# so a shot arcs up into it.
		var hoop := HOOP_SCENE.instantiate() as Node3D
		hoop.name = "HoopModel%d" % i
		hoop.position = to_arena(Vector2(side * BasketBrawl.HOOP_X, 0.0), 0.0)
		# Face the rim toward center (#1037): the .glb's rim points -z at rest,
		# so rotation.y maps its facing to (-sin y, -cos y) — the -x hoop needs
		# -PI/2 to open toward +x, the +x hoop +PI/2 (vertex-probe grounded;
		# the old signs pointed both rims off-court).
		hoop.rotation.y = -PI / 2.0 if side < 0.0 else PI / 2.0
		arena.add_child(hoop)
	_score_label = make_banner(&"Score", 28)
	_build_charge_meter()


## The shot meter (#1037, putt_panic's power-bar pattern): bottom-center,
## visible only while the local player charges, tinted green inside the
## perfect-release window and orange outside it — the 2K green-release read.
func _build_charge_meter() -> void:
	_charge_bar = ProgressBar.new()
	_charge_bar.name = "ChargeBar"
	_charge_bar.show_percentage = false
	_charge_bar.custom_minimum_size = Vector2(220.0, 18.0)
	_charge_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_charge_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_charge_bar.position.y = -46.0
	_charge_bar.visible = false
	add_child(_charge_bar)
	_perfect_label = make_status_label(&"PerfectLabel")
	_perfect_label.text = "PERFECT!"
	_perfect_label.visible = false


## The wood-court texture over the play area, plus painted lines (#929).
func _build_court() -> void:
	var half_x := BasketBrawl.HOOP_X + 0.5
	var surface_mesh := PlaneMesh.new()
	surface_mesh.size = Vector2(half_x * 2.0, COURT_HALF_WIDTH * 2.0)
	var surface_material := StandardMaterial3D.new()
	surface_material.albedo_texture = COURT_TEXTURE
	surface_material.uv1_scale = Vector3(COURT_TEXTURE_TILES, COURT_TEXTURE_TILES, 1.0)
	surface_mesh.material = surface_material
	var surface := MeshInstance3D.new()
	surface.name = "CourtSurface"
	surface.mesh = surface_mesh
	surface.position = to_arena(Vector2.ZERO, 0.015)
	arena.add_child(surface)
	_add_court_line(Vector2.ZERO, Vector2(COURT_LINE_WIDTH, COURT_HALF_WIDTH * 2.0))
	_add_court_ring(Vector2.ZERO, CENTER_CIRCLE_RADIUS)
	for side: float in [-1.0, 1.0]:
		var key_inner_x := side * (BasketBrawl.HOOP_X - KEY_DEPTH)
		var key_center_x := side * (BasketBrawl.HOOP_X - KEY_DEPTH / 2.0)
		_add_court_line(
			Vector2(key_center_x, KEY_WIDTH / 2.0), Vector2(KEY_DEPTH, COURT_LINE_WIDTH)
		)
		_add_court_line(
			Vector2(key_center_x, -KEY_WIDTH / 2.0), Vector2(KEY_DEPTH, COURT_LINE_WIDTH)
		)
		_add_court_line(Vector2(key_inner_x, 0.0), Vector2(COURT_LINE_WIDTH, KEY_WIDTH))
		_add_court_ring(Vector2(key_inner_x, 0.0), FREE_THROW_CIRCLE_RADIUS)


## A straight painted line as a thin flat box, `size` in (x-length, y-length).
func _add_court_line(pos: Vector2, size: Vector2) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, COURT_LINE_HEIGHT, size.y)
	var material := StandardMaterial3D.new()
	material.albedo_color = COURT_LINE_COLOR
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = to_arena(pos, COURT_LINE_HEIGHT / 2.0 + 0.02)
	arena.add_child(node)


## A painted ring: a line-colored disc with a smaller court-textured disc on
## top, so only the border shows — cheaper than building real ring geometry.
func _add_court_ring(pos: Vector2, radius: float) -> void:
	var outer := CylinderMesh.new()
	outer.top_radius = radius
	outer.bottom_radius = radius
	outer.height = COURT_LINE_HEIGHT
	var outer_material := StandardMaterial3D.new()
	outer_material.albedo_color = COURT_LINE_COLOR
	outer.material = outer_material
	var outer_node := MeshInstance3D.new()
	outer_node.mesh = outer
	outer_node.position = to_arena(pos, COURT_LINE_HEIGHT / 2.0 + 0.02)
	arena.add_child(outer_node)
	var inner := CylinderMesh.new()
	inner.top_radius = radius - COURT_LINE_WIDTH
	inner.bottom_radius = radius - COURT_LINE_WIDTH
	inner.height = COURT_LINE_HEIGHT
	var inner_material := StandardMaterial3D.new()
	inner_material.albedo_texture = COURT_TEXTURE
	inner.material = inner_material
	var inner_node := MeshInstance3D.new()
	inner_node.mesh = inner
	inner_node.position = to_arena(pos, COURT_LINE_HEIGHT / 2.0 + 0.03)
	arena.add_child(inner_node)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	ball = game.get("ball", [])
	scores = game.get("scores", [0, 0])
	teams = game.get("teams", [])
	hoops = game.get("hoops", [])
	_tint_hoops()
	_update_players()
	_update_ball()
	_update_score()
	_update_charge_meter()


## Mirrors the local player's replicated charge onto the meter (#1037). The
## meter vanishing from inside the sweet window means the release greened —
## flash PERFECT! so the timing skill has a readable payoff.
func _update_charge_meter() -> void:
	if _charge_bar == null:
		return
	var state: Array = players.get(my_slot, [])
	var charge := 0.0
	if state.size() >= BasketBrawl.PS_COUNT and int(state[BasketBrawl.PS_HAS_BALL]) == 1:
		charge = float(state[BasketBrawl.PS_CHARGE])
	_charge_bar.visible = charge > 0.0
	_charge_bar.value = charge * 100.0
	var sweet := charge >= BasketBrawl.PERFECT_LO and charge <= BasketBrawl.PERFECT_HI
	_charge_bar.modulate = METER_SWEET_COLOR if sweet else METER_CHARGE_COLOR
	var was_sweet := (
		_my_charge_seen >= BasketBrawl.PERFECT_LO and _my_charge_seen <= BasketBrawl.PERFECT_HI
	)
	# _shot_flying gates out fumbles: a shove also zeroes the charge, but only
	# a real release puts a shot in the air.
	if charge == 0.0 and was_sweet and _shot_flying and _perfect_label != null:
		_perfect_label.visible = true
		_perfect_left = PERFECT_FLASH_SEC
		play_sfx(&"confirm")
	_my_charge_seen = charge


## Hoops take their defending team's color, once teams arrive (a hoop reads
## as "this is OUR basket to defend" — dunks happen at the other one).
func _tint_hoops() -> void:
	if _hoops_tinted or teams.size() != 2 or teams[0].is_empty():
		return
	_hoops_tinted = true
	for i in 2:
		var color := player_color(int(teams[i][0]))
		_hoop_materials[i].albedo_color = Color(color, HOOP_ALPHA)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		if rig_for_slot(slot) == null:
			continue
		update_rig(slot, Vector2(state[BasketBrawl.PS_X], state[BasketBrawl.PS_Y]))


func _update_ball() -> void:
	if ball.size() < BasketBrawl.BALL_COUNT:
		return
	var ball_holder := int(ball[BasketBrawl.BALL_HOLDER])
	var shooting := int(ball[BasketBrawl.BALL_SHOT]) == 1
	var ball_pos := Vector2(float(ball[BasketBrawl.BALL_X]), float(ball[BasketBrawl.BALL_Y]))
	_track_shot(shooting, ball_pos)
	var height := BALL_RADIUS
	if ball_holder >= 0:
		# Dribble (#1037): the ball bounces beside the carrier instead of
		# gluing overhead — raised to a two-hand set only while charging.
		if _holder_is_charging(ball_holder):
			height = CARRY_HEIGHT
		else:
			var beat := Time.get_ticks_msec() / 1000.0 * PI * DRIBBLE_HZ
			height = BALL_RADIUS + (DRIBBLE_HEIGHT - BALL_RADIUS) * absf(sin(beat))
			ball_pos += _dribble_side(ball_holder, ball_pos)
	elif shooting:
		height = _shot_arc_height(ball_pos)
	_ball_node.position = to_arena(ball_pos, height)
	# Fumble dust (juice): the holder vanishing without a score change means the
	# ball popped loose — but a shot launch also clears the holder, so a live
	# shot is not a fumble. Seeded via _holder_seen/_scores_seen.
	if _holder_seen >= 0 and ball_holder == -1 and scores == _scores_seen and not shooting:
		fx_dust(ball_pos)
		# The shoved-off carrier now recoils, not just puffs dust (#1038): the
		# shared hit reaction (Hit_A + impact) sells the steal.
		play_hit(_holder_seen)
		# Signature cue (#728): heard by the player who got shoved off the
		# ball — a `bump`, not a score/UI sound.
		if _holder_seen == my_slot:
			play_sfx(&"bump")
	_holder_seen = ball_holder


func _holder_is_charging(holder: int) -> bool:
	var state: Array = players.get(holder, [])
	return state.size() >= BasketBrawl.PS_COUNT and float(state[BasketBrawl.PS_CHARGE]) > 0.0


## The dribble sits off the carrier's shooting hand: perpendicular-right of
## the line to the hoop they attack (falls back to +x with no team data yet).
func _dribble_side(holder: int, ball_pos: Vector2) -> Vector2:
	var dir := Vector2.RIGHT
	if teams.size() == 2 and hoops.size() == 2:
		var team := 0 if holder in (teams[0] as Array) else 1
		var hoop: Array = hoops[1 - team]
		var to_hoop := (
			Vector2(float(hoop[BasketBrawl.HP_X]), float(hoop[BasketBrawl.HP_Y])) - ball_pos
		)
		if to_hoop.length() > 0.1:
			dir = to_hoop.normalized()
	return Vector2(dir.y, -dir.x) * DRIBBLE_SIDE


## Records a shot's launch point on its rising edge (so the arc has a start),
## and clangs the rim on a miss — a shot ending in flight with no score change
## rebounded (#803). A made shot ends via the score tick, handled in _update_score.
func _track_shot(shooting: bool, ball_pos: Vector2) -> void:
	if shooting and not _shot_flying:
		_shot_flying = true
		_shot_launch = ball_pos
		var far := Vector2(BasketBrawl.HOOP_X, 0.0)
		var near := Vector2(-BasketBrawl.HOOP_X, 0.0)
		_shot_target = far if ball_pos.distance_to(far) > ball_pos.distance_to(near) else near
	elif _shot_flying and not shooting:
		_shot_flying = false
		if scores == _scores_seen:
			fx_burst(_shot_target, Color(0.7, 0.7, 0.72), RIM_HEIGHT)
			play_sfx(&"bump")


## A shot rises from the ball's height to the rim, cresting SHOT_ARC_PEAK above
## the straight line at the midpoint — a real basketball arc into a raised hoop.
func _shot_arc_height(ball_pos: Vector2) -> float:
	var total := _shot_launch.distance_to(_shot_target)
	if total < 0.01:
		return RIM_HEIGHT
	var progress := clampf(1.0 - ball_pos.distance_to(_shot_target) / total, 0.0, 1.0)
	return lerpf(BALL_RADIUS, RIM_HEIGHT, progress) + SHOT_ARC_PEAK * sin(progress * PI)


func _update_score() -> void:
	# Dunk burst (juice): a score ticking up bursts at the hoop that team
	# attacks (index 1 - team, hoops are indexed by defender).
	if _scores_seen.size() == 2 and hoops.size() == 2:
		for team in 2:
			if int(scores[team]) > int(_scores_seen[team]):
				var hoop: Array = hoops[1 - team]
				var color := player_color(int(teams[team][0])) if teams.size() == 2 else BALL_COLOR
				fx_burst(
					Vector2(float(hoop[BasketBrawl.HP_X]), float(hoop[BasketBrawl.HP_Y])), color
				)
				# Every dunk is heard from your own team's perspective (M12-02).
				# Signature cue (#728): `bell` for a scored basket, matching
				# docs/AUDIO_GUIDE.md's own worked example.
				if teams.size() == 2:
					play_sfx(&"bell" if my_slot in teams[team] else &"error")
	_scores_seen = scores.duplicate()
	if _score_label != null:
		_score_label.text = "%d : %d" % [int(scores[0]), int(scores[1])]
