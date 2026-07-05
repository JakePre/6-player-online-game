class_name ScreenTransition
extends ColorRect
## Shared app-shell screen transition (M16-02): a cover-and-reveal fade that
## hides the hard cut between screens. AppShell mounts the new screen the same
## frame the cover snaps opaque (no flash of the old screen), then calls
## reveal() to fade the cover out over it.
##
## Reduced-motion (M12-03 / STYLE_GUIDE): reveal() no-ops — the cover never
## shows and the swap is instant, exactly the old behaviour. The design is
## reentrancy-safe: the screen swap is synchronous, so a rapid navigation just
## re-triggers the fade rather than stacking tweens or double-swapping.

var _tween: Tween


func _ready() -> void:
	color = PartyTheme.BG_DARKER
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Hidden and click-through at rest; only blocks input mid-reveal.
	modulate.a = 0.0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Snap opaque, then fade out to reveal whatever is behind us. Call this right
## after the new screen mounts. No-op under reduced motion.
func reveal() -> void:
	if ArenaFX.reduced_motion:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	visible = true
	# Block input while the new screen is still hidden behind the cover.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tween = create_tween()
	_tween.set_trans(PartyTheme.TRANS_DEFAULT).set_ease(PartyTheme.EASE_DEFAULT)
	_tween.tween_property(self, "modulate:a", 0.0, PartyTheme.DUR_MED)
	_tween.tween_callback(_settle)


func _settle() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
