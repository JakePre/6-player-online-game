extends MinigameView
## Trap Corridor client view (M4-15): the corridor with runners, revealed
## traps, and the trapper's own placements (remembered locally — the server
## never replicates hidden traps). Trapper places traps by clicking tiles.
## M13-26 FX pass (2D juice per PHASE2.md §7): the trapper's armed tiles
## pulse while trapping, and a trap going off fires an expanding burst ring.

const CORRIDOR_BORDER := Color(0.4, 0.36, 0.45)
const GRID_LINE := Color(0.1, 0.1, 0.12)
## #930: a checkerboard of two close charcoal-purple tints instead of one flat
## fill — the tiles read as tiles even before anything happens on them, while
## staying within the deliberately-flat 2D style (§7, no gradients/shading).
const TILE_COLOR_A := Color(0.17, 0.16, 0.2)
const TILE_COLOR_B := Color(0.13, 0.12, 0.16)
const REVEALED_COLOR := Color(0.9, 0.3, 0.25)
const MY_TRAP_COLOR := Color(0.9, 0.6, 0.2, 0.55)
const FINISH_COLOR := Color(0.4, 0.85, 0.4)
const SPRING_DURATION := 0.6
const ARM_PULSE_HZ := 2.5
## The keyboard/gamepad placement cursor (M12-05, input parity).
const CURSOR_COLOR := Color(1.0, 1.0, 1.0, 0.9)
## #1159 GFX visual enhancements: brick border, hatch patterns, trap icons,
## runner figure, start line, directional arrows, progress indicator.
const BRICK_COLOR := Color(0.45, 0.42, 0.5)
const BRICK_MORTAR := Color(0.35, 0.32, 0.38)
const BRICK_HEIGHT := 5.0
const START_LINE_COLOR := Color(0.3, 0.85, 0.3, 0.6)
const HATCH_COLOR := Color(0.2, 0.19, 0.24, 0.3)
const DIRECTION_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const FINISHED_PLAYER_ALPHA := 0.35
const REVEAL_FADE_SEC := 0.4
const PROGRESS_BAR_COLOR := Color(0.25, 0.25, 0.3)
const PROGRESS_FILL_COLOR := Color(0.4, 0.85, 0.4)
const RUNNER_LEG_LEN := 3.5
const RUNNER_BODY_RADIUS := 3.0
const RUNNER_HEAD_RADIUS := 2.0
const TRAP_SPIKE_COLOR := Color(0.9, 0.2, 0.15)
const TRAP_SPIKE_COUNT := 3

## Latest replicated state, straight from TrapCorridor.get_snapshot().
var phase := TrapCorridor.Phase.TRAPPING
var phase_left := 0.0
var trapper := -1
var players := {}
var revealed: Array = []
var caught: Array = []
var scores := {}
var traps_left := 0
## Tiles this client placed while trapping (local memory, not replicated).
var my_traps: Array = []
## #1159 GFX animation state: reveal fade-in ages and runner animation clock.
var _reveal_ages: Dictionary = {}
var _runner_clock := 0.0
## #1159: slots that finished (locally tracked — not in snapshot).
var _finished_slots: Array = []
var _prev_active: Array = []
## M13-26 FX state: in-flight spring bursts ({index, age}), last-seen revealed
## list for spring detection, and the arm-pulse clock.
var _springs: Array = []
var _revealed_seen: Array = []
var _seen_snapshot := false
var _arm_clock := 0.0
var _was_caught := false
## Keyboard/gamepad placement cursor (M12-05), on a placeable tile by default.
var _cursor_col := 1
var _cursor_row := TrapCorridor.ROWS / 2


