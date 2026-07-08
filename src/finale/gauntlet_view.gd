extends MinigameView3D
## Finale Gauntlet client view (M8-12): renders the shrinking platform,
## telegraphed hazard discs, and players in the shared 2.5D iso-arena
## (M8-01). New build — the Gauntlet sim (M5-02) had server logic only.
## Renders Gauntlet.get_snapshot() untouched: {radius, shrink_in, players:
## {slot: [x, y, lives, respawn_left, swings, swing_seq, hit_seq]}, hazards:
## [[x, y, r, warn_left]], weapons: [[x, y]]} (#584 weapon fields) — indices
## named via Gauntlet.PS_*/HZ_*/WP_* (#708).

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

## Weapon pickups (#584): the floor axes and the in-hand model both use the
## Barbarian's CC0 2H_Axe mesh (already shipped); the grip offset mirrors the
## GLB's own 2H_Axe bone rest relative to the shared handslot.r bone.
const AXE_SOURCE_SCENE := "res://assets/characters/kaykit_adventurers/Barbarian.glb"
const AXE_MESH_NAME := "2H_Axe"
const AXE_BONE := "handslot.r"
const WEAPON_COLOR := Color(0.95, 0.78, 0.25)
const WEAPON_BOB_HEIGHT := 0.25
const WEAPON_SPIN_HZ := 0.5
## Floor axes hover this far above the platform (plus the bob).
const WEAPON_FLOAT_Y := 0.55
## How long a swing/stagger animation owns the rig before walk/idle resumes.
const REACTION_HOLD_SEC := 0.6

## Shrink telegraph (#583): the band the next shrink stage is about to shed
## lights up for Gauntlet.SHRINK_WARN_SEC before it actually shrinks, reddening
## as the countdown closes in. Steady under reduced motion; a slow pulse
## otherwise (M13 telegraph convention).
const SHRINK_TELEGRAPH_COLOR := Color(0.9, 0.2, 0.15)
const SHRINK_TELEGRAPH_MIN_ALPHA := 0.35
const SHRINK_TELEGRAPH_MAX_ALPHA := 0.85
const SHRINK_TELEGRAPH_PULSE_SEC := 0.6

## Finale chrome (M16-11): themed intro treatment, elimination/grudge callout
## banners, and a champion sequence — presentation-only, built on the M16-01
## design system and honouring ArenaFX.reduced_motion. Lives on its own
## CanvasLayer above the shared banner band.
const CHROME_LAYER := 6
const INTRO_HOLD_SEC := 2.2
const BANNER_HOLD_SEC := 1.7
const WINNER_HOLD_SEC := 4.5

## Latest replicated state, straight from Gauntlet.get_snapshot().
var radius := Gauntlet.START_RADIUS
var players := {}
var hazards: Array = []
var weapons: Array = []

var _platform: MeshInstance3D
var _platform_mesh: CylinderMesh
var _hazard_nodes: Array[MeshInstance3D] = []

var _last_radius := Gauntlet.START_RADIUS
var _last_hazard_keys := {}  # quantized "x,y" -> Vector2 world pos (detonation FX)
var _last_lives := {}  # slot -> lives (fall/KO burst)

## Weapon pickups (#584).
var _axe_mesh: Mesh
var _weapon_nodes: Array[MeshInstance3D] = []
var _last_weapon_keys := {}  # quantized "x,y" -> Vector2 (pickup flash)
var _last_swing_seq := {}  # slot -> seq (play the swing exactly once)
var _last_hit_seq := {}  # slot -> seq (hit reaction exactly once)
var _armed := {}  # slot -> swings left, mirrored for the nameplate + hand prop
var _axe_hint_shown := false
## slot -> ticks_msec until which a swing/stagger owns the rig's animation —
## the #587 _reaction_hold idiom, so update_rig's walk/idle can't stomp it.
var _reaction_hold := {}

## Shrink telegraph (#583).
var _shrink_in := Gauntlet.SHRINK_STAGE_SEC
var _shrink_telegraph: MeshInstance3D
var _shrink_telegraph_mesh: TorusMesh
var _shrink_telegraph_mat: StandardMaterial3D
var _shrink_base_alpha := 0.0

## Finale targeting (fixes the deferred "HUD targeting pass", #462). While
## alive, a sabotage token drops on the nearest living rival; once eliminated,
## the one grudge hazard aims via a cycle-selected target. The sim already
## validates both (token count / grudge availability), so this is view-only.
var _grudge_target := -1
var _grudge_spent := false
var _grudge_prompt: Label

