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
var controls_text := ""


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
