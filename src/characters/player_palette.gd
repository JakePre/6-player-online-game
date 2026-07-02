class_name PlayerPalette
extends RefCounted
## The fixed 6-color player identity palette (SPEC $8). Color is the primary
## identity channel (outline, nameplate, minimap marker); characters are
## flavor. Indexed by room slot so a player keeps their color for the match.

const COLORS: Array[Color] = [
	Color(0.902, 0.290, 0.235),  # P1 red
	Color(0.255, 0.522, 0.957),  # P2 blue
	Color(0.957, 0.792, 0.204),  # P3 yellow
	Color(0.298, 0.749, 0.353),  # P4 green
	Color(0.655, 0.404, 0.902),  # P5 purple
	Color(0.957, 0.553, 0.200),  # P6 orange
]


static func color_for_slot(slot: int) -> Color:
	return COLORS[posmod(slot, COLORS.size())]
