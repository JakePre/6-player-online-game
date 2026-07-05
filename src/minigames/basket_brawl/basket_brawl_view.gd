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

## Latest replicated state, straight from BasketBrawl.get_snapshot().
var players := {}
var ball: Array = []
var scores: Array = [0, 0]
var teams: Array = []
var hoops: Array = []

var _ball_node: MeshInstance3D
var _hoop_nodes: Array[MeshInstance3D] = []
var _hoop_materials: Array[StandardMaterial3D] = []
var _hoops_tinted := false
var _score_label: Label
# M10-09 FX seeds: last-seen scores for dunk bursts, last-seen holder for
# fumble dust.
var _scores_seen: Array = []
var _holder_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"act": true})


func _arena_half() -> float:
	return BasketBrawl.ARENA_HALF + 1.0


func _setup_3d() -> void:
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = BALL_RADIUS
	ball_mesh.height = BALL_RADIUS * 2.0
	var ball_material := StandardMaterial3D.new()
	ball_material.albedo_color = BALL_COLOR
	ball_material.emission_enabled = true
	ball_material.emission = BALL_COLOR
	ball_material.emission_energy_multiplier = 0.25
	ball_mesh.material = ball_material
	_ball_node = MeshInstance3D.new()
	_ball_node.name = "Ball"
	_ball_node.mesh = ball_mesh
	arena.add_child(_ball_node)
	for i in 2:
		var disc := CylinderMesh.new()
		disc.top_radius = BasketBrawl.HOOP_RADIUS
		disc.bottom_radius = BasketBrawl.HOOP_RADIUS
		disc.height = HOOP_DISC_HEIGHT
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.6, 0.6, 0.6, HOOP_ALPHA)
		disc.material = material
		_hoop_materials.append(material)
		var node := MeshInstance3D.new()
		node.name = "Hoop%d" % i
		node.mesh = disc
		var side := -1.0 if i == 0 else 1.0
		node.position = to_arena(Vector2(side * BasketBrawl.HOOP_X, 0.0), HOOP_DISC_HEIGHT / 2.0)
		arena.add_child(node)
		_hoop_nodes.append(node)
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
		update_rig(slot, Vector2(state[0], state[1]))


func _update_ball() -> void:
	if ball.size() < 3:
		return
	var ball_holder := int(ball[2])
	var height := CARRY_HEIGHT if ball_holder >= 0 else BALL_RADIUS
	_ball_node.position = to_arena(Vector2(float(ball[0]), float(ball[1])), height)
	# Fumble dust (juice): the holder vanishing without a score change means
	# the ball just popped loose. Seeded via _holder_seen/_scores_seen.
	if _holder_seen >= 0 and ball_holder == -1 and scores == _scores_seen:
		fx_dust(Vector2(float(ball[0]), float(ball[1])))
	_holder_seen = ball_holder


func _update_score() -> void:
	# Dunk burst (juice): a score ticking up bursts at the hoop that team
	# attacks (index 1 - team, hoops are indexed by defender).
	if _scores_seen.size() == 2 and hoops.size() == 2:
		for team in 2:
			if int(scores[team]) > int(_scores_seen[team]):
				var hoop: Array = hoops[1 - team]
				var color := player_color(int(teams[team][0])) if teams.size() == 2 else BALL_COLOR
				fx_burst(Vector2(float(hoop[0]), float(hoop[1])), color)
				# Every dunk is heard from your own team's perspective (M12-02).
				if teams.size() == 2:
					play_sfx(&"confirm" if my_slot in teams[team] else &"error")
	_scores_seen = scores.duplicate()
	if _score_label != null:
		_score_label.text = "%d : %d" % [int(scores[0]), int(scores[1])]
