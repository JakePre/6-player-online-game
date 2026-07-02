class_name PlayerPalette
extends RefCounted
## The six fixed player colors (SPEC $8) — color is the primary identity
## channel, keyed by room slot.

const COLORS: Array[Color] = [
	Color("e53935"),  # red
	Color("1e88e5"),  # blue
	Color("fdd835"),  # yellow
	Color("43a047"),  # green
	Color("8e24aa"),  # purple
	Color("fb8c00"),  # orange
]


static func for_slot(slot: int) -> Color:
	return COLORS[clampi(slot, 0, COLORS.size() - 1)]
