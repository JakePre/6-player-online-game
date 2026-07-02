extends MinigameView
## Quick Draw client view (M4-06): shows the wait/signal state, per-player
## win tally, and the last round's outcome. 2D presentation, matching the
## Coin Scramble reference's placeholder style.

const WAITING_COLOR := Color(0.7, 0.15, 0.15)
const LIVE_COLOR := Color(0.2, 0.75, 0.3)
const ROUND_OVER_COLOR := Color(0.35, 0.38, 0.45)
const ROW_HEIGHT := 28.0
const ROW_TOP := 90.0

var _phase: int = QuickDraw.Phase.WAITING
var _round := 0
var _rounds_total := QuickDraw.ROUNDS_TO_PLAY
var _wins := {}
var _false_started := {}
var _winner := -1


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"press": true})


func _render(game: Dictionary) -> void:
	_phase = game.get("phase", QuickDraw.Phase.WAITING)
	_round = game.get("round", 0)
	_rounds_total = game.get("rounds_total", QuickDraw.ROUNDS_TO_PLAY)
	_wins = game.get("wins", {})
	_false_started = game.get("false_started", {})
	_winner = game.get("winner", -1)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var center_x := size.x / 2.0

	_draw_centered(font, font_size * 2, _signal_text(), Vector2(center_x, 40.0), _signal_color())
	_draw_centered(
		font, font_size, "Round %d / %d" % [_round + 1, _rounds_total], Vector2(center_x, 64.0)
	)

	var row := 0
	for slot: int in _wins:
		var caption := (
			"%s  —  %d win%s"
			% [
				player_name(slot),
				int(_wins[slot]),
				"" if int(_wins[slot]) == 1 else "s",
			]
		)
		if _false_started.has(slot):
			caption += "  (false start!)"
		_draw_centered(
			font,
			font_size,
			caption,
			Vector2(center_x, ROW_TOP + row * ROW_HEIGHT),
			player_color(slot)
		)
		row += 1


func _signal_text() -> String:
	match _phase:
		QuickDraw.Phase.WAITING:
			return "WAIT..."
		QuickDraw.Phase.LIVE:
			return "DRAW!"
		_:
			return "%s wins the round!" % player_name(_winner) if _winner != -1 else "No winner"


func _signal_color() -> Color:
	match _phase:
		QuickDraw.Phase.WAITING:
			return WAITING_COLOR
		QuickDraw.Phase.LIVE:
			return LIVE_COLOR
		_:
			return ROUND_OVER_COLOR


func _draw_centered(
	font: Font, font_size: int, text: String, at: Vector2, color: Color = Color.WHITE
) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(
		font,
		at - Vector2(text_size.x / 2.0, 0.0),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		font_size,
		color
	)