## Finale chrome nodes (M16-11).
var _chrome: CanvasLayer
var _intro_box: VBoxContainer
var _intro_title: Label
var _intro_sub: Label
var _event_banner: PanelContainer
var _event_label: Label
var _intro_tween: Tween
var _event_tween: Tween
var _intro_done := false
var _winner_shown := false


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Pulses the shrink telegraph between snapshots so the warning reads as alive,
## not a static tint — suppressed under reduced motion (a steady tint instead).
## Floor axes spin and bob for the same reason (steady hover when reduced).
func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for node in _weapon_nodes:
		if ArenaFX.reduced_motion:
			continue
		node.rotation.y = TAU * t * WEAPON_SPIN_HZ
		node.position.y = PLATFORM_THICKNESS + WEAPON_FLOAT_Y + WEAPON_BOB_HEIGHT * sin(TAU * t)
	if _shrink_telegraph == null or not _shrink_telegraph.visible or ArenaFX.reduced_motion:
		return
	var phase := TAU * t / SHRINK_TELEGRAPH_PULSE_SEC
	var pulse := 0.75 + 0.25 * sin(phase)
	_shrink_telegraph_mat.albedo_color.a = _shrink_base_alpha * pulse


## Alive: action_primary swings the held axe (#584), action_secondary spends a
## sabotage token on the nearest living rival. Eliminated: aim the one grudge
## with move-left/right and strike with either action button. Parity-clean —
## one stick axis to aim, one button to fire.
func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	if _local_lives() > 0:
		if event.is_action_pressed(&"action_primary"):
			NetManager.send_match_input({"swing": true})
		elif event.is_action_pressed(&"action_secondary"):
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
	return [state[Gauntlet.PS_X], state[Gauntlet.PS_Y]]


func _nearest_living_rival() -> int:
	if not players.has(my_slot):
		return _first_living_rival()
	var mine: Array = players[my_slot]
	var origin := Vector2(float(mine[Gauntlet.PS_X]), float(mine[Gauntlet.PS_Y]))
	var best := -1
	var best_dist := INF
	for slot: int in _living_rivals():
		var state: Array = players[slot]
		var dist := origin.distance_to(
			Vector2(float(state[Gauntlet.PS_X]), float(state[Gauntlet.PS_Y]))
		)
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
		if int((players[slot] as Array)[Gauntlet.PS_LIVES]) > 0:
			rivals.append(slot)
	rivals.sort()
	return rivals


func _first_living_rival() -> int:
	var rivals := _living_rivals()
	return rivals[0] if not rivals.is_empty() else -1


func _local_lives() -> int:
	if not players.has(my_slot):
		return 1  # pre-snapshot: assume alive, show no grudge prompt
	return int((players[my_slot] as Array)[Gauntlet.PS_LIVES])


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
	NetManager.send_match_input({"grudge": [state[Gauntlet.PS_X], state[Gauntlet.PS_Y]]})
	_grudge_spent = true
	_show_event("GRUDGE!  → %s" % player_name(_grudge_target), PartyTheme.DANGER)
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

	_shrink_telegraph_mesh = TorusMesh.new()
	_shrink_telegraph_mesh.inner_radius = maxf(radius - 0.1, 0.05)
	_shrink_telegraph_mesh.outer_radius = radius
	_shrink_telegraph_mat = StandardMaterial3D.new()
	_shrink_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shrink_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shrink_telegraph_mat.albedo_color = SHRINK_TELEGRAPH_COLOR
	_shrink_telegraph_mat.emission_enabled = true
	_shrink_telegraph_mat.emission = SHRINK_TELEGRAPH_COLOR
	_shrink_telegraph_mesh.material = _shrink_telegraph_mat
	_shrink_telegraph = MeshInstance3D.new()
	_shrink_telegraph.name = "ShrinkTelegraph"
	_shrink_telegraph.mesh = _shrink_telegraph_mesh
	# No rotation: TorusMesh is already flat (its axis is Y). The old
	# rotation.x = PI/2 stood the ring UP — an arch over the stage (#693).
	_shrink_telegraph.position = Vector3(0.0, PLATFORM_THICKNESS + 0.03, 0.0)
	_shrink_telegraph.visible = false
	arena.add_child(_shrink_telegraph)

	# The axe model for floor pickups and hands (#584) is lifted straight out of
	# the shipped Barbarian GLB — no new asset, guaranteed to match the rig.
	var axe_source: Node = (load(AXE_SOURCE_SCENE) as PackedScene).instantiate()
	var axe_nodes := axe_source.find_children(AXE_MESH_NAME, "MeshInstance3D", true, false)
	if not axe_nodes.is_empty():
		_axe_mesh = (axe_nodes[0] as MeshInstance3D).mesh
	axe_source.free()

	_grudge_prompt = Label.new()
	_grudge_prompt.name = "GrudgePrompt"
	_grudge_prompt.theme_type_variation = PartyTheme.HEADER_VARIATION
	_grudge_prompt.add_theme_color_override(&"font_color", PartyTheme.ACCENT_BRIGHT)
	_grudge_prompt.add_theme_stylebox_override(&"normal", _chrome_panel(PartyTheme.DANGER))
	_grudge_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_grudge_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Grow upward off the bottom anchor, or the long "GRUDGE → name … aim /
	# strike" prompt runs downward off screen (#576).
	_grudge_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_grudge_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grudge_prompt.position.y = -70.0
	_grudge_prompt.visible = false
	add_child(_grudge_prompt)

	_build_chrome()


