extends MinigameView
## Pickpocket Plaza client view (M10-14): a top-down plaza (intentionally 2D,
## like Heist Night / Trap Corridor) of identical wandering villagers, the
## thieves' colored blips working the crowd, and the arrest commotion.
##
## The guard's disguise is the load-bearing secret: every crowd body draws
## identically for everyone. Only the local guard's client — reading its own
## private_state (#254) — rings the body it controls, so the guard knows who
## they are without ever leaking it into the shared snapshot. The end reveal
## finally marks the guard body for the whole table.

## Declarative button input (#947): only the guard acts; a stray press from a
## thief is harmless (the server ignores non-guard `act`), so no role gate here.
const INPUT_ACTIONS := {&"action_primary": "act"}
const ARENA_COLOR := Color(0.16, 0.14, 0.11)
const COBBLE_GRID := Color(0.32, 0.28, 0.22, 0.35)
const PLAZA_LINE := Color(0.55, 0.48, 0.36, 0.9)
const VILLAGER_BODY := Color(0.62, 0.6, 0.56)
const VILLAGER_HEAD := Color(0.74, 0.66, 0.55)
const SUSPECT_COLOR := Color(0.98, 0.78, 0.2)
const ALARM_COLOR := Color(0.95, 0.3, 0.25)
const GUARD_MARK := Color(0.3, 0.8, 0.95)
const GRID_STEP := 2.0
const NAME_OFFSET := 14.0
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.2)
const HAT_COLOR := Color(0.8, 0.5, 0.2, 0.9)
const HAT_TIP_COLOR := Color(0.9, 0.6, 0.3)
const BUILDING_WALL := Color(0.28, 0.24, 0.18)
const BUILDING_ROOF := Color(0.35, 0.3, 0.22)
const BUILDING_DOOR := Color(0.5, 0.35, 0.2)
const BUILDING_WINDOW := Color(0.6, 0.7, 0.8, 0.4)
const LIFT_INDICATOR_COLOR := Color(0.98, 0.78, 0.2, 0.6)
const LIFT_INDICATOR_EMPTY := Color(0.98, 0.78, 0.2, 0.15)
const PUFF_COLOR := Color(0.7, 0.65, 0.6, 0.5)
const CROWD_VARIATION := 0.08
const JITTER_AMPLITUDE := 0.08
const JITTER_HZ := 1.2

## Latest replicated state, straight from PickpocketPlaza.get_snapshot().
var crowd: Array = []
var thieves := {}
var guard := -1
var scores := {}
var alarm := false
var time_left := 0.0
var reveal := {}

# FX state: arrest-commotion pulses, a one-shot reveal latch, and the local
# player's last-seen loot (for the pickpocket "cha-ching").
var _pulses: Array = []
var _alarm_seen := false
var _revealed := false
var _my_loot_seen := -1
var _anim_clock := 0.0
var _puffs: Array = []
var _crowd_phases: Array = []
var _last_crowd_size := 0


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _process(delta: float) -> void:
	_anim_clock += delta
	var alive: Array = []
	for pulse: Dictionary in _pulses:
		pulse.age += delta
		if pulse.age < 1.0:
			alive.append(pulse)
	_pulses = alive
	var puff_alive: Array = []
	for puff: Dictionary in _puffs:
		puff.age += delta
		if puff.age < 0.6:
			puff_alive.append(puff)
	_puffs = puff_alive
	if not _pulses.is_empty() or not _puffs.is_empty() or not crowd.is_empty():
		queue_redraw()


