extends MinigameView
## Hot Potato client view (M4-02, SPEC $7 #3): top-down square arena with
## palette-colored players; the carrier wears the bomb (orange disc with the
## fuse countdown above it) and eliminated players are dimmed gray. Same 2D
## presentation tier as the Coin Scramble reference view.

const ARENA_COLOR := Color(0.13, 0.15, 0.19)
const ARENA_BORDER := Color(0.35, 0.38, 0.45)
const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46, 0.6)
const BOMB_COLOR := Color(0.95, 0.55, 0.15)
const FUSE_TEXT_COLOR := Color(1.0, 0.85, 0.4)
const NAME_OFFSET := 14.0
const BOMB_RADIUS_FRACTION := 0.6

## Latest replicated state, straight from HotPotato.get_snapshot().
var players := {}
var carrier := -1
var fuse := 0.0
var alive: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	carrier = int(game.get("carrier", -1))
	fuse = float(game.get("fuse", 0.0))
	alive = game.get("alive", [])
	queue_redraw()


func _draw() -> void:
	var px_per_unit := _pixels_per_unit()
	draw_rect(_arena_rect(px_per_unit), ARENA_COLOR)
	draw_rect(_arena_rect(px_per_unit), ARENA_BORDER, false, 2.0)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in players:
		var state: Array = players[slot]
		var center := _to_px(Vector2(state[0], state[1]), px_per_unit)
		var is_alive := slot in alive
		var color := player_color(slot) if is_alive else ELIMINATED_COLOR
		var radius := HotPotato.PLAYER_RADIUS * px_per_unit
		draw_circle(center, radius, color)
		if slot == carrier and is_alive:
			_draw_bomb(center, radius, font, font_size)
		var caption := player_name(slot)
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(
			font,
			center + Vector2(-text_size.x / 2.0, radius + NAME_OFFSET + float(font_size)),
			caption,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size,
			color
		)


func _draw_bomb(center: Vector2, player_radius: float, font: Font, font_size: int) -> void:
	var bomb_radius := player_radius * BOMB_RADIUS_FRACTION
	var bomb_center := center + Vector2(0.0, -player_radius - bomb_radius)
	draw_circle(bomb_center, bomb_radius, BOMB_COLOR)
	var caption := "%.1f" % fuse
	var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(
		font,
		bomb_center + Vector2(-text_size.x / 2.0, -bomb_radius - 4.0),
		caption,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		font_size,
		FUSE_TEXT_COLOR
	)


func _pixels_per_unit() -> float:
	var side := minf(size.x, size.y) - 2.0 * NAME_OFFSET
	return maxf(side, 100.0) / (HotPotato.ARENA_HALF * 2.0)


func _arena_rect(px_per_unit: float) -> Rect2:
	var half := HotPotato.ARENA_HALF * px_per_unit
	var center := size / 2.0
	return Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)


func _to_px(world: Vector2, px_per_unit: float) -> Vector2:
	return size / 2.0 + world * px_per_unit
