extends MinigameView
## Poison Feast client view (M4-14): draws the shared table top-down —
## players as palette-colored discs with name + score, dishes as plain
## uniform dots. Dishes never indicate which are poisoned; that hiddenness
## is the whole mechanic. 2D presentation, matching the Coin Scramble
## reference's placeholder style.

const ARENA_COLOR := Color(0.13, 0.15, 0.19)
const ARENA_BORDER := Color(0.35, 0.38, 0.45)
const DISH_COLOR := Color(0.85, 0.7, 0.4)
const NAME_OFFSET := 14.0

var players := {}
var dishes: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	dishes = game.get("dishes", [])
	queue_redraw()


func _draw() -> void:
	var px_per_unit := _pixels_per_unit()
	draw_rect(_arena_rect(px_per_unit), ARENA_COLOR)
	draw_rect(_arena_rect(px_per_unit), ARENA_BORDER, false, 2.0)
	for dish: Array in dishes:
		var center := _to_px(Vector2(dish[0], dish[1]), px_per_unit)
		draw_circle(center, 0.3 * px_per_unit, DISH_COLOR)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in players:
		var state: Array = players[slot]
		var center := _to_px(Vector2(state[0], state[1]), px_per_unit)
		var color := player_color(slot)
		draw_circle(center, PoisonFeast.PLAYER_RADIUS * px_per_unit, color)
		var caption := "%s  %d" % [player_name(slot), int(state[2])]
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(
			font,
			(
				center
				+ Vector2(
					-text_size.x / 2.0, -PoisonFeast.PLAYER_RADIUS * px_per_unit - NAME_OFFSET
				)
			),
			caption,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size,
			color
		)


func _pixels_per_unit() -> float:
	var side := minf(size.x, size.y) - 2.0 * NAME_OFFSET
	return maxf(side, 100.0) / (PoisonFeast.ARENA_HALF * 2.0)


func _arena_rect(px_per_unit: float) -> Rect2:
	var half := PoisonFeast.ARENA_HALF * px_per_unit
	var center := size / 2.0
	return Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)


func _to_px(world: Vector2, px_per_unit: float) -> Vector2:
	return size / 2.0 + world * px_per_unit