func _process(delta: float) -> void:
	var alive: Array = []
	for spring: Dictionary in _springs:
		spring.age += delta
		if spring.age < SPRING_DURATION:
			alive.append(spring)
	_springs = alive
	var arming := (
		phase == TrapCorridor.Phase.TRAPPING and my_slot == trapper and not my_traps.is_empty()
	)
	if arming:
		_arm_clock += delta
	# #1159: advance reveal fade-in animation.
	var expired: Array = []
	for index: int in _reveal_ages:
		_reveal_ages[index] = _reveal_ages[index] + delta
		if _reveal_ages[index] >= REVEAL_FADE_SEC:
			expired.append(index)
	for index: int in expired:
		_reveal_ages.erase(index)
	# #1159: runner animation clock ticks during RUNNING phase.
	if phase == TrapCorridor.Phase.RUNNING:
		_runner_clock += delta
	if (
		arming
		or not _springs.is_empty()
		or not _reveal_ages.is_empty()
		or phase == TrapCorridor.Phase.RUNNING
	):
		queue_redraw()


func _physics_process(_delta: float) -> void:
	if phase == TrapCorridor.Phase.RUNNING and my_slot != trapper:
		send_move_intent()


## Mouse placement: click a tile to arm it (unchanged — the pointer path).
func _gui_input(event: InputEvent) -> void:
	if phase != TrapCorridor.Phase.TRAPPING or my_slot != trapper:
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var tile := _tile_at_pixel(click.position)
	if tile == []:
		return
	_place_trap(int(tile[0]), int(tile[1]))


## Keyboard/gamepad placement (M12-05, input parity): the trapper drives a tile
## cursor with move_* and arms it with action_primary — so the game is fully
## playable without a mouse. The pointer path above still works too.
func _unhandled_input(event: InputEvent) -> void:
	if phase != TrapCorridor.Phase.TRAPPING or my_slot != trapper or event.is_echo():
		return
	if event.is_action_pressed(&"move_left"):
		_move_cursor(-1, 0)
	elif event.is_action_pressed(&"move_right"):
		_move_cursor(1, 0)
	elif event.is_action_pressed(&"move_up"):
		_move_cursor(0, -1)
	elif event.is_action_pressed(&"move_down"):
		_move_cursor(0, 1)
	elif event.is_action_pressed(&"action_primary"):
		_place_trap(_cursor_col, _cursor_row)


## The cursor only ever rests on placeable tiles — the start/finish columns
## stay safe (matching the sim's own clamp), so it can never target a dead tile.
func _move_cursor(dcol: int, drow: int) -> void:
	_cursor_col = clampi(_cursor_col + dcol, 1, TrapCorridor.COLS - 2)
	_cursor_row = clampi(_cursor_row + drow, 0, TrapCorridor.ROWS - 1)
	queue_redraw()


## Arms a tile, remembering it locally (traps are never replicated). Shared by
## the mouse and cursor paths. The local highlight is recorded first so it never
## depends on the send; the input RPC only fires from an actual player client —
## the server is dedicated (id 1, never a player), so a real player is always a
## non-1 peer, and this also drops the send in the offline unit-test harness
## (id 1) instead of RPCing to self.
func _place_trap(col: int, row: int) -> void:
	if traps_left <= 0:
		return
	var index := col * TrapCorridor.ROWS + row
	if index not in my_traps:
		my_traps.append(index)
	var mp := NetManager.multiplayer
	if mp.has_multiplayer_peer() and mp.get_unique_id() != 1:
		NetManager.send_match_input({"trap": [col, row]})
	queue_redraw()


