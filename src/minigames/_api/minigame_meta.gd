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
var rules_text := ""


static func create(values: Dictionary) -> MinigameMeta:
	var meta := MinigameMeta.new()
	meta.id = values.id
	meta.display_name = values.get("name", String(values.id))
	meta.category = values.get("category", Category.FFA)
	meta.min_players = values.get("min_players", 2)
	meta.max_players = values.get("max_players", 6)
	meta.duration_sec = values.get("duration_sec", 60.0)
	meta.rules_text = values.get("rules", "")
	return meta


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"category": category,
		"duration_sec": duration_sec,
		"rules": rules_text,
	}
