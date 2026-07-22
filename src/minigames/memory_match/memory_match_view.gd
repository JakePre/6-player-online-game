extends MinigameView3D
## Memory Match client view (M10-05): a thin-ice-style tile grid over a dark
## pit. Safe tiles light up during SHOW; in the dark everything looks the
## same — that's the game. Losers drop with the check, with a shake. The grid
## replaces the default floor (the pattern IS the floor).

## Declarative button input (#947): shove a neighbor off their tile.
const INPUT_ACTIONS := {&"action_primary": "shove"}
const TILE_SAFE_COLOR := Color(0.35, 0.85, 0.5)
const TILE_DARK_COLOR := Color(0.28, 0.3, 0.38)
const PIT_COLOR := Color(0.04, 0.04, 0.07)
const TILE_THICKNESS := 0.3
const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
## Objective-naming banners (#586): the old "REMEMBER THE PATTERN!" read as a
## maze; players weren't sure the green tiles were where to *stand*.
const SHOW_TEXT := "STAND ON A GREEN SAFE TILE — MEMORIZE IT!"
const DARK_TEXT := "GET TO A SAFE TILE — NOW!"
## Safe tiles pulse between these emission energies during SHOW so they read as
## the focal "go here", not scenery.
const SAFE_GLOW_MIN := 0.5
const SAFE_GLOW_MAX := 1.4
const SAFE_PULSE_HZ := 1.5

## Shove feedback (#784): a play-once swing protected from update_rig for this
## long, the impact SFX, and the cooldown ring's color (the #792/#808 idiom).
const ACT_HOLD_SEC := 0.4
const COOLDOWN_RING_COLOR := Color(0.95, 0.7, 0.35)
## Crack + fall (#784, scope items 1–2): the tile a loser stood on discolors and
## drops away, and the loser's rig falls with it into the pit rather than just
## greying in place. FALL_HIDE_Y is well below the pit plane (y=-0.45).
const CRACKED_COLOR := Color(0.5, 0.28, 0.24)
const FALL_SPEED := 7.0
const TILE_DROP_SPEED := 5.0
const FALL_HIDE_Y := -6.0
const TILE_HOME_Y := -TILE_THICKNESS / 2.0
## #1144 GFX: a safe-tile icon, rising pit mist, a pit-edge border, a dark/pit
## mood + floor tint, and a blackout puff on the SHOW -> DARK transition.
## The icon is a drawn 4-point sparkle (crossed bars), not a Unicode glyph —
## a font's symbol coverage isn't guaranteed across platforms/renderers, so
## this follows the same "drawn primitive over font glyph" rule as
## loadout_duel's per-kind glyphs.
const SAFE_ICON_COLOR := Color(0.1, 0.35, 0.18)
const SAFE_ICON_BAR_SIZE := Vector3(0.5, 0.03, 0.12)
const PIT_MIST_COLOR := Color(0.4, 0.55, 0.7, 0.35)
const PIT_BORDER_COLOR := Color(0.5, 0.45, 0.6, 0.8)
const PIT_BORDER_THICKNESS := 0.12
const BLACKOUT_PUFF_COLOR := Color(0.08, 0.08, 0.12)

## Latest replicated state, straight from MemoryMatch.get_snapshot().
var players := {}
var phase: int = MemoryMatch.Phase.SHOW
var safe_tiles: Array = []
var fallen: Array = []
var round_number := 0