func _render(game: Dictionary) -> void:
	var new_phase: int = game.get("phase", TrapCorridor.Phase.TRAPPING)
	if new_phase == TrapCorridor.Phase.TRAPPING and phase == TrapCorridor.Phase.RUNNING:
		my_traps.clear()  # New sub-round, new trapper.
		_reveal_ages.clear()  # #1159: fresh round, fresh reveal animations.
		_finished_slots.clear()  # #1159: fresh round, fresh finishers list.
	phase = new_phase
	phase_left = float(game.get("phase_left", 0.0))
	trapper = int(game.get("trapper", -1))
	var new_players: Dictionary = game.get("players", {})
	# #1159: detect finished runners — slots that were active and are now gone.
	if _seen_snapshot and phase == TrapCorridor.Phase.RUNNING:
		for slot: int in _prev_active:
			if slot not in new_players and slot not in caught and slot not in _finished_slots:
				_finished_slots.append(slot)
	_prev_active = new_players.keys().duplicate()
	players = new_players
	revealed = game.get("revealed", [])
	# Trap springs (M13-26): a trap newly in `revealed` just went off. The
	# first snapshot seeds silently so a late join doesn't erupt.
	var already_seeded := _seen_snapshot
	if already_seeded:
		for index: int in revealed:
			if index not in _revealed_seen:
				_springs.append({"index": index, "age": 0.0})
				# #1159: start reveal fade-in for this trap.
				if index not in _reveal_ages:
					_reveal_ages[index] = 0.0
				# The trapper hears their own trap work (M12-02) — `clang` (#728,
				# docs/AUDIO_GUIDE.md) reads as the mechanical snap, replacing
				# the generic UI `confirm`.
				if my_slot == trapper:
					play_sfx(&"clang")
	_seen_snapshot = true
	_revealed_seen = revealed.duplicate()
	caught = game.get("caught", [])
	scores = game.get("scores", {})
	traps_left = int(game.get("traps_left", 0))
	# Getting caught is heard only by the runner it happened to (M12-02).
	var caught_now := my_slot in caught
	if already_seeded and caught_now and not _was_caught:
		play_sfx(&"error")
	_was_caught = caught_now
	queue_redraw()


func _draw() -> void:
	var rect := _corridor_rect()
	var tile := Vector2(rect.size.x / TrapCorridor.COLS, rect.size.y / TrapCorridor.ROWS)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var px_per_unit := rect.size.x / TrapCorridor.CORRIDOR_LEN
	_draw_tile_checkerboard(rect, tile)
	# #1159: subtle diagonal hatch on tiles for a detailed floor look.
	_draw_tile_hatch(rect, tile)
	# #1159: start line at left edge, just inside the border.
	draw_line(
		Vector2(rect.position.x + tile.x, rect.position.y),
		Vector2(rect.position.x + tile.x, rect.end.y),
		START_LINE_COLOR,
		2.0
	)
	# Revealed traps: fade in during REVEAL_FADE_SEC (#1159).
	for index: int in revealed:
		var tr := _tile_rect(rect, tile, index)
		var reveal_alpha := 1.0
		if _reveal_ages.has(index):
			reveal_alpha = minf(_reveal_ages[index] / REVEAL_FADE_SEC, 1.0)
		var rc := Color(REVEALED_COLOR, reveal_alpha)
		draw_rect(tr, rc)
		# #1159: draw spike/snare icon on the revealed trap tile.
		_draw_trap_icon(tr)
	if my_slot == trapper:
		# Arm pulse (M13-26): armed tiles breathe so placement reads as live.
		var trap_color := MY_TRAP_COLOR
		trap_color.a = 0.35 + 0.25 * (0.5 + 0.5 * sin(_arm_clock * TAU * ARM_PULSE_HZ))
		for index: int in my_traps:
			draw_rect(_tile_rect(rect, tile, index), trap_color)
		# Placement cursor (M12-05): outline the tile the stick/keyboard will arm.
		if phase == TrapCorridor.Phase.TRAPPING:
			var cursor_index := _cursor_col * TrapCorridor.ROWS + _cursor_row
			draw_rect(_tile_rect(rect, tile, cursor_index), CURSOR_COLOR, false, 3.0)
	# Spring bursts (M13-26): an expanding, fading ring where a trap went off.
	for spring: Dictionary in _springs:
		var progress: float = spring.age / SPRING_DURATION
		var center := _tile_rect(rect, tile, int(spring.index)).get_center()
		var radius := tile.y * (0.6 + 1.4 * progress)
		var ring_color := Color(REVEALED_COLOR, 1.0 - progress)
		draw_arc(center, radius, 0.0, TAU, 24, ring_color, 1.0 + 3.0 * (1.0 - progress))
	for col in range(1, TrapCorridor.COLS):
		var x := rect.position.x + col * tile.x
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), GRID_LINE, 1.0)
	# #1159: draw brick-textured border instead of flat solid line.
	_draw_brick_border(rect, tile)
	# Finish line at the right edge.
	draw_line(
		Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), FINISH_COLOR, 3.0
	)
	# Draw runners, finished runners, and directional arrows.
	for slot: int in players:
		var state: Array = players[slot]
		var pos := (
			rect.position
			+ Vector2(
				float(state[TrapCorridor.PS_X]) * px_per_unit,
				(
					(float(state[TrapCorridor.PS_Y]) + TrapCorridor.CORRIDOR_HALF_WIDTH)
					* rect.size.y
					/ (TrapCorridor.CORRIDOR_HALF_WIDTH * 2.0)
				)
			)
		)
		var color := player_color(slot)
		var running := phase == TrapCorridor.Phase.RUNNING
		var is_finished := slot in caught or (running and slot in _finished_slots)
		if is_finished:
			# #1159: show finished/caught runners at reduced opacity at their last
			# position, with a small × indicator.
			color.a = FINISHED_PLAYER_ALPHA
			draw_circle(pos, TrapCorridor.PLAYER_RADIUS * px_per_unit, color)
			# Draw × over caught runners.
			var s := tile.x * 0.15
			draw_line(pos + Vector2(-s, -s), pos + Vector2(s, s), color, 1.5)
			draw_line(pos + Vector2(s, -s), pos + Vector2(-s, s), color, 1.5)
		else:
			# #1159: draw animated runner figure with legs instead of a circle.
			_draw_runner_figure(pos, color)
			# #1159: directional arrow pointing right for active runners.
			_draw_direction_arrow(
				pos + Vector2(TrapCorridor.PLAYER_RADIUS * px_per_unit + 4.0, 0.0), color
			)
		draw_string(font, pos + Vector2(-24.0, -10.0), player_name(slot), 1, 48, font_size, color)
	# #1159: runner progress indicator bar at the top of the corridor.
	if phase == TrapCorridor.Phase.RUNNING:
		_draw_progress_indicator(rect)
	draw_string(
		font, Vector2(rect.position.x, rect.position.y - 12.0), _banner_text(), 0, -1, font_size
	)


