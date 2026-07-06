class_name BotBrains
extends RefCounted
## Registry mapping minigame ids to their goal-seeking bot brains (M19, #684).
## Games without a dedicated brain fall back to RandomBrain — identical to the
## pre-M19 random-input behavior — so coverage can grow game by game (the
## M4/M8/M13 fan-out pattern) with zero risk to uncovered games.
##
## The finale is entered directly (never via the catalog), so "gauntlet" maps
## here like any other id; the brain also handles the FINALE_SHOP phase.

const BRAINS := {
	&"coin_scramble": preload("res://src/core/bots/brains/coin_scramble_brain.gd"),
	&"king_of_the_hill": preload("res://src/core/bots/brains/king_of_the_hill_brain.gd"),
	&"thin_ice": preload("res://src/core/bots/brains/thin_ice_brain.gd"),
	&"meteor_shower": preload("res://src/core/bots/brains/meteor_shower_brain.gd"),
	&"hurdle_dash": preload("res://src/core/bots/brains/hurdle_dash_brain.gd"),
	&"tug_of_war": preload("res://src/core/bots/brains/tug_of_war_brain.gd"),
	&"gauntlet": preload("res://src/core/bots/brains/gauntlet_brain.gd"),
}


## The brain for `minigame_id`, seeded for deterministic-but-distinct play.
static func brain_for(minigame_id: StringName, slot: int, seed_value: int) -> BotBrain:
	var script: GDScript = BRAINS.get(minigame_id)
	if script == null:
		return RandomBrain.new(slot, seed_value)
	return script.new(slot, seed_value)


static func has_brain(minigame_id: StringName) -> bool:
	return BRAINS.has(minigame_id)