var _tile_nodes: Array[MeshInstance3D] = []
## #1144 GFX: a per-tile star icon, shown only while that tile is lit safe.
var _tile_icons: Array[Node3D] = []
var _safe_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _cracked_material: StandardMaterial3D
var _phase_label: Label
var _downed := {}
# Previous phase for reveal-wave detection (M13-12); -1 = unseeded.
var _phase_seen := -1
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _fallen_seen := -1
## Shove state (#784): play-once swing edge (#945); the swing-hold now lives on
## the rig (#942). Plus the pooled cooldown rings.
var _act_edges := EdgeTracker.new()
var _hit_edges := EdgeTracker.new()
var _rings := {}
## Fall animation state (#784): downed slots still sinking, and tile indices
## dropping into the pit (reset when the floor reforms each round).
var _falling := {}
var _dropping := {}
## #1144 GFX: the last non-empty safe_tiles seen — the sim blanks safe_tiles
## to [] on the wire during DARK (#586, no peeking), so the blackout puff
## needs the SHOW snapshot's set, not the current (empty) one.
var _last_safe_tiles: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Pulse the safe tiles during SHOW so the green reads as "go here" rather than
## a static maze pattern (#586). Phase comes from wall time so the per-snapshot
## material reuse never resets it.
func _process(delta: float) -> void:
	_advance_falls(delta)
	if phase != MemoryMatch.Phase.SHOW or _safe_material == null:
		return
	var t := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * SAFE_PULSE_HZ)
	_safe_material.emission_energy_multiplier = lerpf(SAFE_GLOW_MIN, SAFE_GLOW_MAX, t)


## Sink downed rigs and their dropped tiles into the pit (#784). Rigs hide once
## below the pit; dropped tiles stay sunk until the floor reforms next round.
func _advance_falls(delta: float) -> void:
	for slot: int in _falling.keys():
		var rig := rig_for_slot(slot)
		if rig == null:
			_falling.erase(slot)
			continue
		rig.position.y -= FALL_SPEED * delta
		if rig.position.y <= FALL_HIDE_Y:
			rig.visible = false
			_falling.erase(slot)
	for index: int in _dropping.keys():
		var node: MeshInstance3D = _tile_nodes[index]
		node.position.y -= TILE_DROP_SPEED * delta
		if node.position.y <= FALL_HIDE_Y:
			_dropping.erase(index)


func _arena_half() -> float:
	return MemoryMatch.HALF_EXTENT


## Dark/pit tint (#1144) — this game builds its own floor (below), so this
## only feeds the derived _mood() default; the explicit override right after
## makes the dark theme definite rather than implicit.
func _floor_tint() -> Color:
	return Color(0.5, 0.55, 0.7)


## A deliberately dark, void-like mood for the pit theme (#1144).
func _mood() -> Color:
	return Color(0.08, 0.08, 0.14)


## The tile grid IS the floor: a dark pit plane below, one box per tile.
func _build_floor() -> void:
	var pit_mesh := PlaneMesh.new()
	pit_mesh.size = Vector2.ONE * MemoryMatch.HALF_EXTENT * 2.5
	var pit_material := StandardMaterial3D.new()
	pit_material.albedo_color = PIT_COLOR
	pit_mesh.material = pit_material
	var pit := MeshInstance3D.new()
	pit.name = "Pit"
	pit.mesh = pit_mesh
	pit.position.y = -0.45
	arena.add_child(pit)
	_build_pit_border(pit.position.y)
	_build_pit_mist(pit.position.y)

	_safe_material = StandardMaterial3D.new()
	_safe_material.albedo_color = TILE_SAFE_COLOR
	_safe_material.emission_enabled = true
	_safe_material.emission = TILE_SAFE_COLOR
	_safe_material.emission_energy_multiplier = 0.4
	_dark_material = StandardMaterial3D.new()
	_dark_material.albedo_color = TILE_DARK_COLOR
	_cracked_material = StandardMaterial3D.new()
	_cracked_material.albedo_color = CRACKED_COLOR
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(MemoryMatch.TILE_SIZE, TILE_THICKNESS, MemoryMatch.TILE_SIZE)

	for y in MemoryMatch.GRID_SIZE:
		for x in MemoryMatch.GRID_SIZE:
			var node := MeshInstance3D.new()
			node.name = "Tile_%d_%d" % [x, y]
			node.mesh = tile_mesh
			node.material_override = _dark_material
			node.position = Vector3(
				-MemoryMatch.HALF_EXTENT + (x + 0.5) * MemoryMatch.TILE_SIZE,
				-TILE_THICKNESS / 2.0,
				-MemoryMatch.HALF_EXTENT + (y + 0.5) * MemoryMatch.TILE_SIZE
			)
			arena.add_child(node)
			_tile_nodes.append(node)
			# Safe-tile icon (#1144): a sparkle that only shows while this
			# tile is lit safe, reinforcing "stand here" beyond just the color.
			var icon := _build_safe_icon()
			node.add_child(icon)
			_tile_icons.append(icon)


