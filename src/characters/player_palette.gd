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

## High-contrast team colors (#820). During a team_mode round the view tier
## assigns every competing slot to a team and color_for_slot serves one of these
## instead of the personal pick, so allegiance reads at a glance — a 2-team game
## is always the maximally-separable red/blue pair; 3-4 team games (Color Clash)
## add yellow and green. Wraps for any larger team count.
const TEAM_COLORS: Array[Color] = [
	Color(0.902, 0.290, 0.235),  # Team 1 red
	Color(0.255, 0.522, 0.957),  # Team 2 blue
	Color(0.957, 0.792, 0.204),  # Team 3 yellow
	Color(0.298, 0.749, 0.353),  # Team 4 green
]

## Colorblind-safe team colors (M12-03 parity with COLORS_COLORBLIND): orange /
## blue is the Okabe-Ito pair every CB type keeps apart, with yellow + bluish
## green for the 3-4 team games. Served whenever use_colorblind is on.
const TEAM_COLORS_COLORBLIND: Array[Color] = [
	Color(0.902, 0.624, 0.000),  # Team 1 orange
	Color(0.000, 0.447, 0.698),  # Team 2 blue
	Color(0.941, 0.894, 0.259),  # Team 3 yellow
	Color(0.000, 0.620, 0.451),  # Team 4 bluish green
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

## Chosen-color overrides (slot -> palette index), set from room state (#581)
## so every color_for_slot() call site reflects lobby colour picks with no
## per-view change. Empty = everyone on their slot default. Keys are int slots.
static var _overrides := {}

## Team-color assignments (#820), slot(int) -> team index(int). While non-empty
## (a team_mode round is on screen), color_for_slot serves TEAM_COLORS[team]
## for an assigned slot, overriding both the #581 pick and the slot default so
## the whole team reads as one color. Empty everywhere else — the view tier
## clears it as the round leaves the screen, restoring personal identity for the
## lobby, standings, and solo games.
static var _team_of := {}


## Replace the chosen-color overrides wholesale (the client rebuilds this from
## each room_updated). A pick is a palette *index*, not a Color, so it survives
## the colorblind toggle — index N means "the Nth swatch of whatever set is
## active".
static func set_overrides(map: Dictionary) -> void:
	_overrides = map.duplicate()


static func clear_overrides() -> void:
	_overrides = {}


## Assign the competing slots to teams for a team_mode round (#820). `teams` is
## the snapshot's array-of-member-arrays — team 0's slots, team 1's, and so on.
## Replaces any prior assignment wholesale; color_for_slot then serves the team
## color for every listed slot until clear_team_assignments().
static func set_team_assignments(teams: Array) -> void:
	var map := {}
	for team_index in teams.size():
		for slot: int in teams[team_index] as Array:
			map[int(slot)] = team_index
	_team_of = map


static func clear_team_assignments() -> void:
	_team_of = {}


## Whether a team_mode round's colors are currently in force. The view tier
## uses this to apply the assignment exactly once per round (teams are fixed).
static func has_team_assignments() -> bool:
	return not _team_of.is_empty()


## The team palette in force right now (respects the colorblind toggle, exactly
## as active_colors() does for personal identity).
static func active_team_colors() -> Array[Color]:
	return TEAM_COLORS_COLORBLIND if use_colorblind else TEAM_COLORS


## The palette index a slot actually shows: its explicit pick if it made one,
## else the slot default. Shared by the client funnel and the server's
## uniqueness check so both sides agree on which colour is "taken".
static func effective_index(slot: int, color_index: int) -> int:
	return color_index if color_index >= 0 else posmod(slot, COLORS.size())


## Can `index` be picked, given the other members as [slot, color_index] pairs?
## A real palette index that no other member effectively shows (#581). Pure, so
## the server's uniqueness rule is unit-testable without the whole net stack.
static func is_index_free(index: int, others: Array) -> bool:
	if index < 0 or index >= COLORS.size():
		return false
	for pair: Array in others:
		if effective_index(int(pair[0]), int(pair[1])) == index:
			return false
	return true


## The palette in force right now (respects the colorblind toggle).
static func active_colors() -> Array[Color]:
	return COLORS_COLORBLIND if use_colorblind else COLORS


## Player color for a room slot: the slot's chosen override if any, else its
## slot default. Wraps at the palette size, so a 13th player reuses P1's color —
## `label_for_slot()` keeps them distinct.
static func color_for_slot(slot: int) -> Color:
	if _team_of.has(slot):
		var team_colors := active_team_colors()
		return team_colors[posmod(int(_team_of[slot]), team_colors.size())]
	var colors := active_colors()
	var idx: int = _overrides.get(slot, slot)
	return colors[posmod(idx, colors.size())]


## Always-unique player number for a room slot ("P1" for slot 0). The second
## identity channel that lets rooms exceed the palette size (ADR 003 F2).
static func label_for_slot(slot: int) -> String:
	return "P%d" % (slot + 1)
