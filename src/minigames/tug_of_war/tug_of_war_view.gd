extends MinigameView3D
## Tug of War client view (M8-09): renders the replicated tug in the shared
## 2.5D iso-arena (M8-01, MinigameView3D) — the rope as a stretched bar with
## a marker knot tracking the replicated offset, teams lined up on their
## sides as CharacterRigs leaning into the pull. Presentation-tier swap only:
## state storage and the alternating pull input are unchanged from the 2D
## pass (M4-10).

const ROPE_COLOR := Color(0.85, 0.65, 0.35)
const MARKER_COLOR := Color(1.0, 0.9, 0.4)
const LINE_COLOR := Color(0.9, 0.25, 0.25)
const ROPE_HEIGHT := 0.9
const ROPE_THICKNESS := 0.3
## Rope world length is a little longer than the two win offsets.
const ROPE_EXTRA := 4.0
## Where teams stand relative to the rope line.
const TEAM_ROW_Z := 1.6
const TEAMMATE_SPACING := 1.4
## Team identity (#215): side tints in the arena and on the HUD bar. Team A
## owns -x, team B +x.
const TEAM_A_COLOR := Color(0.35, 0.72, 1.0)
const TEAM_B_COLOR := Color(1.0, 0.42, 0.1)
const SIDE_TINT_ALPHA := 0.24
## HUD tug bar geometry (drawn on the Control layer).
const BAR_WIDTH := 480.0
const BAR_HEIGHT := 14.0
const BAR_TOP := 20.0
## FX pass (#314): a pull moves the rope at least this far to spark juice, the
## knot flares this long, and the win burst throws this many streamers.
const PULL_EPSILON := 0.02
const KNOT_FLARE_SEC := 0.18
const SCUFF_SEC := 0.4
const WIN_BURST_SEC := 0.7
const WIN_STREAMERS := 16

## Latest replicated state, straight from TugOfWar.get_snapshot().
var rope := 0.0
var win_offset := TugOfWar.WIN_OFFSET
var team_a: Array = []
var team_b: Array = []

var _marker: MeshInstance3D
var _marker_material: StandardMaterial3D
var _phase := -1
var _last_rope := 0.0
## HUD layer: sits above the 3D SubViewportContainer (the view root's own
## canvas draws underneath it, so the bar must live on this child).
var _hud: Control
## FX state (#314): knot-flare clock and the once-per-round win guard.
var _knot_flare_until := 0.0
var _win_fired := false


## Polled (not event-driven): stick axis motion doesn't deliver discrete
## pressed events reliably, which left gamepads unable to pull at all (#136).
## is_action_just_pressed unifies keys, d-pad, and stick threshold crossings.
func _process(_delta: float) -> void:
	_decay_knot_flare()
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	var phase := -1
	if Input.is_action_just_pressed(&"move_left"):
		phase = 0
	elif Input.is_action_just_pressed(&"move_right"):
		phase = 1
	if phase == -1 or phase == _phase:
		return
	_phase = phase
	NetManager.send_match_input({"pull": phase})


## The knot glows brighter for a beat after each pull, easing back to rest.
func _decay_knot_flare() -> void:
	if _marker_material == null:
		return
	var flaring := _now() < _knot_flare_until
	_marker_material.emission_energy_multiplier = 2.6 if flaring else 0.9


func _arena_half() -> float:
	return TugOfWar.WIN_OFFSET + 4.0


