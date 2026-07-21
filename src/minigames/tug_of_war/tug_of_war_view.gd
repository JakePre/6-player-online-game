extends MinigameView3D
## Tug of War client view (M8-09): renders the replicated tug in the shared
## 2.5D iso-arena (M8-01, MinigameView3D) — the rope as a stretched bar with
## a marker knot tracking the replicated offset, teams lined up on their
## sides as CharacterRigs leaning into the pull. Presentation-tier swap only:
## state storage and the alternating pull input are unchanged from the 2D
## pass (M4-10).
##
## GFX enhancements (#1164): sand-packed floor, CylinderMesh rope, team flags,
## footprint decals, mud splash, rim props, and a desert struggle-pit mood.

const ROPE_COLOR := Color(0.85, 0.65, 0.35)
const MARKER_COLOR := Color(1.0, 0.9, 0.4)
const LINE_COLOR := Color(0.9, 0.25, 0.25)
const ROPE_HEIGHT := 0.9
const ROPE_THICKNESS := 0.3
## Rope world length is a little longer than the two win offsets.
const ROPE_EXTRA := 4.0
## Where teams stand relative to the rope line. #930: nudged out from 1.6 so
## the front rank doesn't crowd the knot marker at the iso camera angle.
const TEAM_ROW_Z := 2.3
const TEAMMATE_SPACING := 1.4
## Big teams (M15-07): a single file of 12 pullers would stretch past the win
## lines, so files cap at this many and spill into parallel files further
## from the rope, FILE_GAP apart.
const MAX_PER_FILE := 6
const FILE_GAP := 1.2
## Team identity (#215): side tints in the arena and on the HUD bar. Team A
## owns -x, team B +x.
const TEAM_A_COLOR := Color(0.35, 0.72, 1.0)
const TEAM_B_COLOR := Color(1.0, 0.42, 0.1)
## #930: the #813 grass floor washed the tints out — blue-over-grass read
## teal, orange-over-grass read yellow-green. Re-punched from 0.24 so the
## team color dominates the blend instead of mixing evenly with the green.
const SIDE_TINT_ALPHA := 0.55
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

# --- GFX pass (#1164) ---------------------------------------------------------

## Sand-packed floor texture (IMG-055): tiled over the arena.
const SAND_TEXTURE := preload("res://assets/generated/textures/sand-packed.png")
const FLOOR_TEXTURE_TILES := 6.0
## Rope: CylinderMesh radius
const ROPE_RADIUS := 0.15
## Flag pole dimensions.
const FLAG_POLE_H := 2.5
const FLAG_POLE_RADIUS := 0.05
const FLAG_Z_OFFSET := 2.0  # behind the team row
## Kenney flag GLB for team flags (#1164).
const FLAG_SCENE := preload("res://assets/environment/kenney_platformer_kit/flag.glb")
## Footprint: dark ellipse on the sand, fading over time.
const FOOTPRINT_W := 0.3
const FOOTPRINT_D := 0.18
const FOOTPRINT_FADE_SEC := 4.0
const FOOTPRINT_MAX := 60
## Mud splash: brown burst particles during intense pulls.
const MUD_BURST_COUNT := 6
const MUD_BURST_SPEED := 1.5
## Rim props: desert struggle-pit scenery around the perimeter.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
	preload("res://assets/environment/kenney_platformer_kit/rocks.glb"),
	preload("res://assets/environment/kenney_platformer_kit/stones.glb"),
	preload("res://assets/environment/kenney_platformer_kit/tree-pine-small.glb"),
	preload("res://assets/environment/kenney_platformer_kit/grass.glb"),
]
const RIM_PROP_COUNT := 16
const RIM_PROP_SEED := 0x1164

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

# --- GFX state (#1164) --------------------------------------------------------

