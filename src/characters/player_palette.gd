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

## Colorblind-safe variant (M12-03): the default set's worst confusions are
## P1 red / P4 green (deutan+protan) and P2 blue / P5 purple. This set leans
## on the blue–orange–yellow axis that all three CB types retain and staggers
## luminance so hues that do collapse stay distinct by brightness. The seven
## chromatic entries are the Okabe-Ito colorblind-safe palette; the rest are
## luminance-separated extras. Identity is still color + number (ADR 003), so
## the P1..P24 label backstops any residual overlap in large rooms.
const COLORS_COLORBLIND: Array[Color] = [
	Color(0.835, 0.369, 0.000),  # P1 vermillion
	Color(0.337, 0.706, 0.914),  # P2 sky blue
	Color(0.941, 0.894, 0.259),  # P3 yellow
	Color(0.000, 0.447, 0.698),  # P4 blue
	Color(0.902, 0.624, 0.000),  # P5 orange
	Color(0.000, 0.620, 0.451),  # P6 bluish green
	Color(0.800, 0.475, 0.655),  # P7 reddish purple
	Color(0.925, 0.925, 0.925),  # P8 near-white
	Color(0.400, 0.400, 0.400),  # P9 mid grey
	Color(0.478, 0.271, 0.588),  # P10 violet
	Color(0.596, 0.843, 0.933),  # P11 pale cyan
	Color(0.518, 0.372, 0.145),  # P12 brown
]

## Set from SettingsStore.apply() at boot and when the toggle changes. When
## true, color_for_slot() serves the colorblind-safe set.
static var use_colorblind := false


## The palette in force right now (respects the colorblind toggle).
static func active_colors() -> Array[Color]:
	return COLORS_COLORBLIND if use_colorblind else COLORS


## Player color for a room slot. Wraps at the palette size, so a 13th player
## reuses P1's color — `label_for_slot()` keeps them distinct.
static func color_for_slot(slot: int) -> Color:
	var colors := active_colors()
	return colors[posmod(slot, colors.size())]


## Always-unique player number for a room slot ("P1" for slot 0). The second
## identity channel that lets rooms exceed the palette size (ADR 003 F2).
static func label_for_slot(slot: int) -> String:
	return "P%d" % (slot + 1)