func _render(game: Dictionary) -> void:
	crowd = game.get("crowd", [])
	thieves = game.get("thieves", {})
	guard = int(game.get("guard", -1))
	scores = game.get("scores", {})
	alarm = bool(game.get("alarm", false))
	time_left = float(game.get("time_left", 0.0))
	reveal = game.get("reveal", {})
	# An arrest is a public commotion (rising edge): a ring where the guard is,
	# plus a puff of smoke at the arrest location.
	if alarm and not _alarm_seen:
		var body := _guard_body_index()
		if body >= 0 and body < crowd.size():
			var arrest_pos := _vec(crowd[body])
			_pulses.append({"pos": arrest_pos, "age": 0.0})
			_puffs.append({"pos": arrest_pos, "age": 0.0})
		# Signature cue (#728): an arrest is exposure/suspicion — exactly
		# docs/AUDIO_GUIDE.md's shared `alarm` meaning, not a generic error.
		play_sfx(&"alarm")
	_alarm_seen = alarm
	# Seed crowd animation phases when size changes.
	if crowd.size() != _last_crowd_size:
		_crowd_phases.clear()
		for i in crowd.size():
			_crowd_phases.append(randf() * TAU)
		_last_crowd_size = crowd.size()
	# A successful lift is heard only by the thief who made it (M12-02).
	var my_loot := int(scores.get(my_slot, -1))
	if my_slot != guard and _my_loot_seen >= 0 and my_loot > _my_loot_seen:
		play_sfx(&"coin")
	_my_loot_seen = my_loot
	if not reveal.is_empty() and not _revealed:
		_revealed = true
		play_sfx(&"confirm")
	queue_redraw()


## The body index to highlight locally: my own if I'm the guard (private
## state), or the revealed guard body once the round ends. -1 otherwise —
## a thief's client never learns the disguise mid-round.
func _guard_body_index() -> int:
	if not reveal.is_empty():
		return int(reveal.get("body", -1))
	if private_state.get("role", "") == "guard":
		return int(private_state.get("body", -1))
	return -1


func _draw() -> void:
	var px := _pixels_per_unit()
	var arena := _arena_rect(px)
	draw_rect(arena, ARENA_COLOR)
	_draw_cobblestone_detail(arena, px)
	_draw_buildings(arena, px)
	draw_rect(arena, PLAZA_LINE, false, 2.0)

	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var my_body := _guard_body_index()

	# Arrest commotion rings (expanding, fading).
	for pulse: Dictionary in _pulses:
		var progress: float = pulse.age
		draw_arc(
			pulse.pos,
			(0.8 + progress * 1.6) * px,
			0.0,
			TAU,
			32,
			Color(ALARM_COLOR, 1.0 - progress),
			2.0 + 3.0 * (1.0 - progress)
		)

	# Arrest puff (expanding smoke cloud).
	for puff: Dictionary in _puffs:
		var t: float = puff.age / 0.6
		var puff_radius := (0.3 + t * 1.2) * px
		var puff_alpha := (1.0 - t) * 0.5
		draw_circle(puff.pos, puff_radius, Color(PUFF_COLOR, puff_alpha))
		draw_circle(
			puff.pos + Vector2(0.15, -0.1) * px,
			puff_radius * 0.7,
			Color(PUFF_COLOR, puff_alpha * 0.6)
		)

	# Character shadows under every figure.
	for i in crowd.size():
		var pos := _crowd_pos(i, px)
		_draw_shadow(pos, 0.42 * px)
	for slot_key: Variant in thieves:
		var state: Array = thieves[slot_key]
		var pos := _to_px(
			Vector2(float(state[PickpocketPlaza.TH_X]), float(state[PickpocketPlaza.TH_Y])), px
		)
		_draw_shadow(pos, PickpocketPlaza.PLAYER_RADIUS * px)

	# The crowd — villagers with slight color variation, animated jitter, and hats.
	for i in crowd.size():
		var pos := _crowd_pos(i, px)
		var body_color := _crowd_body_color(i)
		var head_color := _crowd_head_color(i)
		draw_circle(pos, 0.42 * px, body_color)
		draw_circle(pos, 0.24 * px, head_color)
		_draw_villager_hat(pos, px)
		draw_circle(pos, 0.42 * px, Color(0.2, 0.17, 0.13), false, 1.5)
		if i == my_body:
			var mark := GUARD_MARK if reveal.is_empty() else ALARM_COLOR
			draw_arc(pos, 0.6 * px, 0.0, TAU, 28, mark, 2.5)
			var tag := "YOU" if reveal.is_empty() else "GUARD"
			_label(font, font_size, pos + Vector2(0.0, -0.9 * px), tag, mark)

	# The thieves — colored blips, suspects flagged, with lift progress indicator.
	for slot_key: Variant in thieves:
		var slot := int(slot_key)
		var state: Array = thieves[slot_key]
		var pos := _to_px(
			Vector2(float(state[PickpocketPlaza.TH_X]), float(state[PickpocketPlaza.TH_Y])), px
		)
		var stunned := int(state[PickpocketPlaza.TH_STUN]) == 1
		var suspect := int(state[PickpocketPlaza.TH_SUSPECT]) == 1
		var color := player_color(slot)
		if stunned:
			color = color.darkened(0.5)
		# Lift progress indicator: a ring around the thief when near a villager.
		if not stunned and slot != guard:
			_draw_lift_indicator(pos, px)
		if suspect and not stunned:
			draw_arc(pos, 0.62 * px, 0.0, TAU, 28, SUSPECT_COLOR, 2.5)
		draw_circle(pos, PickpocketPlaza.PLAYER_RADIUS * px, color)
		draw_circle(pos, PickpocketPlaza.PLAYER_RADIUS * px, Color(0, 0, 0, 0.55), false, 1.5)
		if stunned:
			var r := 0.3 * px
			draw_line(pos - Vector2(r, r), pos + Vector2(r, r), Color(0, 0, 0, 0.8), 2.0)
			draw_line(pos - Vector2(r, -r), pos + Vector2(r, -r), Color(0, 0, 0, 0.8), 2.0)
		var label := "%s: %d" % [player_name(slot), int(scores.get(slot_key, 0))]
		_label(font, font_size, pos + Vector2(0.0, -0.9 * px), label, color)

	_draw_hud(font, font_size)