func _setup_3d() -> void:
	var rope_mesh := BoxMesh.new()
	rope_mesh.size = Vector3(TugOfWar.WIN_OFFSET * 2.0 + ROPE_EXTRA, ROPE_THICKNESS, ROPE_THICKNESS)
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color = ROPE_COLOR
	rope_mesh.material = rope_material
	var rope_node := MeshInstance3D.new()
	rope_node.name = "Rope"
	rope_node.mesh = rope_mesh
	rope_node.position = Vector3(0.0, ROPE_HEIGHT, 0.0)
	arena.add_child(rope_node)

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.45
	marker_mesh.height = 0.9
	_marker_material = StandardMaterial3D.new()
	_marker_material.albedo_color = MARKER_COLOR
	_marker_material.emission_enabled = true
	_marker_material.emission = MARKER_COLOR
	_marker_material.emission_energy_multiplier = 0.9
	var marker_material := _marker_material
	marker_mesh.material = marker_material
	_marker = MeshInstance3D.new()
	_marker.name = "Marker"
	_marker.mesh = marker_mesh
	_marker.position = Vector3(0.0, ROPE_HEIGHT, 0.0)
	arena.add_child(_marker)
	# A pole above the knot so the rope's center reads at camera distance.
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.08, 1.6, 0.08)
	pole_mesh.material = marker_material
	var pole := MeshInstance3D.new()
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 1.1, 0.0)
	_marker.add_child(pole)

	for side: float in [-1.0, 1.0]:
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.4, 0.04, 8.0)
		var line_material := StandardMaterial3D.new()
		line_material.albedo_color = LINE_COLOR
		line_material.emission_enabled = true
		line_material.emission = LINE_COLOR
		line_material.emission_energy_multiplier = 0.5
		line_mesh.material = line_material
		var line := MeshInstance3D.new()
		line.name = "WinLineLeft" if side < 0.0 else "WinLineRight"
		line.mesh = line_mesh
		line.position = Vector3(side * TugOfWar.WIN_OFFSET, 0.03, 0.0)
		arena.add_child(line)
		# Translucent team-colored floor halves: each side visibly belongs to
		# the team standing on it (#215).
		var tint_mesh := PlaneMesh.new()
		var half := _arena_half()
		tint_mesh.size = Vector2(half, half * 2.0)
		var tint_material := StandardMaterial3D.new()
		tint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var tint_color := TEAM_A_COLOR if side < 0.0 else TEAM_B_COLOR
		tint_color.a = SIDE_TINT_ALPHA
		tint_material.albedo_color = tint_color
		tint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tint_mesh.material = tint_material
		var tint := MeshInstance3D.new()
		tint.name = "SideTintA" if side < 0.0 else "SideTintB"
		tint.mesh = tint_mesh
		tint.position = Vector3(side * half / 2.0, 0.02, 0.0)
		arena.add_child(tint)

	_hud = Control.new()
	_hud.name = "TugHud"
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)


func _render_3d(game: Dictionary) -> void:
	rope = float(game.get("rope", 0.0))
	win_offset = float(game.get("win_offset", TugOfWar.WIN_OFFSET))
	team_a = game.get("team_a", [])
	team_b = game.get("team_b", [])
	_fire_pull_fx()
	_marker.position.x = rope
	_update_teams()
	_last_rope = rope
	_hud.queue_redraw()


## Juice the rope's motion (#314): each snapshot the rope moved is a pull —
## flare the knot and scuff the ground under the team that gained. A rope at
## the line throws the win burst once.
func _fire_pull_fx() -> void:
	var delta := rope - _last_rope
	if absf(delta) >= PULL_EPSILON:
		_knot_flare_until = _now() + KNOT_FLARE_SEC
		# Rope moving -x means team A gained ground (they pull toward -x).
		_scuff_dust(-1.0 if delta < 0.0 else 1.0)
	if not _win_fired and absf(rope) >= win_offset - 0.001 and not (team_a + team_b).is_empty():
		_win_fired = true
		play_sfx(&"round_win")
		request_shake(10.0)
		_win_burst(-1.0 if rope < 0.0 else 1.0)


## A low puff of dust kicked up under the leading edge of the gaining team.
func _scuff_dust(side: float) -> void:
	var base := Vector2(rope + side * 1.6, TEAM_ROW_Z * side)
	for i in 3:
		var mesh := SphereMesh.new()
		mesh.radius = 0.26
		mesh.height = 0.52
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.72, 0.64, 0.52, 0.75)
		mesh.material = material
		var puff := MeshInstance3D.new()
		puff.mesh = mesh
		puff.position = to_arena(base + Vector2((i - 1) * 0.5, 0.0), 0.2)
		arena.add_child(puff)
		var tween := puff.create_tween()
		tween.set_parallel(true)
		tween.tween_property(puff, "position:y", 0.9, SCUFF_SEC)
		tween.tween_property(puff, "scale", Vector3.ONE * 2.0, SCUFF_SEC)
		tween.tween_property(material, "albedo_color:a", 0.0, SCUFF_SEC)
		tween.chain().tween_callback(puff.queue_free)


