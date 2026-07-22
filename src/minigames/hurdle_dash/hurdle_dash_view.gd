extends MinigameView
## Hurdle Dash client view (M4-07): one horizontal lane per runner with the
## shared hurdle layout, jump arcs, and the finish line. Hold right to run,
## action_primary to jump.
## M13-30 FX pass (2D juice per PHASE2.md §7 — deliberately flat): speed
## lines trail moving runners, and clipping a hurdle throws a spark burst.

## Declarative button input (#947): jump the hurdles (run is the held move axis).
const INPUT_ACTIONS := {&"action_primary": "jump"}
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
## #1141 GFX: landing dust, a fading jump-arc trail, dashed lane markings,
## a start line, a waving finish flag, and dirt specks on the ground band.
const DUST_COLOR := Color(0.75, 0.68, 0.55, 0.6)
const DUST_DURATION := 0.35
const DUST_PUFFS := 4
const TRAIL_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const TRAIL_LIFE_SEC := 0.4
const TRAIL_MAX_POINTS := 6
const LANE_DASH_COLOR := Color(0.4, 0.36, 0.3, 0.5)
const LANE_DASH_LEN := 10.0
const LANE_DASH_GAP := 8.0
const START_COLOR := Color(0.85, 0.85, 0.7, 0.6)
const FLAG_POLE_COLOR := Color(0.7, 0.7, 0.7)
const FLAG_COLOR := Color(0.4, 0.85, 0.4)
const DIRT_SPECK_COLOR := Color(0.14, 0.11, 0.08)

## Latest replicated state, straight from HurdleDash.get_snapshot().
var players := {}
var hurdles: Array = []
var course_len := HurdleDash.COURSE_LEN

