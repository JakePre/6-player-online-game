extends SideScrollView
## Loadout Duel client view (M14-01): renders the replicated arena over the
## M14-00 side-scroll base — the shared stage, weapon daises, in-flight
## projectiles, held-weapon and shield markers, KO'd ducks, and the
## round/score chrome. Simulates nothing locally.
##
## Input: A/D run + W/Space jump go through the base's move axis; J fires,
## K throws (action_primary / action_secondary).

## Declarative button input (#947): jump/fire/throw are momentary; the move
## axis stays a hand-rolled _physics_process send (a continuous vector).
const INPUT_ACTIONS := {
	&"move_up": "jump",
	&"action_primary": "fire",
	&"action_secondary": "throw",
}

const KIND_COLORS := {
	LoadoutDuel.Kind.BLASTER: Color(0.5, 0.8, 1.0),
	LoadoutDuel.Kind.SCATTER: Color(1.0, 0.7, 0.35),
	LoadoutDuel.Kind.BOOMER: Color(1.0, 0.45, 0.35),
	LoadoutDuel.Kind.HAMMER: Color(0.75, 0.6, 0.95),
	LoadoutDuel.Kind.SHIELD: Color(0.4, 0.85, 0.55),
}
## Readable name per pickup (#788): color alone didn't say what a weapon *does*,
## so every dais and held marker now carries its short label (and a distinct
## drawn glyph, below) — the "drawn primitives with labels" identity.
const KIND_LABELS := {
	LoadoutDuel.Kind.BLASTER: "BLAST",
	LoadoutDuel.Kind.SCATTER: "SPRAY",
	LoadoutDuel.Kind.BOOMER: "BOOM",
	LoadoutDuel.Kind.HAMMER: "HAMMER",
	LoadoutDuel.Kind.SHIELD: "SHIELD",
}
const LABEL_SIZE := 13
const GLYPH_COLOR := Color(0.1, 0.1, 0.13)
const KO_MODULATE := Color(0.4, 0.4, 0.45, 0.75)
## #1142 GFX: arena wall panels behind the stage, a shield-edge shimmer, and a
## spawn-platform glow pulse when a fighter respawns at the top of a round.
const WALL_PANEL_COLOR := Color(0.16, 0.17, 0.22)
const WALL_TRIM_COLOR := Color(0.4, 0.8, 1.0, 0.55)
const WALL_PANEL_COUNT := 7
const SHIELD_SHIMMER_COUNT := 5
const SPAWN_GLOW_DURATION := 0.6
const SPAWN_GLOW_COLOR := Color(0.4, 0.85, 1.0, 0.7)

var players := {}
var shots: Array = []
var dais_states: Array = []
var phase: int = LoadoutDuel.Phase.COUNTDOWN
var sub_round := 0

var _fx_layer: Control
var _hud: Label
var _alive_seen := {}
## Last-seen shot count, for the fire edge (#728) — shots only grow between a
## fire and its resolution, so a size increase is a fresh shot.
var _shots_seen := 0
var _seen_snapshot := false
## #1142 GFX: in-flight spawn glow pulses ({slot, age}), fired the moment a new
## sub_round begins (everyone respawns together at that instant).
var _spawn_glows: Array = []
var _sub_round_edges := EdgeTracker.new()
var _wall_layer: Control


func _ready() -> void:
	super()
	# Arena wall panels (#1142) sit behind the stage: right after the shared
	# parallax backdrop, before the platform/rig layers draw over them.
	_wall_layer = Control.new()
	_wall_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wall_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wall_layer.draw.connect(_draw_walls)
	add_child(_wall_layer)
	move_child(_wall_layer, _backdrop.get_index() + 1)
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.draw.connect(_draw_fx)
	add_child(_fx_layer)
	# HUD below the match chrome via the shared helper (#925 clip fix).
	_hud = make_sidescroll_hud()
	resized.connect(_wall_layer.queue_redraw)


func _setup() -> void:
	setup_stage(
		LoadoutDuel.solid_platforms(), LoadoutDuel.one_way_platforms(), LoadoutDuel.stage_bounds()
	)


func _physics_process(_delta: float) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	NetManager.send_match_input({"mx": Input.get_axis(&"move_left", &"move_right")})