## A 4-point sparkle (two crossed bars) marking a safe tile (#1144) — a drawn
## primitive rather than a font glyph, so it renders identically regardless of
## the platform's font glyph coverage.
func _build_safe_icon() -> Node3D:
	var icon := Node3D.new()
	icon.name = "Icon"
	icon.position = Vector3(0.0, TILE_THICKNESS / 2.0 + 0.02, 0.0)
	icon.visible = false
	var material := StandardMaterial3D.new()
	material.albedo_color = SAFE_ICON_COLOR
	for angle_degrees in [0.0, 90.0]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = SAFE_ICON_BAR_SIZE
		box.material = material
		bar.mesh = box
		bar.rotation_degrees.y = angle_degrees
		icon.add_child(bar)
	return icon


## A TorusMesh ring around the pit's edge (#1144) — the tile grid reads as a
## contained arena, not an infinite void.
func _build_pit_border(pit_y: float) -> void:
	var border := MeshInstance3D.new()
	border.name = "PitBorder"
	var torus := TorusMesh.new()
	var radius := MemoryMatch.HALF_EXTENT * 1.25
	torus.inner_radius = radius - PIT_BORDER_THICKNESS
	torus.outer_radius = radius + PIT_BORDER_THICKNESS
	var material := StandardMaterial3D.new()
	material.albedo_color = PIT_BORDER_COLOR
	torus.material = material
	border.mesh = torus
	border.position.y = pit_y
	arena.add_child(border)


## Gentle rising mist from the pit (#1144) — a continuous, low-key ambient
## particle system (not a one-shot ArenaFX effect) giving the void depth.
func _build_pit_mist(pit_y: float) -> void:
	var mist := CPUParticles3D.new()
	mist.name = "PitMist"
	mist.amount = 24
	mist.lifetime = 4.0
	mist.emitting = not ArenaFX.reduced_motion
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3.ONE * MemoryMatch.HALF_EXTENT
	mist.direction = Vector3.UP
	mist.spread = 15.0
	mist.gravity = Vector3(0.0, 0.35, 0.0)
	mist.initial_velocity_min = 0.15
	mist.initial_velocity_max = 0.35
	mist.scale_amount_min = 3.0
	mist.scale_amount_max = 5.0
	mist.color = PIT_MIST_COLOR
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * 0.5
	var mist_material := StandardMaterial3D.new()
	mist_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Without this the mesh renders in its own opaque white albedo — the
	# particle system's per-instance `color` (set below) only tints the mesh
	# once vertex color is read as albedo.
	mist_material.vertex_color_use_as_albedo = true
	mesh.material = mist_material
	mist.mesh = mesh
	mist.position.y = pit_y
	arena.add_child(mist)


func _setup_3d() -> void:
	# make_status_label's outline already keeps this legible over both the
	# bright-green and dark floor phases (#586) — the old plain label washed
	# out against the tiles.
	_phase_label = make_status_label(&"PhaseLabel")


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	phase = int(game.get("phase", MemoryMatch.Phase.SHOW))
	safe_tiles = game.get("safe_tiles", [])
	if not safe_tiles.is_empty():
		_last_safe_tiles = safe_tiles.duplicate()
	fallen = game.get("fallen", [])
	round_number = int(game.get("round", round_number))
	# The floor reforms for the survivors when a new round shows (#784) — any
	# tiles that dropped away last round lift back home before they re-light.
	if _phase_seen == MemoryMatch.Phase.DARK and phase == MemoryMatch.Phase.SHOW:
		_reform_tiles()
	_update_phase_label()
	_update_tiles()
	_update_players()
	_reveal_wave_fx()
	_shake_on_new_downs()