## Footprint pool: pooled ellipse decals, their placement times, and positions.
var _footprint_pool: Array[MeshInstance3D] = []
var _footprint_times: Array[float] = []
var _footprint_positions: Array[Vector3] = []
## Team flag nodes (flag.glb on a pole).
var _flags: Array[Node3D] = []


## Polled (not event-driven): stick axis motion doesn't deliver discrete
## pressed events reliably, which left gamepads unable to pull at all (#136).
## is_action_just_pressed unifies keys, d-pad, and stick threshold crossings.
func _process(_delta: float) -> void:
	_decay_knot_flare()
	_decay_footprints(_delta)
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


## Sand-packed floor (#1164): PlaneMesh with IMG-055 sand-packed.png replacing the
## grass block, tiled for a desert struggle-pit feel.
func _build_floor() -> void:
	var half := _arena_half()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(half * 2.0, half * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = SAND_TEXTURE
	material.albedo_color = Color(0.95, 0.88, 0.72)
	material.uv1_scale = Vector3(FLOOR_TEXTURE_TILES, FLOOR_TEXTURE_TILES, 1.0)
	material.metallic = 0.0
	material.roughness = 1.0
	mesh.material = material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "SandFloor"
	floor_node.mesh = mesh
	floor_node.position.y = -0.01
	arena.add_child(floor_node)


## Warm desert struggle-pit mood (#1164).
func _mood() -> Color:
	return Color(0.22, 0.16, 0.08).lerp(Color(0.45, 0.35, 0.18), 0.25)


func _arena_half() -> float:
	return TugOfWar.WIN_OFFSET + 4.0


## Replace the flat BoxMesh rope with a CylinderMesh (#1164): teams stand on
## either side of the stretched rope, which is a long thin cylinder lying
## along the X axis.
func _setup_3d() -> void:
	# CylinderMesh rope (#1164): the default CylinderMesh points up (Y); rotate
	# 90 degrees around Z to lie along the X axis.
	var rope_mesh := CylinderMesh.new()
	rope_mesh.top_radius = ROPE_RADIUS
	rope_mesh.bottom_radius = ROPE_RADIUS
	rope_mesh.height = TugOfWar.WIN_OFFSET * 2.0 + ROPE_EXTRA
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color = ROPE_COLOR
	rope_material.metallic = 0.2
	rope_material.roughness = 0.7
	rope_mesh.material = rope_material
	var rope_node := MeshInstance3D.new()
	rope_node.name = "Rope"
	rope_node.mesh = rope_mesh
	rope_node.position = Vector3(0.0, ROPE_HEIGHT, 0.0)
	rope_node.rotation.z = PI / 2.0
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

	# Team flags (#1164): Kenney flag.glb on a pole behind each team line.
	_build_team_flags()

	# Rim props (#1164): desert scenery around the perimeter.
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)

	_hud = Control.new()
	_hud.name = "TugHud"
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)


