extends Node
## Audio pass (M6-01, extended by M20-01 #711): one autoload owning music and
## SFX playback on the M2-05 buses. Screens/chrome/games call
## play_music()/play_sfx() with semantic names; nothing else touches
## AudioStreamPlayers. Music crossfades between loops (SPEC $11), and the
## round channel rotates through a pool so consecutive rounds don't share one
## track; SFX round-robin a small player pool so rapid events never cut each
## other off.
##
## The SFX vocabulary (names, meanings, when to use which) is documented in
## docs/AUDIO_GUIDE.md — games pick signature cues from it in the M20-02
## fan-out. Shared-meaning cues (ko, round_start, coin...) must keep the same
## meaning in every game (#591).

## Semantic name -> pool of loop paths. Single-loop channels are one-element
## pools; the round channel rotates via advance_round_music() each round.
const MUSIC := {
	&"menu": ["res://assets/audio/incompetech/menu_loop.mp3"],
	&"round":
	[
		"res://assets/audio/incompetech/round_loop.mp3",
		"res://assets/audio/incompetech/round_loop_duck.mp3",
		"res://assets/audio/incompetech/round_loop_amok.mp3",
		"res://assets/audio/incompetech/round_loop_weasel.mp3",
	],
	&"finale": ["res://assets/audio/incompetech/finale_loop.mp3"],
}

const SFX := {
	# --- chrome / shared jingles (M6-01) ---------------------------------------
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
	# --- gameplay vocabulary (M20-01, #711 — see docs/AUDIO_GUIDE.md) ----------
	# Impacts / combat.
	&"hit": "res://assets/audio/kenney_impact_sounds/hit.ogg",
	&"hit_heavy": "res://assets/audio/kenney_impact_sounds/hit_heavy.ogg",
	&"ko": "res://assets/audio/kenney_impact_sounds/ko.ogg",
	&"thud": "res://assets/audio/kenney_impact_sounds/thud.ogg",
	&"bump": "res://assets/audio/kenney_impact_sounds/bump.ogg",
	&"clang": "res://assets/audio/kenney_impact_sounds/clang.ogg",
	&"bell": "res://assets/audio/kenney_impact_sounds/bell.ogg",
	# Destruction.
	&"break_wood": "res://assets/audio/kenney_impact_sounds/break_wood.ogg",
	&"crack": "res://assets/audio/kenney_impact_sounds/crack.ogg",
	&"shatter": "res://assets/audio/kenney_impact_sounds/shatter.ogg",
	&"explosion": "res://assets/audio/party_rush_synth/explosion.wav",
	&"splash": "res://assets/audio/party_rush_synth/splash.wav",
	# Movement.
	&"jump": "res://assets/audio/kenney_digital_audio/jump.ogg",
	&"dash": "res://assets/audio/kenney_digital_audio/dash.ogg",
	# Energy / state.
	&"zap": "res://assets/audio/kenney_digital_audio/zap.ogg",
	&"laser": "res://assets/audio/kenney_digital_audio/laser.ogg",
	&"alarm": "res://assets/audio/kenney_digital_audio/alarm.ogg",
	&"powerup": "res://assets/audio/kenney_digital_audio/powerup.ogg",
	&"powerdown": "res://assets/audio/kenney_digital_audio/powerdown.ogg",
	&"pop": "res://assets/audio/kenney_digital_audio/pop.ogg",
}

const CROSSFADE_SEC := 0.8
const SFX_POOL_SIZE := 6

## The music channel currently playing (or requested), &"" when silent.
var current_music: StringName = &""

var _music_player: AudioStreamPlayer
var _fade_tween: Tween
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
## Per-channel rotation position into its MUSIC pool (#711).
var _music_index := {}


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_sfx_pool.append(player)


## Crossfades to a MUSIC channel; unknown names (or &"") fade to silence.
## Calling with the already-playing channel is a no-op — rotation within the
## round pool goes through advance_round_music() instead.
func play_music(name: StringName) -> void:
	if name == current_music:
		return
	current_music = name if MUSIC.has(name) else &""
	_crossfade_to(&"" if current_music == &"" else track_for(current_music))


## Rotates the round channel to its next loop (#711): the match screen calls
## this on each round intro after the first, so consecutive rounds don't share
## one track. If round music is playing it crossfades immediately; otherwise
## the bump just changes which loop the next play_music(&"round") starts on.
func advance_round_music() -> void:
	if (MUSIC[&"round"] as Array).size() < 2:
		return
	_music_index[&"round"] = int(_music_index.get(&"round", 0)) + 1
	if current_music == &"round":
		_crossfade_to(track_for(&"round"))


## The path the channel's rotation currently points at.
func track_for(name: StringName) -> String:
	var pool: Array = MUSIC[name]
	return pool[int(_music_index.get(name, 0)) % pool.size()]


func _crossfade_to(path: String) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	if _music_player.playing:
		_fade_tween.tween_property(_music_player, "volume_db", -40.0, CROSSFADE_SEC)
	if path.is_empty():
		_fade_tween.tween_callback(_music_player.stop)
		return
	var stream: AudioStream = load(path)
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
