extends MinigameView
## Heist Night client view (M4-16): arena that dims when the lights cycle
## off (player positions vanish from the snapshot — sneak!), vaults with
## coin totals, and the post-round theft reveal.

## Deliberate security-blueprint look (#210, PHASE2.md §7 — intentionally
## 2D): cyan linework on navy, survey grid, vaults as outlined rooms.
const ARENA_COLOR := Color(0.07, 0.11, 0.2)
const ARENA_DARK := Color(0.02, 0.03, 0.06)
const BLUEPRINT_LINE := Color(0.35, 0.75, 0.95, 0.85)
const BLUEPRINT_GRID := Color(0.35, 0.75, 0.95, 0.14)
const BLUEPRINT_GRID_DARK := Color(0.35, 0.75, 0.95, 0.05)
const COIN_COLOR := Color(1.0, 0.85, 0.25)
const VAULT_FILL := Color(0.12, 0.2, 0.34)
const GRID_STEP := 2.0
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
	var arena := _arena_rect(px_per_unit)
	draw_rect(arena, ARENA_DARK if dark else ARENA_COLOR)
	# Survey grid: the blueprint bones. It stays faintly alive in the dark —
	# the feed is cut, the floor plan isn't.
	var grid := BLUEPRINT_GRID_DARK if dark else BLUEPRINT_GRID
	var step := GRID_STEP * px_per_unit
	var gx := arena.position.x
	while gx <= arena.end.x + 0.5:
		draw_line(Vector2(gx, arena.position.y), Vector2(gx, arena.end.y), grid, 1.0)
		gx += step
	var gy := arena.position.y
	while gy <= arena.end.y + 0.5:
		draw_line(Vector2(arena.position.x, gy), Vector2(arena.end.x, gy), grid, 1.0)
		gy += step
	draw_rect(arena, BLUEPRINT_LINE, false, 2.0)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in vaults:
		var state: Array = vaults[slot]
		var pos := _to_px(Vector2(state[0], state[1]), px_per_unit)
		# Vaults read as blueprint rooms: filled, double-outlined in the
		# owner's color, coin total front and center.
		var vault_radius := HeistNight.VAULT_RADIUS * px_per_unit
		draw_circle(pos, vault_radius, VAULT_FILL)
		draw_circle(pos, vault_radius, player_color(slot), false, 2.5)
		draw_circle(pos, vault_radius * 0.82, BLUEPRINT_LINE, false, 1.0)
		var label := "%s: %d" % [player_name(slot), int(state[2])]
		# Vault totals must stay readable through the dark phase (#177): a
		# black outline under every label, and darker palette colors lifted
		# toward white while the lights are out.
		var label_color := player_color(slot)
		if dark:
			label_color = label_color.lerp(Color.WHITE, 0.6)
		draw_string_outline(
			font,
			pos + Vector2(-20.0, 4.0),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			40,
			font_size,
			6,
			Color(0.0, 0.0, 0.0, 0.9)
		)
		draw_string(
			font,
			pos + Vector2(-20.0, 4.0),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			40,
			font_size,
			label_color
		)
	for coin: Array in coins:
		var coin_px := _to_px(Vector2(coin[0], coin[1]), px_per_unit)
		draw_circle(coin_px, 0.34 * px_per_unit, COIN_COLOR)
		draw_circle(coin_px, 0.34 * px_per_unit, Color(0.4, 0.3, 0.05), false, 1.5)
	for slot: int in players:
		var state: Array = players[slot]
		var pos := _to_px(Vector2(state[0], state[1]), px_per_unit)
		var color := player_color(slot)
		# Players are radar blips: solid dot + halo ring.
		draw_circle(pos, HeistNight.PLAYER_RADIUS * px_per_unit, color)
		draw_circle(
			pos,
			HeistNight.PLAYER_RADIUS * px_per_unit * 1.6,
			color * Color(1, 1, 1, 0.35),
			false,
			1.5
		)
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
		var banner := "◼ FEED LOST — LIGHTS OUT — go rob someone! ◼"
		var banner_size := font.get_string_size(banner, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string_outline(
			font,
			Vector2((size.x - banner_size.x) / 2.0, 26.0),
			banner,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			6,
			Color(0, 0, 0, 0.9)
		)
		draw_string(
			font,
			Vector2((size.x - banner_size.x) / 2.0, 26.0),
			banner,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			BLUEPRINT_LINE
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