## Lift every dropped tile home and clear the drop set — the pit fills back in
## for the next round (#784). Materials are reset to dark; _update_tiles re-lights
## the new safe set this same render.
func _reform_tiles() -> void:
	_dropping.clear()
	for node: MeshInstance3D in _tile_nodes:
		node.position.y = TILE_HOME_Y
		node.material_override = _dark_material


## Banner names the objective, with round context — and during SHOW the safe
## count, so the player knows the memory load (#586). The count is only shown
## while the tiles are already visible, so it is not a dark-phase peek.
func _update_phase_label() -> void:
	var round_tag := "Round %d" % maxi(round_number + 1, 1)
	if phase == MemoryMatch.Phase.SHOW:
		_phase_label.text = "%s — %s  (%d safe)" % [round_tag, SHOW_TEXT, safe_tiles.size()]
	else:
		_phase_label.text = "%s — %s" % [round_tag, DARK_TEXT]


## The pattern landing gets a sparkle wave over the safe tiles (M13-12),
## fired on the DARK->SHOW transition only — never on the seeding snapshot.
func _reveal_wave_fx() -> void:
	if (
		_phase_seen == MemoryMatch.Phase.DARK
		and phase == MemoryMatch.Phase.SHOW
		and not safe_tiles.is_empty()
	):
		for index in safe_tiles:
			fx_sparkle(_tile_world(int(index)), TILE_SAFE_COLOR, 0.4)
	elif _phase_seen == MemoryMatch.Phase.SHOW and phase == MemoryMatch.Phase.DARK:
		# Signature cue (#728, docs/AUDIO_GUIDE.md — Tiles & ice): the lights
		# going out is the danger telegraph — go now.
		play_sfx(&"alarm")
		# Blackout transition (#1144): a dark puff where the safe tiles just
		# were, so the SHOW -> DARK flip reads as an event, not an instant cut.
		for index in _last_safe_tiles:
			fx_burst(_tile_world(int(index)), BLACKOUT_PUFF_COLOR, 0.4)
	_phase_seen = phase


func _tile_world(index: int) -> Vector2:
	var x := index % MemoryMatch.GRID_SIZE
	var y := int(floorf(float(index) / MemoryMatch.GRID_SIZE))
	return Vector2(
		-MemoryMatch.HALF_EXTENT + (x + 0.5) * MemoryMatch.TILE_SIZE,
		-MemoryMatch.HALF_EXTENT + (y + 0.5) * MemoryMatch.TILE_SIZE
	)


func _update_tiles() -> void:
	var lit := phase == MemoryMatch.Phase.SHOW
	for i in _tile_nodes.size():
		# A dropping tile keeps its cracked look and sunk position until it reforms.
		if _dropping.has(i):
			continue
		var is_safe_and_lit := lit and i in safe_tiles
		_tile_nodes[i].material_override = _safe_material if is_safe_and_lit else _dark_material
		# Safe-tile icon (#1144): only while that tile actually reads safe.
		_tile_icons[i].visible = is_safe_and_lit


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var pos := Vector2(float(state[MemoryMatch.PS_X]), float(state[MemoryMatch.PS_Y]))
		_play_shove(slot, state, rig)
		_play_shove_hit(slot, state)
		# While the shove swing plays, drive the rig by hand so update_rig's
		# walk/idle can't overwrite it (#808 idiom); otherwise move normally.
		if rig.is_pose_protected():
			rig.position = to_arena(pos)
		else:
			update_rig(slot, pos)
		_update_cooldown_ring(slot, state, rig)
	for group: Array in fallen:
		for slot: int in group:
			_down_rig(slot)


