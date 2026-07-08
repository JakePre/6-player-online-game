extends GutTest
## Round-music rotation (M20-01, #711): the round channel is a pool that
## advance_round_music() cycles, so consecutive rounds don't share one track.
## Registry-exists and no-op guards live in test_audio_manager.gd; this file
## covers the rotation contract the match screen drives on round intros.


func before_each() -> void:
	AudioManager.current_music = &""
	AudioManager._music_index = {}


func after_each() -> void:
	AudioManager.play_music(&"")
	AudioManager._music_index = {}


func test_round_pool_holds_multiple_loops() -> void:
	assert_gt(
		(AudioManager.MUSIC[&"round"] as Array).size(),
		1,
		"the whole point of #711's music half: rounds stop sharing one track"
	)


func test_advance_round_music_cycles_the_pool_and_wraps() -> void:
	var pool: Array = AudioManager.MUSIC[&"round"]
	var seen: Array = []
	for _i in pool.size():
		seen.append(AudioManager.track_for(&"round"))
		AudioManager.advance_round_music()
	assert_eq(seen.size(), pool.size())
	for path: String in pool:
		assert_has(seen, path, "every loop in the pool gets a turn")
	assert_eq(AudioManager.track_for(&"round"), seen[0], "rotation wraps back around")


func test_play_music_same_channel_is_a_noop_but_advance_rotates() -> void:
	AudioManager.play_music(&"round")
	var first := AudioManager.track_for(&"round")
	AudioManager.play_music(&"round")  # same channel: keeps the current track
	assert_eq(AudioManager.track_for(&"round"), first, "re-request is a no-op")
	AudioManager.advance_round_music()
	assert_ne(AudioManager.track_for(&"round"), first, "explicit advance rotates")
	assert_eq(AudioManager.current_music, &"round", "still on the round channel")


func test_advance_while_not_on_round_only_moves_the_pointer() -> void:
	AudioManager.play_music(&"menu")
	var before := AudioManager.track_for(&"round")
	AudioManager.advance_round_music()
	assert_eq(AudioManager.current_music, &"menu", "menu keeps playing")
	assert_ne(AudioManager.track_for(&"round"), before, "next round entry starts on a fresh loop")