func _render_3d(game: Dictionary) -> void:
	radius = float(game.get("radius", Gauntlet.START_RADIUS))
	_shrink_in = float(game.get("shrink_in", Gauntlet.SHRINK_STAGE_SEC))
	players = game.get("players", {})
	hazards = game.get("hazards", [])
	# The Gauntlet intro treatment flashes once, the instant the finale starts
	# replicating (M16-11).
	if not _intro_done:
		_intro_done = true
		_flash_intro()
	_platform_mesh.top_radius = radius
	_platform_mesh.bottom_radius = radius
	# The platform shrinks in stages; each step sheds a rim, so crumble it away.
	if radius < _last_radius - 0.01:
		_crumble_ring(_last_radius)
	_last_radius = radius
	weapons = game.get("weapons", [])
	_update_players()
	_update_hazards()
	_update_weapons()
	_update_shrink_telegraph()
	_update_grudge_prompt()
	_check_winner()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var lives := int(state[Gauntlet.PS_LIVES])
		var prev_lives := int(_last_lives.get(slot, lives))
		# Fall/KO burst where a player was standing the instant they lose a life.
		if lives < prev_lives:
			fx_burst(
				Vector2(rig.position.x, rig.position.z), HAZARD_FX_COLOR, PLATFORM_THICKNESS + 0.5
			)
			# Losing the last life is a finale elimination — call it out (M16-11).
			if lives == 0:
				_show_event("%s ELIMINATED" % player_name(slot), PartyTheme.DANGER)
		_last_lives[slot] = lives
		var respawning := float(state[Gauntlet.PS_RESPAWN]) > 0.0
		rig.visible = lives > 0 and not respawning
		if not rig.visible:
			continue
		_update_weapon_state(slot, state, rig)
		if Time.get_ticks_msec() < int(_reaction_hold.get(slot, 0)):
			# A swing/stagger owns the rig (#587 idiom): move it, don't re-animate.
			rig.position = to_arena(
				Vector2(state[Gauntlet.PS_X], state[Gauntlet.PS_Y]), PLATFORM_THICKNESS
			)
		else:
			update_rig(slot, Vector2(state[Gauntlet.PS_X], state[Gauntlet.PS_Y]))
			rig.position.y = PLATFORM_THICKNESS
		rig.display_name = (
			"%s %s%s" % [player_name(slot), "♥".repeat(lives), "⚔".repeat(int(_armed.get(slot, 0)))]
		)


## Arms/disarms the rig's hand and fires the swing/hit reactions off the sim's
## monotonic counters (#584) — each plays exactly once no matter how snapshots
## are sampled, and a mid-match join seeds silently instead of replaying.
func _update_weapon_state(slot: int, state: Array, rig: CharacterRig) -> void:
	if state.size() < Gauntlet.PS_COUNT:
		return  # pre-#584 snapshot shape
	var swings := int(state[Gauntlet.PS_ARMED])
	var was_armed := int(_armed.get(slot, 0)) > 0
	_armed[slot] = swings
	if swings > 0 and not was_armed:
		if _axe_mesh != null:
			# Grip offset = the GLB's own 2H_Axe bone rest relative to handslot.r.
			rig.set_held_weapon(
				_axe_mesh, AXE_BONE, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.033, 0.0))
			)
		play_sfx(&"confirm")
		fx_sparkle(Vector2(rig.position.x, rig.position.z), WEAPON_COLOR, FX_LIFT + 0.6)
		if slot == my_slot and not _axe_hint_shown:
			_axe_hint_shown = true
			_show_event("AXE! Swing to launch rivals", PartyTheme.ACCENT_BRIGHT)
	elif swings <= 0 and was_armed:
		rig.clear_held_weapon()
	var swing := int(state[Gauntlet.PS_SWING_SEQ])
	var hit := int(state[Gauntlet.PS_HIT_SEQ])
	var swing_seen: int = _last_swing_seq.get(slot, swing)
	var hit_seen: int = _last_hit_seq.get(slot, hit)
	_last_swing_seq[slot] = swing
	_last_hit_seq[slot] = hit
	# A hit reaction outranks the swing pose — the victim's stagger is the story.
	if hit > hit_seen:
		rig.play(&"hit")
		_reaction_hold[slot] = Time.get_ticks_msec() + int(REACTION_HOLD_SEC * 1000.0)
		fx_burst(Vector2(rig.position.x, rig.position.z), WEAPON_COLOR, FX_LIFT + 0.5)
		if slot == my_slot:
			request_shake(8.0)
			play_sfx(&"error")
	elif swing > swing_seen:
		rig.play(&"attack")
		_reaction_hold[slot] = Time.get_ticks_msec() + int(REACTION_HOLD_SEC * 1000.0)
		play_sfx(&"click")
		fx_sparkle(Vector2(rig.position.x, rig.position.z), WEAPON_COLOR, FX_LIFT + 0.8)


