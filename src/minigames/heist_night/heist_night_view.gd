extends MinigameView
## Heist Night client view (M4-16): arena that dims when the lights cycle
## off (player positions vanish from the snapshot — sneak!), vaults with
## coin totals, and the post-round theft reveal.

const ARENA_COLOR := Color(0.13, 0.15, 0.19)
const ARENA_DARK := Color(0.05, 0.05, 0.08)
const ARENA_BORDER := Color(0.35, 0.38, 0.45)
const COIN_COLOR := Color(0.96, 0.79, 0.2)
const VAULT_COLOR := Color(0.3, 0.32, 0.4)
const NAME_OFFSET := 14.0

## Latest replicated state, straight from HeistNight.get_snapshot().
var dark := false
var players := {}
var vaults := {}
var coins: Array = []
var reveal := {}


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _render(game: Dictionary) -> void:
	dark = bool(game.get("dark", false))
	players = game.get("players", {})
	vaults = game.get("vaults", {})
	coins = game.get("coins", [])
	reveal = game.get("reveal", {})
	queue_redraw()


func _draw() -> void:
	var px_per_unit := _pixels_per_unit()
	draw_rect(_arena_rect(px_per_unit), ARENA_DARK if dark else ARENA_COLOR)
	draw_rect(_arena_rect(px_per_unit), ARENA_BORDER, false, 2.0)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in vaults:
		var state: Array = vaults[slot]
		var pos := _to_px(Vector2(state[0], state[1]), px_per_unit)
		draw_circle(pos, HeistNight.VAULT_RADIUS * px_per_unit, VAULT_COLOR)
		draw_string(
			font,
			pos + Vector2(-20.0, 4.0),
			"%s: %d" % [player_name(slot), int(state[2])],
			HORIZONTAL_ALIGNMENT_CENTER,
			40,
			font_size,
			player_color(slot)
		)
	for coin: Array in coins:
		draw_circle(_to_px(Vector2(coin[0], coin[1]), px_per_unit), 0.3 * px_per_unit, COIN_COLOR)
	for slot: int in players:
		var state: Array = players[slot]
		var pos := _to_px(Vector2(state[0], state[1]), px_per_unit)
		var color := player_color(slot)
		draw_circle(pos, HeistNight.PLAYER_RADIUS * px_per_unit, color)
		draw_string(
			font,
			pos + Vector2(-30.0, -HeistNight.PLAYER_RADIUS * px_per_unit - 4.0),
			player_name(slot),
			HORIZONTAL_ALIGNMENT_CENTER,
			60,
			font_size,
			color
		)
	if dark:
		draw_string(
			font,
			Vector2(size.x / 2.0 - 80.0, 24.0),
			"LIGHTS OUT — go rob someone!",
			HORIZONTAL_ALIGNMENT_CENTER,
			160,
			font_size
		)
	_draw_reveal(font, font_size)


func _draw_reveal(font: Font, font_size: int) -> void:
	if reveal.is_empty():
		return
	var row := 0
	for thief: int in reveal:
		for victim: int in reveal[thief]:
			var line := (
				"%s robbed %s of %d!"
				% [player_name(thief), player_name(victim), int(reveal[thief][victim])]
			)
			draw_string(
				font,
				Vector2(size.x / 2.0 - 110.0, 44.0 + row * 18.0),
				line,
				HORIZONTAL_ALIGNMENT_CENTER,
				220,
				font_size,
				player_color(thief)
			)
			row += 1


func _pixels_per_unit() -> float:
	var side := minf(size.x, size.y) - 2.0 * NAME_OFFSET
	return maxf(side, 100.0) / (HeistNight.ARENA_HALF * 2.0)


func _arena_rect(px_per_unit: float) -> Rect2:
	var half := HeistNight.ARENA_HALF * px_per_unit
	return Rect2(size / 2.0 - Vector2(half, half), Vector2(half, half) * 2.0)


func _to_px(world: Vector2, px_per_unit: float) -> Vector2:
	return size / 2.0 + world * px_per_unit