## #582: who is placing traps, unambiguous for both audiences — the trapper
## gets an explicit "YOU" confirmation instead of only control hints, so a
## first-time trapper isn't left guessing whether the instructions are theirs.
func _banner_text() -> String:
	if phase != TrapCorridor.Phase.TRAPPING:
		return "RUN! (%0.1fs)" % phase_left
	if my_slot == trapper:
		return (
			"YOU are setting traps — move cursor + Space/Ⓐ to arm (or click) — %d left (%0.1fs)"
			% [traps_left, phase_left]
		)
	return "%s is setting traps (%0.1fs)..." % [player_name(trapper), phase_left]


func _draw_tile_checkerboard(rect: Rect2, tile: Vector2) -> void:
	for col in TrapCorridor.COLS:
		for row in TrapCorridor.ROWS:
			var color := TILE_COLOR_A if (col + row) % 2 == 0 else TILE_COLOR_B
			draw_rect(_tile_rect(rect, tile, col * TrapCorridor.ROWS + row), color)


func _corridor_rect() -> Rect2:
	var width := size.x * 0.86
	var height := minf(size.y * 0.5, width * 0.3)
	return Rect2((size - Vector2(width, height)) / 2.0, Vector2(width, height))


func _tile_rect(rect: Rect2, tile: Vector2, index: int) -> Rect2:
	var col := index / TrapCorridor.ROWS
	var row := index % TrapCorridor.ROWS
	return Rect2(rect.position + Vector2(col * tile.x, row * tile.y), tile)


## [col, row] under a pixel, or [] outside the corridor.
func _tile_at_pixel(pixel: Vector2) -> Array:
	var rect := _corridor_rect()
	if not rect.has_point(pixel):
		return []
	var local := pixel - rect.position
	var col := int(local.x / (rect.size.x / TrapCorridor.COLS))
	var row := int(local.y / (rect.size.y / TrapCorridor.ROWS))
	return [col, row]


