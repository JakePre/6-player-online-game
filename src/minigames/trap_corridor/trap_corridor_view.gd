extends MinigameView
## Trap Corridor client view (M4-15): the corridor with runners, revealed
## traps, and the trapper's own placements (remembered locally — the server
## never replicates hidden traps). Trapper places traps by clicking tiles.
## M13-26 FX pass (2D juice per PHASE2.md §7): the trapper's armed tiles
## pulse while trapping, and a trap going off fires an expanding burst ring.

const CORRIDOR_COLOR := Color(0.15, 0.14, 0.17)
const CORRIDOR_BORDER := Color(0.4, 0.36, 0.45)
const GRID_LINE := Color(0.1, 0.1, 0.12)
const REVEALED_COLOR := Color(0.9, 0.3, 0.25)
const MY_TRAP_COLOR := Color(0.9, 0.6, 0.2, 0.55)
const FINISH_COLOR := Color(0.4, 0.85, 0.4)
const SPRING_DURATION := 0.6
const ARM_PULSE_HZ := 2.5
## The keyboard/gamepad placement cursor (M12-05, input parity).
const CURSOR_COLOR := Color(1.0, 1.0, 1.0, 0.9)

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

# M13-26 FX state: in-flight spring bursts ({index, age}), last-seen revealed
# list for spring detection, and the arm-pulse clock.
var _springs: Array = []
var _revealed_seen: Array = []
var _seen_snapshot := false
var _arm_clock := 0.0
var _was_caught := false
## Keyboard/gamepad placement cursor (M12-05), on a placeable tile by default.
var _cursor_col := 1
var _cursor_row := TrapCorridor.ROWS / 2


func _physics_process(_delta: float) -> void:
	if phase == TrapCorridor.Phase.RUNNING and my_slot != trapper:
		send_move_intent()


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
	if arming or not _springs.is_empty():
		queue_redraw()


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
	phase = new_phase
	phase_left = float(game.get("phase_left", 0.0))
	trapper = int(game.get("trapper", -1))
	players = game.get("players", {})
	revealed = game.get("revealed", [])
	# Trap springs (M13-26): a trap newly in `revealed` just went off. The
	# first snapshot seeds silently so a late join doesn't erupt.
	var already_seeded := _seen_snapshot
	if already_seeded:
		for index: int in revealed:
			if index not in _revealed_seen:
				_springs.append({"index": index, "age": 0.0})
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
	draw_rect(rect, CORRIDOR_COLOR)
	for index: int in revealed:
		draw_rect(_tile_rect(rect, tile, index), REVEALED_COLOR)
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
	draw_rect(rect, CORRIDOR_BORDER, false, 2.0)
	draw_line(
		Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), FINISH_COLOR, 3.0
	)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var px_per_unit := rect.size.x / TrapCorridor.CORRIDOR_LEN
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
		draw_circle(pos, TrapCorridor.PLAYER_RADIUS * px_per_unit, color)
		draw_string(font, pos + Vector2(-24.0, -10.0), player_name(slot), 1, 48, font_size, color)
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