## Floor axes: one spinning gold-tinted model per replicated pickup; a sparkle
## telegraphs the drop and a flash marks the spot where one was grabbed.
func _update_weapons() -> void:
	for node in _weapon_nodes:
		node.queue_free()
	_weapon_nodes.clear()
	var current_keys := {}
	for weapon: Array in weapons:
		var pos := Vector2(float(weapon[Gauntlet.WP_X]), float(weapon[Gauntlet.WP_Y]))
		if _axe_mesh != null:
			var node := MeshInstance3D.new()
			node.mesh = _axe_mesh
			node.position = to_arena(pos, PLATFORM_THICKNESS + WEAPON_FLOAT_Y)
			arena.add_child(node)
			_weapon_nodes.append(node)
		var key := _hazard_key(pos)
		current_keys[key] = pos
		if not _last_weapon_keys.has(key):
			fx_sparkle(pos, WEAPON_COLOR, FX_LIFT + WEAPON_FLOAT_Y)
	for key: String in _last_weapon_keys:
		if not current_keys.has(key):
			fx_burst(_last_weapon_keys[key], WEAPON_COLOR, FX_LIFT + WEAPON_FLOAT_Y)
	_last_weapon_keys = current_keys


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
		var pos := Vector2(float(hazard[Gauntlet.HZ_X]), float(hazard[Gauntlet.HZ_Y]))
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(hazard[Gauntlet.HZ_RADIUS])
		mesh.bottom_radius = float(hazard[Gauntlet.HZ_RADIUS])
		mesh.height = 0.05
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var armed := (
			1.0 - clampf(float(hazard[Gauntlet.HZ_WARN]) / Gauntlet.HAZARD_WARN_SEC, 0.0, 1.0)
		)
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


## #583: lights the doomed band — the ring from the post-shrink radius out to
## the current one — for the last Gauntlet.SHRINK_WARN_SEC before it lands,
## reddening as the countdown closes in. Hidden once the platform bottoms out
## at MIN_RADIUS (nothing left to telegraph).
func _update_shrink_telegraph() -> void:
	if _shrink_telegraph == null:
		return
	var doomed := radius > Gauntlet.MIN_RADIUS + 0.01 and _shrink_in <= Gauntlet.SHRINK_WARN_SEC
	_shrink_telegraph.visible = doomed
	if not doomed:
		return
	var next_radius := maxf(
		radius - Gauntlet.shrink_per_stage_for(names.size()), Gauntlet.MIN_RADIUS
	)
	_shrink_telegraph_mesh.inner_radius = next_radius
	_shrink_telegraph_mesh.outer_radius = radius
	var urgency := 1.0 - clampf(_shrink_in / Gauntlet.SHRINK_WARN_SEC, 0.0, 1.0)
	_shrink_base_alpha = lerpf(SHRINK_TELEGRAPH_MIN_ALPHA, SHRINK_TELEGRAPH_MAX_ALPHA, urgency)
	if ArenaFX.reduced_motion:
		_shrink_telegraph_mat.albedo_color.a = _shrink_base_alpha


# --- Finale chrome (M16-11) ---------------------------------------------------


