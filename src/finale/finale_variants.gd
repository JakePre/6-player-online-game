class_name FinaleVariants
extends RefCounted
## The finale-variant registry (#936): every match still ends in shop →
## showdown → podium, but the showdown arena is drawn from this pool, random
## per match (owner decision 2026-07-13). Variants are NOT catalog minigames —
## the match framework enters them directly (M5-02) and every one consumes
## FinaleShop loadouts through the same apply_loadouts() interface. The view
## scene paths live here too, so the match screen can mount any finale the
## same way it mounts the Gauntlet.

const VIEW_SCENES := {
	&"gauntlet": "res://src/finale/gauntlet_view.tscn",
	&"storm_court": "res://src/finale/storm_court_view.tscn",
	&"kingslayer": "res://src/finale/kingslayer_view.tscn",
}
## HUD names without instantiating a sim client-side just for a label.
const NAMES := {
	&"gauntlet": "The Gauntlet",
	&"storm_court": "Storm Court",
	&"kingslayer": "Kingslayer",
}


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in VIEW_SCENES:
		out.append(id)
	return out


static func is_finale(id: StringName) -> bool:
	return VIEW_SCENES.has(id)


static func pick(rng: RandomNumberGenerator) -> StringName:
	var pool := ids()
	return pool[rng.randi_range(0, pool.size() - 1)]


## A fresh sim + meta for `id` (falls back to the Gauntlet on junk input, so
## a stale config override can never crash the finale).
static func instantiate(id: StringName) -> MinigameBase:
	var game: MinigameBase
	match id:
		&"storm_court":
			game = StormCourt.new()
			game.meta = StormCourt.make_meta()
		&"kingslayer":
			game = Kingslayer.new()
			game.meta = Kingslayer.make_meta()
		_:
			game = Gauntlet.new()
			game.meta = Gauntlet.make_meta()
	return game


static func view_scene_path(id: StringName) -> String:
	return String(VIEW_SCENES.get(id, VIEW_SCENES[&"gauntlet"]))


static func display_name(id: StringName) -> String:
	return String(NAMES.get(id, NAMES[&"gauntlet"]))