## Flags on poles behind each team line (#1164): the Kenney flag.glb in the
## team's color, mounted on a tall pole.
func _build_team_flags() -> void:
	for team_index: int in 2:
		var side := -1.0 if team_index == 0 else 1.0
		var team_color := TEAM_A_COLOR if team_index == 0 else TEAM_B_COLOR
		var flag_group := Node3D.new()
		flag_group.name = "FlagGroup%d" % team_index

		# Pole: tall thin CylinderMesh
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = FLAG_POLE_RADIUS
		pole_mesh.bottom_radius = FLAG_POLE_RADIUS
		pole_mesh.height = FLAG_POLE_H
		var pole_material := StandardMaterial3D.new()
		pole_material.albedo_color = Color(0.6, 0.55, 0.45)
		pole_material.metallic = 0.1
		pole_material.roughness = 0.8
		pole_mesh.material = pole_material
		var pole := MeshInstance3D.new()
		pole.name = "FlagPole%d" % team_index
		pole.mesh = pole_mesh
		pole.position = Vector3(side * 2.5, FLAG_POLE_H / 2.0, side * (TEAM_ROW_Z + FLAG_Z_OFFSET))
		flag_group.add_child(pole)

		# Flag: Kenney flag.glb, rotated to face the arena center.
		var flag := FLAG_SCENE.instantiate() as Node3D
		if flag != null:
			flag.name = "TeamFlag%d" % team_index
			# Tint the flag material to the team color.
			for found in flag.find_children("*", "MeshInstance3D", true, false):
				var mesh_node := found as MeshInstance3D
				for surface in mesh_node.mesh.get_surface_count():
					var mat := mesh_node.get_active_material(surface)
					if mat is StandardMaterial3D:
						var tinted: StandardMaterial3D = mat.duplicate()
						tinted.albedo_color = team_color
						tinted.emission_enabled = true
						tinted.emission = team_color
						tinted.emission_energy_multiplier = 0.3
						mesh_node.set_surface_override_material(surface, tinted)
			flag.position = Vector3(
				side * 2.5, FLAG_POLE_H - 0.3, side * (TEAM_ROW_Z + FLAG_Z_OFFSET)
			)
			flag.rotation.y = PI / 2.0 if side < 0.0 else -PI / 2.0
			flag_group.add_child(flag)
		arena.add_child(flag_group)
		_flags.append(flag_group)


func _render_3d(game: Dictionary) -> void:
	rope = float(game.get("rope", 0.0))
	win_offset = float(game.get("win_offset", TugOfWar.WIN_OFFSET))
	team_a = game.get("team_a", [])
	team_b = game.get("team_b", [])
	_fire_pull_fx()
	_marker.position.x = rope
	_update_teams()
	_accumulate_footprints()
	_last_rope = rope
	_hud.queue_redraw()


## Juice the rope's motion (#314): each snapshot the rope moved is a pull —
## flare the knot and scuff the ground under the team that gained. A rope at
## the line throws the win burst once. Also kick mud (#1164) during pulls.
func _fire_pull_fx() -> void:
	var delta := rope - _last_rope
	if absf(delta) >= PULL_EPSILON:
		_knot_flare_until = _now() + KNOT_FLARE_SEC
		# Rope moving -x means team A gained ground (they pull toward -x).
		var side := -1.0 if delta < 0.0 else 1.0
		_scuff_dust(side)
		_mud_splash(side)
	if not _win_fired and absf(rope) >= win_offset - 0.001 and not (team_a + team_b).is_empty():
		_win_fired = true
		play_sfx(&"bell")
		request_shake(10.0)
		_win_burst(-1.0 if rope < 0.0 else 1.0)


## A low puff of dust kicked up under the leading edge of the gaining team.
func _scuff_dust(side: float) -> void:
	if ArenaFX.reduced_motion:
		return
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


## Brown mud splash burst at the leading edge of the gaining team (#1164),
## complementing the scuff dust with heavier wet-ground particles.
func _mud_splash(side: float) -> void:
	if ArenaFX.reduced_motion:
		return
	var base := Vector3(rope + side * 1.6, 0.15, side * TEAM_ROW_Z)
	for i in MUD_BURST_COUNT:
		var mesh := SphereMesh.new()
		mesh.radius = 0.1
		mesh.height = 0.2
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.55, 0.35, 0.2, 0.8)
		mesh.material = material
		var blob := MeshInstance3D.new()
		blob.mesh = mesh
		blob.position = base + Vector3((i - MUD_BURST_COUNT / 2) * 0.3, 0.0, 0.0)
		arena.add_child(blob)
		var angle := TAU * float(i) / float(MUD_BURST_COUNT) + (PI if side < 0.0 else 0.0)
		var target := (
			base + Vector3(cos(angle) * MUD_BURST_SPEED, 0.8, sin(angle) * MUD_BURST_SPEED * 0.5)
		)
		var tween := blob.create_tween()
		tween.set_parallel(true)
		tween.tween_property(blob, "position", target, 0.35).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(blob, "scale", Vector3.ZERO, 0.35)
		tween.tween_property(material, "albedo_color:a", 0.0, 0.35).set_delay(0.15)
		tween.chain().tween_callback(blob.queue_free)


