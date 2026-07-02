extends MinigameView
## Tug of War client view (M4-10): rope with a center marker between two team
## rosters; alternate move_left/move_right to pull. Same 2D presentation tier
## as the Coin Scramble reference view.

const ROPE_COLOR := Color(0.72, 0.55, 0.3)
const LINE_COLOR := Color(0.9, 0.25, 0.25)
const MARKER_COLOR := Color(1.0, 0.9, 0.4)
const ROW_SPACING := 22.0

## Latest replicated state, straight from TugOfWar.get_snapshot().
var rope := 0.0
var win_offset := TugOfWar.WIN_OFFSET
var team_a: Array = []
var team_b: Array = []

var _phase := -1


func _unhandled_input(event: InputEvent) -> void:
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	var phase := -1
	if event.is_action_pressed(&"move_left"):
		phase = 0
	elif event.is_action_pressed(&"move_right"):
		phase = 1
	if phase == -1 or phase == _phase:
		return
	_phase = phase
	NetManager.send_match_input({"pull": phase})


func _render(game: Dictionary) -> void:
	rope = float(game.get("rope", 0.0))
	win_offset = float(game.get("win_offset", TugOfWar.WIN_OFFSET))
	team_a = game.get("team_a", [])
	team_b = game.get("team_b", [])
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var half_px := size.x * 0.35
	var px_per_unit := half_px / win_offset
	var marker_x := center.x + rope * px_per_unit
	draw_line(
		Vector2(center.x - half_px, center.y),
		Vector2(center.x + half_px, center.y),
		ROPE_COLOR,
		6.0
	)
	for side: float in [-1.0, 1.0]:
		var line_x := center.x + side * half_px
		draw_line(
			Vector2(line_x, center.y - 40.0), Vector2(line_x, center.y + 40.0), LINE_COLOR, 3.0
		)
	draw_circle(Vector2(marker_x, center.y), 10.0, MARKER_COLOR)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	_draw_roster(team_a, Vector2(center.x - half_px, center.y + 60.0), font, font_size)
	_draw_roster(team_b, Vector2(center.x + half_px, center.y + 60.0), font, font_size)
	draw_string(
		font,
		Vector2(center.x - 120.0, center.y - 60.0),
		"Alternate ◀ ▶ to pull!",
		HORIZONTAL_ALIGNMENT_CENTER,
		240,
		font_size
	)


func _draw_roster(team: Array, at: Vector2, font: Font, font_size: int) -> void:
	for i in team.size():
		var slot: int = team[i]
		draw_string(
			font,
			at + Vector2(-40.0, ROW_SPACING * i),
			player_name(slot),
			HORIZONTAL_ALIGNMENT_CENTER,
			80,
			font_size,
			player_color(slot)
		)
