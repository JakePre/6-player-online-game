extends GutTest
## Debug launcher arg parsing + force-start payload (#626): the render-bot-games
## pipeline drives `--debug-bots` / `--debug-duration`, so their parsing and the
## config they produce are pinned here. The network orchestration itself is
## exercised end-to-end by the render/soak harnesses, not unit tests — the
## launcher is never added to the tree here, so its _ready never runs.

const LAUNCHER := preload("res://src/client/debug_launcher.gd")


func _launcher(args: PackedStringArray) -> Node:
	var node: Node = LAUNCHER.new()
	node.configure(args)
	autofree(node)
	return node


func test_defaults_solo_full_length() -> void:
	var launcher := _launcher(PackedStringArray(["--debug-minigame=coin_scramble"]))
	assert_eq(launcher.minigame_id, &"coin_scramble")
	assert_eq(launcher.bot_count, 0, "solo by default")
	assert_eq(launcher.duration_sec, 0.0, "no override by default")
	# Explicit type: `launcher` is Node-typed, so `:=` can't infer (§11).
	var config: Dictionary = launcher.start_config()
	assert_eq(config["playlist"], [&"coin_scramble"])
	assert_eq(config["rounds"], 1)
	assert_true(config["debug_force_start"])
	assert_false(config.has("duration_override"), "no override key unless asked")


func test_bots_and_duration_parse() -> void:
	var launcher := _launcher(
		PackedStringArray(["--debug-minigame=sumo_smash", "--debug-bots=5", "--debug-duration=30"])
	)
	assert_eq(launcher.bot_count, 5)
	assert_eq(launcher.duration_sec, 30.0)
	assert_eq(launcher.start_config()["duration_override"], 30.0)


func test_bot_count_clamps_to_room_cap_minus_camera() -> void:
	var launcher := _launcher(
		PackedStringArray(["--debug-minigame=sumo_smash", "--debug-bots=999"])
	)
	assert_eq(
		launcher.bot_count,
		NetConfig.MAX_PLAYERS_PER_ROOM - 1,
		"one slot belongs to the camera client; more would stall the roster wait"
	)


func test_negative_values_clamp_to_off() -> void:
	var launcher := _launcher(
		PackedStringArray(["--debug-minigame=sumo_smash", "--debug-bots=-3", "--debug-duration=-9"])
	)
	assert_eq(launcher.bot_count, 0)
	assert_eq(launcher.duration_sec, 0.0)
	assert_false(launcher.start_config().has("duration_override"))


## #685: `gauntlet` is the finale, not a catalog game — its config skips the
## playlist and opens on a compressed buy-in shop.
func test_gauntlet_config_is_finale_only() -> void:
	var launcher := _launcher(
		PackedStringArray(["--debug-minigame=gauntlet", "--debug-duration=40"])
	)
	var config: Dictionary = launcher.start_config()
	assert_true(bool(config.get("finale_only", false)))
	assert_true(bool(config.get("debug_force_start", false)))
	assert_false(config.has("playlist"), "the finale has no playlist")
	assert_eq(config.get("shop_sec"), 8.0, "shop compressed for a tight clip")
	assert_eq(config.get("duration_override"), 40.0)