## Streamers erupt from the knot at the moment it's dragged over the line —
## the focal point everyone is watching — in the winning team's color.
func _win_burst(side: float) -> void:
	if ArenaFX.reduced_motion:
		return
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
	# Big teams wrap into parallel files stepping away from the rope (M15-07);
	# a team of up to MAX_PER_FILE keeps the classic single file.
	var offsets := LaneLayout.file_positions(team.size(), TEAMMATE_SPACING, FILE_GAP, MAX_PER_FILE)
	for i in team.size():
		var slot: int = team[i]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var x := rope + side * (2.0 + offsets[i].x)
		update_rig(slot, Vector2(x, side * (TEAM_ROW_Z + offsets[i].y)))
		# Everyone faces the rope's center line, leaning into the pull.
		rig.rotation.y = atan2(-side, 0.0)
		var desired: StringName = &"run" if moving else &"idle"
		if rig.current_action() != desired:
			rig.play(desired)


# --- Footprint decals (#1164) -------------------------------------------------


## Accumulate dark ellipse decals at each team member's position. New
## footprints are added each render; old ones fade out over FOOTPRINT_FADE_SEC.
func _accumulate_footprints() -> void:
	if ArenaFX.reduced_motion:
		return
	var now := _now()
	var all_slots: Array = team_a + team_b
	var added := false
	for slot: int in all_slots:
		var rig := rig_for_slot(slot)
		if rig == null or not rig.visible:
			continue
		var pos := rig.position
		pos.y = 0.02
		# Only add a footprint if the rig moved (avoid spamming on idle).
		var is_new := true
		for existing: Vector3 in _footprint_positions:
			if pos.distance_to(existing) < 0.3:
				is_new = false
				break
		if is_new:
			_footprint_positions.append(pos)
			_footprint_times.append(now)
			added = true

	# Trim expired footprints past FOOTPRINT_MAX.
	if added and _footprint_times.size() > FOOTPRINT_MAX:
		var excess := _footprint_times.size() - FOOTPRINT_MAX
		for _j in excess:
			_footprint_times.pop_front()
			_footprint_positions.pop_front()

	# Sync the pool to the current footprint count.
	var print_count := mini(_footprint_positions.size(), FOOTPRINT_MAX)
	sync_pool(_footprint_pool, print_count, _make_footprint, _place_footprint)


## Build one footprint decal: a dark ellipse lying flat on the ground.
func _make_footprint() -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(FOOTPRINT_W, FOOTPRINT_D)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.35, 0.28, 0.18, 0.4)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.rotation.x = -PI / 2.0  # lie flat on ground
	return node


## Position a footprint decal at the stored position for this index.
func _place_footprint(node: MeshInstance3D, index: int) -> void:
	if index < 0 or index >= _footprint_positions.size():
		node.visible = false
		return
	var pos: Vector3 = _footprint_positions[index]
	node.position = pos
	# Random yaw so footprints don't all face the same direction.
	node.rotation.y = float(index) * 1.7
	node.visible = true


## Fade footprints over time as they age past the fade threshold.
func _decay_footprints(_delta: float) -> void:
	var now := _now()
	for i in _footprint_pool.size():
		var node: MeshInstance3D = _footprint_pool[i]
		if not node.visible:
			continue
		if i < _footprint_times.size():
			var age := now - _footprint_times[i]
			if age >= FOOTPRINT_FADE_SEC:
				node.visible = false
			else:
				var alpha := 1.0 - (age / FOOTPRINT_FADE_SEC)
				var mat := node.mesh.surface_get_material(0) as StandardMaterial3D
				if mat != null:
					mat.albedo_color.a = alpha * 0.4
