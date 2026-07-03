extends MinigameView
## Hurdle Dash client view (M4-07): one horizontal lane per runner with the
## shared hurdle layout, jump arcs, and the finish line. Hold right to run,
## action_primary to jump.

const LANE_COLOR := Color(0.15, 0.16, 0.19)
const LANE_BORDER := Color(0.34, 0.37, 0.44)
const HURDLE_COLOR := Color(0.85, 0.55, 0.25)
const FINISH_COLOR := Color(0.4, 0.85, 0.4)
const STUN_COLOR := Color(0.9, 0.3, 0.25)
const LANE_HEIGHT := 54.0
const LANE_GAP := 12.0
const JUMP_LIFT := 16.0

## Latest replicated state, straight from HurdleDash.get_snapshot().
var players := {}
var hurdles: Array = []
var course_len := HurdleDash.COURSE_LEN


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"jump": true})


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	hurdles = game.get("hurdles", [])
	course_len = float(game.get("course_len", HurdleDash.COURSE_LEN))
	queue_redraw()


func _draw() -> void:
	if players.is_empty():
		return
	var lanes := players.keys()
	lanes.sort()
	var total_height := lanes.size() * LANE_HEIGHT + (lanes.size() - 1) * LANE_GAP
	var top := (size.y - total_height) / 2.0
	var left := size.x * 0.07
	var width := size.x * 0.86
	var px_per_unit := width / course_len
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for row in lanes.size():
		var slot: int = lanes[row]
		var state: Array = players[slot]
		var lane_top := top + row * (LANE_HEIGHT + LANE_GAP)
		var ground := lane_top + LANE_HEIGHT - 10.0
		draw_rect(Rect2(left, lane_top, width, LANE_HEIGHT), LANE_COLOR)
		draw_rect(Rect2(left, lane_top, width, LANE_HEIGHT), LANE_BORDER, false, 1.5)
		for hurdle: Variant in hurdles:
			var x := left + float(hurdle) * px_per_unit
			draw_line(Vector2(x, ground), Vector2(x, ground - 14.0), HURDLE_COLOR, 4.0)
		draw_line(
			Vector2(left + width, lane_top),
			Vector2(left + width, lane_top + LANE_HEIGHT),
			FINISH_COLOR,
			3.0
		)
		var x_pos := left + float(state[0]) * px_per_unit
		var airborne := int(state[1]) == 1
		var stunned := float(state[2]) > 0.0
		var y_pos := ground - (JUMP_LIFT if airborne else 0.0)
		var color := STUN_COLOR if stunned else player_color(slot)
		draw_circle(Vector2(x_pos, y_pos - 6.0), 7.0, color)
		var caption := player_name(slot) + ("  🏁" if bool(state[3]) else "")
		draw_string(
			font,
			Vector2(left + 4.0, lane_top + 14.0),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			player_color(slot)
		)
