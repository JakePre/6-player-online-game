extends MinigameView
## Sumo Smash client view (M4-04): top-down platform disc with palette-colored
## players, a dash-cooldown arc, and dash flashes. Forwards move intent plus
## dash presses (action_primary). Same 2D presentation tier as the Coin
## Scramble reference view.

const PLATFORM_COLOR := Color(0.16, 0.14, 0.12)
const PLATFORM_BORDER := Color(0.5, 0.42, 0.3)
const COOLDOWN_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const DASH_FLASH := Color(1.0, 1.0, 1.0, 0.8)
const NAME_OFFSET := 14.0

## Latest replicated state, straight from SumoSmash.get_snapshot().
var players := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"action_primary"):
		if NetManager.multiplayer.multiplayer_peer != null:
			NetManager.send_match_input({"dash": true})


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	queue_redraw()


func _draw() -> void:
	var px_per_unit := _pixels_per_unit()
	var center := size / 2.0
	draw_circle(center, SumoSmash.PLATFORM_RADIUS * px_per_unit, PLATFORM_COLOR)
	draw_arc(center, SumoSmash.PLATFORM_RADIUS * px_per_unit, 0.0, TAU, 64, PLATFORM_BORDER, 2.0)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in players:
		var state: Array = players[slot]
		var pos := center + Vector2(state[0], state[1]) * px_per_unit
		var color := player_color(slot)
		var radius := SumoSmash.PLAYER_RADIUS * px_per_unit
		draw_circle(pos, radius, color)
		if int(state[3]) == 1:
			draw_arc(pos, radius + 3.0, 0.0, TAU, 24, DASH_FLASH, 3.0)
		var cooldown := float(state[2])
		if cooldown > 0.0:
			var fraction := cooldown / SumoSmash.DASH_COOLDOWN_SEC
			draw_arc(
				pos, radius + 3.0, -TAU / 4.0, -TAU / 4.0 + TAU * fraction, 24, COOLDOWN_COLOR, 2.0
			)
		var caption := player_name(slot)
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(
			font,
			pos + Vector2(-text_size.x / 2.0, -radius - NAME_OFFSET),
			caption,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size,
			color
		)


func _pixels_per_unit() -> float:
	var side := minf(size.x, size.y) - 2.0 * NAME_OFFSET
	return maxf(side, 100.0) / (SumoSmash.PLATFORM_RADIUS * 2.0)