## Builds the finale chrome overlay: a centered intro card and a top event
## banner, both hidden until triggered. Themed with the M16-01 design system.
func _build_chrome() -> void:
	_chrome = CanvasLayer.new()
	_chrome.name = "FinaleChrome"
	_chrome.layer = CHROME_LAYER
	add_child(_chrome)

	_intro_box = VBoxContainer.new()
	_intro_box.name = "IntroCard"
	_intro_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_intro_box.set_anchors_preset(Control.PRESET_CENTER)
	_intro_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_intro_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_intro_box.add_theme_constant_override(&"separation", PartyTheme.SPACE_XS)
	_intro_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_box.visible = false
	_chrome.add_child(_intro_box)
	_intro_title = _styled_label(
		PartyTheme.FONT_DISPLAY, PartyTheme.SIZE_DISPLAY, PartyTheme.ACCENT_BRIGHT
	)
	_intro_title.name = "IntroTitle"
	_intro_box.add_child(_intro_title)
	_intro_sub = _styled_label(PartyTheme.FONT_BODY, PartyTheme.SIZE_HEADER, PartyTheme.TEXT)
	_intro_sub.name = "IntroSub"
	_intro_box.add_child(_intro_sub)

	_event_banner = PanelContainer.new()
	_event_banner.name = "EventBanner"
	_event_banner.add_theme_stylebox_override(&"panel", _chrome_panel(PartyTheme.ACCENT))
	_event_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_event_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_event_banner.position.y = 90.0
	_event_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_banner.visible = false
	_chrome.add_child(_event_banner)
	_event_label = _styled_label(PartyTheme.FONT_DISPLAY, PartyTheme.SIZE_TITLE, PartyTheme.TEXT)
	_event_label.name = "EventLabel"
	_event_banner.add_child(_event_label)


## A semi-opaque themed panel keyed to an accent border colour.
func _chrome_panel(accent: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PartyTheme.BG_DARK, 0.92)
	box.set_border_width_all(2)
	box.border_color = accent
	box.set_corner_radius_all(PartyTheme.RADIUS_MD)
	box.content_margin_left = PartyTheme.SPACE_LG
	box.content_margin_right = PartyTheme.SPACE_LG
	box.content_margin_top = PartyTheme.SPACE_SM
	box.content_margin_bottom = PartyTheme.SPACE_SM
	return box


func _styled_label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Flashes "THE GAUNTLET" once as the finale begins replicating.
func _flash_intro() -> void:
	if _intro_box == null:
		return
	_intro_title.text = "THE GAUNTLET"
	_intro_sub.text = "Grab an axe — last one standing takes the crown"
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_tween = _reveal(_intro_box, INTRO_HOLD_SEC)


## Pops a themed top banner (elimination / grudge) in `color`.
func _show_event(text: String, color: Color) -> void:
	if _event_banner == null:
		return
	_event_label.text = text
	_event_label.add_theme_color_override(&"font_color", color)
	_event_banner.add_theme_stylebox_override(&"panel", _chrome_panel(color))
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = _reveal(_event_banner, BANNER_HOLD_SEC)


## Once one blob is left standing, crown it — a gold banner plus a burst at the
## arena center. Fires at most once per finale.
func _check_winner() -> void:
	if _winner_shown or players.size() < 2:
		return
	var standing := -1
	var count := 0
	for slot: int in players:
		if int((players[slot] as Array)[Gauntlet.PS_LIVES]) > 0:
			count += 1
			standing = slot
	if count != 1:
		return
	_winner_shown = true
	_event_label.text = "CHAMPION\n%s" % player_name(standing)
	_event_label.add_theme_color_override(&"font_color", PartyTheme.ACCENT_BRIGHT)
	_event_banner.add_theme_stylebox_override(&"panel", _chrome_panel(PartyTheme.ACCENT_BRIGHT))
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = _reveal(_event_banner, WINNER_HOLD_SEC)
	fx_burst(Vector2.ZERO, PartyTheme.ACCENT_BRIGHT, PLATFORM_THICKNESS + 1.0)


## Reveals `node` for `hold` seconds then hides it. With reduced motion it just
## appears and holds; otherwise it fades in and out on the shared motion tokens.
func _reveal(node: Control, hold: float) -> Tween:
	node.visible = true
	if not is_inside_tree() or ArenaFX.reduced_motion:
		node.modulate.a = 1.0
		_hide_after(node, hold)
		return null
	node.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, PartyTheme.DUR_MED)
	tween.tween_interval(hold)
	tween.tween_property(node, "modulate:a", 0.0, PartyTheme.DUR_SLOW)
	tween.tween_callback(_hide_node.bind(node))
	return tween


func _hide_after(node: Control, hold: float) -> void:
	if not is_inside_tree():
		return
	get_tree().create_timer(hold).timeout.connect(_hide_node.bind(node))


func _hide_node(node: Control) -> void:
	if is_instance_valid(node):
		node.visible = false
