extends MinigameView
## Relay Sprint client view (M4-11): one horizontal lane per team with the
## active runner, sweeping hazards, and progress markers. Same 2D
## presentation tier as the Coin Scramble reference view.
## M13-22 FX pass (2D juice per PHASE2.md §7 — deliberately flat): speed
## lines trail the active runner, and the baton exchange flashes.

const LANE_COLOR := Color(0.14, 0.16, 0.2)
const LANE_BORDER := Color(0.32, 0.36, 0.42)
const HAZARD_COLOR := Color(0.9, 0.3, 0.25)
const FINISH_COLOR := Color(0.4, 0.85, 0.4)
const LANE_HEIGHT := 70.0
const LANE_GAP := 16.0
## Roster/status labels live in a fixed left gutter, off the racing surface
## (#213 — they used to overlap the runners).
const GUTTER_WIDTH := 170.0
const HAZARD_WARN_COLOR := Color(1.0, 0.75, 0.2)
const SPEED_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const BATON_FLASH_COLOR := Color(1.0, 0.9, 0.4)
const FLASH_DURATION := 0.5

## Latest replicated state, straight from RelaySprint.get_snapshot().
var lanes := {}
var track_len := RelaySprint.TRACK_LEN
var hazards: Array = []

# M13-22 FX state: in-flight baton flashes ({lane, age}), last-seen leg and
# progress per lane for handoff detection and speed-line lengths.
var _flashes: Array = []
var _legs_seen := {}
var _progress_seen := {}
var _speeds := {}
var _seen_snapshot := false


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(delta: float) -> void:
	var alive: Array = []
	for flash: Dictionary in _flashes:
		flash.age += delta
		if flash.age < FLASH_DURATION:
			alive.append(flash)
	_flashes = alive
	if not _flashes.is_empty():
		queue_redraw()


func _render(game: Dictionary) -> void:
	lanes = game.get("lanes", {})
	track_len = float(game.get("track_len", RelaySprint.TRACK_LEN))
	hazards = game.get("hazards", [])
	# Baton flash + speed lines (M13-22): the leg index bumping means the
	# baton just changed hands; a same-leg progress delta is the runner's
	# speed. The first snapshot seeds silently.
	for lane_index: int in lanes:
		var state: Array = lanes[lane_index]
		var leg := int(state[1])
		var progress := float(state[2])
		var prev_leg := int(_legs_seen.get(lane_index, leg))
		if _seen_snapshot and leg > prev_leg and not bool(state[4]):
			_flashes.append({"lane": lane_index, "age": 0.0})
		if leg == prev_leg:
			var prev := float(_progress_seen.get(lane_index, progress))
			_speeds[lane_index] = maxf(progress - prev, 0.0)
		else:
			_speeds[lane_index] = 0.0
		_legs_seen[lane_index] = leg
		_progress_seen[lane_index] = progress
	_seen_snapshot = true
	queue_redraw()