func _process(delta: float) -> void:
	var alive: Array = []
	for glow: Dictionary in _spawn_glows:
		glow.age += delta
		if glow.age < SPAWN_GLOW_DURATION:
			alive.append(glow)
	_spawn_glows = alive
	if not _spawn_glows.is_empty() and _fx_layer != null:
		_fx_layer.queue_redraw()


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	shots = game.get("shots", [])
	dais_states = game.get("daises", [])
	phase = int(game.get("phase", LoadoutDuel.Phase.COUNTDOWN))
	sub_round = int(game.get("sub_round", 0))
	# Signature cue (#728, docs/AUDIO_GUIDE.md — Brawlers): any fresh shot
	# (blaster, scatter, or a thrown boomer/hammer) reads as `laser`.
	if _seen_snapshot and shots.size() > _shots_seen:
		play_sfx(&"laser")
	_shots_seen = shots.size()
	# Spawn glow (#1142): a new sub_round respawns everyone at once, so the
	# edge alone is enough to seed a pulse at each fighter's fresh position.
	if _sub_round_edges.changed(&"sub_round", sub_round):
		for slot: int in players:
			_spawn_glows.append({"slot": slot, "age": 0.0})
	render_side_scroll(players)
	for slot: int in players:
		_render_fighter(slot, players[slot])
	_update_hud(game.get("scores", {}))
	if _fx_layer != null:
		_fx_layer.queue_redraw()
	_seen_snapshot = true


func _render_fighter(slot: int, state: Array) -> void:
	if state.size() < LoadoutDuel.PS_COUNT:
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	var flags := int(state[LoadoutDuel.PS_FLAGS])
	var alive := flags & 1 > 0
	rig.modulate = Color.WHITE if alive else KO_MODULATE
	# KO edge: the hit reaction (#1038 — a duel hit is an instant KO, so this is
	# the "got hit" feedback), then shake + the shared elimination cue for
	# everyone, seeded so a rejoiner stays quiet. The spark burst reads even
	# though the grey KO_MODULATE overrides the flinch flash a frame later.
	var was_alive: bool = _alive_seen.get(slot, true)
	if _seen_snapshot and was_alive and not alive:
		play_hit(slot)
		request_shake(7.0)
		play_sfx(&"ko")
	_alive_seen[slot] = alive


func _update_hud(scores: Dictionary) -> void:
	if _hud == null:
		return
	var banner := ""
	match phase:
		LoadoutDuel.Phase.COUNTDOWN:
			banner = "Round %d — Ready…" % (sub_round + 1)
		LoadoutDuel.Phase.FIGHT:
			banner = "Round %d — FIGHT!" % (sub_round + 1)
		LoadoutDuel.Phase.ROUND_OVER:
			banner = "Round %d over" % (sub_round + 1)
	var parts: Array = []
	for slot: int in scores:
		parts.append("%s %d" % [player_name(slot), int(scores[slot])])
	_hud.text = "%s    %s" % [banner, "  ·  ".join(parts)]


## Short readable name for a pickup kind (#788) — empty for NONE.
func kind_label(kind: int) -> String:
	return KIND_LABELS.get(kind, "")


## Daises (colored pads with a per-kind glyph + name, dimmed while cooling),
## then projectiles and per-fighter held/shield markers — world→screen space.
func _draw_fx() -> void:
	for dais in dais_states:
		var kind := int(dais[LoadoutDuel.DS_KIND])
		var at := world_to_screen(
			Vector2(float(dais[LoadoutDuel.DS_X]), float(dais[LoadoutDuel.DS_Y]))
		)
		var active := kind != LoadoutDuel.Kind.NONE
		var color: Color = (
			KIND_COLORS.get(kind, PartyTheme.BG_RAISED) if active else PartyTheme.BG_RAISED
		)
		var radius := 10.0 * _world_scale() / 20.0 + 6.0
		_fx_layer.draw_circle(at, radius, Color(color, 0.9 if active else 0.4))
		if active:
			# The glyph on the pad + the name under it say what it does, not just
			# a color the owner couldn't decode (#788).
			_draw_kind_glyph(at, kind, radius * 0.6)
			_draw_kind_name(Vector2(at.x, at.y + radius + 3.0), kind, color)
	for shot in shots:
		var at := world_to_screen(
			Vector2(float(shot[LoadoutDuel.SH_X]), float(shot[LoadoutDuel.SH_Y]))
		)
		var shot_kind := int(shot[LoadoutDuel.SH_KIND])
		if shot_kind == LoadoutDuel.Shot.THROWN:
			_fx_layer.draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), PartyTheme.TEXT)
		elif shot_kind == LoadoutDuel.Shot.LOB:
			_fx_layer.draw_circle(at, 7.0, KIND_COLORS[LoadoutDuel.Kind.BOOMER])
		else:
			_fx_layer.draw_circle(at, 4.0, PartyTheme.ACCENT_BRIGHT)
	for slot: int in players:
		_draw_fighter_markers(slot, players[slot])


