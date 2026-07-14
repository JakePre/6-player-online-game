extends MinigameView
## Hurdle Dash client view (M4-07): one horizontal lane per runner with the
## shared hurdle layout, jump arcs, and the finish line. Hold right to run,
## action_primary to jump.
## M13-30 FX pass (2D juice per PHASE2.md §7 — deliberately flat): speed
## lines trail moving runners, and clipping a hurdle throws a spark burst.

const LANE_BORDER := Color(0.34, 0.37, 0.44)
## #930: split each lane into a dusk-sky band and a packed-dirt ground band
## instead of one flat charcoal fill — stays within the deliberately-flat 2D
## style (§7), just with color instead of shading. GROUND_FRACTION is how
## much of the lane height, from the bottom, reads as ground.
const SKY_COLOR := Color(0.13, 0.15, 0.24)
const GROUND_COLOR := Color(0.22, 0.17, 0.13)
const GROUND_FRACTION := 0.4
const HURDLE_COLOR := Color(0.85, 0.55, 0.25)
const HURDLE_TIP_COLOR := Color(0.97, 0.9, 0.75)
const FINISH_COLOR := Color(0.4, 0.85, 0.4)
const STUN_COLOR := Color(0.9, 0.3, 0.25)
const SPEED_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const LANE_HEIGHT := 54.0
const LANE_GAP := 12.0
const JUMP_LIFT := 16.0
const SPARK_DURATION := 0.5
const SPARK_RAYS := 6

## Latest replicated state, straight from HurdleDash.get_snapshot().
var players := {}
var hurdles: Array = []
var course_len := HurdleDash.COURSE_LEN

# M13-30 FX state: in-flight clip sparks ({slot, age}), last-seen stun and
# progress per slot for clip detection and speed-line lengths.
var _sparks: Array = []
var _stun_seen := {}
var _progress_seen := {}
var _speeds := {}
var _finished_seen := {}
var _seen_snapshot := false


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(delta: float) -> void:
	var alive: Array = []
	for spark: Dictionary in _sparks:
		spark.age += delta
		if spark.age < SPARK_DURATION:
			alive.append(spark)
	_sparks = alive
	if not _sparks.is_empty():
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"jump": true})


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	hurdles = game.get("hurdles", [])
	course_len = float(game.get("course_len", HurdleDash.COURSE_LEN))
	# Clip sparks + speed lines (M13-30): a stun timer starting means the
	# runner just clipped a hurdle; the progress delta is their speed. The
	# first snapshot seeds silently.
	for slot: int in players:
		var state: Array = players[slot]
		var stun := float(state[HurdleDash.PS_STUN])
		if _seen_snapshot and stun > 0.0 and float(_stun_seen.get(slot, 0.0)) <= 0.0:
			_sparks.append({"slot": slot, "age": 0.0})
			if slot == my_slot:
				# A non-damaging stumble, not a hurt-generic (#728).
				play_sfx(&"bump")
		_stun_seen[slot] = stun
		var progress := float(state[HurdleDash.PS_PROGRESS])
		_speeds[slot] = maxf(progress - float(_progress_seen.get(slot, progress)), 0.0)
		_progress_seen[slot] = progress
		var finished := bool(state[HurdleDash.PS_FINISHED])
		if _seen_snapshot and finished and not bool(_finished_seen.get(slot, false)):
			if slot == my_slot:
				# Crossing the finish line is a checkpoint (#728).
				play_sfx(&"bell")
		_finished_seen[slot] = finished
	_seen_snapshot = true
	queue_redraw()


