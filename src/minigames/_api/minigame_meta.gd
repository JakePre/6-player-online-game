class_name MinigameMeta
extends RefCounted
## Static description of one minigame (SPEC $7 / plan $4): everything the
## framework needs to schedule it and render its intro card.

enum Category {
	FFA,
	SKILL,
	TEAM,
	SABOTAGE,
}

var id: StringName
var display_name := ""
var category := Category.FFA
var min_players := 2
var max_players := 6
var duration_sec := 60.0
## Team games that cannot run with odd player counts (#178): the catalog
## never drafts them for 3 or 5 players.
var even_players := false
var rules_text := ""
## One-line control hint for the intro card (M6-04), e.g.
## "Move — WASD / left stick". Keyboard first, then the gamepad equivalent.
## This static prose is the always-available fallback and what travels over the
## wire (to_dict); the client shows it whenever `control_hints` is empty.
var controls_text := ""
## Optional structured control hints (#608): an ordered segment list the intro
## card renders *device-aware* — literal strings stay verbatim, while a
## `{"action": &"..."}` segment shows the glyph for the input the player is
## actually holding ("Space" vs "Ⓐ" vs "✕"), swapping live on device change.
## Client-derived from the local catalog, so it is NOT serialized (no protocol
## change); an empty list means "use controls_text". Only button actions render
## a glyph — movement/axis hints stay literal (a #608 follow-up).
var control_hints: Array = []


static func create(values: Dictionary) -> MinigameMeta:
	var meta := MinigameMeta.new()
	meta.id = values.id
	meta.display_name = values.get("name", String(values.id))
	meta.category = values.get("category", Category.FFA)
	meta.min_players = values.get("min_players", 2)
	meta.max_players = values.get("max_players", 6)
	meta.duration_sec = values.get("duration_sec", 60.0)
	meta.even_players = values.get("even_players", false)
	meta.rules_text = values.get("rules", "")
	meta.controls_text = values.get("controls", "")
	meta.control_hints = values.get("control_hints", [])
	return meta


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"category": category,
		"duration_sec": duration_sec,
		"rules": rules_text,
		"controls": controls_text,
	}