func _draw_hud(font: Font, font_size: int) -> void:
	# Local role prompt (private) + who the guard is (public) + clock.
	var role := String(private_state.get("role", ""))
	var prompt := ""
	var prompt_color := Color.WHITE
	if not reveal.is_empty():
		var gslot := int(reveal.get("guard", -1))
		prompt = "The guard was %s!" % player_name(gslot)
		prompt_color = GUARD_MARK
	elif role == "guard":
		prompt = "You are the GUARD — blend in, then arrest a thief (SPACE)"
		prompt_color = GUARD_MARK
	else:
		var my_loot := int(scores.get(my_slot, 0))
		prompt = "Lift coins from the crowd — one villager is the guard!  (loot: %d)" % my_loot
		prompt_color = SUSPECT_COLOR
	_banner(font, font_size, 24.0, prompt, prompt_color)

	if reveal.is_empty() and guard >= 0:
		var who := "Guard: %s (somewhere in the crowd)" % player_name(guard)
		_banner(font, font_size, 44.0, who, Color(0.8, 0.78, 0.72))

	if alarm:
		_banner(font, font_size, size.y - 30.0, "! ARREST !", ALARM_COLOR)


func _banner(font: Font, font_size: int, y: float, text: String, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var pos := Vector2((size.x - width) / 2.0, y)
	draw_string_outline(
		font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.9)
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _label(font: Font, font_size: int, center: Vector2, text: String, color: Color) -> void:
	var pos := center + Vector2(-30.0, 0.0)
	draw_string_outline(
		font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 60, font_size, 5, Color(0, 0, 0, 0.9)
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 60, font_size, color)


func _pixels_per_unit() -> float:
	var side := minf(size.x, size.y) - 2.0 * NAME_OFFSET
	return maxf(side, 100.0) / (PickpocketPlaza.ARENA_HALF * 2.0)


func _arena_rect(px_per_unit: float) -> Rect2:
	var half := PickpocketPlaza.ARENA_HALF * px_per_unit
	return Rect2(size / 2.0 - Vector2(half, half), Vector2(half, half) * 2.0)


func _to_px(world: Vector2, px_per_unit: float) -> Vector2:
	return size / 2.0 + world * px_per_unit


func _vec(pair: Array) -> Vector2:
	return Vector2(float(pair[PickpocketPlaza.CR_X]), float(pair[PickpocketPlaza.CR_Y]))


func _crowd_pos(index: int, px: float) -> Vector2:
	## Villager screen position with per-frame jitter for animated crowd wander.
	var base := _to_px(_vec(crowd[index]), px)
	if index < _crowd_phases.size():
		var phase: float = _crowd_phases[index]
		var jx := sin(_anim_clock * TAU * JITTER_HZ + phase) * JITTER_AMPLITUDE * px
		var jy := cos(_anim_clock * TAU * JITTER_HZ * 0.7 + phase * 1.3) * JITTER_AMPLITUDE * px
		return base + Vector2(jx, jy)
	return base


func _crowd_body_color(index: int) -> Color:
	## Slight color variation per villager so the crowd doesn't read as clones.
	if index < _crowd_phases.size():
		var phase: float = _crowd_phases[index]
		var shift := CROWD_VARIATION * sin(phase * 2.0)
		return Color(
			clampf(VILLAGER_BODY.r + shift, 0.0, 1.0),
			clampf(VILLAGER_BODY.g + shift * 0.5, 0.0, 1.0),
			clampf(VILLAGER_BODY.b - shift * 0.3, 0.0, 1.0)
		)
	return VILLAGER_BODY


func _crowd_head_color(index: int) -> Color:
	## Slight color variation for the head, matching the body shift.
	if index < _crowd_phases.size():
		var phase: float = _crowd_phases[index]
		var shift := CROWD_VARIATION * sin(phase * 2.0 + 1.0)
		return Color(
			clampf(VILLAGER_HEAD.r + shift, 0.0, 1.0),
			clampf(VILLAGER_HEAD.g + shift * 0.3, 0.0, 1.0),
			clampf(VILLAGER_HEAD.b - shift * 0.2, 0.0, 1.0)
		)
	return VILLAGER_HEAD


func _draw_villager_hat(pos: Vector2, px: float) -> void:
	## Small triangle hat on top of the head.
	var tip := pos + Vector2(0.0, -0.42 * px)
	var left := pos + Vector2(-0.15 * px, -0.28 * px)
	var right := pos + Vector2(0.15 * px, -0.28 * px)
	var hat := PackedVector2Array([tip, left, right])
	draw_colored_polygon(hat, HAT_COLOR)
	# Tiny pom-pom at the tip.
	draw_circle(tip, 0.04 * px, HAT_TIP_COLOR)


func _draw_shadow(pos: Vector2, radius: float) -> void:
	## Small dark ellipse under the figure, offset slightly down-right.
	var shadow_pos := pos + Vector2(0.06 * radius, 0.08 * radius)
	draw_circle(shadow_pos, radius * 0.85, SHADOW_COLOR)


func _draw_cobblestone_detail(arena: Rect2, px: float) -> void:
	## Enhanced cobblestone pattern: larger primary stones with smaller infill.
	var step := GRID_STEP * px
	# Vertical lines — main grid lines.
	var gx := arena.position.x
	while gx <= arena.end.x + 0.5:
		draw_line(Vector2(gx, arena.position.y), Vector2(gx, arena.end.y), COBBLE_GRID, 1.0)
		gx += step
	# Horizontal lines — main grid lines.
	var gy := arena.position.y
	while gy <= arena.end.y + 0.5:
		draw_line(Vector2(arena.position.x, gy), Vector2(arena.end.x, gy), COBBLE_GRID, 1.0)
		gy += step
	# Detail: diagonal hatches in alternating tiles for a stone-block look.
	var half_step := step * 0.5
	var detail_color := Color(COBBLE_GRID, COBBLE_GRID.a * 0.5)
	gx = arena.position.x
	while gx < arena.end.x:
		gy = arena.position.y
		while gy < arena.end.y:
			var col := int((gx - arena.position.x) / step)
			var row := int((gy - arena.position.y) / step)
			if (col + row) % 2 == 0:
				var cx := gx + half_step
				var cy := gy + half_step
				draw_line(
					Vector2(cx - half_step * 0.3, cy - half_step * 0.3),
					Vector2(cx + half_step * 0.3, cy + half_step * 0.3),
					detail_color,
					1.0
				)
				draw_line(
					Vector2(cx + half_step * 0.3, cy - half_step * 0.3),
					Vector2(cx - half_step * 0.3, cy + half_step * 0.3),
					detail_color,
					1.0
				)
			gy += step
		gx += step


func _draw_buildings(arena: Rect2, px: float) -> void:
	## Building footprints around the plaza perimeter: simple rectangles with
	## door markers and windows, grounding the plaza setting.
	var half := PickpocketPlaza.ARENA_HALF * px
	var margin := 0.3 * px
	var bld_w := 1.0 * px
	var bld_d := 0.6 * px
	# Four buildings: one on each side of the plaza arena.
	var configs := [
		# Top building (north)
		{
			"x": arena.position.x - bld_w,
			"y": arena.position.y - bld_d - margin,
			"w": bld_w,
			"h": bld_d,
		},
		# Bottom building (south)
		{
			"x": arena.end.x,
			"y": arena.end.y + margin,
			"w": bld_w,
			"h": bld_d,
		},
		# Left building (west)
		{
			"x": arena.position.x - bld_d - margin,
			"y": arena.position.y,
			"w": bld_d,
			"h": bld_w * 0.8,
		},
		# Right building (east)
		{
			"x": arena.end.x + margin,
			"y": arena.position.y,
			"w": bld_d,
			"h": bld_w * 0.8,
		},
	]
	for cfg: Dictionary in configs:
		var rect := Rect2(cfg.x, cfg.y, cfg.w, cfg.h)
		draw_rect(rect, BUILDING_WALL)
		draw_rect(rect, BUILDING_ROOF, false, 2.0)
		# Door marker: a small rectangle in the center-bottom of the building face.
		var door_w := rect.size.x * 0.3
		var door_h := rect.size.y * 0.5
		var door_rect := Rect2(
			rect.position.x + (rect.size.x - door_w) / 2.0,
			rect.position.y + rect.size.y - door_h,
			door_w,
			door_h
		)
		draw_rect(door_rect, BUILDING_DOOR)
		# Window: a small square above the door.
		var win_sz := rect.size.x * 0.2
		var win_rect := Rect2(
			rect.position.x + (rect.size.x - win_sz) / 2.0,
			rect.position.y + rect.size.y * 0.2,
			win_sz,
			win_sz
		)
		draw_rect(win_rect, BUILDING_WINDOW)


func _draw_lift_indicator(pos: Vector2, px: float) -> void:
	## Progress ring around a thief who is near a liftable villager.
	## Checks proximity to each crowd body; shows a pulsing ring if in range.
	var in_range := false
	for i in crowd.size():
		var cpos := _crowd_pos(i, px)
		if pos.distance_to(cpos) <= PickpocketPlaza.PICKPOCKET_RADIUS * px:
			in_range = true
			break
	if not in_range:
		return
	# Pulsing ring: the arc angle grows with the animation clock to suggest
	# progress over time.
	var pulse := 0.5 + 0.5 * sin(_anim_clock * TAU * 1.5)
	var radius := PickpocketPlaza.PLAYER_RADIUS * px * 1.8
	var thickness := 2.0 + pulse * 2.0
	var fill_color := LIFT_INDICATOR_COLOR
	fill_color.a = LIFT_INDICATOR_COLOR.a * (0.3 + 0.7 * pulse)
	draw_arc(pos, radius, 0.0, TAU, 24, fill_color, thickness)
	# Inner subtle ring as a backing.
	draw_arc(pos, radius, 0.0, TAU, 24, LIFT_INDICATOR_EMPTY, 1.5)
