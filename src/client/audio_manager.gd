extends Node
## Audio pass (M6-01): one autoload owning music and SFX playback on the
## M2-05 buses. Screens/chrome call play_music()/play_sfx() with semantic
## names; nothing else touches AudioStreamPlayers. Music crossfades between
## the three loops (SPEC $11); SFX round-robin a small player pool so rapid
## events never cut each other off.

const MUSIC := {
	&"menu": "res://assets/audio/incompetech/menu_loop.mp3",
	&"round": "res://assets/audio/incompetech/round_loop.mp3",
	&"finale": "res://assets/audio/incompetech/finale_loop.mp3",
}

const SFX := {
	&"click": "res://assets/audio/kenney_interface_sounds/click.ogg",
	&"confirm": "res://assets/audio/kenney_interface_sounds/confirm.ogg",
	&"error": "res://assets/audio/kenney_interface_sounds/error.ogg",
	&"tick": "res://assets/audio/kenney_interface_sounds/tick.ogg",
	&"coin": "res://assets/audio/kenney_interface_sounds/coin.ogg",
	&"round_start": "res://assets/audio/kenney_music_jingles/round_start.ogg",
	&"round_win": "res://assets/audio/kenney_music_jingles/round_win.ogg",
	&"round_lose": "res://assets/audio/kenney_music_jingles/round_lose.ogg",
	&"leaderboard": "res://assets/audio/kenney_music_jingles/leaderboard.ogg",
	&"podium": "res://assets/audio/kenney_music_jingles/podium.ogg",
}

const CROSSFADE_SEC := 0.8
const SFX_POOL_SIZE := 6

## The music loop currently playing (or requested), &"" when silent.
var current_music: StringName = &""

var _music_player: AudioStreamPlayer
var _fade_tween: Tween
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_sfx_pool.append(player)


## Crossfades to a MUSIC loop; unknown names (or &"") fade to silence.
## Calling with the already-playing loop is a no-op.
func play_music(name: StringName) -> void:
	if name == current_music:
		return
	current_music = name if MUSIC.has(name) else &""
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	if _music_player.playing:
		_fade_tween.tween_property(_music_player, "volume_db", -40.0, CROSSFADE_SEC)
	if current_music == &"":
		_fade_tween.tween_callback(_music_player.stop)
		return
	var stream: AudioStream = load(MUSIC[current_music])
	if stream is AudioStreamMP3:
		stream.loop = true
	_fade_tween.tween_callback(
		func() -> void:
			_music_player.stream = stream
			_music_player.play()
	)
	_fade_tween.tween_property(_music_player, "volume_db", 0.0, CROSSFADE_SEC)


## Fires a one-shot SFX by semantic name; unknown names are ignored (so
## minigame hooks can call speculatively).
func play_sfx(name: StringName) -> void:
	if not SFX.has(name):
		return
	var player := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_POOL_SIZE
	player.stream = load(SFX[name])
	player.play()