func _draw() -> void:
	if players.is_empty():
		return
	var lanes := players.keys()
	lanes.sort()
	# Crowd fit (M15-07): lanes shrink together so any count stacks inside the
	# viewport; up to ~8 runners render exactly as before (fit stays 1.0).
	var fit := LaneLayout.fitted_scale(lanes.size(), LANE_HEIGHT + LANE_GAP, size.y * 0.94)
	var lane_height := LANE_HEIGHT * fit
	var lane_gap := LANE_GAP * fit
	var total_height := lanes.size() * lane_height + (lanes.size() - 1) * lane_gap
	var top := (size.y - total_height) / 2.0
	var left := size.x * 0.07
	var width := size.x * 0.86
	var px_per_unit := width / course_len
	var font := get_theme_default_font()
	var font_size := maxi(8, int(get_theme_default_font_size() * fit))
	for row in lanes.size():
		var slot: int = lanes[row]
		var state: Array = players[slot]
		var lane_top := top + row * (lane_height + lane_gap)
		var ground := lane_top + lane_height - 10.0 * fit
		var ground_band_height := lane_height * GROUND_FRACTION
		draw_rect(Rect2(left, lane_top, width, lane_height - ground_band_height), SKY_COLOR)
		draw_rect(
			Rect2(left, lane_top + lane_height - ground_band_height, width, ground_band_height),
			GROUND_COLOR
		)
		draw_rect(Rect2(left, lane_top, width, lane_height), LANE_BORDER, false, 1.5)
		for hurdle: Variant in hurdles:
			var x := left + float(hurdle) * px_per_unit
			draw_line(Vector2(x, ground), Vector2(x, ground - 14.0 * fit), HURDLE_COLOR, 4.0)
			draw_line(
				Vector2(x, ground - 14.0 * fit),
				Vector2(x, ground - 10.0 * fit),
				HURDLE_TIP_COLOR,
				4.0
			)
		draw_line(
			Vector2(left + width, lane_top),
			Vector2(left + width, lane_top + lane_height),
			FINISH_COLOR,
			3.0
		)
		var x_pos := left + float(state[HurdleDash.PS_PROGRESS]) * px_per_unit
		var airborne := int(state[HurdleDash.PS_AIRBORNE]) == 1
		var stunned := float(state[HurdleDash.PS_STUN]) > 0.0
		var y_pos := ground - (JUMP_LIFT * fit if airborne else 0.0)
		var color := STUN_COLOR if stunned else player_color(slot)
		# Speed lines (M13-30): trailing streaks scaled by snapshot speed.
		var speed: float = _speeds.get(slot, 0.0)
		if speed > 0.01 and not stunned and not bool(state[HurdleDash.PS_FINISHED]):
			var line_len := clampf(speed * px_per_unit * 3.0, 8.0, 30.0)
			for i in 3:
				var line_y := y_pos - (12.0 - float(i) * 5.0) * fit
				var streak := SPEED_LINE_COLOR
				streak.a -= 0.08 * float(i)
				draw_line(
					Vector2(x_pos - 10.0 - line_len, line_y),
					Vector2(x_pos - 10.0, line_y),
					streak,
					1.5
				)
		draw_circle(Vector2(x_pos, y_pos - 6.0 * fit), maxf(3.0, 7.0 * fit), color)
		# Clip sparks (M13-30): radiating rays where a hurdle got eaten.
		for spark: Dictionary in _sparks:
			if int(spark.slot) != slot:
				continue
			var age_t: float = spark.age / SPARK_DURATION
			var reach := (8.0 + 14.0 * age_t) * fit
			var ray_color := Color(HURDLE_COLOR, 1.0 - age_t)
			for ray in SPARK_RAYS:
				var direction := Vector2.from_angle(TAU * float(ray) / SPARK_RAYS)
				var center := Vector2(x_pos, y_pos - 6.0 * fit)
				draw_line(
					center + direction * reach * 0.5, center + direction * reach, ray_color, 2.0
				)
		var caption := player_name(slot) + ("  🏁" if bool(state[HurdleDash.PS_FINISHED]) else "")
		draw_string(
			font,
			Vector2(left + 4.0, lane_top + maxf(10.0, 14.0 * fit)),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			player_color(slot)
		)
