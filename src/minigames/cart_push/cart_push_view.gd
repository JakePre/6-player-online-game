extends MinigameView
## Cart Push client view (M4-12): two lanes with carts rolling toward their
## depots, players in palette colors. Same 2D presentation tier as the Coin
## Scramble reference view.

const ARENA_COLOR := Color(0.14, 0.13, 0.11)
const ARENA_BORDER := Color(0.42, 0.36, 0.28)
const TRACK_COLOR := Color(0.3, 0.26, 0.2)
const CART_COLORS: Array[Color] = [Color(0.75, 0.45, 0.2), Color(0.35, 0.55, 0.8)]
const DEPOT_COLOR := Color(0.4, 0.85, 0.4)
const NAME_OFFSET := 14.0

## Latest replicated state, straight from CartPush.get_snapshot().
var players := {}
var carts: Array = []
var track: Array = []
var lane_y := CartPush.LANE_Y
var teams: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	carts = game.get("carts", [])
	track = game.get("track", [])
	lane_y = float(game.get("lane_y", CartPush.LANE_Y))
	teams = game.get("teams", [])
	queue_redraw()


func _draw() -> void:
	var px_per_unit := _pixels_per_unit()
	var half := CartPush.ARENA_HALF * px_per_unit
	var arena := Rect2(size / 2.0 - Vector2(half, half), Vector2(half, half) * 2.0)
	draw_rect(arena, ARENA_COLOR)
	draw_rect(arena, ARENA_BORDER, false, 2.0)
	if track.size() == 2:
		for lane_sign: float in [-1.0, 1.0]:
			var y := size.y / 2.0 + lane_sign * lane_y * px_per_unit
			var from := Vector2(size.x / 2.0 + float(track[0]) * px_per_unit, y)
			var to := Vector2(size.x / 2.0 + float(track[1]) * px_per_unit, y)
			draw_line(from, to, TRACK_COLOR, 5.0)
			draw_circle(to, 0.6 * px_per_unit, DEPOT_COLOR)
	for i in carts.size():
		var lane_sign := -1.0 if i == 0 else 1.0
		var pos := size / 2.0 + Vector2(float(carts[i]), lane_sign * lane_y) * px_per_unit
		draw_circle(pos, CartPush.CART_RADIUS * px_per_unit, CART_COLORS[mini(i, 1)])
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in players:
		var state: Array = players[slot]
		var pos := size / 2.0 + Vector2(state[0], state[1]) * px_per_unit
		var color := player_color(slot)
		draw_circle(pos, CartPush.PLAYER_RADIUS * px_per_unit, color)
		draw_string(
			font,
			pos + Vector2(-30.0, -CartPush.PLAYER_RADIUS * px_per_unit - 4.0),
			player_name(slot),
			HORIZONTAL_ALIGNMENT_CENTER,
			60,
			font_size,
			color
		)


func _pixels_per_unit() -> float:
	var side := minf(size.x, size.y) - 2.0 * NAME_OFFSET
	return maxf(side, 100.0) / (CartPush.ARENA_HALF * 2.0)