## #1159: draw brick-textured border around the corridor — alternating
## brick rectangles with mortar gaps to give the border a stone-wall look.
func _draw_brick_border(rect: Rect2, tile: Vector2) -> void:
	var brick_h := BRICK_HEIGHT
	var brick_w := tile.x * 2.0
	var mortar := 1.0
	# Top border.
	var top_y := rect.position.y - brick_h - mortar
	var top_rect := Rect2(rect.position.x, top_y, rect.size.x, brick_h)
	_draw_brick_row(top_rect, brick_w, mortar, 0)
	# Bottom border.
	var bot_y := rect.end.y + mortar
	var bot_rect := Rect2(rect.position.x, bot_y, rect.size.x, brick_h)
	_draw_brick_row(bot_rect, brick_w, mortar, 1)
	# Left border cap.
	var left_rect := Rect2(
		rect.position.x - brick_w * 0.5 - mortar,
		top_y,
		brick_w * 0.5,
		brick_h * 2.0 + mortar * 2.0 + brick_h
	)
	draw_rect(left_rect, BRICK_COLOR)
	draw_rect(
		Rect2(left_rect.position, Vector2(brick_w * 0.15, left_rect.size.y)),
		BRICK_MORTAR,
		false,
		1.0
	)
	# Right border cap.
	var right_rect := Rect2(
		rect.end.x + mortar, top_y, brick_w * 0.5, brick_h * 2.0 + mortar * 2.0 + brick_h
	)
	draw_rect(right_rect, BRICK_COLOR)
	draw_rect(
		Rect2(right_rect.position, Vector2(brick_w * 0.15, right_rect.size.y)),
		BRICK_MORTAR,
		false,
		1.0
	)


## Draw a single row of bricks with mortar gaps, offset by `row_offset`.
func _draw_brick_row(row_rect: Rect2, brick_w: float, mortar: float, row_offset: int) -> void:
	var x := row_rect.position.x - (brick_w * 0.5 if row_offset % 2 == 1 else 0.0)
	var y := row_rect.position.y
	while x < row_rect.end.x + brick_w:
		var bw := brick_w - mortar
		var br := Rect2(x, y, bw, row_rect.size.y)
		draw_rect(br, BRICK_COLOR)
		draw_rect(br, BRICK_MORTAR, false, 1.0)
		x += brick_w


## #1159: draw subtle diagonal hatch pattern on a checkerboard tile to give
## the floor a more detailed stone-tile feel.
func _draw_tile_hatch(rect: Rect2, tile: Vector2) -> void:
	for col in TrapCorridor.COLS:
		for row in TrapCorridor.ROWS:
			var tr := _tile_rect(rect, tile, col * TrapCorridor.ROWS + row)
			var center := tr.get_center()
			var half := minf(tile.x, tile.y) * 0.3
			# Diagonal lines from top-left to bottom-right.
			draw_line(
				center + Vector2(-half, -half), center + Vector2(half, half), HATCH_COLOR, 1.0
			)
			# Diagonal lines from top-right to bottom-left.
			draw_line(
				center + Vector2(half, -half), center + Vector2(-half, half), HATCH_COLOR, 1.0
			)


## #1159: draw a spike/snare icon on a revealed trap tile — three small
## triangular spikes pointing upward.
func _draw_trap_icon(tr: Rect2) -> void:
	var center := tr.get_center()
	var spike_w := tr.size.x * 0.12
	var spike_h := tr.size.y * 0.25
	for i in TRAP_SPIKE_COUNT:
		var offset := (i - (TRAP_SPIKE_COUNT - 1) * 0.5) * spike_w * 1.5
		var pts: PackedVector2Array = [
			center + Vector2(offset - spike_w * 0.5, -spike_h * 0.3),
			center + Vector2(offset, -spike_h),
			center + Vector2(offset + spike_w * 0.5, -spike_h * 0.3),
		]
		draw_colored_polygon(pts, TRAP_SPIKE_COLOR)
		# Small horizontal base line under the spikes.
		draw_line(
			center + Vector2(offset - spike_w * 0.8, -spike_h * 0.3),
			center + Vector2(offset + spike_w * 0.8, -spike_h * 0.3),
			Color(0.6, 0.15, 0.1),
			1.5
		)