## Play the shove swing once, when the sim's monotonic counter ticks (#784) —
## a swing pose, the impact SFX, and a burst; guarded for the pre-shove wire
## shape so an [x, y]-only snapshot (older tests / rejoin) is a no-op.
func _play_shove(slot: int, state: Array, rig: CharacterRig) -> void:
	if state.size() <= MemoryMatch.PS_ACT_SEQ:
		return
	var seq := int(state[MemoryMatch.PS_ACT_SEQ])
	if not _act_edges.rose(slot, seq):
		return
	# The rig owns its own swing hold now (#942).
	rig.play_protected(&"attack", ACT_HOLD_SEC)
	play_sfx(&"bump")
	fx_burst(
		Vector2(float(state[MemoryMatch.PS_X]), float(state[MemoryMatch.PS_Y])),
		COOLDOWN_RING_COLOR,
		0.6
	)


## The shove's target flinches too (#1038) — the shover's own swing used to be
## the only reaction; the player actually knocked away had none.
func _play_shove_hit(slot: int, state: Array) -> void:
	if state.size() <= MemoryMatch.PS_SHOVE_HIT_SEQ:
		return
	if not _hit_edges.rose(slot, int(state[MemoryMatch.PS_SHOVE_HIT_SEQ])):
		return
	play_hit(slot)


## A flat ring under a player showing their shove cooldown (#792/#808): visible
## and shrinking while cooling, hidden the moment it's ready. Lazily built per
## rig and reused (rigs are pooled).
func _update_cooldown_ring(slot: int, state: Array, rig: CharacterRig) -> void:
	if state.size() <= MemoryMatch.PS_SHOVE_CD:
		return
	# PS_SHOVE_CD is raw seconds here — normalize to a 0..1 fraction for the
	# shared cooldown-ring chrome (#945).
	var fraction := float(state[MemoryMatch.PS_SHOVE_CD]) / MemoryMatch.SHOVE_COOLDOWN_SEC
	update_cooldown_ring(_rings, slot, rig, fraction, COOLDOWN_RING_COLOR)


func _down_rig(slot: int) -> void:
	if _downed.has(slot):
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	_downed[slot] = true
	rig.play(&"ko")
	rig.player_color = ELIMINATED_COLOR
	# The drop into the pit splashes (M13-12).
	fx_splash(Vector2(rig.position.x, rig.position.z))
	# The tile gives way and the loser falls with it (#784) instead of just
	# greying in place — the crack/fall the owner asked for.
	_drop_tile_under(rig)
	_falling[slot] = true


## Row-major tile index under a world position — mirrors MemoryMatch.tile_of on
## the arena's X/Z plane.
func tile_index_at(world: Vector3) -> int:
	var col := clampi(
		int(floorf((world.x + MemoryMatch.HALF_EXTENT) / MemoryMatch.TILE_SIZE)),
		0,
		MemoryMatch.GRID_SIZE - 1
	)
	var row := clampi(
		int(floorf((world.z + MemoryMatch.HALF_EXTENT) / MemoryMatch.TILE_SIZE)),
		0,
		MemoryMatch.GRID_SIZE - 1
	)
	return row * MemoryMatch.GRID_SIZE + col


## Crack + sink the tile the downed rig is standing on (#784). Idempotent per
## tile — two players sharing a tile only drop it once.
func _drop_tile_under(rig: CharacterRig) -> void:
	var index := tile_index_at(rig.position)
	if _dropping.has(index):
		return
	_dropping[index] = true
	_tile_nodes[index].material_override = _cracked_material


func _shake_on_new_downs() -> void:
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _fallen_seen >= 0 and fallen_count > _fallen_seen:
		request_shake(10.0)
		# The pit-fall + elimination cues, same pattern as thin_ice's #727 pilot.
		play_sfx(&"splash")
		play_sfx(&"ko")
	_fallen_seen = fallen_count
