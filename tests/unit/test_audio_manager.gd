extends GutTest
## Audio pass (M6-01): semantic music/SFX registries, bus routing, crossfade
## state, and the speculative-hook no-op guarantee.


func test_every_registered_stream_exists() -> void:
	# Music channels are pools since M20-01 (#711): every loop in every pool.
	for name: StringName in AudioManager.MUSIC:
		for path: String in AudioManager.MUSIC[name]:
			assert_true(ResourceLoader.exists(path), "music %s -> %s must exist" % [name, path])
	for name: StringName in AudioManager.SFX:
		assert_true(ResourceLoader.exists(AudioManager.SFX[name]), "sfx %s must exist" % name)


func test_players_ride_the_settings_buses() -> void:
	var players := AudioManager.get_children().filter(
		func(child: Node) -> bool: return child is AudioStreamPlayer
	)
	assert_eq(players.size(), 1 + AudioManager.SFX_POOL_SIZE)
	var buses := {}
	for player: AudioStreamPlayer in players:
		buses[player.bus] = int(buses.get(player.bus, 0)) + 1
	assert_eq(buses.get(&"Music", 0), 1)
	assert_eq(buses.get(&"SFX", 0), AudioManager.SFX_POOL_SIZE)


func test_play_music_tracks_current_and_ignores_repeats() -> void:
	AudioManager.play_music(&"menu")
	assert_eq(AudioManager.current_music, &"menu")
	AudioManager.play_music(&"menu")
	assert_eq(AudioManager.current_music, &"menu")
	AudioManager.play_music(&"round")
	assert_eq(AudioManager.current_music, &"round")
	AudioManager.play_music(&"")
	assert_eq(AudioManager.current_music, &"")


func test_unknown_music_fades_to_silence() -> void:
	AudioManager.play_music(&"menu")
	AudioManager.play_music(&"elevator_jazz")
	assert_eq(AudioManager.current_music, &"")


func test_unknown_sfx_is_a_noop() -> void:
	AudioManager.play_sfx(&"kazoo_solo")
	pass_test("speculative minigame hooks must not error")


func test_sfx_pool_round_robins() -> void:
	var before: int = AudioManager._sfx_next
	AudioManager.play_sfx(&"click")
	AudioManager.play_sfx(&"coin")
	assert_eq(AudioManager._sfx_next, (before + 2) % AudioManager.SFX_POOL_SIZE)


## #804: the current loop can be paused in place (Musical Platforms' music
## stopping is the mechanic) and resumed.
func test_set_music_paused_toggles_the_loop() -> void:
	AudioManager.play_music(&"round")
	AudioManager.set_music_paused(true)
	assert_true(AudioManager.music_paused, "the loop pauses in place")
	AudioManager.set_music_paused(false)
	assert_false(AudioManager.music_paused, "and resumes")


## #804: a game must never strand the next screen's music paused — starting any
## new track clears a lingering pause.
func test_new_track_clears_a_lingering_pause() -> void:
	AudioManager.set_music_paused(true)
	AudioManager.play_music(&"round")
	AudioManager.play_music(&"finale")
	# Drive the crossfade tween's deferred play callback deterministically.
	AudioManager._fade_tween.custom_step(AudioManager.CROSSFADE_SEC * 2.0)
	assert_false(AudioManager.music_paused, "a fresh track is never left paused")