func _draw_fighter_markers(slot: int, state: Array) -> void:
	if state.size() < LoadoutDuel.PS_COUNT:
		return
	var center := world_to_screen(
		Vector2(float(state[LoadoutDuel.PS_X]), float(state[LoadoutDuel.PS_Y]))
	)
	for glow: Dictionary in _spawn_glows:
		if int(glow.slot) != slot:
			continue
		var glow_t: float = float(glow.age) / SPAWN_GLOW_DURATION
		var ring_color := SPAWN_GLOW_COLOR
		ring_color.a *= 1.0 - glow_t
		_fx_layer.draw_arc(center, 14.0 + 20.0 * glow_t, 0.0, TAU, 24, ring_color, 3.0)
	if int(state[LoadoutDuel.PS_FLAGS]) & 1 == 0:
		return
	var facing := int(state[LoadoutDuel.PS_FACING])
	var held := int(state[LoadoutDuel.PS_HELD])
	if held != LoadoutDuel.Kind.NONE:
		var muzzle := center + Vector2(float(facing) * 18.0, -2.0)
		_fx_layer.draw_circle(muzzle, 5.0, KIND_COLORS.get(held, PartyTheme.TEXT))
		# Name what they're holding above their head (#788), so a duck knows its
		# own loadout at a glance — not just a colored dot.
		_draw_kind_name(center - Vector2(0.0, 34.0), held, KIND_COLORS.get(held, PartyTheme.TEXT))
	if int(state[LoadoutDuel.PS_FLAGS]) & 2 > 0:
		_fx_layer.draw_arc(center, 22.0, 0.0, TAU, 20, KIND_COLORS[LoadoutDuel.Kind.SHIELD], 3.0)
		_draw_shield_shimmer(center, 22.0, KIND_COLORS[LoadoutDuel.Kind.SHIELD])


## Shield shimmer (#1142): a handful of bright points sweep around the shield
## ring, purely time-driven — no extra replicated state needed.
func _draw_shield_shimmer(center: Vector2, radius: float, color: Color) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in SHIELD_SHIMMER_COUNT:
		var angle := t * 2.2 + TAU * float(i) / SHIELD_SHIMMER_COUNT
		var point := center + Vector2.from_angle(angle) * radius
		_fx_layer.draw_circle(point, 2.5, Color(color, 0.9))


## Arena wall panels (#1142): vertical support panels with neon trim behind
## the stage, reading as an arena rather than an empty backdrop.
func _draw_walls() -> void:
	var panel_width := size.x / WALL_PANEL_COUNT
	for i in WALL_PANEL_COUNT:
		var x := i * panel_width
		_wall_layer.draw_rect(Rect2(x, 0.0, panel_width * 0.82, size.y), WALL_PANEL_COLOR)
		_wall_layer.draw_line(
			Vector2(x + panel_width * 0.82, 0.0),
			Vector2(x + panel_width * 0.82, size.y),
			WALL_TRIM_COLOR,
			2.0
		)


## The pickup's name, centered at `pos`.
func _draw_kind_name(pos: Vector2, kind: int, color: Color) -> void:
	var text := kind_label(kind)
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	# A dark plate keeps the label legible over any arena color.
	_fx_layer.draw_string(
		font,
		pos - Vector2(width / 2.0, 0.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LABEL_SIZE,
		color
	)


## A distinct drawn glyph per weapon kind, so the pad reads at a glance even
## before the name (#788): a bolt, a spray fan, a boomerang arc, a hammer head,
## a shield ring.
func _draw_kind_glyph(at: Vector2, kind: int, size: float) -> void:
	match kind:
		LoadoutDuel.Kind.BLASTER:
			var tip := at + Vector2(size, 0.0)
			var back := at - Vector2(size * 0.6, 0.0)
			_fx_layer.draw_colored_polygon(
				PackedVector2Array(
					[tip, back + Vector2(0.0, -size * 0.7), back + Vector2(0.0, size * 0.7)]
				),
				GLYPH_COLOR
			)
		LoadoutDuel.Kind.SCATTER:
			for dx in [-size * 0.6, 0.0, size * 0.6]:
				_fx_layer.draw_circle(at + Vector2(dx, 0.0), size * 0.28, GLYPH_COLOR)
		LoadoutDuel.Kind.BOOMER:
			_fx_layer.draw_arc(at, size, -PI * 0.7, PI * 0.7, 12, GLYPH_COLOR, 3.0)
		LoadoutDuel.Kind.HAMMER:
			_fx_layer.draw_rect(
				Rect2(at - Vector2(size, size * 0.5), Vector2(size * 2.0, size)), GLYPH_COLOR
			)
		LoadoutDuel.Kind.SHIELD:
			_fx_layer.draw_arc(at, size, 0.0, TAU, 18, GLYPH_COLOR, 3.0)
