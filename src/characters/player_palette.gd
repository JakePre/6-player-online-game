class_name PlayerPalette
extends RefCounted
## Player identity palette (SPEC $8, amended by ADR 003). Color is a primary
## identity channel (outline, nameplate, minimap marker); characters are
## flavor. Indexed by room slot so a player keeps their color for the match.
##
## Rooms now hold up to 24 players (ADR 003) — more than any set of colors can
## keep telling apart — so identity is **color + number**: the palette gives a
## dozen distinct colors that wrap for larger rooms, and `label_for_slot()`
## supplies an always-unique "P1..P24" number that disambiguates the wrap.

const COLORS: Array[Color] = [
	Color(0.902, 0.290, 0.235),  # P1 red
	Color(0.255, 0.522, 0.957),  # P2 blue
	Color(0.957, 0.792, 0.204),  # P3 yellow
	Color(0.298, 0.749, 0.353),  # P4 green
	Color(0.655, 0.404, 0.902),  # P5 purple
	Color(0.957, 0.553, 0.200),  # P6 orange
	Color(0.180, 0.800, 0.820),  # P7 cyan
	Color(0.925, 0.365, 0.680),  # P8 pink
	Color(0.600, 0.851, 0.255),  # P9 lime
	Color(0.545, 0.380, 0.245),  # P10 brown
	Color(0.870, 0.870, 0.902),  # P11 white
	Color(0.145, 0.510, 0.480),  # P12 teal
]


## Player color for a room slot. Wraps at the palette size, so a 13th player
## reuses P1's color — `label_for_slot()` keeps them distinct.
static func color_for_slot(slot: int) -> Color:
	return COLORS[posmod(slot, COLORS.size())]


## Always-unique player number for a room slot ("P1" for slot 0). The second
## identity channel that lets rooms exceed the palette size (ADR 003 F2).
static func label_for_slot(slot: int) -> String:
	return "P%d" % (slot + 1)
