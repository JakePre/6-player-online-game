extends MinigameView
## Thin Ice client view (M4-03): top-down tile grid colored by damage state,
## palette-colored players on top. Forwards the shared WASD/stick move
## intent. Same 2D presentation tier as the Sumo Smash reference view.

const INTACT_COLOR := Color(0.55, 0.78, 0.95)
const CRACKED_COLOR := Color(0.75, 0.68, 0.55)
const GONE_COLOR := Color(0.05, 0.05, 0.08)
const GRID_LINE := Color(0.2, 0.3, 0.4, 0.6)
const NAME_OFFSET := 14.0

## Latest replicated state, straight from ThinIce.get_snapshot().
var tiles: Array = []
var players := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _render(game: Dictionary) -> void:
	tiles = game.get("tiles", [])
	players = game.get("players", {})
	queue_redraw()


func _draw() -> void:
	var px_per_unit := _pixels_per_unit()
	var origin := size / 2.0 - Vector2.ONE * ThinIce.HALF_EXTENT * px_per_unit
	var tile_px := ThinIce.TILE_SIZE * px_per_unit
	for y in ThinIce.GRID_SIZE:
		for x in ThinIce.GRID_SIZE:
			var idx := y * ThinIce.GRID_SIZE + x
			var state: int = tiles[idx] if idx < tiles.size() else ThinIce.TileState.INTACT
			var color := INTACT_COLOR
			if state == ThinIce.TileState.CRACKED:
				color = CRACKED_COLOR
			elif state == ThinIce.TileState.GONE:
				color = GONE_COLOR
			var rect := Rect2(origin + Vector2(x, y) * tile_px, Vector2.ONE * tile_px)
			draw_rect(rect, color)
			draw_rect(rect, GRID_LINE, false, 1.0)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in players:
		var state: Array = players[slot]
		var pos := (
			origin + (Vector2(state[0], state[1]) + Vector2.ONE * ThinIce.HALF_EXTENT) * px_per_unit
		)
		var color := player_color(slot)
		var radius := ThinIce.PLAYER_RADIUS * px_per_unit
		draw_circle(pos, radius, color)
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
	return maxf(side, 100.0) / (ThinIce.HALF_EXTENT * 2.0)
