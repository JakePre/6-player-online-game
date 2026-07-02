extends MinigameView
## Color Clash client view (M4-13): the tile grid painted in faction colors
## with players and names on top. Faction color is the painter's palette
## color in FFA and the first teammate's palette color in team play.

const UNPAINTED_COLOR := Color(0.16, 0.17, 0.2)
const GRID_LINE := Color(0.1, 0.1, 0.12)
const NAME_OFFSET := 14.0

## Latest replicated state, straight from ColorClash.get_snapshot().
var players := {}
var grid: Array = []
var teams: Array = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _render(game: Dictionary) -> void:
	players = game.get("players", {})
	grid = game.get("grid", [])
	teams = game.get("teams", [])
	queue_redraw()


func _draw() -> void:
	var px_per_unit := _pixels_per_unit()
	var tile_px := ColorClash.TILE_WORLD * px_per_unit
	var origin := size / 2.0 - Vector2.ONE * ColorClash.ARENA_HALF * px_per_unit
	for i in grid.size():
		var row := i / ColorClash.GRID_SIZE
		var col := i % ColorClash.GRID_SIZE
		var rect := Rect2(origin + Vector2(col, row) * tile_px, Vector2(tile_px, tile_px))
		draw_rect(rect, _faction_color(int(grid[i])))
		draw_rect(rect, GRID_LINE, false, 1.0)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in players:
		var state: Array = players[slot]
		var pos := size / 2.0 + Vector2(state[0], state[1]) * px_per_unit
		var color := player_color(slot)
		var radius := ColorClash.PLAYER_RADIUS * px_per_unit
		draw_circle(pos, radius, color)
		draw_circle(pos, radius, Color.BLACK, false, 1.5)
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


func _faction_color(faction: int) -> Color:
	if faction == ColorClash.UNPAINTED:
		return UNPAINTED_COLOR
	if faction < teams.size() and not teams[faction].is_empty():
		return player_color(int(teams[faction][0])).darkened(0.15)
	return player_color(faction).darkened(0.15)


func _pixels_per_unit() -> float:
	var side := minf(size.x, size.y) - 2.0 * NAME_OFFSET
	return maxf(side, 100.0) / (ColorClash.ARENA_HALF * 2.0)
