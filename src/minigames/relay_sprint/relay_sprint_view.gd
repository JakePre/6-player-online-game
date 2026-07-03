extends MinigameView
## Relay Sprint client view (M4-11): one horizontal lane per team with the
## active runner, sweeping hazards, and progress markers. Same 2D
## presentation tier as the Coin Scramble reference view.

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

## Latest replicated state, straight from RelaySprint.get_snapshot().
var lanes := {}
var track_len := RelaySprint.TRACK_LEN
var hazards: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _render(game: Dictionary) -> void:
	lanes = game.get("lanes", {})
	track_len = float(game.get("track_len", RelaySprint.TRACK_LEN))
	hazards = game.get("hazards", [])
	queue_redraw()


func _draw() -> void:
	if lanes.is_empty():
		return
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var total_height := lanes.size() * LANE_HEIGHT + (lanes.size() - 1) * LANE_GAP
	var top := (size.y - total_height) / 2.0
	var left := GUTTER_WIDTH + 12.0
	var width := size.x - left - size.x * 0.04
	var px_per_unit := width / track_len
	var lane_indices := lanes.keys()
	lane_indices.sort()
	for row in lane_indices.size():
		var lane_index: int = lane_indices[row]
		var state: Array = lanes[lane_index]
		var lane_top := top + row * (LANE_HEIGHT + LANE_GAP)
		var rect := Rect2(left, lane_top, width, LANE_HEIGHT)
		draw_rect(rect, LANE_COLOR)
		draw_rect(rect, LANE_BORDER, false, 2.0)
		draw_line(
			Vector2(left + width, lane_top),
			Vector2(left + width, lane_top + LANE_HEIGHT),
			FINISH_COLOR,
			3.0
		)
		var mid_y := lane_top + LANE_HEIGHT / 2.0
		var lat_scale := (LANE_HEIGHT / 2.0 - 8.0) / RelaySprint.LANE_HALF
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
			var closing := runner >= 0 and absf(hy - runner_y) < LANE_HEIGHT * 0.25
			draw_circle(
				Vector2(hx, hy),
				RelaySprint.HAZARD_RADIUS * px_per_unit,
				HAZARD_WARN_COLOR if closing else HAZARD_COLOR
			)
		if not done:
			var rx := left + float(state[2]) * px_per_unit
			var color := player_color(runner)
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
				Vector2(8.0, lane_top + 18.0 + i * 18.0),
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				GUTTER_WIDTH - 16.0,
				font_size,
				player_color(slot)
			)
		var status := "done!" if done else "leg %d" % (leg + 1)
		draw_string(
			font,
			Vector2(8.0, lane_top + LANE_HEIGHT - 8.0),
			status,
			HORIZONTAL_ALIGNMENT_LEFT,
			GUTTER_WIDTH - 16.0,
			font_size,
			FINISH_COLOR if done else LANE_BORDER
		)