func _draw() -> void:
	if lanes.is_empty():
		return
	var font := get_theme_default_font()
	# Crowd fit (M15-07): team lanes shrink together so any count stacks
	# inside the viewport; up to ~6 teams render exactly as before.
	var fit := LaneLayout.fitted_scale(lanes.size(), LANE_HEIGHT + LANE_GAP, size.y * 0.94)
	var lane_height := LANE_HEIGHT * fit
	var lane_gap := LANE_GAP * fit
	var font_size := maxi(8, int(get_theme_default_font_size() * fit))
	var total_height := lanes.size() * lane_height + (lanes.size() - 1) * lane_gap
	var top := (size.y - total_height) / 2.0
	var left := GUTTER_WIDTH + 12.0
	var width := size.x - left - size.x * 0.04
	var px_per_unit := width / track_len
	var lane_indices := lanes.keys()
	lane_indices.sort()
	for row in lane_indices.size():
		var lane_index: int = lane_indices[row]
		var state: Array = lanes[lane_index]
		var lane_top := top + row * (lane_height + lane_gap)
		var rect := Rect2(left, lane_top, width, lane_height)
		draw_rect(rect, LANE_COLOR)
		draw_rect(rect, LANE_BORDER, false, 2.0)
		draw_line(
			Vector2(left + width, lane_top),
			Vector2(left + width, lane_top + lane_height),
			FINISH_COLOR,
			3.0
		)
		var mid_y := lane_top + lane_height / 2.0
		var lat_scale := (lane_height / 2.0 - 8.0 * fit) / RelaySprint.LANE_HALF
		var team: Array = state[0]
		var leg := int(state[1])
		var done: bool = state[4]
		var runner := -1
		var runner_y := mid_y
		if not done:
			runner = team[mini(leg, team.size() - 1)]
			runner_y = mid_y + float(state[3]) * lat_scale
		for hazard: Array in hazards:
			var hx := left + float(hazard[0]) * px_per_unit
			var hy := mid_y + float(hazard[1]) * lat_scale
			# Warn when the sweep is closing on the runner's row (#213).
			var closing := runner >= 0 and absf(hy - runner_y) < lane_height * 0.25
			draw_circle(
				Vector2(hx, hy),
				RelaySprint.HAZARD_RADIUS * px_per_unit,
				HAZARD_WARN_COLOR if closing else HAZARD_COLOR
			)
		if not done:
			var rx := left + float(state[2]) * px_per_unit
			var color := player_color(runner)
			# Speed lines (M13-22): trailing streaks scaled by snapshot speed.
			var speed: float = _speeds.get(lane_index, 0.0)
			if speed > 0.01:
				var line_len := clampf(speed * px_per_unit * 3.0, 8.0, 34.0)
				for i in 3:
					var line_y := runner_y - 6.0 + float(i) * 6.0
					var streak := SPEED_LINE_COLOR
					streak.a -= 0.08 * float(i)
					draw_line(
						Vector2(rx - 12.0 - line_len, line_y),
						Vector2(rx - 12.0, line_y),
						streak,
						1.5
					)
			# Baton flash (M13-22): an expanding ring where the exchange landed.
			for flash: Dictionary in _flashes:
				if int(flash.lane) != lane_index:
					continue
				var age_t: float = flash.age / FLASH_DURATION
				var ring := Color(BATON_FLASH_COLOR, 1.0 - age_t)
				var reach := RelaySprint.RUNNER_RADIUS * px_per_unit * (1.6 + 2.4 * age_t)
				draw_arc(
					Vector2(rx, runner_y), reach, 0.0, TAU, 24, ring, 3.0 * (1.0 - age_t) + 1.0
				)
			draw_circle(Vector2(rx, runner_y), RelaySprint.RUNNER_RADIUS * px_per_unit * 1.4, color)
			draw_circle(
				Vector2(rx, runner_y),
				RelaySprint.RUNNER_RADIUS * px_per_unit * 1.4,
				Color.BLACK,
				false,
				1.5
			)
			# Name tag pinned above the lane so it never sits on the action.
			var tag := player_name(runner)
			var tag_size := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var tag_x := clampf(rx - tag_size.x / 2.0, left, left + width - tag_size.x)
			draw_string(
				font,
				Vector2(tag_x, lane_top - 4.0),
				tag,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				color
			)
		# Roster + status in the gutter, one line per teammate, active bolded
		# by color; never drawn over the lane (#213).
		for i in team.size():
			var slot: int = team[i]
			var line := player_name(slot)
			if not done and i == leg:
				line = "▶ " + line
			draw_string(
				font,
				Vector2(8.0, lane_top + (18.0 + i * 18.0) * fit),
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				GUTTER_WIDTH - 16.0,
				font_size,
				player_color(slot)
			)
		var status := "done!" if done else "leg %d" % (leg + 1)
		draw_string(
			font,
			Vector2(8.0, lane_top + lane_height - 8.0 * fit),
			status,
			HORIZONTAL_ALIGNMENT_LEFT,
			GUTTER_WIDTH - 16.0,
			font_size,
			FINISH_COLOR if done else LANE_BORDER
		)