## Streamers erupt from the knot at the moment it's dragged over the line —
## the focal point everyone is watching — in the winning team's color.
func _win_burst(side: float) -> void:
	var origin := Vector3(side * win_offset, ROPE_HEIGHT + 0.5, 0.0)
	var color := TEAM_A_COLOR if side < 0.0 else TEAM_B_COLOR
	# A big expanding shockwave ring on the ground at the knot — the reliably
	# readable centerpiece of the win, in the winner's color.
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 0.9
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = color
	ring_mesh.material = ring_material
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.position = Vector3(side * win_offset, 0.1, 0.0)
	arena.add_child(ring)
	var ring_tween := ring.create_tween()
	ring_tween.set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector3(5.0, 1.0, 5.0), WIN_BURST_SEC)
	ring_tween.tween_property(ring_material, "albedo_color:a", 0.0, WIN_BURST_SEC)
	ring_tween.chain().tween_callback(ring.queue_free)
	for i in WIN_STREAMERS:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.22, 0.22, 0.7)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color if i % 2 == 0 else MARKER_COLOR
		mesh.material = material
		var streamer := MeshInstance3D.new()
		streamer.mesh = mesh
		streamer.position = origin
		arena.add_child(streamer)
		var angle := TAU * i / WIN_STREAMERS
		var reach := Vector3(cos(angle) * 3.0, 4.2, sin(angle) * 3.0)
		var tween := streamer.create_tween()
		tween.set_parallel(true)
		tween.tween_property(streamer, "position", origin + reach, WIN_BURST_SEC).set_trans(
			Tween.TRANS_CUBIC
		)
		tween.tween_property(streamer, "rotation", Vector3(angle * 2.0, angle, 0.0), WIN_BURST_SEC)
		tween.tween_property(material, "albedo_color:a", 0.0, WIN_BURST_SEC).set_delay(
			WIN_BURST_SEC * 0.4
		)
		tween.chain().tween_callback(streamer.queue_free)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## HUD tug bar (#215): rope progress between the two win lines with
## team-colored ends and a YOU chip on the local player's side — the arena
## alone never told you which team you were on or who was winning.
func _draw_hud() -> void:
	if team_a.is_empty() and team_b.is_empty():
		return
	var left := (_hud.size.x - BAR_WIDTH) / 2.0
	var bar := Rect2(left, BAR_TOP, BAR_WIDTH, BAR_HEIGHT)
	_hud.draw_rect(bar.grow(2.0), Color(0.0, 0.0, 0.0, 0.55))
	var cap_width := 26.0
	_hud.draw_rect(Rect2(bar.position, Vector2(cap_width, BAR_HEIGHT)), TEAM_A_COLOR)
	_hud.draw_rect(
		Rect2(bar.position + Vector2(BAR_WIDTH - cap_width, 0.0), Vector2(cap_width, BAR_HEIGHT)),
		TEAM_B_COLOR
	)
	var track := Rect2(
		bar.position + Vector2(cap_width, 0.0), Vector2(BAR_WIDTH - cap_width * 2.0, BAR_HEIGHT)
	)
	_hud.draw_rect(track, Color(0.25, 0.25, 0.28))
	var center_x := track.position.x + track.size.x / 2.0
	_hud.draw_line(
		Vector2(center_x, bar.position.y - 3.0),
		Vector2(center_x, bar.end.y + 3.0),
		Color(1.0, 1.0, 1.0, 0.5),
		2.0
	)
	var ratio := clampf(rope / win_offset, -1.0, 1.0)
	var knot_x := center_x + ratio * (track.size.x / 2.0)
	var urgency := absf(ratio)
	var knot_color := MARKER_COLOR.lerp(LINE_COLOR, maxf(urgency - 0.6, 0.0) / 0.4)
	_hud.draw_circle(Vector2(knot_x, bar.position.y + BAR_HEIGHT / 2.0), 9.0, knot_color)
	var my_side := -1.0 if my_slot in team_a else (1.0 if my_slot in team_b else 0.0)
	if my_side != 0.0:
		var you_x := bar.position.x - 44.0 if my_side < 0.0 else bar.end.x + 8.0
		_hud.draw_string(
			ThemeDB.fallback_font,
			Vector2(you_x, bar.position.y + BAR_HEIGHT - 1.0),
			"YOU",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			15,
			TEAM_A_COLOR if my_side < 0.0 else TEAM_B_COLOR
		)


func _update_teams() -> void:
	# Team A pulls toward -x and stands on the -x side; B mirrors.
	_place_team(team_a, -1.0)
	_place_team(team_b, 1.0)


func _place_team(team: Array, side: float) -> void:
	var moving := absf(rope - _last_rope) > 0.001
	for i in team.size():
		var slot: int = team[i]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var x := rope + side * (2.0 + i * TEAMMATE_SPACING)
		update_rig(slot, Vector2(x, TEAM_ROW_Z * side))
		# Everyone faces the rope's center line, leaning into the pull.
		rig.rotation.y = atan2(-side, 0.0)
		var desired: StringName = &"run" if moving else &"idle"
		if rig.current_action() != desired:
			rig.play(desired)
