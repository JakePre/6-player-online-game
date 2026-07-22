extends MinigameView
## Heist Night client view (M4-16): arena that dims when the lights cycle
## off (player positions vanish from the snapshot — sneak!), vaults with
## coin totals, and the post-round theft reveal.
## M13-27 FX pass (2D juice per PHASE2.md §7): a scanline sweeps the
## blueprint while the feed is live, and a vault being robbed pulses.

## Deliberate security-blueprint look (#210, PHASE2.md §7 — intentionally
## 2D): cyan linework on navy, survey grid, vaults as outlined rooms.
const ARENA_COLOR := Color(0.07, 0.11, 0.2)
const ARENA_DARK := Color(0.02, 0.03, 0.06)
const BLUEPRINT_LINE := Color(0.35, 0.75, 0.95, 0.85)
const BLUEPRINT_GRID := Color(0.35, 0.75, 0.95, 0.14)
const BLUEPRINT_GRID_DARK := Color(0.35, 0.75, 0.95, 0.05)
const COIN_COLOR := Color(1.0, 0.85, 0.25)
const VAULT_FILL := Color(0.12, 0.2, 0.34)
## The warm aura painted behind a player caught in a vault's glow during the
## dark phase (#806), so the reveal reads as "lit by the vault", not a full blip.
const VAULT_GLOW := Color(1.0, 0.9, 0.5)
const GRID_STEP := 2.0
const NAME_OFFSET := 14.0
const ALARM_COLOR := Color(0.95, 0.3, 0.3)
const SCAN_PERIOD_SEC := 6.0
const PULSE_DURATION := 0.7
## Radiating scan lines (#1134): a few faint spokes from arena center, slowly
## rotating, alongside the existing horizontal scanline sweep.
const RADIAL_SCAN_COUNT := 4
const RADIAL_SCAN_SPEED := 0.15
const RADIAL_SCAN_COLOR := Color(0.35, 0.75, 0.95, 0.1)
## Vault door wedge (#1134): while a robbery pulse plays, an arc "door" swings
## open across the vault's own outline instead of just the alarm ring.
const VAULT_DOOR_COLOR := Color(0.95, 0.3, 0.3, 0.8)
## #930: the board used to center on the full viewport, so its top vaults
## clipped under the match-chrome header. Reuses the 3D views' named chrome
## clearance (#924) even though this view is 2D — it's the same header.
const CHROME_CLEARANCE_Y := MinigameView3D.CHROME_CLEARANCE_Y

## Latest replicated state, straight from HeistNight.get_snapshot().
var dark := false
var players := {}
var vaults := {}
var coins: Array = []
var reveal := {}

# M13-27 FX state: in-flight steal pulses ({slot, age}), last-seen vault
# totals for theft detection, and the scanline clock.
var _pulses: Array = []
var _totals_edges := EdgeTracker.new()
var _scan_clock := 0.0


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(delta: float) -> void:
	var alive: Array = []
	for pulse: Dictionary in _pulses:
		pulse.age += delta
		if pulse.age < PULSE_DURATION:
			alive.append(pulse)
	_pulses = alive
	# The scanline only sweeps while the feed is live; "FEED LOST" freezes it.
	if not dark:
		_scan_clock += delta
	if not dark or not _pulses.is_empty():
		queue_redraw()


