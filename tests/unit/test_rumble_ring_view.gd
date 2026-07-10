extends GutTest
## Rumble Ring client view (M10-17): renders replicated snapshots without
## simulating anything locally.

var view: MinigameView3D


func before_each() -> void:
	var scene: PackedScene = load("res://src/minigames/rumble_ring/rumble_ring_view.tscn")
	view = scene.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func test_view_scene_lives_at_catalog_path() -> void:
	assert_eq(
		MinigameCatalog.view_scene_path(&"rumble_ring"),
		"res://src/minigames/rumble_ring/rumble_ring_view.tscn"
	)


func test_render_replaces_state_and_updates_nameplates() -> void:
	(
		view
		. render(
			{
				"players": {0: [1.0, 2.0, 2, 6, 0, 0.0, 1.0, 0.0]},
				"coins": [[0.5, 0.5]],
				"events": [],
			}
		)
	)
	assert_eq(view.players.size(), 1)
	assert_eq(view.coins.size(), 1)
	var rig: CharacterRig = view.rig_for_slot(0)
	# #777: plain HP pips (2 of 3 left) + a labelled KO count, not ♥/⚔ icons.
	assert_string_contains(rig.display_name, "●●○")
	assert_string_contains(rig.display_name, "KOs 6")


## #777: a swing plays a real attack animation. Before, it played `interact`,
## which update_rig clobbered to walk/idle the same frame — so a swing looked
## like nothing happened ("space does nothing?").
func test_swing_event_plays_the_attack_animation() -> void:
	view.render(
		{
			"players": {0: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0]},
			"events": [{"type": "swing", "slot": 0}]
		}
	)
	assert_eq(view.rig_for_slot(0).current_action(), &"attack", "a swing swings the rig")


## #777/#800: the swing animation never roots you — moving interrupts it.
func test_moving_interrupts_the_swing_animation() -> void:
	view.render(
		{
			"players": {0: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0]},
			"events": [{"type": "swing", "slot": 0}]
		}
	)
	assert_eq(view.rig_for_slot(0).current_action(), &"attack")
	view.render({"players": {0: [4.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0]}, "events": []})
	assert_eq(view.rig_for_slot(0).current_action(), &"walk", "movement wins over the swing pose")


## #777: the smasher also throws an attack swing, not just the shockwave.
func test_smash_event_plays_the_attack_animation_on_the_smasher() -> void:
	view.render(
		{
			"players": {0: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0]},
			"events": [{"type": "smash", "slot": 0}]
		}
	)
	assert_eq(view.rig_for_slot(0).current_action(), &"attack")


## #777: a swing press while the swing is still on cooldown flashes a hint
## instead of doing nothing — the root of "space does nothing?".
func test_swing_press_on_cooldown_flashes_a_recharging_hint() -> void:
	view._register_local_swing()  # first press: ready, arms the cooldown, no hint
	view._register_local_swing()  # immediate second press: on cooldown
	assert_string_contains(view._banner.text, "recharging")


func test_ko_event_plays_the_ko_action() -> void:
	(
		view
		. render(
			{
				"players": {0: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0]},
				"coins": [],
				"events": [{"type": "ko", "slot": 0, "by": 1}],
			}
		)
	)
	var rig: CharacterRig = view.rig_for_slot(0)
	assert_eq(rig.current_action(), &"ko")


func _burst_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


func _has_shockwave() -> bool:
	for child in view.arena.get_children():
		if child.name.begins_with("SmashShockwave"):
			return true
	return false


## M13-28: the charged smash bursts a shockwave ring (was sound-only before).
func test_smash_event_bursts_a_shockwave() -> void:
	assert_false(_has_shockwave(), "no shockwave at rest")
	view.render(
		{
			"players": {0: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0]},
			"events": [{"type": "smash", "slot": 0}]
		}
	)
	assert_true(_has_shockwave(), "the smash bursts a shockwave ring")


## A KO throws an impact burst where the fighter went down.
func test_ko_event_bursts() -> void:
	view.render(
		{
			"players": {0: [0.0, 0.0, 0, 0, 0, 0.0, 1.0, 0.0]},
			"events": [{"type": "ko", "slot": 0, "by": 1}]
		}
	)
	assert_gt(_burst_count(), 0, "a KO throws an impact burst")


## A successful block now sparks (the event had no view handler before).
func test_blocked_event_sparks() -> void:
	view.render(
		{
			"players": {0: [0.0, 0.0, 3, 0, 1, 0.0, 1.0, 0.0]},
			"events": [{"type": "blocked", "slot": 0}]
		}
	)
	assert_gt(_burst_count(), 0, "a blocked hit sparks off the guard")


## #587: swing SFX was gated to the local player only, so every opponent's
## sword swing was silent — it now matches hit/ko/blocked/smash and always
## plays. my_slot is 0 (per before_each); the swinger here is slot 1, Bob,
## an opponent — the exact case the old gate silenced.
func test_swing_event_plays_sfx_for_every_player_not_just_local() -> void:
	watch_signals(view)
	(
		view
		. render(
			{
				"players": {1: [0.0, 0.0, 3, 0, 0, 0.0, 1.0, 0.0]},
				"events": [{"type": "swing", "slot": 1}],
			}
		)
	)
	assert_signal_emitted_with_parameters(view, "sfx_requested", [&"click"])


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_eq(view.players.size(), 0)
	assert_eq(view.coins, [])
