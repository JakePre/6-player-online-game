extends MinigameView3D
## Basket Brawl client view (M10-09): the shared 2.5D iso-arena with players
## as CharacterRig instances, the ball as a gold sphere (riding above the
## carrier's head, skidding on the floor while loose), and each team's hoop
## as a translucent tinted disc. Dunks burst at the hoop, fumbles puff dust
## where the ball popped loose. Renders get_snapshot() only.

const BALL_COLOR := Color(0.95, 0.6, 0.15)
const HOOP_ALPHA := 0.4
const BALL_RADIUS := 0.35
const CARRY_HEIGHT := 2.0
const HOOP_DISC_HEIGHT := 0.05
## Real hoop + basketball models (#803, MDL-001/002): the hoop rides its post so
## a shot arcs up INTO a raised rim, and the ball is an actual basketball.
const BALL_SCENE := preload("res://assets/generated/models/basketball.glb")
const HOOP_SCENE := preload("res://assets/generated/models/basketball-hoop.glb")
## The .glb rim sits about here (MDL-001 spec) — the top of a shot's arc lands on it.
const RIM_HEIGHT := 2.6
## A shot lofts this far above the straight launch→rim line at the peak.
const SHOT_ARC_PEAK := 2.2

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


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if event.is_action_pressed(&"action_primary"):
		NetManager.send_match_input({"act": true})
	elif event.is_action_pressed(&"action_secondary"):
		NetManager.send_match_input({"shoot": true})


## Warm hardwood-court floor (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.93, 0.8)


func _arena_half() -> float:
	return BasketBrawl.ARENA_HALF + 1.0


func _setup_3d() -> void:
	# The ball is now an actual basketball model (#803).
	_ball_node = BALL_SCENE.instantiate()
	_ball_node.name = "Ball"
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
		# Face the rim toward center: mirror the two hoops so both open inward.
		hoop.rotation.y = PI / 2.0 if side < 0.0 else -PI / 2.0
		arena.add_child(hoop)
	_score_label = make_banner(&"Score", 28)


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
		height = CARRY_HEIGHT
	elif shooting:
		height = _shot_arc_height(ball_pos)
	_ball_node.position = to_arena(ball_pos, height)
	# Fumble dust (juice): the holder vanishing without a score change means the
	# ball popped loose — but a shot launch also clears the holder, so a live
	# shot is not a fumble. Seeded via _holder_seen/_scores_seen.
	if _holder_seen >= 0 and ball_holder == -1 and scores == _scores_seen and not shooting:
		fx_dust(ball_pos)
		# Signature cue (#728): heard by the player who got shoved off the
		# ball — a `bump`, not a score/UI sound.
		if _holder_seen == my_slot:
			play_sfx(&"bump")
	_holder_seen = ball_holder


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
