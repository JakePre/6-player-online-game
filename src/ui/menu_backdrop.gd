class_name MenuBackdrop
extends Control
## Animated menu backdrop (M16-03): a dark blue-slate vertical gradient with a
## field of slow-drifting gold "coin" bokeh discs and the odd sparkle — the
## title screen's ambient motion. Pure `_draw`, no art dependency, so it never
## blocks on an image request. Reusable behind any full-screen menu surface.
##
## Reduced-motion (M12-03 / STYLE_GUIDE motion rules): when `ArenaFX.reduced_motion`
## is set the drift is frozen — the field is populated once and drawn static,
## and `_process` does no work. The gradient and discs still render, just still.

## Coin/bokeh disc count scales a little with area; this is the density at the
## design resolution (1280x720) and the cap.
const DISC_COUNT := 26
const SPARKLE_COUNT := 14
## Vertical drift speed range (px/sec) — deliberately slow (ambient, not busy).
const DRIFT_MIN := 6.0
const DRIFT_MAX := 18.0
## Horizontal sway amplitude (px) and period (sec) per disc.
const SWAY_AMP := 24.0
## Disc radius range (px).
const DISC_MIN_R := 10.0
const DISC_MAX_R := 46.0

## Discs: {x, y, r, speed, phase, sway_period, alpha}. `x` is the sway centre.
var _discs: Array[Dictionary] = []
## Sparkles: {x, y, r, twinkle_phase, twinkle_speed}.
var _sparkles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _populated := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Deterministic enough to look organic; seeded so tests are stable.
	_rng.seed = 0xC0FFEE
	resized.connect(_on_resized)
	_populate()
	# Static field under reduced motion: skip the per-frame advance entirely.
	set_process(not ArenaFX.reduced_motion)


func _on_resized() -> void:
	if _populated:
		_populate()


func _process(delta: float) -> void:
	_clock += delta
	_advance(delta)
	queue_redraw()


## Drift every disc upward, wrapping it back to just below the bottom edge once
## it clears the top. Sparkles hold position and only twinkle (handled in draw).
func _advance(delta: float) -> void:
	var span := size
	if span.x <= 0.0 or span.y <= 0.0:
		return
	for disc in _discs:
		disc.y -= float(disc.speed) * delta
		var r: float = disc.r
		if disc.y < -r * 2.0:
			disc.y = span.y + r * 2.0
			disc.x = _rng.randf_range(0.0, span.x)


func _draw() -> void:
	_draw_gradient()
	for disc in _discs:
		var cx: float = (
			disc.x + sin(_clock / float(disc.sway_period) + float(disc.phase)) * SWAY_AMP
		)
		var center := Vector2(cx, disc.y)
		# Soft bokeh: a faint filled disc with a slightly brighter rim.
		draw_circle(center, float(disc.r), Color(PartyTheme.ACCENT, float(disc.alpha)))
		draw_arc(
			center,
			float(disc.r),
			0.0,
			TAU,
			40,
			Color(PartyTheme.ACCENT_BRIGHT, float(disc.alpha)),
			1.5
		)
	for sparkle in _sparkles:
		var tw := (
			0.5 + 0.5 * sin(_clock * float(sparkle.twinkle_speed) + float(sparkle.twinkle_phase))
		)
		_draw_sparkle(Vector2(sparkle.x, sparkle.y), float(sparkle.r), tw)


func _draw_gradient() -> void:
	# Top-lit dark slate: a touch brighter at the top, sinking to BG_DARKER.
	var top := PartyTheme.BG_DARK.lerp(PartyTheme.BG_DARKER, 0.35)
	var bottom := PartyTheme.BG_DARKER
	var colors := PackedColorArray([top, top, bottom, bottom])
	var points := PackedVector2Array(
		[Vector2.ZERO, Vector2(size.x, 0.0), Vector2(size.x, size.y), Vector2(0.0, size.y)]
	)
	draw_polygon(points, colors)


## A four-point twinkle: a soft plus of two crossed lines, alpha driven by `tw`.
func _draw_sparkle(center: Vector2, radius: float, tw: float) -> void:
	var color := Color(PartyTheme.ACCENT_BRIGHT, 0.12 + 0.4 * tw)
	var r := radius * (0.6 + 0.4 * tw)
	draw_line(center - Vector2(r, 0.0), center + Vector2(r, 0.0), color, 1.5)
	draw_line(center - Vector2(0.0, r), center + Vector2(0.0, r), color, 1.5)


func _populate() -> void:
	_populated = true
	var span := size
	if span.x <= 0.0 or span.y <= 0.0:
		span = Vector2(1280, 720)
	_discs.clear()
	for _i in DISC_COUNT:
		var r := _rng.randf_range(DISC_MIN_R, DISC_MAX_R)
		# Bigger discs are fainter and drift slower — a cheap depth cue.
		var depth := (r - DISC_MIN_R) / (DISC_MAX_R - DISC_MIN_R)
		(
			_discs
			. append(
				{
					"x": _rng.randf_range(0.0, span.x),
					"y": _rng.randf_range(0.0, span.y),
					"r": r,
					"speed": lerpf(DRIFT_MAX, DRIFT_MIN, depth),
					"phase": _rng.randf_range(0.0, TAU),
					"sway_period": _rng.randf_range(4.0, 9.0),
					"alpha": lerpf(0.14, 0.04, depth),
				}
			)
		)
	_sparkles.clear()
	for _i in SPARKLE_COUNT:
		(
			_sparkles
			. append(
				{
					"x": _rng.randf_range(0.0, span.x),
					"y": _rng.randf_range(0.0, span.y),
					"r": _rng.randf_range(3.0, 7.0),
					"twinkle_phase": _rng.randf_range(0.0, TAU),
					"twinkle_speed": _rng.randf_range(1.2, 3.0),
				}
			)
		)