## #1159: draw a small runner figure with a body, head, and two animated legs.
## Legs swing based on `_runner_clock` to simulate running motion.
func _draw_runner_figure(pos: Vector2, color: Color) -> void:
	var body_r := RUNNER_BODY_RADIUS
	var head_r := RUNNER_HEAD_RADIUS
	var leg_len := RUNNER_LEG_LEN
	# Body circle.
	draw_circle(pos, body_r, color)
	# Head circle (slightly above the body).
	var head_pos := pos + Vector2(0.0, -(body_r + head_r + 1.0))
	draw_circle(head_pos, head_r, color)
	# Animated legs: alternate swing based on runner clock.
	var leg_swing := sin(_runner_clock * 6.0) * 0.4
	var leg_angle := PI * 0.5 + leg_swing
	# Left leg.
	var left_foot := pos + Vector2(-leg_len * 0.3, body_r + leg_len)
	var left_knee := pos + Vector2(-leg_len * 0.5 * cos(leg_angle), body_r + leg_len * 0.6)
	draw_line(pos + Vector2(0.0, body_r), left_knee, color, 1.5)
	draw_line(left_knee, left_foot, color, 1.5)
	# Right leg (opposite phase).
	var right_leg_angle := PI * 0.5 - leg_swing
	var right_foot := pos + Vector2(leg_len * 0.3, body_r + leg_len)
	var right_knee := pos + Vector2(leg_len * 0.5 * cos(right_leg_angle), body_r + leg_len * 0.6)
	draw_line(pos + Vector2(0.0, body_r), right_knee, color, 1.5)
	draw_line(right_knee, right_foot, color, 1.5)


## #1159: draw a small right-pointing arrow to indicate runner direction.
func _draw_direction_arrow(pos: Vector2, color: Color) -> void:
	var arrow_len := 6.0
	var arrow_wing := 3.0
	# Arrow shaft.
	draw_line(pos, pos + Vector2(arrow_len, 0.0), Color(DIRECTION_COLOR, color.a), 1.5)
	# Arrow head.
	var tip := pos + Vector2(arrow_len, 0.0)
	draw_line(tip, tip + Vector2(-arrow_wing, -arrow_wing), Color(DIRECTION_COLOR, color.a), 1.5)
	draw_line(tip, tip + Vector2(-arrow_wing, arrow_wing), Color(DIRECTION_COLOR, color.a), 1.5)


## #1159: draw a progress indicator bar at the top of the corridor showing
## each runner's progress toward the finish line.
func _draw_progress_indicator(rect: Rect2) -> void:
	var bar_y := rect.position.y - 20.0
	var bar_h := 4.0
	var bar_x := rect.position.x
	var bar_w := rect.size.x
	# Background bar.
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), PROGRESS_BAR_COLOR)
	# Draw a dot for each runner at their fractional position.
	for slot: int in players:
		var state: Array = players[slot]
		var pos_x := float(state[TrapCorridor.PS_X])
		var frac := clampf(pos_x / TrapCorridor.CORRIDOR_LEN, 0.0, 1.0)
		var dot_x := bar_x + frac * bar_w
		var dot_color := player_color(slot)
		draw_circle(Vector2(dot_x, bar_y + bar_h * 0.5), 3.0, dot_color)
	# Draw finished markers.
	for slot: int in _finished_slots:
		var dot_color := player_color(slot)
		dot_color.a = FINISHED_PLAYER_ALPHA
		draw_circle(Vector2(bar_x + bar_w, bar_y + bar_h * 0.5), 3.0, dot_color)
