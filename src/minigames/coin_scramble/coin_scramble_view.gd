extends MinigameView
## Coin Scramble client view (M3-06): draws the replicated arena top-down —
## players as palette-colored discs with name + coin count, coins as gold
## dots. 2D presentation for the vertical slice; the 2.5D isometric pass
## (M2-04 kit) replaces the drawing, not the contract, in the M4 template
## refinement.

const ARENA_COLOR := Color(0.13, 0.15, 0.19)
const ARENA_BORDER := Color(0.35, 0.38, 0.45)
const COIN_COLOR := Color(0.96, 0.79, 0.2)
const NAME_OFFSET := 14.0

## Latest replicated state, straight from CoinScramble.get_snapshot().
var players := {}
var coins: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	coins = game.get("coins", [])
	queue_redraw()


func _draw() -> void:
	var px_per_unit := _pixels_per_unit()
	draw_rect(_arena_rect(px_per_unit), ARENA_COLOR)
	draw_rect(_arena_rect(px_per_unit), ARENA_BORDER, false, 2.0)
	for coin: Array in coins:
		var center := _to_px(Vector2(coin[0], coin[1]), px_per_unit)
		draw_circle(center, 0.3 * px_per_unit, COIN_COLOR)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in players:
		var state: Array = players[slot]
		var center := _to_px(Vector2(state[0], state[1]), px_per_unit)
		var color := player_color(slot)
		draw_circle(center, CoinScramble.PLAYER_RADIUS * px_per_unit, color)
		var caption := "%s  %d" % [player_name(slot), int(state[2])]
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(
			font,
			(
				center
				+ Vector2(
					-text_size.x / 2.0, -CoinScramble.PLAYER_RADIUS * px_per_unit - NAME_OFFSET
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
	return maxf(side, 100.0) / (CoinScramble.ARENA_HALF * 2.0)


func _arena_rect(px_per_unit: float) -> Rect2:
	var half := CoinScramble.ARENA_HALF * px_per_unit
	var center := size / 2.0
	return Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)


func _to_px(world: Vector2, px_per_unit: float) -> Vector2:
	return size / 2.0 + world * px_per_unit
