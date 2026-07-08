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


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _unhandled_input(event: InputEvent) -> void:
	# Only the guard acts; a stray press from a thief is harmless (the server
	# ignores non-guard `act`), so we don't gate on role here.
	if not event.is_action_pressed(&"action_primary"):
		return
	if NetManager.multiplayer.multiplayer_peer == null:
		return
	NetManager.send_match_input({"act": true})


func _process(delta: float) -> void:
	var alive: Array = []
	for pulse: Dictionary in _pulses:
		pulse.age += delta
		if pulse.age < 1.0:
			alive.append(pulse)
	_pulses = alive
	if not _pulses.is_empty():
		queue_redraw()


func _render(game: Dictionary) -> void:
	crowd = game.get("crowd", [])
	thieves = game.get("thieves", {})
	guard = int(game.get("guard", -1))
	scores = game.get("scores", {})
	alarm = bool(game.get("alarm", false))
	time_left = float(game.get("time_left", 0.0))
	reveal = game.get("reveal", {})
	# An arrest is a public commotion (rising edge): a ring where the guard is.
	if alarm and not _alarm_seen:
		var body := _guard_body_index()
		if body >= 0 and body < crowd.size():
			_pulses.append({"pos": _vec(crowd[body]), "age": 0.0})
		# Signature cue (#728): an arrest is exposure/suspicion — exactly
		# docs/AUDIO_GUIDE.md's shared `alarm` meaning, not a generic error.
		play_sfx(&"alarm")
	_alarm_seen = alarm
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
	var step := GRID_STEP * px
	var gx := arena.position.x
	while gx <= arena.end.x + 0.5:
		draw_line(Vector2(gx, arena.position.y), Vector2(gx, arena.end.y), COBBLE_GRID, 1.0)
		gx += step
	var gy := arena.position.y
	while gy <= arena.end.y + 0.5:
		draw_line(Vector2(arena.position.x, gy), Vector2(arena.end.x, gy), COBBLE_GRID, 1.0)
		gy += step
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

	# The crowd — every villager identical. The one exception is purely local:
	# the guard's own client rings the body it controls (or the reveal marks it
	# for everyone at the end). Nothing about this rides the shared snapshot.
	for i in crowd.size():
		var pos := _to_px(_vec(crowd[i]), px)
		draw_circle(pos, 0.42 * px, VILLAGER_BODY)
		draw_circle(pos, 0.24 * px, VILLAGER_HEAD)
		draw_circle(pos, 0.42 * px, Color(0.2, 0.17, 0.13), false, 1.5)
		if i == my_body:
			var mark := GUARD_MARK if reveal.is_empty() else ALARM_COLOR
			draw_arc(pos, 0.6 * px, 0.0, TAU, 28, mark, 2.5)
			var tag := "YOU" if reveal.is_empty() else "GUARD"
			_label(font, font_size, pos + Vector2(0.0, -0.9 * px), tag, mark)

	# The thieves — colored blips, suspects flagged (a thief on the hook glows),
	# the stunned slumped and dimmed.
	for slot_key: Variant in thieves:
		var slot := int(slot_key)
		var state: Array = thieves[slot_key]
		var pos := _to_px(Vector2(float(state[0]), float(state[1])), px)
		var stunned := int(state[2]) == 1
		var suspect := int(state[3]) == 1
		var color := player_color(slot)
		if stunned:
			color = color.darkened(0.5)
		if suspect and not stunned:
			draw_arc(pos, 0.62 * px, 0.0, TAU, 28, SUSPECT_COLOR, 2.5)
		draw_circle(pos, PickpocketPlaza.PLAYER_RADIUS * px, color)
		draw_circle(pos, PickpocketPlaza.PLAYER_RADIUS * px, Color(0, 0, 0, 0.55), false, 1.5)
		if stunned:
			# A little X for "caught".
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
	return Vector2(float(pair[0]), float(pair[1]))
