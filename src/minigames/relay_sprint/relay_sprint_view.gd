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
	var left := size.x * 0.08
	var width := size.x * 0.84
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
		for hazard: Array in hazards:
			var hx := left + float(hazard[0]) * px_per_unit
			var hy := mid_y + float(hazard[1]) * lat_scale
			draw_circle(Vector2(hx, hy), RelaySprint.HAZARD_RADIUS * px_per_unit, HAZARD_COLOR)
		var team: Array = state[0]
		var leg := int(state[1])
		var done: bool = state[4]
		if not done:
			var runner: int = team[mini(leg, team.size() - 1)]
			var rx := left + float(state[2]) * px_per_unit
			var ry := mid_y + float(state[3]) * lat_scale
			var color := player_color(runner)
			draw_circle(Vector2(rx, ry), RelaySprint.RUNNER_RADIUS * px_per_unit, color)
			draw_string(
				font,
				Vector2(rx - 30.0, ry - 14.0),
				player_name(runner),
				HORIZONTAL_ALIGNMENT_CENTER,
				60,
				font_size,
				color
			)
		var roster: Array = []
		for slot: int in team:
			roster.append(player_name(slot))
		var label := " / ".join(roster) + (" — done!" if done else "  (leg %d)" % (leg + 1))
		draw_string(
			font,
			Vector2(left + 6.0, lane_top + 16.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size
		)
