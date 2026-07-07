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
	# Hidden-role / rotating-role batch (M19-02, #686).
	&"the_mole": preload("res://src/core/bots/brains/the_mole_brain.gd"),
	&"faulty_wiring": preload("res://src/core/bots/brains/faulty_wiring_brain.gd"),
	&"trap_corridor": preload("res://src/core/bots/brains/trap_corridor_brain.gd"),
	# Aim / reaction / racing batch (M19-02, #686).
	&"quick_draw": preload("res://src/core/bots/brains/quick_draw_brain.gd"),
	&"target_range": preload("res://src/core/bots/brains/target_range_brain.gd"),
	&"putt_panic": preload("res://src/core/bots/brains/putt_panic_brain.gd"),
	&"bullseye_bowl": preload("res://src/core/bots/brains/bullseye_bowl_brain.gd"),
	&"turbo_lap": preload("res://src/core/bots/brains/turbo_lap_brain.gd"),
	# Chase / tag / positional batch (M19-02, #686).
	&"hot_potato": preload("res://src/core/bots/brains/hot_potato_brain.gd"),
	&"shock_tag": preload("res://src/core/bots/brains/shock_tag_brain.gd"),
	&"snake_chain": preload("res://src/core/bots/brains/snake_chain_brain.gd"),
	&"sumo_smash": preload("res://src/core/bots/brains/sumo_smash_brain.gd"),
	&"color_clash": preload("res://src/core/bots/brains/color_clash_brain.gd"),
	# SideScrollSim platformer batch (M19-02, #686).
	&"knock_off": preload("res://src/core/bots/brains/knock_off_brain.gd"),
	&"loadout_duel": preload("res://src/core/bots/brains/loadout_duel_brain.gd"),
	&"tumble_run": preload("res://src/core/bots/brains/tumble_run_brain.gd"),
}


## The brain for `minigame_id`, seeded for deterministic-but-distinct play.
static func brain_for(minigame_id: StringName, slot: int, seed_value: int) -> BotBrain:
	var script: GDScript = BRAINS.get(minigame_id)
	if script == null:
		return RandomBrain.new(slot, seed_value)
	return script.new(slot, seed_value)


static func has_brain(minigame_id: StringName) -> bool:
	return BRAINS.has(minigame_id)
