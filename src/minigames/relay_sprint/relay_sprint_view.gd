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
## GFX pass (#1148): visual upgrades for Relay Sprint — baton, zone markers,
## team borders, start line, directional indicator, finished runners, progress.
const EXCHANGE_ZONE_START_OFFSET := 4.0  # last N units before finish = exchange zone
const START_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const DIRECTION_COLOR := Color(1.0, 1.0, 1.0, 0.25)
const BATON_SIZE := Vector2(8.0, 4.0)
const BATON_COLOR := Color(1.0, 0.85, 0.3)
const FINISHED_DOT_RADIUS := 4.0
const FINISHED_LABEL_COLOR := Color(0.6, 0.9, 0.6, 0.7)
const LEG_PROGRESS_COLOR := Color(1.0, 1.0, 1.0, 0.3)

## Latest replicated state, straight from RelaySprint.get_snapshot().
var lanes := {}
var track_len := RelaySprint.TRACK_LEN
var hazards: Array = []

# M13-22 FX state: in-flight baton flashes ({lane, age}), last-seen leg and
# progress per lane for handoff detection and speed-line lengths.
var _flashes: Array = []
var _leg_edges := EdgeTracker.new()
var _progress_edges := EdgeTracker.new()
var _speeds := {}


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
		var leg := int(state[RelaySprint.LN_ACTIVE_LEG])
		var progress := float(state[RelaySprint.LN_PROGRESS])
		var prev_leg := int(_leg_edges.peek(lane_index, leg))
		if leg > prev_leg and not bool(state[RelaySprint.LN_DONE]):
			_flashes.append({"lane": lane_index, "age": 0.0})
			# Only your own team's handoff pings (M12-02) — the baton pass is a
			# checkpoint (#728), replacing generic UI confirm.
			if my_slot in (state[RelaySprint.LN_ROSTER] as Array):
				play_sfx(&"bell")
		if leg == prev_leg:
			var prev := float(_progress_edges.peek(lane_index, progress))
			# A hazard hit knocks progress back a station (#1068) — the
			# setback debuff, personal to your own team (#728).
			if progress < prev and my_slot in (state[RelaySprint.LN_ROSTER] as Array):
				play_sfx(&"powerdown")
			_speeds[lane_index] = maxf(progress - prev, 0.0)
		else:
			_speeds[lane_index] = 0.0
		_leg_edges.changed(lane_index, leg)
		_progress_edges.changed(lane_index, progress)
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
		var team: Array = state[RelaySprint.LN_ROSTER]
		var team_color := player_color(team[0])
		# Lane background
		draw_rect(rect, LANE_COLOR)
		# Team-colored lane border (GFX #1148)
		draw_rect(rect, team_color, false, 2.0)
		# Start line (GFX #1148): dashed vertical at x=0
		var start_x := left
		var dash_count := 6
		var dash_len := lane_height / (dash_count * 2.0)
		for d in dash_count:
			var dy := lane_top + d * 2.0 * dash_len
			draw_rect(Rect2(start_x - 1.0, dy, 2.0, dash_len), START_LINE_COLOR)
		# Finish line
		draw_line(
			Vector2(left + width, lane_top),
			Vector2(left + width, lane_top + lane_height),
			FINISH_COLOR,
			3.0
		)
		# Exchange zone markers (GFX #1148): dashed vertical lines where handoff happens
		var ez_start_sim := track_len - EXCHANGE_ZONE_START_OFFSET
		var ez_start_px := left + ez_start_sim * px_per_unit
		var ez_end_px := left + width
		for dz in 2:
			var dz_x := ez_start_px if dz == 0 else ez_end_px
			var dz_dash_count := 4
			var dz_dash_len := lane_height / (dz_dash_count * 2.0)
			for d in dz_dash_count:
				var dy := lane_top + d * 2.0 * dz_dash_len
				draw_rect(Rect2(dz_x - 1.0, dy, 2.0, dz_dash_len), team_color * 1.5)
		# Handoff zone highlight (GFX #1148): tint exchange zone when runner is in it
		var mid_y := lane_top + lane_height / 2.0
		var lat_scale := (lane_height / 2.0 - 8.0 * fit) / RelaySprint.LANE_HALF
		var leg := int(state[RelaySprint.LN_ACTIVE_LEG])
		var done: bool = state[RelaySprint.LN_DONE]
		var runner := -1
		var runner_y := mid_y
		if not done:
			runner = team[mini(leg, team.size() - 1)]
			runner_y = mid_y + float(state[RelaySprint.LN_LATERAL]) * lat_scale
			var progress := float(state[RelaySprint.LN_PROGRESS])
			if progress >= ez_start_sim:
				var zone_rect := Rect2(ez_start_px, lane_top, ez_end_px - ez_start_px, lane_height)
				var zone_tint := team_color
				zone_tint.a = 0.15
				draw_rect(zone_rect, zone_tint)
		# Directional indicator (GFX #1148): small chevrons pointing right
		var chev_x := left + 16.0 * fit
		var chev_y := mid_y
		for c in 3:
			var cx := chev_x + float(c) * 8.0 * fit
			var cy_offset := 6.0 * fit - float(c) * 2.0 * fit
			draw_line(
				Vector2(cx - 4.0 * fit, chev_y + cy_offset),
				Vector2(cx, chev_y),
				DIRECTION_COLOR,
				1.5
			)
			draw_line(
				Vector2(cx - 4.0 * fit, chev_y - cy_offset),
				Vector2(cx, chev_y),
				DIRECTION_COLOR,
				1.5
			)
		for hazard: Array in hazards:
			var hx := left + float(hazard[RelaySprint.HZ_X]) * px_per_unit
			var hy := mid_y + float(hazard[RelaySprint.HZ_LATERAL]) * lat_scale
			# Warn when the sweep is closing on the runner's row (#213).
			var closing := runner >= 0 and absf(hy - runner_y) < lane_height * 0.25
			draw_circle(
				Vector2(hx, hy),
				RelaySprint.HAZARD_RADIUS * px_per_unit,
				HAZARD_WARN_COLOR if closing else HAZARD_COLOR
			)
		if not done:
			var rx := left + float(state[RelaySprint.LN_PROGRESS]) * px_per_unit
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
			# Baton (GFX #1148): small rectangle visible in the runner's hand,
			# drawn ahead of the runner (in front of their position).
			var baton_rect := Rect2(
				rx + RelaySprint.RUNNER_RADIUS * px_per_unit * 1.4 - BATON_SIZE.x * 0.5,
				runner_y - BATON_SIZE.y * 0.5,
				BATON_SIZE.x,
				BATON_SIZE.y
			)
			draw_rect(baton_rect, BATON_COLOR)
			draw_rect(baton_rect, Color.BLACK, false, 1.0)
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
		else:
			# Finished runners (GFX #1148): show small dots at the finish line
			var fin_x := left + width - 8.0
			var total_team := team.size()
			for ti in total_team:
				var dot_y := mid_y - (total_team - 1) * 6.0 * 0.5 + float(ti) * 6.0
				draw_circle(
					Vector2(fin_x, dot_y), FINISHED_DOT_RADIUS * fit, player_color(team[ti])
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
		var total_legs := team.size()
		if done:
			var status := "done!"
			draw_string(
				font,
				Vector2(8.0, lane_top + lane_height - 8.0 * fit),
				status,
				HORIZONTAL_ALIGNMENT_LEFT,
				GUTTER_WIDTH - 16.0,
				font_size,
				FINISH_COLOR
			)
		else:
			# Progress indicator (GFX #1148): show leg X of Y
			var status := "leg %d/%d" % [leg + 1, total_legs]
			draw_string(
				font,
				Vector2(8.0, lane_top + lane_height - 8.0 * fit),
				status,
				HORIZONTAL_ALIGNMENT_LEFT,
				GUTTER_WIDTH - 16.0,
				font_size,
				LEG_PROGRESS_COLOR
			)
			# Leg progress bar (GFX #1148): thin bar under the status
			var bar_top := lane_top + lane_height - 4.0 * fit
			var bar_w := GUTTER_WIDTH - 16.0
			var bar_h := 3.0 * fit
			var prog_frac := clampf(float(state[RelaySprint.LN_PROGRESS]) / track_len, 0.0, 1.0)
			draw_rect(Rect2(8.0, bar_top, bar_w, bar_h), Color.WHITE * 0.15)
			if prog_frac > 0.01:
				draw_rect(Rect2(8.0, bar_top, bar_w * prog_frac, bar_h), team_color)