# M13-30 FX state: in-flight clip sparks ({slot, age}), last-seen stun and
# progress per slot for clip detection and speed-line lengths.
var _sparks: Array = []
var _stun_edges := EdgeTracker.new()
var _progress_edges := EdgeTracker.new()
var _speeds := {}
var _finished_edges := EdgeTracker.new()
## #1141 GFX: in-flight landing dust puffs ({slot, age}), a fading per-slot
## jump-arc trail ({progress, lift, age} lists), and airborne-falling detection.
var _dust: Array = []
var _trails := {}
var _airborne_edges := EdgeTracker.new()


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(delta: float) -> void:
	var alive: Array = []
	for spark: Dictionary in _sparks:
		spark.age += delta
		if spark.age < SPARK_DURATION:
			alive.append(spark)
	_sparks = alive
	var dust_alive: Array = []
	for puff: Dictionary in _dust:
		puff.age += delta
		if puff.age < DUST_DURATION:
			dust_alive.append(puff)
	_dust = dust_alive
	var any_trail := false
	for slot: int in _trails:
		var points: Array = _trails[slot]
		var trail_alive: Array = []
		for point: Dictionary in points:
			point.age += delta
			if point.age < TRAIL_LIFE_SEC:
				trail_alive.append(point)
		_trails[slot] = trail_alive
		any_trail = any_trail or not trail_alive.is_empty()
	if not _sparks.is_empty() or not _dust.is_empty() or any_trail:
		queue_redraw()


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
		if _stun_edges.rose(slot, stun > 0.0):
			_sparks.append({"slot": slot, "age": 0.0})
			if slot == my_slot:
				# A non-damaging stumble, not a hurt-generic (#728).
				play_sfx(&"bump")
		var progress := float(state[HurdleDash.PS_PROGRESS])
		_speeds[slot] = maxf(progress - float(_progress_edges.peek(slot, progress)), 0.0)
		_progress_edges.changed(slot, progress)
		var finished := bool(state[HurdleDash.PS_FINISHED])
		if _finished_edges.rose(slot, finished):
			if slot == my_slot:
				# Crossing the finish line is a checkpoint (#728).
				play_sfx(&"bell")
		var airborne := int(state[HurdleDash.PS_AIRBORNE]) == 1
		if airborne:
			var points: Array = _trails.get(slot, [])
			points.append({"progress": float(state[HurdleDash.PS_PROGRESS]), "age": 0.0})
			if points.size() > TRAIL_MAX_POINTS:
				points.pop_front()
			_trails[slot] = points
		if _airborne_edges.fell(slot, airborne):
			_dust.append({"slot": slot, "age": 0.0})
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
		# Track texture (#1141): dashed lane markings + dirt specks sell the
		# ground band as a running track rather than a flat fill.
		_draw_lane_markings(left, width, ground, fit)
		_draw_dirt_specks(left, width, ground, ground_band_height, row, fit)
		draw_rect(Rect2(left, lane_top, width, lane_height), LANE_BORDER, false, 1.5)
		# Start line (#1141): bookends the finish line at the opposite edge.
		draw_line(Vector2(left, lane_top), Vector2(left, lane_top + lane_height), START_COLOR, 3.0)
		for hurdle: Variant in hurdles:
			var x := left + float(hurdle) * px_per_unit
			# Two posts + a crossbar (#1141) read as a hurdle silhouette rather
			# than a single painted post.
			var post_gap := 3.0 * fit
			draw_line(
				Vector2(x - post_gap, ground),
				Vector2(x - post_gap, ground - 14.0 * fit),
				HURDLE_COLOR,
				3.0
			)
			draw_line(
				Vector2(x + post_gap, ground),
				Vector2(x + post_gap, ground - 14.0 * fit),
				HURDLE_COLOR,
				3.0
			)
			draw_line(
				Vector2(x - post_gap, ground - 14.0 * fit),
				Vector2(x + post_gap, ground - 14.0 * fit),
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
		# Jump-arc trail (#1141): fading marks along the airborne path this
		# runner just flew, so the arc itself reads, not just the jump pose.
		for point: Dictionary in _trails.get(slot, []):
			var trail_x := left + float(point.progress) * px_per_unit
			var trail_t: float = 1.0 - float(point.age) / TRAIL_LIFE_SEC
			var trail_color := TRAIL_COLOR
			trail_color.a *= trail_t
			draw_circle(
				Vector2(trail_x, ground - JUMP_LIFT * fit), maxf(1.5, 3.0 * fit), trail_color
			)
		# Stun stumble (#1141): the runner tilts/wobbles while stunned, easing
		# out as the stun timer runs down, rather than just tinting red.
		var stun_remaining := float(state[HurdleDash.PS_STUN])
		var wobble := 0.0
		if stunned:
			var stun_t := stun_remaining / HurdleDash.STUN_SEC
			wobble = sin(Time.get_ticks_msec() / 1000.0 * 18.0) * 0.35 * stun_t
		_draw_runner(Vector2(x_pos, y_pos - 6.0 * fit), color, fit, airborne, wobble)
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
		# Landing dust (#1141): a puff of ground specks where this runner
		# just touched back down after a jump.
		for puff: Dictionary in _dust:
			if int(puff.slot) != slot:
				continue
			var puff_t: float = float(puff.age) / DUST_DURATION
			var puff_color := DUST_COLOR
			puff_color.a *= 1.0 - puff_t
			for i in DUST_PUFFS:
				var puff_dir := Vector2.from_angle(PI + (float(i) - 1.5) * 0.5)
				var puff_reach := (3.0 + 10.0 * puff_t) * fit
				draw_circle(
					Vector2(x_pos, ground) + puff_dir * puff_reach, maxf(1.0, 2.0 * fit), puff_color
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
	# Finish flag (#1141): a single waving pennant above the top lane's finish
	# edge — the animated "you're racing toward this" landmark.
	_draw_finish_flag(top, left, width, fit)


## Runner silhouette (#1141): head + body + splayed legs instead of a bare
## circle, so the jump arc reads on the runner's own pose. `wobble` is a
## radians tilt applied while stunned, easing out with the stun timer.
func _draw_runner(head: Vector2, color: Color, fit: float, airborne: bool, wobble: float) -> void:
	var body_len := 9.0 * fit
	var leg_len := 6.0 * fit
	var up := Vector2.UP.rotated(wobble)
	var down := -up
	var hip := head + down * body_len
	draw_circle(head, maxf(2.5, 4.0 * fit), color)
	draw_line(head, hip, color, maxf(1.5, 2.5 * fit))
	if airborne:
		# Tucked mid-jump.
		draw_line(hip, hip + (down.rotated(0.9) * leg_len), color, maxf(1.5, 2.0 * fit))
		draw_line(hip, hip + (down.rotated(0.3) * leg_len), color, maxf(1.5, 2.0 * fit))
	else:
		# A running stride, splayed fore and aft.
		draw_line(hip, hip + (down.rotated(0.6) * leg_len), color, maxf(1.5, 2.0 * fit))
		draw_line(hip, hip + (down.rotated(-0.6) * leg_len), color, maxf(1.5, 2.0 * fit))


## Track texture (#1141): dashed lane markings across the ground band.
func _draw_lane_markings(left: float, width: float, ground: float, fit: float) -> void:
	var line_y := ground + 3.0 * fit
	var dash := LANE_DASH_LEN * fit
	var gap := LANE_DASH_GAP * fit
	var x := left
	while x < left + width:
		draw_line(
			Vector2(x, line_y), Vector2(minf(x + dash, left + width), line_y), LANE_DASH_COLOR, 2.0
		)
		x += dash + gap


## Track texture (#1141): small dirt specks scattered across the ground band,
## seeded from the lane row so they stay stable across frames.
func _draw_dirt_specks(
	left: float, width: float, ground: float, band_height: float, row: int, fit: float
) -> void:
	var speck_count := 10
	for i in speck_count:
		var seed_val := (row + 1) * 977 + i * 133
		var frac_x := float(seed_val % 97) / 97.0
		var frac_y := float((seed_val * 31) % 61) / 61.0
		var pos := Vector2(left + frac_x * width, ground + frac_y * band_height * 0.9)
		draw_circle(pos, maxf(0.8, 1.2 * fit), DIRT_SPECK_COLOR)


## Finish flag (#1141): a waving pennant above the top lane's finish edge.
func _draw_finish_flag(top: float, left: float, width: float, fit: float) -> void:
	var pole_base := Vector2(left + width, top)
	var pole_top := Vector2(left + width, top - 14.0 * fit)
	draw_line(pole_base, pole_top, FLAG_POLE_COLOR, 2.0)
	var wave := sin(Time.get_ticks_msec() / 1000.0 * 5.0) * 2.0 * fit
	var flag_pts := PackedVector2Array(
		[
			pole_top,
			Vector2(pole_top.x + 10.0 * fit + wave, pole_top.y + 4.0 * fit),
			Vector2(pole_top.x + wave, pole_top.y + 8.0 * fit),
		]
	)
	draw_colored_polygon(flag_pts, FLAG_COLOR)
