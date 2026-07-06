class_name ButtonMotion
extends RefCounted
## Hover/press motion for menu buttons (M16-03), the first reusable motion
## piece for the M16 surfaces. The theme (M16-01) already handles the button's
## color/shadow states; this adds the subtle *movement* — a small scale-pop on
## hover and a sink on press — at the shared `PartyTheme` tempo.
##
## Reduced-motion (M12-03 / STYLE_GUIDE): when `ArenaFX.reduced_motion` is set,
## nothing is wired up at all — the button keeps its static themed states and
## never scales. Call `attach()` once per button after it's in the tree.

## How far the button grows on hover / shrinks on press (scale multipliers).
const HOVER_SCALE := 1.04
const PRESS_SCALE := 0.97


## Wire hover/press scale motion onto `button`. No-op (leaves the button
## untouched) under reduced motion. Pivots from the button's centre so the pop
## is symmetric; safe to call before or after the button has a final size.
static func attach(button: Button) -> void:
	if ArenaFX.reduced_motion:
		return
	_recenter_pivot(button)
	button.resized.connect(func() -> void: _recenter_pivot(button))
	button.mouse_entered.connect(func() -> void: _scale_to(button, HOVER_SCALE))
	button.mouse_exited.connect(func() -> void: _scale_to(button, 1.0))
	button.button_down.connect(func() -> void: _scale_to(button, PRESS_SCALE))
	# Snap back to the hover/rest scale on release depending on where the
	# cursor ended up.
	button.button_up.connect(
		func() -> void: _scale_to(button, HOVER_SCALE if button.is_hovered() else 1.0)
	)


static func _recenter_pivot(button: Button) -> void:
	button.pivot_offset = button.size / 2.0


static func _scale_to(button: Button, target: float) -> void:
	if not is_instance_valid(button):
		return
	var tween := button.create_tween()
	tween.set_trans(PartyTheme.TRANS_DEFAULT).set_ease(PartyTheme.EASE_DEFAULT)
	tween.tween_property(button, "scale", Vector2(target, target), PartyTheme.DUR_FAST)
	button.set_meta(&"_button_motion_tween", tween)


## Returns the in-flight hover/press tween, if any — lets tests await the
## actual animation instead of racing a fixed wall-clock timer (#653).
static func active_tween(button: Button) -> Tween:
	return button.get_meta(&"_button_motion_tween", null)