func _render(game: Dictionary) -> void:
	dark = bool(game.get("dark", false))
	players = game.get("players", {})
	vaults = game.get("vaults", {})
	coins = game.get("coins", [])
	reveal = game.get("reveal", {})
	# Steal pulse (M13-27): only theft makes a vault total drop, so a drop
	# means a robbery in progress. First sighting seeds silently.
	for slot: int in vaults:
		var total := int(vaults[slot][HeistNight.VT_COINS])
		var before := int(_totals_edges.peek(slot, total))
		if total < before:
			_pulses.append({"slot": slot, "age": 0.0})
			# Getting robbed is heard only by the victim (M12-02). Signature
			# cue (#728): `alarm` — the FX above is already called the
			# "alarm ring" (M13-27); the sound now matches, and the shared
			# meaning ("exposure, suspicion") fits a robbery in progress.
			if slot == my_slot:
				play_sfx(&"alarm")
		elif total > before and slot == my_slot:
			# Signature cue (#728): banking a pickup, heard only by us.
			play_sfx(&"coin")
		_totals_edges.changed(slot, total)
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
	# Scanline sweep (M13-27): the live feed reads as a slow scan down the
	# blueprint, with a short fading trail. Gone while the feed is cut.
	if not dark:
		var scan_y := arena.position.y + fmod(_scan_clock / SCAN_PERIOD_SEC, 1.0) * arena.size.y
		for i in 4:
			var trail_y := scan_y - float(i) * 3.0
			if trail_y < arena.position.y:
				break
			var alpha := 0.4 * (1.0 - float(i) / 4.0)
			draw_line(
				Vector2(arena.position.x, trail_y),
				Vector2(arena.end.x, trail_y),
				Color(BLUEPRINT_LINE, alpha),
				2.0 if i == 0 else 1.0
			)
			# Radiating scan spokes (#1134): a few faint lines from center,
			# slowly rotating — a second read on "this feed is live" beyond
			# the horizontal sweep.
			var spoke_center := arena.position + arena.size / 2.0
			var reach := arena.size.length() / 2.0
			for r in RADIAL_SCAN_COUNT:
				var angle := (
					TAU * float(r) / float(RADIAL_SCAN_COUNT) + _scan_clock * RADIAL_SCAN_SPEED
				)
				draw_line(
					spoke_center,
					spoke_center + Vector2(cos(angle), sin(angle)) * reach,
					RADIAL_SCAN_COLOR,
					1.0
				)
	# Steal pulses (M13-27): an expanding alarm ring, plus a door wedge
	# swinging open across the vault outline (#1134).
	for pulse: Dictionary in _pulses:
		if not vaults.has(pulse.slot):
			continue
		var vault_state: Array = vaults[pulse.slot]
		var center := _to_px(
			Vector2(vault_state[HeistNight.VT_X], vault_state[HeistNight.VT_Y]), px_per_unit
		)
		var progress: float = pulse.age / PULSE_DURATION
		var ring_radius := HeistNight.VAULT_RADIUS * px_per_unit * (1.0 + progress)
		var ring_color := Color(ALARM_COLOR, 1.0 - progress)
		draw_arc(center, ring_radius, 0.0, TAU, 32, ring_color, 1.0 + 2.0 * (1.0 - progress))
		var door_sweep := progress * PI * 0.6
		draw_arc(
			center,
			HeistNight.VAULT_RADIUS * px_per_unit * 0.82,
			-door_sweep / 2.0,
			door_sweep / 2.0,
			16,
			Color(VAULT_DOOR_COLOR, VAULT_DOOR_COLOR.a * (1.0 - progress)),
			3.0
		)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for slot: int in vaults:
		var state: Array = vaults[slot]
		var pos := _to_px(Vector2(state[HeistNight.VT_X], state[HeistNight.VT_Y]), px_per_unit)
		# Vaults read as blueprint rooms: filled, double-outlined in the
		# owner's color, coin total front and center.
		var vault_radius := HeistNight.VAULT_RADIUS * px_per_unit
		draw_circle(pos, vault_radius, VAULT_FILL)
		draw_circle(pos, vault_radius, player_color(slot), false, 2.5)
		draw_circle(pos, vault_radius * 0.82, BLUEPRINT_LINE, false, 1.0)
		var label := "%s: %d" % [player_name(slot), int(state[HeistNight.VT_COINS])]
		# Vault totals must stay readable through the dark phase (#177): a
		# black outline under every label, and darker palette colors lifted
		# toward white while the lights are out.
		var label_color := player_color(slot)
		if dark:
			label_color = label_color.lerp(Color.WHITE, 0.6)
		# Center on the vault by the label's true width and draw unbounded, so a
		# two-digit total is never clipped against a fixed box (#806).
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var label_pos := pos + Vector2(-label_width / 2.0, 4.0)
		draw_string_outline(
			font,
			label_pos,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			6,
			Color(0.0, 0.0, 0.0, 0.9)
		)
		draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
	for coin: Array in coins:
		var coin_px := _to_px(Vector2(coin[HeistNight.CN_X], coin[HeistNight.CN_Y]), px_per_unit)
		draw_circle(coin_px, 0.34 * px_per_unit, COIN_COLOR)
		draw_circle(coin_px, 0.34 * px_per_unit, Color(0.4, 0.3, 0.05), false, 1.5)
	for slot: int in players:
		var state: Array = players[slot]
		var pos := _to_px(Vector2(state[HeistNight.PS_X], state[HeistNight.PS_Y]), px_per_unit)
		var color := player_color(slot)
		# In the dark, the only players in the snapshot are the ones standing in a
		# vault's glow (#806): a soft gold aura sells "caught in the vault light"
		# rather than looking like the radar came back on.
		if dark:
			draw_circle(pos, HeistNight.PLAYER_RADIUS * px_per_unit * 2.4, Color(VAULT_GLOW, 0.3))
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
		# #930: sits below the chrome header, not under it.
		var banner_pos := Vector2((size.x - banner_size.x) / 2.0, CHROME_CLEARANCE_Y + 16.0)
		draw_string_outline(
			font,
			banner_pos,
			banner,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			6,
			Color(0, 0, 0, 0.9)
		)
		draw_string(
			font, banner_pos, banner, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, BLUEPRINT_LINE
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
				# #930: below the chrome header, not under it.
				Vector2(size.x / 2.0 - 110.0, CHROME_CLEARANCE_Y + 34.0 + row * 18.0),
				line,
				HORIZONTAL_ALIGNMENT_CENTER,
				220,
				font_size,
				player_color(thief)
			)
			row += 1


## Center of the board, offset down so it renders in the viewport below the
## chrome header instead of centering on the full viewport (#930).
func _board_center() -> Vector2:
	return Vector2(size.x / 2.0, CHROME_CLEARANCE_Y + (size.y - CHROME_CLEARANCE_Y) / 2.0)


func _pixels_per_unit() -> float:
	var usable_height := size.y - CHROME_CLEARANCE_Y
	var side := minf(size.x, usable_height) - 2.0 * NAME_OFFSET
	return maxf(side, 100.0) / (HeistNight.ARENA_HALF * 2.0)


func _arena_rect(px_per_unit: float) -> Rect2:
	var half := HeistNight.ARENA_HALF * px_per_unit
	return Rect2(_board_center() - Vector2(half, half), Vector2(half, half) * 2.0)


func _to_px(world: Vector2, px_per_unit: float) -> Vector2:
	return _board_center() + world * px_per_unit
